--!strict
--  SkillsPanel -- Combat/Mining/Fishing skill bars, live-wired to SkillXPShared (the same data
--  source XpHud's floating bars read). Styling matches the main Inventory panel (PlayerPreview /
--  InvSlots): the same dark-wood/gold-stroke "slot" look and BuilderSans uppercase labels, minus
--  the ornate corner GoldFrame image (PanelShell's plain gold UIStroke around the whole panel
--  already does that job here).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local SkillXPShared = require(ReplicatedStorage:WaitForChild("SkillXPShared"))
local PanelShell = require(script.Parent:WaitForChild("PanelShell"))
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))

local e = React.createElement

-- Same palette as PlayerPreview/InvSlots -- dark wood panel, gold slot borders, cream label text.
local THEME = {
	SlotBg     = Color3.fromRGB(20, 16, 13),
	SlotBorder = UITheme.Gold,
	LabelText  = Color3.fromRGB(240, 230, 210),
}

local LABEL_FONT = Font.new("rbxasset://fonts/families/BuilderSans.json", Enum.FontWeight.Bold)

local SKILLS = {
	{ key = "Combat",  label = "Combat",  fill = Color3.fromRGB(150, 52, 40) },
	{ key = "Mining",  label = "Mining",  fill = Color3.fromRGB(120, 104, 78) },
	{ key = "Fishing", label = "Fishing", fill = Color3.fromRGB(64, 104, 118) },
}

local function Bar(props: { label: string, fill: Color3, level: number, xp: number, xpNeeded: number, layoutOrder: number })
	local pct = math.clamp(props.xp / math.max(props.xpNeeded, 1), 0, 1)
	return e("Frame", {
		LayoutOrder = props.layoutOrder,
		Size = UDim2.new(1, 0, 0, 70),
		BackgroundTransparency = 1,
	}, {
		-- Uppercase BuilderSans label, same treatment as PlayerPreview's equipment-slot labels.
		NameLabel = e("TextLabel", {
			Size = UDim2.new(1, -60, 0, 22),
			BackgroundTransparency = 1,
			Text = string.upper(props.label),
			FontFace = LABEL_FONT,
			TextSize = 17,
			TextColor3 = THEME.LabelText,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),

		-- Level badge -- a small gold-stroked chip, same visual family as ItemSlot's stack-count
		-- badge, instead of folding the level into the label text.
		LevelBadge = e("Frame", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.fromOffset(52, 22),
			BackgroundColor3 = THEME.SlotBg,
			BorderSizePixel = 0,
		}, {
			Stroke = e("UIStroke", { Color = THEME.SlotBorder, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
			Text = e("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = "LV " .. tostring(props.level),
				Font = Enum.Font.GothamBold,
				TextSize = 13,
				TextColor3 = THEME.LabelText,
			}),
		}),

		-- Progress track, same square gold-stroked "slot" box as the equipment/bag slots.
		Track = e("Frame", {
			Position = UDim2.fromOffset(0, 28),
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundColor3 = THEME.SlotBg,
			BorderSizePixel = 0,
		}, {
			Stroke = e("UIStroke", { Color = THEME.SlotBorder, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
			Fill = e("Frame", {
				Size = UDim2.fromScale(pct, 1),
				BackgroundColor3 = props.fill,
				BorderSizePixel = 0,
				ZIndex = 1,
			}),
			XpLabel = e("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = string.format("%d / %d XP", props.xp, props.xpNeeded),
				Font = Enum.Font.GothamMedium,
				TextSize = 13,
				TextColor3 = Color3.fromRGB(240, 235, 225),
				ZIndex = 2,
			}),
		}),
	})
end

local function SkillsPanel(props: { onClose: () -> () })
	local _version, setVersion = React.useState(0)
	React.useEffect(function()
		return SkillXPShared.Subscribe(function()
			setVersion(function(v)
				return v + 1
			end)
		end)
	end, {})

	local content: { [string]: any } = {
		Layout = e("UIListLayout", {
			Padding = UDim.new(0, 14),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for i, s in ipairs(SKILLS) do
		local state = SkillXPShared[s.key]
		content[s.key] = e(Bar, {
			label = s.label,
			fill = s.fill,
			level = state.Level,
			xp = state.XP,
			xpNeeded = SkillXPShared.GetXPForLevel(state.Level),
			layoutOrder = i,
		})
	end

	return e(PanelShell, { title = "Skills", onClose = props.onClose }, {
		Content = e("Frame", {
			Size = UDim2.new(1, -32, 1, -32),
			Position = UDim2.fromOffset(16, 16),
			BackgroundTransparency = 1,
		}, content),
	})
end

return SkillsPanel
