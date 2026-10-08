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
	preset swatches; List categories get option rows, plus a linked slider underneath when the
	category names one (Eyes -> EyeColor, which has no tab of its own).

	Look (rebuilt 2026-10-02 from the Journal kit; was a cold steel-and-glass style): one book
	page on the left (Journal art: book_cover around page_paper), the categories as bookmark tabs
	on its top edge, options on chip plates, the colour ramps as bronze-ringed sliders with round
	swatches, Cancel / Confirm chips at the foot. The character stays clear on the right; drag
	there to turn it. React inside; the API above is unchanged, so Wardrobe/init and the stage
	don't know.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local AppearanceOptions = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Appearance"):WaitForChild("AppearanceOptions"))
local Journal = script.Parent.Parent:WaitForChild("InventoryHud"):WaitForChild("Inventory"):WaitForChild("Journal")
local Style = require(Journal:WaitForChild("Style"))
local Parts = require(Journal:WaitForChild("Parts"))

local e = React.createElement
local text = Parts.Text

local WardrobeMenu = {}
WardrobeMenu.__index = WardrobeMenu

local DESIGN_HEIGHT = 900 -- the page is authored at this screen height, then scaled (.9 .. 1.5)
local PAGE_W, PAGE_H = 560, 790
local COVER = 18 -- leather visible around the parchment
local PAD = 30 -- inside the parchment
local TAB_W = 84
local ROTATE_DEG_PER_PX = .45
local RING = Color3.fromRGB(138, 113, 70) -- tarnished bronze, as the HUD bars

local function copy(t)
	local out = {}
	for k, v in pairs(t) do out[k] = v end
	return out
end

----------------------------------------------------------------------
-- Pieces
----------------------------------------------------------------------

-- A colour ramp: label + value, the gradient track with a round knob, and preset swatches.
local function Slider(props: { category: any, value: number, onChange: (number) -> () })
	local category = props.category
	local id = category.Id
	local trackRef = React.useRef(nil :: GuiObject?)
	local dragging, setDragging = React.useState(false)

	local function setFromX(x: number)
		local track = trackRef.current
		if not track then return end
		local t = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		props.onChange(math.floor(t * 1000 + .5) / 1000)
	end

	React.useEffect(function()
		if not dragging then return end
		local moved = UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
				setFromX(input.Position.X)
			end
		end)
		local ended = UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				setDragging(false)
			end
		end)
		return function()
			moved:Disconnect()
			ended:Disconnect()
		end
	end, { dragging })

	local swatches: { [string]: any } = {
		Layout = e("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
	}
	for i, t in ipairs(category.Presets or {}) do
		local on = math.abs(t - props.value) < .005
		swatches["S" .. i] = e("TextButton", {
			LayoutOrder = i, Size = UDim2.fromOffset(40, 40), Text = "", AutoButtonColor = false,
			BackgroundColor3 = AppearanceOptions.RampColor(id, t), BorderSizePixel = 0,
			[React.Event.Activated] = function() props.onChange(t) end,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Ring = e("UIStroke", { Color = on and Style.Text.Heading or RING, Thickness = on and 3 or 1.5 }),
		})
	end

	return e("Frame", { Size = UDim2.new(1, 0, 0, 150), BackgroundTransparency = 1 }, {
		Label = text({
			text = category.Name, font = Style.Font.Heading, size = 18, color = Style.Text.Heading,
			align = Enum.TextXAlignment.Left, Size = UDim2.new(.7, 0, 0, 24),
		}),
		Value = text({
			text = tostring(math.floor(props.value * 100 + .5)), font = Style.Font.Number, size = 18, color = Style.Text.Value,
			align = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(.3, 0, 0, 24),
		}),
		Track = e("TextButton", {
			ref = trackRef,
			Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 0, 18),
			Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
			[React.Event.InputBegan] = function(_, input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					setDragging(true)
					setFromX(input.Position.X)
				end
			end,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Ramp = e("UIGradient", { Color = AppearanceOptions.RampSequence(id) }),
			Edge = e("UIStroke", { Color = RING, Thickness = 1.5 }),
			Knob = e("Frame", {
				AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(props.value, .5), Size = UDim2.fromOffset(30, 30),
				BackgroundColor3 = AppearanceOptions.RampColor(id, props.value), BorderSizePixel = 0, ZIndex = 3,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
				Ring = e("UIStroke", { Color = Style.Text.Heading, Thickness = 2.5 }),
			}),
		}),
		Swatches = e("Frame", { Position = UDim2.fromOffset(0, 76), Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1 }, swatches),
	})
end

-- One option on a chip plate: its name, and "Current" on the one that's saved.
local function OptionRow(props: { name: string, selected: boolean, current: boolean, order: number, onClick: () -> () })
	local hovered, setHovered = React.useState(false)
	return e("TextButton", {
		LayoutOrder = props.order, Size = UDim2.new(1, 0, 0, 50), BackgroundTransparency = 1, AutoButtonColor = false, Text = "",
		[React.Event.Activated] = props.onClick,
		[React.Event.MouseEnter] = function() setHovered(true) end,
		[React.Event.MouseLeave] = function() setHovered(false) end,
	}, {
		Plate = e(Parts.ArtFrame, {
			art = props.selected and "chip_selected" or "chip",
			flat = {
				color = props.selected and Style.Flat.PlateOn or Style.Flat.Plate, edge = Style.Flat.Edge,
				edgeTransparency = props.selected and .05 or (hovered and .3 or .65), corner = 5,
			},
			ZIndex = 1,
		}),
		Name = e("TextLabel", {
			Position = UDim2.fromOffset(22, 0), Size = UDim2.new(1, -140, 1, 0), BackgroundTransparency = 1,
			Text = props.name, FontFace = Style.Font.Chrome, TextSize = 18,
			TextColor3 = (props.selected or hovered) and Style.Chrome.Selected or Style.Chrome.Label,
			TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3,
		}),
		Current = props.current and e("TextLabel", {
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -22, 0, 0), Size = UDim2.new(0, 110, 1, 0),
			BackgroundTransparency = 1, Text = "Current", FontFace = Style.Font.Body, TextSize = 14,
			TextColor3 = Style.Chrome.Dim, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3,
		}) or nil,
	})
