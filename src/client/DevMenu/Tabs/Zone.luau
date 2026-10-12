--[[
	Zone -- draws a zone polygon: name, alignment (Lawful / Wilderness / Chaotic), banned player
	alignments (entry flash), optional elite-mob zone and its mob, optional music id.

	Drawing: Draw Zone, then E or left-click places a corner (at least ZoneConfig.MIN_POLYGON_POINTS,
	at most MAX_POLYGON_POINTS); after the first corner every corner snaps to its height. A live edge
	follows the aim from the last corner. Aiming within SNAP_RADIUS of a corner (3+ placed) turns it
	green: placing there closes the shape and saves it (snapping onto corner k saves corners k..last).
	Enter / Finish Zone saves, Backspace undoes, Clear removes all, Esc cancels. Drawing survives
	closing or hiding the window (KeepPlacingWhenClosed), so you can fly around while you draw.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Keys = require(ReplicatedStorage:WaitForChild("KeybindConfig"))
local ZoneConfig = require(ReplicatedStorage:WaitForChild("ZoneConfig"))
local Lists = require(script.Parent.Parent:WaitForChild("Lists"))

local Tab = { key = "Zone", label = "Zone", group = "World", places = true, KeepPlacingWhenClosed = true,
	listType = "Zone", listTitle = "MANAGED ZONES" }

local YELLOW = ZoneConfig.DEV_ZONE_COLOR
local SNAP_GREEN = Color3.fromRGB(80, 255, 120)
local SNAP_RADIUS = math.max(3, ZoneConfig.DEV_ZONE_CORNER_SIZE * 2.5)
local EDGE = ZoneConfig.DEV_ZONE_EDGE_THICKNESS
local CORNER = ZoneConfig.DEV_ZONE_CORNER_SIZE

local settings = {
	alignment = "Lawful",
	banned = { Lawful = false, Neutral = false, Chaotic = false },
	isElite = false,
	eliteMobIdx = 1,
}
local points = {}
local ui = {}

local preview = Instance.new("Folder")
preview.Name = "DevPlacerZonePreview"

local rubberBand = Instance.new("Part")
rubberBand.Name = "DevPlacerZoneRubberBand"
rubberBand.Anchored = true
rubberBand.CanCollide = false
rubberBand.CanQuery = false
rubberBand.CanTouch = false
rubberBand.CastShadow = false
rubberBand.Material = Enum.Material.Neon
rubberBand.Transparency = 0.5

local function neonPart(shape, size, cframe, color, transparency)
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.CFrame = cframe
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = transparency
	p.Parent = preview
	return p
end

local function edge(a, b, y)
	local p1, p2 = Vector3.new(a.X, y + 0.2, a.Z), Vector3.new(b.X, y + 0.2, b.Z)
	local length = (p2 - p1).Magnitude
	if length < 0.05 then return end
	neonPart(Enum.PartType.Block, Vector3.new(length, EDGE, EDGE),
		CFrame.new((p1 + p2) * 0.5, p2) * CFrame.Angles(0, math.rad(90), 0), YELLOW, 0.3)
end

local function redraw(ctx)
	preview:ClearAllChildren()
	local n = #points
	if ui.count then ui.count.Text = "Corners: " .. n end
	ctx.refreshHud()
	if n == 0 then return end
	local y = points[1].Y
	for i, p in ipairs(points) do
		neonPart(Enum.PartType.Ball, Vector3.new(CORNER, CORNER, CORNER), CFrame.new(p.X, y + 0.3, p.Z), YELLOW, 0.2)
		if i > 1 then edge(points[i - 1], p, y) end
	end
	if n >= 3 then edge(points[n], points[1], y) end
end

local function clearDraw(ctx)
	table.clear(points)
	redraw(ctx)
end

-- The existing corner the aim snaps to, or nil. Only corners that still leave a valid closed loop
-- (that corner through the last one) are snappable.
local function snapIndex(pos)
	local n = #points
	if n < ZoneConfig.MIN_POLYGON_POINTS then return nil end
	local best, bestDist = nil, SNAP_RADIUS
	for i, p in ipairs(points) do
		if n - i + 1 >= ZoneConfig.MIN_POLYGON_POINTS then
			local d = Vector2.new(p.X - pos.X, p.Z - pos.Z).Magnitude
			if d < bestDist then best, bestDist = i, d end
		end
	end
	return best
end

local function aim(ctx)
	local pos = ctx.Placement.Aim()
	if #points > 0 then
		pos = Vector3.new(pos.X, points[1].Y, pos.Z)
	end
	return pos
end

-- loop: optional corner list (the snapped loop); defaults to every drawn corner.
local function finish(ctx, loop)
	loop = loop or points
	if #loop < ZoneConfig.MIN_POLYGON_POINTS then
		ctx.status("Need at least " .. ZoneConfig.MIN_POLYGON_POINTS .. " corners", true)
		return
	end
	local rfPlaceZone = ctx.GE and ctx.GE:FindFirstChild("DevPlaceZone")
	if not rfPlaceZone then ctx.status("DevPlaceZone remote missing", true) return end
	local banned = {}
	for name, on in pairs(settings.banned) do
		if on then table.insert(banned, name) end
	end
	local pts = {}
	for _, p in ipairs(loop) do
		table.insert(pts, { x = p.X, z = p.Z })
	end
	ctx.status("Saving zone...")
	local ok, result = pcall(function()
		return rfPlaceZone:InvokeServer({
			Name = ui.name.Text,
			Alignment = settings.alignment,
			BannedAlignments = banned,
			IsEliteZone = settings.isElite,
			EliteMobId = Lists.MOB_IDS[settings.eliteMobIdx],
			Points = pts,
			Position = Vector3.new(0, loop[1].Y, 0),
			MusicId = ui.music.Text,
		})
	end)
	if not ok or type(result) ~= "table" or not result.ok then
		local err = (type(result) == "table" and result.error) or tostring(result)
		ctx.status("Zone save failed: " .. tostring(err), true)
		warn("[DevMenu] zone save failed: " .. tostring(err))
		return
	end
	clearDraw(ctx)
	ctx.setPlacing(false)
	ctx.panel.setExplore(false)
	-- Bring the window back so the saved outline (ZoneDevVisuals) and its row are visible.
	if not ctx.panel.isOpen() then ctx.panel.setOpen(true) end
	ctx.hudToast(6)
	ctx.status("Zone saved: " .. ((result.zone and result.zone.name) or "?") .. " (" .. #pts .. " corners)")
	task.delay(0.3, ctx.refreshList)
end

local function addCorner(ctx)
	local pos = aim(ctx)
	local snapped = snapIndex(pos)
	if snapped then
		-- Placing onto an existing corner closes the shape there; corners before it are dropped.
		local loop = {}
		for i = snapped, #points do table.insert(loop, points[i]) end
		ctx.status(snapped > 1 and ("Closed at corner " .. snapped .. ", skipping " .. (snapped - 1) .. " earlier corner(s). Saving...")
			or "Shape closed. Saving...")
		finish(ctx, loop)
		return
	end
	if #points >= ZoneConfig.MAX_POLYGON_POINTS then
		ctx.status("Max corners (" .. ZoneConfig.MAX_POLYGON_POINTS .. ")", true)
		return
	end
	table.insert(points, pos)
	redraw(ctx)
	ctx.status(#points >= ZoneConfig.MIN_POLYGON_POINTS and ("Corner " .. #points .. " placed. Aim at a corner to close, or Enter to finish")
		or ("Corner " .. #points .. " placed"))
end

---------------------------------------------------------------- the section

local function tint(button, name, active)
	local c = ZoneConfig.ALIGNMENT_COLORS[name]
	button.BackgroundColor3 = active and c or Color3.fromRGB(50, 40, 34)
	button.TextColor3 = active and Color3.new(0, 0, 0) or c
end

function Tab.Build(ctx)
	local Ui, lbl, mkB, mkI = ctx.Ui, ctx.lbl, ctx.mkB, ctx.mkI
	local W = ctx.w
	local muted = Ui.Color.Muted
	local sec = Ui.section(ctx, "ZoneSection", true)

	lbl(sec, "ZONE NAME", 12, 2, 120, 16, 12, ctx.acc, true)
	ui.name = mkI(sec, "e.g. Stormhaven", 12, 20, math.min(W - 24, 460), 30, "")
	lbl(sec, "Draw corners (min 3). Place a corner on top of an existing one to close and save.", 12, 56, W - 24, 18, 13, muted)
	lbl(sec, "E / Click = corner   Enter = finish   Backspace = undo   RMB = look   F = fly", 12, 74, W - 24, 18, 13, muted)

	lbl(sec, "ALIGNMENT", 12, 102, 120, 16, 12, ctx.acc, true)
	local align = {
		Lawful = mkB(sec, "LAWFUL", 12, 120, 90, 28),
		Neutral = mkB(sec, ZoneConfig.DisplayAlignment("Neutral"):upper(), 108, 120, 120, 28),
		Chaotic = mkB(sec, "CHAOTIC", 234, 120, 90, 28),
	}
	lbl(sec, "BANNED PLAYER ALIGNMENTS (entry flash)", 12, 158, W - 24, 16, 12, ctx.acc, true)
	local ban = {
		Lawful = mkB(sec, "Lawful", 12, 176, 90, 28),
		Neutral = mkB(sec, "Neutral", 108, 176, 90, 28),
		Chaotic = mkB(sec, "Chaotic", 204, 176, 90, 28),
	}
	local function paintAlign()
		for name, b in pairs(align) do tint(b, name, settings.alignment == name) end
		for name, b in pairs(ban) do tint(b, name, settings.banned[name] == true) end
	end
	for name, b in pairs(align) do
		b.Activated:Connect(function() settings.alignment = name paintAlign() end)
	end
	for name, b in pairs(ban) do
		b.Activated:Connect(function() settings.banned[name] = not settings.banned[name] paintAlign() end)
	end
	paintAlign()

	lbl(sec, "ELITE MOB ZONE", 12, 216, 160, 16, 12, ctx.acc, true)
	local eliteToggle = mkB(sec, "OFF", 180, 212, 60, 26)
	local elitePrev = mkB(sec, "<", 12, 242, 30, 30)
	local eliteNext = mkB(sec, ">", math.min(W - 42, 430), 242, 30, 30)
	local eliteDisp = lbl(sec, "", 48, 242, math.min(W - 96, 376), 30, 14, nil, false, Enum.TextXAlignment.Center)
	local function paintElite()
		local on = settings.isElite
		eliteToggle.Text = on and "ON" or "OFF"
		eliteToggle.BackgroundColor3 = on and Ui.Color.Good or Ui.Color.Bad
		eliteDisp.Text = Lists.MOB_IDS[settings.eliteMobIdx] or "-"
		eliteDisp.TextColor3 = on and Ui.Color.Text or muted
		elitePrev.TextColor3 = eliteDisp.TextColor3
		eliteNext.TextColor3 = eliteDisp.TextColor3
	end
	eliteToggle.Activated:Connect(function() settings.isElite = not settings.isElite paintElite() end)
	local function stepElite(delta)
		if not settings.isElite then return end
		settings.eliteMobIdx = Lists.step(settings.eliteMobIdx, delta, #Lists.MOB_IDS)
		paintElite()
	end
	elitePrev.Activated:Connect(function() stepElite(-1) end)
	eliteNext.Activated:Connect(function() stepElite(1) end)
	paintElite()

	lbl(sec, "MUSIC ID (optional, blank = none)", 12, 284, W - 24, 16, 12, ctx.acc, true)
	ui.music = mkI(sec, "rbxassetid://... or bare number", 12, 302, math.min(W - 24, 460), 30, "")

	local finishBtn = mkB(sec, "Finish Zone", 12, 346, 110, 30, Ui.Color.Good)
	local clearBtn = mkB(sec, "Clear", 128, 346, 70, 30, Ui.Color.Bad)
	local flyBtn = mkB(sec, "Fly: OFF", 204, 346, 100, 30)
	local hideBtn = mkB(sec, "Hide Panel", 310, 346, 110, 30, Color3.fromRGB(50, 70, 110))
	ui.count = lbl(sec, "Corners: 0", 12, 384, W - 24, 20, 13, Ui.Color.Status)

	finishBtn.Activated:Connect(function() finish(ctx) end)
	clearBtn.Activated:Connect(function() clearDraw(ctx) ctx.status("Cleared corners") end)
	flyBtn.Activated:Connect(function() ctx.fly.set(not ctx.fly.enabled()) end)
	ctx.fly.onChanged(function(on)
		flyBtn.Text = on and "Fly: ON" or "Fly: OFF"
		flyBtn.BackgroundColor3 = on and Ui.Color.Good or Ui.Color.Plate
	end)
	hideBtn.Activated:Connect(function()
		if not (ctx.placing() or ctx.fly.enabled()) then
			ctx.status("Start drawing or turn on Fly first", true)
			return
		end
		ctx.panel.setExplore(not ctx.panel.isExplore())
	end)

	ctx.Placement.IgnoreForAim(preview)
	return sec
end

---------------------------------------------------------------- placing hooks

function Tab.ActionLabel(ctx)
	if ctx.placing() then
		return "Drawing... (E or click)", Color3.fromRGB(140, 110, 20)
	end
	return "Draw Zone", ctx.Ui.Color.Good
end

function Tab.SetupGhost(ctx)
	local ghost = ctx.Placement.ghost
	ghost.Shape = Enum.PartType.Ball
	ghost.Color = YELLOW
	ghost.Transparency = 0.2
	ghost.Size = Vector3.new(CORNER, CORNER, CORNER)
end

function Tab.OnPlacingChanged(ctx, placing)
	if placing then
		preview.Parent = Workspace
	else
		clearDraw(ctx)
		preview.Parent = nil
		rubberBand.Parent = nil
	end
end

function Tab.OnAim(ctx, pos)
	pos = #points > 0 and Vector3.new(pos.X, points[1].Y, pos.Z) or pos
	local ghost = ctx.Placement.ghost
	local snapped = snapIndex(pos)
	local target = pos
	if snapped then
		target = Vector3.new(points[snapped].X, pos.Y, points[snapped].Z)
		ghost.Color = SNAP_GREEN
		ghost.Size = Vector3.new(CORNER * 2, CORNER * 2, CORNER * 2)
	else
		ghost.Color = YELLOW
		ghost.Size = Vector3.new(CORNER, CORNER, CORNER)
	end
	ghost.CFrame = CFrame.new(target.X, target.Y + 0.3, target.Z)

	local n = #points
	if n == 0 then rubberBand.Parent = nil return end
	local last = points[n]
	local p1 = Vector3.new(last.X, last.Y + 0.2, last.Z)
	local p2 = Vector3.new(target.X, last.Y + 0.2, target.Z)
	local length = (p2 - p1).Magnitude
	if length < 0.05 then rubberBand.Parent = nil return end
	rubberBand.Color = snapped and SNAP_GREEN or YELLOW
	rubberBand.Size = Vector3.new(length, EDGE, EDGE)
	rubberBand.CFrame = CFrame.new((p1 + p2) * 0.5, p2) * CFrame.Angles(0, math.rad(90), 0)
	rubberBand.Parent = Workspace
end

function Tab.OnWorldClick(ctx)
	addCorner(ctx)
end

function Tab.OnKey(ctx, keyCode)
	if keyCode == Keys.DevPlaceCorner then
		addCorner(ctx)
		return true
	elseif keyCode == Keys.DevPlaceConfirm then
		finish(ctx)
		return true
	elseif keyCode == Keys.DevPlaceDelete then
		if #points > 0 then
			table.remove(points)
			redraw(ctx)
			ctx.status("Removed corner (" .. #points .. " left)")
		end
		return true
	end
	return false
end

function Tab.HudLines()
	local n = #points
	return "ZONE DRAW  |  " .. n .. " corner" .. (n == 1 and "" or "s"),
		"E / Click = place corner    Aim at an existing corner (turns green) + E / Click = close and save",
		"Enter = finish    Backspace = undo    Esc = cancel"
end

return Tab
