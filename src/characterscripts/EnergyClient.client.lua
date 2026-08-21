local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config        = require(ReplicatedStorage:WaitForChild("EnergyConfig"))
local States        = require(ReplicatedStorage:WaitForChild("PlayerStateEnum"))
local EnergyEvents  = ReplicatedStorage:WaitForChild("EnergyEvents")
local GameEvents    = ReplicatedStorage:WaitForChild("GameEvents")
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
local currentBarTween = nil

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
