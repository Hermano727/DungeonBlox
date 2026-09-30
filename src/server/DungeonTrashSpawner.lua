--[[
    DungeonTrashSpawner  -- ServerScriptService
    One-shot group spawner for dungeon trash mobs.

    Dungeon spawns are FLAT: the group spawns once when a player first comes
    into range, and never respawns. Clearing a room stays cleared. That is the
    whole difference from the overworld MobSpawner, which respawns on a timer.
]]
local ServerScriptService = game:GetService("ServerScriptService")
local MobSpawner = require(ServerScriptService:WaitForChild("MobSpawner"))

local DungeonTrashSpawner = setmetatable({}, { __index = MobSpawner })
DungeonTrashSpawner.__index = DungeonTrashSpawner

function DungeonTrashSpawner.new(location, mobId, count, opts)
    opts = opts or {}
    local self = MobSpawner.new(
        location, mobId,
        math.huge,                       -- cooldown: never re-arm
        count,
        opts.activationRadius or 250,
        opts.zoneName or "T1Dungeon",
        opts.level and { minLevel = opts.level, maxLevel = opts.level } or nil
    )
    setmetatable(self, DungeonTrashSpawner)
    self.HasSpawned = false
    self.IsDungeonTrash = true
    self.NeverDeaggro = true -- dungeon mobs chase for good (see MobClass.NeverDeaggro)
    return self
end

-- Spawn the whole group once, then go permanently inert.
function DungeonTrashSpawner:Tick(deltaTime, players)
    if self.HasSpawned then return end
    if not self:FindNearestPlayer(players) then return end

    self.HasSpawned = true
    for _ = 1, self.MaxSpawns do
        self:SpawnMob()
    end
    print(("[DungeonTrashSpawner] spawned %d x %s (one-shot)"):format(self.MaxSpawns, self.MobID))
end

return DungeonTrashSpawner
