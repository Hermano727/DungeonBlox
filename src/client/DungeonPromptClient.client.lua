--[[
	DungeonPromptClient
	Shows the party-wide "Ready to enter [dungeon]?" dialog fired by
	DungeonInstanceService when the party leader touches a dungeon portal. Renders every
	real party member by name with a live status (Waiting.../Accepted/Rejected/Missing Key),
	not just an accepted-count -- updated in realtime via DungeonPromptStatusUpdate as
	members respond. If anyone lacks the tier's dungeon key, the dialog opens read-only with
	a blocking banner instead of Accept/Reject buttons.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MenuMouse = require(ReplicatedStorage:WaitForChild("CursorUtils"))
local DungeonTypes = require(ReplicatedStorage:WaitForChild("DungeonInstanceTypes"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gameEvents = ReplicatedStorage:WaitForChild("GameEvents")
local DungeonReadyPrompt = gameEvents:WaitForChild("DungeonReadyPrompt")
local DungeonPromptStatusUpdate = gameEvents:WaitForChild("DungeonPromptStatusUpdate")
local DungeonPromptCancelled = gameEvents:WaitForChild("DungeonPromptCancelled")
local DungeonPromptRespond = gameEvents:WaitForChild("DungeonPromptRespond")
local DungeonInstanceStateUpdate = gameEvents:WaitForChild("DungeonInstanceStateUpdate")

local STATUS_COLOR = {
	Waiting    = Color3.fromRGB(200, 190, 160),
	Accepted   = Color3.fromRGB(130, 220, 130),
	Rejected   = Color3.fromRGB(230, 110, 110),
	MissingKey = Color3.fromRGB(230, 170, 90),
}

----------------------------------------------------------------------
-- UI
----------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DungeonPromptUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 145
screenGui.Enabled = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local dim = Instance.new("TextButton")
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 0.45
dim.BorderSizePixel = 0
dim.Text = ""
dim.AutoButtonColor = false
dim.ZIndex = 1
dim.Parent = screenGui

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(380, 420)
panel.BackgroundColor3 = Color3.fromRGB(30, 22, 22)
panel.BorderSizePixel = 0
panel.ZIndex = 2
panel.Parent = screenGui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)
Instance.new("UIStroke", panel).Color = Color3.fromRGB(90, 70, 70)

local title = Instance.new("TextLabel", panel)
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, -24, 0, 36)
title.Position = UDim2.new(0, 12, 0, 10)
title.Font = Enum.Font.GothamBold
title.TextSize = 19
title.TextWrapped = true
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.new(1, 1, 1)
title.Text = "Ready to enter?"
title.ZIndex = 3

local bannerLbl = Instance.new("TextLabel", panel)
bannerLbl.BackgroundTransparency = 1
bannerLbl.Size = UDim2.new(1, -24, 0, 40)
bannerLbl.Position = UDim2.new(0, 12, 0, 46)
bannerLbl.Font = Enum.Font.GothamMedium
bannerLbl.TextSize = 13
bannerLbl.TextWrapped = true
bannerLbl.TextXAlignment = Enum.TextXAlignment.Left
bannerLbl.TextYAlignment = Enum.TextYAlignment.Top
bannerLbl.TextColor3 = Color3.fromRGB(230, 170, 90)
bannerLbl.Text = ""
bannerLbl.Visible = false
bannerLbl.ZIndex = 3

local rosterScroll = Instance.new("ScrollingFrame", panel)
rosterScroll.BackgroundColor3 = Color3.fromRGB(22, 16, 16)
rosterScroll.BorderSizePixel = 0
rosterScroll.Position = UDim2.new(0, 12, 0, 92)
rosterScroll.Size = UDim2.new(1, -24, 1, -160)
rosterScroll.CanvasSize = UDim2.new()
rosterScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
rosterScroll.ScrollBarThickness = 6
rosterScroll.ZIndex = 3
Instance.new("UICorner", rosterScroll).CornerRadius = UDim.new(0, 8)
local rosterLayout = Instance.new("UIListLayout", rosterScroll)
rosterLayout.Padding = UDim.new(0, 4)
rosterLayout.SortOrder = Enum.SortOrder.LayoutOrder
local rosterPad = Instance.new("UIPadding", rosterScroll)
rosterPad.PaddingTop = UDim.new(0, 6)
rosterPad.PaddingBottom = UDim.new(0, 6)
rosterPad.PaddingLeft = UDim.new(0, 8)
rosterPad.PaddingRight = UDim.new(0, 8)

local acceptBtn = Instance.new("TextButton", panel)
acceptBtn.Size = UDim2.fromOffset(160, 36)
acceptBtn.Position = UDim2.new(0, 12, 1, -46)
acceptBtn.BackgroundColor3 = Color3.fromRGB(55, 120, 70)
acceptBtn.BorderSizePixel = 0
acceptBtn.Font = Enum.Font.GothamBold
acceptBtn.TextSize = 15
acceptBtn.TextColor3 = Color3.new(1, 1, 1)
acceptBtn.Text = "Accept"
acceptBtn.ZIndex = 3
Instance.new("UICorner", acceptBtn).CornerRadius = UDim.new(0, 8)

local rejectBtn = Instance.new("TextButton", panel)
rejectBtn.Size = UDim2.fromOffset(160, 36)
rejectBtn.AnchorPoint = Vector2.new(1, 0)
rejectBtn.Position = UDim2.new(1, -12, 1, -46)
rejectBtn.BackgroundColor3 = Color3.fromRGB(120, 50, 50)
rejectBtn.BorderSizePixel = 0
rejectBtn.Font = Enum.Font.GothamBold
rejectBtn.TextSize = 15
rejectBtn.TextColor3 = Color3.new(1, 1, 1)
rejectBtn.Text = "Reject"
rejectBtn.ZIndex = 3
Instance.new("UICorner", rejectBtn).CornerRadius = UDim.new(0, 8)

local closeBtn = Instance.new("TextButton", panel)
closeBtn.Size = UDim2.fromOffset(160, 36)
closeBtn.AnchorPoint = Vector2.new(0.5, 0)
closeBtn.Position = UDim2.new(0.5, 0, 1, -46)
closeBtn.BackgroundColor3 = Color3.fromRGB(70, 55, 55)
closeBtn.BorderSizePixel = 0
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 15
closeBtn.TextColor3 = Color3.new(1, 1, 1)
closeBtn.Text = "Close"
closeBtn.Visible = false
closeBtn.ZIndex = 3
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------

local currentInstanceId = nil
local myResponseSent = false

local function close()
	screenGui.Enabled = false
	MenuMouse.release()
	currentInstanceId = nil
	myResponseSent = false
end

local function rebuildRoster(members)
	for _, ch in ipairs(rosterScroll:GetChildren()) do
		if ch:IsA("Frame") then ch:Destroy() end
	end
	for i, row in ipairs(members) do
		local frame = Instance.new("Frame")
		frame.LayoutOrder = i
		frame.Size = UDim2.new(1, 0, 0, 26)
		frame.BackgroundTransparency = 1
		frame.ZIndex = 4
		frame.Parent = rosterScroll

		local nameLbl = Instance.new("TextLabel", frame)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Size = UDim2.new(1, -110, 1, 0)
		nameLbl.Font = Enum.Font.GothamMedium
		nameLbl.TextSize = 14
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.TextColor3 = (row.userId == player.UserId) and Color3.fromRGB(255, 220, 130) or Color3.fromRGB(225, 225, 230)
		nameLbl.Text = row.name
		nameLbl.ZIndex = 4

		local statusLbl = Instance.new("TextLabel", frame)
		statusLbl.BackgroundTransparency = 1
		statusLbl.AnchorPoint = Vector2.new(1, 0)
		statusLbl.Size = UDim2.new(0, 108, 1, 0)
		statusLbl.Position = UDim2.new(1, 0, 0, 0)
		statusLbl.Font = Enum.Font.GothamBold
		statusLbl.TextSize = 13
		statusLbl.TextXAlignment = Enum.TextXAlignment.Right
		statusLbl.TextColor3 = STATUS_COLOR[row.status] or Color3.new(1, 1, 1)
		statusLbl.Text = DungeonTypes.MemberStatusLabel[row.status] or row.status
		statusLbl.ZIndex = 4
	end
end

local function applyPayload(payload)
	title.Text = string.format("Ready to enter %s?", payload.dungeonName or "the dungeon")
	rebuildRoster(payload.members or {})

	if payload.blocked then
		bannerLbl.Visible = true
		bannerLbl.Text = payload.blockedReason or "A party member is missing their dungeon key."
		acceptBtn.Visible = false
		rejectBtn.Visible = false
		closeBtn.Visible = true
	else
		bannerLbl.Visible = false
		closeBtn.Visible = false
		local myStatus = nil
		for _, row in ipairs(payload.members or {}) do
			if row.userId == player.UserId then
				myStatus = row.status
			end
		end
		local canRespond = myStatus == DungeonTypes.MemberStatus.WAITING
		acceptBtn.Visible = canRespond
		rejectBtn.Visible = canRespond
	end
end

DungeonReadyPrompt.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	currentInstanceId = payload.instanceId
	myResponseSent = false
	applyPayload(payload)
	screenGui.Enabled = true
	MenuMouse.acquire()
end)

DungeonPromptStatusUpdate.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" or payload.instanceId ~= currentInstanceId then return end
	applyPayload(payload)
end)

