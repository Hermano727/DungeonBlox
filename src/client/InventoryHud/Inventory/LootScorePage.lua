--!strict
--  LootScorePage -- the Journal's "Loot Score" page, drawn in Journal/Book with the tier
--  bookmark tabs (T1-T5, unlocked at combat level 1/21/41/61/81) on the book's top edge.
--  The tier filters both pages. Two levels, like the Settings screen:
--
--  Landing (all time):
--    left   "Tier N Score": the total, the overworld / dungeon split bar, runs cleared,
--           and "Activity >" (one level deeper)
--    right  Dry Streaks (?) : one row per rarity, gem + name + bar + count
--  Activity (from "Activity >", Back returns):
--    left   window chips 1H 24H 7D 30D; "This <window>": score + split, kills, runs, drops
--           by rarity, and the score chart across the window
--    right  a table: this window vs the player's average window of the same length (score,
--           kills, runs, drops, +/- %), then the tier's illustration (JournalUI illustration_t<N>)
--
--  Data:
--    totals   profile snapshot, stats.tracking: scoreByTier (total), dungeonScoreByTier,
--             runsClearedByTier (overworld = total - dungeon)
--    streaks  GameEvents/JournalRequest "lootScore" (LootPityService)
--    activity GameEvents/JournalRequest "activity", tier, window (RS/JournalActivity.Summary)
--  Streaks are one pool shared by every tier; the tier changes the chance curve, so a bar is
--  the streak against that tier's "near certain" point (LootPityConfig.PITY_FULL_MULT times
--  the average wait).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Types = require(ReplicatedStorage:WaitForChild("ProfileTypes"))
local PityConfig = require(ReplicatedStorage:WaitForChild("LootPityConfig"))
local InventoryData = require(script.Parent:WaitForChild("InventoryData"))
local Journal = script.Parent:WaitForChild("Journal")
local Style = require(Journal:WaitForChild("Style"))
local Parts = require(Journal:WaitForChild("Parts"))
local Book = require(Journal:WaitForChild("Book"))
local ScoreChart = require(Journal:WaitForChild("ScoreChart"))

local e = React.createElement
local player = Players.LocalPlayer

local TIER_LEVELS = { 1, 21, 41, 61, 81 }
local WINDOWS = { "1H", "24H", "7D", "30D" }
local WINDOW_TITLE = { ["1H"] = "This Hour", ["24H"] = "Last 24 Hours", ["7D"] = "Last 7 Days", ["30D"] = "Last 30 Days" }
local WINDOW_NOUN = { ["1H"] = "hour", ["24H"] = "day", ["7D"] = "week", ["30D"] = "month" }

local STREAK_HELP = "How many rolls since your last drop of each rarity. The bar fills toward the point where "
	.. "a drop is almost certain, so a long streak means one is close."
local AVERAGE_HELP = "Your avg: what you usually get in a window this long, counting only the windows in "
	.. "which you played. The last column is how this one compares."

local function formatCount(n: number): string
	local out = tostring(math.max(0, math.floor(n + 0.5)))
	while true do
		local replaced: number
		out, replaced = string.gsub(out, "^(%d+)(%d%d%d)", "%1,%2")
		if replaced == 0 then break end
	end
	return out
end

local function tierValue(list: any, tier: number): number
	return type(list) == "table" and (tonumber(list[tier]) or 0) or 0
end

local function text(props: any)
	return e("TextLabel", {
		LayoutOrder = props.order,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		Size = props.Size or UDim2.new(1, 0, 0, props.height or 22),
		BackgroundTransparency = 1,
		Text = props.text,
		RichText = props.rich == true,
		TextWrapped = props.wrap == true,
		FontFace = props.font or Style.Font.Body,
		TextSize = props.size or 16,
		TextColor3 = props.color or Style.Text.Body,
		TextXAlignment = props.align or Enum.TextXAlignment.Center,
		TextYAlignment = props.alignY or Enum.TextYAlignment.Center,
	})
end

local function list(padding: number, children: { [string]: any }, align: Enum.HorizontalAlignment?)
	children.Layout = e("UIListLayout", {
		Padding = UDim.new(0, padding),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center, -- short pages sit mid-page, not top-heavy
	})
	return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, children)
end

