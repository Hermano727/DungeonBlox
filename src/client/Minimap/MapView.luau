--[[
	MapView -- one rendering of the world map inside a frame (the corner minimap and the expanded
	map are two MapViews over the same chunk images; see Minimap/init.client).

		local view = MapView.new(parentFrame, { labelScale = 5, labelMin = 10, labelMax = 16, cornerRadius = 6 })
		view:SetBounds(bounds)                    -- MinimapConfig.CellBounds
		view:SetChunkImage(key, content)          -- Content.fromObject(EditableImage)
		view:SetZones(zones, discovered, labelAt) -- discovered outlines + names
		view:SetScale(pixelsPerCell)
		view:Update(centreCellX, centreCellZ, playerCellX, playerCellZ, lookVector)
		view:Glow(zoneId)                         -- the "region discovered" pulse
		view:SetNpcMarkers(list)                  -- NPC crests (RS/NpcMapMarkers), see below
		view:SetPlayerMarkers(list)               -- your own pins ({ id, type, x, z }), see below
		view:PlayerMarkerAt(screenPoint)          -- the pin under a point (input space) -> id
		view:StylePlayerMarkers(hover, selected, tracked, pulse) -- per frame: grow / ring
		view:PlayerMarkerCentre(id)               -- a pin's centre on screen (input space)

	North is up (world -Z), east is right (+X). Positions are in map cells (world / CELL).
]]

