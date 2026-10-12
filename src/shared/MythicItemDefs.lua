--[[
    MythicItemDefs  -- ReplicatedStorage
    Mythic sits ABOVE Legendary. Elite / boss only. Flat drop chance, NO pity,
    never in TIER_RARITY_WEIGHTS. Each mythic is hand-authored.
]]
local MythicItemDefs = {}

MythicItemDefs.RARITY_NAME  = "Mythic"
MythicItemDefs.RARITY_COLOR = Color3.fromRGB(255, 85, 0)  -- deep red-orange

--[[
    Item fields:
        DisplayName, Kind ("Weapon" | "Armor"), WeaponType / ArmorSlot
        SourceMobID     who drops it
        BaseStatsAs     { tier, rarity, level }: the base stats roll as an ordinary item of
                        that rarity (Kane's set rolls Rare hp / energy / armor / damage)
        SubStats        the guaranteed substats, nothing random on top:
                          { id = "critical", min = 3, max = 4 }   authored window
                          { id = "block", useStandardRoll = true } the registry's own roll for
                            this tier (ItemConfig ranges; str/vit/int/dex use ARMOR_SUBSTAT_RANGE
                            x the BaseStatsAs rarity's multiplier)

    Who drops a Mythic and how: dungeon bosses through DropTable below (DungeonBossLootService,
    straight to inventory); named elites through RS/NamedEliteLootDefs entries with a `Mythic`
    key (a flat chance per piece, world loot for the killer). Either way MythicItemBuilder builds it.
]]
MythicItemDefs.Items = {
    -- Kane the Enraged's set (named elite, T1 overworld; dropped via NamedEliteLootDefs.Drops.Kane).
    KaneForsakenWaraxe = {
        DisplayName = "Kane's Forsaken Waraxe",
        Kind        = "Weapon",
        WeaponType  = "Axe",
        SourceMobID = "Kane",
        BaseStatsAs = { tier = 1, rarity = "Rare", level = 12 },
        SubStats = {
            { id = "elemDmg",  min = 4, max = 6 }, -- the fire damage
            { id = "critical", min = 3, max = 4 },
            { id = "vsPly",    min = 5, max = 8 },
        },
    },
    KaneTatteredScarf = {
        DisplayName = "Kane's Tattered Scarf",
        Kind        = "Armor",
        ArmorSlot   = "Helm",
        SourceMobID = "Kane",
        BaseStatsAs = { tier = 1, rarity = "Rare", level = 12 },
        SubStats = {
            { id = "str",   useStandardRoll = true },
            { id = "vit",   useStandardRoll = true },
            { id = "block", useStandardRoll = true }, -- T1 3-4% (ItemConfig ARMOR_BONUS_EFFECTS)
        },
    },
    KaneBattlewornTunic = {
        DisplayName = "Kane's Battleworn Tunic",
        Kind        = "Armor",
        ArmorSlot   = "Chest",
        SourceMobID = "Kane",
        BaseStatsAs = { tier = 1, rarity = "Rare", level = 12 },
        SubStats = {
            { id = "str",   useStandardRoll = true },
            { id = "vit",   useStandardRoll = true },
            { id = "block", useStandardRoll = true },
        },
    },
    KaneRaiderTrousers = {
        DisplayName = "Kane's Raider Trousers",
        Kind        = "Armor",
        ArmorSlot   = "Legs",
        SourceMobID = "Kane",
        BaseStatsAs = { tier = 1, rarity = "Rare", level = 12 },
        SubStats = {
            { id = "str",   useStandardRoll = true },
            { id = "vit",   useStandardRoll = true },
            { id = "block", useStandardRoll = true },
        },
    },
    KaneWarTornBoots = {
        DisplayName = "Kane's War-torn Boots",
        Kind        = "Armor",
        ArmorSlot   = "Boots",
        SourceMobID = "Kane",
        BaseStatsAs = { tier = 1, rarity = "Rare", level = 12 },
        SubStats = {
            { id = "str",   useStandardRoll = true },
            { id = "vit",   useStandardRoll = true },
            { id = "block", useStandardRoll = true },
        },
    },
    KaneSplinteredBulwark = {
        DisplayName = "Kane's Splintered Bulwark",
        Kind        = "Armor",
        ArmorSlot   = "Shield", -- base stats roll as a Rare shield (hp, hp/s, damage reduction)
        SourceMobID = "Kane",
        BaseStatsAs = { tier = 1, rarity = "Rare", level = 12 },
        SubStats = {
            { id = "str",   useStandardRoll = true },
            { id = "vit",   useStandardRoll = true },
            { id = "block", useStandardRoll = true },
        },
    },

    MiasmaBlade = {
        DisplayName = "Miasma, the Devouring Tide",
        Kind        = "Weapon",
        WeaponType  = "Sword",
        SourceMobID = "MiasmaBoss",
        BaseStatsAs = { tier = 1, rarity = "Legendary", level = 21 },
        SubStats = {
            -- no flat "pure damage" effect exists; elemDmg is the closest
            { id = "elemDmg",   min = 6,  max = 8  },
            { id = "critical",  min = 10, max = 15 },
            { id = "lifesteal", min = 6,  max = 8  },
        },
    },
    MiasmaCarapace = {
        DisplayName = "Miasma Carapace",
        Kind        = "Armor",
        ArmorSlot   = "Chest",
        SourceMobID = "MiasmaBoss",
        BaseStatsAs = { tier = 1, rarity = "Legendary", level = 21 },
        SubStats = {
            { id = "dex", useStandardRoll = true },
            { id = "str", useStandardRoll = true },
        },
    },
}

MythicItemDefs.DropTable = {
    -- Per eligible party member, rolled at the kill. 0.10 for now (was 1.0 while the path was
    -- built). To test either outcome on demand: F8 Mythic tab, "Force win" / "Force loss"
    -- (DungeonClearConfig.MYTHIC_FORCE_ATTR, dev only).
    MiasmaBoss = { Chance = 0.10, Pool = { "MiasmaBlade", "MiasmaCarapace" } },
}

function MythicItemDefs.GetDropSpec(mobId) return MythicItemDefs.DropTable[mobId] end
function MythicItemDefs.GetItem(itemKey)   return MythicItemDefs.Items[itemKey] end

function MythicItemDefs.PickFromPool(mobId)
    local spec = MythicItemDefs.DropTable[mobId]
    if not spec or #spec.Pool == 0 then return nil end
    local key = spec.Pool[math.random(1, #spec.Pool)]
    return key, MythicItemDefs.Items[key]
end

return MythicItemDefs