end

local function useViewportScale(): number
	local scale, setScale = React.useState(1)
	React.useEffect(function()
		local camera = Workspace.CurrentCamera
		if not camera then return end
		local function fit()
			setScale(math.clamp(camera.ViewportSize.Y / DESIGN_HEIGHT, .9, 1.5))
		end
		fit()
		local conn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
		return function() conn:Disconnect() end
	end, {})
	return scale
end

----------------------------------------------------------------------
-- The page
----------------------------------------------------------------------

local function WardrobePage(props: { saved: any, callbacks: any, api: any })
	local callbacks = props.callbacks
	local saved = props.saved
	local draft, setDraft = React.useState(copy(saved))
	local categoryId, setCategoryId = React.useState(AppearanceOptions.Categories[1].Id)
	local busy, setBusy = React.useState(false)
	local status, setStatus = React.useState("")
	local alive = React.useRef(true)
	local scale = useViewportScale()

	React.useEffect(function()
		return function() alive.current = false end
	end, {})
	-- The stage follows every change, and reframes per tab.
	React.useEffect(function()
		if callbacks.onPreview then callbacks.onPreview(copy(draft)) end
	end, { draft })
	React.useEffect(function()
		if callbacks.onCategory then callbacks.onCategory(AppearanceOptions.GetCategory(categoryId)) end
	end, { categoryId })

	local function set(id: string, value: any)
		local nextDraft = copy(draft)
		nextDraft[id] = value
		setStatus("")
		setDraft(nextDraft)
	end

	local function confirm()
		if busy then return end
		setBusy(true)
		setStatus("")
		task.spawn(function()
			local ok, err = true, nil
			if callbacks.onConfirm then ok, err = callbacks.onConfirm(copy(draft)) end
			if not alive.current then return end
			setBusy(false)
			if not ok then setStatus(err or "Could not save. Try again.") end
		end)
	end
	local function cancel()
		if busy then return end
		if callbacks.onCancel then callbacks.onCancel() end
	end
	-- Esc / Enter (wired in WardrobeMenu.new) reach the latest versions through this.
	props.api.confirm = confirm
	props.api.cancel = cancel

	local category = AppearanceOptions.GetCategory(categoryId)
	local unsaved = false
	for id, value in pairs(draft) do
		if saved[id] ~= value then unsaved = true end
	end

	-- Bookmark tabs: every visible category.
	local tabs: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for i, c in ipairs(AppearanceOptions.Categories) do
		if not c.Hidden then
			tabs[c.Id] = e(Parts.ChromeButton, {
				text = c.Name, selected = c.Id == categoryId,
				art = "bookmark_tab", artSelected = "bookmark_tab_active",
				Size = UDim2.fromOffset(TAB_W, Style.TAB_H), LayoutOrder = i, textSize = 13,
				onClick = function() setCategoryId(c.Id) end,
			})
		end
	end

	-- The body: a slider, or option rows (+ a linked colour slider).
	local body
	if category.Kind == "Slider" then
		body = e(Slider, { category = category, value = draft[category.Id], onChange = function(v) set(category.Id, v) end })
	else
		local rows: { [string]: any } = {
			Layout = e("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		}
		for i, option in ipairs(category.Options) do
			rows[option.Id] = e(OptionRow, {
				name = option.Name, order = i,
				selected = draft[category.Id] == option.Id,
				current = saved[category.Id] == option.Id,
				onClick = function() set(category.Id, option.Id) end,
			})
		end
		if #category.Options <= 1 then
			rows.More = text({ text = "More styles are on the way.", size = 15, color = Style.Text.Muted, height = 30, order = 999 })
		end
		local linked = category.Slider and AppearanceOptions.GetCategory(category.Slider)
		if linked then
			rows.Linked = e("Frame", { LayoutOrder = 1000, Size = UDim2.new(1, 0, 0, 170), BackgroundTransparency = 1 }, {
				Pad = e("UIPadding", { PaddingTop = UDim.new(0, 18) }),
				Slider = e(Slider, { category = linked, value = draft[linked.Id], onChange = function(v) set(linked.Id, v) end }),
			})
		end
		body = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, rows)
	end

	local selectedName
	if category.Kind == "Slider" then
		selectedName = ("%s %d"):format(category.Name, math.floor(draft[category.Id] * 100 + .5))
	else
		local option = AppearanceOptions.GetOption(category.Id, draft[category.Id])
		selectedName = option and option.Name or ""
	end

	local innerW = PAGE_W - (COVER + PAD) * 2
	return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
		Page = e("Frame", {
			AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 84, .5, 0),
			Size = UDim2.fromOffset(PAGE_W, PAGE_H + Style.TAB_H), BackgroundTransparency = 1,
		}, {
			Scale = e("UIScale", { Scale = scale }),
			Tabs = e("Frame", {
				Size = UDim2.new(1, 0, 0, Style.TAB_H), BackgroundTransparency = 1, ZIndex = 3,
			}, tabs),
			Cover = e(Parts.ArtFrame, {
				art = "book_cover",
				flat = { color = Style.Flat.Cover, edge = Style.Flat.CoverEdge, edgeTransparency = .2, corner = 10 },
				Position = UDim2.fromOffset(0, Style.TAB_H - 6), Size = UDim2.fromOffset(PAGE_W, PAGE_H),
				ZIndex = 1,
				children = {
					Paper = e(Parts.ArtFrame, {
						art = "page_paper",
						flat = { color = Style.Flat.Page, corner = 4 },
						Position = UDim2.fromOffset(COVER, COVER), Size = UDim2.new(1, -COVER * 2, 1, -COVER * 2),
						ZIndex = 2,
						children = {
							Content = e("Frame", {
								Position = UDim2.fromOffset(PAD, PAD - 6), Size = UDim2.new(1, -PAD * 2, 1, -(PAD * 2 - 6)),
								BackgroundTransparency = 1, ZIndex = 3,
							}, {
								Heading = e(Parts.Heading, { text = "Wardrobe", size = 30, height = 38 }),
								Sub = text({
									text = category.Subtitle or category.Name, size = 15, color = Style.Text.Muted,
									Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 0, 20),
								}),
								Rule = e("Frame", { Position = UDim2.fromOffset(0, 62), Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1 }, {
									Line = e(Parts.Divider, { width = 1 }),
								}),
								Body = e("Frame", {
									Position = UDim2.fromOffset(0, 90), Size = UDim2.fromOffset(innerW, 470), BackgroundTransparency = 1,
								}, { Content = body }),
								-- The foot: what's picked and whether it's saved, then the two buttons.
								Picked = text({
									text = selectedName, font = Style.Font.Heading, size = 20, color = Style.Text.Heading, truncate = true,
									AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -82),
									Size = UDim2.new(.65, 0, 0, 26), align = Enum.TextXAlignment.Left,
								}),
								State = text({
									text = unsaved and "Not saved" or "Saved", size = 15, font = Style.Font.BodyBold,
									color = unsaved and Style.Text.Bad or Style.Text.Good,
									AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, -82),
									Size = UDim2.new(.35, 0, 0, 26), align = Enum.TextXAlignment.Right,
								}),
								Status = text({
									text = status, size = 14, color = Style.Text.Bad,
									AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -60), Size = UDim2.new(1, 0, 0, 18),
								}),
								Cancel = e(Parts.ChromeButton, {
									text = "Cancel", art = "chip", artSelected = "chip_selected", disabled = busy,
									AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0),
									Size = UDim2.new(.5, -6, 0, 48), textSize = 18, onClick = cancel,
								}),
								Confirm = e(Parts.ChromeButton, {
									text = busy and "Saving..." or "Confirm", art = "chip", artSelected = "chip_selected",
									selected = true, disabled = busy,
									AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, 0),
									Size = UDim2.new(.5, -6, 0, 48), textSize = 18, onClick = confirm,
								}),
							}),
						},
					}),
				},
			}),
		}),
		-- Hints along the bottom right, over the scene.
		Hints = e("TextLabel", {
			AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -60, 1, -40), Size = UDim2.fromOffset(520, 30),
			BackgroundTransparency = 1, Text = "Drag to turn    Enter to confirm    Esc to close",
			FontFace = Style.Font.Heading, TextSize = 18, TextColor3 = Style.Chrome.Selected,
			TextStrokeColor3 = Color3.new(0, 0, 0), TextStrokeTransparency = .45,
			TextXAlignment = Enum.TextXAlignment.Right,
		}),
	})
