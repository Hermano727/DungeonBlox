--!strict
--  QuickNav -- persistent header carousel (StarterGui.quick nav's FigBloxUI export,
--  reworked 2026-09-13 into a sliding carousel per direct request + reference
--  screenshots, then reworked again same day: bigger icons, all 5 visible at once
--  with the two edge ones dimmed, plus arrow buttons and scroll-to-navigate). Lives
--  once at the top of the Inventory panel now (see Inventory/init.lua) instead of
--  being nested inside the main inventory screen -- selecting a destination here
--  (click any icon, the arrow buttons, Left/Right arrow keys, or scrolling while
--  hovering) drives which body Inventory/init.lua renders below it; QuickNav owns
--  its own carousel index internally and reports the selected id (plus which
--  direction the selection moved, for Inventory/init.lua's slide-in/out transition)
--  up via onSelect.
--
--  Carousel mechanics: all 5 destinations always exist in the tree, each with a
--  signed offset from the selected one in the range [-2, 2] (5 items, an odd count,
--  so every offset is unique -- see computeOffset, no tie at the antipode the way an
--  even count would have). Offset drives position (tweened, so changing the
--  selection slides everything) -- all 5 stay visible now (2026-09-13 rework: "make
--  it so there is 1 more icon visible on each side... 5 total"), with only the two
--  |offset| == 2 edge icons dimmed to 50% opacity rather than clipped out of view.
--
--  Backing art: the two reference-image assets (nonselected/selected) sit at
--  ZIndex 1, BEHIND the icon glyph (ZIndex 2, unchanged size/position) -- replacing
--  the hand-drawn procedural diamond Frame the old version drew.
--
--  "Inventory" is a real, selectable destination now (previously panel = nil meant
--  "does nothing, it's already open" back when the main screen was reached by
--  default and QuickNav sat inside it) -- with QuickNav now living in a persistent
--  header above whatever's showing, cycling back to it is how you return to the
--  main bag/equip screen from Skills/Stats/Hearthstone/Party.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local ProfileMenusState = require(ReplicatedStorage:WaitForChild("ProfileMenusState"))
local e = React.createElement

-- Reference-image backing, layered beneath the icon glyph (per request) instead of the old
-- procedural diamond Frame -- unselected vs. selected are two different source images now,
-- not one shape recolored.
local BACKING_UNSELECTED = "rbxassetid://131438000506839"
local BACKING_SELECTED = "rbxassetid://79091640085978"

local LEFT_ARROW_IMAGE = "rbxassetid://84213366573746"
local RIGHT_ARROW_IMAGE = "rbxassetid://94729541331626"

-- Icons + their backing images, sized up from the original baseline (2026-09-13, per direct
-- request). First pass tripled everything (SIZE_MULTIPLIER=3, "200% bigger" taken literally);
-- came back too large on an actual playtest, so dialed back to 2x the same day ("decrease by
-- 33%... instead 2/3 of it" -- 2/3 of the original 3x jump is 2x).
--
-- 2026-09-14 fix: SIZE_MULTIPLIER used to be baked into these design-canvas constants directly,
-- which meant it also scaled DESIGN_H/DESIGN_W below -- the exact values the auto-fit-to-header
-- `scale` (see recompute()) divides the available space by. Since UNIFORM_SIZE and DESIGN_H both
-- carried the same SIZE_MULTIPLIER factor, it canceled out of the final on-screen size
-- (UNIFORM_SIZE * scale) whenever the header's height was the binding dimension -- which it is
-- here, so changing SIZE_MULTIPLIER (tried 0.9) visibly did nothing. Fix: these constants are now
-- fixed baseline design units again, and SIZE_MULTIPLIER is applied once, separately, as an extra
-- factor on top of the auto-fit scale (see the root UIScale + designScale in QuickNav below) --
-- that composes multiplicatively no matter which axis the auto-fit is bound by.
local SIZE_MULTIPLIER = 0.9
local UNIFORM_SIZE = 900
local ICON_SIZE = 740
local ICON_HOVER_SCALE = 1.18
local BACKING_HOVER_SCALE = 1.08 -- subtler than the icon's own pop -- it's a big flat image, not a small gem
local TWEEN_IN = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TWEEN_OUT = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

-- Edge icons (|offset| == 2) render dimmed instead of clipped out now that all 5 are always
-- visible -- both the icon glyph and its backing image share this transparency.
local EDGE_TRANSPARENCY = 0.5

-- Carousel slide tween -- a touch slower/softer than the hover pop since it's moving a whole
-- icon across the row, not just nudging its own scale.
local SLIDE_TWEEN = TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local SLOT_SPACING = 1100 -- center-to-center distance between adjacent carousel slots
local VISIBLE_PAD = 260 -- headroom above/below the icon so a hover-pop scale doesn't clip vertically

-- Arrow buttons flank the 5-wide icon row -- their own reserved zone on each side of the
-- design canvas, sized independently of the nav icons themselves.
local ARROW_SIZE = UNIFORM_SIZE * 0.5
local ARROW_ZONE = ARROW_SIZE + 400
local ARROW_HOVER_SCALE = 1.15

local DESIGN_W = SLOT_SPACING * 5 + ARROW_ZONE * 2 -- all 5 slots plus both arrow zones
local DESIGN_H = UNIFORM_SIZE + VISIBLE_PAD * 2

local TOOLTIP_OFFSET = 16
local TOOLTIP_BG = Color3.fromRGB(15, 12, 10)
local TOOLTIP_TEXT = Color3.fromRGB(255, 255, 255)

-- Not too sensitive (per direct request): a mouse-wheel notch only advances the carousel
-- once every SCROLL_COOLDOWN seconds, since a single physical notch can otherwise fire
-- several InputChanged events in a row and skip more than one slot.
local SCROLL_COOLDOWN = 0.18

local ICONS = {
	{ id = "inventory",   image = "rbxassetid://124308421822604", label = "Inventory" },
	{ id = "skills",      image = "rbxassetid://73632421462187",  label = "Skills" },
	{ id = "stats",       image = "rbxassetid://113519481797233", label = "Stats" },
	{ id = "hearthstone", image = "rbxassetid://92412859018068",  label = "Hearthstone" },
	{ id = "party",       image = "rbxassetid://80729608864109",  label = "Party" },
}
local ICON_COUNT = #ICONS

-- Shortest signed distance (in slot units) from `fromIndex` to `toIndex`, wrapped around the
-- ring -- range is [-2, 2] for 5 icons, and every icon gets a distinct offset since 5 is odd.
-- Doubles as the left/right "which way did the selection move" signal (see prevIndexRef in
-- QuickNav below) -- a positive result means `toIndex` sits to the right of `fromIndex`.
local function computeOffset(toIndex: number, fromIndex: number): number
	local raw = (toIndex - fromIndex) % ICON_COUNT
	if raw > ICON_COUNT / 2 then
		raw -= ICON_COUNT
	end
	return raw
end

-- Left/Right, the arrow buttons, and scroll-wheel should only cycle the carousel while the
-- panel is actually open -- this component is mounted once and never torn down
-- (InventoryHud/init.client.lua only toggles the ScreenGui's Enabled), so the connections
-- below stay alive the whole session and need their own visibility check. ProfileMenusState
-- is the same open/closed signal InventoryHud/init.client.lua's setOpen() publishes to.
local function isMenuOpen(): boolean
	return ProfileMenusState.IsOpen()
end

local function NavIcon(props: {
	image: string,
	label: string,
	offset: number,
	onClick: () -> (),
	onHoverStart: (string, number, number) -> (),
	onHoverMove: (number, number) -> (),
	onHoverEnd: () -> (),
})
	local hovered, setHovered = React.useState(false)
	local backingScaleRef = React.useRef(nil :: UIScale?)
	local iconScaleRef = React.useRef(nil :: UIScale?)
	local posRef = React.useRef(nil :: Frame?)

	local selected = props.offset == 0
	local isEdge = math.abs(props.offset) == 2
	local transparency = isEdge and EDGE_TRANSPARENCY or 0

	-- Hover-pop tweens -- same shape QuickNav has always used. All 5 icons are clickable now
	-- (even the dimmed edge ones), so hover works everywhere, not just the center 3.
	React.useEffect(function()
		local scaleObj = backingScaleRef.current
		if not scaleObj then
			return
		end
		local target = hovered and BACKING_HOVER_SCALE or 1
		local info = hovered and TWEEN_IN or TWEEN_OUT
		TweenService:Create(scaleObj, info, { Scale = target }):Play()
	end, { hovered })

	React.useEffect(function()
		local scaleObj = iconScaleRef.current
		if not scaleObj then
			return
		end
		local target = hovered and ICON_HOVER_SCALE or 1
		local info = hovered and TWEEN_IN or TWEEN_OUT
		TweenService:Create(scaleObj, info, { Scale = target }):Play()
	end, { hovered })

	-- Slide to the new slot whenever `offset` changes -- this (not a snap) is what makes
	-- selecting a neighbor read as a carousel instead of a row of buttons swapping icons.
	React.useEffect(function()
		local inst = posRef.current
		if not inst then
			return
		end
		local targetX = props.offset * SLOT_SPACING
		TweenService:Create(inst, SLIDE_TWEEN, {
			Position = UDim2.new(0.5, targetX, 0.5, 0),
		}):Play()
	end, { props.offset })

	return e("Frame", {
		ref = posRef,
		AnchorPoint = Vector2.new(0.5, 0.5),
		-- Only matters on first mount -- every offset change after that is picked up by the
		-- useEffect above instead of this Position prop, since re-setting Position directly on
		-- every render would fight the in-flight tween.
		Position = UDim2.new(0.5, props.offset * SLOT_SPACING, 0.5, 0),
		Size = UDim2.fromOffset(UNIFORM_SIZE, UNIFORM_SIZE),
		BackgroundTransparency = 1,
		Active = true,
		[React.Event.MouseEnter] = function(_, x, y)
			setHovered(true)
			props.onHoverStart(props.label, x, y)
		end,
		[React.Event.MouseMoved] = function(_, x, y)
			props.onHoverMove(x, y)
		end,
		[React.Event.MouseLeave] = function()
			setHovered(false)
			props.onHoverEnd()
		end,
	}, {
		Backing = e("ImageLabel", {
			Image = selected and BACKING_SELECTED or BACKING_UNSELECTED,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ImageTransparency = transparency,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 1,
		}, {
			Scale = e("UIScale", { ref = backingScaleRef, Scale = 1 }),
		}),

		Icon = e("ImageButton", {
			Image = props.image,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
			BackgroundTransparency = 1,
			ImageTransparency = transparency,
			AutoButtonColor = false,
			Active = true,
			ZIndex = 2,
			[React.Event.Activated] = props.onClick,
		}, {
			Scale = e("UIScale", { ref = iconScaleRef, Scale = 1 }),
		}),
	})
end

local function ArrowButton(props: { image: string, position: UDim2, onClick: () -> () })
	local hovered, setHovered = React.useState(false)
	local scaleRef = React.useRef(nil :: UIScale?)

	React.useEffect(function()
		local scaleObj = scaleRef.current
		if not scaleObj then
			return
		end
		local target = hovered and ARROW_HOVER_SCALE or 1
		local info = hovered and TWEEN_IN or TWEEN_OUT
		TweenService:Create(scaleObj, info, { Scale = target }):Play()
	end, { hovered })

	return e("ImageButton", {
		Image = props.image,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = props.position,
		Size = UDim2.fromOffset(ARROW_SIZE, ARROW_SIZE),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = 3,
		[React.Event.Activated] = props.onClick,
		[React.Event.MouseEnter] = function()
			setHovered(true)
		end,
		[React.Event.MouseLeave] = function()
			setHovered(false)
		end,
	}, {
		Scale = e("UIScale", { ref = scaleRef, Scale = 1 }),
	})
end

local function QuickNav(props: { onSelect: (string, number) -> (), resetKey: number? })
	local scale, setScale = React.useState(1)
	local containerRef = React.useRef(nil :: Frame?)
	local selectedIndex, setSelectedIndex = React.useState(1)
	local hover, setHover = React.useState(nil :: { label: string, x: number, y: number }?)
	local hoveringCarouselRef = React.useRef(false)
	local lastScrollRef = React.useRef(0)
	local prevIndexRef = React.useRef(1)

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

	-- Publishes the actual rendered icon row's bottom-center point (real screen pixels) so
	-- HealthClient/EnergyClient can hang the HP/Energy/Hunger/Potion cluster directly beneath
	-- the carousel (2026-09-13, per direct request) without hand-duplicating this component's
	-- own scale-to-fit math in two other files -- see ProfileMenusState.SetCarouselAnchor's doc
	-- comment for why. Reads container.AbsoluteSize/AbsolutePosition directly (not the `scale`
	-- state above) so this always reflects what actually got rendered, not what render pass is
	-- mid-flight. UNIFORM_SIZE/2 (not half of DESIGN_H) because DESIGN_H also includes
	-- VISIBLE_PAD headroom above/below the icons for the hover-pop scale -- using the full
	-- container bottom would leave an oversized, unintended gap between the icons and whatever
	-- hangs below them.
	React.useEffect(function()
		local container = containerRef.current
		if not container then
			return
		end
		local function publishAnchor()
			local size = container.AbsoluteSize
			local pos = container.AbsolutePosition
			if size.Y <= 0 then
				return
			end
			local scaleY = size.Y / DESIGN_H
			local centerX = pos.X + size.X / 2
			local iconBottomY = pos.Y + size.Y / 2 + (UNIFORM_SIZE / 2) * scaleY
			ProfileMenusState.SetCarouselAnchor(Vector2.new(centerX, iconBottomY))
		end
		publishAnchor()
		local c1 = container:GetPropertyChangedSignal("AbsolutePosition"):Connect(publishAnchor)
		local c2 = container:GetPropertyChangedSignal("AbsoluteSize"):Connect(publishAnchor)
		return function()
			c1:Disconnect()
			c2:Disconnect()
		end
	end, {})

	-- Reports the selected destination up every time it changes, together with which way it
	-- moved (-1 left / 0 unchanged / 1 right, via computeOffset's sign) -- Inventory/init.lua
	-- uses the direction to slide its content area the same way the carousel just moved.
	-- Fires once on mount too (direction 0), so Inventory/init.lua knows the default is
	-- "inventory" without duplicating ICONS[1]'s id.
	React.useEffect(function()
		local prev = prevIndexRef.current
		prevIndexRef.current = selectedIndex
		local delta = computeOffset(selectedIndex, prev)
		local direction = delta > 0 and 1 or (delta < 0 and -1 or 0)
		props.onSelect(ICONS[selectedIndex].id, direction)
	end, { selectedIndex })

	-- resetKey bumps every time the whole Inventory UI closes (see InventoryHud/init.client.lua)
	-- -- snap the carousel back to "inventory" so reopening doesn't resume on whatever was last
	-- selected, mirroring the old push/pop stack's reset behavior.
	React.useEffect(function()
		setSelectedIndex(1)
	end, { props.resetKey })

	-- Shared by the Left/Right keys, the arrow buttons, and the scroll wheel -- one stepping
	-- function so all four input paths move the carousel identically.
	local function stepSelection(delta: number)
		setSelectedIndex(function(i)
			if delta < 0 then
				return ((i - 2) % ICON_COUNT) + 1
			else
				return (i % ICON_COUNT) + 1
			end
		end)
	end

	-- Left/Right arrow keys cycle the carousel same as clicking a neighbor. Connected once --
	-- this component now lives for the whole session (persistent header, never unmounted), so
	-- isMenuOpen() guards against firing while the Inventory panel is closed.
	React.useEffect(function()
		local conn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed or not isMenuOpen() then
				return
			end
			if input.KeyCode == Enum.KeyCode.Left then
				stepSelection(-1)
			elseif input.KeyCode == Enum.KeyCode.Right then
				stepSelection(1)
			end
		end)
		return function()
			conn:Disconnect()
		end
	end, {})

	-- Scroll wheel cycles the carousel too, but only while the cursor is actually over it
	-- (hoveringCarouselRef, set by the root Frame's MouseEnter/MouseLeave below) and gated by
	-- SCROLL_COOLDOWN so one physical notch can't skip multiple slots ("not too sensitive",
	-- per direct request). A ref, not React state, for both the hover flag and the cooldown
	-- clock -- this connection is set up once and needs to read their LIVE values without
	-- having to reconnect every time either changes.
	React.useEffect(function()
		local conn = UserInputService.InputChanged:Connect(function(input, gameProcessed)
			if gameProcessed or not isMenuOpen() or not hoveringCarouselRef.current then
				return
			end
			if input.UserInputType ~= Enum.UserInputType.MouseWheel then
				return
			end
			local now = os.clock()
			if now - lastScrollRef.current < SCROLL_COOLDOWN then
				return
			end
			lastScrollRef.current = now
			-- Scroll up = previous (left), same convention HotbarHud's own slot-scroll uses.
			stepSelection(input.Position.Z > 0 and -1 or 1)
		end)
		return function()
			conn:Disconnect()
		end
	end, {})

	-- Hover state lives up here (not inside NavIcon) so the tooltip can be rendered as a
	-- sibling of the icon row instead of nested inside one icon's own Frame.
	local function onHoverStart(label: string, x: number, y: number)
		local container = containerRef.current
		if not container then
			return
		end
		local rootPos = container.AbsolutePosition
		setHover({ label = label, x = x - rootPos.X, y = y - rootPos.Y })
	end

	local function onHoverMove(x: number, y: number)
		local container = containerRef.current
		if not container then
			return
		end
		local rootPos = container.AbsolutePosition
		setHover(function(prev)
			if not prev then
				return prev
			end
			return { label = prev.label, x = x - rootPos.X, y = y - rootPos.Y }
		end)
	end

	local function onHoverEnd()
		setHover(nil)
	end

	local icons: { [string]: any } = {}
	for i, icon in ipairs(ICONS) do
		icons[icon.id] = e(NavIcon, {
			image = icon.image,
			label = icon.label,
			offset = computeOffset(i, selectedIndex),
			onClick = function()
				setSelectedIndex(i)
			end,
			onHoverStart = onHoverStart,
			onHoverMove = onHoverMove,
			onHoverEnd = onHoverEnd,
		})
	end

	-- SIZE_MULTIPLIER is folded in here (not into the design-canvas constants above) -- see the
	-- 2026-09-14 comment near SIZE_MULTIPLIER's definition for why. This is the ONE place that
	-- controls final on-screen icon size now.
	local designScale = math.max(scale * SIZE_MULTIPLIER, 0.0001)

	return e("Frame", {
		ref = containerRef,
		Size = UDim2.fromOffset(DESIGN_W, DESIGN_H),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = true,
		ClipsDescendants = false,
		[React.Event.MouseEnter] = function()
			hoveringCarouselRef.current = true
		end,
		[React.Event.MouseLeave] = function()
			hoveringCarouselRef.current = false
		end,
	}, {
		Scale = e("UIScale", { Scale = scale * SIZE_MULTIPLIER }),

		LeftArrow = e(ArrowButton, {
			image = LEFT_ARROW_IMAGE,
			position = UDim2.new(0, ARROW_ZONE / 2, 0.5, 0),
			onClick = function()
				stepSelection(-1)
			end,
		}),

		RightArrow = e(ArrowButton, {
			image = RIGHT_ARROW_IMAGE,
			position = UDim2.new(1, -ARROW_ZONE / 2, 0.5, 0),
			onClick = function()
				stepSelection(1)
			end,
		}),

		Icons = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		}, icons),

		HoverTooltip = hover and e("Frame", {
			ZIndex = 60,
			AnchorPoint = Vector2.new(0, 0),
			-- Bug found 2026-09-13 (playtest report: tooltip renders above the icons, off the
			-- top of the screen): hover.x/hover.y are already real screen-pixel deltas (see
			-- onHoverStart below, which subtracts container.AbsolutePosition), but this Frame
			-- is a descendant of the root-level "Scale" UIScale above, which scales EVERY
			-- descendant's offset-based Position/Size, not just the icon row it was meant for
			-- -- so the intended real-pixel offset was getting silently shrunk by `designScale`
			-- a second time, collapsing the tooltip toward the container's own top-left corner
			-- (well above the icons themselves, since the design canvas has a lot of vertical
			-- headroom above them for the hover-pop scale -- see VISIBLE_PAD) instead of
			-- tracking the cursor. Dividing by designScale here cancels that out, same trick
			-- CounterScale below already used for this frame's own CONTENT size. math.max(...,
			-- 0) on the Y term is an extra floor so this can never resolve above the container's
			-- own top edge even in some future edge case -- "guaranteed safe" per direct
			-- request, on top of fixing the actual bug.
			Position = UDim2.fromOffset(
				(hover.x + TOOLTIP_OFFSET) / designScale,
				(math.max(hover.y, 0) + TOOLTIP_OFFSET) / designScale
			),
			AutomaticSize = Enum.AutomaticSize.XY,
			Size = UDim2.fromOffset(0, 0),
			BackgroundColor3 = TOOLTIP_BG,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
		}, {
			-- Cancels the Root-level UIScale so this frame's own children are plain,
			-- uncompensated screen pixels (same trick the old in-icon tooltip used).
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
				Text = hover.label,
				FontFace = UIFonts.DisplayBold,
				TextSize = 20,
				TextColor3 = TOOLTIP_TEXT,
			}),
		}) or nil,
	})
end

return QuickNav
