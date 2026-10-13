--!strict
--  PlayerPreview -- the Inventory tab's left side (rebuilt 2026-09-30 as the "courtyard
--  diorama"): your character standing on the painted flagstones (CharacterViewport, drag to
--  turn), with the ten gear slots as carved sockets around it:
--
--      Helm
--      Chest      character     Weapon   Pickaxe        } the tool column hangs on a timber
--      Legs                     Shield   Fishing Spear  } rack (InventoryUI.TOOL_RACK), each
--      Boots                    Bow      Mount          } socket on one of its iron bands
--
--  (2026-10-12: the profession tools left their small sockets under the feet for full-size ones
--  beside the combat column, joined by Mount, which always shows the fastest saddle you own;
--  the canvas widened, so the satchel moved right.) The tool sockets show an engraved disc
--  (InventoryUI.SOCKET_DISCS: a pickaxe / fishing spear / horse head) so an empty one says
--  what goes there.
--
--  The courtyard itself is InventoryBackdrop (its own ScreenGui, behind the menu).
--
--  SLOTS below is the UI-facing source of truth for which equip slots are real (see the
--  CLAUDE.md inventory notes). Props are unchanged from the old boxed panel, so InventoryMain's
--  click / right-click / tooltip / hold-drag wiring works as before: every socket reports
--  enter/leave (empty ones are drop targets), occupied ones also hover for the tooltip.
--
--  Laid out on a fixed DESIGN canvas, contain-fit into whatever space the column has (UIScale).
--  Socket art: JournalUI nav_medallion / nav_medallion_selected (hovered) and nav_plaque for
--  the names, the same carved rings as the Tab menu's top row. The rarity ring is drawn in
--  code (RarityBorder on a circle), so Legendary still shimmers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local ProfileMenusState = require(ReplicatedStorage:WaitForChild("ProfileMenusState"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local RarityBorder = require(script.Parent:WaitForChild("RarityBorder"))
local LegendaryGlow = require(script.Parent:WaitForChild("LegendaryGlow"))
local EnchantBadge = require(script.Parent:WaitForChild("EnchantBadge"))
local DurabilityBar = require(script.Parent:WaitForChild("DurabilityBar"))
local CharacterViewport = require(script.Parent:WaitForChild("CharacterViewport"))
local Style = require(script.Parent:WaitForChild("Journal"):WaitForChild("Style"))
local InventoryUI = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images"):WaitForChild("InventoryUI"))
local e = React.createElement

local DESIGN = Vector2.new(1130, 1170) -- Inventory/init.lua's STAGE_ASPECT mirrors this
-- 2026-10-12: sockets (ring, name plaque, rarity ring) and the spacing between them 15% larger.
local SOCKET_SCALE = 1.15
local SOCKET = math.floor(150 * SOCKET_SCALE + 0.5) -- every socket
local DISC = 0.78        -- the engraved disc, of the socket (inside the carved ring)
local PLAQUE_H = math.floor(44 * SOCKET_SCALE + 0.5)
local PLAQUE_W = math.floor(180 * SOCKET_SCALE + 0.5)
local ICON_FRACTION = 0.64 -- the item picture, of the socket (the carved ring is the rest)
local RING_THICKNESS = 4 * SOCKET_SCALE -- the rarity ring, design px

-- The character: centred and as tall as the column allows, standing on the flagstones (FEET_Y
-- is where its feet land; the viewport frames the model with 15% headroom, see
-- CharacterViewport FRAME_PADDING). Above its head is a band for the HP / hunger cluster:
-- this component publishes that spot (just over the head, at the figure's centre) as the vitals anchor,
-- ProfileMenusState.SetCarouselAnchor, so the bars sit over the player. The sockets tuck in
-- around the figure, the right column centred on the left one.
-- 2026-10-12: the whole scene (figure, sockets, rack) sits SCENE_DROP lower on the canvas, nearer
-- the bottom of the screen, and the vitals hang just over the character's head instead of at the
-- canvas top: the anchor is the head's top in real px, minus the cluster's height (HP bar, gap,
-- hunger + potion row: HealthClient HP_HEIGHT 10 + MENU_GAP_HP_TO_HUNGER 10 + the ~22 px row)
-- and a small gap. Real px, not design px, because the cluster doesn't scale with the canvas.
local SCENE_DROP = 50
local FIGURE = { x = 225, y = 110 + SCENE_DROP, w = 390, h = 900 }
local HEADROOM = 0.15 / 2 / 1.15 -- the empty space CharacterViewport leaves above the head, of FIGURE.h
local FEET_Y = FIGURE.y + FIGURE.h * (1 - HEADROOM)
local VITALS_CLUSTER_H = 42 -- real px
local VITALS_GAP = 8 -- real px, between the cluster and the head

-- Rows 230 apart (200 before the 15%), around the same centre (y 550). The tool column sits 270
-- right of the combat column: the scaled 230 plus 40 of breathing room, so it doesn't crowd it.
local ROW_STEP = 230
local ROWS_MID = 550 + SCENE_DROP
local LEFT_X, RIGHT_X, TOOL_X = 115, 735, 1005
local LEFT_ROWS = { ROWS_MID - 1.5 * ROW_STEP, ROWS_MID - 0.5 * ROW_STEP, ROWS_MID + 0.5 * ROW_STEP, ROWS_MID + 1.5 * ROW_STEP }
local RIGHT_ROWS = { ROWS_MID - ROW_STEP, ROWS_MID, ROWS_MID + ROW_STEP }
local RACK_W = math.floor(180 * SOCKET_SCALE + 0.5) -- the timber rack behind the tool column (its bands line up with RIGHT_ROWS)

local SLOTS = {
	{ id = "Helmet",       label = "Helm",          slot = "Helm",         x = LEFT_X,  y = LEFT_ROWS[1] },
	{ id = "Chestplate",   label = "Chest",         slot = "Chest",        x = LEFT_X,  y = LEFT_ROWS[2] },
	{ id = "Leggings",     label = "Leggings",      slot = "Legs",         x = LEFT_X,  y = LEFT_ROWS[3] },
	{ id = "Boots",        label = "Boots",         slot = "Boots",        x = LEFT_X,  y = LEFT_ROWS[4] },
	{ id = "Weapon",       label = "Weapon",        slot = "Weapon",       x = RIGHT_X, y = RIGHT_ROWS[1] },
	{ id = "Shield",       label = "Shield",        slot = "Shield",       x = RIGHT_X, y = RIGHT_ROWS[2] },
	{ id = "Bow",          label = "Bow",           slot = "Bow",          x = RIGHT_X, y = RIGHT_ROWS[3] },
	{ id = "Pickaxe",      label = "Pickaxe",       slot = "Pickaxe",      x = TOOL_X,  y = RIGHT_ROWS[1], disc = "Pickaxe" },
	{ id = "FishingSpear", label = "Fishing Spear", slot = "FishingSpear", x = TOOL_X,  y = RIGHT_ROWS[2], disc = "FishingSpear" },
	{ id = "Mount",        label = "Mount",         slot = "Mount",        x = TOOL_X,  y = RIGHT_ROWS[3], disc = "Mount" },
}

local function padScale(art: any): (UDim2, UDim2)
	local w = art.Width
	local h = w / art.Aspect
	local l, t, r, b = art.Pad[1], art.Pad[2], art.Pad[3], art.Pad[4]
	local innerW, innerH = w - l - r, h - t - b
	return UDim2.fromScale(-l / innerW, -t / innerH), UDim2.fromScale(w / innerW, h / innerH)
end

type SocketProps = {
	id: string, -- NOT `key`: React keeps that prop for itself
	label: string,
	slot: string,
	x: number,
	y: number,
	disc: string?, -- an InventoryUI.SOCKET_DISCS cell: the engraved face inside the ring
	item: any?,
	onClick: (() -> ())?,
	onRightClick: ((x: number, y: number) -> ())?,
	onHoverStart: ((x: number, y: number) -> ())?,
	onHoverEnd: (() -> ())?,
	onPressStart: ((x: number, y: number) -> ())?,
}

local function Socket(props: SocketProps)
	local hovered, setHovered = React.useState(false)
	local size = SOCKET
	local item = props.item
	-- GetRarityForItem (not raw item.rarity): catalog grants without a stamped rarity still
	-- resolve one from the catalog.
	local rarity = item and ItemDefinitions.GetRarityForItem(item) or nil

	local ringArt = Style.Art(hovered and "nav_medallion_selected" or "nav_medallion")
	local ring
	if ringArt and ringArt.Pad then
		local pos, sz = padScale(ringArt)
		ring = e("ImageLabel", { Position = pos, Size = sz, BackgroundTransparency = 1, Image = ringArt.Image, ZIndex = 1 })
	elseif ringArt then
		ring = e("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = ringArt.Image, ZIndex = 1 })
	else
		ring = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Style.Flat.Plate, ZIndex = 1 }, {
			Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Edge = e("UIStroke", { Color = Style.Flat.Edge, Thickness = 2 }),
		})
	end

	local inner: { [string]: any } = {}
	if item then
		local icon = ItemDefinitions.GetIconForItem(item)
		local broken = DurabilityBar.IsBroken(item)
		if type(icon) == "string" and icon ~= "" then
			inner.Icon = e("ImageLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Image = icon,
				ImageColor3 = broken and DurabilityBar.BROKEN_ICON_TINT or Color3.new(1, 1, 1),
				ImageTransparency = broken and DurabilityBar.BROKEN_ICON_ALPHA or 0,
				ScaleType = Enum.ScaleType.Fit,
				ZIndex = 4,
			})
		end
		if rarity == "Legendary" then
			inner.Glow = e(LegendaryGlow, { zIndex = 2 })
		end
		inner.EnchantBadge = EnchantBadge.ForItem(item)
		-- Inside the round socket: a little narrower and lifted so it clears the carved ring.
		inner.Durability = DurabilityBar.ForItem(item, { width = 0.7, bottom = 1.02 })
	end

	-- The engraved disc (tool / mount sockets): full strength while empty, dimmed under an item
	-- so the engraving doesn't compete with the icon.
	local discs = InventoryUI.SOCKET_DISCS
	local discCell = props.disc and discs.Image ~= "" and discs.Cells[props.disc] or nil

	return e("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(props.x, props.y),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
	}, {
		Ring = ring,
		Disc = discCell and e("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(DISC, DISC),
			BackgroundTransparency = 1,
			Image = discs.Image,
			ImageRectOffset = discCell.Offset,
			ImageRectSize = discCell.Size,
			ImageColor3 = item and Color3.fromRGB(110, 110, 110) or Color3.new(1, 1, 1),
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 2,
		}) or nil,
		-- Rarity: a thin coloured ring just inside the carved one (code-drawn, so it's crisp at
		-- any size and Legendary/Mythic animate through RarityBorder).
		Rarity = item and e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.8, 0.8),
			BackgroundTransparency = 1,
			ZIndex = 3,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Stroke = e(RarityBorder, { rarity = rarity, thickness = RING_THICKNESS }),
		}) or nil,
		Inner = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(ICON_FRACTION, ICON_FRACTION),
			BackgroundTransparency = 1,
			ZIndex = 4,
		}, inner),
		Plaque = e("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 1, -6 * SOCKET_SCALE),
			Size = UDim2.fromOffset(PLAQUE_W, PLAQUE_H),
			BackgroundTransparency = 1,
			Image = (Style.Art("nav_plaque") or { Image = "" }).Image,
			ScaleType = Style.Art("nav_plaque") and Enum.ScaleType.Slice or Enum.ScaleType.Stretch,
			SliceCenter = Style.Art("nav_plaque") and (Style.Art("nav_plaque") :: any).SliceCenter or nil,
			SliceScale = 0.22 * SOCKET_SCALE,
			ZIndex = 5,
		}, {
			Label = e("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = props.label,
				FontFace = Style.Font.Chrome,
				TextSize = math.floor((props.label == "Fishing Spear" and 21 or 24) * SOCKET_SCALE + 0.5),
				TextColor3 = hovered and Style.Chrome.Selected or Style.Chrome.Label,
				ZIndex = 6,
			}),
		}),
		Hit = e("ImageButton", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Image = "",
			ZIndex = 7,
			[React.Event.Activated] = props.onClick,
			[React.Event.MouseEnter] = function(_rbx, x, y)
				setHovered(true)
				if props.onHoverStart then props.onHoverStart(x, y) end
			end,
			[React.Event.MouseLeave] = function()
				setHovered(false)
				if props.onHoverEnd then props.onHoverEnd() end
			end,
			[React.Event.InputBegan] = function(_rbx, input)
				if input.UserInputType == Enum.UserInputType.MouseButton2 and props.onRightClick then
					props.onRightClick(input.Position.X, input.Position.Y)
				elseif input.UserInputType == Enum.UserInputType.MouseButton1 and props.onPressStart then
					-- Possible hold-drag start (socket -> bag = unequip); InventoryMain decides.
					props.onPressStart(input.Position.X, input.Position.Y)
				end
			end,
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
	-- Hold-drag (see InventoryMain). onSlotEnter/onSlotLeave fire for EVERY socket, empty or
	-- not: an empty socket is still a drop target. onHoverStart/onHoverEnd are tooltip-only.
	onSlotPressStart: ((slotName: string, uuid: string?, x: number, y: number) -> ())?,
	onSlotEnter: ((slotName: string) -> ())?,
	onSlotLeave: ((slotName: string) -> ())?,
}

