--[[
    ItemGenerator
    Factory that rolls a procedurally generated item and returns an ItemClass instance.

    Usage:
        local ItemGenerator = require(SSS.ItemGenerator)
        local item = ItemGenerator.generate({ tier=1, rarity="Rare", weaponType="Mace" })
        item:debugPrint()
        DungeonProfile.GrantItem(player, item:toGrantTemplate(), 1)

    generate() options:
        tier        number   1-5  (required)
        rarity      string   optional; random if nil
        level       number   optional; defaults to tier median
        weaponType  string   "Sword"|"Scythe"|"Axe"|"Mace"|"Bow"|nil
        armorSlot   string   "Helm"|"Chest"|"Legs"|"Boots"|nil
        -- If neither weaponType nor armorSlot is given, picks randomly.
]]

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config    = require(ReplicatedStorage:WaitForChild("ItemConfig"))
local ItemClass = require(ServerScriptService:WaitForChild("ItemClass"))

local ItemGenerator = {}

------------------------------------------------------------------------
-- scaleStat(baseStat, level, tierMedian)
--
-- Core scaling formula from spec:
--   result = baseStat * (1 + (level - tierMedian) * 0.01)
--
-- Level 100 example for T5 (median=90):
--   result = base * (1 + (100-90)*0.01) = base * 1.10  -- correct per spec
--
-- For level > 100, enforce a rising minimum floor:
--   floor = baseStat * (1 + (level-100) * 0.05)
-- This ensures high-level items can't roll worse than the floor.
------------------------------------------------------------------------
local function scaleStat(baseStat, level, tierMedian)
    local result = baseStat * (1 + (level - tierMedian) * 0.01)

    if level > 100 then
        local floor = baseStat * (1 + (level - 100) * 0.05)
        result = math.max(result, floor)
    end

    return math.floor(result)
end

------------------------------------------------------------------------
-- randRange(min, max) -- uniform integer roll
------------------------------------------------------------------------
local function randRange(lo, hi)
    if lo >= hi then return lo end
    return math.random(lo, hi)
end

------------------------------------------------------------------------
-- rollRarity()
-- Picks a rarity from DEFAULT_RARITY_WEIGHTS.
-- LootService can call generate() with an explicit rarity instead.
------------------------------------------------------------------------
local function rollRarity()
    local weights = Config.DEFAULT_RARITY_WEIGHTS
    local total   = 0
    for _, w in pairs(weights) do total = total + w end

    local roll = math.random() * total
    local cum  = 0
    -- Iterate in defined order so the roll is deterministic
    local order = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }
    for _, rarity in ipairs(order) do
        cum = cum + weights[rarity]
        if roll <= cum then return rarity end
    end
    return "Common"
end

