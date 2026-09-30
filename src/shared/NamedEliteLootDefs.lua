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
        Pool = { entry, ... } -- each rolls its own DropChance

    entry fields:
        Key                  unique id for logs/debugging
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
        Pool = {
            {
                Key              = "KaneAxe",
                DisplayName      = "Kane's Axe",
                Kind             = "Weapon",
                WeaponType       = "Axe",
                EquivalentRarity = "Rare",
                SubStats = {
                    { id = "critical", min = 6, max = 9 },
                    { id = "elemDmg",  min = 3, max = 5 }, -- the "fire damage" roll
                    { id = "vsMon",    min = 5, max = 8 },
                },
            },
            -- Armor: Helm/Chest/Legs/Boots only. Kane drops no shield, so no
            -- entry rolls dmgRed/HPs (those are shield-exclusive anyway).
            {
                Key              = "KaneHelm",
                DisplayName      = "Kane's Helm",
                Kind             = "Armor",
                ArmorSlot        = "Helm",
                EquivalentRarity = "Rare",
                SubStats = {
                    { id = "str",   highRollStandard = true },
                    { id = "vit",   highRollStandard = true },
                    { id = "block", min = 2, max = 4 },
                },
            },
            {
                Key              = "KaneChest",
                DisplayName      = "Kane's Chestplate",
                Kind             = "Armor",
                ArmorSlot        = "Chest",
                EquivalentRarity = "Rare",
                SubStats = {
                    { id = "str",   highRollStandard = true },
                    { id = "vit",   highRollStandard = true },
                    { id = "block", min = 2, max = 4 },
                },
            },
            {
                Key              = "KaneLegs",
                DisplayName      = "Kane's Greaves",
                Kind             = "Armor",
                ArmorSlot        = "Legs",
                EquivalentRarity = "Rare",
                SubStats = {
                    { id = "str",   highRollStandard = true },
                    { id = "vit",   highRollStandard = true },
                    { id = "block", min = 2, max = 4 },
                },
            },
            {
                Key              = "KaneBoots",
                DisplayName      = "Kane's Sabatons",
                Kind             = "Armor",
                ArmorSlot        = "Boots",
                EquivalentRarity = "Rare",
                SubStats = {
                    { id = "str",   highRollStandard = true },
                    { id = "vit",   highRollStandard = true },
                    { id = "block", min = 2, max = 4 },
                },
            },
        },
    },
}

function NamedEliteLootDefs.GetDrops(mobId)
    if type(mobId) ~= "string" then return nil end
    return NamedEliteLootDefs.Drops[mobId]
end

return NamedEliteLootDefs
