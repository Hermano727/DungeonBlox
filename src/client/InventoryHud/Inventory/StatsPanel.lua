--!strict
--  StatsPanel -- quick, deliberately plain mockup of the character-sheet
--  stats (a simplified version of StatsOverlayClient's rows), live-wired to
--  the same DungeonMenuNet snapshot data. Real visual design gets plugged
--  in later.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local React = require(ReplicatedStorage.Packages.React)
local PanelShell = require(script.Parent:WaitForChild("PanelShell"))
local InventoryData = require(script.Parent:WaitForChild("InventoryData"))
-- Row-value math (sum equipped attributes, format HP/regen/level strings) is
-- shared with StatsOverlayClient's character-sheet overlay -- see
-- DerivedStatsView for why this used to be two independent copies of the
-- same computation.
local DerivedStatsView = require(ReplicatedStorage:WaitForChild("DerivedStatsView"))

local e = React.createElement

local ROWS = {
	{ key = "hp",      label = "Health" },
	{ key = "armor",   label = "Armor" },
	{ key = "hpReg",   label = "HP Regen" },
	{ key = "enReg",   label = "Energy Regen" },
	{ key = "str",     label = "STR -- Axe" },
	{ key = "int",     label = "INT -- Scythe" },
	{ key = "dex",     label = "DEX -- Sword" },
	{ key = "vit",     label = "VIT -- Mace" },
	{ key = "combat",  label = "Combat Level" },
	{ key = "mining",  label = "Mining Level" },
	{ key = "fishing", label = "Fishing Level" },
	{ key = "coins",   label = "Coins" },
}

local function Row(props: { label: string, value: string, layoutOrder: number })
	return e("Frame", {
		LayoutOrder = props.layoutOrder,
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
	}, {
		Label = e("TextLabel", {
			Size = UDim2.new(0.6, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = props.label,
			FontFace = UIFonts.BodyMedium,
			TextSize = 14,
			TextColor3 = Color3.fromRGB(180, 165, 145),
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Value = e("TextLabel", {
			Size = UDim2.new(0.4, 0, 1, 0),
			Position = UDim2.new(0.6, 0, 0, 0),
			BackgroundTransparency = 1,
			Text = props.value,
			FontFace = UIFonts.BodyBold,
			TextSize = 15,
			TextColor3 = Color3.fromRGB(238, 230, 206),
			TextXAlignment = Enum.TextXAlignment.Right,
		}),
	})
end

local function StatsPanel(props: { onClose: () -> () })
	local snapshot = InventoryData.useSnapshot()

	local values = DerivedStatsView.Compute(snapshot)
	local rows: { [string]: any } = {
		Layout = e("UIListLayout", {
			Padding = UDim.new(0, 4),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for i, r in ipairs(ROWS) do
		rows[r.key] = e(Row, { label = r.label, value = values[r.key] or "--", layoutOrder = i })
	end

	return e(PanelShell, { title = "Stats", onClose = props.onClose }, {
		Content = e("Frame", {
			Size = UDim2.new(1, -32, 1, -32),
			Position = UDim2.fromOffset(16, 16),
			BackgroundTransparency = 1,
		}, rows),
	})
end

return StatsPanel
