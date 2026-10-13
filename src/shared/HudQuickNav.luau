--[[
	HudQuickNav (client-only; lives in RS so every client script shares one copy)

	The row of small quick-access buttons at the top right, hanging under the minimap and lined up
	with its RIGHT edge (so a long row grows leftwards and can never run off the screen corner).
	New buttons join on the RIGHT of the row, in ORDER.

		Button(opts) -> TextButton     the one way to make a row button (shared plate, hover, press,
		                               tooltip, optional key badge); parents itself into its slot
			opts.name       string     instance name (also the slot name unless opts.slot is set)
			opts.slot       string?    slot name, when it should differ from the button's name
			opts.order      number     ORDER.* (lower = further left)
			opts.tooltip    string     hover label ("Settings")
			opts.key        string?    key badge on the plate corner ("Tab"); also shown in the tooltip
			opts.image      string?    rbxassetid:// icon (RS/Assets/Images/JournalUI art works as-is)
			opts.iconSize   number?    icon size in px (default 22)
			opts.tint       Color3?    icon tint
			opts.content    Content?   or an EditableImage content, for icons drawn in code
			opts.text       string?    fallback text when there is no icon
			opts.onActivated function? click handler
		Adopt(button)                  restyle a button some other script parented into a slot, so it
		                               matches the rest of the row (runs automatically for every slot)
		Slot(name, order) -> Frame     lower order = further left; Button() calls this for you
		FollowBelow(frame)             hang the row under `frame` (the minimap does this);
		                               while that frame is hidden (dungeons), the row moves up
		                               to the top of the screen instead of leaving a gap
		BUTTON_SIZE                    the square size every button here uses (before SCALE)
		SCALE                          the whole row is drawn this much bigger (a UIScale), so
		                               buttons keep authoring in BUTTON_SIZE units
		Tooltip(button, text, key?)    a small label under the button while hovered
		STYLE                          the palette, shared with the minimap frame
		PaintPlate(frame)              the plate look, for other HUD pieces that should match the row
		KeyCap(parent, text, height?)  a keyboard key drawn as a little bronze key ("M", "Tab", "Esc"):
		                               the one way a keybind is shown (tooltips, the map's hints);
		                               "Click" / "Right click" / "Scroll" / "Drag" draw the mouse
		                               icon instead (MenuUI.MOUSE_ICONS)

	Keybinds are NOT stamped on the buttons (2026-10-11: a badge on one button and not the
	others read as noise). A button's key shows in its hover tooltip as a KeyCap; the full list
	is the Settings > Controls page.

	ORDER.Settings = 10        (the settings gear, SettingsClient)
	ORDER.CursorLock = 25      (re-lock a stuck cursor, client/CursorLockButton)
	ORDER.Inventory / Journal / Hearthstone = 30 / 40 / 50 (client/MenuShortcuts)
	The crosshair toggle used to be ORDER 20; it now lives on the Settings Video page.

	A slot sizes itself to its content (AutomaticSize), so owners just parent a button into it.
	DisplayOrder sits just above SettingsGui's click-away backdrop (250), so the gear stays
	clickable while its own panel is open.

]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local MapUI = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images"):WaitForChild("MapUI"))
local MenuUI = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images"):WaitForChild("MenuUI"))
local Keys = require(ReplicatedStorage:WaitForChild("KeybindConfig"))

local QuickNav = {}

QuickNav.ORDER = {
	Settings = 10,
	CursorLock = 25,  -- re-lock a stuck cursor (client/CursorLockButton)
	-- The Tab menu's destinations, one tap each (MenuShortcuts; mostly for touch players).
	Inventory = 30,
	Journal = 40,
	Hearthstone = 50,
}

QuickNav.MARGIN = 8       -- from the screen's top/right edges when nothing to follow
QuickNav.GAP = 14         -- under the followed frame (clears the minimap's ring and key badge)
QuickNav.PADDING = 5      -- between buttons
QuickNav.BUTTON_SIZE = 30
QuickNav.SCALE = 1.3      -- 2026-10-06: the row grew 30% with the minimap

-- Warm bronze on near-black: the same family the Settings screen and the inventory use.
QuickNav.STYLE = {
	PlateTop = Color3.fromRGB(38, 32, 25),
	PlateBottom = Color3.fromRGB(15, 13, 11),
	Edge = Color3.fromRGB(112, 90, 56),
	EdgeHover = Color3.fromRGB(226, 186, 112),
	EdgeDark = Color3.fromRGB(8, 6, 6),
	Bevel = Color3.fromRGB(255, 232, 186),
	Text = Color3.fromRGB(236, 226, 208),
	Muted = Color3.fromRGB(150, 138, 120),
}
local S = QuickNav.STYLE

local ICON_SIZE = 22
local HOVER_TI = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local gui, container, followConns
local tip, hovered -- the shared tooltip and the button it's showing for (QuickNav.Tooltip)

local function fonts()
	return require(ReplicatedStorage:WaitForChild("UIFonts"))
end

local function ensure()
	if container and container.Parent then return container end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = Instance.new("ScreenGui")
	gui.Name = "HudQuickNav"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 251
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	-- Hidden behind a menu (HudHider turns Enabled off): no tooltip may outlive it.
	gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not gui.Enabled then
			hovered = nil
			if tip then tip.Visible = false end
		end
	end)

	container = Instance.new("Frame")
	container.Name = "Row"
	container.AnchorPoint = Vector2.new(1, 0)
	container.Position = UDim2.new(1, -QuickNav.MARGIN, 0, QuickNav.MARGIN)
	container.Size = UDim2.fromOffset(0, 0)
	container.AutomaticSize = Enum.AutomaticSize.XY
	container.BackgroundTransparency = 1
	container.Parent = gui

	local scale = Instance.new("UIScale")
	scale.Scale = QuickNav.SCALE
	scale.Parent = container

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, QuickNav.PADDING)
	layout.Parent = container
	return container
end

-------------------------------------------------------------------------------------------------
-- Plate + key badge (shared by Button and Adopt)

-- The plate is the painted tile (MapUI.BUTTON_PLATE, 2026-10-11: dark wood, gold rim, a leaf and
-- flower top left), laid so its face fills the button and the sprig sticks out past it. Without
-- the art: the old gradient, bronze edge and bevel. Either way it returns what hover lights up
-- (the plate image, or the edge UIStroke).
local PLATE = MapUI.BUTTON_PLATE
local PLATE_IDLE = Color3.fromRGB(222, 222, 222) -- dimmed a touch, so hover can brighten it
local PLATE_HOVER = Color3.new(1, 1, 1)

local function paintPlate(button)
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.Size = UDim2.fromOffset(QuickNav.BUTTON_SIZE, QuickNav.BUTTON_SIZE)

	for _, old in ipairs(button:GetChildren()) do
		if old:IsA("UIStroke") or old:IsA("UICorner") or old:IsA("UIGradient")
			or old.Name == "Plate" or old.Name == "Bevel" then
			old:Destroy()
		end
	end

	if PLATE and PLATE.Image ~= "" then
		button.BackgroundTransparency = 1
		local body = PLATE.Body
		local bodyW, bodyH = body.X1 - body.X0, body.Y1 - body.Y0
		local plate = Instance.new("ImageLabel")
		plate.Name = "Plate"
		plate.Image = PLATE.Image
		plate.ImageColor3 = PLATE_IDLE
		plate.BackgroundTransparency = 1
		plate.Size = UDim2.fromScale(PLATE.Size.X / bodyW, PLATE.Size.Y / bodyH)
		plate.Position = UDim2.fromScale(-body.X0 / bodyW, -body.Y0 / bodyH)
		plate.ZIndex = button.ZIndex
		plate.Parent = button
		return plate
	end

	button.BackgroundColor3 = Color3.new(1, 1, 1) -- the gradient supplies the colour
	button.BackgroundTransparency = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 7)
	corner.Parent = button

	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(S.PlateTop, S.PlateBottom)
	gradient.Parent = button

	local edge = Instance.new("UIStroke")
	edge.Name = "Edge"
	edge.Color = S.Edge
	edge.Thickness = 1.5
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = button

	-- A faint inner bevel line, so the plate reads as a raised tile instead of a flat square.
	local bevel = Instance.new("Frame")
	bevel.Name = "Bevel"
	bevel.AnchorPoint = Vector2.new(0.5, 0.5)
	bevel.Position = UDim2.fromScale(0.5, 0.5)
	bevel.Size = UDim2.new(1, -5, 1, -5)
	bevel.BackgroundTransparency = 1
	bevel.ZIndex = button.ZIndex
	bevel.Parent = button
	local bevelCorner = Instance.new("UICorner")
	bevelCorner.CornerRadius = UDim.new(0, 5)
	bevelCorner.Parent = bevel
	local bevelStroke = Instance.new("UIStroke")
	bevelStroke.Color = S.Bevel
	bevelStroke.Transparency = 0.9
	bevelStroke.Thickness = 1
	bevelStroke.Parent = bevel

	return edge
