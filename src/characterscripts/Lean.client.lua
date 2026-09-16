local runService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ============================================
-- LEAN CONFIGURATION
-- ============================================
local LEAN_AMOUNT = 0.5          -- How much the character leans (0.1 = subtle, 0.5 = moderate, 1.0 = extreme)
local LEAN_SPEED = 6             -- How fast the lean happens (LOWER = smoother, 3-10 recommended)
local LEAN_SMOOTHNESS = 0.03     -- How smooth the transition is (LOWER = smoother, 0.01-0.08 recommended)

local FORWARD_LEAN = 25          -- How much to lean forward when moving forward (multiplier)
local BACKWARD_LEAN = 25          -- How much to lean backward when moving backward (multiplier)
local SIDE_LEAN = 25             -- How much to lean sideways when strafing (multiplier)

-- ============================================
-- SPRINT ACCELERATION LEAN CONFIGURATION
-- ============================================
local SPRINT_BURST_LEAN = 50            -- Extra forward lean amount when starting to sprint (0.2-0.6 recommended)
local SPRINT_BURST_DURATION = 0.4        -- How long the burst lean lasts in seconds (0.3-0.6 recommended)
local SPRINT_BURST_DECAY = 3             -- How fast the burst lean fades (higher = faster fade)

-- ============================================

local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
local m6d = nil
local originalM6dC0 = nil

-- Track our last applied offset so we can work additively
local lastLeanOffset = CFrame.new()

-- New custom skeleton (bone-driven skinned mesh, no LowerTorso/RootJoint) has neither
-- of this script's expected R15/R6 joints -- FindFirstChild (non-yielding) instead of
-- the old WaitForChild (no timeout, would hang this script's thread forever) here, so
-- this safely no-ops instead. Lean effect is lost on that rig until a bone-based
-- rewrite (Bone.Transform can carry the same kind of additive offset Motor6D.C0 did
-- here) -- not required for the character migration itself.
if humanoid.RigType == Enum.HumanoidRigType.R15 then
	local lowerTorso = character:FindFirstChild("LowerTorso")
	m6d = lowerTorso and lowerTorso:FindFirstChild("Root")
else
	m6d = humanoidRootPart:FindFirstChild("RootJoint")
end

if not m6d then
	return
end

-- Store original C0 once
originalM6dC0 = m6d.C0

-- Current lean angles (smoothed)
local currentX = 0
local currentZ = 0

-- Sprint burst tracking
local isRunning = false
local wasRunning = false
local sprintBurstAmount = 0  -- Current burst lean value (decays over time)
local sprintBurstTimer = 0   -- Tracks time since sprint started

-- Listen for running state from UpdateRunningState RemoteEvent
local runEvent = ReplicatedStorage:WaitForChild("UpdateRunningState")

-- Track running state (this gets set by your Animate2 script via RemoteEvent)
-- We'll detect it by checking WalkSpeed changes instead
local function isCharacterSprinting()
	-- Check if running based on WalkSpeed being above walk speed
	return humanoid.WalkSpeed > 16  -- Adjust if your walk speed is different
end

runService:BindToRenderStep("CharacterLean", Enum.RenderPriority.Character.Value, function(dt)

	-- Check if we just started sprinting
	isRunning = isCharacterSprinting()

	if isRunning and not wasRunning then
		-- Just started sprinting! Trigger burst lean
		sprintBurstAmount = SPRINT_BURST_LEAN
		sprintBurstTimer = 0
	end

	wasRunning = isRunning

	-- Decay the sprint burst over time
	if sprintBurstAmount > 0 then
		sprintBurstTimer = sprintBurstTimer + dt

		-- Exponential decay
		local decayFactor = math.clamp(1 - math.exp(-SPRINT_BURST_DECAY * dt), 0, 1)
		sprintBurstAmount = sprintBurstAmount * (1 - decayFactor)

		-- Clamp to 0 when very small
		if sprintBurstAmount < 0.001 then
			sprintBurstAmount = 0
		end
	end

	-- Calculate desired lean based on movement
	local direction = humanoidRootPart.CFrame:VectorToObjectSpace(humanoid.MoveDirection)
	local velocity = humanoidRootPart.CFrame:VectorToObjectSpace(humanoidRootPart.AssemblyLinearVelocity)

	-- Calculate momentum based on actual velocity
	local speed = velocity.Magnitude
	local momentumFactor = math.min(speed / humanoid.WalkSpeed, 1.5)  -- Cap at 1.5x for running

	-- Calculate target lean angles
	local targetX = 0
	local targetZ = 0

	if speed > 0.5 then  -- Only lean if actually moving
		-- Side-to-side lean (strafe left/right)
		targetX = direction.X * momentumFactor * LEAN_AMOUNT * SIDE_LEAN

		-- Forward/backward lean
		if direction.Z < -0.1 then
			-- Moving forward - lean forward
			targetZ = direction.Z * momentumFactor * LEAN_AMOUNT * FORWARD_LEAN

			-- Add sprint burst lean (extra forward lean when starting sprint)
			-- Only apply if moving forward
			targetZ = targetZ - sprintBurstAmount

		elseif direction.Z > 0.1 then
			-- Moving backward - lean backward slightly
			targetZ = direction.Z * momentumFactor * LEAN_AMOUNT * BACKWARD_LEAN
		end
	else
		-- Not moving, decay burst faster
		sprintBurstAmount = 0
	end

	-- Smoothly interpolate current lean toward target (frame-rate independent)
	local smoothFactor = math.clamp(1 - math.exp(-LEAN_SMOOTHNESS * dt * 144), 0, 1)
	currentX = currentX + (targetX - currentX) * smoothFactor
	currentZ = currentZ + (targetZ - currentZ) * smoothFactor

	-- Build the lean offset CFrame
	local leanOffset
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		-- R15: X = side tilt, Z = forward/back tilt
		leanOffset = CFrame.Angles(currentZ, 0, -currentX)
	else
		-- R6
		leanOffset = CFrame.Angles(-currentZ, -currentX, 0)
	end

	-- ADDITIVE APPROACH:
	-- Remove last frame's lean offset to get the base C0 (set by other scripts like directional movement)
	-- Then apply our new lean on top
	local baseC0 = m6d.C0 * lastLeanOffset:Inverse()
	local targetC0 = baseC0 * leanOffset

	-- Apply with smoothing (frame-rate independent)
	local speedFactor = math.clamp(1 - math.exp(-LEAN_SPEED * dt), 0, 1)
	m6d.C0 = m6d.C0:Lerp(targetC0, speedFactor)

	-- Store what we applied for next frame
	lastLeanOffset = leanOffset
end)