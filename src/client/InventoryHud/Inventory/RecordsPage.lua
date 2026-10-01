--!strict
--  FIRST PASS (2026-10-01): built from the art we already had (Journal book, carved
--  medallions, the ink rules). Due a second pass: more records, its own art.
--
--  RecordsPage -- the Journal's Records page: your lifetime totals, written as a ledger.
--    left   Combat: monsters slain, score (overworld / dungeon), dungeons cleared, and a
--           per-tier table (score, runs cleared)
--    right  Mining (ores, coal) and Fishing (fish caught)
--
--  Data: the profile snapshot, profile.stats.tracking (uncapped lifetime counters bumped by
--  QuestProgressService and LootService; see ProfileTypes' DefaultProfile). Kills don't push a
--  snapshot, so JournalPanel requests a sync when the Journal opens.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local ItemConfig = require(ReplicatedStorage:WaitForChild("ItemConfig"))
local HudIcons = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Icons"):WaitForChild("Hud"):WaitForChild("HudIcons"))
local InventoryData = require(script.Parent:WaitForChild("InventoryData"))
local Journal = script.Parent:WaitForChild("Journal")
local Style = require(Journal:WaitForChild("Style"))
local Parts = require(Journal:WaitForChild("Parts"))
local Book = require(Journal:WaitForChild("Book"))

local e = React.createElement
local text, list = Parts.Text, Parts.List

local function formatCount(n: number): string
	local out = tostring(math.max(0, math.floor(n)))
	while true do
		local replaced: number
		out, replaced = string.gsub(out, "^(%d+)(%d%d%d)", "%1,%2")
		if replaced == 0 then break end
	end
	return out
end

local function tierValue(list: any, tier: number): number
	return type(list) == "table" and (tonumber(list[tier]) or tonumber(list[tostring(tier)]) or 0) or 0
end

local function sum(list: any): number
	local total = 0
	for t = 1, 5 do total += tierValue(list, t) end
	return total
end

-- "Monsters slain .......... 1,204": a ledger line, label left, value right, a faint rule under.
local function Line(props: { label: string, value: number, order: number, sub: boolean? })
	return e("Frame", { LayoutOrder = props.order, Size = UDim2.new(1, 0, 0, props.sub and 24 or 30), BackgroundTransparency = 1 }, {
		Label = text({
			text = props.label, size = props.sub and 14 or 16,
			font = props.sub and Style.Font.Body or Style.Font.BodyBold,
			color = props.sub and Style.Text.Muted or Style.Text.Body,
			align = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(props.sub and 16 or 0, 0), Size = UDim2.new(0.7, 0, 1, 0),
		}),
		Value = text({
			text = formatCount(props.value), font = Style.Font.Number, size = props.sub and 15 or 18,
			color = props.sub and Style.Text.Body or Style.Text.Value,
			align = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.3, 0, 1, 0),
		}),
		Rule = e("Frame", {
			AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Style.Text.Muted, BackgroundTransparency = 0.8, BorderSizePixel = 0,
		}),
	})
end

local function Header(props: { icon: string, title: string, level: number?, order: number })
	return e("Frame", { LayoutOrder = props.order, Size = UDim2.new(1, 0, 0, 60), BackgroundTransparency = 1 }, {
		Icon = e(Parts.Medallion, {
			image = props.icon, size = 56, imageScale = 0.56, lit = true,
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
		}),
		Title = text({
			text = props.title, font = Style.Font.Heading, size = 24, color = Style.Text.Heading,
			align = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(68, 0), Size = UDim2.new(1, -180, 1, 0),
		}),
		Level = props.level and text({
			text = "Level " .. props.level, font = Style.Font.Number, size = 18, color = Style.Text.Muted,
			align = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 110, 1, 0),
		}) or nil,
	})
end

