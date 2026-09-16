--[[
    ItemConfig
    All static tables for the item generation system.
    No logic here, just data. Safe to require from both server and client.

    Tier medians (used in level scaling formula):
      T1=10, T2=30, T3=50, T4=70, T5=90

    Scaling formula:
      stat = baseStat * (1 + (level - tierMedian) * 0.01)
      For level > 100: min floor = baseStat * (1 + (level - 100) * 0.05)

    HP/s rule: always exactly 0.5 * the HP roll for the same tier/rarity.
    Armor feeds DamageService.ComputeFinal which uses rawDamage*(100/(100+armor)),
    so Armor here is a flat rating, not a percentage.
]]

local ItemConfig = {}

ItemConfig.TIER_MEDIANS        = { 10, 30, 50, 70, 90 }
ItemConfig.MAX_SUBSTATS        = { 2, 3, 3, 4, 4 }
ItemConfig.RARITY_SUBSTAT_MULT = { Common=0.70, Uncommon=0.85, Rare=1.00, Epic=1.20, Legendary=1.45, Mythic=1.45 }
ItemConfig.WEAPON_MULTIPLIERS  = { Sword=1.00, Scythe=1.05, Axe=1.10, Mace=1.15, Bow=1.20 }
ItemConfig.WEAPON_TYPES        = { "Sword", "Scythe", "Axe", "Mace", "Bow" }
-- Procedural weapon drops clone these StarterPack Tool names from DungeonToolPrefabsArchive.
-- Scythe/Axe/Mace removed (2026-08): no icon art yet and WEAPON_TYPES_BY_TIER[1] already
-- restricts T1 drops to Sword/Bow only, so these three entries were pure dead config --
-- EquippedHotbar.ensureStarterWeaponDropPrefabs iterates every value in this map
-- unconditionally at boot, so having them here warned "StarterPack missing Tool for
-- weapon drop prefab: Axe Tool / Mace / scythe" on every server start even though nothing
-- live ever requested them. Re-add an entry here (and to WEAPON_TYPES_BY_TIER once a tier
-- unlocks it) when that weapon type actually gets art + a StarterPack prefab.
ItemConfig.WEAPON_DROP_PREFAB_BY_TYPE = {
	Sword = "TrainingSword",
	Bow = "WoodenBow",
}
ItemConfig.ARMOR_SLOTS         = { "Helm", "Chest", "Legs", "Boots", "Shield" }

------------------------------------------------------------------------
-- Weapon kind -> equip-panel slot. Every weapon kind shares the single
-- "Weapon" slot except Bow, which gets its own -- PlayerPreview.lua's 8-slot
-- layout, ProfileBootstrap's TRAINING_GEAR_FOR_SLOT, and
-- KeybindConfig.Keybinds.ToolSlot already all assume Bow is independent of
-- Weapon; this table (plus WEAPON_ID_KIND below) is what makes item
-- generation/granting agree with them. Add a new non-default-slot weapon
-- kind here, nowhere else -- both src/shared/Items/WeaponItem.lua (catalog
-- grants) and src/server/ItemClass.lua (procedural drops) read this same
-- table so the two item-creation paths can't drift apart again.
------------------------------------------------------------------------
ItemConfig.WEAPON_TYPE_EQUIP_SLOT = {
    Sword = "Weapon", Scythe = "Weapon", Axe = "Weapon", Mace = "Weapon", Bow = "Bow",
}

-- Catalog weapon entries (TrainingSword, TrainingBow, ...) don't carry an explicit weapon
-- "kind" field of their own -- only WeaponId (keys into WeaponData for combat stats).
-- This maps WeaponId -> kind string so a catalog grant can look up
-- WEAPON_TYPE_EQUIP_SLOT the same way a procedural drop does via its weaponType. Default
-- kind for any WeaponId not listed here is "Sword" -- correct for every catalog weapon
-- that exists today; only bow-family WeaponIds need an entry.
ItemConfig.WEAPON_ID_KIND = {
    WoodenBow = "Bow",
}

------------------------------------------------------------------------
-- ARMOR BASE STATS (spec values; apply to all slot types)
-- HP/s = floor(hp * 0.5) per spec; computed in ItemGenerator.
------------------------------------------------------------------------

