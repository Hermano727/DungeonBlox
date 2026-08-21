-- Animate2 (LocalScript) - R15 Version
-- Place in StarterPlayer > StarterCharacterScripts

local Figure = script.Parent

-- Delete the default Animate script
local defaultAnimate = Figure:WaitForChild("Animate", 5)
if defaultAnimate then
	defaultAnimate:Destroy()
end

local Humanoid = Figure:WaitForChild("Humanoid")
local HumanoidRootPart = Figure:WaitForChild("HumanoidRootPart")

-- Destroying the default Animate script above does NOT stop any AnimationTracks
-- it already started playing -- tracks live on the Animator and outlive the
-- script that created them. An orphaned track keeps IsPlaying=true at whatever
-- priority it used (often Core) forever, which both locks its joints against
-- procedural scripts (Turning/Lean writing C0) and fights our own animations
-- below. Stop anything already playing before we take over.
local function stopOrphanedTracks()
	local existingAnimator = Humanoid:FindFirstChildOfClass("Animator")
	if existingAnimator then
		for _, track in ipairs(existingAnimator:GetPlayingAnimationTracks()) do
			track:Stop(0)
		end
	end
end
stopOrphanedTracks()

local pose = "Standing"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")
local camera = workspace.CurrentCamera
local defaultFOV = camera.FieldOfView
local fovTween

local Config = require(ReplicatedStorage:WaitForChild("EnergyConfig"))
local EnergyEvents = ReplicatedStorage:WaitForChild("EnergyEvents")
local RequestSprint = EnergyEvents:WaitForChild("RequestSprint")
local EnergyChanged = EnergyEvents:WaitForChild("EnergyChanged")

-- ============================================
-- ANIMATION SPEED CONFIGURATION
-- ============================================
local IDLE_ANIM_SPEED = 1.0
local WALK_ANIM_SPEED = 1.0
local RUN_ANIM_SPEED = 1.3
local WALK_SPEED_SCALE = 8.7 -- was 14.5; scaled down with NORMAL_SPEED (-40%) to keep walk animation pace matched to actual WalkSpeed
local BACKWARDS_WALK_SPEED = 1.0
local JUMP_ANIM_SPEED = 1.0
local FALL_ANIM_SPEED = 1.0
local CLIMB_ANIM_SPEED_SCALE = 12.0
local SIT_ANIM_SPEED = 1.0

-- ============================================
-- RUNNING CONFIGURATION
-- ============================================
local isRunning = false
local originalWalkSpeed = Config.NORMAL_SPEED
local runSpeedBoost = Config.SPRINT_SPEED - Config.NORMAL_SPEED
local runAcceleration = 50
local targetWalkSpeed = originalWalkSpeed

-- ============================================
-- FOV CONFIGURATION
-- ============================================
local FOV_TWEEN_TIME = 0.5
local RUN_FOV_BOOST = 15

local currentAnim = ""
local currentAnimInstance = nil
local currentAnimTrack = nil
local currentAnimKeyframeHandler = nil
local currentAnimSpeed = 1
local animTable = {}

-- R15 animation IDs
local animNames = {
	idle = {
		{ id = "rbxassetid://507766666", weight = 9 },
		{ id = "rbxassetid://507766951", weight = 1 }
	},
	walk = {
		{ id = "rbxassetid://507777826", weight = 10 }
	},
	jump = {
		{ id = "rbxassetid://507765000", weight = 10 }
	},
	fall = {
		{ id = "rbxassetid://507767968", weight = 10 }
	},
	climb = {
		{ id = "rbxassetid://507765644", weight = 10 }
	},
	sit = {
		{ id = "rbxassetid://507768133", weight = 10 }
	},
	run = {
		{ id = "rbxassetid://507767714", weight = 10 }
	},
}

local idleWalkTransitionTime = 0.35

-- ============================================
-- CROUCH CHECK FUNCTION
-- ============================================
local function IsCrouching()
	if HumanoidRootPart then
		return HumanoidRootPart:GetAttribute("IsCrouching") == true
	end
	return false
end

