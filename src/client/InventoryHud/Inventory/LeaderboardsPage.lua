--!strict
--  FIRST PASS (2026-10-01): built from the art we already had (Journal book, chips, carved
--  medallions). Due a second pass: a proper podium piece, rank badges.
--
--  LeaderboardsPage -- the Journal's Leaderboards page (cross-server).
--    left   board chips (Skills / Kills / Score) and its filters: the skill (Combat / Mining /
--           Fishing), or the period (1H / 24H / 7D / 30D / All) and tier (All, T1-T5); the top
--           three on a podium of carved rings; your own standing
--    right  ranks 4 to 25
--
--  Data: GameEvents/JournalRequest("leaderboard", board, a, b) -> SSS/LeaderboardService.Read:
--  { available, rows = { { rank, userId, name, value, level? } }, you = { rank?, value?, level? } }.
--  Kills and score windows are rolling, summed from short buckets; the server batches writes once
--  a minute and caches reads for 30 s, so a fresh kill shows up within about a minute.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Journal = script.Parent:WaitForChild("Journal")
local Style = require(Journal:WaitForChild("Style"))
local Parts = require(Journal:WaitForChild("Parts"))
local Book = require(Journal:WaitForChild("Book"))

local e = React.createElement
local text = Parts.Text

local BOARDS = { { id = "skill", label = "Skills" }, { id = "kills", label = "Kills" }, { id = "score", label = "Score" } }
local SKILLS = { { id = "combat", label = "Combat" }, { id = "mining", label = "Mining" }, { id = "fishing", label = "Fishing" } }
local PERIODS = { "1H", "24H", "7D", "30D", "All" }
local PERIOD_TITLE = { ["1H"] = "last hour", ["24H"] = "last 24 hours", ["7D"] = "last 7 days", ["30D"] = "last 30 days", All = "all time" }
local TIERS = { 0, 1, 2, 3, 4, 5 } -- 0 = all tiers

local function headshot(userId: number): string
	return ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(userId)
end

local function formatCount(n: number): string
	local out = tostring(math.max(0, math.floor(n)))
	while true do
		local replaced: number
		out, replaced = string.gsub(out, "^(%d+)(%d%d%d)", "%1,%2")
		if replaced == 0 then break end
	end
	return out
end

local function valueText(board: string, row: any): string
	if board == "skill" then return "Level " .. tostring(row.level or 1) end
	if board == "kills" then return formatCount(row.value or 0) .. " kills" end
	return formatCount(row.value or 0)
end

local function useBoard(board: string, a: string, b: number)
	local result, setResult = React.useState(nil :: any)
	local loading, setLoading = React.useState(true)
	React.useEffect(function()
		local alive = true
		setLoading(true)
		task.spawn(function()
			local remote = ReplicatedStorage:WaitForChild("GameEvents"):WaitForChild("JournalRequest", 10)
			if not remote then return end
			local ok, reply = pcall(function()
				return (remote :: RemoteFunction):InvokeServer("leaderboard", board, a, b ~= 0 and b or nil)
			end)
			if alive then
				setResult(ok and reply or nil)
				setLoading(false)
			end
		end)
		return function() alive = false end
	end, { board, a, b } :: { any })
	return result, loading
end

local function ChipRow(props: { items: { any }, selected: any, width: number, order: number, onPick: (any) -> () })
	local chips: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for i, item in ipairs(props.items) do
		chips["c" .. i] = e(Parts.ChromeButton, {
			text = item.label, selected = item.id == props.selected,
			art = "chip", artSelected = "chip_selected",
			Size = UDim2.fromOffset(props.width, 30), LayoutOrder = i, textSize = 14,
			onClick = function() props.onPick(item.id) end,
		})
	end
	return e("Frame", { LayoutOrder = props.order, Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1 }, chips)
end

local function PodiumSpot(props: { row: any?, place: number, board: string, x: number, lift: number })
	local row = props.row
	local size = props.place == 1 and 92 or 74
	return e("Frame", {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(props.x, 0, 1, -props.lift),
		Size = UDim2.fromOffset(150, size + 52), BackgroundTransparency = 1,
	}, {
		Ring = e(Parts.Medallion, {
			image = row and headshot(row.userId) or nil, round = true, size = size, lit = props.place == 1, dim = row == nil,
			AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0),
		}),
		Place = text({
			text = tostring(props.place), font = Style.Font.Number, size = 16, color = Style.Chrome.Selected,
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, size / 2 - 6, 0, 10), Size = UDim2.fromOffset(24, 22), ZIndex = 5,
		}),
		Name = text({
			text = row and row.name or "-", font = Style.Font.Heading, size = 15, color = Style.Text.Heading, truncate = true,
			Position = UDim2.fromOffset(0, size + 4), Size = UDim2.new(1, 0, 0, 20),
		}),
		Value = text({
			text = row and valueText(props.board, row) or "", font = Style.Font.Number, size = 14, color = Style.Text.Value,
			Position = UDim2.fromOffset(0, size + 24), Size = UDim2.new(1, 0, 0, 18),
		}),
	})
end