ItemConfig.ARMOR_HP_RANGES = {
    [1] = { Common={45,51},    Uncommon={57,63},    Rare={69,75},    Epic={81,87},    Legendary={93,99}    },
    [2] = { Common={131,147},  Uncommon={163,179},  Rare={196,212},  Epic={228,244},  Legendary={260,276}  },
    [3] = { Common={355,395},  Uncommon={435,475},  Rare={516,556},  Epic={596,636},  Legendary={676,716}  },
    [4] = { Common={894,986},  Uncommon={1077,1169},Rare={1260,1352},Epic={1443,1535},Legendary={1626,1718}},
    [5] = { Common={2080,2268},Uncommon={2457,2645},Rare={2833,3021},Epic={3210,3398},Legendary={3586,3774}},
}

-- DMG Reduction rolls only on Shields (not on Helm/Chest/Legs/Boots).
ItemConfig.ARMOR_DMGRED_RANGES = {
    [1] = { Common={2,3},  Uncommon={2,3},  Rare={3,3},   Epic={3,3},   Legendary={3,4}  },
    [2] = { Common={3,4},  Uncommon={3,4},  Rare={4,5},   Epic={4,5},   Legendary={5,5}  },
    [3] = { Common={5,5},  Uncommon={5,5},  Rare={6,7},   Epic={6,7},   Legendary={7,8}  },
    [4] = { Common={6,8},  Uncommon={7,9},  Rare={7,9},   Epic={8,10},  Legendary={9,11} },
    [5] = { Common={9,11}, Uncommon={9,11}, Rare={10,12}, Epic={11,13}, Legendary={11,13}},
}

ItemConfig.ARMOR_ARMOR_RANGES = {
    [1] = { Common={3,4},   Uncommon={3,4},   Rare={4,5},   Epic={4,5},   Legendary={5,6}   },
    [2] = { Common={5,6},   Uncommon={5,6},   Rare={6,7},   Epic={6,7},   Legendary={7,8}   },
    [3] = { Common={7,8},   Uncommon={7,8},   Rare={9,10},  Epic={9,11},  Legendary={10,12} },
    [4] = { Common={9,12},  Uncommon={10,13}, Rare={11,14}, Epic={12,15}, Legendary={13,16} },
    [5] = { Common={13,16}, Uncommon={14,17}, Rare={15,18}, Epic={16,19}, Legendary={17,20} },
}

ItemConfig.ARMOR_ENERGY_RANGES = {
    [1] = { Common={2.81,3.00},Uncommon={3.00,3.19},Rare={3.19,3.38},Epic={3.38,3.56},Legendary={3.56,3.75} },
    [2] = { Common={3.75,3.94},Uncommon={3.94,4.13},Rare={4.13,4.31},Epic={4.31,4.50},Legendary={4.50,4.69} },
    [3] = { Common={4.69,4.88},Uncommon={4.88,5.06},Rare={5.06,5.25},Epic={5.25,5.44},Legendary={5.44,5.63} },
    [4] = { Common={5.63,5.81},Uncommon={5.81,6.00},Rare={6.00,6.19},Epic={6.19,6.38},Legendary={6.38,6.56} },
    [5] = { Common={6.56,6.75},Uncommon={6.75,6.94},Rare={6.94,7.13},Epic={7.13,7.31},Legendary={7.31,7.50} },
}

------------------------------------------------------------------------
-- WEAPON BASE DMG (Sword base; WEAPON_MULTIPLIERS applied per type)
-- { min={lo,hi}, max={lo,hi} } gives a rolled range e.g. "7-9"
------------------------------------------------------------------------

ItemConfig.WEAPON_DMG_RANGES = {
    [1] = {
        Common={min={7,8},max={8,9}},      Uncommon={min={9,10},max={10,11}},
        Rare={min={11,12},max={12,13}},    Epic={min={13,14},max={14,15}},
        Legendary={min={15,16},max={16,17}},
    },
    [2] = {
        Common={min={21,23},max={23,25}},  Uncommon={min={25,27},max={27,29}},
        Rare={min={29,31},max={31,33}},    Epic={min={33,34},max={34,36}},
        Legendary={min={36,38},max={38,40}},
    },
    [3] = {
        Common={min={50,54},max={54,58}},  Uncommon={min={58,62},max={62,66}},
        Rare={min={66,71},max={71,75}},    Epic={min={75,79},max={79,83}},
        Legendary={min={83,87},max={87,91}},
    },
    [4] = {
        Common={min={109,118},max={118,127}}, Uncommon={min={127,135},max={135,143}},
        Rare={min={143,152},max={152,161}},   Epic={min={161,169},max={169,177}},
        Legendary={min={177,186},max={186,195}},
    },
    [5] = {
        Common={min={227,242},max={242,259}}, Uncommon={min={259,274},max={274,289}},
        Rare={min={289,305},max={305,321}},   Epic={min={321,337},max={337,353}},
        Legendary={min={353,368},max={368,383}},
    },
}

