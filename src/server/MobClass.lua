-- MobClass ModuleScript
-- OOP Metatable blueprint for an active mob
-- Lives only in server memory

local MobClass = {}
MobClass.__index = MobClass

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")

local MOB_COLLISION_GROUP = "DungeonMobs"

local function ensureMobCollisionGroup()
	local registered = false
	pcall(function()
		registered = PhysicsService:IsCollisionGroupRegistered(MOB_COLLISION_GROUP)
	end)

	if not registered then
		pcall(function()
			PhysicsService:RegisterCollisionGroup(MOB_COLLISION_GROUP)
		end)
	end

	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(MOB_COLLISION_GROUP, MOB_COLLISION_GROUP, true)
	end)
end

-- Simple v1 AI: direct CFrame stepping each tick (no Humanoid:MoveTo, no
-- AssemblyLinearVelocity locomotion, no PathfindingService). Every attempt
-- to drive movement through Humanoid's native walk controller in this
-- project ran into a different engine quirk (MoveDirection never populating
-- for AI, MoveTo restarting its controller when reissued, periodic reissue
-- causing velocity overshoot). Setting position and facing directly via
-- Model:PivotTo() is the one approach that tested perfectly smooth with zero
-- jitter, so that is the only movement mechanism here.
local KNOCKBACK_DISTANCE = 0.6 -- studs, one-time positional nudge away from attacker (~20% of original 3)
local ATTACK_RANGE_LEEWAY = 1.3 -- multiplier before giving up attack range and resuming walk
local MOB_COLLISION_RADIUS = 3 -- studs; mobs push apart instead of overlapping
local LEASH_GRACE_DURATION = 1.0 -- seconds a mob may stay aggro'd past ReturnDistance if still close to the target
local LEASH_GRACE_PROXIMITY = 12 -- studs; "physically close enough" to ignore the leash during the grace window
local PLAYER_HIT_KNOCKBACK_HORIZONTAL = 4 -- studs/s impulse added to the player on being hit
local PLAYER_HIT_KNOCKBACK_VERTICAL = 8 -- studs/s upward impulse -- a small hop, just enough to interrupt movement

ensureMobCollisionGroup()

local MobData = require(ReplicatedStorage:WaitForChild("MobData"))
local DamageService = require(script.Parent:WaitForChild("DamageService"))
local MobAnimController = require(script.Parent:WaitForChild("MobAnimController"))
local MobHPBarUI = require(script.Parent:WaitForChild("MobHPBarUI"))
local MobGroundUtils = require(script.Parent:WaitForChild("MobGroundUtils"))

-- Counter for generating unique IDs
local mobIdCounter = 0

-- Constructor. `class` lets a subclass (e.g. HoppingMobClass) reuse all of
-- this initialization while registering instances under its own metatable,
-- so self:Move(...) and friends resolve to the subclass's overrides first.
function MobClass.new(mobId, spawnPosition, spawnerRef, level, class)
    local self = setmetatable({}, class or MobClass)
    
    -- Generate unique ID
    mobIdCounter = mobIdCounter + 1
    self.UID = "Mob_" .. tostring(mobIdCounter)
    
    -- Get base mob stats
    local baseStats, tier = MobData.FindMobById(mobId)
    if not baseStats then
        warn("MobClass: Could not find mob data for MobID: " .. tostring(mobId))
        return nil
    end

    -- Clone stats so we do not mutate the shared MobData table
    local statsCopy = {}
    for k, v in pairs(baseStats) do
        statsCopy[k] = v
    end

    self.Stats = statsCopy
    self.Tier = tier
    
    self.MobID = mobId
    self.SpawnPosition = spawnPosition
    self.SpawnerRef = spawnerRef
    self._deathPosition = nil

    -- Dynamic level override
    self.Level = tonumber(level) or self.Stats.Level
    self.Stats.Level = self.Level

    -- Level scaling
    local levelMultiplier = 1 + (self.Level * 0.1)
    
    -- Health tracking
    self.MaxHealth = math.floor(self.Stats.BaseHP * levelMultiplier)
    self.CurrentHealth = self.MaxHealth

    -- Scale outgoing damage
    self.Stats.BaseDamage = math.floor(self.Stats.BaseDamage * levelMultiplier)
    
    -- Damage tracking for loot distribution
    self.DamageTracker = {}
    
    -- AI state: Idle -> Walking -> Attacking, and back to Idle when the
    -- target is lost/dead/out of leash range. No "Returning" state in v1 --
    -- losing the target just goes straight back to Idle in place.
    self.AIState = "Idle"
    self.TargetPlayer = nil
    self.LastAttackTime = 0
    self._feetToRootHeight = 0
    self.IsSpawnStunned = false
    self.IsInvulnerable = false

    -- Clone and setup visual model
    self.Model = self:SpawnModel()
    if not self.Model then
        return nil
    end
    
    -- Create HP bar above mob
    self.HPBar = self:CreateHPBar()
    MobAnimController.attach(self)

    return self
