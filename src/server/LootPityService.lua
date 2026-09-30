--[[
    LootPityService  -- ServerScriptService

    Owns every player's per-rarity dry streaks and resolves score into drops.
    ONE POOL: overworld kills and dungeon runs feed the same streaks.
    Rarities are INDEPENDENT -- one score point rolls all five separately, so
    a single kill can award a Common and a Legendary at once. Winning resets
    only that rarity.

    PERSISTENCE: streaks live at profile.Progression.DryStreaks.
    DataSchema needs that field or streaks reset each session.
]]
local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PityConfig    = require(ReplicatedStorage:WaitForChild("LootPityConfig"))
local ItemGenerator = require(ServerScriptService:WaitForChild("ItemGenerator"))

local LootPityService = {}

local PlayerDataManager
local function pdm()
    if not PlayerDataManager then
        PlayerDataManager = require(ServerScriptService:WaitForChild("PlayerDataManager"))
    end
    return PlayerDataManager
end

local function getProgression(player)
    local profile = pdm().Get(player)
    if not profile then return nil end
    profile.Progression = profile.Progression or {}
    local p = profile.Progression
    if type(p.DryStreaks) ~= "table" then p.DryStreaks = {} end
    for _, r in ipairs(PityConfig.RARITIES) do
        p.DryStreaks[r] = tonumber(p.DryStreaks[r]) or 0
    end
    return p
end

function LootPityService.GetStreaks(player)
    local p = getProgression(player)
    if not p then return nil end
    local out = {}
    for _, r in ipairs(PityConfig.RARITIES) do out[r] = p.DryStreaks[r] end
    return out
end

function LootPityService.GetLootBuff(player)
    local profile = pdm().Get(player)
    if not profile then return PityConfig.DEFAULT_LOOT_BUFF end
    profile.Progression = profile.Progression or {}
    return tonumber(profile.Progression.LootBuff) or PityConfig.DEFAULT_LOOT_BUFF
end

function LootPityService.SetLootBuff(player, value)
    local profile = pdm().Get(player)
    if not profile then return false end
    profile.Progression = profile.Progression or {}
    profile.Progression.LootBuff = math.clamp(tonumber(value) or 1.0, 1.0, PityConfig.MAX_LOOT_BUFF)
    return true
end

function LootPityService.PreviewChances(player, tier)
    local p = getProgression(player)
    if not p then return nil end
    local out = {}
    for _, r in ipairs(PityConfig.RARITIES) do
        out[r] = { streak = p.DryStreaks[r], chance = PityConfig.GetChance(tier, r, p.DryStreaks[r]) }
    end
    return out
end

function LootPityService.ResolveScore(player, tier, score)
    local p = getProgression(player)
    if not p then return {} end
    tier  = math.clamp(tonumber(tier) or 1, 1, 5)
    score = math.floor(tonumber(score) or 0)
    if score <= 0 then return {} end

    local won = {}
    for _ = 1, score do
        for _, rarity in ipairs(PityConfig.RARITIES) do
            local streak = p.DryStreaks[rarity] + 1
            if math.random() < PityConfig.GetChance(tier, rarity, streak) then
                table.insert(won, rarity)
                p.DryStreaks[rarity] = 0
            else
                p.DryStreaks[rarity] = streak
            end
        end
    end
    return won
end

function LootPityService.GenerateItems(wonRarities, tier, level)
    local items = {}
    for _, rarity in ipairs(wonRarities or {}) do
        local ok, item = pcall(function()
            return ItemGenerator.generate({ tier = tier, rarity = rarity, level = level })
        end)
        if ok and item then table.insert(items, item)
        else warn("[LootPityService] generate failed for", rarity, item) end
    end
    return items
end

-- Returns items, plus the score this kill actually generated (0 when the
-- contribution gate rejects it). The score is a second return value rather
-- than something recorded here because this service persists to the LEGACY
-- PlayerDataManager profile -- the lifetime totals live on the modern
-- ProfileService profile, so LootService records them at the one call site
-- that sees both the overworld and dungeon paths.
function LootPityService.OnKill(player, mob, contribution)
    if not player or not mob then return {}, 0 end
    local share = tonumber(contribution) or 1
    if share < 0.5 and math.random() > share then return {}, 0 end
    local tier  = math.clamp(mob.Tier or 1, 1, 5)
    local score = PityConfig.RollScore(LootPityService.GetLootBuff(player))
    local won   = LootPityService.ResolveScore(player, tier, score)
    return LootPityService.GenerateItems(won, tier, mob.Stats and mob.Stats.Level), score
end

function LootPityService.DebugDump(player, tier)
    local prev = LootPityService.PreviewChances(player, tier or 1)
    if not prev then return "no profile" end
    local lines = { ("LootBuff %.2fx"):format(LootPityService.GetLootBuff(player)) }
    for _, r in ipairs(PityConfig.RARITIES) do
        table.insert(lines, ("  %-10s streak %-6d  %.4f%%"):format(r, prev[r].streak, prev[r].chance * 100))
    end
    return table.concat(lines, "\n")
end

return LootPityService
