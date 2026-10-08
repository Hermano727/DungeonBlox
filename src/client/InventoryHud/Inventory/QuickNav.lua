--!strict
--  QuickNav -- the Tab menu's destinations (Inventory, Journal, Hearthstone, Party) as a
--  VERTICAL column of carved medallions down the right edge of the screen (2026-10-01; was a
--  row across the top, which cost every tab its top band). Click a medallion, or Up/Down
--  (Left/Right also work) to move. The column fits itself to the space Inventory/init.lua gives
--  it (QuickNavCol). The vitals no longer hang under this: the Inventory tab publishes their
--  anchor itself (ProfileMenusState.SetCarouselAnchor, from InventoryMain).
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
--
--  Art (2026-09-30, the Journal's look): carved medallions (nav_medallion /
--  nav_medallion_selected), bronze glyphs (nav_glyph_<id>) and a name plaque (nav_plaque) from
--  RS/Assets/Images/JournalUI. Any piece missing falls back to the older art below.
--
--  Adding a destination: one entry in ALL_ICONS (plus its panel in Inventory/init.lua's PANELS),
--  and a nav_glyph_<id> registry entry for its glyph.
--  Tuning: the constants below.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local ProfileMenusState = require(ReplicatedStorage:WaitForChild("ProfileMenusState"))
local DungeonMenuNet = require(script.Parent.Parent.Parent:WaitForChild("DungeonMenuNet"))
local JournalUI = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images"):WaitForChild("JournalUI"))
local e = React.createElement

local function art(key: string): any?
	local entry = (JournalUI :: any)[key]
	return (type(entry) == "table" and entry.Image ~= "") and entry or nil
end
local MEDALLION = art("nav_medallion")
local MEDALLION_SELECTED = art("nav_medallion_selected")
local PLAQUE = art("nav_plaque")

local BACKING_UNSELECTED = "rbxassetid://131438000506839"
local BACKING_SELECTED = "rbxassetid://79091640085978"

-- Older glyph for the Journal (the Stats one), used only if nav_glyph_journal is missing.
local JOURNAL_ICON_PLACEHOLDER = "rbxassetid://113519481797233"

local ALL_ICONS = {
	{ id = "inventory",   image = "rbxassetid://124308421822604", label = "Inventory" },
	{ id = "journal",     image = JOURNAL_ICON_PLACEHOLDER,       label = "Journal" },
	-- Hidden until the player has unlocked it (profile.flags.hearthstoneUnlocked, the
	-- tutorial's totem; the server refuses to use it before then anyway).
	{ id = "hearthstone", image = "rbxassetid://92412859018068",  label = "Hearthstone", unlockFlag = "hearthstoneUnlocked" },
	{ id = "party",       image = "rbxassetid://80729608864109",  label = "Party" },
}
for _, icon in ipairs(ALL_ICONS) do
	local glyph = art("nav_glyph_" .. icon.id)
	if glyph then icon.image = glyph.Image end
end

-- The destinations this profile can see.
local function visibleIcons(flags)
	local out = {}
	for _, icon in ipairs(ALL_ICONS) do
		if not icon.unlockFlag or (type(flags) == "table" and flags[icon.unlockFlag] == true) then
			table.insert(out, icon)
		end
	end
	return out
end

local TILE_MAX = 118         -- px, largest a tile gets (the row fits itself to the header)
local TILE_GAP = 26          -- MINIMUM px between tiles (the column spreads them further)
local LABEL_H = PLAQUE and 26 or 22   -- px, the name (on its plaque) under each tile
local PLAQUE_W = 1.3                  -- plaque width relative to the medallion (wider, like the blueprint)
local PLAQUE_OVERLAP = 8              -- px the plaque tucks up under the medallion
local TILE_W = PLAQUE and PLAQUE_W or 1
-- glyph size relative to its backing: the medallion's recess is smaller than the old plate
local GLYPH_FRACTION = MEDALLION and 0.52 or 0.72
local SELECTED_SCALE = 1.08
local HOVER_SCALE = 1.05
local DIM_TRANSPARENCY = MEDALLION and 0.2 or 0.35 -- unselected, not hovered
local LABEL_SELECTED = Color3.fromRGB(245, 226, 180)
local LABEL_IDLE = Color3.fromRGB(176, 164, 150)
local LABEL_EDGE = Color3.fromRGB(10, 8, 8)
local TWEEN = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function NavTile(props: {
	id: string?,
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
		Size = UDim2.fromOffset(math.floor(size * TILE_W), size + LABEL_H - (PLAQUE and PLAQUE_OVERLAP or 0)),
		BackgroundTransparency = 1,
	}, {
		Plate = e("ImageButton", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromOffset(size, size),
			BackgroundTransparency = 1,
			Image = MEDALLION and "" or (props.selected and BACKING_SELECTED or BACKING_UNSELECTED),
			ImageTransparency = transparency,
			ScaleType = Enum.ScaleType.Fit,
			AutoButtonColor = false,
			[React.Event.Activated] = props.onClick,
			[React.Event.MouseEnter] = function() setHovered(true) end,
			[React.Event.MouseLeave] = function() setHovered(false) end,
			-- The tutorial can point at a destination ("nav_journal", ...).
			ref = function(rbx)
				if rbx and props.id then rbx:SetAttribute("TutorialTarget", "nav_" .. props.id) end
			end,
		}, {
			Scale = e("UIScale", { ref = scaleRef, Scale = 1 }),
			-- The selected medallion carries its glow outside the ring: draw it bigger by that
			-- margin so both rings are the same size.
			Medallion = MEDALLION and (function()
				local sel = props.selected and MEDALLION_SELECTED
				local grow = 1
				if sel and sel.Pad and sel.Width then
					grow = sel.Width / (sel.Width - sel.Pad[1] - sel.Pad[3])
				end
				return e("ImageLabel", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromScale(grow, grow),
					BackgroundTransparency = 1,
					Image = sel and sel.Image or MEDALLION.Image,
					ImageTransparency = transparency,
					ScaleType = Enum.ScaleType.Fit,
					ZIndex = 1,
				})
			end)() or nil,
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
		Plaque = PLAQUE and e("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, size - PLAQUE_OVERLAP),
			Size = UDim2.new(1, 0, 0, LABEL_H),
			BackgroundTransparency = 1,
			Image = PLAQUE.Image,
			ImageTransparency = transparency,
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = PLAQUE.SliceCenter,
			SliceScale = PLAQUE.SliceScale or 1,
			ZIndex = 3,
		}) or nil,
		Label = e("TextLabel", {
			Position = UDim2.fromOffset(0, size - (PLAQUE and PLAQUE_OVERLAP or 0)),
			Size = UDim2.new(1, 0, 0, LABEL_H),
			BackgroundTransparency = 1,
			Text = props.label,
			FontFace = PLAQUE and UIFonts.SerifBold or UIFonts.DisplayBold,
			TextSize = PLAQUE and 15 or 16,
			TextColor3 = props.selected and LABEL_SELECTED or LABEL_IDLE,
			TextTransparency = lit and 0 or 0.25,
			TextStrokeColor3 = LABEL_EDGE,
			TextStrokeTransparency = 0.5,
			ZIndex = 4,
		}),
	})
end

local function QuickNav(props: { onSelect: (string, number) -> (), resetKey: number?, openTo: any? })
	local containerRef = React.useRef(nil :: Frame?)
	local rowRef = React.useRef(nil :: Frame?)
	local tileSize, setTileSize = React.useState(TILE_MAX)
	local selectedIndex, setSelectedIndex = React.useState(1)
	local prevIndexRef = React.useRef(1)
	local ICONS, setIcons = React.useState(function()
		local snap = DungeonMenuNet.getLastSnapshot()
		return visibleIcons(snap and snap.profile and snap.profile.flags)
	end)
	local ICON_COUNT = #ICONS
	local countRef = React.useRef(ICON_COUNT)
	countRef.current = ICON_COUNT
	React.useEffect(function()
		return DungeonMenuNet.addSnapshotListener(function(snapshot)
			local nextIcons = visibleIcons(snapshot and snapshot.profile and snapshot.profile.flags)
			setIcons(function(prev)
				if #prev == #nextIcons then return prev end -- unchanged (it only ever grows)
				return nextIcons
			end)
		end)
	end, {})

	-- Fit the row to the header: as large as TILE_MAX, smaller if the header is short or narrow.
	React.useEffect(function()
		local container = containerRef.current
		if not container then return end
		local function recompute()
			local avail = container.AbsoluteSize
			if avail.X <= 0 or avail.Y <= 0 then return end
			local byWidth = avail.X / TILE_W
			local byHeight = (avail.Y - TILE_GAP * (ICON_COUNT - 1)) / ICON_COUNT - LABEL_H + (PLAQUE and PLAQUE_OVERLAP or 0)
			setTileSize(math.max(24, math.floor(math.min(TILE_MAX, byHeight, byWidth))))
		end
		recompute()
		local conn = container:GetPropertyChangedSignal("AbsoluteSize"):Connect(recompute)
		return function() conn:Disconnect() end
	end, { ICON_COUNT })

	-- The row's real bottom-centre in screen pixels, for the vitals that hang beneath it.

	React.useEffect(function()
		local prev = prevIndexRef.current
		prevIndexRef.current = selectedIndex
		local direction = selectedIndex > prev and 1 or (selectedIndex < prev and -1 or 0)
		props.onSelect(ICONS[selectedIndex].id, direction)
		ProfileMenusState.SetDestination(ICONS[selectedIndex].id)
	end, { selectedIndex })

	-- Opened straight at a destination (ProfileMenusState.RequestOpen). A request re-renders
	-- with a new openTo only (resetKey unchanged), so the close-time reset below doesn't undo it.
	local openSeq = props.openTo and props.openTo.seq
	React.useEffect(function()
		if not props.openTo then return end
		for i, icon in ipairs(ICONS) do
			if icon.id == props.openTo.id then
				setSelectedIndex(i)
				return
			end
		end
	end, { openSeq, ICON_COUNT } :: { any })

	-- The menu closed: reopen on Inventory.
	React.useEffect(function()
		setSelectedIndex(1)
	end, { props.resetKey })

	-- Left/Right step along the row (wrapping), only while the menu is open: this component
	-- is mounted for the whole session and the ScreenGui is just toggled.
	React.useEffect(function()
		local conn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed or not ProfileMenusState.IsOpen() then return end
			if input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.Up then
				setSelectedIndex(function(i) return ((i - 2) % countRef.current) + 1 end)
			elseif input.KeyCode == Enum.KeyCode.Right or input.KeyCode == Enum.KeyCode.Down then
				setSelectedIndex(function(i) return (i % countRef.current) + 1 end)
			end
		end)
		return function() conn:Disconnect() end
	end, {})

	local tiles: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			-- Spread over the whole column: the medallions keep their size and the GAPS take the
			-- slack, so adding a destination only tightens the spacing (tiles shrink only once
			-- the gaps are down to TILE_GAP, see the size fit above).
			VerticalFlex = Enum.UIFlexAlignment.SpaceEvenly,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for i, icon in ipairs(ICONS) do
		tiles[icon.id] = e(NavTile, {
			id = icon.id,
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
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.new(0, math.floor(tileSize * TILE_W), 1, 0),
			BackgroundTransparency = 1,
		}, tiles),
	})
end

return QuickNav