end

-- Spawn the visual model into workspace
function MobClass:SpawnModel()
    local mobModelsFolder = ServerStorage:FindFirstChild("MobModels")
    if not mobModelsFolder then
        warn("MobClass: MobModels folder not found in ServerStorage")
        return nil
    end

    local modelTemplate = mobModelsFolder:FindFirstChild(self.MobID)
    if not modelTemplate then
        warn("MobClass: Model not found for MobID: " .. self.MobID)
        return nil
    end
    
    local model = modelTemplate:Clone()
    model.Name = self.UID
    model:SetAttribute("MobUID", self.UID)
    model:SetAttribute("MobID", self.MobID)
    model:SetAttribute("MobLevel", self.Level)
    
    -- Position the model: raycast down to find the real walkable surface
    -- below the spawn point and rest the model's own geometry on top of it,
    -- rather than trusting the spawn marker's raw Y (which is often a flat
    -- trigger volume sitting at/near ground level, not at character height).
    if model:IsA("Model") then
        self._feetToRootHeight = self:GetFeetToRootHeight(model) or 0
        local groundedPosition = self:ResolveGroundedSpawnPosition(model, self.SpawnPosition)
        self.SpawnPosition = groundedPosition
        model:PivotTo(CFrame.new(groundedPosition))
    elseif model:IsA("BasePart") then
        model.Position = self.SpawnPosition
    end
    
    self:ConfigureModel(model)
    model.Parent = workspace
    
    return model
end

-- Height from the model's true geometric bottom (feet) up to its
-- PrimaryPart. Thin wrapper -- see MobGroundUtils for the actual raycast-free
-- bounding-box math, shared with anything else that needs it.
function MobClass:GetFeetToRootHeight(model)
    return MobGroundUtils.GetFeetToRootHeight(model)
end

-- Raycast straight down from above `position` to find the nearest surface,
-- then return a position with the model's feet resting exactly on it (a
-- small drop from there is fine -- gravity will settle it the rest of the
-- way once Humanoid.HipHeight, set in ConfigureModel, is correct).
-- Falls back to `position` unchanged if nothing is hit (e.g. a void).
function MobClass:ResolveGroundedSpawnPosition(model, position)
    return MobGroundUtils.ResolveGroundedSpawnPosition(model, position, self._feetToRootHeight)
end

