--!strict
--[[
	ArmorItem : Item -- catalog armor (Kind = "Armor"). Its equip slot is already
	1:1 with the catalog's own `Slot` field (Helm/Chest/Legs/Boots/Shield) -- this class
	just makes sure that field actually gets copied onto the owned record, which
	GrantItemId never used to do. Without it, EVERY armor piece collapsed onto one shared
	generic "Armor" slot that isn't even one of PlayerPreview's real equip-panel boxes, so
	e.g. equipping a Shield and then Boots would silently bounce each other back to the bag
	-- both were fighting over that one fake slot.
]]

local Item = require(script.Parent:WaitForChild("Item"))

local ArmorItem = setmetatable({}, { __index = Item })
ArmorItem.__index = ArmorItem

function ArmorItem.new(itemId: string, def)
	local self = Item.new(itemId, def)
	self.armorSlot = def.Slot -- "Helm" | "Chest" | "Legs" | "Boots" | "Shield"
	return setmetatable(self, ArmorItem)
end

function ArmorItem:GetEquipSlot(): string?
	return self.armorSlot
end

return ArmorItem
