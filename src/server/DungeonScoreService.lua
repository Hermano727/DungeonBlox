--[[
    DungeonScoreService  -- ServerScriptService
    Dungeon kills BANK score; on run end the total plays through the SAME
    pity pools the overworld uses. Dying costs nothing.

    Wire-up:
      entry               -> StartRun(player, tier)
      kill inside dungeon -> AddKill(player, mob, contribution)
      clear/death/leave   -> EndRun(player, reason, position)
]]
local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PityConfig = require(ReplicatedStorage:WaitForChild("LootPityConfig"))
local Pity       = require(ServerScriptService:WaitForChild("LootPityService"))
local WorldLoot  = require(ServerScriptService:WaitForChild("WorldLootService"))

local DungeonScoreService = {}
local activeRuns = {}

function DungeonScoreService.StartRun(player, tier, runId, partySize)
    if not player then return end
    activeRuns[player.UserId] = {
        tier  = math.clamp(tonumber(tier) or 1, 1, 5),
        score = 0, kills = 0, coins = 0, xp = 0,
        runId = runId or tostring(os.time()),
        partySize = math.clamp(math.floor(tonumber(partySize) or 1), 1, 8),
    }
end

function DungeonScoreService.IsInRun(player)
    return player ~= nil and activeRuns[player.UserId] ~= nil
end

function DungeonScoreService.GetRun(player)
    return player and activeRuns[player.UserId] or nil
end

function DungeonScoreService.AddKill(player, mob, contribution)
    local run = player and activeRuns[player.UserId]
    if not run then return false end
    local share = tonumber(contribution) or 1
    if share < 0.5 and math.random() > share then return true, 0 end
    -- Dungeon score is a FLAT per-kill amount set by party size (see
    -- DungeonRunConfig), NOT the overworld's 1-per-kill. The loot buff still
    -- applies on top: it rolls its usual whole/fractional bonus and that
    -- bonus is added to the party rate.
    local RunConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("DungeonRunConfig"))
    local scaling = RunConfig.Get(run.partySize or 1)
    local flat = scaling.ScorePerKill

    -- loot buff contributes its bonus above 1 (e.g. 2.5x -> +1 or +2)
    local buffBonus = PityConfig.RollScore(Pity.GetLootBuff(player)) - 1
    local gained = flat + math.max(0, buffBonus)
    run.score = run.score + gained
    run.kills = run.kills + 1
    return true, gained
end

-- Coins and combat XP accumulate separately from loot score. They are NOT
-- score-driven: the amount per kill is whatever the overworld would have
-- given, banked instead of dropped/awarded.
--
-- Unlike loot score, these are FORFEIT on failure -- only a completed run
-- pays them out. See DungeonRunService.EndRunFor.
function DungeonScoreService.AddCoins(player, amount)
    local run = player and activeRuns[player.UserId]
    if not run then return false end
    run.coins = run.coins + math.max(0, math.floor(tonumber(amount) or 0))
    return true
end

function DungeonScoreService.AddXP(player, amount)
    local run = player and activeRuns[player.UserId]
    if not run then return false end
    run.xp = run.xp + math.max(0, math.floor(tonumber(amount) or 0))
    return true
end

function DungeonScoreService.EndRun(player, reason, dropPosition)
    local run = player and activeRuns[player.UserId]
    if not run then return nil end
    activeRuns[player.UserId] = nil

    local retention = 1.0
    if reason == "died" then retention = PityConfig.DEATH_SCORE_RETENTION
    elseif reason == "left" then retention = PityConfig.LEAVE_SCORE_RETENTION end

    local finalScore = math.floor(run.score * retention)
    local won   = Pity.ResolveScore(player, run.tier, finalScore)
    local items = Pity.GenerateItems(won, run.tier, run.tier * 5)

    if #items > 0 and dropPosition then
        for idx, item in ipairs(items) do
            pcall(function() WorldLoot.SpawnMobDrop(dropPosition, player.UserId, item, idx) end)
        end
    end

    -- Coins and XP pay out ONLY on completion. Dying or leaving forfeits them,
    -- even though the loot score itself survives (the key was already paid).
    -- The forfeited amounts are reported separately so the summary can show
    -- the penalty rather than silently omitting it.
    local completed = (reason == "cleared")

    return {
        reason     = reason,
        rawScore   = run.score,
        finalScore = finalScore,
        kills      = run.kills,
        rarities   = won,
        items      = items,
        coins      = completed and run.coins or 0,
        xp         = completed and run.xp or 0,
        coinsLost  = (not completed) and run.coins or 0,
        xpLost     = (not completed) and run.xp or 0,
    }
end

Players.PlayerRemoving:Connect(function(player)
    activeRuns[player.UserId] = nil
end)

return DungeonScoreService
