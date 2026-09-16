--!strict
--  ContextMenu -- small right-click popup. Options are supplied by the caller
--  (Equip/Swap/Unequip, Drop, Trash today; more -- apply scroll, salvage, etc. --
--  can come later the same way).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local React = require(ReplicatedStorage.Packages.React)
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
local e = React.createElement

export type MenuOption = { text: string, onClick: () -> () }

-- Kept in lockstep with the render function's actual box below (240 fixed width, 36px
-- rows, 2px UIListLayout padding, 6px frame padding on every side) so EstimateSize can
-- predict the real rendered size exactly -- see Tooltip.lua's EstimateSize for why this
-- matters (clamping an AutomaticSize box against the viewport before it ever renders).
local ROW_HEIGHT, ROW_PADDING, FRAME_PADDING, WIDTH = 36, 2, 12, 240

local function ContextMenu(props: { position: Vector2, options: { MenuOption }, onDismiss: () -> () })
	local rows: { [string]: any } = {
		Layout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 2),
		}),
	}
	for i, opt in ipairs(props.options) do
		rows["Opt" .. i] = e("TextButton", {
			LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, 36),
			BackgroundColor3 = Color3.fromRGB(40, 30, 20),
			BorderSizePixel = 0,
			Text = opt.text,
			TextWrapped = true,
			FontFace = UIFonts.BodyMedium,
			TextSize = 15,
			TextColor3 = Color3.new(1, 1, 1),
			[React.Event.Activated] = function()
				opt.onClick()
				props.onDismiss()
			end,
		}, {
			Pad = e("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
		})
	end

	-- Position is the final, already-clamped top-left corner -- the caller
	-- (Inventory/init.lua) decides where that is, using EstimateSize below.
	return e("Frame", {
		Position = UDim2.fromOffset(props.position.X, props.position.Y),
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromOffset(WIDTH, 0),
		BackgroundColor3 = Color3.fromRGB(26, 18, 11),
		BorderSizePixel = 0,
		ZIndex = 50,
	}, {
		Stroke = e("UIStroke", { Color = UITheme.Gold, Thickness = 2 }),
		Padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6),
			PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
		}),
		Options = e("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			ZIndex = 51,
		}, rows),
	})
end

-- Predicts the real rendered size for a menu with `numOptions` rows -- see
-- Tooltip.EstimateSize for why: clamping needs this before the AutomaticSize frame
-- above has ever actually rendered.
local function estimateSize(numOptions: number): Vector2
	local n = math.max(0, numOptions)
	local height = FRAME_PADDING + n * ROW_HEIGHT + math.max(0, n - 1) * ROW_PADDING
	return Vector2.new(WIDTH, height)
end

return {
	Component = ContextMenu,
	EstimateSize = estimateSize,
}
