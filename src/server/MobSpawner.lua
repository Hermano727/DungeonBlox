-- MobSpawner ModuleScript
-- OOP Metatable blueprint representing a specific spawn location/camp in the world

local MobSpawner = {}
MobSpawner.__index = MobSpawner

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MobClass = require(ServerScriptService:WaitForChild("MobClass"))
local MobData = require(ReplicatedStorage:WaitForChild("MobData"))

-- Constructor
function MobSpawner.new(location, mobId, cooldownTime, maxSpawns, activationRadius, zoneName, levelRange)
    local self = setmetatable({}, MobSpawner)

    self.Location = location
    self.MobID = mobId
    self.CooldownTime = cooldownTime
    self.MaxSpawns = maxSpawns
    self.ActivationRadius = activationRadius
    self.ZoneName = zoneName or "Default"

    -- Optional spawn level range: { minLevel = number, maxLevel = number }
    self.LevelRange = levelRange

    self.CurrentTimer = 0
    self.SpawnedMobs = {}
    self.IsEliteSpawn = false -- Set by pity system
    self.IsActive = false -- Tracks if any player is nearby

    return self
end

-- Tick method - called every frame by MobManager
function MobSpawner:Tick(deltaTime, players)
    -- Check 1: Limit Check
    local aliveMobCount = self:CountAliveMobs()
    if aliveMobCount >= self.MaxSpawns then
        return
    end

    -- Check 2: Timer Check
    if self.CurrentTimer > 0 then
        self.CurrentTimer = self.CurrentTimer - deltaTime
        return
    end

    -- Check 3: Distance Check - is any player nearby?
    local nearbyPlayer = self:FindNearestPlayer(players)
    if not nearbyPlayer then
        self.IsActive = false
        return
    end

    self.IsActive = true

    -- Respawn the whole group at once, capped at MaxSpawns
    local toSpawn = self.MaxSpawns - aliveMobCount
    for i = 1, toSpawn do
        self:SpawnMob()
    end
end

-- Count alive mobs in SpawnedMobs list
function MobSpawner:CountAliveMobs()
    local count = 0
    for i = #self.SpawnedMobs, 1, -1 do
        local mob = self.SpawnedMobs[i]
        if mob and mob:IsAlive() then
            count = count + 1
        else
            -- Remove dead mob references
            table.remove(self.SpawnedMobs, i)
        end
    end
    return count
end

-- Find nearest player within activation radius
function MobSpawner:FindNearestPlayer(players)
    local nearestPlayer = nil
    local nearestDistance = self.ActivationRadius

    for _, player in ipairs(players) do
        local character = player.Character
        if character then
            local hrp = character:FindFirstChild("HumanoidRootPart")
            local humanoid = character:FindFirstChildOfClass("Humanoid")

            if hrp and humanoid and humanoid.Health > 0 then
                local distance = (self.Location - hrp.Position).Magnitude
                if distance < nearestDistance then
                    nearestDistance = distance
                    nearestPlayer = player
                end
            end
        end
    end

    return nearestPlayer
end

-- Spawn a new mob
function MobSpawner:SpawnMob()
    -- Determine which mob to spawn (regular or elite)
    local mobIdToSpawn = self.MobID

    if self.IsEliteSpawn then
        -- Find elite variant for this mob
        local eliteId = self.MobID .. "Elite"
        local eliteStats = MobData.FindMobById(eliteId)

        if eliteStats then
            mobIdToSpawn = eliteId
        end

        self.IsEliteSpawn = false -- Reset after spawning
    end

    -- Compute spawn level
    local spawnLevel
    if self.LevelRange then
        local minLevel = tonumber(self.LevelRange.minLevel)
        local maxLevel = tonumber(self.LevelRange.maxLevel)

        if not minLevel then minLevel = 1 end
        if not maxLevel then maxLevel = minLevel end

        minLevel = math.floor(minLevel)
        maxLevel = math.floor(maxLevel)
        if maxLevel < minLevel then
            minLevel, maxLevel = maxLevel, minLevel
        end

        spawnLevel = math.random(minLevel, maxLevel)
    else
        -- fallback: use the base level from MobData for this specific mobIdToSpawn
        local baseStats = MobData.FindMobById(mobIdToSpawn)
        spawnLevel = baseStats and baseStats.Level or 1
    end

    -- Create the mob
    local mob = MobClass.new(mobIdToSpawn, self.Location, self, spawnLevel)

    if mob then
        table.insert(self.SpawnedMobs, mob)
        self.CurrentTimer = self.CooldownTime
        return mob
    end

    return nil
end

-- Called when a mob dies
function MobSpawner:OnMobDied(mob)
    -- Remove from SpawnedMobs list
    for i = #self.SpawnedMobs, 1, -1 do
        if self.SpawnedMobs[i] == mob then
            table.remove(self.SpawnedMobs, i)
            break
        end
    end
end

-- Force spawn an elite (called by pity system)
function MobSpawner:SetNextSpawnElite()
    self.IsEliteSpawn = true
end

-- Get spawn info for debugging
function MobSpawner:GetInfo()
    return {
        Location = self.Location,
        MobID = self.MobID,
        ZoneName = self.ZoneName,
        AliveCount = self:CountAliveMobs(),
        IsActive = self.IsActive,
        TimerRemaining = self.CurrentTimer
    }
end

return MobSpawner
