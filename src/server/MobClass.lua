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
local MOB_COLLISION_RADIUS = 3 -- studs; floor for SeparationRadius (boss bounds), NOT crowding (CROWD_* below)
local SEPARATION_STEP_MULT = 1.5 -- studs/sec headroom over MoveSpeed for a separation correction (see ClampSeparationPush)
local LEASH_GRACE_DURATION = 1.0 -- seconds a mob may stay aggro'd past ReturnDistance if still close to the target
local LEASH_GRACE_PROXIMITY = 12 -- studs; "physically close enough" to ignore the leash during the grace window
-- Never-deaggro re-target radius: covers a whole dungeon realm, but not other realms or
-- the overworld (realms are parked ~100k studs apart).
local NEVER_DEAGGRO_REACQUIRE_RANGE = 1500
local PLAYER_HIT_KNOCKBACK_HORIZONTAL = 4 -- studs/s impulse added to the player on being hit
local PLAYER_HIT_KNOCKBACK_VERTICAL = 8 -- studs/s upward impulse -- a small hop, just enough to interrupt movement
-- Both are the BASELINE every ordinary mob hit uses. A mob scales its own
-- outgoing knockback with MobData's PlayerKnockbackMultiplier (Kane hits much
-- harder than a slime), and one authored special can override that again with
-- its own PlayerKnockbackMultiplier -- see ApplyPlayerHitstun. That multiplier
-- is HORIZONTAL ONLY: the vertical hop above is the same for every mob.
-- NOT to be confused with MobData's KnockbackMultiplier, which is the opposite
-- direction: how much knockback the MOB takes when the player hits IT.
-- Crowding (2026-09-29 overhaul: "Minecraft-like" clumping, no seat rings). Mobs walk straight
-- at their target and only push EACH OTHER apart, softly: they may overlap part of their size,
-- and each tick resolves only a share of the rest, so a crowd reads as a loose huddle that
-- jostles instead of a rigid ring with gaps. Mobs never push the player (not yet, by request).
local CROWD_MIN_RADIUS = 1.2      -- studs: the smallest footprint any mob gets
local CROWD_BODY_FRACTION = 0.85  -- of the model's NARROWER half-extent (antlers/tails/weapons don't count)
local CROWD_OVERLAP = 0.2         -- share of two mobs' combined radii they may overlap before any push
                                  -- (two slimes: 6 studs apart with the old rigid radius, ~1.9 now)
local CROWD_STIFFNESS = 0.35      -- share of the remaining overlap resolved per tick (soft, not rigid)
local CROWD_PRIORITY_MASS = 4     -- elites and bosses weigh this much more: they keep right of way
-- Threat (2026-09-29): who a mob fights is decided by a per-player threat score, not just "whoever
-- hit last". Damage adds threat; threat fades (halves every THREAT_HALF_LIFE seconds), so recent
-- damage dominates and a burst from long ago barely counts. Another player takes the mob over
-- once their threat beats the current target's by THREAT_SWITCH_MARGIN; no minimum hold time.
-- If the target dies, leaves, spectates or gets out of reach, the mob falls back to the next
-- highest threat, and only then to plain proximity aggro. Elites and bosses react faster.
local THREAT_HALF_LIFE = 6          -- seconds
local THREAT_HALF_LIFE_PRIORITY = 4 -- elites / bosses
local THREAT_SWITCH_MARGIN = 1.2    -- challenger must exceed current x this
local THREAT_SWITCH_MARGIN_PRIORITY = 1.1
local THREAT_FORGET = 0.5           -- entries decayed below this are dropped
local CROWD_CELL = 8              -- spatial grid cell (studs); mobs with a radius over half a cell
                                  -- live in a small "large" list everyone checks
local FALL_RESCUE_DEPTH = 80 -- studs below its spawn before a mob is presumed to have fallen out of the world
local DEFAULT_ATTACK_ANIM_DURATION = 0.4 -- seconds; fallback for a mob whose attack has no measurable length yet (see PerformAttack)
-- How long an attack telegraph lingers past its impact before the server drops
-- the tag. The client fades its own mark on the same schedule (Tail in
-- MobTelegraphConfig); this is the authoritative cleanup behind it.
local TELEGRAPH_CLEAR_TAIL = 0.35

