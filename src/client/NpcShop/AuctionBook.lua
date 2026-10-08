--!strict
--  NpcShop/AuctionBook -- the Auction House (rebuilt 2026-10-01 from the old 1,900-line window).
--  Three sections in the Journal sidebar:
--    Browse       category bookmark tabs on the book's top edge (All, Weapons, Armor,
--                 Consumables, Professions, Other). Left page: search (by item or seller),
--                 sort, the listings and the page controls. Right page: the selected listing,
--                 its real stats, seller, time left, and Buy. Buying is an explicit button on
--                 the selected listing (the old window bought on a single click).
--    Sell         left: your bags (anything not equipped and tradeable). Right: the item, a
--                 price box, how long to list it, and List it.
--    My Listings  Selling / History tabs. Right page: the listing; active ones can be taken
--                 back (the item returns to your bags).
--  Server: SSS/AuctionHouseService remotes AuctionGetListings / GetMyListings / CreateListing /
--  CancelListing / BuyListing (RS). Limits in RS/AuctionConfig.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local Config = require(ReplicatedStorage:WaitForChild("AuctionConfig"))
local DungeonMenuNet = require(script.Parent.Parent:WaitForChild("DungeonMenuNet"))
local ShopParts = require(script.Parent:WaitForChild("ShopParts"))
local Inventory = script.Parent.Parent:WaitForChild("InventoryHud"):WaitForChild("Inventory")
local InventoryData = require(Inventory:WaitForChild("InventoryData"))
local Tooltip = require(Inventory:WaitForChild("Tooltip"))
local Journal = Inventory:WaitForChild("Journal")
local Style = require(Journal:WaitForChild("Style"))
local Parts = require(Journal:WaitForChild("Parts"))
local Book = require(Journal:WaitForChild("Book"))
local Sidebar = require(Journal:WaitForChild("Sidebar"))

local e = React.createElement
local text = Parts.Text

local SECTIONS = {
	{ id = "Browse", label = "Browse", iconArt = "fx_coinfind" },
	{ id = "Sell", label = "Sell", iconArt = "nav_glyph_inventory" },
	{ id = "Mine", label = "My Listings", iconArt = "icon_records" },
}
local CATEGORIES = {
	{ id = "All", label = "All" },
	{ id = "Weapons", label = "Weapons" },
	{ id = "Armor", label = "Armor" },
	{ id = "Consumables", label = "Potions" },
	{ id = "Professions", label = "Tools" },
	{ id = "Other", label = "Other" },
}
local SORTS = { { id = "new", label = "Newest" }, { id = "asc", label = "Cheapest" }, { id = "desc", label = "Priciest" } }
local DURATIONS = { { id = 1, label = "1 day" }, { id = 3, label = "3 days" }, { id = Config.MAX_DURATION_DAYS, label = Config.MAX_DURATION_DAYS .. " days" } }

local ERRORS = {
	own_listing = "That's your own listing.",
	insufficient_funds = "Not enough coins.",
	not_found = "That listing is gone.",
	already_sold = "Someone just bought it.",
	save_failed = "The auction house didn't answer. Try again.",
	untradeable = "That can't be sold.",
	item_equipped = "Unequip it first.",
	not_in_inventory = "That's no longer in your bags.",
	too_many_listings = ("You can have at most %d listings."):format(Config.MAX_ACTIVE_PER_PLAYER),
	bad_price = ("Price must be 1 to %s."):format(ShopParts.commas(Config.MAX_PRICE)),
	bad_duration = "Pick how long to list it.",
	not_owner = "That isn't yours.",
	no_profile = "Still loading. Try again.",
	unavailable = "The auction house isn't answering. Try again.",
}
local function errorText(code: any): string
	return (type(code) == "string" and ERRORS[code]) or "That didn't work."
end

