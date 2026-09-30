--[[
	WardrobeMenu -- the customization menu drawn over the WardrobeStage (client).

		local menu = WardrobeMenu.new(parentGui, savedAppearance, {
			onPreview = function(draft) end,      -- every change (the stage recolours live)
			onRotate  = function(degrees) end,    -- drag on the right side of the screen
			onCategory = function(category) end,  -- a tab was opened (the stage reframes)
			onConfirm = function(draft) return ok, errText end,  -- may yield (server save)
			onCancel  = function() end,
		})
		menu:Destroy()

	Categories and options come from RS/Assets/Appearance/AppearanceOptions, so new hair
	styles etc. appear here with no UI change. Slider categories (Skin) get a ramp slider plus
	preset chips; List categories get option cards, plus a linked slider underneath when the
	category names one (Eyes -> EyeColor, which has no tab of its own).

	Look: deliberately NOT the brown/gold inventory UI. Cold near-black glass, thin steel lines,
	condensed uppercase headings (Oswald) over a clean sans (Montserrat); menu on the left, the
	character on the right, the selected option's name + description on the far right.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local AppearanceOptions = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Appearance"):WaitForChild("AppearanceOptions"))

local WardrobeMenu = {}
WardrobeMenu.__index = WardrobeMenu

----------------------------------------------------------------------
-- Look
----------------------------------------------------------------------

local C = {
	text = Color3.fromRGB(236, 239, 244),
	muted = Color3.fromRGB(186, 193, 206),
	faint = Color3.fromRGB(128, 137, 152),
	line = Color3.fromRGB(88, 98, 116),
	accent = Color3.fromRGB(170, 212, 228),
	unsaved = Color3.fromRGB(236, 200, 120),
	shade = Color3.fromRGB(7, 9, 13),
	card = Color3.fromRGB(16, 19, 26),
	danger = Color3.fromRGB(214, 110, 104),
	ink = Color3.fromRGB(12, 14, 18),
}

local function font(family, weight)
	local ok, f = pcall(Font.fromName, family, weight or Enum.FontWeight.Regular)
	return ok and f or Font.new("rbxasset://fonts/families/GothamSSm.json", weight or Enum.FontWeight.Regular)
end
local HEAD = font("Oswald", Enum.FontWeight.Medium)
local HEAD_BOLD = font("Oswald", Enum.FontWeight.SemiBold)
local BODY = font("Montserrat", Enum.FontWeight.Regular)
local BODY_MED = font("Montserrat", Enum.FontWeight.Medium)

local DESIGN_HEIGHT = 900 -- layout is authored at this screen height, then scaled (never below .9)
local LEFT_W = 600
local ROTATE_DEG_PER_PX = .45

local function new(class, props, children)
	local inst = Instance.new(class)
	for k, v in pairs(props or {}) do
		if k ~= "Parent" then inst[k] = v end
	end
	for _, child in ipairs(children or {}) do child.Parent = inst end
	if props and props.Parent then inst.Parent = props.Parent end
	return inst
end

local function label(props)
	props.BackgroundTransparency = 1
	props.TextColor3 = props.TextColor3 or C.text
	props.FontFace = props.FontFace or BODY
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Center
	return new("TextLabel", props)
end

local function stroke(parent, color, thickness, transparency)
	return new("UIStroke", {
		Color = color, Thickness = thickness or 1, Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = parent,
	})
end

local function diamond(parent, size, color, position)
	return new("Frame", {
		Size = UDim2.fromOffset(size, size), AnchorPoint = Vector2.new(.5, .5), Position = position,
		Rotation = 45, BackgroundColor3 = color, BorderSizePixel = 0, Parent = parent,
	})
end

local function tween(inst, seconds, props, style)
	local t = TweenService:Create(inst, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function copy(t)
	local out = {}
	for k, v in pairs(t) do out[k] = v end
	return out
end

----------------------------------------------------------------------
-- Build
----------------------------------------------------------------------

function WardrobeMenu.new(parent, saved, callbacks)
	local self = setmetatable({}, WardrobeMenu)
	self.saved = AppearanceOptions.Sanitize(saved)
	self.draft = copy(self.saved)
	self.callbacks = callbacks or {}
	self.conns = {}
	self.category = AppearanceOptions.Categories[1].Id

	local root = new("Frame", { Name = "WardrobeMenu", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = parent })
	self.root = root

	-- Left-side shade so the menu reads over the bright field; the right stays clear.
	new("Frame", {
		Name = "Shade", Size = UDim2.fromScale(.62, 1), BackgroundColor3 = C.shade, BorderSizePixel = 0, Parent = root,
	}, {
		new("UIGradient", { Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, .08), NumberSequenceKeypoint.new(.55, .35), NumberSequenceKeypoint.new(1, 1),
		}) }),
	})
	new("Frame", {
		Name = "BottomShade", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, .22),
		BackgroundColor3 = C.shade, BorderSizePixel = 0, Parent = root,
	}, {
		new("UIGradient", { Rotation = -90, Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, .35), NumberSequenceKeypoint.new(1, 1),
		}) }),
	})

	-- Drag anywhere on the right (behind the info panel) to turn the character.
	local drag = new("TextButton", {
		Name = "RotateArea", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(.52, 1),
		BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Parent = root,
	})
	self:_bindRotate(drag)

	self:_buildLeft(root)
	self:_buildInfo(root)
	self:_buildFooter(root)

	-- The panels are authored at DESIGN_HEIGHT; each gets its own UIScale (it scales around the
	-- panel's anchor, so edge-anchored panels stay pinned to their edge at any screen size).
	local scales = {}
	for _, panel in ipairs({ self.left, self.info, self.footer }) do
		table.insert(scales, new("UIScale", { Parent = panel }))
	end
	local function rescale()
		local h = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize.Y or DESIGN_HEIGHT
		for _, sc in ipairs(scales) do sc.Scale = math.clamp(h / DESIGN_HEIGHT, .9, 1.5) end
	end
	rescale()
	table.insert(self.conns, Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale))
	self:_selectCategory(self.category)

	-- Keys: Esc = cancel, Enter = confirm.
	table.insert(self.conns, UserInputService.InputBegan:Connect(function(input, gp)
		if self.busy then return end
		if input.KeyCode == Enum.KeyCode.Escape then
			self:_cancel()
		elseif input.KeyCode == Enum.KeyCode.Return and not gp then
			self:_confirm()
		end
	end))

	-- Open animation: slide the left column in, fade the rest.
	self.left.Position = self.left.Position - UDim2.fromOffset(40, 0)
	self.left.GroupTransparency = 1
	self.info.GroupTransparency = 1
	tween(self.left, .45, { Position = self.left.Position + UDim2.fromOffset(40, 0), GroupTransparency = 0 }, Enum.EasingStyle.Quart)
	task.delay(.12, function() if self.info.Parent then tween(self.info, .45, { GroupTransparency = 0 }) end end)
	return self
