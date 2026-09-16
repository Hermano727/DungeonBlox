--[[
    MythicItemDefs  -- ReplicatedStorage
    Mythic sits ABOVE Legendary. Elite / boss only. Flat drop chance, NO pity,
    never in TIER_RARITY_WEIGHTS. Each mythic is hand-authored.
]]
local MythicItemDefs = {}

MythicItemDefs.RARITY_NAME  = "Mythic"
MythicItemDefs.RARITY_COLOR = Color3.fromRGB(255, 85, 0)  -- deep red-orange

MythicItemDefs.Items = {
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
    -- TEMP TESTING: 1.0 instead of 0.20 so the Mythic path is exercised every
    -- kill. Put this back to 0.20 before it means anything.
    MiasmaBoss = { Chance = 1.0, Pool = { "MiasmaBlade", "MiasmaCarapace" } },
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