end

-- What hover tweens on paintPlate's result.
local function hoverGoal(lit, on)
	if lit:IsA("UIStroke") then
		return { Color = on and S.EdgeHover or S.Edge }
	end
	return { ImageColor3 = on and PLATE_HOVER or PLATE_IDLE }
end

-- A keyboard key: a cream face standing on a darker bronze base that shows as a lip along the
-- bottom, a dark outline, the key's name in dark ink. Grows sideways with its text ("Tab",
-- "Scroll"), never narrower than it is tall. `height` in px (default 20).
local KEY_FACE = Color3.fromRGB(236, 222, 186)
local KEY_BASE = Color3.fromRGB(122, 98, 62)
local KEY_INK = Color3.fromRGB(43, 30, 20)
local KEY_OUTLINE = Color3.fromRGB(26, 18, 12)

-- Mouse inputs are drawn as the mouse icons (MenuUI.MOUSE_ICONS), not as a key with a word on it.
local MOUSE_CELLS = {
	Click = "Left", ["Left click"] = "Left", ["Right click"] = "Right", Scroll = "Scroll", Drag = "Drag",
}

local function makeMouseCap(parent, cellName, height)
	local cell = MenuUI.MOUSE_ICONS.Rects[cellName]
	local cap = Instance.new("Frame")
	cap.Name = "KeyCap"
	cap.BackgroundTransparency = 1
	cap.Size = UDim2.fromOffset(math.floor(height * cell.Size.X / cell.Size.Y + .5), height)
	local face = Instance.new("ImageLabel")
	face.Name = "Face" -- same child name as a key cap's, so callers can treat both alike
	face.BackgroundTransparency = 1
	face.Size = UDim2.fromScale(1, 1)
	face.Image = MenuUI.MOUSE_ICONS.Image
	face.ImageRectOffset = cell.Offset
	face.ImageRectSize = cell.Size
	face.ScaleType = Enum.ScaleType.Fit
	face.Parent = cap
	cap.Parent = parent
	return cap