end

function WardrobeMenu:_buildLeft(root)
	local left = new("CanvasGroup", {
		Name = "Left", AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 84, .5, -10),
		Size = UDim2.fromOffset(LEFT_W + 60, 820), BackgroundTransparency = 1, Parent = root,
	})
	self.left = left

	label({ Text = "WARDROBE", FontFace = HEAD, TextSize = 26, TextColor3 = C.accent,
		Size = UDim2.fromOffset(LEFT_W, 30), Position = UDim2.fromOffset(0, 0), Parent = left })
	label({ Text = "APPEARANCE", FontFace = HEAD_BOLD, TextSize = 72,
		Size = UDim2.fromOffset(LEFT_W, 80), Position = UDim2.fromOffset(0, 30), Parent = left })

	-- Category tabs.
	local tabs = new("Frame", { Name = "Tabs", Size = UDim2.fromOffset(LEFT_W + 60, 44), Position = UDim2.fromOffset(0, 128),
		BackgroundTransparency = 1, Parent = left }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 26), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	self.tabButtons = {}
	for i, category in ipairs(AppearanceOptions.Categories) do
		if category.Hidden then continue end
		local button = new("TextButton", {
			Name = category.Id, LayoutOrder = i, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 44),
			BackgroundTransparency = 1, AutoButtonColor = false, Text = string.upper(category.Name), FontFace = HEAD,
			TextSize = 28, TextColor3 = C.muted, Parent = tabs,
		})
		local underline = new("Frame", {
			Name = "Underline", AnchorPoint = Vector2.new(.5, 1), Position = UDim2.fromScale(.5, 1), Size = UDim2.new(0, 0, 0, 3),
			BackgroundColor3 = C.accent, BorderSizePixel = 0, Parent = button,
		})
		button.MouseEnter:Connect(function() if self.category ~= category.Id then tween(button, .12, { TextColor3 = C.text }) end end)
		button.MouseLeave:Connect(function() if self.category ~= category.Id then tween(button, .12, { TextColor3 = C.muted }) end end)
		button.Activated:Connect(function() self:_selectCategory(category.Id) end)
		self.tabButtons[category.Id] = { button = button, underline = underline }
	end

	-- Divider with a diamond at its start.
	new("Frame", { Name = "Divider", Position = UDim2.fromOffset(0, 186), Size = UDim2.fromOffset(LEFT_W, 1),
		BackgroundColor3 = C.line, BorderSizePixel = 0, Parent = left })
	diamond(left, 9, C.accent, UDim2.fromOffset(0, 186))

	self.content = new("CanvasGroup", { Name = "Content", Position = UDim2.fromOffset(0, 216), Size = UDim2.fromOffset(LEFT_W + 30, 580),
		BackgroundTransparency = 1, Parent = left })
