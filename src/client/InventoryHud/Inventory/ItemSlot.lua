--!strict
--  ItemSlot -- shared item rendering (icon/rarity border/count badge/durability bar) +
--  click/right-click/hover wiring, used by the bag (InvSlots), shops, the bank and the Enchanting
--  Station. The equip sockets (PlayerPreview) draw their own, with the same DurabilityBar.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local React = require(ReplicatedStorage.Packages.React)
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local RarityBorder = require(script.Parent:WaitForChild("RarityBorder"))
local LegendaryGlow = require(script.Parent:WaitForChild("LegendaryGlow"))
local EnchantBadge = require(script.Parent:WaitForChild("EnchantBadge"))
local DurabilityBar = require(script.Parent:WaitForChild("DurabilityBar"))
local e = React.createElement

local EMPTY_BORDER_COLOR = Color3.fromRGB(90, 76, 58)
local SELECTED_BORDER_COLOR = Color3.fromRGB(255, 255, 255)

export type ItemSlotProps = {
	item: any?,
	size: number,
	selected: boolean?,
	onClick: (() -> ())?,
	onRightClick: ((x: number, y: number) -> ())?,
	onHoverStart: ((x: number, y: number) -> ())?,
	onHoverEnd: (() -> ())?,
	-- Fires on MouseButton1 InputBegan, in ADDITION to (never instead of) Activated below --
	-- see InventoryMain's press/drag effect for how it turns this into hold-drag-and-drop.
	onPressStart: ((x: number, y: number) -> ())?,
	-- true where the caller draws its own "+N" chip (the Enchanting Station, whose preview
	-- slot shows the NEXT level), so the two don't stack.
	hideEnchant: boolean?,
	-- Optional overrides for callers that draw ItemSlot at a different scale (the bag: a 508-unit
	-- slot contain-fit down to ~85 px, where an 8-unit outline shrinks to ~1.4 px). Defaults keep
	-- every other caller (shops, Enchanting Station) exactly as it was.
	borderThickness: number?,
	iconScale: number?,
	-- Rounds the outline to match a rounded pocket behind the slot (the bag's).
	cornerRadius: number?,
}

local function ItemSlot(props: ItemSlotProps)
	local item = props.item
	local size = props.size

	-- GetRarityForItem (not raw item.rarity) so catalog-only grants that never had `rarity`
	-- stamped onto their owned record (e.g. a dev-granted AdminSword) still resolve their
	-- rarity via the catalog's own Rarity field instead of silently rendering unrarity'd.
	local rarity = item and ItemDefinitions.GetRarityForItem(item) or nil

	local children: { [string]: any } = {}

	-- Selected (currently held/picked-up) always wins as a flat white outline; otherwise
	-- rarity-colored gradient border for an occupied slot, plain muted border when empty.
	-- Default thickness 8 (10 held). The bag passes its own (borderThickness) because it draws
	-- at ~0.17x scale; PlayerPreview's sockets draw their own round rings, so there's no second
	-- square-box copy of this number to keep in step.
	local thickness = props.borderThickness or 8
	if props.cornerRadius then
		children.Corner = e("UICorner", { CornerRadius = UDim.new(0, props.cornerRadius) })
	end
	if props.selected then
		children.Stroke = e(RarityBorder, { color = SELECTED_BORDER_COLOR, thickness = thickness + math.max(2, thickness * 0.25) })
	elseif item then
		children.Stroke = e(RarityBorder, { rarity = rarity, thickness = thickness })
	else
		children.Stroke = e(RarityBorder, { color = EMPTY_BORDER_COLOR, thickness = 8 })
	end

	if item and rarity == "Legendary" then
		-- Glow sits behind everything else in this slot (Icon is ZIndex 4+) -- see
		-- LegendaryGlow's zIndex doc.
		children.Glow = e(LegendaryGlow, { zIndex = 1 })
	end

	if item then
		-- GetIconForItem (not the itemId-only GetIcon) so procedurally generated mob drops --
		-- which never carry an itemId -- still resolve an icon via their tier + weapon/armor kind.
		local icon = ItemDefinitions.GetIconForItem(item)
		local broken = DurabilityBar.IsBroken(item)
		if type(icon) == "string" and icon ~= "" then
			children.Icon = e("ImageLabel", {
				-- Icon should take up the majority of the slot -- bumped from 0.8 to 0.92.
				Image = icon,
				ImageColor3 = broken and DurabilityBar.BROKEN_ICON_TINT or Color3.new(1, 1, 1),
				ImageTransparency = broken and DurabilityBar.BROKEN_ICON_ALPHA or 0,
				Size = UDim2.fromScale(props.iconScale or 0.92, props.iconScale or 0.92),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				ScaleType = Enum.ScaleType.Fit,
				ZIndex = 4,
			})
		else
			children.NameLabel = e("TextLabel", {
				Size = UDim2.fromScale(0.9, 0.9),
				Position = UDim2.fromScale(0.5, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Text = ItemDefinitions.GetDisplayNameForItem(item),
				TextWrapped = true,
				TextScaled = true,
				FontFace = UIFonts.BodyMedium,
				TextColor3 = Color3.new(1, 1, 1),
				ZIndex = 4,
			})
		end

		if not props.hideEnchant then
			children.EnchantBadge = EnchantBadge.ForItem(item)
		end
		children.Durability = DurabilityBar.ForItem(item)

		local count = math.floor(tonumber(item.count) or 1)
		if count > 1 then
			children.CountLabel = e("TextLabel", {
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.fromScale(1, 1),
				Size = UDim2.fromOffset(size * 0.4, size * 0.24),
				BackgroundTransparency = 1,
				Text = tostring(count),
				FontFace = UIFonts.BodyBold,
				TextScaled = true,
				TextColor3 = Color3.new(1, 1, 1),
				TextStrokeTransparency = 0,
				ZIndex = 5,
			})
		end
	end

	local uuid = item and item.uuid or nil
	return e("ImageButton", {
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Image = "",
		-- Which item this slot shows, so the tutorial can point at it ("item:<uuid>").
		ref = function(rbx)
			if rbx then rbx:SetAttribute("ItemUuid", uuid) end
		end,
		[React.Event.Activated] = props.onClick,
		[React.Event.MouseEnter] = props.onHoverStart and function(_rbx, x, y)
			if props.onHoverStart then props.onHoverStart(x, y) end
		end or nil,
		[React.Event.MouseLeave] = props.onHoverEnd,
		[React.Event.InputBegan] = function(_rbx, input)
			if input.UserInputType == Enum.UserInputType.MouseButton2 and props.onRightClick then
				props.onRightClick(input.Position.X, input.Position.Y)
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 and props.onPressStart then
				-- Possible hold-drag start. Whether this becomes a real drag (vs. a plain click)
				-- is decided by movement-past-threshold up in InventoryMain, not here -- this
				-- button doesn't know or care, and Activated below still fires normally for an
				-- actual click.
				props.onPressStart(input.Position.X, input.Position.Y)
			end
		end,
	}, children)
end

return ItemSlot
