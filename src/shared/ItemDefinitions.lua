-- ItemDefinitions
-- Catalog of every item that can exist in a player inventory.
-- Weapons reference entries in ReplicatedStorage.WeaponData for their
-- combat-relevant stats (Damage, MaxRange, AttackType). This module owns
-- everything else: stacking rules, slot kind, armor rating, consumable
-- effects, tier gating.
--
-- Fields:
--   Stackable : items with Stackable=false take exactly one slot, with a UID.
--   MaxStack  : default 50 for stackables, 1 for non-stackables.
--   Kind      : "Weapon" | "Armor" | "Consumable" | "Ammo" | "Material"
--   Tier      : 1..5.
--   Slot      : armor only. "Helm" | "Chest" | "Legs" | "Boots".
--   WeaponId  : weapons only. Key into WeaponData.Weapons.
--   Armor     : armor pieces only. Flat armor rating added when equipped.
--   ProtectedOnDeath : explicit boolean. true means never dropped on player death.
--   HotbarEquippable : optional boolean. If set, gates assigning this catalog item to the 9-slot dungeon hotbar.
--       Raw materials / collectibles should be false; weapons, tools, ammo, potions typically true.
--   DisplayName : optional string for UI when different from itemId.
--   Description : optional string for tooltips (scrolls, etc.).
--   ToolPrefabName : optional. Tool template name under ServerStorage.DungeonToolPrefabsArchive (dungeon hotbar sync).
--   MountSpeed     : optional. Saddle tools: cloned Horse model Humanoid.WalkSpeed (tier scaling).