local function invoke(name: string, ...: any): any
	local remote = ReplicatedStorage:FindFirstChild(name)
	if not remote then return { ok = false, err = "unavailable" } end
	local args = table.pack(...)
	local ok, res = pcall(function() return (remote :: RemoteFunction):InvokeServer(table.unpack(args, 1, args.n)) end)
	if not ok or type(res) ~= "table" then return { ok = false, err = "unavailable" } end
	return res
end

local function timeLeft(expiresAt: number?, now: number): string
	local secs = math.max(0, (tonumber(expiresAt) or 0) - now)
	if secs <= 0 then return "Ended" end
	local d, h, m = math.floor(secs / 86400), math.floor(secs % 86400 / 3600), math.floor(secs % 3600 / 60)
	if d > 0 then return ("%dd %dh"):format(d, h) end
	if h > 0 then return ("%dh %dm"):format(h, m) end
	return ("%dm %ds"):format(m, secs % 60)
end

local function dateText(ts: number?): string
	if type(ts) ~= "number" then return "" end
	local ok, s = pcall(function() return DateTime.fromUnixTimestamp(ts):FormatLocalTime("MMM D, h:mm A", "en-us") end)
	return ok and s or ""
end

local function nameOf(item: any): string
	return ItemDefinitions.GetDisplayNameForItem(item or {})
end

local function kindOf(item: any): string
	local bits = {}
	local rarity = ItemDefinitions.GetRarityForItem(item or {})
	if rarity then table.insert(bits, rarity) end
	if tonumber(item and item.tier) then table.insert(bits, "Tier " .. item.tier) end
	if item and type(item.type) == "string" then table.insert(bits, item.type) end
	return table.concat(bits, ", ")
end

-- The item's stats as a few lines: base stats on one line, then its substats.
local function statsText(item: any): string
	local lines = {}
	local base = Tooltip.BaseStatLines(item and item.subStats)
	if #base > 0 then table.insert(lines, table.concat(base, ", ")) end
	for _, line in ipairs(Tooltip.SubstatLines(item and item.subStats)) do
		if #lines >= 4 then break end
		table.insert(lines, line)
	end
	if #lines == 0 then
		local def = item and type(item.itemId) == "string" and ItemDefinitions.Get(item.itemId)
		return def and def.Description or ""
	end
	return table.concat(lines, "\n")
end

local function useNow(): number
	local now, setNow = React.useState(os.time())
	React.useEffect(function()
		local alive = true
		task.spawn(function()
			while alive do
				task.wait(1)
				if alive then setNow(os.time()) end
			end
		end)
		return function() alive = false end
	end, {})
	return now
end

local function listingRow(listing: any, props: { selected: boolean, order: number, onSelect: () -> (), sub: string })
	local item = listing.item or {}
	return e(ShopParts.ItemRow, {
		item = item,
		name = nameOf(item),
		nameColor = ShopParts.rarityColor(item),
		sub = props.sub,
		selected = props.selected,
		order = props.order,
		onSelect = props.onSelect,
	})
end

--------------------------------------------------------------------------------
-- Browse
--------------------------------------------------------------------------------

