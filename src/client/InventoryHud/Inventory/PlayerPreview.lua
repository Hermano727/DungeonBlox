--!strict
--  PlayerPreview -- the equipment/gear panel content.
--
--  Moved here from the old standalone PlayerPreviewHud (deleted) now that
--  this panel is one of three pieces composed inside the Inventory root
--  component instead of its own always-on floating ScreenGui. Only change
--  from that version: PANEL_FIT_FRACTION, since this now fits a column of
--  the Inventory layout instead of the whole screen.
--
--  Ported in intent from StarterGui.Player Preview (FigBloxUI's Figma
--  export), cleaned up from the raw export in three ways:
--
--  1. Positions come from each instance's FigBloxUIData `bounds` (clean
--     integer pixel rects in the original 3037x3748 Figma canvas) instead of
--     the noisy Size/Position UDim2 the plugin wrote -- things like
--     {-5.05e-05, 511} are floating-point residue from the plugin's own
--     scale/offset split, not anything meaningful.
--  2. The 8 equipment-slot labels were positioned by hand in Figma and each
--     drifted a different amount (33px-82px) off-center above its box --
--     that inconsistency was the "off center" look. Replaced with one
--     EquipmentSlot component that derives each label's X from its own
--     box's center, so every slot is now exactly centered, using a single
--     LABEL_GAP constant instead of 8 slightly-different hand-placed numbers.
--  3. The panel keeps FigBloxUI's "author at native Figma pixel size, then
--     scale the whole thing down to fit" approach (Container below is a
--     fixed 3037x3748 canvas) because that's what makes UIStroke thickness,
--     text size, and corner radii all shrink together in proportion.
--     Difference from the raw export: the UIScale factor is now computed
--     live off the panel's actual on-screen space (contain-fit), instead of
--     a frozen 0.186 baked in at whatever size Studio's viewport happened
--     to be at export.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
local RarityBorder = require(script.Parent:WaitForChild("RarityBorder"))
local LegendaryGlow = require(script.Parent:WaitForChild("LegendaryGlow"))
local CharacterViewport = require(script.Parent:WaitForChild("CharacterViewport"))
local e = React.createElement