local TweenService = game:GetService("TweenService")
local AssetService = game:GetService("AssetService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ZoneConfig = require(ReplicatedStorage:WaitForChild("ZoneConfig"))
local Config = require(ReplicatedStorage:WaitForChild("MinimapConfig"))
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local NametagArt = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images"):WaitForChild("NpcNametagArt"))
local HudArt = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images"):WaitForChild("HudArt"))
local HudIcons = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Icons"):WaitForChild("Hud"):WaitForChild("HudIcons"))
local ConsumableIcons = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Icons"):WaitForChild("Consumables"):WaitForChild("ConsumableIcons"))
local ItemConfig = require(ReplicatedStorage:WaitForChild("ItemConfig"))
local MapStyle = require(script.Parent:WaitForChild("MapStyle"))

local MapView = {}
MapView.__index = MapView

local OUTLINE_PX = 2
local GLOW_PX = 9
local ARROW_PX = 22
local OTHER_ARROW_PX = 17
local BLACK = Color3.new(0, 0, 0)
local NPC_GREEN = Color3.fromHex("28462C")
local NPC_BRONZE = Color3.fromHex("AC966C")
local NPC_NAME = Color3.fromHex("EEE6CE")
local NPC_INK = Color3.fromHex("120C08")
-- An NPC crest reads over bright ground thanks to a dark ring (NPC_RING x its size) and a soft
-- shadow under it (NPC_SHADOW x its size, dropped NPC_SHADOW_DROP of its size).
local NPC_RING = 1.16
local NPC_SHADOW = 1.75
local NPC_SHADOW_DROP = .1

-- Player marker icons (MVP: existing art; dedicated pins can replace these later). "" or a
-- missing entry = no image: General draws a bronze diamond pin instead.
local PLAYER_MARKER_ICONS = {
	Combat = HudIcons.COMBAT,         -- the game's combat icon (sword and shield)
	Fishing = ConsumableIcons.FISH,
	Mining = ItemConfig.TOOL_ICONS.Pickaxe,
}
MapView.PLAYER_MARKER_ICONS = PLAYER_MARKER_ICONS
local MARKER_PLATE = Color3.fromHex("17120E")
local MARKER_RING_PX = 2
local LABEL_GOLD = Color3.fromRGB(240, 222, 178)

-------------------------------------------------------------------------------------------------
-- The player arrow, drawn once into a small EditableImage (no uploaded asset needed).

local arrowContent
local function arrowImage()
	if arrowContent ~= nil then return arrowContent end
	arrowContent = false
	local ok, img = pcall(function() return AssetService:CreateEditableImage({ Size = Vector2.new(32, 32) }) end)
	if not ok or not img then return false end
	-- Arrowhead pointing up: the triangle tip (16, 2) / wings (4, 29) (28, 29), minus a notch
	-- triangle cut up into its base to (16, 22). `grow` fattens it for the dark outline.
	local function side(ax, ay, bx, by, px, py) return (bx - ax) * (py - ay) - (by - ay) * (px - ax) end
	local function inTriangle(px, py, ax, ay, bx, by, cx, cy)
		local d1, d2, d3 = side(ax, ay, bx, by, px, py), side(bx, by, cx, cy, px, py), side(cx, cy, ax, ay, px, py)
		local hasNeg = d1 < 0 or d2 < 0 or d3 < 0
		local hasPos = d1 > 0 or d2 > 0 or d3 > 0
		return not (hasNeg and hasPos)
	end
	local function inside(px, py, grow)
		return inTriangle(px, py, 16, 2 - grow, 4 - grow, 29 + grow, 28 + grow, 29 + grow)
			and not inTriangle(px, py, 2, 32, 16, 22 + grow, 30, 32)
	end
	local buf = buffer.create(32 * 32 * 4)
	for y = 0, 31 do
		for x = 0, 31 do
			local px, py = x + .5, y + .5
			local r, g, b, a = 0, 0, 0, 0
			if inside(px, py, 0) then
				r, g, b, a = 255, 255, 255, 255
			elseif inside(px, py, 1.6) then
				r, g, b, a = 20, 20, 24, 255
			end
			local at = (y * 32 + x) * 4
			buffer.writeu8(buf, at, r); buffer.writeu8(buf, at + 1, g); buffer.writeu8(buf, at + 2, b); buffer.writeu8(buf, at + 3, a)
		end
	end
	img:WritePixelsBuffer(Vector2.zero, Vector2.new(32, 32), buf)
	arrowContent = Content.fromObject(img)
	return arrowContent
end

-------------------------------------------------------------------------------------------------

function MapView.new(parent, options)
	options = options or {}
	local self = setmetatable({}, MapView)
	self.labelScale = options.labelScale or 6
	self.labelMin = options.labelMin or 11
	self.labelMax = options.labelMax or 34
	self.scale = options.scale or 2
	self.tiles = {}    -- [key] = ImageLabel
	self.segments = {} -- { frame, ax, az, bx, bz, glow }
	self.labels = {}   -- { label, x, z }
	self.zoneSegments = {} -- [zoneId] = { outline point list }

	local clip = Instance.new("Frame")
	clip.Name = "MapClip"
	clip.Size = UDim2.fromScale(1, 1)
	clip.BackgroundColor3 = MapStyle.FOG -- unexplored ground reads as dark parchment, not a black hole
	clip.BorderSizePixel = 0
	clip.ClipsDescendants = true
	clip.Parent = parent
	if options.cornerRadius then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, options.cornerRadius)
		corner.Parent = clip
	end
	self.clip = clip

	local canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.BackgroundTransparency = 1
	canvas.BorderSizePixel = 0
	canvas.Parent = clip
	self.canvas = canvas

	local function layer(name, z)
		local f = Instance.new("Frame")
		f.Name = name
		f.BackgroundTransparency = 1
		f.Size = UDim2.fromScale(1, 1)
		f.ZIndex = z
		f.Parent = canvas
		return f
	end
	self.tileLayer = layer("Tiles", 1)
	self.outlineLayer = layer("Outlines", 2)
	self.labelLayer = layer("Labels", 3)
	self.npcLayer = layer("NpcMarkers", 4)
	self.npcMarkers = {} -- [id] = { holder, name, x, z, icon }
	self.npcGroupLabels = {} -- name lists under grouped crests, rebuilt every layout
	-- NPC crest size: a fixed npcMarkerPx, or npcMarkerPerCell * scale clamped to
	-- npcMarkerMin..npcMarkerMax. Names show from npcNameScale up (nil = never).
	self.npcMarkerPx = options.npcMarkerPx
	self.npcMarkerPerCell = options.npcMarkerPerCell or 8
	self.npcMarkerMin = options.npcMarkerMin or 16
	self.npcMarkerMax = options.npcMarkerMax or 30
	self.npcNameScale = options.npcNameScale
	-- Player markers sit above the NPC crests; sized like them (fixed px, or per cell clamped).
	self.playerLayer = layer("PlayerMarkers", 5)
	self.playerMarkers = {} -- [id] = { holder, x, z }
	self.playerMarkerPx = options.playerMarkerPx
	self.playerMarkerPerCell = options.playerMarkerPerCell or 7
	self.playerMarkerMin = options.playerMarkerMin or 18
	self.playerMarkerMax = options.playerMarkerMax or 30

	local arrow = Instance.new("ImageLabel")
	arrow.Name = "PlayerArrow"
	arrow.AnchorPoint = Vector2.new(.5, .5)
	arrow.Size = UDim2.fromOffset(ARROW_PX, ARROW_PX)
	arrow.BackgroundTransparency = 1
	arrow.ZIndex = 10
	local content = arrowImage()
	if content then arrow.ImageContent = content else arrow.BackgroundTransparency = 0; arrow.Size = UDim2.fromOffset(8, 8) end
	arrow.Parent = clip
	self.arrow = arrow
	self.others = {} -- pooled arrows for other players
	return self
