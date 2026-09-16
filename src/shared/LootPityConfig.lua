--[[
    LootPityConfig  -- ReplicatedStorage
    Score-driven, per-rarity pity. ONE dry-streak pool per player, shared by
    overworld kills and dungeon runs. Mythic is NOT part of this system.
]]
local LootPityConfig = {}

LootPityConfig.BASE_CHANCE = {
    -- TEMP TESTING: T1 Common raised from 1/64 to 1/5 so drops are visible
    -- immediately. Revert to 1/64 before this is anywhere near real balance.
    [1] = { Common = 1/5,   Uncommon = 1/128, Rare = 1/512,  Epic = 1/1536, Legendary = 1/3072 },
    [2] = { Common = 1/80,  Uncommon = 1/160, Rare = 1/640,  Epic = 1/1920, Legendary = 1/3840 },
    [3] = { Common = 1/96,  Uncommon = 1/192, Rare = 1/768,  Epic = 1/2304, Legendary = 1/4608 },
    [4] = { Common = 1/112, Uncommon = 1/224, Rare = 1/896,  Epic = 1/2688, Legendary = 1/5376 },
    [5] = { Common = 1/128, Uncommon = 1/256, Rare = 1/1024, Epic = 1/3072, Legendary = 1/6144 },
}

LootPityConfig.RARITIES = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }

-- p(streak) = base + (1-base) * PHI((streak - mu)/sigma),  mu = 1/base
-- sigma = mu/3.719 puts 99.99% at exactly 2x the mean streak.
LootPityConfig.PITY_FULL_MULT = 2.0
LootPityConfig.SIGMA_DIVISOR  = 3.719
LootPityConfig.CHANCE_CAP     = 0.9999

-- 1.0x -> 1 score. 1.1x -> 1 score, 10% chance of 2. 2.5x -> 2, 50% chance of 3.
LootPityConfig.DEFAULT_LOOT_BUFF   = 1.0
LootPityConfig.MAX_LOOT_BUFF       = 10.0
LootPityConfig.BASE_SCORE_PER_KILL = 1

LootPityConfig.DUNGEON_SCORE_MULTIPLIER = { [1]=3.0, [2]=3.0, [3]=3.5, [4]=4.0, [5]=4.5 }
LootPityConfig.DEATH_SCORE_RETENTION    = 1.0   -- dying costs nothing; key was already paid
LootPityConfig.LEAVE_SCORE_RETENTION    = 1.0

local function erf(x)
    local sign = x < 0 and -1 or 1
    x = math.abs(x)
    local a1,a2,a3,a4,a5,p = 0.254829592,-0.284496736,1.421413741,-1.453152027,1.061405429,0.3275911
    local t = 1.0 / (1.0 + p * x)
    local y = 1.0 - (((((a5*t + a4)*t) + a3)*t + a2)*t + a1) * t * math.exp(-x*x)
    return sign * y
end

function LootPityConfig.Phi(z)
    return 0.5 * (1.0 + erf(z / math.sqrt(2)))
end

function LootPityConfig.GetChance(tier, rarity, streak)
    local tbl = LootPityConfig.BASE_CHANCE[math.clamp(tier, 1, 5)]
    if not tbl then return 0 end
    local base = tbl[rarity]
    if not base or base <= 0 then return 0 end
    local mu    = 1 / base
    local sigma = mu / LootPityConfig.SIGMA_DIVISOR
    if sigma <= 0 then return base end
    local p = base + (1 - base) * LootPityConfig.Phi((streak - mu) / sigma)
    return math.clamp(p, 0, LootPityConfig.CHANCE_CAP)
end

function LootPityConfig.RollScore(lootBuff)
    local buff = math.clamp(tonumber(lootBuff) or 1.0, 1.0, LootPityConfig.MAX_LOOT_BUFF)
    local whole = math.floor(buff)
    local frac  = buff - whole
    if frac > 0 and math.random() < frac then whole = whole + 1 end
    return math.max(whole, LootPityConfig.BASE_SCORE_PER_KILL)
end

return LootPityConfig