-- Native Figma canvas size (Container's FigBloxUIData.geometry.bounds).
local DESIGN_W, DESIGN_H = 3037, 3748

local GOLD_FRAME_IMAGE = "rbxassetid://134017400103368"

local THEME = {
	PanelBg    = Color3.fromRGB(26, 18, 11),    -- Container's background
	SlotBg     = Color3.fromRGB(20, 16, 13),    -- equipment slot fill
	SlotBorder = UITheme.Gold,  -- muted gold UIStroke -- see UITheme
	LabelText  = Color3.fromRGB(240, 230, 210), -- same #F0E6D2 as XpHud's THEME.TextPrimary
}

-- Equipment slot geometry, reduced from the FigBloxUI bounds to the handful
-- of numbers that actually vary: two column left-edges, four row top-edges
-- (evenly spaced 809px apart), and one shared box size.
local BOX_SIZE     = 510
local COL_LEFT_X   = 156
local COL_RIGHT_X  = 2335
-- Centre column: a single slot (Shield) sitting between the two columns on the
-- bottom row, so the preview area above it narrows rather than the grid growing
-- a lopsided 5th row. Derived from the other two columns so it stays centred if
-- either edge moves.
local COL_CENTER_X = ((COL_LEFT_X + BOX_SIZE) + COL_RIGHT_X) / 2 - BOX_SIZE / 2
local ROW_TOPS     = { 405, 1214, 2023, 2832 }
local LABEL_HEIGHT = 144
local LABEL_GAP    = 40 -- standardized; the export had this at 33-82px per label, hence "off center"
local PANEL_FIT_FRACTION = 0.96 -- fits its column in the Inventory layout, not the whole screen

local SLOTS = {
	{ id = "Helmet",     label = "Helmet",      column = "Left",  row = 1, slot = "Helm" },
	{ id = "Chestplate", label = "Chestplate",  column = "Left",  row = 2, slot = "Chest" },
	{ id = "Leggings",   label = "Leggings",    column = "Left",  row = 3, slot = "Legs" },
	{ id = "Boots",      label = "Boots",       column = "Left",  row = 4, slot = "Boots" },
	{ id = "Weapon",     label = "Weapon",      column = "Right", row = 1, slot = "Weapon" },
	{ id = "Bow",        label = "Bow",         column = "Right", row = 2, slot = "Bow" },
	{ id = "Pickaxe",    label = "Pickaxe",     column = "Right", row = 3, slot = "Pickaxe" },
	{ id = "FishingRod", label = "Fishing Rod", column = "Right", row = 4, slot = "FishingSpear" },
	{ id = "Shield",     label = "Shield",      column = "Center", row = 4, slot = "Shield" },
}

type SlotProps = {
	id: string, -- NOT `key` -- React reserves that prop name for its own reconciliation
	            -- and strips it before the component ever sees props, so `props.key`
	            -- is always nil.
	label: string,
	column: "Left" | "Right" | "Center",
	row: number,
	slot: string,
	item: any?,
	onClick: (() -> ())?,
	onRightClick: ((x: number, y: number) -> ())?,
	onHoverStart: ((x: number, y: number) -> ())?,
	onHoverEnd: (() -> ())?,
	-- Fires on MouseButton1 InputBegan, in ADDITION to (never instead of) Activated above --
	-- see InventoryMain's press/drag effect. Same pattern as ItemSlot.lua's own onPressStart,
	-- so hold-drag works identically whether the item started in the bag or an equip box.
	onPressStart: ((x: number, y: number) -> ())?,
}

-- Box and Label are SIBLINGS (via a Fragment) both positioned in
-- Container-absolute coordinates -- nesting Label inside Box's own
-- coordinate space was the original bug that dropped every label but Helmet.
local function EquipmentSlot(props: SlotProps)
	local boxLeft = COL_RIGHT_X
	if props.column == "Left" then
		boxLeft = COL_LEFT_X
	elseif props.column == "Center" then
		boxLeft = COL_CENTER_X
	end
	local boxTop = ROW_TOPS[props.row]
	local centerX = boxLeft + BOX_SIZE / 2
	local item = props.item

	-- GetRarityForItem (not raw item.rarity) so catalog-only grants that never had `rarity`
	-- stamped onto their owned record (e.g. a dev-granted AdminSword) still resolve their
	-- rarity via the catalog's own Rarity field instead of silently rendering unrarity'd.
	local rarity = item and ItemDefinitions.GetRarityForItem(item) or nil

	-- Rarity-colored gradient border when a piece is equipped (same look/component as the bag
	-- slots), falling back to the plain gold outline the export shipped with when the slot is
	-- empty -- an empty equip box isn't "a rarity", so it shouldn't render as one.
	-- Thickness (8) must match ItemSlot.lua's own three RarityBorder call sites -- this
	-- component reimplements the bag slot's border logic instead of using ItemSlot, so
	-- nothing enforces that automatically. See the CLAUDE.md note on this (2026-08: bag
	-- slots were rendering at thickness 3 while these rendered at 8, so an equipped item
	-- had a bold outline and the same item sitting in the bag looked borderless).
	local boxChildren: { [string]: any } = {
		Stroke = item and e(RarityBorder, { rarity = rarity, thickness = 8 })
			or e(RarityBorder, { color = THEME.SlotBorder, thickness = 8 }),
	}

	if item and rarity == "Legendary" then
		-- Glow sits behind the icon (bumped to ZIndex 4 below) and the Stroke/Hit button.
		boxChildren.Glow = e(LegendaryGlow, { zIndex = 1 })
	end

	if item then
		-- GetIconForItem (not the itemId-only GetIcon) so procedurally generated mob drops --
		-- which never carry an itemId -- still resolve an icon via their tier + weapon/armor kind.
		local icon = ItemDefinitions.GetIconForItem(item)
		if type(icon) == "string" and icon ~= "" then
			boxChildren.Icon = e("ImageLabel", {
				-- Icon should take up the majority of the slot -- bumped from 0.8 to 0.92.
				Image = icon,
				Size = UDim2.fromScale(0.92, 0.92),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				ScaleType = Enum.ScaleType.Fit,
				-- Bumped from 2 to 4 so it always sits above LegendaryGlow's 3 layers (1-3),
				-- regardless of Lua dict child-ordering; still below Hit's 5.
				ZIndex = 4,
			})
		end
	end

	boxChildren.Hit = e("ImageButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Image = "",
		ZIndex = 5,
		[React.Event.Activated] = props.onClick,
		[React.Event.MouseEnter] = props.onHoverStart and function(_rbx, x, y)
			if props.onHoverStart then props.onHoverStart(x, y) end
		end or nil,
		[React.Event.MouseLeave] = props.onHoverEnd,
		[React.Event.InputBegan] = function(_rbx, input)
			if input.UserInputType == Enum.UserInputType.MouseButton2 and props.onRightClick then
				props.onRightClick(input.Position.X, input.Position.Y)
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 and props.onPressStart then
				-- Possible hold-drag start (equip box -> bag, i.e. drag-to-unequip). Whether
				-- this becomes a real drag is decided by movement-past-threshold up in
				-- InventoryMain -- this button doesn't know or care, and Activated above
				-- still fires normally for an actual click.
				props.onPressStart(input.Position.X, input.Position.Y)
			end
		end,
	})

	local labelText = string.upper(item and ItemDefinitions.GetDisplayNameForItem(item) or props.label)

	return e(React.Fragment, nil, {
		[props.id .. "Box"] = e("Frame", {
			Size = UDim2.fromOffset(BOX_SIZE, BOX_SIZE),
			Position = UDim2.fromOffset(boxLeft, boxTop),
			BackgroundColor3 = THEME.SlotBg,
			BorderSizePixel = 0,
			ClipsDescendants = true, -- fine -- only a future item icon/viewport lives inside this box
		}, boxChildren),

		[props.id .. "Label"] = e("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromOffset(centerX, boxTop - LABEL_GAP),
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, LABEL_HEIGHT),
			BackgroundTransparency = 1,
			Text = labelText,
			FontFace = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold),
			TextSize = 100,
			TextColor3 = THEME.LabelText,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
		}),
	})
