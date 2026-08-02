local Keys = require(game:GetService("ReplicatedStorage"):WaitForChild("KeybindConfig"))
--[[
	PartyClient
	Press P to open the party menu, accept/decline invites, and show [PARTY] name tags.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local MenuMouse = require(ReplicatedStorage:WaitForChild("CursorUtils"))
local PartyConfig = require(ReplicatedStorage:WaitForChild("PartyConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local PartyRequest = ReplicatedStorage:WaitForChild("PartyRequest")
local gameEvents = ReplicatedStorage:WaitForChild("GameEvents")
local PartyInviteReceived = gameEvents:WaitForChild("PartyInviteReceived")
local PartyStateSync = gameEvents:WaitForChild("PartyStateSync")

local open = false
local partyUserIdSet = {}
local myParty = nil
local nameTags = {} -- [userId] = BillboardGui
local alignmentTags = {} -- [userId] = BillboardGui
local hpRefreshAccum = 0

local function request(action, arg)
	local ok, success, err = pcall(function()
		return PartyRequest:InvokeServer(action, arg)
	end)
	if not ok then
		warn("[PartyClient] request failed:", success)
		return false, "invoke_failed"
	end
	return success, err
end

------------------------------------------------------------------------
-- Compact Party HUD (right side, always-on when in party)
------------------------------------------------------------------------
local hudGui = Instance.new("ScreenGui")
hudGui.Name = "PartyHUD"
hudGui.ResetOnSpawn = false
hudGui.IgnoreGuiInset = false
hudGui.DisplayOrder = 125
hudGui.Enabled = false
hudGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
hudGui.Parent = playerGui

local hudPanel = Instance.new("Frame")
hudPanel.Name = "Panel"
hudPanel.AnchorPoint = Vector2.new(1, 0)
hudPanel.Position = UDim2.new(1, -8, 0.20, 0)
hudPanel.Size = UDim2.new(0, 220, 0, 0)
hudPanel.AutomaticSize = Enum.AutomaticSize.Y
hudPanel.BackgroundColor3 = Color3.fromRGB(18, 13, 13)
hudPanel.BackgroundTransparency = 0.10
hudPanel.BorderSizePixel = 0
hudPanel.ZIndex = 1
hudPanel.Parent = hudGui
Instance.new("UICorner", hudPanel).CornerRadius = UDim.new(0, 8)
local hudStroke = Instance.new("UIStroke", hudPanel)
hudStroke.Color = Color3.fromRGB(90, 65, 40)
hudStroke.Thickness = 1

local hudListLayout = Instance.new("UIListLayout", hudPanel)
hudListLayout.SortOrder = Enum.SortOrder.LayoutOrder
hudListLayout.Padding = UDim.new(0, 0)

local hudHeader = Instance.new("TextLabel")
hudHeader.Name = "Header"
hudHeader.LayoutOrder = 0
hudHeader.Size = UDim2.new(1, 0, 0, 26)
hudHeader.BackgroundColor3 = Color3.fromRGB(30, 20, 14)
hudHeader.BackgroundTransparency = 0
hudHeader.BorderSizePixel = 0
hudHeader.Font = Enum.Font.GothamBold
hudHeader.TextSize = 13
hudHeader.TextColor3 = Color3.fromRGB(255, 210, 110)
hudHeader.TextXAlignment = Enum.TextXAlignment.Center
hudHeader.Text = "Party | 0% Loot Buff"
hudHeader.ZIndex = 2
hudHeader.Parent = hudPanel

local hudDivider = Instance.new("Frame")
hudDivider.LayoutOrder = 1
hudDivider.Size = UDim2.new(1, 0, 0, 1)
hudDivider.BackgroundColor3 = Color3.fromRGB(80, 55, 35)
hudDivider.BackgroundTransparency = 0
hudDivider.BorderSizePixel = 0
hudDivider.ZIndex = 2
hudDivider.Parent = hudPanel

local hudMemberFrame = Instance.new("Frame")
hudMemberFrame.Name = "Members"
hudMemberFrame.LayoutOrder = 2
hudMemberFrame.Size = UDim2.new(1, 0, 0, 0)
hudMemberFrame.AutomaticSize = Enum.AutomaticSize.Y
hudMemberFrame.BackgroundTransparency = 1
hudMemberFrame.BorderSizePixel = 0
hudMemberFrame.ZIndex = 2
hudMemberFrame.Parent = hudPanel
Instance.new("UIListLayout", hudMemberFrame).SortOrder = Enum.SortOrder.LayoutOrder
local hudMemberPad = Instance.new("UIPadding", hudMemberFrame)
hudMemberPad.PaddingLeft = UDim.new(0, 8)
hudMemberPad.PaddingRight = UDim.new(0, 8)
hudMemberPad.PaddingTop = UDim.new(0, 3)
hudMemberPad.PaddingBottom = UDim.new(0, 4)

local function refreshHud()
	for _, ch in ipairs(hudMemberFrame:GetChildren()) do
		if ch:IsA("Frame") then ch:Destroy() end
	end
	if not myParty or not myParty.members or #myParty.members == 0 then
		hudGui.Enabled = false
		return
	end

	local memberData = {}
	for _, m in ipairs(myParty.members) do
		local plr = Players:GetPlayerByUserId(m.userId)
		local hp = 0
		if plr and plr.Character then
			local hum = plr.Character:FindFirstChildOfClass("Humanoid")
			if hum then hp = math.floor(hum.Health) end
		end
		table.insert(memberData, { name = m.name, userId = m.userId, hp = hp, isSelf = (m.userId == player.UserId) })
	end
	table.sort(memberData, function(a, b) return a.hp > b.hp end)

	local count = #memberData
	hudHeader.Text = string.format("Party | %d%% Loot Buff", count < 2 and 0 or count * 5)

	for i, m in ipairs(memberData) do
		local row = Instance.new("Frame")
		row.LayoutOrder = i
		row.Size = UDim2.new(1, 0, 0, 22)
		row.BackgroundTransparency = 1
		row.BorderSizePixel = 0
		row.ZIndex = 3
		row.Parent = hudMemberFrame

		local nameLbl = Instance.new("TextLabel", row)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Size = UDim2.new(1, -60, 1, 0)
		nameLbl.Font = Enum.Font.Gotham
		nameLbl.TextSize = 12
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
		nameLbl.TextColor3 = m.isSelf and Color3.fromRGB(255, 220, 130) or Color3.fromRGB(210, 210, 220)
		nameLbl.Text = string.format("%d. %s", i, m.name)
		nameLbl.ZIndex = 3

		local hpLbl = Instance.new("TextLabel", row)
		hpLbl.BackgroundTransparency = 1
		hpLbl.AnchorPoint = Vector2.new(1, 0)
		hpLbl.Size = UDim2.new(0, 58, 1, 0)
		hpLbl.Position = UDim2.new(1, 0, 0, 0)
		hpLbl.Font = Enum.Font.Gotham
		hpLbl.TextSize = 12
		hpLbl.TextXAlignment = Enum.TextXAlignment.Right
		hpLbl.TextColor3 = Color3.fromRGB(130, 195, 130)
		hpLbl.Text = m.hp .. " HP"
		hpLbl.ZIndex = 3
	end

	hudGui.Enabled = true
end

RunService.Heartbeat:Connect(function(dt)
	hpRefreshAccum = hpRefreshAccum + dt
	if hpRefreshAccum >= 0.5 then
		hpRefreshAccum = 0
		if hudGui.Enabled then refreshHud() end
	end
end)

------------------------------------------------------------------------
-- Main party UI (P key)
------------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PartyUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 130
screenGui.Enabled = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local dim = Instance.new("TextButton")
dim.Name = "Dim"
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 0.45
dim.BorderSizePixel = 0
dim.Text = ""
dim.AutoButtonColor = false
dim.ZIndex = 1
dim.Parent = screenGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(420, 400)
panel.BackgroundColor3 = Color3.fromRGB(30, 22, 22)
panel.BorderSizePixel = 0
panel.ZIndex = 2
panel.Parent = screenGui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)
local panelStroke = Instance.new("UIStroke", panel)
panelStroke.Color = Color3.fromRGB(90, 70, 70)

local title = Instance.new("TextLabel", panel)
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, -24, 0, 36)
title.Position = UDim2.new(0, 12, 0, 8)
title.Font = Enum.Font.GothamBold
title.TextSize = 22
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.new(1, 1, 1)
title.Text = "Party"
title.ZIndex = 3

local hint = Instance.new("TextLabel", panel)
hint.BackgroundTransparency = 1
hint.Size = UDim2.new(1, -24, 0, 18)
hint.Position = UDim2.new(0, 12, 0, 40)
hint.Font = Enum.Font.Gotham
hint.TextSize = 13
hint.TextXAlignment = Enum.TextXAlignment.Left
hint.TextColor3 = Color3.fromRGB(180, 160, 130)
hint.Text = "Press P to toggle  ·  party loot buff: +5% per member (max 8 players)"
hint.ZIndex = 3

local createBtn = Instance.new("TextButton", panel)
createBtn.Size = UDim2.fromOffset(120, 30)
createBtn.Position = UDim2.new(0, 12, 0, 72)
createBtn.BackgroundColor3 = Color3.fromRGB(50, 80, 55)
createBtn.BorderSizePixel = 0
createBtn.Font = Enum.Font.GothamBold
createBtn.TextSize = 14
createBtn.TextColor3 = Color3.new(1, 1, 1)
createBtn.Text = "Create Party"
createBtn.Visible = true
createBtn.ZIndex = 3
Instance.new("UICorner", createBtn).CornerRadius = UDim.new(0, 8)

local leaveBtn = Instance.new("TextButton", panel)
leaveBtn.Size = UDim2.fromOffset(110, 30)
leaveBtn.Position = UDim2.new(0, 12, 0, 72)
leaveBtn.BackgroundColor3 = Color3.fromRGB(120, 45, 45)
leaveBtn.BorderSizePixel = 0
leaveBtn.Font = Enum.Font.GothamBold
leaveBtn.TextSize = 14
leaveBtn.TextColor3 = Color3.new(1, 1, 1)
leaveBtn.Text = "Leave Party"
leaveBtn.Visible = false
leaveBtn.ZIndex = 3
Instance.new("UICorner", leaveBtn).CornerRadius = UDim.new(0, 8)

local serverSection = Instance.new("TextLabel", panel)
serverSection.BackgroundTransparency = 1
serverSection.Size = UDim2.new(1, -24, 0, 20)
serverSection.Position = UDim2.new(0, 12, 0, 114)
serverSection.Font = Enum.Font.GothamBold
serverSection.TextSize = 14
serverSection.TextXAlignment = Enum.TextXAlignment.Left
serverSection.TextColor3 = Color3.fromRGB(200, 200, 210)
serverSection.Text = "Players in Server"
serverSection.ZIndex = 3

local scroll = Instance.new("ScrollingFrame", panel)
scroll.Name = "PlayerScroll"
scroll.BackgroundColor3 = Color3.fromRGB(22, 16, 16)
scroll.BorderSizePixel = 0
scroll.Position = UDim2.new(0, 12, 0, 138)
scroll.Size = UDim2.new(1, -24, 1, -150)
scroll.CanvasSize = UDim2.new()
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.ScrollBarThickness = 6
scroll.ZIndex = 3
Instance.new("UICorner", scroll).CornerRadius = UDim.new(0, 8)
local scrollLayout = Instance.new("UIListLayout", scroll)
scrollLayout.Padding = UDim.new(0, 4)
scrollLayout.SortOrder = Enum.SortOrder.Name
local scrollPad = Instance.new("UIPadding", scroll)
scrollPad.PaddingTop = UDim.new(0, 6)
scrollPad.PaddingBottom = UDim.new(0, 6)
scrollPad.PaddingLeft = UDim.new(0, 8)
scrollPad.PaddingRight = UDim.new(0, 8)

local statusLabel = Instance.new("TextLabel", panel)
statusLabel.BackgroundTransparency = 1
statusLabel.AnchorPoint = Vector2.new(0, 1)
statusLabel.Position = UDim2.new(0, 12, 1, -10)
statusLabel.Size = UDim2.new(1, -24, 0, 16)
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 12
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
statusLabel.Text = ""
statusLabel.ZIndex = 3

local function showStatus(msg, isError)
	statusLabel.Text = msg or ""
	statusLabel.TextColor3 = isError and Color3.fromRGB(255, 120, 120) or Color3.fromRGB(140, 200, 140)
end

local function clearChildren(frame)
	for _, ch in ipairs(frame:GetChildren()) do
		if not ch:IsA("UIListLayout") and not ch:IsA("UIPadding") then
			ch:Destroy()
		end
	end
end

local function makeRow(parent, labelText, buttonText, onClick)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 28)
	row.ZIndex = 4
	row.Parent = parent

	local lbl = Instance.new("TextLabel", row)
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.new(1, -90, 1, 0)
	lbl.Font = Enum.Font.GothamMedium
	lbl.TextSize = 14
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextColor3 = Color3.fromRGB(230, 230, 235)
	lbl.Text = labelText
	lbl.ZIndex = 4

	if buttonText and onClick then
		local btn = Instance.new("TextButton", row)
		btn.AnchorPoint = Vector2.new(1, 0.5)
		btn.Position = UDim2.new(1, 0, 0.5, 0)
		btn.Size = UDim2.fromOffset(80, 24)
		btn.BackgroundColor3 = Color3.fromRGB(55, 95, 65)
		btn.BorderSizePixel = 0
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 12
		btn.TextColor3 = Color3.new(1, 1, 1)
		btn.Text = buttonText
		btn.ZIndex = 4
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
		btn.Activated:Connect(onClick)
	end
end

local function updateModalButtons()
	local inParty = myParty ~= nil
	createBtn.Visible = not inParty
	leaveBtn.Visible = inParty
end

local function refreshServerList()
	clearChildren(scroll)
	local myMemberIds = {}
	if myParty and myParty.members then
		for _, m in ipairs(myParty.members) do
			myMemberIds[m.userId] = true
		end
	end
	local partyFull = myParty and myParty.members and #myParty.members >= PartyConfig.MAX_PARTY_SIZE

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= player then
			local display = plr.DisplayName ~= "" and plr.DisplayName or plr.Name
			if myMemberIds[plr.UserId] then
				makeRow(scroll, display, nil, nil)
			elseif partyUserIdSet[plr.UserId] then
				makeRow(scroll, display .. " (in another party)", nil, nil)
			elseif not partyFull then
				makeRow(scroll, display, "Invite", function()
					local ok, err = request("invite", plr.UserId)
					if ok then
						showStatus("Invite sent to " .. display, false)
					else
						showStatus("Invite failed: " .. tostring(err), true)
					end
				end)
			else
				makeRow(scroll, display .. " (party full)", nil, nil)
			end
		end
	end
end

local function setOpen(v)
	if v == open then return end
	open = v
	screenGui.Enabled = v
	if v then
		MenuMouse.acquire()
		updateModalButtons()
		refreshServerList()
		showStatus("", false)
	else
		MenuMouse.release()
	end
end

dim.Activated:Connect(function() setOpen(false) end)

createBtn.Activated:Connect(function()
	local ok, err = request("create")
	if ok then
		showStatus("Party created", false)
	else
		showStatus("Could not create party: " .. tostring(err), true)
	end
end)

leaveBtn.Activated:Connect(function()
	local ok, err = request("leave")
	if ok then
		showStatus("Left party", false)
	else
		showStatus("Leave failed: " .. tostring(err), true)
	end
end)

------------------------------------------------------------------------
-- Invite popup
------------------------------------------------------------------------
local inviteGui = Instance.new("ScreenGui")
inviteGui.Name = "PartyInviteUI"
inviteGui.ResetOnSpawn = false
inviteGui.IgnoreGuiInset = true
inviteGui.DisplayOrder = 140
inviteGui.Enabled = false
inviteGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
inviteGui.Parent = playerGui

local invitePanel = Instance.new("Frame", inviteGui)
invitePanel.AnchorPoint = Vector2.new(0.5, 0.5)
invitePanel.Position = UDim2.fromScale(0.5, 0.5)
invitePanel.Size = UDim2.fromOffset(360, 170)
invitePanel.BackgroundColor3 = Color3.fromRGB(30, 22, 22)
invitePanel.BorderSizePixel = 0
invitePanel.ZIndex = 2
Instance.new("UICorner", invitePanel).CornerRadius = UDim.new(0, 12)
Instance.new("UIStroke", invitePanel).Color = Color3.fromRGB(90, 70, 70)

local inviteTitle = Instance.new("TextLabel", invitePanel)
inviteTitle.BackgroundTransparency = 1
inviteTitle.Size = UDim2.new(1, -24, 0, 28)
inviteTitle.Position = UDim2.new(0, 12, 0, 12)
inviteTitle.Font = Enum.Font.GothamBold
inviteTitle.TextSize = 18
inviteTitle.TextColor3 = Color3.new(1, 1, 1)
inviteTitle.Text = "Party Invite"
inviteTitle.ZIndex = 3

local inviteBody = Instance.new("TextLabel", invitePanel)
inviteBody.BackgroundTransparency = 1
inviteBody.Size = UDim2.new(1, -24, 0, 48)
inviteBody.Position = UDim2.new(0, 12, 0, 44)
inviteBody.Font = Enum.Font.Gotham
inviteBody.TextSize = 15
inviteBody.TextWrapped = true
inviteBody.TextColor3 = Color3.fromRGB(210, 210, 220)
inviteBody.Text = ""
inviteBody.ZIndex = 3

local acceptBtn = Instance.new("TextButton", invitePanel)
acceptBtn.Size = UDim2.fromOffset(120, 34)
acceptBtn.Position = UDim2.new(0.5, -130, 1, -46)
acceptBtn.BackgroundColor3 = Color3.fromRGB(55, 120, 70)
acceptBtn.BorderSizePixel = 0
acceptBtn.Font = Enum.Font.GothamBold
acceptBtn.TextSize = 14
acceptBtn.TextColor3 = Color3.new(1, 1, 1)
acceptBtn.Text = "Accept"
acceptBtn.ZIndex = 3
Instance.new("UICorner", acceptBtn).CornerRadius = UDim.new(0, 8)

local declineBtn = Instance.new("TextButton", invitePanel)
declineBtn.Size = UDim2.fromOffset(120, 34)
declineBtn.Position = UDim2.new(0.5, 10, 1, -46)
declineBtn.BackgroundColor3 = Color3.fromRGB(120, 50, 50)
declineBtn.BorderSizePixel = 0
declineBtn.Font = Enum.Font.GothamBold
declineBtn.TextSize = 14
declineBtn.TextColor3 = Color3.new(1, 1, 1)
declineBtn.Text = "Decline"
declineBtn.ZIndex = 3
Instance.new("UICorner", declineBtn).CornerRadius = UDim.new(0, 8)

local pendingInviterUserId = nil

local function showInvite(inviterName, inviterUserId)
	pendingInviterUserId = inviterUserId
	inviteBody.Text = string.format("%s invited you to join their party.", inviterName)
	inviteGui.Enabled = true
	MenuMouse.acquire()
end

local function hideInvite()
	inviteGui.Enabled = false
	pendingInviterUserId = nil
	if not open then
		MenuMouse.release()
	end
end

acceptBtn.Activated:Connect(function()
	if not pendingInviterUserId then
		return
	end
	local ok, err = request("accept", pendingInviterUserId)
	hideInvite()
	if not ok then
		showStatus("Could not join party: " .. tostring(err), true)
		if open then
			refreshServerList()
		end
	end
end)

declineBtn.Activated:Connect(function()
	if pendingInviterUserId then
		request("decline", pendingInviterUserId)
	end
	hideInvite()
end)

PartyInviteReceived.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	showInvite(tostring(payload.inviterName or "Someone"), payload.inviterUserId)
end)

