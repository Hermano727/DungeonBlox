--[[
	SettingsClient
	Gear icon (in the top-right quick-nav row under the minimap, RS/HudQuickNav) opens the
	Settings screen, centred, Minecraft-style (2026-09-30): a root page of buttons leading to
	Audio / Video / Controls pages, each a two-column grid of bars (sliders show "Label: value"
	inside the bar with a draggable handle). Every page ends in Done: back one level, and Done
	on the root closes Settings (Esc does the same). While it is open the HP/energy cluster is
	hidden (InteractionLock's menu default, RS/HudVitals).

	Audio -- generated from RS/AudioCategories (2026-10-11): one slider per sound
	bucket, in titled sections (Master; Environment: Music, Ambient & World;
	Movement: Player Footsteps, Mount; ...). A new bucket in that registry shows
	up here, saves and applies with no edit in this file. Each slider is the
	bucket's SoundGroup volume (Master = SoundService.Main, Music = ZoneMusic).

	Video -- FOV, Sensitivity, Brightness, Crosshair on/off. Backed by VideoSettings.luau
	(the crosshair toggle is stored under hud.crosshair, see SettingsRanges).
	FOV/Sensitivity feed FirstPersonViewModel + the Crouching/Animate2/
	DialogModule scripts that also touch Camera.FieldOfView (see VideoSettings
	header comment). Brightness is a client-local ColorCorrectionEffect, not
	Lighting.Brightness -- DayNightService owns Lighting.ClockTime
	authoritatively every Heartbeat and this sidesteps that fight entirely.

	Controls -- every player-facing key, rebindable (2026-10-11): KeybindConfig.Actions in a
	scrolling list; click a key slot and press the new key (Esc cancels); a clash with another
	action offers Swap / Cancel, locked controls and reserved keys are refused with the reason;
	Reset per row and Reset all (asks twice). Applies at once (KeybindConfig.Set -> .Changed) and
	saves as settings category "keys" (SettingsDataService; applied at join by KeybindLoader).
	See the "Controls page" section below for the UX rules.

	Look (2026-10-11): the dark menu kit, RS/Assets/Images/MenuUI (+ MapUI's panel and button
	tile): the map's small dark panel as the body, a cream ribbon carrying the page title, wood
	plates with a slim gold rim for every row (the leaf from the map slides in beside a hovered
	button), a groove + flower knob for sliders with a gold fill, a tick box for on/off, bronze
	glyphs on the root's buttons, the quick-nav tile as Done. Labels in the Journal's serif.
	Every piece falls back to the old flat look while its art id is empty.

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
local Keys           = require(ReplicatedStorage:WaitForChild("KeybindConfig"))
local SettingsRanges = require(ReplicatedStorage:WaitForChild("SettingsRanges"))
local AudioCategories = require(ReplicatedStorage:WaitForChild("AudioCategories"))
local SettingsStore  = require(ReplicatedStorage:WaitForChild("SettingsStore"))
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

-- The gear is the bronze glyph from the nav set (MapUI.SETTINGS_GLYPH, 2026-10-11). It used to
-- be a white gear drawn into an EditableImage, and before that the "⚙" character (a grey emoji
-- that ignored TextColor3). Without the art the button reads "SET".
local MapUI = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images"):WaitForChild("MapUI"))
local gearArt = MapUI.SETTINGS_GLYPH.Image
local gearBtn = QuickNav.Button({
	name    = "GearButton",
	order   = QuickNav.ORDER.Settings,
	tooltip = "Settings",
	image   = gearArt ~= "" and gearArt or nil,
	text    = gearArt == "" and "SET" or nil,
})

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
local ImagesFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images")
local MenuUI = require(ImagesFolder:WaitForChild("MenuUI"))
local MapUI = require(ImagesFolder:WaitForChild("MapUI"))

local function hasArt(art)
	return art ~= nil and art.Image ~= ""
end

local C = {
	Dim          = Color3.fromRGB(0, 0, 0),
	Panel        = Color3.fromRGB(16, 14, 12),
	PanelEdge    = Color3.fromRGB(70, 60, 50),
	Bar          = Color3.fromRGB(30, 26, 22),
	BarHover     = Color3.fromRGB(42, 36, 30),
	BarEdge      = Color3.fromRGB(78, 68, 56),
	BarEdgeHover = Color3.fromRGB(215, 175, 105),
	Handle       = Color3.fromRGB(215, 175, 105),
	Text         = Color3.fromRGB(236, 226, 208),
	TextMuted    = Color3.fromRGB(150, 138, 120),
	Title        = Color3.fromRGB(215, 175, 105),
	TextEdge     = Color3.fromRGB(8, 6, 6),
	Ink          = Color3.fromRGB(38, 28, 18),   -- the title, written on the cream ribbon
	PlateIdle    = Color3.fromRGB(226, 226, 226), -- plate art dimmed a touch so hover can lift it
	FillLow      = Color3.fromRGB(201, 138, 46),  -- a slider's gold fill, left to right
	FillHigh     = Color3.fromRGB(242, 196, 90),
}
local BAR_W, BAR_H     = 250, 34
local COL_GAP, ROW_GAP = 12, 8
local PAD              = 22
local TITLE_H          = 44
local DONE_GAP         = 18 -- between the grid and the Done button
local FOOTER_H         = 18
local HANDLE_W         = 8  -- the fallback slider handle (no knob art)
local KNOB_PX          = 20 -- the flower knob
local TRACK_H          = 11 -- the slider groove
local PANEL_SLICE      = .3 -- the panel art's 9-slice scale (its corners ~36 px)
local BAR_SLICE        = .24 -- the plate art's 9-slice scale (rim ~4 px at 34 px tall)
local HEADER_H         = 24 -- a section title on a list page (the Audio page)
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
local panelArt = MapUI.PANEL
if hasArt(panelArt) then
	-- The map's small dark panel: slim bronze double rule, a sprig in the top-left corner.
	panel.BackgroundTransparency = 1
	local body = Instance.new("ImageLabel")
	body.Name                   = "Body"
	body.BackgroundTransparency = 1
	body.Size                   = UDim2.fromScale(1, 1)
	body.Image                  = panelArt.Image
	body.ScaleType              = Enum.ScaleType.Slice
	body.SliceCenter            = panelArt.SliceCenter
	body.SliceScale             = PANEL_SLICE
	body.ZIndex                 = 9
	body.Parent                 = panel
else
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)
	local panelStroke = Instance.new("UIStroke", panel)
	panelStroke.Thickness    = 1
	panelStroke.Color        = C.PanelEdge
	panelStroke.Transparency = 0.2
end
local panelScale = Instance.new("UIScale", panel)

-- The page title: written on a cream ribbon that sits across the panel's top edge (drawn whole
-- at its own aspect: its flowers are mid-top, so it can't be 9-sliced), or gold text without it.
local titleLabel = Instance.new("TextLabel")
titleLabel.Name                   = "Title"
titleLabel.BackgroundTransparency = 1
titleLabel.Text                   = "Settings"
titleLabel.ZIndex                 = 10
local ribbonArt = MenuUI.TITLE_RIBBON
if hasArt(ribbonArt) then
	local RIBBON_W = 360
	local ribbonH = math.floor(RIBBON_W * ribbonArt.Size.Y / ribbonArt.Size.X + .5)
	local ribbon = Instance.new("ImageLabel")
	ribbon.Name                   = "TitleRibbon"
	ribbon.BackgroundTransparency = 1
	ribbon.AnchorPoint            = Vector2.new(0.5, 0)
	ribbon.Position               = UDim2.new(0.5, 0, 0, -math.floor(ribbonH * .38))
	ribbon.Size                   = UDim2.fromOffset(RIBBON_W, ribbonH)
	ribbon.Image                  = ribbonArt.Image
	ribbon.ZIndex                 = 10
	ribbon.Parent                 = panel
	local band = ribbonArt.Band
	titleLabel.Position   = UDim2.fromScale(0.15, band.Y0 / ribbonArt.Size.Y)
	titleLabel.Size       = UDim2.fromScale(0.7, (band.Y1 - band.Y0) / ribbonArt.Size.Y)
	titleLabel.FontFace   = UIFonts.SerifBold
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = C.Ink
	titleLabel.ZIndex     = 11
	local fit = Instance.new("UITextSizeConstraint", titleLabel)
	fit.MaxTextSize, fit.MinTextSize = 18, 10
	titleLabel.Parent = ribbon
else
	titleLabel.Position               = UDim2.fromOffset(0, PAD - 6)
	titleLabel.Size                   = UDim2.new(1, 0, 0, TITLE_H - 10)
	titleLabel.FontFace               = UIFonts.DisplayBold
	titleLabel.TextSize               = 22
	titleLabel.TextColor3             = C.Title
	titleLabel.TextStrokeColor3       = C.TextEdge
	titleLabel.TextStrokeTransparency = 0.6
	titleLabel.Parent                 = panel
end

local function barLabel(parent, text)
	local label = Instance.new("TextLabel")
	label.Name                   = "Label"
	label.BackgroundTransparency = 1
	label.Size                   = UDim2.new(1, -12, 1, 0)
	label.AnchorPoint            = Vector2.new(0.5, 0.5)
	label.Position               = UDim2.fromScale(0.5, 0.5)
	label.FontFace               = UIFonts.SerifBold
	label.TextScaled             = true
	label.TextColor3             = C.Text
	label.TextStrokeColor3       = C.TextEdge
	label.TextStrokeTransparency = 0.7
	label.RichText               = true
	label.Text                   = text
	label.ZIndex                 = 14
	label.Parent                 = parent
	local size = Instance.new("UITextSizeConstraint", label)
	size.MaxTextSize, size.MinTextSize = 15, 9
	return label
end

-- The plate behind a row: MenuUI.BAR (9-slice), else the flat dark plate with an edge. Returns
-- a setHover(on) function.
local function paintPlate(bar, art, sliceScale)
	art = art or MenuUI.BAR
	if hasArt(art) then
		bar.BackgroundTransparency = 1
		local plate = Instance.new("ImageLabel")
		plate.Name                   = "Plate"
		plate.BackgroundTransparency = 1
		plate.Size                   = UDim2.fromScale(1, 1)
		plate.Image                  = art.Image
		plate.ImageColor3            = C.PlateIdle
		plate.ScaleType              = Enum.ScaleType.Slice
		plate.SliceCenter            = art.SliceCenter
		plate.SliceScale             = sliceScale or BAR_SLICE
		plate.ZIndex                 = bar.ZIndex
		plate.Parent                 = bar
		return function(on)
			plate.ImageColor3 = on and Color3.new(1, 1, 1) or C.PlateIdle
		end
	end
	bar.BackgroundColor3 = C.Bar
	Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 4)
	local edge = Instance.new("UIStroke", bar)
	edge.Color = C.BarEdge
	edge.Thickness = 1
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	return function(on)
		bar.BackgroundColor3 = on and C.BarHover or C.Bar
		edge.Color = on and C.BarEdgeHover or C.BarEdge
	end
end

-- The map's hover leaf (MapUI.ROW_POINTER), at a button's left end while it's hovered.
local function addPointer(bar)
	local leaf = MapUI.ROW_POINTER
	if not hasArt(leaf) then return nil end
	local pointer = Instance.new("ImageLabel")
	pointer.Name                   = "Pointer"
	pointer.BackgroundTransparency = 1
	pointer.AnchorPoint            = Vector2.new(0, 0.5)
	pointer.Position               = UDim2.new(0, 9, 0.5, 0)
	pointer.Size                   = UDim2.fromOffset(17, math.floor(17 / leaf.Aspect + .5))
	pointer.Image                  = leaf.Image
	pointer.Visible                = false
	pointer.ZIndex                 = 15
	pointer.Parent                 = bar
	return pointer
end

-- The shared bar: a plate that lifts on hover (interactive bars only; buttons also get the
-- leaf, `opts.noPointer` leaves it off: sliders).
local function makeBar(parent, text, interactive, opts)
	opts = opts or {}
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
	local setHover = paintPlate(bar, opts.art, opts.sliceScale)
	local label = barLabel(bar, text)
	if interactive then
		local pointer = not opts.noPointer and addPointer(bar)
		bar.MouseEnter:Connect(function()
			setHover(true)
			if pointer then pointer.Visible = true end
		end)
		bar.MouseLeave:Connect(function()
			setHover(false)
			if pointer then pointer.Visible = false end
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

-- A page that can carry section titles (the Audio page): a vertical list of titles and rows of
-- up to two bars, instead of the plain two-column grid. page.height tracks its content.
local function makeListPage(name, title, parentPage)
	local page = makePage(name, title, parentPage)
	page.grid:FindFirstChildOfClass("UIGridLayout"):Destroy()
	local layout = Instance.new("UIListLayout", page.grid)
	layout.Padding   = UDim.new(0, ROW_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	page.list, page.height = true, 0
	page.rowH = BAR_H
	return page
end

local function growListPage(page, h)
	page.height += (page.height > 0 and ROW_GAP or 0) + h
end

-- Bars join a page in call order (LayoutOrder): left column, then right, row by row. On a list
-- page a `wide` bar takes a whole row (both columns).
local function addToPage(page, bar, wide)
	page.count += 1
	bar.LayoutOrder = page.count
	if not page.list then return end
	if wide or not page.row or page.rowCount >= 2 then
		local row = Instance.new("Frame")
		row.Name                   = "Row"
		row.BackgroundTransparency = 1
		row.Size                   = UDim2.new(1, 0, 0, page.rowH)
		row.LayoutOrder            = page.count
		row.ZIndex                 = 10
		row.Parent                 = page.grid
		local rowLayout = Instance.new("UIListLayout", row)
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.Padding       = UDim.new(0, COL_GAP)
		rowLayout.SortOrder     = Enum.SortOrder.LayoutOrder
		page.row, page.rowCount = row, 0
		growListPage(page, page.rowH)
	end
	bar.Parent = page.row
	page.rowCount += 1
	if wide then
		bar.Size = UDim2.fromOffset(BAR_W * 2 + COL_GAP, page.rowH)
		page.rowCount = 2
	end
end

-- A section title on a list page: gold capitals on the left, a faint rule filling the rest at its midline.
local function addSectionTitle(page, text)
	page.count += 1
	page.row = nil
	local header = Instance.new("Frame")
	header.Name                   = "Section"
	header.BackgroundTransparency = 1
	header.Size                   = UDim2.new(1, 0, 0, HEADER_H)
	header.LayoutOrder            = page.count
	header.ZIndex                 = 10
	header.Parent                 = page.grid
	local headerLayout = Instance.new("UIListLayout", header)
	headerLayout.FillDirection     = Enum.FillDirection.Horizontal
	headerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	headerLayout.Padding           = UDim.new(0, 10)
	headerLayout.SortOrder         = Enum.SortOrder.LayoutOrder
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AutomaticSize          = Enum.AutomaticSize.X
	label.Size                   = UDim2.new(0, 0, 0, 18)
	label.FontFace               = UIFonts.SerifBold
	label.TextSize               = 14
	label.TextColor3             = C.Title
	label.TextStrokeColor3       = C.TextEdge
	label.TextStrokeTransparency = 0.6
	label.Text                   = string.upper(text)
	label.LayoutOrder            = 1
	label.ZIndex                 = 11
	label.Parent                 = header
	local rule = Instance.new("Frame")
	rule.Name                   = "Rule"
	rule.Size                   = UDim2.fromOffset(0, 1) -- the flex item below stretches it
	rule.BackgroundColor3       = C.PanelEdge
	rule.BackgroundTransparency = 0.3
	rule.BorderSizePixel        = 0
	rule.LayoutOrder            = 2
	rule.ZIndex                 = 11
	rule.Parent                 = header
	Instance.new("UIFlexItem", rule).FlexMode = Enum.UIFlexMode.Fill
	growListPage(page, HEADER_H)
end

-- Done stands out from the rows: the quick-nav tile (leaf and flower top left), sliced wide.
local DONE_ART = hasArt(MapUI.BUTTON_PLATE) and {
	Image = MapUI.BUTTON_PLATE.Image, SliceCenter = Rect.new(190, 190, 630, 600),
} or nil
local doneButton = makeBar(panel, "Done", true, { art = DONE_ART, sliceScale = .085 })
doneButton.Name = "Done"

-- The panel's scale: 1, or less when the page is taller than the screen (the Controls page on a
-- short window). Set by showPage; the open tween grows to it.
local panelFit = 1

local function showPage(page)
	if currentPage then
		currentPage.grid.Visible = false
		if currentPage.onLeave then currentPage.onLeave() end
	end
	currentPage = page
	page.grid.Visible = true
	titleLabel.Text = page.title
	local rows = math.max(1, math.ceil(page.count / 2))
	local gridH = page.fixedHeight or (page.list and page.height) or rows * BAR_H + (rows - 1) * ROW_GAP
	page.grid.Size = UDim2.new(1, -PAD * 2, 0, gridH)
	local doneY = PAD + TITLE_H + gridH + DONE_GAP
	doneButton.Position = UDim2.fromOffset((PANEL_W - BAR_W) / 2, doneY)
	local panelH = doneY + BAR_H + FOOTER_H + PAD
	panel.Size = UDim2.fromOffset(PANEL_W, panelH)
	local screenH = sg.AbsoluteSize.Y
	panelFit = screenH > 0 and math.min(1, (screenH - 40) / panelH) or 1
	if panel.Visible then panelScale.Scale = panelFit end
end

local rootPage    = makePage("Root", "Settings")
local audioTab    = makeListPage("Audio", "Audio Settings", rootPage)
local videoTab    = makePage("Video", "Video Settings", rootPage)
local controlsTab = makePage("Controls", "Controls", rootPage) -- its own layout, see "Controls page"

-- A button to a sub-page, with its bronze glyph (MenuUI.CATEGORY_ICONS) on the right end.
local function navButton(page, text, target, glyph)
	local bar = makeBar(page.grid, text, true)
	addToPage(page, bar)
	bar.Activated:Connect(function() showPage(target) end)
	local sheet = MenuUI.CATEGORY_ICONS
	local cell = glyph and hasArt(sheet) and sheet.Rects[glyph]
	if cell then
		local icon = Instance.new("ImageLabel")
		icon.Name                   = "Glyph"
		icon.BackgroundTransparency = 1
		icon.AnchorPoint            = Vector2.new(1, 0.5)
		icon.Position               = UDim2.new(1, -12, 0.5, 0)
		icon.Size                   = UDim2.fromOffset(24, 22)
		icon.Image                  = sheet.Image
		icon.ImageRectOffset        = cell.Offset
		icon.ImageRectSize          = cell.Size
		icon.ScaleType              = Enum.ScaleType.Fit
		icon.ZIndex                 = 14
		icon.Parent                 = bar
	end
	return bar
end

navButton(rootPage, "Audio", audioTab, "Audio")
navButton(rootPage, "Video", videoTab, "Video")
navButton(rootPage, "Controls", controlsTab, "Controls")

local footer = Instance.new("TextLabel")
footer.BackgroundTransparency = 1
footer.AnchorPoint    = Vector2.new(0.5, 1)
footer.Position       = UDim2.new(0.5, 0, 1, -PAD + 8)
footer.Size           = UDim2.new(1, -PAD * 2, 0, FOOTER_H)
footer.FontFace       = Font.new(UIFonts.Families.Body, Enum.FontWeight.Regular, Enum.FontStyle.Italic)
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

-- opts: { min, max, format(value)->string, onChange(value), onCommit(value), wide }
-- onChange fires on every drag frame (instant local feedback -- volume/FOV/
-- etc apply live). onCommit fires once, when the mouse/touch releases, with
-- the final value -- that's the one that should hit the network, so a drag
-- across the whole track doesn't fire dozens of UpdatePlayerSettings events.
-- Layout: the name and its value on the left ("Music  60%"), the groove on the right with a
-- gold fill and the flower knob. Dragging anywhere on the row sets the value along the groove.
local function makeSlider(page, label, initValue, opts)
	opts = opts or {}
	local min = opts.min or 0
	local max = opts.max or 1
	local format = opts.format or percentFormat
	local onChange = opts.onChange or function() end
	local onCommit = opts.onCommit or function() end
	local lastValue = initValue

	local bar, text = makeBar(page.grid, "", true, { noPointer = true })
	addToPage(page, bar, opts.wide)
	local labelShare = opts.wide and 0.34 or 0.5
	text.AnchorPoint    = Vector2.new(0, 0.5)
	text.Position       = UDim2.new(0, 12, 0.5, 0)
	text.Size           = UDim2.new(labelShare, -16, 1, -12)
	text.TextXAlignment = Enum.TextXAlignment.Left

	local trackArt = MenuUI.SLIDER_TRACK
	local knobArt = MenuUI.SLIDER_KNOB
	local track = Instance.new("Frame")
	track.Name                   = "Track"
	track.AnchorPoint            = Vector2.new(0, 0.5)
	track.Position               = UDim2.new(labelShare, 0, 0.5, 0)
	track.Size                   = UDim2.new(1 - labelShare, -16, 0, TRACK_H)
	track.BackgroundColor3       = C.TextEdge
	track.BackgroundTransparency = hasArt(trackArt) and 1 or 0.3
	track.BorderSizePixel        = 0
	track.ZIndex                 = 12
	track.Parent                 = bar
	if hasArt(trackArt) then
		local groove = Instance.new("ImageLabel")
		groove.Name                   = "Groove"
		groove.BackgroundTransparency = 1
		groove.Size                   = UDim2.fromScale(1, 1)
		groove.Image                  = trackArt.Image
		groove.ScaleType              = Enum.ScaleType.Slice
		groove.SliceCenter            = trackArt.SliceCenter
		groove.SliceScale             = TRACK_H / trackArt.Size.Y
		groove.ZIndex                 = 12
		groove.Parent                 = track
	else
		Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)
	end

	-- The fill sits inside the groove's lip.
	local lip = hasArt(trackArt) and math.max(1, math.floor(trackArt.Inner * TRACK_H / trackArt.Size.Y + .5)) or 0
	local fillHolder = Instance.new("Frame")
	fillHolder.Name                   = "FillArea"
	fillHolder.BackgroundTransparency = 1
	fillHolder.Position               = UDim2.fromOffset(lip, lip)
	fillHolder.Size                   = UDim2.new(1, -lip * 2, 1, -lip * 2)
	fillHolder.ZIndex                 = 13
	fillHolder.Parent                 = track
	local fill = Instance.new("Frame")
	fill.Name             = "Fill"
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.BorderSizePixel  = 0
	fill.ZIndex           = 13
	fill.Parent           = fillHolder
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)
	local gold = Instance.new("UIGradient", fill)
	gold.Color = ColorSequence.new(C.FillLow, C.FillHigh)

	local handle
	if hasArt(knobArt) then
		handle = Instance.new("ImageLabel")
		handle.BackgroundTransparency = 1
		handle.Size  = UDim2.fromOffset(KNOB_PX, KNOB_PX)
		handle.Image = knobArt.Image
	else
		handle = Instance.new("Frame")
		handle.Size             = UDim2.fromOffset(HANDLE_W, BAR_H - 10)
		handle.BackgroundColor3 = C.Handle
		handle.BorderSizePixel  = 0
		Instance.new("UICorner", handle).CornerRadius = UDim.new(0, 2)
	end
	handle.Name        = "Handle"
	handle.AnchorPoint = Vector2.new(0.5, 0.5)
	handle.ZIndex      = 14
	handle.Parent      = track

	local valueHex = C.Title:ToHex()
	local function render(t, value)
		fill.Size = UDim2.fromScale(t, 1)
		fill.Visible = t > 0.001
		handle.Position = UDim2.fromScale(t, 0.5)
		text.Text = ('%s  <font color="#%s">%s</font>'):format(label, valueHex, format(value))
	end
	render(invLerp(min, max, initValue), initValue)

	local dragging = false
	local function applyAt(absX)
		local width = track.AbsoluteSize.X
		if width <= 0 then return end
		local t = math.clamp((absX - track.AbsolutePosition.X) / width, 0, 1)
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
-- Audio page: one slider per sound bucket, built from RS/AudioCategories
----------------------------------------------------------------------