end

function WardrobeMenu:_buildInfo(root)
	local info = new("CanvasGroup", {
		Name = "Info", AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -84, .4, 0), Size = UDim2.fromOffset(460, 170),
		BackgroundTransparency = 1, Parent = root,
	})
	self.info = info
	-- Thin frame line down the right edge with diamond ends, like a label pinned to the scene.
	new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 10), Size = UDim2.new(0, 1, 1, -20),
		BackgroundColor3 = C.line, BorderSizePixel = 0, Parent = info })
	diamond(info, 7, C.accent, UDim2.new(1, 0, 0, 10))
	diamond(info, 7, C.line, UDim2.new(1, 0, 1, -10))
	new("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, -10), Size = UDim2.new(.7, 0, 0, 1),
		BackgroundColor3 = C.line, BorderSizePixel = 0, Parent = info })

	self.infoEyebrow = label({ Text = "", FontFace = HEAD, TextSize = 24, TextColor3 = C.accent,
		Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, -28, 0, 28), Parent = info })
	self.infoName = label({ Text = "", FontFace = HEAD_BOLD, TextSize = 60, TextWrapped = true,
		Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, -28, 0, 70), Parent = info })
	self.infoState = label({ Text = "", FontFace = HEAD, TextSize = 26, TextColor3 = C.accent,
		Position = UDim2.fromOffset(0, 116), Size = UDim2.new(1, -28, 0, 30), Parent = info })
end

local function keyHint(parent, key, text, order)
	local row = new("Frame", { LayoutOrder = order, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 36),
		BackgroundTransparency = 1, Parent = parent }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), VerticalAlignment = Enum.VerticalAlignment.Center }),
	})
	local box = label({ Text = key, FontFace = HEAD, TextSize = 20, TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Center,
		AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(44, 32), LayoutOrder = 1, Parent = row })
	new("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9), Parent = box })
	stroke(box, C.faint, 1)
	label({ Text = text, FontFace = BODY_MED, TextSize = 20, TextColor3 = C.muted, AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 32), LayoutOrder = 2, Parent = row })
