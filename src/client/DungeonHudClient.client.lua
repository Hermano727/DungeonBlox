--[[
	DungeonHudClient
	Small always-on HUD shown only while this player is inside an active dungeon instance:
	dungeon name + run-duration timer + a "Leave Dungeon" button that removes only this
	player (DungeonInstanceService.removePlayerFromInstance), teleporting them to their
	hearthstone without affecting the rest of the party.

	The elapsed-time readout ticks locally off RunService.Heartbeat purely to refresh a text
	label (computed from the server-sent Unix `startTime`, exactly like HearthstoneClient's
	own cooldown countdown) -- this is NOT proximity/portal polling, and no remote is fired
	on tick.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DungeonTypes = require(ReplicatedStorage:WaitForChild("DungeonInstanceTypes"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gameEvents = ReplicatedStorage:WaitForChild("GameEvents")
local DungeonInstanceStateUpdate = gameEvents:WaitForChild("DungeonInstanceStateUpdate")
local DungeonLeaveRequest = gameEvents:WaitForChild("DungeonLeaveRequest")

----------------------------------------------------------------------
-- UI
----------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "DungeonHudUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 120
gui.Enabled = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0)
panel.Position = UDim2.new(0.5, 0, 0, 10)
panel.Size = UDim2.fromOffset(260, 64)
panel.BackgroundColor3 = Color3.fromRGB(18, 13, 13)
panel.BackgroundTransparency = 0.1
panel.BorderSizePixel = 0
panel.ZIndex = 1
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)
local stroke = Instance.new("UIStroke", panel)
stroke.Color = Color3.fromRGB(90, 65, 40)

local nameLbl = Instance.new("TextLabel", panel)
nameLbl.BackgroundTransparency = 1
nameLbl.Size = UDim2.new(1, -16, 0, 20)
nameLbl.Position = UDim2.new(0, 8, 0, 4)
nameLbl.Font = Enum.Font.GothamBold
nameLbl.TextSize = 14
nameLbl.TextXAlignment = Enum.TextXAlignment.Left
nameLbl.TextColor3 = Color3.fromRGB(255, 210, 110)
nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
nameLbl.Text = "In Dungeon"
nameLbl.ZIndex = 2

local timerLbl = Instance.new("TextLabel", panel)
timerLbl.BackgroundTransparency = 1
timerLbl.Size = UDim2.new(1, -100, 0, 18)
timerLbl.Position = UDim2.new(0, 8, 0, 24)
timerLbl.Font = Enum.Font.Gotham
timerLbl.TextSize = 12
timerLbl.TextXAlignment = Enum.TextXAlignment.Left
timerLbl.TextColor3 = Color3.fromRGB(200, 200, 210)
timerLbl.Text = "0:00"
timerLbl.ZIndex = 2

local leaveBtn = Instance.new("TextButton", panel)
leaveBtn.Size = UDim2.new(1, -16, 0, 22)
leaveBtn.Position = UDim2.new(0, 8, 1, -26)
leaveBtn.BackgroundColor3 = Color3.fromRGB(120, 45, 45)
leaveBtn.BorderSizePixel = 0
leaveBtn.Font = Enum.Font.GothamBold
leaveBtn.TextSize = 13
leaveBtn.TextColor3 = Color3.new(1, 1, 1)
leaveBtn.Text = "Leave Dungeon"
leaveBtn.ZIndex = 2
Instance.new("UICorner", leaveBtn).CornerRadius = UDim.new(0, 6)

----------------------------------------------------------------------
-- State + local timer tick (UI-only, not a server poll)
----------------------------------------------------------------------

local inDungeon = false
local startTime = 0

local function formatDuration(secs)
	secs = math.max(0, math.floor(secs))
	local h = math.floor(secs / 3600)
	local m = math.floor((secs % 3600) / 60)
	local s = secs % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

RunService.Heartbeat:Connect(function()
	if not inDungeon then return end
	timerLbl.Text = formatDuration(os.time() - startTime)
end)

leaveBtn.Activated:Connect(function()
	if not inDungeon then return end
	leaveBtn.Active = false
	DungeonLeaveRequest:FireServer()
end)

DungeonInstanceStateUpdate.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end

	if payload.state == DungeonTypes.State.IN_PROGRESS then
		inDungeon = true
		startTime = tonumber(payload.startTime) or os.time()
		nameLbl.Text = "In Dungeon: " .. tostring(payload.dungeonName or "?")
		leaveBtn.Active = true
		gui.Enabled = true
	elseif payload.state == DungeonTypes.State.ENDED then
		inDungeon = false
		gui.Enabled = false
	end
end)

print("[DungeonHudClient] ready")
