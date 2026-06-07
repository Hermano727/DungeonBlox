-- MobClass ModuleScript
-- OOP Metatable blueprint for an active mob
-- Lives only in server memory

local MobClass = {}
MobClass.__index = MobClass

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local PathfindingService = game:GetService("PathfindingService")
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

local MOB_SEPARATION_RADIUS = 5
local MOB_BOUNCE_STRENGTH = 10
local KNOCKBACK_BASE_FORCE     = 6    -- horizontal studs/s impulse at KnockbackMultiplier 1.0
local KNOCKBACK_VERTICAL_FORCE = 1  -- upward studs/s component (slight hop)
local KNOCKBACK_STUN_DURATION  = 0.3  -- seconds WalkSpeed is suppressed after a hit
-- Light lateral offset so mobs do not walk in a perfectly straight line;
-- kept small so approach paths stay mostly direct.
local MOVE_STRAFE_MIN_DURATION = 0.9
local MOVE_STRAFE_MAX_DURATION = 1.8
local MOVE_STRAFE_MIN = 0.25
local MOVE_STRAFE_MAX = 1.0
-- Rhythmic hops while walking (only when MobData JumpHeight > 0).
local MOVE_JUMP_INTERVAL_MIN = 0.32
local MOVE_JUMP_INTERVAL_MAX = 0.5
local MOVE_JUMP_FORWARD_SPEED_MIN = 8
local MOVE_JUMP_FORWARD_SPEED_MAX = 22
-- Humanoid jump capability for engine physics; MobData JumpHeight only gates scripted hops.
local DEFAULT_HUMANOID_JUMP_HEIGHT = 7.2

ensureMobCollisionGroup()

local MobData = require(ReplicatedStorage:WaitForChild("MobData"))
local DamageService = require(script.Parent:WaitForChild("DamageService"))

-- Counter for generating unique IDs
local mobIdCounter = 0

-- HP Bar colors
local HP_BAR_COLOR_FULL = Color3.fromRGB(0, 255, 0)    -- Green at full health
local HP_BAR_COLOR_MID = Color3.fromRGB(255, 255, 0)     -- Yellow at half health
local HP_BAR_COLOR_LOW = Color3.fromRGB(255, 0, 0)      -- Red at low health

-- Constructor
function MobClass.new(mobId, spawnPosition, spawnerRef, level)
    local self = setmetatable({}, MobClass)

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

    -- AI state
    self.AIState = "Idle"
    self.TargetPlayer = nil
    self.LastAttackTime = 0
    self.AttackStateEnteredAt = 0
    self.Path = nil
    self.CurrentWaypointIndex = 1
    self.LastPathTime = 0
    self.MovementTimer = 0
    self.StrafeDirection = math.random() < 0.5 and -1 or 1
    self.StrafeMagnitude = math.random() * (MOVE_STRAFE_MAX - MOVE_STRAFE_MIN) + MOVE_STRAFE_MIN
    self.NextStrafeChange = 0
    self._nextMovementJumpAt = 0

    -- Clone and setup visual model
    self.Model = self:SpawnModel()
    if not self.Model then
        return nil
    end

    -- Create HP bar above mob
    self.HPBar = self:CreateHPBar()

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

    -- Position the model
    if model:IsA("Model") then
        model:PivotTo(CFrame.new(self.SpawnPosition))
    elseif model:IsA("BasePart") then
        model.Position = self.SpawnPosition
    end

    self:ConfigureModel(model)
    model.Parent = workspace

    return model
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
        self:SyncHumanoidLocomotionStats(humanoid)
        humanoid.AutoRotate = false
        humanoid.PlatformStand = false
        humanoid.Sit = false
        humanoid.RequiresNeck = false
        humanoid.AutoJumpEnabled = false
        humanoid.BreakJointsOnDeath = false

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