function MobClass:ConfigureModel(model)
    if not model then
        return
    end

    local humanoid = model:FindFirstChildOfClass("Humanoid")
    local rootPart = model:FindFirstChild("HumanoidRootPart")
    if not rootPart then
        rootPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
    end

    if model:IsA("Model") and rootPart then
        model.PrimaryPart = rootPart
    end

    if humanoid then
        -- Roblox's own ground-following controller hovers HumanoidRootPart
        -- at HipHeight above whatever surface it detects. If HipHeight does
        -- not match this rig's real feet-to-root distance (common after an
        -- R6->R15 conversion, since the default/imported value is rarely
        -- right), the engine itself will sink or float the visual mesh
        -- relative to the ground every physics step, independent of how
        -- accurately we place it at spawn -- and a mis-grounded Humanoid can
        -- also fail to settle into the Running state, which is why the walk
        -- animation stops firing along with the sinking.
        local feetToRootHeight = rootPart and self:GetFeetToRootHeight(model)
        if feetToRootHeight then
            humanoid.HipHeight = feetToRootHeight
        end

        self:SyncHumanoidLocomotionStats(humanoid)
        humanoid.AutoRotate = false
        humanoid.PlatformStand = false
        humanoid.Sit = false
        humanoid.RequiresNeck = false
        humanoid.AutoJumpEnabled = false
        humanoid.BreakJointsOnDeath = false
        -- Suppress Roblox's built-in floating name/health display -- the
        -- model is named after self.UID (e.g. "Mob_1"), and without this it
        -- shows up as a second nametag stacked under our custom HPBar.
        humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

        for _, state in ipairs({
            Enum.HumanoidStateType.FallingDown,
            Enum.HumanoidStateType.Ragdoll,
            Enum.HumanoidStateType.Seated,
            Enum.HumanoidStateType.PlatformStanding,
        }) do
            pcall(function()
                humanoid:SetStateEnabled(state, false)
            end)
        end

        self:SyncHumanoidHealth(humanoid)
    end

    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("BasePart") then
            descendant.CollisionGroup = MOB_COLLISION_GROUP

            if descendant.Name == "HumanoidRootPart" then
                descendant.CanCollide = true
                descendant.Massless = false
            elseif descendant.Name == "Body" then
                descendant.CanCollide = false
                descendant.Massless = true
            end
        end
    end
end

-- Raycast straight down from above (x, z) to find the nearest surface.
-- Falls back to fallbackY (unchanged) if nothing is hit, e.g. a void --
-- never let a momentary missed raycast yank the mob's height around.
function MobClass:FindGroundY(x, z, fallbackY)
    if not self.Model then
        return fallbackY
    end
    return MobGroundUtils.FindGroundY(self.Model, x, z, fallbackY)
end

-- Rotate in place to face a world point, without moving. Used while
-- attacking (face the target, do not walk into it).
function MobClass:FaceToward(worldPoint)
    if not self.Model then
        return
    end
    local primaryPart = self.Model.PrimaryPart
    if not primaryPart then
        return
    end

    local pos = primaryPart.Position
    local flat = Vector3.new(worldPoint.X - pos.X, 0, worldPoint.Z - pos.Z)
    if flat.Magnitude < 0.1 then
        return
    end

    self.Model:PivotTo(CFrame.lookAt(pos, Vector3.new(worldPoint.X, pos.Y, worldPoint.Z)))
end

-- Simple anti-collision: nudge a desired (x, z) away from any other alive
-- mob closer than MOB_COLLISION_RADIUS, so mobs converging on the same
-- target push apart instead of fighting for the same spot every frame.
-- Reads self._activeMobsRef, set once per tick by UpdateAI.
function MobClass:ResolveMobSeparation(x, z)
    local activeMobs = self._activeMobsRef
    if not activeMobs then
        return x, z
    end

    local pushX, pushZ = 0, 0
    for _, otherMob in pairs(activeMobs) do
        if otherMob ~= self and otherMob.IsAlive and otherMob:IsAlive() and otherMob.Model then
            local otherPart = otherMob.Model.PrimaryPart
            if otherPart then
                local dx = x - otherPart.Position.X
                local dz = z - otherPart.Position.Z
                local dist = math.sqrt(dx * dx + dz * dz)
                if dist > 0.001 and dist < MOB_COLLISION_RADIUS then
                    local strength = (MOB_COLLISION_RADIUS - dist) / MOB_COLLISION_RADIUS
                    pushX += (dx / dist) * strength * MOB_COLLISION_RADIUS * 0.5
                    pushZ += (dz / dist) * strength * MOB_COLLISION_RADIUS * 0.5
                end
            end
        end
    end

    return x + pushX, z + pushZ
end

-- Override hook for subclasses (e.g. a hopping mob): called by HandleWalking
-- every tick with the current chase goal. Default behaviour is a smooth walk.
function MobClass:Move(goalPosition, deltaTime)
    self:StepToward(goalPosition, deltaTime)
end

