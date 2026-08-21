-- MobSpawner ModuleScript
-- OOP Metatable blueprint representing a specific spawn location/camp in the world

local MobSpawner = {}
MobSpawner.__index = MobSpawner

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local SUMMON_RUNE_COLOR = Color3.fromRGB(168, 84, 255)

local MobClassRegistry = require(ServerScriptService:WaitForChild("MobClassRegistry"))
local MobData = require(ReplicatedStorage:WaitForChild("MobData"))

-- Factory: MobClassRegistry decides which MobClass subclass to instantiate
-- for a given MobID (see that module for the selection rules -- currently
-- the same JumpHeight-based heuristic this file used to hardcode). Adding a
-- future movement style is a registry entry there, not another branch here.
local function createMob(mobId, spawnPosition, spawnerRef, level)
    return MobClassRegistry.Create(mobId, spawnPosition, spawnerRef, level)
end

-- Spawn placement: scatter mobs in a group instead of stacking them on the
-- spawner's marker point, and ground-snap each one via raycast.
local SCATTER_RADIUS = 14        -- max horizontal studs from the spawner marker
local MIN_MOB_SEPARATION = 6     -- min studs between two mobs spawned by this spawner
local SCATTER_MAX_ATTEMPTS = 8
local GROUND_PROBE_UP = 50
local GROUND_PROBE_DOWN = 100

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
    self.NextForcedMobId = nil -- Optional exact MobID for next spawn
    self.NextForcedSpawnPosition = nil -- Optional exact world position override
    self.NextForcedRiseAnimation = false -- Optional spawn intro for elites
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

-- Pick a spawn point for one mob in this group: scattered within
-- SCATTER_RADIUS of the spawner marker and kept at least MIN_MOB_SEPARATION
-- studs from this spawner's other living mobs. Only the XZ footprint is
-- chosen here -- MobClass does the precise vertical ground-snap once it
-- knows the actual model's geometry, since the spawner marker itself is
-- often a flat trigger volume, not a reliable stand-height reference.
function MobSpawner:_findSpawnPosition()
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    local excludeInstances = {}
    for _, mob in ipairs(self.SpawnedMobs) do
        if mob.Model then
            table.insert(excludeInstances, mob.Model)
        end
    end
    rayParams.FilterDescendantsInstances = excludeInstances

    for _ = 1, SCATTER_MAX_ATTEMPTS do
        local angle = math.random() * math.pi * 2
        local dist = math.random() * SCATTER_RADIUS
        local candidate = self.Location + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)

        local tooClose = false
        for _, mob in ipairs(self.SpawnedMobs) do
            local otherPart = mob.Model and mob.Model.PrimaryPart
            if otherPart then
                local flat = Vector3.new(candidate.X - otherPart.Position.X, 0, candidate.Z - otherPart.Position.Z)
                if flat.Magnitude < MIN_MOB_SEPARATION then
                    tooClose = true
                    break
                end
            end
        end

        if not tooClose then
            -- Sanity check there is *some* surface nearby (not a void/cliff edge)
            -- before committing to this candidate.
            local hit = workspace:Raycast(
                candidate + Vector3.new(0, GROUND_PROBE_UP, 0),
                Vector3.new(0, -GROUND_PROBE_DOWN, 0),
                rayParams
            )
            if hit then
                return Vector3.new(candidate.X, self.Location.Y, candidate.Z)
            end
        end
    end

    -- No valid scattered spot found; the marker position is always safe.
    return self.Location
end

local function createSummonRune(targetPivot, feetOffset)
    local rune = Instance.new("Part")
    rune.Name = "EliteSummonRune"
    rune.Anchored = true
    rune.CanCollide = false
    rune.CanTouch = false
    rune.CanQuery = false
    rune.Material = Enum.Material.Neon
    rune.Color = SUMMON_RUNE_COLOR
    rune.Transparency = 0.25
    rune.Shape = Enum.PartType.Cylinder
    rune.Size = Vector3.new(0.12, 3.2, 3.2)
    local groundY = targetPivot.Position.Y - (tonumber(feetOffset) or 2)
    rune.CFrame = CFrame.new(targetPivot.Position.X, groundY + 0.08, targetPivot.Position.Z) * CFrame.Angles(0, 0, math.rad(90))
    rune.Parent = workspace

    local light = Instance.new("PointLight")
    light.Color = SUMMON_RUNE_COLOR
    light.Brightness = 1.6
    light.Range = 12
    light.Parent = rune

    local attachment = Instance.new("Attachment")
    attachment.Position = Vector3.new(0, 0.1, 0)
    attachment.Parent = rune

    local burst = Instance.new("ParticleEmitter")
    burst.Name = "EliteSummonBurst"
    burst.Texture = "rbxasset://textures/particles/sparkles_main.dds"
    burst.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(235, 200, 255)),
        ColorSequenceKeypoint.new(1, SUMMON_RUNE_COLOR)
    })
    burst.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.05),
        NumberSequenceKeypoint.new(0.7, 0.25),
        NumberSequenceKeypoint.new(1, 1)
    })
    burst.LightEmission = 0.8
    burst.LightInfluence = 0
    burst.Speed = NumberRange.new(4, 9)
    burst.Lifetime = NumberRange.new(0.35, 0.8)
    burst.Rate = 0
    burst.Rotation = NumberRange.new(0, 360)
    burst.RotSpeed = NumberRange.new(-140, 140)
    burst.SpreadAngle = Vector2.new(360, 30)
    burst.VelocitySpread = 180
    burst.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.45),
        NumberSequenceKeypoint.new(0.65, 0.22),
        NumberSequenceKeypoint.new(1, 0)
    })
    burst.Parent = attachment
    burst:Emit(36)

    local pulse = TweenService:Create(rune, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = Vector3.new(0.12, 6.2, 6.2),
        Transparency = 0.1,
    })
    pulse:Play()

    local glowOut = TweenService:Create(light, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Brightness = 0.6,
        Range = 8,
    })
    glowOut:Play()

    local cleaned = false
    local function cleanup()
        if cleaned then return end
        cleaned = true
        if rune and rune.Parent then
            local fade = TweenService:Create(rune, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                Transparency = 1,
                Size = Vector3.new(0.12, 1.6, 1.6),
            })
            fade:Play()
            local lightFade = TweenService:Create(light, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                Brightness = 0,
                Range = 0,
            })
            lightFade:Play()
            fade.Completed:Connect(function()
                if rune then rune:Destroy() end
            end)
        end
    end

    return cleanup
