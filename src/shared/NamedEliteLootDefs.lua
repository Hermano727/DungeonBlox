--[[
    NamedEliteLootDefs  -- ReplicatedStorage

    Signature gear for named elites (MobData IsNamedElite). Overworld, pity-fed,
    hand-authored -- NOT the dungeon Mythic system (MythicItemDefs), which is
    boss-only, sits above Legendary, and grants straight to inventory.

    A named elite's drops are:
      * a FLAT per-item chance on kill, no score and no pity (the pity is on the
        elite SPAWNING, not on its loot),
      * base stats generated at a real rarity, but always at the TOP of that
        rarity's range ("high roll <rarity> equivalent" -- see
        docs/named-elite-loot.md for the term),
      * substats fixed to authored ranges rather than rolled from the pool.

    CHANCE FORMULA
    --------------
    BASE_CHANCE_DENOMINATOR is the chance of a RARE-equivalent drop from an
    elite of that tier. Better gear is rarer, so the denominator is multiplied
    by RARITY_DENOMINATOR_MULT and rounded UP to a whole number:

        chance = 1 / ceil(BASE_CHANCE_DENOMINATOR[tier] * MULT[rarity])

    T1 worked through: Rare 1/32, Epic 1/ceil(41.6) = 1/42, Legendary
    1/ceil(54.4) = 1/55.

    Every pool entry rolls INDEPENDENTLY, so the number above really is "the
    chance to get that drop" -- an elite with five authored items is not
    splitting one roll five ways.
]]

local NamedEliteLootDefs = {}

-- Tier -> denominator for a Rare-equivalent drop.
NamedEliteLootDefs.BASE_CHANCE_DENOMINATOR = { 32, 64, 96, 128, 192 }

-- Applied to the denominator above, so a higher number is a RARER drop.
NamedEliteLootDefs.RARITY_DENOMINATOR_MULT = {
    Rare      = 1.0,
    Epic      = 1.3,
    Legendary = 1.7,
}

-- Returns chance (0..1) and the whole-number denominator behind it, so callers
-- and dev tools can print "1/42" rather than 0.0238.
function NamedEliteLootDefs.DropChance(tier, equivalentRarity)
    local base = NamedEliteLootDefs.BASE_CHANCE_DENOMINATOR[math.clamp(tonumber(tier) or 1, 1, 5)]
    local mult = NamedEliteLootDefs.RARITY_DENOMINATOR_MULT[equivalentRarity] or 1.0
    local denominator = math.ceil(base * mult)
    if denominator < 1 then denominator = 1 end
    return 1 / denominator, denominator
end

--[[
    Drops[MobID] = {
        Tier, Level          -- what the gear generates as (the elite's own level)
        OneDrop              optional { EquivalentRarity }: ONE roll per kill at that DropChance,
                             a hit drops exactly ONE entry picked by its Weight (default 1), so
                             never two pieces from one kill. Without it each entry rolls its
                             own DropChance independently.
        Pool = { entry, ... }

    entry fields:
        Key                  unique id for logs/debugging (and the item's provenance stamp)
        Mythic               optional: a RS/MythicItemDefs key. The piece is then a Mythic built
                             by MythicItemBuilder from that def (its BaseStatsAs and guaranteed
                             SubStats); only Key (+ Weight / EquivalentRarity for the drop) is
                             read here. Kane's set works this way.
        Weight               OneDrop only: relative pick weight (default 1)
        DisplayName          optional; overrides the generated name
        Kind                 "Weapon" | "Armor"
        WeaponType/ArmorSlot passed straight to ItemGenerator
        EquivalentRarity     "Rare" | "Epic" | "Legendary" -- drives BOTH the
                             base-stat range and the drop chance
        SubStats             authored list, replacing the random roll:
                               { id = "critical", min = 6, max = 9 }
                               { id = "str", highRollStandard = true }
                             highRollStandard takes the top of that substat's
                             own standard roll for this tier/rarity instead of a
                             hand-written range (used for str/vit, whose values
                             come from ARMOR_SUBSTAT_RANGE, not a per-effect one).
]]
NamedEliteLootDefs.Drops = {
    Kane = {
        Tier  = 1,
        Level = 12, -- Kane's own level; base stats scale off it as usual
        -- Kane's Mythic set (2026-10-09), built from RS/MythicItemDefs: Rare base stats; the waraxe
        -- guarantees fire damage 4-6, critical 3-4, vs. Players 5-8; the armour and the shield
        -- guarantee str + vit + block (T1 3-4%).
        -- ONE roll per kill at the Rare-equivalent chance (T1 1/32); a hit drops exactly one piece:
        -- the waraxe 1/3 (weight 5 of 15), one of the five armour pieces 2/3 (weight 2 each).
        OneDrop = { EquivalentRarity = "Rare" },
        Pool = {
            { Key = "KaneForsakenWaraxe",    Mythic = "KaneForsakenWaraxe",    Weight = 5 },
            { Key = "KaneTatteredScarf",     Mythic = "KaneTatteredScarf",     Weight = 2 },
            { Key = "KaneBattlewornTunic",   Mythic = "KaneBattlewornTunic",   Weight = 2 },
            { Key = "KaneRaiderTrousers",    Mythic = "KaneRaiderTrousers",    Weight = 2 },
            { Key = "KaneWarTornBoots",      Mythic = "KaneWarTornBoots",      Weight = 2 },
            { Key = "KaneSplinteredBulwark", Mythic = "KaneSplinteredBulwark", Weight = 2 },
        },
    },
}

-- Pieces that no longer drop but may still sit in inventories: their provenance key (origin.d)
-- must keep resolving to the authored substat windows they rolled in, or a substat rebalance
-- (ItemStatRanges) would clamp them to the generic tier window. Kane's first set (high-roll Rare,
-- replaced by his Mythic set 2026-10-09).
NamedEliteLootDefs.Retired = {
    KaneAxe   = { SubStats = { { id = "critical", min = 6, max = 9 }, { id = "elemDmg", min = 3, max = 5 }, { id = "vsMon", min = 5, max = 8 } } },
    KaneHelm  = { SubStats = { { id = "str", highRollStandard = true }, { id = "vit", highRollStandard = true }, { id = "block", min = 2, max = 4 } } },
    KaneChest = { SubStats = { { id = "str", highRollStandard = true }, { id = "vit", highRollStandard = true }, { id = "block", min = 2, max = 4 } } },
    KaneLegs  = { SubStats = { { id = "str", highRollStandard = true }, { id = "vit", highRollStandard = true }, { id = "block", min = 2, max = 4 } } },
    KaneBoots = { SubStats = { { id = "str", highRollStandard = true }, { id = "vit", highRollStandard = true }, { id = "block", min = 2, max = 4 } } },
}

function NamedEliteLootDefs.GetDrops(mobId)
    if type(mobId) ~= "string" then return nil end
    return NamedEliteLootDefs.Drops[mobId]
end

return NamedEliteLootDefs