------------------------------------------------------------------------
-- weightedPick(pool, typeOverrides)
--
-- pool: array of entries with { id, baseWeight, ... }
-- typeOverrides: dict { [id] = multiplier } -- from WEAPON_TYPE_WEIGHTS
--
-- Builds a cumulative weight table on the fly, then picks one entry.
-- The mace example from spec: if crushing.baseWeight=10 and Mace override=3,
-- the effective weight is 30. All other effects stay at their baseWeight.
------------------------------------------------------------------------
local function weightedPick(pool, typeOverrides)
    local overrides    = typeOverrides or {}
    local cumulative   = {}
    local totalWeight  = 0

    for _, entry in ipairs(pool) do
        local effective = entry.baseWeight * (overrides[entry.id] or 1)
        totalWeight = totalWeight + effective
        table.insert(cumulative, { entry = entry, cumWeight = totalWeight })
    end

    local roll = math.random() * totalWeight
    for _, bucket in ipairs(cumulative) do
        if roll <= bucket.cumWeight then
            return bucket.entry
        end
    end
    return cumulative[#cumulative].entry  -- float precision fallback
end

------------------------------------------------------------------------
-- rollWeaponSubstats(tier, rarity, weaponType, count)
-- Returns array of { id, label, value, valueType }.
-- No duplicates -- already-picked ids are excluded from subsequent rolls.
------------------------------------------------------------------------
local MELEE_TYPES = { Sword=true, Scythe=true, Axe=true, Mace=true }

local function rollWeaponSubstats(tier, rarity, weaponType, count)
    local typeOverrides = Config.WEAPON_TYPE_WEIGHTS[weaponType] or {}
    local rarityMult    = Config.RARITY_SUBSTAT_MULT[rarity]
    local isMelee       = MELEE_TYPES[weaponType] == true
    local usedIds       = {}
    local results       = {}

    for _ = 1, count do
        local available = {}
        for _, effect in ipairs(Config.WEAPON_EFFECTS) do
            if not usedIds[effect.id]
                and not (effect.meleeOnly  and not isMelee)
                and not (effect.rangedOnly and isMelee) then
                table.insert(available, effect)
            end
        end
        if #available == 0 then break end

        local effect = weightedPick(available, typeOverrides)
        usedIds[effect.id] = true

        -- Roll within the tier range, then apply rarity multiplier
        local range = effect.ranges[tier]
        local raw   = randRange(range[1], range[2])
        local val   = math.floor(raw * rarityMult)

        table.insert(results, {
            id        = effect.id,
            label     = effect.label,
            value     = val,
            valueType = effect.valueType,
        })
    end

    return results
end

------------------------------------------------------------------------
-- rollArmorSubstats(tier, rarity)
-- Sequential roll chances from ARMOR_SUBSTAT_ROLL_CHANCE: 50% then 25%.
-- Each successful roll picks uniformly from the remaining VIT/STR/INT/DEX pool.
-- Hard cap of 2 substats per armor piece.
------------------------------------------------------------------------
local function rollArmorSubstats(tier, rarity)
    local rarityMult = Config.RARITY_SUBSTAT_MULT[rarity]
    local range      = Config.ARMOR_SUBSTAT_RANGE[tier]
    local chances    = Config.ARMOR_SUBSTAT_ROLL_CHANCE
    local usedIds    = {}
    local results    = {}

    for i = 1, #chances do
        if math.random() >= chances[i] then break end

        local available = {}
        for _, effect in ipairs(Config.ARMOR_EFFECTS) do
            if not usedIds[effect.id] then table.insert(available, effect) end
        end
        if #available == 0 then break end

        local effect = available[math.random(1, #available)]
        usedIds[effect.id] = true
        local val = math.floor(randRange(range[1], range[2]) * rarityMult)

        table.insert(results, { id=effect.id, label=effect.label, value=val, valueType="flat" })
    end

    return results
end

------------------------------------------------------------------------
-- generate(options) -> ItemClass
------------------------------------------------------------------------
function ItemGenerator.generate(options)
    assert(type(options) == "table", "ItemGenerator.generate expects an options table")

    local tier = math.clamp(math.floor(options.tier or 1), 1, 5)
    local rarity = options.rarity or rollRarity()

    local tierMedian = Config.TIER_MEDIANS[tier]
    local level      = math.max(1, math.floor(options.level or tierMedian))

    -- Determine weapon type or armor slot
    local weaponType = options.weaponType
    local armorSlot  = options.armorSlot

    if not weaponType and not armorSlot then
        if math.random() < 0.5 then
            local pool = Config.WEAPON_TYPES
            weaponType = pool[math.random(1, #pool)]
        else
            local pool = Config.ARMOR_SLOTS
            armorSlot  = pool[math.random(1, #pool)]
        end
    end

    local isWeapon = weaponType ~= nil

    -- Roll base stats
    local baseStats = {}
    if isWeapon then
        local d      = Config.WEAPON_DMG_RANGES[tier][rarity]
        local rawMin = randRange(d.min[1], d.min[2])
        local rawMax = randRange(d.max[1], d.max[2])
        local lo = scaleStat(rawMin, level, tierMedian)
        local hi = scaleStat(rawMax, level, tierMedian)
        if lo > hi then lo, hi = hi, lo end
        baseStats.dmgMin     = lo
        baseStats.dmgMax     = hi
        baseStats._rawDmgMin = rawMin
        baseStats._rawDmgMax = rawMax
    else
        local hpR      = Config.ARMOR_HP_RANGES[tier][rarity]
        local arR      = Config.ARMOR_ARMOR_RANGES[tier][rarity]
        local enR      = Config.ARMOR_ENERGY_RANGES[tier][rarity]
        local rawHp    = randRange(hpR[1], hpR[2])
        local scaledHp = scaleStat(rawHp, level, tierMedian)
        baseStats._rawHp = rawHp
        local enRoll   = enR[1] + math.random() * (enR[2] - enR[1])
        baseStats.hp     = scaledHp
        baseStats.hps    = math.floor(scaledHp * 0.5)
        baseStats.armor  = randRange(arR[1], arR[2])
        baseStats.energy = math.floor(enRoll * 100 + 0.5) / 100  -- 2 decimal places
        -- dmgRed is shield-exclusive; regular armor slots do not roll it
        if armorSlot == "Shield" then
            local drR = Config.ARMOR_DMGRED_RANGES[tier][rarity]
            baseStats.dmgRed = randRange(drR[1], drR[2])
        end
    end

    local substats
    if isWeapon then
        local maxSubs  = Config.MAX_SUBSTATS[tier]
        local subCount = math.random(1, maxSubs)
        substats = rollWeaponSubstats(tier, rarity, weaponType, subCount)
    else
        substats = rollArmorSubstats(tier, rarity)
    end

    -- Build a human-readable name
    local kindLabel = weaponType or (armorSlot .. " Armor")
    local name = string.format("%s %s (T%d)", rarity, kindLabel, tier)

    return ItemClass.new({
        name       = name,
        itemType   = isWeapon and "Weapon" or "Armor",
        weaponType = weaponType,
        armorSlot  = armorSlot,
        rarity     = rarity,
        tier       = tier,
        level      = level,
        baseStats  = baseStats,
        substats   = substats,
    })
end

return ItemGenerator
