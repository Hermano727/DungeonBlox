--!strict
--  QuickNav -- the bottom icon bar (StarterGui.quick nav's FigBloxUI export).
--  Each icon is a real button now, wired to the Inventory root's stack
--  navigation via onSelect(panelName). All five diamonds are now a uniform
--  813px (the smallest of the original export sizes) so the row reads as one
--  consistent set of buttons instead of mismatched backpack/skills vs. the rest.
--  Horizontal centers are kept from the original design; only the size shrank.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
local e = React.createElement

local DESIGN_W, DESIGN_H = 7419, 856

--  Diamond button backing -- rotated rounded-square "gem" behind each nav icon (in place of the
--  plain rectangle), with a hover pop: the diamond scales up on MouseEnter and eases back down
--  on MouseLeave via a UIScale + TweenService, the icon itself staying a fixed size on top.
local DIAMOND_SIDE_FRACTION = 0.94 -- of min(icon w, icon h)
local DIAMOND_INNER_FRACTION = 0.82 -- inset of the outer diamond
local DIAMOND_HOVER_SCALE = 1.14
local ICON_HOVER_SCALE = 1.18 -- the icon glyph pops slightly more than the diamond behind it
local DIAMOND_TWEEN_IN = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local DIAMOND_TWEEN_OUT = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

-- Hover-follow name tooltip -- a clean dark pill with white text that tracks the cursor while
-- hovering an icon, and disappears (no fade) the instant the cursor leaves.
local TOOLTIP_OFFSET = 16 -- rendered screen pixels between the cursor and the tooltip's corner
local TOOLTIP_BG = Color3.fromRGB(15, 12, 10)
local TOOLTIP_TEXT = Color3.fromRGB(255, 255, 255)

local DIAMOND_BORDER = Color3.fromRGB(18, 13, 11)
local DIAMOND_GOLD = UITheme.Gold
local DIAMOND_FILL_TOP = Color3.fromRGB(196, 62, 64)
local DIAMOND_FILL_BOTTOM = Color3.fromRGB(94, 16, 20)

-- All buttons share one uniform size (813px, the smallest of the original
-- export sizes). Left offsets are recentered on each icon's original center
-- so horizontal spacing still matches the original design; top is 0 for all
-- since every diamond is now the same height.
-- Bumped ~50% (813 -> 1220) per request -- left offsets recentered on the same original centers
-- used before (see the comment above) so the row still lines up the same, just bigger.
-- UNIFORM_SIZE is the diamond background box (drives diamondSide below); ICON_SIZE is the glyph
-- drawn on top of it, in its own absolute pixels -- independent of the diamond now, not a scale
-- fraction of it, so bumping one no longer drags the other along.
local UNIFORM_SIZE = 900
local ICON_SIZE = 740 -- was accidentally wired to the same value as UNIFORM_SIZE -- 900 here would
                       -- overflow the diamond's inscribed safe area (~0.62 * diamondSide); tune freely.

local ICONS = {
	-- panel = nil means "does nothing" -- the backpack icon is the inventory
	-- itself, which is already open, per request.
	{ id = "inventory",   panel = nil,           image = "rbxassetid://120011654836121", left = 17,   top = 0, w = UNIFORM_SIZE, h = UNIFORM_SIZE, iconSize = ICON_SIZE, label = "Inventory" },
	{ id = "skills",      panel = "skills",      image = "rbxassetid://73632421462187",  left = 1689, top = 0, w = UNIFORM_SIZE, h = UNIFORM_SIZE, iconSize = ICON_SIZE, label = "Skills" },
	{ id = "stats",       panel = "stats",       image = "rbxassetid://82100684435846",  left = 3246, top = 0, w = UNIFORM_SIZE, h = UNIFORM_SIZE, iconSize = ICON_SIZE, label = "Stats" },
	{ id = "hearthstone", panel = "hearthstone", image = "rbxassetid://92412859018068",  left = 4688, top = 0, w = UNIFORM_SIZE, h = UNIFORM_SIZE, iconSize = ICON_SIZE, label = "Hearthstone" },
	{ id = "party",       panel = "party",       image = "rbxassetid://139950368008948", left = 6025, top = 0, w = UNIFORM_SIZE, h = UNIFORM_SIZE, iconSize = ICON_SIZE, label = "Party" },
}

local function NavIcon(props: { image: string, left: number, top: number, w: number, h: number, iconSize: number, label: string, scale: number, onClick: (() -> ())? })
	local hovered, setHovered = React.useState(false)
	local scaleRef = React.useRef(nil :: UIScale?)
	local iconScaleRef = React.useRef(nil :: UIScale?)
	-- Tooltip position tracks the cursor imperatively (direct Instance.Position writes via this
	-- ref) instead of through React state. Funneling every single MouseMoved pixel through
	-- setState forced a full re-render/reconciliation of the whole tooltip subtree (frame +
	-- corner + padding + counter-scale + AutomaticSize text) on every pixel of mouse movement --
	-- that's what made the cursor-follow feel dulled/laggy. A ref write is a plain property set,
	-- no reconciliation, so it can keep up 1:1 with the mouse.
	local tooltipRef = React.useRef(nil :: Frame?)
	local lastLocalPos = React.useRef(Vector2.new(0, 0))

	React.useEffect(function()
		local scaleObj = scaleRef.current
		if not scaleObj then
			return
		end
		local target = hovered and DIAMOND_HOVER_SCALE or 1
		local info = hovered and DIAMOND_TWEEN_IN or DIAMOND_TWEEN_OUT
		TweenService:Create(scaleObj, info, { Scale = target }):Play()
	end, { hovered })

	-- Icon glyph pops on hover too, independently of the diamond behind it -- same tween shape,
	-- just a slightly bigger target scale so the icon itself visibly reacts, not just the frame.
	React.useEffect(function()
		local scaleObj = iconScaleRef.current
		if not scaleObj then
			return
		end
		local target = hovered and ICON_HOVER_SCALE or 1
		local info = hovered and DIAMOND_TWEEN_IN or DIAMOND_TWEEN_OUT
		TweenService:Create(scaleObj, info, { Scale = target }):Play()
	end, { hovered })

	local diamondSide = math.min(props.w, props.h) * DIAMOND_SIDE_FRACTION
	-- QuickNav's whole canvas is drawn at design-pixel scale and then shrunk to fit the screen via
	-- one UIScale ancestor (see QuickNav's own `scale` state, passed down as props.scale). Dividing
	-- pixel constants by that factor (the old approach) blows past TextSize's ~100 render cap since
	-- the factor is tiny (~0.15), so both 20 and 40 landed on the same clamped value -- instead the
	-- tooltip below carries its own inverse UIScale (1/designScale) to cancel the ancestor's shrink,
	-- so its own children can just use ordinary, uncompensated screen-pixel constants.
	local designScale = math.max(props.scale, 0.0001)

	return e("Frame", {
		Size = UDim2.fromOffset(props.w, props.h),
		Position = UDim2.fromOffset(props.left, props.top),
		BackgroundTransparency = 1,
		Active = true,
		[React.Event.MouseEnter] = function(rbx, x, y)
			local absPos = rbx.AbsolutePosition
			lastLocalPos.current = Vector2.new(x - absPos.X, y - absPos.Y)
			setHovered(true)
		end,
		[React.Event.MouseMoved] = function(rbx, x, y)
			local absPos = rbx.AbsolutePosition
			local pos = Vector2.new(x - absPos.X, y - absPos.Y)
			lastLocalPos.current = pos
			local tooltip = tooltipRef.current
			if tooltip then
				tooltip.Position = UDim2.fromOffset(pos.X + TOOLTIP_OFFSET, pos.Y + TOOLTIP_OFFSET)
			end
		end,
		[React.Event.MouseLeave] = function()
			-- Releasing just drops the tooltip -- no fade, no effect.
			setHovered(false)
		end,
	}, {
		DiamondOuter = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(diamondSide, diamondSide),
			Rotation = 45,
			BackgroundColor3 = DIAMOND_BORDER,
			BorderSizePixel = 0,
			ZIndex = 1,
		}, {
			Scale = e("UIScale", { ref = scaleRef, Scale = 1 }),
			Corner = e("UICorner", { CornerRadius = UDim.new(0.16, 0) }),
			Stroke = e("UIStroke", {
				Color = DIAMOND_GOLD,
				Thickness = math.max(2, diamondSide * 0.03),
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
			Inner = e("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(DIAMOND_INNER_FRACTION, DIAMOND_INNER_FRACTION),
				BackgroundColor3 = DIAMOND_FILL_TOP,
				BorderSizePixel = 0,
				ZIndex = 1,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0.16, 0) }),
				Gradient = e("UIGradient", {
					Color = ColorSequence.new(DIAMOND_FILL_TOP, DIAMOND_FILL_BOTTOM),
					Rotation = 90,
				}),
			}),
		}),

		Icon = e("ImageButton", {
			Image = props.image,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(props.iconSize, props.iconSize),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			ZIndex = 2,
			[React.Event.Activated] = props.onClick,
		}, {
			Scale = e("UIScale", { ref = iconScaleRef, Scale = 1 }),
		}),

		-- Clean hover tooltip: a slightly-opaque dark pill with white text that tracks the cursor
		-- position while hovering, gone the instant MouseLeave fires (no tween, no fade). Initial
		-- Position reads lastLocalPos (already set on MouseEnter) so it appears at the cursor on
		-- the very first frame instead of snapping in from the top-left corner; every frame after
		-- that is driven by the imperative tooltipRef write in MouseMoved above, not by re-render.
		HoverTooltip = hovered and e("Frame", {
			ref = tooltipRef,
			ZIndex = 60,
			AnchorPoint = Vector2.new(0, 0),
			Position = UDim2.fromOffset(lastLocalPos.current.X + TOOLTIP_OFFSET, lastLocalPos.current.Y + TOOLTIP_OFFSET),
			AutomaticSize = Enum.AutomaticSize.XY,
			Size = UDim2.fromOffset(0, 0),
			BackgroundColor3 = TOOLTIP_BG,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
		}, {
			-- Cancels the ancestor QuickNav UIScale so everything below is plain, uncompensated
			-- screen pixels -- this is what fixes the TextSize clamp instead of dividing it away.
			CounterScale = e("UIScale", { Scale = 1 / designScale }),
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 8) }),
			Padding = e("UIPadding", {
				PaddingLeft = UDim.new(0, 14),
				PaddingRight = UDim.new(0, 14),
				PaddingTop = UDim.new(0, 8),
				PaddingBottom = UDim.new(0, 8),
			}),
			Text = e("TextLabel", {
				AutomaticSize = Enum.AutomaticSize.XY,
				Size = UDim2.fromOffset(0, 0),
				BackgroundTransparency = 1,
				Text = props.label,
				FontFace = UIFonts.DisplayBold,
				TextSize = 20,
				TextColor3 = TOOLTIP_TEXT,
			}),
		}) or nil,
	})
