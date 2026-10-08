--!strict
--  PartyPanel -- the Tab menu's Party destination (rebuilt 2026-10-01 in the Journal's look:
--  Journal/Book, Parts, Style; no new art).
--
--    left   Your party: each member in a carved ring (their Roblox head shot), Leader / Member,
--           combat level; the open seats up to PartyConfig.MAX_PARTY_SIZE; the loot boost; Leave.
--           Not in a party: what a party gives you, and Create party.
--    right  Players here: everyone else in the server, with Invite (needs a party, not full).
--           Already in your party / in another party is shown instead of the button.
--
--  Server side is unchanged: RS/PartyRequestUtil (Request("create" | "invite" | "leave"),
--  Changed, GetMyParty / GetState). Invites you RECEIVE are still the PartyClient popup.
--  Levels come from the CombatLevel player attribute (set by ProfileService for nametags).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local PartyRequestUtil = require(ReplicatedStorage:WaitForChild("PartyRequestUtil"))
local PartyConfig = require(ReplicatedStorage:WaitForChild("PartyConfig"))
local Journal = script.Parent:WaitForChild("Journal")
local Style = require(Journal:WaitForChild("Style"))
local Parts = require(Journal:WaitForChild("Parts"))
local Book = require(Journal:WaitForChild("Book"))

local e = React.createElement
local text, list = Parts.Text, Parts.List
local player = Players.LocalPlayer

local MEMBER_ROW_H = 46
local PLAYER_ROW_H = 58
local PARTY_HELP = ("A party shares kill score on every kill and earns %d%% more coins per member (from 2 members). Up to %d players.")
	:format(math.floor(PartyConfig.BOOST_PER_MEMBER * 100 + 0.5), PartyConfig.MAX_PARTY_SIZE)

local REASONS = {
	throttled = "Too fast. Wait a moment.",
	party_full = "Your party is full.",
	not_in_party = "Create a party first.",
	no_party = "Create a party first.",
	already_in_party = "You're already in a party.",
	target_in_party = "They're already in a party.",
	player_gone = "They've left the world.",
	bad_target = "They've left the world.",
}

local function headshot(userId: number): string
	return ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(userId)
end

local function levelOf(userId: number): number?
	local plr = Players:GetPlayerByUserId(userId)
	local lvl = plr and plr:GetAttribute("CombatLevel")
	return type(lvl) == "number" and lvl or nil
end

local function displayName(plr: Player): string
	return plr.DisplayName ~= "" and plr.DisplayName or plr.Name
end

local function usePartyState()
	local state, setState = React.useState(PartyRequestUtil.GetState())
	React.useEffect(function()
		local conn = PartyRequestUtil.Changed:Connect(function(payload)
			setState(payload)
		end)
		task.spawn(PartyRequestUtil.Refresh)
		return function() conn:Disconnect() end
	end, {})
	return state
end

local function usePlayers(): { Player }
	local players, setPlayers = React.useState(Players:GetPlayers())
	React.useEffect(function()
		local function refresh() setPlayers(Players:GetPlayers()) end
		local c1 = Players.PlayerAdded:Connect(refresh)
		local c2 = Players.PlayerRemoving:Connect(function()
			task.defer(refresh) -- after the player is actually gone
		end)
		return function() c1:Disconnect(); c2:Disconnect() end
	end, {})
	return players
end