end

local function button(parent, text, primary, order)
	local b = new("TextButton", {
		LayoutOrder = order, Size = UDim2.fromOffset(220, 62), AutoButtonColor = false, Text = text, FontFace = HEAD,
		TextSize = 28, TextColor3 = primary and C.ink or C.text, BackgroundColor3 = primary and C.text or C.card,
		BackgroundTransparency = primary and 0 or .35, BorderSizePixel = 0, Parent = parent,
	})
	if not primary then stroke(b, C.line, 1) end
	b.MouseEnter:Connect(function() tween(b, .12, { BackgroundTransparency = primary and .12 or .15 }) end)
	b.MouseLeave:Connect(function() tween(b, .12, { BackgroundTransparency = primary and 0 or .35 }) end)
	return b
end

function WardrobeMenu:_buildFooter(root)
	local footer = new("Frame", { Name = "Footer", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -84, 1, -64),
		Size = UDim2.fromOffset(640, 130), BackgroundTransparency = 1, Parent = root })
	self.footer = footer
	local hints = new("Frame", { Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, Parent = footer }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding = UDim.new(0, 22), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	keyHint(hints, "DRAG", "Turn", 1)
	keyHint(hints, "ENTER", "Confirm", 2)
	keyHint(hints, "ESC", "Close", 3)
	local row = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 62),
		BackgroundTransparency = 1, Parent = footer }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	self.status = label({ Text = "", FontFace = BODY_MED, TextSize = 20, TextColor3 = C.danger, TextXAlignment = Enum.TextXAlignment.Right,
		LayoutOrder = 0, Size = UDim2.fromOffset(170, 62), TextWrapped = true, Parent = row })
	local cancel = button(row, "CANCEL", false, 1)
	local confirm = button(row, "CONFIRM", true, 2)
	self.confirmButton = confirm
	cancel.Activated:Connect(function() self:_cancel() end)
	confirm.Activated:Connect(function() self:_confirm() end)
end

----------------------------------------------------------------------
-- Categories + content
----------------------------------------------------------------------

function WardrobeMenu:_selectCategory(id)
	self.category = id
	if self.callbacks.onCategory then self.callbacks.onCategory(AppearanceOptions.GetCategory(id)) end
	for cid, tab in pairs(self.tabButtons) do
		local active = cid == id
		tween(tab.button, .15, { TextColor3 = active and C.text or C.muted })
		tween(tab.underline, .2, { Size = UDim2.new(active and 1 or 0, 0, 0, 3) })
	end
	for _, child in ipairs(self.content:GetChildren()) do child:Destroy() end
	for _, c in ipairs(self.dragConns or {}) do c:Disconnect() end
	self.dragConns = {}
	self.sliderRefresh = {}
	local category = AppearanceOptions.GetCategory(id)
	if category.Kind == "Slider" then
		local holder = new("Frame", { Size = UDim2.fromOffset(LEFT_W + 30, 240), BackgroundTransparency = 1, Parent = self.content })
		self:_buildSlider(category, holder)
	else
		self:_buildList(category)
	end
	self.content.GroupTransparency = 1
	tween(self.content, .2, { GroupTransparency = 0 })
	self:_refreshInfo()
end