------------------------------------------------------------------------
-- Alignment name tags (Neutral=yellow, Chaotic=red)
------------------------------------------------------------------------
local ALIGNMENT_COLOR = {
	Neutral = Color3.fromRGB(255, 215, 80),
	Chaotic = Color3.fromRGB(255, 80, 80),
}
local ALIGNMENT_LABEL = {
	Neutral = "[NEUTRAL]",
	Chaotic = "[CHAOTIC]",
}

local function removeAlignmentTag(userId)
	local tag = alignmentTags[userId]
	if tag then
		tag:Destroy()
		alignmentTags[userId] = nil
	end
end

local function refreshAlignmentTag(plr)
	if plr == player then return end
	local alignment = plr:GetAttribute("PlayerAlignment")
	local color = alignment and ALIGNMENT_COLOR[alignment]
	local labelText = alignment and ALIGNMENT_LABEL[alignment]
	if not color then
		removeAlignmentTag(plr.UserId)
		return
	end

	local char = plr.Character
	local head = char and char:FindFirstChild("Head")
	if not head then
		removeAlignmentTag(plr.UserId)
		return
	end

	local existing = alignmentTags[plr.UserId]
	if existing and existing.Parent == head then
		local lbl = existing:FindFirstChild("AlignLabel")
		if lbl then
			lbl.Text = labelText
			lbl.TextColor3 = color
		end
		return
	end

	removeAlignmentTag(plr.UserId)

	local bb = Instance.new("BillboardGui")
	bb.Name = "AlignmentTag"
	bb.Size = UDim2.fromOffset(200, 24)
	bb.StudsOffset = Vector3.new(0, 3.8, 0)
	bb.AlwaysOnTop = true
	bb.Adornee = head
	bb.Parent = head

	local lbl = Instance.new("TextLabel")
	lbl.Name = "AlignLabel"
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 13
	lbl.TextColor3 = color
	lbl.TextStrokeTransparency = 0.4
	lbl.Text = labelText
	lbl.Parent = bb

	alignmentTags[plr.UserId] = bb
