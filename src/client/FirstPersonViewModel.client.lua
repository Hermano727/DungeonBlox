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

-- Camera rotation sensitivity now lives in VideoSettings.sensitivity (Settings
-- menu Video tab) -- read live below instead of a cached local, so dragging
-- the slider takes effect immediately without a respawn.

-- PERSPECTIVE MODES (Minecraft-style F5 cycling, bound to Keys.TogglePerspective)
--   1 = first person       - camera at the head, original behaviour
--   2 = over-shoulder      - camera pulled back along the look vector
-- Minecraft's 3rd-person camera sits 4 blocks back; scaled to a 5.8-stud
-- character that is ~13 studs. Roblox's own zoom system is NOT in play here
-- (CameraType is Scriptable), so this is an absolute distance, not a zoom %.
local PERSPECTIVE_FIRST  = 1
local PERSPECTIVE_THIRD  = 2
local THIRD_DISTANCE     = 11.05      -- studs behind the head
local THIRD_HEIGHT       = 1.5     -- studs above the head
local CAMERA_COLLIDE_PAD = 1.0     -- keep this far off geometry when pulled in
local perspective = PERSPECTIVE_FIRST

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
	local headBone = nil

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
	local function updateCamera()
		if head and head.Parent and humanoidRootPart and humanoidRootPart.Parent then
			local yaw = CFrame.Angles(0, cameraRotation.Y, 0)
			-- Align the character before measuring its animated forward lean.
			humanoidRootPart.CFrame = CFrame.new(humanoidRootPart.Position) * yaw
			local eyePosition = head.Position
			if perspective == PERSPECTIVE_FIRST then
				if not headBone or not headBone.Parent then
					local mesh = character:FindFirstChild("Hero_Character")
					local candidate = mesh and mesh:FindFirstChild("Head", true)
					headBone = candidate and candidate:IsA("Bone") and candidate or nil
				end
				if headBone then
					-- The helper Head stays still while walk/run poses lean forward.
					-- Follow only that forward displacement, keeping height and lateral
					-- position steady. Blended poses also ease this back when stopping.
					local displacement = headBone.TransformedWorldCFrame.Position - headBone.WorldPosition
					local forwardLean = math.max(0, displacement:Dot(yaw.LookVector))
					eyePosition += yaw.LookVector * forwardLean
				end
			end

			-- Position at eye height before pitching, so looking up/down cannot
			-- orbit the camera around the head if an offset is tuned later.
			local cameraCFrame = CFrame.new(eyePosition) *
				yaw *
				CFrame.new(CAMERA_OFFSET) *
				CFrame.Angles(cameraRotation.X, 0, 0)  -- Pitch (vertical rotation)

			if perspective == PERSPECTIVE_THIRD then
				local focus = cameraCFrame.Position + Vector3.new(0, THIRD_HEIGHT, 0)
				local back  = -cameraCFrame.LookVector
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = { humanoidRootPart.Parent }
				local hit = workspace:Raycast(focus, back * THIRD_DISTANCE, params)
				local dist = hit and math.max((hit.Position - focus).Magnitude - CAMERA_COLLIDE_PAD, 0.5)
					or THIRD_DISTANCE
				cameraCFrame = CFrame.lookAt(focus + back * dist, focus)
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
-- Cycles first person <-> over-shoulder, Minecraft F5 style.
-- View 3 (camera facing the player's face) is deliberately NOT implemented:
-- it needs character rotation decoupled from camera yaw, which the
-- humanoidRootPart.CFrame line inside updateCamera owns.
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode ~= Keys.TogglePerspective then return end

	perspective = (perspective == PERSPECTIVE_FIRST) and PERSPECTIVE_THIRD or PERSPECTIVE_FIRST

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