local mainGroup = SoundService:WaitForChild("Main")

local function liveMusicSound()
	return SoundService:FindFirstChild("ZoneMusic")
end

-- Per-track volume scale, stamped on the Sound by ZoneClient (see MusicPlayback).
-- Master and Music both write ZoneMusic.Volume directly, so both have to carry it
-- or moving a slider would silently flatten a track that is meant to sit louder
-- or quieter than the rest.
local function musicTrackScale(musicSound)
	return tonumber(musicSound:GetAttribute("TrackVolumeScale")) or 1
end

local function refreshMusic()
	local musicSound = liveMusicSound()
	if musicSound and musicSound.IsPlaying then
		musicSound.Volume = VolumeSettings.master * VolumeSettings.music * musicTrackScale(musicSound) * VolumeSettings.OUTPUT_GAIN
	end
end

-- Writes one bucket's volume to the engine. Master scales everything under Main via SoundGroup
-- nesting, plus the music (ZoneMusic lives outside Main); Music is the ZoneMusic Sound; every
-- other bucket is its own group under Main.
local function applyVolume(id, v)
	VolumeSettings[id] = v
	if id == "master" then
		mainGroup.Volume = v * VolumeSettings.OUTPUT_GAIN
		refreshMusic()
	elseif id == "music" then
		refreshMusic()
	else
		local group = AudioCategories.GetGroup(id)
		if group then group.Volume = v end
	end