end

local function watchAlignmentFor(plr)
	if plr == player then return end
	plr.AttributeChanged:Connect(function(attr)
		if attr == "PlayerAlignment" then
			refreshAlignmentTag(plr)
		end
	end)
	plr.CharacterAdded:Connect(function()
		task.defer(function()
			refreshAlignmentTag(plr)
		end)
	end)
	refreshAlignmentTag(plr)
end

------------------------------------------------------------------------
-- [PARTY] name tags
------------------------------------------------------------------------
local function removeNameTag(userId)
	local tag = nameTags[userId]
	if tag then
		tag:Destroy()
		nameTags[userId] = nil
	end
end

local function ensureNameTag(plr)
	if not partyUserIdSet[plr.UserId] then
		removeNameTag(plr.UserId)
		return
	end

	local char = plr.Character
	if not char then
		return
	end
	local head = char:FindFirstChild("Head")
	if not head then
		return
	end

	local existing = nameTags[plr.UserId]
	if existing and existing.Parent == head then
		local lbl = existing:FindFirstChild("PartyLabel")
		if lbl and lbl:IsA("TextLabel") then
			local display = plr.DisplayName ~= "" and plr.DisplayName or plr.Name
			lbl.Text = "[PARTY] " .. display
		end
		return
	end

	removeNameTag(plr.UserId)

	local bb = Instance.new("BillboardGui")
	bb.Name = "PartyNameTag"
	bb.Size = UDim2.fromOffset(200, 28)
	bb.StudsOffset = Vector3.new(0, 2.4, 0)
	bb.AlwaysOnTop = true
	bb.Adornee = head
	bb.Parent = head

	local lbl = Instance.new("TextLabel")
	lbl.Name = "PartyLabel"
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 14
	lbl.TextColor3 = Color3.fromRGB(120, 220, 255)
	lbl.TextStrokeTransparency = 0.4
	lbl.Text = "[PARTY] " .. (plr.DisplayName ~= "" and plr.DisplayName or plr.Name)
	lbl.Parent = bb

	nameTags[plr.UserId] = bb