------------------------------------------------------------------------
-- ARMOR SUBSTATS (VIT/STR/INT/DEX share one range per tier; weight=30)
------------------------------------------------------------------------

ItemConfig.ARMOR_SUBSTAT_RANGE = {
    [1]={175,200}, [2]={200,225}, [3]={225,250}, [4]={250,275}, [5]={275,300},
}

-- ARMOR_EFFECTS: the 4 weapon-damage stats. Only these roll on initial item generation.
-- Alteration Orb treats these as the "stat pool" (max 2 per item).
ItemConfig.ARMOR_EFFECTS = {
    { id="vit", label="VIT (Mace DMG)",   baseWeight=100 },
    { id="str", label="STR (Axe DMG)",    baseWeight=100 },
    { id="int", label="INT (Scythe DMG)", baseWeight=100 },
    { id="dex", label="DEX (Sword DMG)",  baseWeight=100 },
}

-- ARMOR_BONUS_EFFECTS: extra substats available only via Alteration Orb (not on initial rolls).
-- None have gameplay effects yet; listed here for future wiring.
ItemConfig.ARMOR_BONUS_EFFECTS = {
    { id="block",    label="Block",                baseWeight=100, valueType="pct",
      ranges={ {3,4},{3,4},{3,4},{4,5},{4,6} } },
    { id="reflect",  label="Reflect",              baseWeight=100, valueType="pct",
      ranges={ {3,4},{3,4},{3,4},{4,5},{4,6} } },
    { id="dodge",    label="Dodge",                baseWeight=100, valueType="pct",
      ranges={ {3,4},{3,4},{3,4},{4,5},{4,6} } },
    { id="coinFind", label="Coin Find",            baseWeight=100, valueType="pct",
      ranges={ {12,16},{12,16},{12,16},{12,16},{14,20} } },
    { id="elemRes",  label="Elemental Resistance", baseWeight=100, valueType="pct",
      ranges={ {15,25},{15,25},{15,25},{15,25},{15,25} } },
}

-- Armor substat roll chances (per slot, sequential)
-- Slot 1: 50% to roll any of the 4 stats (equal weights)
-- Slot 2: 25% to roll one of the 3 remaining stats
-- Hard cap: 2 substats total
ItemConfig.ARMOR_SUBSTAT_ROLL_CHANCE = { 0.50, 0.25 }
ItemConfig.ARMOR_SUBSTAT_DMG_PER_200 = 0.05  -- 5% damage per 200 stat
ItemConfig.ARMOR_SUBSTAT_WEAPON_MAP = { vit="Mace", str="Axe", int="Scythe", dex="Sword" }

------------------------------------------------------------------------
-- WEAPON SUBSTATS
-- meleeOnly=true  excluded from Bow pool
-- rangedOnly=true excluded from all melee pools
------------------------------------------------------------------------

