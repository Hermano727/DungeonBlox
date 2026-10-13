--[[
	JumpMotion (LocalScript, StarterCharacterScripts) -- the player's jump: a small state machine over
	Roblox's Humanoid, replacing the default jump (instant, very high, no weight).

	States:  Grounded -> Windup -> Takeoff -> Rise | LongAir -> Fall -> Land -> Grounded
	         walking off a ledge goes Grounded -> Fall (after WALKOFF_AIR_TIME, so stairs never trigger it)
	  Windup   jump pressed: the squat plays (Takeoff clip); the Humanoid leaves the ground WINDUP later
	  Takeoff  the push-off and stretch finish in the air (TAKEOFF_LENGTH after the Windup began; the clip
	           holds its last pose until then, so a longer TAKEOFF_LENGTH never drops the arms)
	  Rise     the air pose of a standing / short jump        LongAir  the stretched leap of a fast one
	  Fall     once the rise is over (or off a ledge): legs reach for the ground, arms out
	  Land     the compress and recover, played at a weight from the impact speed; a hard enough one
	           also slows you for a moment

	Physics (RS/JumpConfig): the default jump is switched off (the Jumping state stays DISABLED, so
	pressing jump alone does nothing, not even the Humanoid's jump pose) and this script releases a jump of
	the right height itself after the squat. While airborne an
	upward force cancels most of Workspace gravity for THIS character, so it rises at GRAVITY_RISE and falls
	at GRAVITY_FALL: ~4 studs high, ~0.7 s in the air, a quicker fall than rise. Workspace.Gravity is
	untouched (mobs and loot use it).

	Clips (RS/Assets/Animations/JumpAnimations) are Action priority and play on the owner's Animator, so
	everyone sees them. Each state has a Body clip (legs, spine; always) and an Arms clip (only with
	nothing held: with a weapon out the arms keep their hold).

	Respects every other system that blocks jumping. Crouching, PotionActionLock, EnergyServer and
	MountRiderCleanupClient all toggle the Jumping state, so this script owns that flag (it keeps it off and
	flips it on only for the release) and reads their reasons directly instead: IsCrouching, the potion
	lock, the walk speed above zero (dialogue and cutscene freezes), and not mounted, seated, swimming or
	climbing.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContentProvider = game:GetService("ContentProvider")

local Config = require(ReplicatedStorage:WaitForChild("JumpConfig"))
local JumpAnimations = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Animations"):WaitForChild("JumpAnimations"))
local Clips = JumpAnimations.Clips
local ActiveEquipment = require(ReplicatedStorage:WaitForChild("ActiveEquipment"))
local CharacterAnimProfiles = require(ReplicatedStorage:WaitForChild("CharacterAnimProfiles"))
local PotionAction = require(ReplicatedStorage:WaitForChild("PotionAction"))

local character = script.Parent
local player = Players.LocalPlayer
local humanoid = character:WaitForChild("Humanoid")
local root = character:WaitForChild("HumanoidRootPart")
local animator = humanoid:WaitForChild("Animator")

local State = Enum.HumanoidStateType
local SUSPENDED_STATES = {
	[State.Swimming] = true, [State.Climbing] = true, [State.Seated] = true, [State.Dead] = true,
	[State.Physics] = true, [State.PlatformStanding] = true, [State.Ragdoll] = true,
	[State.FallingDown] = true, [State.GettingUp] = true, [State.Flying] = true,
}

----------------------------------------------------------------------
-- The default jump off; ours released on demand
----------------------------------------------------------------------

-- Launch speed for a jump that peaks at HEIGHT under GRAVITY_RISE, and the Humanoid JumpHeight that
-- produces that speed under Workspace's own gravity (the Humanoid computes v0 = sqrt(2 * g * JumpHeight)).
local LAUNCH_SPEED = math.sqrt(2 * Config.GRAVITY_RISE * Config.HEIGHT)
local function releasedJumpHeight()
	return LAUNCH_SPEED * LAUNCH_SPEED / (2 * workspace.Gravity)
end

local releasing = false -- true only for the instant we let the Humanoid jump

local function lockDefaultJump()
	if humanoid.UseJumpPower then humanoid.UseJumpPower = false end
	if not releasing and humanoid.JumpHeight ~= 0 then humanoid.JumpHeight = 0 end
	-- Other scripts re-enable the Jumping state when THEIR reason to block it ends (stood up, drink done,
	-- dismounted): take it straight back, or the next press would be the Humanoid's own instant jump.
	if not releasing and humanoid:GetStateEnabled(State.Jumping) then humanoid:SetStateEnabled(State.Jumping, false) end
end
humanoid.UseJumpPower = false
humanoid.JumpHeight = 0
humanoid:SetStateEnabled(State.Jumping, false)
humanoid:GetPropertyChangedSignal("JumpHeight"):Connect(lockDefaultJump)
humanoid:GetPropertyChangedSignal("UseJumpPower"):Connect(lockDefaultJump)

----------------------------------------------------------------------
-- Clips
----------------------------------------------------------------------

local tracks = {} -- [state] = { Body = AnimationTrack, Arms = AnimationTrack }
local preload = {}
for state, ids in pairs(Clips) do
	tracks[state] = {}
	for part, id in pairs(ids) do
		if id ~= "" then
			local animation = Instance.new("Animation")
			animation.AnimationId = id
			local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
			if ok and track then
				track.Priority = Enum.AnimationPriority.Action
				-- The arms of the air states loop their balance wobble; everything else plays once and holds.
				track.Looped = part == "Arms" and JumpAnimations.LoopedArms[state] == true
				tracks[state][part] = track
				table.insert(preload, animation)
			else
				warn("[JumpMotion] clip failed to load:", state, part, track)
			end
		end
	end
end
task.spawn(function() pcall(function() ContentProvider:PreloadAsync(preload) end) end)

local current -- the state whose clips are playing

local ours = {} -- every jump track, so the arm check below can tell them from other animations
for _, set in pairs(tracks) do
	for _, track in pairs(set) do ours[track] = true end
end

-- Another animation is driving the arms right now (a sword swing, a bow draw, a drink): the jump arms
-- step aside rather than blend with it at the same priority.
local ACTION_MIN, ACTION_MAX = Enum.AnimationPriority.Action.Value, Enum.AnimationPriority.Action4.Value
local function otherArmsActive()
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		if not ours[track] and track.WeightCurrent > 0.05 then
			local priority = track.Priority.Value
			if priority >= ACTION_MIN and priority <= ACTION_MAX then return true end
		end
	end
	return false
end

-- The arms join in with nothing held. With a sword out they still flail in a FALL (the sword simply
-- rides Hand_R); every other state, and any other tool (bow, pickaxe, spear), keeps its own hold.
local function armsWanted(stateName)
	local tool = ActiveEquipment.GetTool(character)
	local free = tool == nil
		or (stateName == "Fall" and CharacterAnimProfiles.GetProfileForTool(tool) == "Sword")
	return free and not otherArmsActive()
end

local function stopCurrent(fade)
	if not current then return end
	for _, track in pairs(tracks[current]) do
		if track.IsPlaying then track:Stop(fade) end
	end
	current = nil
end

-- Starts `name`'s clips (arms only when nothing is held), fading the previous state's out.
local function play(name, fade, weight)
	local previous = current
	local set = tracks[name]
	if set.Body then set.Body:Play(fade, weight or 1, 1) end
	if set.Arms and armsWanted(name) then set.Arms:Play(fade, weight or 1, 1) end
	if previous and previous ~= name then
		for _, track in pairs(tracks[previous]) do track:Stop(fade) end
	end
	current = name
end

-- Drawing or sheathing a weapon mid-air hands the arms back / takes them over.
local function syncArms()
	if not current or PotionAction.IsLocked(character) then return end -- a drink owns the arms
	local set = tracks[current]
	local arms, body = set.Arms, set.Body
	if not arms then return end
	if armsWanted(current) then
		if not arms.IsPlaying then
			arms:Play(Config.FADE_IN, 1, 1)
			if body and arms.Length > 0 then arms.TimePosition = body.TimePosition % arms.Length end
		end
	elseif arms.IsPlaying then
		arms:Stop(Config.FADE_IN)
	end
end

----------------------------------------------------------------------
-- State machine
----------------------------------------------------------------------

local state = "Grounded"
local jumpId = 0          -- invalidates a pending Windup / Takeoff when the jump is cancelled
local jumpedAt = 0        -- when the Humanoid was released into the jump
local takeoffEndsAt = 0
local longJump = false
local airTime = 0         -- Grounded only: how long we have been unsupported without a jump
local airStart = 0
local fallSpeed = 0       -- the fastest downward speed this airtime: the landing's impact
local landEndsAt = 0
local nextJumpAt = 0
-- Seen in the air since the release (or the walk-off). A landing needs this: FloorMaterial lags the
-- physics by a frame or more, so right after the release it can still report the ground. Treating that as
-- a landing ended the jump at once (idle pose for a frame) and the walk-off check then threw the Fall pose
-- straight back on: the random "arms up, flicker down, snap back up" (2026-10-12).
local leftGround = false

local function grounded()
	return humanoid.FloorMaterial ~= Enum.Material.Air
end

local function horizontalSpeed()
	local v = root.AssemblyLinearVelocity
	return Vector3.new(v.X, 0, v.Z).Magnitude
end

-- Mounted, seated, swimming, climbing, dead: the jump machine stands down.
local function suspended()
	return humanoid.Health <= 0 or humanoid.Sit or SUSPENDED_STATES[humanoid:GetState()] == true
		or player:GetAttribute("Mounted") == true
end

local function setGrounded(fade)
	jumpId += 1
	stopCurrent(fade or Config.FADE_OUT)
	state = "Grounded"
	airTime, fallSpeed = 0, 0
end

local function enterFall()
	state = "Fall"
	play("Fall", Config.FADE_IN)
end

local function land()
	local impact = fallSpeed
	local airFor = os.clock() - airStart
	fallSpeed = 0
	if airFor < Config.LAND_MIN_AIR and impact < Config.LAND_IMPACT_SOFT then
		setGrounded()
		return
	end
	local u = math.clamp((impact - Config.LAND_IMPACT_SOFT) / (Config.LAND_IMPACT_HARD - Config.LAND_IMPACT_SOFT), 0, 1)
	local weight = Config.LAND_WEIGHT_MIN + (1 - Config.LAND_WEIGHT_MIN) * u
	state = "Land"
	play("Land", Config.FADE_IN, weight)
	-- The clip holds its last pose (it never ends on its own), so the landing lasts LAND_LENGTH and then
	-- fades out to whatever the run / idle is doing.
	landEndsAt = os.clock() + Config.LAND_LENGTH
	nextJumpAt = os.clock() + Config.JUMP_COOLDOWN
	-- A hard landing costs a moment of speed (client-side: the server's own walk speed is untouched and
	-- simply wins again when it next changes it).
	if impact >= Config.HARD_LANDING_IMPACT then
		local base = humanoid.WalkSpeed
		local slowed = base * Config.HARD_LANDING_SLOW
		humanoid.WalkSpeed = slowed
		task.delay(Config.HARD_LANDING_SECONDS, function()
			if humanoid.Parent and math.abs(humanoid.WalkSpeed - slowed) < 1e-3 then humanoid.WalkSpeed = base end
		end)
	end
end

local function canStartJump()
	if suspended() or state == "Windup" or state == "Takeoff" or state == "Rise" or state == "LongAir" or state == "Fall" then
		return false
	end
	if os.clock() < nextJumpAt then return false end
	if root:GetAttribute("IsCrouching") == true then return false end
	if humanoid.WalkSpeed <= 0 or humanoid.PlatformStand then return false end
	if PotionAction.IsLocked(character) then return false end
	local current = humanoid:GetState()
	if current ~= State.Running and current ~= State.RunningNoPhysics and current ~= State.Landed then return false end
	return grounded()
end

-- The Humanoid is released into the jump: it leaves the ground with exactly LAUNCH_SPEED.
local function release()
	releasing = true
	humanoid:SetStateEnabled(State.Jumping, true)
	humanoid.JumpHeight = releasedJumpHeight()
	humanoid:ChangeState(State.Jumping)
	-- Launch here and now, rather than whenever the Humanoid gets round to its jump: same speed, no lag.
	local v = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(v.X, LAUNCH_SPEED, v.Z)
	leftGround = false
	task.delay(0.12, function()
		releasing = false
		if humanoid.Parent then
			humanoid.JumpHeight = 0
			humanoid:SetStateEnabled(State.Jumping, false)
		end
	end)
	jumpedAt = os.clock()
	airStart = jumpedAt
	fallSpeed = 0
	longJump = horizontalSpeed() >= Config.LONG_SPEED
	state = "Takeoff"
	takeoffEndsAt = jumpedAt + math.max(0.05, Config.TAKEOFF_LENGTH - Config.WINDUP)
end

local function requestJump()
	if not canStartJump() then return end
	jumpId += 1
	local id = jumpId
	state = "Windup"
	play("Takeoff", Config.FADE_IN)
	task.delay(Config.WINDUP, function()
		if id ~= jumpId or state ~= "Windup" then return end
		-- The world may have changed during the squat (stunned, frozen, mounted, knocked off the ground).
		if suspended() or humanoid.WalkSpeed <= 0 or PotionAction.IsLocked(character) or root:GetAttribute("IsCrouching") == true then
			setGrounded(Config.FADE_IN)
			return
		end
		release()
	end)
end

UserInputService.JumpRequest:Connect(requestJump)

humanoid.Died:Connect(function()
	setGrounded(0.1)
end)

RunService.Heartbeat:Connect(function(dt)
	if humanoid.Health <= 0 then return end
	-- Their re-enables (another script's reason to block jumping ended) carry no property change to listen
	-- for, so the Jumping state is taken back here, every frame.
	if not releasing and humanoid:GetStateEnabled(State.Jumping) then humanoid:SetStateEnabled(State.Jumping, false) end
	if suspended() then
		if state ~= "Grounded" then setGrounded(Config.FADE_IN) end
		airTime = 0
		return
	end
	local now = os.clock()
	local velocity = root.AssemblyLinearVelocity
	local onGround = grounded()
	local current = humanoid:GetState()
	-- Back on the ground for real: not rising, or the Humanoid itself says so (running up a slope still rises).
	local settled = velocity.Y <= 1 or current == State.Landed or current == State.Running or current == State.RunningNoPhysics

	if state == "Grounded" then
		-- Off a ledge (not a jump): the fall pose, once it is clearly more than a bump or a stair.
		if not onGround and (current == State.Freefall or current == State.Jumping) then
			airTime += dt
			fallSpeed = math.max(fallSpeed, -velocity.Y)
			if airTime >= Config.WALKOFF_AIR_TIME then
				airStart = now - airTime
				leftGround = true
				enterFall()
			end
		else
			airTime, fallSpeed = 0, 0
		end
	elseif state == "Takeoff" then
		fallSpeed = math.max(fallSpeed, -velocity.Y)
		if not onGround then leftGround = true end
		if leftGround and onGround and settled then
			land()
		elseif not leftGround and now - jumpedAt > 0.4 then
			setGrounded(Config.FADE_OUT) -- never left the ground (a ceiling, or the Humanoid refused): no jump
		elseif now >= takeoffEndsAt then
			state = longJump and "LongAir" or "Rise"
			play(state, Config.FADE_IN)
		end
	elseif state == "Rise" or state == "LongAir" or state == "Fall" then
		fallSpeed = math.max(fallSpeed, -velocity.Y)
		if not onGround then leftGround = true end
		if leftGround and onGround and settled then
			land()
		elseif state ~= "Fall" and velocity.Y < Config.APEX_SPEED then
			enterFall()
		end
	elseif state == "Land" then
		if now >= landEndsAt then setGrounded(Config.FADE_OUT) end
	end
	syncArms()
end)

----------------------------------------------------------------------
-- Heavier fall: cancel most of the world's gravity while airborne
----------------------------------------------------------------------

local attachment = Instance.new("Attachment")
attachment.Name = "JumpGravityAttachment"
attachment.Parent = root
local lift = Instance.new("VectorForce")
lift.Name = "JumpGravityLift"
lift.Attachment0 = attachment
lift.RelativeTo = Enum.ActuatorRelativeTo.World
lift.ApplyAtCenterOfMass = true
lift.Force = Vector3.zero
lift.Parent = root

RunService.PreSimulation:Connect(function()
	local current = humanoid:GetState()
	local airborne = humanoid.FloorMaterial == Enum.Material.Air and (current == State.Freefall or current == State.Jumping)
		and not suspended()
	if not airborne then
		if lift.Force ~= Vector3.zero then lift.Force = Vector3.zero end
		return
	end
	local target = root.AssemblyLinearVelocity.Y > 0 and Config.GRAVITY_RISE or Config.GRAVITY_FALL
	lift.Force = Vector3.new(0, root.AssemblyMass * math.max(0, workspace.Gravity - target), 0)
end)
