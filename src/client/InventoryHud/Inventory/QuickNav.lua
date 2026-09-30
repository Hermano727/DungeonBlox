--!strict
--  QuickNav -- the Tab menu's top navigation row (2026-09-30 rework: was a sliding
--  carousel with arrows and 5 visible slots; now EVERY destination sits in one fixed
--  row across the top at once, like a console game's menu tabs). Click an icon, or use
--  Left/Right, to move between Inventory / Skills / Stats / Journal / Hearthstone / Party.
--
--  Each destination: the backing plate (selected / unselected art), its glyph, and its
--  name underneath. The selected one is lit and slightly larger; the rest are dimmed
--  until hovered.
--
--  Contract with Inventory/init.lua (unchanged from the carousel, so nothing else moved):
--    onSelect(key, direction)  fires on every change (and once on mount, direction 0);
--                              direction is -1 / 1 by where the new tab sits relative to
--                              the old one, which drives SlidingBody's slide.
--    resetKey                  bumps when the menu closes -> back to "inventory".
--  It also publishes the row's bottom-centre point through
--  ProfileMenusState.SetCarouselAnchor, which HealthClient/EnergyClient hang the vitals
--  from (name kept for those callers).
--
--  Adding a destination: one entry in ICONS (plus its panel in Inventory/init.lua's PANELS).
--  Tuning: the constants below.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local ProfileMenusState = require(ReplicatedStorage:WaitForChild("ProfileMenusState"))
local e = React.createElement

local BACKING_UNSELECTED = "rbxassetid://131438000506839"
local BACKING_SELECTED = "rbxassetid://79091640085978"

-- PLACEHOLDER (2026-09-17): the Journal has no art of its own yet and reuses the Stats glyph.
local JOURNAL_ICON_PLACEHOLDER = "rbxassetid://113519481797233"

local ICONS = {
	{ id = "inventory",   image = "rbxassetid://124308421822604", label = "Inventory" },
	{ id = "skills",      image = "rbxassetid://73632421462187",  label = "Skills" },
	{ id = "stats",       image = "rbxassetid://113519481797233", label = "Stats" },
	{ id = "journal",     image = JOURNAL_ICON_PLACEHOLDER,       label = "Journal" },
	{ id = "hearthstone", image = "rbxassetid://92412859018068",  label = "Hearthstone" },
	{ id = "party",       image = "rbxassetid://80729608864109",  label = "Party" },
}
local ICON_COUNT = #ICONS

local TILE_MAX = 118         -- px, largest a tile gets (the row fits itself to the header)
local TILE_GAP = 26          -- px between tiles
local LABEL_H = 22           -- px, the name under each tile
local GLYPH_FRACTION = 0.72  -- glyph size relative to its backing plate
local SELECTED_SCALE = 1.08
local HOVER_SCALE = 1.05
local DIM_TRANSPARENCY = 0.35 -- unselected, not hovered
local LABEL_SELECTED = Color3.fromRGB(245, 226, 180)
local LABEL_IDLE = Color3.fromRGB(176, 164, 150)
local LABEL_EDGE = Color3.fromRGB(10, 8, 8)
local TWEEN = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function NavTile(props: {
	image: string,
	label: string,
	selected: boolean,
	size: number,
	order: number,
	onClick: () -> (),
})
	local hovered, setHovered = React.useState(false)
	local scaleRef = React.useRef(nil :: UIScale?)

	React.useEffect(function()
		local scaleObj = scaleRef.current
		if not scaleObj then return end
		local target = props.selected and SELECTED_SCALE or (hovered and HOVER_SCALE or 1)
		TweenService:Create(scaleObj, TWEEN, { Scale = target }):Play()
	end, { hovered, props.selected } :: { any })

	local lit = props.selected or hovered
	local transparency = lit and 0 or DIM_TRANSPARENCY
	local size = props.size

	return e("Frame", {
		LayoutOrder = props.order,
		Size = UDim2.fromOffset(size, size + LABEL_H),
		BackgroundTransparency = 1,
	}, {
		Plate = e("ImageButton", {
			Size = UDim2.fromOffset(size, size),
			BackgroundTransparency = 1,
			Image = props.selected and BACKING_SELECTED or BACKING_UNSELECTED,
			ImageTransparency = transparency,
			ScaleType = Enum.ScaleType.Fit,
			AutoButtonColor = false,
			[React.Event.Activated] = props.onClick,
			[React.Event.MouseEnter] = function() setHovered(true) end,
			[React.Event.MouseLeave] = function() setHovered(false) end,
		}, {
			Scale = e("UIScale", { ref = scaleRef, Scale = 1 }),
			Glyph = e("ImageLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(GLYPH_FRACTION, GLYPH_FRACTION),
				BackgroundTransparency = 1,
				Image = props.image,
				ImageTransparency = transparency,
				ScaleType = Enum.ScaleType.Fit,
				ZIndex = 2,
			}),
		}),
		Label = e("TextLabel", {
			Position = UDim2.fromOffset(0, size),
			Size = UDim2.new(1, 0, 0, LABEL_H),
			BackgroundTransparency = 1,
			Text = props.label,
			FontFace = UIFonts.DisplayBold,
			TextSize = 16,
			TextColor3 = props.selected and LABEL_SELECTED or LABEL_IDLE,
			TextTransparency = lit and 0 or 0.25,
			TextStrokeColor3 = LABEL_EDGE,
			TextStrokeTransparency = 0.5,
		}),
	})