ensureMobCollisionGroup()

local MobData = require(ReplicatedStorage:WaitForChild("MobData"))
local CombatSfxConfig = require(ReplicatedStorage:WaitForChild("CombatSfxConfig"))
local DamageService = require(script.Parent:WaitForChild("DamageService"))
local MobAnimController = require(script.Parent:WaitForChild("MobAnimController"))
local MobTelegraph = require(script.Parent:WaitForChild("MobTelegraph"))
local MobHPBarUI = require(script.Parent:WaitForChild("MobHPBarUI"))
local MobGroundUtils = require(script.Parent:WaitForChild("MobGroundUtils"))
local MobDeathEffect = require(script.Parent:WaitForChild("MobDeathEffect"))
local CombatEnchantStatus = require(script.Parent:WaitForChild("CombatEnchantStatus"))

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
    -- Never-deaggro mobs (MobData NeverDeaggro, or anything from a spawner flagged
    -- NeverDeaggro: dungeon trash, dungeon bosses, encounter adds) ignore the
    -- ReturnDistance leash, and once engaged re-target the nearest living player
    -- within NEVER_DEAGGRO_REACQUIRE_RANGE instead of going idle.
    self.NeverDeaggro = statsCopy.NeverDeaggro == true or (spawnerRef ~= nil and spawnerRef.NeverDeaggro == true)

    -- Dynamic level override
    self.Level = tonumber(level) or self.Stats.Level
    self.Stats.Level = self.Level

    -- Authored fixed-stat elites can opt out; ordinary mobs keep level scaling.
    local levelMultiplier = self.Stats.ScaleWithLevel == false and 1 or (1 + self.Level * 0.1)
    
    -- Health tracking. HPScaleWithLevel = false fixes HP alone (damage keeps scaling).
    local hpMultiplier = self.Stats.HPScaleWithLevel == false and 1 or levelMultiplier
    self.MaxHealth = math.floor(self.Stats.BaseHP * hpMultiplier)
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

    local modelName = (self.Stats and self.Stats.ModelName) or self.MobID
    local modelTemplate = mobModelsFolder:FindFirstChild(modelName)
    if not modelTemplate then
        warn("MobClass: Model not found for MobID: " .. self.MobID .. " (model " .. tostring(modelName) .. ")")
        return nil
    end
    
    local model = modelTemplate:Clone()
    model.Name = self.UID
    model:SetAttribute("MobUID", self.UID)
    model:SetAttribute("MobID", self.MobID)
    model:SetAttribute("MobLevel", self.Level)

    -- Optional per-mob size multiplier (MobData ModelScale, e.g. 0.67 = 33% smaller). Applied
    -- BEFORE the feet-to-root measurement and grounding below, so every size-derived value
    -- (grounding, hit radius, VFX radius) sees the scaled model.
    local modelScale = tonumber(self.Stats and self.Stats.ModelScale)
    if modelScale and modelScale > 0 and modelScale ~= 1 and model:IsA("Model") then
        model:ScaleTo(modelScale)
    end

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