end

local function makeKeyCap(parent, text, height)
	height = height or 20
	local mouse = MOUSE_CELLS[text]
	if mouse and MenuUI.MOUSE_ICONS.Image ~= "" then
		return makeMouseCap(parent, mouse, height + 2)
	end
	local lip = math.max(2, math.floor(height * .16 + .5))
	local cap = Instance.new("Frame")
	cap.Name = "KeyCap"
	cap.Size = UDim2.fromOffset(0, height)
	cap.AutomaticSize = Enum.AutomaticSize.X
	cap.BackgroundColor3 = KEY_BASE
	cap.BorderSizePixel = 0
	Instance.new("UICorner", cap).CornerRadius = UDim.new(0, 4)
	local outline = Instance.new("UIStroke", cap)
	outline.Color = KEY_OUTLINE
	outline.Thickness = 1
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

	local face = Instance.new("TextLabel")
	face.Name = "Face"
	face.Size = UDim2.fromOffset(0, height - lip)
	face.AutomaticSize = Enum.AutomaticSize.X
	face.BackgroundColor3 = KEY_FACE
	face.BorderSizePixel = 0
	face.FontFace = fonts().BodyBold
	face.TextSize = math.max(9, math.floor(height * .55))
	face.TextColor3 = KEY_INK
	face.Text = text
	face.Parent = cap
	Instance.new("UICorner", face).CornerRadius = UDim.new(0, 3)
	local pad = Instance.new("UIPadding", face)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 5), UDim.new(0, 5)
	local minSize = Instance.new("UISizeConstraint", face)
	minSize.MinSize = Vector2.new(height, 0)

	cap.Parent = parent
	return cap
