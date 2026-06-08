-- First Person ViewModel System
-- Allows player to see their own body in first person with realistic camera

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera


-- CAMERA POSITION SETTINGS - ADJUST HERE

-- CAMERA_OFFSET controls where the camera sits relative to your head
-- Vector3.new(X, Y, Z) where:
--   X = left/right offset (negative = left, positive = right)
--   Y = up/down offset (negative = down, positive = up)
--   Z = forward/back offset (negative = forward, positive = back)
-- Example: Vector3.new(0, 0, 0) = center of head
--          Vector3.new(0, 0.2, 0.3) = slightly up and forward
local CAMERA_OFFSET = Vector3.new(0, 0.95, 0)

-- Camera rotation sensitivity
local SENSITIVITY = 0.003

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
			local delta = input.Delta

			-- Update rotation (yaw and pitch)
			cameraRotation = Vector2.new(
				math.clamp(cameraRotation.X - delta.Y * SENSITIVITY, -math.pi/2 + 0.1, math.pi/2 - 0.1), -- Pitch (up/down) with limits
				cameraRotation.Y - delta.X * SENSITIVITY  -- Yaw (left/right)
			)
		end
	end)

	-- Camera update function
	local function updateCamera()
		if head and head.Parent and humanoidRootPart and humanoidRootPart.Parent then
			-- Create rotation CFrame from camera angles
			local cameraCFrame = CFrame.new(head.Position) *
				CFrame.Angles(0, cameraRotation.Y, 0) *  -- Yaw (horizontal rotation)
				CFrame.Angles(cameraRotation.X, 0, 0) *  -- Pitch (vertical rotation)
				CFrame.new(CAMERA_OFFSET)  -- Apply offset

			camera.CFrame = cameraCFrame

			-- Rotate character to face camera direction (only horizontal)
			humanoidRootPart.CFrame = CFrame.new(humanoidRootPart.Position) * CFrame.Angles(0, cameraRotation.Y, 0)
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