-- Default walk implementation: step the model directly toward goalPosition
-- by Stats.MoveSpeed * deltaTime, resolve overlap with other mobs,
-- ground-snap the new spot, and face the direction of travel -- all
-- combined into one PivotTo so there is exactly one position+rotation
-- write per tick (no competing systems to fight).
function MobClass:StepToward(goalPosition, deltaTime)
    if not self.Model then
        return
    end
    local primaryPart = self.Model.PrimaryPart
    if not primaryPart then
        return
    end

    local pos = primaryPart.Position
    local flat = Vector3.new(goalPosition.X - pos.X, 0, goalPosition.Z - pos.Z)
    local dist = flat.Magnitude

    local newX, newZ = pos.X, pos.Z
    if dist > 0.05 then
        local moveSpeed = self.Stats.MoveSpeed or 8
        local step = math.min(moveSpeed * deltaTime, dist)
        local dir = flat.Unit
        newX = pos.X + dir.X * step
        newZ = pos.Z + dir.Z * step
    end

    newX, newZ = self:ResolveMobSeparation(newX, newZ)

    local groundY = self:FindGroundY(newX, newZ, pos.Y)
    local newPos = Vector3.new(newX, groundY + (self._feetToRootHeight or 0), newZ)

    if dist > 0.1 then
        self.Model:PivotTo(CFrame.lookAt(newPos, Vector3.new(goalPosition.X, newPos.Y, goalPosition.Z)))
    else
        local _, yaw = primaryPart.CFrame:ToEulerAnglesYXZ()
        self.Model:PivotTo(CFrame.new(newPos) * CFrame.Angles(0, yaw, 0))
    end
end

function MobClass:SyncHumanoidHealth(humanoid)
    if not humanoid then
        return
    end

    local maxHealth = math.max(self.MaxHealth, 1)
    local currentHealth = math.clamp(self.CurrentHealth, 0, maxHealth)

    humanoid.MaxHealth = maxHealth
    humanoid.Health = currentHealth

    if self._healthLockConnection then
        self._healthLockConnection:Disconnect()
    end

    self._healthLockConnection = humanoid:GetPropertyChangedSignal("Health"):Connect(function()
        if self.CurrentHealth <= 0 then
            return
        end

        local syncedHealth = math.clamp(self.CurrentHealth, 0, maxHealth)
        if humanoid.Health ~= syncedHealth then
            humanoid.Health = syncedHealth
        end
    end)
end

function MobClass:SyncHumanoidLocomotionStats(humanoid)
    if not humanoid then
        return
    end
    -- Informational only -- movement is driven by StepToward, not by
    -- Humanoid's own walk controller. Kept in sync in case anything else
    -- (UI, animations) reads it.
    humanoid.WalkSpeed = self.Stats.MoveSpeed or humanoid.WalkSpeed
end

-- Small one-time positional nudge away from the attacker. No physics, no
-- decay loop -- just an immediate, ground-snapped step, consistent with how
-- every other position change in this file works.
function MobClass:ApplyKnockback(attackerPosition)
    if not self.Model or self.CurrentHealth <= 0 then
        return
    end
    local primaryPart = self.Model.PrimaryPart
    if not primaryPart then
        return
    end

    local mult = (self.Stats and self.Stats.KnockbackMultiplier ~= nil)
        and self.Stats.KnockbackMultiplier or 1.0
    if mult <= 0 then
        return
    end

    local pos = primaryPart.Position
    local horizontal = Vector3.new(pos.X - attackerPosition.X, 0, pos.Z - attackerPosition.Z)
    local dir = horizontal.Magnitude > 0.1 and horizontal.Unit or Vector3.new(0, 0, 1)

    local nudge = KNOCKBACK_DISTANCE * mult
    local newX = pos.X + dir.X * nudge
    local newZ = pos.Z + dir.Z * nudge
    local groundY = self:FindGroundY(newX, newZ, pos.Y)
    local newPos = Vector3.new(newX, groundY + (self._feetToRootHeight or 0), newZ)

    local _, yaw = primaryPart.CFrame:ToEulerAnglesYXZ()
    self.Model:PivotTo(CFrame.new(newPos) * CFrame.Angles(0, yaw, 0))