-- A ramp slider + preset chips for a Slider category (Skin, EyeColor...), built into `parent`.
function WardrobeMenu:_buildSlider(category, parent)
	local id = category.Id
	label({ Text = category.ValueLabel or "VALUE", FontFace = HEAD, TextSize = 26, TextColor3 = C.muted, Size = UDim2.fromOffset(300, 30), Parent = parent })
	local valueText = label({ Text = "", FontFace = HEAD, TextSize = 26, TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(LEFT_W, 0), Size = UDim2.fromOffset(120, 30), Parent = parent })

	local track = new("TextButton", {
		Name = "Track", Position = UDim2.fromOffset(0, 48), Size = UDim2.fromOffset(LEFT_W, 22), Text = "", AutoButtonColor = false,
		BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = parent,
	}, {
		new("UICorner", { CornerRadius = UDim.new(1, 0) }),
		new("UIGradient", { Color = AppearanceOptions.RampSequence(id) }),
	})
	stroke(track, C.line, 1)
	local knob = new("Frame", {
		Name = "Knob", AnchorPoint = Vector2.new(.5, .5), Size = UDim2.fromOffset(38, 38), BorderSizePixel = 0, ZIndex = 3, Parent = track,
	}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	stroke(knob, C.text, 2.5)

	-- Preset chips.
	local chips = new("Frame", { Position = UDim2.fromOffset(0, 96), Size = UDim2.fromOffset(LEFT_W, 64), BackgroundTransparency = 1, Parent = parent }, {
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12) }),
	})
	local chipStrokes = {}
	for _, t in ipairs(category.Presets or {}) do
		local chip = new("TextButton", { Size = UDim2.fromOffset(64, 64), Text = "", AutoButtonColor = false,
			BackgroundColor3 = AppearanceOptions.RampColor(id, t), BorderSizePixel = 0, Parent = chips })
		chipStrokes[t] = stroke(chip, C.line, 1)
		chip.Activated:Connect(function() self:_setSlider(id, t) end)
	end

	self.sliderRefresh[id] = function()
		local t = self.draft[id]
		knob.Position = UDim2.fromScale(t, .5)
		knob.BackgroundColor3 = AppearanceOptions.RampColor(id, t)
		valueText.Text = string.format("%d", math.floor(t * 100 + .5))
		for preset, st in pairs(chipStrokes) do
			local on = math.abs(preset - t) < .005
			st.Color = on and C.text or C.line
			st.Thickness = on and 2 or 1
		end
	end
	self.sliderRefresh[id]()

	local function setFromX(x)
		self:_setSlider(id, math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1))
	end
	local dragging = false
	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromX(input.Position.X)
		end
	end)
	table.insert(self.dragConns, UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end))
	table.insert(self.dragConns, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
	end))
end

function WardrobeMenu:_setSlider(id, t)
	self.draft[id] = math.floor(math.clamp(t, 0, 1) * 1000 + .5) / 1000
	local refresh = self.sliderRefresh and self.sliderRefresh[id]
	if refresh then refresh() end
	self:_changed()
end