function configureAnimationSet(name, fileList)
	if (animTable[name] ~= nil) then
		for _, connection in pairs(animTable[name].connections) do
			connection:disconnect()
		end
	end
	animTable[name] = {}
	animTable[name].count = 0
	animTable[name].totalWeight = 0
	animTable[name].connections = {}

	local config = script:FindFirstChild(name)
	if (config ~= nil) then
		table.insert(animTable[name].connections, config.ChildAdded:connect(function(child) configureAnimationSet(name, fileList) end))
		table.insert(animTable[name].connections, config.ChildRemoved:connect(function(child) configureAnimationSet(name, fileList) end))
		local idx = 1
		for _, childPart in pairs(config:GetChildren()) do
			if (childPart:IsA("Animation")) then
				table.insert(animTable[name].connections, childPart.Changed:connect(function(property) configureAnimationSet(name, fileList) end))
				animTable[name][idx] = {}
				animTable[name][idx].anim = childPart
				local weightObject = childPart:FindFirstChild("Weight")
				if (weightObject == nil) then
					animTable[name][idx].weight = 1
				else
					animTable[name][idx].weight = weightObject.Value
				end
				animTable[name].count = animTable[name].count + 1
				animTable[name].totalWeight = animTable[name].totalWeight + animTable[name][idx].weight
				idx = idx + 1
			end
		end
	end

	if (animTable[name].count <= 0) then
		for idx, anim in pairs(fileList) do
			animTable[name][idx] = {}
			animTable[name][idx].anim = Instance.new("Animation")
			animTable[name][idx].anim.Name = name
			animTable[name][idx].anim.AnimationId = anim.id
			animTable[name][idx].weight = anim.weight
			animTable[name].count = animTable[name].count + 1
			animTable[name].totalWeight = animTable[name].totalWeight + anim.weight
		end
	end
end

function scriptChildModified(child)
	local fileList = animNames[child.Name]
	if (fileList ~= nil) then
		configureAnimationSet(child.Name, fileList)
	end
end

script.ChildAdded:connect(scriptChildModified)
script.ChildRemoved:connect(scriptChildModified)

local function setupRunAnimation()
	local runValue = script:FindFirstChild("run")
	if runValue and runValue:IsA("StringValue") and runValue.Value ~= "" then
		animNames.run = { { id = runValue.Value, weight = 10 } }
	end
end

setupRunAnimation()

for name, fileList in pairs(animNames) do
	configureAnimationSet(name, fileList)
end

local function preloadAnimations()
	local assetsToLoad = {}
	for animName, animSet in pairs(animTable) do
		for i = 1, animSet.count do
			table.insert(assetsToLoad, animSet[i].anim)
		end
	end
	pcall(function()
		ContentProvider:PreloadAsync(assetsToLoad)
	end)
end

preloadAnimations()
setupRunAnimation()

-- Second pass: catch any default-Animate track that started slightly after our
-- first cleanup (preloading above takes real time, giving it a window to sneak in).
stopOrphanedTracks()

local jumpAnimTime = 0
local jumpAnimDuration = 0.3
local fallTransitionTime = 0.3

function stopAllAnimations()
	local oldAnim = currentAnim
	currentAnim = ""
	currentAnimInstance = nil
	if (currentAnimKeyframeHandler ~= nil) then
		currentAnimKeyframeHandler:disconnect()
	end
	if (currentAnimTrack ~= nil) then
		currentAnimTrack:Stop()
		currentAnimTrack:Destroy()
		currentAnimTrack = nil
	end
	return oldAnim
end

function setAnimationSpeed(speed)
	if speed ~= currentAnimSpeed then
		currentAnimSpeed = speed
		if currentAnimTrack then
			currentAnimTrack:AdjustSpeed(currentAnimSpeed)
		end
	end
end

function keyFrameReachedFunc(frameName)
	if (frameName == "End") then
		local repeatAnim = currentAnim
		local animSpeed = currentAnimSpeed
		playAnimation(repeatAnim, 0.0, Humanoid)
		setAnimationSpeed(animSpeed)
	end
end

