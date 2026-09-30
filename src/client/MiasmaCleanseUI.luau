--[[
	MiasmaCleanseUI -- the cleansing altar's player-facing presentation.

	1. Signifier. The altar's ProximityPrompt (MiasmaCleanseAltar, Style = Custom) is drawn
	   here instead of Roblox's default prompt: a warded emblem floating over the basin with a
	   ring of beads that fills while the key is held, the word CLEANSE, the key to press, and
	   motes of holy water rising from the basin while you are in range. Roblox still owns the
	   input (key, hold, gamepad), so this is purely the look. Touch taps the emblem.

	2. Channel. When the server starts a cleanse (Presentation "AltarChannel", sent only to
	   the channelling player) the camera pans down over the basin the same way the Enchanting
	   Station takes the camera (CameraOverrideState + InteractionLock), movement is held, and
	   a small rite bar fills over the channel. Pressing a movement key (or X / Esc) breaks the
	   rite on purpose. The server decides success ("AltarSuccess") or failure
	   ("AltarInterrupted"); this module only presents it and hands the camera back smoothly.

	   Future: set MiasmaEncounterConfig.Animations.CleanseHands to the published "hands into
	   the basin" clip and it plays on the local character for the channel.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CameraOverrideState = require(ReplicatedStorage:WaitForChild("CameraOverrideState"))
local Config = require(ReplicatedStorage:WaitForChild("MiasmaEncounterConfig"))
local InteractionLock = require(ReplicatedStorage:WaitForChild("InteractionLock"))
local Keys = require(ReplicatedStorage:WaitForChild("KeybindConfig"))
local RuneArt = require(ReplicatedStorage:WaitForChild("MiasmaRuneArt"))
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local PROMPT_NAME = "MiasmaCleansePrompt"
local LOCK_OWNER = "MiasmaCleanse"
local CANCEL_ACTION = "MiasmaCleanseCancel"
local BEAD_COUNT = 16
local MOTE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"

local STYLE = {
	Holy = Color3.fromRGB(150, 245, 230),
	HolyBright = Color3.fromRGB(225, 255, 250),
	HolyDeep = Color3.fromRGB(60, 170, 160),
	Core = Color3.fromRGB(10, 24, 24),
	Text = Color3.fromRGB(205, 250, 242),
	Muted = Color3.fromRGB(130, 180, 172),
	Broken = Color3.fromRGB(220, 110, 90),
	BeadIdle = Color3.fromRGB(40, 70, 68),
}

-- Camera framing over the basin (tune live; see CLAUDE.md, no playtesting from here).
local CAMERA_BACK = 2.8     -- toward the arena centre, i.e. where the player stands
local CAMERA_UP = 2.2
local CAMERA_PUSH_IN = .7   -- slow push toward the water during the rite
local CAMERA_IN = TweenInfo.new(.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local CAMERA_OUT = TweenInfo.new(.35, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)

local UI = {}

local function new(className, props, parent)
	local item = Instance.new(className)
	for key, value in pairs(props) do item[key] = value end
	if parent then item.Parent = parent end
	return item
end

local function round(parent, scale)
	return new("UICorner", { CornerRadius = UDim.new(scale or .5, 0) }, parent)
end

local function tween(instance, info, goal)
	local t = TweenService:Create(instance, info, goal)
	t:Play()
	return t
end

-- 1. Signifier ------------------------------------------------------------------------------

local function keyLabel(prompt, inputType)
	if inputType == Enum.ProximityPromptInputType.Gamepad then
		return (string.gsub(prompt.GamepadKeyCode.Name, "Button", ""))
	elseif inputType == Enum.ProximityPromptInputType.Touch then
		return "TAP"
	end
	return prompt.KeyboardKeyCode.Name
end

local function buildSignifier(prompt, inputType)
	local host = prompt.Parent
	local billboard = new("BillboardGui", {
		Name = "MiasmaCleanseSignifier",
		Adornee = host,
		Size = UDim2.fromOffset(180, 200),
		StudsOffset = Vector3.new(0, 1.8, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		ResetOnSpawn = false,
		Active = inputType == Enum.ProximityPromptInputType.Touch,
	}, playerGui)
	local root = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, billboard)
	local scale = new("UIScale", { Scale = .55 }, root)

	-- Only touch gets a tappable emblem: on keyboard/gamepad a clickable billboard would eat
	-- mouse clicks (sword swings) whenever the player looks at the altar.
	local isTouch = inputType == Enum.ProximityPromptInputType.Touch
	local emblem = new(isTouch and "TextButton" or "Frame", {
		Name = "Emblem",
		AnchorPoint = Vector2.new(.5, 0),
		Position = UDim2.fromScale(.5, 0),
		Size = UDim2.fromOffset(128, 128),
		BackgroundTransparency = 1,
	}, root)
	if isTouch then
		emblem.Text = ""
		emblem.AutoButtonColor = false
	end
	local halo = new("Frame", {
		AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5), Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = STYLE.Holy, BackgroundTransparency = .88,
	}, emblem)
	round(halo)
	local haloStroke = new("UIStroke", { Color = STYLE.Holy, Thickness = 2, Transparency = .35 }, halo)

	local beadRing = new("Frame", {
		AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5), Size = UDim2.fromScale(.86, .86),
		BackgroundTransparency = 1,
	}, emblem)
	local beads = {}
	for i = 1, BEAD_COUNT do
		local angle = (i - 1) / BEAD_COUNT * math.pi * 2 - math.pi / 2
		local bead = new("Frame", {
			AnchorPoint = Vector2.new(.5, .5),
			Position = UDim2.fromScale(.5 + math.cos(angle) * .5, .5 + math.sin(angle) * .5),
			Size = UDim2.fromOffset(7, 7),
			BackgroundColor3 = STYLE.BeadIdle,
		}, beadRing)
		round(bead)
		beads[i] = bead
	end

	local core = new("Frame", {
		AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5), Size = UDim2.fromScale(.62, .62),
		BackgroundColor3 = STYLE.Core, BackgroundTransparency = .2,
	}, emblem)
	round(core)
	local coreStroke = new("UIStroke", { Color = STYLE.HolyDeep, Thickness = 1.5 }, core)
	local runeHolder = new("Frame", {
		AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5), Size = UDim2.fromScale(.62, .62),
		BackgroundTransparency = 1,
	}, core)
	local rune = RuneArt.Render(runeHolder, "Ward", { Color = STYLE.HolyBright, GlowColor = STYLE.Holy, GlowTransparency = .6, Thickness = .11 })

	local title = new("TextLabel", {
		AnchorPoint = Vector2.new(.5, 0), Position = UDim2.new(.5, 0, 0, 134), Size = UDim2.fromOffset(180, 26),
		BackgroundTransparency = 1, FontFace = UIFonts.DisplayBold, Text = "CLEANSE", TextColor3 = STYLE.Text, TextSize = 24,
		TextStrokeColor3 = Color3.new(0, 0, 0), TextStrokeTransparency = .55,
	}, root)
	local hint = new("Frame", {
		AnchorPoint = Vector2.new(.5, 0), Position = UDim2.new(.5, 0, 0, 164), Size = UDim2.fromOffset(150, 26),
		BackgroundTransparency = 1,
	}, root)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6),
	}, hint)
	local keyChip = new("TextLabel", {
		Size = UDim2.fromOffset(26, 22), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = STYLE.Core, BackgroundTransparency = .15,
		FontFace = UIFonts.BodyBold, Text = keyLabel(prompt, inputType), TextColor3 = STYLE.HolyBright, TextSize = 15,
	}, hint)
	round(keyChip, .25)
	new("UIStroke", { Color = STYLE.HolyDeep, Thickness = 1.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, keyChip)
	new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, keyChip)
	new("TextLabel", {
		Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1,
		FontFace = UIFonts.BodyBold, Text = inputType == Enum.ProximityPromptInputType.Touch and "the ward" or "hold to purge poison",
		TextColor3 = STYLE.Muted, TextSize = 14,
	}, hint)

	-- Holy-water motes rising from the basin while in range.
	local attachment = new("Attachment", { Name = "MiasmaCleanseMotes", Position = Vector3.new(0, -.6, 0) }, host)
	new("ParticleEmitter", {
		Texture = MOTE_TEXTURE,
		Color = ColorSequence.new(STYLE.HolyBright, STYLE.Holy),
		LightEmission = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, .35), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .2), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(1.1, 1.8),
		Rate = 14,
		Speed = NumberRange.new(1.2, 2.4),
		SpreadAngle = Vector2.new(24, 24),
		EmissionDirection = Enum.NormalId.Top,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-60, 60),
	}, attachment)

	local state = { progress = 0, holding = false, holdStart = 0 }
	tween(scale, TweenInfo.new(.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })

	local connections = {}
	table.insert(connections, prompt.PromptButtonHoldBegan:Connect(function()
		state.holding = true
		state.holdStart = os.clock()
	end))
	table.insert(connections, prompt.PromptButtonHoldEnded:Connect(function()
		state.holding = false
	end))
	table.insert(connections, prompt.Triggered:Connect(function()
		state.holding = false
		state.progress = 1
		tween(halo, TweenInfo.new(.25), { BackgroundTransparency = .4 })
	end))
	if isTouch then
		table.insert(connections, emblem.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then prompt:InputHoldBegin() end
		end))
		table.insert(connections, emblem.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then prompt:InputHoldEnd() end
		end))
	end
	table.insert(connections, RunService.RenderStepped:Connect(function(dt)
		local t = os.clock()
		local hold = math.max(prompt.HoldDuration, .01)
		if state.holding then
			state.progress = math.clamp((t - state.holdStart) / hold, 0, 1)
		elseif state.progress < 1 then
			state.progress = math.max(0, state.progress - dt * 4)
		end
		local lit = math.floor(state.progress * BEAD_COUNT + .5)
		for i, bead in ipairs(beads) do
			local on = i <= lit
			bead.BackgroundColor3 = on and STYLE.HolyBright or STYLE.BeadIdle
			bead.Size = on and UDim2.fromOffset(9, 9) or UDim2.fromOffset(6, 6)
		end
		beadRing.Rotation = state.holding and 0 or (t * 12) % 360
		local pulse = (math.sin(t * 2.6) + 1) / 2
		haloStroke.Transparency = .2 + pulse * .45
		coreStroke.Color = STYLE.HolyDeep:Lerp(STYLE.HolyBright, math.max(state.progress, pulse * .35))
		RuneArt.SetColor(rune, STYLE.HolyBright, 0, STYLE.Holy, .75 - state.progress * .45)
		billboard.StudsOffset = Vector3.new(0, 1.8 + math.sin(t * 1.8) * .12, 0)
	end))

	return function()
		for _, connection in ipairs(connections) do connection:Disconnect() end
		attachment:Destroy()
		local fade = tween(scale, TweenInfo.new(.15), { Scale = .5 })
		fade.Completed:Once(function() billboard:Destroy() end)
		task.delay(.3, function() if billboard.Parent then billboard:Destroy() end end)
	end
