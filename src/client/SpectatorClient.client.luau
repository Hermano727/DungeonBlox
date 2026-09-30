--[[
	SpectatorClient -- watching the boss fight after dying in it (server: DungeonInstanceService,
	DungeonSpectate remote). There are no revives in the boss room: a member who dies there stays
	in the run as a spectator until the fight ends or they leave.

	  - Every other UI is hidden (HudHider); the camera follows a living teammate.
	  - Right-drag orbits, the scroll wheel zooms, Keys.SpectatePrev/Next (or the arrows on the
	    bar) switch teammate. If nobody is left alive the camera holds where it is.
	  - The bar at the top shows who you're watching and a Leave Dungeon button
	    (DungeonLeaveRequest: the server respawns you at your hearthstone).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Keys = require(ReplicatedStorage:WaitForChild("KeybindConfig"))
local CursorUtils = require(ReplicatedStorage:WaitForChild("CursorUtils"))
local CameraOverrideState = require(ReplicatedStorage:WaitForChild("CameraOverrideState"))
local HudHider = require(script.Parent:WaitForChild("HudHider"))

local GameEvents = ReplicatedStorage:WaitForChild("GameEvents")
local SpectateEvent = GameEvents:WaitForChild("DungeonSpectate")
local LeaveRequest = GameEvents:WaitForChild("DungeonLeaveRequest")

local player = Players.LocalPlayer
local RENDER_NAME = "DungeonSpectateCamera"
local CURSOR_BIND = "DungeonSpectateCursor"
local SPECTATE_ATTR = "DungeonSpectating"
local DISTANCE, MIN_DISTANCE, MAX_DISTANCE = 18, 8, 45
local ORBIT_SENSITIVITY = .35
local FOLLOW_SMOOTHING = 8

local PANEL = Color3.fromRGB(14, 13, 16)
local EDGE = Color3.fromRGB(70, 66, 60)
local TEXT = Color3.fromRGB(236, 230, 214)
local MUTED = Color3.fromRGB(160, 152, 138)

-------------------------------------------------------------------------------------------------
-- UI

local gui = Instance.new("ScreenGui")
gui.Name = "SpectatorGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 260
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local bar = Instance.new("Frame")
bar.Name = "Bar"
bar.AnchorPoint = Vector2.new(.5, 0)
bar.Position = UDim2.new(.5, 0, 0, 16)
bar.Size = UDim2.fromOffset(460, 64)
bar.BackgroundColor3 = PANEL
bar.BackgroundTransparency = .15
bar.BorderSizePixel = 0
bar.Parent = gui
Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 8)
local stroke = Instance.new("UIStroke", bar)
stroke.Color = EDGE
stroke.Thickness = 1.5

local function label(text, size, color, font, pos, dims, align)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextSize = size
	l.TextColor3 = color
	l.Font = font
	l.Position = pos
	l.Size = dims
	l.TextXAlignment = align or Enum.TextXAlignment.Center
	l.Parent = bar
	return l
end

local function button(text, pos, dims, colour)
	local b = Instance.new("TextButton")
	b.Text = text
	b.Font = Enum.Font.GothamBold
	b.TextSize = 14
	b.TextColor3 = TEXT
	b.BackgroundColor3 = colour
	b.AutoButtonColor = true
	b.Position = pos
	b.Size = dims
	b.BorderSizePixel = 0
	b.Parent = bar
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
	return b
end

label("SPECTATING", 12, MUTED, Enum.Font.GothamBold, UDim2.fromOffset(52, 8), UDim2.fromOffset(200, 16))
local nameLabel = label("", 20, TEXT, Enum.Font.GothamBold, UDim2.fromOffset(52, 26), UDim2.fromOffset(200, 26))
local prevButton = button("<", UDim2.fromOffset(12, 17), UDim2.fromOffset(32, 32), Color3.fromRGB(40, 38, 44))
local nextButton = button(">", UDim2.fromOffset(260, 17), UDim2.fromOffset(32, 32), Color3.fromRGB(40, 38, 44))
local leaveButton = button("Leave Dungeon", UDim2.fromOffset(308, 14), UDim2.fromOffset(140, 36), Color3.fromRGB(120, 38, 38))

local hint = Instance.new("TextLabel")
hint.AnchorPoint = Vector2.new(.5, 0)
hint.Position = UDim2.new(.5, 0, 0, 86)
hint.Size = UDim2.fromOffset(460, 18)
hint.BackgroundTransparency = 1
hint.Font = Enum.Font.GothamMedium
hint.TextSize = 12
hint.TextColor3 = MUTED
hint.TextStrokeTransparency = .5
hint.Text = ("You fell in the boss room. Right-drag to look around, scroll to zoom, [%s] [%s] to switch.")
	:format(Keys.SpectatePrev.Name, Keys.SpectateNext.Name)
hint.Parent = gui

-------------------------------------------------------------------------------------------------
-- State

local active = false
local members = {}      -- userIds in the run
local targetUserId      -- who we're watching
local yaw, pitch = 0, -20
local distance = DISTANCE
local orbiting = false
local releaseHud
local focus             -- smoothed camera focus point

local function aliveTargets()
	local list = {}
	for _, userId in ipairs(members) do
		local p = Players:GetPlayerByUserId(userId)
		if p and p ~= player and p:GetAttribute(SPECTATE_ATTR) == nil then
			local char = p.Character
			local humanoid = char and char:FindFirstChildOfClass("Humanoid")
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if humanoid and root and humanoid.Health > 0 then table.insert(list, p) end
		end
	end
	return list
end

local function cycle(step)
	local list = aliveTargets()
	if #list == 0 then targetUserId = nil return end
	local at = 0
	for i, p in ipairs(list) do
		if p.UserId == targetUserId then at = i end
	end
	local nextIndex = ((at - 1 + step) % #list) + 1
	if at == 0 then nextIndex = 1 end
	targetUserId = list[nextIndex].UserId
end

local function currentTarget()
	local p = targetUserId and Players:GetPlayerByUserId(targetUserId)
	if p and p:GetAttribute(SPECTATE_ATTR) == nil then
		local char = p.Character
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if humanoid and root and humanoid.Health > 0 then return p, root end
	end
	cycle(1) -- they died or left: move on to someone still standing
	p = targetUserId and Players:GetPlayerByUserId(targetUserId)
	local root = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	return p, root
end

local function render(dt)
	local camera = Workspace.CurrentCamera
	if not camera then return end
	camera.CameraType = Enum.CameraType.Scriptable
	local target, root = currentTarget()
	nameLabel.Text = target and target.DisplayName or "No one left standing"
	prevButton.Visible = target ~= nil
	nextButton.Visible = target ~= nil
	if not root then return end -- hold the camera where it is
	local want = root.Position + Vector3.new(0, 2.5, 0)
	focus = focus and focus:Lerp(want, math.min(1, dt * FOLLOW_SMOOTHING)) or want
	local rotation = CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(math.rad(pitch), 0, 0)
	camera.CFrame = CFrame.lookAt(focus + rotation:VectorToWorldSpace(Vector3.new(0, 0, distance)), focus)
end

local function stop()
	if not active then return end
	active = false
	gui.Enabled = false
	pcall(function() RunService:UnbindFromRenderStep(RENDER_NAME) end)
	pcall(function() RunService:UnbindFromRenderStep(CURSOR_BIND) end)
	if releaseHud then releaseHud(); releaseHud = nil end
	CameraOverrideState.SetActive(false)
	CursorUtils.release()
	orbiting = false
	focus = nil
end

local function start(payload)
	members = type(payload.memberUserIds) == "table" and payload.memberUserIds or {}
	if active then return end
	active = true
	targetUserId = nil
	cycle(1)
	distance = DISTANCE
	-- Start behind the camera's current heading, so the switch doesn't spin the view.
	local camera = Workspace.CurrentCamera
	if camera then
		local look = camera.CFrame.LookVector
		yaw = math.deg(math.atan2(-look.X, -look.Z))
	end
	pitch = -20
	gui.Enabled = true
	releaseHud = HudHider.Acquire(gui)
	CameraOverrideState.SetActive(true)
	CursorUtils.acquire()
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 2, render)
	-- A spectator's cursor is always free (the bar's buttons, right-drag to orbit). Re-asserted
	-- every frame AFTER every other per-frame cursor writer (CursorUtils and the valve maze's
	-- pointer lock both run at Last, the dev panel at Last + 1): the shared CursorUtils hold
	-- alone could lose that tie and leave the mouse locked while spectating.
	pcall(function() RunService:UnbindFromRenderStep(CURSOR_BIND) end)
	RunService:BindToRenderStep(CURSOR_BIND, Enum.RenderPriority.Last.Value + 10, function()
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
		if not UserInputService.MouseIconEnabled then UserInputService.MouseIconEnabled = true end
	end)
end

SpectateEvent.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	if payload.active then start(payload) else stop() end
end)

prevButton.Activated:Connect(function() cycle(-1) end)
nextButton.Activated:Connect(function() cycle(1) end)
leaveButton.Activated:Connect(function()
	leaveButton.Text = "Leaving..."
	LeaveRequest:FireServer()
	task.delay(3, function() leaveButton.Text = "Leave Dungeon" end)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if not active then return end
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		orbiting = true
	elseif not processed and input.KeyCode == Keys.SpectatePrev then
		cycle(-1)
	elseif not processed and input.KeyCode == Keys.SpectateNext then
		cycle(1)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then orbiting = false end
end)
UserInputService.InputChanged:Connect(function(input)
	if not active then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement and orbiting then
		yaw -= input.Delta.X * ORBIT_SENSITIVITY
		pitch = math.clamp(pitch - input.Delta.Y * ORBIT_SENSITIVITY, -75, 20)
	elseif input.UserInputType == Enum.UserInputType.MouseWheel then
		distance = math.clamp(distance - input.Position.Z * 3, MIN_DISTANCE, MAX_DISTANCE)
	end
end)
