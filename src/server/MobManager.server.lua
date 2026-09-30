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
local DungeonLevels = require(ReplicatedStorage:WaitForChild("DungeonLevels"))
local MobCombat   = require(ServerScriptService:WaitForChild("MobCombat"))
local LootService = require(ServerScriptService:WaitForChild("LootService"))
local DropperKeyService = require(ServerScriptService:WaitForChild("DropperKeyService"))
local DungeonProfile = require(ServerScriptService:WaitForChild("ProfileService"))
local CombatStateService = require(ServerScriptService:WaitForChild("CombatStateService"))
local MountService = require(ServerScriptService:WaitForChild("MountService"))
local PartyService = require(ServerScriptService:WaitForChild("PartyService"))
local ZoneService = require(ServerScriptService:WaitForChild("ZoneService"))
local NamedEliteSoundtracks = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Sounds"):WaitForChild("NamedEliteSoundtracks"))

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
-- Named-elite spawning. The lucky roll and the pity counter are INDEPENDENT
-- triggers (they used to be one escalating roll: 1% + 1% per kill, which meant
-- the "chance" WAS the pity bar). Either one firing spawns the elite:
--   * NAMED_ELITE_ROLL_CHANCE -- flat per-kill chance, never scales with kills
--   * NAMED_ELITE_PITY_KILLS  -- kills in that zone that force a spawn
-- Both are gated on no named elite already being alive (see namedEliteActive).
local NAMED_ELITE_ROLL_CHANCE = 1 / 300
local NAMED_ELITE_PITY_KILLS = 100
-- Everyone sees a live named elite's bar; only players this close (or its spawner) get its music.
local NAMED_ELITE_MUSIC_RADIUS = 250
-- A named elite that has neither taken nor dealt a hit for this long despawns (no loot, no
-- credit), freeing the one-elite slot. Every hit either way resets the clock (_lastCombatAt,
-- written by MobClass.TakeDamage and DamageService.ApplyToPlayer).
local NAMED_ELITE_IDLE_DESPAWN = 5 * 60

-- State
local ActiveMobs = {} -- Dictionary: [UID] = MobObject
local ActiveSpawners = {} -- Array of SpawnerObjects
local ZonePity = {} -- Dictionary: [ZoneName] = killCount
local PendingEliteZones = {} -- Set of zone names waiting for elite spawn
local PlayerEliteZoneStacks = {} -- [userId] = { [zoneName] = killsSinceLastEliteSpawn }
local PlayerActiveEliteMob = {} -- [userId] = mob object currently tied to elite bar
-- Exactly ONE named elite may be alive server-wide. While it is, no roll and no
-- pity progress happen for anybody -- otherwise two lucky kills seconds apart
-- could put two named elites up at once.
local ActiveNamedElite = nil

local function namedEliteActive()
    if ActiveNamedElite and ActiveNamedElite.IsAlive and ActiveNamedElite:IsAlive() then
        return true
    end
    ActiveNamedElite = nil
    return false
end

-- Single place that takes ownership of a freshly spawned named elite: the
-- server-wide "only one alive" slot, the per-player boss-bar binding, and the
-- soundtrack (RS/Assets/Sounds/NamedEliteSoundtracks) picked once per spawn so
-- an elite with several possible tracks keeps the same one for the whole fight.
local function trackNamedElite(player, mob)
    if not mob then return end
    ActiveNamedElite = mob
    mob._soundtrackId = NamedEliteSoundtracks.Pick(mob.MobID)
    mob._lastCombatAt = os.clock() -- the idle-despawn clock starts at spawn
    if player then
        PlayerActiveEliteMob[player.UserId] = mob
    end
end

-- Boss bar for NON-named bosses (dungeon bosses like Miasma): same per-player
-- binding the named-elite top-middle bar reads (EliteActive / EliteCurrentHealth /
-- EliteMaxHealth / CurrentEliteMobId, kept fresh by OnHeartbeat), but WITHOUT
-- claiming the server-wide ActiveNamedElite slot (a dungeon boss must not block
-- world elites) and without picking a named-elite soundtrack.
local function setBossBar(player, mob)
    if player and mob then
        PlayerActiveEliteMob[player.UserId] = mob
    end
end

local function clearBossBar(player, mob)
    if not player then return end
    if mob == nil or PlayerActiveEliteMob[player.UserId] == mob then
        PlayerActiveEliteMob[player.UserId] = nil
        clearPlayerEliteHealthAttributes(player)
    end