function MobClass:TryOrientModelYawToward(worldPoint)
    if not self.Model or not worldPoint then
        return
    end

    local primaryPart = self.Model.PrimaryPart or self.Model:FindFirstChildWhichIsA("BasePart")
    if not primaryPart then
        return
    end

    local pos = primaryPart.Position
    local flat = Vector3.new(worldPoint.X - pos.X, 0, worldPoint.Z - pos.Z)
    if flat.Magnitude < 0.2 then
        return
    end

    local lookAt = Vector3.new(worldPoint.X, pos.Y, worldPoint.Z)
    local faceCF = CFrame.lookAt(pos, lookAt)
    local _, yaw, _ = faceCF:ToEulerAnglesYXZ()

    primaryPart.AssemblyAngularVelocity = Vector3.zero
    self.Model:PivotTo(CFrame.new(pos) * CFrame.Angles(0, yaw, 0))
end

function MobClass:UpdateCombatFacing()
    if self.AIState == "Chasing" or self.AIState == "Attacking" then
        if self.TargetPlayer and self.TargetPlayer.Character then
            local hrp = self.TargetPlayer.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                self:TryOrientModelYawToward(hrp.Position)
            end
        end
    elseif self.AIState == "Returning" then
        self:TryOrientModelYawToward(self.SpawnPosition)
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

-- MobData JumpHeight: rhythmic hop height only (0 = walk on ground, no scripted jumps).
function MobClass:GetMovementHopHeight()
    if not self.Stats then
        return 0
    end
    local hopHeight = self.Stats.JumpHeight
    if hopHeight == nil then
        return 0
    end
    return math.max(0, hopHeight)
end

function MobClass:SyncHumanoidLocomotionStats(humanoid)
    if not humanoid then
        return
    end

    humanoid.WalkSpeed = self.Stats.MoveSpeed or humanoid.WalkSpeed
    local hopHeight = self:GetMovementHopHeight()
    if hopHeight > 0 then
        humanoid.JumpHeight = hopHeight
    elseif humanoid.JumpHeight <= 0 then
        humanoid.JumpHeight = DEFAULT_HUMANOID_JUMP_HEIGHT
    end
end

function MobClass:GetVariedTargetPosition(originPosition, targetPosition, deltaTime)
    self.MovementTimer = (self.MovementTimer or 0) + deltaTime

    if self.MovementTimer >= (self.NextStrafeChange or 0) then
        self.StrafeDirection = math.random() < 0.5 and -1 or 1
        self.StrafeMagnitude = math.random() * (MOVE_STRAFE_MAX - MOVE_STRAFE_MIN) + MOVE_STRAFE_MIN
        self.NextStrafeChange = self.MovementTimer
            + math.random() * (MOVE_STRAFE_MAX_DURATION - MOVE_STRAFE_MIN_DURATION)
            + MOVE_STRAFE_MIN_DURATION
    end

    local toTarget = targetPosition - originPosition
    local horizontal = Vector3.new(toTarget.X, 0, toTarget.Z)
    if horizontal.Magnitude < 0.1 then
        return targetPosition
    end

    local right = horizontal.Unit:Cross(Vector3.yAxis)
    local wave = math.sin(self.MovementTimer * 1.25 + (self.StrafeDirection * 0.5))
    local lateralOffset = right * self.StrafeDirection * self.StrafeMagnitude * (0.92 + (0.08 * math.abs(wave)))

    return targetPosition + lateralOffset
end