end

-- Create HP bar above mob. Actual UI construction lives in MobHPBarUI so
-- this file stays focused on AI/combat/spawning, not BillboardGui layout.
function MobClass:CreateHPBar()
    return MobHPBarUI.Create(self)
end

-- Update HP bar display to match CurrentHealth/MaxHealth.
function MobClass:UpdateHPBar()
    MobHPBarUI.Update(self)
end

-- Take damage method
-- amount comes in pre-armor (e.g. MobCombat already applied level scaling).
-- DamageService applies the armor curve here so every damage source funnels
-- through the same math.
function MobClass:TakeDamage(player, amount)
    if self.CurrentHealth <= 0 then
        return false -- Already dead
    end
    if self.IsInvulnerable then
        return false
    end

    local armorRating = (self.Stats and self.Stats.Armor) or 0
    local final = DamageService.ComputeFinal(amount, armorRating)

    -- Apply damage
    self.CurrentHealth = self.CurrentHealth - final
    if self.CurrentHealth < 0 then
        self.CurrentHealth = 0
    end
    
    -- Track damage contribution (post-armor so loot reflects actual damage)
    local playerId = player.UserId
    self.DamageTracker[playerId] = (self.DamageTracker[playerId] or 0) + final
    
    -- Update HP bar display
    self:UpdateHPBar()

    local humanoid = self.Model and self.Model:FindFirstChildOfClass("Humanoid")
    if humanoid then
        self:SyncHumanoidHealth(humanoid)
    end

    -- Cancel an in-progress attack swing -- getting hit interrupts the
    -- animation, but NOT the attack-cooldown timer, so the mob can still
    -- land its own hit back if the player is already in range (no hit-stun
    -- lockout on the attempt itself, only a visual flinch).
    if self._animTracks and self._animTracks.Attack and self._animTracks.Attack.IsPlaying then
        self._animTracks.Attack:Stop(0.05)
    end

    -- Re-aggro on whoever just hit us
    if self.AIState == "Idle" then
        self.AIState = "Walking"
    end
    self.TargetPlayer = player
    
    -- Check for death
    if self.CurrentHealth <= 0 then
        -- Award tier-aware kill credit and XP to the killer before Die()
        -- tears down the model.
        DamageService.AwardKill(player, self)
        self:Die()
        return true -- Mob died
    end

    return false -- Mob still alive
end

-- Die method
function MobClass:Die()
    -- Clean up HP bar
    if self.HPBar then
        self.HPBar:Destroy()
        self.HPBar = nil
    end
    
    if self._healthLockConnection then
        self._healthLockConnection:Disconnect()
        self._healthLockConnection = nil
    end

    -- Snapshot world position before the model is destroyed (death callbacks still need this).
    do
        local mdl = self.Model
        if mdl then
            local pp = mdl.PrimaryPart or mdl:FindFirstChildWhichIsA("BasePart")
            if pp then
                self._deathPosition = pp.Position
            end
        end
    end

    -- Destroy the visual model
    if self.Model then
        self.Model:Destroy()
        self.Model = nil
    end
    
    -- Notify spawner
    if self.SpawnerRef then
        self.SpawnerRef:OnMobDied(self)
    end
    
    -- Return damage tracker for loot/score calculation
    return self.DamageTracker
end

-- Update AI behavior. Simple 3-state machine: Idle -> Walking -> Attacking.
-- No PathfindingService, no Humanoid velocity -- StepToward/FaceToward
-- (direct PivotTo) is the only thing that ever moves or rotates the model.
function MobClass:UpdateAI(deltaTime, players, activeMobs)
    if not self.Model or self.CurrentHealth <= 0 then
        return
    end
    if self.IsSpawnStunned then
        MobAnimController.setWalking(self, false)
        return
    end

    local primaryPart = self.Model.PrimaryPart
    if not primaryPart then
        return
    end

    self._activeMobsRef = activeMobs

    local currentPosition = primaryPart.Position

    if self.AIState == "Idle" then
        self:HandleIdle(players, currentPosition)
    elseif self.AIState == "Walking" then
        self:HandleWalking(deltaTime, players, currentPosition)
    elseif self.AIState == "Attacking" then
        self:HandleAttacking(players, currentPosition)
    end