ItemConfig.WEAPON_EFFECTS = {
    { id="vsMon",    label="vs. Monsters",  baseWeight=15, valueType="pct",
      ranges={ {5,8},{6,9},{7,10},{8,11},{9,12} } },
    { id="vsPly",    label="vs. Players",   baseWeight=15, valueType="pct",
      ranges={ {5,8},{6,9},{7,10},{8,11},{9,12} } },
    { id="accuracy", label="Accuracy",       baseWeight=10, valueType="pct",
      ranges={ {4,6},{5,8},{6,10},{8,12},{10,16} } },
    { id="critical", label="Critical Hit",   baseWeight=10, valueType="pct",
      ranges={ {2,3},{3,4},{4,6},{5,8},{6,10} } },
    { id="execute",  label="Execute",        baseWeight=10, valueType="pct",
      ranges={ {2,3},{3,4},{4,6},{5,8},{6,10} } },
    { id="cleave",   label="Cleave",         baseWeight=10, valueType="pct", meleeOnly=true,
      ranges={ {2,3},{3,4},{4,6},{5,8},{6,10} } },
    { id="crushing", label="Crushing",       baseWeight=10, valueType="pct", meleeOnly=true,
      ranges={ {2,3},{3,4},{4,6},{5,8},{6,10} } },
    { id="pierce",   label="Piercing",       baseWeight=10, valueType="pct",
      ranges={ {3,4},{4,6},{5,8},{6,10},{8,12} } },
    { id="shatter",  label="Shatter",        baseWeight=10, valueType="pct", meleeOnly=true,
      ranges={ {2,3},{3,4},{4,6},{5,8},{6,10} } },
    { id="elemDmg",  label="Elemental DMG",  baseWeight=20, valueType="flat",
      ranges={ {3,4},{6,8},{12,16},{24,32},{48,64} } },
    { id="lifesteal",label="Life Steal",     baseWeight=10, valueType="pct",
      ranges={ {8,12},{6,10},{5,8},{5,8},{5,8} } },
    { id="glowing",  label="Glowing",        baseWeight=20, valueType="flat", rangedOnly=true,
      ranges={ {15,30},{20,40},{25,50},{30,60},{35,70} } },
    { id="bleeding", label="Bleeding",       baseWeight=5,  valueType="flat",
      ranges={ {4,8},{4,8},{4,8},{4,8},{4,8} } },
    { id="blinding", label="Blinding",       baseWeight=15, valueType="pct", rangedOnly=true,
      ranges={ {3,5},{4,6},{5,8},{6,10},{8,12} } },
    { id="slowness", label="Slowness",       baseWeight=15, valueType="pct", rangedOnly=true,
      ranges={ {3,5},{4,6},{5,8},{6,10},{8,12} } },
}

ItemConfig.WEAPON_TYPE_WEIGHTS = {
    Sword  = { accuracy=2, execute=3, pierce=2,    crushing=0.5, shatter=0.5, cleave=0.5 },
    Scythe = { execute=2,  cleave=3,  lifesteal=2, crushing=0.5, shatter=0.5 },
    Axe    = { shatter=3,  lifesteal=2, crushing=2, execute=0.5, pierce=0.5,  cleave=0.5 },
    Mace   = { critical=3, crushing=3, shatter=2,  execute=0.5, pierce=0.5,  cleave=0.5 },
    Bow    = { accuracy=2, pierce=2,   bleeding=3 },
}

------------------------------------------------------------------------
-- Drop config
------------------------------------------------------------------------

-- Canonical rarity order (Common -> Legendary). Single source of truth for anything that
-- must iterate rarities in a fixed order -- ItemGenerator.rollRarity's deterministic roll,
-- and DevClient's Item Spawner tab (rarity cycle control).
ItemConfig.RARITY_ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }
ItemConfig.DEFAULT_RARITY_WEIGHTS  = { Common=45, Uncommon=27, Rare=16, Epic=9, Legendary=3 }
ItemConfig.TIER_DROP_CHANCE        = { [1]=0.18,[2]=0.28,[3]=0.40,[4]=0.55,[5]=0.72 }
ItemConfig.ELITE_DROP_CHANCE_BONUS = 0.25

-- Mob kill coin purse (wallet). Separate roll from gear drop above.
ItemConfig.MOB_COIN_DROP_CHANCE = 0.30
ItemConfig.MOB_COIN_RANGE_BY_TIER = {
	[1] = { 3, 8 },
	[2] = { 9, 18 },
	[3] = { 19, 38 },
	[4] = { 38, 76 },
	[5] = { 76, 152 },
}
ItemConfig.TIER_RARITY_WEIGHTS = {
    [1]={ Common=82.0, Uncommon=9.6, Rare=4.8, Epic=2.4, Legendary=1.2 },
    [2]={ Common=38, Uncommon=32, Rare=20, Epic=8,  Legendary=2  },
    [3]={ Common=25, Uncommon=30, Rare=28, Epic=13, Legendary=4  },
    [4]={ Common=12, Uncommon=23, Rare=32, Epic=25, Legendary=8  },
    [5]={ Common=5,  Uncommon=12, Rare=28, Epic=35, Legendary=20 },
}
ItemConfig.ELITE_RARITY_TIER_BOOST = 1

