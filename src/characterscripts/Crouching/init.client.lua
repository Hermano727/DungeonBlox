
-- -=/GETTING CHARACTER/=-
local plr = game.Players.LocalPlayer
local Character = plr.Character or plr.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")
local RootPart = Character:WaitForChild("HumanoidRootPart")

-- -=/SERVICES & CAMERA/=-
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Camera = workspace.CurrentCamera

----------------- { CONFIGURATION } ---------------------

local config = {
	CrouchButtons = Enum.KeyCode.C,                                                    -- Key for crouching
	CrouchingCooldown = 0.1,                                                           -- Minimum time required between crouching and uncrouching
	Speed = 8,                                                                         -- Speed while crouching
	DefaultFieldOfView = 70,                                                           -- Default Camera FOV
	CrouchFieldOfView = 60,                                                            -- Crouching Camera FOV (can make it the same or zoom in/out)
	CameraFOVCrouchTime = 0.5,                                                         -- Time to tween the camera to the crouching FOV
	CameraFOVResetTime = 1,                                                            -- Time to tween the camera back to the default FOV
	CameraOffset = -1,                                                                 -- How much the camera tweens down when crouching
	MinCameraDistance = 0.5,                                                           -- Minimum camera distance you want while Crouching
	MaxCameraDistance = 10,                                                            -- Maximum camera distance you want while Crouching
	CrouchEnabled = true,                                                              -- Whether crouching is enabled by default
	DustEnabled = true,                                                                -- Enables dust particles when crouching (if disabled you can delete the VFX folder in ReplicatedStorage)
	DynamicDustColor = true,                                                           -- Whether dust color should change based on material
	DustSpawnRate = 0.15,                                                              -- How often you want dust particles spawning
	MaxFreefallDuration = 0.35,                                                        -- Max Freefall duration before getting up
	StopOnLanding = true,                                                              -- Does crouch stop when the player lands
	CrouchInAir = false,                                                               -- Whether crouching is enabled when in the air
	RunningEnabled = true,                                                             -- Enabled since you have running system
	CrouchWalkAnimSpeed = 0.5                                                          -- Speed multiplier for crouch walk animation (1.0 = normal speed)
}

---------------------------------------------------------

-- -=/ANIMATIONS/=-
local Animator = Humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", Humanoid)
local CrouchIdleAnim = Animator:LoadAnimation(script:WaitForChild("Crouching"))
local CrouchWalkAnim = Animator:LoadAnimation(script:WaitForChild("CrouchWalk"))

-- -=/VARIABLES/=-
local CrouchSound = script:FindFirstChild("Crouch")
local GetUpSound = script:FindFirstChild("GetUp")
local originalSpeed = Humanoid.WalkSpeed
local originalMinCameraDistance = plr.CameraMinZoomDistance
local originalMaxCameraDistance = plr.CameraMaxZoomDistance
local dustDebounce = true
local notMoving = true
local crouchDebounce = true
local isOnGround = true
local freefallTimer = 0
local currentCrouchAnim = nil
local isCrouching = false
local fovTween = nil
local lastFOV = config.DefaultFieldOfView

-- Get references to the running system
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local runEvent = ReplicatedStorage:WaitForChild("UpdateRunningState")

-- Server-authoritative crouch (routes through the existing energy system)
local RequestCrouch = ReplicatedStorage:WaitForChild("EnergyEvents"):WaitForChild("RequestCrouch", 10)

-- -=/SETTING CAMERA FOV/=-
Camera.FieldOfView = config.DefaultFieldOfView
lastFOV = config.DefaultFieldOfView

-- -=/INITIAL ATTRIBUTE SETUP/=-
if RootPart:GetAttribute("IsCrouching") == nil then
	RootPart:SetAttribute("IsCrouching", false)
end

if RootPart:GetAttribute("CrouchEnabled") == nil then
	if config.CrouchEnabled == true then
		RootPart:SetAttribute("CrouchEnabled", true)
	else
		RootPart:SetAttribute("CrouchEnabled", false)
	end
end

-- -=/CROUCH KEY CHECK/=-
local function crouchKey(input)
	local crouchKeys = (typeof(config.CrouchButtons) == "table") and config.CrouchButtons or {config.CrouchButtons}

	for _, key in ipairs(crouchKeys) do
		if input.KeyCode == key then
			return true
		end
	end
	return false
end

-- -=/HEADROOM CHECK/=-
local function IsObstructed()
	local head = Character:FindFirstChild("Head")
	if head then
		local rayStart = head.Position
		local rayDirection = head.CFrame.UpVector * 1.5
		local raycastParams = RaycastParams.new()
		raycastParams.FilterDescendantsInstances = {Character}
		local raycastResult = workspace:Raycast(rayStart, rayDirection, raycastParams)
		return raycastResult ~= nil
	end
	return false