-- Last-resort recovery for a mob that has ended up under the map.
--
-- Nothing in the AI can climb back: FindGroundY keeps the current height when
-- its probe hits nothing, so a mob below the world stays below the world and
-- falls until Roblox's FallenPartsDestroyHeight destroys the model -- which
-- looks exactly like an unexplained despawn. The 2026-09-18 report (flying
-- above Kane) was one way in, fixed at the source in MobGroundUtils, but a mob
-- can reach the void by other means (thin geometry, a bad spawn point,
-- knockback off a ledge), so this catches all of them rather than that one.
function MobClass:RescueIfFallen(currentPosition)
    local spawnPosition = self.SpawnPosition
    if typeof(spawnPosition) ~= "Vector3" then
        return false
    end
    if currentPosition.Y > spawnPosition.Y - FALL_RESCUE_DEPTH then
        return false
    end

    local grounded = self:ResolveGroundedSpawnPosition(self.Model, spawnPosition)
    self.Model:PivotTo(CFrame.new(grounded))
    local primaryPart = self.Model.PrimaryPart
    if primaryPart then
        -- Drop the fall speed too, or it resumes plummeting from the new spot.
        primaryPart.AssemblyLinearVelocity = Vector3.zero
    end
    warn(string.format("[MobClass] %s fell to Y=%.1f (spawn Y=%.1f) -- returned to its spawn point",
        tostring(self.MobID), currentPosition.Y, spawnPosition.Y))
    return true
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

-- The body footprint used for crowding between mobs (NOT SeparationRadius, which bosses also
-- use for their movement bounds): a share of the model's narrower half-extent, so antlers,
-- tails and held weapons don't hold neighbours away. Cached; boss shrink rescales it.
function MobClass:CrowdRadius()
    if self._crowdRadius then return self._crowdRadius end
    local r = CROWD_MIN_RADIUS
    local model = self.Model
    if model and model:IsA("Model") then
        local ok, size = pcall(function() return model:GetExtentsSize() end)
        if ok and size then
            r = math.max(CROWD_MIN_RADIUS, math.min(size.X, size.Z) * 0.5 * CROWD_BODY_FRACTION)
        end
    end
    self._crowdRadius = r
    return r
end

-- Push weight: footprint area, with elites and bosses boosted so trash yields to them.
function MobClass:CrowdMass()
    if self._crowdMass then return self._crowdMass end
    local r = self:CrowdRadius()
    local stats = self.Stats or {}
    local priority = (stats.IsBoss or stats.IsNamedElite or stats.IsElite) and CROWD_PRIORITY_MASS or 1
    self._crowdMass = r * r * priority
    return self._crowdMass
end

-- Spatial grid of the living mobs, rebuilt once per MobManager tick (BuildCrowdGrid), so a mob
-- only checks neighbours in the 3x3 cells around it instead of every mob on the server.
local crowdGrid = {}      -- [cellKey] = { mob, ... }
local crowdLarge = {}     -- mobs too big for one cell; checked by everyone
local crowdGridReady = false
local crowdScratch = {}

local function crowdCellKey(cx, cz)
    return cx * 100003 + cz
end

function MobClass.BuildCrowdGrid(activeMobs)
    table.clear(crowdGrid)
    table.clear(crowdLarge)
    for _, mob in pairs(activeMobs) do
        local part = mob.Model and mob.Model.PrimaryPart
        if part and mob.IsAlive and mob:IsAlive() then
            if mob:CrowdRadius() > CROWD_CELL * 0.5 then
                table.insert(crowdLarge, mob)
            else
                local key = crowdCellKey(math.floor(part.Position.X / CROWD_CELL), math.floor(part.Position.Z / CROWD_CELL))
                local list = crowdGrid[key]
                if not list then
                    list = {}
                    crowdGrid[key] = list
                end
                table.insert(list, mob)
            end
        end
    end
    crowdGridReady = true
end

-- Mobs that could overlap (x, z): the 3x3 cells around it plus the large list. Before the
-- first grid build (or for a caller outside the manager tick) falls back to the full list.
local function crowdNeighbours(self, x, z)
    table.clear(crowdScratch)
    if not crowdGridReady then
        for _, other in pairs(self._activeMobsRef or {}) do table.insert(crowdScratch, other) end
        return crowdScratch
    end
    local cx, cz = math.floor(x / CROWD_CELL), math.floor(z / CROWD_CELL)
    for ix = cx - 1, cx + 1 do
        for iz = cz - 1, cz + 1 do
            local list = crowdGrid[crowdCellKey(ix, iz)]
            if list then
                for _, other in ipairs(list) do table.insert(crowdScratch, other) end
            end
        end
    end
    for _, other in ipairs(crowdLarge) do table.insert(crowdScratch, other) end
    return crowdScratch