------------------------------------------------------------------------
-- Tier-scoped generation pools. Temporary restriction: Scythe/Axe/Mace have
-- no icon art yet, so T1 weapon drops are Sword/Bow only until that art
-- exists (reintroduce by just adding them back to WEAPON_TYPES_BY_TIER[1]).
-- Any tier without its own override here falls back to the full
-- WEAPON_TYPES/ARMOR_SLOTS pool.
------------------------------------------------------------------------

ItemConfig.WEAPON_TYPES_BY_TIER = {
    [1] = { "Sword", "Bow" },
}
ItemConfig.ARMOR_SLOTS_BY_TIER = {
    [1] = { "Helm", "Chest", "Legs", "Boots", "Shield" },
}

------------------------------------------------------------------------
-- Procedural + catalog item naming/icon architecture.
--
-- TIER_WEAPON_MATERIAL / TIER_ARMOR_MATERIAL give each tier a material
-- prefix (T1 = Wooden/Leather), matching the already-hand-authored T2-T5
-- catalog names (IronHelm/SteelHelm/RuneHelm/VoidHelm already exist).
-- WEAPON_KIND_LABEL / ARMOR_KIND_LABEL turn a weaponType/armorSlot into its
-- display word ("Chest" -> "Chestplate"). ItemGenerator composes
-- `material .. " " .. kindLabel` for procedural drop names; rarity is shown
-- separately via the item's border color + tooltip badge, not baked into
-- the name.
--
-- GENERATED_ITEM_ICONS is the single source of truth for which image asset
-- a given tier+kind uses. Both ItemDefinitions' hand-authored catalog
-- entries (Training*/Wooden*/Leather*) AND ItemDefinitions.GetIconForItem's
-- fallback for itemId-less mob-dropped items read from this ONE table, so a
-- training-gear icon and a mob-dropped icon of the same tier+kind can never
-- drift apart -- "no curve balls with potential drop -> asset mapping."
------------------------------------------------------------------------

ItemConfig.TIER_WEAPON_MATERIAL = { [1] = "Wooden", [2] = "Iron", [3] = "Steel", [4] = "Rune", [5] = "Void" }
ItemConfig.TIER_ARMOR_MATERIAL  = { [1] = "Leather", [2] = "Iron", [3] = "Steel", [4] = "Rune", [5] = "Void" }

ItemConfig.WEAPON_KIND_LABEL = { Sword = "Sword", Scythe = "Scythe", Axe = "Axe", Mace = "Mace", Bow = "Bow" }
ItemConfig.ARMOR_KIND_LABEL  = { Helm = "Helmet", Chest = "Chestplate", Legs = "Leggings", Boots = "Boots", Shield = "Shield" }

-- [tier][kind] -> rbxassetid. Weapon kinds keyed by a WEAPON_TYPES id (Sword/Bow/...);
-- armor kinds keyed by an ARMOR_SLOTS id (Helm/Chest/Legs/Boots/Shield).
ItemConfig.GENERATED_ITEM_ICONS = {
    [1] = {
        Sword  = "rbxassetid://107047939268385", -- better shade of brown (2026-09-12, per direct request)
        Bow    = "rbxassetid://82650715306940", -- better shade of brown (2026-09-12, per direct request)
        Helm   = "rbxassetid://84010311919153",
        Chest  = "rbxassetid://95963199323247",
        Legs   = "rbxassetid://128669788193929",
        Boots  = "rbxassetid://122126957029681",
        Shield = "rbxassetid://112340687099581",
    },
}

-- T1 profession tool icons (pickaxe/fishing rod). ItemGenerator never rolls these -- they're
-- catalog-only starter/drop tools -- so they live separate from GENERATED_ITEM_ICONS, but are
-- still one shared table so Training* and Wooden* always match.
ItemConfig.TOOL_ICONS = {
    Pickaxe    = "rbxassetid://87543815456373",
    FishingRod = "rbxassetid://96915159262223",
}

ItemConfig.ADMIN_SWORD_ICON = "rbxassetid://112375884547005"

return ItemConfig
