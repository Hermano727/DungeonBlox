--[[
  Server-authoritative Dungeon profile session store.
  ProfileService integration: replace sessions table + Load/Unload with
  ProfileService:LoadProfileAsync / ListenToRelease while keeping Reconcile().
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(ReplicatedStorage:WaitForChild("DungeonProfileTypes"))
local Economy = require(ServerScriptService:WaitForChild("DungeonEconomyConfig"))
local StatsService = require(ServerScriptService:WaitForChild("DungeonStatsService"))
local EnergyData = require(ServerScriptService:WaitForChild("EnergyData"))
local Hotbar = require(ServerScriptService:WaitForChild("DungeonEquippedHotbar"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local EnchantScrollApply = require(ReplicatedStorage:WaitForChild("EnchantScrollApply"))
local ProtectionScrollApply = require(ReplicatedStorage:WaitForChild("ProtectionScrollApply"))
local CraftingOrbApply = require(ReplicatedStorage:WaitForChild("CraftingOrbApply"))
local AltarUpgrade = require(ServerScriptService:WaitForChild("AltarUpgrade"))

local DungeonProfileService = {}

local sessions = {}
-- Monotonic per-player snapshot generation for network payloads (push + RF). Lets the client
-- ignore out-of-order/stale RemoteEvent pushes that would otherwise overwrite a newer cache.
local snapshotGenByUserId = {}
local lastSnapshotPayloadByUserId = {}

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
		error("[DungeonProfileService] Missing ReplicatedStorage.DungeonProfilePush RemoteEvent")
	end
	pushEvent = ev
	return pushEvent
end

function DungeonProfileService.SetPushEventForTests(ev)
	pushEvent = ev
end

function DungeonProfileService.Get(player)
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

-- One Tool instance per inventory UUID (DungeonEquippedHotbar). Never keep the same uuid in
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

function DungeonProfileService.Load(player)
	local existing = sessions[player.UserId]
	if existing then
		-- Reconcile in case new fields were added after the profile was first created
		Types.Reconcile(existing)
		ensureSkillStats(existing)
		dedupeHotbarInPlace(existing)
		dedupeBagSlotsInPlace(existing)
		return existing
	end
	local fresh = Types.DefaultProfile()
	ensureSkillStats(fresh)
	dedupeHotbarInPlace(fresh)
	dedupeBagSlotsInPlace(fresh)
	sessions[player.UserId] = fresh
	return fresh
end

function DungeonProfileService.Unload(player)
	sessions[player.UserId] = nil
	snapshotGenByUserId[player.UserId] = nil
	lastSnapshotPayloadByUserId[player.UserId] = nil
end

function DungeonProfileService.SaveProfile(_player)
	-- Intentionally empty: wire to ProfileService UpdateAsync in a later milestone.
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

local function mapKindToLegacyItemType(kind)
	if kind == "Weapon" then
		return "Weapon"
	elseif kind == "Armor" then
		return "Armor"
	elseif kind == "Consumable" then
		return "Consumable"
	elseif kind == "Food" then
		return "Food"
	end
	return "Material"
end

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
			local uuid = HttpService:GenerateGUID(false)
			local take = math.min(maxStack, remaining)
			local it = {
				uuid = uuid,
				itemId = itemId,
				count = take,
				name = def.DisplayName or itemId,
				type = mapKindToLegacyItemType(def.Kind),
				rarity = def.Rarity or "Common",
				tier = def.Tier,
				enchantLevel = 0,
				subStats = {},
				toolPrefabName = def.ToolPrefabName,
			}
			profile.inventory[uuid] = it
			placeItemInFirstEmptySlot(profile, uuid)
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

function DungeonProfileService.GrantItem(player, template, count)
	local profile = DungeonProfileService.Load(player)
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
			placeItemInFirstEmptySlot(profile, uuid)
		end
	end

	StatsService.RecomputeRuntimeHp(profile)
	DungeonProfileService.PushProfile(player)
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
placeItemInFirstEmptyBagSlot = function(profile, uuid)
	if type(uuid) ~= "string" or uuid == "" then
		return
	end
	ensureBagSlots(profile)
	for i = 1, Types.BAG_SLOT_COUNT do
		if bagSlotUuid(profile.bagSlots, i) == nil then
			profile.bagSlots[i] = uuid
			return
		end
	end
	-- Bag full: item stays owned in profile.inventory but unplaced (same as today's
	-- de-facto bag-overflow behavior; not a regression).
end

-- Hotbar-priority placement for newly-acquired items (grants, chest withdrawals): hotbar[1..9]
-- is filled first, then the bag, matching "fill the first empty slot" pickup behavior.
placeItemInFirstEmptySlot = function(profile, uuid)
	if type(uuid) ~= "string" or uuid == "" then
		return
	end
	local item = profile.inventory[uuid]
	if type(item) ~= "table" then
		return
	end
	if itemAllowsHotbar(item) then
		ensureHotbar(profile)
		for i = 1, 9 do
			if hotbarSlotUuid(profile.hotbar, i) == nil then
				profile.hotbar[i] = uuid
				return
			end
		end
	end
	placeItemInFirstEmptyBagSlot(profile, uuid)
end

-- Public wrapper for callers outside this module that mint inventory entries directly
-- (e.g. AuctionHouseService returning/claiming a listing's item) instead of through
-- GrantItem/GrantItemId. Keeps "fill the first empty hotbar/bag slot" universal.
function DungeonProfileService.PlaceItemInFirstEmptySlot(profile, uuid)
	placeItemInFirstEmptySlot(profile, uuid)
end

function DungeonProfileService.GrantItemId(player, itemId, count)
	local profile = DungeonProfileService.Load(player)
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
			local uuid = HttpService:GenerateGUID(false)
			local it = {
				uuid = uuid,
				itemId = itemId,
				count = 1,
				name = def.DisplayName or itemId,
				type = mapKindToLegacyItemType(def.Kind),
				rarity = def.Rarity or "Common",
				tier = def.Tier,
				enchantLevel = 0,
				subStats = {},
				toolPrefabName = def.ToolPrefabName,
			}
			if def.Kind == "Weapon" then
				local WeaponData = require(ReplicatedStorage:WaitForChild("WeaponData"))
				local wid = (type(def.WeaponId) == "string" and def.WeaponId ~= "") and def.WeaponId or itemId
				local st = WeaponData.GetStats(wid)
				local d = math.max(1, math.floor(tonumber(st.Damage) or 1))
				it.subStats = { dmgMin = d, dmgMax = d }
			end
			profile.inventory[uuid] = it
			placeItemInFirstEmptySlot(profile, uuid)
		end
	end

	StatsService.RecomputeRuntimeHp(profile)
	DungeonProfileService.PushProfile(player)
	maybeFireT1KeyFragment30Milestone(player, profile, prevT1Frags)
	return true, nil
end


function DungeonProfileService.ClearHotbarSlot(player, slotIndex)
	local profile = DungeonProfileService.Load(player)
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
	DungeonProfileService.PushProfile(player)
	Hotbar.syncFromProfile(player, profile)
	return true, DungeonProfileService.BuildSnapshotPayload(player)
end

function DungeonProfileService.SetHotbarSlot(player, slotIndex, itemUuid)
	local profile = DungeonProfileService.Load(player)
	slotIndex = math.floor(tonumber(slotIndex) or -1)
	if slotIndex ~= slotIndex or slotIndex < 1 or slotIndex > 9 then
		return false, "bad_slot"
	end
	ensureHotbar(profile)
	if type(itemUuid) ~= "string" or itemUuid == "" then
		return DungeonProfileService.ClearHotbarSlot(player, slotIndex)
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
	DungeonProfileService.PushProfile(player)
	Hotbar.syncFromProfile(player, profile)
	return true, DungeonProfileService.BuildSnapshotPayload(player)
end

function DungeonProfileService.SwapHotbarSlots(player, a, b)
	local profile = DungeonProfileService.Load(player)
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
		return true, DungeonProfileService.BuildSnapshotPayload(player)
	end
	ensureHotbar(profile)
	local ua = hotbarSlotUuid(profile.hotbar, a); local ub = hotbarSlotUuid(profile.hotbar, b)
	profile.hotbar[a], profile.hotbar[b] = ub, ua
	profile.hotbar[tostring(a)] = nil
	profile.hotbar[tostring(b)] = nil
	dedupeHotbarInPlace(profile)
	DungeonProfileService.PushProfile(player)
	Hotbar.syncFromProfile(player, profile)
	return true, DungeonProfileService.BuildSnapshotPayload(player)
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

function DungeonProfileService.ChestDepositToSlot(player, uuid, slotIndex)
	local profile = DungeonProfileService.Load(player)
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
		DungeonProfileService.PushProfile(player)
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
	DungeonProfileService.PushProfile(player)
	Hotbar.syncFromProfile(player, profile)
	return true, nil
end

function DungeonProfileService.ChestWithdrawSlot(player, slotIndex)
	local profile = DungeonProfileService.Load(player)
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
	placeItemInFirstEmptySlot(profile, uuid)

	StatsService.RecomputeRuntimeHp(profile)
	DungeonProfileService.PushProfile(player)
	Hotbar.syncFromProfile(player, profile)
	maybeFireT1KeyFragment30Milestone(player, profile, prevT1Frags)
	return true, nil
end

--[[
  RemoteFunction action: SetBagSlot(player, slotIndex, itemUuid) -- explicit placement into a
  bag slot (click-to-place destination). No hotbar-eligibility restriction: anything ownable
  can sit in the bag. Modeled directly on SetHotbarSlot/ClearHotbarSlot.
]]
function DungeonProfileService.SetBagSlot(player, slotIndex, itemUuid)
	local profile = DungeonProfileService.Load(player)
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
	DungeonProfileService.PushProfile(player)
	Hotbar.syncFromProfile(player, profile)
	return true, DungeonProfileService.BuildSnapshotPayload(player)
end

--[[
  RemoteFunction action: SwapBagSlot(player, a, b) -- bag-to-bag swap by index. Replaces the
  old client-only cosmetic bag reordering with a server-authoritative swap.
]]
function DungeonProfileService.SwapBagSlot(player, a, b)
	local profile = DungeonProfileService.Load(player)
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
		return true, DungeonProfileService.BuildSnapshotPayload(player)
	end
	ensureBagSlots(profile)
	local ua = bagSlotUuid(profile.bagSlots, a); local ub = bagSlotUuid(profile.bagSlots, b)
	profile.bagSlots[a], profile.bagSlots[b] = ub, ua
	profile.bagSlots[tostring(a)] = nil
	profile.bagSlots[tostring(b)] = nil
	dedupeBagSlotsInPlace(profile)
	DungeonProfileService.PushProfile(player)
	return true, DungeonProfileService.BuildSnapshotPayload(player)
end

function DungeonProfileService.UnlockChestRow(player, rowToUnlock)
	local profile = DungeonProfileService.Load(player)
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
	DungeonProfileService.PushProfile(player)
	return true, nil
end

function DungeonProfileService.ApplyEnchantScroll(player, scrollUuid, targetUuid)
	local profile = DungeonProfileService.Load(player)
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
	DungeonProfileService.PushProfile(player)
	Hotbar.syncFromProfile(player, profile)
	local lp = DungeonProfileService.GetLastSnapshotPayload(player)
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

function DungeonProfileService.ApplyProtectionScroll(player, scrollUuid, targetUuid)
	local profile = DungeonProfileService.Load(player)
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
	DungeonProfileService.PushProfile(player)
	Hotbar.syncFromProfile(player, profile)
	local lp = DungeonProfileService.GetLastSnapshotPayload(player)
	return true, lp
end

function DungeonProfileService.ApplyCraftingOrb(player, scrollUuid, targetUuid)
	local profile = DungeonProfileService.Load(player)
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
	DungeonProfileService.PushProfile(player)
	Hotbar.syncFromProfile(player, profile)
	local lp = DungeonProfileService.GetLastSnapshotPayload(player)
	return true, lp
end


function DungeonProfileService.ConsumeItemId(player, itemId, count)
	local profile = DungeonProfileService.Load(player)
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
	DungeonProfileService.PushProfile(player)
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
    - Allowed slot derived from item type/tags/equipSlot hint.
    - If target slot occupied, previous UUID is cleared (item remains in inventory).
    - Weapons are never equip-panel items (Minecraft-style hotbar model): a weapon's only
      "equipped" location is whichever hotbar slot it's placed in via SetHotbar/SwapHotbar.
]]
function DungeonProfileService.EquipItem(player, itemUuid, equipOpts)
	local profile = DungeonProfileService.Load(player)
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
	if slot == "Weapon" then
		return false, "weapon_not_equippable_panel"
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
	DungeonProfileService.PushProfile(player)
	Hotbar.syncFromProfile(player, profile)
	return true, nil
end

function DungeonProfileService.UnequipItem(player, slot)
	if not isValidEquipSlot(slot) then
		return false, "bad_slot"
	end
	local profile = DungeonProfileService.Load(player)
	if type(profile.equipped) ~= "table" or profile.equipped[slot] == nil then
		return true, nil
	end
	local unequippedUuid = profile.equipped[slot]
	profile.equipped[slot] = nil
	-- Unequipped item leaves the equip panel entirely -- it must land in the bag, not vanish.
	placeItemInFirstEmptyBagSlot(profile, unequippedUuid)
	dedupeHotbarInPlace(profile)
	StatsService.RecomputeRuntimeHp(profile)
	DungeonProfileService.PushProfile(player)
	Hotbar.syncFromProfile(player, profile)
	return true, nil
end

function DungeonProfileService.BuildSnapshotPayload(player)
	local profile = DungeonProfileService.Load(player)
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
	return {
		profile = profileWire,
		derived = derived,
		_seq = seq,
	}
end

function DungeonProfileService.PushProfile(player)
	if not player or player.Parent == nil then
		return
	end
	local payload = DungeonProfileService.BuildSnapshotPayload(player)
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
	player:SetAttribute("PlayerAlignment", DungeonProfileService.GetAlignment(player))

	local ok, err = pcall(function()
		getPushEvent():FireClient(player, payload)
	end)
	if not ok then
		warn("[DungeonProfileService] PushProfile FireClient failed:", err)
	end
	return payload
end

function DungeonProfileService.GetLastSnapshotPayload(player)
	if not player then
		return nil
	end
	return lastSnapshotPayloadByUserId[player.UserId]
end

function DungeonProfileService.SetInRaid(player, inRaid)
	local profile = DungeonProfileService.Load(player)
	profile.flags.inRaid = inRaid
	DungeonProfileService.PushProfile(player)
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
function DungeonProfileService.GetAlignment(player)
	local profile = DungeonProfileService.Load(player)
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
function DungeonProfileService.CanPvP(attacker, target)
	if not attacker or not target or attacker == target then
		return false
	end
	local a = DungeonProfileService.GetAlignment(attacker)
	local t = DungeonProfileService.GetAlignment(target)
	return PVP_ALIGNMENTS[a] == true and PVP_ALIGNMENTS[t] == true
end

function DungeonProfileService.SetAlignment(player, newAlignment)
	if type(newAlignment) ~= "string" or not VALID_ALIGNMENTS[newAlignment] then
		return false, "invalid_alignment"
	end

	local profile = DungeonProfileService.Load(player)
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

	DungeonProfileService.PushProfile(player)
	return true, nil
end

function DungeonProfileService.AddSkillXP(player, branch, amount)
	local profile = DungeonProfileService.Load(player)
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

	DungeonProfileService.PushProfile(player)
	return true, nil
end

--[[
  Merchant salvage: destroy one non-equipped armor or weapon in camp inventory and grant tier-matched scrap items.
  Qty = 4 * rarity tier (Common 4 .. Legendary 20). Item id = T{gearTier}Scrap where gearTier is catalog Tier (1..5).
]]
function DungeonProfileService.SalvageGearByUuid(player, itemUuid)
	local profile = DungeonProfileService.Load(player)
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
	DungeonProfileService.PushProfile(player)
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

function DungeonProfileService.ApplyAltarUpgrade(player, altarTier, centerUuid, sacrificeUuids)
	local profile = DungeonProfileService.Load(player)
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
	DungeonProfileService.PushProfile(player)
	Hotbar.syncFromProfile(player, profile)
	return true, nil
end

DungeonProfileService.SalvageArmorByUuid = DungeonProfileService.SalvageGearByUuid

return DungeonProfileService