local Items = {

	-- Stackable consumables and materials.
	HealPotion  = { Stackable = true,  MaxStack = 50, Kind = "Consumable", Tier = 1, Rarity = "Common", HealAmount = 40, HotbarEquippable = true, ProtectedOnDeath = false },
	MajorPotion = { Stackable = true,  MaxStack = 50, Kind = "Consumable", Tier = 3, Rarity = "Rare", HealAmount = 120, HotbarEquippable = true, ProtectedOnDeath = false },
	EtherFlask  = { Stackable = true,  MaxStack = 50, Kind = "Consumable", Tier = 4, Rarity = "Epic", EnergyAmount = 60, HotbarEquippable = true, ProtectedOnDeath = false },
	Arrow       = { Stackable = true,  MaxStack = 50, Kind = "Ammo",       Tier = 1, Rarity = "Common", HotbarEquippable = true, ProtectedOnDeath = false },
	Coal        = { Stackable = true,  MaxStack = 50, Kind = "Material",   Tier = 1, Rarity = "Common", DisplayName = "Coal", HotbarEquippable = false, ProtectedOnDeath = false },
	T1Scrap     = { Stackable = true,  MaxStack = 50, Kind = "Material",   Tier = 1, Rarity = "Common", DisplayName = "T1 Scrap", HotbarEquippable = false, ProtectedOnDeath = false },
	T1Scroll    = { Stackable = true, MaxStack = 50, Kind = "Material", Tier = 1, Rarity = "Uncommon",  DisplayName = "T1 Scroll",     HotbarEquippable = false, ProtectedOnDeath = false, EnchantScroll = true, Icon = "rbxassetid://115282044684914", Description = "Add to armor to increase that piece's current HP by 5%, or to a weapon to increase its current min and max damage by 5%. Each successful enchant compounds on the new value." },

	-- Mount saddles (Animal Trainer): hotbar tools that spawn the Horse model; Humanoid.WalkSpeed scales by tier.
	T1MountSaddle = { Stackable = false, MaxStack = 1, Kind = "Material", Tier = 1, Rarity = "Common", DisplayName = "T1 Mount Saddle", HotbarEquippable = true, ProtectedOnDeath = false, ToolPrefabName = "DungeonMountSaddleTool", MountSpeed = 20 },
	T2MountSaddle = { Stackable = false, MaxStack = 1, Kind = "Material", Tier = 2, Rarity = "Uncommon", DisplayName = "T2 Mount Saddle", HotbarEquippable = true, ProtectedOnDeath = false, ToolPrefabName = "DungeonMountSaddleTool", MountSpeed = 30 },
	T3MountSaddle = { Stackable = false, MaxStack = 1, Kind = "Material", Tier = 3, Rarity = "Rare", DisplayName = "T3 Mount Saddle", HotbarEquippable = true, ProtectedOnDeath = false, ToolPrefabName = "DungeonMountSaddleTool", MountSpeed = 40 },
	T4MountSaddle = { Stackable = false, MaxStack = 1, Kind = "Material", Tier = 4, Rarity = "Epic", DisplayName = "T4 Mount Saddle", HotbarEquippable = true, ProtectedOnDeath = false, ToolPrefabName = "DungeonMountSaddleTool", MountSpeed = 50 },

	-- Key fragments + forged keys (Dungeoneer: 40 fragments -> 1 key per tier)
	T1KeyFragment = { Stackable = true, MaxStack = 99, Kind = "Material", Tier = 1, Rarity = "Uncommon", DisplayName = "T1 Key Fragment", HotbarEquippable = false, ProtectedOnDeath = false },
	T2KeyFragment = { Stackable = true, MaxStack = 99, Kind = "Material", Tier = 2, Rarity = "Uncommon", DisplayName = "T2 Key Fragment", HotbarEquippable = false, ProtectedOnDeath = false },
	T3KeyFragment = { Stackable = true, MaxStack = 99, Kind = "Material", Tier = 3, Rarity = "Rare", DisplayName = "T3 Key Fragment", HotbarEquippable = false, ProtectedOnDeath = false },
	T4KeyFragment = { Stackable = true, MaxStack = 99, Kind = "Material", Tier = 4, Rarity = "Epic", DisplayName = "T4 Key Fragment", HotbarEquippable = false, ProtectedOnDeath = false },
	T1DungeonKey = { Stackable = true, MaxStack = 50, Kind = "Material", Tier = 1, Rarity = "Rare", DisplayName = "T1 Dungeon Key", HotbarEquippable = false, ProtectedOnDeath = false },
	T2DungeonKey = { Stackable = true, MaxStack = 50, Kind = "Material", Tier = 2, Rarity = "Rare", DisplayName = "T2 Dungeon Key", HotbarEquippable = false, ProtectedOnDeath = false },
	T3DungeonKey = { Stackable = true, MaxStack = 50, Kind = "Material", Tier = 3, Rarity = "Epic", DisplayName = "T3 Dungeon Key", HotbarEquippable = false, ProtectedOnDeath = false },
	T4DungeonKey = { Stackable = true, MaxStack = 50, Kind = "Material", Tier = 4, Rarity = "Epic", DisplayName = "T4 Dungeon Key", HotbarEquippable = false, ProtectedOnDeath = false },
	-- Weapon enchant scrolls (T1–T5)
	T1WeaponScroll = { Stackable = true, MaxStack = 50, Kind = "Material", Tier = 1, Rarity = "Uncommon",  DisplayName = "T1 Wep Scroll", HotbarEquippable = false, ProtectedOnDeath = false, EnchantScroll = true, ScrollTarget = "Weapon", Icon = "rbxassetid://115282044684914", Description = "Add to a weapon to increase its current min and max damage by 5%. Each successful enchant compounds on the new value." },
	T2WeaponScroll = { Stackable = true, MaxStack = 50, Kind = "Material", Tier = 2, Rarity = "Uncommon",  DisplayName = "T2 Wep Scroll", HotbarEquippable = false, ProtectedOnDeath = false, EnchantScroll = true, ScrollTarget = "Weapon", Icon = "rbxassetid://115282044684914" },
	T3WeaponScroll = { Stackable = true, MaxStack = 50, Kind = "Material", Tier = 3, Rarity = "Rare",      DisplayName = "T3 Wep Scroll", HotbarEquippable = false, ProtectedOnDeath = false, EnchantScroll = true, ScrollTarget = "Weapon", Icon = "rbxassetid://115282044684914" },
	T4WeaponScroll = { Stackable = true, MaxStack = 50, Kind = "Material", Tier = 4, Rarity = "Epic",      DisplayName = "T4 Wep Scroll", HotbarEquippable = false, ProtectedOnDeath = false, EnchantScroll = true, ScrollTarget = "Weapon", Icon = "rbxassetid://115282044684914" },
	T5WeaponScroll = { Stackable = true, MaxStack = 50, Kind = "Material", Tier = 5, Rarity = "Legendary", DisplayName = "T5 Wep Scroll", HotbarEquippable = false, ProtectedOnDeath = false, EnchantScroll = true, ScrollTarget = "Weapon", Icon = "rbxassetid://115282044684914" },

	-- Armor enchant scrolls (T1–T5)
	T1ArmorScroll  = { Stackable = true, MaxStack = 50, Kind = "Material", Tier = 1, Rarity = "Uncommon",  DisplayName = "T1 Arm Scroll", HotbarEquippable = false, ProtectedOnDeath = false, EnchantScroll = true, ScrollTarget = "Armor",  Icon = "rbxassetid://115282044684914", Description = "Add to a piece of armor to increase its current HP by 5%. Each successful enchant compounds on the new value." },
	T2ArmorScroll  = { Stackable = true, MaxStack = 50, Kind = "Material", Tier = 2, Rarity = "Uncommon",  DisplayName = "T2 Arm Scroll", HotbarEquippable = false, ProtectedOnDeath = false, EnchantScroll = true, ScrollTarget = "Armor",  Icon = "rbxassetid://115282044684914" },
	T3ArmorScroll  = { Stackable = true, MaxStack = 50, Kind = "Material", Tier = 3, Rarity = "Rare",      DisplayName = "T3 Arm Scroll", HotbarEquippable = false, ProtectedOnDeath = false, EnchantScroll = true, ScrollTarget = "Armor",  Icon = "rbxassetid://115282044684914" },
	T4ArmorScroll  = { Stackable = true, MaxStack = 50, Kind = "Material", Tier = 4, Rarity = "Epic",      DisplayName = "T4 Arm Scroll", HotbarEquippable = false, ProtectedOnDeath = false, EnchantScroll = true, ScrollTarget = "Armor",  Icon = "rbxassetid://115282044684914" },
	T5ArmorScroll  = { Stackable = true, MaxStack = 50, Kind = "Material", Tier = 5, Rarity = "Legendary", DisplayName = "T5 Arm Scroll", HotbarEquippable = false, ProtectedOnDeath = false, EnchantScroll = true, ScrollTarget = "Armor",  Icon = "rbxassetid://115282044684914" },
	IronOre     = { Stackable = true,  MaxStack = 50, Kind = "Material",   Tier = 2, Rarity = "Uncommon", DisplayName = "Iron Ore", HotbarEquippable = false, ProtectedOnDeath = false },
	Fish        = { Stackable = true,  MaxStack = 50, Kind = "Material",   Tier = 1, Rarity = "Common", DisplayName = "Fish", HotbarEquippable = false, ProtectedOnDeath = false },
	VoidShard   = { Stackable = true,  MaxStack = 50, Kind = "Material",   Tier = 5, Rarity = "Legendary", DisplayName = "Void Shard", HotbarEquippable = false, ProtectedOnDeath = false },
	WoodenPickaxe = { Stackable = false, MaxStack = 1, Kind = "Material", Tier = 1, Rarity = "Common", DisplayName = "Wooden Pickaxe", HotbarEquippable = true, ProtectedOnDeath = true, ToolPrefabName = "WoodenPickaxe" },
	WoodenSpear   = { Stackable = false, MaxStack = 1, Kind = "Material", Tier = 1, Rarity = "Common", DisplayName = "Wooden Spear", HotbarEquippable = true, ProtectedOnDeath = true },

	-- Orbs of Alteration (T1-T5): rerolls all substats on a same-tier weapon or armor.
	T1OrbOfAlteration = { Stackable = true, MaxStack = 50, Kind = "Material", Tier = 1, Rarity = "Rare", DisplayName = "T1 Orb of Alteration", HotbarEquippable = false, ProtectedOnDeath = false, CraftingOrb = true, OrbKind = "Alteration", Icon = "rbxassetid://98829122247267", Description = "Rerolls all substats on a T1 weapon or armor. Wins or loses a 50/50 to determine how many substats are rolled. 75% chance to guarantee Elemental DMG on weapons." },
	T2OrbOfAlteration = { Stackable = true, MaxStack = 50, Kind = "Material", Tier = 2, Rarity = "Rare", DisplayName = "T2 Orb of Alteration", HotbarEquippable = false, ProtectedOnDeath = false, CraftingOrb = true, OrbKind = "Alteration", Icon = "rbxassetid://98829122247267", Description = "Rerolls all substats on a T2 weapon or armor. Wins or loses a 50/50 to determine how many substats are rolled. 75% chance to guarantee Elemental DMG on weapons." },
	T3OrbOfAlteration = { Stackable = true, MaxStack = 50, Kind = "Material", Tier = 3, Rarity = "Rare", DisplayName = "T3 Orb of Alteration", HotbarEquippable = false, ProtectedOnDeath = false, CraftingOrb = true, OrbKind = "Alteration", Icon = "rbxassetid://98829122247267", Description = "Rerolls all substats on a T3 weapon or armor. Wins or loses a 50/50 to determine how many substats are rolled. 75% chance to guarantee Elemental DMG on weapons." },
	T4OrbOfAlteration = { Stackable = true, MaxStack = 50, Kind = "Material", Tier = 4, Rarity = "Rare", DisplayName = "T4 Orb of Alteration", HotbarEquippable = false, ProtectedOnDeath = false, CraftingOrb = true, OrbKind = "Alteration", Icon = "rbxassetid://98829122247267", Description = "Rerolls all substats on a T4 weapon or armor. Wins or loses a 50/50 to determine how many substats are rolled. 75% chance to guarantee Elemental DMG on weapons." },
	T5OrbOfAlteration = { Stackable = true, MaxStack = 50, Kind = "Material", Tier = 5, Rarity = "Rare", DisplayName = "T5 Orb of Alteration", HotbarEquippable = false, ProtectedOnDeath = false, CraftingOrb = true, OrbKind = "Alteration", Icon = "rbxassetid://98829122247267", Description = "Rerolls all substats on a T5 weapon or armor. Wins or loses a 50/50 to determine how many substats are rolled. 75% chance to guarantee Elemental DMG on weapons." },

	-- Orbs of Wisdom (T1-T5): each use adds +1 level to a same-tier weapon or armor, up to tier cap (20/40/60/80/100).
	T1OrbOfWisdom = { Stackable = true, MaxStack = 50, Kind = "Material", Tier = 1, Rarity = "Rare", DisplayName = "T1 Orb of Wisdom", HotbarEquippable = false, ProtectedOnDeath = false, CraftingOrb = true, OrbKind = "Wisdom", Icon = "rbxassetid://18147139480", Description = "Increases a T1 weapon or armor's level by 1 (max level 20). Right-click the orb, then right-click the target item." },
	T2OrbOfWisdom = { Stackable = true, MaxStack = 50, Kind = "Material", Tier = 2, Rarity = "Rare", DisplayName = "T2 Orb of Wisdom", HotbarEquippable = false, ProtectedOnDeath = false, CraftingOrb = true, OrbKind = "Wisdom", Icon = "rbxassetid://18147139480", Description = "Increases a T2 weapon or armor's level by 1 (max level 40). Right-click the orb, then right-click the target item." },
	T3OrbOfWisdom = { Stackable = true, MaxStack = 50, Kind = "Material", Tier = 3, Rarity = "Rare", DisplayName = "T3 Orb of Wisdom", HotbarEquippable = false, ProtectedOnDeath = false, CraftingOrb = true, OrbKind = "Wisdom", Icon = "rbxassetid://18147139480", Description = "Increases a T3 weapon or armor's level by 1 (max level 60). Right-click the orb, then right-click the target item." },
	T4OrbOfWisdom = { Stackable = true, MaxStack = 50, Kind = "Material", Tier = 4, Rarity = "Rare", DisplayName = "T4 Orb of Wisdom", HotbarEquippable = false, ProtectedOnDeath = false, CraftingOrb = true, OrbKind = "Wisdom", Icon = "rbxassetid://18147139480", Description = "Increases a T4 weapon or armor's level by 1 (max level 80). Right-click the orb, then right-click the target item." },
	T5OrbOfWisdom = { Stackable = true, MaxStack = 50, Kind = "Material", Tier = 5, Rarity = "Rare", DisplayName = "T5 Orb of Wisdom", HotbarEquippable = false, ProtectedOnDeath = false, CraftingOrb = true, OrbKind = "Wisdom", Icon = "rbxassetid://18147139480", Description = "Increases a T5 weapon or armor's level by 1 (max level 100). Right-click the orb, then right-click the target item." },

	-- Weapons: each row maps to a WeaponData entry.
	TrainingSword = { Stackable = false, MaxStack = 1, Kind = "Weapon", Tier = 1, Rarity = "Common", WeaponId = "TrainingSword", HotbarEquippable = true, ProtectedOnDeath = false, DisplayName = "Training Sword" },
	TrainingBow   = { Stackable = false, MaxStack = 1, Kind = "Weapon", Tier = 1, Rarity = "Common", WeaponId = "WoodenBow", HotbarEquippable = true, ProtectedOnDeath = false, DisplayName = "Training Bow" },
	WoodenSword   = { Stackable = false, MaxStack = 1, Kind = "Weapon", Tier = 1, Rarity = "Common", WeaponId = "WoodenSword", HotbarEquippable = true, ProtectedOnDeath = false },
	WoodenBow     = { Stackable = false, MaxStack = 1, Kind = "Weapon", Tier = 1, Rarity = "Common", WeaponId = "WoodenBow", HotbarEquippable = true, ProtectedOnDeath = false },

	-- Starter / training armor (same tier as T1 leather; stats live on the item instance subStats).
	TrainingHelm   = { Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Helm",  Tier = 1, Rarity = "Common", Armor = 0, HotbarEquippable = false, ProtectedOnDeath = false, DisplayName = "Training Helm" },
	TrainingChest  = { Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Chest", Tier = 1, Rarity = "Common", Armor = 0, HotbarEquippable = false, ProtectedOnDeath = false, DisplayName = "Training Chest" },
	TrainingLegs   = { Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Legs",  Tier = 1, Rarity = "Common", Armor = 0, HotbarEquippable = false, ProtectedOnDeath = false, DisplayName = "Training Legs" },
	TrainingBoots  = { Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Boots", Tier = 1, Rarity = "Common", Armor = 0, HotbarEquippable = false, ProtectedOnDeath = false, DisplayName = "Training Boots" },
	TrainingShield = { Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Shield", Tier = 1, Rarity = "Common", Armor = 0, HotbarEquippable = false, ProtectedOnDeath = false, DisplayName = "Training Shield" },

	-- Starter profession tools (reuse default T1 tool prefabs).
	TrainingPickaxe = { Stackable = false, MaxStack = 1, Kind = "Material", Tier = 1, Rarity = "Common", HotbarEquippable = true, ProtectedOnDeath = true, ToolPrefabName = "WoodenPickaxe", DisplayName = "Training Pickaxe" },
	TrainingSpear   = { Stackable = false, MaxStack = 1, Kind = "Material", Tier = 1, Rarity = "Common", HotbarEquippable = true, ProtectedOnDeath = true, ToolPrefabName = "WoodenSpear", DisplayName = "Training Spear" },

	-- Armor pieces. Armor is RATING, not percentage.
	LeatherHelm  = { Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Helm",  Tier = 1, Rarity = "Common", Armor = 5, HotbarEquippable = false, ProtectedOnDeath = false },
	IronHelm     = { Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Helm",  Tier = 2, Rarity = "Uncommon", Armor = 14, HotbarEquippable = false, ProtectedOnDeath = false },
	SteelHelm    = { Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Helm",  Tier = 3, Rarity = "Rare", Armor = 28, HotbarEquippable = false, ProtectedOnDeath = false },
	RuneHelm     = { Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Helm",  Tier = 4, Rarity = "Epic", Armor = 48, HotbarEquippable = false, ProtectedOnDeath = false },
	VoidHelm     = { Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Helm",  Tier = 5, Rarity = "Legendary", Armor = 75, HotbarEquippable = false, ProtectedOnDeath = false },

	LeatherChest = { Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Chest", Tier = 1, Rarity = "Common", Armor = 10, HotbarEquippable = false, ProtectedOnDeath = false },
	IronChest    = { Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Chest", Tier = 2, Rarity = "Uncommon", Armor = 24, HotbarEquippable = false, ProtectedOnDeath = false },
	SteelChest   = { Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Chest", Tier = 3, Rarity = "Rare", Armor = 44, HotbarEquippable = false, ProtectedOnDeath = false },
	RuneChest    = { Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Chest", Tier = 4, Rarity = "Epic", Armor = 72, HotbarEquippable = false, ProtectedOnDeath = false },
	VoidChest    = { Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Chest", Tier = 5, Rarity = "Legendary", Armor = 110, HotbarEquippable = false, ProtectedOnDeath = false },

	-- Fill in Legs and Boots tiers following the same pattern.
}

local ItemDefinitions = {}
ItemDefinitions.Items = Items

function ItemDefinitions.Get(itemId)
	return Items[itemId]
end

function ItemDefinitions.GetMaxStack(itemId)
	local def = Items[itemId]
	if not def then return 0 end
	if def.Stackable then
		return def.MaxStack or 50
	end
	return 1
end

function ItemDefinitions.GetKind(itemId)
	local def = Items[itemId]
	return def and def.Kind or nil
end

function ItemDefinitions.IsProtectedOnDeath(itemId)
	local def = Items[itemId]
	if not def then
		return false
	end
	return def.ProtectedOnDeath == true
end

-- Backward-compatible helper for legacy callers.
function ItemDefinitions.GetDroppableOnDeath(itemId)
	return not ItemDefinitions.IsProtectedOnDeath(itemId)
end

function ItemDefinitions.IsStackable(itemId)
	local def = Items[itemId]
	if def and def.Stackable then
		return true
	end
	return false
end

function ItemDefinitions.IsHotbarEquippable(itemId)
	local def = Items[itemId]
	if not def then
		return false
	end
	if def.HotbarEquippable ~= nil then
		return def.HotbarEquippable == true
	end
	local kind = def.Kind
	if kind == "Weapon" or kind == "Ammo" then
		return true
	end
	if kind == "Consumable" then
		return true
	end
	return false
end

function ItemDefinitions.IsMeleeWeapon(itemId)
	local def = Items[itemId]
	if not def or def.Kind ~= "Weapon" then
		return false
	end
	local weaponId = string.lower(def.WeaponId or itemId)
	if string.find(weaponId, "bow", 1, true) then
		return false
	end
	return true
end

function ItemDefinitions.IsEnchantScroll(itemId)
	local def = Items[itemId]
	return def ~= nil and def.EnchantScroll == true
end

function ItemDefinitions.GetDescription(itemId)
	if type(itemId) ~= "string" or itemId == "" then
		return ""
	end
	local def = Items[itemId]
	return (def and type(def.Description) == "string") and def.Description or ""
end

function ItemDefinitions.GetIcon(itemId)
	if type(itemId) ~= "string" or itemId == "" then return "" end
	local def = Items[itemId]
	return (def and type(def.Icon) == "string") and def.Icon or ""
end

function ItemDefinitions.GetScrollTarget(itemId)
	local def = Items[itemId]
	return def and def.ScrollTarget or nil
end

return ItemDefinitions
