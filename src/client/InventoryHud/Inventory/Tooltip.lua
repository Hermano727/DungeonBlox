--!strict
--  Tooltip -- hover popup for an owned item: name, rarity badge (ALL CAPS, rarity-colored),
--  a "Base Stats" section (HP / HP Regen / Armor / Damage / Damage Reduction / Energy Per
--  Second), and a "Substats" section (everything else the item rolled -- omitted entirely
--  when the item has none). Base-stat labels/order and substat labels are intentionally basic
--  RPG-UI styling for now, per request ("we can make custom UI later").
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Types = require(ReplicatedStorage:WaitForChild("ProfileTypes"))
local ItemConfig = require(ReplicatedStorage:WaitForChild("ItemConfig"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local e = React.createElement

-- Substat id -> { label, valueType } pulled straight from ItemConfig so the tooltip can never
-- drift out of sync with what ItemGenerator is actually able to roll onto an item.
local SUBSTAT_META: { [string]: { label: string, valueType: string? } } = {}
local function registerEffects(list)
	for _, effect in ipairs(list) do
		SUBSTAT_META[effect.id] = { label = effect.label, valueType = effect.valueType }
	end
end
registerEffects(ItemConfig.WEAPON_EFFECTS)
registerEffects(ItemConfig.ARMOR_EFFECTS)
registerEffects(ItemConfig.ARMOR_BONUS_EFFECTS)

-- Base-stat keys, rendered under "Base Stats" in a fixed order below (not the alphabetical
-- Substats list) -- plus the "_raw*" pre-scaling values ItemClass:toGrantTemplate() also stows
-- in subStats for its own bookkeeping. Neither set should ever reach the tooltip as a bare
-- "_rawDmgMin: 7" style row.
local BASE_STAT_KEYS = { dmgMin = true, dmgMax = true, hp = true, hps = true, armor = true, energy = true, dmgRed = true }

local function isInternalKey(key): boolean
	return string.sub(key, 1, 1) == "_"
end

local function baseStatLines(subStats): { string }
	local lines = {}
	if type(subStats) ~= "table" then
		return lines
	end
	if subStats.dmgMin and subStats.dmgMax then
		table.insert(lines, string.format("%d-%d Damage", subStats.dmgMin, subStats.dmgMax))
	end
	if subStats.hp then
		table.insert(lines, string.format("%d HP", subStats.hp))
	end
	if subStats.hps then
		table.insert(lines, string.format("%d HP Regen", subStats.hps))
	end
	if subStats.armor then
		table.insert(lines, string.format("%d Armor", subStats.armor))
	end
	if subStats.dmgRed then
		table.insert(lines, string.format("%d%% Damage Reduction", subStats.dmgRed))
	end
	if subStats.energy then
		table.insert(lines, string.format("%.2f Energy Per Second", subStats.energy))
	end
	return lines
end

local function substatLines(subStats): { string }
	local entries = {}
	if type(subStats) == "table" then
		for key, value in pairs(subStats) do
			if not BASE_STAT_KEYS[key] and not isInternalKey(key) then
				local meta = SUBSTAT_META[key]
				local label = meta and meta.label or key
				local suffix = (meta and meta.valueType == "pct") and "%" or ""
				table.insert(entries, { label = label, text = string.format("%s: %s%s", label, tostring(value), suffix) })
			end
		end
	end
	table.sort(entries, function(a, b) return a.label < b.label end)
	local lines = {}
	for _, entry in ipairs(entries) do
		table.insert(lines, entry.text)
	end
	return lines
end

local function SectionHeader(text: string, layoutOrder: number)
	return e("TextLabel", {
		LayoutOrder = layoutOrder,
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		Text = text,
		FontFace = UIFonts.BodyBold,
		TextSize = 13,
		TextColor3 = UITheme.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
end

local function Spacer(layoutOrder: number)
	return e("Frame", {
		LayoutOrder = layoutOrder,
		Size = UDim2.new(1, 0, 0, 8),
		BackgroundTransparency = 1,
	})
end

local function StatLine(text: string, layoutOrder: number)
	return e("TextLabel", {
		LayoutOrder = layoutOrder,
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		Text = text,
		FontFace = UIFonts.Body,
		TextSize = 13,
		TextColor3 = Color3.fromRGB(210, 205, 195),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
end

-- Exact same height math the render function below builds, kept in one place
-- (TOOLTIP_LINE_HEIGHTS-shaped constants) so EstimateSize can never drift from what
-- actually renders -- callers use this to clamp the tooltip on-screen (see
-- Inventory/init.lua) before the real AutomaticSize frame ever exists.
local NAME_H, RARITY_H, SPACER_H, HEADER_H, STAT_LINE_H, LIST_PADDING = 20, 16, 8, 16, 16, 2
local OUTER_PADDING_Y, CONTENT_WIDTH, OUTER_PADDING_X = 16, 230, 20 -- 8+8 top/bottom, 10+10 left/right

local function renderTooltip(props: { item: any, position: Vector2 })
	local item = props.item
	if type(item) ~= "table" then
		return nil :: any
	end

	local name = ItemDefinitions.GetDisplayNameForItem(item)
	-- GetRarityForItem (not raw item.rarity) so catalog-only grants that never had `rarity`
	-- stamped onto their owned record (e.g. a dev-granted AdminSword) still resolve their
	-- rarity via the catalog's own Rarity field.
	local rarity = ItemDefinitions.GetRarityForItem(item)
	local rarityColor = Types.GetRarityColor(rarity)
	local rarityText = type(rarity) == "string" and string.upper(rarity) or ""

	local baseLines = baseStatLines(item.subStats)
	local subLines = substatLines(item.subStats)

	local order = 0
	local children: { [string]: any } = {
		Layout = e("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }),
	}

	order = order + 1
	children.Name = e("TextLabel", {
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Text = name,
		FontFace = UIFonts.BodyBold,
		TextSize = 16,
		TextColor3 = Color3.fromRGB(240, 230, 210),
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	if rarityText ~= "" then
		order = order + 1
		children.Rarity = e("TextLabel", {
			LayoutOrder = order,
			Size = UDim2.new(1, 0, 0, 16),
			BackgroundTransparency = 1,
			Text = rarityText,
			FontFace = UIFonts.BodyBold,
			TextSize = 12,
			TextColor3 = rarityColor,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	end

	if #baseLines > 0 then
		order = order + 1
		children["Gap" .. order] = Spacer(order)
		order = order + 1
		children.BaseHeader = SectionHeader("Base Stats", order)
		for _, line in ipairs(baseLines) do
			order = order + 1
			children["Base" .. order] = StatLine(line, order)
		end
	end

	if #subLines > 0 then
		order = order + 1
		children["Gap" .. order] = Spacer(order)
		order = order + 1
		children.SubHeader = SectionHeader("Substats", order)
		for _, line in ipairs(subLines) do
			order = order + 1
			children["Sub" .. order] = StatLine(line, order)
		end
	end

	-- Position is the final, already-clamped/offset top-left corner -- the caller
	-- (Inventory/init.lua) decides where that is (near the cursor, flipped/clamped to
	-- stay on screen), using EstimateSize below to know how big this will render.
	return e("Frame", {
		Position = UDim2.fromOffset(props.position.X, props.position.Y),
		AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0),
		BackgroundColor3 = Color3.fromRGB(20, 14, 9),
		BorderSizePixel = 0,
		ZIndex = 60,
	}, {
		Stroke = e("UIStroke", { Color = UITheme.Gold, Thickness = 1 }),
		Padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
			PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
		}),
		Content = e("Frame", {
			Size = UDim2.fromOffset(CONTENT_WIDTH, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			ZIndex = 61,
		}, children),
	})
end

-- Predicts the AutomaticSize box's real rendered size for `item`, without ever
-- creating one -- lets the caller clamp/flip the tooltip's position against the
-- viewport before the first frame renders (an AutomaticSize frame's real size isn't
-- known until after it's already on screen, which would show one frame in the wrong
-- place otherwise). Must stay in lockstep with renderTooltip's actual line list above.
local function estimateSize(item: any): Vector2
	if type(item) ~= "table" then
		return Vector2.new(0, 0)
	end
	local rarity = ItemDefinitions.GetRarityForItem(item)
	local hasRarity = type(rarity) == "string" and rarity ~= ""
	local baseLines = baseStatLines(item.subStats)
	local subLines = substatLines(item.subStats)

	local lineHeights = { NAME_H }
	if hasRarity then
		table.insert(lineHeights, RARITY_H)
	end
	if #baseLines > 0 then
		table.insert(lineHeights, SPACER_H)
		table.insert(lineHeights, HEADER_H)
		for _ = 1, #baseLines do
			table.insert(lineHeights, STAT_LINE_H)
		end
	end
	if #subLines > 0 then
		table.insert(lineHeights, SPACER_H)
		table.insert(lineHeights, HEADER_H)
		for _ = 1, #subLines do
			table.insert(lineHeights, STAT_LINE_H)
		end
	end

	local contentHeight = 0
	for _, h in ipairs(lineHeights) do
		contentHeight += h
	end
	contentHeight += math.max(0, #lineHeights - 1) * LIST_PADDING

	return Vector2.new(CONTENT_WIDTH + OUTER_PADDING_X, contentHeight + OUTER_PADDING_Y)
end

return {
	Component = renderTooltip,
	EstimateSize = estimateSize,
}
