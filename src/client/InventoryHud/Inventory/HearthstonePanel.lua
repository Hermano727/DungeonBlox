--!strict
--  HearthstonePanel -- the Tab menu's Hearthstone destination (rebuilt 2026-10-01 in the
--  Journal's look: Journal/Book, Parts, Style; no new art).
--
--    left   your hearthstone: the carved medallion, where it's bound, ready / resting (a bar
--           filling back up over HearthstoneConfig.COOLDOWN), and "Return to <town>"
--    right  Locations: every waystone, Bound / Owned (Bind) / sold by the Innkeeper
--
--  Server side is unchanged (SSS/HearthstoneService via ProfileBootstrap's remotes):
--    HearthstoneSync      the location catalog (fetched once, cached for the session)
--    HearthstoneTeleport  -> ok, cooldownUntil | false, reason
--    HearthstoneSwap(id)  -> ok | false, reason
--  State comes from the profile snapshot (profile.hearthstone: active, unlocked, cooldownUntil);
--  after an action it calls DungeonMenuNet.requestSync() (the push can race, see CLAUDE.md).
--  A successful teleport closes the Tab menu (InteractionLock.CloseMenu).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local HearthstoneConfig = require(ReplicatedStorage:WaitForChild("HearthstoneConfig"))
local HearthstoneIcons = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Icons"):WaitForChild("Hearthstones"):WaitForChild("HearthstoneIcons"))
local InteractionLock = require(ReplicatedStorage:WaitForChild("InteractionLock"))
local InventoryData = require(script.Parent:WaitForChild("InventoryData"))
local DungeonMenuNet = require(script.Parent.Parent.Parent:WaitForChild("DungeonMenuNet"))
local Journal = script.Parent:WaitForChild("Journal")
local Style = require(Journal:WaitForChild("Style"))
local Parts = require(Journal:WaitForChild("Parts"))
local Book = require(Journal:WaitForChild("Book"))

local e = React.createElement
local text, list = Parts.Text, Parts.List

local ROW_H = 64
local LOCATIONS_HELP = "Buy new locations from the Innkeeper in any town. Bind one to choose where your hearthstone takes you."

local REASONS = {
	cooldown = "Your hearthstone is still resting.",
	no_character = "You need to be standing somewhere first.",
	invalid_location = "That place can't be reached right now.",
	not_owned = "You don't own that location.",
	throttled = "Too fast. Wait a moment.",
}

local function clock(secs: number): string
	secs = math.max(0, math.floor(secs))
	return ("%d:%02d"):format(math.floor(secs / 60), secs % 60)
end

-- The catalog only changes when a dev adds a location, so one fetch per session is enough.
local catalogCache: { any }? = nil
local function useCatalog(): { any }
	local catalog, setCatalog = React.useState(catalogCache or HearthstoneConfig.SEED_LOCATIONS)
	React.useEffect(function()
		if catalogCache then return end
		local alive = true
		task.spawn(function()
			local remote = ReplicatedStorage:WaitForChild("HearthstoneSync", 10)
			if not remote then return end
			local ok, result = pcall(function() return (remote :: RemoteFunction):InvokeServer() end)
			if ok and type(result) == "table" and #result > 0 then
				catalogCache = result
				if alive then setCatalog(result) end
			end
		end)
		return function() alive = false end
	end, {})
	return catalog
end

-- Re-renders every second while mounted (the cooldown countdown).
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

local function invoke(name: string, ...: any): (boolean, any)
	local remote = ReplicatedStorage:FindFirstChild(name)
	if not remote then return false, "unavailable" end
	local args = table.pack(...)
	local ok, a, b = pcall(function() return (remote :: RemoteFunction):InvokeServer(table.unpack(args, 1, args.n)) end)
	if not ok then return false, "unavailable" end
	return a == true, b
end

local function iconFor(loc: any): string
	local icon = loc.icon or (HearthstoneIcons :: any)[loc.id]
	if type(icon) == "string" and icon ~= "" then return icon end
	local glyph = Style.Art("nav_glyph_hearthstone")
	return glyph and glyph.Image or ""
end

local function LocationRow(props: { loc: any, bound: boolean, owned: boolean, order: number, onBind: () -> () })
	local loc = props.loc
	local sub, subColor
	if props.bound then
		sub, subColor = "Bound here", Style.Text.Good
	elseif props.owned then
		sub, subColor = "Owned", Style.Text.Body
	else
		local cost = tonumber(loc.cost) or 0
		sub = cost > 0 and ("Sold by the Innkeeper, %d coins"):format(cost) or "Sold by the Innkeeper"
		subColor = Style.Text.Muted
	end
	return e("Frame", { LayoutOrder = props.order, Size = UDim2.new(1, 0, 0, ROW_H), BackgroundTransparency = 1 }, {
		Icon = e(Parts.Medallion, {
			image = iconFor(loc), size = 54, lit = props.bound, dim = not props.owned, imageScale = 0.6,
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
		}),
		Name = text({
			text = loc.name or loc.id, font = Style.Font.Heading, size = 18,
			color = props.owned and Style.Text.Heading or Style.Text.Muted,
			align = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(66, 10), Size = UDim2.new(1, -170, 0, 24),
		}),
		Sub = text({
			text = sub, size = 14, color = subColor, truncate = true,
			align = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(66, 34), Size = UDim2.new(1, -170, 0, 20),
		}),
		Bind = (props.owned and not props.bound) and e(Parts.ChromeButton, {
			text = "Bind", art = "chip", artSelected = "chip_selected",
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(92, 34),
			textSize = 15, onClick = props.onBind,
		}) or nil,
		Rule = e("Frame", {
			AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Style.Text.Muted, BackgroundTransparency = 0.75, BorderSizePixel = 0,
		}),
	})
end

local function HearthstonePanel()
	local snapshot = InventoryData.useSnapshot()
	local catalog = useCatalog()
	local now = useNow()
	local status, setStatus = React.useState("")
	local busy, setBusy = React.useState(false)

	local hs = snapshot and snapshot.profile and snapshot.profile.hearthstone or {}
	local active = type(hs.active) == "string" and hs.active or "oakhaven"
	local owned: { [string]: boolean } = {}
	for _, seed in ipairs(HearthstoneConfig.SEED_LOCATIONS) do owned[seed.id] = true end
	for _, id in ipairs(type(hs.unlocked) == "table" and hs.unlocked or {}) do owned[id] = true end

	local byId: { [string]: any } = {}
	for _, loc in ipairs(catalog) do byId[loc.id] = loc end
	local boundLoc = byId[active] or { id = active, name = active }
	local remaining = math.max(0, (tonumber(hs.cooldownUntil) or 0) - now)
	local ready = remaining <= 0

	local function teleport()
		if busy or not ready then return end
		setBusy(true)
		local ok, reason = invoke("HearthstoneTeleport")
		setBusy(false)
		DungeonMenuNet.requestSync()
		if ok then
			setStatus("")
			InteractionLock.CloseMenu()
		else
			setStatus(REASONS[reason] or "Couldn't travel.")
		end
	end

	local function bind(id: string)
		local ok, reason = invoke("HearthstoneSwap", id)
		DungeonMenuNet.requestSync()
		setStatus(ok and ("Bound to " .. ((byId[id] and byId[id].name) or id) .. ".") or (REASONS[reason] or "Couldn't bind there."))
	end

	-- Left page: your hearthstone.
	local left = list(10, {
		Heading = e(Parts.Heading, { text = "Hearthstone", size = 26, order = 1, height = 34 }),
		Stone = e(Parts.Medallion, {
			image = (Style.Art("nav_glyph_hearthstone") or { Image = "" }).Image,
			size = 130, lit = ready, imageScale = 0.5, order = 2,
		}),
		BoundLabel = text({ text = "Bound to", size = 15, color = Style.Text.Muted, height = 18, order = 3 }),
		BoundName = text({ text = boundLoc.name or active, font = Style.Font.Heading, size = 30, color = Style.Text.Heading, height = 38, order = 4 }),
		State = e("Frame", { LayoutOrder = 5, Size = UDim2.new(1, -60, 0, 44), BackgroundTransparency = 1 }, {
			Label = text({
				text = ready and "Ready" or ("Resting, ready in " .. clock(remaining)),
				size = 16, font = Style.Font.BodyBold, color = ready and Style.Text.Good or Style.Text.Body, height = 22,
			}),
			Bar = e(Parts.BarTrough, {
				fill = ready and 1 or (1 - remaining / math.max(1, HearthstoneConfig.COOLDOWN)),
				color = ready and Style.Split.Overworld or Style.Split.Dungeon,
				Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 12),
			}),
		}),
		Go = e(Parts.ChromeButton, {
			text = "Return to " .. (boundLoc.name or active),
			art = "chip", artSelected = "chip_selected", selected = ready,
			disabled = not ready or busy,
			Size = UDim2.fromOffset(280, 46), LayoutOrder = 6, textSize = 17,
			onClick = teleport,
		}),
		Status = text({ text = status, size = 14, color = Style.Text.Bad, height = 20, order = 7 }),
		Note = text({
			text = ("Takes you back to the town it's bound to, then rests for %d minutes."):format(math.floor(HearthstoneConfig.COOLDOWN / 60)),
			size = 13, color = Style.Text.Muted, wrap = true, height = 36, order = 8,
		}),
	})

	-- Right page: every location.
	local rows: { [string]: any } = {
		Layout = e("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
	}
	local ordered = table.clone(catalog)
	table.sort(ordered, function(a, b)
		local ao, bo = owned[a.id] and 0 or 1, owned[b.id] and 0 or 1
		if ao ~= bo then return ao < bo end
		return (a.name or a.id) < (b.name or b.id)
	end)
	for i, loc in ipairs(ordered) do
		rows["loc_" .. loc.id] = e(LocationRow, {
			loc = loc, bound = loc.id == active, owned = owned[loc.id] == true, order = i,
			onBind = function() bind(loc.id) end,
		})
	end
	local right = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
		Heading = e(Parts.Heading, { text = "Locations", size = 26, height = 34 }),
		Help = e(Parts.HelpIcon, { text = LOCATIONS_HELP, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 6) }),
		Rule = e("Frame", { Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1 }, {
			Line = e(Parts.Divider, { width = 1 }),
		}),
		List = e("ScrollingFrame", {
			Position = UDim2.fromOffset(0, 50),
			Size = UDim2.new(1, 0, 1, -50),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollBarThickness = 4,
			ScrollBarImageColor3 = Style.Text.Muted,
		}, rows),
	})

	return e(Book, { left = left, right = right })
end

return HearthstonePanel
