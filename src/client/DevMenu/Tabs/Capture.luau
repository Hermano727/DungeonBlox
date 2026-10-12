--[[
	Capture (was DevCaptureMode) -- the F8 dev menu's CAPTURE tab (DevMenu, group Media), dev-only.

	A clean, cinematic camera for recording marketing clips (TikTok / Shorts / Reels):
	  - Hides every ScreenGui and the Roblox core UI (HudHider), the crosshair and the cursor.
	  - Shows your own character fully (first person hides your accessories / face locally).
	  - Three cameras, cycled with G:
	      FREE    fly anywhere, smoothed: WASD move, Q / E down / up, mouse look,
	              Shift faster, Ctrl slower, scroll = speed. Your character stays put.
	      ORBIT   slow automatic circle round your character; mouse steers, scroll = distance.
	      FOLLOW  smooth third-person behind you while you PLAY (move, fight, mine, fish);
	              mouse swings the angle, scroll = distance.
	  - H toggles slow motion for effects (every ParticleEmitter at 0.3x).
	  - [ / ] narrow / widen the field of view.
	  - F8 exits (DevClient routes F8 here while capture is on). The key help shows for a few
	    seconds at the start, then nothing is on screen.
	Lives outside DevClient (Luau's 200-locals limit), like DevProfileTab / DevMapTab.

	Build(ctx) -> section Frame (starts hidden; DevClient toggles Visible with the tab).
	ctx: parent, y, w, h, lbl, mkB, acc, gold, status(msg, isErr), onStart() (closes the panel).
	Also: DevCaptureMode.IsActive(), DevCaptureMode.Start(mode), DevCaptureMode.Stop().
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local TweenService = game:GetService("TweenService")

local CameraOverrideState = require(ReplicatedStorage:WaitForChild("CameraOverrideState"))
local HudHider = require(script:FindFirstAncestorWhichIsA("PlayerScripts"):WaitForChild("HudHider"))

local player = Players.LocalPlayer

local DevCaptureMode = { key = "Capture", label = "Capture", group = "Media" }

local MODES = { "Free", "Orbit", "Follow" }
local KEY_MODE = Enum.KeyCode.G
local KEY_SLOWMO = Enum.KeyCode.H
local KEY_FOV_IN = Enum.KeyCode.LeftBracket
local KEY_FOV_OUT = Enum.KeyCode.RightBracket
local SINK_ACTION = "DevCaptureSink"

local LOOK_SENSITIVITY = 0.0035 -- radians per pixel of mouse movement
local LOOK_SMOOTH = 10          -- higher = snappier camera turns
local MOVE_SMOOTH = 4           -- higher = less glide on the free camera
local FOLLOW_SMOOTH = 5
local SLOWMO_SCALE = 0.3

local state = nil -- the live capture session, or nil

local function damp(rate, dt)
	return 1 - math.exp(-rate * dt)
end

local function root()
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

---------------------------------------------------------------------------
-- Show your own character (first person hides accessories and the face locally)
---------------------------------------------------------------------------

local function revealCharacter(s)
	local character = player.Character
	if not character then return end
	for _, d in ipairs(character:GetDescendants()) do
		if (d:IsA("BasePart") or d:IsA("Decal")) and d.LocalTransparencyModifier ~= 0 then
			if s.ltm[d] == nil then s.ltm[d] = d.LocalTransparencyModifier end
			d.LocalTransparencyModifier = 0
		end
	end
end

local function restoreCharacter(s)
	for inst, value in pairs(s.ltm) do
		if inst.Parent then inst.LocalTransparencyModifier = value end
	end
	table.clear(s.ltm)
end

---------------------------------------------------------------------------
-- Slow motion (particles)
---------------------------------------------------------------------------

local function slowEmitter(s, e)
	if e:IsA("ParticleEmitter") and s.particles[e] == nil then
		s.particles[e] = e.TimeScale
		e.TimeScale = e.TimeScale * SLOWMO_SCALE
	end
end

local function setSlowmo(s, on)
	if on == s.slowmo then return end
	s.slowmo = on
	if on then
		for _, d in ipairs(workspace:GetDescendants()) do slowEmitter(s, d) end
		s.slowConn = workspace.DescendantAdded:Connect(function(d) slowEmitter(s, d) end)
	else
		if s.slowConn then s.slowConn:Disconnect(); s.slowConn = nil end
		for e, value in pairs(s.particles) do
			if e.Parent then e.TimeScale = value end
		end
		table.clear(s.particles)
	end
end

---------------------------------------------------------------------------
-- The start hint (gone after a few seconds: the screen must be clean to record)
---------------------------------------------------------------------------

local function showHint(s, text, seconds)
	local label = s.hint
	label.Text = text
	label.TextTransparency = 0
	label.TextStrokeTransparency = 0.4
	if s.hintTween then s.hintTween:Cancel() end
	s.hintToken = (s.hintToken or 0) + 1
	local token = s.hintToken
	task.delay(seconds, function()
		if state ~= s or s.hintToken ~= token then return end
		s.hintTween = TweenService:Create(label, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 })
		s.hintTween:Play()
	end)
end

---------------------------------------------------------------------------
-- Cameras
---------------------------------------------------------------------------

local function enterMode(s, mode)
	s.mode = mode
	local cam = workspace.CurrentCamera
	local look = cam.CFrame.LookVector
	-- Every camera keeps a yaw / pitch, picked up from wherever the camera is now.
	s.yaw = math.atan2(-look.X, -look.Z)
	s.pitch = math.asin(math.clamp(look.Y, -1, 1))
	s.targetYaw, s.targetPitch = s.yaw, s.pitch
	s.velocity = Vector3.zero
	s.position = cam.CFrame.Position
	local r = root()
	if mode == "Orbit" or mode == "Follow" then
		local centre = r and r.Position or cam.CFrame.Position
		s.distance = math.clamp((cam.CFrame.Position - centre).Magnitude, 6, 30)
		if mode == "Follow" then s.distance = 11 end
	end
	-- Free and Orbit hold the character still; Follow lets you play.
	if mode == "Follow" then
		ContextActionService:UnbindAction(SINK_ACTION)
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and s.autoRotate == nil then
			s.autoRotate = humanoid.AutoRotate
			humanoid.AutoRotate = true -- face the way you walk under a third-person camera
		end
	else
		ContextActionService:BindActionAtPriority(SINK_ACTION, function()
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 200,
			Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Q, Enum.KeyCode.E,
			Enum.KeyCode.Space, Enum.KeyCode.LeftShift, Enum.KeyCode.LeftControl, Enum.KeyCode.C)
	end
	showHint(s, ("Camera: %s"):format(mode:upper()), 1.2)
end

local function step(s, dt)
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false
	revealCharacter(s)

	-- Mouse look, smoothed.
	local delta = UserInputService:GetMouseDelta()
	s.targetYaw -= delta.X * LOOK_SENSITIVITY
	s.targetPitch = math.clamp(s.targetPitch - delta.Y * LOOK_SENSITIVITY, -1.45, 1.45)
	if s.mode == "Orbit" then
		s.targetYaw += dt * 0.22 -- the slow automatic circle
	end
	local k = damp(LOOK_SMOOTH, dt)
	s.yaw += (s.targetYaw - s.yaw) * k
	s.pitch += (s.targetPitch - s.pitch) * k
	local rotation = CFrame.Angles(0, s.yaw, 0) * CFrame.Angles(s.pitch, 0, 0)

	-- Field of view, eased.
	local fovDir = (UserInputService:IsKeyDown(KEY_FOV_IN) and -1 or 0) + (UserInputService:IsKeyDown(KEY_FOV_OUT) and 1 or 0)
	s.fov = math.clamp(s.fov + fovDir * 30 * dt, 15, 100)
	cam.FieldOfView = s.fov

	local r = root()
	if s.mode == "Free" then
		local input = Vector3.new(
			(UserInputService:IsKeyDown(Enum.KeyCode.D) and 1 or 0) - (UserInputService:IsKeyDown(Enum.KeyCode.A) and 1 or 0),
			(UserInputService:IsKeyDown(Enum.KeyCode.E) and 1 or 0) - (UserInputService:IsKeyDown(Enum.KeyCode.Q) and 1 or 0),
			(UserInputService:IsKeyDown(Enum.KeyCode.S) and 1 or 0) - (UserInputService:IsKeyDown(Enum.KeyCode.W) and 1 or 0))
		local speed = s.speed
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then speed *= 3 end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then speed *= 0.3 end
		local wanted = (rotation:VectorToWorldSpace(Vector3.new(input.X, 0, input.Z)) + Vector3.new(0, input.Y, 0))
		if wanted.Magnitude > 1 then wanted = wanted.Unit end
		s.velocity = s.velocity:Lerp(wanted * speed, damp(MOVE_SMOOTH, dt))
		s.position += s.velocity * dt
		cam.CFrame = CFrame.new(s.position) * rotation
	elseif r then
		local focus = r.Position + Vector3.new(0, 1.8, 0)
		local wantPos = focus + rotation:VectorToWorldSpace(Vector3.new(s.mode == "Follow" and 2.2 or 0, 0.6, s.distance))
		s.position = s.position:Lerp(wantPos, damp(s.mode == "Follow" and FOLLOW_SMOOTH or 8, dt))
		cam.CFrame = CFrame.lookAt(s.position, focus + rotation:VectorToWorldSpace(Vector3.new(s.mode == "Follow" and 1.2 or 0, 0, 0)))
	end
end

---------------------------------------------------------------------------
-- Start / stop
---------------------------------------------------------------------------

function DevCaptureMode.IsActive()
	return state ~= nil
end

function DevCaptureMode.Start(mode)
	if state then return end
	local cam = workspace.CurrentCamera
	local gui = Instance.new("ScreenGui")
	gui.Name = "DevCaptureHint"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1000
	local hint = Instance.new("TextLabel")
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -40)
	hint.Size = UDim2.fromOffset(900, 28)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.GothamBold
	hint.TextSize = 18
	hint.TextColor3 = Color3.fromRGB(240, 230, 210)
	hint.TextStrokeTransparency = 0.4
	hint.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")

	local s = {
		gui = gui, hint = hint, ltm = {}, particles = {}, slowmo = false,
		fov = cam.FieldOfView, oldFov = cam.FieldOfView, speed = 16, distance = 12,
		oldMouse = UserInputService.MouseBehavior, connections = {},
	}
	state = s
	s.releaseHud = HudHider.Acquire(gui) -- everything else, core UI included
	CameraOverrideState.SetActive(true)
	enterMode(s, mode or "Free")
	showHint(s, "CAPTURE   G camera   H slow motion   [ ] zoom   scroll speed   F8 exit", 3.5)

	table.insert(s.connections, RunService.RenderStepped:Connect(function(dt)
		if state == s then step(s, dt) end
	end))
	table.insert(s.connections, UserInputService.InputBegan:Connect(function(input)
		if state ~= s or UserInputService:GetFocusedTextBox() then return end
		if input.KeyCode == KEY_MODE then
			local i = table.find(MODES, s.mode) or 1
			enterMode(s, MODES[i % #MODES + 1])
		elseif input.KeyCode == KEY_SLOWMO then
			setSlowmo(s, not s.slowmo)
			showHint(s, s.slowmo and "Slow motion ON" or "Slow motion OFF", 1.2)
		end
	end))
	table.insert(s.connections, UserInputService.InputChanged:Connect(function(input)
		if state ~= s or input.UserInputType ~= Enum.UserInputType.MouseWheel then return end
		local up = input.Position.Z > 0
		if s.mode == "Free" then
			s.speed = math.clamp(s.speed * (up and 1.2 or 1 / 1.2), 2, 200)
		else
			s.distance = math.clamp(s.distance * (up and 1 / 1.12 or 1.12), 3, 60)
		end
	end))
	table.insert(s.connections, player.CharacterAdded:Connect(function()
		table.clear(s.ltm)
		s.autoRotate = nil
		if s.mode == "Follow" then enterMode(s, "Follow") end
	end))
end

function DevCaptureMode.Stop()
	local s = state
	if not s then return end
	state = nil
	for _, c in ipairs(s.connections) do c:Disconnect() end
	ContextActionService:UnbindAction(SINK_ACTION)
	setSlowmo(s, false)
	restoreCharacter(s)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and s.autoRotate ~= nil then humanoid.AutoRotate = s.autoRotate end
	local cam = workspace.CurrentCamera
	cam.FieldOfView = s.oldFov
	-- Hand the camera back facing the way it looks now.
	CameraOverrideState.RequestLook(cam.CFrame.LookVector)
	CameraOverrideState.SetActive(false)
	UserInputService.MouseBehavior = s.oldMouse
	if s.releaseHud then s.releaseHud() end
	s.gui:Destroy()
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------

function DevCaptureMode.Build(ctx)
	local lbl, mkB = ctx.lbl, ctx.mkB
	local W = ctx.w
	local muted = Color3.fromRGB(150, 135, 120)

	local sec = Instance.new("Frame")
	sec.Name = "CaptureSection"
	sec.Position = UDim2.fromOffset(0, ctx.y)
	sec.Size = UDim2.fromOffset(W, ctx.h)
	sec.BackgroundTransparency = 1
	sec.Visible = false
	sec.Parent = ctx.parent

	lbl(sec, "CAPTURE MODE", 12, 2, 200, 16, 11, ctx.acc, true)
	lbl(sec, "A clean screen and a smooth camera for recording clips. F8 exits.", 12, 18, W - 24, 14, 10, muted)

	lbl(sec, "Start with", 12, 40, 120, 16, 11, ctx.gold, true)
	local chosen = "Follow"
	local chips = {}
	local onColor, offColor = Color3.fromRGB(70, 110, 160), Color3.fromRGB(40, 45, 55)
	local function paint()
		for name, chip in pairs(chips) do
			chip.BackgroundColor3 = (name == chosen) and onColor or offColor
		end
	end
	for i, name in ipairs(MODES) do
		local chip = mkB(sec, name:upper(), 12 + (i - 1) * 96, 58, 90, 26, offColor)
		chips[name] = chip
		chip.Activated:Connect(function()
			chosen = name
			paint()
		end)
	end
	paint()

	local lines = {
		"FREE: fly anywhere. WASD, Q / E down / up, Shift fast, Ctrl slow.",
		"ORBIT: a slow circle round you. FOLLOW: third person while you play.",
		"G next camera   H slow motion   [ ] zoom   scroll speed / distance",
	}
	for i, text in ipairs(lines) do
		lbl(sec, text, 12, 92 + (i - 1) * 15, W - 24, 14, 10, muted)
	end

	local start = mkB(sec, "Start Capture", 12, 142, 180, 32, Color3.fromRGB(40, 90, 50))
	start.Activated:Connect(function()
		if ctx.onStart then ctx.onStart() end
		task.defer(DevCaptureMode.Start, chosen)
	end)

	return sec
end

-- DevMenu asks every tab on F8: while capturing, F8 ends capture (and leaves the menu closed).
function DevCaptureMode.InterceptToggle()
	if DevCaptureMode.IsActive() then
		DevCaptureMode.Stop()
		return true
	end
	return false
end

return DevCaptureMode
