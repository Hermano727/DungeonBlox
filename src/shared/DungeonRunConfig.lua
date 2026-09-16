--[[
    DungeonRunConfig  -- ReplicatedStorage
    Party-size scaling for dungeon runs. Indexed by the number of players who
    entered the run (clamped 1..8).

      HPMult       : multiplier applied to every mob's MaxHP inside the run
      ScorePerKill : flat score banked per kill, BEFORE the loot buff

    Note the deliberate difficulty curve: a solo run is EASIER than baseline
    (0.8x HP) but pays the least score. Each extra player adds more HP than
    they add raw damage throughput, so bigger groups are harder per-head --
    the score payout is the compensation.
]]
local DungeonRunConfig = {}

DungeonRunConfig.PartyScaling = {
    [1] = { HPMult = 0.8, ScorePerKill = 2 },
    [2] = { HPMult = 1.1, ScorePerKill = 3 },
    [3] = { HPMult = 1.4, ScorePerKill = 4 },
    [4] = { HPMult = 1.7, ScorePerKill = 5 },
    [5] = { HPMult = 2.0, ScorePerKill = 6 },
    [6] = { HPMult = 2.3, ScorePerKill = 7 },
    [7] = { HPMult = 2.6, ScorePerKill = 8 },
    [8] = { HPMult = 2.9, ScorePerKill = 9 },
}

-- After the boss dies the run is OVER but players are not yanked out. They get
-- a grace window to loot the room, regroup and leave on their own terms via the
-- Leave button. When it expires they're teleported to hearthstone.
--
-- Remaining trash despawns at clear time -- the boss is already dead, and
-- leaving live mobs around during a victory lap is just annoying.
DungeonRunConfig.EXIT_WINDOW_SECONDS = 300   -- 5 minutes
DungeonRunConfig.EXIT_WARN_AT = { 60, 30, 10 }  -- client-side countdown emphasis

function DungeonRunConfig.Get(partySize)
    local n = math.clamp(math.floor(tonumber(partySize) or 1), 1, 8)
    return DungeonRunConfig.PartyScaling[n], n
end

return DungeonRunConfig
