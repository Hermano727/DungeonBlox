--!strict
--[[
	Item -- base class for the DEFINITION side of the item system (one instance per
	catalog entry in ItemDefinitions, built once at server start by ItemFactory).

	IMPORTANT boundary: this class and its subclasses (WeaponItem/ArmorItem/MaterialItem/
	ConsumableItem) exist only on the authoring side (server + shared "what IS this item,
	and how do I make one" logic). An *owned* item -- what actually lives in
	profile.inventory[uuid], crosses DungeonMenuNet's RemoteEvent to the client, and gets
	written to a DataStore -- is always the PLAIN TABLE that :CreateOwnedRecord() returns,
	never a class instance. Roblox can't replicate or persist a table with a metatable and
	methods on it, so that boundary is load-bearing, not stylistic -- never hand a class
	instance to PushProfile/GrantItem/a RemoteEvent.

	Subclasses override GetEquipSlot()/GetTags()/GetExtraFields() to add their own
	behavior; they should not need to override CreateOwnedRecord() itself. This is the ONE
	place an owned item record gets built from a catalog definition, replacing the
	duplicated inline table literals that used to live in GrantItemId and
	mergeStackableIntoInventory (and, separately, the old src/server/ItemClass.lua used by
	ItemGenerator for procedural drops -- see that file's own comment for how it fits in).

	Historically only armor stamped a specific `equipSlot` onto the owned record; weapons
	and materials fell back to generic type-based guessing in
	ProfileTypes.GetAllowedEquipSlot, which silently collapsed every weapon (Sword
	AND Bow) onto one "Weapon" slot and, worse, every catalog-granted item (GrantItemId
	never copied `Slot`/tags at all) onto one generic "Armor" bucket. That bucket isn't
	even a slot PlayerPreview's UI reads -- see ProfileTypes.lua's Reconcile()
	migration for how already-corrupted saves get fixed up. Routing every grant through
	this class hierarchy means the slot is always correct at creation time, in one place,
	instead of re-derived (and re-drifting) in N places.
]]

local HttpService = game:GetService("HttpService")
local ItemIdentity = require(game:GetService("ReplicatedStorage"):WaitForChild("ItemIdentity"))

local Item = {}
Item.__index = Item

export type ItemDef = {
	Kind: string?,
	DisplayName: string?,
	Rarity: string?,
	Tier: number?,
	Stackable: boolean?,
	MaxStack: number?,
	Untradeable: boolean?,
	ProtectedOnDeath: boolean?,
	HotbarEquippable: boolean?,
	ToolPrefabName: string?,
	[string]: any,
}

-- Legacy owned-item `type` values: only these four Kinds ever get their own literal
-- `type` string on the owned record; everything else (Ammo/Fish/Alteration/Reforging/
-- Chaos/Divinity/Nullification/Transmutation/Wisdom/plain Material/...) collapses to
-- "Material", matching what ProfileService's old inline table construction did via
-- its own mapKindToLegacyItemType helper (now removed -- this replaces it). Getting this
-- wrong would be a real regression: several crafting/enchant systems (CraftingOrbApply,
-- EnchantScrollApply, ProtectionScrollApply) key off `item.type == "Material"` for scroll/
-- orb items whose catalog Kind is one of those more specific strings, not "Material"
-- itself.
local KIND_TO_LEGACY_TYPE = {
	Weapon = "Weapon",
	Armor = "Armor",
	Consumable = "Consumable",
	Food = "Food",
}

function Item.new(itemId: string, def: ItemDef)
	local self = setmetatable({}, Item)
	self.itemId = itemId
	self.kind = def.Kind or "Material" -- raw catalog Kind, used for class dispatch/GetEquipSlot
	self.legacyType = KIND_TO_LEGACY_TYPE[self.kind] or "Material" -- what `type` becomes on the owned record
	self.displayName = def.DisplayName or itemId
	self.rarity = def.Rarity or "Common"
	self.tier = def.Tier
	self.stackable = def.Stackable == true
	self.maxStack = def.MaxStack or 1
	self.protectedOnDeath = def.ProtectedOnDeath == true
	self.hotbarEquippable = def.HotbarEquippable == true
	self.toolPrefabName = def.ToolPrefabName
	self.def = def -- full raw catalog def, for subclasses / rare full-field access
	return self
end

-- Overridden by subclasses that are equippable. Base Item (and, by extension, any Kind
-- with no dedicated subclass) is not equippable.
function Item:GetEquipSlot(): string?
	return nil
end

-- Overridden by subclasses that want to stamp `tags` on the owned record. Left empty by
-- default -- see WeaponItem's comment for why catalog-granted weapons intentionally don't
-- populate this (EquippedHotbar reads weapon tags to apply WeaponSwingMult; adding
-- tags here would be a live gameplay-balance change, not a bugfix, so it's opt-in).
function Item:GetTags(): { string }?
	return nil
end

-- Overridden by subclasses that roll their own subStats onto the record (e.g. WeaponItem
-- computing dmgMin/dmgMax from WeaponData). Returning nil leaves subStats as whatever
-- `opts.subStats` provided (or {} if that was omitted too).
function Item:GetExtraSubStats(_opts: { [string]: any }): { [string]: any }?
	return nil
end

-- The one place an owned item record gets built. `opts` is optional:
--   count, rarity, tier, enchantLevel, subStats -- override the corresponding default.
--   origin -- ItemIdentity origin context; see ItemIdentity.NewOrigin.
function Item:CreateOwnedRecord(opts: { [string]: any }?)
	opts = opts or {}
	local record: { [string]: any } = {
		uuid = HttpService:GenerateGUID(false),
		itemId = self.itemId,
		count = opts.count or 1,
		name = self.displayName,
		type = self.legacyType,
		rarity = opts.rarity or self.rarity,
		tier = opts.tier or self.tier,
		enchantLevel = opts.enchantLevel or 0,
		subStats = opts.subStats or {},
		toolPrefabName = self.toolPrefabName,
	}

	local slot = self:GetEquipSlot()
	if slot then
		record.equipSlot = slot
	end
	local tags = self:GetTags()
	if tags then
		record.tags = tags
	end

	local extraSubStats = self:GetExtraSubStats(opts)
	if extraSubStats then
		record.subStats = extraSubStats
	end

	-- Durable identity. Stackables are skipped on purpose: a per-unit serial is
	-- meaningless for something that merges into an existing pile by count, and
	-- skipping them is what keeps ProfileTypes.AuditItemIdentity honest (every
	-- stack merge would otherwise look like a dropped serial).
	if not self.stackable then
		ItemIdentity.Stamp(record, opts.origin)
	end

	return record
end

return Item