function MobClass:ApplyForwardJumpBoost(humanoid, primaryPart, goalPosition)
    if not humanoid or not primaryPart or not goalPosition then
        return
    end

    local fromPos = primaryPart.Position
    local flat = Vector3.new(goalPosition.X - fromPos.X, 0, goalPosition.Z - fromPos.Z)
    local dir
    if flat.Magnitude >= 0.05 then
        dir = flat.Unit
    else
        local md = humanoid.MoveDirection
        local flatMd = Vector3.new(md.X, 0, md.Z)
        if flatMd.Magnitude < 0.05 then
            return
        end
        dir = flatMd.Unit
    end

    local moveSpeed = self.Stats.MoveSpeed or 16
    local hopHeight = self:GetMovementHopHeight()
    local boost = math.clamp(
        moveSpeed * 0.5 + hopHeight * 0.35,
        MOVE_JUMP_FORWARD_SPEED_MIN,
        MOVE_JUMP_FORWARD_SPEED_MAX
    )

    local v = primaryPart.AssemblyLinearVelocity
    primaryPart.AssemblyLinearVelocity = Vector3.new(
        v.X + dir.X * boost,
        v.Y,
        v.Z + dir.Z * boost
    )
end

function MobClass:ApplyWalkLocomotion(humanoid, primaryPart, goalPosition, deltaTime)
    if not humanoid or not primaryPart or not goalPosition then
        return
    end

    local fromPos = primaryPart.Position
    local flat = Vector3.new(goalPosition.X - fromPos.X, 0, goalPosition.Z - fromPos.Z)
    if flat.Magnitude < 0.4 then
        return
    end

    local dir = flat.Unit
    local walkSpeed = self.Stats.MoveSpeed or humanoid.WalkSpeed or 16
    local v = primaryPart.AssemblyLinearVelocity
    local targetX = dir.X * walkSpeed
    local targetZ = dir.Z * walkSpeed
    local dt = deltaTime or (1 / 30)
    local blend = math.clamp(dt * 10, 0, 1)

    primaryPart.AssemblyLinearVelocity = Vector3.new(
        v.X + (targetX - v.X) * blend,
        v.Y,
        v.Z + (targetZ - v.Z) * blend
    )
end

function MobClass:DriveToward(humanoid, primaryPart, goalPosition, deltaTime)
    if not humanoid or not primaryPart or not goalPosition then
        return
    end

    humanoid:MoveTo(goalPosition)

    if self:GetMovementHopHeight() <= 0 then
        self:ApplyWalkLocomotion(humanoid, primaryPart, goalPosition, deltaTime)
    else
        self:TryPeriodicMovementJump(humanoid, primaryPart, goalPosition)
    end
end

function MobClass:TryPeriodicMovementJump(humanoid, primaryPart, goalPosition)
    if not humanoid or not primaryPart or not goalPosition then
        return
    end

    if self:GetMovementHopHeight() <= 0 then
        return
    end

    local now = tick()
    self._nextMovementJumpAt = self._nextMovementJumpAt or 0
    if now < self._nextMovementJumpAt then
        return
    end

    local state = humanoid:GetState()
    if state ~= Enum.HumanoidStateType.Running
        and state ~= Enum.HumanoidStateType.Landed
        and state ~= Enum.HumanoidStateType.RunningNoPhysics then
        return
    end

    humanoid.Jump = true
    self:ApplyForwardJumpBoost(humanoid, primaryPart, goalPosition)

    local span = MOVE_JUMP_INTERVAL_MAX - MOVE_JUMP_INTERVAL_MIN
    self._nextMovementJumpAt = now + MOVE_JUMP_INTERVAL_MIN + (math.random() * span)
end

function MobClass:ResolveMobOverlap(primaryPart, activeMobs, deltaTime)
    if not primaryPart or not activeMobs then
        return
    end

    local position = primaryPart.Position
    local push = Vector3.zero

    for _, otherMob in pairs(activeMobs) do
        if otherMob ~= self and otherMob:IsAlive() and otherMob.Model then
            local otherPart = otherMob.Model.PrimaryPart or otherMob.Model:FindFirstChildWhichIsA("BasePart")
            if otherPart then
                local offset = position - otherPart.Position
                local horizontal = Vector3.new(offset.X, 0, offset.Z)
                local distance = horizontal.Magnitude

                if distance > 0 and distance < MOB_SEPARATION_RADIUS then
                    local strength = (MOB_SEPARATION_RADIUS - distance) / MOB_SEPARATION_RADIUS
                    push = push + horizontal.Unit * strength * MOB_BOUNCE_STRENGTH
                end
            end
        end
    end

    if push.Magnitude > 0.05 then
        local velocity = primaryPart.AssemblyLinearVelocity
        primaryPart.AssemblyLinearVelocity = Vector3.new(
            velocity.X + push.X * deltaTime,
            velocity.Y,
            velocity.Z + push.Z * deltaTime
        )
    end
