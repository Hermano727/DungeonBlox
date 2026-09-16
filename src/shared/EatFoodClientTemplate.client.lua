--[[
	EatFoodClientTemplate
	Not run from ReplicatedStorage (LocalScripts don't run there). EquippedHotbar
	clones this script into the DefaultFoodTool prefab at runtime so the LocalScript only
	executes once parented under the player's Backpack/Character.

	Reads Tool attributes: DungeonItemUuid (required), FoodTimeToEat (seconds, optional).
	Fires ReplicatedStorage.GameEvents.EatFoodRequest with the UUID.
]]

local tool = script.Parent
local UIS = game:GetService("UserInputService")
local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local lp = Players.LocalPlayer
local pg = lp:WaitForChild("PlayerGui")

local conns = {}
local eatThread = nil

local function getEvent()
	local ge = RS:FindFirstChild("GameEvents")
	if not ge then return nil end
	local ev = ge:FindFirstChild("EatFoodRequest")
	if ev and ev:IsA("RemoteEvent") then return ev end
	return nil
end

local screenGui, barFrame, barFill, barLabel
local function buildHud()
	if screenGui and screenGui.Parent then return end
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "EatFoodHUD"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = pg

	barFrame = Instance.new("Frame")
	barFrame.Size = UDim2.new(0, 220, 0, 18)
	barFrame.Position = UDim2.new(0.5, -110, 0.68, 0)
	barFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	barFrame.BackgroundTransparency = 0.25
	barFrame.BorderSizePixel = 0
	barFrame.Visible = false
	barFrame.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = barFrame

	barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.Size = UDim2.new(0, 0, 1, 0)
	barFill.BackgroundColor3 = Color3.fromRGB(120, 200, 80)
	barFill.BorderSizePixel = 0
	barFill.Parent = barFrame

	local fillCorner = corner:Clone()
	fillCorner.Parent = barFill

	barLabel = Instance.new("TextLabel")
	barLabel.Size = UDim2.new(1, 0, 1, 0)
	barLabel.BackgroundTransparency = 1
	barLabel.Font = Enum.Font.GothamMedium
	barLabel.TextSize = 13
	barLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	barLabel.Text = "Eating..."
	barLabel.Parent = barFrame
end

local function cancelEat()
	if eatThread then
		task.cancel(eatThread)
		eatThread = nil
	end
	if barFrame then barFrame.Visible = false end
end

local function fireEat()
	local uuid = tool:GetAttribute("DungeonItemUuid")
	if type(uuid) ~= "string" or uuid == "" then return end
	local ev = getEvent()
	if ev then ev:FireServer(uuid) end
end

local function startEat()
	cancelEat()
	local tte = tonumber(tool:GetAttribute("FoodTimeToEat")) or 0
	if tte <= 0 then
		fireEat()
		return
	end
	buildHud()
	barLabel.Text = string.format("Eating %s...", tool.Name)
	barFill.Size = UDim2.new(0, 0, 1, 0)
	barFrame.Visible = true
	eatThread = task.spawn(function()
		local elapsed = 0
		while elapsed < tte do
			local dt = task.wait()
			elapsed = elapsed + dt
			local pct = math.clamp(elapsed / tte, 0, 1)
			barFill.Size = UDim2.new(pct, 0, 1, 0)
		end
		barFrame.Visible = false
		eatThread = nil
		fireEat()
	end)
end

tool.Equipped:Connect(function()
	buildHud()
	if UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
		startEat()
	end
	table.insert(conns, UIS.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			startEat()
		end
	end))
	table.insert(conns, UIS.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			cancelEat()
		end
	end))
end)

tool.Unequipped:Connect(function()
	for _, c in ipairs(conns) do
		pcall(function() c:Disconnect() end)
	end
	conns = {}
	cancelEat()
end)

tool.AncestryChanged:Connect(function(_, parent)
	if parent == nil then
		for _, c in ipairs(conns) do
			pcall(function() c:Disconnect() end)
		end
		conns = {}
		cancelEat()
	end
end)
