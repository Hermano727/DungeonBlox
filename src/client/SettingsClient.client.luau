--[[
	SettingsClient
	Gear icon (in the top-right quick-nav row under the minimap, RS/HudQuickNav) opens the
	Settings screen, centred, Minecraft-style (2026-09-30): a root page of buttons leading to
	Audio / Video / Controls pages, each a two-column grid of bars (sliders show "Label: value"
	inside the bar with a draggable handle). Every page ends in Done: back one level, and Done
	on the root closes Settings (Esc does the same). While it is open the HP/energy cluster is
	hidden (InteractionLock's menu default, RS/HudVitals).

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
local QuickNav       = require(ReplicatedStorage:WaitForChild("HudQuickNav"))
local InteractionLock = require(ReplicatedStorage:WaitForChild("InteractionLock"))

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

-- The gear is drawn into a small EditableImage at startup: pure white with a thin dark rim.
-- (It used to be the "⚙" character, which Roblox renders as a grey emoji that ignores
-- TextColor3, and emoji don't belong in the UI anyway.)
local function drawGearIcon()
	local N = 64
	local ok, img = pcall(function() return game:GetService("AssetService"):CreateEditableImage({ Size = Vector2.new(N, N) }) end)
	if not ok or not img then return nil end
	local TEETH, OUTER, ROOT, HOLE, RIM = 8, 30, 23.5, 9.5, 2.2
	-- Signed distance-ish test: inside the gear body when HOLE <= r <= edge(angle).
	local function edge(angle)
		local tooth = math.cos(angle * TEETH)
		-- flat-topped teeth: full height while cos > 0.35, blended down to the root
		local t = math.clamp((tooth - 0.1) / 0.35, 0, 1)
		return ROOT + (OUTER - ROOT) * t
	end
	local function coverage(px, py, grow)
		local hits = 0
		for sy = 0, 1 do
			for sx = 0, 1 do
				local x, y = px + 0.25 + sx * 0.5 - N / 2, py + 0.25 + sy * 0.5 - N / 2
				local r = math.sqrt(x * x + y * y)
				if r >= HOLE - grow and r <= edge(math.atan2(y, x)) + grow then hits += 1 end
			end
		end
		return hits / 4
	end
	local buf = buffer.create(N * N * 4)
	for py = 0, N - 1 do
		for px = 0, N - 1 do
			local body = coverage(px, py, 0)   -- white gear
			local rim = coverage(px, py, RIM)  -- dark edge around it
			local alpha = math.max(body, rim * 0.85)
			local at = (py * N + px) * 4
			local v = math.floor(24 + (255 - 24) * body + 0.5) -- white inside, blending to the rim
			buffer.writeu8(buf, at, v)
			buffer.writeu8(buf, at + 1, v)
			buffer.writeu8(buf, at + 2, v)
			buffer.writeu8(buf, at + 3, math.floor(alpha * 255 + 0.5))
		end
	end
	img:WritePixelsBuffer(Vector2.zero, Vector2.new(N, N), buf)
	return Content.fromObject(img)
end

local gearBtn = Instance.new("TextButton")
gearBtn.Name                 = "GearButton"
gearBtn.Size                 = UDim2.fromOffset(QuickNav.BUTTON_SIZE, QuickNav.BUTTON_SIZE)
gearBtn.BackgroundColor3     = Color3.fromRGB(14, 13, 16)
gearBtn.BackgroundTransparency = 0.25
gearBtn.AutoButtonColor      = false
gearBtn.Text                 = ""
gearBtn.ZIndex               = 10
-- Lives in the quick-nav row (its own ScreenGui, drawn above this one's click-away backdrop).
gearBtn.Parent               = QuickNav.Slot("Settings", QuickNav.ORDER.Settings)
Instance.new("UICorner", gearBtn).CornerRadius = UDim.new(0, 5)
QuickNav.Tooltip(gearBtn, "Settings")

local GEAR_SIZE, GEAR_HOVER_SIZE = 22, 27
local gearIcon = Instance.new("ImageLabel")
gearIcon.Name                   = "Icon"
gearIcon.AnchorPoint            = Vector2.new(0.5, 0.5)
gearIcon.Position               = UDim2.fromScale(0.5, 0.5)
gearIcon.Size                   = UDim2.fromOffset(GEAR_SIZE, GEAR_SIZE)
gearIcon.BackgroundTransparency = 1
gearIcon.ZIndex                 = 11
gearIcon.Parent                 = gearBtn
local gearContent = drawGearIcon()
if gearContent then
	gearIcon.ImageContent = gearContent
else
	-- No EditableImage (budget exhausted): fall back to a plain label so the button still reads.
	gearBtn.Text, gearBtn.TextColor3, gearBtn.TextSize, gearBtn.Font = "SET", Color3.new(1, 1, 1), 11, Enum.Font.GothamBold
end

-- Hover: the icon grows, the backing darkens. Only the icon grows, not the button, so the
-- quick-nav row never reflows under the cursor.
local hoverTI = TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local unhoverTI = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
gearBtn.MouseEnter:Connect(function()
	TweenService:Create(gearIcon, hoverTI, { Size = UDim2.fromOffset(GEAR_HOVER_SIZE, GEAR_HOVER_SIZE) }):Play()
	TweenService:Create(gearBtn, hoverTI, { BackgroundTransparency = 0.05 }):Play()
end)
gearBtn.MouseLeave:Connect(function()
	TweenService:Create(gearIcon, unhoverTI, { Size = UDim2.fromOffset(GEAR_SIZE, GEAR_SIZE) }):Play()
	TweenService:Create(gearBtn, unhoverTI, { BackgroundTransparency = 0.25 }):Play()
end)

----------------------------------------------------------------------
-- Settings screen (2026-09-30): a centred page stack, Minecraft-style.
--   Settings (root)  ->  Audio Settings... / Video Settings... / Controls...
-- Every page is a two-column grid of full-width bars (a slider bar shows
-- "Label: value" inside it with a draggable handle; a button bar opens a
-- sub-page) and ends in a Done button: Done goes back one level, and Done
-- on the root closes Settings. Esc (Keys.CloseMenu) does the same as Done.
-- New settings: add a bar to a page, or a new page + a nav button on root.
----------------------------------------------------------------------

local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))

local C = {
	Dim          = Color3.fromRGB(0, 0, 0),
	Panel        = Color3.fromRGB(16, 14, 12),
	PanelEdge    = Color3.fromRGB(70, 60, 50),
	Bar          = Color3.fromRGB(30, 26, 22),
	BarHover     = Color3.fromRGB(42, 36, 30),
	BarEdge      = Color3.fromRGB(78, 68, 56),
	BarEdgeHover = Color3.fromRGB(215, 175, 105),
	Fill         = Color3.fromRGB(175, 140, 80),
	Handle       = Color3.fromRGB(215, 175, 105),
	Text         = Color3.fromRGB(236, 226, 208),
	TextMuted    = Color3.fromRGB(150, 138, 120),
	Title        = Color3.fromRGB(215, 175, 105),
	TextEdge     = Color3.fromRGB(8, 6, 6),
}
local BAR_W, BAR_H     = 250, 34
local COL_GAP, ROW_GAP = 12, 8
local PAD              = 22
local TITLE_H          = 40
local DONE_GAP         = 18 -- between the grid and the Done button
local FOOTER_H         = 18
local HANDLE_W         = 8
local PANEL_W          = PAD * 2 + BAR_W * 2 + COL_GAP

-- Full-screen dim behind the panel. A TextButton so clicks never reach the world; clicking it
-- does nothing (Done, Esc and the gear close Settings, the way Minecraft menus work).
local backdrop = Instance.new("TextButton")
backdrop.Name                   = "Backdrop"
backdrop.Size                   = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3       = C.Dim
backdrop.BackgroundTransparency = 1
backdrop.AutoButtonColor        = false
backdrop.Text                   = ""
backdrop.ZIndex                 = 8
backdrop.Visible                = false
backdrop.Parent                 = sg

local panel = Instance.new("Frame")
panel.Name                   = "SettingsPanel"
panel.AnchorPoint            = Vector2.new(0.5, 0.5)
panel.Position               = UDim2.fromScale(0.5, 0.5)
panel.Size                   = UDim2.fromOffset(PANEL_W, 300)
panel.BackgroundColor3       = C.Panel
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel        = 0
panel.Visible                = false
panel.ZIndex                 = 9
panel.Parent                 = sg
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)
local panelStroke = Instance.new("UIStroke", panel)
panelStroke.Thickness    = 1
panelStroke.Color        = C.PanelEdge
panelStroke.Transparency = 0.2
local panelScale = Instance.new("UIScale", panel)

local titleLabel = Instance.new("TextLabel")
titleLabel.Name                   = "Title"
titleLabel.BackgroundTransparency = 1
titleLabel.Position               = UDim2.fromOffset(0, PAD - 6)
titleLabel.Size                   = UDim2.new(1, 0, 0, TITLE_H - 10)
titleLabel.FontFace               = UIFonts.DisplayBold
titleLabel.TextSize               = 22
titleLabel.TextColor3             = C.Title
titleLabel.TextStrokeColor3       = C.TextEdge
titleLabel.TextStrokeTransparency = 0.6
titleLabel.Text                   = "Settings"
titleLabel.ZIndex                 = 10
titleLabel.Parent                 = panel

local function barLabel(parent, text)
	local label = Instance.new("TextLabel")
	label.Name                   = "Label"
	label.BackgroundTransparency = 1
	label.Size                   = UDim2.new(1, -12, 1, 0)
	label.AnchorPoint            = Vector2.new(0.5, 0.5)
	label.Position               = UDim2.fromScale(0.5, 0.5)
	label.FontFace               = UIFonts.BodyBold
	label.TextScaled             = true
	label.TextColor3             = C.Text
	label.TextStrokeColor3       = C.TextEdge
	label.TextStrokeTransparency = 0.45
	label.RichText               = true
	label.Text                   = text
	label.ZIndex                 = 14
	label.Parent                 = parent
	local size = Instance.new("UITextSizeConstraint", label)
	size.MaxTextSize, size.MinTextSize = 15, 9
	return label
end

-- The shared bar: dark plate, thin edge that turns gold on hover (interactive bars only).
local function makeBar(parent, text, interactive)
	local bar = Instance.new(interactive and "TextButton" or "Frame")
	bar.Size             = UDim2.fromOffset(BAR_W, BAR_H)
	bar.BackgroundColor3 = C.Bar
	bar.BorderSizePixel  = 0
	bar.ZIndex           = 11
	if interactive then
		bar.AutoButtonColor = false
		bar.Text = ""
	end
	bar.Parent = parent
	Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 4)
	local edge = Instance.new("UIStroke", bar)
	edge.Color = C.BarEdge
	edge.Thickness = 1
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local label = barLabel(bar, text)
	if interactive then
		bar.MouseEnter:Connect(function()
			bar.BackgroundColor3 = C.BarHover
			edge.Color = C.BarEdgeHover
		end)
		bar.MouseLeave:Connect(function()
			bar.BackgroundColor3 = C.Bar
			edge.Color = C.BarEdge
		end)
	end
	return bar, label
end

----------------------------------------------------------------------
-- Pages
----------------------------------------------------------------------

local currentPage = nil

local function makePage(name, title, parentPage)
	local grid = Instance.new("Frame")
	grid.Name                   = name .. "Page"
	grid.BackgroundTransparency = 1
	grid.Position               = UDim2.fromOffset(PAD, PAD + TITLE_H)
	grid.Size                   = UDim2.new(1, -PAD * 2, 0, 0)
	grid.Visible                = false
	grid.ZIndex                 = 10
	grid.Parent                 = panel
	local layout = Instance.new("UIGridLayout", grid)
	layout.CellSize              = UDim2.fromOffset(BAR_W, BAR_H)
	layout.CellPadding           = UDim2.fromOffset(COL_GAP, ROW_GAP)
	layout.FillDirectionMaxCells = 2
	layout.SortOrder             = Enum.SortOrder.LayoutOrder
	return { name = name, title = title, parent = parentPage, grid = grid, count = 0 }
end

-- Bars join a page in call order (LayoutOrder): left column, then right, row by row.
local function addToPage(page, bar)
	page.count += 1
	bar.LayoutOrder = page.count
end

local doneButton = makeBar(panel, "Done", true)
doneButton.Name = "Done"

local function showPage(page)
	if currentPage then currentPage.grid.Visible = false end
	currentPage = page
	page.grid.Visible = true
	titleLabel.Text = page.title
	local rows = math.max(1, math.ceil(page.count / 2))
	local gridH = rows * BAR_H + (rows - 1) * ROW_GAP
	page.grid.Size = UDim2.new(1, -PAD * 2, 0, gridH)
	local doneY = PAD + TITLE_H + gridH + DONE_GAP
	doneButton.Position = UDim2.fromOffset((PANEL_W - BAR_W) / 2, doneY)
	panel.Size = UDim2.fromOffset(PANEL_W, doneY + BAR_H + FOOTER_H + PAD)
end

local rootPage    = makePage("Root", "Settings")
local audioTab    = makePage("Audio", "Audio Settings", rootPage)
local videoTab    = makePage("Video", "Video Settings", rootPage)
local controlsTab = makePage("Controls", "Controls", rootPage)

local function navButton(page, text, target)
	local bar = makeBar(page.grid, text, true)
	addToPage(page, bar)
	bar.Activated:Connect(function() showPage(target) end)
	return bar
end

navButton(rootPage, "Audio Settings...", audioTab)
navButton(rootPage, "Video Settings...", videoTab)
navButton(rootPage, "Controls...", controlsTab)

local footer = Instance.new("TextLabel")
footer.BackgroundTransparency = 1
footer.AnchorPoint    = Vector2.new(0.5, 1)
footer.Position       = UDim2.new(0.5, 0, 1, -PAD + 8)
footer.Size           = UDim2.new(1, -PAD * 2, 0, FOOTER_H)
footer.FontFace       = UIFonts.Body
footer.TextSize       = 11
footer.TextColor3     = C.TextMuted
footer.Text           = "Settings save automatically and carry over next time you join."
footer.ZIndex         = 10
footer.Parent         = panel

----------------------------------------------------------------------
-- Slider bar (Minecraft-style): "Label: value" drawn inside the bar, a
-- faint fill up to the value, and a handle that drags along it.
----------------------------------------------------------------------

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
local function makeSlider(page, label, initValue, opts)
	opts = opts or {}
	local min = opts.min or 0
	local max = opts.max or 1
	local format = opts.format or percentFormat
	local onChange = opts.onChange or function() end
	local onCommit = opts.onCommit or function() end
	local lastValue = initValue

	local bar, text = makeBar(page.grid, "", true)
	addToPage(page, bar)

	local fill = Instance.new("Frame")
	fill.Name                   = "Fill"
	fill.BackgroundColor3       = C.Fill
	fill.BackgroundTransparency = 0.78
	fill.BorderSizePixel        = 0
	fill.ZIndex                 = 12
	fill.Parent                 = bar
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 4)

	local handle = Instance.new("Frame")
	handle.Name             = "Handle"
	handle.AnchorPoint      = Vector2.new(0.5, 0.5)
	handle.Size             = UDim2.new(0, HANDLE_W, 1, -4)
	handle.BackgroundColor3 = C.Handle
	handle.BorderSizePixel  = 0
	handle.ZIndex           = 13
	handle.Parent           = bar
	Instance.new("UICorner", handle).CornerRadius = UDim.new(0, 2)
	local handleEdge = Instance.new("UIStroke", handle)
	handleEdge.Color = C.TextEdge
	handleEdge.Transparency = 0.4

	local function render(t, value)
		fill.Size = UDim2.fromScale(t, 1)
		-- Offset keeps the handle inside the bar at both ends.
		handle.Position = UDim2.new(t, (0.5 - t) * HANDLE_W, 0.5, 0)
		text.Text = label .. ": " .. format(value)
	end
	render(invLerp(min, max, initValue), initValue)

	local dragging = false
	local function applyAt(absX)
		local width = bar.AbsoluteSize.X - HANDLE_W
		if width <= 0 then return end
		local t = math.clamp((absX - bar.AbsolutePosition.X - HANDLE_W / 2) / width, 0, 1)
		local value = lerp(min, max, t)
		lastValue = value
		render(t, value)
		onChange(value)
	end

	bar.InputBegan:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1
			or inp.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			applyAt(inp.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(inp)
		if not dragging then return end
		if inp.UserInputType == Enum.UserInputType.MouseMovement
			or inp.UserInputType == Enum.UserInputType.Touch then
			applyAt(inp.Position.X)
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

	return bar
end

----------------------------------------------------------------------
-- Audio page: Master, Music, Movement, Effects
----------------------------------------------------------------------

local mainGroup        = SoundService:WaitForChild("Main")
local movementSfxGroup = mainGroup:WaitForChild("Character")

local function liveMusicSound()
	return SoundService:FindFirstChild("ZoneMusic")
end

-- Per-track volume scale, stamped on the Sound by ZoneClient (see MusicPlayback).
-- Both sliders below write ZoneMusic.Volume directly, so both have to carry it
-- or moving a slider would silently flatten a track that is meant to sit louder
-- or quieter than the rest.
local function musicTrackScale(musicSound)
	return tonumber(musicSound:GetAttribute("TrackVolumeScale")) or 1
end

-- Push the saved volumes onto the live SoundGroups once at startup.
--
-- Without this the ONLY writer was a slider's onChange, so every fresh session
-- played at whatever volume the place file's groups happen to carry, no matter
-- what the player had saved -- footsteps blasted at full volume until you
-- nudged the Movement slider, which is what "fixed" it (2026-09-17 report:
-- "3% is super loud, set it to 2% then back to 3% and it's fine").
--
-- Only the group-driven buses need this. Music and one-shot effect sounds
-- recompute their own volume from VolumeSettings every time they play
-- (ZoneClient's targetMusicVolume, SfxService.PlayEffect), which is why
-- movement was the one that was audibly wrong.
local function applySavedVolumes()
	mainGroup.Volume = VolumeSettings.master * VolumeSettings.OUTPUT_GAIN
	movementSfxGroup.Volume = VolumeSettings.movement
	local effectsGroup = SfxService.GetEffectsGroup()
	if effectsGroup then
		effectsGroup.Volume = VolumeSettings.effects
	end
end

applySavedVolumes()

makeSlider(audioTab, "Master", VolumeSettings.master, {
	min = SettingsRanges.volume.master.min,
	max = SettingsRanges.volume.master.max,
	onChange = function(v)
		VolumeSettings.master = v
		mainGroup.Volume = v * VolumeSettings.OUTPUT_GAIN -- scales everything under Main via SoundGroup nesting
		local musicSound = liveMusicSound()
		if musicSound and musicSound.IsPlaying then
			musicSound.Volume = v * VolumeSettings.music * musicTrackScale(musicSound) * VolumeSettings.OUTPUT_GAIN
		end
	end,
	onCommit = persist("volume", "master"),
})

makeSlider(audioTab, "Music", VolumeSettings.music, {
	min = SettingsRanges.volume.music.min,
	max = SettingsRanges.volume.music.max,
	onChange = function(v)
		VolumeSettings.music = v
		local musicSound = liveMusicSound()
		if musicSound and musicSound.IsPlaying then
			musicSound.Volume = VolumeSettings.master * v * musicTrackScale(musicSound) * VolumeSettings.OUTPUT_GAIN
		end
	end,
	onCommit = persist("volume", "music"),
})

makeSlider(audioTab, "Movement", VolumeSettings.movement, {
	min = SettingsRanges.volume.movement.min,
	max = SettingsRanges.volume.movement.max,
	onChange = function(v)
		VolumeSettings.movement = v
		movementSfxGroup.Volume = v
	end,
	onCommit = persist("volume", "movement"),
})

makeSlider(audioTab, "Effects", VolumeSettings.effects, {
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
-- Video page: FOV, Sensitivity, Brightness
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

makeSlider(videoTab, "FOV", VideoSettings.fov, {
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

makeSlider(videoTab, "Sensitivity", VideoSettings.sensitivity, {
	min = SettingsRanges.video.sensitivity.min,
	max = SettingsRanges.video.sensitivity.max,
	format = function(v) return tostring(math.round(v / 0.003 * 100)) .. "%" end,
	onChange = function(v)
		VideoSettings.sensitivity = v
	end,
	onCommit = persist("video", "sensitivity"),
})

makeSlider(videoTab, "Brightness", VideoSettings.brightness, {
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
-- Controls page: read-only reference generated from KeybindConfig
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

-- One read-only bar per control: "Action: key", the key in gold.
local KEY_HEX = C.Title:ToHex()
for _, entry in ipairs(CONTROLS_ROWS) do
	local bar = makeBar(controlsTab.grid, ('%s: <font color="#%s">%s</font>'):format(entry[1], KEY_HEX, entry[2]), false)
	addToPage(controlsTab, bar)
end

----------------------------------------------------------------------
-- Open / close / Done
----------------------------------------------------------------------

local panelOpen = false
local openTI  = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local closeTI = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local DIM_TRANSPARENCY = 0.45

local function setPanelOpen(open)
	if open and InteractionLock.IsLocked() then return end -- a blocking overlay (map, station) is up
	if open == panelOpen then return end
	panelOpen = open
	-- A switchable menu: opening Settings closes the inventory / party panel (and hides the
	-- HP/energy cluster, InteractionLock's default for menus).
	if open then
		InteractionLock.OpenMenu("Settings", function() setPanelOpen(false) end)
	else
		InteractionLock.MenuClosed("Settings")
	end
	CursorManager.setFree("settings", open)
	if open then
		showPage(rootPage) -- always opens at the top level
		backdrop.BackgroundTransparency = 1
		backdrop.Visible = true
		panel.Visible = true
		panelScale.Scale = 0.96
		TweenService:Create(backdrop, openTI, { BackgroundTransparency = DIM_TRANSPARENCY }):Play()
		TweenService:Create(panelScale, openTI, { Scale = 1 }):Play()
	else
		TweenService:Create(backdrop, closeTI, { BackgroundTransparency = 1 }):Play()
		local shrink = TweenService:Create(panelScale, closeTI, { Scale = 0.96 })
		shrink:Play()
		shrink.Completed:Connect(function()
			if not panelOpen then
				panel.Visible = false
				backdrop.Visible = false
			end
		end)
	end
end

-- Done: back one level; on the root page it closes Settings.
local function done()
	if not panelOpen then return end
	if currentPage and currentPage.parent then
		showPage(currentPage.parent)
	else
		setPanelOpen(false)
	end
end

doneButton.Activated:Connect(done)

gearBtn.Activated:Connect(function()
	setPanelOpen(not panelOpen)
end)

UserInputService.InputBegan:Connect(function(input)
	if panelOpen and input.KeyCode == Keys.CloseMenu then done() end
end)

-- A blocking overlay opened on top: close.
InteractionLock.Subscribe(function(locked)
	if locked and panelOpen then setPanelOpen(false) end
end)