end

function MobClass:StabilizeMovement(humanoid, primaryPart)
    if not humanoid or not primaryPart or self.CurrentHealth <= 0 then
        return
    end

    if humanoid.PlatformStand or humanoid.Sit then
        humanoid.PlatformStand = false
        humanoid.Sit = false
    end

    local state = humanoid:GetState()
    if state == Enum.HumanoidStateType.Physics
        or state == Enum.HumanoidStateType.FallingDown
        or state == Enum.HumanoidStateType.Ragdoll then
        humanoid:ChangeState(Enum.HumanoidStateType.Running)
        self.LastPathTime = 0
    end

    if primaryPart.CFrame.UpVector.Y < 0.8 then
        local position = primaryPart.Position
        local _, yaw = primaryPart.CFrame:ToEulerAnglesYXZ()
        primaryPart.AssemblyAngularVelocity = Vector3.zero
        self.Model:PivotTo(CFrame.new(position) * CFrame.Angles(0, yaw, 0))
        humanoid:ChangeState(Enum.HumanoidStateType.Running)
        self.LastPathTime = 0
    end
end

function MobClass:ApplyKnockback(attackerPosition)
    if not self.Model or self.CurrentHealth <= 0 then return end

    local primaryPart = self.Model.PrimaryPart or self.Model:FindFirstChildWhichIsA("BasePart")
    local humanoid    = self.Model:FindFirstChildOfClass("Humanoid")
    if not primaryPart or not humanoid then return end

    -- KnockbackMultiplier: 1.0 = full force, 0 = immune
    local mult = (self.Stats and self.Stats.KnockbackMultiplier ~= nil)
        and self.Stats.KnockbackMultiplier or 1.0
    if mult <= 0 then return end

    -- Push direction: horizontally away from attacker
    local mobPos     = primaryPart.Position
    local horizontal = Vector3.new(mobPos.X - attackerPosition.X, 0, mobPos.Z - attackerPosition.Z)
    local dir        = horizontal.Magnitude > 0.1 and horizontal.Unit or Vector3.new(0, 0, 1)

    -- Replace velocity for a clean, predictable impulse (not additive to prevent stacking)
    primaryPart.AssemblyLinearVelocity = Vector3.new(
        dir.X * KNOCKBACK_BASE_FORCE * mult,
        KNOCKBACK_VERTICAL_FORCE * mult,
        dir.Z * KNOCKBACK_BASE_FORCE * mult
    )

    -- Suppress AI locomotion: WalkSpeed = 0 makes MoveTo calls no-ops during stun window
    humanoid.WalkSpeed = 0
    local restoreSpeed = self.Stats.MoveSpeed or 8
    task.delay(KNOCKBACK_STUN_DURATION, function()
        if self.Model and self.CurrentHealth > 0 then
            humanoid.WalkSpeed = restoreSpeed
        end
    end)
end