local function useRequest(page: string, tier: number?, window: string?)
	local result, setResult = React.useState(nil :: any)
	React.useEffect(function()
		local alive = true
		setResult(nil)
		task.spawn(function()
			local remote = ReplicatedStorage:WaitForChild("GameEvents"):WaitForChild("JournalRequest", 10)
			if not remote then return end
			local ok, reply = pcall(function()
				return (remote :: RemoteFunction):InvokeServer(page, tier, window)
			end)
			if alive and ok and type(reply) == "table" then setResult(reply) end
		end)
		return function() alive = false end
	end, { page, tier or 0, window or "" } :: { any })
	return result
end

------------------------------------------------------------------------------------------
-- Pieces
------------------------------------------------------------------------------------------

local function SplitLegend(props: { overworld: number, dungeon: number, order: number? })
	local function side(label: string, value: number, color: Color3, anchorX: number)
		return e("Frame", {
			AnchorPoint = Vector2.new(anchorX, 0),
			Position = UDim2.fromScale(anchorX, 0),
			Size = UDim2.new(0.5, -10, 1, 0),
			BackgroundTransparency = 1,
		}, {
			Label = text({ text = label, size = 16, color = Style.Text.Body, height = 20 }),
			Value = text({
				text = formatCount(value), font = Style.Font.Number, size = 26, color = color,
				Position = UDim2.fromOffset(0, 20), height = 30,
			}),
		})
	end
	local strongOverworld = Style.OnPaper and Color3.fromRGB(62, 84, 40) or Color3.fromRGB(150, 176, 112)
	local strongDungeon = Style.OnPaper and Color3.fromRGB(62, 68, 80) or Color3.fromRGB(150, 160, 178)
	return e("Frame", {
		LayoutOrder = props.order,
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundTransparency = 1,
	}, {
		Overworld = side("Overworld", props.overworld, strongOverworld, 0),
		Rule = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.1),
			Size = UDim2.new(0, 1, 0.8, 0),
			BackgroundColor3 = Style.Text.Muted,
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
		}),
		Dungeon = side("Dungeons", props.dungeon, strongDungeon, 1),
	})
end

local function StreakRow(props: { rarity: string, streak: number?, fill: number, order: number })
	return e("Frame", {
		LayoutOrder = props.order,
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
	}, {
		Gem = e(Parts.Gem, { rarity = props.rarity, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 20, 0.5, 0) }),
		Name = text({
			text = props.rarity, font = Style.Font.BodyBold, size = 18, color = Style.Text.Heading,
			align = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(48, 0), Size = UDim2.new(0, 120, 1, 0),
		}),
		Bar = e(Parts.BarTrough, {
			fill = props.fill,
			color = Types.GetRarityColor(props.rarity),
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 172, 0.5, 0),
			Size = UDim2.new(1, -172 - 60, 0, 16),
		}),
		Count = text({
			text = props.streak and formatCount(props.streak) or "-", font = Style.Font.Number, size = 22,
			color = Style.Text.Value, align = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 52, 1, 0),
		}),
	})
end

local function HeadingWithHelp(props: { text: string, help: string, order: number? })
	return e("Frame", {
		LayoutOrder = props.order,
		Size = UDim2.new(1, 0, 0, 42),
		BackgroundTransparency = 1,
	}, {
		Heading = e(Parts.Heading, { text = props.text, size = 30 }),
		Help = e(Parts.HelpIcon, {
			text = props.help,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
		}),
	})
end

------------------------------------------------------------------------------------------
-- Landing
------------------------------------------------------------------------------------------