DungeonPromptCancelled.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" or payload.instanceId ~= currentInstanceId then return end
	bannerLbl.Visible = true
	bannerLbl.Text = payload.reason or "Dungeon entry cancelled."
	acceptBtn.Visible = false
	rejectBtn.Visible = false
	closeBtn.Visible = true
end)

-- Once every member has accepted, DungeonInstanceService launches the run and fires this
-- (separately from DungeonPromptStatusUpdate) -- close the ready-check dialog so it doesn't
-- sit on screen, full-screen-dimmed with both buttons hidden, forever after a successful
-- launch (this dialog was the only thing that ever tracked the prompt; nothing else closes it).
DungeonInstanceStateUpdate.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" or payload.instanceId ~= currentInstanceId then return end
	if payload.state == DungeonTypes.State.IN_PROGRESS or payload.state == DungeonTypes.State.ENDED then
		close()
	end
end)

acceptBtn.Activated:Connect(function()
	if not currentInstanceId or myResponseSent then return end
	myResponseSent = true
	acceptBtn.Visible = false
	rejectBtn.Visible = false
	DungeonPromptRespond:FireServer(currentInstanceId, true)
end)

rejectBtn.Activated:Connect(function()
	if not currentInstanceId or myResponseSent then return end
	myResponseSent = true
	DungeonPromptRespond:FireServer(currentInstanceId, false)
	close()
end)

closeBtn.Activated:Connect(close)
dim.Activated:Connect(function()
	-- Dim-click only dismisses a blocked/cancelled (read-only) prompt -- an active
	-- Waiting-for-response prompt should not be dismissible by accident.
	if closeBtn.Visible then
		close()
	end
end)

player.CharacterAdded:Connect(close)

print("[DungeonPromptClient] ready")
