-- MobManager Script
-- The "Game Master" Singleton
-- Only script running an active loop

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local MobClass    = require(ServerScriptService:WaitForChild("MobClass"))
local MobSpawner  = require(ServerScriptService:WaitForChild("MobSpawner"))
local MobData     = require(ReplicatedStorage:WaitForChild("MobData"))
local MobCombat   = require(ServerScriptService:WaitForChild("MobCombat"))
local LootService = require(ServerScriptService:WaitForChild("LootService"))
local DropperKeyService = require(ServerScriptService:WaitForChild("DropperKeyService"))
local DungeonProfile = require(ServerScriptService:WaitForChild("DungeonProfileService"))
local CombatStateService = require(ServerScriptService:WaitForChild("CombatStateService"))
local MountService = require(ServerScriptService:WaitForChild("MountService"))

local CombatRemote = ReplicatedStorage:WaitForChild("CombatRemote")
local CombatXPEvent = ReplicatedStorage:WaitForChild("CombatXPEvent")

-- Combat XP Configuration
local COMBAT_XP_PER_KILL = 5 -- XP gained per mob kill
local BASE_COMBAT_XP_REQUIREMENT = 5 -- XP needed for level 1 to 2

-- Configuration
local LEVEL_PENALTY_THRESHOLD = 5 -- Level difference for penalties
local DAMAGE_REDUCTION_PER_LEVEL = 0.1 -- 10% reduction per level over threshold
local XP_PENALTY_MULTIPLIER = 0.25 -- 75% XP reduction when over-leveled
local PITY_THRESHOLD = 100 -- Kills needed to spawn elite

-- State
local ActiveMobs = {} -- Dictionary: [UID] = MobObject
local ActiveSpawners = {} -- Array of SpawnerObjects
local ZonePity = {} -- Dictionary: [ZoneName] = killCount
local PendingEliteZones = {} -- Set of zone names waiting for elite spawn

-- ============================================
-- Spawner Management
-- ============================================

-- Register a spawner
local function RegisterSpawner(location, mobId, cooldownTime, maxSpawns, activationRadius, zoneName, levelRange)
    local spawner = MobSpawner.new(location, mobId, cooldownTime, maxSpawns, activationRadius, zoneName, levelRange)
    table.insert(ActiveSpawners, spawner)

    -- Initialize zone pity if not exists
    local zone = zoneName or "Default"
    if not ZonePity[zone] then
        ZonePity[zone] = 0
    end

    return spawner
end

-- ============================================
-- Combat System
-- ============================================

-- Check if kill should have XP penalty
local function ShouldApplyXPPenalty(player, mob)
    local playerLevel = player:GetAttribute("Level") or 1
    local mobLevel = mob.Stats.Level

    return (playerLevel - mobLevel) >= LEVEL_PENALTY_THRESHOLD
end

-- Handle combat remote event
local function OnCombatRequest(player, mobUID, hitPosition, weaponId)
    MobCombat.ApplyWeaponDamage(player, mobUID, weaponId, hitPosition)
    CombatStateService.OnPlayerDamaged(player)
    MountService.dismount(player)
end

-- ============================================
-- Death and Loot System
-- ============================================

-- Process mob death
function ProcessMobDeath(mob, killingBlowPlayer)
    local zone = mob.SpawnerRef and mob.SpawnerRef.ZoneName or "Default"

    -- Update pity counter
    ZonePity[zone] = ZonePity[zone] + 1

    -- Check if pity threshold reached
    if ZonePity[zone] >= PITY_THRESHOLD then
        ZonePity[zone] = 0
        PendingEliteZones[zone] = true
    end

    -- Calculate and distribute rewards
    local damageTracker = mob.DamageTracker
    local totalDamage = 0

    for playerId, damage in pairs(damageTracker) do
        totalDamage = totalDamage + damage
    end

    -- Distribute score based on damage contribution
    for playerId, damage in pairs(damageTracker) do
        local player = Players:GetPlayerByUserId(playerId)
        if player then
            local contribution = damage / totalDamage
            local baseScore = mob.Stats.BaseScore

            -- Apply XP penalty if over-leveled
            if ShouldApplyXPPenalty(player, mob) then
                baseScore = math.floor(baseScore * XP_PENALTY_MULTIPLIER)
            end

            local score = math.floor(baseScore * contribution)

            -- Award score (implement your own scoring system)
            local currentScore = player:GetAttribute("Score") or 0
            player:SetAttribute("Score", currentScore + score)

            -- Award combat XP (5 XP per mob kill)
            DungeonProfile.AddSkillXP(player, "combat", COMBAT_XP_PER_KILL)
            -- Keep HUD popup event
            CombatXPEvent:FireClient(player, COMBAT_XP_PER_KILL)
        end
    end

    -- Remove from ActiveMobs
    ActiveMobs[mob.UID] = nil

    -- Trigger loot drop for the killing blow player
    if killingBlowPlayer then
        task.spawn(LootService.onMobDied, mob, killingBlowPlayer)
        task.spawn(DropperKeyService.onMobDied, mob, killingBlowPlayer)
    end