end

local shown = {}
ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
	if prompt.Name ~= PROMPT_NAME or prompt.Style ~= Enum.ProximityPromptStyle.Custom then return end
	if shown[prompt] then shown[prompt]() end
	shown[prompt] = buildSignifier(prompt, inputType)
end)
ProximityPromptService.PromptHidden:Connect(function(prompt)
	local close = shown[prompt]
	if close then
		shown[prompt] = nil
		close()
	end
end)

-- 2. Channel ---------------------------------------------------------------------------------

local channel = nil

local function getControls()
	local scripts = player:FindFirstChild("PlayerScripts")
	local module = scripts and scripts:FindFirstChild("PlayerModule")
	if not module then return nil end
	local ok, playerModule = pcall(require, module)
	return ok and playerModule and playerModule:GetControls() or nil
end

local function buildOverlay(duration)
	local gui = new("ScreenGui", {
		Name = "MiasmaCleanseRite", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 55,
	}, playerGui)
	local vignette = new("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = STYLE.HolyDeep, BackgroundTransparency = 1, BorderSizePixel = 0,
	}, gui)
	new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(.22, .85), NumberSequenceKeypoint.new(.78, .85), NumberSequenceKeypoint.new(1, 0),
		}),
	}, vignette)
	tween(vignette, TweenInfo.new(.4), { BackgroundTransparency = .55 })

	local panel = new("Frame", {
		AnchorPoint = Vector2.new(.5, 1), Position = UDim2.new(.5, 0, 1, -110), Size = UDim2.fromOffset(300, 66),
		BackgroundColor3 = STYLE.Core, BackgroundTransparency = .25,
	}, gui)
	round(panel, .18)
	new("UIStroke", { Color = STYLE.HolyDeep, Thickness = 1.5 }, panel)
	local runeHolder = new("Frame", { Position = UDim2.fromOffset(10, 9), Size = UDim2.fromOffset(48, 48), BackgroundTransparency = 1 }, panel)
	RuneArt.Render(runeHolder, "Ward", { Color = STYLE.HolyBright, GlowColor = STYLE.Holy, GlowTransparency = .55, Thickness = .11 })
	local title = new("TextLabel", {
		Position = UDim2.fromOffset(68, 8), Size = UDim2.new(1, -78, 0, 24), BackgroundTransparency = 1,
		FontFace = UIFonts.DisplayBold, Text = "CLEANSING", TextColor3 = STYLE.Text, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left,
	}, panel)
	local sub = new("TextLabel", {
		Position = UDim2.fromOffset(68, 32), Size = UDim2.new(1, -78, 0, 14), BackgroundTransparency = 1,
		FontFace = UIFonts.Body, Text = "Move to break the rite", TextColor3 = STYLE.Muted, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
	}, panel)
	local track = new("Frame", {
		Position = UDim2.fromOffset(68, 50), Size = UDim2.new(1, -80, 0, 5), BackgroundColor3 = STYLE.BeadIdle, BorderSizePixel = 0,
	}, panel)
	round(track)
	local fill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = STYLE.HolyBright, BorderSizePixel = 0 }, track)
	round(fill)
	tween(fill, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) })
	return { gui = gui, vignette = vignette, panel = panel, title = title, sub = sub, fill = fill }
