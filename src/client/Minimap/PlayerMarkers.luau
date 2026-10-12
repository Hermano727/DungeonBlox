--[[
	PlayerMarkers -- your own pins on the world map (client half; the server half is
	SSS/MinimapService, remote MinimapMarkerAction). Created once by Minimap/init.client.

	On the expanded (M) map:
	  - right click empty ground   the picker: General / Mining / Fishing / Combat
	  - click or right click a pin the pin's card: Track / Stop tracking, Change type, Remove
	  - hover a pin                it grows, and a tooltip names it with its distance
	  - Delete over a pin          removes it straight away
	  - the legend (top left)      a row per type with its count; click to hide / show that type
	                               (NPCs too), Centre on me, Clear all (click twice)
	Tracking (one pin at a time, saved): the pin breathes a ring on both maps, sits on the
	map's edge with a pointer when it's out of view, and stands in the world as a beacon with
	its distance (hidden once you're there).

	Every control here is hit-tested from UserInputService, not from GuiButton events: input
	reaches us even if some other screen ever sits on top of the map (that is how the first
	picker lost its clicks: the map then drew under most of the HUD).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("MinimapConfig"))
local Keys = require(ReplicatedStorage:WaitForChild("KeybindConfig"))
local UILayers = require(ReplicatedStorage:WaitForChild("UILayers"))
local MapView = require(script.Parent:WaitForChild("MapView"))

local player = Players.LocalPlayer
local CELL = Config.CELL

local PANEL = Color3.fromRGB(14, 13, 16)
local ROW_HOVER = Color3.fromRGB(38, 34, 30)
local EDGE = Color3.fromRGB(70, 66, 60)
local TEXT = Color3.fromRGB(226, 220, 204)
local MUTED = Color3.fromRGB(150, 144, 132)
local DANGER = Color3.fromRGB(214, 96, 80)

local ROW_H = 30
local PANEL_W = 184
local Z = 40 -- panels draw above everything the map frame holds (map 1..12, hints 20..21)
local BEACON_HIDE_WITHIN = 10 -- studs: you're there
local EDGE_INSET = 14 -- px: the off-view pointer sits this far inside a view's edge

local PlayerMarkers = {}
PlayerMarkers.__index = PlayerMarkers

-------------------------------------------------------------------------------------------------
-- Small builders

local function make(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do inst[k] = v end
	inst.Parent = parent
	return inst
end

local function corner(parent, radius)
	make("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function stroke(parent, colour, thickness)
	make("UIStroke", { Color = colour, Thickness = thickness, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end

local function panel(name, parent)
	local frame = make("Frame", {
		Name = name, Size = UDim2.fromOffset(PANEL_W, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = PANEL, BackgroundTransparency = .04, BorderSizePixel = 0,
		Active = true, Visible = false, ZIndex = Z,
	}, parent)
	corner(frame, 6)
	stroke(frame, EDGE, 1)
	make("UIPadding", {
		PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6),
	}, frame)
	make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, frame)
	return frame
end

local function heading(parent, order)
	return make("TextLabel", {
		Name = "Heading", LayoutOrder = order, Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = Z + 1, Text = "",
	}, parent)
end

local function distanceText(studs)
	return ("%dm"):format(math.floor(studs + .5))
end

-------------------------------------------------------------------------------------------------

-- ctx: big (the expanded map frame), bigView, miniView, getScale(), getBounds(), isOpen(),
-- cellAt(point) -> Vector2 map cell, recentre(), setNpcsVisible(bool),
-- remote (MinimapMarkerAction)
function PlayerMarkers.new(ctx)
	local self = setmetatable({}, PlayerMarkers)
	self.ctx = ctx
	self.markers = {}        -- { { id, type, x, z } }, map cells
	self.tracked = nil       -- id
	self.hover = nil         -- pin id under the cursor
	self.selected = nil      -- pin id whose card is open
	self.hidden = {}         -- [typeId] = true: hidden on both maps
	self.npcsHidden = false
	self.buttons = {}        -- hit-tested rows: { frame, panel, onClick, base }
	self.panels = {}
	self.lastPoint = Vector2.zero
	self:_buildPicker()
	self:_buildCard()
	self:_buildLegend()
	self:_buildTooltip()
	self:_buildToast()
	self:_buildEdgePointers()
	self:_buildBeacon()
	self:_connectInput()
	return self
end

-------------------------------------------------------------------------------------------------
-- Rows (hit-tested buttons)

-- A clickable row in a panel: optional marker badge, a label, optional right-hand text.
function PlayerMarkers:_row(panelFrame, order, text, onClick, typeEntry)
	local row = make("Frame", {
		Name = "Row", LayoutOrder = order, Size = UDim2.new(1, 0, 0, ROW_H),
		BackgroundColor3 = ROW_HOVER, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = Z + 1,
	}, panelFrame)
	corner(row, 4)
	local left = 8
	if typeEntry then
		local badge = make("Frame", {
			Name = "Badge", AnchorPoint = Vector2.new(0, .5), Position = UDim2.new(0, 4, .5, 0),
			Size = UDim2.fromOffset(ROW_H - 6, ROW_H - 6), BackgroundTransparency = 1, ZIndex = Z + 1,
		}, row)
		MapView.BuildPlayerMarkerBadge(badge, typeEntry, Z + 1)
		left = ROW_H + 4
	end
	local label = make("TextLabel", {
		Name = "Label", Position = UDim2.fromOffset(left, 0), Size = UDim2.new(1, -left - 6, 1, 0),
		BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 15, TextColor3 = TEXT,
		TextXAlignment = Enum.TextXAlignment.Left, Text = text, ZIndex = Z + 2,
	}, row)
	local right = make("TextLabel", {
		Name = "Right", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 0),
		Size = UDim2.new(0, 60, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamMedium,
		TextSize = 13, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Right, Text = "", ZIndex = Z + 2,
	}, row)
	table.insert(self.buttons, { frame = row, panel = panelFrame, onClick = onClick })
	return row, label, right
end

local function inside(gui, point)
	local p, s = gui.AbsolutePosition, gui.AbsoluteSize
	return point.X >= p.X and point.X <= p.X + s.X and point.Y >= p.Y and point.Y <= p.Y + s.Y
end

function PlayerMarkers:_panelAt(point)
	for _, p in ipairs(self.panels) do
		if p.Visible and inside(p, point) then return p end
	end
	return nil
end

function PlayerMarkers:_buttonAt(point)
	for _, b in ipairs(self.buttons) do
		if b.panel.Visible and b.frame.Visible and inside(b.frame, point) then return b end
	end
	return nil
end

-- Places a panel next to a screen point, kept inside the map frame.
function PlayerMarkers:_placePanel(frame, point)
	local big = self.ctx.big
	local rel = point - big.AbsolutePosition
	local h = math.max(frame.AbsoluteSize.Y, 120)
	local x = math.clamp(rel.X + 12, 6, math.max(6, big.AbsoluteSize.X - PANEL_W - 6))
	local y = math.clamp(rel.Y + 8, 6, math.max(6, big.AbsoluteSize.Y - h - 6))
	frame.Position = UDim2.fromOffset(x, y)
end

-------------------------------------------------------------------------------------------------
-- Picker: place a pin, or change a pin's type

function PlayerMarkers:_buildPicker()
	local frame = panel("MarkerPicker", self.ctx.big)
	self.picker = frame
	table.insert(self.panels, frame)
	self.pickerTitle = heading(frame, 0)
	for order, typeEntry in ipairs(Config.PlayerMarkerTypes) do
		self:_row(frame, order, typeEntry.label, function() self:_pick(typeEntry.id) end, typeEntry)
	end
end

-- mode "place" (at cell) or "retype" (the pin id)
function PlayerMarkers:_openPicker(point, mode, arg)
	self:_closeCard()
	self.pickerMode, self.pickerArg = mode, arg
	if mode == "place" then
		self.pickerTitle.Text = ("Place marker  %d / %d"):format(#self.markers, Config.PlayerMarkerMax)
	else
		self.pickerTitle.Text = "Change type"
	end
	self.picker.Visible = true
	self:_placePanel(self.picker, point)
end

function PlayerMarkers:_closePicker()
	self.picker.Visible = false
	self.pickerMode, self.pickerArg = nil, nil
end

function PlayerMarkers:_pick(typeId)
	local mode, arg = self.pickerMode, self.pickerArg
	self:_closePicker()
	if mode == "place" then
		self:_place(typeId, arg)
	elseif mode == "retype" then
		self:_retype(arg, typeId)
	end
end

-------------------------------------------------------------------------------------------------
-- Card: one pin's options

function PlayerMarkers:_buildCard()
	local frame = panel("MarkerCard", self.ctx.big)
	self.card = frame
	table.insert(self.panels, frame)
	self.cardTitle = heading(frame, 0)
	self.cardTitle.TextColor3 = TEXT
	self.cardTitle.TextSize = 15
	self.cardSub = heading(frame, 1)
	self.cardSub.Font = Enum.Font.GothamMedium
	local _, trackLabel = self:_row(frame, 2, "Track", function()
		local id = self.selected
		self:_closeCard()
		if not id then return end
		if self.tracked == id then
			self:_setTracked(nil)
		else
			self:_setTracked(id)
		end
	end)
	self.cardTrackLabel = trackLabel
	self:_row(frame, 3, "Change type", function()
		local id = self.selected
		if id then self:_openPicker(self.lastPoint, "retype", id) end
	end)
	local _, removeLabel = self:_row(frame, 4, "Remove", function()
		local id = self.selected
		self:_closeCard()
		if id then self:_remove(id) end
	end)
	removeLabel.TextColor3 = DANGER
end

function PlayerMarkers:_openCard(id)
	local marker = self:_find(id)
	if not marker then return end
	self:_closePicker()
	self.selected = id
	local typeEntry = Config.PlayerMarkerType(marker.type)
	self.cardTitle.Text = (typeEntry and typeEntry.label or "Marker") .. " marker"
	self.cardTrackLabel.Text = self.tracked == id and "Stop tracking" or "Track"
	self:_refreshCardDistance()
	self.card.Visible = true
	local at = self.ctx.bigView:PlayerMarkerCentre(id) or self.lastPoint
	self:_placePanel(self.card, at)
end

function PlayerMarkers:_closeCard()
	self.card.Visible = false
	self.selected = nil
end

function PlayerMarkers:_refreshCardDistance()
	local marker = self.selected and self:_find(self.selected)
	local dist = marker and self:_distance(marker)
	self.cardSub.Text = dist and (distanceText(dist) .. " away") or ""
end

-------------------------------------------------------------------------------------------------
-- Legend: counts, show / hide by type, centre, clear all

function PlayerMarkers:_buildLegend()
	local frame = panel("MarkerLegend", self.ctx.big)
	frame.Position = UDim2.fromOffset(12, 12)
	frame.Visible = true
	self.legend = frame
	table.insert(self.panels, frame)
	local title = heading(frame, 0)
	title.Text = "Markers"
	self.legendRows = {}
	for order, typeEntry in ipairs(Config.PlayerMarkerTypes) do
		local row, label, right = self:_row(frame, order, typeEntry.label, function()
			self.hidden[typeEntry.id] = not self.hidden[typeEntry.id] or nil
			self:_render()
		end, typeEntry)
		self.legendRows[typeEntry.id] = { row = row, label = label, right = right }
	end
	local _, npcLabel, npcRight = self:_row(frame, 10, "NPCs", function()
		self.npcsHidden = not self.npcsHidden
		self.ctx.setNpcsVisible(not self.npcsHidden)
		self:_refreshLegend()
	end)
	self.npcLegend = { label = npcLabel, right = npcRight }
	make("Frame", {
		Name = "Divider", LayoutOrder = 20, Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = EDGE,
		BorderSizePixel = 0, ZIndex = Z + 1,
	}, frame)
	local _, _, centreRight = self:_row(frame, 21, "Centre on me", function() self.ctx.recentre() end)
	centreRight.Text = "[" .. Keys.MapRecentre.Name .. "]"
	local _, clearLabel = self:_row(frame, 22, "Clear all", function()
		if #self.markers == 0 then return end
		if self.clearArmedUntil and os.clock() < self.clearArmedUntil then
			self.clearArmedUntil = nil
			self:_clearAll()
		else
			self.clearArmedUntil = os.clock() + 3
			self:_refreshLegend()
		end
	end)
	self.clearLabel = clearLabel
	self:_refreshLegend()
end

function PlayerMarkers:_refreshLegend()
	local counts = {}
	for _, m in ipairs(self.markers) do counts[m.type] = (counts[m.type] or 0) + 1 end
	for id, entry in pairs(self.legendRows) do
		local hidden = self.hidden[id] == true
		entry.right.Text = hidden and "Hidden" or tostring(counts[id] or 0)
		entry.label.TextColor3 = hidden and MUTED or TEXT
		local badge = entry.row:FindFirstChild("Badge")
		local plate = badge and badge:FindFirstChild("Plate")
		if plate then plate.BackgroundTransparency = hidden and .6 or 0 end
	end
	self.npcLegend.right.Text = self.npcsHidden and "Hidden" or "Shown"
	self.npcLegend.label.TextColor3 = self.npcsHidden and MUTED or TEXT
	local armed = self.clearArmedUntil and os.clock() < self.clearArmedUntil
	self.clearLabel.Text = armed and ("Click again to clear %d"):format(#self.markers) or "Clear all"
	self.clearLabel.TextColor3 = #self.markers == 0 and MUTED or DANGER
end

-------------------------------------------------------------------------------------------------
-- Tooltip, toast

function PlayerMarkers:_buildTooltip()
	local tip = make("TextLabel", {
		Name = "MarkerTooltip", AnchorPoint = Vector2.new(.5, 1), Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = PANEL, BackgroundTransparency = .05,
		BorderSizePixel = 0, Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = TEXT,
		Visible = false, ZIndex = Z + 5, Text = "",
	}, self.ctx.big)
	corner(tip, 4)
	stroke(tip, EDGE, 1)
	make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, tip)
	self.tooltip = tip
end

function PlayerMarkers:_buildToast()
	local toast = make("TextLabel", {
		Name = "MarkerToast", AnchorPoint = Vector2.new(.5, 0), Position = UDim2.new(.5, 0, 0, 14),
		Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = PANEL,
		BackgroundTransparency = .05, BorderSizePixel = 0, Font = Enum.Font.GothamBold, TextSize = 15,
		TextColor3 = TEXT, Visible = false, ZIndex = Z + 6, Text = "",
	}, self.ctx.big)
	corner(toast, 5)
	stroke(toast, EDGE, 1)
	make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, toast)
	self.toast = toast
end

function PlayerMarkers:_say(text)
	self.toast.Text = text
	self.toast.Visible = true
	self.toastUntil = os.clock() + 2.5
end

-------------------------------------------------------------------------------------------------
-- The tracked pin when it's out of view: a badge on the view's edge with a pointer outward.

function PlayerMarkers:_edgePointer(view)
	local holder = make("Frame", {
		Name = "TrackedEdge", AnchorPoint = Vector2.new(.5, .5), Size = UDim2.fromOffset(22, 22),
		BackgroundTransparency = 1, Visible = false, ZIndex = 11,
	}, view.clip)
	local pointer = make("Frame", {
		Name = "Pointer", AnchorPoint = Vector2.new(.5, .5), Size = UDim2.fromOffset(9, 9),
		Rotation = 45, BorderSizePixel = 0, ZIndex = 11,
	}, holder)
	stroke(pointer, Color3.fromRGB(18, 14, 10), 1)
	return { view = view, holder = holder, pointer = pointer, type = nil }
end

function PlayerMarkers:_buildEdgePointers()
	self.edges = { self:_edgePointer(self.ctx.miniView), self:_edgePointer(self.ctx.bigView) }
end

-- centre*: the view's centre cell; scale: px per cell.
function PlayerMarkers:_updateEdge(edge, marker, centreX, centreZ, scale)
	if not marker or self.hidden[marker.type] then
		edge.holder.Visible = false
		return
	end
	if edge.type ~= marker.type then
		edge.type = marker.type
		local old = edge.holder:FindFirstChild("Plate")
		if old then old:Destroy() end
		local typeEntry = Config.PlayerMarkerType(marker.type)
		MapView.BuildPlayerMarkerBadge(edge.holder, typeEntry, 11)
		edge.pointer.BackgroundColor3 = typeEntry.ring
	end
	local size = edge.view.clip.AbsoluteSize
	local half = Vector2.new(size.X / 2 - EDGE_INSET, size.Y / 2 - EDGE_INSET)
	local offset = Vector2.new((marker.x - centreX) * scale, (marker.z - centreZ) * scale)
	if math.abs(offset.X) <= half.X and math.abs(offset.Y) <= half.Y or offset.Magnitude < 1 then
		edge.holder.Visible = false -- in view: the pin itself shows
		return
	end
	local k = math.min(half.X / math.max(math.abs(offset.X), 1e-3), half.Y / math.max(math.abs(offset.Y), 1e-3))
	local at = offset * k
	local dir = offset.Unit
	edge.holder.Position = UDim2.new(.5, at.X, .5, at.Y)
	edge.pointer.Position = UDim2.new(.5, dir.X * 15, .5, dir.Y * 15)
	edge.holder.Visible = true
end

-------------------------------------------------------------------------------------------------
-- The world beacon over the tracked pin (visible with the map closed: that's the point).

function PlayerMarkers:_buildBeacon()
	local anchor = make("Attachment", { Name = "TrackedMarkerBeacon" }, Workspace.Terrain)
	local gui = make("BillboardGui", {
		Name = "TrackedMarkerBeacon", Adornee = anchor, AlwaysOnTop = true, LightInfluence = 0,
		Size = UDim2.fromOffset(64, 62), Enabled = false, ResetOnSpawn = false,
	}, player:WaitForChild("PlayerGui"))
	local badgeHolder = make("Frame", {
		Name = "BadgeHolder", AnchorPoint = Vector2.new(.5, 0), Position = UDim2.fromScale(.5, 0),
		Size = UDim2.fromOffset(36, 36), BackgroundTransparency = 1,
	}, gui)
	local label = make("TextLabel", {
		Name = "Distance", AnchorPoint = Vector2.new(.5, 1), Position = UDim2.fromScale(.5, 1),
		Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
		TextSize = 15, TextColor3 = TEXT, TextStrokeTransparency = .3, Text = "",
	}, gui)
	self.beacon = { anchor = anchor, gui = gui, badgeHolder = badgeHolder, label = label, type = nil, groundY = nil, nextRay = 0, id = nil }
end

function PlayerMarkers:_updateBeacon(marker, root)
	local b = self.beacon
	if not marker or not root then
		b.gui.Enabled = false
		return
	end
	if b.id ~= marker.id or b.type ~= marker.type then
		if b.id ~= marker.id then b.groundY = nil; b.nextRay = 0 end
		b.id, b.type = marker.id, marker.type
		b.badgeHolder:ClearAllChildren()
		MapView.BuildPlayerMarkerBadge(b.badgeHolder, Config.PlayerMarkerType(marker.type), 1)
	end
	local x, z = marker.x * CELL, marker.z * CELL
	local now = os.clock()
	if not b.groundY and now >= b.nextRay then
		b.nextRay = now + 2 -- the spot may not have streamed in yet; keep asking
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = { player.Character }
		params.FilterType = Enum.RaycastFilterType.Exclude
		local hit = Workspace:Raycast(Vector3.new(x, 1500, z), Vector3.new(0, -3000, 0), params)
		if hit then b.groundY = hit.Position.Y end
	end
	local y = (b.groundY or root.Position.Y) + 6
	b.anchor.WorldPosition = Vector3.new(x, y, z)
	local flat = Vector3.new(x - root.Position.X, 0, z - root.Position.Z).Magnitude
	b.gui.Enabled = flat > BEACON_HIDE_WITHIN
	b.label.Text = distanceText(flat)
end

-------------------------------------------------------------------------------------------------
-- Data + server

function PlayerMarkers:_find(id)
	for i, m in ipairs(self.markers) do
		if m.id == id then return m, i end
	end
	return nil
end

function PlayerMarkers:_distance(marker)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	return Vector3.new(marker.x * CELL - root.Position.X, 0, marker.z * CELL - root.Position.Z).Magnitude
end

function PlayerMarkers:_render()
	local shown = {}
	for _, m in ipairs(self.markers) do
		if not self.hidden[m.type] then table.insert(shown, m) end
	end
	self.ctx.miniView:SetPlayerMarkers(shown)
	self.ctx.bigView:SetPlayerMarkers(shown)
	self:_refreshLegend()
end

local function invoke(remote, ...)
	local ok, success, result = pcall(remote.InvokeServer, remote, ...)
	return ok and success == true, result
end

function PlayerMarkers:_place(typeId, cell)
	if not cell or self.placing then return end
	if #self.markers >= Config.PlayerMarkerMax then
		self:_say(("Marker limit reached (%d). Remove one first."):format(Config.PlayerMarkerMax))
		return
	end
	self.placing = true
	task.spawn(function()
		local ok, result = invoke(self.ctx.remote, "add", typeId, cell.X, cell.Y)
		self.placing = false
		if ok and type(result) == "table" then
			table.insert(self.markers, result)
			self:_render()
		elseif result == "full" then
			self:_say(("Marker limit reached (%d). Remove one first."):format(Config.PlayerMarkerMax))
		else
			self:_say("Couldn't place the marker.")
		end
	end)
end

-- Optimistic: gone at once, back if the server says no.
function PlayerMarkers:_remove(id)
	local marker, index = self:_find(id)
	if not marker then return end
	table.remove(self.markers, index)
	local wasTracked = self.tracked == id
	if wasTracked then self.tracked = nil end
	if self.hover == id then self.hover = nil end
	self:_render()
	task.spawn(function()
		local ok, err = invoke(self.ctx.remote, "remove", id)
		if not ok and err ~= "not_found" then
			table.insert(self.markers, math.min(index, #self.markers + 1), marker)
			if wasTracked then self.tracked = id end
			self:_render()
			self:_say("Couldn't remove the marker.")
		end
	end)
end

function PlayerMarkers:_retype(id, typeId)
	local marker = self:_find(id)
	if not marker or marker.type == typeId then return end
	local old = marker.type
	marker.type = typeId
	self:_render()
	task.spawn(function()
		local ok = invoke(self.ctx.remote, "retype", id, typeId)
		if not ok then
			marker.type = old
			self:_render()
			self:_say("Couldn't change the marker.")
		end
	end)
end

function PlayerMarkers:_setTracked(id)
	local old = self.tracked
	self.tracked = id
	task.spawn(function()
		local ok = invoke(self.ctx.remote, "track", id)
		if not ok then self.tracked = old end
	end)
end

function PlayerMarkers:_clearAll()
	local old, oldTracked = self.markers, self.tracked
	self.markers, self.tracked, self.hover = {}, nil, nil
	self:_render()
	task.spawn(function()
		local ok = invoke(self.ctx.remote, "clear")
		if not ok then
			self.markers, self.tracked = old, oldTracked
			self:_render()
			self:_say("Couldn't clear the markers.")
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- Public

-- From MinimapStateRequest: the saved pins and the tracked one.
function PlayerMarkers:Load(list, trackedId)
	local clean = {}
	for _, m in ipairs(type(list) == "table" and list or {}) do
		if type(m) == "table" and type(m.id) == "string" and Config.PlayerMarkerType(m.type)
			and type(m.x) == "number" and type(m.z) == "number" then
			table.insert(clean, { id = m.id, type = m.type, x = m.x, z = m.z })
		end
	end
	self.markers = clean
	self.tracked = type(trackedId) == "string" and self:_find(trackedId) and trackedId or nil
	self:_render()
end

-- The map closed: drop the transient bits.
function PlayerMarkers:OnClosed()
	self:_closePicker()
	self:_closeCard()
	self.hover = nil
	self.tooltip.Visible = false
	self.clearArmedUntil = nil
end

-- Esc: closes a picker / card first. Returns true if it did.
function PlayerMarkers:HandleEscape()
	if self.picker.Visible then self:_closePicker() return true end
	if self.card.Visible then self:_closeCard() return true end
	return false
end

-- Is this point on one of our panels? (the controller doesn't start a drag there)
function PlayerMarkers:Covers(point)
	return self:_panelAt(point) ~= nil
end

-- Every frame (the controller's RenderStepped).
function PlayerMarkers:Update(miniCentreX, miniCentreZ, bigCentreX, bigCentreZ)
	local ctx = self.ctx
	local now = os.clock()
	local pulse = (math.sin(now * 4) + 1) / 2
	local tracked = self.tracked and self:_find(self.tracked)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")

	ctx.miniView:StylePlayerMarkers(nil, nil, self.tracked, pulse)
	if miniCentreX then
		self:_updateEdge(self.edges[1], tracked, miniCentreX, miniCentreZ, Config.MiniScale)
	else
		self.edges[1].holder.Visible = false
	end
	self:_updateBeacon(miniCentreX and tracked and not self.hidden[tracked.type] and tracked or nil, root)

	if ctx.isOpen() and bigCentreX then
		ctx.bigView:StylePlayerMarkers(self.hover, self.selected, self.tracked, pulse)
		self:_updateEdge(self.edges[2], tracked, bigCentreX, bigCentreZ, ctx.getScale())
		local hovered = self.hover and self:_find(self.hover)
		if hovered and not self.card.Visible and not self.picker.Visible then
			local at = ctx.bigView:PlayerMarkerCentre(hovered.id)
			local typeEntry = Config.PlayerMarkerType(hovered.type)
			local dist = self:_distance(hovered)
			if at then
				local rel = at - ctx.big.AbsolutePosition
				self.tooltip.Position = UDim2.fromOffset(rel.X, rel.Y - 18)
				self.tooltip.Text = (typeEntry and typeEntry.label or "Marker") .. (dist and ("   " .. distanceText(dist)) or "")
				self.tooltip.Visible = true
			end
		else
			self.tooltip.Visible = false
		end
		if self.card.Visible then self:_refreshCardDistance() end
		if self.clearArmedUntil and now >= self.clearArmedUntil then
			self.clearArmedUntil = nil
			self:_refreshLegend()
		end
	else
		self.edges[2].holder.Visible = false
	end
	if self.toastUntil and now >= self.toastUntil then
		self.toastUntil = nil
		self.toast.Visible = false
	end
end

-------------------------------------------------------------------------------------------------
-- Input

function PlayerMarkers:_hoverAt(point)
	for _, b in ipairs(self.buttons) do
		b.frame.BackgroundTransparency = 1
	end
	local button = self:_buttonAt(point)
	if button then
		button.frame.BackgroundTransparency = 0
		self.hover = nil
		return
	end
	if self:_panelAt(point) or not inside(self.ctx.bigView.clip, point) then
		self.hover = nil
		return
	end
	self.hover = self.ctx.bigView:PlayerMarkerAt(point)
end

function PlayerMarkers:_connectInput()
	local ctx = self.ctx
	UserInputService.InputChanged:Connect(function(input)
		if not ctx.isOpen() or input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
		local point = Vector2.new(input.Position.X, input.Position.Y)
		self.lastPoint = point
		self:_hoverAt(point)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if not ctx.isOpen() then return end
		local kind = input.UserInputType
		if kind == Enum.UserInputType.Keyboard then
			if processed then return end
			if input.KeyCode == Keys.MapDeleteMarker then
				local id = self.hover or self.selected
				if id then
					self:_closeCard()
					self:_remove(id)
				end
			end
			return
		end
		if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.MouseButton2 then return end
		local point = Vector2.new(input.Position.X, input.Position.Y)
		self.lastPoint = point

		local button = self:_buttonAt(point)
		if button then
			if kind == Enum.UserInputType.MouseButton1 then button.onClick() end
			return
		end
		if self:_panelAt(point) then return end
		if not inside(ctx.bigView.clip, point) then return end

		local pinId = ctx.bigView:PlayerMarkerAt(point)
		if pinId then
			self:_openCard(pinId) -- left or right click: the pin's options
			return
		end
		self:_closeCard()
		if kind == Enum.UserInputType.MouseButton2 then
			local cell = ctx.cellAt(point)
			local bounds = ctx.getBounds()
			if cell and bounds and Config.CellInBounds(bounds, math.floor(cell.X), math.floor(cell.Y)) then
				self:_openPicker(point, "place", cell)
			else
				self:_closePicker()
			end
		else
			self:_closePicker()
		end
	end)
end

-- The layer the expanded map's ScreenGui uses (the controller reads it).
PlayerMarkers.MAP_DISPLAY_ORDER = UILayers.WORLD_MAP

return PlayerMarkers