end

local function refreshAllNameTags()
	for _, plr in ipairs(Players:GetPlayers()) do
		ensureNameTag(plr)
	end
	for uid in pairs(nameTags) do
		if not partyUserIdSet[uid] then
			removeNameTag(uid)
		end
	end
end

local function applyState(payload)
	if type(payload) ~= "table" then
		return
	end

	partyUserIdSet = {}
	if type(payload.partyUserIds) == "table" then
		for _, uid in ipairs(payload.partyUserIds) do
			partyUserIdSet[uid] = true
		end
	end

	myParty = payload.myParty
	refreshHud()
	refreshAllNameTags()
	if open then
		updateModalButtons()
		refreshServerList()
	end
end

PartyStateSync.OnClientEvent:Connect(applyState)

Players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(function()
		task.defer(function()
			ensureNameTag(plr)
		end)
	end)
	watchAlignmentFor(plr)
end)

for _, plr in ipairs(Players:GetPlayers()) do
	plr.CharacterAdded:Connect(function()
		task.defer(function()
			ensureNameTag(plr)
		end)
	end)
	if plr.Character then
		task.defer(function()
			ensureNameTag(plr)
		end)
	end
	watchAlignmentFor(plr)
end

------------------------------------------------------------------------
-- Keybinds
------------------------------------------------------------------------
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.KeyCode == Keys.PartyMenu then
		setOpen(not open)
		return
	end
	if gameProcessed then
		return
	end
	if input.KeyCode == Keys.CloseMenu then
		if inviteGui.Enabled then
			hideInvite()
		elseif open then
			setOpen(false)
		end
	end
end)

player.CharacterAdded:Connect(function()
	setOpen(false)
	hideInvite()
end)

print("[PartyClient] ready")