end

-- Other players: plain tinted arrows, no names. `list` = { { x, z, look } } in map cells.
function MapView:SetOthers(centreX, centreZ, list, colour)
	local s = self.scale
	for i, entry in ipairs(list) do
		local arrow = self.others[i]
		if not arrow then
			arrow = Instance.new("ImageLabel")
			arrow.Name = "OtherArrow"
			arrow.AnchorPoint = Vector2.new(.5, .5)
			arrow.Size = UDim2.fromOffset(OTHER_ARROW_PX, OTHER_ARROW_PX)
			arrow.BackgroundTransparency = 1
			arrow.ZIndex = 9 -- under your own arrow
			local content = arrowImage()
			if content then arrow.ImageContent = content else arrow.BackgroundTransparency = 0; arrow.Size = UDim2.fromOffset(6, 6) end
			arrow.Parent = self.clip
			self.others[i] = arrow
		end
		arrow.ImageColor3 = colour
		arrow.BackgroundColor3 = colour
		arrow.Position = UDim2.new(.5, (entry.x - centreX) * s, .5, (entry.z - centreZ) * s)
		if entry.look then arrow.Rotation = math.deg(math.atan2(entry.look.X, -entry.look.Z)) end
		arrow.Visible = true
	end
	for i = #list + 1, #self.others do
		self.others[i].Visible = false
	end
end

