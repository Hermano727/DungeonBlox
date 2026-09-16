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
local DungeonProfile = require(ServerScriptService:WaitForChild("ProfileService"))
local CombatStateService = require(ServerScriptService:WaitForChild("CombatStateService"))
local MountService = require(ServerScriptService:WaitForChild("MountService"))
local PartyService = require(ServerScriptService:WaitForChild("PartyService"))
local ZoneService = require(ServerScriptService:WaitForChild("ZoneService"))

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
local ELITE_ZONE_BASE_CHANCE = 0.01
local ELITE_ZONE_KILL_BONUS = 0.01

-- State
local ActiveMobs = {} -- Dictionary: [UID] = MobObject
local ActiveSpawners = {} -- Array of SpawnerObjects
local ZonePity = {} -- Dictionary: [ZoneName] = killCount
local PendingEliteZones = {} -- Set of zone names waiting for elite spawn
local PlayerEliteZoneStacks = {} -- [userId] = { [zoneName] = killsSinceLastEliteSpawn }
local PlayerActiveEliteMob = {} -- [userId] = mob object currently tied to elite bar

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

local function getZoneEliteConfig(zoneName)
    for _, zone in ipairs(ZoneService.GetAllZones()) do
        if zone.name == zoneName then
            return zone
        end
    end
    return nil
end

local function getPlayerZoneStacks(userId)
    local stacks = PlayerEliteZoneStacks[userId]
    if not stacks then
        stacks = {}
        PlayerEliteZoneStacks[userId] = stacks
    end
    return stacks
end

local function setPlayerElitePityAttributes(player, zoneName, killsSinceLastElite)
    if not player then return end
    if type(zoneName) ~= "string" then zoneName = "" end
    killsSinceLastElite = math.max(0, math.floor(tonumber(killsSinceLastElite) or 0))
    local chancePercent = math.clamp(1 + killsSinceLastElite, 1, 100)
    player:SetAttribute("ElitePityZone", zoneName)
    player:SetAttribute("ElitePityKills", killsSinceLastElite)
    player:SetAttribute("ElitePityChance", chancePercent)
end

local function clearPlayerEliteHealthAttributes(player)
    if not player then return end
    player:SetAttribute("EliteActive", false)
    player:SetAttribute("EliteCurrentHealth", 0)
    player:SetAttribute("EliteMaxHealth", 0)
end

local function getFrontSpawnPosition(player, fallback)
    if not player or not player.Character then
        return fallback
    end
    local hrp = player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then
        return fallback
    end
    local look = hrp.CFrame.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    if flat.Magnitude < 0.001 then
        flat = Vector3.new(0, 0, -1)
    else
        flat = flat.Unit
    end
    return hrp.Position + (flat * 9)
