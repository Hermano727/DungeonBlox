--!strict
--  ContextMenu -- small right-click popup. First pass only offers Equip / Swap / Unequip
--  (per spec); more actions (apply scroll, salvage, etc.) come later.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
local e = React.createElement

export type MenuOption = { text: string, onClick: () -> () }

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
			Font = Enum.Font.GothamMedium,
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

	return e("Frame", {
		Position = UDim2.fromOffset(props.position.X, props.position.Y),
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromOffset(240, 0),
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

return ContextMenu
