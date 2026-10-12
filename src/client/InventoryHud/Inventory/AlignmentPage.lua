--!strict
--  AlignmentPage -- the Journal's Alignment page (2026-10-11): pick Lawful / Neutral / Chaotic.
--    left   what you are now: its medallion and colour band, what it means, and whether you
--           can change it here (in a safe zone? held to Lawful after a death?)
--    right  the three choices with their trade-offs and a Choose button each
--
--  Rules live in RS/AlignmentConfig and are enforced by the server (ProfileService.SetAlignment,
--  through the AlignmentSet RemoteFunction): only in a safe zone, out of combat; dying Neutral or
--  Chaotic sets you to Lawful and holds you there (profile.alignment.cooldownUntil). This page
--  only mirrors them so the buttons say why before you press. Safe-zone state is the
--  `InSafeZone` player attribute (ZoneService); combat isn't mirrored, the server's refusal
--  says it. No art of its own yet: the icons are borrowed (Stats defence shield, melee sword,
--  the HUD skull).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local AlignmentConfig = require(ReplicatedStorage:WaitForChild("AlignmentConfig"))
local HearthstoneConfig = require(ReplicatedStorage:WaitForChild("HearthstoneConfig"))
local ShardConfig = require(ReplicatedStorage:WaitForChild("ShardConfig"))
local HudIcons = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Icons"):WaitForChild("Hud"):WaitForChild("HudIcons"))
local InventoryData = require(script.Parent:WaitForChild("InventoryData"))
local DungeonMenuNet = require(script.Parent.Parent.Parent:WaitForChild("DungeonMenuNet"))
local Journal = script.Parent:WaitForChild("Journal")
local Style = require(Journal:WaitForChild("Style"))
local Parts = require(Journal:WaitForChild("Parts"))
local Book = require(Journal:WaitForChild("Book"))

local e = React.createElement
local text, list = Parts.Text, Parts.List
local player = Players.LocalPlayer

local ROW_H = 120

local function artImage(key: string): string
	local art = Style.Art(key)
	return art and art.Image or ""
end

local ICONS = {
	Lawful = artImage("icon_cat_defense"),
	Neutral = artImage("icon_cat_melee"),
	Chaotic = HudIcons.SKULL,
}

local REASONS = {
	not_safe_zone = "Only in a safe zone, like a town.",
	in_combat = "Not while you are in combat.",
	on_cooldown = "You died recently. Lawful only for now.",
	throttled = "Too fast. Wait a moment.",
}

local function clock(secs: number): string
	secs = math.max(0, math.floor(secs))
	return ("%d:%02d"):format(math.floor(secs / 60), secs % 60)
end

-- Re-renders every second while mounted (the lockout countdown).
local function useNow(): number
	local now, setNow = React.useState(os.time())
	React.useEffect(function()
		local alive = true
		task.spawn(function()
			while alive do
				task.wait(1)
				if alive then setNow(os.time()) end
			end
		end)
		return function() alive = false end
	end, {})
	return now
end

local function useSafeZone(): boolean
	local safe, setSafe = React.useState(player:GetAttribute("InSafeZone") == true)
	React.useEffect(function()
		local conn = player:GetAttributeChangedSignal("InSafeZone"):Connect(function()
			setSafe(player:GetAttribute("InSafeZone") == true)
		end)
		return function() conn:Disconnect() end
	end, {})
	return safe
end

-- A strip of the alignment's colour (the nametag colour), stroked so bone-white Lawful still
-- reads on parchment.
local function Band(props: { alignment: string, order: number?, Size: UDim2?, Position: UDim2? })
	return e("Frame", {
		LayoutOrder = props.order,
		Size = props.Size or UDim2.fromOffset(150, 6),
		Position = props.Position,
		BackgroundColor3 = AlignmentConfig.COLORS[props.alignment],
		BorderSizePixel = 0,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Edge = e("UIStroke", { Color = Style.Text.Heading, Transparency = 0.55, Thickness = 1 }),
	})
end

local function facts(alignment: string): string
	local pvp = alignment == "Lawful" and "No PvP" or "PvP outside safe zones"
	return ("%s. Hearthstone %ds, shard hop %ds."):format(
		pvp, tonumber(HearthstoneConfig.CHANNEL_SECONDS[alignment]) or 0, tonumber(ShardConfig.CHANNEL_SECONDS[alignment]) or 0)
end