local function MemberRow(props: { userId: number?, name: string?, leader: boolean?, you: boolean?, order: number, headshotUserId: number? })
	if not props.userId then
		return e("Frame", { LayoutOrder = props.order, Size = UDim2.new(1, 0, 0, MEMBER_ROW_H), BackgroundTransparency = 1 }, {
			Ring = e(Parts.Medallion, { size = 40, dim = true, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 4, 0.5, 0) }),
			Open = text({
				text = "Open seat", size = 14, color = Style.Text.Muted,
				align = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(56, 0), Size = UDim2.new(1, -56, 1, 0),
			}),
		})
	end
	local level = levelOf(props.userId)
	return e("Frame", { LayoutOrder = props.order, Size = UDim2.new(1, 0, 0, MEMBER_ROW_H), BackgroundTransparency = 1 }, {
		Portrait = e(Parts.Medallion, {
			image = headshot(props.headshotUserId or props.userId), round = true, size = 44, lit = props.leader,
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 2, 0.5, 0),
		}),
		Name = text({
			text = (props.name or "?") .. (props.you and "  (you)" or ""), font = Style.Font.Heading, size = 17,
			color = Style.Text.Heading, truncate = true,
			align = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(56, 2), Size = UDim2.new(1, -130, 0, 22),
		}),
		Role = text({
			text = props.leader and "Leader" or "Member", size = 13,
			color = props.leader and Style.Text.Good or Style.Text.Muted,
			align = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(56, 23), Size = UDim2.new(1, -130, 0, 18),
		}),
		Level = level and text({
			text = "Lv " .. tostring(level), font = Style.Font.Number, size = 16, color = Style.Text.Value,
			align = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -4, 0.5, 0),
			Size = UDim2.fromOffset(70, 22),
		}) or nil,
	})
end

local function PlayerRow(props: { plr: Player, state: string, order: number, onInvite: () -> () })
	local plr = props.plr
	local level = levelOf(plr.UserId)
	local right
	if props.state == "invite" then
		right = e(Parts.ChromeButton, {
			text = "Invite", art = "chip", artSelected = "chip_selected",
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(96, 34),
			textSize = 15, onClick = props.onInvite,
		})
	else
		right = text({
			text = props.state, size = 13, color = Style.Text.Muted,
			align = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -4, 0.5, 0),
			Size = UDim2.fromOffset(120, 20),
		})
	end
	return e("Frame", { LayoutOrder = props.order, Size = UDim2.new(1, 0, 0, PLAYER_ROW_H), BackgroundTransparency = 1 }, {
		Portrait = e(Parts.Medallion, {
			image = headshot(plr.UserId), round = true, size = 46,
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 2, 0.5, 0),
		}),
		Name = text({
			text = displayName(plr), font = Style.Font.Heading, size = 17, color = Style.Text.Heading, truncate = true,
			align = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(60, 8), Size = UDim2.new(1, -190, 0, 22),
		}),
		Level = text({
			text = level and ("Combat level " .. tostring(level)) or "", size = 13, color = Style.Text.Muted,
			align = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(60, 30), Size = UDim2.new(1, -190, 0, 18),
		}),
		Right = right,
		Rule = e("Frame", {
			AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Style.Text.Muted, BackgroundTransparency = 0.75, BorderSizePixel = 0,
		}),
	})
end