end

-- Spawn a new mob
function MobSpawner:SpawnMob()
    -- Determine which mob to spawn (forced > elite flag > regular)
    local mobIdToSpawn = self.MobID
    local forcedSpawnPosition = self.NextForcedSpawnPosition
    local shouldPlayRiseIntro = self.NextForcedRiseAnimation == true

    if type(self.NextForcedMobId) == "string" and self.NextForcedMobId ~= "" then
        local forcedStats = MobData.FindMobById(self.NextForcedMobId)
        if forcedStats then
            mobIdToSpawn = self.NextForcedMobId
        end
        self.NextForcedMobId = nil -- One-shot override
        self.IsEliteSpawn = false
    elseif self.IsEliteSpawn then
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
    local spawnPosition = (typeof(forcedSpawnPosition) == "Vector3") and forcedSpawnPosition or self:_findSpawnPosition()
    local mob = createMob(mobIdToSpawn, spawnPosition, self, spawnLevel)

    self.NextForcedSpawnPosition = nil
    self.NextForcedRiseAnimation = false
    
    if mob then
        table.insert(self.SpawnedMobs, mob)
        self.CurrentTimer = self.CooldownTime

        if shouldPlayRiseIntro and mob.Model and mob.Model.PrimaryPart then
            if mob.SetSpawnIntroState then
                mob:SetSpawnIntroState(true)
            end

            local targetPivot = mob.Model:GetPivot()
            local startPivot = targetPivot * CFrame.new(0, -6, 0)
            mob.Model:PivotTo(startPivot)
            local cleanupRune = nil
            local okRune, errRune = pcall(function()
                cleanupRune = createSummonRune(targetPivot, mob._feetToRootHeight)
            end)
            if not okRune then
                warn("[MobSpawner] createSummonRune failed:", errRune)
            end

            local anchoredState = {}
            for _, part in ipairs(mob.Model:GetDescendants()) do
                if part:IsA("BasePart") then
                    anchoredState[part] = part.Anchored
                    part.Anchored = true
                end
            end

            local riseValue = Instance.new("NumberValue")
            riseValue.Value = 0
            local riseConn
            riseConn = riseValue.Changed:Connect(function(alpha)
                if mob and mob.Model then
                    mob.Model:PivotTo(startPivot:Lerp(targetPivot, alpha))
                end
            end)
            local tween = TweenService:Create(riseValue, TweenInfo.new(0.85, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = 1 })
            tween:Play()
            tween.Completed:Connect(function()
                if riseConn then riseConn:Disconnect() end
                riseValue:Destroy()
                if mob and mob.Model then
                    mob.Model:PivotTo(targetPivot)
                    for _, part in ipairs(mob.Model:GetDescendants()) do
                        if part:IsA("BasePart") then
                            part.Anchored = anchoredState[part] == true
                        end
                    end
                    if mob.SetSpawnIntroState then
                        mob:SetSpawnIntroState(false)
                    end
                end
                if cleanupRune then cleanupRune() end
            end)
        end

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
    self.NextForcedMobId = nil
    self.NextForcedSpawnPosition = nil
    self.NextForcedRiseAnimation = false
end

function MobSpawner:SetNextSpawnMob(mobId, spawnPosition, riseFromGround)
    if type(mobId) ~= "string" or mobId == "" then
        return false
    end
    if not MobData.FindMobById(mobId) then
        return false
    end
    self.NextForcedMobId = mobId
    self.NextForcedSpawnPosition = (typeof(spawnPosition) == "Vector3") and spawnPosition or nil
    self.NextForcedRiseAnimation = (riseFromGround == true)
    self.IsEliteSpawn = false
    return true
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