function WardrobeMenu:_buildList(category)
	local content = self.content
	local list = new("Frame", { Size = UDim2.fromOffset(LEFT_W, 560), BackgroundTransparency = 1, Parent = content }, {
		new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	self.cards = {}
	for i, option in ipairs(category.Options) do
		local card = new("TextButton", {
			Name = option.Id, LayoutOrder = i, Size = UDim2.fromOffset(LEFT_W, 74), Text = "", AutoButtonColor = false,
			BackgroundColor3 = C.card, BackgroundTransparency = .3, BorderSizePixel = 0, Parent = list,
		})
		local s = stroke(card, C.line, 1)
		local icon = diamond(card, 13, C.faint, UDim2.fromOffset(32, 37))
		label({ Text = option.Name, FontFace = BODY_MED, TextSize = 26, Position = UDim2.fromOffset(62, 0), Size = UDim2.new(1, -200, 1, 0), Parent = card })
		local tag = label({ Text = "", FontFace = HEAD, TextSize = 22, TextColor3 = C.accent, TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 0), Size = UDim2.new(0, 130, 1, 0), Parent = card })
		card.MouseEnter:Connect(function() tween(card, .12, { BackgroundTransparency = .12 }) end)
		card.MouseLeave:Connect(function() tween(card, .12, { BackgroundTransparency = .3 }) end)
		card.Activated:Connect(function()
			self.draft[category.Id] = option.Id
			self:_refreshCards(category)
			self:_changed()
		end)
		self.cards[option.Id] = { stroke = s, icon = icon, tag = tag }
	end
	if #category.Options <= 1 then
		label({ Text = "More styles are on the way.", FontFace = BODY_MED, TextSize = 22, TextColor3 = C.muted,
			LayoutOrder = 999, Size = UDim2.fromOffset(LEFT_W, 40), Parent = list })
	end
	-- A linked slider under the cards (Eyes -> EyeColor).
	local linked = category.Slider and AppearanceOptions.GetCategory(category.Slider)
	if linked then
		local holder = new("Frame", { LayoutOrder = 1000, Size = UDim2.fromOffset(LEFT_W + 30, 190), BackgroundTransparency = 1, Parent = list })
		new("UIPadding", { PaddingTop = UDim.new(0, 18), Parent = holder })
		self:_buildSlider(linked, holder)
	end
	self:_refreshCards(category)
end

function WardrobeMenu:_refreshCards(category)
	for id, card in pairs(self.cards or {}) do
		local selected = self.draft[category.Id] == id
		card.stroke.Color = selected and C.text or C.line
		card.stroke.Thickness = selected and 1.5 or 1
		card.icon.BackgroundColor3 = selected and C.accent or C.faint
		card.tag.Text = (self.saved[category.Id] == id) and "CURRENT" or ""
	end
end

function WardrobeMenu:_refreshInfo()
	local category = AppearanceOptions.GetCategory(self.category)
	self.infoEyebrow.Text = string.upper(category.Subtitle or category.Name)
	if category.Kind == "Slider" then
		self.infoName.Text = (category.ValueLabel or "") .. " " .. math.floor(self.draft[category.Id] * 100 + .5)
	else
		local option = AppearanceOptions.GetOption(category.Id, self.draft[category.Id])
		self.infoName.Text = option and string.upper(option.Name) or ""
	end
	local changed = self.draft[category.Id] ~= self.saved[category.Id]
		or (category.Slider ~= nil and self.draft[category.Slider] ~= self.saved[category.Slider])
	self.infoState.Text = changed and "NOT SAVED" or "SAVED"
	self.infoState.TextColor3 = changed and C.unsaved or C.accent
end

function WardrobeMenu:_changed()
	self.status.Text = ""
	self:_refreshInfo()
	if self.callbacks.onPreview then self.callbacks.onPreview(copy(self.draft)) end
end

----------------------------------------------------------------------
-- Rotate / confirm / cancel
----------------------------------------------------------------------

function WardrobeMenu:_bindRotate(area)
	local dragging, lastX = false, 0
	area.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging, lastX = true, input.Position.X
		end
	end)
	table.insert(self.conns, UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			local dx = input.Position.X - lastX
			lastX = input.Position.X
			if self.callbacks.onRotate then self.callbacks.onRotate(dx * ROTATE_DEG_PER_PX) end
		end
	end))
	table.insert(self.conns, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
	end))
end

function WardrobeMenu:_confirm()
	if self.busy then return end
	self.busy = true
	self.status.Text = ""
	self.confirmButton.Text = "SAVING"
	local ok, err = true, nil
	if self.callbacks.onConfirm then ok, err = self.callbacks.onConfirm(copy(self.draft)) end
	if not self.root.Parent then return end
	self.busy = false
	self.confirmButton.Text = "CONFIRM"
	if not ok then self.status.Text = err or "Could not save. Try again." end
end

function WardrobeMenu:_cancel()
	if self.busy then return end
	if self.callbacks.onCancel then self.callbacks.onCancel() end
end

function WardrobeMenu:Destroy()
	for _, c in ipairs(self.conns) do c:Disconnect() end
	self.conns = {}
	for _, c in ipairs(self.dragConns or {}) do c:Disconnect() end
	self.dragConns = {}
	if self.root then self.root:Destroy() end
end

return WardrobeMenu
