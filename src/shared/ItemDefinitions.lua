-- ItemDefinitions
-- Catalog of every item that can exist in a player inventory.
-- Weapons reference entries in ReplicatedStorage.WeaponData for their
-- combat-relevant stats (Damage, MaxRange, AttackType). This module owns
-- everything else: stacking rules, slot kind, armor rating, consumable
-- effects, tier gating.
--
-- Fields:
--   Stackable : items with Stackable=false take exactly one slot, with a UID.
--   MaxStack  : default 100 for stackables, 1 for non-stackables.
--   Kind      : "Weapon" | "Armor" | "Consumable" | "Ammo" | "Material" | "Food"
--   SubKind   : optional sub-classifier. For Food: "Fish" marks the fish subclass.
--   Tier      : 1..5.
--   Slot      : armor only. "Helm" | "Chest" | "Legs" | "Boots".
--   WeaponId  : weapons only. Key into WeaponData.Weapons.
--   Armor     : armor pieces only. Flat armor rating added when equipped.
--   ProtectedOnDeath : explicit boolean. true means never dropped on player death.
--   HotbarEquippable : optional boolean. If set, gates assigning this catalog item to the 9-slot dungeon hotbar.
--       Raw materials / collectibles should be false; weapons, tools, ammo, potions, food typically true.
--   DisplayName : optional string for UI when different from itemId.
--   ToolPrefabName : optional. Tool template name under ServerStorage.DungeonToolPrefabsArchive (dungeon hotbar sync).
--       Food items without a ToolPrefabName fall back to "DefaultFoodTool" (generated at runtime).
--   MountSpeed     : optional. Saddle tools: cloned Horse model Humanoid.WalkSpeed (tier scaling).
--   Food fields (Kind="Food"):
--     HungerAmount : hunger restored on eat (HungerData.addHunger).
--     TimeToEat    : seconds the player must hold right-click while equipped before the eat resolves. Fish use 0 for instant eat.
--     Buffs        : optional array of { type=string, amount=number, duration=number } applied via BuffService on eat.
--                    Buff types currently consumed: "WalkSpeedPct" (EnergyServer), "LuckPct" (LootService).
--                    Other types are stored and visible via BuffService but produce no effect yet.

--  NAMING CONVENTION (see .claude/CLAUDE.md "Asset & naming conventions")
--  The game is 5-tier. Names must encode tier, never vague adjectives.
--    New ids:  T1_Sword, T2_Helm, T1_Bow   (PascalCase after the tier prefix)
--    Never as a code-facing id: "Low tier", "Basic", "Starter" -- those are
--    display words. DisplayName is the only place human phrasing belongs.
--    No snake_case or spaces. Low_tier_sword / "Wood Sword" / "Gravity Coil"
--    are legacy: leave them, do not imitate them.
--
--  Legacy ids are FROZEN. Keys here are itemIds persisted in PlayerProfile_v1;
--  renaming one orphans every saved item using it. Convention applies to new
--  entries only. Renaming an existing id needs an alias map applied on profile
--  load.

local MaterialIcons   = require(script.Parent.Assets.Icons.Materials.MaterialIcons)
local KeyIcons        = require(script.Parent.Assets.Icons.Keys.KeyIcons)
local ConsumableIcons = require(script.Parent.Assets.Icons.Consumables.ConsumableIcons)
local ItemConfig      = require(script.Parent:WaitForChild("ItemConfig"))

