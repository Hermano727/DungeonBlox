--[[
	DeathProtection — decides which inventory items survive a death-drop.
	Kept standalone (not inlined in DeathLootService) so the "what's protected" policy
	isn't coupled to the drop-loop/world-loot mechanics.

	There is no more hotbar -- everything a player can "equip" (armor AND tools: Weapon,
	Bow, Pickaxe, FishingSpear) lives in profile.equipped now, one slot name each.

	Protection rules, in precedence order:
	  1. Profession items (Pickaxe/FishingSpear, or ItemDefinitions.IsProtectedOnDeath) — always.
	  2. Anything currently equipped (any slot in profile.equipped) — always. This is the
	     literal "can't ever lose the weapon in your weapon slot if you die" rule, generalized
	     to every equip slot rather than special-cased per item type.
	Everything else in profile.inventory (unequipped bag items) drops.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local Types = require(ReplicatedStorage:WaitForChild("ProfileTypes"))

local DeathProtection = {}

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
DeathProtection.BuildEquippedSlotByUuid = buildEquippedSlotByUuid

-- True if `item` (at `uuid`) survives a death-drop. `equippedSlotByUuid` comes from
-- BuildEquippedSlotByUuid. Caller computes it once per death, not once per item.
function DeathProtection.ShouldKeepOnDeath(uuid, item, equippedSlotByUuid)
	if type(item) ~= "table" then
		return true
	end

	if isProfessionItem(item) then
		return true
	end

	if equippedSlotByUuid and equippedSlotByUuid[uuid] then
		return true
	end

	return false
end

return DeathProtection
