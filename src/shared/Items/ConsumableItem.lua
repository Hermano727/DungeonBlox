--!strict
--[[
	ConsumableItem : Item -- catalog consumables (Kind = "Consumable"), e.g. potions.
	Matches ProfileTypes.GetAllowedEquipSlot's existing Consumable -> "Potion"
	fallback, just stamped directly onto the owned record instead of re-derived from
	`item.type` every time something asks.
]]

local Item = require(script.Parent:WaitForChild("Item"))

local ConsumableItem = setmetatable({}, { __index = Item })
ConsumableItem.__index = ConsumableItem

function ConsumableItem.new(itemId: string, def)
	local self = Item.new(itemId, def)
	return setmetatable(self, ConsumableItem)
end

function ConsumableItem:GetEquipSlot(): string?
	return "Potion"
end

return ConsumableItem