-- NPC markers: the floating nametag's crest + role icon, and the role name under it once
-- zoomed in to npcNameScale. `list` = { { id, x, z, name, icon, npcType } }, x/z in map cells,
-- icon = an NpcNametagArt.ICONS entry or nil. Lives on the canvas, so panning costs nothing.
function MapView:SetNpcMarkers(list)
	local keep = {}
	for _, entry in ipairs(list) do
		keep[entry.id] = true
		local marker = self.npcMarkers[entry.id]
		if not marker then
			local holder = Instance.new("Frame")
			holder.Name = entry.id
			holder.AnchorPoint = Vector2.new(.5, .5)
			holder.BackgroundTransparency = 1
			holder.Parent = self.npcLayer

			-- ZIndex 5..8 sits above the map layers (1..4) and under the player arrows (9, 10)
			-- whether this ScreenGui layers by sibling or globally.
			if HudArt.GLOW_SOFT ~= "" then
				local shadow = Instance.new("ImageLabel")
				shadow.Name = "Shadow"
				shadow.AnchorPoint = Vector2.new(.5, .5)
				shadow.Position = UDim2.fromScale(.5, .5 + NPC_SHADOW_DROP)
				shadow.Size = UDim2.fromScale(NPC_SHADOW, NPC_SHADOW)
				shadow.BackgroundTransparency = 1
				shadow.Image = HudArt.GLOW_SOFT
				shadow.ImageColor3 = BLACK
				shadow.ImageTransparency = .15
				shadow.ZIndex = 5
				shadow.Parent = holder
			end

			local ring = Instance.new("Frame")
			ring.Name = "Ring"
			ring.AnchorPoint = Vector2.new(.5, .5)
			ring.Position = UDim2.fromScale(.5, .5)
			ring.Size = UDim2.fromScale(NPC_RING, NPC_RING)
			ring.BackgroundColor3 = NPC_INK
			ring.BorderSizePixel = 0
			ring.ZIndex = 6
			ring.Parent = holder
			local ringCorner = Instance.new("UICorner")
			ringCorner.CornerRadius = UDim.new(1, 0)
			ringCorner.Parent = ring

			local crest = Instance.new("ImageLabel")
			crest.Name = "Crest"
			crest.Size = UDim2.fromScale(1, 1)
			crest.BackgroundTransparency = 1
			crest.ZIndex = 7
			crest.Parent = holder
			if NametagArt.CREST.Image ~= "" then
				crest.Image = NametagArt.CREST.Image
			else
				crest.BackgroundTransparency = 0
				crest.BackgroundColor3 = NPC_GREEN
				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(1, 0)
				corner.Parent = crest
				local edge = Instance.new("UIStroke")
				edge.Color = NPC_BRONZE
				edge.Thickness = 2
				edge.Parent = crest
			end

			if entry.icon and entry.icon.Image ~= "" then
				local hole = NametagArt.CREST.HOLE
				local icon = Instance.new("ImageLabel")
				icon.Name = "Icon"
				icon.AnchorPoint = Vector2.new(.5, .5)
				icon.Position = UDim2.fromScale(hole.X, hole.Y)
				icon.Size = UDim2.fromScale(hole.D * 1.15, hole.D * 1.15) -- over the inner rim: these draw small
				icon.BackgroundTransparency = 1
				icon.Image = entry.icon.Image
				icon.ImageRectOffset = entry.icon.Offset
				icon.ImageRectSize = entry.icon.Size
				icon.ZIndex = 8
				icon.Parent = crest
			end

			local name = Instance.new("TextLabel")
			name.Name = "NameLabel"
			name.AnchorPoint = Vector2.new(.5, 0)
			name.Position = UDim2.new(.5, 0, (1 + NPC_RING) / 2, 1)
			name.Size = UDim2.fromOffset(0, 16)
			name.AutomaticSize = Enum.AutomaticSize.X
			name.BackgroundTransparency = 1
			name.FontFace = UIFonts.GetNPCFont(entry.npcType, "Tag")
			name.TextSize = 13
			name.TextColor3 = NPC_NAME
			name.ZIndex = 8
			name.Visible = false
			name.Parent = holder
			local nameStroke = Instance.new("UIStroke")
			nameStroke.Color = NPC_INK
			nameStroke.Thickness = 1.5
			nameStroke.Parent = name

			marker = { holder = holder, name = name }
			self.npcMarkers[entry.id] = marker
		end
		marker.x, marker.z = entry.x, entry.z
		marker.icon = entry.icon
		marker.name.Text = entry.name or ""
	end
	for id, marker in pairs(self.npcMarkers) do
		if not keep[id] then
			marker.holder:Destroy()
			self.npcMarkers[id] = nil
		end
	end
	self:_layoutNpcMarkers()
end

-- Crests whose names (or, unnamed, whose crests) would overlap at this zoom merge into one
-- group: the crests sit side by side at the group's centre, and their names are listed under
-- the row in the same left-to-right order, each line led by that NPC's icon.
local NAME_CHAR_PX = 7.5 -- rough width of one name character at TextSize 13 (overlap test only)
local GROUP_GAP = 3

