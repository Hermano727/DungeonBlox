--[[
	SettingsClient
	Gear icon (top-right) opens a tabbed Settings panel: Audio / Video / Controls.

	Audio -- Master, Music, Movement, Effects. All four are live SoundGroup/Sound
	volumes (see VolumeSettings.luau for exactly what each one drives and why
	"Movement"/"Effects" replaced the old "SFX"/"VFX" names -- neither was ever
	a visual-effects control, both are sound buses).

	Video -- FOV, Sensitivity, Brightness. Backed by VideoSettings.luau.
	FOV/Sensitivity feed FirstPersonViewModel + the Crouching/Animate2/
	DialogModule scripts that also touch Camera.FieldOfView (see VideoSettings
	header comment). Brightness is a client-local ColorCorrectionEffect, not
	Lighting.Brightness -- DayNightService owns Lighting.ClockTime
	authoritatively every Heartbeat and this sidesteps that fight entirely.

	Controls -- read-only reference generated from KeybindConfig (the game's
	single source of truth for keybinds) plus a few movement binds that live
	outside it (WASD/Space/Shift/Crouch are Roblox defaults / hardcoded in
	Animate2 & Crouching, not routed through KeybindConfig). Deliberately NOT
	interactive: several KeybindConfig consumers cache their keycodes into a
	local table once at script load instead of reading Keys.* live at
	input-handling time, so a rebind here would silently fail to take effect
	in some of them. Wiring live rebinding is future work, not this pass.

	Persistence -- every slider fires "UpdatePlayerSettings" once when you
	release it (not per drag frame; see makeSlider's onCommit), which
	SettingsDataService.server.lua validates/clamps against SettingsRanges
	and saves to its own DataStore. VolumeSettings.luau/VideoSettings.luau
	pull your saved values back on next join via SettingsStore.luau. Min/max
	ranges for every slider below come from SettingsRanges.luau so the
	client display and the server-side clamp can never drift apart.
]]

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local SoundService     = game:GetService("SoundService")
local Lighting         = game:GetService("Lighting")

local VolumeSettings = require(ReplicatedStorage:WaitForChild("VolumeSettings"))
local VideoSettings  = require(ReplicatedStorage:WaitForChild("VideoSettings"))
local CursorManager  = require(ReplicatedStorage:WaitForChild("CursorManager"))
local SfxService     = require(ReplicatedStorage:WaitForChild("SfxService"))
local Keys           = require(ReplicatedStorage:WaitForChild("KeybindConfig"))
local SettingsRanges = require(ReplicatedStorage:WaitForChild("SettingsRanges"))

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Fired once per slider release (see makeSlider's onCommit) to persist the
-- new value; SettingsDataService.server.lua owns validating + saving it.
local evUpdateSettings = ReplicatedStorage:WaitForChild("UpdatePlayerSettings")

local function persist(category, key)
	return function(value)
		evUpdateSettings:FireServer(category, key, value)
	end
end

----------------------------------------------------------------------
-- Root ScreenGui
----------------------------------------------------------------------

local sg = Instance.new("ScreenGui")
sg.Name           = "SettingsGui"
sg.ResetOnSpawn   = false
sg.IgnoreGuiInset = true
sg.DisplayOrder   = 250
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.Parent         = playerGui

----------------------------------------------------------------------
-- Gear button
----------------------------------------------------------------------

local gearBtn = Instance.new("TextButton")
gearBtn.Name                 = "GearButton"
gearBtn.AnchorPoint          = Vector2.new(1, 0)
gearBtn.Position             = UDim2.new(1, -14, 0, 14)
gearBtn.Size                 = UDim2.fromOffset(30, 30)
gearBtn.BackgroundTransparency = 1
gearBtn.Text                 = "⚙"
gearBtn.TextColor3           = Color3.fromRGB(210, 195, 175)
gearBtn.TextTransparency     = 0
gearBtn.TextSize             = 22
gearBtn.Font                 = Enum.Font.GothamBold
gearBtn.ZIndex               = 10
gearBtn.Parent               = sg
local gearStroke = Instance.new("UIStroke", gearBtn)
gearStroke.Thickness    = 1.5
gearStroke.Color        = Color3.fromRGB(110, 98, 82)
gearStroke.Transparency = 0.35

----------------------------------------------------------------------
-- Settings panel
----------------------------------------------------------------------

local PANEL_W = 300
local TABBAR_H = 26
local CONTENT_TOP = 48
local CONTENT_H = 168
local FOOTER_H = 16
local PANEL_H = CONTENT_TOP + CONTENT_H + FOOTER_H + 14

local panel = Instance.new("Frame")
panel.Name                   = "SettingsPanel"
panel.AnchorPoint            = Vector2.new(1, 0)
panel.Position               = UDim2.new(1, -14, 0, 52)
panel.Size                   = UDim2.fromOffset(PANEL_W, PANEL_H)
panel.BackgroundColor3       = Color3.fromRGB(16, 14, 12)
panel.BackgroundTransparency = 0.1
panel.BorderSizePixel        = 0
panel.Visible                = false
panel.ZIndex                 = 9
panel.Parent                 = sg
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)
local panelStroke = Instance.new("UIStroke", panel)
panelStroke.Thickness    = 1
panelStroke.Color        = Color3.fromRGB(70, 60, 50)
panelStroke.Transparency = 0.3

----------------------------------------------------------------------
-- Tab bar
----------------------------------------------------------------------

local TAB_NAMES = { "Audio", "Video", "Controls" }
local tabButtons = {}
local tabContents = {}
local activeTab = "Audio"

local tabBar = Instance.new("Frame")
tabBar.BackgroundTransparency = 1
tabBar.Position = UDim2.fromOffset(14, 12)
tabBar.Size     = UDim2.new(1, -28, 0, TABBAR_H)
tabBar.Parent   = panel

local TAB_W = (PANEL_W - 28) / #TAB_NAMES

local function setActiveTab(name)
	activeTab = name
	for tabName, btn in pairs(tabButtons) do
		local isActive = tabName == name
		btn.TextColor3 = isActive and Color3.fromRGB(215, 175, 105) or Color3.fromRGB(140, 128, 108)
		btn.UIStroke.Transparency = isActive and 0.1 or 1
	end
	for tabName, content in pairs(tabContents) do
		content.Visible = tabName == name
	end
end

for i, name in ipairs(TAB_NAMES) do
	local btn = Instance.new("TextButton")
	btn.Name                 = name .. "Tab"
	btn.BackgroundTransparency = 1
	btn.Position             = UDim2.fromOffset((i - 1) * TAB_W, 0)
	btn.Size                 = UDim2.fromOffset(TAB_W, TABBAR_H)
	btn.Font                 = Enum.Font.GothamBold
	btn.TextSize             = 13
	btn.Text                 = name
	btn.TextColor3           = Color3.fromRGB(140, 128, 108)
	btn.Parent               = tabBar

	local underline = Instance.new("UIStroke")
	underline.Name              = "UIStroke"
	underline.Thickness         = 1.5
	underline.Color             = Color3.fromRGB(215, 175, 105)
	underline.Transparency      = 1
	underline.ApplyStrokeMode   = Enum.ApplyStrokeMode.Border
	underline.Parent            = btn

	btn.Activated:Connect(function()
		setActiveTab(name)
	end)

	tabButtons[name] = btn
end

local divider = Instance.new("Frame")
divider.Position         = UDim2.fromOffset(14, 12 + TABBAR_H + 6)
divider.Size             = UDim2.new(1, -28, 0, 1)
divider.BackgroundColor3 = Color3.fromRGB(70, 60, 50)
divider.BackgroundTransparency = 0.4
divider.BorderSizePixel  = 0
divider.Parent           = panel

----------------------------------------------------------------------
-- Tab content containers
----------------------------------------------------------------------

local function makeTabContent(name)
	local content = Instance.new("Frame")
	content.Name                 = name .. "Content"
	content.BackgroundTransparency = 1
	content.Position             = UDim2.fromOffset(14, CONTENT_TOP)
	content.Size                 = UDim2.new(1, -28, 0, CONTENT_H)
	content.Visible              = false
	content.Parent               = panel
	tabContents[name] = content
	return content
end

local audioTab    = makeTabContent("Audio")
local videoTab    = makeTabContent("Video")
local controlsTab = makeTabContent("Controls")

----------------------------------------------------------------------
-- Slider factory (generalized: arbitrary min/max range + display format)
----------------------------------------------------------------------

local LABEL_W  = 68
local TRACK_GAP = 8
local VAL_W    = 42
local TRACK_H  = 4
local KNOB_D   = 13
local ROW_H    = 32
local trackW   = (PANEL_W - 28) - LABEL_W - TRACK_GAP - VAL_W - 8

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function invLerp(a, b, v)
	if b == a then return 0 end
	return math.clamp((v - a) / (b - a), 0, 1)
end

local function percentFormat(v)
	return tostring(math.round(v * 100)) .. "%"
end

-- opts: { min, max, format(value)->string, onChange(value), onCommit(value) }
-- onChange fires on every drag frame (instant local feedback -- volume/FOV/
-- etc apply live). onCommit fires once, when the mouse/touch releases, with
-- the final value -- that's the one that should hit the network, so a drag
-- across the whole track doesn't fire dozens of UpdatePlayerSettings events.
local function makeSlider(parent, label, yOff, initValue, opts)
	opts = opts or {}
	local min = opts.min or 0
	local max = opts.max or 1
	local format = opts.format or percentFormat
	local onChange = opts.onChange or function() end
	local onCommit = opts.onCommit or function() end
	local initT = invLerp(min, max, initValue)
	local lastValue = initValue

	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(0, yOff)
	row.Size     = UDim2.new(1, 0, 0, ROW_H)
	row.Parent   = parent

	local rowLbl = Instance.new("TextLabel")
	rowLbl.BackgroundTransparency = 1
	rowLbl.Position    = UDim2.fromOffset(0, (ROW_H - 16) / 2)
	rowLbl.Size        = UDim2.fromOffset(LABEL_W, 16)
	rowLbl.Font        = Enum.Font.GothamMedium
	rowLbl.TextSize    = 12
	rowLbl.TextColor3  = Color3.fromRGB(175, 160, 140)
	rowLbl.TextXAlignment = Enum.TextXAlignment.Left
	rowLbl.Text        = label
	rowLbl.Parent      = row

	local trackBg = Instance.new("Frame")
	trackBg.AnchorPoint      = Vector2.new(0, 0.5)
	trackBg.Position         = UDim2.new(0, LABEL_W + TRACK_GAP, 0.5, 0)
	trackBg.Size             = UDim2.fromOffset(trackW, TRACK_H)
	trackBg.BackgroundColor3 = Color3.fromRGB(55, 48, 42)
	trackBg.BorderSizePixel  = 0
	trackBg.Parent           = row
	Instance.new("UICorner", trackBg).CornerRadius = UDim.new(0, 2)

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = Color3.fromRGB(175, 140, 80)
	fill.BorderSizePixel  = 0
	fill.Size             = UDim2.new(initT, 0, 1, 0)
	fill.Parent           = trackBg
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 2)

	local knob = Instance.new("Frame")
	knob.AnchorPoint      = Vector2.new(0.5, 0.5)
	knob.Position         = UDim2.new(initT, 0, 0.5, 0)
	knob.Size             = UDim2.fromOffset(KNOB_D, KNOB_D)
	knob.BackgroundColor3 = Color3.fromRGB(215, 175, 105)
	knob.BorderSizePixel  = 0
	knob.ZIndex           = 2
	knob.Parent           = trackBg
	Instance.new("UICorner", knob).CornerRadius = UDim.new(0.5, 0)

	local valLbl = Instance.new("TextLabel")
	valLbl.BackgroundTransparency = 1
	valLbl.AnchorPoint    = Vector2.new(0, 0.5)
	valLbl.Position       = UDim2.new(0, LABEL_W + TRACK_GAP + trackW + 6, 0.5, 0)
	valLbl.Size           = UDim2.fromOffset(VAL_W, 16)
	valLbl.Font           = Enum.Font.GothamMedium
	valLbl.TextSize       = 11
	valLbl.TextColor3     = Color3.fromRGB(140, 128, 108)
	valLbl.TextXAlignment = Enum.TextXAlignment.Right
	valLbl.Text           = format(initValue)
	valLbl.Parent         = row

	local dragging = false

	local function applyT(absX)
		local tPos  = trackBg.AbsolutePosition.X
		local tSize = trackBg.AbsoluteSize.X
		if tSize == 0 then return end
		local t = math.clamp((absX - tPos) / tSize, 0, 1)
		local value = lerp(min, max, t)
		lastValue = value
		fill.Size     = UDim2.new(t, 0, 1, 0)
		knob.Position = UDim2.new(t, 0, 0.5, 0)
		valLbl.Text   = format(value)
		onChange(value)
	end

	trackBg.InputBegan:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1
			or inp.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			applyT(inp.Position.X)
		end
	end)
	knob.InputBegan:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1
			or inp.UserInputType == Enum.UserInputType.Touch then
			dragging = true
		end
	end)
	UserInputService.InputChanged:Connect(function(inp)
		if not dragging then return end
		if inp.UserInputType == Enum.UserInputType.MouseMovement
			or inp.UserInputType == Enum.UserInputType.Touch then
			applyT(inp.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1
			or inp.UserInputType == Enum.UserInputType.Touch then
			if dragging then
				dragging = false
				onCommit(lastValue)
			end
		end
	end)

	return row
end

----------------------------------------------------------------------
-- Audio tab: Master, Music, Movement, Effects
----------------------------------------------------------------------

local mainGroup        = SoundService:WaitForChild("Main")
local movementSfxGroup = mainGroup:WaitForChild("Character")

local function liveMusicSound()
	return SoundService:FindFirstChild("ZoneMusic")
end

makeSlider(audioTab, "Master", 0 * ROW_H, VolumeSettings.master, {
	min = SettingsRanges.volume.master.min,
	max = SettingsRanges.volume.master.max,
	onChange = function(v)
		VolumeSettings.master = v
		mainGroup.Volume = v -- scales Movement + Effects together via SoundGroup nesting
		local musicSound = liveMusicSound()
		if musicSound and musicSound.IsPlaying then
			musicSound.Volume = v * VolumeSettings.music
		end
	end,
	onCommit = persist("volume", "master"),
})

makeSlider(audioTab, "Music", 1 * ROW_H, VolumeSettings.music, {
	min = SettingsRanges.volume.music.min,
	max = SettingsRanges.volume.music.max,
	onChange = function(v)
		VolumeSettings.music = v
		local musicSound = liveMusicSound()
		if musicSound and musicSound.IsPlaying then
			musicSound.Volume = VolumeSettings.master * v
		end
	end,
	onCommit = persist("volume", "music"),
})

makeSlider(audioTab, "Movement", 2 * ROW_H, VolumeSettings.movement, {
	min = SettingsRanges.volume.movement.min,
	max = SettingsRanges.volume.movement.max,
	onChange = function(v)
		VolumeSettings.movement = v
		movementSfxGroup.Volume = v
	end,
	onCommit = persist("volume", "movement"),
})

makeSlider(audioTab, "Effects", 3 * ROW_H, VolumeSettings.effects, {
	min = SettingsRanges.volume.effects.min,
	max = SettingsRanges.volume.effects.max,
	onChange = function(v)
		VolumeSettings.effects = v
		local effectsGroup = SfxService.GetEffectsGroup()
		if effectsGroup then
			effectsGroup.Volume = v
		end
	end,
	onCommit = persist("volume", "effects"),
})

----------------------------------------------------------------------
-- Video tab: FOV, Sensitivity, Brightness
----------------------------------------------------------------------

-- Client-local post-process brightness. Deliberately not Lighting.Brightness
-- -- see file header. LocalScript-created instances under a service like
-- Lighting are never replicated, so this never touches the server or other
-- clients.
local function getColorCorrection()
	local cc = Lighting:FindFirstChild("PlayerColorCorrection")
	if not cc then
		cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "PlayerColorCorrection"
		cc.Brightness = VideoSettings.brightness
		cc.Parent = Lighting
	end
	return cc
end
getColorCorrection() -- apply saved/default value immediately, no-op at brightness=0

makeSlider(videoTab, "FOV", 0 * ROW_H, VideoSettings.fov, {
	min = SettingsRanges.video.fov.min,
	max = SettingsRanges.video.fov.max,
	format = function(v) return tostring(math.round(v)) .. "°" end,
	onChange = function(v)
		VideoSettings.fov = v
		-- Best-effort immediate feedback; Crouching/Animate2/DialogModule own
		-- re-applying this whenever they next tween FOV (crouch, sprint,
		-- dialogue open/close), so a brief mismatch while one of those is
		-- mid-tween self-corrects on its own within a fraction of a second.
		workspace.CurrentCamera.FieldOfView = v
	end,
	onCommit = persist("video", "fov"),
})

makeSlider(videoTab, "Sensitivity", 1 * ROW_H, VideoSettings.sensitivity, {
	min = SettingsRanges.video.sensitivity.min,
	max = SettingsRanges.video.sensitivity.max,
	format = function(v) return tostring(math.round(v / 0.003 * 100)) .. "%" end,
	onChange = function(v)
		VideoSettings.sensitivity = v
	end,
	onCommit = persist("video", "sensitivity"),
})

makeSlider(videoTab, "Brightness", 2 * ROW_H, VideoSettings.brightness, {
	min = SettingsRanges.video.brightness.min,
	max = SettingsRanges.video.brightness.max,
	format = function(v)
		local pct = math.round(v / SettingsRanges.video.brightness.max * 100)
		return (pct >= 0 and "+" or "") .. tostring(pct) .. "%"
	end,
	onChange = function(v)
		VideoSettings.brightness = v
		getColorCorrection().Brightness = v
	end,
	onCommit = persist("video", "brightness"),
})

----------------------------------------------------------------------
-- Controls tab: read-only reference generated from KeybindConfig
----------------------------------------------------------------------

local KEY_DISPLAY_OVERRIDES = {
	[Enum.KeyCode.LeftControl]  = "Ctrl",
	[Enum.KeyCode.RightControl] = "Ctrl",
	[Enum.KeyCode.LeftShift]    = "Shift",
	[Enum.KeyCode.RightShift]   = "Shift",
	[Enum.KeyCode.Escape]       = "Esc",
	[Enum.KeyCode.Return]       = "Enter",
	[Enum.KeyCode.One]   = "1",
	[Enum.KeyCode.Two]   = "2",
	[Enum.KeyCode.Three] = "3",
	[Enum.KeyCode.Four]  = "4",
}

local function keyName(k)
	return KEY_DISPLAY_OVERRIDES[k] or k.Name
end

-- Accepts a single KeyCode or a list of them (e.g. Keys.FreeLook); dedupes
-- display names so {LeftControl, RightControl} shows once as "Ctrl".
local function keysDisplay(binding)
	if typeof(binding) ~= "table" then
		return keyName(binding)
	end
	local seen, out = {}, {}
	for _, k in ipairs(binding) do
		local n = keyName(k)
		if not seen[n] then
			seen[n] = true
			table.insert(out, n)
		end
	end
	return table.concat(out, " / ")
end

local toolSlotParts = {}
for _, kc in ipairs({ Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four }) do
	local slot = Keys.ToolSlot[kc]
	if slot then
		table.insert(toolSlotParts, keyName(kc) .. " " .. slot)
	end
end

-- Move/Jump/Sprint/Crouch aren't in KeybindConfig (WASD + Space are Roblox
-- engine defaults; Shift is hardcoded in Animate2, C in Crouching) -- listed
-- here anyway since a control reference that skips half the controls isn't
-- useful, just flagged in this comment as not-yet-centralized.
local CONTROLS_ROWS = {
	{ "Move", "WASD" },
	{ "Jump", "Space" },
	{ "Sprint", "Shift" },
	{ "Crouch", "C" },
	{ "Dash", keysDisplay(Keys.Dash) },
	{ "Swap View", keysDisplay(Keys.TogglePerspective) },
	{ "Free Look", keysDisplay(Keys.FreeLook) },
	{ "Equip Tool", table.concat(toolSlotParts, "   ") },
	{ "Skills Menu", keysDisplay(Keys.SkillsTab) },
	{ "Party Menu", keysDisplay(Keys.PartyMenu) },
	{ "Close Menu", keysDisplay(Keys.CloseMenu) },
	{ "Dialogue Choice", "1-" .. tostring(#Keys.DialogChoice) },
}

local controlsScroll = Instance.new("ScrollingFrame")
controlsScroll.BackgroundTransparency = 1
controlsScroll.BorderSizePixel = 0
controlsScroll.Size = UDim2.new(1, 0, 1, 0)
controlsScroll.CanvasSize = UDim2.new(0, 0, 0, #CONTROLS_ROWS * 22)
controlsScroll.ScrollBarThickness = 3
controlsScroll.ScrollBarImageColor3 = Color3.fromRGB(140, 128, 108)
controlsScroll.Parent = controlsTab

for i, entry in ipairs(CONTROLS_ROWS) do
	local rowLabel, rowValue = entry[1], entry[2]

	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(0, (i - 1) * 22)
	row.Size     = UDim2.new(1, 0, 0, 22)
	row.Parent   = controlsScroll

	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Position    = UDim2.fromOffset(0, 3)
	lbl.Size        = UDim2.new(0.55, 0, 0, 16)
	lbl.Font        = Enum.Font.GothamMedium
	lbl.TextSize    = 12
	lbl.TextColor3  = Color3.fromRGB(175, 160, 140)
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Text        = rowLabel
	lbl.Parent      = row

	local val = Instance.new("TextLabel")
	val.BackgroundTransparency = 1
	val.AnchorPoint = Vector2.new(1, 0)
	val.Position    = UDim2.new(1, 0, 0, 3)
	val.Size        = UDim2.new(0.45, 0, 0, 16)
	val.Font        = Enum.Font.GothamBold
	val.TextSize    = 12
	val.TextColor3  = Color3.fromRGB(215, 175, 105)
	val.TextXAlignment = Enum.TextXAlignment.Right
	val.Text        = rowValue
	val.Parent      = row
end

----------------------------------------------------------------------
-- Footer note (persistence caveat)
----------------------------------------------------------------------

local footer = Instance.new("TextLabel")
footer.BackgroundTransparency = 1
footer.Position    = UDim2.new(0, 14, 1, -FOOTER_H - 8)
footer.Size        = UDim2.new(1, -28, 0, FOOTER_H)
footer.Font        = Enum.Font.Gotham
footer.TextSize    = 10
footer.TextColor3  = Color3.fromRGB(110, 100, 88)
footer.TextXAlignment = Enum.TextXAlignment.Left
footer.Text        = "Settings save automatically and carry over next time you join."
footer.Parent      = panel

----------------------------------------------------------------------
-- Open / close
----------------------------------------------------------------------

setActiveTab("Audio")

-- Invisible full-screen click-catcher sits behind the panel; clicking it
-- anywhere outside the panel closes the menu.
local backdrop = Instance.new("TextButton")
backdrop.Name                 = "Backdrop"
backdrop.Size                 = UDim2.new(1, 0, 1, 0)
backdrop.BackgroundTransparency = 1
backdrop.Text                 = ""
backdrop.ZIndex               = 8
backdrop.Visible              = false
backdrop.Parent               = sg

local panelOpen = false
local openTI  = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local closeTI = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function setPanelOpen(open)
	panelOpen = open
	CursorManager.setFree("settings", open)
	if open then
		backdrop.Visible             = true
		panel.BackgroundTransparency = 0.7
		panel.Visible                = true
		TweenService:Create(panel,   openTI, { BackgroundTransparency = 0.1 }):Play()
		TweenService:Create(gearBtn, openTI, { TextTransparency = 0 }):Play()
	else
		backdrop.Visible = false
		local t = TweenService:Create(panel, closeTI, { BackgroundTransparency = 0.7 })
		t:Play()
		t.Completed:Connect(function()
			if not panelOpen then panel.Visible = false end
		end)
		TweenService:Create(gearBtn, closeTI, { TextTransparency = 0.2 }):Play()
	end
end

backdrop.Activated:Connect(function()
	setPanelOpen(false)
end)

gearBtn.Activated:Connect(function()
	setPanelOpen(not panelOpen)
end)
