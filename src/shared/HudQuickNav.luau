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

local function paintPlate(button)
	button.AutoButtonColor = false
	button.BackgroundColor3 = Color3.new(1, 1, 1) -- the gradient supplies the colour
	button.BackgroundTransparency = 0
	button.BorderSizePixel = 0
	button.Size = UDim2.fromOffset(QuickNav.BUTTON_SIZE, QuickNav.BUTTON_SIZE)

	for _, old in ipairs(button:GetChildren()) do
		if old:IsA("UIStroke") or old:IsA("UICorner") or old:IsA("UIGradient") then old:Destroy() end
	end

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
	local old = button:FindFirstChild("Bevel")
	if old then old:Destroy() end
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

local function makeKeyBadge(button, text)
	local old = button:FindFirstChild("KeyBadge")
	if old then old:Destroy() end
	local badge = Instance.new("TextLabel")
	badge.Name = "KeyBadge"
	badge.AnchorPoint = Vector2.new(1, 1)
	badge.Position = UDim2.new(1, 3, 1, 3)
	badge.Size = UDim2.fromOffset(0, 13)
	badge.AutomaticSize = Enum.AutomaticSize.X
	badge.BackgroundColor3 = Color3.fromRGB(10, 9, 8)
	badge.BackgroundTransparency = 0.05
	badge.BorderSizePixel = 0
	badge.FontFace = fonts().BodyBold
	badge.TextSize = 9
	badge.TextColor3 = S.Text
	badge.Text = string.upper(text)
	badge.ZIndex = button.ZIndex + 5
	badge.Parent = button
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 3)
	corner.Parent = badge
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 4), UDim.new(0, 4)
	pad.Parent = badge
	local stroke = Instance.new("UIStroke")
	stroke.Color = S.Edge
	stroke.Thickness = 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = badge
	return badge
end

-- Hover brightens the edge and pops the icon; pressing sinks it. Only the icon scales, never the
-- button, so the row does not reflow under the cursor.
local function wireStates(button, edge, iconScale)
	button.MouseEnter:Connect(function()
		TweenService:Create(edge, HOVER_TI, { Color = S.EdgeHover }):Play()
		if iconScale then TweenService:Create(iconScale, HOVER_TI, { Scale = 1.14 }):Play() end
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(edge, HOVER_TI, { Color = S.Edge }):Play()
		if iconScale then TweenService:Create(iconScale, HOVER_TI, { Scale = 1 }):Play() end
	end)
	button.MouseButton1Down:Connect(function()
		if iconScale then TweenService:Create(iconScale, HOVER_TI, { Scale = 0.9 }):Play() end
	end)
	button.MouseButton1Up:Connect(function()
		if iconScale then TweenService:Create(iconScale, HOVER_TI, { Scale = 1.14 }):Play() end
	end)
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

	if opts.key then makeKeyBadge(button, opts.key) end
	wireStates(button, edge, iconScale)
	if opts.tooltip then QuickNav.Tooltip(button, opts.tooltip, opts.key) end
	if opts.onActivated then button.Activated:Connect(opts.onActivated) end

	button.Parent = QuickNav.Slot(opts.slot or button.Name, opts.order)
	return button
end

-- Restyles a button some other script put into a slot. Any short loose label next to or inside
-- it (an old "Tab" hint) is folded into the standard key badge so it matches the rest of the row.
function QuickNav.Adopt(button)
	if not button.Parent or button:GetAttribute("QuickNavStyled") then return end
	button:SetAttribute("QuickNavStyled", true)
	local keyText
	local function absorb(label)
		if label:IsA("TextLabel") and label.Name ~= "KeyBadge" and #label.Text > 0 and #label.Text <= 5 then
			keyText = keyText or label.Text
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
		icon.ZIndex = math.max(icon.ZIndex, 11)
		iconScale = icon:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", icon)
	end
	if keyText then makeKeyBadge(button, keyText) end
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
local tip
local hovered

local function ensureTip()
	if tip and tip.Parent then return tip end
	ensure()
	tip = Instance.new("TextLabel")
	tip.Name = "Tooltip"
	tip.AnchorPoint = Vector2.new(0.5, 0)
	tip.AutomaticSize = Enum.AutomaticSize.XY
	tip.Size = UDim2.fromOffset(0, 0)
	tip.BackgroundColor3 = Color3.fromRGB(14, 13, 16)
	tip.BackgroundTransparency = 0.08
	tip.BorderSizePixel = 0
	tip.FontFace = fonts().BodyBold
	tip.TextSize = math.round(13 * QuickNav.SCALE)
	tip.TextColor3 = S.Text
	tip.RichText = true
	tip.Visible = false
	tip.ZIndex = 20
	tip.Parent = gui
	Instance.new("UICorner", tip).CornerRadius = UDim.new(0, 5)
	local pad = Instance.new("UIPadding", tip)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 4), UDim.new(0, 4)
	local edge = Instance.new("UIStroke", tip)
	edge.Color = S.Edge
	edge.Transparency = 0.2
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	return tip
end

function QuickNav.Tooltip(button, text, key)
	local shown = text
	if key then shown = ('%s  <font color="#968A78">[%s]</font>'):format(text, key) end
	button.MouseEnter:Connect(function()
		local label = ensureTip()
		hovered = button
		label.Text = shown
		local pos, size = button.AbsolutePosition, button.AbsoluteSize
		local screenW = gui.AbsoluteSize.X
		-- Centred under the button, kept on screen at the right edge.
		local x = math.min(pos.X + size.X / 2, screenW - label.AbsoluteSize.X / 2 - QuickNav.MARGIN)
		label.Position = UDim2.fromOffset(x, pos.Y + size.Y + 8)
		label.Visible = true
	end)
	button.MouseLeave:Connect(function()
		if hovered == button and tip then
			hovered = nil
			tip.Visible = false
		end
	end)
end

return QuickNav