end

-- The model's average half-extent (floored at MOB_COLLISION_RADIUS). No longer used for crowding
-- (see CrowdRadius); bosses still read it for their movement bounds and stun shrink.
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

-- Nudge a desired (x, z) out of neighbouring mobs, SOFTLY (see the CROWD_* constants): mobs may
-- overlap part of their footprint, and only CROWD_STIFFNESS of the remaining overlap is resolved
-- per tick. Weighted by CrowdMass, so trash walking into an elite or boss moves almost the whole
-- way while the big one barely registers it; two equal mobs split it and settle.
function MobClass:ResolveMobSeparation(x, z)
    local myRadius = self:CrowdRadius()
    local myMass = self:CrowdMass()

    local pushX, pushZ = 0, 0
    for _, otherMob in ipairs(crowdNeighbours(self, x, z)) do
        if otherMob ~= self and otherMob.IsAlive and otherMob:IsAlive() and otherMob.Model then
            local otherPart = otherMob.Model.PrimaryPart
            if otherPart then
                local otherRadius = otherMob.CrowdRadius and otherMob:CrowdRadius() or CROWD_MIN_RADIUS
                local minDist = (myRadius + otherRadius) * (1 - CROWD_OVERLAP)

                local dx = x - otherPart.Position.X
                local dz = z - otherPart.Position.Z
                local dist = math.sqrt(dx * dx + dz * dz)

                if dist > 0.001 and dist < minDist then
                    local otherMass = otherMob.CrowdMass and otherMob:CrowdMass() or (CROWD_MIN_RADIUS * CROWD_MIN_RADIUS)
                    -- Share of the overlap THIS mob yields: heavier neighbour -> larger share.
                    local yield = otherMass / (myMass + otherMass)
                    local amount = (minDist - dist) * yield * CROWD_STIFFNESS
                    pushX += (dx / dist) * amount
                    pushZ += (dz / dist) * amount
                elseif dist <= 0.001 then
                    -- Exactly co-located (spawned on the same point): fan out on a stable
                    -- per-mob bearing (UID is a string: hash it) instead of all the same way.
                    local seed = 0
                    for i = 1, #tostring(self.UID or "") do
                        seed = (seed * 31 + string.byte(tostring(self.UID), i)) % 100003
                    end
                    local a = (seed * 2.399963) % (math.pi * 2)
                    pushX += math.cos(a) * minDist * 0.5 * CROWD_STIFFNESS
                    pushZ += math.sin(a) * minDist * 0.5 * CROWD_STIFFNESS
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
        local moveSpeed = self:GetEffectiveMoveSpeed()
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
    humanoid.WalkSpeed = self:GetEffectiveMoveSpeed()
end

