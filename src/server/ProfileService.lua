--[[
  Server-authoritative Dungeon profile session store.
  ProfileService integration: replace sessions table + Load/Unload with
  ProfileService:LoadProfileAsync / ListenToRelease while keeping Reconcile().
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Types = require(ReplicatedStorage:WaitForChild("ProfileTypes"))
local Economy = require(ServerScriptService:WaitForChild("DungeonEconomyConfig"))
local StatsService = require(ServerScriptService:WaitForChild("StatsService"))
local EnergyData = require(ServerScriptService:WaitForChild("EnergyData"))
local Hotbar = require(ServerScriptService:WaitForChild("EquippedHotbar"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local ItemFactory = require(ReplicatedStorage:WaitForChild("Items"):WaitForChild("ItemFactory"))
local EnchantScrollApply = require(ReplicatedStorage:WaitForChild("EnchantScrollApply"))
local ProtectionScrollApply = require(ReplicatedStorage:WaitForChild("ProtectionScrollApply"))
local CraftingOrbApply = require(ReplicatedStorage:WaitForChild("CraftingOrbApply"))
local AltarUpgrade = require(ServerScriptService:WaitForChild("AltarUpgrade"))
local ArmorVisualsService = require(ServerScriptService:WaitForChild("ArmorVisualsService"))

local ProfileService = {}

-- Lazy requires for cross-cutting gates (combat flag, safe-zone) used by DropItem/
-- TrashItem below. Lazy + FindFirstChild (not WaitForChild) mirrors DamageService's
-- own getCombatState()/getPDM() pattern: CombatStateService already requires this
-- module back (dp() in CombatStateService.lua), so a hard top-level require here
-- would be circular at boot.
local _combatState
local function getCombatState()
	if not _combatState then
		local m = ServerScriptService:FindFirstChild("CombatStateService")
		if m then _combatState = require(m) end
	end
	return _combatState
end

local _zoneService
local function getZoneService()
	if not _zoneService then
		local m = ServerScriptService:FindFirstChild("ZoneService")
		if m then _zoneService = require(m) end
	end
	return _zoneService
end

local sessions = {}
-- Monotonic per-player snapshot generation for network payloads (push + RF). Lets the client
-- ignore out-of-order/stale RemoteEvent pushes that would otherwise overwrite a newer cache.
local snapshotGenByUserId = {}
local lastSnapshotPayloadByUserId = {}

--[[
	Persistence (2026-09): SaveProfile used to be a literal no-op ("wire to
	ProfileService UpdateAsync in a later milestone") -- this is that milestone.
	Mirrors PlayerDataManager.lua's session-locking pattern (see that file's header
	comment for the full rationale): each saved profile carries a
	{ JobId, UpdatedAt } Lock so a second server can't silently stomp a session
	that's still live elsewhere (relevant here because DungeonInstanceService can
	teleport a player to a different server for a dungeon run).

	Own DataStore, not shared with PlayerDataManager's "PlayerProfile_v1" (legacy
	HP/stats) or SettingsDataService's "PlayerSettings_v1" (audio/video sliders) --
	different owner, different data shape.
]]
local STORE_NAME        = "DungeonProfile_v1"
local LOCK_STALE_AFTER  = 60
local LOCK_HEARTBEAT    = 20
local LOAD_RETRY_COUNT  = 6
local LOAD_RETRY_DELAY  = 5
local AUTOSAVE_INTERVAL = 120

local store = DataStoreService:GetDataStore(STORE_NAME)
local studioFallback = false -- flips on when Studio API access is disabled
local heartbeats = {}
local loadingInProgress = {} -- [userId] = true while a Load's DataStore fetch is in flight

local function jobIdString()
	if game.JobId ~= "" then return game.JobId end
	return "Studio_" .. tostring(game.PlaceId)
end

local function keyFor(player)
	return "u_" .. tostring(player.UserId)
end

local function isApiDisabledError(err)
	return RunService:IsStudio() and string.find(tostring(err), "StudioAccessToApisNotAllowed", 1, true) ~= nil
end

-- Attempts to take the session lock for `player`, reading + reconciling whatever is
-- currently saved. Returns the (now locked-by-us) profile table, or nil if the lock
-- is held by another live server (age < LOCK_STALE_AFTER) or the DataStore call failed.
local function tryAcquireLock(player)
	local jobId = jobIdString()
	local now = os.time()
	local profile

	local ok, err = pcall(function()
		store:UpdateAsync(keyFor(player), function(old)
			old = Types.Reconcile(old)
			local lock = old.Lock
			if lock and lock.JobId ~= jobId then
				local age = now - (lock.UpdatedAt or 0)
				if age < LOCK_STALE_AFTER then
					return nil
				end
			end
			old.Lock = { JobId = jobId, UpdatedAt = now }
			profile = old
			return old
		end)
	end)

	if not ok then
		if isApiDisabledError(err) then
			studioFallback = true
		end
		warn("[ProfileService] UpdateAsync failed for " .. player.Name .. ": " .. tostring(err))
		return nil
	end
	return profile
end

-- Refreshes Lock.UpdatedAt every LOCK_HEARTBEAT seconds while this player's session is
-- live on this server, so the lock never goes stale under them mid-session. Exits on
-- its own once Unload clears sessions[userId].
local function startHeartbeat(player)
	heartbeats[player.UserId] = task.spawn(function()
		while sessions[player.UserId] do
			task.wait(LOCK_HEARTBEAT)
			if not sessions[player.UserId] then break end
			pcall(function()
				store:UpdateAsync(keyFor(player), function(old)
					if type(old) ~= "table" then return nil end
					if not old.Lock or old.Lock.JobId ~= jobIdString() then
						return nil
					end
					old.Lock.UpdatedAt = os.time()
					return old
				end)
			end)
		end
	end)
end

local t1KeyFragmentMilestoneShowRE = nil

local function countItemIdInBag(profile, itemId)
	local total = 0
	if type(profile) ~= "table" or type(profile.inventory) ~= "table" then
		return 0
	end
	for _, it in pairs(profile.inventory) do
		if type(it) == "table" and it.itemId == itemId then
			local c = tonumber(it.count)
			if c and ItemDefinitions.IsStackable(itemId) then
				total = total + math.max(0, math.floor(c))
			else
				total = total + 1
			end
		end
	end
	return total
end

local function getT1KeyFragmentMilestoneShowRE()
	if t1KeyFragmentMilestoneShowRE and t1KeyFragmentMilestoneShowRE.Parent then
		return t1KeyFragmentMilestoneShowRE
	end
	local ge = ReplicatedStorage:FindFirstChild("GameEvents")
	if not ge then
		return nil
	end
	local ev = ge:FindFirstChild("T1KeyFragment30MilestoneShow")
	if ev and ev:IsA("RemoteEvent") then
		t1KeyFragmentMilestoneShowRE = ev
		return ev
	end
	return nil
end

local function maybeFireT1KeyFragment30Milestone(player, profile, prevBagCount)
	if type(profile) ~= "table" then
		return
	end
	if type(profile.flags) ~= "table" then
		profile.flags = {}
	end
	if profile.flags.t1KeyFragment30NoticeDismissed == true then
		return
	end
	local newCount = countItemIdInBag(profile, "T1KeyFragment")
	prevBagCount = math.max(0, math.floor(tonumber(prevBagCount) or 0))
	if prevBagCount < 30 and newCount >= 30 then
		local ev = getT1KeyFragmentMilestoneShowRE()
		if ev then
			ev:FireClient(player, { count = newCount })
		end
	end
end

local pushEvent = nil
local BASE_SKILL_XP_REQUIREMENT = 5

local function getPushEvent()
	if pushEvent and pushEvent.Parent then
		return pushEvent
	end
	local ev = ReplicatedStorage:FindFirstChild("DungeonProfilePush")
	if not ev or not ev:IsA("RemoteEvent") then
		error("[ProfileService] Missing ReplicatedStorage.DungeonProfilePush RemoteEvent")
	end
	pushEvent = ev
	return pushEvent
end

function ProfileService.SetPushEventForTests(ev)
	pushEvent = ev
end

function ProfileService.Get(player)
	return sessions[player.UserId]
end

-- Forward declaration so Load can reference it before the body is defined below.
local ensureSkillStats
local dedupeHotbarInPlace
local placeItemInFirstEmptySlot
local placeItemInFirstEmptyBagSlot

local function hotbarSlotUuid(hb, i)
	if type(hb) ~= "table" then return nil end
	i = math.floor(tonumber(i) or -1)
	if i < 1 or i > 9 then return nil end
	local v = hb[i]
	if type(v) == "string" and v ~= "" then return v end
	v = hb[tostring(i)]
	if type(v) == "string" and v ~= "" then return v end
	return nil
end



local function ensureHotbar(profile)
	if type(profile.hotbar) ~= "table" then
		profile.hotbar = { nil, nil, nil, nil, nil, nil, nil, nil, nil }
	else
		local hb = {}
		for i = 1, 9 do
			hb[i] = hotbarSlotUuid(profile.hotbar, i)
		end
		profile.hotbar = hb
		for k in pairs(profile.hotbar) do
			if type(k) ~= "number" then
				profile.hotbar[k] = nil
			end
		end
	end
end

-- One Tool instance per inventory UUID (EquippedHotbar). Never keep the same uuid in
-- equipped.* and hotbar at once, or two hotbar slots, or UI/actions will look "linked".
local function clearItemUuidFromAllHotbar(profile, itemUuid)
	if type(itemUuid) ~= "string" or itemUuid == "" then
		return
	end
	ensureHotbar(profile)
	for i = 1, 9 do
		if hotbarSlotUuid(profile.hotbar, i) == itemUuid then
			profile.hotbar[i] = nil
			profile.hotbar[tostring(i)] = nil
		end
	end
end

local function bagSlotUuid(bs, i)
	if type(bs) ~= "table" then return nil end
	i = math.floor(tonumber(i) or -1)
	if i < 1 or i > Types.BAG_SLOT_COUNT then return nil end
	local v = bs[i]
	if type(v) == "string" and v ~= "" then return v end
	v = bs[tostring(i)]
	if type(v) == "string" and v ~= "" then return v end
	return nil
end

local function ensureBagSlots(profile)
	if type(profile.bagSlots) ~= "table" then
		profile.bagSlots = {}
		for i = 1, Types.BAG_SLOT_COUNT do
			profile.bagSlots[i] = nil
		end
	else
		local bs = {}
		for i = 1, Types.BAG_SLOT_COUNT do
			bs[i] = bagSlotUuid(profile.bagSlots, i)
		end
		profile.bagSlots = bs
	end
end

local function hasFreeBagSlot(profile)
	ensureBagSlots(profile)
	for i = 1, Types.BAG_SLOT_COUNT do
		if bagSlotUuid(profile.bagSlots, i) == nil then
			return true
		end
	end
	return false
end

-- Equip-box slots that double as extra storage when they're empty (Minecraft-style: an
-- unused gear slot isn't wasted capacity, and "inventory full" should account for it).
-- Kept in sync with PlayerPreview.lua's SLOTS list -- the only equip slots with a real
-- UI box. Necklace/Ring/Armor/Potion are valid VALID_SLOTS values with no equip box
-- today, so they're deliberately excluded here (landing an item there would be
-- invisible to the player).
local STORAGE_EQUIP_SLOTS = {
	Helm = true, Chest = true, Legs = true, Boots = true, Shield = true,
	Weapon = true, Bow = true, Pickaxe = true, FishingSpear = true,
}

-- Returns the equip-box slot `item` could land in if the bag is full, or nil if it
-- isn't equippable into one of STORAGE_EQUIP_SLOTS or that slot is already occupied.
local function emptyStorageEquipSlotFor(profile, item)
	if type(item) ~= "table" then
		return nil
	end
	local slot = Types.GetAllowedEquipSlot(item)
	if not slot or not STORAGE_EQUIP_SLOTS[slot] then
		return nil
	end
	if type(profile.equipped) == "table" and profile.equipped[slot] ~= nil then
		return nil
	end
	return slot
end

-- Whether granting `item` (an owned-item/template-shaped table -- has type/equipSlot/
-- tags) would find a home: an open bag slot, or an empty equip-box slot it can wear
-- into. Mirrors placeItemInFirstEmptySlot's own fallback below -- keep both in sync.
function ProfileService.HasRoomForItem(profile, item)
	if hasFreeBagSlot(profile) then
		return true
	end
	return emptyStorageEquipSlotFor(profile, item) ~= nil
end

-- Whether granting `count` more of stackable `itemId` would find a home: room in an
-- existing under-cap stack counts, so this only needs a free bag slot when every
-- existing stack of itemId is already maxed (stackables never use equip-box slots).
function ProfileService.HasRoomForStackable(profile, itemId, count)
	count = math.max(0, math.floor(tonumber(count) or 0))
	if count <= 0 then
		return true
	end
	local maxStack = ItemDefinitions.GetMaxStack(itemId)
	for _, it in pairs(profile.inventory) do
		if type(it) == "table" and it.itemId == itemId and type(it.count) == "number" and it.count < maxStack then
			return true
		end
	end
	return hasFreeBagSlot(profile)
end

-- Whether granting one more of catalog `itemId` would find a home. Dispatches to
-- HasRoomForStackable for stackables; for non-stackables, builds a throwaway sample
-- record (ItemFactory.CreateOwnedItem has no side effects beyond minting a uuid we
-- discard) so the equip-slot fallback can be checked without a real item existing yet.
function ProfileService.HasRoomForItemId(profile, itemId)
	if not ItemDefinitions.Get(itemId) then
		return false
	end
	if ItemDefinitions.IsStackable(itemId) then
		return ProfileService.HasRoomForStackable(profile, itemId, 1)
	end
	if hasFreeBagSlot(profile) then
		return true
	end
	local sample = ItemFactory.CreateOwnedItem(itemId)
	return sample ~= nil and emptyStorageEquipSlotFor(profile, sample) ~= nil
end

-- Whether granting every item in `items` (owned-item-shaped tables, e.g. a death-loot
-- bundle) would find a home -- simulated against a scratch copy of bag/equip occupancy
-- so two items that would both only fit the same single empty equip slot correctly
-- count as "no room" for the second one, not a false pass.
function ProfileService.HasRoomForItems(profile, items)
	if type(items) ~= "table" then
		return true
	end
	local freeBag = 0
	ensureBagSlots(profile)
	for i = 1, Types.BAG_SLOT_COUNT do
		if bagSlotUuid(profile.bagSlots, i) == nil then
			freeBag = freeBag + 1
		end
	end
	local equippedScratch = {}
	if type(profile.equipped) == "table" then
		for slot, uuid in pairs(profile.equipped) do
			equippedScratch[slot] = uuid
		end
	end
	for _, item in ipairs(items) do
		if type(item) == "table" then
			if freeBag > 0 then
				freeBag = freeBag - 1
			else
				local slot = Types.GetAllowedEquipSlot(item)
				if slot and STORAGE_EQUIP_SLOTS[slot] and equippedScratch[slot] == nil then
					equippedScratch[slot] = true
				else
					return false
				end
			end
		end
	end
	return true
end

-- Mirrors clearItemUuidFromAllHotbar: an item leaving the bag (equipped, hotbarred,
-- chested, consumed, or destroyed) must not leave a stale bagSlots reference behind.
local function clearUuidFromBagSlots(profile, itemUuid)
	if type(itemUuid) ~= "string" or itemUuid == "" then
		return
	end
	ensureBagSlots(profile)
	for i = 1, Types.BAG_SLOT_COUNT do
		if bagSlotUuid(profile.bagSlots, i) == itemUuid then
			profile.bagSlots[i] = nil
			profile.bagSlots[tostring(i)] = nil
		end
	end
end

local function clearItemUuidFromAllEquipped(profile, itemUuid)
	if type(itemUuid) ~= "string" or itemUuid == "" then
		return
	end
	if type(profile.equipped) ~= "table" then
		return
	end
	for slot, eu in pairs(profile.equipped) do
		if eu == itemUuid then
			profile.equipped[slot] = nil
		end
	end
end

dedupeHotbarInPlace = function(profile)
	ensureHotbar(profile)
	local seen = {}
	for i = 1, 9 do
		local u = hotbarSlotUuid(profile.hotbar, i)
		if type(u) == "string" and u ~= "" then
			if seen[u] then
				profile.hotbar[i] = nil
			profile.hotbar[tostring(i)] = nil
			else
				seen[u] = true
			end
		end
	end
end

local function dedupeBagSlotsInPlace(profile)
	ensureBagSlots(profile)
	local seen = {}
	for i = 1, Types.BAG_SLOT_COUNT do
		local u = bagSlotUuid(profile.bagSlots, i)
		if type(u) == "string" and u ~= "" then
			if seen[u] then
				profile.bagSlots[i] = nil
			profile.bagSlots[tostring(i)] = nil
			else
				seen[u] = true
			end
		end
	end
end

--[[
	Load(player) -- get-or-create the in-memory session for `player`.

	First call per player (normally from ProfileBootstrap's PlayerAdded handler)
	yields: it fetches + reconciles the saved profile from DataStore under a
	session lock (retrying LOAD_RETRY_COUNT times against LOCK_STALE_AFTER, same
	shape as PlayerDataManager.Load), then caches it in `sessions` and starts a
	heartbeat to keep the lock fresh. Every call after that returns the cached
	session instantly, same as before this milestone.

	If a second thread calls Load while the first's DataStore fetch is still in
	flight, it waits on that fetch rather than racing a second UpdateAsync --
	two concurrent fetches would each hand back a *different* profile table, and
	whichever one loses the `sessions[userId] = profile` race would silently
	orphan any mutation the other thread already made to it.
]]
function ProfileService.Load(player)
	local existing = sessions[player.UserId]
	if existing then
		-- Reconcile in case new fields were added after the profile was first created
		Types.Reconcile(existing)
		ensureSkillStats(existing)
		dedupeHotbarInPlace(existing)
		dedupeBagSlotsInPlace(existing)
		return existing
	end

	if loadingInProgress[player.UserId] then
		while loadingInProgress[player.UserId] and sessions[player.UserId] == nil do
			task.wait(0.05)
		end
		if sessions[player.UserId] then
			return sessions[player.UserId]
		end
	end

	loadingInProgress[player.UserId] = true

	local profile = nil
	if not studioFallback then
		for attempt = 1, LOAD_RETRY_COUNT do
			profile = tryAcquireLock(player)
			if profile or studioFallback then
				break
			end
			if attempt < LOAD_RETRY_COUNT then
				task.wait(LOAD_RETRY_DELAY)
			end
		end
	end

	if profile then
		startHeartbeat(player)
	elseif studioFallback then
		warn("[ProfileService] Studio API access disabled. Using ephemeral profile for " .. player.Name .. " (no persistence).")
		profile = Types.DefaultProfile()
		profile.IsEphemeral = true
	else
		warn("[ProfileService] Could not acquire session lock for " .. player.Name .. " -- kicking.")
		player:Kick("Your session is still active on another server. Wait ~30 seconds and try again.")
		profile = Types.DefaultProfile()
		profile.IsEphemeral = true
	end

	ensureSkillStats(profile)
	dedupeHotbarInPlace(profile)
	dedupeBagSlotsInPlace(profile)
	sessions[player.UserId] = profile
	loadingInProgress[player.UserId] = nil
	return profile
end

--[[
	Unload(player) -- final cleanup at session end (called from ProfileBootstrap's
	PlayerRemoving, right after SaveProfile). Also releases the DataStore lock
	(Lock = nil) so another server can pick up the session immediately instead of
	waiting out LOCK_STALE_AFTER -- same idea as PlayerDataManager.Release.
]]
function ProfileService.Unload(player)
	local profile = sessions[player.UserId]
	if profile and not profile.IsEphemeral and not studioFallback then
		local jobId = jobIdString()
		pcall(function()
			store:UpdateAsync(keyFor(player), function(old)
				if type(old) == "table" and old.Lock and old.Lock.JobId ~= jobId then
					return nil
				end
				profile.Lock = nil
				return profile
			end)
		end)
	end
	sessions[player.UserId] = nil
	snapshotGenByUserId[player.UserId] = nil
	lastSnapshotPayloadByUserId[player.UserId] = nil
	loadingInProgress[player.UserId] = nil
	heartbeats[player.UserId] = nil
end

--[[
	SaveProfile(player) -- writes the cached session back to DataStore, keeping
	the lock (JobId/UpdatedAt refreshed) so autosave can call this repeatedly
	without releasing the session. No-ops for ephemeral (Studio-fallback)
	profiles and once studioFallback has latched on. Low-stakes compared to
	PlayerDataManager's data (that kicks on lock loss elsewhere); here, losing
	a race to another server just means this write is silently skipped --
	last-write-wins, same tradeoff SettingsDataService makes.
]]
function ProfileService.SaveProfile(player)
	local profile = sessions[player.UserId]
	if not profile or profile.IsEphemeral or studioFallback then
		return
	end
	local jobId = jobIdString()
	local ok, err = pcall(function()
		store:UpdateAsync(keyFor(player), function(old)
			if type(old) == "table" and old.Lock and old.Lock.JobId ~= jobId then
				return nil
			end
			profile.Lock = { JobId = jobId, UpdatedAt = os.time() }
			return profile
		end)
	end)
	if not ok then
		if isApiDisabledError(err) then
			studioFallback = true
		end
		warn("[ProfileService] SaveProfile failed for " .. player.Name .. ": " .. tostring(err))
	end
end

local function clampCount(count)
	if count == nil then
		return 1
	end
	if count ~= count or count <= 0 then
		return 1
	end
	return math.clamp(math.floor(count), 1, 100)
end

-- mapKindToLegacyItemType used to be needed here to build owned-item `type` fields by
-- hand; both call sites now go through ItemFactory.CreateOwnedItem (src/shared/Items/),
-- whose Item base class does this same Kind -> type mapping itself. Removed as dead code.

local function mergeStackableIntoInventory(player, profile, itemId, count)
	local def = ItemDefinitions.Get(itemId)
	if not def or not ItemDefinitions.IsStackable(itemId) then
		return false, "not_stackable"
	end
	local n = math.max(0, math.floor(tonumber(count) or 0))
	if n <= 0 then
		return true, nil
	end
	local maxStack = ItemDefinitions.GetMaxStack(itemId)
	local remaining = n
	while remaining > 0 do
		local merged = false
		for _, it in pairs(profile.inventory) do
			if type(it) == "table" and it.itemId == itemId and type(it.count) == "number" and it.count < maxStack then
				local room = maxStack - it.count
				local add = math.min(room, remaining)
				it.count = it.count + add
				remaining = remaining - add
				merged = true
				if remaining <= 0 then
					break
				end
			end
		end
		if remaining <= 0 then
			break
		end
		if not merged then
			local take = math.min(maxStack, remaining)
			-- ItemFactory stamps equipSlot correctly per Kind (see src/shared/Items/) --
			-- the old inline table here never set it at all, which is how e.g. training
			-- armor lost its specific Helm/Chest/Legs/Boots/Shield slot identity.
			local it = ItemFactory.CreateOwnedItem(itemId, { count = take })
			if not it then
				break
			end
			profile.inventory[it.uuid] = it
			placeItemInFirstEmptySlot(profile, it.uuid, player)
			remaining = remaining - take
		end
	end
	return true, nil
end

local function xpRequiredForLevel(level)
	local lv = math.max(1, math.floor(tonumber(level) or 1))
	return BASE_SKILL_XP_REQUIREMENT * (2 ^ (lv - 1))
end

-- Assign to the forward-declared upvalue (not a new local — that would shadow it)
ensureSkillStats = function(profile)
	if type(profile.stats) ~= "table" then
		profile.stats = {}
	end

	if type(profile.stats.combat) ~= "table" then
		profile.stats.combat = {}
	end
	profile.stats.combat.level = math.max(1, math.floor(tonumber(profile.stats.combat.level) or 1))
	profile.stats.combat.xp = math.max(0, math.floor(tonumber(profile.stats.combat.xp) or 0))

	if type(profile.stats.mining) ~= "table" then
		profile.stats.mining = {}
	end
	local miningLevel = profile.stats.mining.level or profile.stats.mining.miningLevel or 1
	profile.stats.mining.level = math.max(1, math.floor(tonumber(miningLevel) or 1))
	profile.stats.mining.xp = math.max(0, math.floor(tonumber(profile.stats.mining.xp) or 0))
	profile.stats.mining.miningLevel = profile.stats.mining.level

	if type(profile.stats.fishing) ~= "table" then
		profile.stats.fishing = {}
	end
	local fishingLevel = profile.stats.fishing.level or profile.stats.fishing.fishingLevel or 1
	profile.stats.fishing.level = math.max(1, math.floor(tonumber(fishingLevel) or 1))
	profile.stats.fishing.xp = math.max(0, math.floor(tonumber(profile.stats.fishing.xp) or 0))
	profile.stats.fishing.fishingLevel = profile.stats.fishing.level
end

function ProfileService.GrantItem(player, template, count)
	local profile = ProfileService.Load(player)
	local ok, err = Types.ValidateItemTemplate(template)
	if not ok then
		return false, err
	end
	local n = clampCount(count)

	local function isSalvageRarity(r)
		return r == "Common" or r == "Uncommon"
	end

	if profile.flags.inRaid and isSalvageRarity(template.rarity) then
		local per = Economy.SCRAP_PER_UNCOMMON_IN_RAID
		if template.rarity == "Common" then
			per = Economy.SCRAP_PER_COMMON_IN_RAID
		end
		local okm, errm = mergeStackableIntoInventory(player, profile, "T1Scrap", per * n)
		if not okm then
			return false, errm or "merge_failed"
		end
	else
		for _ = 1, n do
			local uuid = HttpService:GenerateGUID(false)
			local item = {
				uuid = uuid,
				name = template.name,
				type = template.type,
				rarity = template.rarity,
				tier = template.tier,
				level = template.level,
				enchantLevel = template.enchantLevel,
				subStats = template.subStats,
				equipSlot = template.equipSlot,
				tags = template.tags,
				toolPrefabName = template.toolPrefabName,
				durability    = template.durability,
				maxDurability = template.maxDurability,
			}
			if type(template.itemId) == "string" and template.itemId ~= "" then
				item.itemId = template.itemId
			else
				local inferred = Types.InferLegacyItemIdFromName(template.name)
				if type(inferred) == "string" and inferred ~= "" then
					item.itemId = inferred
				end
			end
			if type(item.count) ~= "number" or item.count < 1 or item.count ~= math.floor(item.count) then
				item.count = 1
			end
			profile.inventory[uuid] = item
			placeItemInFirstEmptySlot(profile, uuid, player)
		end
	end

	StatsService.RecomputeRuntimeHp(profile)
	ProfileService.PushProfile(player)
	return true, nil
end

local function legacyItemAllowsHotbar(item)
	if type(item) ~= "table" then
		return false
	end
	if item.type == "Weapon" then
		return true
	end
	if item.type == "Consumable" or item.type == "Food" then
		return true
	end
	if item.type == "Armor" then
		return false
	end
	if item.type == "Material" then
		if item.equipSlot == "Pickaxe" or item.equipSlot == "FishingSpear" then
			return true
		end
		if type(item.toolPrefabName) == "string" and item.toolPrefabName ~= "" then
			return true
		end
		return false
	end
	return false
end

local function itemAllowsHotbar(item)
	if type(item) ~= "table" then
		return false
	end
	if type(item.itemId) == "string" and item.itemId ~= "" then
		return ItemDefinitions.IsHotbarEquippable(item.itemId)
	end
	return legacyItemAllowsHotbar(item)
end

-- Bag-only placement: first empty bagSlots index. Used when an item is displaced from the
-- hotbar/equip panel back into general inventory (unequip, clear-hotbar) -- it should land
-- in the bag, never silently re-fill another hotbar slot.
-- Returns true if `uuid` landed in a bag slot, false if the bag was full.
placeItemInFirstEmptyBagSlot = function(profile, uuid)
	if type(uuid) ~= "string" or uuid == "" then
		return false
	end
	ensureBagSlots(profile)
	for i = 1, Types.BAG_SLOT_COUNT do
		if bagSlotUuid(profile.bagSlots, i) == nil then
			profile.bagSlots[i] = uuid
			return true
		end
	end
	return false
end

-- First-empty-slot placement for newly-acquired items (grants, chest withdrawals). The
-- hotbar is retired -- first choice is always the bag (first empty slot, top-left to
-- bottom-right); equipping is otherwise a separate, deliberate player action
-- (drag/right-click). Only when the bag is completely full does this fall back to an
-- empty equip-box slot (STORAGE_EQUIP_SLOTS above) the item can wear into -- an empty
-- gear slot is real capacity, not a place items only reach by choice. That fallback
-- needs `player` to drive the same visual/hotbar sync ProfileService.EquipItem does;
-- callers that only have `profile` (a handful of internal ones) skip it and the item
-- stays owned-but-unplaced, same as before this changed. Returns true if the item
-- found a home anywhere.
placeItemInFirstEmptySlot = function(profile, uuid, player)
	if placeItemInFirstEmptyBagSlot(profile, uuid) then
		return true
	end
	local item = profile.inventory[uuid]
	if player and type(item) == "table" then
		local slot = emptyStorageEquipSlotFor(profile, item)
		if slot then
			profile.equipped[slot] = uuid
			Hotbar.syncFromProfile(player, profile)
			ArmorVisualsService.ApplyVisual(player.Character, slot, item.itemId)
			return true
		end
	end
	return false
end

-- Public wrapper for callers outside this module that mint inventory entries directly
-- (e.g. AuctionHouseService returning/claiming a listing's item) instead of through
-- GrantItem/GrantItemId. Keeps "fill the first empty bag/equip-box slot" universal.
-- `player` is optional -- pass it when available so the equip-box fallback (see
-- placeItemInFirstEmptySlot above) can fire; omit it to keep the old bag-only behavior.
function ProfileService.PlaceItemInFirstEmptySlot(profile, uuid, player)
	return placeItemInFirstEmptySlot(profile, uuid, player)
end

-- Public wrapper around the same bag-count logic maybeFireT1KeyFragment30Milestone already
-- uses internally (countItemIdInBag). Exposed for callers outside this module that need a
-- read-only "how many of itemId does this player have" check -- e.g. the dungeon system
-- validating a party member's T1DungeonKey before letting the run start -- without having
-- to duplicate the stackable-vs-unstackable counting rule themselves.
function ProfileService.CountItemId(player, itemId)
	if type(itemId) ~= "string" or itemId == "" then
		return 0
	end
	local profile = ProfileService.Load(player)
	return countItemIdInBag(profile, itemId)
end

function ProfileService.GrantItemId(player, itemId, count)
	local profile = ProfileService.Load(player)
	local prevT1Frags = countItemIdInBag(profile, "T1KeyFragment")
	local def = ItemDefinitions.Get(itemId)
	if not def then
		return false, "unknown_item"
	end
	local n
	if ItemDefinitions.IsStackable(itemId) then
		n = math.max(0, math.floor(tonumber(count) or 0))
		if n <= 0 then
			return true, nil
		end
	else
		n = clampCount(count)
	end

	local function raidSalvageRarity(r)
		return r == "Common" or r == "Uncommon"
	end

	if profile.flags.inRaid and def.Rarity and raidSalvageRarity(def.Rarity) and not ItemDefinitions.IsTierScrapItemId(itemId) then
		local per = Economy.SCRAP_PER_UNCOMMON_IN_RAID
		if def.Rarity == "Common" then
			per = Economy.SCRAP_PER_COMMON_IN_RAID
		end
		local okm, errm = mergeStackableIntoInventory(player, profile, "T1Scrap", per * n)
		if not okm then
			return false, errm or "merge_failed"
		end
	elseif ItemDefinitions.IsStackable(itemId) then
		local okm, errm = mergeStackableIntoInventory(player, profile, itemId, n)
		if not okm then
			return false, errm or "merge_failed"
		end
	else
		for _ = 1, n do
			-- ItemFactory (src/shared/Items/) replaces this inline table: it stamps
			-- equipSlot correctly per Kind (Weapon/Armor/Material/Consumable) and, for
			-- weapons, rolls the same dmgMin/dmgMax from WeaponData this used to do by
			-- hand. The old version never set equipSlot at all -- every weapon collapsed
			-- onto "Weapon" (Bow included) and every armor piece onto a generic "Armor"
			-- bucket that isn't even a real equip-panel slot.
			local it = ItemFactory.CreateOwnedItem(itemId)
			if not it then
				break
			end
			profile.inventory[it.uuid] = it
			placeItemInFirstEmptySlot(profile, it.uuid, player)
		end
	end

	StatsService.RecomputeRuntimeHp(profile)
	ProfileService.PushProfile(player)
	maybeFireT1KeyFragment30Milestone(player, profile, prevT1Frags)
	return true, nil
end


function ProfileService.ClearHotbarSlot(player, slotIndex)
	local profile = ProfileService.Load(player)
	slotIndex = math.floor(tonumber(slotIndex) or -1)
	if slotIndex ~= slotIndex or slotIndex < 1 or slotIndex > 9 then
		return false, "bad_slot"
	end
	ensureHotbar(profile)
	local clearedUuid = hotbarSlotUuid(profile.hotbar, slotIndex)
	profile.hotbar[slotIndex] = nil
	profile.hotbar[tostring(slotIndex)] = nil
	-- Cleared item leaves the hotbar entirely -- it must land in the bag, not vanish.
	placeItemInFirstEmptyBagSlot(profile, clearedUuid)
	StatsService.RecomputeRuntimeHp(profile)
	ProfileService.PushProfile(player)
	Hotbar.syncFromProfile(player, profile)
	return true, ProfileService.BuildSnapshotPayload(player)
end

function ProfileService.SetHotbarSlot(player, slotIndex, itemUuid)
	local profile = ProfileService.Load(player)
	slotIndex = math.floor(tonumber(slotIndex) or -1)
	if slotIndex ~= slotIndex or slotIndex < 1 or slotIndex > 9 then
		return false, "bad_slot"
	end
	ensureHotbar(profile)
	if type(itemUuid) ~= "string" or itemUuid == "" then
		return ProfileService.ClearHotbarSlot(player, slotIndex)
	else
		if not profile.inventory[itemUuid] then
			return false, "not_owned"
		end
		if not itemAllowsHotbar(profile.inventory[itemUuid]) then
			return false, "not_hotbar_item"
		end
		clearItemUuidFromAllEquipped(profile, itemUuid)
		clearUuidFromBagSlots(profile, itemUuid)
		for i = 1, 9 do
			if hotbarSlotUuid(profile.hotbar, i) == itemUuid then
				profile.hotbar[i] = nil
			profile.hotbar[tostring(i)] = nil
			end
		end
		profile.hotbar[slotIndex] = itemUuid
		profile.hotbar[tostring(slotIndex)] = nil
	end
	dedupeHotbarInPlace(profile)
	StatsService.RecomputeRuntimeHp(profile)
	ProfileService.PushProfile(player)
	Hotbar.syncFromProfile(player, profile)
	return true, ProfileService.BuildSnapshotPayload(player)
end

function ProfileService.SwapHotbarSlots(player, a, b)
	local profile = ProfileService.Load(player)
	if type(a) ~= "number" or type(b) ~= "number" then
		return false, "bad_arg"
	end
	if a ~= math.floor(a) or b ~= math.floor(b) then
		return false, "bad_arg"
	end
	if a < 1 or a > 9 or b < 1 or b > 9 then
		return false, "bad_slot"
	end
	if a == b then
		return true, ProfileService.BuildSnapshotPayload(player)
	end
	ensureHotbar(profile)
	local ua = hotbarSlotUuid(profile.hotbar, a); local ub = hotbarSlotUuid(profile.hotbar, b)
	profile.hotbar[a], profile.hotbar[b] = ub, ua
	profile.hotbar[tostring(a)] = nil
	profile.hotbar[tostring(b)] = nil
	dedupeHotbarInPlace(profile)
	ProfileService.PushProfile(player)
	Hotbar.syncFromProfile(player, profile)
	return true, ProfileService.BuildSnapshotPayload(player)
end

local function readChestSlotRaw(slots, i)
	if type(slots) ~= "table" then
		return nil
	end
	local v = slots[i]
	if v ~= nil then
		return v
	end
	return slots[tostring(i)]
end

local function chestSlotIsEmpty(u)
	if u == nil or u == false then
		return true
	end
	if type(u) == "string" and u == "" then
		return true
	end
	return false
end

local function ensureChest(profile)
	if type(profile.chestInventory) ~= "table" then
		profile.chestInventory = {}
	end
	if type(profile.chestSlots) ~= "table" then
		profile.chestSlots = {}
		for i = 1, Types.CHEST_SLOT_COUNT do
			profile.chestSlots[i] = nil
		end
	else
		local cs = {}
		for i = 1, Types.CHEST_SLOT_COUNT do
			cs[i] = readChestSlotRaw(profile.chestSlots, i)
		end
		profile.chestSlots = cs
	end
	if type(profile.chestUnlockedRows) ~= "number" then
		profile.chestUnlockedRows = 1
	else
		profile.chestUnlockedRows = math.clamp(math.floor(profile.chestUnlockedRows), 1, Types.CHEST_GRID_ROWS)
	end
end

local function chestSlotRow(slotIndex)
	if type(slotIndex) ~= "number" then
		return 999
	end
	return math.ceil(slotIndex / Types.CHEST_GRID_COLUMNS)
end

local function getChestUnlockedRows(profile)
	return math.clamp(math.floor(tonumber(profile.chestUnlockedRows) or 1), 1, Types.CHEST_GRID_ROWS)
end

local function isChestSlotAccessible(profile, slotIndex)
	if type(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > Types.CHEST_SLOT_COUNT then
		return false
	end
	return chestSlotRow(slotIndex) <= getChestUnlockedRows(profile)
end

local function findFirstEmptyChestSlot(profile)
	for j = 1, Types.CHEST_SLOT_COUNT do
		if isChestSlotAccessible(profile, j) and chestSlotIsEmpty(profile.chestSlots[j]) then
			return j
		end
	end
	return nil
end

local function uuidEquipped(profile, uuid)
	for _, u in pairs(profile.equipped or {}) do
		if u == uuid then
			return true
		end
	end
	return false
end

local function clearUuidFromHotbar(profile, uuid)
	ensureHotbar(profile)
	for i = 1, 9 do
		if hotbarSlotUuid(profile.hotbar, i) == uuid then
			profile.hotbar[i] = nil
			profile.hotbar[tostring(i)] = nil
		end
	end
end

function ProfileService.ChestDepositToSlot(player, uuid, slotIndex)
	local profile = ProfileService.Load(player)
	if type(uuid) ~= "string" or uuid == "" then
		return false, "bad_uuid"
	end
	if type(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > Types.CHEST_SLOT_COUNT or slotIndex ~= math.floor(slotIndex) then
		return false, "bad_slot"
	end
	ensureChest(profile)
	ensureHotbar(profile)

	if not isChestSlotAccessible(profile, slotIndex) then
		return false, "locked"
	end

	local oldChestIdx = nil
	for i = 1, Types.CHEST_SLOT_COUNT do
		if profile.chestSlots[i] == uuid then
			oldChestIdx = i
			break
		end
	end

	if oldChestIdx then
		if not isChestSlotAccessible(profile, oldChestIdx) then
			return false, "bad_state"
		end
		local occ = profile.chestSlots[slotIndex]
		if occ == uuid then
			return true, nil
		end
		if occ == nil then
			profile.chestSlots[oldChestIdx] = nil
			profile.chestSlots[slotIndex] = uuid
		else
			profile.chestSlots[oldChestIdx] = occ
			profile.chestSlots[slotIndex] = uuid
		end
		ProfileService.PushProfile(player)
		return true, nil
	end

	local item = profile.inventory[uuid]
	if not item then
		return false, "not_owned"
	end
	if uuidEquipped(profile, uuid) then
		return false, "equipped"
	end

	clearUuidFromHotbar(profile, uuid)
	clearUuidFromBagSlots(profile, uuid)

	local targetSlot = nil
	if chestSlotIsEmpty(profile.chestSlots[slotIndex]) then
		targetSlot = slotIndex
	else
		targetSlot = findFirstEmptyChestSlot(profile)
	end
	if not targetSlot then
		return false, "chest_full"
	end

	profile.inventory[uuid] = nil
	profile.chestInventory[uuid] = item
	profile.chestSlots[targetSlot] = uuid

	StatsService.RecomputeRuntimeHp(profile)
	ProfileService.PushProfile(player)
	Hotbar.syncFromProfile(player, profile)
	return true, nil
end

function ProfileService.ChestWithdrawSlot(player, slotIndex)
	local profile = ProfileService.Load(player)
	local prevT1Frags = countItemIdInBag(profile, "T1KeyFragment")
	if type(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > Types.CHEST_SLOT_COUNT or slotIndex ~= math.floor(slotIndex) then
		return false, "bad_slot"
	end
	ensureChest(profile)
	if not isChestSlotAccessible(profile, slotIndex) then
		return false, "locked"
	end

	local uuid = profile.chestSlots[slotIndex]
	if type(uuid) ~= "string" or uuid == "" then
		return false, "empty"
	end

	local item = profile.chestInventory[uuid]
	if type(item) ~= "table" then
		return false, "missing_item"
	end

	profile.chestSlots[slotIndex] = nil
	profile.chestInventory[uuid] = nil
	profile.inventory[uuid] = item
	-- Item re-enters the bag/hotbar positional system when pulled from the chest.
	placeItemInFirstEmptySlot(profile, uuid, player)

	StatsService.RecomputeRuntimeHp(profile)
	ProfileService.PushProfile(player)
	Hotbar.syncFromProfile(player, profile)
	maybeFireT1KeyFragment30Milestone(player, profile, prevT1Frags)
	return true, nil
end

--[[
  RemoteFunction action: SetBagSlot(player, slotIndex, itemUuid) -- explicit placement into a
  bag slot (click-to-place destination). No hotbar-eligibility restriction: anything ownable
  can sit in the bag. Modeled directly on SetHotbarSlot/ClearHotbarSlot.
]]
function ProfileService.SetBagSlot(player, slotIndex, itemUuid)
	local profile = ProfileService.Load(player)
	slotIndex = math.floor(tonumber(slotIndex) or -1)
	if slotIndex ~= slotIndex or slotIndex < 1 or slotIndex > Types.BAG_SLOT_COUNT then
		return false, "bad_slot"
	end
	ensureBagSlots(profile)
	if type(itemUuid) ~= "string" or itemUuid == "" then
		return false, "bad_uuid"
	end
	if not profile.inventory[itemUuid] then
		return false, "not_owned"
	end
	clearItemUuidFromAllHotbar(profile, itemUuid)
	clearItemUuidFromAllEquipped(profile, itemUuid)
	clearUuidFromBagSlots(profile, itemUuid)
	profile.bagSlots[slotIndex] = itemUuid
	profile.bagSlots[tostring(slotIndex)] = nil
	dedupeBagSlotsInPlace(profile)
	dedupeHotbarInPlace(profile)
	StatsService.RecomputeRuntimeHp(profile)
	ProfileService.PushProfile(player)
	Hotbar.syncFromProfile(player, profile)
	return true, ProfileService.BuildSnapshotPayload(player)
end

--[[
  RemoteFunction action: SwapBagSlot(player, a, b) -- bag-to-bag swap by index. Replaces the
  old client-only cosmetic bag reordering with a server-authoritative swap.
]]
function ProfileService.SwapBagSlot(player, a, b)
	local profile = ProfileService.Load(player)
	if type(a) ~= "number" or type(b) ~= "number" then
		return false, "bad_arg"
	end
	if a ~= math.floor(a) or b ~= math.floor(b) then
		return false, "bad_arg"
	end
	if a < 1 or a > Types.BAG_SLOT_COUNT or b < 1 or b > Types.BAG_SLOT_COUNT then
		return false, "bad_slot"
	end
	if a == b then
		return true, ProfileService.BuildSnapshotPayload(player)
	end
	ensureBagSlots(profile)
	local ua = bagSlotUuid(profile.bagSlots, a); local ub = bagSlotUuid(profile.bagSlots, b)
	profile.bagSlots[a], profile.bagSlots[b] = ub, ua
	profile.bagSlots[tostring(a)] = nil
	profile.bagSlots[tostring(b)] = nil
	dedupeBagSlotsInPlace(profile)
	ProfileService.PushProfile(player)
	return true, ProfileService.BuildSnapshotPayload(player)
end

function ProfileService.UnlockChestRow(player, rowToUnlock)
	local profile = ProfileService.Load(player)
	ensureHotbar(profile)
	ensureChest(profile)
	if type(rowToUnlock) ~= "number" or rowToUnlock ~= math.floor(rowToUnlock) then
		return false, "bad_arg"
	end
	local r = rowToUnlock
	if r < 2 or r > Types.CHEST_GRID_ROWS then
		return false, "bad_arg"
	end
	local cur = getChestUnlockedRows(profile)
	if r ~= cur + 1 then
		return false, "not_next_row"
	end
	if cur >= Types.CHEST_GRID_ROWS then
		return false, "max_unlock"
	end
	local cost = Types.CHEST_ROW_UNLOCK_COIN_COST
	if type(cost) ~= "number" or cost < 0 then
		cost = 1
	end
	cost = math.floor(cost)
	if type(profile.currencies) ~= "table" then
		profile.currencies = { Coins = 0 }
	end
	local coins = math.floor(tonumber(profile.currencies.Coins) or 0)
	if coins < cost then
		return false, "not_enough"
	end
	profile.currencies.Coins = coins - cost
	profile.chestUnlockedRows = cur + 1
	ProfileService.PushProfile(player)
	return true, nil
end

function ProfileService.ApplyEnchantScroll(player, scrollUuid, targetUuid)
	local profile = ProfileService.Load(player)
	if type(scrollUuid) ~= "string" or scrollUuid == "" or type(targetUuid) ~= "string" or targetUuid == "" then
		return false, "bad_arg"
	end
	if scrollUuid == targetUuid then
		return false, "bad_arg"
	end
	ensureHotbar(profile)

	local scroll = profile.inventory[scrollUuid]
	local target = profile.inventory[targetUuid]
	if type(scroll) ~= "table" or type(target) ~= "table" then
		return false, "not_owned"
	end
	if type(scroll.itemId) ~= "string" or not ItemDefinitions.IsEnchantScroll(scroll.itemId) then
		return false, "not_scroll"
	end
	if uuidEquipped(profile, scrollUuid) then
		return false, "scroll_equipped"
	end
	if target.type ~= "Weapon" and target.type ~= "Armor" then
		return false, "bad_target"
	end

	local okScroll, scrollErr = Types.ValidateOwnedItem(scroll)
	if not okScroll then
		return false, scrollErr or "bad_scroll"
	end
	-- Rolled mob loot is valid Weapon/Armor but often has no catalog itemId;
	-- ValidateOwnedItem returns bad_itemId. Scroll rules only need type/tier/subStats.
	local okTarget, targetErr = EnchantScrollApply.ValidateEnchantTargetItem(target)
	if not okTarget then
		return false, targetErr or "bad_target_item"
	end

	local okApply, errApply = EnchantScrollApply.ApplyFromAct(profile, {
		kind = "ApplyEnchantScroll",
		scrollUuid = scrollUuid,
		targetUuid = targetUuid,
	}, Random.new())
	if not okApply then
		return false, errApply
	end
	-- The scroll stack may have been fully consumed (uuid removed from inventory); make sure
	-- no stale bagSlots reference is left pointing at it.
	if profile.inventory[scrollUuid] == nil then
		clearUuidFromBagSlots(profile, scrollUuid)
	end

	StatsService.RecomputeRuntimeHp(profile)
	ProfileService.PushProfile(player)
	Hotbar.syncFromProfile(player, profile)
	local lp = ProfileService.GetLastSnapshotPayload(player)
	do
		local post = profile.inventory[targetUuid]
		if type(post) == "table" then
			local el = math.floor(tonumber(post.enchantLevel) or 0)
			local ss = post.subStats
			local dmin = type(ss) == "table" and ss.dmgMin or nil
			local hp = type(ss) == "table" and ss.hp or nil
			print(("[EnchantTrace] SRV user=%d target=%s enchant=%d dmgMin=%s hp=%s push_seq=%s"):format(
				player.UserId,
				tostring(targetUuid),
				el,
				tostring(dmin),
				tostring(hp),
				tostring(lp and lp._seq)
			))
		end
	end
	return true, lp
end

function ProfileService.ApplyProtectionScroll(player, scrollUuid, targetUuid)
	local profile = ProfileService.Load(player)
	if type(scrollUuid) ~= "string" or scrollUuid == "" or type(targetUuid) ~= "string" or targetUuid == "" then
		return false, "bad_arg"
	end
	if scrollUuid == targetUuid then
		return false, "bad_arg"
	end
	ensureHotbar(profile)

	local scroll = profile.inventory[scrollUuid]
	local target = profile.inventory[targetUuid]
	if type(scroll) ~= "table" or type(target) ~= "table" then
		return false, "not_owned"
	end
	if type(scroll.itemId) ~= "string" or not ItemDefinitions.IsProtectionScroll(scroll.itemId) then
		return false, "not_scroll"
	end
	if uuidEquipped(profile, scrollUuid) then
		return false, "scroll_equipped"
	end
	if target.type ~= "Weapon" and target.type ~= "Armor" then
		return false, "bad_target"
	end

	local okScroll, scrollErr = Types.ValidateOwnedItem(scroll)
	if not okScroll then
		return false, scrollErr or "bad_scroll"
	end
	local okTarget, targetErr = EnchantScrollApply.ValidateEnchantTargetItem(target)
	if not okTarget then
		return false, targetErr or "bad_target_item"
	end

	local okApply, errApply = ProtectionScrollApply.ApplyFromAct(profile, {
		kind = "ApplyProtectionScroll",
		scrollUuid = scrollUuid,
		targetUuid = targetUuid,
	})
	if not okApply then
		return false, errApply
	end
	if profile.inventory[scrollUuid] == nil then
		clearUuidFromBagSlots(profile, scrollUuid)
	end

	StatsService.RecomputeRuntimeHp(profile)
	ProfileService.PushProfile(player)
	Hotbar.syncFromProfile(player, profile)
	local lp = ProfileService.GetLastSnapshotPayload(player)
	return true, lp
end

function ProfileService.ApplyCraftingOrb(player, scrollUuid, targetUuid)
	local profile = ProfileService.Load(player)
	if type(scrollUuid) ~= "string" or scrollUuid == "" or type(targetUuid) ~= "string" or targetUuid == "" then
		return false, "bad_arg"
	end
	if scrollUuid == targetUuid then
		return false, "bad_arg"
	end
	ensureHotbar(profile)

	local scroll = profile.inventory[scrollUuid]
	local target = profile.inventory[targetUuid]
	if type(scroll) ~= "table" or type(target) ~= "table" then
		return false, "not_owned"
	end
	if type(scroll.itemId) ~= "string" or not ItemDefinitions.IsCraftingOrb(scroll.itemId) then
		return false, "not_orb"
	end
	if uuidEquipped(profile, scrollUuid) then
		return false, "scroll_equipped"
	end
	if target.type ~= "Weapon" and target.type ~= "Armor" then
		return false, "bad_target"
	end

	local okScroll, scrollErr = Types.ValidateOwnedItem(scroll)
	if not okScroll then
		return false, scrollErr or "bad_scroll"
	end
	local okTarget, targetErr = EnchantScrollApply.ValidateEnchantTargetItem(target)
	if not okTarget then
		return false, targetErr or "bad_target_item"
	end

	local okApply, errApply = CraftingOrbApply.ApplyFromAct(profile, {
		kind = "ApplyCraftingOrb",
		scrollUuid = scrollUuid,
		targetUuid = targetUuid,
	}, Random.new())
	if not okApply then
		return false, errApply
	end
	if profile.inventory[scrollUuid] == nil then
		clearUuidFromBagSlots(profile, scrollUuid)
	end

	StatsService.RecomputeRuntimeHp(profile)
	ProfileService.PushProfile(player)
	Hotbar.syncFromProfile(player, profile)
	local lp = ProfileService.GetLastSnapshotPayload(player)
	return true, lp
end


function ProfileService.ConsumeItemId(player, itemId, count)
	local profile = ProfileService.Load(player)
	if not ItemDefinitions.Get(itemId) then
		return false, "unknown_item"
	end
	local remaining = math.max(0, math.floor(tonumber(count) or 0))
	if remaining <= 0 then
		return true, nil
	end

	ensureHotbar(profile)

	local function clearUuidRefs(uuid)
		for i = 1, 9 do
			if hotbarSlotUuid(profile.hotbar, i) == uuid then
				profile.hotbar[i] = nil
			profile.hotbar[tostring(i)] = nil
			end
		end
		if type(profile.equipped) == "table" then
			for slot, u in pairs(profile.equipped) do
				if u == uuid then
					profile.equipped[slot] = nil
				end
			end
		end
		clearUuidFromBagSlots(profile, uuid)
	end

	-- Track whether any item UUID was fully removed from inventory.
	-- syncFromProfile tears down and rebuilds all equipped tools; if the
	-- stack still has items remaining the tool should stay equipped so the
	-- player can consume the next one without having to re-select the slot.
	local anyItemRemoved = false

	if ItemDefinitions.IsStackable(itemId) then
		for uuid, it in pairs(profile.inventory) do
			if remaining <= 0 then
				break
			end
			if type(it) == "table" and it.itemId == itemId then
				local c = math.max(1, tonumber(it.count) or 1)
				local take = math.min(c, remaining)
				it.count = c - take
				remaining = remaining - take
				if it.count <= 0 then
					clearUuidRefs(uuid)
					profile.inventory[uuid] = nil
					anyItemRemoved = true
				end
			end
		end
	else
		for uuid, it in pairs(profile.inventory) do
			if remaining <= 0 then
				break
			end
			if type(it) == "table" and it.itemId == itemId then
				clearUuidRefs(uuid)
				profile.inventory[uuid] = nil
				remaining = remaining - 1
				anyItemRemoved = true
			end
		end
	end

	if remaining > 0 then
		return false, "insufficient"
	end

	StatsService.RecomputeRuntimeHp(profile)
	ProfileService.PushProfile(player)
	-- Only rebuild hotbar tools when an item was fully removed. If the stack
	-- still has count remaining the existing equipped tool is still valid and
	-- rebuilding it would force the player to re-select the hotbar slot.
	if anyItemRemoved then
		Hotbar.syncFromProfile(player, profile)
	end
	return true, nil
end

local function isValidEquipSlot(slot)
	return slot == "Weapon"
		or slot == "Bow"
		or slot == "Armor"
		or slot == "Helm"
		or slot == "Chest"
		or slot == "Legs"
		or slot == "Boots"
		or slot == "Shield"
		or slot == "Necklace"
		or slot == "Ring"
		or slot == "Pickaxe"
		or slot == "FishingSpear"
		or slot == "Potion"
end

--[[
  Equip flow (exploit-safe):
    - Item UUID must exist in inventory (server-owned dictionary).
    - Allowed slot derived from item type/tags/equipSlot hint (Types.GetAllowedEquipSlot).
    - If target slot occupied, previous UUID is cleared and returned to the first empty bag slot.
    - 8 slots total: Helm/Chest/Legs/Boots/Shield (armor) + Weapon/Bow/Pickaxe/FishingSpear
      (tools) -- no more freeform hotbar; a tool's only "equipped" location is this panel.
]]
function ProfileService.EquipItem(player, itemUuid, equipOpts)
	local profile = ProfileService.Load(player)
	if type(itemUuid) ~= "string" or itemUuid == "" then
		return false, "bad_uuid"
	end
	local item = profile.inventory[itemUuid]
	if not item then
		return false, "not_owned"
	end
	if item.broken then
		return false, "item_broken"
	end
	local slot = Types.GetAllowedEquipSlot(item)
	if not slot then
		return false, "not_equippable"
	end

	if type(profile.equipped) == "table" and profile.equipped[slot] == itemUuid then
		return true, nil
	end

	local prevUuid = type(profile.equipped) == "table" and profile.equipped[slot] or nil
	profile.equipped[slot] = itemUuid
	clearItemUuidFromAllHotbar(profile, itemUuid)
	clearUuidFromBagSlots(profile, itemUuid)
	if type(prevUuid) == "string" and prevUuid ~= "" and prevUuid ~= itemUuid then
		placeItemInFirstEmptyBagSlot(profile, prevUuid)
	end
	dedupeHotbarInPlace(profile)
	StatsService.RecomputeRuntimeHp(profile)
	ProfileService.PushProfile(player)
	Hotbar.syncFromProfile(player, profile)
	-- Physically wear it: rigid Motor6D-weld visual driven by the same slot key
	-- (ArmorVisualsService no-ops silently for slots/items with no prefab yet).
	ArmorVisualsService.ApplyVisual(player.Character, slot, item.itemId)
	return true, nil
end

function ProfileService.UnequipItem(player, slot)
	if not isValidEquipSlot(slot) then
		return false, "bad_slot"
	end
	local profile = ProfileService.Load(player)
	if type(profile.equipped) ~= "table" or profile.equipped[slot] == nil then
		return true, nil
	end
	local unequippedUuid = profile.equipped[slot]
	profile.equipped[slot] = nil
	-- Unequipped item leaves the equip panel entirely -- it must land in the bag, not vanish.
	placeItemInFirstEmptyBagSlot(profile, unequippedUuid)
	dedupeHotbarInPlace(profile)
	StatsService.RecomputeRuntimeHp(profile)
	ProfileService.PushProfile(player)
	Hotbar.syncFromProfile(player, profile)
	ArmorVisualsService.RemoveVisual(player.Character, slot)
	return true, nil
end

-- Shared removal step for DropItem/TrashItem: strips `itemUuid` out of every slot
-- system (bag, hotbar, equip panel) and out of profile.inventory itself, syncing
-- visuals/hotbar the same way UnequipItem does when the removed item happened to be
-- equipped. Returns the removed item table (the caller decides what happens to it --
-- become a world pickup, or just vanish) or nil+reason on failure.
local function removeOwnedItemFromProfile(player, profile, itemUuid)
	if type(itemUuid) ~= "string" or itemUuid == "" then
		return nil, "bad_uuid"
	end
	local item = profile.inventory[itemUuid]
	if not item then
		return nil, "not_owned"
	end
	local equippedSlot = nil
	if type(profile.equipped) == "table" then
		for slot, uuid in pairs(profile.equipped) do
			if uuid == itemUuid then
				equippedSlot = slot
				break
			end
		end
	end
	profile.inventory[itemUuid] = nil
	clearItemUuidFromAllHotbar(profile, itemUuid)
	clearUuidFromBagSlots(profile, itemUuid)
	clearItemUuidFromAllEquipped(profile, itemUuid)
	dedupeHotbarInPlace(profile)
	StatsService.RecomputeRuntimeHp(profile)
	ProfileService.PushProfile(player)
	Hotbar.syncFromProfile(player, profile)
	if equippedSlot then
		ArmorVisualsService.RemoveVisual(player.Character, equippedSlot)
	end
	return item, nil
end

--[[
	DropItem(player, itemUuid) -- removes the item from the profile and hands it back
	to the caller (ProfileBootstrap.server.lua's DungeonInventoryAct "DropItem" action)
	to spawn as a world pickup via WorldLootService.SpawnPlayerDrop. Denied while the
	player is in combat -- dumping gear mid-fight (e.g. to bait/deny a killer, or duck
	death-drop rules) isn't a safe-anytime action, same spirit as the trash/safe-zone
	rule below.
]]
function ProfileService.DropItem(player, itemUuid)
	local cs = getCombatState()
	if cs and cs.IsInCombat(player) then
		return false, "in_combat"
	end
	local profile = ProfileService.Load(player)
	local item, err = removeOwnedItemFromProfile(player, profile, itemUuid)
	if not item then
		return false, err
	end
	return true, nil, item
end

--[[
	TrashItem(player, itemUuid) -- permanently deletes the item (no world pickup).
	Denied while in combat (same as DropItem) AND unless the player is currently in a
	Lawful/"safe" zone (ZoneService.IsPlayerInSafeZone) -- destroying gear is
	irreversible, so it's gated tighter than a drop.
]]
function ProfileService.TrashItem(player, itemUuid)
	local cs = getCombatState()
	if cs and cs.IsInCombat(player) then
		return false, "in_combat"
	end
	local zs = getZoneService()
	if not zs or not zs.IsPlayerInSafeZone(player) then
		return false, "not_safe_zone"
	end
	local profile = ProfileService.Load(player)
	local item, err = removeOwnedItemFromProfile(player, profile, itemUuid)
	if not item then
		return false, err
	end
	return true, nil
end

function ProfileService.BuildSnapshotPayload(player)
	local profile = ProfileService.Load(player)
	ensureHotbar(profile)
	ensureBagSlots(profile)
	ensureChest(profile)
	local derived = StatsService.BuildSnapshot(profile)
	local uid = player.UserId
	local seq = (snapshotGenByUserId[uid] or 0) + 1
	snapshotGenByUserId[uid] = seq
	-- Dense string keys survive RemoteEvent serialization (sparse numeric arrays reindex).
	local hotbarWire = {}
	for i = 1, 9 do
		local u = hotbarSlotUuid(profile.hotbar, i)
		hotbarWire[tostring(i)] = (type(u) == "string" and u ~= "") and u or ""
	end
	local bagSlotsWire = {}
	for i = 1, Types.BAG_SLOT_COUNT do
		local u = bagSlotUuid(profile.bagSlots, i)
		bagSlotsWire[tostring(i)] = (type(u) == "string" and u ~= "") and u or ""
	end
	local profileWire = table.clone(profile)
	profileWire.hotbar = hotbarWire
	profileWire.bagSlots = bagSlotsWire
	-- Internal persistence plumbing -- no client-side use for it, and no reason to ship it.
	profileWire.Lock = nil
	return {
		profile = profileWire,
		derived = derived,
		_seq = seq,
	}
end

function ProfileService.PushProfile(player)
	if not player or player.Parent == nil then
		return
	end
	local payload = ProfileService.BuildSnapshotPayload(player)
	lastSnapshotPayloadByUserId[player.UserId] = payload

	-- Sync Humanoid MaxHealth to derived maxHp
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local maxHp = payload.derived.combat.maxHp
		humanoid.MaxHealth = maxHp
		if humanoid.Health > maxHp then
			humanoid.Health = maxHp
		end
	end

	-- Sync per-player energy regen rate
	EnergyData.setRegenRate(player, payload.derived.combat.energyRegen)

	-- Replicate alignment to all clients via player attribute
	player:SetAttribute("PlayerAlignment", ProfileService.GetAlignment(player))

	local ok, err = pcall(function()
		getPushEvent():FireClient(player, payload)
	end)
	if not ok then
		warn("[ProfileService] PushProfile FireClient failed:", err)
	end
	return payload
end

function ProfileService.GetLastSnapshotPayload(player)
	if not player then
		return nil
	end
	return lastSnapshotPayloadByUserId[player.UserId]
end

function ProfileService.SetInRaid(player, inRaid)
	local profile = ProfileService.Load(player)
	profile.flags.inRaid = inRaid
	ProfileService.PushProfile(player)
end

-- Alignment system: server-authoritative selection of Lawful / Neutral / Chaotic.
-- Changing alignment triggers a 5-minute cooldown during which no further change
-- is allowed. Picking the alignment you already have is idempotent (no cooldown burn).
local ALIGNMENT_COOLDOWN = 300  -- seconds
local VALID_ALIGNMENTS = { Lawful = true, Neutral = true, Chaotic = true }
-- Alignments that may engage in PvP. Lawful players are non-combatants:
-- they cannot attack other players and cannot be attacked by other players.
local PVP_ALIGNMENTS  = { Neutral = true, Chaotic = true }

-- Read-only helper: returns current alignment string for `player`, defaulting
-- to "Lawful" if the profile is missing or malformed. Safe to call during
-- the brief window after join and before Reconcile completes.
function ProfileService.GetAlignment(player)
	local profile = ProfileService.Load(player)
	if type(profile) ~= "table" or type(profile.alignment) ~= "table" then
		return "Lawful"
	end
	local cur = profile.alignment.current
	if type(cur) ~= "string" or not VALID_ALIGNMENTS[cur] then
		return "Lawful"
	end
	return cur
end

-- PvP gate. Returns true only when BOTH players are Neutral/Chaotic and
-- they aren't the same player. Lawful on either side blocks the hit.
-- This is the single source of truth — all PvP damage paths funnel through here.
function ProfileService.CanPvP(attacker, target)
	if not attacker or not target or attacker == target then
		return false
	end
	local a = ProfileService.GetAlignment(attacker)
	local t = ProfileService.GetAlignment(target)
	return PVP_ALIGNMENTS[a] == true and PVP_ALIGNMENTS[t] == true
end

function ProfileService.SetAlignment(player, newAlignment)
	if type(newAlignment) ~= "string" or not VALID_ALIGNMENTS[newAlignment] then
		return false, "invalid_alignment"
	end

	local profile = ProfileService.Load(player)
	if not profile then
		return false, "no_profile"
	end

	if type(profile.alignment) ~= "table" then
		profile.alignment = { current = "Lawful", cooldownUntil = 0 }
	end

	-- No-op if already this alignment
	if profile.alignment.current == newAlignment then
		return true, nil
	end

	if os.time() < (tonumber(profile.alignment.cooldownUntil) or 0) then
		return false, "on_cooldown"
	end

	profile.alignment.current       = newAlignment
	profile.alignment.cooldownUntil = os.time() + ALIGNMENT_COOLDOWN

	ProfileService.PushProfile(player)
	return true, nil
end

function ProfileService.AddSkillXP(player, branch, amount)
	local profile = ProfileService.Load(player)
	ensureSkillStats(profile)
	local gain = math.max(0, math.floor(tonumber(amount) or 0))
	if gain <= 0 then
		return false, "bad_amount"
	end

	local key = string.lower(tostring(branch or ""))
	if key ~= "combat" and key ~= "mining" and key ~= "fishing" then
		return false, "bad_branch"
	end

	local bucket = profile.stats[key]
	bucket.xp = bucket.xp + gain

	local required = xpRequiredForLevel(bucket.level)
	while bucket.xp >= required do
		bucket.xp = bucket.xp - required
		bucket.level = bucket.level + 1
		required = xpRequiredForLevel(bucket.level)
	end

	if key == "mining" then
		profile.stats.mining.miningLevel = bucket.level
	elseif key == "fishing" then
		profile.stats.fishing.fishingLevel = bucket.level
	end

	ProfileService.PushProfile(player)
	return true, nil
end

--[[
  Merchant salvage: destroy one non-equipped armor or weapon in camp inventory and grant tier-matched scrap items.
  Qty = 4 * rarity tier (Common 4 .. Legendary 20). Item id = T{gearTier}Scrap where gearTier is catalog Tier (1..5).
]]
function ProfileService.SalvageGearByUuid(player, itemUuid)
	local profile = ProfileService.Load(player)
	if type(itemUuid) ~= "string" or itemUuid == "" then
		return false, "bad_uuid"
	end
	if type(profile.flags) == "table" and profile.flags.inRaid then
		return false, "in_raid"
	end

	local item = profile.inventory[itemUuid]
	if type(item) ~= "table" then
		return false, "not_owned"
	end

	if uuidEquipped(profile, itemUuid) then
		return false, "equipped"
	end

	local catDef = nil
	if type(item.itemId) == "string" and item.itemId ~= "" then
		catDef = ItemDefinitions.Get(item.itemId)
		if not catDef then
			return false, "unknown_item"
		end
		if catDef.Kind ~= "Armor" and catDef.Kind ~= "Weapon" then
			return false, "not_salvageable"
		end
		if ItemDefinitions.IsStackable(item.itemId) then
			return false, "not_salvageable"
		end
	else
		if item.type ~= "Armor" and item.type ~= "Weapon" then
			return false, "not_salvageable"
		end
	end

	local rarity = item.rarity
	if (type(rarity) ~= "string" or rarity == "") and catDef then
		rarity = catDef.Rarity
	end
	if type(rarity) ~= "string" or rarity == "" then
		rarity = "Common"
	end

	local gearTier = 1
	if catDef and type(catDef.Tier) == "number" then
		gearTier = catDef.Tier
	elseif type(item.tier) == "number" then
		gearTier = item.tier
	end
	gearTier = math.clamp(math.floor(gearTier), 1, 5)
	local scrapItemId = ItemDefinitions.GetTierScrapItemId(gearTier)
	if not ItemDefinitions.Get(scrapItemId) then
		return false, "bad_scrap_item"
	end

	local tierIdx = Types.GetRarityTierIndex(rarity)
	local scrapQty = 4 * tierIdx

	ensureHotbar(profile)
	clearUuidFromHotbar(profile, itemUuid)
	clearItemUuidFromAllEquipped(profile, itemUuid)
	clearUuidFromBagSlots(profile, itemUuid)

	profile.inventory[itemUuid] = nil

	local okGrant, errGrant = mergeStackableIntoInventory(player, profile, scrapItemId, scrapQty)
	if not okGrant then
		return false, errGrant or "grant_failed"
	end

	StatsService.RecomputeRuntimeHp(profile)
	ProfileService.PushProfile(player)
	Hotbar.syncFromProfile(player, profile)

	local coinsTotal = math.floor(tonumber(profile.currencies and profile.currencies.Coins) or 0)
	return true, {
		grantedItemId = scrapItemId,
		grantedQty = scrapQty,
		wallet = coinsTotal,
	}
end


local function uuidInChest(profile, uuid)
	if type(profile.chestSlots) ~= "table" then
		return false
	end
	for i = 1, Types.CHEST_SLOT_COUNT do
		if profile.chestSlots[i] == uuid then
			return true
		end
	end
	return false
end

function ProfileService.ApplyAltarUpgrade(player, altarTier, centerUuid, sacrificeUuids)
	local profile = ProfileService.Load(player)
	ensureHotbar(profile)
	ensureBagSlots(profile)
	ensureChest(profile)

	if type(centerUuid) ~= "string" or centerUuid == "" then
		return false, "bad_center"
	end
	if type(sacrificeUuids) ~= "table" then
		return false, "bad_sacrifices"
	end

	local allUuids = { centerUuid }
	for _, su in ipairs(sacrificeUuids) do
		table.insert(allUuids, su)
	end

	for _, uuid in ipairs(allUuids) do
		if not profile.inventory[uuid] then
			return false, "not_owned"
		end
		if uuidEquipped(profile, uuid) then
			return false, "equipped"
		end
		if uuidInChest(profile, uuid) then
			return false, "in_chest"
		end
	end

	local okApply, errApply = AltarUpgrade.ApplyUpgrade(profile, altarTier, centerUuid, sacrificeUuids)
	if not okApply then
		return false, errApply
	end

	for _, su in ipairs(sacrificeUuids) do
		clearUuidFromHotbar(profile, su)
		clearItemUuidFromAllEquipped(profile, su)
		clearUuidFromBagSlots(profile, su)
	end

	StatsService.RecomputeRuntimeHp(profile)
	ProfileService.PushProfile(player)
	Hotbar.syncFromProfile(player, profile)
	return true, nil
end

ProfileService.SalvageArmorByUuid = ProfileService.SalvageGearByUuid

-- Periodic autosave (mirrors PlayerDataManager's loop): keeps the lock, just
-- refreshes the saved copy so a crash loses at most AUTOSAVE_INTERVAL seconds
-- of progress instead of the whole session.
task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		for _, plr in ipairs(Players:GetPlayers()) do
			if sessions[plr.UserId] then
				ProfileService.SaveProfile(plr)
			end
			task.wait(1)
		end
	end
end)

-- Final safety net if PlayerRemoving doesn't get to finish for everyone during
-- a server shutdown (crash, forced close). SaveProfile + Unload is the same
-- pair ProfileBootstrap's PlayerRemoving handler already calls per player.
game:BindToClose(function()
	for _, plr in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			ProfileService.SaveProfile(plr)
			ProfileService.Unload(plr)
		end)
	end
	task.wait(5)
end)

return ProfileService