local function Landing(props: { tier: number, tracking: any, tabs: any, side: any?, onActivity: () -> () })
	local reply = useRequest("lootScore")
	local streaks = reply and reply.streaks
	local tier = props.tier
	local total = tierValue(props.tracking.scoreByTier, tier)
	local dungeon = tierValue(props.tracking.dungeonScoreByTier, tier)
	local runs = tierValue(props.tracking.runsClearedByTier, tier)

	local left = list(10, {
		Heading = e(Parts.Heading, { text = ("Tier %d Score"):format(tier), size = 32, order = 1 }),
		Divider = e(Parts.Divider, { order = 2 }),
		Total = text({ text = formatCount(total), font = Style.Font.Number, size = 64, color = Style.Text.Value, height = 76, order = 3 }),
		Split = e(Parts.SplitBar, { a = total - dungeon, b = dungeon, height = 22, order = 4 }),
		Legend = e(SplitLegend, { overworld = math.max(0, total - dungeon), dungeon = dungeon, order = 5 }),
		Runs = text({
			text = runs == 1 and "1 run cleared" or (formatCount(runs) .. " runs cleared"),
			size = 17, color = Style.Text.Muted, height = 24, order = 6,
		}),
		Spacer = e("Frame", { LayoutOrder = 7, Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1 }),
		Activity = e(Parts.ChromeButton, {
			text = "Activity  >", art = "chip", artSelected = "chip_selected",
			Size = UDim2.new(0.7, 0, 0, 44), LayoutOrder = 8, textSize = 18,
			onClick = props.onActivity,
		}),
	})

	local rows: { [string]: any } = {
		Heading = e(HeadingWithHelp, { text = "Dry Streaks", help = STREAK_HELP, order = 0 }),
		Divider = e(Parts.Divider, { order = 1 }),
	}
	local chances = PityConfig.BASE_CHANCE[tier] or {}
	for i, rarity in ipairs(PityConfig.RARITIES) do
		local base = tonumber(chances[rarity]) or 0
		local streak = streaks and tonumber(streaks[rarity]) or nil
		local fullAt = base > 0 and (PityConfig.PITY_FULL_MULT / base) or math.huge
		rows[rarity] = e(StreakRow, { rarity = rarity, streak = streak, fill = (streak or 0) / fullAt, order = 1 + i })
	end

	return e(Book, { tabs = props.tabs, side = props.side, left = left, right = list(14, rows) })
end

------------------------------------------------------------------------------------------
-- Activity
------------------------------------------------------------------------------------------

local WINDOW_SHORT = { ["1H"] = "Last hour", ["24H"] = "Last 24h", ["7D"] = "Last 7d", ["30D"] = "Last 30d" }
local CHART_TITLE = {
	["1H"] = "Score every 5 minutes", ["24H"] = "Score per hour", ["7D"] = "Score per day", ["30D"] = "Score per day",
}

-- The two right-page tables share one column grid (design px; the canvas is 480 wide).
-- Numbers are right-aligned inside their column so they line up down the table.
local COL = {
	label = { x = 0, w = 150 },
	a = { x = 150, w = 100 },
	b = { x = 262, w = 100 },
	c = { x = 372, w = 108 },
}

local function cell(props: any)
	local col = COL[props.col]
	return e("TextLabel", {
		Position = UDim2.fromOffset(col.x + (props.indent or 0), 0),
		Size = UDim2.new(0, col.w - (props.indent or 0), 1, 0),
		BackgroundTransparency = 1,
		Text = props.text,
		RichText = props.rich == true,
		FontFace = props.font or Style.Font.Body,
		TextSize = props.size or 17,
		TextColor3 = props.color or Style.Text.Body,
		TextXAlignment = props.align or Enum.TextXAlignment.Right,
	})
end

local function TableRow(props: { order: number, height: number?, children: { [string]: any } })
	return e("Frame", {
		LayoutOrder = props.order,
		Size = UDim2.new(1, 0, 0, props.height or 32),
		BackgroundTransparency = 1,
	}, props.children)
end

-- Small muted column headers above a table ("Last 24h   Your avg").
local function HeaderRow(props: { order: number, a: string, b: string, c: string? })
	return TableRow({ order = props.order, height = 22, children = {
		A = cell({ col = "a", text = props.a, size = 14, color = Style.Text.Muted, font = Style.Font.BodyBold }),
		B = cell({ col = "b", text = props.b, size = 14, color = Style.Text.Muted, font = Style.Font.BodyBold }),
		C = props.c and cell({ col = "c", text = props.c, size = 14, color = Style.Text.Muted, font = Style.Font.BodyBold }) or nil,
		Rule = e("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Style.Text.Muted,
			BackgroundTransparency = 0.6,
			BorderSizePixel = 0,
		}),
	} })
end

local function percentText(now: number, avg: number): (string, Color3)
	if avg <= 0 then
		return now > 0 and "new" or "-", Style.Text.Muted
	end
	local pct = math.floor((now - avg) / avg * 100 + 0.5)
	if pct > 0 then return "+" .. pct .. "%", Style.Text.Good end
	if pct < 0 then return pct .. "%", Style.Text.Bad end
	return "even", Style.Text.Muted
end