end

local function playCleanseAnimation()
	local id = Config.Animations.CleanseHands
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not id or not animator then return nil end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
	if ok and track then
		track.Priority = Enum.AnimationPriority.Action
		track:Play(.2)
		return track
	end
	return nil
end

-- Hands the camera back and releases everything. `delay` lets a result read first.
local function endChannel(delay)
	local current = channel
	if not current or current.ending then return end
	current.ending = true
	ContextActionService:UnbindAction(CANCEL_ACTION)
	if current.track then current.track:Stop(.25) end
	task.delay(delay or 0, function()
		local camera = Workspace.CurrentCamera
		local finish = function()
			if channel ~= current then return end
			channel = nil
			CameraOverrideState.SetActive(false)
			InteractionLock.Release(LOCK_OWNER)
			local controls = getControls()
			if controls then controls:Enable() end
			if current.overlay then current.overlay.gui:Destroy() end
		end
		if current.overlay then
			tween(current.overlay.vignette, TweenInfo.new(.3), { BackgroundTransparency = 1 })
			tween(current.overlay.panel, TweenInfo.new(.3), { BackgroundTransparency = 1 })
		end
		if camera and current.returnCFrame then
			local back = tween(camera, CAMERA_OUT, { CFrame = current.returnCFrame })
			back.Completed:Once(finish)
			task.delay(CAMERA_OUT.Time + .1, finish)
		else
			finish()
		end
	end)