-- MoveSpeed after status effects. EVERY movement site goes through this rather
-- than reading Stats.MoveSpeed directly, or a slow would apply to some kinds of
-- movement and not others -- a slowed hopper would keep hopping the same
-- distance just as often. Returns the base speed unchanged when nothing applies.
function MobClass:GetEffectiveMoveSpeed()
    local base = (self.Stats and self.Stats.MoveSpeed) or 8
    return base * CombatEnchantStatus.GetSpeedMultiplier(self.Model)
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
    if self.Stats and (self.Stats.IsNamedElite or self.Stats.IsBoss) then
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
function MobClass:TakeDamage(player, amount, weaponSubStats)
    if self.CurrentHealth <= 0 then
        return false -- Already dead
    end
    if self.IsInvulnerable then
        return false
    end

    local armorRating = (self.Stats and self.Stats.Armor) or 0
    local final, armorHit = DamageService.ComputeHitFinal(amount, armorRating, self, weaponSubStats)
    if final <= 0 then return false end

    -- Apply damage. HealthFloor (optional, set by encounter scripts) is a level the HP can't be
    -- pushed below -- e.g. a boss that must play a phase transition before it can die.
    local floor = math.max(0, tonumber(self.HealthFloor) or 0)
    if floor > 0 and self.CurrentHealth <= floor then
        return false
    end
    self.CurrentHealth = math.max(floor, self.CurrentHealth - final)
    
    -- In combat (a named elite's idle-despawn timer reads this; see MobManager).
    self._lastCombatAt = os.clock()

    -- Track damage contribution (post-armor so loot reflects actual damage)
    local playerId = player.UserId
    self.DamageTracker[playerId] = (self.DamageTracker[playerId] or 0) + final
    
    -- Update HP bar display
    self:UpdateHPBar()

    local humanoid = self.Model and self.Model:FindFirstChildOfClass("Humanoid")
    if humanoid then
        self:SyncHumanoidHealth(humanoid)
    end

    -- Unless this mob has an uninterruptible moveset, getting hit interrupts the
    -- animation, but NOT the attack-cooldown timer, so the mob can still
    -- land its own hit back if the player is already in range (no hit-stun
    -- lockout on the attempt itself, only a visual flinch).
    if self.Stats.InterruptAttackOnHit ~= false then
        if self._animTracks and self._animTracks.Attack and self._animTracks.Attack.IsPlaying then
            self._animTracks.Attack:Stop(0.05)
        end
        -- An authored special (see MobMovesetBehaviour) is an attack too, and its
        -- track lives outside _animTracks.Attack, so it needs stopping here as
        -- well -- otherwise an "interruptible" mob would still finish its combo
        -- through a flinch. The moveset update sees the stopped track on the next
        -- tick and closes the special out properly (cooldown, state).
        if self._moveset and self._moveset.track and self._moveset.track.IsPlaying then
            self._moveset.track:Stop(0.05)
        end
    end

    -- Threat, not "whoever hit last": the hit adds its damage, then the target is re-picked
    -- (see RefreshThreatTarget). A mob with no target always takes its attacker.
    self:AddThreat(player, final)
    if not self:RefreshThreatTarget() and not self.TargetPlayer then
        self.TargetPlayer = player
    end
    if self.AIState == "Idle" and self.TargetPlayer then
        self.AIState = "Walking"
    end
    
    -- Check for death
    if self.CurrentHealth <= 0 then
        -- Award tier-aware kill credit and XP to the killer before Die()
        -- tears down the model.
        DamageService.AwardKill(player, self)
        self:Die()
        return true, armorHit -- Mob died
    end

    return false, armorHit -- Mob still alive
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

-- Threat ------------------------------------------------------------------------------------

function MobClass:IsPriorityMob()
    local stats = self.Stats or {}
    return stats.IsBoss == true or stats.IsNamedElite == true or stats.IsElite == true
end

local function threatHalfLife(self)
    return self:IsPriorityMob() and THREAT_HALF_LIFE_PRIORITY or THREAT_HALF_LIFE
end

local function threatValue(self, entry, now)
    return entry.value * 0.5 ^ ((now - entry.at) / threatHalfLife(self))
end

-- A player this mob may still fight: in the game, alive, not spectating a boss fight, and within
-- reach of this mob (the realm for never-deaggro bosses; home zone + aggro range otherwise).
function MobClass:IsValidThreatTarget(player)
    if not player or not player.Parent or player:GetAttribute("DungeonSpectating") ~= nil then return false end
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root or humanoid.Health <= 0 then return false end
    local position = self:GetPosition()
    if not position then return false end
    local reach = self.NeverDeaggro and NEVER_DEAGGRO_REACQUIRE_RANGE
        or ((self.Stats.AggroRange or 60) + (self.Stats.ReturnDistance or 90))
    return (root.Position - position).Magnitude <= reach
end

function MobClass:AddThreat(player, amount)
    if not player or not (amount and amount > 0) then return end
    self.Threat = self.Threat or {}
    local now = os.clock()
    local entry = self.Threat[player]
    local value = entry and threatValue(self, entry, now) or 0
    self.Threat[player] = { value = value + amount, at = now }
end

function MobClass:GetThreat(player)
    local entry = self.Threat and self.Threat[player]
    return entry and threatValue(self, entry, os.clock()) or 0
end

-- Highest-threat valid player (optionally only among `allowed`, a set of players). Drops entries
-- that have faded out or whose player is dead or gone.
function MobClass:TopThreat(allowed)
    if not self.Threat then return nil, 0 end
    local now = os.clock()
    local best, bestValue = nil, 0
    for player, entry in pairs(self.Threat) do
        local value = threatValue(self, entry, now)
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if value < THREAT_FORGET or not player.Parent or not humanoid or humanoid.Health <= 0 then
            self.Threat[player] = nil -- faded, dead or gone: a respawn starts clean
        elseif (not allowed or allowed[player]) and value > bestValue and self:IsValidThreatTarget(player) then
            best, bestValue = player, value
        end
    end
    return best, bestValue
end

function MobClass:ClearThreat()
    self.Threat = nil
end

-- Re-picks the target from threat: take the top player when there is no valid target, or when
-- they out-threat the current one by the switch margin. Returns true if the target changed.
function MobClass:RefreshThreatTarget()
    local best, bestValue = self:TopThreat()
    if not best then return false end
    local current = self.TargetPlayer
    if current == best then return false end
    local margin = self:IsPriorityMob() and THREAT_SWITCH_MARGIN_PRIORITY or THREAT_SWITCH_MARGIN
    if current and self:IsValidThreatTarget(current) and bestValue <= self:GetThreat(current) * margin then
        return false
    end
    self.TargetPlayer = best
    self._engaged = true
    if self.AIState == "Idle" then self.AIState = "Walking" end
    return true
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
        local mdl = self.Model
        self.Model = nil -- unchanged: IsAlive()/UpdateAI etc. still see "no model" immediately

        -- A subclass with an authored death sequence (DungeonBossMobClass, Miasma) can take
        -- ownership of the model: it keeps it alive for the sequence and destroys it itself,
        -- so the generic death effect and the 0.2s Debris below are skipped. Gameplay death
        -- (rewards, spawner notify, IsAlive) still happens right now either way.
        local presenting = false
        if self.PlayDefeatPresentation then
            local okPres, res = pcall(self.PlayDefeatPresentation, self, mdl)
            if not okPres then
                warn("MobClass: PlayDefeatPresentation failed: " .. tostring(res))
            end
            presenting = okPres and res == true
        end

        -- Spawn the red-silhouette death effect from the model's exact
        -- final pose BEFORE anything below tears it down (Debris just
        -- defers the real destruction, but MobDeathEffect.Play clones mdl
        -- synchronously right now, so it must run first regardless).
        if not presenting then
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
        end -- not presenting
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

    -- Skip this tick's AI after a rescue: the mob just teleported, so any
    -- movement computed from the old position would be nonsense.
    if self:RescueIfFallen(currentPosition) then
        return
    end

    -- Threat decides the target each tick: a stronger attacker takes over, and a target that
    -- died, left or went out of reach falls back to the next highest threat.
    if self.Threat then
        self:RefreshThreatTarget()
    end

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
    local ignoreHomeZone = false
    if self.NeverDeaggro and self._engaged then
        closestDistance = NEVER_DEAGGRO_REACQUIRE_RANGE
        ignoreHomeZone = true
    end

    for _, player in ipairs(players) do
        local character = player.Character
        if character then
            local hrp = character:FindFirstChild("HumanoidRootPart")
            local humanoid = character:FindFirstChildOfClass("Humanoid")

            if hrp and humanoid and humanoid.Health > 0 and player:GetAttribute("DungeonSpectating") == nil then
                local distance = (currentPosition - hrp.Position).Magnitude
                local distanceFromSpawn = (hrp.Position - self.SpawnPosition).Magnitude
                if distance < closestDistance and (ignoreHomeZone or distanceFromSpawn <= self.Stats.ReturnDistance) then
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
    self._engaged = true
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

    -- Keep flat distance for approach/leash behavior. Melee separately checks
    -- body bounds in Y, avoiding both root-height mismatches and infinite reach.
    local dtx, dtz = currentPosition.X - targetHRP.Position.X, currentPosition.Z - targetHRP.Position.Z
    local distanceToTarget = math.sqrt(dtx * dtx + dtz * dtz)
    local distanceFromSpawn = (currentPosition - self.SpawnPosition).Magnitude

    if not self.NeverDeaggro and distanceFromSpawn > self.Stats.ReturnDistance then
        if distanceToTarget <= LEASH_GRACE_PROXIMITY then
            -- Still right on the player despite being past the zone -- hold off.
            self._leashGraceStartedAt = nil
        else
            local now = tick()
            self._leashGraceStartedAt = self._leashGraceStartedAt or now
            if now - self._leashGraceStartedAt >= LEASH_GRACE_DURATION then
                self:ClearThreat() -- gave up the chase: forget it, like an MMO leash reset
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

    -- Straight at the target (no seat rings since 2026-09-29): the melee-reach check above
    -- flips to Attacking once close enough, and the soft crowd push keeps a pack from
    -- stacking into one point, so a crowd clumps around the player like Minecraft mobs.
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

    -- Telegraph the windup, using the SAME delay the damage below uses so the
    -- two can never drift (retuning AttackSpeed re-times both). Opt-in per mob
    -- via MobData's `Telegraph`, so mobs without it are untouched. Only the
    -- delayed-hit path can telegraph at all -- an instant-hit mob has no windup
    -- to warn during. No frontal cone here on purpose: IsTargetWithinMeleeReach
    -- has none for the ordinary swing, so the honest shape is a full ring.
    if self._attackHitDelay and self.Stats and self.Stats.Telegraph then
        MobTelegraph.Begin(self, self.Stats.Telegraph, { self._attackHitDelay },
            MobTelegraph.ReachFor(self), nil)
        MobTelegraph.ClearAfter(self, self._attackHitDelay + TELEGRAPH_CLEAR_TAIL)
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
-- `knockbackMultiplier` is an optional per-hit override (one authored special
-- hitting harder than the mob's ordinary swing); omitted, the mob's own
-- MobData PlayerKnockbackMultiplier applies, and failing that the baseline.
function MobClass:ApplyPlayerHitstun(playerCharacter, knockbackMultiplier)
    local hrp = playerCharacter:FindFirstChild("HumanoidRootPart")
    if not hrp or not self.Model then
        return
    end
    local primaryPart = self.Model.PrimaryPart
    if not primaryPart then
        return
    end

    local mult = tonumber(knockbackMultiplier)
        or tonumber(self.Stats and self.Stats.PlayerKnockbackMultiplier)
        or 1
    if mult <= 0 then return end

    local horizontal = Vector3.new(hrp.Position.X - primaryPart.Position.X, 0, hrp.Position.Z - primaryPart.Position.Z)
    local dir = horizontal.Magnitude > 0.1 and horizontal.Unit or Vector3.new(0, 0, 1)

    -- HORIZONTAL ONLY. The vertical component stays at the baseline hop for
    -- every mob however hard it hits: scaling it too launched the player high
    -- enough to read as floaty, and a big pop can also lift them past the
    -- melee vertical reach so the later impacts of a combo whiff entirely.
    -- A heavy hit should send you further back, not further up.
    local bv = Instance.new("BodyVelocity")
    bv.Velocity = Vector3.new(
        dir.X * PLAYER_HIT_KNOCKBACK_HORIZONTAL * mult,
        PLAYER_HIT_KNOCKBACK_VERTICAL,
        dir.Z * PLAYER_HIT_KNOCKBACK_HORIZONTAL * mult
    )
    -- Only the horizontal budget scales with it, for the same reason. (The
    -- vertical 4000 is mostly spent holding the character's weight against
    -- gravity anyway, which is why the baseline hop is as small as it is.)
    local force = 4000 * math.max(1, mult)
    bv.MaxForce = Vector3.new(force, 4000, force)
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