local function PartyPanel()
	local state = usePartyState()
	local players = usePlayers()
	local status, setStatus = React.useState("")

	local myParty = state and state.myParty or nil
	local inParty = myParty ~= nil
	local members = (myParty and myParty.members) or {}
	local full = #members >= PartyConfig.MAX_PARTY_SIZE
	local inMine: { [number]: boolean } = {}
	for _, m in ipairs(members) do inMine[m.userId] = true end
	local inAny: { [number]: boolean } = {}
	for _, uid in ipairs((state and state.partyUserIds) or {}) do inAny[uid] = true end

	local function act(action: string, arg: any?, done: string)
		local ok, err = PartyRequestUtil.Request(action, arg)
		setStatus(ok and done or (REASONS[err] or "Couldn't do that."))
	end

	-- Left page: your party.
	local left
	if inParty then
		local rows: { [string]: any } = {
			Layout = e("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
		}
		local order = 0
		for _, m in ipairs(members) do
			order += 1
			rows["m" .. m.userId] = e(MemberRow, {
				userId = m.userId, name = m.name, leader = m.userId == myParty.leaderUserId,
				headshotUserId = m.headshotUserId, -- a companion wears its owner's face
				you = m.userId == player.UserId, order = m.userId == myParty.leaderUserId and 0 or order,
			})
		end
		for i = #members + 1, PartyConfig.MAX_PARTY_SIZE do
			rows["open" .. i] = e(MemberRow, { order = 100 + i })
		end
		local boost = tonumber(myParty.lootBoostPct) or 0
		left = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
			Heading = e(Parts.Heading, { text = "Your Party", size = 26, height = 34 }),
			Count = text({
				text = ("%d / %d"):format(#members, PartyConfig.MAX_PARTY_SIZE), font = Style.Font.Number, size = 16,
				color = Style.Text.Muted, align = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 0, 0, 6), Size = UDim2.fromOffset(80, 22),
			}),
			Members = e("Frame", { Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 1, -42 - 78), BackgroundTransparency = 1 }, {
				Scroll = e("ScrollingFrame", {
					Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
					CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
					ScrollBarThickness = 4, ScrollBarImageColor3 = Style.Text.Muted,
				}, rows),
			}),
			Boost = text({
				text = boost > 0 and ("Party loot boost: +%d%% coins"):format(boost) or "The loot boost starts at 2 members",
				size = 14, font = Style.Font.BodyBold, color = boost > 0 and Style.Text.Good or Style.Text.Muted,
				AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -50), Size = UDim2.new(1, 0, 0, 20),
			}),
			Leave = e(Parts.ChromeButton, {
				text = "Leave party", art = "chip", artSelected = "chip_selected",
				AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -4), Size = UDim2.fromOffset(200, 40),
				textSize = 16, onClick = function() act("leave", nil, "You left the party.") end,
			}),
		})
	else
		left = list(12, {
			Heading = e(Parts.Heading, { text = "Your Party", size = 26, order = 1, height = 34 }),
			Glyph = e(Parts.Medallion, {
				image = (Style.Art("nav_glyph_party") or { Image = "" }).Image, size = 120, imageScale = 0.5, order = 2,
			}),
			Alone = text({ text = "You travel alone", font = Style.Font.Heading, size = 22, color = Style.Text.Heading, height = 30, order = 3 }),
			Why = text({ text = PARTY_HELP, size = 14, color = Style.Text.Body, wrap = true, height = 58, order = 4 }),
			Create = e(Parts.ChromeButton, {
				text = "Create party", art = "chip", artSelected = "chip_selected", selected = true,
				Size = UDim2.fromOffset(220, 44), LayoutOrder = 5, textSize = 17,
				onClick = function() act("create", nil, "Party created. Invite players from the right.") end,
			}),
		})
	end

	-- Right page: everyone else here.
	local rows: { [string]: any } = {
		Layout = e("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
	}
	local others = {}
	for _, plr in ipairs(players) do
		if plr ~= player then table.insert(others, plr) end
	end
	table.sort(others, function(a, b) return displayName(a) < displayName(b) end)
	for i, plr in ipairs(others) do
		local rowState
		if inMine[plr.UserId] then
			rowState = "In your party"
		elseif inAny[plr.UserId] then
			rowState = "In a party"
		elseif not inParty then
			rowState = "Create a party to invite"
		elseif full then
			rowState = "Your party is full"
		else
			rowState = "invite"
		end
		rows["p" .. plr.UserId] = e(PlayerRow, {
			plr = plr, state = rowState, order = i,
			onInvite = function() act("invite", plr.UserId, "Invite sent to " .. displayName(plr) .. ".") end,
		})
	end
	local right = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
		Heading = e(Parts.Heading, { text = "Players Here", size = 26, height = 34 }),
		Help = e(Parts.HelpIcon, { text = PARTY_HELP, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 6) }),
		Rule = e("Frame", { Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1 }, {
			Line = e(Parts.Divider, { width = 1 }),
		}),
		Empty = #others == 0 and text({
			text = "No one else is in this world right now.", size = 15, color = Style.Text.Muted,
			Position = UDim2.fromOffset(0, 70), height = 24,
		}) or nil,
		List = e("ScrollingFrame", {
			Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 1, -50 - 26),
			BackgroundTransparency = 1, BorderSizePixel = 0,
			CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 4, ScrollBarImageColor3 = Style.Text.Muted,
		}, rows),
		Status = text({
			text = status, size = 14, color = Style.Text.Body,
			AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), height = 22,
		}),
	})

	return e(Book, { left = left, right = right })
end

return PartyPanel
