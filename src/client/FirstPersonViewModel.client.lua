-- First Person ViewModel System
-- Custom Scriptable camera: lets the player see their own body in first
-- person, drives a fixed-distance Minecraft-style over-the-shoulder view
-- on Keys.TogglePerspective (R), and (since it never touches
-- Player.CameraMode) never fights CursorManager -- Ctrl-freelook works
-- correctly here because Roblox's stock camera controller, which forces
-- MouseBehavior back to LockCenter every frame in real first person, is
-- never in the loop at all.
--
-- This is the ACTIVE perspective/camera system. It replaced
-- PerspectiveToggle.client.lua (now disabled, kept for reference), which
-- used Roblox's stock camera modes specifically to avoid an old conflict
-- with the movement system. That conflict no longer reproduces -- verified
-- by re-enabling this script and playtesting -- so this is back to being
-- the one true camera driver. If movement ever visibly jitters/fights
-- again, that's the thing to suspect first.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Keys = require(ReplicatedStorage:WaitForChild("KeybindConfig"))
local VideoSettings = require(ReplicatedStorage:WaitForChild("VideoSettings"))
local CameraOverrideState = require(ReplicatedStorage:WaitForChild("CameraOverrideState"))
local Movement = require(script.Parent:WaitForChild("MovementPresentation"))
local GroundState = require(script.Parent:WaitForChild("CharacterGroundState"))
local MotionMath = require(ReplicatedStorage:WaitForChild("MovementPresentationMath"))
local MotionConfig = require(ReplicatedStorage:WaitForChild("MovementPresentationConfig"))
local landingConnection = nil

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera


-- CAMERA POSITION SETTINGS - ADJUST HERE

-- The 5-stud StarterCharacter's invisible Head is already at eye height:
-- 4.5 studs above the mesh's feet (0.5 below the top of the head).
-- The old rig's +0.95 Y correction put the camera above this model.
-- CAMERA_OFFSET is relative to that anchor, rotated by yaw only.
-- Vector3.new(X, Y, Z) where:
--   X = left/right offset (negative = left, positive = right)
--   Y = up/down offset (negative = down, positive = up)
--   Z = forward/back offset (negative = forward, positive = back)
-- Example: Vector3.new(0, 0, 0) = center of head
--          Vector3.new(0, 0.2, -0.3) = slightly up and forward
local CAMERA_OFFSET = Vector3.new(0, 0, -0.5)
-- Extra forward clearance beyond the idle offset. Use the existing locomotion
-- state so unarmed/sword, sprint denial, and backwards walking all agree.
-- Total forward distance: idle 0.5, walk 1.5, sprint 2.0 studs.
local WALK_CAMERA_FORWARD = 1.0
local SPRINT_CAMERA_FORWARD = 1.5
local CAMERA_FORWARD_BLEND_SPEED = 18
local FIRST_PERSON_WALL_PAD = 0.15

-- Camera rotation sensitivity now lives in VideoSettings.sensitivity (Settings
-- menu Video tab) -- read live below instead of a cached local, so dragging
-- the slider takes effect immediately without a respawn.

-- PERSPECTIVE MODES (Minecraft-style F5 cycling, bound to Keys.TogglePerspective)
--   1 = first person       - camera at the head, original behaviour
--   2 = over-shoulder      - camera pulled back along the look vector
--   3 = front              - camera out in FRONT, looking back at the face (Minecraft's
--                            second F5 view). The character still faces where you aim, and
--                            movement is re-applied relative to the CHARACTER (W walks toward
--                            the camera), since Roblox's default controls move relative to the
--                            camera and would otherwise walk you backwards.
-- Minecraft's 3rd-person camera sits 4 blocks back; scaled to a 5.8-stud
-- character that is ~13 studs. Roblox's own zoom system is NOT in play here
-- (CameraType is Scriptable), so this is an absolute distance, not a zoom %.
local PERSPECTIVE_FIRST  = 1
local PERSPECTIVE_THIRD  = 2
local PERSPECTIVE_FRONT  = 3
local FRONT_DISTANCE     = 8       -- studs in front of the head
local FRONT_HEIGHT       = 0.6     -- studs above the head
-- Published as Player attribute "PerspectiveMode" (RS/AimRay reads it: in the front view the
-- camera's look is the OPPOSITE of the aim, so tools aim from the head instead).
local PERSPECTIVE_NAMES  = { "First", "Back", "Front" }
local THIRD_DISTANCE     = 11.05      -- studs behind the head
local THIRD_HEIGHT       = 1.5     -- studs above the head
local CAMERA_COLLIDE_PAD = 1.0     -- keep this far off geometry when pulled in
local perspective = PERSPECTIVE_FIRST
-- Published so other client systems (CombatClient's first-person swing pick)
-- don't need their own copy of the perspective state.
player:SetAttribute("FirstPersonView", perspective == PERSPECTIVE_FIRST)
player:SetAttribute("PerspectiveMode", PERSPECTIVE_NAMES[perspective])

-- Roblox's own ControlModule (camera-relative movement); the front view overrides its output.
local controlModule
local function getControlModule()
	if controlModule == nil then
		local ok, module = pcall(function()
			return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 5)):GetControls()
		end)
		controlModule = ok and module or false
	end
	return controlModule or nil