local function Browse(props: { snapshot: any, side: any, now: number })
	local profile = props.snapshot and props.snapshot.profile
	local coins = ShopParts.coins(profile)
	local category, setCategory = React.useState("All")
	local sort, setSort = React.useState("new")
	local search, setSearch = React.useState({ text = "", by = "item" })
	local draft, setDraft = React.useState("")
	local page, setPage = React.useState(1)
	local reload, setReload = React.useState(0)
	local result, setResult = React.useState(nil :: any)
	local loading, setLoading = React.useState(true)
	local selectedId, setSelectedId = React.useState(nil :: string?)
	local busy, setBusy = React.useState(false)
	local status, statusGood, setStatus = ShopParts.useStatus()

	React.useEffect(function()
		local alive = true
		setLoading(true)
		task.spawn(function()
			local res = invoke("AuctionGetListings", {
				page = page,
				filter = category ~= "All" and category or nil,
				searchItem = (search.by == "item" and search.text ~= "") and search.text or nil,
				searchPlayer = (search.by == "seller" and search.text ~= "") and search.text or nil,
				priceSort = sort ~= "new" and sort or nil,
			})
			if not alive then return end
			setLoading(false)
			setResult(res.listings and res or { listings = {}, totalPages = 1, currentPage = 1, totalCount = 0, failed = true })
		end)
		return function() alive = false end
	end, { category, sort, search.text, search.by, page, reload } :: { any })

	local listings = result and result.listings or {}
	local current = nil
	for _, listing in ipairs(listings) do
		if listing.id == selectedId then current = listing end
	end
	current = current or listings[1]

	local rows: { [string]: any } = {}
	for i, listing in ipairs(listings) do
		rows["L" .. i] = listingRow(listing, {
			selected = current ~= nil and listing.id == current.id,
			order = i,
			onSelect = function() setSelectedId(listing.id) end,
			sub = ("%s, %s, %s"):format(ShopParts.priceText(listing.price or 0, "Coins"), listing.sellerName or "?", timeLeft(listing.expiresAt, props.now)),
		})
	end

	local totalPages = result and result.totalPages or 1
	local sub
	if loading then
		sub = "Looking..."
	elseif result and result.failed then
		sub = "The auction house isn't answering."
	else
		local count = result and result.totalCount or 0
		sub = (count == 1 and "1 listing" or (ShopParts.commas(count) .. " listings")) .. (totalPages > 1 and (", page %d of %d"):format(page, totalPages) or "")
	end

	local function nextSort()
		for i, option in ipairs(SORTS) do
			if option.id == sort then
				setSort(SORTS[i % #SORTS + 1].id)
				setPage(1)
				return
			end
		end
	end
	local sortLabel = "Newest"
	for _, option in ipairs(SORTS) do
		if option.id == sort then sortLabel = option.label end
	end

	local left = e(ShopParts.Page, {
		heading = "Auction House",
		sub = sub,
		body = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
			Search = e(ShopParts.Input, {
				placeholder = search.by == "item" and "Search items" or "Search sellers",
				initial = search.text,
				Size = UDim2.new(1, -130, 0, 34),
				onChanged = setDraft,
				onSubmit = function(value)
					setSearch({ text = value, by = search.by })
					setPage(1)
				end,
			}),
			By = e(Parts.ChromeButton, {
				text = search.by == "item" and "By item" or "By seller",
				art = "chip", artSelected = "chip_selected",
				AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 2),
				Size = UDim2.fromOffset(120, 30), textSize = 14,
				onClick = function()
					setSearch({ text = draft, by = search.by == "item" and "seller" or "item" })
					setPage(1)
				end,
			}),
			List = e("Frame", {
				Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 1, -88), BackgroundTransparency = 1,
			}, {
				Rows = ShopParts.List(rows, loading and "" or "Nothing listed here right now."),
			}),
			Sort = e(Parts.ChromeButton, {
				text = "Sort: " .. sortLabel, art = "chip", artSelected = "chip_selected",
				AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0),
				Size = UDim2.fromOffset(150, 32), textSize = 14,
				onClick = nextSort,
			}),
			Prev = e(Parts.ChromeButton, {
				text = "Prev", art = "chip", artSelected = "chip_selected", disabled = page <= 1,
				AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -96, 1, 0),
				Size = UDim2.fromOffset(86, 32), textSize = 14,
				onClick = function() setPage(math.max(1, page - 1)) end,
			}),
			Next = e(Parts.ChromeButton, {
				text = "Next", art = "chip", artSelected = "chip_selected", disabled = page >= totalPages,
				AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, 0),
				Size = UDim2.fromOffset(86, 32), textSize = 14,
				onClick = function() setPage(math.min(totalPages, page + 1)) end,
			}),
		}),
	})

	local detail: { [string]: any }
	if current then
		local item = current.item or {}
		local price = math.floor(tonumber(current.price) or 0)
		local mine = current.sellerName == game:GetService("Players").LocalPlayer.Name
		local function buy()
			if busy then return end
			setBusy(true)
			local res = invoke("AuctionBuyListing", current.id)
			setBusy(false)
			if res.ok then
				setStatus("Bought " .. nameOf(item) .. ".", true)
				setSelectedId(nil)
				setReload(reload + 1)
				DungeonMenuNet.requestSync()
			else
				setStatus(errorText(res.err), false)
				if res.err == "already_sold" or res.err == "not_found" then setReload(reload + 1) end
			end
		end
		detail = {
			item = item,
			name = nameOf(item),
			nameColor = ShopParts.rarityColor(item),
			kind = kindOf(item),
			body = statsText(item),
			bodySize = 14,
			lines = {
				{ "Seller", current.sellerName or "?" },
				{ "Ends in", timeLeft(current.expiresAt, props.now) },
				{ "Price", ShopParts.priceText(price, "Coins"), coins >= price },
			},
			action = {
				text = mine and "Your listing" or (busy and "Buying..." or "Buy"),
				disabled = mine or busy or coins < price,
				onClick = buy,
			},
		}
	else
		detail = { emptyText = loading and "" or "Pick a listing on the left." }
	end
	detail.status, detail.statusGood = status, statusGood
	detail.coins = coins

	return e(Book, {
		side = props.side,
		tabs = e(ShopParts.BookTabs, {
			options = CATEGORIES, selected = category, width = 88,
			onSelect = function(id)
				setCategory(id)
				setPage(1)
			end,
		}),
		left = left,
		right = e(ShopParts.Detail, detail),
	})