end

local function QuickNav(props: { onSelect: (string) -> () })
	local scale, setScale = React.useState(1)
	local containerRef = React.useRef(nil :: Frame?)

	React.useEffect(function()
		local container = containerRef.current
		if not container then
			return
		end
		local parent = container.Parent :: GuiObject
		local function recompute()
			local avail = parent.AbsoluteSize
			if avail.X <= 0 or avail.Y <= 0 then
				return
			end
			setScale(math.min(avail.X / DESIGN_W, avail.Y / DESIGN_H))
		end
		recompute()
		local conn = parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(recompute)
		return function()
			conn:Disconnect()
		end
	end, {})

	local icons: { [string]: any } = {}
	for _, icon in ipairs(ICONS) do
		icons[icon.id] = e(NavIcon, {
			image = icon.image,
			left = icon.left,
			top = icon.top,
			w = icon.w,
			h = icon.h,
			iconSize = icon.iconSize,
			label = icon.label,
			scale = scale,
			onClick = icon.panel and function()
				props.onSelect(icon.panel)
			end or nil,
		})
	end

	return e("Frame", {
		ref = containerRef,
		Size = UDim2.fromOffset(DESIGN_W, DESIGN_H),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = false,
	}, {
		Scale = e("UIScale", { Scale = scale }),
		Icons = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		}, icons),
	})
end

return QuickNav
