--[[
	DungeonHudClient
	Small readout shown only while this player is inside an active dungeon instance:
	[hourglass] 1:26 -- the run's elapsed time. No dungeon title (2026-09-26: the old
	top-centre panel with the name and a big Leave button overlapped the boss bar).

	Sits in the bottom-left HUD stack (RS/HudBottomLeftStack, ORDER.Dungeon), directly above
	the combat timer (which always owns the very bottom).

	Leaving: a "Leave Dungeon" button sits beside the timer for the whole run (2026-10-11; it
	used to hide until you clicked the timer). Hold Ctrl (FreeLook) to free the cursor, click it,
	then click again within CONFIRM_SECONDS to confirm, so a stray click never ends your run.
	Leave removes only this player
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

local CONFIRM_SECONDS = 3
local LEAVE_COLOR = Color3.fromRGB(120, 42, 42)
local CONFIRM_COLOR = Color3.fromRGB(190, 52, 44)

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

-- Same height and plate as the timer pill, in a dark red, so the two read as one row.
local leaveBtn = Instance.new("TextButton")
leaveBtn.Name = "Leave"
leaveBtn.LayoutOrder = 2
leaveBtn.Size = UDim2.fromOffset(132, 32)
leaveBtn.BackgroundColor3 = LEAVE_COLOR
leaveBtn.BackgroundTransparency = .15
leaveBtn.BorderSizePixel = 0
leaveBtn.AutoButtonColor = true
leaveBtn.TextColor3 = Color3.fromRGB(245, 230, 220)
leaveBtn.TextStrokeTransparency = .6
leaveBtn.TextSize = 15
leaveBtn.Text = "Leave Dungeon"
pcall(function() leaveBtn.FontFace = UIFonts.HUDLabel end)
Instance.new("UICorner", leaveBtn).CornerRadius = UDim.new(0, 6)
local leaveStroke = Instance.new("UIStroke", leaveBtn)
leaveStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
leaveStroke.Color = Color3.fromRGB(60, 16, 16)
leaveStroke.Transparency = .3
leaveBtn.Parent = slot

----------------------------------------------------------------------
-- State + local timer tick (UI-only, not a server poll)
----------------------------------------------------------------------

local inDungeon = false
local startTime = 0
local armedSerial = 0 -- bumps on every arm/reset, so a stale confirm timeout can't disarm a newer one
local armed = false

local function disarm()
	armed = false
	armedSerial += 1
	leaveBtn.Text = "Leave Dungeon"
	leaveBtn.BackgroundColor3 = LEAVE_COLOR
end

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

leaveBtn.Activated:Connect(function()
	if not inDungeon or not leaveBtn.Active then return end
	if not armed then
		disarm()
		armed = true
		leaveBtn.Text = "Click to confirm"
		leaveBtn.BackgroundColor3 = CONFIRM_COLOR
		local serial = armedSerial
		task.delay(CONFIRM_SECONDS, function()
			if armedSerial == serial and armed then disarm() end
		end)
		return
	end
	disarm()
	leaveBtn.Active = false
	DungeonLeaveRequest:FireServer()
end)

DungeonInstanceStateUpdate.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end

	if payload.state == DungeonTypes.State.IN_PROGRESS then
		inDungeon = true
		startTime = tonumber(payload.startTime) or os.time()
		disarm()
		leaveBtn.Active = true
		slot.Visible = true
	elseif payload.state == DungeonTypes.State.ENDED then
		inDungeon = false
		disarm()
		slot.Visible = false
	end
end)

print("[DungeonHudClient] ready")