end
task.spawn(getControlModule) -- fetch it now, off the camera step (which must never yield)

-- Transparency settings
local HEAD_TRANSPARENCY = 0  -- Not used - head clipped by camera near plane
local ACCESSORY_TRANSPARENCY = 1  -- Mostly invisible but casts visible shadows
local BODY_TRANSPARENCY = 0   -- 0 = fully visible body

local inputConnection = nil  -- Stored so it can be disconnected on respawn
local cameraRotation = Vector2.new(0, 0)  -- Pitch and yaw

-- Function to set transparency on character body parts and accessories
local function setCharacterTransparency(character)
	print("[FirstPersonViewModel] Setting character transparency")

	for _, descendant in character:GetDescendants() do
		-- Handle BaseParts (body parts)
		if descendant:IsA("BasePart") then
			if descendant.Name == "Head" then
				-- DON'T set LocalTransparencyModifier on head so it casts proper shadows
				-- Camera near plane clipping will keep it out of view
				descendant.LocalTransparencyModifier = 0
				descendant.CastShadow = true
			elseif descendant.Parent:IsA("Accessory") then
				-- Make accessories invisible to local player but keep shadows
				descendant.LocalTransparencyModifier = ACCESSORY_TRANSPARENCY
				descendant.CastShadow = true
			else
				-- Apply to torso, arms, legs, etc.
				descendant.LocalTransparencyModifier = BODY_TRANSPARENCY
			end
		end

		-- Also handle special face/decal objects on head
		if descendant:IsA("Decal") and descendant.Parent and descendant.Parent.Name == "Head" then
			descendant.LocalTransparencyModifier = 1
		end
	end
end