-- Create HP bar above mob
function MobClass:CreateHPBar()
    if not self.Model then return nil end

    -- Find the head or primary part to attach the HP bar
    local head = self.Model:FindFirstChild("Head")
    if not head then
        head = self.Model.PrimaryPart or self.Model:FindFirstChildWhichIsA("BasePart")
    end
    if not head then return nil end

    -- Create BillboardGui for the name/level + HP bar
    local billboardGui = Instance.new("BillboardGui")
    billboardGui.Name = "HPBar"
    billboardGui.Size = UDim2.new(5, 0, 0.75, 0)
    billboardGui.StudsOffset = Vector3.new(0, 3, 0)
    billboardGui.Adornee = head
    billboardGui.AlwaysOnTop = true
    billboardGui.Parent = self.Model

    -- Name/Level label above the health bar
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "NameTag"
    titleLabel.Size = UDim2.new(1, 0, 0.25, 0)
    titleLabel.Position = UDim2.new(0, 0, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextSize = 14
    titleLabel.TextColor3 = Color3.fromRGB(255, 220, 150)
    titleLabel.TextStrokeTransparency = 0.3

    local mobName = (self.Stats and self.Stats.Name) or self.MobID
    titleLabel.Text = "Level " .. tostring(self.Level) .. " " .. tostring(mobName)
    Instance.new("UIStroke", titleLabel).Color = Color3.fromRGB(80, 60, 20)
    titleLabel.Parent = billboardGui

    -- Create background frame (dark background)
    local background = Instance.new("Frame")
    background.Name = "Background"
    background.Size = UDim2.new(1, 0, 0.45, 0)
    background.Position = UDim2.new(0, 0, 0.25, 0)
    background.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    background.BorderSizePixel = 2
    background.BorderColor3 = Color3.fromRGB(20, 20, 20)
    background.Parent = billboardGui

    -- Create health bar fill (green by default)
    local healthBar = Instance.new("Frame")
    healthBar.Name = "HealthBar"
    healthBar.Size = UDim2.new(1, 0, 1, 0)
    healthBar.Position = UDim2.new(0, 0, 0, 0)
    healthBar.BackgroundColor3 = HP_BAR_COLOR_FULL
    healthBar.BorderSizePixel = 0
    healthBar.Parent = background

    -- Create corner radius for rounded look
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 4)
    corner.Parent = background

    local healthCorner = Instance.new("UICorner")
    healthCorner.CornerRadius = UDim.new(0, 4)
    healthCorner.Parent = healthBar

    return billboardGui
end

-- Update HP bar display
function MobClass:UpdateHPBar()
    if not self.HPBar then return end

    local healthBar = self.HPBar:FindFirstChild("Background", true)
    if healthBar then
        healthBar = healthBar:FindFirstChild("HealthBar")
    end
    if not healthBar then return end

    -- Calculate health percentage
    local healthPercent = self.CurrentHealth / self.MaxHealth

    -- Update bar size
    healthBar.Size = UDim2.new(healthPercent, 0, 1, 0)

    -- Update color based on health percentage
    if healthPercent > 0.5 then
        -- Green to Yellow transition
        healthBar.BackgroundColor3 = HP_BAR_COLOR_FULL:Lerp(HP_BAR_COLOR_MID, (1 - healthPercent) * 2)
    else
        -- Yellow to Red transition
        healthBar.BackgroundColor3 = HP_BAR_COLOR_MID:Lerp(HP_BAR_COLOR_LOW, (0.5 - healthPercent) * 2)
    end
end

-- Take damage method
-- amount comes in pre-armor (e.g. MobCombat already applied level scaling).
-- DamageService applies the armor curve here so every damage source funnels
-- through the same math.
function MobClass:TakeDamage(player, amount)
    if self.CurrentHealth <= 0 then
        return false -- Already dead
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

    local primaryPart = self.Model and (self.Model.PrimaryPart or self.Model:FindFirstChildWhichIsA("BasePart"))
    if humanoid and primaryPart then
        self:StabilizeMovement(humanoid, primaryPart)
    end

    -- Trigger aggro if idle or returning (re-aggro when attacked)
    if self.AIState == "Idle" or self.AIState == "Returning" then
        self.TargetPlayer = player
        self.AIState = "Chasing"
    end

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