end

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

    -- Elite-zone progression: each player gets an increasing chance while
    -- killing mobs in their CURRENT elite zone. This keeps server logic and
    -- UI bar tracking keyed to the same zone name.
    if killingBlowPlayer and mob.SpawnerRef then
        local activeEliteZoneName = killingBlowPlayer:GetAttribute("CurrentEliteZone")
        if type(activeEliteZoneName) ~= "string" or activeEliteZoneName == "" then
            activeEliteZoneName = zone
        end

        local zoneConfig = getZoneEliteConfig(activeEliteZoneName)
        if zoneConfig and zoneConfig.isEliteZone and type(zoneConfig.eliteMobId) == "string" and zoneConfig.eliteMobId ~= "" then
            local userId = killingBlowPlayer.UserId
            local zoneStacks = getPlayerZoneStacks(userId)
            local killsSinceLastElite = zoneStacks[activeEliteZoneName] or 0
            local chance = math.clamp(ELITE_ZONE_BASE_CHANCE + (killsSinceLastElite * ELITE_ZONE_KILL_BONUS), 0, 1)

            if math.random() < chance then
                local forcedSpawnPos = getFrontSpawnPosition(killingBlowPlayer, mob.SpawnerRef.Location)
                local queued = mob.SpawnerRef:SetNextSpawnMob(zoneConfig.eliteMobId, forcedSpawnPos, true)
                if queued then
                    -- Spawn immediately so players always see the rise animation
                    -- at the captured kill-time position, independent of range checks.
                    local spawnedElite = mob.SpawnerRef:SpawnMob()
                    if spawnedElite then
                        PlayerActiveEliteMob[userId] = spawnedElite
                    end
                    zoneStacks[activeEliteZoneName] = 0
                else
                    zoneStacks[activeEliteZoneName] = killsSinceLastElite + 1
                end
            else
                zoneStacks[activeEliteZoneName] = killsSinceLastElite + 1
            end
            setPlayerElitePityAttributes(killingBlowPlayer, activeEliteZoneName, zoneStacks[activeEliteZoneName])
        end
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
            
            -- Award combat XP (5 XP per mob kill).
            -- Inside a dungeon this BANKS instead: XP is only paid out on a
            -- completed run and forfeited on failure. Note this is the LIVE
            -- xp path -- DamageService.AwardKill also fires CombatXPEvent but
            -- with a (mobId, score, tier) signature the client misreads, so it
            -- contributes nothing.
            local xpGain = COMBAT_XP_PER_KILL
            local xpBanked = false
            do
                local okX, DungeonScore = pcall(function()
                    return require(ServerScriptService:WaitForChild("DungeonScoreService", 5))
                end)
                if okX and DungeonScore and DungeonScore.IsInRun(player) then
                    DungeonScore.AddXP(player, xpGain)
                    xpBanked = true
                end
            end

            if not xpBanked then
                DungeonProfile.AddSkillXP(player, "combat", xpGain)
                CombatXPEvent:FireClient(player, xpGain)
            end
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

    for _, player in ipairs(players) do
        local eliteZoneName = player:GetAttribute("CurrentEliteZone")
        if type(eliteZoneName) ~= "string" then
            eliteZoneName = ""
        end
        local activeEliteMob = PlayerActiveEliteMob[player.UserId]
        if activeEliteMob and activeEliteMob.IsAlive and activeEliteMob:IsAlive() then
            player:SetAttribute("EliteActive", true)
            player:SetAttribute("EliteCurrentHealth", activeEliteMob.CurrentHealth or 0)
            player:SetAttribute("EliteMaxHealth", activeEliteMob.MaxHealth or 0)
            -- Overwrite (not just read) CurrentEliteMobId with the REAL active
            -- mob's id while it's alive -- ZoneService only ever sets this to
            -- "whichever elite THIS ZONE is configured to spawn", which is
            -- wrong once a specific mob (e.g. a dev-tool force-spawn, see
            -- ForceSpawnNamedElite below) is actually up. HealthClient (and
            -- the top-middle boss bar) resolve the elite's display Name from
            -- this attribute via MobData.FindMobById, so it must reflect the
            -- real spawned mob, not just the zone's configured slot.
            player:SetAttribute("CurrentEliteMobId", activeEliteMob.MobID)
        else
            PlayerActiveEliteMob[player.UserId] = nil
            clearPlayerEliteHealthAttributes(player)
        end

        if eliteZoneName ~= "" then
            local stacks = getPlayerZoneStacks(player.UserId)
            setPlayerElitePityAttributes(player, eliteZoneName, stacks[eliteZoneName] or 0)
        else
            player:SetAttribute("ElitePityZone", "")
            player:SetAttribute("ElitePityKills", 0)
            player:SetAttribute("ElitePityChance", 1)
        end
    end
    
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
Players.PlayerRemoving:Connect(function(player)
    PlayerEliteZoneStacks[player.UserId] = nil
    PlayerActiveEliteMob[player.UserId] = nil
    player:SetAttribute("ElitePityZone", "")
    player:SetAttribute("ElitePityKills", 0)
    player:SetAttribute("ElitePityChance", 1)
    clearPlayerEliteHealthAttributes(player)
end)

-- ============================================
-- Spawner Setup API
-- ============================================

