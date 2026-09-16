-- MobClass ModuleScript
-- OOP Metatable blueprint for an active mob
-- Lives only in server memory

local MobClass = {}
MobClass.__index = MobClass

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local MOB_COLLISION_GROUP = "DungeonMobs"

-- Named-elite outline color (Kane the Enraged and any future named-elite
-- character mobs, gated on MobData's IsNamedElite flag -- see ConfigureModel
-- below). Same Highlight-based "trace the real silhouette" technique
-- WorldLootService.lua's attachOutline() already uses for elite/rare item
-- drops, just recolored -- keeps the visual language consistent between
-- "this is special loot" and "this is a special mob".
local NAMED_ELITE_OUTLINE_COLOR = Color3.fromRGB(255, 140, 0)

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
-- 2026-09-09: briefly restored to 1.5 after 0.6 read as imperceptible
-- against MoveSpeed 8-16, then brought back down to 0.5 per direct request
-- once the actual bug (HoppingMobClass silently overwriting ApplyKnockback's
-- PivotTo every Heartbeat -- see ApplyKnockback below) was fixed; with that
-- fixed, even a small nudge reads correctly instead of vanishing outright.
-- Tune this one constant if playtesting wants it stronger/weaker.
local KNOCKBACK_DISTANCE = 0.5 -- studs, one-time positional nudge away from attacker
local ATTACK_RANGE_LEEWAY = 1.3 -- multiplier before giving up attack range and resuming walk
local MELEE_VERTICAL_REACH = 2 -- studs beyond the bodies' vertical bounds; never an infinite column
local MOB_COLLISION_RADIUS = 3 -- studs; mobs push apart instead of overlapping
local SEPARATION_STEP_MULT = 1.5 -- studs/sec headroom over MoveSpeed for a separation correction (see ClampSeparationPush)
local LEASH_GRACE_DURATION = 1.0 -- seconds a mob may stay aggro'd past ReturnDistance if still close to the target
local LEASH_GRACE_PROXIMITY = 12 -- studs; "physically close enough" to ignore the leash during the grace window
local PLAYER_HIT_KNOCKBACK_HORIZONTAL = 4 -- studs/s impulse added to the player on being hit
local PLAYER_HIT_KNOCKBACK_VERTICAL = 8 -- studs/s upward impulse -- a small hop, just enough to interrupt movement
local ATTACK_SLOT_COUNT = 8 -- evenly-spaced "seats" per ring around an attack target (see acquireAttackSlot)
local ATTACK_SLOT_RING_STEP = MOB_COLLISION_RADIUS * 2.2 -- studs between concentric rings once a ring's seats are full
local DEFAULT_ATTACK_ANIM_DURATION = 0.4 -- seconds; fallback for a mob whose attack has no measurable length yet (see PerformAttack)

ensureMobCollisionGroup()