end

----------------------------------------------------------------------
-- The object Wardrobe/init drives
----------------------------------------------------------------------

function WardrobeMenu.new(parent, saved, callbacks)
	local self = setmetatable({}, WardrobeMenu)
	self.conns = {}
	self.api = {}
	callbacks = callbacks or {}

	local root = Instance.new("Frame")
	root.Name = "WardrobeMenu"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = parent
	self.root = root

	-- Drag anywhere on the right half to turn the character (outside React: plain input).
	local drag = Instance.new("TextButton")
	drag.Name = "RotateArea"
	drag.AnchorPoint = Vector2.new(1, 0)
	drag.Position = UDim2.fromScale(1, 0)
	drag.Size = UDim2.fromScale(.52, 1)
	drag.BackgroundTransparency = 1
	drag.Text = ""
	drag.AutoButtonColor = false
	drag.Parent = root
	local dragging, lastX = false, 0
	drag.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging, lastX = true, input.Position.X
		end
	end)
	table.insert(self.conns, UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local dx = input.Position.X - lastX
			lastX = input.Position.X
			if callbacks.onRotate then callbacks.onRotate(dx * ROTATE_DEG_PER_PX) end
		end
	end))
	table.insert(self.conns, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
	end))

	-- Esc = cancel, Enter = confirm.
	table.insert(self.conns, UserInputService.InputBegan:Connect(function(input, gp)
		if input.KeyCode == Enum.KeyCode.Escape then
			if self.api.cancel then self.api.cancel() end
		elseif input.KeyCode == Enum.KeyCode.Return and not gp then
			if self.api.confirm then self.api.confirm() end
		end
	end))

	local host = Instance.new("Frame")
	host.Name = "Page"
	host.Size = UDim2.fromScale(1, 1)
	host.BackgroundTransparency = 1
	host.Parent = root
	self.reactRoot = ReactRoblox.createRoot(host)
	self.reactRoot:render(e(WardrobePage, {
		saved = AppearanceOptions.Sanitize(saved), callbacks = callbacks, api = self.api,
	}))
	return self
end

function WardrobeMenu:Destroy()
	for _, c in ipairs(self.conns) do c:Disconnect() end
	self.conns = {}
	if self.reactRoot then
		self.reactRoot:unmount()
		self.reactRoot = nil
	end
	if self.root then self.root:Destroy() end
end

return WardrobeMenu