local function PlayerPreview(props: PlayerPreviewProps?)
	local safeProps: PlayerPreviewProps = props or {}
	local equipped = safeProps.equipped or {}
	local inventory = safeProps.inventory or {}

	-- Contain-fit the design canvas into the column.
	local scale, setScale = React.useState(1)
	local hostRef = React.useRef(nil :: Frame?)
	React.useEffect(function()
		local host = hostRef.current
		if not host then return end
		local function fit()
			local avail = host.AbsoluteSize
			if avail.X <= 0 or avail.Y <= 0 then return end
			setScale(math.min(avail.X / DESIGN.X, avail.Y / DESIGN.Y))
		end
		fit()
		local conn = host:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		return function() conn:Disconnect() end
	end, {})

	-- The HP / hunger cluster hangs at the top of the canvas, over the character's head.
	local canvasRef = React.useRef(nil :: Frame?)
	React.useEffect(function()
		local canvas = canvasRef.current
		if not canvas then return end
		local function publish()
			local size = canvas.AbsoluteSize
			if size.X <= 0 then return end
			local k = size.X / DESIGN.X -- real px per design px (the UIScale)
			local pos = canvas.AbsolutePosition
			ProfileMenusState.SetCarouselAnchor(Vector2.new(
				pos.X + (FIGURE.x + FIGURE.w / 2) * k,
				pos.Y + (FIGURE.y + FIGURE.h * HEADROOM) * k - VITALS_CLUSTER_H - VITALS_GAP
			))
		end
		publish()
		local c1 = canvas:GetPropertyChangedSignal("AbsolutePosition"):Connect(publish)
		local c2 = canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(publish)
		return function()
			c1:Disconnect()
			c2:Disconnect()
		end
	end, {})

	local sockets: { [string]: any } = {}
	for _, def in ipairs(SLOTS) do
		local uuid = equipped[def.slot]
		local item = uuid and inventory[uuid]
		local p = table.clone(def) :: any
		p.item = item
		p.onClick = safeProps.onSlotClick and function() safeProps.onSlotClick(def.slot) end or nil
		p.onRightClick = safeProps.onSlotRightClick and function(x, y)
			safeProps.onSlotRightClick(def.slot, uuid, x, y)
		end or nil
		p.onHoverStart = function(x, y)
			if safeProps.onSlotEnter then safeProps.onSlotEnter(def.slot) end
			if item and safeProps.onHoverStart then safeProps.onHoverStart(item, x, y) end
		end
		p.onHoverEnd = function()
			if safeProps.onSlotLeave then safeProps.onSlotLeave(def.slot) end
			if safeProps.onHoverEnd then safeProps.onHoverEnd() end
		end
		p.onPressStart = safeProps.onSlotPressStart and function(x, y)
			safeProps.onSlotPressStart(def.slot, uuid, x, y)
		end or nil
		sockets[def.id] = e(Socket, p)
	end

	-- The timber rack behind the tool column, scaled so its three iron bands sit at the three
	-- sockets' centres (the rack's own height follows from that).
	local rack = InventoryUI.TOOL_RACK
	local rackEl = nil
	if rack.Image ~= "" then
		local k = (RIGHT_ROWS[2] - RIGHT_ROWS[1]) / (rack.Bands[2] - rack.Bands[1])
		rackEl = e("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(TOOL_X, RIGHT_ROWS[1] - rack.Bands[1] * k),
			Size = UDim2.fromOffset(RACK_W, rack.Size.Y * k),
			BackgroundTransparency = 1,
			Image = rack.Image,
			ZIndex = 2,
		})
	end

	local shadow = Style.Art("inv_shadow")
	return e("Frame", {
		ref = hostRef,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		Canvas = e("Frame", {
			ref = canvasRef,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(DESIGN.X, DESIGN.Y),
			BackgroundTransparency = 1,
		}, {
			Scale = e("UIScale", { Scale = scale }),
			Shadow = shadow and e("ImageLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(FIGURE.x + FIGURE.w / 2, FEET_Y),
				Size = UDim2.fromOffset(280, 280 / shadow.Aspect),
				BackgroundTransparency = 1,
				Image = shadow.Image,
				ImageColor3 = Color3.new(0, 0, 0),
				ImageTransparency = 0.25,
				ZIndex = 1,
			}) or nil,
			Figure = e(CharacterViewport, {
				equipped = equipped,
				size = UDim2.fromOffset(FIGURE.w, FIGURE.h),
				position = UDim2.fromOffset(FIGURE.x, FIGURE.y),
				zIndex = 2,
				rotatable = true,
			}),
			Rack = rackEl,
			Sockets = e("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = 3,
			}, sockets),
		}),
	})
end

return PlayerPreview