local function CompareRow(props: { label: string, now: number, avg: number?, order: number })
	local pct, pctColor = "", Style.Text.Muted
	if props.avg then pct, pctColor = percentText(props.now, props.avg) end
	return TableRow({ order = props.order, children = {
		Label = cell({ col = "label", text = props.label, align = Enum.TextXAlignment.Left,
			font = Style.Font.BodyBold, size = 18, color = Style.Text.Heading }),
		Now = cell({ col = "a", text = formatCount(props.now), font = Style.Font.Number, size = 19, color = Style.Text.Value }),
		Avg = cell({ col = "b", text = props.avg and formatCount(props.avg) or "-", size = 17, color = Style.Text.Muted }),
		Pct = cell({ col = "c", text = pct, font = Style.Font.BodyBold, size = 17, color = pctColor }),
	} })
end

-- One labelled number in the row under the split bar.
local function StatBlock(props: { value: number, caption: string, color: Color3?, order: number })
	return e("Frame", {
		LayoutOrder = props.order,
		Size = UDim2.new(0.25, -6, 1, 0),
		BackgroundTransparency = 1,
	}, {
		Value = text({ text = formatCount(props.value), font = Style.Font.Number, size = 21,
			color = props.color or Style.Text.Value, height = 24 }),
		Caption = text({ text = props.caption, size = 13, color = Style.Text.Muted, height = 16,
			Position = UDim2.fromOffset(0, 25) }),
	})
end

local function Activity(props: { tier: number, window: string, tabs: any, side: any?, setWindow: (string) -> (), onBack: () -> () })
	local summary = useRequest("activity", props.tier, props.window)
	local cur = summary and summary.current
	local avg = summary and summary.average
	local drops, avgDrops = 0, 0
	if cur then for i = 1, 5 do drops += cur.w[i] or 0 end end
	if avg then for i = 1, 5 do avgDrops += avg.w[i] or 0 end end
	local score = cur and ((cur.o or 0) + (cur.d or 0)) or 0
	local moss = Style.OnPaper and Color3.fromRGB(62, 84, 40) or Color3.fromRGB(150, 176, 112)
	local iron = Style.OnPaper and Color3.fromRGB(62, 68, 80) or Color3.fromRGB(150, 160, 178)

	local chips: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for i, w in ipairs(WINDOWS) do
		chips[w] = e(Parts.ChromeButton, {
			text = w, selected = w == props.window, art = "chip", artSelected = "chip_selected",
			Size = UDim2.fromOffset(70, 32), LayoutOrder = i, textSize = 15,
			onClick = function() props.setWindow(w) end,
		})
	end

	local dropGems: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 14),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Label = text({ text = "Drops", font = Style.Font.BodyBold, size = 15, color = Style.Text.Muted,
			Size = UDim2.fromOffset(52, 32), order = 0, align = Enum.TextXAlignment.Left }),
	}
	for i, rarity in ipairs(PityConfig.RARITIES) do
		dropGems[rarity] = e("Frame", { LayoutOrder = i, Size = UDim2.fromOffset(56, 32), BackgroundTransparency = 1 }, {
			Gem = e(Parts.Gem, { rarity = rarity, scale = 0.8, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5) }),
			Count = text({ text = cur and tostring(cur.w[i] or 0) or "-", font = Style.Font.Number, size = 18,
				color = Style.Text.Value, align = Enum.TextXAlignment.Right, Size = UDim2.fromScale(1, 1) }),
		})
	end

	local left = list(7, {
		Chips = e("Frame", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1 }, chips),
		-- "Score: Last 24 Hours": the heading names the number, so the blocks under the
		-- bar read as its parts (Overworld / Dungeon) and companions (Kills / Runs).
		Heading = e(Parts.Heading, { text = "Score: " .. WINDOW_TITLE[props.window], size = 27, order = 2, height = 34 }),
		Score = text({
			text = cur and formatCount(score) or "...",
			font = Style.Font.Number, size = 42, color = Style.Text.Value, height = 46, order = 3,
		}),
		Split = e(Parts.SplitBar, { a = cur and cur.o or 0, b = cur and cur.d or 0, height = 14, order = 4 }),
		Stats = e("Frame", { LayoutOrder = 5, Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1 }, {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Overworld = e(StatBlock, { value = cur and cur.o or 0, caption = "Overworld", color = moss, order = 1 }),
			Dungeon = e(StatBlock, { value = cur and cur.d or 0, caption = "Dungeon", color = iron, order = 2 }),
			Kills = e(StatBlock, { value = cur and cur.k or 0, caption = "Kills", order = 3 }),
			Runs = e(StatBlock, { value = cur and cur.r or 0, caption = "Runs", order = 4 }),
		}),
		Drops = e("Frame", { LayoutOrder = 6, Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1 }, dropGems),
		ChartTitle = text({ text = CHART_TITLE[props.window], font = Style.Font.BodyBold, size = 14,
			color = Style.Text.Muted, align = Enum.TextXAlignment.Left, height = 18, order = 7 }),
		Chart = e(ScoreChart, {
			points = summary and summary.chart or {}, window = props.window,
			Size = UDim2.new(1, 0, 0, 108), LayoutOrder = 8,
		}),
		Back = e(Parts.ChromeButton, {
			text = "<  Back", art = "chip", Size = UDim2.new(0.42, 0, 0, 36), LayoutOrder = 9, textSize = 17,
			onClick = props.onBack,
		}),
	})

	local rightRows: { [string]: any } = {
		Layout = e("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
		Header = e("Frame", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1 }, {
			Columns = e(HeaderRow, { order = 1, a = WINDOW_SHORT[props.window], b = "Your avg" }),
			Help = e(Parts.HelpIcon, {
				text = AVERAGE_HELP, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
			}),
		}),
		Score = e(CompareRow, { label = "Score", now = score, avg = avg and (avg.o + avg.d) or nil, order = 2 }),
		Kills = e(CompareRow, { label = "Kills", now = cur and cur.k or 0, avg = avg and avg.k or nil, order = 3 }),
		Runs = e(CompareRow, { label = "Runs", now = cur and cur.r or 0, avg = avg and avg.r or nil, order = 4 }),
		DropsRow = e(CompareRow, { label = "Drops", now = drops, avg = avg and avgDrops or nil, order = 5 }),
		NotEnough = (summary and not avg) and text({
			text = string.format("Your average shows up after a few more %ss of play.", WINDOW_NOUN[props.window]),
			wrap = true, size = 14, color = Style.Text.Muted, height = 20, order = 6,
		}) or nil,
	}
	-- The rest of the page belongs to the tier's illustration (empty until its art exists).
	local illustration = Style.Art("illustration_t" .. props.tier)
	local right = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
		Table = e("Frame", { Size = UDim2.new(1, 0, 0, 190), BackgroundTransparency = 1 }, rightRows),
		Illustration = illustration and e("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.new(1, 0, 1, -206),
			BackgroundTransparency = 1,
			Image = illustration.Image,
			ScaleType = Enum.ScaleType.Fit,
		}) or nil,
	})

	return e(Book, { tabs = props.tabs, side = props.side, left = left, right = right })