end

-- -=/HANDLE CROUCH ANIMATIONS/=-
local function HandleCrouchAnimations()
	if notMoving and isCrouching then
		-- Stop walk animation and play idle animation
		if currentCrouchAnim == CrouchWalkAnim then
			CrouchWalkAnim:Stop()
		end
		if not CrouchIdleAnim.IsPlaying then
			CrouchIdleAnim:Play()
			currentCrouchAnim = CrouchIdleAnim
		end
	elseif not notMoving and isCrouching then
		-- Stop idle animation and play walk animation
		if currentCrouchAnim == CrouchIdleAnim then
			CrouchIdleAnim:Stop()
		end
		if not CrouchWalkAnim.IsPlaying then
			CrouchWalkAnim:Play()
			CrouchWalkAnim:AdjustSpeed(config.CrouchWalkAnimSpeed)
			currentCrouchAnim = CrouchWalkAnim
		end
	end
end

-- -=/SMOOTH FOV FUNCTION/=-
local function SmoothFOV(targetFOV, duration)
	if fovTween then
		fovTween:Cancel()
		fovTween = nil
	end

	local tweenInfo = TweenInfo.new(
		duration,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)

	fovTween = TweenService:Create(Camera, tweenInfo, {FieldOfView = targetFOV})
	fovTween:Play()

	-- Store the target FOV
	lastFOV = targetFOV
end

-- -=/CROUCH FUNCTION/=-
local function Crouch()
	if not crouchDebounce or not RootPart:GetAttribute("CrouchEnabled") then return end
	if not config.CrouchInAir and not isOnGround then return end
	if isCrouching then return end

	crouchDebounce = false
	isCrouching = true
	RootPart:SetAttribute("IsCrouching", true)

	-- Play appropriate crouch animation based on movement
	HandleCrouchAnimations()

	if CrouchSound then
		CrouchSound:Play()
	end

	-- Crouch speed is applied server-side by CrouchService via RequestCrouch
	if RequestCrouch then RequestCrouch:FireServer(true) end

	plr.CameraMinZoomDistance = config.MinCameraDistance
	plr.CameraMaxZoomDistance = config.MaxCameraDistance
	Humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)

	-- Set crouch FOV
	SmoothFOV(config.CrouchFieldOfView, config.CameraFOVCrouchTime)

	local CAMgoal1 = { CameraOffset = Vector3.new(0, config.CameraOffset, 0) }
	local CAMinfo1 = TweenInfo.new(
		0.3,
		Enum.EasingStyle.Back,
		Enum.EasingDirection.Out,
		0,
		false,
		0
	)
	local CAMtween1 = TweenService:Create(Humanoid, CAMinfo1, CAMgoal1)
	CAMtween1:Play()

	task.delay(config.CrouchingCooldown, function()
		crouchDebounce = true
	end)
end

-- -=/STOP FUNCTION/=-
local function Stop()
	if not IsObstructed() then
		if isCrouching then
			isCrouching = false
			RootPart:SetAttribute("IsCrouching", false)

			-- Stop both crouch animations
			CrouchIdleAnim:Stop()
			CrouchWalkAnim:Stop()
			currentCrouchAnim = nil

			if GetUpSound then
				GetUpSound:Play()
			end

			-- Speed reset is applied server-side by CrouchService via RequestCrouch
			if RequestCrouch then RequestCrouch:FireServer(false) end

			plr.CameraMinZoomDistance = originalMinCameraDistance
			plr.CameraMaxZoomDistance = originalMaxCameraDistance
			Humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)

			-- Reset FOV to default
			SmoothFOV(config.DefaultFieldOfView, config.CameraFOVResetTime)

			local CAMgoal2 = { CameraOffset = Vector3.new(0, 0, 0) }
			local CAMinfo2 = TweenInfo.new(
				0.3,
				Enum.EasingStyle.Back,
				Enum.EasingDirection.Out,
				0,
				false,
				0
			)
			local CAMtween2 = TweenService:Create(Humanoid, CAMinfo2, CAMgoal2)
			CAMtween2:Play()
		end
	end
end

-- -=/KEY INPUT HANDLER/=-
UIS.InputBegan:Connect(function(input, isTyping)
	if isTyping then return end

	if crouchKey(input) then
		if not isCrouching then
			Crouch()
		else
			Stop()
		end
	end
end)

-- -=/STATE CHANGES HANDLER/=-
local function onStateChanged(_, newState)
	if isCrouching then
		if (newState == Enum.HumanoidStateType.Landed and config.StopOnLanding ~= false)
			or newState == Enum.HumanoidStateType.Dead
			or newState == Enum.HumanoidStateType.Climbing
			or newState == Enum.HumanoidStateType.Swimming
			or newState == Enum.HumanoidStateType.Seated
			or newState == Enum.HumanoidStateType.Physics then
			Stop()
		end
	end
