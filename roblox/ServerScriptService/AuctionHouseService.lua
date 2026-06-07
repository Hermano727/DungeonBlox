--[[
	AuctionHouseService
	Server-side auction house: DataStore persistence, remote handlers.
	Listings stored under AuctionHouse_v1 / key "active".
	Seller coins held offline under "pendingCoins_userId".
	Expired items held offline under "pendingReturn_userId".
]]

local DataStoreService = game:GetService("DataStoreService")
local Players          = game:GetService("Players")
local HttpService      = game:GetService("HttpService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage:WaitForChild("AuctionConfig"))
local DPS    = require(ServerScriptService:WaitForChild("DungeonProfileService"))

local store = DataStoreService:GetDataStore(Config.DATASTORE_NAME)

-- In-memory cache so we don't spam GetAsync on every browse request.
local activeCache      = nil
local cacheLoadedAt    = 0
local CACHE_TTL        = 30 -- seconds (os.clock)

-- ---------------------------------------------------------------------------
-- Remote setup
-- ---------------------------------------------------------------------------
local function makeRF(name)
	local ex = ReplicatedStorage:FindFirstChild(name)
	if ex and ex:IsA("RemoteFunction") then return ex end
	local rf   = Instance.new("RemoteFunction")
	rf.Name    = name
	rf.Parent  = ReplicatedStorage
	return rf
end

local rfGetListings   = makeRF("AuctionGetListings")
local rfGetMyListings = makeRF("AuctionGetMyListings")
local rfCreateListing = makeRF("AuctionCreateListing")
local rfCancelListing = makeRF("AuctionCancelListing")
local rfBuyListing    = makeRF("AuctionBuyListing")

-- ---------------------------------------------------------------------------
-- DataStore helpers
-- ---------------------------------------------------------------------------
local function sweepExpiredInPlace(listings)
	-- Remove expired entries (mutates the table). Returns array of removed listings.
	local now     = os.time()
	local expired = {}
	for id, listing in pairs(listings) do
		if type(listing.expiresAt) == "number" and now > listing.expiresAt then
			table.insert(expired, listing)
			listings[id] = nil
		end
	end
	return expired
end

local function getActiveCache()
	local now = os.clock()
	if not activeCache or (now - cacheLoadedAt) > CACHE_TTL then
		local ok, data = pcall(function() return store:GetAsync("active") end)
		activeCache   = (ok and type(data) == "table") and data or {}
		cacheLoadedAt = now
	end
	return activeCache
end

local function invalidateCache()
	activeCache   = nil
	cacheLoadedAt = 0
end

-- Atomic mutate of the "active" key. fn(tbl) mutates the table in-place.
-- Returns ok, expiredListings.
local function mutateActive(fn)
	local expiredListings = {}
	local updatedTable    = nil
	local ok, err = pcall(function()
		store:UpdateAsync("active", function(existing)
			existing = (type(existing) == "table") and existing or {}
			local swept = sweepExpiredInPlace(existing)
			for _, v in ipairs(swept) do table.insert(expiredListings, v) end
			fn(existing)
			updatedTable = existing
			return existing
		end)
	end)
	if ok and updatedTable then
		activeCache   = updatedTable
		cacheLoadedAt = os.clock()
	else
		invalidateCache()
	end
	return ok, err, expiredListings
end

local function addToHistory(userId, entry)
	pcall(function()
		store:UpdateAsync("history_" .. tostring(userId), function(existing)
			existing = (type(existing) == "table") and existing or {}
			table.insert(existing, 1, entry)
			if #existing > 50 then table.remove(existing) end
			return existing
		end)
	end)
end

-- Deposit coins to an offline player (claimed on their next login).
local function depositPendingCoins(userId, amount)
	pcall(function()
		store:UpdateAsync("pendingCoins_" .. tostring(userId), function(existing)
			return (type(existing) == "number" and existing or 0) + amount
		end)
	end)
end

-- Queue an item return for an offline player.
local function depositPendingReturn(userId, item)
	pcall(function()
		store:UpdateAsync("pendingReturn_" .. tostring(userId), function(existing)
			existing = (type(existing) == "table") and existing or {}
			table.insert(existing, item)
			return existing
		end)
	end)
end

-- Grant an item back directly into profile.inventory (bypasses ValidateItemTemplate).
local function grantItemDirect(player, item)
	local profile = DPS.Load(player)
	if not profile then return false end
	local newUuid = HttpService:GenerateGUID(false)
	local copy = {}
	for k, v in pairs(item) do copy[k] = v end
	copy.uuid = newUuid
	profile.inventory[newUuid] = copy
	return true
end

-- Return a listing's item to its seller (online or offline).
local function returnItemToSeller(listing)
	local seller = Players:GetPlayerByUserId(listing.sellerId)
	if seller then
		if grantItemDirect(seller, listing.item) then
			DPS.PushProfile(seller)
		end
	else
		depositPendingReturn(listing.sellerId, listing.item)
	end
end

-- Handle any listings swept as expired during a mutateActive call.
local function processExpired(expiredListings)
	for _, listing in ipairs(expiredListings) do
		task.spawn(function()
			returnItemToSeller(listing)
			addToHistory(listing.sellerId, {
				id        = listing.id,
				item      = listing.item,
				price     = listing.price,
				listedAt  = listing.listedAt,
				expiresAt = listing.expiresAt,
				status    = "expired",
			})
		end)
	end
end

-- ---------------------------------------------------------------------------
-- Pending-claim on player join
-- ---------------------------------------------------------------------------
local function claimPendingForPlayer(player)
	local userId = player.UserId

	-- Pending coins from items sold while offline
	local pendingCoins = 0
	pcall(function()
		store:UpdateAsync("pendingCoins_" .. tostring(userId), function(existing)
			if type(existing) == "number" and existing > 0 then
				pendingCoins = existing
				return 0
			end
			return existing
		end)
	end)
	if pendingCoins > 0 then
		local profile = DPS.Load(player)
		if profile and type(profile.currencies) == "table" then
			profile.currencies.Coins = (tonumber(profile.currencies.Coins) or 0) + pendingCoins
			DPS.PushProfile(player)
		end
	end

	-- Pending item returns (expired/cancelled while offline)
	local pendingItems = {}
	pcall(function()
		store:UpdateAsync("pendingReturn_" .. tostring(userId), function(existing)
			if type(existing) == "table" and #existing > 0 then
				pendingItems = existing
				return {}
			end
			return existing
		end)
	end)
	if #pendingItems > 0 then
		for _, item in ipairs(pendingItems) do
			grantItemDirect(player, item)
		end
		DPS.PushProfile(player)
	end
end

-- ---------------------------------------------------------------------------
-- RF: AuctionGetListings
-- params = { page, filter, searchItem, searchPlayer, priceSort }
-- ---------------------------------------------------------------------------
rfGetListings.OnServerInvoke = function(_player, params)
	params = type(params) == "table" and params or {}
	local page        = math.max(1, math.floor(tonumber(params.page) or 1))
	local filter      = type(params.filter)       == "string" and params.filter       or nil
	local searchItem  = type(params.searchItem)   == "string" and params.searchItem:lower() or nil
	local searchPlayer= type(params.searchPlayer) == "string" and params.searchPlayer:lower() or nil
	local priceSort   = type(params.priceSort)    == "string" and params.priceSort    or nil

	local all  = getActiveCache()
	local now  = os.time()
	local list = {}

	for _, listing in pairs(all) do
		if type(listing.expiresAt) == "number" and now <= listing.expiresAt then
			local item    = listing.item or {}
			local include = true

			if filter and filter ~= "" then
				local itype = item.type or ""
				local tags  = type(item.tags) == "table" and item.tags or {}
				local isProf = false
				for _, t in ipairs(tags) do
					if t == "Pickaxe" or t == "FishingSpear" then isProf = true end
				end
				if filter == "Weapons" then
					include = itype == "Weapon"
				elseif filter == "Armor" then
					include = itype == "Armor"
				elseif filter == "Consumables" then
					include = itype == "Consumable" or itype == "Food"
				elseif filter == "Professions" then
					include = isProf
				elseif filter == "Other" then
					include = (itype ~= "Weapon" and itype ~= "Armor"
						and itype ~= "Consumable" and itype ~= "Food" and not isProf)
				end
			end

			if include and searchItem and searchItem ~= "" then
				include = (item.name or ""):lower():find(searchItem, 1, true) ~= nil
			end
			if include and searchPlayer and searchPlayer ~= "" then
				include = (listing.sellerName or ""):lower():find(searchPlayer, 1, true) ~= nil
			end

			if include then table.insert(list, listing) end
		end
	end

	if priceSort == "asc" then
		table.sort(list, function(a, b) return a.price < b.price end)
	elseif priceSort == "desc" then
		table.sort(list, function(a, b) return a.price > b.price end)
	else
		table.sort(list, function(a, b) return (a.listedAt or 0) > (b.listedAt or 0) end)
	end

	local pageSize   = Config.PAGE_SIZE
	local total      = #list
	local totalPages = math.max(1, math.ceil(total / pageSize))
	page = math.clamp(page, 1, totalPages)
	local s = (page - 1) * pageSize + 1
	local e = math.min(s + pageSize - 1, total)
	local slice = {}
	for i = s, e do slice[#slice + 1] = list[i] end

	return { listings = slice, totalPages = totalPages, currentPage = page, totalCount = total }
end

-- ---------------------------------------------------------------------------
-- RF: AuctionGetMyListings
-- ---------------------------------------------------------------------------
rfGetMyListings.OnServerInvoke = function(player)
	local userId = player.UserId
	local all    = getActiveCache()
	local active = {}
	for _, listing in pairs(all) do
		if listing.sellerId == userId then table.insert(active, listing) end
	end
	table.sort(active, function(a, b) return (a.listedAt or 0) > (b.listedAt or 0) end)

	local history = {}
	pcall(function()
		local raw = store:GetAsync("history_" .. tostring(userId))
		if type(raw) == "table" then history = raw end
	end)

	return { active = active, history = history }
end

-- ---------------------------------------------------------------------------
-- RF: AuctionCreateListing
-- ---------------------------------------------------------------------------
rfCreateListing.OnServerInvoke = function(player, itemUuid, price, durationDays)
	if type(itemUuid) ~= "string" or itemUuid == "" then
		return { ok = false, err = "bad_item" }
	end
	price = math.floor(tonumber(price) or 0)
	if price < 1 or price > Config.MAX_PRICE then
		return { ok = false, err = "bad_price" }
	end
	durationDays = math.floor(tonumber(durationDays) or 0)
	if durationDays < 1 or durationDays > Config.MAX_DURATION_DAYS then
		return { ok = false, err = "bad_duration" }
	end

	local profile = DPS.Load(player)
	if not profile then return { ok = false, err = "no_profile" } end

	local item = profile.inventory[itemUuid]
	if not item then return { ok = false, err = "not_in_inventory" } end

	if type(profile.equipped) == "table" then
		for _, uuid in pairs(profile.equipped) do
			if uuid == itemUuid then
				return { ok = false, err = "item_equipped" }
			end
		end
	end

	-- Untradeable items (starter/training gear) cannot be listed
	local ItemDefinitions = require(game:GetService("ReplicatedStorage"):WaitForChild("ItemDefinitions"))
	if item.untradeable == true or (type(item.itemId) == "string" and ItemDefinitions.IsUntradeable(item.itemId)) then
		return { ok = false, err = "untradeable" }
	end

	-- Cap active listings per player
	local all = getActiveCache()
	local myCount = 0
	for _, l in pairs(all) do
		if l.sellerId == player.UserId then myCount += 1 end
	end
	if myCount >= Config.MAX_ACTIVE_PER_PLAYER then
		return { ok = false, err = "too_many_listings" }
	end

	-- Snapshot the item and remove from inventory
	local itemSnapshot = {}
	for k, v in pairs(item) do itemSnapshot[k] = v end

	profile.inventory[itemUuid] = nil
	if type(profile.hotbar) == "table" then
		for i = 1, 9 do
			if profile.hotbar[i] == itemUuid then profile.hotbar[i] = nil end
		end
	end

	local listingId = HttpService:GenerateGUID(false)
	local now       = os.time()
	local listing   = {
		id          = listingId,
		sellerId    = player.UserId,
		sellerName  = player.Name,
		item        = itemSnapshot,
		price       = price,
		listedAt    = now,
		expiresAt   = now + durationDays * 86400,
	}

	local saveOk, saveErr, expiredListings = mutateActive(function(existing)
		existing[listingId] = listing
	end)

	if not saveOk then
		-- Restore item
		profile.inventory[itemUuid] = item
		return { ok = false, err = "save_failed" }
	end

	processExpired(expiredListings)
	DPS.PushProfile(player)
	return { ok = true, listing = listing }
end

-- ---------------------------------------------------------------------------
-- RF: AuctionCancelListing
-- ---------------------------------------------------------------------------
rfCancelListing.OnServerInvoke = function(player, listingId)
	if type(listingId) ~= "string" then
		return { ok = false, err = "bad_id" }
	end

	local all     = getActiveCache()
	local listing = all[listingId]
	if not listing then return { ok = false, err = "not_found" } end
	if listing.sellerId ~= player.UserId then return { ok = false, err = "not_owner" } end

	local removedListing = nil
	local saveOk, _, expiredListings = mutateActive(function(existing)
		removedListing = existing[listingId]
		existing[listingId] = nil
	end)

	if not saveOk then return { ok = false, err = "save_failed" } end

	processExpired(expiredListings)

	if removedListing then
		if grantItemDirect(player, removedListing.item) then
			DPS.PushProfile(player)
		end
		addToHistory(player.UserId, {
			id        = listingId,
			item      = removedListing.item,
			price     = removedListing.price,
			listedAt  = removedListing.listedAt,
			expiresAt = removedListing.expiresAt,
			status    = "cancelled",
			soldAt    = os.time(),
		})
	end

	return { ok = true }
end

-- ---------------------------------------------------------------------------
-- RF: AuctionBuyListing
-- ---------------------------------------------------------------------------
rfBuyListing.OnServerInvoke = function(player, listingId)
	if type(listingId) ~= "string" then
		return { ok = false, err = "bad_id" }
	end

	local profile = DPS.Load(player)
	if not profile then return { ok = false, err = "no_profile" } end

	local preview = getActiveCache()[listingId]
	if not preview then return { ok = false, err = "not_found" } end
	if preview.sellerId == player.UserId then return { ok = false, err = "own_listing" } end

	local coins = math.floor(tonumber(profile.currencies and profile.currencies.Coins) or 0)
	if coins < preview.price then return { ok = false, err = "insufficient_funds" } end

	-- Atomically remove the listing (race-safe: another buyer may beat us)
	local removedListing = nil
	local alreadyGone    = false
	local saveOk, _, expiredListings = mutateActive(function(existing)
		local target = existing[listingId]
		if not target then
			alreadyGone = true
			return
		end
		removedListing = target
		existing[listingId] = nil
	end)

	if not saveOk then return { ok = false, err = "save_failed" } end
	if alreadyGone then return { ok = false, err = "already_sold" } end
	if not removedListing then return { ok = false, err = "not_found" } end

	processExpired(expiredListings)

	-- Deduct coins from buyer
	profile.currencies.Coins = coins - removedListing.price

	-- Grant item to buyer
	if grantItemDirect(player, removedListing.item) then
		DPS.PushProfile(player)
	end

	-- Pay seller
	local seller = Players:GetPlayerByUserId(removedListing.sellerId)
	if seller then
		local sellerProfile = DPS.Load(seller)
		if sellerProfile and type(sellerProfile.currencies) == "table" then
			sellerProfile.currencies.Coins =
				(tonumber(sellerProfile.currencies.Coins) or 0) + removedListing.price
			DPS.PushProfile(seller)
		end
	else
		depositPendingCoins(removedListing.sellerId, removedListing.price)
	end

	addToHistory(removedListing.sellerId, {
		id         = listingId,
		item       = removedListing.item,
		price      = removedListing.price,
		listedAt   = removedListing.listedAt,
		expiresAt  = removedListing.expiresAt,
		status     = "sold",
		buyerId    = player.UserId,
		buyerName  = player.Name,
		soldAt     = os.time(),
	})

	return { ok = true }
end

-- ---------------------------------------------------------------------------
-- Player join: claim pending coins/items
-- ---------------------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	task.wait(4) -- allow DungeonBootstrap to load profile first
	if player and player.Parent then
		claimPendingForPlayer(player)
	end
end)

print("[AuctionHouseService] ready")