end

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
    player:SetAttribute("ElitePityZone", zoneName)
    player:SetAttribute("ElitePityKills", math.min(killsSinceLastElite, NAMED_ELITE_PITY_KILLS))
    player:SetAttribute("ElitePityMax", NAMED_ELITE_PITY_KILLS)
end

local function clearPlayerEliteHealthAttributes(player)
    if not player then return end
    player:SetAttribute("EliteActive", false)
    player:SetAttribute("EliteCurrentHealth", 0)
    player:SetAttribute("EliteMaxHealth", 0)
end

local function getFrontSpawnPosition(player, fallback, distance)
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
    return hrp.Position + (flat * (distance or 9))
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
    -- No progress and no rolls while a named elite is already up.
    if killingBlowPlayer and mob.SpawnerRef and not namedEliteActive() then
        local activeEliteZoneName = killingBlowPlayer:GetAttribute("CurrentEliteZone")
        if type(activeEliteZoneName) ~= "string" or activeEliteZoneName == "" then
            activeEliteZoneName = zone
        end

        local zoneConfig = getZoneEliteConfig(activeEliteZoneName)
        if zoneConfig and zoneConfig.isEliteZone and type(zoneConfig.eliteMobId) == "string" and zoneConfig.eliteMobId ~= "" then
            local userId = killingBlowPlayer.UserId
            local zoneStacks = getPlayerZoneStacks(userId)
            local killsSinceLastElite = zoneStacks[activeEliteZoneName] or 0
            local nextKills = killsSinceLastElite + 1
            local luckyRoll = math.random() < NAMED_ELITE_ROLL_CHANCE
            local pityFull = nextKills >= NAMED_ELITE_PITY_KILLS

            if luckyRoll or pityFull then
                local forcedSpawnPos = getFrontSpawnPosition(killingBlowPlayer, mob.SpawnerRef.Location)
                local queued = mob.SpawnerRef:SetNextSpawnMob(zoneConfig.eliteMobId, forcedSpawnPos, true)
                if queued then
                    -- Spawn immediately so players always see the rise animation
                    -- at the captured kill-time position, independent of range checks.
                    local spawnedElite = mob.SpawnerRef:SpawnMob()
                    if spawnedElite then
                        trackNamedElite(killingBlowPlayer, spawnedElite)
                    end
                    zoneStacks[activeEliteZoneName] = 0
                else
                    zoneStacks[activeEliteZoneName] = nextKills
                end
            else
                zoneStacks[activeEliteZoneName] = nextKills
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
                local _, _, totals = DungeonProfile.AddSkillXP(player, "combat", xpGain)
                CombatXPEvent:FireClient(player, xpGain, totals)
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

local DespawnNamedElite -- defined below (Dev/API section), used by the idle check here
local devBoss = { mob = nil, spawner = nil } -- the one F8 dev boss (ForceSpawnBoss below)

