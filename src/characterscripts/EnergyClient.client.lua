local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config        = require(ReplicatedStorage:WaitForChild("EnergyConfig"))
local States        = require(ReplicatedStorage:WaitForChild("PlayerStateEnum"))
local EnergyEvents  = ReplicatedStorage:WaitForChild("EnergyEvents")
local GameEvents    = ReplicatedStorage:WaitForChild("GameEvents")
local RequestSprint  = EnergyEvents:WaitForChild("RequestSprint")
local RequestCrouch  = EnergyEvents:WaitForChild("RequestCrouch", 10)
local EnergyChanged = EnergyEvents:WaitForChild("EnergyChanged")
local StateChanged  = GameEvents:WaitForChild("StateChanged")

local player      = Players.LocalPlayer
local character   = player.Character or player.CharacterAdded:Wait()
local humanoid    = character:WaitForChild("Humanoid")
local playerGui   = player:WaitForChild("PlayerGui")
local energyBarGui  = playerGui:WaitForChild("EnergyBarGui")
local barBackground = energyBarGui:WaitForChild("BarBackground")
local barFill       = barBackground:WaitForChild("BarFill")
-- Use FindFirstChild with fallback so script never freezes if label is missing
local lowEnergyLabel = barBackground:FindFirstChild("LowEnergyLabel")

local HungerCfg = require(ReplicatedStorage:WaitForChild("HungerConfig"))
local hungerVal = player:WaitForChild("Hunger", 30)

local COLOR_NORMAL  = Color3.fromRGB(255, 200, 50)
local COLOR_LOCKOUT = Color3.fromRGB(220, 50, 50)
local barTweenInfo   = TweenInfo.new(0.08, Enum.EasingStyle.Linear)
local flashTweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local flashTween     = TweenService:Create(barFill, flashTweenInfo, {BackgroundTransparency=0.6})

local function setLabelVisible(v)
	if not lowEnergyLabel then return end
	TweenService:Create(lowEnergyLabel, TweenInfo.new(0.2), {TextTransparency = v and 0 or 1}):Play()
end

local isInLockout  = false
local isCrouching  = false
local currentBarTween = nil

-- Capture baseline HipHeight once (accounts for avatar scale modifiers)
local baseHipHeight = humanoid.HipHeight
humanoid:GetPropertyChangedSignal("HipHeight"):Connect(function()
    -- Keep baseHipHeight in sync unless WE changed it (guarded by isCrouching)
    if not isCrouching then
        baseHipHeight = humanoid.HipHeight
    end
end)

-- Animation track (optional — set CROUCH_ANIM_ID in EnergyConfig to enable)
local crouchTrack = nil
if Config.CROUCH_ANIM_ID and Config.CROUCH_ANIM_ID ~= "" then
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if animator then
        local anim = Instance.new("Animation")
        anim.AnimationId = "rbxassetid://" .. Config.CROUCH_ANIM_ID
        crouchTrack = animator:LoadAnimation(anim)
        crouchTrack.Priority = Enum.AnimationPriority.Action
        crouchTrack.Looped   = true
    end
end

local crouchTweenInfo = TweenInfo.new(
    Config.CROUCH_TWEEN_TIME or 0.18,
    Enum.EasingStyle.Quad,
    Enum.EasingDirection.Out
)

local function applyCrouchVisual(crouched)
    local targetHip = crouched
        and math.max(baseHipHeight - (Config.CROUCH_HIP_REDUCTION or 1.4), 0.1)
        or  baseHipHeight
    local targetOffset = crouched
        and Vector3.new(0, Config.CROUCH_CAM_OFFSET or -0.8, 0)
        or  Vector3.new(0, 0, 0)

    -- Single tween moves both HipHeight and CameraOffset together
    TweenService:Create(humanoid, crouchTweenInfo, {
        HipHeight    = targetHip,
        CameraOffset = targetOffset,
    }):Play()
end

local function enterCrouch()
    if isCrouching then return end
    isCrouching = true
    applyCrouchVisual(true)
    if crouchTrack then crouchTrack:Play() end
    if RequestCrouch then RequestCrouch:FireServer(true) end
end

local function exitCrouch()
    if not isCrouching then return end
    isCrouching = false
    applyCrouchVisual(false)
    if crouchTrack then crouchTrack:Stop() end
    if RequestCrouch then RequestCrouch:FireServer(false) end
end

local function updateBar(e)
	local ratio = math.clamp(e / Config.MAX_ENERGY, 0, 1)
	if currentBarTween then currentBarTween:Cancel() end
	currentBarTween = TweenService:Create(barFill, barTweenInfo, {Size=UDim2.new(ratio,0,1,0)})
	currentBarTween:Play()
end

local function enterLockout()
	flashTween:Cancel()
	barFill.BackgroundTransparency = 0
	barFill.BackgroundColor3 = COLOR_LOCKOUT
	flashTween:Play()
	if lowEnergyLabel and lowEnergyLabel:IsA("TextLabel") then
		lowEnergyLabel.Text = "PANTING..."
	end
	setLabelVisible(true)
end

local function exitLockout()
	flashTween:Cancel()
	barFill.BackgroundTransparency = 0
	barFill.BackgroundColor3 = COLOR_NORMAL
	setLabelVisible(false)
end

EnergyChanged.OnClientEvent:Connect(function(newEnergy, lockout)
	updateBar(newEnergy)
	if lockout and not isInLockout then
		isInLockout = true
		enterLockout()
	elseif not lockout and isInLockout then
		isInLockout = false
		exitLockout()
	end
end)

StateChanged.OnClientEvent:Connect(function(new, prev)
	if new == States.LOW_ENERGY and not isInLockout then
		isInLockout = true enterLockout()
	elseif prev == States.LOW_ENERGY and isInLockout then
		isInLockout = false exitLockout()
	end
end)

-- Sprint: LeftShift is a movement key, never skip it for gameProcessed
UserInputService.InputBegan:Connect(function(input, _gp)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		if isInLockout then return end
		if hungerVal and hungerVal.Value < HungerCfg.MIN_HUNGER_TO_SPRINT then
			return
		end
		-- Sprint cancels crouch
		if isCrouching then exitCrouch() end
		RequestSprint:FireServer(true)
	end
end)
UserInputService.InputEnded:Connect(function(input, _gp)
	if input.KeyCode == Enum.KeyCode.LeftShift then
		RequestSprint:FireServer(false)
	end
end)

-- Crouch: C key toggles. Blocked when dead (handled server-side too).
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.C then
		if isCrouching then
			exitCrouch()
		else
			-- Can't crouch during lockout (no movement restriction needed, but feels odd)
			enterCrouch()
		end
	end
end)