end

--------------------------------------------------------------------------------
-- Sell
--------------------------------------------------------------------------------

local function Sell(props: { snapshot: any, side: any })
	local profile = props.snapshot and props.snapshot.profile
	local selectedUuid, setSelectedUuid = React.useState(nil :: string?)
	local priceText, setPriceText = React.useState("")
	local days, setDays = React.useState(DURATIONS[#DURATIONS].id)
	local busy, setBusy = React.useState(false)
	local listed, setListed = React.useState(nil :: number?)
	local status, statusGood, setStatus = ShopParts.useStatus()

	-- How many listings you already have (the cap is per player).
	React.useEffect(function()
		local alive = true
		task.spawn(function()
			local res = invoke("AuctionGetMyListings")
			if alive and type(res.active) == "table" then setListed(#res.active) end
		end)
		return function() alive = false end
	end, {})

	local equipped: { [string]: boolean } = {}
	for _, uuid in pairs(profile and profile.equipped or {}) do equipped[uuid] = true end
	local items = {}
	for uuid, item in pairs(profile and profile.inventory or {}) do
		local untradeable = type(item) == "table" and (item.untradeable == true
			or (type(item.itemId) == "string" and ItemDefinitions.IsUntradeable(item.itemId)))
		if type(item) == "table" and not equipped[uuid] and not untradeable then
			table.insert(items, { uuid = uuid, item = item })
		end
	end
	table.sort(items, function(a, b)
		local ta, tb = tostring(a.item.type or ""), tostring(b.item.type or "")
		if ta ~= tb then return ta < tb end
		return nameOf(a.item) < nameOf(b.item)
	end)
	local current = items[1]
	for _, entry in ipairs(items) do
		if entry.uuid == selectedUuid then current = entry end
	end
	-- A new item gets a fresh, empty price box (keyed below), so the price starts over too.
	local currentUuid = current and current.uuid
	React.useEffect(function()
		setPriceText("")
	end, { currentUuid })

	local rows: { [string]: any } = {}
	for i, entry in ipairs(items) do
		rows[entry.uuid] = e(ShopParts.ItemRow, {
			item = entry.item,
			name = nameOf(entry.item),
			nameColor = ShopParts.rarityColor(entry.item),
			sub = kindOf(entry.item),
			selected = current ~= nil and entry.uuid == current.uuid,
			order = i,
			onSelect = function() setSelectedUuid(entry.uuid) end,
		})
	end
	local left = e(ShopParts.Page, {
		heading = "Sell",
		sub = listed and ("Your listings: %d of %d"):format(listed, Config.MAX_ACTIVE_PER_PLAYER) or "Pick something from your bags.",
		help = "Equipped gear and starter gear can't be sold. A listed item leaves your bags; take it back from My Listings any time before it sells.",
		body = ShopParts.List(rows, "Nothing in your bags can be sold."),
	})

	local detail: { [string]: any }
	if current then
		local price = tonumber(priceText) or 0
		local valid = price >= 1 and price <= Config.MAX_PRICE
		local function list()
			if busy then return end
			if not valid then setStatus(ERRORS.bad_price, false); return end
			setBusy(true)
			local res = invoke("AuctionCreateListing", current.uuid, price, days)
			setBusy(false)
			if res.ok then
				setStatus(("Listed %s for %s."):format(nameOf(current.item), ShopParts.priceText(price, "Coins")), true)
				setSelectedUuid(nil)
				setListed((listed or 0) + 1)
				DungeonMenuNet.requestSync()
			else
				setStatus(errorText(res.err), false)
			end
		end
		detail = {
			item = current.item,
			name = nameOf(current.item),
			nameColor = ShopParts.rarityColor(current.item),
			kind = kindOf(current.item),
			body = statsText(current.item),
			bodySize = 14,
			controls = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
				Price = e(ShopParts.Input, {
					key = current.uuid, -- a fresh box per item
					placeholder = "Price in coins",
					numeric = true,
					Size = UDim2.new(1, 0, 0, 32),
					onChanged = setPriceText,
					onSubmit = function() list() end,
				}),
				Days = e(ShopParts.Chips, {
					options = DURATIONS, selected = days, onSelect = setDays, width = 100, height = 30,
					align = Enum.HorizontalAlignment.Center,
					Position = UDim2.fromOffset(0, 38),
				}),
			}),
			action = {
				text = busy and "Listing..." or (valid and ("List for " .. ShopParts.priceText(price, "Coins")) or "List it"),
				disabled = busy or not valid,
				onClick = list,
			},
		}
	else
		detail = { emptyText = "Pick something from your bags to sell." }
	end
	detail.status, detail.statusGood = status, statusGood
	detail.coins = ShopParts.coins(profile)

	return e(Book, { side = props.side, left = left, right = e(ShopParts.Detail, detail) })
end

--------------------------------------------------------------------------------
-- My Listings
--------------------------------------------------------------------------------

local HISTORY_WORDS = { sold = "Sold", cancelled = "Taken back", expired = "Expired" }

local function Mine(props: { snapshot: any, side: any, now: number })
	local profile = props.snapshot and props.snapshot.profile
	local view, setView = React.useState("active")
	local data, setData = React.useState(nil :: any)
	local reload, setReload = React.useState(0)
	local selectedId, setSelectedId = React.useState(nil :: string?)
	local busy, setBusy = React.useState(false)
	local status, statusGood, setStatus = ShopParts.useStatus()

	React.useEffect(function()
		local alive = true
		task.spawn(function()
			local res = invoke("AuctionGetMyListings")
			if alive then setData(res) end
		end)
		return function() alive = false end
	end, { reload })

	local entries = {}
	if data then
		local source = view == "active" and data.active or data.history
		for _, entry in ipairs(type(source) == "table" and source or {}) do table.insert(entries, entry) end
		if view == "history" then
			table.sort(entries, function(a, b) return (a.soldAt or 0) > (b.soldAt or 0) end)
		end
	end
	local current = entries[1]
	for _, entry in ipairs(entries) do
		if entry.id == selectedId then current = entry end
	end

	local rows: { [string]: any } = {}
	for i, entry in ipairs(entries) do
		local sub
		if view == "active" then
			sub = ("%s, %s left"):format(ShopParts.priceText(entry.price or 0, "Coins"), timeLeft(entry.expiresAt, props.now))
		else
			sub = ("%s, %s"):format(HISTORY_WORDS[entry.status] or "Ended", ShopParts.priceText(entry.price or 0, "Coins"))
		end
		rows["M" .. i] = listingRow(entry, {
			selected = current ~= nil and entry.id == current.id,
			order = i,
			onSelect = function() setSelectedId(entry.id) end,
			sub = sub,
		})
	end
	local left = e(ShopParts.Page, {
		heading = view == "active" and "Selling" or "History",
		sub = data == nil and "Looking..." or (view == "active"
			and ("%d of %d listings"):format(#entries, Config.MAX_ACTIVE_PER_PLAYER)
			or "Your recent sales"),
		body = ShopParts.List(rows, data == nil and "" or (view == "active" and "You aren't selling anything." or "Nothing sold yet.")),
	})

	local detail: { [string]: any }
	if current then
		local item = current.item or {}
		local lines
		local action = nil
		if view == "active" then
			lines = {
				{ "Price", ShopParts.priceText(current.price or 0, "Coins") },
				{ "Ends in", timeLeft(current.expiresAt, props.now) },
				{ "Listed", dateText(current.listedAt) },
			}
			action = {
				text = busy and "Taking back..." or "Take it back",
				disabled = busy,
				onClick = function()
					if busy then return end
					setBusy(true)
					local res = invoke("AuctionCancelListing", current.id)
					setBusy(false)
					if res.ok then
						setStatus(nameOf(item) .. " is back in your bags.", true)
						setSelectedId(nil)
						setReload(reload + 1)
						DungeonMenuNet.requestSync()
					else
						setStatus(errorText(res.err), false)
					end
				end,
			}
		else
			lines = {
				{ HISTORY_WORDS[current.status] or "Ended", dateText(current.soldAt) },
				{ "Price", ShopParts.priceText(current.price or 0, "Coins"), current.status == "sold" },
			}
			if current.status == "sold" then table.insert(lines, { "Buyer", current.buyerName or "?" }) end
		end
		detail = {
			item = item,
			name = nameOf(item),
			nameColor = ShopParts.rarityColor(item),
			kind = kindOf(item),
			body = statsText(item),
			bodySize = 14,
			lines = lines,
			action = action,
		}
	else
		detail = { emptyText = "" }
	end
	detail.status, detail.statusGood = status, statusGood
	detail.coins = ShopParts.coins(profile)

	return e(Book, {
		side = props.side,
		tabs = e(ShopParts.BookTabs, {
			options = { { id = "active", label = "Selling" }, { id = "history", label = "History" } },
			selected = view, width = 110,
			onSelect = function(id)
				setView(id)
				setSelectedId(nil)
			end,
		}),
		left = left,
		right = e(ShopParts.Detail, detail),
	})
end

--------------------------------------------------------------------------------

local function AuctionBook(_props: { npcId: string })
	local snapshot = InventoryData.useSnapshot()
	local now = useNow()
	local sectionId, setSection = React.useState("Browse")
	local side = e(Sidebar, { pages = SECTIONS, selected = sectionId, onSelect = setSection })
	if sectionId == "Sell" then
		return e(Sell, { key = "Sell", snapshot = snapshot, side = side })
	elseif sectionId == "Mine" then
		return e(Mine, { key = "Mine", snapshot = snapshot, side = side, now = now })
	end
	return e(Browse, { key = "Browse", snapshot = snapshot, side = side, now = now })
end

return AuctionBook