end

-- A binding's (first) key as shown on a key cap: KeybindConfig.DisplayName ("Esc", "Del", "Ctrl").
-- A string passes through, unless it names a rebindable action ("SkillsTab"): then that
-- action's CURRENT key, so a tooltip follows a rebind.
function QuickNav.KeyName(binding)
	if type(binding) == "string" then
		return Keys.IsRebindable(binding) and Keys.DisplayName(Keys[binding]) or binding
	end
	return Keys.DisplayName(binding)
end

-- Hover brightens the edge and pops the icon; pressing sinks it. Only the icon scales, never the
-- button, so the row does not reflow under the cursor.
local function wireStates(button, edge, iconScale)
	button.MouseEnter:Connect(function()
		TweenService:Create(edge, HOVER_TI, hoverGoal(edge, true)):Play()
		if iconScale then TweenService:Create(iconScale, HOVER_TI, { Scale = 1.14 }):Play() end
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(edge, HOVER_TI, hoverGoal(edge, false)):Play()
		if iconScale then TweenService:Create(iconScale, HOVER_TI, { Scale = 1 }):Play() end
	end)
	button.MouseButton1Down:Connect(function()
		if iconScale then TweenService:Create(iconScale, HOVER_TI, { Scale = 0.9 }):Play() end
	end)
	button.MouseButton1Up:Connect(function()
		if iconScale then TweenService:Create(iconScale, HOVER_TI, { Scale = 1.14 }):Play() end
	end)
end