-- Expose function to create spawners (call from other scripts or command line)
-- Register an already-constructed spawner object (e.g. a DungeonBossSpawner
-- subclass) rather than building a plain MobSpawner from primitives. Needed
-- because boss spawners carry extra config (ceiling anchor) that
-- RegisterSpawner's positional signature cannot express.
local function RegisterSpawnerObject(spawner)
    if not spawner then return nil end
    table.insert(ActiveSpawners, spawner)
    local zone = spawner.ZoneName or "Default"
    if not ZonePity[zone] then
        ZonePity[zone] = 0
    end
    return spawner
end

-- Remove a spawner and destroy everything it spawned. Needed for dungeon
-- instances: each run clones the realm and registers its own spawners, and
-- those must go away with the realm or they leak forever and keep ticking
-- against a destroyed model.
local function UnregisterSpawner(spawner)
    if not spawner then return false end
    for i = #ActiveSpawners, 1, -1 do
        if ActiveSpawners[i] == spawner then
            table.remove(ActiveSpawners, i)
        end
    end
    for _, mob in ipairs(spawner.SpawnedMobs or {}) do
        if mob then
            if mob.UID then ActiveMobs[mob.UID] = nil end
            if mob.Model then
                pcall(function() mob.Model:Destroy() end)
            end
        end
    end
    spawner.SpawnedMobs = {}
    return true
end

-- Dev-tool convenience (F8 "Force Spawn Elite"): force-spawn a specific named
-- elite mob immediately in front of `player`, going through the EXACT same
-- path a real elite pity/chance trigger uses (SetNextSpawnMob + an immediate
-- SpawnMob with the rise-from-ground intro -- see MobSpawner:SpawnMob) rather
-- than a plain grunt-mob spawner, so testing a named elite (e.g. Kane) gets
-- the same intro effect, PlayerActiveEliteMob HP-bar tracking, and top-middle
-- boss bar a naturally-triggered elite would. A huge CooldownTime + MaxSpawns
-- = 1 means this ad-hoc spawner never auto-respawns another copy once this
-- one dies -- it exists purely to carry ONE forced spawn through the normal
-- Tick/ActiveMobs registration pipeline (see OnHeartbeat's spawner loop).
-- Returns the spawned mob object, or nil on failure (unknown MobID, no
-- player Character, etc).
local function ForceSpawnNamedElite(player, mobId)
    if not player or type(mobId) ~= "string" or mobId == "" then
        return nil
    end
    if not MobData.FindMobById(mobId) then
        warn("[MobManager] ForceSpawnNamedElite: unknown MobID " .. tostring(mobId))
        return nil
    end

    local spawnPos = getFrontSpawnPosition(player, Vector3.new())
    local spawner = RegisterSpawner(spawnPos, mobId, 999999, 1, 100, "DevForcedElite")
    spawner:SetNextSpawnMob(mobId, spawnPos, true)
    local mob = spawner:SpawnMob()
    if mob then
        PlayerActiveEliteMob[player.UserId] = mob
    end
    return mob
end

_G.MobSystem = {
    CreateSpawner = RegisterSpawner,
    RegisterSpawnerObject = RegisterSpawnerObject,
    UnregisterSpawner = UnregisterSpawner,
    ForceSpawnNamedElite = ForceSpawnNamedElite,
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

-- Declarative dungeon spawns (model-anchored, defined in source rather than
-- placed by hand in Play mode). Runs after the DataStore-backed F8 camps so
-- a dungeon definition always wins over a stale saved marker.
do
	local dss = ServerScriptService:FindFirstChild("DungeonMobSpawnService")
	if dss and dss:IsA("ModuleScript") then
		local ok, mod = pcall(require, dss)
		if ok and type(mod) == "table" and mod.RegisterAll then
			local ok2, err2 = pcall(mod.RegisterAll)
			if not ok2 then
				warn("[MobManager] DungeonMobSpawnService.RegisterAll failed: ", err2)
			end
		elseif not ok then
			warn("[MobManager] DungeonMobSpawnService require failed: ", mod)
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