end

-- Push the saved volumes onto the live SoundGroups once at startup.
--
-- Without this the ONLY writer was a slider's onChange, so every fresh session
-- played at whatever volume the place file's groups happen to carry, no matter
-- what the player had saved -- footsteps blasted at full volume until you
-- nudged the Movement slider, which is what "fixed" it (2026-09-17 report:
-- "3% is super loud, set it to 2% then back to 3% and it's fine").
for _, category in ipairs(AudioCategories.CATEGORIES) do
	if category.id ~= "music" then -- ZoneClient sets the music volume itself when a track starts
		applyVolume(category.id, VolumeSettings[category.id])
	end
end

for _, section in ipairs(AudioCategories.Sections()) do
	if section.title then addSectionTitle(audioTab, section.title) end
	for _, category in ipairs(section.items) do
		local range = SettingsRanges.volume[category.id]
		makeSlider(audioTab, category.label, VolumeSettings[category.id], {
			min = range.min,
			max = range.max,
			wide = category.wide,
			onChange = function(v) applyVolume(category.id, v) end,
			onCommit = persist("volume", category.id),
		})
	end
end

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

-- Crosshair on/off. It used to be a button in the HUD corner row; it lives here now. The
-- Crosshair script owns drawing it and listens to the "CrosshairEnabled" player attribute, so
-- this bar only has to flip the attribute and persist the value (missing = on).
local savedHud = SettingsStore.Get().hud
local crosshairOn = true
if type(savedHud) == "table" and tonumber(savedHud.crosshair) ~= nil then
	crosshairOn = tonumber(savedHud.crosshair) >= 0.5