function playAnimation(animName, transitionTime, humanoid)
	local roll = math.random(1, animTable[animName].totalWeight)
	local idx = 1
	while (roll > animTable[animName][idx].weight) do
		roll = roll - animTable[animName][idx].weight
		idx = idx + 1
	end
	local anim = animTable[animName][idx].anim

	if (anim ~= currentAnimInstance) then
		if (currentAnimTrack ~= nil) then
			currentAnimTrack:Stop(transitionTime)
			currentAnimTrack:Destroy()
		end

		currentAnimSpeed = 1.0

		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end

		currentAnimTrack = animator:LoadAnimation(anim)
		currentAnimTrack.Priority = Enum.AnimationPriority.Core
		currentAnimTrack:Play(transitionTime)
		currentAnim = animName
		currentAnimInstance = anim

		if (currentAnimKeyframeHandler ~= nil) then
			currentAnimKeyframeHandler:disconnect()
		end
		currentAnimKeyframeHandler = currentAnimTrack.KeyframeReached:connect(keyFrameReachedFunc)
	end
end

local function tweenFOV(targetFOV)
	if fovTween then
		fovTween:Cancel()
	end
	local tweenInfo = TweenInfo.new(FOV_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	fovTween = TweenService:Create(camera, tweenInfo, {FieldOfView = targetFOV})
	fovTween:Play()
end

function onRunning(speed)
	if speed > 0.01 then
		local backwards = false
		if HumanoidRootPart then
			local velocity = HumanoidRootPart.AssemblyLinearVelocity
			local look = HumanoidRootPart.CFrame.LookVector
			if velocity.Magnitude > 0.1 then
				local dot = velocity.Unit:Dot(look)
				if dot < -0.1 then
					backwards = true
				end
			end
		end

		local animToPlay = "walk"
		local transition = idleWalkTransitionTime

		if backwards then
			targetWalkSpeed = originalWalkSpeed
			animToPlay = "walk"
			tweenFOV(defaultFOV)
			if currentAnim == "walk" then
				transition = 0.1
			end
			playAnimation(animToPlay, transition, Humanoid)
			setAnimationSpeed(-(speed / WALK_SPEED_SCALE) * WALK_ANIM_SPEED * BACKWARDS_WALK_SPEED)
		else
			-- Check if crouching - if so, don't allow running
			if IsCrouching() then
				-- While crouching, ignore running input and keep default FOV
				targetWalkSpeed = originalWalkSpeed
				animToPlay = "walk"
				tweenFOV(defaultFOV)
				if currentAnim == "walk" then
					transition = 0.1
				end
				playAnimation(animToPlay, transition, Humanoid)
				setAnimationSpeed((speed / WALK_SPEED_SCALE) * WALK_ANIM_SPEED)
			else
				-- Not crouching, allow running normally
				if isRunning then
					targetWalkSpeed = originalWalkSpeed + runSpeedBoost
				else
					targetWalkSpeed = originalWalkSpeed
				end

				if isRunning and animNames.run[1].id ~= "" then
					animToPlay = "run"
					tweenFOV(defaultFOV + RUN_FOV_BOOST)
					if currentAnim == "run" then
						transition = 0.1
					end
				else
					animToPlay = "walk"
					tweenFOV(defaultFOV)
					if currentAnim == "walk" then
						transition = 0.1
					end
				end
				playAnimation(animToPlay, transition, Humanoid)

				if animToPlay == "run" then
					setAnimationSpeed(RUN_ANIM_SPEED)
				else
					setAnimationSpeed((speed / WALK_SPEED_SCALE) * WALK_ANIM_SPEED)
				end
			end
		end
		pose = "Running"
	else
		local transition = idleWalkTransitionTime
		if currentAnim == "idle" then
			transition = 0.1
		end
		playAnimation("idle", transition, Humanoid)
		setAnimationSpeed(IDLE_ANIM_SPEED)
		pose = "Standing"
		tweenFOV(defaultFOV)
	end
end

function onDied()
	pose = "Dead"
end

function onJumping()
	playAnimation("jump", 0.1, Humanoid)
	setAnimationSpeed(JUMP_ANIM_SPEED)
	jumpAnimTime = jumpAnimDuration
	pose = "Jumping"
end

function onClimbing(speed)
	playAnimation("climb", 0.1, Humanoid)
	setAnimationSpeed(speed / CLIMB_ANIM_SPEED_SCALE)
	pose = "Climbing"
end

function onGettingUp()
	pose = "GettingUp"
end

function onFreeFall()
	if (jumpAnimTime <= 0) then
		playAnimation("fall", fallTransitionTime, Humanoid)
		setAnimationSpeed(FALL_ANIM_SPEED)
	end
	pose = "FreeFall"
end

function onFallingDown()
	pose = "FallingDown"
end

function onSeated()
	pose = "Seated"
end

function onPlatformStanding()
	pose = "PlatformStanding"
end

function onSwimming(speed)
	if speed > 0 then
		pose = "Running"
	else
		pose = "Standing"
	end
end

local lastTick = 0

function move(time)
	local deltaTime = time - lastTick
	lastTick = time

	-- WalkSpeed is server-authoritative (EnergyServer); this script only drives feel/animation.

	if (jumpAnimTime > 0) then
		jumpAnimTime = jumpAnimTime - deltaTime
	end

	if (pose == "FreeFall" and jumpAnimTime <= 0) then
		playAnimation("fall", fallTransitionTime, Humanoid)
		setAnimationSpeed(FALL_ANIM_SPEED)
	elseif (pose == "Seated") then
		playAnimation("sit", 0.5, Humanoid)
		setAnimationSpeed(SIT_ANIM_SPEED)
		return
	elseif (pose == "Running") then
		-- handled by onRunning
	elseif (pose == "Dead" or pose == "GettingUp" or pose == "FallingDown" or pose == "PlatformStanding") then
		stopAllAnimations()
	end
end

-- ============================================
-- INPUT HANDLING
-- ============================================
local function onInputBegan(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift or input.KeyCode == Enum.KeyCode.ButtonL2 then
		if not isRunning then
			isRunning = true
			-- Only change speed if not crouching
			if not IsCrouching() then
				targetWalkSpeed = originalWalkSpeed + runSpeedBoost
			end
			RequestSprint:FireServer(true)
		end
	end
end

local function onInputEnded(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift or input.KeyCode == Enum.KeyCode.ButtonL2 then
		if isRunning then
			isRunning = false
			targetWalkSpeed = originalWalkSpeed
			RequestSprint:FireServer(false)
		end
	end
end

-- If the server denies/cancels sprint (out of energy, panting, etc.), sync local state
EnergyChanged.OnClientEvent:Connect(function(_, isPanting)
	if isPanting and isRunning then
		isRunning = false
		targetWalkSpeed = originalWalkSpeed
	end
end)

local function setupInputConnection()
	local player = Players.LocalPlayer
	if player then
		UserInputService = game:GetService("UserInputService")
		if player.Character == Figure or player.CharacterAdded:Wait() == Figure then
			pcall(function()
				UserInputService.InputBegan:Connect(onInputBegan)
				UserInputService.InputEnded:Connect(onInputEnded)
			end)
		end
	end
end

spawn(function()
	wait(1)
	setupInputConnection()
end)

-- ============================================
-- HUMANOID EVENT CONNECTIONS
-- ============================================
Humanoid.Died:connect(onDied)
Humanoid.Running:connect(onRunning)
Humanoid.Jumping:connect(onJumping)
Humanoid.Climbing:connect(onClimbing)
Humanoid.GettingUp:connect(onGettingUp)
Humanoid.FreeFalling:connect(onFreeFall)
Humanoid.FallingDown:connect(onFallingDown)
Humanoid.Seated:connect(onSeated)
Humanoid.PlatformStanding:connect(onPlatformStanding)
Humanoid.Swimming:connect(onSwimming)

playAnimation("idle", idleWalkTransitionTime, Humanoid)
setAnimationSpeed(IDLE_ANIM_SPEED)
pose = "Standing"

while Figure.Parent ~= nil do
	local _, time = wait(0.1)
	move(time)
end