-- Update AI behavior
function MobClass:UpdateAI(deltaTime, players, activeMobs)
    if not self.Model or self.CurrentHealth <= 0 then
        return
    end

    local primaryPart = self.Model.PrimaryPart or self.Model:FindFirstChildWhichIsA("BasePart")
    if not primaryPart then
        return
    end

    local currentPosition = primaryPart.Position
    local humanoid = self.Model:FindFirstChildOfClass("Humanoid")
    self:StabilizeMovement(humanoid, primaryPart)
    self:ResolveMobOverlap(primaryPart, activeMobs, deltaTime)

    -- State machine
    if self.AIState == "Idle" then
        self:HandleIdleState(players, currentPosition)

    elseif self.AIState == "Chasing" then
        self:HandleChasingState(deltaTime, currentPosition, humanoid)

    elseif self.AIState == "Attacking" then
        self:HandleAttackingState(deltaTime, currentPosition, humanoid)

    elseif self.AIState == "Returning" then
        self:HandleReturningState(deltaTime, currentPosition, humanoid, players)
    end

    self:UpdateCombatFacing()
end

-- Handle Idle state
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
                if distance < closestDistance then
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
    self.AIState = "Chasing"
    self.Path = nil
    self.CurrentWaypointIndex = 1
    self.LastPathTime = 0
    return true
end

function MobClass:HandleIdleState(players, currentPosition)
    self:TryAcquireTarget(players, currentPosition)
end

-- Handle Chasing state
function MobClass:HandleChasingState(deltaTime, currentPosition, humanoid)
    if not self.TargetPlayer or not self.TargetPlayer.Character then
        self.AIState = "Returning"
        return
    end

    local targetHRP = self.TargetPlayer.Character:FindFirstChild("HumanoidRootPart")
    local targetHumanoid = self.TargetPlayer.Character:FindFirstChildOfClass("Humanoid")

    if not targetHRP or not targetHumanoid or targetHumanoid.Health <= 0 then
        self.TargetPlayer = nil
        self.AIState = "Returning"
        return
    end

    local distanceToTarget = (currentPosition - targetHRP.Position).Magnitude
    local distanceFromSpawn = (currentPosition - self.SpawnPosition).Magnitude

    -- Check if too far from spawn (with buffer to prevent oscillation)
    -- Only return if significantly past the return distance
    if distanceFromSpawn > self.Stats.ReturnDistance * 1.2 then
        self.TargetPlayer = nil
        self.AIState = "Returning"
        return
    end

    -- Check if in attack range
    if distanceToTarget <= self.Stats.AttackRange then
        self.AIState = "Attacking"
        self.AttackStateEnteredAt = tick()
        return
    end

    -- Pathfind to target
    self:MoveToTarget(targetHRP.Position, humanoid, deltaTime)
end

-- Handle Attacking state
function MobClass:HandleAttackingState(deltaTime, currentPosition, humanoid)
    local now = tick()

    -- Check if target is still valid
    if not self.TargetPlayer or not self.TargetPlayer.Character then
        self.AIState = "Returning"
        return
    end

    local targetHRP = self.TargetPlayer.Character:FindFirstChild("HumanoidRootPart")
    local targetHumanoid = self.TargetPlayer.Character:FindFirstChildOfClass("Humanoid")

    if not targetHRP or not targetHumanoid or targetHumanoid.Health <= 0 then
        self.TargetPlayer = nil
        self.AIState = "Returning"
        return
    end

    local distanceToTarget = (currentPosition - targetHRP.Position).Magnitude

    -- Hold position during the attack window; prevents pathfinding drift that
    -- would otherwise push the mob out of range and trigger a Chasing re-entry.
    humanoid:MoveTo(currentPosition)

    -- Larger hysteresis (2.5x) + minimum hold time: mob must have been in
    -- Attacking state for at least one full cooldown before it can exit.
    -- This survives crowd-jostle from multiple mobs without state thrashing.
    local holdElapsed = now - self.AttackStateEnteredAt
    if distanceToTarget > self.Stats.AttackRange * 2.5 and holdElapsed >= self.Stats.AttackCooldown then
        self.AIState = "Chasing"
        return
    end

    -- Attack cooldown
    if now - self.LastAttackTime >= self.Stats.AttackCooldown then
        self:PerformAttack(targetHumanoid)
        self.LastAttackTime = now
    end
