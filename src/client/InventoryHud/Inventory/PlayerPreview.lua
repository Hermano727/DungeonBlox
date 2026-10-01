--!strict
--  PlayerPreview -- the Inventory tab's left side (rebuilt 2026-09-30 as the "courtyard
--  diorama"): your character standing on the painted flagstones (CharacterViewport, drag to
--  turn), with the nine gear slots as carved sockets around it:
--
--      Helm
--      Chest      character     Weapon
--      Legs                     Shield
--      Boots                    Bow
--               Pickaxe  Fishing Spear      (smaller, under the feet)
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
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local RarityBorder = require(script.Parent:WaitForChild("RarityBorder"))
local LegendaryGlow = require(script.Parent:WaitForChild("LegendaryGlow"))
local EnchantBadge = require(script.Parent:WaitForChild("EnchantBadge"))
local CharacterViewport = require(script.Parent:WaitForChild("CharacterViewport"))
local Style = require(script.Parent:WaitForChild("Journal"):WaitForChild("Style"))
local e = React.createElement

local DESIGN = Vector2.new(820, 1010) -- Inventory/init.lua's STAGE_ASPECT mirrors this
local SOCKET = 120       -- armor + combat sockets
local TOOL_SOCKET = 96   -- the two profession sockets under the feet
local PLAQUE_H = 40
local RING_THICKNESS = 4 -- the rarity ring, design px

-- The character: centred and as tall as the column allows, standing on the flagstones (FEET_Y
-- is where its feet land; the viewport frames the model with 15% headroom, see
-- CharacterViewport FRAME_PADDING). The sockets tuck in around it; the right column starts a
-- row lower so its top socket stays clear of anything hanging at the top of the screen.
local FIGURE = { x = 220, y = 0, w = 380, h = 900 }
local FEET_Y = FIGURE.y + FIGURE.h * (1 - 0.15 / 2 / 1.15)

local LEFT_X, RIGHT_X = 95, 725
local ROWS = { 120, 320, 520, 720 }
local TOOLS_Y = 920

local SLOTS = {
	{ id = "Helmet",       label = "Helm",          slot = "Helm",         x = LEFT_X,  y = ROWS[1] },
	{ id = "Chestplate",   label = "Chest",         slot = "Chest",        x = LEFT_X,  y = ROWS[2] },
	{ id = "Leggings",     label = "Legs",          slot = "Legs",         x = LEFT_X,  y = ROWS[3] },
	{ id = "Boots",        label = "Boots",         slot = "Boots",        x = LEFT_X,  y = ROWS[4] },
	{ id = "Weapon",       label = "Weapon",        slot = "Weapon",       x = RIGHT_X, y = ROWS[2] },
	{ id = "Shield",       label = "Shield",        slot = "Shield",       x = RIGHT_X, y = ROWS[3] },
	{ id = "Bow",          label = "Bow",           slot = "Bow",          x = RIGHT_X, y = ROWS[4] },
	{ id = "Pickaxe",      label = "Pickaxe",       slot = "Pickaxe",      x = 320,     y = TOOLS_Y, small = true },
	{ id = "FishingSpear", label = "Fishing Spear", slot = "FishingSpear", x = 500,     y = TOOLS_Y, small = true },
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
	small: boolean?,
	item: any?,
	onClick: (() -> ())?,
	onRightClick: ((x: number, y: number) -> ())?,
	onHoverStart: ((x: number, y: number) -> ())?,
	onHoverEnd: (() -> ())?,
	onPressStart: ((x: number, y: number) -> ())?,
}

local function Socket(props: SocketProps)
	local hovered, setHovered = React.useState(false)
	local size = props.small and TOOL_SOCKET or SOCKET
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
		if type(icon) == "string" and icon ~= "" then
			inner.Icon = e("ImageLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.6, 0.6),
				BackgroundTransparency = 1,
				Image = icon,
				ScaleType = Enum.ScaleType.Fit,
				ZIndex = 4,
			})
		end
		if rarity == "Legendary" then
			inner.Glow = e(LegendaryGlow, { zIndex = 2 })
		end
		inner.EnchantBadge = EnchantBadge.ForItem(item)
	end

	return e("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(props.x, props.y),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
	}, {
		Ring = ring,
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
			Size = UDim2.fromScale(0.72, 0.72),
			BackgroundTransparency = 1,
			ZIndex = 4,
		}, inner),
		Plaque = e("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 1, -6),
			Size = UDim2.fromOffset(props.small and 190 or 160, PLAQUE_H),
			BackgroundTransparency = 1,
			Image = (Style.Art("nav_plaque") or { Image = "" }).Image,
			ScaleType = Style.Art("nav_plaque") and Enum.ScaleType.Slice or Enum.ScaleType.Stretch,
			SliceCenter = Style.Art("nav_plaque") and (Style.Art("nav_plaque") :: any).SliceCenter or nil,
			SliceScale = 0.22,
			ZIndex = 5,
		}, {
			Label = e("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = props.label,
				FontFace = Style.Font.Chrome,
				TextSize = props.small and 19 or 22,
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

	local shadow = Style.Art("inv_shadow")
	return e("Frame", {
		ref = hostRef,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		Canvas = e("Frame", {
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
			Sockets = e("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = 3,
			}, sockets),
		}),
	})
end

return PlayerPreview