end

--[[
	BeginChannel(payload, cancel): payload = { altar, duration, focus, towardCentre }
	cancel() fires CancelAltar to the server.
]]
function UI.BeginChannel(payload, cancel)
	if channel then endChannel(0) end
	if typeof(payload.focus) ~= "Vector3" then return end
	local duration = tonumber(payload.duration) or 2
	local toward = typeof(payload.towardCentre) == "Vector3" and payload.towardCentre or Vector3.new(0, 0, 1)
	local camera = Workspace.CurrentCamera
	local current = { altar = payload.altar, returnCFrame = camera and camera.CFrame }
	channel = current

	InteractionLock.Acquire(LOCK_OWNER, { keepVitals = true }) -- mid-fight: health stays on screen
	local controls = getControls()
	if controls then controls:Disable() end
	ContextActionService:BindActionAtPriority(CANCEL_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin and channel == current and not current.ending then
			cancel()
		end
		return Enum.ContextActionResult.Sink
	end, false, 3000, Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D, Enum.KeyCode.Space,
		Keys.ReleaseValve, Keys.CloseMenu, Keys.Dash)

	if camera then
		CameraOverrideState.SetActive(true)
		camera.CameraType = Enum.CameraType.Scriptable
		local eye = payload.focus + toward * CAMERA_BACK + Vector3.new(0, CAMERA_UP, 0)
		local look = payload.focus - toward * .2
		local framed = CFrame.lookAt(eye, look)
		local pushed = CFrame.lookAt(eye - (eye - look).Unit * CAMERA_PUSH_IN, look)
		local into = tween(camera, CAMERA_IN, { CFrame = framed })
		into.Completed:Once(function()
			if channel == current and not current.ending then
				tween(camera, TweenInfo.new(math.max(.1, duration - CAMERA_IN.Time), Enum.EasingStyle.Sine), { CFrame = pushed })
			end
		end)
	end
	current.overlay = buildOverlay(duration)
	current.track = playCleanseAnimation()
	-- Never strand the camera if the result is lost.
	task.delay(duration + 2.5, function()
		if channel == current then endChannel(0) end
	end)