end

-- Handle Returning state
function MobClass:HandleReturningState(deltaTime, currentPosition, humanoid, players)
    if self:TryAcquireTarget(players, currentPosition) then
        return
    end

    local distanceFromSpawn = (currentPosition - self.SpawnPosition).Magnitude

    if distanceFromSpawn < 6 then
        self.AIState = "Idle"
        self.TargetPlayer = nil
        self.Path = nil
        self.CurrentWaypointIndex = 1
        self.LastPathTime = 0
        self:TryAcquireTarget(players, currentPosition)
        return
    end

    local primaryPart = self.Model and (self.Model.PrimaryPart or self.Model:FindFirstChildWhichIsA("BasePart"))
    if humanoid and primaryPart then
        self:DriveToward(humanoid, primaryPart, self.SpawnPosition, deltaTime)
    end
end

-- Move to target using pathfinding
function MobClass:MoveToTarget(targetPosition, humanoid, deltaTime)
    if not humanoid then return end

    local now = tick()
    local primaryPart = self.Model.PrimaryPart or self.Model:FindFirstChildWhichIsA("BasePart")
    if not primaryPart then return end

    local variedTarget = self:GetVariedTargetPosition(primaryPart.Position, targetPosition, deltaTime)
    local hopHeight = self:GetMovementHopHeight()

    if not self.Path or now - self.LastPathTime > 1.0 then
        self.Path = PathfindingService:CreatePath({
            AgentRadius = 2,
            AgentHeight = 5,
            AgentCanJump = true,
        })

        self.Path:ComputeAsync(primaryPart.Position, variedTarget)
        self.CurrentWaypointIndex = 1
        self.LastPathTime = now
    end

    if self.Path.Status ~= Enum.PathStatus.Success then
        self:DriveToward(humanoid, primaryPart, variedTarget, deltaTime)
        return
    end

    local waypoints = self.Path:GetWaypoints()

    if self.CurrentWaypointIndex <= #waypoints then
        local waypoint = waypoints[self.CurrentWaypointIndex]
        if hopHeight > 0 and waypoint.Action == Enum.PathWaypointAction.Jump then
            humanoid.Jump = true
            self:ApplyForwardJumpBoost(humanoid, primaryPart, targetPosition)
        end
        humanoid:MoveTo(waypoint.Position)
        if hopHeight <= 0 then
            self:ApplyWalkLocomotion(humanoid, primaryPart, waypoint.Position, deltaTime)
        end

        local distanceToWaypoint = (primaryPart.Position - waypoint.Position).Magnitude
        if distanceToWaypoint < 2 then
            self.CurrentWaypointIndex = self.CurrentWaypointIndex + 1
        end
    end

    if hopHeight > 0 then
        self:TryPeriodicMovementJump(humanoid, primaryPart, targetPosition)
    end
end

-- Perform attack on target
-- Routes through DamageService so player armor reduces incoming damage and
-- the player profile HP stays in sync with the Humanoid.
function MobClass:PerformAttack(targetHumanoid)
    if not targetHumanoid or targetHumanoid.Health <= 0 then return end
    local char = targetHumanoid.Parent
    local player = char and Players:GetPlayerFromCharacter(char)
    if player then
        DamageService.ApplyToPlayer(player, self.Stats.BaseDamage, self)
    else
        -- NPC target (no player profile). Fall back to direct.
        targetHumanoid:TakeDamage(self.Stats.BaseDamage)
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
