--!strict
--  JournalPanel -- the "Journal" QuickNav destination: lifetime grind totals,
--  one card per system (Combat / Mining / Fishing).
--
--  Layout is deliberately NOT the label-left/value-right list StatsPanel uses
--  (per direct request). Each system gets its own bordered card with an icon
--  badge, its skill level, and a row of big-number stat tiles -- so a system's
--  numbers read as a group at a glance instead of dissolving into one long
--  undifferentiated column. The cards live in a ScrollingFrame with an
--  auto-growing canvas, so adding a system later is one more entry in CARDS
--  below and nothing else.
--
--  Data source: profile.stats.tracking (see ProfileTypes' DefaultProfile), the
--  uncapped lifetime counters QuestProgressService bumps on every kill / ore
--  collect / fish catch. Those are deliberately NOT pushed per-kill (that would
--  mean a full snapshot per mob death), so this panel requests one sync on
--  mount -- same defensive convention the shop clients use.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
local ItemConfig = require(ReplicatedStorage:WaitForChild("ItemConfig"))
local PanelShell = require(script.Parent:WaitForChild("PanelShell"))
local InventoryData = require(script.Parent:WaitForChild("InventoryData"))
local DungeonMenuNet = require(script.Parent.Parent.Parent:WaitForChild("DungeonMenuNet"))

local e = React.createElement

local THEME = {
	CardBg     = Color3.fromRGB(20, 14, 9),
	TileBg     = Color3.fromRGB(30, 22, 14),
	Border     = UITheme.Gold,
	Title      = Color3.fromRGB(238, 230, 206),
	Label      = Color3.fromRGB(158, 143, 122),
	Value      = Color3.fromRGB(245, 238, 219),
	LevelText  = Color3.fromRGB(198, 178, 130),
}

local CARD_HEIGHT = 156
local CARD_GAP = 14
local CARD_PAD = 14
local ACCENT_WIDTH = 4
local HEADER_HEIGHT = 44
local BADGE_SIZE = 38
local TILE_GAP = 10

-- Combat intentionally uses the QuickNav "Skills" glyph rather than XpHud's combat
-- XP-bar icon (per direct request). Mining/Fishing reuse the same tool icons
-- SkillsPanel shows, so a system looks identical wherever it appears.
local COMBAT_ICON = "rbxassetid://73632421462187"

-- Accent per system, matching SkillsPanel's bar fills so the colour coding is
-- consistent between the two panels.
-- Score and kills are deliberately two tiles, not one: score is loot rolls, not
-- a kill count -- a single kill can award several (dungeon party rate, loot-buff
-- roll) or none (the damage-contribution gate), so the two never track together.
-- Only T1 is surfaced for now; scoreByTier already stores all five.
local SCORE_TIER = 1

local CARDS = {
	{
		key = "combat",
		title = "Combat",
		icon = COMBAT_ICON,
		accent = Color3.fromRGB(78, 124, 54),
		levelFrom = "combat",
		tiles = {
			{ label = "T1 Score", tierScore = SCORE_TIER },
			{ label = "Kills", stat = "mobsKilled" },
		},
	},
	{
		key = "mining",
		title = "Mining",
		icon = ItemConfig.TOOL_ICONS.Pickaxe,
		accent = Color3.fromRGB(150, 150, 150),
		levelFrom = "mining",
		tiles = {
			{ label = "Ores Mined", stat = "oresMined" },
			{ label = "Coal", stat = "coalMined" },
		},
	},
	{
		key = "fishing",
		title = "Fishing",
		icon = ItemConfig.TOOL_ICONS.FishingRod,
		accent = Color3.fromRGB(96, 178, 224),
		levelFrom = "fishing",
		tiles = { { label = "Fish Caught", stat = "fishCaught" } },
	},
}

-- 12345 -> "12,345". Grind totals get long, and an unseparated run of digits is
-- genuinely hard to read at a glance.
local function formatCount(n: number): string
	local whole = tostring(math.max(0, math.floor(n)))
	local out = whole
	while true do
		local replaced: number
		out, replaced = string.gsub(out, "^(%d+)(%d%d%d)", "%1,%2")
		if replaced == 0 then
			break
		end
	end
	return out
end

local function StatTile(props: { label: string, value: string, widthScale: number, widthOffset: number, layoutOrder: number })
	return e("Frame", {
		LayoutOrder = props.layoutOrder,
		Size = UDim2.new(props.widthScale, props.widthOffset, 1, 0),
		BackgroundColor3 = THEME.TileBg,
		BorderSizePixel = 0,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Stroke = e("UIStroke", { Color = THEME.Border, Thickness = 1, Transparency = 0.6 }),

		Value = e("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 12),
			Size = UDim2.new(1, -16, 0, 32),
			BackgroundTransparency = 1,
			Text = props.value,
			FontFace = UIFonts.DisplayBold,
			TextSize = 28,
			TextColor3 = THEME.Value,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextScaled = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
		Label = e("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -10),
			Size = UDim2.new(1, -12, 0, 14),
			BackgroundTransparency = 1,
			Text = string.upper(props.label),
			FontFace = UIFonts.BodyMedium,
			TextSize = 11,
			TextColor3 = THEME.Label,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
	})
end

local function CategoryCard(props: {
	title: string,
	icon: string,
	accent: Color3,
	level: number?,
	tiles: { { label: string, value: string } },
	layoutOrder: number,
})
	local tileCount = math.max(1, #props.tiles)
	-- Equal-width tiles sharing the row, with TILE_GAP between them: each tile gives up
	-- its share of the total gap so the row always fills the card exactly.
	local widthScale = 1 / tileCount
	local widthOffset = -(TILE_GAP * (tileCount - 1)) / tileCount

	local tiles: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, TILE_GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for i, t in ipairs(props.tiles) do
		tiles["tile" .. i] = e(StatTile, {
			label = t.label,
			value = t.value,
			widthScale = widthScale,
			widthOffset = widthOffset,
			layoutOrder = i,
		})
	end

	return e("Frame", {
		LayoutOrder = props.layoutOrder,
		Size = UDim2.new(1, 0, 0, CARD_HEIGHT),
		BackgroundColor3 = THEME.CardBg,
		BorderSizePixel = 0,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0, 8) }),
		Stroke = e("UIStroke", { Color = THEME.Border, Thickness = 1.5, Transparency = 0.35 }),

		-- Colour-coded spine down the left edge: the fastest read of "which system is
		-- this" when scanning a scrolled column of cards.
		Accent = e("Frame", {
			Size = UDim2.new(0, ACCENT_WIDTH, 1, -16),
			Position = UDim2.fromOffset(0, 8),
			BackgroundColor3 = props.accent,
			BorderSizePixel = 0,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 2) }),
		}),

		Body = e("Frame", {
			Size = UDim2.new(1, -(CARD_PAD * 2 + ACCENT_WIDTH), 1, -CARD_PAD * 2),
			Position = UDim2.fromOffset(CARD_PAD + ACCENT_WIDTH, CARD_PAD),
			BackgroundTransparency = 1,
		}, {
			Header = e("Frame", {
				Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
				BackgroundTransparency = 1,
			}, {
				Badge = e("Frame", {
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, 0, 0.5, 0),
					Size = UDim2.fromOffset(BADGE_SIZE, BADGE_SIZE),
					BackgroundColor3 = THEME.TileBg,
					BorderSizePixel = 0,
				}, {
					Corner = e("UICorner", { CornerRadius = UDim.new(0, 6) }),
					Stroke = e("UIStroke", { Color = props.accent, Thickness = 1, Transparency = 0.45 }),
					Icon = e("ImageLabel", {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.5),
						Size = UDim2.new(1, -8, 1, -8),
						BackgroundTransparency = 1,
						Image = props.icon,
						ScaleType = Enum.ScaleType.Fit,
					}),
				}),

				Title = e("TextLabel", {
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, BADGE_SIZE + 12, 0.5, 0),
					Size = UDim2.new(1, -(BADGE_SIZE + 12 + 90), 0, 22),
					BackgroundTransparency = 1,
					Text = string.upper(props.title),
					FontFace = UIFonts.DisplayBold,
					TextSize = 17,
					TextColor3 = THEME.Title,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),

				Level = props.level and e("TextLabel", {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, 0, 0.5, 0),
					Size = UDim2.fromOffset(86, 20),
					BackgroundTransparency = 1,
					Text = "LEVEL " .. tostring(props.level),
					FontFace = UIFonts.BodyBold,
					TextSize = 12,
					TextColor3 = THEME.LevelText,
					TextXAlignment = Enum.TextXAlignment.Right,
				}) or nil,
			}),

			Divider = e("Frame", {
				Position = UDim2.new(0, 0, 0, HEADER_HEIGHT),
				Size = UDim2.new(1, 0, 0, 1),
				BackgroundColor3 = THEME.Border,
				BackgroundTransparency = 0.6,
				BorderSizePixel = 0,
			}),

			Tiles = e("Frame", {
				Position = UDim2.new(0, 0, 0, HEADER_HEIGHT + 12),
				Size = UDim2.new(1, 0, 1, -(HEADER_HEIGHT + 12)),
				BackgroundTransparency = 1,
			}, tiles),
		}),
	})
