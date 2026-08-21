--!strict
--[[
	ItemFactory -- the single place that turns a catalog itemId into an owned item record.

	Replaces the inline table-literal construction that used to be duplicated (and, in the
	weapon/material case, subtly wrong) in DungeonProfileService.GrantItemId and its
	stack-merge sibling mergeStackableIntoInventory. Both now call
	ItemFactory.CreateOwnedItem(itemId, opts) instead of hand-building the record.

	Dispatches by the catalog def's `Kind` field to the matching Item subclass; Weapon/
	Armor/Material/Consumable get their own class, anything else (Food, Key, currency-ish
	stackables, ...) falls back to the plain base Item, which is correct for them today
	(not equippable, no extra fields) and gives them an obvious upgrade path if that ever
	changes -- add a Kind branch and a new subclass, same pattern as the four here.

	NOTE on the OTHER item-creation path, procedural drops: ItemGenerator.lua (mob loot)
	still goes through the older src/server/ItemClass.lua, which is server-only and rolls
	very different (randomized, tier/rarity-scaled) stat math that has nothing to do with
	catalog defs. It was NOT folded into this hierarchy -- the risk/benefit of touching its
	tuned drop-rate math wasn't worth it for what is fundamentally a slot-resolution bug.
	It got the same one-line equip-slot fix (now reads the shared
	ItemConfig.WEAPON_TYPE_EQUIP_SLOT table instead of hardcoding "Weapon"), so both paths
	agree on slots via the same source of truth even though they don't share a class tree.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local Item = require(script.Parent:WaitForChild("Item"))
local WeaponItem = require(script.Parent:WaitForChild("WeaponItem"))
local ArmorItem = require(script.Parent:WaitForChild("ArmorItem"))
local MaterialItem = require(script.Parent:WaitForChild("MaterialItem"))
local ConsumableItem = require(script.Parent:WaitForChild("ConsumableItem"))

local CLASS_BY_KIND = {
	Weapon = WeaponItem,
	Armor = ArmorItem,
	Material = MaterialItem,
	Consumable = ConsumableItem,
}

local ItemFactory = {}

-- Builds (and caches) the class instance for a catalog itemId. Cheap to call repeatedly --
-- catalog defs are static for the lifetime of the server, so each itemId's instance is
-- only actually constructed once.
local instanceCache: { [string]: any } = {}

function ItemFactory.GetDefinitionInstance(itemId: string)
	local cached = instanceCache[itemId]
	if cached then
		return cached
	end
	local def = ItemDefinitions.Get(itemId)
	if not def then
		return nil
	end
	local class = CLASS_BY_KIND[def.Kind] or Item
	local instance = class.new(itemId, def)
	instanceCache[itemId] = instance
	return instance
end

-- Builds one owned item record ready to drop straight into profile.inventory[uuid].
-- opts: { count, rarity, tier, enchantLevel, subStats } -- all optional overrides.
function ItemFactory.CreateOwnedItem(itemId: string, opts: { [string]: any }?)
	local instance = ItemFactory.GetDefinitionInstance(itemId)
	if not instance then
		return nil
	end
	return instance:CreateOwnedRecord(opts)
end

return ItemFactory
