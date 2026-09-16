--!strict
--  HearthstonePanel -- a square grid of hearthstone destination icons, live off
--  HearthstoneConfig's seed locations. Same "slot" visual language as the rest of the Inventory
--  panel (PlayerPreview / InvSlots / SkillsPanel): gold-stroked square tiles, all sitting inside
--  one bordered grid background instead of just floating on the panel -- mirrors how InvSlots'
--  bag grid has its own bordered panel behind the individual item slots. No teleport wiring yet --
--  just the grid layout for review. HearthstoneClient/HearthstoneConfig/HearthstoneService own
--  the real system.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local React = require(ReplicatedStorage.Packages.React)
local PanelShell = require(script.Parent:WaitForChild("PanelShell"))
local HearthstoneConfig = require(ReplicatedStorage:WaitForChild("HearthstoneConfig"))
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))

local e = React.createElement

-- Same palette as PlayerPreview/InvSlots/SkillsPanel -- dark wood, gold slot borders, cream text.
local THEME = {
	GridBg     = Color3.fromRGB(20, 16, 13), -- the bordered background sitting behind every tile
	SlotBg     = Color3.fromRGB(26, 18, 11), -- individual tile fill -- one notch lighter than the grid bg
	SlotBorder = UITheme.Gold,
	LabelText  = Color3.fromRGB(240, 230, 210),
}

local TILE_SIZE = 96
local TILE_GAP = 12

local function LocationTile(props: { name: string, icon: string?, layoutOrder: number })
	local hasIcon = type(props.icon) == "string" and props.icon ~= ""

	return e("TextButton", {
		LayoutOrder = props.layoutOrder,
		Size = UDim2.fromOffset(TILE_SIZE, TILE_SIZE),
		BackgroundColor3 = THEME.SlotBg,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
	}, {
		Stroke = e("UIStroke", { Color = THEME.SlotBorder, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),

		Icon = hasIcon and e("ImageLabel", {
			Image = props.icon,
			Size = UDim2.fromScale(0.62, 0.62),
			Position = UDim2.new(0.5, 0, 0.42, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 2,
		}) or nil,

		-- No icon assigned yet for this location -- fall back to just centering the name.
		Name = e("TextLabel", {
			AnchorPoint = hasIcon and Vector2.new(0.5, 1) or Vector2.new(0.5, 0.5),
			Position = hasIcon and UDim2.new(0.5, 0, 1, -6) or UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -8, 0, hasIcon and 16 or 34),
			BackgroundTransparency = 1,
			Text = string.upper(props.name),
			FontFace = UIFonts.BodyBold,
			TextSize = hasIcon and 11 or 13,
			TextColor3 = THEME.LabelText,
			TextWrapped = true,
			ZIndex = 2,
		}),
	})
end

local function HearthstonePanel(props: { onClose: () -> () })
	local tiles: { [string]: any } = {
		Layout = e("UIGridLayout", {
			CellSize = UDim2.fromOffset(TILE_SIZE, TILE_SIZE),
			CellPadding = UDim2.fromOffset(TILE_GAP, TILE_GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Top,
		}),
	}
	for i, loc in ipairs(HearthstoneConfig.SEED_LOCATIONS) do
		tiles[loc.id] = e(LocationTile, { name = loc.name, icon = loc.icon, layoutOrder = i })
	end

	return e(PanelShell, { title = "Hearthstone", onClose = props.onClose }, {
		Content = e("Frame", {
			Size = UDim2.new(1, -32, 1, -32),
			Position = UDim2.fromOffset(16, 16),
			BackgroundTransparency = 1,
		}, {
			-- One bordered "grid panel" sits behind every tile -- not just per-tile borders
			-- floating directly on PanelShell's own background.
			GridPanel = e("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = THEME.GridBg,
				BorderSizePixel = 0,
			}, {
				Stroke = e("UIStroke", { Color = THEME.SlotBorder, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
				Padding = e("UIPadding", {
					PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16),
					PaddingTop = UDim.new(0, 16), PaddingBottom = UDim.new(0, 16),
				}),
				Tiles = e("Frame", {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
				}, tiles),
			}),
		}),
	})
end

return HearthstonePanel