local function ChoiceRow(props: { alignment: string, current: boolean, blocked: string?, busy: boolean,
	order: number, onChoose: () -> () })
	local alignment = props.alignment
	local lockout = AlignmentConfig.DEATH_LOCKOUT[alignment]
	local label = props.current and "Current" or (props.blocked or "Choose")
	return e("Frame", { LayoutOrder = props.order, Size = UDim2.new(1, 0, 0, ROW_H), BackgroundTransparency = 1 }, {
		Icon = e(Parts.Medallion, {
			image = ICONS[alignment], size = 58, lit = props.current, imageScale = 0.56,
			AnchorPoint = Vector2.new(0, 0), Position = UDim2.fromOffset(0, 10),
		}),
		Name = text({
			text = alignment, font = Style.Font.Heading, size = 20, color = Style.Text.Heading,
			align = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(72, 8), Size = UDim2.new(1, -190, 0, 26),
		}),
		Band = e(Band, { alignment = alignment, Size = UDim2.fromOffset(64, 5), Position = UDim2.fromOffset(72, 36) }),
		Facts = text({
			text = facts(alignment), size = 13, font = Style.Font.BodyBold, color = Style.Text.Body, wrap = true,
			align = Enum.TextXAlignment.Left, alignY = Enum.TextYAlignment.Top,
			Position = UDim2.fromOffset(72, 46), Size = UDim2.new(1, -72, 0, 18),
		}),
		Blurb = text({
			text = AlignmentConfig.BLURB[alignment] .. (lockout and (" Die like this and you're Lawful for %d min."):format(math.ceil(lockout / 60)) or ""),
			size = 13, color = Style.Text.Muted, wrap = true,
			align = Enum.TextXAlignment.Left, alignY = Enum.TextYAlignment.Top,
			Position = UDim2.fromOffset(72, 66), Size = UDim2.new(1, -72, 0, 46),
		}),
		Choose = e(Parts.ChromeButton, {
			text = label, art = "chip", artSelected = "chip_selected",
			selected = props.current, disabled = props.current or props.blocked ~= nil or props.busy,
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 8), Size = UDim2.fromOffset(110, 32),
			textSize = 15, onClick = props.onChoose,
		}),
		Rule = e("Frame", {
			AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Style.Text.Muted, BackgroundTransparency = 0.75, BorderSizePixel = 0,
		}),
	})
end

local function AlignmentPage(props: { side: any? })
	local snapshot = InventoryData.useSnapshot()
	local now = useNow()
	local safe = useSafeZone()
	local status, setStatus = React.useState("")
	local busy, setBusy = React.useState(false)

	local saved = snapshot and snapshot.profile and snapshot.profile.alignment or {}
	local attr = player:GetAttribute("PlayerAlignment")
	local current: string = "Lawful"
	if type(saved.current) == "string" and AlignmentConfig.COLORS[saved.current] then
		current = saved.current
	elseif type(attr) == "string" and AlignmentConfig.COLORS[attr] then
		current = attr
	end
	local locked = math.max(0, (tonumber(saved.cooldownUntil) or 0) - now)

	local function choose(alignment: string)
		if busy then return end
		setBusy(true)
		local remote = ReplicatedStorage:FindFirstChild("AlignmentSet")
		local ok, reason = false, "unavailable"
		if remote then
			local called, a, b = pcall(function() return (remote :: RemoteFunction):InvokeServer(alignment) end)
			if called then ok, reason = a == true, b end
		end
		DungeonMenuNet.requestSync()
		setBusy(false)
		setStatus(ok and "" or (REASONS[reason] or "Couldn't change your alignment."))
	end

	-- Where you stand, said before you press anything.
	local where, whereColor
	if locked > 0 and current == "Lawful" then
		where, whereColor = "Held to Lawful for " .. clock(locked) .. " after your death.", Style.Text.Bad
	elseif safe then
		where, whereColor = "You're in a safe zone. You can change it here.", Style.Text.Good
	else
		where, whereColor = "Go to a safe zone, like a town, to change it.", Style.Text.Muted
	end

	local left = list(8, {
		Heading = e(Parts.Heading, { text = "Alignment", size = 26, order = 1, height = 34 }),
		Medal = e(Parts.Medallion, { image = ICONS[current], size = 120, lit = true, imageScale = 0.5, order = 2 }),
		You = text({ text = "You are", size = 15, color = Style.Text.Muted, height = 18, order = 3 }),
		Name = text({ text = current, font = Style.Font.Heading, size = 32, color = Style.Text.Heading, height = 40, order = 4 }),
		Band = e(Band, { alignment = current, order = 5 }),
		Blurb = text({
			text = AlignmentConfig.BLURB[current], size = 15, color = Style.Text.Body, wrap = true,
			Size = UDim2.new(1, -40, 0, 44), order = 6,
		}),
		Where = text({ text = where, size = 15, font = Style.Font.BodyBold, color = whereColor, wrap = true,
			Size = UDim2.new(1, -40, 0, 22), order = 7 }),
		Status = text({ text = status, size = 14, color = Style.Text.Bad, height = 20, order = 8 }),
		Note = text({
			text = ("Change it in a safe zone, out of combat. Dying Neutral holds you to Lawful for %d minutes, dying Chaotic for %d."):format(
				math.ceil(AlignmentConfig.DEATH_LOCKOUT.Neutral / 60), math.ceil(AlignmentConfig.DEATH_LOCKOUT.Chaotic / 60)),
			size = 13, color = Style.Text.Muted, wrap = true, Size = UDim2.new(1, -40, 0, 36), order = 9,
		}),
	})

	local rows: { [string]: any } = {
		Layout = e("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	}
	for i, name in ipairs(AlignmentConfig.ORDER) do
		local alignment = name :: string
		local blocked: string? = nil
		if alignment ~= current then
			if alignment ~= "Lawful" and locked > 0 then
				blocked = clock(locked)
			elseif not safe then
				blocked = "Safe zone"
			end
		end
		rows[alignment] = e(ChoiceRow, {
			alignment = alignment, current = alignment == current, blocked = blocked, busy = busy, order = i,
			onChoose = function() choose(alignment) end,
		})
	end
	local right = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
		Heading = e(Parts.Heading, { text = "Choose", size = 26, height = 34 }),
		Rule = e("Frame", { Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1 }, {
			Line = e(Parts.Divider, { width = 1 }),
		}),
		Rows = e("Frame", { Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 1, -54), BackgroundTransparency = 1 }, rows),
	})

	return e(Book, { side = props.side, left = left, right = right })
end

return AlignmentPage
