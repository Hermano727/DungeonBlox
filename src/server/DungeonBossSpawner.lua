--[[
    DungeonBossSpawner  -- ServerScriptService
    Subclass of MobSpawner for single-boss encounters.

    Deliberately DELEGATES to MobSpawner:SpawnMob rather than reimplementing
    it -- the base already handles level ranges, forced-mob overrides, elite
    variants and ActiveMobs bookkeeping. This subclass only changes:
      * MaxSpawns is pinned to 1 (no group, no scatter)
      * _findSpawnPosition returns the fixed floor anchor
      * NextForcedSpawnPosition is set to the CEILING anchor before each
        spawn, so the boss materialises up there
      * after spawn, the ceiling-latch intro is kicked off

    Construct via DungeonBossSpawner.new(floorPosition, mobId, opts):
      opts = { ceilingPosition, activationRadius, respawnDelay, zoneName, level }
]]
local ServerScriptService = game:GetService("ServerScriptService")
local MobSpawner = require(ServerScriptService:WaitForChild("MobSpawner"))

local DungeonBossSpawner = setmetatable({}, { __index = MobSpawner })
DungeonBossSpawner.__index = DungeonBossSpawner

function DungeonBossSpawner.new(floorPosition, mobId, opts)
    opts = opts or {}
    local level = opts.level
    local self = MobSpawner.new(
        floorPosition,
        mobId,
        opts.respawnDelay or 30,
        1,                                   -- exactly one boss
        opts.activationRadius or 200,
        opts.zoneName or "T1Dungeon",
        level and { minLevel = level, maxLevel = level } or nil
    )
    setmetatable(self, DungeonBossSpawner)

    self.FloorPosition   = floorPosition
    self.CeilingPosition = opts.ceilingPosition
    self.IsBossSpawner   = true
    return self
end

-- Never scatter: the spawn footprint IS the floor anchor.
function DungeonBossSpawner:_findSpawnPosition()
    return self.FloorPosition
end

function DungeonBossSpawner:SpawnMob()
    if self:CountAliveMobs() >= 1 then
        return nil
    end

    -- Materialise at the ceiling; the intro drops it to the floor.
    if self.CeilingPosition then
        self.NextForcedSpawnPosition = self.CeilingPosition
    end

    local mob = MobSpawner.SpawnMob(self)
    if not mob then return nil end

    if self.CeilingPosition and mob.BeginCeilingIntro then
        mob:BeginCeilingIntro(self.CeilingPosition, self.FloorPosition)
    end

    return mob
end

return DungeonBossSpawner