end

------------------------------------------------------------------------------------------
-- Page
------------------------------------------------------------------------------------------

local function LootScorePage(props: { side: any? })
	local snapshot = InventoryData.useSnapshot()
	local view, setView = React.useState("landing")
	local window, setWindow = React.useState("24H")

	local profile = snapshot and snapshot.profile
	local stats = (profile and profile.stats) or {}
	local tracking = (type(stats.tracking) == "table" and stats.tracking) or {}
	local combat = type(stats.combat) == "table" and tonumber(stats.combat.level) or nil
	local level = combat or tonumber(player:GetAttribute("CombatLevel")) or 1

	local highestTier = 1
	for t, need in ipairs(TIER_LEVELS) do
		if level >= need then highestTier = t end
	end
	local selectedTier, setSelectedTier = React.useState(highestTier)
	local tier = math.min(selectedTier, highestTier)

	local tabs: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for t = 1, #TIER_LEVELS do
		local unlocked = t <= highestTier
		tabs["T" .. t] = e(Parts.ChromeButton, {
			text = "T" .. t,
			selected = t == tier,
			disabled = not unlocked,
			locked = not unlocked,
			art = "bookmark_tab",
			artSelected = "bookmark_tab_active",
			Size = UDim2.fromOffset(96, Style.TAB_H),
			LayoutOrder = t,
			textSize = 17,
			onClick = function() setSelectedTier(t) end,
		})
	end
	local tabRow = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, tabs)

	if view == "activity" then
		return e(Activity, {
			tier = tier, window = window, tabs = tabRow, side = props.side, setWindow = setWindow,
			onBack = function() setView("landing") end,
		})
	end
	return e(Landing, {
		tier = tier, tracking = tracking, tabs = tabRow, side = props.side,
		onActivity = function() setView("activity") end,
	})
end

return LootScorePage
