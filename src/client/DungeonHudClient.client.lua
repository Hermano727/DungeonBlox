--[[
	DungeonHudClient
	Small readout shown only while this player is inside an active dungeon instance:
	[hourglass] 1:26 -- the run's elapsed time. No dungeon title (2026-09-26: the old
	top-centre panel with the name and a big Leave button overlapped the boss bar).

	Sits in the bottom-left HUD stack (RS/HudBottomLeftStack, ORDER.Dungeon), directly above
	the combat timer (which always owns the very bottom).

	Leaving: click the timer and a small "Leave Dungeon" button opens beside it (it closes
	itself after a few seconds). Leave removes only this player
	(DungeonInstanceService.removePlayerFromInstance), teleporting them to their hearthstone
	without affecting the rest of the party.

	The elapsed-time readout ticks locally off RunService.Heartbeat purely to refresh a text
	label (computed from the server-sent Unix `startTime`, exactly like HearthstoneClient's
	own cooldown countdown) -- this is NOT proximity/portal polling, and no remote is fired
	on tick.
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DungeonTypes = require(ReplicatedStorage:WaitForChild("DungeonInstanceTypes"))
local Stack = require(ReplicatedStorage:WaitForChild("HudBottomLeftStack"))
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local HudIcons = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Icons"):WaitForChild("Hud"):WaitForChild("HudIcons"))

local gameEvents = ReplicatedStorage:WaitForChild("GameEvents")
local DungeonInstanceStateUpdate = gameEvents:WaitForChild("DungeonInstanceStateUpdate")
local DungeonLeaveRequest = gameEvents:WaitForChild("DungeonLeaveRequest")

local LEAVE_OPEN_SECONDS = 5

----------------------------------------------------------------------
-- UI
----------------------------------------------------------------------

local slot = Stack.Slot("DungeonTimer", Stack.ORDER.Dungeon)

-- [pill][leave button], side by side.
local row = Instance.new("UIListLayout", slot)
row.FillDirection = Enum.FillDirection.Horizontal
row.VerticalAlignment = Enum.VerticalAlignment.Center
row.SortOrder = Enum.SortOrder.LayoutOrder
row.Padding = UDim.new(0, 6)

local pill = Stack.Pill(slot, {
	height = 32,
	iconSize = 24,
	textSize = 18,
	textWidth = 58, -- fits "59:59"; hours widen it below
	font = UIFonts.HUDLabel,
	image = HudIcons.HOURGLASS,
	textColor = Color3.fromRGB(235, 215, 170),
})
pill.frame.LayoutOrder = 1
pill.label.Text = "0:00"

-- The whole pill is the button that opens Leave. Parented to the label (not the pill, whose
-- list layout would slot it in as a third item) and stretched back over the icon and padding.
local hit = Instance.new("TextButton")
hit.Name = "Hit"
hit.BackgroundTransparency = 1
hit.Text = ""
hit.Position = UDim2.fromOffset(-38, 0) -- left padding 8 + icon 24 + gap 6
hit.Size = UDim2.new(1, 50, 1, 0)       -- ...plus right padding 12
hit.ZIndex = 5
hit.Parent = pill.label

local leaveBtn = Instance.new("TextButton")
leaveBtn.Name = "Leave"
leaveBtn.LayoutOrder = 2
leaveBtn.Size = UDim2.fromOffset(120, 28)
leaveBtn.BackgroundColor3 = Color3.fromRGB(120, 42, 42)
leaveBtn.BackgroundTransparency = .1
leaveBtn.BorderSizePixel = 0
leaveBtn.TextColor3 = Color3.new(1, 1, 1)
leaveBtn.TextSize = 14
leaveBtn.Text = "Leave Dungeon"
leaveBtn.Visible = false
pcall(function() leaveBtn.FontFace = UIFonts.HUDLabel end)
Instance.new("UICorner", leaveBtn).CornerRadius = UDim.new(0, 6)
leaveBtn.Parent = slot

----------------------------------------------------------------------
-- State + local timer tick (UI-only, not a server poll)
----------------------------------------------------------------------

local inDungeon = false
local startTime = 0
local leaveSerial = 0

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
	local text = formatDuration(os.time() - startTime)
	if pill.label.Text ~= text then
		pill.label.Text = text
		pill.label.Size = UDim2.fromOffset(#text > 5 and 84 or 58, pill.label.Size.Y.Offset)
	end
end)

hit.Activated:Connect(function()
	if not inDungeon then return end
	leaveBtn.Visible = not leaveBtn.Visible
	leaveSerial += 1
	local serial = leaveSerial
	if leaveBtn.Visible then
		task.delay(LEAVE_OPEN_SECONDS, function()
			if leaveSerial == serial then leaveBtn.Visible = false end
		end)
	end
end)

leaveBtn.Activated:Connect(function()
	if not inDungeon or not leaveBtn.Active then return end
	leaveBtn.Active = false
	leaveBtn.Visible = false
	DungeonLeaveRequest:FireServer()
end)

DungeonInstanceStateUpdate.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end

	if payload.state == DungeonTypes.State.IN_PROGRESS then
		inDungeon = true
		startTime = tonumber(payload.startTime) or os.time()
		leaveBtn.Active = true
		leaveBtn.Visible = false
		slot.Visible = true
	elseif payload.state == DungeonTypes.State.ENDED then
		inDungeon = false
		leaveBtn.Visible = false
		slot.Visible = false
	end
end)

print("[DungeonHudClient] ready")