-- Function to setup first person camera
local function setupFirstPersonCamera(character)
	local humanoid = character:WaitForChild("Humanoid")
	local head = character:WaitForChild("Head")
	local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
	local movementCameraForward = 0
    local crouchY, cameraRoll, cameraPitch, landing = 0, 0, 0, 0
    if landingConnection then landingConnection:Disconnect() end
    landingConnection = GroundState.Landed:Connect(function(speed, snapshot)
        if snapshot.Character == character and perspective == PERSPECTIVE_FIRST
            and UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
            landing = math.max(landing, MotionMath.LandingStrength(speed))
        end
    end)
	local cameraRayParams = RaycastParams.new()
	cameraRayParams.FilterType = Enum.RaycastFilterType.Exclude
	cameraRayParams.FilterDescendantsInstances = { character }
	cameraRayParams.RespectCanCollide = true

	print("[FirstPersonViewModel] Setting up first person camera")

	-- Disable auto rotate so camera controls character rotation
	humanoid.AutoRotate = false

	-- Set camera to scriptable mode
	camera.CameraType = Enum.CameraType.Scriptable

	-- Lock mouse to center
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter

	-- Set transparency on body parts and accessories
	setCharacterTransparency(character)

	-- Reset camera rotation
	cameraRotation = Vector2.new(0, 0)

	-- Disconnect previous InputChanged connection to prevent stacking on respawn
	if inputConnection then
		inputConnection:Disconnect()
		inputConnection = nil
	end

	-- Disconnect previous camera RenderStep if it exists
	RunService:UnbindFromRenderStep("FirstPersonCamera")

	-- Handle mouse movement for camera rotation
	inputConnection = UserInputService.InputChanged:Connect(function(input, gameProcessed)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			-- Respect free cursor (DevPlacer, dialogs, minigames, etc.)
			if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
				return
			end
			local delta = input.Delta
			local sensitivity = VideoSettings.sensitivity

			-- Update rotation (yaw and pitch)
			cameraRotation = Vector2.new(
				math.clamp(cameraRotation.X - delta.Y * sensitivity, -math.pi/2 + 0.1, math.pi/2 - 0.1), -- Pitch (up/down) with limits
				cameraRotation.Y - delta.X * sensitivity  -- Yaw (left/right)
			)
		end
	end)

	-- Camera update function
	local function updateCamera(deltaTime)
		-- Studio/respawn can replace CurrentCamera; always drive the live camera.
		camera = workspace.CurrentCamera
		if not camera then return end
		-- Some other system (e.g. EnchantStationClient's altar-view pan) owns the
		-- camera right now -- leave CameraType/CFrame alone until it hands back.
		if CameraOverrideState.IsActive() then return end
		-- An override owner asked for us to come back looking somewhere (boss cutscene).
		-- Yaw/pitch are this script's own convention: Angles(pitch, yaw) looks along -Z.
		local look = CameraOverrideState.ConsumeLook()
		if look then
			cameraRotation = Vector2.new(
				math.clamp(math.asin(math.clamp(look.Y, -1, 1)), -math.pi/2 + 0.1, math.pi/2 - 0.1),
				math.atan2(-look.X, -look.Z)
			)
		end
		camera.CameraType = Enum.CameraType.Scriptable
		if head and head.Parent and humanoidRootPart and humanoidRootPart.Parent then
			local yaw = CFrame.Angles(0, cameraRotation.Y, 0)
			humanoidRootPart.CFrame = CFrame.new(humanoidRootPart.Position) * yaw
			local eyePosition = head.Position
			local locomotionState = character:GetAttribute("LocomotionState")
			local desiredForward = 0
			if locomotionState == "RunStart" or locomotionState == "RunLoop" then
				desiredForward = SPRINT_CAMERA_FORWARD
			elseif locomotionState == "Walk" or locomotionState == "CrouchWalk" then
				desiredForward = WALK_CAMERA_FORWARD
			end
			local blend = 1 - math.exp(-CAMERA_FORWARD_BLEND_SPEED * deltaTime)
			movementCameraForward += (desiredForward - movementCameraForward) * blend
			if perspective == PERSPECTIVE_FIRST then
				eyePosition += yaw.LookVector * movementCameraForward
			end

            local effectsEnabled = perspective == PERSPECTIVE_FIRST and humanoid.Health > 0
                and UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
            local motion = Movement.GetLocalMotion()
            local crouched = humanoidRootPart:GetAttribute("IsCrouching") == true
            crouchY += ((crouched and MotionConfig.CrouchCameraY or 0) - crouchY)
                * (1-math.exp(-MotionConfig.CrouchBlendSpeed*deltaTime))
            if not effectsEnabled then landing = 0 end
            local targetRoll = effectsEnabled and motion and -motion.CameraSide * MotionConfig.CameraRoll or 0
            local targetPitch = effectsEnabled and motion and motion.Burst * MotionConfig.CameraSprintPitch or 0
            local effectBlend = 1-math.exp(-MotionConfig.BlendSpeed*deltaTime)
            cameraRoll += (targetRoll-cameraRoll)*effectBlend
            cameraPitch += (targetPitch-cameraPitch)*effectBlend
            if perspective == PERSPECTIVE_FIRST then
                eyePosition += Vector3.new(0, crouchY - landing*MotionConfig.LandingDip, 0)
            end
            local roll = effectsEnabled and cameraRoll or 0
            local pitch = effectsEnabled and (cameraPitch + landing*MotionConfig.LandingPitch) or 0
            landing *= math.exp(-MotionConfig.LandingDecay*deltaTime)
			-- Position at eye height before pitching, so looking up/down cannot
			-- orbit the camera around the head if an offset is tuned later.
			local cameraCFrame = CFrame.new(eyePosition) *
				yaw *
				CFrame.new(CAMERA_OFFSET) *
				CFrame.Angles(cameraRotation.X + pitch, 0, roll)  -- Look plus bounded movement feedback

			if perspective == PERSPECTIVE_FRONT then
				-- Out in front, looking back at the face along the reversed aim.
				local focus = cameraCFrame.Position + Vector3.new(0, FRONT_HEIGHT, 0)
				local ahead = cameraCFrame.LookVector
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = { humanoidRootPart.Parent }
				local hit = workspace:Raycast(focus, ahead * FRONT_DISTANCE, params)
				local dist = hit and math.max((hit.Position - focus).Magnitude - CAMERA_COLLIDE_PAD, 0.5)
					or FRONT_DISTANCE
				cameraCFrame = CFrame.lookAt(focus + ahead * dist, focus)
				-- The default controls just moved us relative to THIS (reversed) camera, which
				-- would walk backwards; re-apply the input relative to the character instead.
				-- (Camera priority runs after the controls' Input-priority step, so this wins.)
				local controls = controlModule or nil
				local moveVector = controls and controls.GetMoveVector and controls:GetMoveVector()
				if moveVector then
					humanoid:Move(yaw:VectorToWorldSpace(moveVector), false)
				end
			elseif perspective == PERSPECTIVE_THIRD then
				local focus = cameraCFrame.Position + Vector3.new(0, THIRD_HEIGHT, 0)
				local back  = -cameraCFrame.LookVector
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = { humanoidRootPart.Parent }
				local hit = workspace:Raycast(focus, back * THIRD_DISTANCE, params)
				local dist = hit and math.max((hit.Position - focus).Magnitude - CAMERA_COLLIDE_PAD, 0.5)
					or THIRD_DISTANCE
				cameraCFrame = CFrame.lookAt(focus + back * dist, focus)
			else
				-- The larger forward offset must not put the camera through a wall.
				local wallOrigin = head.Position + Vector3.new(0, crouchY, 0)
				local offset = cameraCFrame.Position - wallOrigin
				local hit = workspace:Raycast(wallOrigin, offset, cameraRayParams)
				if hit and offset.Magnitude > 0.001 then
					local distance = math.max(0, (hit.Position - wallOrigin).Magnitude - FIRST_PERSON_WALL_PAD)
					cameraCFrame = CFrame.new(wallOrigin + offset.Unit * distance) * cameraCFrame.Rotation
				end
			end

			camera.CFrame = cameraCFrame

		end
	end

	-- Bind camera update to RenderStep at Camera priority
	RunService:BindToRenderStep("FirstPersonCamera", Enum.RenderPriority.Camera.Value, updateCamera)

	print("[FirstPersonViewModel] First person camera active")
end

-- Function to handle character added
local function onCharacterAdded(character)
	print("[FirstPersonViewModel] Character added, initializing first person view")

	-- Wait for character to fully load
	character:WaitForChild("Humanoid")
	character:WaitForChild("Head")
	character:WaitForChild("HumanoidRootPart")

	-- Small delay to ensure character is fully loaded
	task.wait(0.1)

	setupFirstPersonCamera(character)
end

-- Setup for current character if exists
if player.Character then
	onCharacterAdded(player.Character)
end

-- Handle character respawn
player.CharacterAdded:Connect(onCharacterAdded)

print("[FirstPersonViewModel] Script loaded")

-- Perspective toggle (Keys.TogglePerspective, default R).
-- Cycles first person -> over-shoulder -> front -> first person, Minecraft F5 style.
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode ~= Keys.TogglePerspective then return end

	perspective = perspective % #PERSPECTIVE_NAMES + 1
	player:SetAttribute("FirstPersonView", perspective == PERSPECTIVE_FIRST)
	player:SetAttribute("PerspectiveMode", PERSPECTIVE_NAMES[perspective])

	-- the head decal is forced invisible for first person; restore it in third
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	if head then
		for _, d in ipairs(head:GetDescendants()) do
			if d:IsA("Decal") then
				d.LocalTransparencyModifier = (perspective == PERSPECTIVE_FIRST) and 1 or 0
			end
		end
	end

	print("[FirstPersonViewModel] perspective =", perspective)
end)