end

-- A player must be both within AggroRange of the mob's current position AND
-- within ReturnDistance of the mob's spawn (its "home zone") to be
-- acquired. If the player is already outside the zone, the mob does not
-- aggro onto them in the first place -- physical proximity alone is not
-- enough to start a chase, only to continue one (see HandleWalking).
function MobClass:FindClosestAggroTarget(players, currentPosition)
    local closestPlayer = nil
    local closestDistance = self.Stats.AggroRange

    for _, player in ipairs(players) do
        local character = player.Character
        if character then
            local hrp = character:FindFirstChild("HumanoidRootPart")
            local humanoid = character:FindFirstChildOfClass("Humanoid")

            if hrp and humanoid and humanoid.Health > 0 then
                local distance = (currentPosition - hrp.Position).Magnitude
                local distanceFromSpawn = (hrp.Position - self.SpawnPosition).Magnitude
                if distance < closestDistance and distanceFromSpawn <= self.Stats.ReturnDistance then
                    closestDistance = distance
                    closestPlayer = player
                end
            end
        end
    end

    return closestPlayer, closestDistance
end

function MobClass:TryAcquireTarget(players, currentPosition)
    local closestPlayer = self:FindClosestAggroTarget(players, currentPosition)
    if not closestPlayer then
        return false
    end

    self.TargetPlayer = closestPlayer
    self.AIState = "Walking"
    return true
end

-- Waiting: watch for a player entering AggroRange.
function MobClass:HandleIdle(players, currentPosition)
    self:TryAcquireTarget(players, currentPosition)
end