local function TierTable(props: { tracking: any, order: number })
	local rows: { [string]: any } = {
		Layout = e("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
		Head = e("Frame", { LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1 }, {
			T = text({ text = "Tier", size = 13, font = Style.Font.BodyBold, color = Style.Text.Muted, align = Enum.TextXAlignment.Left, Size = UDim2.new(0.3, 0, 1, 0) }),
			S = text({ text = "Score", size = 13, font = Style.Font.BodyBold, color = Style.Text.Muted, align = Enum.TextXAlignment.Right, Position = UDim2.fromScale(0.3, 0), Size = UDim2.new(0.4, 0, 1, 0) }),
			R = text({ text = "Runs", size = 13, font = Style.Font.BodyBold, color = Style.Text.Muted, align = Enum.TextXAlignment.Right, Position = UDim2.fromScale(0.7, 0), Size = UDim2.new(0.3, 0, 1, 0) }),
		}),
	}
	for t = 1, 5 do
		local score = tierValue(props.tracking.scoreByTier, t)
		local runs = tierValue(props.tracking.runsClearedByTier, t)
		local any = score > 0 or runs > 0
		local color = any and Style.Text.Value or Style.Text.Muted
		rows["T" .. t] = e("Frame", { LayoutOrder = t, Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1 }, {
			T = text({ text = "T" .. t, size = 15, font = Style.Font.Heading, color = color, align = Enum.TextXAlignment.Left, Size = UDim2.new(0.3, 0, 1, 0) }),
			S = text({ text = formatCount(score), size = 15, font = Style.Font.Number, color = color, align = Enum.TextXAlignment.Right, Position = UDim2.fromScale(0.3, 0), Size = UDim2.new(0.4, 0, 1, 0) }),
			R = text({ text = formatCount(runs), size = 15, font = Style.Font.Number, color = color, align = Enum.TextXAlignment.Right, Position = UDim2.fromScale(0.7, 0), Size = UDim2.new(0.3, 0, 1, 0) }),
		})
	end
	return e("Frame", { LayoutOrder = props.order, Size = UDim2.new(1, 0, 0, 22 * 6), BackgroundTransparency = 1 }, rows)
end

local function RecordsPage(props: { side: any? })
	local snapshot = InventoryData.useSnapshot()
	local profile = snapshot and snapshot.profile
	local stats = (profile and profile.stats) or {}
	local tracking = (type(stats.tracking) == "table" and stats.tracking) or {}
	local function level(key: string): number?
		local s = stats[key]
		return type(s) == "table" and tonumber(s.level) and math.floor(s.level) or nil
	end

	local totalScore = sum(tracking.scoreByTier)
	local dungeonScore = sum(tracking.dungeonScoreByTier)

	local left = list(4, {
		Header = e(Header, { icon = HudIcons.COMBAT, title = "Combat", level = level("combat"), order = 1 }),
		Kills = e(Line, { label = "Monsters slain", value = tonumber(tracking.mobsKilled) or 0, order = 2 }),
		Score = e(Line, { label = "Score earned", value = totalScore, order = 3 }),
		Overworld = e(Line, { label = "in the world", value = math.max(0, totalScore - dungeonScore), order = 4, sub = true }),
		Dungeon = e(Line, { label = "in dungeons", value = dungeonScore, order = 5, sub = true }),
		Runs = e(Line, { label = "Dungeons cleared", value = sum(tracking.runsClearedByTier), order = 6 }),
		Gap = e("Frame", { LayoutOrder = 7, Size = UDim2.new(1, 0, 0, 6), BackgroundTransparency = 1 }),
		Tiers = e(TierTable, { tracking = tracking, order = 8 }),
	})

	local right = list(6, {
		Mining = e(Header, { icon = ItemConfig.TOOL_ICONS.Pickaxe, title = "Mining", level = level("mining"), order = 1 }),
		Ores = e(Line, { label = "Ores mined", value = tonumber(tracking.oresMined) or 0, order = 2 }),
		Coal = e(Line, { label = "Coal mined", value = tonumber(tracking.coalMined) or 0, order = 3 }),
		Divider = e(Parts.Divider, { order = 4 }),
		Fishing = e(Header, { icon = ItemConfig.TOOL_ICONS.FishingRod, title = "Fishing", level = level("fishing"), order = 5 }),
		Fish = e(Line, { label = "Fish caught", value = tonumber(tracking.fishCaught) or 0, order = 6 }),
	})

	return e(Book, { side = props.side, left = left, right = right })
end

return RecordsPage
