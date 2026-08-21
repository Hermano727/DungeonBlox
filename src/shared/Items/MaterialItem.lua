--!strict
--[[
	MaterialItem : Item -- catalog materials (Kind = "Material"): profession tools
	(TrainingPickaxe/TrainingSpear today), crafting/salvage stacks, key fragments, scrap,
	and anything else that doesn't fit Weapon/Armor/Consumable.

	Most materials aren't equippable at all (ore, scrap, scrolls) -- GetEquipSlot() returns
	nil for those, same as the base Item. A material only has a slot when the catalog entry
	says so via `Slot` (the same field ArmorItem reads), which today means the two
	profession tools: TrainingPickaxe -> "Pickaxe", TrainingSpear -> "FishingSpear". Before
	this class existed, DungeonProfileTypes.GetAllowedEquipSlot had no branch at all for
	Kind == "Material", so these silently resolved to *not equippable* every time they were
	granted through GrantItemId (i.e. every respawn) -- same missing-equipSlot root cause
	as the armor bug, just for tools instead of armor.

	This is also deliberately its own class (rather than folding tool-slot handling into
	Item directly) so future profession items -- smithing hammers, cooking pots, whatever
	comes next -- have an obvious, single place to add their own fields/behavior without
	touching Weapon/Armor at all.
]]

local Item = require(script.Parent:WaitForChild("Item"))

local MaterialItem = setmetatable({}, { __index = Item })
MaterialItem.__index = MaterialItem

function MaterialItem.new(itemId: string, def)
	local self = Item.new(itemId, def)
	self.toolSlot = def.Slot -- "Pickaxe" | "FishingSpear" | nil (nil = not equippable)
	return setmetatable(self, MaterialItem)
end

function MaterialItem:GetEquipSlot(): string?
	return self.toolSlot
end

return MaterialItem