function MapView:_groupLabel(members, x, y)
	local frame = Instance.new("Frame")
	frame.Name = "NpcGroupNames"
	frame.AnchorPoint = Vector2.new(.5, 0)
	frame.Position = UDim2.fromOffset(x, y)
	frame.Size = UDim2.fromOffset(0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.XY
	frame.BackgroundTransparency = 1
	frame.ZIndex = 8
	frame.Parent = self.npcLayer
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.Parent = frame
	for k, marker in ipairs(members) do
		local row = Instance.new("Frame")
		row.Name = marker.holder.Name
		row.LayoutOrder = k
		row.Size = UDim2.fromOffset(0, 16)
		row.AutomaticSize = Enum.AutomaticSize.X
		row.BackgroundTransparency = 1
		row.ZIndex = 8
		row.Parent = frame
		local rowLayout = Instance.new("UIListLayout")
		rowLayout.FillDirection = Enum.FillDirection.Horizontal
		rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
		rowLayout.Padding = UDim.new(0, 3)
		rowLayout.Parent = row
		if marker.icon and marker.icon.Image ~= "" then
			local icon = Instance.new("ImageLabel")
			icon.LayoutOrder = 1
			icon.Size = UDim2.fromOffset(14, 14)
			icon.BackgroundTransparency = 1
			icon.Image = marker.icon.Image
			icon.ImageRectOffset = marker.icon.Offset
			icon.ImageRectSize = marker.icon.Size
			icon.ZIndex = 8
			icon.Parent = row
		end
		local text = Instance.new("TextLabel")
		text.LayoutOrder = 2
		text.Size = UDim2.fromOffset(0, 16)
		text.AutomaticSize = Enum.AutomaticSize.X
		text.BackgroundTransparency = 1
		text.FontFace = marker.name.FontFace
		text.TextSize = 13
		text.TextColor3 = NPC_NAME
		text.Text = marker.name.Text
		text.ZIndex = 8
		text.Parent = row
		local stroke = Instance.new("UIStroke")
		stroke.Color = NPC_INK
		stroke.Thickness = 1.5
		stroke.Parent = text
	end
	table.insert(self.npcGroupLabels, frame)
end

function MapView:_layoutNpcMarkers()
	for _, label in ipairs(self.npcGroupLabels) do label:Destroy() end
	table.clear(self.npcGroupLabels)
	local b = self.bounds
	if not b then return end
	local s = self.scale
	local px = self.npcMarkerPx or math.clamp(math.floor(s * self.npcMarkerPerCell + .5), self.npcMarkerMin, self.npcMarkerMax)
	local named = self.npcNameScale ~= nil and s >= self.npcNameScale

	local list = {}
	for _, marker in pairs(self.npcMarkers) do
		marker.px, marker.pz = (marker.x - b.x0) * s, (marker.z - b.z0) * s
		marker.width = named and math.max(px, #marker.name.Text * NAME_CHAR_PX + 6) or px
		table.insert(list, marker)
	end
	table.sort(list, function(a, c)
		if a.px ~= c.px then return a.px < c.px end
		return a.holder.Name < c.holder.Name
	end)

	-- Union every pair that would overlap into groups.
	local parent = {}
	for i = 1, #list do parent[i] = i end
	local function find(i)
		while parent[i] ~= i do
			parent[i] = parent[parent[i]]
			i = parent[i]
		end
		return i
	end
	local tall = named and px + 18 or px
	for i = 1, #list do
		for j = i + 1, #list do
			local a, c = list[i], list[j]
			if math.abs(a.px - c.px) < (a.width + c.width) / 2 + 4 and math.abs(a.pz - c.pz) < tall then
				parent[find(j)] = find(i)
			end
		end
	end
	local groups = {}
	for i, marker in ipairs(list) do
		local root = find(i)
		groups[root] = groups[root] or {}
		table.insert(groups[root], marker) -- stays in left-to-right order
	end

	for _, members in pairs(groups) do
		local n = #members
		local cx, cz = 0, 0
		for _, marker in ipairs(members) do
			cx += marker.px
			cz += marker.pz
		end
		cx, cz = cx / n, cz / n
		for k, marker in ipairs(members) do
			marker.holder.Size = UDim2.fromOffset(px, px)
			if n == 1 then
				marker.holder.Position = UDim2.fromOffset(marker.px, marker.pz)
			else
				marker.holder.Position = UDim2.fromOffset(cx + (k - (n + 1) / 2) * (px + GROUP_GAP), cz)
			end
			marker.name.Visible = named and n == 1 and marker.name.Text ~= ""
		end
		if named and n > 1 then
			self:_groupLabel(members, cx, cz + px * NPC_RING / 2 + 1)
		end
	end
end

-- One player marker: a dark round plate, a ring in its type's colour, the type's icon. Also
-- used by the controller for the picker's buttons. Fills `parent` (give it a square size).
function MapView.BuildPlayerMarkerBadge(parent, typeEntry, zBase)
	zBase = zBase or 5
	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.AnchorPoint = Vector2.new(.5, .5)
	plate.Position = UDim2.fromScale(.5, .5)
	plate.Size = UDim2.new(1, -MARKER_RING_PX * 2, 1, -MARKER_RING_PX * 2)
	plate.BackgroundColor3 = MARKER_PLATE
	plate.BorderSizePixel = 0
	plate.ZIndex = zBase + 1
	plate.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = plate
	local ring = Instance.new("UIStroke")
	ring.Color = typeEntry.ring
	ring.Thickness = MARKER_RING_PX
	ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ring.Parent = plate

	local image = PLAYER_MARKER_ICONS[typeEntry.id]
	if image and image ~= "" then
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.AnchorPoint = Vector2.new(.5, .5)
		icon.Position = UDim2.fromScale(.5, .5)
		icon.Size = UDim2.fromScale(.72, .72)
		icon.BackgroundTransparency = 1
		icon.Image = image
		icon.ScaleType = Enum.ScaleType.Fit
		icon.ZIndex = zBase + 2
		icon.Parent = plate
	else
		-- The general pin: a small bronze diamond with a dark edge.
		local pin = Instance.new("Frame")
		pin.Name = "Pin"
		pin.AnchorPoint = Vector2.new(.5, .5)
		pin.Position = UDim2.fromScale(.5, .5)
		pin.Size = UDim2.fromScale(.42, .42)
		pin.Rotation = 45
		pin.BackgroundColor3 = typeEntry.ring
		pin.BorderSizePixel = 0
		pin.ZIndex = zBase + 2
		pin.Parent = plate
		local edge = Instance.new("UIStroke")
		edge.Color = NPC_INK
		edge.Thickness = 1
		edge.Parent = pin
	end
	return plate
end

-- Your own markers. `list` = { { id, type, x, z } }, x/z in map cells. Always shown (they're
-- yours), on the canvas like the NPC crests, so panning costs nothing.
function MapView:SetPlayerMarkers(list)
	local keep = {}
	for _, entry in ipairs(list) do
		local typeEntry = Config.PlayerMarkerType(entry.type)
		if typeEntry then
			keep[entry.id] = true
			local marker = self.playerMarkers[entry.id]
			if not marker or marker.type ~= entry.type then
				if marker then marker.holder:Destroy() end
				local holder = Instance.new("Frame")
				holder.Name = entry.id
				holder.AnchorPoint = Vector2.new(.5, .5)
				holder.BackgroundTransparency = 1
				holder.Parent = self.playerLayer
				if HudArt.GLOW_SOFT ~= "" then
					local shadow = Instance.new("ImageLabel")
					shadow.Name = "Shadow"
					shadow.AnchorPoint = Vector2.new(.5, .5)
					shadow.Position = UDim2.fromScale(.5, .5 + NPC_SHADOW_DROP)
					shadow.Size = UDim2.fromScale(NPC_SHADOW, NPC_SHADOW)
					shadow.BackgroundTransparency = 1
					shadow.Image = HudArt.GLOW_SOFT
					shadow.ImageColor3 = BLACK
					shadow.ImageTransparency = .25
					shadow.ZIndex = 5
					shadow.Parent = holder
				end
				MapView.BuildPlayerMarkerBadge(holder, typeEntry, 5)
				-- The tracked pin wears a pulsing ring in its type's colour (StylePlayerMarkers).
				local track = Instance.new("Frame")
				track.Name = "TrackRing"
				track.AnchorPoint = Vector2.new(.5, .5)
				track.Position = UDim2.fromScale(.5, .5)
				track.Size = UDim2.fromScale(1.5, 1.5)
				track.BackgroundTransparency = 1
				track.Visible = false
				track.ZIndex = 5
				track.Parent = holder
				local trackCorner = Instance.new("UICorner")
				trackCorner.CornerRadius = UDim.new(1, 0)
				trackCorner.Parent = track
				local trackStroke = Instance.new("UIStroke")
				trackStroke.Color = typeEntry.ring
				trackStroke.Thickness = 2
				trackStroke.Parent = track
				local grow = Instance.new("UIScale")
				grow.Parent = holder
				marker = { holder = holder, type = entry.type, scale = grow, track = track, trackStroke = trackStroke }
				self.playerMarkers[entry.id] = marker
			end
			marker.x, marker.z = entry.x, entry.z
		end
	end
	for id, marker in pairs(self.playerMarkers) do
		if not keep[id] then
			marker.holder:Destroy()
			self.playerMarkers[id] = nil
		end
	end
	self:_layoutPlayerMarkers()
end

function MapView:_layoutPlayerMarkers()
	local b = self.bounds
	if not b then return end
	local s = self.scale
	local px = self.playerMarkerPx or math.clamp(math.floor(s * self.playerMarkerPerCell + .5), self.playerMarkerMin, self.playerMarkerMax)
	for _, marker in pairs(self.playerMarkers) do
		marker.holder.Size = UDim2.fromOffset(px, px)
		marker.holder.Position = UDim2.fromOffset((marker.x - b.x0) * s, (marker.z - b.z0) * s)
	end
end

-- Per frame: the hovered / selected pin grows, the tracked one wears a ring that breathes with
-- `pulse` (0..1).
function MapView:StylePlayerMarkers(hoverId, selectedId, trackedId, pulse)
	for id, marker in pairs(self.playerMarkers) do
		marker.scale.Scale = (id == hoverId or id == selectedId) and 1.3 or 1
		marker.track.Visible = id == trackedId
		if id == trackedId then
			marker.track.Size = UDim2.fromScale(1.35 + .35 * pulse, 1.35 + .35 * pulse)
			marker.trackStroke.Transparency = .1 + .6 * pulse
		end
	end
end

function MapView:PlayerMarkerCentre(id)
	local marker = self.playerMarkers[id]
	if not marker then return nil end
	return marker.holder.AbsolutePosition + marker.holder.AbsoluteSize / 2
end

-- The marker under `point` (input / AbsolutePosition space), nearest first, or nil.
function MapView:PlayerMarkerAt(point)
	local best, bestDist = nil, math.huge
	for id, marker in pairs(self.playerMarkers) do
		local holder = marker.holder
		local centre = holder.AbsolutePosition + holder.AbsoluteSize / 2
		local radius = holder.AbsoluteSize.X / 2 + 2
		local dist = (point - centre).Magnitude
		if dist <= radius and dist < bestDist then best, bestDist = id, dist end
	end
	return best
end

function MapView:SetBounds(bounds)
	self.bounds = bounds
	self:Layout()
end

function MapView:SetChunkImage(key, content)
	local tile = self.tiles[key]
	if not tile then
		tile = Instance.new("ImageLabel")
		tile.Name = key
		tile.BackgroundTransparency = 1
		tile.BorderSizePixel = 0
		-- Bilinear on purpose: with MapStyle's banded colours this turns the cell grid into soft
		-- painted shapes (Pixelated gave the hard blocky look).
		tile.ResampleMode = Enum.ResamplerMode.Default
		tile.Parent = self.tileLayer
		self.tiles[key] = tile
		self:_layoutTile(key, tile)
	end
	tile.ImageContent = content
end

-- zones: ZoneService wire rows; discovered: { [zoneId] = true }; labelAt(zone) -> x, z (studs)
function MapView:SetZones(zones, discovered, labelAt)
	self.outlineLayer:ClearAllChildren()
	self.labelLayer:ClearAllChildren()
	table.clear(self.segments)
	table.clear(self.labels)
	table.clear(self.zoneSegments)
	for _, zone in ipairs(zones) do
		if discovered[zone.id] then
			local colour = ZoneConfig.ALIGNMENT_COLORS[zone.alignment] or Color3.fromRGB(200, 190, 170)
			local outline = Config.ZoneOutline(zone)
			self.zoneSegments[zone.id] = { outline = outline, colour = colour }
			for i = 1, #outline do
				local a, b = outline[i], outline[i % #outline + 1]
				self:_addSegment(a, b, colour, false)
			end
			local x, z = labelAt(zone)
			local label = Instance.new("TextLabel")
			label.Name = zone.name
			label.AnchorPoint = Vector2.new(.5, .5)
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromOffset(400, 40)
			label.FontFace = UIFonts.DisplayBold
			label.Text = string.upper(zone.name)
			label.TextColor3 = LABEL_GOLD
			label.TextStrokeTransparency = .15
			label.TextStrokeColor3 = BLACK
			label.Parent = self.labelLayer
			table.insert(self.labels, { label = label, x = x / Config.CELL, z = z / Config.CELL })
		end
	end
	self:Layout()
end

function MapView:_addSegment(a, b, colour, glow)
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(.5, .5)
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = colour
	frame.ZIndex = glow and 1 or 2
	frame.Parent = self.outlineLayer
	local segment = { frame = frame, ax = a.x / Config.CELL, az = a.z / Config.CELL, bx = b.x / Config.CELL, bz = b.z / Config.CELL, glow = glow }
	table.insert(self.segments, segment)
	self:_layoutSegment(segment)
	return segment
end

-- The "region discovered" pulse: a thick bright copy of the outline that flares twice and fades.
function MapView:Glow(zoneId)
	local zone = self.zoneSegments[zoneId]
	if not zone then return end
	local glows = {}
	for i = 1, #zone.outline do
		local a, b = zone.outline[i], zone.outline[i % #zone.outline + 1]
		local seg = self:_addSegment(a, b, Color3.new(1, 1, 1):Lerp(zone.colour, .35), true)
		seg.frame.BackgroundTransparency = 1
		table.insert(glows, seg)
	end
	task.spawn(function()
		for _ = 1, 2 do
			for _, seg in ipairs(glows) do
				TweenService:Create(seg.frame, TweenInfo.new(.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = .05 }):Play()
			end
			task.wait(.3)
			for _, seg in ipairs(glows) do
				TweenService:Create(seg.frame, TweenInfo.new(.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 }):Play()
			end
			task.wait(.95)
		end
		for _, seg in ipairs(glows) do
			local at = table.find(self.segments, seg)
			if at then table.remove(self.segments, at) end
			seg.frame:Destroy()
		end
	end)
end

function MapView:SetScale(scale)
	if scale == self.scale then return end
	self.scale = scale
	self:Layout()
end

function MapView:_layoutTile(key, tile)
	local b = self.bounds
	if not b then return end
	local kx, kz = Config.ParseKey(key)
	local s = self.scale
	tile.Position = UDim2.fromOffset((kx * Config.CHUNK - b.x0) * s, (kz * Config.CHUNK - b.z0) * s)
	tile.Size = UDim2.fromOffset(Config.CHUNK * s, Config.CHUNK * s)
end

function MapView:_layoutSegment(seg)
	local b = self.bounds
	if not b then return end
	local s = self.scale
	local ax, az = (seg.ax - b.x0) * s, (seg.az - b.z0) * s
	local bx, bz = (seg.bx - b.x0) * s, (seg.bz - b.z0) * s
	local dx, dz = bx - ax, bz - az
	local length = math.sqrt(dx * dx + dz * dz)
	local thick = seg.glow and GLOW_PX or OUTLINE_PX
	seg.frame.Position = UDim2.fromOffset((ax + bx) / 2, (az + bz) / 2)
	seg.frame.Size = UDim2.fromOffset(length + thick * .5, thick)
	seg.frame.Rotation = math.deg(math.atan2(dz, dx))
end

function MapView:Layout()
	local b = self.bounds
	if not b then return end
	local s = self.scale
	self.canvas.Size = UDim2.fromOffset((b.x1 - b.x0 + 1) * s, (b.z1 - b.z0 + 1) * s)
	for key, tile in pairs(self.tiles) do self:_layoutTile(key, tile) end
	for _, seg in ipairs(self.segments) do self:_layoutSegment(seg) end
	local textSize = math.clamp(math.floor(self.labelScale * s + .5), self.labelMin, self.labelMax)
	for _, entry in ipairs(self.labels) do
		entry.label.Position = UDim2.fromOffset((entry.x - b.x0) * s, (entry.z - b.z0) * s)
		entry.label.TextSize = textSize
	end
	self:_layoutNpcMarkers()
	self:_layoutPlayerMarkers()
end

-- centre*: the map cell at the middle of the view; player*: where the arrow goes.
function MapView:Update(centreX, centreZ, playerX, playerZ, look)
	local b = self.bounds
	if not b then return end
	local s = self.scale
	self.canvas.Position = UDim2.new(.5, -(centreX - b.x0) * s, .5, -(centreZ - b.z0) * s)
	if playerX then
		self.arrow.Visible = true
		self.arrow.Position = UDim2.new(.5, (playerX - centreX) * s, .5, (playerZ - centreZ) * s)
		if look then self.arrow.Rotation = math.deg(math.atan2(look.X, -look.Z)) end
	else
		self.arrow.Visible = false
	end
end

return MapView
