--[[
	DungeonDeathProtection — decides which inventory items survive a death-drop.
	Kept standalone (not inlined in DungeonDeathLoot) so the "what's protected" policy
	isn't coupled to the drop-loop/world-loot mechanics.

	Protection rules, in precedence order. ALL of these are location-independent (hotbar OR
	bag) -- profession items always were; weapon/bow used to be hotbar-only but that meant
	moving your bow into the bag for a moment made it drop on death, which is surprising and
	not what rule 1/2 do, so weapon/bow protection now matches them:
	  1. Profession items (Pickaxe/FishingSpear, or ItemDefinitions.IsProtectedOnDeath) — always.
	  2. Equipped armor — always.
	  3. The "main weapon": first melee weapon found scanning hotbar[1..9] then bagSlots[1..27].
	  4. The single highest-damage Bow found anywhere in hotbar or bag (others drop). Can
	     overlap with rule 3 — an item kept for either reason is just kept.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local Types = require(ReplicatedStorage:WaitForChild("DungeonProfileTypes"))

local DungeonDeathProtection = {}

local function isProfessionItem(item)
	if type(item) ~= "table" then
		return false
	end
	if type(item.itemId) == "string" and item.itemId ~= "" then
		return ItemDefinitions.IsProtectedOnDeath(item.itemId)
	end
	local slot = item.equipSlot
	return slot == "Pickaxe" or slot == "FishingSpear"
end

local function isWeaponItem(item)
	return type(item) == "table" and item.type == "Weapon"
end

local function isBowItem(item)
	if not isWeaponItem(item) then
		return false
	end
	if type(item.itemId) == "string" and item.itemId ~= "" then
		return not ItemDefinitions.IsMeleeWeapon(item.itemId)
	end
	if type(item.tags) == "table" then
		for _, tag in ipairs(item.tags) do
			if tag == "Bow" then
				return true
			end
		end
	end
	local n = string.lower(tostring(item.name or ""))
	local wt = string.lower(tostring(item.weaponType or ""))
	return string.find(n, "bow", 1, true) ~= nil or string.find(wt, "bow", 1, true) ~= nil
end

local function bowDamage(item)
	local subs = type(item) == "table" and type(item.subStats) == "table" and item.subStats or {}
	local dmax = tonumber(subs.dmgMax)
	if dmax then
		return dmax
	end
	return tonumber(subs.dmgMin) or 0
end

local function isPickaxeItem(item)
	if type(item) ~= "table" then
		return false
	end
	if item.equipSlot == "Pickaxe" then
		return true
	end
	local tp = item.toolPrefabName
	if type(tp) == "string" and string.find(string.lower(tp), "pickaxe", 1, true) then
		return true
	end
	local id = item.itemId
	if type(id) == "string" and string.find(string.lower(id), "pickaxe", 1, true) then
		return true
	end
	return false
end

local function isFishingSpearItem(item)
	if type(item) ~= "table" then
		return false
	end
	if item.equipSlot == "FishingSpear" then
		return true
	end
	local tp = item.toolPrefabName
	if type(tp) == "string" and string.find(string.lower(tp), "spear", 1, true) then
		return true
	end
	local id = item.itemId
	if type(id) == "string" and string.find(string.lower(id), "spear", 1, true) then
		return true
	end
	return false
end

local function buildEquippedSlotByUuid(profile)
	local equippedSet = {}
	if type(profile.equipped) == "table" then
		for slot, u in pairs(profile.equipped) do
			if type(u) == "string" and u ~= "" then
				equippedSet[u] = slot
			end
		end
	end
	return equippedSet
end
DungeonDeathProtection.BuildEquippedSlotByUuid = buildEquippedSlotByUuid

-- Scans hotbar[1..9] then bagSlots[1..27] and returns the uuid of the first melee weapon
-- found — the player's "main weapon" for death-protection purposes. Location-independent:
-- a weapon parked in the bag is just as protected as one in the hotbar.
function DungeonDeathProtection.GetProtectedWeaponUuid(profile)
	if type(profile.inventory) ~= "table" then
		return nil
	end
	if type(profile.hotbar) == "table" then
		for i = 1, 9 do
			local u = profile.hotbar[i]
			if type(u) == "string" and u ~= "" and isWeaponItem(profile.inventory[u]) then
				return u
			end
		end
	end
	if type(profile.bagSlots) == "table" then
		for i = 1, Types.BAG_SLOT_COUNT do
			local u = profile.bagSlots[i]
			if type(u) == "string" and u ~= "" and isWeaponItem(profile.inventory[u]) then
				return u
			end
		end
	end
	return nil
end

-- Among every Bow anywhere in hotbar or bag, returns the uuid of the single highest-damage
-- one. Location-independent for the same reason as GetProtectedWeaponUuid above.
function DungeonDeathProtection.GetProtectedBowUuid(profile)
	if type(profile.inventory) ~= "table" then
		return nil
	end
	local bestUuid, bestDamage = nil, -1
	local function scan(container, count)
		if type(container) ~= "table" then
			return
		end
		for i = 1, count do
			local u = container[i]
			if type(u) == "string" and u ~= "" then
				local it = profile.inventory[u]
				if isBowItem(it) then
					local d = bowDamage(it)
					if d > bestDamage then
						bestDamage = d
						bestUuid = u
					end
				end
			end
		end
	end
	scan(profile.hotbar, 9)
	scan(profile.bagSlots, Types.BAG_SLOT_COUNT)
	return bestUuid
end

-- Shared priority ordering for hotbar placement: melee weapon, bow, pickaxe, fishing spear,
-- then anything else. Used by BOTH the starter-seed placement (DungeonBootstrap) and the
-- post-death reorder below -- one rule, not two copies that can drift apart.
function DungeonDeathProtection.OrderByPriority(profile, uuids)
	local melee, bow, pickaxe, spear, other = {}, {}, {}, {}, {}
	for _, uuid in ipairs(uuids) do
		local item = profile.inventory[uuid]
		if isBowItem(item) then
			table.insert(bow, uuid)
		elseif isWeaponItem(item) then
			table.insert(melee, uuid)
		elseif isPickaxeItem(item) then
			table.insert(pickaxe, uuid)
		elseif isFishingSpearItem(item) then
			table.insert(spear, uuid)
		else
			table.insert(other, uuid)
		end
	end
	local ordered = {}
	for _, bucket in ipairs({ melee, bow, pickaxe, spear, other }) do
		for _, uuid in ipairs(bucket) do
			table.insert(ordered, uuid)
		end
	end
	return ordered
end

local function isHotbarPriorityItem(item)
	return isWeaponItem(item) or isPickaxeItem(item) or isFishingSpearItem(item)
end

-- Compacts and reorders every weapon/pickaxe/fishing-spear the player owns -- wherever it
-- currently sits, hotbar or bag -- into hotbar slots 1-9, priority-ordered (melee weapon,
-- bow, pickaxe, fishing spear). Hotbar slots holding anything else (a potion, say) are left
-- exactly where they are; only "candidate" slots get cleared and reflowed around them.
-- Shared by the starter-seed placement (DungeonBootstrap) and the post-death reorder below --
-- "make the hotbar look right" is one operation, not two copies that can drift apart.
function DungeonDeathProtection.CompactAndOrderHotbar(profile)
	if type(profile.hotbar) ~= "table" or type(profile.inventory) ~= "table" then
		return
	end
	local seen = {}
	local candidates = {}
	local function collect(uuid)
		if type(uuid) == "string" and uuid ~= "" and profile.inventory[uuid] and not seen[uuid] then
			seen[uuid] = true
			table.insert(candidates, uuid)
		end
	end

	local protectedSlot = {}
	for i = 1, 9 do
		local uuid = profile.hotbar[i]
		if type(uuid) == "string" and uuid ~= "" then
			if isHotbarPriorityItem(profile.inventory[uuid]) then
				collect(uuid)
				profile.hotbar[i] = nil
			else
				protectedSlot[i] = true
			end
		end
	end
	if type(profile.bagSlots) == "table" then
		for i = 1, Types.BAG_SLOT_COUNT do
			local uuid = profile.bagSlots[i]
			if type(uuid) == "string" and uuid ~= "" and isHotbarPriorityItem(profile.inventory[uuid]) then
				collect(uuid)
			end
		end
	end

	local ordered = DungeonDeathProtection.OrderByPriority(profile, candidates)
	local slot = 1
	for _, uuid in ipairs(ordered) do
		while slot <= 9 and (protectedSlot[slot] or profile.hotbar[slot] ~= nil) do
			slot += 1
		end
		if slot > 9 then
			break
		end
		profile.hotbar[slot] = uuid
		-- Pulled from the bag into the hotbar -- clear the stale bagSlots reference so the
		-- item doesn't render in both places at once.
		if type(profile.bagSlots) == "table" then
			for j = 1, Types.BAG_SLOT_COUNT do
				if profile.bagSlots[j] == uuid then
					profile.bagSlots[j] = nil
				end
			end
		end
		slot += 1
	end
end

-- After a death-drop, front-load survivors into the hotbar. Profession items/weapon/bow can
-- have survived in either the hotbar or the bag (the rules above are location-independent),
-- and they should all end up front-loaded into the hotbar, not just whatever was already there.
function DungeonDeathProtection.ReorderHotbarAfterDeath(profile)
	DungeonDeathProtection.CompactAndOrderHotbar(profile)
end

-- True if `item` (at `uuid`) survives a death-drop. `equippedSlotByUuid` comes from
-- BuildEquippedSlotByUuid; `protectedWeaponUuid`/`protectedBowUuid` come from the two
-- functions above. Callers compute those once per death, not once per item.
function DungeonDeathProtection.ShouldKeepOnDeath(uuid, item, equippedSlotByUuid, protectedWeaponUuid, protectedBowUuid)
	if type(item) ~= "table" then
		return true
	end

	if isProfessionItem(item) then
		return true
	end

	local eqSlot = equippedSlotByUuid and equippedSlotByUuid[uuid]
	if eqSlot and item.type == "Armor" then
		return true
	end

	if protectedWeaponUuid and uuid == protectedWeaponUuid then
		return true
	end

	if protectedBowUuid and uuid == protectedBowUuid then
		return true
	end

	return false
end

return DungeonDeathProtection