local function OnHeartbeat(deltaTime)
    local players = Players:GetPlayers()
    -- One read per tick: drives every player's "pity is frozen" HUD state.
    local eliteLocked = namedEliteActive()
    -- Idle despawn: out of combat (no hit taken or dealt) for NAMED_ELITE_IDLE_DESPAWN.
    if eliteLocked and os.clock() - (ActiveNamedElite._lastCombatAt or 0) > NAMED_ELITE_IDLE_DESPAWN then
        if DespawnNamedElite(ActiveNamedElite) then
            eliteLocked = false
        else
            ActiveNamedElite._lastCombatAt = os.clock() -- not despawnable: don't retry every tick
        end
    end

    for _, player in ipairs(players) do
        player:SetAttribute("EliteSpawnLocked", eliteLocked)
        local eliteZoneName = player:GetAttribute("CurrentEliteZone")
        if type(eliteZoneName) ~= "string" then
            eliteZoneName = ""
        end
        -- A per-player binding (a dungeon boss via setBossBar, or the elite's spawner) wins;
        -- otherwise EVERYONE outside a dungeon sees the one live named elite's bar -- there is
        -- only ever one (namedEliteActive), so it's never ambiguous whose bar it is.
        local activeEliteMob = PlayerActiveEliteMob[player.UserId]
        -- Safety net: a DUNGEON boss's bar (Miasma, bound by its encounter) never follows a
        -- player out of the dungeon, whatever the exit path (InDungeon is cleared by
        -- DungeonInstanceService.releaseMember). The dev overworld boss is exempt.
        if activeEliteMob and activeEliteMob.Stats and activeEliteMob.Stats.IsBoss
            and activeEliteMob ~= devBoss.mob and player:GetAttribute("InDungeon") ~= true then
            PlayerActiveEliteMob[player.UserId] = nil
            activeEliteMob = nil
        end
        local bound = activeEliteMob ~= nil and activeEliteMob.IsAlive ~= nil and activeEliteMob:IsAlive()
        if not bound and eliteLocked and player:GetAttribute("InDungeon") ~= true then
            activeEliteMob = ActiveNamedElite
        end
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
            -- Named-elite soundtrack outranks the zone's while the fight is on -- for its
            -- spawner and anyone near it, not the whole server (the bar alone is global).
            -- Cheap to re-assert every tick: SetMusicOverride no-ops unless the
            -- value actually changed.
            local nearby = bound
            if not nearby then
                local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                local position = activeEliteMob.GetPosition and activeEliteMob:GetPosition()
                nearby = root ~= nil and typeof(position) == "Vector3"
                    and (root.Position - position).Magnitude <= NAMED_ELITE_MUSIC_RADIUS
            end
            ZoneService.SetMusicOverride(player, nearby and (activeEliteMob._soundtrackId or "") or "")
        else
            PlayerActiveEliteMob[player.UserId] = nil
            if player:GetAttribute("EliteActive") == true then
                -- The bar just ended: hand CurrentEliteMobId (overwritten above with the live
                -- elite's id, for EVERYONE now) back to this zone's own elite, or the pity
                -- plate would name the wrong elite in a different elite zone.
                local zoneConfig = eliteZoneName ~= "" and getZoneEliteConfig(eliteZoneName) or nil
                local zoneEliteId = zoneConfig and zoneConfig.isEliteZone and type(zoneConfig.eliteMobId) == "string" and zoneConfig.eliteMobId or ""
                player:SetAttribute("CurrentEliteMobId", zoneEliteId)
            end
            clearPlayerEliteHealthAttributes(player)
            ZoneService.SetMusicOverride(player, "")
        end

        if eliteZoneName ~= "" then
            local stacks = getPlayerZoneStacks(player.UserId)
            setPlayerElitePityAttributes(player, eliteZoneName, stacks[eliteZoneName] or 0)
        else
            player:SetAttribute("ElitePityZone", "")
            player:SetAttribute("ElitePityKills", 0)
            player:SetAttribute("ElitePityMax", NAMED_ELITE_PITY_KILLS)
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
    
    -- Update AI for all active mobs. The crowd grid is built once first, so every mob's
    -- neighbour check this tick is local (MobClass.BuildCrowdGrid).
    MobClass.BuildCrowdGrid(ActiveMobs)
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
    ZoneService.SetMusicOverride(player, "")
    player:SetAttribute("ElitePityZone", "")
    player:SetAttribute("ElitePityKills", 0)
    player:SetAttribute("ElitePityMax", NAMED_ELITE_PITY_KILLS)
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
    -- Same one-at-a-time rule as a natural spawn: the dev tool is not an exception,
    -- or testing would be the one way to get two named elites up at once.
    if namedEliteActive() then
        warn("[MobManager] ForceSpawnNamedElite: a named elite is already active (" ..
            tostring(ActiveNamedElite and ActiveNamedElite.MobID) .. ") -- kill it first")
        return nil
    end

    local spawnPos = getFrontSpawnPosition(player, Vector3.new())
    local spawner = RegisterSpawner(spawnPos, mobId, 999999, 1, 100, "DevForcedElite")
    spawner:SetNextSpawnMob(mobId, spawnPos, true)
    local mob = spawner:SpawnMob()
    if mob then
        trackNamedElite(player, mob)
    end
    return mob
end

-- Dev-tool only: drop a dungeon boss (MobData IsBoss) into the overworld for
-- playtesting, with its real stats and its real class -- MobClassRegistry still
-- resolves MovementClass = "DungeonBoss", so AggroStart and the boss attack come
-- with it. Deliberately NOT a dungeon run: no instance, no ceiling intro (that
-- needs a DungeonBossSpawner with authored anchors), and killing it outside a run
-- ends nothing, because LootService's boss-death cash-out returns early when no
-- player is in a run.
--
-- One at a time. A second request replaces the first instead of stacking, and
-- the previous throwaway spawner is unregistered so dev spawns don't leak
-- spawners that tick forever.
-- (devBoss itself is declared above OnHeartbeat, which reads it.)
local DEV_BOSS_SPAWN_DISTANCE = 45 -- studs; Miasma's hit radius alone is ~26

local function ForceSpawnBoss(player, mobId)
    if not player or type(mobId) ~= "string" or mobId == "" then
        return nil
    end
    local stats, tier = MobData.FindMobById(mobId)
    if not stats or not stats.IsBoss then
        warn("[MobManager] ForceSpawnBoss: not a boss MobID " .. tostring(mobId))
        return nil
    end
    -- Same level a real run of this boss's tier would use (no modifiers), so a
    -- dev playtest fights the boss at its actual dungeon HP and damage.
    local level = DungeonLevels.Resolve(tier or 1)

    if devBoss.spawner then
        UnregisterSpawner(devBoss.spawner)
        devBoss.mob, devBoss.spawner = nil, nil
    end

    -- Far enough out that a boss this size does not spawn on top of you.
    local spawnPos = getFrontSpawnPosition(player, Vector3.new(), DEV_BOSS_SPAWN_DISTANCE)
    -- Respawn delay effectively never: this is a one-shot, not a camp.
    local spawner = RegisterSpawner(spawnPos, mobId, 999999, 1, 200, "DevForcedBoss", DungeonLevels.SpawnRange(level))
    spawner:SetNextSpawnMob(mobId, spawnPos, false)
    local mob = spawner:SpawnMob()
    if not mob then
        UnregisterSpawner(spawner)
        return nil
    end
    devBoss.mob, devBoss.spawner = mob, spawner
    setBossBar(player, mob)
    return mob
end

-- Remove a live named elite WITHOUT killing it: no loot, no XP, no kill credit,
-- no death effect. Called by the idle check in OnHeartbeat once it has been out of
-- combat for NAMED_ELITE_IDLE_DESPAWN (it used to fire when it killed a player, which
-- ended the fight for everyone the moment one person died). The elite, its boss bar and
-- its soundtrack go away together and the pity counter starts building again.
-- Safe to call with a mob that is already gone.
function DespawnNamedElite(mob)
    if type(mob) ~= "table" then return false end
    if not (mob.Stats and mob.Stats.IsNamedElite) then return false end

    -- IsAlive() is `Model ~= nil and CurrentHealth > 0`, and both the spawner's
    -- CountAliveMobs and OnHeartbeat below prune off exactly that -- so zeroing
    -- health and dropping the model is what actually frees the spawner's slot.
    mob.CurrentHealth = 0
    local model = mob.Model
    mob.Model = nil
    if model then
        pcall(function() model:Destroy() end)
    end
    if mob.HPBar then
        mob.HPBar:Destroy()
        mob.HPBar = nil
    end
    if mob.UID then
        ActiveMobs[mob.UID] = nil
    end
    if mob.SpawnerRef and mob.SpawnerRef.OnMobDied then
        mob.SpawnerRef:OnMobDied(mob)
    end

    if ActiveNamedElite == mob then
        ActiveNamedElite = nil
    end
    for userId, tracked in pairs(PlayerActiveEliteMob) do
        if tracked == mob then
            PlayerActiveEliteMob[userId] = nil
            local player = Players:GetPlayerByUserId(userId)
            if player then
                clearPlayerEliteHealthAttributes(player)
                ZoneService.SetMusicOverride(player, "")
            end
        end
    end
    print("[MobManager] despawned named elite " .. tostring(mob.MobID))
    return true
end

_G.MobSystem = {
    CreateSpawner = RegisterSpawner,
    RegisterSpawnerObject = RegisterSpawnerObject,
    UnregisterSpawner = UnregisterSpawner,
    ForceSpawnNamedElite = ForceSpawnNamedElite,
    ForceSpawnBoss = ForceSpawnBoss,
    DespawnNamedElite = DespawnNamedElite,
    SetBossBar = setBossBar,
    ClearBossBar = clearBossBar,
    GetActiveMobs = function() return ActiveMobs end,
    GetActiveSpawners = function() return ActiveSpawners end,
    GetZonePity = function() return ZonePity end,
    IsNamedEliteActive = namedEliteActive,
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