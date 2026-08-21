--!strict
--  ItemSlot -- shared item rendering (icon/rarity border/count badge) + click/right-click/
--  hover wiring, used by both InvSlots (bag) and PlayerPreview (equip boxes). No durability
--  bar yet -- first pass covers equip/swap only, per spec.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local RarityBorder = require(script.Parent:WaitForChild("RarityBorder"))
local LegendaryGlow = require(script.Parent:WaitForChild("LegendaryGlow"))
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
	if props.selected then
		children.Stroke = e(RarityBorder, { color = SELECTED_BORDER_COLOR, thickness = 5 })
	elseif item then
		children.Stroke = e(RarityBorder, { rarity = rarity, thickness = 3 })
	else
		children.Stroke = e(RarityBorder, { color = EMPTY_BORDER_COLOR, thickness = 3 })
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
		if type(icon) == "string" and icon ~= "" then
			children.Icon = e("ImageLabel", {
				-- Icon should take up the majority of the slot -- bumped from 0.8 to 0.92.
				Image = icon,
				Size = UDim2.fromScale(0.92, 0.92),
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
				Font = Enum.Font.GothamMedium,
				TextColor3 = Color3.new(1, 1, 1),
				ZIndex = 4,
			})
		end

		local count = math.floor(tonumber(item.count) or 1)
		if count > 1 then
			children.CountLabel = e("TextLabel", {
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.fromScale(1, 1),
				Size = UDim2.fromOffset(size * 0.4, size * 0.24),
				BackgroundTransparency = 1,
				Text = tostring(count),
				Font = Enum.Font.GothamBold,
				TextScaled = true,
				TextColor3 = Color3.new(1, 1, 1),
				TextStrokeTransparency = 0,
				ZIndex = 5,
			})
		end
	end

	return e("ImageButton", {
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Image = "",
		[React.Event.Activated] = props.onClick,
		[React.Event.MouseEnter] = props.onHoverStart and function(_rbx, x, y)
			if props.onHoverStart then props.onHoverStart(x, y) end
		end or nil,
		[React.Event.MouseLeave] = props.onHoverEnd,
		[React.Event.InputBegan] = function(_rbx, input)
			if input.UserInputType == Enum.UserInputType.MouseButton2 and props.onRightClick then
				props.onRightClick(input.Position.X, input.Position.Y)
			end
		end,
	}, children)
end

return ItemSlot