-- The shared plate look (gradient, bronze edge, bevel) and key badge, for other HUD pieces that
-- should match this row. PaintPlate returns what hover lights up (the plate image, or the
-- fallback's edge UIStroke).
function QuickNav.PaintPlate(frame)
	return paintPlate(frame)
end
function QuickNav.KeyCap(parent, text, height)
	return makeKeyCap(parent, text, height)
end

function QuickNav.Slot(name, order)
	local parent = ensure()
	local slot = parent:FindFirstChild(name)
	if slot then return slot end
	slot = Instance.new("Frame")
	slot.Name = name
	slot.LayoutOrder = order or 0
	slot.Size = UDim2.fromOffset(0, 0)
	slot.AutomaticSize = Enum.AutomaticSize.XY
	slot.BackgroundTransparency = 1
	slot.Parent = parent
	-- Buttons other scripts drop into a slot get the shared look automatically.
	slot.ChildAdded:Connect(function(child)
		if child:IsA("GuiButton") then task.defer(QuickNav.Adopt, child) end
	end)
	return slot
end

function QuickNav.Button(opts)
	local button = Instance.new("TextButton")
	button.Name = opts.name or "QuickNavButton"
	button.Text = ""
	button.ZIndex = 10
	button:SetAttribute("QuickNavStyled", true)
	local edge = paintPlate(button)

	local iconScale = Instance.new("UIScale")
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromOffset(opts.iconSize or ICON_SIZE, opts.iconSize or ICON_SIZE)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = 11
	if opts.tint then icon.ImageColor3 = opts.tint end
	if opts.content then
		icon.ImageContent = opts.content
	elseif opts.image then
		icon.Image = opts.image
	elseif opts.text then
		button.Text = opts.text
		button.FontFace = fonts().BodyBold
		button.TextSize = 12
		button.TextColor3 = S.Text
	end
	iconScale.Parent = icon
	icon.Parent = button

	wireStates(button, edge, iconScale)
	if opts.tooltip then QuickNav.Tooltip(button, opts.tooltip, opts.key) end
	if opts.onActivated then button.Activated:Connect(opts.onActivated) end

	button.Parent = QuickNav.Slot(opts.slot or button.Name, opts.order)
	return button
end

-- Restyles a button some other script put into a slot. Any short loose label next to or inside
-- it (an old "Tab" hint) is removed: keys show in tooltips, not on the buttons.
function QuickNav.Adopt(button)
	if not button.Parent or button:GetAttribute("QuickNavStyled") then return end
	button:SetAttribute("QuickNavStyled", true)
	local function absorb(label)
		if label:IsA("TextLabel") and #label.Text > 0 and #label.Text <= 5 then
			label:Destroy()
		end
	end
	for _, child in ipairs(button:GetChildren()) do absorb(child) end
	if button.Parent then
		for _, sibling in ipairs(button.Parent:GetChildren()) do
			if sibling ~= button then absorb(sibling) end
		end
	end

	local edge = paintPlate(button)
	local iconScale
	local icon = button:FindFirstChildWhichIsA("ImageLabel", true) or button:FindFirstChildWhichIsA("ImageButton", true)
	if icon then
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale(0.5, 0.5)
		icon.Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
		icon.BackgroundTransparency = 1
		icon.ScaleType = Enum.ScaleType.Fit
		icon.ZIndex = math.max(icon.ZIndex, 11, button.ZIndex + 1)
		iconScale = icon:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", icon)
	end
	wireStates(button, edge, iconScale)
end

-- Hangs the row under `frame`'s bottom-RIGHT corner. `frame` must sit directly in a full-screen
-- ScreenGui that ignores the inset (like this one), so its own Position/Size/AnchorPoint ARE
-- screen coordinates here too. Uses those layout values, not AbsolutePosition: the minimap starts
-- hidden, and reading absolute pixels at that moment (before layout) put the row inside the map.
function QuickNav.FollowBelow(frame)
	local row = ensure()
	if followConns then
		for _, c in ipairs(followConns) do c:Disconnect() end
	end
	local function place()
		local pos, size, anchor = frame.Position, frame.Size, frame.AnchorPoint
		local rightScale = pos.X.Scale + (1 - anchor.X) * size.X.Scale
		local rightOffset = pos.X.Offset + (1 - anchor.X) * size.X.Offset
		local bottomScale = pos.Y.Scale + (1 - anchor.Y) * size.Y.Scale
		local bottomOffset = pos.Y.Offset + (1 - anchor.Y) * size.Y.Offset
		row.AnchorPoint = Vector2.new(1, 0)
		if frame.Visible then
			row.Position = UDim2.new(rightScale, rightOffset, bottomScale, bottomOffset + QuickNav.GAP)
		else
			row.Position = UDim2.new(rightScale, rightOffset, 0, QuickNav.MARGIN)
		end
	end
	followConns = {}
	for _, prop in ipairs({ "Position", "Size", "AnchorPoint", "Visible" }) do
		table.insert(followConns, frame:GetPropertyChangedSignal(prop):Connect(place))
	end
	place()
end

-- One shared hover label for the whole row. It lives in this ScreenGui (not inside the button:
-- slots size themselves to their content, so a child hanging below would reflow the row) and is
-- placed from the hovered button's AbsolutePosition, which is screen space here (IgnoreGuiInset).

local tipText, tipKey

local function ensureTip()
	if tip and tip.Parent then return tip end
	ensure()
	tip = Instance.new("Frame")
	tip.Name = "Tooltip"
	tip.AnchorPoint = Vector2.new(0.5, 0)
	tip.AutomaticSize = Enum.AutomaticSize.X
	tip.Size = UDim2.fromOffset(0, math.round(26 * QuickNav.SCALE))
	tip.BackgroundTransparency = 1
	tip.Visible = false
	tip.ZIndex = 20
	tip.Parent = gui
	-- The backing: the map's small dark panel (MapUI.PANEL, 9-slice), else a plain dark plate.
	local panel = MapUI.PANEL
	local back = Instance.new("ImageLabel")
	back.Name = "Back"
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundTransparency = 1
	back.ZIndex = 20
	if panel and panel.Image ~= "" then
		back.Image = panel.Image
		back.ScaleType = Enum.ScaleType.Slice
		back.SliceCenter = panel.SliceCenter
		back.SliceScale = .1
	else
		back.BackgroundColor3 = Color3.fromRGB(14, 13, 16)
		back.BackgroundTransparency = 0.08
		Instance.new("UICorner", back).CornerRadius = UDim.new(0, 5)
		local edge = Instance.new("UIStroke", back)
		edge.Color = S.Edge
	end
	back.Parent = tip
	-- The text and key in their own row, so the backing isn't laid out with them.
	local row = Instance.new("Frame")
	row.Name = "Row"
	row.AutomaticSize = Enum.AutomaticSize.X
	row.Size = UDim2.fromScale(0, 1)
	row.BackgroundTransparency = 1
	row.ZIndex = 21
	row.Parent = tip
	local layout = Instance.new("UIListLayout", row)
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 7)
	local pad = Instance.new("UIPadding", row)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 11), UDim.new(0, 9)
	tipText = Instance.new("TextLabel")
	tipText.Name = "Text"
	tipText.AutomaticSize = Enum.AutomaticSize.X
	tipText.Size = UDim2.fromScale(0, 1)
	tipText.BackgroundTransparency = 1
	tipText.FontFace = fonts().BodyBold
	tipText.TextSize = math.round(13 * QuickNav.SCALE)
	tipText.TextColor3 = S.Text
	tipText.LayoutOrder = 1
	tipText.ZIndex = 22
	tipText.Parent = row
	tipKey = makeKeyCap(row, "", math.round(17 * QuickNav.SCALE))
	tipKey.LayoutOrder = 2
	tipKey.ZIndex = 22
	tipKey.Face.ZIndex = 23
	return tip