end

local function JournalPanel()
	local snapshot = InventoryData.useSnapshot()

	-- Kills don't push a snapshot (see this file's header), so pull once on open --
	-- otherwise the totals would be however stale the last unrelated push left them.
	React.useEffect(function()
		DungeonMenuNet.requestSync()
	end, {})

	local profile = snapshot and snapshot.profile
	local stats = (profile and profile.stats) or {}
	local tracking = (type(stats.tracking) == "table" and stats.tracking) or {}

	local cards: { [string]: any } = {
		Layout = e("UIListLayout", {
			Padding = UDim.new(0, CARD_GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Padding = e("UIPadding", {
			PaddingTop = UDim.new(0, 4),
			PaddingBottom = UDim.new(0, 4),
			PaddingLeft = UDim.new(0, 2),
			PaddingRight = UDim.new(0, 10), -- clears the scrollbar
		}),
	}

	for i, card in ipairs(CARDS) do
		local skill = stats[card.levelFrom]
		local level = type(skill) == "table" and tonumber(skill.level) or nil

		local scoreByTier = (type(tracking.scoreByTier) == "table" and tracking.scoreByTier) or {}
		local tiles = {}
		for _, t in ipairs(card.tiles) do
			local raw
			if t.tierScore then
				raw = scoreByTier[t.tierScore]
			else
				raw = tracking[t.stat]
			end
			table.insert(tiles, {
				label = t.label,
				value = formatCount(tonumber(raw) or 0),
			})
		end

		cards[card.key] = e(CategoryCard, {
			title = card.title,
			icon = card.icon,
			accent = card.accent,
			level = level and math.floor(level) or nil,
			tiles = tiles,
			layoutOrder = i,
		})
	end

	return e(PanelShell, { title = "Journal" }, {
		Content = e("ScrollingFrame", {
			Size = UDim2.new(1, -32, 1, -32),
			Position = UDim2.fromOffset(16, 16),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			-- Auto canvas means a new entry in CARDS just works -- no hand-maintained
			-- CanvasSize to keep in sync with the card count.
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollBarThickness = 6,
			ScrollBarImageColor3 = THEME.Border,
			ScrollBarImageTransparency = 0.4,
			VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		}, cards),
	})
end

return JournalPanel