end

local function QuickNav(props: { onSelect: (string, number) -> (), resetKey: number? })
	local containerRef = React.useRef(nil :: Frame?)
	local rowRef = React.useRef(nil :: Frame?)
	local tileSize, setTileSize = React.useState(TILE_MAX)
	local selectedIndex, setSelectedIndex = React.useState(1)
	local prevIndexRef = React.useRef(1)

	-- Fit the row to the header: as large as TILE_MAX, smaller if the header is short or narrow.
	React.useEffect(function()
		local container = containerRef.current
		if not container then return end
		local function recompute()
			local avail = container.AbsoluteSize
			if avail.X <= 0 or avail.Y <= 0 then return end
			local byHeight = avail.Y - LABEL_H
			local byWidth = (avail.X - TILE_GAP * (ICON_COUNT - 1)) / ICON_COUNT
			setTileSize(math.max(24, math.floor(math.min(TILE_MAX, byHeight, byWidth))))
		end
		recompute()
		local conn = container:GetPropertyChangedSignal("AbsoluteSize"):Connect(recompute)
		return function() conn:Disconnect() end
	end, {})

	-- The row's real bottom-centre in screen pixels, for the vitals that hang beneath it.
	React.useEffect(function()
		local row = rowRef.current
		if not row then return end
		local function publishAnchor()
			local size, pos = row.AbsoluteSize, row.AbsolutePosition
			if size.Y <= 0 then return end
			ProfileMenusState.SetCarouselAnchor(Vector2.new(pos.X + size.X / 2, pos.Y + size.Y))
		end
		publishAnchor()
		local c1 = row:GetPropertyChangedSignal("AbsolutePosition"):Connect(publishAnchor)
		local c2 = row:GetPropertyChangedSignal("AbsoluteSize"):Connect(publishAnchor)
		return function()
			c1:Disconnect()
			c2:Disconnect()
		end
	end, {})

	React.useEffect(function()
		local prev = prevIndexRef.current
		prevIndexRef.current = selectedIndex
		local direction = selectedIndex > prev and 1 or (selectedIndex < prev and -1 or 0)
		props.onSelect(ICONS[selectedIndex].id, direction)
	end, { selectedIndex })

	-- The menu closed: reopen on Inventory.
	React.useEffect(function()
		setSelectedIndex(1)
	end, { props.resetKey })

	-- Left/Right step along the row (wrapping), only while the menu is open: this component
	-- is mounted for the whole session and the ScreenGui is just toggled.
	React.useEffect(function()
		local conn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed or not ProfileMenusState.IsOpen() then return end
			if input.KeyCode == Enum.KeyCode.Left then
				setSelectedIndex(function(i) return ((i - 2) % ICON_COUNT) + 1 end)
			elseif input.KeyCode == Enum.KeyCode.Right then
				setSelectedIndex(function(i) return (i % ICON_COUNT) + 1 end)
			end
		end)
		return function() conn:Disconnect() end
	end, {})

	local tiles: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, TILE_GAP),
		}),
	}
	for i, icon in ipairs(ICONS) do
		tiles[icon.id] = e(NavTile, {
			image = icon.image,
			label = icon.label,
			selected = i == selectedIndex,
			size = tileSize,
			order = i,
			onClick = function() setSelectedIndex(i) end,
		})
	end

	return e("Frame", {
		ref = containerRef,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		Row = e("Frame", {
			ref = rowRef,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(0, tileSize + LABEL_H),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
		}, tiles),
	})
end

return QuickNav