end

-- Shows the shared tooltip under (or, `above`, over) a screen rectangle. `key` = a keybind
-- (EnumItem or list), an action id ("SkillsTab": its current key) or a ready name; nil = none.
function QuickNav.ShowTip(text, key, absPos, absSize, above)
	local label = ensureTip()
	tipText.Text = text
	tipKey.Visible = key ~= nil
	if key ~= nil then
		tipKey.Face.Text = QuickNav.KeyName(key)
	end
	local screenW = gui.AbsoluteSize.X
	-- Centred on the rectangle, kept on screen at the right edge.
	local x = math.min(absPos.X + absSize.X / 2, screenW - label.AbsoluteSize.X / 2 - QuickNav.MARGIN)
	if above then
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.Position = UDim2.fromOffset(x, absPos.Y - 8)
	else
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.fromOffset(x, absPos.Y + absSize.Y + 8)
	end
	label.Visible = true
end

function QuickNav.HideTip()
	if tip then tip.Visible = false end
end

-- MouseLeave alone isn't enough: a click that opens a menu hides this row (HudHider) or covers
-- it, and the button never sees the mouse leave, so the tip stayed on screen after the menu
-- closed. A click, the row going hidden, or the button going away all drop it too.
function QuickNav.Tooltip(button, text, key)
	local function drop()
		if hovered == button then
			hovered = nil
			QuickNav.HideTip()
		end
	end
	button.MouseEnter:Connect(function()
		if gui and not gui.Enabled then return end
		hovered = button
		QuickNav.ShowTip(text, key, button.AbsolutePosition, button.AbsoluteSize)
	end)
	button.MouseLeave:Connect(drop)
	button.Activated:Connect(drop)
	button:GetPropertyChangedSignal("Visible"):Connect(drop)
	button.AncestryChanged:Connect(drop)
end

return QuickNav