local function RankRow(props: { row: any, board: string, you: boolean, order: number })
	local row = props.row
	return e("Frame", { LayoutOrder = props.order, Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1 }, {
		Rank = text({
			text = tostring(row.rank), font = Style.Font.Number, size = 16, color = Style.Text.Muted,
			align = Enum.TextXAlignment.Right, Size = UDim2.new(0, 30, 1, 0),
		}),
		Portrait = e(Parts.Medallion, {
			image = headshot(row.userId), round = true, size = 34, lit = props.you,
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 40, 0.5, 0),
		}),
		Name = text({
			text = row.name .. (props.you and "  (you)" or ""), font = Style.Font.Heading, size = 16,
			color = props.you and Style.Text.Good or Style.Text.Heading, truncate = true,
			align = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(84, 0), Size = UDim2.new(1, -200, 1, 0),
		}),
		Value = text({
			text = valueText(props.board, row), font = Style.Font.Number, size = 16, color = Style.Text.Value,
			align = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 120, 1, 0),
		}),
		Rule = e("Frame", {
			AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Style.Text.Muted, BackgroundTransparency = 0.8, BorderSizePixel = 0,
		}),
	})
end

local function LeaderboardsPage(props: { side: any? })
	local board, setBoard = React.useState("kills")
	local skill, setSkill = React.useState("combat")
	local period, setPeriod = React.useState("24H")
	local tier, setTier = React.useState(0)

	local a = board == "skill" and skill or period
	local b = board == "skill" and 0 or tier
	local result, loading = useBoard(board, a, b)
	local rows = (result and result.rows) or {}
	local you = result and result.you
	local myId = game:GetService("Players").LocalPlayer.UserId

	-- Title for the right page: "Kills, last 24 hours, T2" / "Combat level".
	local title
	if board == "skill" then
		title = (skill:sub(1, 1):upper() .. skill:sub(2)) .. " level"
	else
		title = ("%s, %s%s"):format(board == "kills" and "Kills" or "Score", PERIOD_TITLE[period], tier ~= 0 and (", T" .. tier) or "")
	end

	-- Left page: the board picker, filters, podium, you.
	local leftChildren: { [string]: any } = {
		Layout = e("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center }),
		Heading = e(Parts.Heading, { text = "Leaderboards", size = 26, order = 1, height = 34 }),
		Boards = e(ChipRow, { items = BOARDS, selected = board, width = 120, order = 2, onPick = setBoard }),
	}
	if board == "skill" then
		leftChildren.Skills = e(ChipRow, { items = SKILLS, selected = skill, width = 110, order = 3, onPick = setSkill })
	else
		local periodItems = {}
		for _, p in ipairs(PERIODS) do table.insert(periodItems, { id = p, label = p }) end
		local tierItems = {}
		for _, t in ipairs(TIERS) do table.insert(tierItems, { id = t, label = t == 0 and "All" or ("T" .. t) }) end
		leftChildren.Periods = e(ChipRow, { items = periodItems, selected = period, width = 74, order = 3, onPick = setPeriod })
		leftChildren.Tiers = e(ChipRow, { items = tierItems, selected = tier, width = 62, order = 4, onPick = setTier })
	end
	leftChildren.Divider = e(Parts.Divider, { order = 5 })
	leftChildren.Podium = e("Frame", { LayoutOrder = 6, Size = UDim2.new(1, 0, 0, 170), BackgroundTransparency = 1 }, {
		Second = e(PodiumSpot, { row = rows[2], place = 2, board = board, x = 0.2, lift = 0 }),
		First = e(PodiumSpot, { row = rows[1], place = 1, board = board, x = 0.5, lift = 18 }),
		Third = e(PodiumSpot, { row = rows[3], place = 3, board = board, x = 0.8, lift = 0 }),
	})
	local youLine
	if loading then
		youLine = "Reading the boards..."
	elseif not result or result.available == false then
		youLine = "The boards can't be reached right now."
	elseif you and you.rank then
		youLine = ("You: #%d, %s"):format(you.rank, valueText(board, you))
	elseif you then
		youLine = ("You: %s, not in the top 100 yet"):format(valueText(board, you))
	else
		youLine = "You aren't on this board yet."
	end
	leftChildren.You = text({ text = youLine, font = Style.Font.BodyBold, size = 15, color = Style.Text.Body, height = 22, order = 7 })

	-- Right page: ranks 4..25.
	local list: { [string]: any } = {
		Layout = e("UIListLayout", { Padding = UDim.new(0, 0), SortOrder = Enum.SortOrder.LayoutOrder }),
	}
	for i = 4, #rows do
		list["r" .. i] = e(RankRow, { row = rows[i], board = board, you = rows[i].userId == myId, order = i })
	end
	local right = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
		Heading = e(Parts.Heading, { text = title, size = 22, height = 32 }),
		Rule = e("Frame", { Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1 }, {
			Line = e(Parts.Divider, { width = 1 }),
		}),
		Empty = (#rows <= 3 and not loading) and text({
			text = #rows == 0 and "No one on this board yet." or "That's everyone so far.",
			size = 15, color = Style.Text.Muted, Position = UDim2.fromOffset(0, 70), height = 24,
		}) or nil,
		List = e("ScrollingFrame", {
			Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 1, -52),
			BackgroundTransparency = 1, BorderSizePixel = 0,
			CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 4, ScrollBarImageColor3 = Style.Text.Muted,
		}, list),
	})

	return e(Book, {
		side = props.side,
		left = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, leftChildren),
		right = right,
	})
end

return LeaderboardsPage