end

export type PlayerPreviewProps = {
	equipped: { [string]: string }?,
	inventory: { [string]: any }?,
	onSlotClick: ((slotName: string) -> ())?,
	onSlotRightClick: ((slotName: string, uuid: string?, x: number, y: number) -> ())?,
	onHoverStart: ((item: any, x: number, y: number) -> ())?,
	onHoverEnd: (() -> ())?,
	-- Hold-drag support, iteration 2 (see InventoryMain). onSlotEnter/onSlotLeave fire for
	-- EVERY equip box, empty or not -- an empty box is still a legal drop target (e.g.
	-- dragging an unequipped weapon in) -- unlike onHoverStart/onHoverEnd above, which stay
	-- tooltip-only and so only make sense when the box is occupied.
	onSlotPressStart: ((slotName: string, uuid: string?, x: number, y: number) -> ())?,
	onSlotEnter: ((slotName: string) -> ())?,
	onSlotLeave: ((slotName: string) -> ())?,
}

local function PlayerPreview(props: PlayerPreviewProps?)
	local safeProps: PlayerPreviewProps = props or {}
	local equipped = safeProps.equipped or {}
	local inventory = safeProps.inventory or {}

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
			setScale(math.min(avail.X / DESIGN_W, avail.Y / DESIGN_H) * PANEL_FIT_FRACTION)
		end
		recompute()
		local conn = parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(recompute)
		return function()
			conn:Disconnect()
		end
	end, {})

	local slots: { [string]: any } = {}
	for _, slotDef in ipairs(SLOTS) do
		local uuid = equipped[slotDef.slot]
		local item = uuid and inventory[uuid]
		local slotProps = table.clone(slotDef)
		slotProps.item = item
		slotProps.onClick = safeProps.onSlotClick and function()
			safeProps.onSlotClick(slotDef.slot)
		end or nil
		slotProps.onRightClick = safeProps.onSlotRightClick and function(x, y)
			safeProps.onSlotRightClick(slotDef.slot, uuid, x, y)
		end or nil
		-- onHoverStart/onHoverEnd now always run (previously gated on `item`) so
		-- onSlotEnter/onSlotLeave fire for empty equip boxes too -- see the PlayerPreviewProps
		-- comment above. The original item-gated tooltip call just moves inside, unchanged.
		slotProps.onHoverStart = function(x, y)
			if safeProps.onSlotEnter then
				safeProps.onSlotEnter(slotDef.slot)
			end
			if item and safeProps.onHoverStart then
				safeProps.onHoverStart(item, x, y)
			end
		end
		slotProps.onHoverEnd = function()
			if safeProps.onSlotLeave then
				safeProps.onSlotLeave(slotDef.slot)
			end
			if safeProps.onHoverEnd then
				safeProps.onHoverEnd()
			end
		end
		slotProps.onPressStart = safeProps.onSlotPressStart and function(x, y)
			safeProps.onSlotPressStart(slotDef.slot, uuid, x, y)
		end or nil
		slots[slotDef.id] = e(EquipmentSlot, slotProps)
	end

	return e("Frame", {
		ref = containerRef,
		Size = UDim2.fromOffset(DESIGN_W, DESIGN_H),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = THEME.PanelBg,
		BorderSizePixel = 0,
		ClipsDescendants = false, -- the gold frame image below intentionally bleeds past the edges
	}, {
		Scale = e("UIScale", { Scale = scale }),

		Backdrop = e(CharacterViewport, {
			equipped = equipped,
			size = UDim2.fromOffset(1318, 2963),
			position = UDim2.fromOffset(839, 417),
			zIndex = 1,
		}),

		Slots = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 2,
		}, slots),

		GoldFrame = e("ImageLabel", {
			Image = GOLD_FRAME_IMAGE,
			Size = UDim2.fromOffset(3410, 4125),
			Position = UDim2.fromOffset(-180, -186),
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 3,
		}),
	})
end

return PlayerPreview
