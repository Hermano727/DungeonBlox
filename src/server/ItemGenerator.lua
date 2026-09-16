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
        substatCount number  optional; force an exact substat count (clamped to what's
                              possible for the tier/kind). Random if nil.
        -- If neither weaponType nor armorSlot is given, picks randomly.
]]

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config    = require(ReplicatedStorage:WaitForChild("ItemConfig"))
local ItemClass = require(ServerScriptService:WaitForChild("ItemClass"))

local ItemGenerator = {}

-- MAX_SUBSTATS is keyed by RARITY (Common..Legendary), not by dungeon tier --
-- build the lookup once instead of indexing it with a tier number.
local RARITY_TO_SUBSTAT_INDEX = {}
for i, r in ipairs(Config.RARITY_ORDER) do
    RARITY_TO_SUBSTAT_INDEX[r] = i
end

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
    local order = Config.RARITY_ORDER
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

local function rollWeaponSubstats(tier, rarity, weaponType, count, forcedSubstat)
    local typeOverrides = Config.WEAPON_TYPE_WEIGHTS[weaponType] or {}
    local rarityMult    = Config.RARITY_SUBSTAT_MULT[rarity]
    local isMelee       = MELEE_TYPES[weaponType] == true
    local usedIds       = {}
    local results       = {}

    -- forcedSubstat (dev tool only): { id, value } -- reserves this exact
    -- substat/value first (skipping the normal weighted roll and rarity
    -- multiplier for it), then the loop below fills any remaining slots
    -- normally. Real mob-drop calls never pass this (nil).
    local remaining = count
    if forcedSubstat ~= nil and type(forcedSubstat.id) == "string" then
        local def = nil
        for _, effect in ipairs(Config.WEAPON_EFFECTS) do
            if effect.id == forcedSubstat.id then def = effect break end
        end
        if def ~= nil then
            usedIds[def.id] = true
            table.insert(results, {
                id        = def.id,
                label     = def.label,
                value     = math.max(0, math.floor(tonumber(forcedSubstat.value) or 0)),
                valueType = def.valueType,
            })
            remaining = count - 1
        end
    end

    for _ = 1, remaining do
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
local function rollArmorSubstats(tier, rarity, forceCount, forcedSubstat)
    local rarityMult = Config.RARITY_SUBSTAT_MULT[rarity]
    local range      = Config.ARMOR_SUBSTAT_RANGE[tier]
    local chances    = Config.ARMOR_SUBSTAT_ROLL_CHANCE
    local usedIds    = {}
    local results    = {}

    -- forceCount (dev tool only): skip the 50%/25% chance gates and always attempt exactly
    -- this many rolls, still capped at #chances (the hard 2-substat max) and by how many
    -- distinct ARMOR_EFFECTS exist. Real mob-drop calls never pass this (nil), so the
    -- original random chance-gated behavior is unchanged for them.
    local target = forceCount ~= nil and math.clamp(math.floor(forceCount), 0, #chances) or nil

    -- forcedSubstat (dev tool only): { id, value } -- reserves one slot with
    -- this exact value up front, same idea as rollWeaponSubstats.
    if forcedSubstat ~= nil and type(forcedSubstat.id) == "string" then
        local def = nil
        for _, effect in ipairs(Config.ARMOR_EFFECTS) do
            if effect.id == forcedSubstat.id then def = effect break end
        end
        if def ~= nil then
            usedIds[def.id] = true
            table.insert(results, {
                id        = def.id,
                label     = def.label,
                value     = math.max(0, math.floor(tonumber(forcedSubstat.value) or 0)),
                valueType = "flat",
            })
        end
    end

    for i = 1, #chances do
        if #results >= (target or #chances) then break end
        if target ~= nil then
            if i > target then break end
        elseif math.random() >= chances[i] then
            break
        end

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
            local pool = Config.WEAPON_TYPES_BY_TIER[tier] or Config.WEAPON_TYPES
            weaponType = pool[math.random(1, #pool)]
        else
            local pool = Config.ARMOR_SLOTS_BY_TIER[tier] or Config.ARMOR_SLOTS
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
        baseStats.armor  = randRange(arR[1], arR[2])
        -- HP/s and Energy/s are mutually exclusive by slot:
        --   Shields roll HP/s (half the HP roll) and never roll Energy/s.
        --   Helm/Chest/Legs/Boots roll Energy/s and never roll HP/s.
        if armorSlot == "Shield" then
            baseStats.hps = math.floor(scaledHp * 0.5)
        else
            baseStats.energy = math.floor(enRoll * 100 + 0.5) / 100  -- 2 decimal places
        end
        -- dmgRed is shield-exclusive; regular armor slots do not roll it
        if armorSlot == "Shield" then
            local drR = Config.ARMOR_DMGRED_RANGES[tier][rarity]
            baseStats.dmgRed = randRange(drR[1], drR[2])
        end
    end

    -- Dev tool override: force one specific substat id to an exact value
    -- (e.g. { id = "critical", value = 100 } for a guaranteed-crit test
    -- weapon). Real mob drops never pass this. Validated against the
    -- matching effect table so a bad/mismatched id is silently ignored
    -- rather than corrupting the roll.
    local forcedSubstat = nil
    if type(options.forceSubstat) == "table" and type(options.forceSubstat.id) == "string" and options.forceSubstat.id ~= "" then
        forcedSubstat = options.forceSubstat
    end

    local substats
    if isWeapon then
        -- Bug fix: this used to index MAX_SUBSTATS by dungeon TIER (1-5), which
        -- happens to also have 5 entries, so it silently capped every T1 item
        -- (including Legendaries) at MAX_SUBSTATS[1] == 2 instead of scaling
        -- with rarity like the table (and the "Legendary = 4 substats" spec)
        -- actually intends.
        local maxSubs  = Config.MAX_SUBSTATS[RARITY_TO_SUBSTAT_INDEX[rarity] or #Config.MAX_SUBSTATS]
        local subCount
        if options.substatCount ~= nil then
            -- Dev tool override: force an exact substat count (clamped to what's possible
            -- for this tier). Real mob drops never pass substatCount, so they keep rolling
            -- a random count exactly as before.
            subCount = math.clamp(math.floor(options.substatCount), 0, maxSubs)
        else
            subCount = math.random(1, maxSubs)
        end
        if forcedSubstat ~= nil then
            subCount = math.max(subCount, 1)
        end
        substats = rollWeaponSubstats(tier, rarity, weaponType, subCount, forcedSubstat)
    else
        local armorCount = options.substatCount
        if forcedSubstat ~= nil then
            armorCount = math.max(tonumber(armorCount) or 0, 1)
        end
        substats = rollArmorSubstats(tier, rarity, armorCount, forcedSubstat)
    end

    -- Build a human-readable name: "<tier material> <kind>", e.g. "Wooden Sword" /
    -- "Leather Chestplate" -- matches the same T1 wooden/leather assets the training gear
    -- catalog entries use (ItemConfig.GENERATED_ITEM_ICONS), and mirrors the already
    -- hand-authored T2-T5 catalog naming (IronHelm/SteelHelm/...). Rarity is intentionally
    -- NOT in the name anymore -- it's shown separately via the rarity border + tooltip badge.
    local material, kindLabel
    if isWeapon then
        material  = Config.TIER_WEAPON_MATERIAL[tier] or ("T" .. tostring(tier))
        kindLabel = Config.WEAPON_KIND_LABEL[weaponType] or weaponType
    else
        material  = Config.TIER_ARMOR_MATERIAL[tier] or ("T" .. tostring(tier))
        kindLabel = Config.ARMOR_KIND_LABEL[armorSlot] or armorSlot
    end
    local name = material .. " " .. kindLabel

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
