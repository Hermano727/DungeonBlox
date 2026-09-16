--!strict
--  SkillsPanel -- Combat/Mining/Fishing skill bars, live-wired to SkillXPShared (the same data
--  source XpHud's floating bars read). No panel chrome anymore (per direct request 2026-09-12:
--  "remove the background rectangle completely, and the skills header, i just want the 3 floating
--  bars") -- this now returns just the 3 bars floating directly over whatever's behind the
--  Inventory window, same visual family as XpHud's own floating HUD bars: icon + "Level N" ABOVE
--  the bar (not inside it), and only the bar itself gets the ROW_ORNAMENT_IMAGE frame.
--
--  The standalone close (X) button that used to float top-right (added 2026-09-12 after
--  dropping PanelShell removed the only way back to the main inventory screen) is gone again
--  as of 2026-09-13: QuickNav is now a persistent header above this panel (see
--  Inventory/init.lua), so cycling it back to "Inventory" is the way back, same as every
--  other sub-panel.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))

local React = require(ReplicatedStorage.Packages.React)
local SkillXPShared = require(ReplicatedStorage:WaitForChild("SkillXPShared"))
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
local UIDevTuning = require(ReplicatedStorage:WaitForChild("UIDevTuning"))
local ItemConfig = require(ReplicatedStorage:WaitForChild("ItemConfig"))

local e = React.createElement

-- Same palette as PlayerPreview/InvSlots -- dark wood slot/bar interior, gold slot borders, cream
-- label text.
local THEME = {
	SlotBg     = Color3.fromRGB(20, 16, 13),
	SlotBorder = UITheme.Gold,
	LabelText  = Color3.fromRGB(240, 230, 210),
}

local LABEL_FONT = UIFonts.BodyBold

-- Reuses the exact icon the main-screen Combat XP bar uses (XpHud.luau COMBAT_ICON_IMAGE) so the
-- two don't visually drift apart. Not exported from a shared registry table today -- XpHud only
-- exports its component, not its constants -- so this is a deliberate duplicate of that literal.
local COMBAT_ICON_IMAGE = "rbxassetid://71642300678008"

-- The ornate bronze nameplate frame pasted in for this panel. Wraps the BAR only now -- the icon
-- and level text sit above it, outside the frame (per direct request).
local ROW_ORNAMENT_IMAGE = "rbxassetid://71776650392746"

-- Base overhang at Scale == 1 -- tune via F6 (UIDevTool -> "SkillsPanel").
local ORNAMENT_PAD_X, ORNAMENT_PAD_Y = 40, 18

-- Icon significantly larger than the "Level N" text next to it (2026-09-12, per direct request:
-- "increase their size by 50%" -- was 44).
local ICON_SIZE = 66
local HEADER_GAP = 10  -- between icon and "Level N" text
local HEADER_H = ICON_SIZE

local BAR_H = 30
local BAR_ROW_GAP = 14        -- between the icon/level header and its own bar
-- Bars are 33% horizontally smaller than a full-width bar, then widened ~15% back out, then
-- another ~10% on top of that (per direct request 2026-09-12: 0.67 * 1.15 * 1.10 ~= 0.847).
local BAR_WIDTH_SCALE = 0.847