end

-- -=/HEARTBEAT LOOP/=-
RunService.Heartbeat:Connect(function()

	-- -=/NON-MOVEMENT CHECK/=-
	notMoving = Humanoid.MoveDirection.Magnitude == 0

	-- Handle crouch animations based on movement
	HandleCrouchAnimations()

	if isCrouching then
		-- Only maintain FOV if our tween is complete and FOV gets changed externally
		if fovTween == nil and math.abs(Camera.FieldOfView - config.CrouchFieldOfView) > 0.5 then
			Camera.FieldOfView = config.CrouchFieldOfView
		end
	end

	-- -=/CROUCHING ENABLED VALUE CHECK/=-
	if isCrouching and not RootPart:GetAttribute("CrouchEnabled") then
		Stop()
	end

	-- -=/DUST PARTICLES/=-
	isOnGround = Humanoid.FloorMaterial ~= Enum.Material.Air

	if config.DustEnabled and isOnGround and isCrouching and dustDebounce and not notMoving then
		dustDebounce = false

		local rayParams = RaycastParams.new()
		rayParams.FilterDescendantsInstances = {Character}
		rayParams.FilterType = Enum.RaycastFilterType.Exclude

		local rayResult = workspace:Raycast(
			RootPart.Position + Vector3.new(0, 1, 0),
			Vector3.new(0, -4.5, 0),
			rayParams
		)

		local dustTemplate = game.ReplicatedStorage:FindFirstChild("VFX") and game.ReplicatedStorage.VFX:FindFirstChild("Dust")
		if dustTemplate then
			local dust = game.ReplicatedStorage.VFX.Dust:Clone()
			dust.Position = RootPart.Position + Vector3.new(0, -2.5, 0)
			dust.Parent = workspace.FX
			dust.Name = "CrouchDust"

			if config.DynamicDustColor then
				if rayResult then
					local hitPart = rayResult.Instance
					if hitPart and hitPart:IsA("BasePart") then
						dust.Attachment.Dust.Color = ColorSequence.new{
							ColorSequenceKeypoint.new(0, hitPart.Color),
							ColorSequenceKeypoint.new(1, hitPart.Color)
						}
					end
				end
			else
				dust.Attachment.Dust.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255)) -- Default dust color if dynamic dust color is not enabled
			end

			dust.Attachment.Dust:Emit(1)
			game.Debris:AddItem(dust, 0.8)

			task.wait(config.DustSpawnRate)
			dustDebounce = true
		end
	end

	-- -=/FREEFALL CHECK/=-
	if not isOnGround and isCrouching then
		freefallTimer = freefallTimer + RunService.Heartbeat:Wait()
		if freefallTimer >= config.MaxFreefallDuration then
			Stop()
		end
	else
		freefallTimer = 0
	end
end)

-- Monitor FOV changes from other scripts and maintain crouch FOV
RunService.Heartbeat:Connect(function()
	if isCrouching and fovTween == nil then
		-- If FOV gets changed by another script while crouching, restore it
		if math.abs(Camera.FieldOfView - config.CrouchFieldOfView) > 0.5 then
			Camera.FieldOfView = config.CrouchFieldOfView
		end
	end
end)

Humanoid.StateChanged:Connect(onStateChanged)

-- -=/CHARACTER ADDED HANDLER/=-
plr.CharacterAdded:Connect(function(newCharacter)
	Character = newCharacter
	Humanoid = Character:WaitForChild("Humanoid")
	RootPart = Character:WaitForChild("HumanoidRootPart")
	Animator = Humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", Humanoid)

	-- Reload animations for new character
	CrouchIdleAnim = Animator:LoadAnimation(script:WaitForChild("Crouching"))
	CrouchWalkAnim = Animator:LoadAnimation(script:WaitForChild("CrouchWalk"))

	-- Reset variables
	currentCrouchAnim = nil
	dustDebounce = true
	notMoving = true
	crouchDebounce = true
	isOnGround = true
	freefallTimer = 0
	isCrouching = false
	originalSpeed = Humanoid.WalkSpeed
	fovTween = nil
	lastFOV = config.DefaultFieldOfView

	-- Reset attributes for new character
	if RootPart:GetAttribute("IsCrouching") == nil then
		RootPart:SetAttribute("IsCrouching", false)
	end

	if RootPart:GetAttribute("CrouchEnabled") == nil then
		if config.CrouchEnabled == true then
			RootPart:SetAttribute("CrouchEnabled", true)
		else
			RootPart:SetAttribute("CrouchEnabled", false)
		end
	end

	-- Reconnect state changed event
	Humanoid.StateChanged:Connect(onStateChanged)
end)