--[[
	PotionClient
	Charge/cooldown HUD for PotionService. Drinking itself is triggered by right-clicking
	while a potion is the equipped/held tool — see DrinkPotionClientTemplate (cloned into
	the DefaultPotionTool prefab by DungeonEquippedHotbar). This script owns only the
	charge readout, not the drink trigger.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gameEvents = ReplicatedStorage:WaitForChild("GameEvents", 10)
local chargesSync = gameEvents and gameEvents:WaitForChild("PotionChargesSync", 10)
local requestCharges = gameEvents and gameEvents:WaitForChild("RequestPotionCharges", 10)

local POTION_LABELS = {
	MinorPotion = "Minor",
	MediumPotion = "Medium",
}

---------------------------------------------------------------------------
-- Charge HUD (minimal: tier label, count, seconds until next charge)
---------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "PotionChargesUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50
gui.Parent = playerGui

local holder = Instance.new("Frame")
holder.Name = "Holder"
holder.BackgroundTransparency = 1
holder.AnchorPoint = Vector2.new(0, 1)
holder.Position = UDim2.new(0, 16, 1, -160)
holder.Size = UDim2.fromOffset(160, 50)
holder.Parent = gui

local rows = {}
local order = { "MinorPotion", "MediumPotion" }
for i, itemId in ipairs(order) do
	local row = Instance.new("TextLabel")
	row.Name = itemId
	row.BackgroundTransparency = 0.4
	row.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
	row.Size = UDim2.new(1, 0, 0, 22)
	row.Position = UDim2.fromOffset(0, (i - 1) * 24)
	row.Font = Enum.Font.GothamMedium
	row.TextSize = 13
	row.TextColor3 = Color3.fromRGB(220, 220, 220)
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.Text = "  " .. POTION_LABELS[itemId] .. " x?/3"
	row.Visible = false
	row.Parent = holder
	rows[itemId] = row
end

local latestCharges = {}

local function renderRow(itemId)
	local row = rows[itemId]
	if not row then return end
	local data = latestCharges[itemId]
	if not data then
		row.Visible = false
		return
	end
	row.Visible = true
	local label = POTION_LABELS[itemId] or itemId
	if data.secondsUntilNext and data.secondsUntilNext > 0 then
		row.Text = string.format("  %s x%d/3  (%ds)", label, data.count, math.ceil(data.secondsUntilNext))
	else
		row.Text = string.format("  %s x%d/3", label, data.count)
	end
end

local function applyChargesPayload(payload)
	if type(payload) ~= "table" then return end
	for itemId, data in pairs(payload) do
		latestCharges[itemId] = data
		renderRow(itemId)
	end
end

if chargesSync then
	chargesSync.OnClientEvent:Connect(applyChargesPayload)
end

if requestCharges then
	task.spawn(function()
		local ok, payload = pcall(function()
			return requestCharges:InvokeServer()
		end)
		if ok then
			applyChargesPayload(payload)
		end
	end)
end

-- Smooth the countdown between server pushes without waiting for the next sync.
RunService.Heartbeat:Connect(function(dt)
	for itemId, data in pairs(latestCharges) do
		if data.secondsUntilNext and data.secondsUntilNext > 0 then
			data.secondsUntilNext = math.max(0, data.secondsUntilNext - dt)
			renderRow(itemId)
		end
	end
end)

print("[PotionClient] ready")
