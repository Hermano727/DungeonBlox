--[[
	InventoryHotbarRules — single place for hotbar slot policy (client).
	Slot 1 mirrors server equipped.Weapon; only Weapon-type rows may be assigned there via drag.
]]

local InventoryHotbarRules = {}

InventoryHotbarRules.WEAPON_SLOT = 1
InventoryHotbarRules.ACTION_SLOT_MIN = 2
InventoryHotbarRules.ACTION_SLOT_MAX = 9

function InventoryHotbarRules.isWeaponMirrorSlot(slotIndex)
	return slotIndex == InventoryHotbarRules.WEAPON_SLOT
end

function InventoryHotbarRules.mayAssignToHotbarSlot(slotIndex, item)
	if type(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > 9 then
		return false
	end
	if InventoryHotbarRules.isWeaponMirrorSlot(slotIndex) then
		return type(item) == "table" and item.type == "Weapon"
	end
	return true
end

return InventoryHotbarRules
