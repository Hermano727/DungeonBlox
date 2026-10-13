--!strict
--  ContextMenu -- small right-click popup. Options are supplied by the caller
--  (Equip/Swap/Unequip, Drop, Trash today; more -- apply scroll, salvage, etc. --
--  can come later the same way).
--
--  An option with a `quantity` field (2026-10-12: dropping part of a stack) doesn't fire
--  straight away: clicking it turns the popup into a how-many picker (- / amount / +, quick
--  1 / Half / All, then the confirm button), and `quantity.onConfirm(n)` gets the amount.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local React = require(ReplicatedStorage.Packages.React)
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
local e = React.createElement

export type QuantitySpec = { max: number, verb: string, name: string, onConfirm: (number) -> () }
export type MenuOption = { text: string, onClick: (() -> ())?, quantity: QuantitySpec? }

-- Kept in lockstep with the render function's actual box below (240 fixed width, 36px
-- rows, 2px UIListLayout padding, 6px frame padding on every side) so EstimateSize can
-- predict the real rendered size exactly -- see Tooltip.lua's EstimateSize for why this
-- matters (clamping an AutomaticSize box against the viewport before it ever renders).
local ROW_HEIGHT, ROW_PADDING, FRAME_PADDING, WIDTH = 36, 2, 12, 240
-- The how-many picker: title 22 + stepper 36 + quick picks 28 + confirm 36, padding 6 between.
local PICKER_HEIGHT = 22 + 36 + 28 + 36 + 3 * 6

local BUTTON = Color3.fromRGB(40, 30, 20)
local BUTTON_STRONG = Color3.fromRGB(92, 70, 38)
local TEXT_MUTED = Color3.fromRGB(196, 178, 146)

local function button(props: { order: number, text: string, size: UDim2, strong: boolean?, onClick: () -> () })
	return e("TextButton", {
		LayoutOrder = props.order,
		Size = props.size,
		BackgroundColor3 = if props.strong then BUTTON_STRONG else BUTTON,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Text = props.text,
		FontFace = UIFonts.BodyMedium,
		TextSize = 15,
		TextColor3 = Color3.new(1, 1, 1),
		[React.Event.Activated] = props.onClick,
	}, {
		Stroke = props.strong and e("UIStroke", {
			Color = UITheme.Gold,
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}) or nil,
	})
end

-- How many of a stack: starts at the whole stack (the common case), clamped to 1..max.
-- Shift on - / + steps by 10.
local function QuantityPicker(props: { spec: QuantitySpec, onDone: () -> () })
	local max = math.max(1, math.floor(props.spec.max))
	local amount, setAmount = React.useState(max)
	local function set(n: number)
		setAmount(math.clamp(math.floor(n), 1, max))
	end
	local function step(sign: number)
		local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		set(amount + sign * (if shift then 10 else 1))
	end
	local function confirm()
		props.spec.onConfirm(amount)
		props.onDone()
	end

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ZIndex = 51,
	}, {
		Layout = e("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }),
		Title = e("TextLabel", {
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundTransparency = 1,
			Text = props.spec.verb .. " how many " .. props.spec.name .. "?",
			TextTruncate = Enum.TextTruncate.AtEnd,
			FontFace = UIFonts.BodyMedium,
			TextSize = 14,
			TextColor3 = TEXT_MUTED,
		}),
		Stepper = e("Frame", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1 }, {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 4),
			}),
			Minus = button({ order = 1, text = "-", size = UDim2.fromOffset(44, 36), onClick = function() step(-1) end }),
			Amount = e("TextBox", {
				LayoutOrder = 2,
				Size = UDim2.new(1, -96, 1, 0),
				BackgroundColor3 = Color3.fromRGB(18, 12, 8),
				BorderSizePixel = 0,
				ClearTextOnFocus = true,
				Text = tostring(amount),
				FontFace = UIFonts.BodyMedium,
				TextSize = 17,
				TextColor3 = Color3.new(1, 1, 1),
				[React.Event.FocusLost] = function(box: TextBox, enterPressed: boolean)
					local typed = tonumber((string.gsub(box.Text, "%D", "")))
					local value = if typed then math.clamp(math.floor(typed), 1, max) else amount
					set(value)
					box.Text = tostring(value) -- React won't rewrite it if the amount didn't change
					if enterPressed and typed then
						props.spec.onConfirm(value)
						props.onDone()
					end
				end,
			}, {
				Stroke = e("UIStroke", { Color = UITheme.Gold, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
			}),
			Plus = button({ order = 3, text = "+", size = UDim2.fromOffset(44, 36), onClick = function() step(1) end }),
		}),
		Quick = e("Frame", { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1 }, {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 4),
			}),
			One = button({ order = 1, text = "1", size = UDim2.new(1 / 3, -3, 1, 0), onClick = function() set(1) end }),
			Half = button({ order = 2, text = "Half", size = UDim2.new(1 / 3, -3, 1, 0), onClick = function() set(math.max(1, max // 2)) end }),
			All = button({ order = 3, text = "All", size = UDim2.new(1 / 3, -2, 1, 0), onClick = function() set(max) end }),
		}),
		Confirm = button({
			order = 4,
			text = props.spec.verb .. " " .. amount .. " / " .. max,
			size = UDim2.new(1, 0, 0, 36),
			strong = true,
			onClick = confirm,
		}),
	})
end

local function ContextMenu(props: { position: Vector2, options: { MenuOption }, onDismiss: () -> () })
	-- The option whose amount is being picked (nil = the plain list). Reset when a new menu opens.
	local picking, setPicking = React.useState(nil :: MenuOption?)
	React.useEffect(function()
		setPicking(nil)
	end, { props.options })

	local body
	if picking and picking.quantity then
		body = e(QuantityPicker, {
			spec = picking.quantity,
			onDone = props.onDismiss,
		})
	else
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
				BackgroundColor3 = BUTTON,
				BorderSizePixel = 0,
				Text = opt.text,
				TextWrapped = true,
				FontFace = UIFonts.BodyMedium,
				TextSize = 15,
				TextColor3 = Color3.new(1, 1, 1),
				[React.Event.Activated] = function()
					if opt.quantity then
						setPicking(opt)
						return
					end
					if opt.onClick then opt.onClick() end
					props.onDismiss()
				end,
			}, {
				Pad = e("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
			})
		end
		body = e("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			ZIndex = 51,
		}, rows)
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
		Options = body,
	})
end

-- Predicts the real rendered size for a menu's options -- see Tooltip.EstimateSize for why:
-- clamping needs this before the AutomaticSize frame above has ever actually rendered. A
-- menu with a quantity option is sized for the taller of its list and the picker, so the
-- picker opening in place never runs off the screen.
local function estimateSize(options: { MenuOption }): Vector2
	local n = #options
	local height = n * ROW_HEIGHT + math.max(0, n - 1) * ROW_PADDING
	for _, opt in ipairs(options) do
		if opt.quantity then
			height = math.max(height, PICKER_HEIGHT)
			break
		end
	end
	return Vector2.new(WIDTH, FRAME_PADDING + height)
end

return {
	Component = ContextMenu,
	EstimateSize = estimateSize,
}