end

-- ============================================
-- Pity System
-- ============================================

-- Check and apply elite spawns
local function ProcessPitySystem()
    for _, spawner in ipairs(ActiveSpawners) do
        local zone = spawner.ZoneName

        if PendingEliteZones[zone] then
            spawner:SetNextSpawnElite()
            PendingEliteZones[zone] = nil
        end
    end
end

-- ============================================
-- Heartbeat Loop
-- ============================================

local function OnHeartbeat(deltaTime)
    local players = Players:GetPlayers()

    -- Process pity system
    ProcessPitySystem()

    -- Tick all spawners
    for _, spawner in ipairs(ActiveSpawners) do
        spawner:Tick(deltaTime, players)

        -- Register newly spawned mobs
        for _, mob in ipairs(spawner.SpawnedMobs) do
            if not ActiveMobs[mob.UID] then
                ActiveMobs[mob.UID] = mob
            end
        end
    end

    -- Update AI for all active mobs
    for uid, mob in pairs(ActiveMobs) do
        if mob:IsAlive() then
            mob:UpdateAI(deltaTime, players, ActiveMobs)
        else
            ActiveMobs[uid] = nil
        end
    end
end

-- ============================================
-- Initialization
-- ============================================

-- Connect events
MobCombat.Initialize(ActiveMobs, ProcessMobDeath, {
    LevelPenaltyThreshold = LEVEL_PENALTY_THRESHOLD,
    DamageReductionPerLevel = DAMAGE_REDUCTION_PER_LEVEL,
})

RunService.Heartbeat:Connect(OnHeartbeat)
CombatRemote.OnServerEvent:Connect(OnCombatRequest)

-- ============================================
-- Spawner Setup API
-- ============================================

-- Expose function to create spawners (call from other scripts or command line)
_G.MobSystem = {
    CreateSpawner = RegisterSpawner,
    GetActiveMobs = function() return ActiveMobs end,
    GetActiveSpawners = function() return ActiveSpawners end,
    GetZonePity = function() return ZonePity end,
    ApplyWeaponDamage = MobCombat.ApplyWeaponDamage,
    ApplyWeaponDamageInRadius = MobCombat.ApplyWeaponDamageInRadius,
}

print("MobManager initialized. Use _G.MobSystem.CreateSpawner() to create spawners.")

-- Auto-create test spawner on game start
RegisterSpawner(Vector3.new(5, 30, 50), "PlainsSlime", 5, 3, 100, "Plains")
RegisterSpawner(Vector3.new(80, 5, -40), "Bandit", 10, 2, 95, "Plains")
print("Test spawner created at (0, 5, 0)")

-- F8 DevPlacer mob camps: persisted in DataStore (see ServerScriptService.MobDevSpawnStore)
do
	local mds = ServerScriptService:FindFirstChild("MobDevSpawnStore")
	if mds and mds:IsA("ModuleScript") then
		local ok, mod = pcall(require, mds)
		if ok and type(mod) == "table" and mod.applySavedSpawns then
			mod.applySavedSpawns(RegisterSpawner)
		elseif not ok then
			warn("[MobManager] MobDevSpawnStore require failed: ", mod)
		end
	end
end

-- Optional hand-authored spawns (ServerStorage.MobSpawnCodegen)
local codegen = ServerStorage:FindFirstChild("MobSpawnCodegen")
if codegen and codegen:IsA("ModuleScript") then
	local ok, run = pcall(require, codegen)
	if ok and type(run) == "function" then
		local ok2, err2 = pcall(run, RegisterSpawner)
		if not ok2 then
			warn("[MobManager] MobSpawnCodegen failed: ", err2)
		end
	elseif not ok then
		warn("[MobManager] MobSpawnCodegen require failed: ", run)
	end
end