end

local INTERRUPT_TEXT = {
	Damaged = "Struck. The rite breaks.",
	Moved = "Knocked away. The rite breaks.",
	TooFar = "Too far from the altar.",
	Cancelled = "You step away from the altar.",
}

function UI.Succeed(payload)
	if not channel or payload.userId ~= player.UserId then return end
	local overlay = channel.overlay
	if overlay then
		overlay.title.Text = "PURIFIED"
		local cleared = tonumber(payload.cleared) or 0
		overlay.sub.Text = cleared > 0 and (("%d poison %s washed away"):format(cleared, cleared == 1 and "stack" or "stacks")) or "No poison to wash away"
		overlay.fill.BackgroundColor3 = STYLE.HolyBright
		overlay.vignette.BackgroundColor3 = STYLE.HolyBright
		overlay.vignette.BackgroundTransparency = .25
		tween(overlay.vignette, TweenInfo.new(.6), { BackgroundTransparency = .7 })
	end
	endChannel(.7)
end

function UI.Interrupt(payload)
	if not channel then return end
	local overlay = channel.overlay
	if overlay then
		overlay.title.Text = "RITE BROKEN"
		overlay.title.TextColor3 = STYLE.Broken
		overlay.sub.Text = INTERRUPT_TEXT[payload.reason] or "The rite breaks."
		overlay.vignette.BackgroundColor3 = STYLE.Broken
	end
	endChannel(.45)
end

function UI.ForceClose()
	if channel then endChannel(0) end
end

return UI