-- Walking toward the player. Drops back to Idle (in place -- no "return to
-- spawn" walk in v1) if the target is lost or dead. Leaving the home zone
-- (ReturnDistance from spawn) does not instantly deaggro: physical distance
-- to the player takes priority. While still within LEASH_GRACE_PROXIMITY of
-- the player, the leash is ignored entirely. Only once the player is BOTH
-- outside the zone AND no longer physically close does a LEASH_GRACE_DURATION
-- countdown start, after which the mob gives up and goes Idle.
function MobClass:HandleWalking(deltaTime, players, currentPosition)
    if not self.TargetPlayer or not self.TargetPlayer.Character then
        self.TargetPlayer = nil
        self.AIState = "Idle"
        self._leashGraceStartedAt = nil
        MobAnimController.setWalking(self, false)
        return
    end

    local targetHRP = self.TargetPlayer.Character:FindFirstChild("HumanoidRootPart")
    local targetHumanoid = self.TargetPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not targetHRP or not targetHumanoid or targetHumanoid.Health <= 0 then
        self.TargetPlayer = nil
        self.AIState = "Idle"
        self._leashGraceStartedAt = nil
        MobAnimController.setWalking(self, false)
        return
    end

    local distanceToTarget = (currentPosition - targetHRP.Position).Magnitude
    local distanceFromSpawn = (currentPosition - self.SpawnPosition).Magnitude

    if distanceFromSpawn > self.Stats.ReturnDistance then
        if distanceToTarget <= LEASH_GRACE_PROXIMITY then
            -- Still right on the player despite being past the zone -- hold off.
            self._leashGraceStartedAt = nil
        else
            local now = tick()
            self._leashGraceStartedAt = self._leashGraceStartedAt or now
            if now - self._leashGraceStartedAt >= LEASH_GRACE_DURATION then
                self.TargetPlayer = nil
                self.AIState = "Idle"
                self._leashGraceStartedAt = nil
                MobAnimController.setWalking(self, false)
                return
            end
        end
    else
        self._leashGraceStartedAt = nil
    end

    if distanceToTarget <= self.Stats.AttackRange then
        self.AIState = "Attacking"
        MobAnimController.setWalking(self, false)
        return
    end

    MobAnimController.setWalking(self, true)
    self:Move(targetHRP.Position, deltaTime)
end

-- In range: stop, face the player, attack on cooldown. Getting hit cancels
-- the swing animation (see TakeDamage) but never blocks the attempt itself,
-- so a mob already in range still lands its own hit even mid-flinch.
function MobClass:HandleAttacking(players, currentPosition)
    if not self.TargetPlayer or not self.TargetPlayer.Character then
        self.TargetPlayer = nil
        self.AIState = "Idle"
        return
    end

    local targetHRP = self.TargetPlayer.Character:FindFirstChild("HumanoidRootPart")
    local targetHumanoid = self.TargetPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not targetHRP or not targetHumanoid or targetHumanoid.Health <= 0 then
        self.TargetPlayer = nil
        self.AIState = "Idle"
        return
    end

    self:FaceToward(targetHRP.Position)

    local distanceToTarget = (currentPosition - targetHRP.Position).Magnitude
    if distanceToTarget > self.Stats.AttackRange * ATTACK_RANGE_LEEWAY then
        self.AIState = "Walking"
        return
    end

    local now = tick()
    if now - self.LastAttackTime >= self.Stats.AttackCooldown then
        self:PerformAttack(targetHumanoid)
        self.LastAttackTime = now
    end
end

-- Perform attack on target
-- Routes through DamageService so player armor reduces incoming damage and
-- the player profile HP stays in sync with the Humanoid.
function MobClass:PerformAttack(targetHumanoid)
    if self.IsSpawnStunned then return end
    if not targetHumanoid or targetHumanoid.Health <= 0 then return end
    MobAnimController.playAttack(self)
    local char = targetHumanoid.Parent
    local player = char and Players:GetPlayerFromCharacter(char)
    if player then
        DamageService.ApplyToPlayer(player, self.Stats.BaseDamage, self)
        self:ApplyPlayerHitstun(char)
    else
        -- NPC target (no player profile). Fall back to direct.
        targetHumanoid:TakeDamage(self.Stats.BaseDamage)
    end
end

-- Small hop + outward push on the player when hit -- just enough to
-- interrupt their movement slightly. A one-time AssemblyLinearVelocity add
-- does NOT work here: confirmed by direct testing that Roblox's player
-- Humanoid controller zeroes it out the very next physics step (the same
-- class of problem as mob locomotion, just on the player's side this time).
-- A BodyVelocity re-asserts the push every step for a short duration, which
-- wins against that correction -- confirmed by testing to produce real,
-- if small, displacement. Self-destructs via Debris so it never lingers.
local Debris = game:GetService("Debris")
function MobClass:ApplyPlayerHitstun(playerCharacter)
    local hrp = playerCharacter:FindFirstChild("HumanoidRootPart")
    if not hrp or not self.Model then
        return
    end
    local primaryPart = self.Model.PrimaryPart
    if not primaryPart then
        return
    end

    local horizontal = Vector3.new(hrp.Position.X - primaryPart.Position.X, 0, hrp.Position.Z - primaryPart.Position.Z)
    local dir = horizontal.Magnitude > 0.1 and horizontal.Unit or Vector3.new(0, 0, 1)

    local bv = Instance.new("BodyVelocity")
    bv.Velocity = Vector3.new(dir.X * PLAYER_HIT_KNOCKBACK_HORIZONTAL, PLAYER_HIT_KNOCKBACK_VERTICAL, dir.Z * PLAYER_HIT_KNOCKBACK_HORIZONTAL)
    bv.MaxForce = Vector3.new(4000, 4000, 4000)
    bv.P = 1250
    bv.Parent = hrp
    Debris:AddItem(bv, 0.15)
end

function MobClass:SetSpawnIntroState(active)
    local on = (active == true)
    self.IsSpawnStunned = on
    self.IsInvulnerable = on
    if on then
        self.AIState = "Idle"
        self.TargetPlayer = nil
    end
end

-- Get current position
function MobClass:GetPosition()
    if self.Model then
        local primaryPart = self.Model.PrimaryPart or self.Model:FindFirstChildWhichIsA("BasePart")
        if primaryPart then
            return primaryPart.Position
        end
    end
    return self._deathPosition
end

-- Check if mob is alive
function MobClass:IsAlive()
    return self.Model ~= nil and self.CurrentHealth > 0
end

return MobClass