end
player:SetAttribute("CrosshairEnabled", crosshairOn)

local crosshairBar, crosshairLabel = makeBar(videoTab.grid, "", true, { noPointer = true })
addToPage(videoTab, crosshairBar)
-- The name on the left and a tick box on the right (MenuUI.CHECKBOX), else "Crosshair: On".
local checkSheet = MenuUI.CHECKBOX
local checkBox
if hasArt(checkSheet) then
	crosshairLabel.AnchorPoint    = Vector2.new(0, 0.5)
	crosshairLabel.Position       = UDim2.new(0, 12, 0.5, 0)
	crosshairLabel.Size           = UDim2.new(1, -60, 1, -12)
	crosshairLabel.TextXAlignment = Enum.TextXAlignment.Left
	checkBox = Instance.new("ImageLabel")
	checkBox.Name                   = "Check"
	checkBox.BackgroundTransparency = 1
	checkBox.AnchorPoint            = Vector2.new(1, 0.5)
	checkBox.Position               = UDim2.new(1, -12, 0.5, 0)
	checkBox.Size                   = UDim2.fromOffset(22, 21)
	checkBox.Image                  = checkSheet.Image
	checkBox.ScaleType              = Enum.ScaleType.Fit
	checkBox.ZIndex                 = 14
	checkBox.Parent                 = crosshairBar
