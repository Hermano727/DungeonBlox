--[[
	InventoryHotbarRules — single place for hotbar slot policy (client).
	Minecraft-style model: all 9 slots behave identically, any hotbar-eligible item may go
	in any slot. There is no reserved weapon-mirror slot.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local InventoryHotbarRules = {}

InventoryHotbarRules.ACTION_SLOT_MIN = 1
InventoryHotbarRules.ACTION_SLOT_MAX = 9

local function legacyItemAllowsHotbar(item)
	if type(item) ~= "table" then
		return false
	end
	if item.type == "Weapon" or item.type == "Consumable" or item.type == "Food" then
		return true
	end
	if item.type == "Material" then
		if item.equipSlot == "Pickaxe" or item.equipSlot == "FishingSpear" then
			return true
		end
		if type(item.toolPrefabName) == "string" and item.toolPrefabName ~= "" then
			return true
		end
	end
	return false
end

function InventoryHotbarRules.mayAssignToHotbarSlot(slotIndex, item)
	if type(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > 9 then
		return false
	end
	if type(item) ~= "table" then
		return false
	end
	if type(item.itemId) == "string" and item.itemId ~= "" then
		return ItemDefinitions.IsHotbarEquippable(item.itemId)
	end
	return legacyItemAllowsHotbar(item)
end

return InventoryHotbarRules
