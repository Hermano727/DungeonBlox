-- During an accepted drink, only walking and camera look remain available.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CAS = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local Prompts = game:GetService("ProximityPromptService")
local Action = require(RS:WaitForChild("PotionAction"))
local InteractionLock = require(RS:WaitForChild("InteractionLock"))
local player = Players.LocalPlayer
local inputs = {}
local allowed = {W = true, A = true, S = true, D = true, Escape = true, Unknown = true, Thumbstick1 = true, Thumbstick2 = true}
for _, key in ipairs(Enum.KeyCode:GetEnumItems()) do
	if not allowed[key.Name] then table.insert(inputs, key) end
end
for _, input in ipairs({Enum.UserInputType.MouseButton1, Enum.UserInputType.MouseButton2, Enum.UserInputType.MouseWheel}) do
	table.insert(inputs, input)
end
local character, attributeConnection, tickConnection, locked, promptsWereEnabled
local function unlock()
	if not locked then return end
	locked = false
	CAS:UnbindAction("PotionDrinkOnlyWalk")
	InteractionLock.Release("PotionDrink")
	Prompts.Enabled = promptsWereEnabled
	if tickConnection then tickConnection:Disconnect(); tickConnection = nil end
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if hum then hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, not (root and root:GetAttribute("IsCrouching"))) end
end
local function refresh()
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if not Action.IsLocked(character) or not hum or hum.Health <= 0 then unlock(); return end
	hum.Jump = false
	hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
	if locked then return end
	locked = true
	promptsWereEnabled = Prompts.Enabled
	Prompts.Enabled = false
	InteractionLock.CloseMenu()
	InteractionLock.Acquire("PotionDrink", {keepVitals = true})
	CAS:BindActionAtPriority("PotionDrinkOnlyWalk", function() return Enum.ContextActionResult.Sink end,
		false, Enum.ContextActionPriority.High.Value + 100, table.unpack(inputs))
	tickConnection = RunService.Heartbeat:Connect(refresh)
end
local function bind(nextCharacter)
	unlock()
	if attributeConnection then attributeConnection:Disconnect() end
	character = nextCharacter
	if character then attributeConnection = character:GetAttributeChangedSignal(Action.ATTRIBUTE):Connect(refresh); refresh() end
end
player.CharacterAdded:Connect(bind)
player.CharacterRemoving:Connect(function() bind(nil) end)
if player.Character then bind(player.Character) end
script.Destroying:Connect(function() bind(nil) end)