end
local function paintCrosshairBar()
	if checkBox then
		crosshairLabel.Text = "Crosshair"
		local cell = checkSheet.Rects[crosshairOn and "On" or "Off"]
		checkBox.ImageRectOffset = cell.Offset
		checkBox.ImageRectSize = cell.Size
	else
		crosshairLabel.Text = "Crosshair: " .. (crosshairOn and "On" or "Off")
	end
end
paintCrosshairBar()
crosshairBar.Activated:Connect(function()
	crosshairOn = not crosshairOn
	paintCrosshairBar()
	player:SetAttribute("CrosshairEnabled", crosshairOn)
	persist("hud", "crosshair")(crosshairOn and 1 or 0)
end)

----------------------------------------------------------------------
-- Controls page (2026-10-11): rebindable keys, the way PC games do it.
--   * One row per action (KeybindConfig.Actions), in sections, in a scrolling list. The key
--     slot on the right shows the CURRENT key(s) as key caps.
--   * Click a slot -> it listens ("Press a key"). The next key press is the new key. Esc,
--     clicking anywhere or pressing a mouse button cancels without changing anything.
--   * Conflicts are caught at once and explained in the status line under the title:
--       - the key belongs to another rebindable action in the same context -> "Swap / Cancel"
--         (Swap gives that action this one's old key)
--       - it belongs to a locked control (Move, Jump, Interact, Esc) -> refused
--       - a reserved key (Esc, /, `, F9, I/O ...) -> refused with the reason
--   * A changed row shows its label in gold and a Reset on its right (back to the default);
--     "Reset all" (top right) asks for a second click before it resets every key.
--   * Locked rows (engine / mouse controls) show a padlock instead of a slot.
--   * Every change applies at once (KeybindConfig.Set -> .Changed: HUD labels, hints and
--     ContextActionService binds follow) and saves (settings category "keys").
-- While a slot listens, a hidden TextBox holds focus: the game's own key handlers see every press
-- as processed (or skip it, ContextActionService), so the key you're binding doesn't also fire.
----------------------------------------------------------------------

local JournalUI = require(ImagesFolder:WaitForChild("JournalUI"))

local CONTROLS_VIEW_H = 380 -- the scrolling list's height
local CONTROL_H = 30
local CONTROL_KEY_H = 20
local SLOT_W = 150
local RESET_W = 46
local STATUS_H = 30
local LIST_GAP = 8
local HINT_TEXT = "Click a key to change it.  Esc cancels."
local GOOD = Color3.fromRGB(150, 196, 120)
local BAD = Color3.fromRGB(226, 120, 100)

controlsTab.grid:FindFirstChildWhichIsA("UIGridStyleLayout"):Destroy()
controlsTab.fixedHeight = STATUS_H + LIST_GAP + CONTROLS_VIEW_H

-- The status line: instructions, results, and the Swap / Cancel choice.
local statusBar = Instance.new("Frame")
statusBar.Name                   = "Status"
statusBar.BackgroundTransparency = 1
statusBar.Size                   = UDim2.new(1, 0, 0, STATUS_H)
statusBar.ZIndex                 = 11
statusBar.Parent                 = controlsTab.grid

local statusText = Instance.new("TextLabel")
statusText.Name                   = "Text"
statusText.BackgroundTransparency = 1
statusText.Size                   = UDim2.new(1, -130, 1, 0)
statusText.FontFace               = Font.new(UIFonts.Families.Body, Enum.FontWeight.Medium, Enum.FontStyle.Italic)
statusText.TextSize               = 13
statusText.TextColor3             = C.TextMuted
statusText.TextXAlignment         = Enum.TextXAlignment.Left
statusText.TextWrapped            = true
statusText.RichText               = true
statusText.ZIndex                 = 12
statusText.Parent                 = statusBar

-- Small plate buttons for the status line (Reset all, Swap, Cancel).
local function smallButton(text, width)
	local b, label = makeBar(statusBar, text, true, { noPointer = true, sliceScale = BAR_SLICE * 26 / BAR_H })
	b.Size = UDim2.fromOffset(width, 26)
	b.AnchorPoint = Vector2.new(1, 0.5)
	return b, label
end
local resetAllButton, resetAllLabel = smallButton("Reset all", 112)
resetAllButton.Position = UDim2.new(1, 0, 0.5, 0)
local cancelButton = smallButton("Cancel", 76)
cancelButton.Position = UDim2.new(1, 0, 0.5, 0)
local swapButton = smallButton("Swap", 76)
swapButton.Position = UDim2.new(1, -84, 0.5, 0)

local list = Instance.new("ScrollingFrame")
list.Name                   = "List"
list.BackgroundTransparency = 1
list.BorderSizePixel        = 0
list.Position               = UDim2.fromOffset(0, STATUS_H + LIST_GAP)
list.Size                   = UDim2.new(1, 0, 0, CONTROLS_VIEW_H)
list.CanvasSize             = UDim2.new()
list.AutomaticCanvasSize    = Enum.AutomaticSize.Y
list.ScrollingDirection     = Enum.ScrollingDirection.Y
list.ScrollBarThickness     = 5
list.ScrollBarImageColor3   = C.Title
list.ZIndex                 = 11
list.Parent                 = controlsTab.grid
do
	local layout = Instance.new("UIListLayout", list)
	layout.Padding   = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	local pad = Instance.new("UIPadding", list)
	pad.PaddingRight = UDim.new(0, 12)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 2), UDim.new(0, 6)
end

-- A section title inside the list: gold serif capitals and a faint rule.
local function listSection(text, order)
	local header = Instance.new("Frame")
	header.Name                   = "Section"
	header.BackgroundTransparency = 1
	header.Size                   = UDim2.new(1, 0, 0, HEADER_H + 4)
	header.LayoutOrder            = order
	header.ZIndex                 = 11
	header.Parent                 = list
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint            = Vector2.new(0, 1)
	label.Position               = UDim2.new(0, 2, 1, -2)
	label.Size                   = UDim2.new(0.6, 0, 0, 18)
	label.FontFace               = UIFonts.SerifBold
	label.TextSize               = 14
	label.TextColor3             = C.Title
	label.TextXAlignment         = Enum.TextXAlignment.Left
	label.Text                   = string.upper(text)
	label.ZIndex                 = 12
	label.Parent                 = header
	local rule = Instance.new("Frame")
	rule.BackgroundColor3       = C.PanelEdge
	rule.BackgroundTransparency = 0.3
	rule.BorderSizePixel        = 0
	rule.AnchorPoint            = Vector2.new(0, 1)
	rule.Position               = UDim2.new(0, 0, 1, 0)
	rule.Size                   = UDim2.new(1, 0, 0, 1)
	rule.ZIndex                 = 12
	rule.Parent                 = header
end

-- Fills a frame with key caps for a list of display names.
local function drawCaps(frame, names, dim)
	for _, old in ipairs(frame:GetChildren()) do
		if old.Name == "KeyCap" then old:Destroy() end
	end
	for i, name in ipairs(names) do
		local cap = QuickNav.KeyCap(frame, name, CONTROL_KEY_H)
		cap.LayoutOrder = i
		cap.ZIndex = 14
		cap.Face.ZIndex = 15
		if dim then
			if cap.Face:IsA("TextLabel") then cap.Face.TextTransparency = 0.35 end
			if cap.Face:IsA("ImageLabel") then cap.Face.ImageTransparency = 0.35 end
		end
	end
end

local rows = {} -- [actionId] = { entry, label, slot, caps, prompt, reset }
local capture = { id = nil, pending = nil, endedAt = 0 }
local refreshRow -- forward

-- Saves one action's key ("" = its default: the server drops the entry).
local function persistKey(id)
	local binding = Keys[id]
	local value = (not Keys.IsDefault(id) and typeof(binding) == "EnumItem") and binding.Name or ""
	evUpdateSettings:FireServer("keys", id, value)
end

local function keyText(keyCode)
	return "<b>" .. Keys.DisplayName(keyCode) .. "</b>"
end

local statusToken = 0
local function setStatus(text, colour, hold)
	statusToken += 1
	local token = statusToken
	statusText.Text = text
	statusText.TextColor3 = colour or C.TextMuted
	if hold then
		task.delay(hold, function()
			if statusToken == token and not capture.id then
				statusText.Text = HINT_TEXT
				statusText.TextColor3 = C.TextMuted
			end
		end)
	end
end

-- The status line's buttons: Reset all normally, Swap + Cancel while a conflict waits.
local resetArmedUntil = 0
local function paintStatusButtons()
	local choosing = capture.pending ~= nil
	resetAllButton.Visible = not choosing
	swapButton.Visible = choosing
	cancelButton.Visible = choosing
	local armed = os.clock() < resetArmedUntil
	resetAllLabel.Text = armed and "Confirm reset" or "Reset all"
	resetAllLabel.TextColor3 = armed and BAD or C.Text
end

-- The hidden TextBox that holds focus while a slot listens.
local captureBox = Instance.new("TextBox")
captureBox.Name                   = "KeyCapture"
captureBox.BackgroundTransparency = 1
captureBox.TextTransparency       = 1
captureBox.Size                   = UDim2.fromOffset(1, 1)
captureBox.Position               = UDim2.fromOffset(-10, -10)
captureBox.ClearTextOnFocus       = true
captureBox.Text                   = ""
captureBox.Parent                 = sg

local function endCapture()
	local id = capture.id
	capture.id = nil
	capture.endedAt = os.clock()
	if captureBox:IsFocused() then captureBox:ReleaseFocus() end
	if id and rows[id] then refreshRow(id) end
end

local function cancelCapture(message)
	capture.pending = nil
	endCapture()
	paintStatusButtons()
	if message then
		setStatus(message, BAD, 3)
	else
		setStatus(HINT_TEXT)
	end
end

local function startCapture(id)
	if capture.pending then return end
	if capture.id then endCapture() end
	capture.id = id
	local row = rows[id]
	drawCaps(row.caps, {})
	row.prompt.Visible = true
	row.slotEdge.Color = C.Title
	setStatus(("Press a key for <b>%s</b>.  Esc cancels."):format(row.entry.label), C.Title)
	captureBox.Text = ""
	captureBox:CaptureFocus()
end

local function applyKey(id, keyCode, note)
	Keys.Set(id, keyCode)
	persistKey(id)
	setStatus(note or ("%s is now %s."):format(rows[id].entry.label, keyText(keyCode)), GOOD, 3)
end

-- The pressed key, checked against everything else.
local function tryKey(keyCode)
	local id = capture.id
	if not id then return end
	if Keys.Matches(Keys[id], keyCode) then -- already this action's key: nothing to change
		endCapture()
		setStatus(HINT_TEXT)
		return
	end
	local ok, problem, other = Keys.Check(id, keyCode)
	if ok then
		endCapture()
		applyKey(id, keyCode)
		return
	end
	if problem == "conflict" then
		-- Hold the slot on the new key and ask.
		capture.pending = { id = id, key = keyCode, other = other }
		local row = rows[id]
		row.prompt.Visible = false
		drawCaps(row.caps, { Keys.DisplayName(keyCode) })
		row.slotEdge.Color = BAD
		capture.id = nil
		if captureBox:IsFocused() then captureBox:ReleaseFocus() end
		setStatus(("%s is already <b>%s</b>. Swap them?"):format(keyText(keyCode), other.label), C.Title)
		paintStatusButtons()
		return
	end
	if problem == "locked_conflict" then
		cancelCapture(("%s is %s, which can't be changed."):format(keyText(keyCode), other.label))
	elseif problem == "reserved" then
		cancelCapture(("%s %s, so it can't be bound."):format(keyText(keyCode), Keys.ReservedReason(keyCode)))
	else
		cancelCapture(("%s can't be bound."):format(keyText(keyCode)))
	end
end

swapButton.Activated:Connect(function()
	local pending = capture.pending
	if not pending then return end
	capture.pending = nil
	local oldKey = Keys[pending.id]
	if typeof(oldKey) == "table" then oldKey = oldKey[1] end
	-- Free the key first, so neither assignment sees the other as a clash.
	Keys.Set(pending.other.id, oldKey)
	Keys.Set(pending.id, pending.key)
	persistKey(pending.other.id)
	persistKey(pending.id)
	refreshRow(pending.id)
	paintStatusButtons()
	setStatus(("Swapped: %s is %s, %s is %s."):format(rows[pending.id].entry.label, keyText(pending.key),
		pending.other.label, keyText(oldKey)), GOOD, 4)
end)

cancelButton.Activated:Connect(function()
	local pending = capture.pending
	capture.pending = nil
	if pending then refreshRow(pending.id) end
	paintStatusButtons()
	setStatus(HINT_TEXT)
end)

resetAllButton.Activated:Connect(function()
	if os.clock() < resetArmedUntil then
		resetArmedUntil = 0
		for id in pairs(rows) do
			if not Keys.IsDefault(id) then
				evUpdateSettings:FireServer("keys", id, "")
			end
		end
		Keys.ResetAll()
		paintStatusButtons()
		setStatus("Every key is back to its default.", GOOD, 3)
	else
		resetArmedUntil = os.clock() + 3
		paintStatusButtons()
		setStatus("Click again to reset every key to its default.", BAD, 3)
		task.delay(3.05, paintStatusButtons)
	end
end)

UserInputService.InputBegan:Connect(function(input)
	if not capture.id then return end
	if input.UserInputType == Enum.UserInputType.Keyboard then
		if input.KeyCode == Enum.KeyCode.Escape then
			cancelCapture()
		elseif input.KeyCode ~= Enum.KeyCode.Unknown then
			tryKey(input.KeyCode)
		end
	elseif input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.MouseButton2
		or input.UserInputType == Enum.UserInputType.MouseButton3 then
		cancelCapture()
	end
end)
captureBox.FocusLost:Connect(function(enterPressed)
	if not capture.id then return end
	if enterPressed then
		tryKey(Enum.KeyCode.Return)
	else
		cancelCapture() -- Esc, or focus taken elsewhere
	end
end)

-- One row: the action, its key slot (or a padlock), and Reset when changed.
local function controlRow(entry, order)
	local bar = Instance.new("Frame")
	bar.Name            = entry.label
	bar.Size            = UDim2.new(1, 0, 0, CONTROL_H)
	bar.BorderSizePixel = 0
	bar.LayoutOrder     = order
	bar.ZIndex          = 11
	bar.Parent          = list
	paintPlate(bar, nil, BAR_SLICE * CONTROL_H / BAR_H)

	local label = Instance.new("TextLabel")
	label.Name                   = "Action"
	label.BackgroundTransparency = 1
	label.Position               = UDim2.fromOffset(12, 0)
	label.Size                   = UDim2.new(1, -(SLOT_W + RESET_W + 30), 1, 0)
	label.FontFace               = UIFonts.SerifBold
	label.TextSize               = 14
	label.TextColor3             = C.Text
	label.TextXAlignment         = Enum.TextXAlignment.Left
	label.TextTruncate           = Enum.TextTruncate.AtEnd
	label.Text                   = entry.label
	label.ZIndex                 = 12
	label.Parent                 = bar

	-- The slot: a dark inset holding the key caps; a button unless the row is locked.
	local slot = Instance.new(entry.fixed and "Frame" or "TextButton")
	slot.Name                   = "Slot"
	slot.AnchorPoint            = Vector2.new(1, 0.5)
	slot.Position               = UDim2.new(1, -(RESET_W + 10), 0.5, 0)
	slot.Size                   = UDim2.fromOffset(SLOT_W, CONTROL_H - 6)
	slot.BackgroundColor3       = C.Panel
	slot.BackgroundTransparency = entry.fixed and 0.7 or 0.25
	slot.BorderSizePixel        = 0
	slot.ZIndex                 = 12
	if not entry.fixed then
		slot.AutoButtonColor = false
		slot.Text = ""
	end
	slot.Parent = bar
	Instance.new("UICorner", slot).CornerRadius = UDim.new(0, 4)
	local slotEdge = Instance.new("UIStroke", slot)
	slotEdge.Color = C.BarEdge
	slotEdge.Thickness = 1
	slotEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	slotEdge.Transparency = entry.fixed and 0.6 or 0

	local caps = Instance.new("Frame")
	caps.Name                   = "Caps"
	caps.BackgroundTransparency = 1
	caps.Size                   = UDim2.fromScale(1, 1)
	caps.ZIndex                 = 13
	caps.Parent                 = slot
	local capsLayout = Instance.new("UIListLayout", caps)
	capsLayout.FillDirection       = Enum.FillDirection.Horizontal
	capsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	capsLayout.VerticalAlignment   = Enum.VerticalAlignment.Center
	capsLayout.SortOrder           = Enum.SortOrder.LayoutOrder
	capsLayout.Padding             = UDim.new(0, 3)

	if entry.fixed then
		drawCaps(caps, entry.show, true)
		local lockArt = JournalUI.lock_icon
		if type(lockArt) == "table" and lockArt.Image ~= "" then
			local lock = Instance.new("ImageLabel")
			lock.Name                   = "Locked"
			lock.BackgroundTransparency = 1
			lock.AnchorPoint            = Vector2.new(0.5, 0.5)
			lock.Position               = UDim2.new(1, -(RESET_W / 2 + 4), 0.5, 0)
			lock.Size                   = UDim2.fromOffset(13, 16)
			lock.Image                  = lockArt.Image
			lock.ImageTransparency      = 0.35
			lock.ScaleType              = Enum.ScaleType.Fit
			lock.ZIndex                 = 13
			lock.Parent                 = bar
		end
		return
	end

	local prompt = Instance.new("TextLabel")
	prompt.Name                   = "Prompt"
	prompt.BackgroundTransparency = 1
	prompt.Size                   = UDim2.fromScale(1, 1)
	prompt.FontFace               = Font.new(UIFonts.Families.Body, Enum.FontWeight.SemiBold, Enum.FontStyle.Italic)
	prompt.TextSize               = 13
	prompt.TextColor3             = C.Title
	prompt.Text                   = "Press a key"
	prompt.Visible                = false
	prompt.ZIndex                 = 14
	prompt.Parent                 = slot

	local reset = Instance.new("TextButton")
	reset.Name                   = "Reset"
	reset.AnchorPoint            = Vector2.new(1, 0.5)
	reset.Position               = UDim2.new(1, -6, 0.5, 0)
	reset.Size                   = UDim2.fromOffset(RESET_W, CONTROL_H - 8)
	reset.BackgroundTransparency = 1
	reset.AutoButtonColor        = false
	reset.FontFace               = UIFonts.SerifBold
	reset.TextSize               = 12
	reset.TextColor3             = C.TextMuted
	reset.Text                   = "Reset"
	reset.ZIndex                 = 13
	reset.Parent                 = bar
	reset.MouseEnter:Connect(function() reset.TextColor3 = C.Title end)
	reset.MouseLeave:Connect(function() reset.TextColor3 = C.TextMuted end)

	slot.MouseEnter:Connect(function()
		if capture.id ~= entry.id and not capture.pending then slotEdge.Color = C.BarEdgeHover end
	end)
	slot.MouseLeave:Connect(function()
		if capture.id ~= entry.id and not capture.pending then slotEdge.Color = C.BarEdge end
	end)
	slot.Activated:Connect(function()
		if capture.id == entry.id then return end
		startCapture(entry.id)
	end)
	reset.Activated:Connect(function()
		if capture.pending then return end
		if capture.id then endCapture() end
		Keys.Reset(entry.id)
		persistKey(entry.id)
		setStatus(("%s is back to %s."):format(entry.label, keyText(Keys[entry.id])), GOOD, 3)
	end)

	rows[entry.id] = { entry = entry, label = label, slot = slot, slotEdge = slotEdge, caps = caps, prompt = prompt, reset = reset }
	refreshRow(entry.id)
end

function refreshRow(id)
	local row = rows[id]
	if not row then return end
	local changed = not Keys.IsDefault(id)
	row.prompt.Visible = false
	drawCaps(row.caps, Keys.DisplayNames(Keys[id]))
	row.slotEdge.Color = C.BarEdge
	row.label.TextColor3 = changed and C.Title or C.Text
	row.reset.Visible = changed
end

do
	local order = 0
	for _, entry in ipairs(Keys.Actions) do
		order += 1
		if entry.section then
			listSection(entry.section, order)
		else
			controlRow(entry, order)
		end
	end
end
setStatus(HINT_TEXT)
paintStatusButtons()

-- Keys changed (the saved ones landing at join, a reset, a swap): redraw every row.
Keys.Changed:Connect(function()
	for id in pairs(rows) do
		if id ~= capture.id and not (capture.pending and capture.pending.id == id) then refreshRow(id) end
	end
end)

-- Leaving the page (Done / Esc / closing Settings) drops a capture or an open question.
controlsTab.onLeave = function()
	if capture.id or capture.pending then
		if capture.pending then refreshRow(capture.pending.id) end
		capture.pending = nil
		endCapture()
		paintStatusButtons()
		setStatus(HINT_TEXT)
	end
end
controlsTab.isBusy = function()
	return capture.id ~= nil or os.clock() - capture.endedAt < 0.25
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
		panelScale.Scale = panelFit * 0.96
		TweenService:Create(backdrop, openTI, { BackgroundTransparency = DIM_TRANSPARENCY }):Play()
		TweenService:Create(panelScale, openTI, { Scale = panelFit }):Play()
	else
		if currentPage and currentPage.onLeave then currentPage.onLeave() end
		TweenService:Create(backdrop, closeTI, { BackgroundTransparency = 1 }):Play()
		local shrink = TweenService:Create(panelScale, closeTI, { Scale = panelFit * 0.96 })
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
	-- Esc while a Controls slot listens (or just stopped) only cancels that, not the page.
	local busy = currentPage and currentPage.isBusy and currentPage.isBusy()
	if panelOpen and input.KeyCode == Keys.CloseMenu and not busy then done() end
end)

-- A blocking overlay opened on top: close.
InteractionLock.Subscribe(function(locked)
	if locked and panelOpen then setPanelOpen(false) end
end)