local MobData = require(ReplicatedStorage:WaitForChild("MobData"))
local CombatSfxConfig = require(ReplicatedStorage:WaitForChild("CombatSfxConfig"))
local DamageService = require(script.Parent:WaitForChild("DamageService"))
local MobAnimController = require(script.Parent:WaitForChild("MobAnimController"))
local MobHPBarUI = require(script.Parent:WaitForChild("MobHPBarUI"))
local MobGroundUtils = require(script.Parent:WaitForChild("MobGroundUtils"))
local MobDeathEffect = require(script.Parent:WaitForChild("MobDeathEffect"))

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
    self:ApplyDungeonScaling()


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

    -- Named elites (Kane the Enraged, etc -- MobData's IsNamedElite flag)
    -- get a standing orange outline so they read as distinct from regular
    -- mobs at a glance, same Highlight technique WorldLootService uses for
    -- elite item-drop outlines. FillTransparency = 1 means no color wash
    -- over the mesh, just the traced edge -- doesn't affect the mesh's own
    -- material/texture, so it costs nothing else to add.
    if self.Stats and self.Stats.IsNamedElite then
        local outline = Instance.new("Highlight")
        outline.Name = "NamedEliteOutline"
        outline.Adornee = model
        outline.FillTransparency = 1
        outline.OutlineColor = NAMED_ELITE_OUTLINE_COLOR
        outline.OutlineTransparency = 0
        outline.DepthMode = Enum.HighlightDepthMode.Occluded
        outline.Parent = model
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
                -- Anchored so the ONLY thing that ever moves this part is our
                -- own Model:PivotTo() calls -- never real physics, and never
                -- Humanoid's own hip-height hover controller. That hover
                -- controller is exactly what the comment above already warns
                -- about ("hovers HumanoidRootPart at HipHeight above whatever
                -- surface it detects"), and with CanCollide=true here too,
                -- the two were compounding: physics settles the root's own
                -- collision box onto the ground, then Humanoid ALSO tries to
                -- hover HipHeight above THAT already-rested surface, adding a
                -- second, redundant lift on top of the first -- a real,
                -- consistently-reproduced ~1 stud gap between the visible
                -- mesh and the actual floor on flat ground (2026-09-09, per
                -- direct request: "on flat grassy areas the slimes aren't
                -- directly on the ground"). Anchoring removes the part from
                -- both systems entirely; CanCollide=true is untouched so the
                -- player still can't walk through a mob, and knockback/
                -- movement/ground-snapping all already go through PivotTo
                -- (see ApplyKnockback, StepToward, HoppingMobClass:Move)
                -- rather than relying on the part being physics-movable.
                descendant.Anchored = true
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
-- Separation radius for crowd resolution. Derived from the model's footprint
-- rather than a flat constant: a 57-stud boss and a 4-stud slime previously
-- used the SAME radius of 3, which is why Miasma had no presence in a crowd
-- and slimes spawned on top of each other never pushed apart.
function MobClass:SeparationRadius()
    if self._sepRadius then return self._sepRadius end
    local r = MOB_COLLISION_RADIUS
    local model = self.Model
    if model and model:IsA("Model") then
        local ok, size = pcall(function() return model:GetExtentsSize() end)
        if ok and size then
            r = math.max(MOB_COLLISION_RADIUS, (size.X + size.Z) * 0.25)
        end
    end
    self._sepRadius = r
    return r
end

-- "Mass" for push arbitration. Bigger mobs shove smaller ones and barely move
-- themselves -- the boss should not get jostled by trash. Scales with footprint
-- area, so the difference is pronounced rather than marginal.
function MobClass:SeparationMass()
    local r = self:SeparationRadius()
    return r * r
end

-- Nudge a desired (x, z) out of any other alive mob's personal space.
--
-- Push is now WEIGHTED, not symmetric: each mob yields in proportion to the
-- other's mass, so a slime walking into Miasma gets moved almost the whole
-- overlap while Miasma barely registers it. Two equal slimes still split it
-- 50/50 and settle instead of oscillating.
function MobClass:ResolveMobSeparation(x, z)
    local activeMobs = self._activeMobsRef
    if not activeMobs then
        return x, z
    end

    local myRadius = self:SeparationRadius()
    local myMass   = self:SeparationMass()

    local pushX, pushZ = 0, 0
    for _, otherMob in pairs(activeMobs) do
        if otherMob ~= self and otherMob.IsAlive and otherMob:IsAlive() and otherMob.Model then
            local otherPart = otherMob.Model.PrimaryPart
            if otherPart then
                local otherRadius = otherMob.SeparationRadius
                    and otherMob:SeparationRadius() or MOB_COLLISION_RADIUS
                local minDist = myRadius + otherRadius

                local dx = x - otherPart.Position.X
                local dz = z - otherPart.Position.Z
                local dist = math.sqrt(dx * dx + dz * dz)

                if dist > 0.001 and dist < minDist then
                    local overlap = minDist - dist
                    local otherMass = otherMob.SeparationMass
                        and otherMob:SeparationMass() or (MOB_COLLISION_RADIUS * MOB_COLLISION_RADIUS)

                    -- Share of the overlap THIS mob yields. Heavier neighbour
                    -- -> larger share for us. Equal mass -> 0.5 each.
                    local yield = otherMass / (myMass + otherMass)

                    pushX += (dx / dist) * overlap * yield
                    pushZ += (dz / dist) * overlap * yield
                elseif dist <= 0.001 then
                    -- Exactly co-located (spawned on the same point): nudge on a
                    -- deterministic-but-varied bearing so the stack fans out
                    -- instead of every mob picking the same escape direction.
                    -- UID is a STRING id, not a number. Hash it to a stable
                    -- numeric bearing so co-located mobs fan out on different
                    -- headings instead of all escaping the same way.
                    local seed = 0
                    for i = 1, #tostring(self.UID or "") do
                        seed = (seed * 31 + string.byte(tostring(self.UID), i)) % 100003
                    end
                    local a = (seed * 2.399963) % (math.pi * 2)
                    pushX += math.cos(a) * minDist * 0.5
                    pushZ += math.sin(a) * minDist * 0.5
                end
            end
        end
    end

    return x + pushX, z + pushZ
end

-- ResolveMobSeparation's push is an unbounded sum over every overlapping
-- neighbour -- fine when there's one neighbour, but with three or more mobs
-- clustered on the same player (exactly the "gather around the player"
-- case) the pushes stack, and applying an unclamped result through a single
-- instant PivotTo reads as a teleport rather than a shove. This caps any
-- separation-induced displacement to what the mob could actually cover in
-- one tick at MoveSpeed (with a little headroom), the same clamp
-- SettleSeparation always used for the "standing still, unstacking from a
-- pile" case -- now shared so every caller that resolves separation gets a
-- smooth correction instead of a snap.
--
-- baseX/baseZ: position before separation was applied.
-- pushedX/pushedZ: position ResolveMobSeparation returned.
-- Returns a position no further from base than one clamped step allows.
function MobClass:ClampSeparationPush(baseX, baseZ, pushedX, pushedZ, deltaTime)
    local dx, dz = pushedX - baseX, pushedZ - baseZ
    local magSq = dx * dx + dz * dz
    if magSq < 0.0004 then
        return pushedX, pushedZ
    end

    local maxStep = (self.Stats and self.Stats.MoveSpeed or 8) * (deltaTime or 0.033) * SEPARATION_STEP_MULT
    local mag = math.sqrt(magSq)
    if mag > maxStep then
        dx, dz = dx / mag * maxStep, dz / mag * maxStep
    end

    return baseX + dx, baseZ + dz
end

-- Run separation even when standing still. Previously this only happened
-- inside StepToward, so a group that spawned stacked would sit in the pile
-- forever because nobody was walking.
function MobClass:SettleSeparation(deltaTime)
    if not self.Model then return end
    local part = self.Model.PrimaryPart
    if not part then return end

    local x, z = part.Position.X, part.Position.Z
    local nx, nz = self:ResolveMobSeparation(x, z)
    nx, nz = self:ClampSeparationPush(x, z, nx, nz, deltaTime)

    local dx, dz = nx - x, nz - z
    if (dx * dx + dz * dz) < 0.0004 then
        return
    end

    local targetX, targetZ = x + dx, z + dz
    local y = self:FindGroundY(targetX, targetZ, part.Position.Y)
    self.Model:PivotTo(CFrame.new(targetX, y, targetZ) * (part.CFrame - part.Position))
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

    -- Clamp the separation contribution the same way SettleSeparation does --
    -- otherwise a mob overlapping several neighbours at once (several mobs
    -- converging on the player) can get shoved an unbounded distance in a
    -- single PivotTo, which reads as a teleport rather than a shove.
    local preSepX, preSepZ = newX, newZ
    newX, newZ = self:ResolveMobSeparation(newX, newZ)
    newX, newZ = self:ClampSeparationPush(preSepX, preSepZ, newX, newZ, deltaTime)

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
--
-- Found 2026-09-09 (direct report: "plains slime should take knockback, can
-- u check"): a mob mid-hop (HoppingMobClass) doesn't read its live position
-- each tick the way StepToward does -- Move() recomputes position purely
-- from the stored _hopStartPos/_hopGoalPos anchors every Heartbeat while
-- _hopEndTime is set, so a PivotTo here got silently overwritten on the very
-- next tick. Since a hop lasts far longer than the pause between hops, a
-- landed hit almost always arrives mid-air, which made knockback look
-- completely absent for any hopping mob even though this function was
-- firing correctly. Fix: when a hop is in flight, translate its own anchor
-- points by the knockback offset instead of PivotTo-ing the model directly,
-- so the in-flight arc continues from a shifted path rather than fighting
-- back to the original one.
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
    local offsetX, offsetZ = dir.X * nudge, dir.Z * nudge

    if self._hopEndTime and self._hopStartPos and self._hopGoalPos then
        self._hopStartPos = Vector3.new(self._hopStartPos.X + offsetX, self._hopStartPos.Y, self._hopStartPos.Z + offsetZ)
        self._hopGoalPos = Vector3.new(self._hopGoalPos.X + offsetX, self._hopGoalPos.Y, self._hopGoalPos.Z + offsetZ)
        return
    end

    local newX = pos.X + offsetX
    local newZ = pos.Z + offsetZ
    local groundY = self:FindGroundY(newX, newZ, pos.Y)
    local newPos = Vector3.new(newX, groundY + (self._feetToRootHeight or 0), newZ)

    local _, yaw = primaryPart.CFrame:ToEulerAnglesYXZ()
    self.Model:PivotTo(CFrame.new(newPos) * CFrame.Angles(0, yaw, 0))
end

-- Create HP bar above mob. Actual UI construction lives in MobHPBarUI so
-- this file stays focused on AI/combat/spawning, not BillboardGui layout.
function MobClass:CreateHPBar()
    -- Named elites (Kane the Enraged, etc) get the dedicated top-middle
    -- BossHealthBar.client.lua UI instead -- the normal floating "LVL n
    -- <Name>" billboard nameplate/HP bar above the mob's head is skipped
    -- entirely for them (per direct request). MobHPBarUI.Update already
    -- no-ops safely when mob.HPBar is nil, so nothing else needs to check
    -- this flag.
    if self.Stats and self.Stats.IsNamedElite then
        return nil
    end
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

-- Default hit sound: every mob plays the same shared "glass" clip
-- (CombatSfxConfig.MELEE_HIT_GLASS_SOUND_ID) unless a MobClassRegistry
-- subclass overrides this method with its own -- see SkeletonMobClass for
-- the template (mirrors how HoppingMobClass overrides Move() while
-- inheriting everything else). MobCombat.applyDamage calls mob:GetHitSoundId()
-- and sends whatever it returns to the attacking player's client.
function MobClass:GetHitSoundId()
    return CombatSfxConfig.MELEE_HIT_GLASS_SOUND_ID
end

-- Attack-slot registry: gives every mob walking toward the same player a
-- stable angular "seat" around them, instead of every mob's walk goal being
-- the player's exact position. ClampSeparationPush (above) only cleans up
-- overlap AFTER mobs have already piled onto the same spot -- it's a
-- reactive fix for the symptom. Slotting is the proactive half: it keeps
-- mobs from choosing to converge on one point in the first place, which is
-- what makes a pack surround a player in a clean ring instead of scrumming
-- into a single stack that separation then has to keep shoving apart
-- (2026-09-09, per direct request: "gather and collide cleanly like a group
-- of zombies hitting a player in Minecraft").
--
-- Keyed by Player instance (weak keys, so a player leaving the game doesn't
-- pin this table open) -> a sparse array of mob refs holding each slot index
-- (nil = free). A mob's own _attackSlot / _attackSlotPlayer fields record
-- what it currently holds, purely so it can find and clear its own entry
-- again without scanning every slot.
--
-- Declared here (above Die/GetHitSoundId) rather than down by
-- FindClosestAggroTarget/HandleWalking/HandleAttacking, which is where this
-- registry conceptually belongs -- Die() below is the first caller in file
-- order, and a Luau local is only visible to code that comes after its
-- declaration in the same chunk. Placing it below Die() silently resolved
-- `releaseAttackSlot`/`acquireAttackSlot` to globals (both nil) instead of
-- these locals, so every mob death threw "attempt to call a nil value" and
-- aborted Die() before the HP bar, model, and death snapshot cleanup ever
-- ran. Keep this block above every function that calls into it.
local slotRegistry = setmetatable({}, { __mode = "k" })

-- Drops whatever seat `mob` is holding (if any). Always safe to call even
-- if the mob holds nothing. Must be called before a mob stops targeting a
-- player (target lost/died, or the mob itself died) -- otherwise the slot
-- table keeps a live reference to a mob nothing will ever release, quietly
-- leaking a "taken" seat forever.
local function releaseAttackSlot(mob)
	local player = mob._attackSlotPlayer
	local slot = mob._attackSlot
	if player and slot ~= nil then
		local slots = slotRegistry[player]
		if slots and slots[slot] == mob then
			slots[slot] = nil
		end
	end
	mob._attackSlot = nil
	mob._attackSlotPlayer = nil
end

-- Returns the slot index `mob` should walk to relative to `player`, claiming
-- the next free one the first time (or instantly returning its existing
-- seat on repeat calls -- HandleWalking calls this every tick, so this must
-- be cheap and stable for a mob that already holds a slot on this player).
local function acquireAttackSlot(mob, player)
	if mob._attackSlotPlayer == player and mob._attackSlot ~= nil then
		return mob._attackSlot
	end
	releaseAttackSlot(mob)

	local slots = slotRegistry[player]
	if not slots then
		slots = {}
		slotRegistry[player] = slots
	end

	local index = 0
	while slots[index] do
		index += 1
	end

	slots[index] = mob
	mob._attackSlot = index
	mob._attackSlotPlayer = player
	return index
end

-- Turns a slot index into a flat (Y=0) world-space offset from the target:
-- ATTACK_SLOT_COUNT evenly-spaced angles per ring, then overflow mobs
-- (index >= ATTACK_SLOT_COUNT) spill onto a wider concentric ring so a pack
-- bigger than one ring's seats still spreads out radially instead of
-- stacking multiple mobs on the same angle.
local function attackSlotOffset(index, radius)
	local ring = math.floor(index / ATTACK_SLOT_COUNT)
	local angleIndex = index % ATTACK_SLOT_COUNT
	local angle = (angleIndex / ATTACK_SLOT_COUNT) * math.pi * 2
	local ringRadius = radius + ring * ATTACK_SLOT_RING_STEP
	return Vector3.new(math.cos(angle) * ringRadius, 0, math.sin(angle) * ringRadius)
end

-- Die method
function MobClass:Die()
    -- Release any attack-slot seat this mob was holding so a dead mob's
    -- table doesn't sit in slotRegistry forever as a permanently "taken"
    -- seat nothing will ever free (see acquireAttackSlot).
    releaseAttackSlot(self)

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
        local mdl = self.Model
        self.Model = nil -- unchanged: IsAlive()/UpdateAI etc. still see "no model" immediately

        -- Spawn the red-silhouette death effect from the model's exact
        -- final pose BEFORE anything below tears it down (Debris just
        -- defers the real destruction, but MobDeathEffect.Play clones mdl
        -- synchronously right now, so it must run first regardless).
        local okFx, fxErr = pcall(function()
            MobDeathEffect.Play(mdl)
        end)
        if not okFx then
            warn("MobClass: MobDeathEffect.Play failed: " .. tostring(fxErr))
        end

        -- NOT self.Model:Destroy() here. TakeDamage() (our caller) is called
        -- from MobCombat.applyDamage, which fires the killing blow's
        -- DamageNumberEvent to the client right after TakeDamage() returns --
        -- still referencing this same Model instance. Destroying it
        -- synchronously in this same call stack invalidates the Instance
        -- before Roblox's networking layer actually replicates that
        -- FireClient call, so the reference arrives as nil and the damage
        -- number silently never shows up on a kill. A prior fix attempt
        -- (see the comment in MobCombat.applyDamage) only snapshotted
        -- mob.Model into a local variable before calling TakeDamage -- that
        -- stops mob.Model itself from reading nil afterward, but does
        -- nothing about the underlying Instance being torn down out from
        -- under that reference. Debris just gives the network a beat to
        -- flush before the Instance actually goes away; 0.2s is well past
        -- any replication delay and short enough that the frozen corpse
        -- pose isn't noticeable before it vanishes.
        Debris:AddItem(mdl, 0.2)
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

    self._lastDeltaTime = deltaTime
    self._activeMobsRef = activeMobs

    -- Crowd resolution runs every tick regardless of AI state, so a group
    -- that spawned stacked unpacks itself instead of sitting in the pile.
    self:SettleSeparation(deltaTime)

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
-- Override point for ambient idle movement. Base mobs stand still; a
-- subclass (e.g. HoppingMobClass) can wander here. Called every tick while
-- Idle, AFTER target acquisition, so a mob that just aggro'd doesn't waste
-- a tick wandering.
function MobClass:IdleBehaviour(deltaTime, currentPosition)
end

function MobClass:HandleIdle(players, currentPosition)
    self:TryAcquireTarget(players, currentPosition)
    if self.AIState == "Idle" then
        self:IdleBehaviour(self._lastDeltaTime or 0.033, currentPosition)
    end
end

local function verticalBounds(cf, size)
    local half = size * 0.5
    local extent = math.abs(cf.RightVector.Y) * half.X
        + math.abs(cf.UpVector.Y) * half.Y + math.abs(cf.LookVector.Y) * half.Z
    return cf.Position.Y - extent, cf.Position.Y + extent
end

-- Use actual body height, not root-to-root Y distance: small slimes and
-- tall bosses have different root offsets. Held tools/accessories must not
-- enlarge the player's hurtbox, so only direct character body parts count.
function MobClass:IsTargetWithinMeleeReach(targetHumanoid, horizontalLeeway)
    if not self:IsAlive() or self.IsSpawnStunned or not self.Model.Parent then return false end
    if not targetHumanoid or targetHumanoid.Health <= 0 then return false end
    local character = targetHumanoid.Parent
    if not character or not character:IsDescendantOf(workspace) then return false end
    local root = self.Model.PrimaryPart
    local targetRoot = character:FindFirstChild("HumanoidRootPart")
    if not root or not targetRoot then return false end
    local delta = root.Position - targetRoot.Position
    local reach = (self.Stats.AttackRange + self:GetHitRadius()) * (horizontalLeeway or 1)
    if delta.X * delta.X + delta.Z * delta.Z > reach * reach then return false end

    local mobCF, mobSize = self.Model:GetBoundingBox()
    local mobMin, mobMax = verticalBounds(mobCF, mobSize)
    local targetMin, targetMax = verticalBounds(targetRoot.CFrame, targetRoot.Size)
    for _, part in ipairs(character:GetChildren()) do
        if part:IsA("BasePart") and part.Transparency < 1 then
            local low, high = verticalBounds(part.CFrame, part.Size)
            targetMin, targetMax = math.min(targetMin, low), math.max(targetMax, high)
        end
    end
    return targetMin <= mobMax + MELEE_VERTICAL_REACH
        and targetMax >= mobMin - MELEE_VERTICAL_REACH
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
        releaseAttackSlot(self)
        self.TargetPlayer = nil
        self.AIState = "Idle"
        self._leashGraceStartedAt = nil
        MobAnimController.setWalking(self, false)
        return
    end

    local targetHRP = self.TargetPlayer.Character:FindFirstChild("HumanoidRootPart")
    local targetHumanoid = self.TargetPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not targetHRP or not targetHumanoid or targetHumanoid.Health <= 0 then
        releaseAttackSlot(self)
        self.TargetPlayer = nil
        self.AIState = "Idle"
        self._leashGraceStartedAt = nil
        MobAnimController.setWalking(self, false)
        return
    end

    -- Keep flat distance for approach/leash behavior. Melee separately checks
    -- body bounds in Y, avoiding both root-height mismatches and infinite reach.
    local dtx, dtz = currentPosition.X - targetHRP.Position.X, currentPosition.Z - targetHRP.Position.Z
    local distanceToTarget = math.sqrt(dtx * dtx + dtz * dtz)
    local distanceFromSpawn = (currentPosition - self.SpawnPosition).Magnitude

    if distanceFromSpawn > self.Stats.ReturnDistance then
        if distanceToTarget <= LEASH_GRACE_PROXIMITY then
            -- Still right on the player despite being past the zone -- hold off.
            self._leashGraceStartedAt = nil
        else
            local now = tick()
            self._leashGraceStartedAt = self._leashGraceStartedAt or now
            if now - self._leashGraceStartedAt >= LEASH_GRACE_DURATION then
                releaseAttackSlot(self)
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

    -- Gated on `not self._hopEndTime`: a hop that's already mid-arc must be
    -- allowed to land before the state machine hands off to Attacking.
    -- Without this, a mob that enters attack range while airborne (its
    -- Move() call is what advances the arc -- HandleAttacking never calls
    -- Move at all) would simply stop being ticked mid-flight and hang
    -- frozen at whatever height the arc had reached the instant the state
    -- flipped -- exactly the "not directly on the ground" floating-slime
    -- symptom, alongside making walk and attack visuals overlap (2026-09-09,
    -- per direct request: a move must ATOMICALLY finish -- land -- before
    -- switching into an attack).
    if not self._hopEndTime and self:IsTargetWithinMeleeReach(targetHumanoid) then
        self.AIState = "Attacking"
        MobAnimController.setWalking(self, false)
        return
    end

    MobAnimController.setWalking(self, true)

    -- Walk toward this mob's own seat around the target instead of the
    -- target's exact position -- see acquireAttackSlot above. The seat
    -- sits just inside AttackRange so reaching it reliably flips the mob
    -- into Attacking on the very next tick (the check above compares real
    -- distance to the target, not to the slot).
    local slotIndex = acquireAttackSlot(self, self.TargetPlayer)
    local approachRadius = math.max(self.Stats.AttackRange * 0.8, self:GetHitRadius())
    local goalPosition = targetHRP.Position + attackSlotOffset(slotIndex, approachRadius)
    self:Move(goalPosition, deltaTime)
end

-- In range: stop, face the player, attack on cooldown. Getting hit cancels
-- the swing animation (see TakeDamage) but never blocks the attempt itself,
-- so a mob already in range still lands its own hit even mid-flinch.
function MobClass:HandleAttacking(players, currentPosition)
    if not self.TargetPlayer or not self.TargetPlayer.Character then
        releaseAttackSlot(self)
        self.TargetPlayer = nil
        self.AIState = "Idle"
        return
    end

    local targetHRP = self.TargetPlayer.Character:FindFirstChild("HumanoidRootPart")
    local targetHumanoid = self.TargetPlayer.Character:FindFirstChildOfClass("Humanoid")
    if not targetHRP or not targetHumanoid or targetHumanoid.Health <= 0 then
        releaseAttackSlot(self)
        self.TargetPlayer = nil
        self.AIState = "Idle"
        return
    end

    self:FaceToward(targetHRP.Position)

    local now = tick()

    -- Same atomicity rule as the hop-landing guard above, applied to the
    -- attack swing itself: self._attackLockedUntil (set in PerformAttack,
    -- below) covers exactly how long the attack's visual takes to play out.
    -- Refusing to leave Attacking before that expires is what stops a mob
    -- from sliding/hopping away mid-swing -- previously the distance check
    -- alone could flip AIState to Walking the instant the player backed off,
    -- even with the squash-and-stretch (or Animator) attack track still
    -- mid-play (2026-09-09, per direct request: an attack must ATOMICALLY
    -- finish playing before any other state becomes reachable).
    local attackLocked = self._attackLockedUntil and now < self._attackLockedUntil

    -- Keep horizontal hysteresis for stable attack seating, but never expand
    -- vertical reach. Finishing an animation lock does not guarantee a hit.
    if not attackLocked and not self:IsTargetWithinMeleeReach(targetHumanoid, ATTACK_RANGE_LEEWAY) then
        self.AIState = "Walking"
        return
    end

    if attackLocked then
        return
    end

    if now - self.LastAttackTime >= self.Stats.AttackCooldown then
        -- HoppingMobClass:Move() tracks its own grounded/at-rest state via
        -- _hopEndTime -- set while mid-arc, nil once landed and paused. Bail
        -- here WITHOUT consuming the cooldown so a hopping mob still fires
        -- its attack the instant it lands rather than skipping a whole
        -- cooldown window (2026-09-08, per direct request: mobs shouldn't
        -- be able to fire the attack animation unless they're at rest in
        -- their own move state machine, not mid-hop in the air).
        -- self._hopEndTime is always nil for non-hopping mobs, so this is a
        -- no-op for every mob that doesn't use HoppingMobClass.
        if self._hopEndTime then
            return
        end
        if self:PerformAttack(targetHumanoid) then
            self.LastAttackTime = now
        end
    end
end

-- Perform attack on target
-- Routes through DamageService so player armor reduces incoming damage and
-- the player profile HP stays in sync with the Humanoid.
function MobClass:PerformAttack(targetHumanoid)
    if not self:IsTargetWithinMeleeReach(targetHumanoid) then return false end
    local targetCharacter = targetHumanoid.Parent
    local targetPlayer = Players:GetPlayerFromCharacter(targetCharacter)
    MobAnimController.playAttack(self)

    -- Starts the atomic attack-lock window HandleAttacking checks above.
    -- _attackAnimDuration is cached once at spawn by MobAnimController.attach
    -- (the ScriptedBody squash/pop/recover pulse's own total length, or a
    -- loaded Animator track's real Length) so this always matches however
    -- long the attack actually plays, rather than a guessed fixed number.
    self._attackLockedUntil = tick() + (self._attackAnimDuration or DEFAULT_ATTACK_ANIM_DURATION)

    local function applyDamage()
        -- Recheck at the hit frame: jumping, backing away, teleporting or
        -- respawning during the windup must avoid both damage and hitstun.
        if not self:IsTargetWithinMeleeReach(targetHumanoid) then return end
        if targetPlayer and targetPlayer.Character ~= targetCharacter then return end
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

    -- Mobs with an AttackHitFrame configured (see MobAnimConfig) land their
    -- damage in sync with the swing animation instead of instantly on
    -- attack start -- e.g. Plains Slime's damage lands at frame 13 of its
    -- attack anim (2026-09-08, per direct request). Every other mob keeps
    -- the original instant-hit behavior since self._attackHitDelay is nil
    -- for them.
    if self._attackHitDelay then
        local attackTrack = self._animTracks and self._animTracks.Attack
        task.delay(self._attackHitDelay, function()
            if not self.Model then return end -- mob died mid-swing
            if attackTrack and not attackTrack.IsPlaying then return end -- swing got interrupted (see TakeDamage)
            if targetHumanoid.Health <= 0 then return end -- target already dead/gone
            applyDamage()
        end)
    else
        applyDamage()
    end
    return true
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


-- Size-derived hit radius. Both combat directions historically measured to
-- mob:GetPosition(), which is the HumanoidRootPart -- the model's CENTRE.
-- That is fine for a 5-stud slime but nonsense for a 57-stud boss, where the
-- centre sits ~30 studs inside the mesh: the player had to stand inside its
-- mouth to land a hit, and vice versa. This returns the horizontal half-
-- extent of the model so callers can treat range as surface-to-surface
-- instead of centre-to-centre. Cached -- extents don't change at runtime.
-- Dungeon party HP scaling. Applied once at construction so a mob spawned
-- inside an active run is tougher with more players in it. Wrapped in pcall
-- because DungeonRunService is optional -- overworld mobs must be unaffected
-- if it never loaded.
function MobClass:ApplyDungeonScaling()
    local zone = self.SpawnerRef and self.SpawnerRef.ZoneName
    if type(zone) ~= "string" or not string.find(zone, "Dungeon", 1, true) then
        return
    end
    local ok, svc = pcall(function()
        return require(game:GetService("ServerScriptService"):WaitForChild("DungeonRunService", 5))
    end)
    if not ok or not svc then return end
    local scaling = svc.GetScaling and svc.GetScaling()
    if not scaling then return end

    local mult = scaling.HPMult or 1
    self.MaxHealth     = math.floor(self.MaxHealth * mult)
    self.CurrentHealth = self.MaxHealth
end

function MobClass:GetHitRadius()
    if self._hitRadius then
        return self._hitRadius
    end
    local model = self.Model
    if not model or not model:IsA("Model") then
        return 0
    end
    local ok, size = pcall(function() return model:GetExtentsSize() end)
    if not ok or not size then
        return 0
    end
    -- Horizontal half-extent, averaged so a long thin mob isn't over-rated.
    local r = (math.max(size.X, size.Z) * 0.5 + math.min(size.X, size.Z) * 0.5) * 0.5
    -- Small mobs keep their existing feel: only credit radius beyond ~3 studs.
    r = math.max(0, r - 3)
    self._hitRadius = r
    return r
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