local Items = {

	-- Stackable consumables and materials.
	-- Renamed from HealPotion/MajorPotion 2026-06-22 to match Minor/Medium icon registry naming.
	MinorPotion  = { Stackable = true,  MaxStack = 100, Kind = "Consumable", Tier = 1, Rarity = "Common", HealAmount = 40, HotbarEquippable = true, ProtectedOnDeath = false, Icon = ConsumableIcons.MINOR_POTION },
	MediumPotion = { Stackable = true,  MaxStack = 100, Kind = "Consumable", Tier = 3, Rarity = "Rare", HealAmount = 120, HotbarEquippable = true, ProtectedOnDeath = false, Icon = ConsumableIcons.MEDIUM_POTION },
	EtherFlask  = { Stackable = true,  MaxStack = 100, Kind = "Consumable", Tier = 4, Rarity = "Epic", EnergyAmount = 60, HotbarEquippable = true, ProtectedOnDeath = false },
	Arrow       = { Stackable = true,  MaxStack = 100, Kind = "Ammo",       Tier = 1, Rarity = "Common", HotbarEquippable = true, ProtectedOnDeath = false },
	Coal        = { Stackable = true,  MaxStack = 100, Kind = "Material",   Tier = 1, Rarity = "Common", DisplayName = "Coal", HotbarEquippable = false, ProtectedOnDeath = false, Icon = "rbxassetid://257670479" },
	Coins       = { Stackable = true,  MaxStack = 100, Kind = "Material",   Tier = 1, Rarity = "Common", DisplayName = "Coins", HotbarEquippable = false, ProtectedOnDeath = false, Icon = "rbxassetid://595987284" },
	T1Scrap     = { Stackable = true,  MaxStack = 100, Kind = "Material",   Tier = 1, Rarity = "Common", DisplayName = "T1 Scrap", HotbarEquippable = false, ProtectedOnDeath = false, Icon = MaterialIcons.T1_SCRAP },
	T2Scrap     = { Stackable = true,  MaxStack = 100, Kind = "Material",   Tier = 2, Rarity = "Uncommon", DisplayName = "T2 Scrap", HotbarEquippable = false, ProtectedOnDeath = false, Icon = MaterialIcons.T2_SCRAP },
	T3Scrap     = { Stackable = true,  MaxStack = 100, Kind = "Material",   Tier = 3, Rarity = "Rare", DisplayName = "T3 Scrap", HotbarEquippable = false, ProtectedOnDeath = false, Icon = MaterialIcons.T3_SCRAP },
	T4Scrap     = { Stackable = true,  MaxStack = 100, Kind = "Material",   Tier = 4, Rarity = "Epic", DisplayName = "T4 Scrap", HotbarEquippable = false, ProtectedOnDeath = false, Icon = MaterialIcons.T4_SCRAP },
	T5Scrap     = { Stackable = true,  MaxStack = 100, Kind = "Material",   Tier = 5, Rarity = "Legendary", DisplayName = "T5 Scrap", HotbarEquippable = false, ProtectedOnDeath = false, Icon = MaterialIcons.T5_SCRAP },
	T1WeaponProtectionScroll = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 1, Rarity = "Uncommon", DisplayName = "T1 Weapon Protection Scroll", HotbarEquippable = false, ProtectedOnDeath = false, ProtectionScroll = true, ScrollTarget = "Weapon", Icon = "rbxassetid://77558639338433", Description = "Apply only to a T1 weapon to mark it Protected (tooltip). While Protected, a failed T1 enchant roll will not reset your enchant (protection is consumed). A successful T1 enchant also removes Protected. Cannot apply if already Protected." },
	T1ArmorProtectionScroll = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 1, Rarity = "Uncommon", DisplayName = "T1 Armor Protection Scroll", HotbarEquippable = false, ProtectedOnDeath = false, ProtectionScroll = true, ScrollTarget = "Armor", Icon = "rbxassetid://137035522570475", Description = "Apply only to a T1 armor piece to mark it Protected (tooltip). While Protected, a failed T1 enchant roll will not reset your enchant (protection is consumed). A successful T1 enchant also removes Protected. Cannot apply if already Protected." },
	T2WeaponProtectionScroll = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 2, Rarity = "Uncommon", DisplayName = "T2 Weapon Protection Scroll", HotbarEquippable = false, ProtectedOnDeath = false, ProtectionScroll = true, ScrollTarget = "Weapon", Icon = "rbxassetid://77558639338433", Description = "Apply only to a T2 weapon to mark it Protected (tooltip). While Protected, a failed T2 enchant roll will not reset your enchant (protection is consumed). A successful T2 enchant also removes Protected. Cannot apply if already Protected." },
	T2ArmorProtectionScroll = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 2, Rarity = "Uncommon", DisplayName = "T2 Armor Protection Scroll", HotbarEquippable = false, ProtectedOnDeath = false, ProtectionScroll = true, ScrollTarget = "Armor", Icon = "rbxassetid://137035522570475", Description = "Apply only to a T2 armor piece to mark it Protected (tooltip). While Protected, a failed T2 enchant roll will not reset your enchant (protection is consumed). A successful T2 enchant also removes Protected. Cannot apply if already Protected." },
	T3WeaponProtectionScroll = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 3, Rarity = "Rare", DisplayName = "T3 Weapon Protection Scroll", HotbarEquippable = false, ProtectedOnDeath = false, ProtectionScroll = true, ScrollTarget = "Weapon", Icon = "rbxassetid://77558639338433", Description = "Apply only to a T3 weapon to mark it Protected (tooltip). While Protected, a failed T3 enchant roll will not reset your enchant (protection is consumed). A successful T3 enchant also removes Protected. Cannot apply if already Protected." },
	T3ArmorProtectionScroll = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 3, Rarity = "Rare", DisplayName = "T3 Armor Protection Scroll", HotbarEquippable = false, ProtectedOnDeath = false, ProtectionScroll = true, ScrollTarget = "Armor", Icon = "rbxassetid://137035522570475", Description = "Apply only to a T3 armor piece to mark it Protected (tooltip). While Protected, a failed T3 enchant roll will not reset your enchant (protection is consumed). A successful T3 enchant also removes Protected. Cannot apply if already Protected." },
	T4WeaponProtectionScroll = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 4, Rarity = "Epic", DisplayName = "T4 Weapon Protection Scroll", HotbarEquippable = false, ProtectedOnDeath = false, ProtectionScroll = true, ScrollTarget = "Weapon", Icon = "rbxassetid://77558639338433", Description = "Apply only to a T4 weapon to mark it Protected (tooltip). While Protected, a failed T4 enchant roll will not reset your enchant (protection is consumed). A successful T4 enchant also removes Protected. Cannot apply if already Protected." },
	T4ArmorProtectionScroll = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 4, Rarity = "Epic", DisplayName = "T4 Armor Protection Scroll", HotbarEquippable = false, ProtectedOnDeath = false, ProtectionScroll = true, ScrollTarget = "Armor", Icon = "rbxassetid://137035522570475", Description = "Apply only to a T4 armor piece to mark it Protected (tooltip). While Protected, a failed T4 enchant roll will not reset your enchant (protection is consumed). A successful T4 enchant also removes Protected. Cannot apply if already Protected." },
	T5WeaponProtectionScroll = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 5, Rarity = "Legendary", DisplayName = "T5 Weapon Protection Scroll", HotbarEquippable = false, ProtectedOnDeath = false, ProtectionScroll = true, ScrollTarget = "Weapon", Icon = "rbxassetid://77558639338433", Description = "Apply only to a T5 weapon to mark it Protected (tooltip). While Protected, a failed T5 enchant roll will not reset your enchant (protection is consumed). A successful T5 enchant also removes Protected. Cannot apply if already Protected." },
	T5ArmorProtectionScroll = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 5, Rarity = "Legendary", DisplayName = "T5 Armor Protection Scroll", HotbarEquippable = false, ProtectedOnDeath = false, ProtectionScroll = true, ScrollTarget = "Armor", Icon = "rbxassetid://137035522570475", Description = "Apply only to a T5 armor piece to mark it Protected (tooltip). While Protected, a failed T5 enchant roll will not reset your enchant (protection is consumed). A successful T5 enchant also removes Protected. Cannot apply if already Protected." },
	T1OrbOfWisdom = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 1, Rarity = "Rare", DisplayName = "T1 Orb of Wisdom", HotbarEquippable = false, ProtectedOnDeath = false, CraftingOrb = true, OrbKind = "Wisdom", Icon = "rbxassetid://81085733676869", Description = "Increases a T1 weapon or armor's level by 1 (max level 20). Right-click the orb, then right-click the target item." },
	T2OrbOfWisdom = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 2, Rarity = "Rare", DisplayName = "T2 Orb of Wisdom", HotbarEquippable = false, ProtectedOnDeath = false, CraftingOrb = true, OrbKind = "Wisdom", Icon = "rbxassetid://81085733676869", Description = "Increases a T2 weapon or armor's level by 1 (max level 40). Right-click the orb, then right-click the target item." },
	T3OrbOfWisdom = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 3, Rarity = "Rare", DisplayName = "T3 Orb of Wisdom", HotbarEquippable = false, ProtectedOnDeath = false, CraftingOrb = true, OrbKind = "Wisdom", Icon = "rbxassetid://81085733676869", Description = "Increases a T3 weapon or armor's level by 1 (max level 60). Right-click the orb, then right-click the target item." },
	T4OrbOfWisdom = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 4, Rarity = "Rare", DisplayName = "T4 Orb of Wisdom", HotbarEquippable = false, ProtectedOnDeath = false, CraftingOrb = true, OrbKind = "Wisdom", Icon = "rbxassetid://81085733676869", Description = "Increases a T4 weapon or armor's level by 1 (max level 80). Right-click the orb, then right-click the target item." },
	T5OrbOfWisdom = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 5, Rarity = "Rare", DisplayName = "T5 Orb of Wisdom", HotbarEquippable = false, ProtectedOnDeath = false, CraftingOrb = true, OrbKind = "Wisdom", Icon = "rbxassetid://81085733676869", Description = "Increases a T5 weapon or armor's level by 1 (max level 100). Right-click the orb, then right-click the target item." },
	T1OrbOfChaos = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 1, Rarity = "Rare", DisplayName = "T1 Orb of Chaos", HotbarEquippable = false, ProtectedOnDeath = false, CraftingOrb = true, OrbKind = "Chaos", Icon = "rbxassetid://115226929770266", Description = "Crafting reagent (no stat effect yet). Must match item tier (T1). In Character: right-click the orb, then right-click a weapon or armor to consume it." },
	T1OrbOfNullification = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 1, Rarity = "Rare", DisplayName = "T1 Orb of Nullification", HotbarEquippable = false, ProtectedOnDeath = false, CraftingOrb = true, OrbKind = "Nullification", Icon = "rbxassetid://120424322569692", Description = "Crafting reagent (no stat effect yet). Must match item tier (T1). In Character: right-click the orb, then right-click a weapon or armor to consume it." },
	T1OrbOfAlteration = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 1, Rarity = "Rare", DisplayName = "T1 Orb of Alteration", HotbarEquippable = false, ProtectedOnDeath = false, CraftingOrb = true, OrbKind = "Alteration", Icon = "rbxassetid://98829122247267", Description = "Rerolls all substats on a T1 weapon or armor. Wins or loses a 50/50 to determine how many substats are rolled. 75% chance to guarantee Elemental DMG on weapons." },
	T2OrbOfAlteration = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 2, Rarity = "Rare", DisplayName = "T2 Orb of Alteration", HotbarEquippable = false, ProtectedOnDeath = false, CraftingOrb = true, OrbKind = "Alteration", Icon = "rbxassetid://98829122247267", Description = "Rerolls all substats on a T2 weapon or armor. Wins or loses a 50/50 to determine how many substats are rolled. 75% chance to guarantee Elemental DMG on weapons." },
	T3OrbOfAlteration = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 3, Rarity = "Rare", DisplayName = "T3 Orb of Alteration", HotbarEquippable = false, ProtectedOnDeath = false, CraftingOrb = true, OrbKind = "Alteration", Icon = "rbxassetid://98829122247267", Description = "Rerolls all substats on a T3 weapon or armor. Wins or loses a 50/50 to determine how many substats are rolled. 75% chance to guarantee Elemental DMG on weapons." },
	T4OrbOfAlteration = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 4, Rarity = "Rare", DisplayName = "T4 Orb of Alteration", HotbarEquippable = false, ProtectedOnDeath = false, CraftingOrb = true, OrbKind = "Alteration", Icon = "rbxassetid://98829122247267", Description = "Rerolls all substats on a T4 weapon or armor. Wins or loses a 50/50 to determine how many substats are rolled. 75% chance to guarantee Elemental DMG on weapons." },
	T5OrbOfAlteration = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 5, Rarity = "Rare", DisplayName = "T5 Orb of Alteration", HotbarEquippable = false, ProtectedOnDeath = false, CraftingOrb = true, OrbKind = "Alteration", Icon = "rbxassetid://98829122247267", Description = "Rerolls all substats on a T5 weapon or armor. Wins or loses a 50/50 to determine how many substats are rolled. 75% chance to guarantee Elemental DMG on weapons." },
	T1OrbOfTransmutation = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 1, Rarity = "Rare", DisplayName = "T1 Orb of Transmutation", HotbarEquippable = false, ProtectedOnDeath = false, CraftingOrb = true, OrbKind = "Transmutation", Icon = "rbxassetid://83384060673495", Description = "Crafting reagent (no stat effect yet). Must match item tier (T1). In Character: right-click the orb, then right-click a weapon or armor to consume it." },
	T1OrbOfReforging = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 1, Rarity = "Rare", DisplayName = "T1 Orb of Reforging", HotbarEquippable = false, ProtectedOnDeath = false, CraftingOrb = true, OrbKind = "Reforging", Icon = "rbxassetid://92494447000682", Description = "Crafting reagent (no stat effect yet). Must match item tier (T1). In Character: right-click the orb, then right-click a weapon or armor to consume it." },
	T1OrbOfDivinity = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 1, Rarity = "Rare", DisplayName = "T1 Orb of Divinity", HotbarEquippable = false, ProtectedOnDeath = false, CraftingOrb = true, OrbKind = "Divinity", Icon = "rbxassetid://78151024612669", Description = "Crafting reagent (no stat effect yet). Must match item tier (T1). In Character: right-click the orb, then right-click a weapon or armor to consume it." },

	-- Mount saddles (Animal Trainer): hotbar tools that spawn the Horse model; Humanoid.WalkSpeed scales by tier.
	T1MountSaddle = { Stackable = false, MaxStack = 1, Kind = "Material", Tier = 1, Rarity = "Common", DisplayName = "T1 Mount Saddle", HotbarEquippable = true, ProtectedOnDeath = false, ToolPrefabName = "DungeonMountSaddleTool", MountSpeed = 20 },
	T2MountSaddle = { Stackable = false, MaxStack = 1, Kind = "Material", Tier = 2, Rarity = "Uncommon", DisplayName = "T2 Mount Saddle", HotbarEquippable = true, ProtectedOnDeath = false, ToolPrefabName = "DungeonMountSaddleTool", MountSpeed = 30 },
	T3MountSaddle = { Stackable = false, MaxStack = 1, Kind = "Material", Tier = 3, Rarity = "Rare", DisplayName = "T3 Mount Saddle", HotbarEquippable = true, ProtectedOnDeath = false, ToolPrefabName = "DungeonMountSaddleTool", MountSpeed = 40 },
	T4MountSaddle = { Stackable = false, MaxStack = 1, Kind = "Material", Tier = 4, Rarity = "Epic", DisplayName = "T4 Mount Saddle", HotbarEquippable = true, ProtectedOnDeath = false, ToolPrefabName = "DungeonMountSaddleTool", MountSpeed = 50 },

	-- Key fragments + forged keys (Dungeoneer: 40 fragments -> 1 key per tier)
	T1KeyFragment = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 1, Rarity = "Uncommon", DisplayName = "T1 Key Fragment", HotbarEquippable = false, ProtectedOnDeath = false },
	T2KeyFragment = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 2, Rarity = "Uncommon", DisplayName = "T2 Key Fragment", HotbarEquippable = false, ProtectedOnDeath = false },
	T3KeyFragment = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 3, Rarity = "Rare", DisplayName = "T3 Key Fragment", HotbarEquippable = false, ProtectedOnDeath = false },
	T4KeyFragment = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 4, Rarity = "Epic",      DisplayName = "T4 Key Fragment", HotbarEquippable = false, ProtectedOnDeath = false },
	T5KeyFragment = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 5, Rarity = "Legendary", DisplayName = "T5 Key Fragment", HotbarEquippable = false, ProtectedOnDeath = false },
	T1DungeonKey = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 1, Rarity = "Rare", DisplayName = "T1 Dungeon Key", HotbarEquippable = false, ProtectedOnDeath = false, Icon = KeyIcons.T1_DUNGEON_KEY },
	T2DungeonKey = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 2, Rarity = "Rare", DisplayName = "T2 Dungeon Key", HotbarEquippable = false, ProtectedOnDeath = false, Icon = KeyIcons.T2_DUNGEON_KEY },
	T3DungeonKey = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 3, Rarity = "Epic", DisplayName = "T3 Dungeon Key", HotbarEquippable = false, ProtectedOnDeath = false, Icon = KeyIcons.T3_DUNGEON_KEY },
	T4DungeonKey = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 4, Rarity = "Epic",      DisplayName = "T4 Dungeon Key",  HotbarEquippable = false, ProtectedOnDeath = false, Icon = KeyIcons.T4_DUNGEON_KEY },
	T5DungeonKey = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 5, Rarity = "Legendary", DisplayName = "T5 Dungeon Key",  HotbarEquippable = false, ProtectedOnDeath = false, Icon = KeyIcons.T5_DUNGEON_KEY },
	-- Weapon enchant scrolls (T1–T5)
	T1WeaponScroll = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 1, Rarity = "Uncommon",  DisplayName = "T1 Weapon Scroll", HotbarEquippable = false, ProtectedOnDeath = false, EnchantScroll = true, ScrollTarget = "Weapon", Icon = "rbxassetid://133972739954362", Description = "Add to a weapon to increase its current min and max damage by 5%. Each successful enchant compounds on the new value. Only works on weapons; use T1 Armor Scroll for armor." },
	T2WeaponScroll = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 2, Rarity = "Uncommon",  DisplayName = "T2 Wep Scroll", HotbarEquippable = false, ProtectedOnDeath = false, EnchantScroll = true, ScrollTarget = "Weapon", Icon = "rbxassetid://133972739954362" },
	T3WeaponScroll = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 3, Rarity = "Rare",      DisplayName = "T3 Wep Scroll", HotbarEquippable = false, ProtectedOnDeath = false, EnchantScroll = true, ScrollTarget = "Weapon", Icon = "rbxassetid://133972739954362" },
	T4WeaponScroll = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 4, Rarity = "Epic",      DisplayName = "T4 Wep Scroll", HotbarEquippable = false, ProtectedOnDeath = false, EnchantScroll = true, ScrollTarget = "Weapon", Icon = "rbxassetid://133972739954362" },
	T5WeaponScroll = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 5, Rarity = "Legendary", DisplayName = "T5 Wep Scroll", HotbarEquippable = false, ProtectedOnDeath = false, EnchantScroll = true, ScrollTarget = "Weapon", Icon = "rbxassetid://133972739954362" },

	-- Armor enchant scrolls (T1–T5)
	T1ArmorScroll  = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 1, Rarity = "Uncommon",  DisplayName = "T1 Armor Scroll", HotbarEquippable = false, ProtectedOnDeath = false, EnchantScroll = true, ScrollTarget = "Armor",  Icon = "rbxassetid://93890103968535", Description = "Add to a piece of armor to increase its current HP by 5%. Each successful enchant compounds on the new value. Only works on armor; use T1 Weapon Scroll for weapons." },
	T2ArmorScroll  = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 2, Rarity = "Uncommon",  DisplayName = "T2 Arm Scroll", HotbarEquippable = false, ProtectedOnDeath = false, EnchantScroll = true, ScrollTarget = "Armor",  Icon = "rbxassetid://93890103968535" },
	T3ArmorScroll  = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 3, Rarity = "Rare",      DisplayName = "T3 Arm Scroll", HotbarEquippable = false, ProtectedOnDeath = false, EnchantScroll = true, ScrollTarget = "Armor",  Icon = "rbxassetid://93890103968535" },
	T4ArmorScroll  = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 4, Rarity = "Epic",      DisplayName = "T4 Arm Scroll", HotbarEquippable = false, ProtectedOnDeath = false, EnchantScroll = true, ScrollTarget = "Armor",  Icon = "rbxassetid://93890103968535" },
	T5ArmorScroll  = { Stackable = true, MaxStack = 100, Kind = "Material", Tier = 5, Rarity = "Legendary", DisplayName = "T5 Arm Scroll", HotbarEquippable = false, ProtectedOnDeath = false, EnchantScroll = true, ScrollTarget = "Armor",  Icon = "rbxassetid://93890103968535" },
	Emerald     = { Stackable = true,  MaxStack = 100, Kind = "Material",   Tier = 2, Rarity = "Uncommon", DisplayName = "Emerald", HotbarEquippable = false, ProtectedOnDeath = false },
	IronOre     = { Stackable = true,  MaxStack = 100, Kind = "Material",   Tier = 2, Rarity = "Uncommon", DisplayName = "Iron Ore", HotbarEquippable = false, ProtectedOnDeath = false },
	Diamond     = { Stackable = true,  MaxStack = 100, Kind = "Material",   Tier = 4, Rarity = "Epic", DisplayName = "Diamond", HotbarEquippable = false, ProtectedOnDeath = false },
	Gold        = { Stackable = true,  MaxStack = 100, Kind = "Material",   Tier = 5, Rarity = "Legendary", DisplayName = "Gold", HotbarEquippable = false, ProtectedOnDeath = false },
	VoidShard   = { Stackable = true,  MaxStack = 100, Kind = "Material",   Tier = 5, Rarity = "Legendary", DisplayName = "Void Shard", HotbarEquippable = false, ProtectedOnDeath = false },

	-- Food (Kind="Food"). HotbarEquippable; right-click hold while equipped to eat (TimeToEat seconds).
	-- Fish are a sub-class (SubKind="Fish") with TimeToEat=0 for instant eat.
	Fish        = { Stackable = true, MaxStack = 100, Kind = "Food", SubKind = "Fish", Tier = 1, Rarity = "Common",   DisplayName = "Fish",        HotbarEquippable = true, ProtectedOnDeath = false, HungerAmount = 25, TimeToEat = 0,
	                Buffs = { { type = "WalkSpeedPct", amount = 10, duration = 15 } } },
	SwiftFish   = { Stackable = true, MaxStack = 100, Kind = "Food", SubKind = "Fish", Tier = 2, Rarity = "Uncommon", DisplayName = "Swift Fish",  HotbarEquippable = true, ProtectedOnDeath = false, HungerAmount = 30, TimeToEat = 0,
	                Buffs = { { type = "WalkSpeedPct", amount = 25, duration = 30 } } },
	LuckyFish   = { Stackable = true, MaxStack = 100, Kind = "Food", SubKind = "Fish", Tier = 2, Rarity = "Uncommon", DisplayName = "Lucky Fish",  HotbarEquippable = true, ProtectedOnDeath = false, HungerAmount = 25, TimeToEat = 0,
	                Buffs = { { type = "LuckPct", amount = 15, duration = 30 } } },
	GoldenFish  = { Stackable = true, MaxStack = 100, Kind = "Food", SubKind = "Fish", Tier = 3, Rarity = "Rare",     DisplayName = "Golden Fish", HotbarEquippable = true, ProtectedOnDeath = false, HungerAmount = 35, TimeToEat = 0,
	                Buffs = { { type = "WalkSpeedPct", amount = 20, duration = 30 }, { type = "LuckPct", amount = 15, duration = 30 } } },

	-- Regular (non-fish) food: TimeToEat > 0, no buffs by default.
	Bread       = { Stackable = true, MaxStack = 100, Kind = "Food", Tier = 1, Rarity = "Common",   DisplayName = "Bread",       HotbarEquippable = true, ProtectedOnDeath = false, HungerAmount = 40, TimeToEat = 2.0 },
	CookedMeat  = { Stackable = true, MaxStack = 100, Kind = "Food", Tier = 1, Rarity = "Uncommon", DisplayName = "Cooked Meat", HotbarEquippable = true, ProtectedOnDeath = false, HungerAmount = 60, TimeToEat = 3.0 },
	WoodenPickaxe = { Icon = ItemConfig.TOOL_ICONS.Pickaxe, Stackable = false, MaxStack = 1, Kind = "Material", Tier = 1, Rarity = "Common", DisplayName = "Wooden Pickaxe", HotbarEquippable = true, ProtectedOnDeath = true, ToolPrefabName = "WoodenPickaxe" },
	WoodenSpear   = { Icon = ItemConfig.TOOL_ICONS.FishingRod, Stackable = false, MaxStack = 1, Kind = "Material", Tier = 1, Rarity = "Common", DisplayName = "Wooden Fishing Rod", HotbarEquippable = true, ProtectedOnDeath = true, ToolPrefabName = "WoodenSpear" },

	-- Weapons: each row maps to a WeaponData entry.
	TrainingSword = { Icon = ItemConfig.GENERATED_ITEM_ICONS[1].Sword, Stackable = false, MaxStack = 1, Kind = "Weapon", Tier = 1, Rarity = "Common", WeaponId = "TrainingSword", HotbarEquippable = true, ProtectedOnDeath = false, DisplayName = "Training Sword", ToolPrefabName = "TrainingSword" },
	TrainingBow   = { Icon = ItemConfig.GENERATED_ITEM_ICONS[1].Bow, Stackable = false, MaxStack = 1, Kind = "Weapon", Tier = 1, Rarity = "Common", WeaponId = "WoodenBow", HotbarEquippable = true, ProtectedOnDeath = false, DisplayName = "Training Bow" },
	WoodenSword   = { Icon = ItemConfig.GENERATED_ITEM_ICONS[1].Sword, Stackable = false, MaxStack = 1, Kind = "Weapon", Tier = 1, Rarity = "Common", WeaponId = "WoodenSword", HotbarEquippable = true, ProtectedOnDeath = false, DisplayName = "Wooden Sword", ToolPrefabName = "Wood Sword" },
	Low_tier_sword = { Stackable = false, MaxStack = 1, Kind = "Weapon", Tier = 1, Rarity = "Common", WeaponId = "WoodenSword", HotbarEquippable = true, ProtectedOnDeath = false, DisplayName = "Low Tier Sword", ToolPrefabName = "Low_tier_sword" },
	AdminSword    = { Icon = ItemConfig.ADMIN_SWORD_ICON, Stackable = false, MaxStack = 1, Kind = "Weapon", Tier = 99, Rarity = "Legendary", WeaponId = "AdminSword", HotbarEquippable = true, ProtectedOnDeath = false, DisplayName = "Admin Sword", ToolPrefabName = "Low_tier_sword" },
	WoodenBow     = { Icon = ItemConfig.GENERATED_ITEM_ICONS[1].Bow, Stackable = false, MaxStack = 1, Kind = "Weapon", Tier = 1, Rarity = "Common", WeaponId = "WoodenBow", HotbarEquippable = true, ProtectedOnDeath = false, DisplayName = "Wooden Bow" },

	-- Starter / training armor (T1-tier catalog ids; rolled stats live on the item instance).
	-- Untradeable = true: item cannot be listed on Auction House, salvaged, or dropped (see AuctionHouseService, TODO comments below).
	-- Icons pulled from ItemConfig.GENERATED_ITEM_ICONS so training gear always matches the
	-- same wooden/leather assets mob-dropped T1 gear uses (ItemDefinitions.GetIconForItem) --
	-- one shared table, no drift.
	TrainingHelm   = { Icon = ItemConfig.GENERATED_ITEM_ICONS[1].Helm,   Untradeable = true, Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Helm",   Tier = 1, Rarity = "Common", Armor = 0, HotbarEquippable = false, ProtectedOnDeath = false, DisplayName = "Training Helmet" },
	TrainingChest  = { Icon = ItemConfig.GENERATED_ITEM_ICONS[1].Chest,  Untradeable = true, Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Chest",  Tier = 1, Rarity = "Common", Armor = 0, HotbarEquippable = false, ProtectedOnDeath = false, DisplayName = "Training Chestplate" },
	TrainingLegs   = { Icon = ItemConfig.GENERATED_ITEM_ICONS[1].Legs,   Untradeable = true, Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Legs",   Tier = 1, Rarity = "Common", Armor = 0, HotbarEquippable = false, ProtectedOnDeath = false, DisplayName = "Training Leggings" },
	TrainingBoots  = { Icon = ItemConfig.GENERATED_ITEM_ICONS[1].Boots,  Untradeable = true, Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Boots",  Tier = 1, Rarity = "Common", Armor = 0, HotbarEquippable = false, ProtectedOnDeath = false, DisplayName = "Training Boots" },
	TrainingShield = { Icon = ItemConfig.GENERATED_ITEM_ICONS[1].Shield, Untradeable = true, Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Shield", Tier = 1, Rarity = "Common", Armor = 0, HotbarEquippable = false, ProtectedOnDeath = false, DisplayName = "Training Shield" },

	-- Starter profession tools (reuse T1 wooden tool prefabs).
	TrainingPickaxe = { Icon = ItemConfig.TOOL_ICONS.Pickaxe, Untradeable = true, Stackable = false, MaxStack = 1, Kind = "Material", Tier = 1, Rarity = "Common", HotbarEquippable = true, ProtectedOnDeath = true, ToolPrefabName = "WoodenPickaxe", DisplayName = "Training Pickaxe" },
	TrainingSpear   = { Icon = ItemConfig.TOOL_ICONS.FishingRod, Untradeable = true, Stackable = false, MaxStack = 1, Kind = "Material", Tier = 1, Rarity = "Common", HotbarEquippable = true, ProtectedOnDeath = true, ToolPrefabName = "WoodenSpear", DisplayName = "Training Fishing Rod" },
	-- TODO: FUTURE (Drop system) check Untradeable before allowing drops
	-- TODO: FUTURE (PvP loot system) check Untradeable before including item in death loot table

	-- Armor pieces. Armor is RATING, not percentage.
	LeatherHelm  = { Icon = ItemConfig.GENERATED_ITEM_ICONS[1].Helm,  DisplayName = "Leather Helmet",     Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Helm",  Tier = 1, Rarity = "Common",   Armor = 5,  HotbarEquippable = false, ProtectedOnDeath = false },
	IronHelm     = { Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Helm",  Tier = 2, Rarity = "Uncommon", Armor = 14, HotbarEquippable = false, ProtectedOnDeath = false },
	SteelHelm    = { Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Helm",  Tier = 3, Rarity = "Rare", Armor = 28, HotbarEquippable = false, ProtectedOnDeath = false },
	RuneHelm     = { Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Helm",  Tier = 4, Rarity = "Epic", Armor = 48, HotbarEquippable = false, ProtectedOnDeath = false },
	VoidHelm     = { Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Helm",  Tier = 5, Rarity = "Legendary", Armor = 75, HotbarEquippable = false, ProtectedOnDeath = false },

	LeatherChest = { Icon = ItemConfig.GENERATED_ITEM_ICONS[1].Chest, DisplayName = "Leather Chestplate", Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Chest", Tier = 1, Rarity = "Common",   Armor = 10, HotbarEquippable = false, ProtectedOnDeath = false },
	IronChest    = { Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Chest", Tier = 2, Rarity = "Uncommon", Armor = 24, HotbarEquippable = false, ProtectedOnDeath = false },
	SteelChest   = { Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Chest", Tier = 3, Rarity = "Rare", Armor = 44, HotbarEquippable = false, ProtectedOnDeath = false },
	RuneChest    = { Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Chest", Tier = 4, Rarity = "Epic", Armor = 72, HotbarEquippable = false, ProtectedOnDeath = false },
	VoidChest    = { Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Chest", Tier = 5, Rarity = "Legendary", Armor = 110, HotbarEquippable = false, ProtectedOnDeath = false },

	LeatherLegs  = { Icon = ItemConfig.GENERATED_ITEM_ICONS[1].Legs,  DisplayName = "Leather Leggings",   Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Legs",  Tier = 1, Rarity = "Common",    Armor = 8,   HotbarEquippable = false, ProtectedOnDeath = false },
	IronLegs     = {                                          Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Legs",  Tier = 2, Rarity = "Uncommon",  Armor = 20,  HotbarEquippable = false, ProtectedOnDeath = false },
	SteelLegs    = {                                          Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Legs",  Tier = 3, Rarity = "Rare",      Armor = 36,  HotbarEquippable = false, ProtectedOnDeath = false },
	RuneLegs     = {                                          Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Legs",  Tier = 4, Rarity = "Epic",      Armor = 60,  HotbarEquippable = false, ProtectedOnDeath = false },
	VoidLegs     = {                                          Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Legs",  Tier = 5, Rarity = "Legendary", Armor = 92,  HotbarEquippable = false, ProtectedOnDeath = false },

	LeatherBoots = { Icon = ItemConfig.GENERATED_ITEM_ICONS[1].Boots, DisplayName = "Leather Boots",      Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Boots", Tier = 1, Rarity = "Common",    Armor = 5,   HotbarEquippable = false, ProtectedOnDeath = false },
	IronBoots    = {                                          Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Boots", Tier = 2, Rarity = "Uncommon",  Armor = 14,  HotbarEquippable = false, ProtectedOnDeath = false },
	SteelBoots   = {                                          Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Boots", Tier = 3, Rarity = "Rare",      Armor = 26,  HotbarEquippable = false, ProtectedOnDeath = false },
	RuneBoots    = {                                          Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Boots", Tier = 4, Rarity = "Epic",      Armor = 44,  HotbarEquippable = false, ProtectedOnDeath = false },
	VoidBoots    = {                                          Stackable = false, MaxStack = 1, Kind = "Armor", Slot = "Boots", Tier = 5, Rarity = "Legendary", Armor = 68,  HotbarEquippable = false, ProtectedOnDeath = false },
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
		return def.MaxStack or 100
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

--- Returns true if the item can never be traded, auctioned, salvaged, or dropped.
--- Checked by AuctionHouseService on listing creation.
--- TODO: FUTURE (Salvage) enforce in NPCService SalvageGear handler.
--- TODO: FUTURE (Drop system) enforce in death loot / player trading.
function ItemDefinitions.IsUntradeable(itemId)
	local def = Items[itemId]
	if not def then return false end
	return def.Untradeable == true
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
	if kind == "Consumable" or kind == "Food" then
		return true
	end
	return false
end

function ItemDefinitions.IsFood(itemId)
	local def = Items[itemId]
	return def ~= nil and def.Kind == "Food"
end

function ItemDefinitions.IsFish(itemId)
	local def = Items[itemId]
	return def ~= nil and def.Kind == "Food" and def.SubKind == "Fish"
end

-- Returns a copy of the food config table, or nil if itemId is not a Food entry.
-- Fields: hungerAmount, timeToEat, buffs (array, may be empty), isFish.
function ItemDefinitions.GetFoodConfig(itemId)
	local def = Items[itemId]
	if not def or def.Kind ~= "Food" then
		return nil
	end
	local buffsCopy = {}
	if type(def.Buffs) == "table" then
		for _, b in ipairs(def.Buffs) do
			if type(b) == "table" and type(b.type) == "string" then
				table.insert(buffsCopy, {
					type = b.type,
					amount = tonumber(b.amount) or 0,
					duration = math.max(0, tonumber(b.duration) or 0),
				})
			end
		end
	end
	return {
		hungerAmount = math.max(0, tonumber(def.HungerAmount) or 0),
		timeToEat = math.max(0, tonumber(def.TimeToEat) or 0),
		buffs = buffsCopy,
		isFish = def.SubKind == "Fish",
	}
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

function ItemDefinitions.IsProtectionScroll(itemId)
	local def = Items[itemId]
	return def ~= nil and def.ProtectionScroll == true
end

function ItemDefinitions.IsCraftingOrb(itemId)
	local def = Items[itemId]
	return def ~= nil and def.CraftingOrb == true
end

function ItemDefinitions.GetOrbKind(itemId)
	local def = Items[itemId]
	return def and def.OrbKind or nil
end

function ItemDefinitions.IsScrollApplyItem(itemId)
	return ItemDefinitions.IsEnchantScroll(itemId) or ItemDefinitions.IsProtectionScroll(itemId) or ItemDefinitions.IsCraftingOrb(itemId)
end

function ItemDefinitions.GetDescription(itemId)
	if type(itemId) ~= "string" or itemId == "" then
		return ""
	end
	local def = Items[itemId]
	return (def and type(def.Description) == "string") and def.Description or ""
end

function ItemDefinitions.GetIcon(itemId)
	if type(itemId) ~= "string" or itemId == "" then
		return ""
	end
	local def = Items[itemId]
	if not def or type(def.Icon) ~= "string" then
		return ""
	end
	local icon = def.Icon
	icon = string.gsub(icon, "^%s+", "")
	icon = string.gsub(icon, "%s+$", "")
	if icon == "" then
		return ""
	end
	-- Full URI passthrough (ImageLabel / ImageButton)
	if string.sub(icon, 1, 13) == "rbxassetid://" or string.sub(icon, 1, 11) == "rbxthumb://" then
		return icon
	end
	if string.sub(icon, 1, 7) == "http://" or string.sub(icon, 1, 8) == "https://" then
		return icon
	end
	-- Bare numeric asset id (user pasted only digits)
	if string.match(icon, "^%d+$") then
		return "rbxassetid://" .. icon
	end
	return icon
end

function ItemDefinitions.GetScrollTarget(itemId)
	local def = Items[itemId]
	return def and def.ScrollTarget or nil
end

function ItemDefinitions.GetTierScrapItemId(tier)
	local t = math.clamp(math.floor(tonumber(tier) or 1), 1, 5)
	return "T" .. tostring(t) .. "Scrap"
end

function ItemDefinitions.IsTierScrapItemId(itemId)
	return type(itemId) == "string" and string.match(itemId, "^T[1-5]Scrap$") ~= nil
end

-- GetIconForItem -- like GetIcon, but also resolves itemId-less items. Procedurally generated
-- mob drops (ItemGenerator -> ItemClass:toGrantTemplate()) never persist an itemId, only
-- {type, tier, tags, equipSlot, ...}, so GetIcon(item.itemId) alone always came back "" for
-- them -- the root cause of drops rendering with no icon. Falls back to
-- ItemConfig.GENERATED_ITEM_ICONS[tier][kind], keyed by the weapon type (item.tags[1] -- the
-- only place ItemClass stashes it, since equipSlot is the generic "Weapon" for every weapon
-- type) or the armor slot (item.equipSlot, already slot-specific for armor).
function ItemDefinitions.GetIconForItem(item)
	if type(item) ~= "table" then
		return ""
	end

	if type(item.itemId) == "string" and item.itemId ~= "" then
		local icon = ItemDefinitions.GetIcon(item.itemId)
		if icon ~= "" then
			return icon
		end
	end

	local tier = math.clamp(math.floor(tonumber(item.tier) or 1), 1, 5)
	local tierIcons = ItemConfig.GENERATED_ITEM_ICONS[tier]
	if not tierIcons then
		return ""
	end

	local kind = nil
	if item.type == "Weapon" then
		kind = type(item.tags) == "table" and item.tags[1] or nil
	elseif item.type == "Armor" then
		if type(item.equipSlot) == "string" and tierIcons[item.equipSlot] then
			kind = item.equipSlot
		elseif type(item.tags) == "table" then
			for _, tag in ipairs(item.tags) do
				if tierIcons[tag] then
					kind = tag
					break
				end
			end
		end
	end

	if type(kind) ~= "string" then
		return ""
	end
	return tierIcons[kind] or ""
end

-- GetRarityForItem -- like GetIconForItem/GetDisplayNameForItem: procedurally generated items
-- always carry their own `rarity` (ItemGenerator/ItemClass stamp it onto the granted
-- template), but a catalog-granted item (an itemId-only owned record -- e.g. a dev-granted
-- AdminSword) may not have `rarity` copied onto the owned record depending on how
-- DungeonProfileService's grant-by-itemId path built it. Fall back to the catalog's own
-- Rarity field so the UI never silently renders a Legendary catalog item with a plain/white
-- border just because `item.rarity` itself came back nil.
function ItemDefinitions.GetRarityForItem(item)
	if type(item) ~= "table" then
		return nil
	end
	if type(item.rarity) == "string" and item.rarity ~= "" then
		return item.rarity
	end
	if type(item.itemId) == "string" and item.itemId ~= "" then
		local def = Items[item.itemId]
		if def and type(def.Rarity) == "string" then
			return def.Rarity
		end
	end
	return nil
end

-- GetDisplayNameForItem -- owned-item display name for UI (bag slot label, equip slot label,
-- tooltip title). Procedurally generated items always carry their own `name` (ItemGenerator
-- composes "<tier material> <kind>", e.g. "Wooden Sword"); catalog items fall back to their
-- DisplayName, then their raw itemId.
function ItemDefinitions.GetDisplayNameForItem(item)
	if type(item) ~= "table" then
		return "Item"
	end
	if type(item.name) == "string" and item.name ~= "" then
		return item.name
	end
	if type(item.itemId) == "string" and item.itemId ~= "" then
		local def = Items[item.itemId]
		if def and type(def.DisplayName) == "string" then
			return def.DisplayName
		end
		return item.itemId
	end
	return "Item"
end

return ItemDefinitions