local ROW_H = HEADER_H + BAR_ROW_GAP + BAR_H
-- More breathing room between skills now that the icon/level sits above each bar instead of
-- inline with it (per direct request: "add vertical spacing between each bar to allow the icons
-- more space").
local ROW_GAP = 46

local SKILLS = {
	-- Combat's fill matches XpHud's main-HUD Combat-bar green (XpHud.luau THEME.XpGreen) so the
	-- skill menu doesn't introduce a second "combat color" into the game.
	{ key = "Combat",  label = "Combat",  icon = COMBAT_ICON_IMAGE,                fill = Color3.fromRGB(78, 124, 54) },
	{ key = "Mining",  label = "Mining",  icon = ItemConfig.TOOL_ICONS.Pickaxe,    fill = Color3.fromRGB(150, 150, 150) },
	{ key = "Fishing", label = "Fishing", icon = ItemConfig.TOOL_ICONS.FishingRod, fill = Color3.fromRGB(96, 178, 224) },
}

-- Registered so UIDevTool (F6) picks it up automatically -- see UIDevTuning's header comment.
-- One independently-tunable target per skill row in case the ornament needs to sit slightly
-- differently once actual placements are eyeballed in Studio. Scale=1.95 approved via F6
-- (2026-09-12) and hand-copied back here per UIDevTuning's own "snapshot, then paste into
-- Register()" workflow, so the tuned look survives a server restart.
local SkillsOrnamentTuning = UIDevTuning.Register("SkillsPanel", {
	Combat  = { Scale = 1.95, OffsetX = 0, OffsetY = 0, Rotation = 0 },
	Mining  = { Scale = 1.95, OffsetX = 0, OffsetY = 0, Rotation = 0 },
	Fishing = { Scale = 1.95, OffsetX = 0, OffsetY = 0, Rotation = 0 },
})

local function Row(props: {
	key: string,
	label: string,
	icon: string,
	fill: Color3,
	level: number,
	xp: number,
	xpNeeded: number,
	layoutOrder: number,
	tuning: { Scale: number, OffsetX: number, OffsetY: number, Rotation: number },
})
	local pct = math.clamp(props.xp / math.max(props.xpNeeded, 1), 0, 1)
	local t = props.tuning
	local padX = ORNAMENT_PAD_X * t.Scale
	local padY = ORNAMENT_PAD_Y * t.Scale
	local amountStr = string.format("%d / %d", props.xp, props.xpNeeded)

	return e("Frame", {
		LayoutOrder = props.layoutOrder,
		Size = UDim2.new(1, 0, 0, ROW_H),
		BackgroundTransparency = 1,
	}, {
		-- Icon + "Level N", centered as a group ABOVE the bar (moved out of it, per direct
		-- request). AutomaticSize so the horizontal UIListLayout centers the visible icon+text
		-- pair itself rather than a fixed-width box with the pair sitting inside it.
		Header = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.new(0, 0, 0, HEADER_H),
			BackgroundTransparency = 1,
			ZIndex = 2,
		}, {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, HEADER_GAP),
			}),
			Icon = e("ImageLabel", {
				LayoutOrder = 1,
				Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
				BackgroundTransparency = 1,
				Image = props.icon,
				ScaleType = Enum.ScaleType.Fit,
				ZIndex = 2,
			}),
			LevelLabel = e("TextLabel", {
				LayoutOrder = 2,
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.new(0, 0, 0, HEADER_H),
				BackgroundTransparency = 1,
				Text = "Level " .. tostring(props.level),
				FontFace = LABEL_FONT,
				TextSize = 20,
				TextColor3 = THEME.LabelText,
				TextStrokeColor3 = Color3.new(0, 0, 0),
				TextStrokeTransparency = 0, -- fully floating over the world now, no dark backdrop -- needs full contrast
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 2,
			}),
		}),

		-- Progress track, 33% narrower than full width and centered. XP amount rendered inside
		-- it, offset-clone shadow behind the real text (same "black text shadow" technique
		-- XpHud's in-pill Combat amount uses) for readability over the fill color.
		Bar = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, HEADER_H + BAR_ROW_GAP),
			Size = UDim2.new(BAR_WIDTH_SCALE, 0, 0, BAR_H),
			BackgroundColor3 = THEME.SlotBg,
			BorderSizePixel = 0,
			ZIndex = 2,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 6) }),
			Stroke = e("UIStroke", { Color = THEME.SlotBorder, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
			Fill = e("Frame", {
				Size = UDim2.fromScale(pct, 1),
				BackgroundColor3 = props.fill,
				BorderSizePixel = 0,
				ZIndex = 3,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, 6) }),
			}),
			AmountShadow = e("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				Position = UDim2.fromOffset(1, 1),
				BackgroundTransparency = 1,
				Text = amountStr,
				FontFace = UIFonts.BodyBold,
				TextSize = 14,
				TextColor3 = Color3.new(0, 0, 0),
				TextTransparency = 0.35,
				ZIndex = 4,
			}),
			AmountText = e("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = amountStr,
				FontFace = UIFonts.BodyBold,
				TextSize = 14,
				TextColor3 = THEME.LabelText,
				ZIndex = 5,
			}),

			-- Full-wrap ornament frame over the bar only (not the header above it) -- same
			-- overhang-via-padding technique as XpHud's pill Border. Scale/OffsetX/OffsetY/
			-- Rotation live in UIDevTuning so F6 can nudge this per skill without a redeploy.
			Ornament = e("ImageLabel", {
				Image = ROW_ORNAMENT_IMAGE,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, t.OffsetX, 0.5, t.OffsetY),
				Size = UDim2.new(1, padX * 2, 1, padY * 2),
				Rotation = t.Rotation,
				BackgroundTransparency = 1,
				ScaleType = Enum.ScaleType.Stretch,
				ZIndex = 6,
			}),
		}),
	})
end

local function SkillsPanel()
	local _version, setVersion = React.useState(0)
	React.useEffect(function()
		return SkillXPShared.Subscribe(function()
			setVersion(function(v)
				return v + 1
			end)
		end)
	end, {})

	-- Used to also tell XpHud the Skills tab was open so it force-showed the floating
	-- Combat bar on top of this panel's own bar -- removed 2026-09-13, it caused two
	-- Combat bars to render at once (see SkillXPShared.lua's header note).

	local ornamentTuning, setOrnamentTuning = React.useState(SkillsOrnamentTuning:Get())
	React.useEffect(function()
		return SkillsOrnamentTuning:Subscribe(function()
			setOrnamentTuning(SkillsOrnamentTuning:Get())
		end)
	end, {})

	local rows: { [string]: any } = {
		Layout = e("UIListLayout", {
			Padding = UDim.new(0, ROW_GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
		}),
	}
	for i, s in ipairs(SKILLS) do
		local state = SkillXPShared[s.key]
		rows[s.key] = e(Row, {
			key = s.key,
			label = s.label,
			icon = s.icon,
			fill = s.fill,
			level = state.Level,
			xp = state.XP,
			xpNeeded = SkillXPShared.GetXPForLevel(state.Level),
			layoutOrder = i,
			tuning = ornamentTuning[s.key],
		})
	end

	-- Still no PanelShell background/header -- just the 3 floating bars. No close button
	-- either now -- see this file's header comment.
	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, rows)
end

return SkillsPanel
