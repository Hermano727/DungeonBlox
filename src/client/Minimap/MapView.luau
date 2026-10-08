--[[
	MapView -- one rendering of the world map inside a frame (the corner minimap and the expanded
	map are two MapViews over the same chunk images; see Minimap/init.client).

		local view = MapView.new(parentFrame, { labelScale = 5, labelMin = 10, labelMax = 16 })
		view:SetBounds(bounds)                    -- MinimapConfig.CellBounds
		view:SetChunkImage(key, content)          -- Content.fromObject(EditableImage)
		view:SetZones(zones, discovered, labelAt) -- discovered outlines + names
		view:SetScale(pixelsPerCell)
		view:Update(centreCellX, centreCellZ, playerCellX, playerCellZ, lookVector)
		view:Glow(zoneId)                         -- the "region discovered" pulse
		view:SetNpcMarkers(list)                  -- NPC crests (RS/NpcMapMarkers), see below

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
	clip.BackgroundColor3 = BLACK
	clip.BorderSizePixel = 0
	clip.ClipsDescendants = true
	clip.Parent = parent
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
	self.npcMarkers = {} -- [id] = { holder, name, x, z }
	-- NPC crest size: a fixed npcMarkerPx, or npcMarkerPerCell * scale clamped to
	-- npcMarkerMin..npcMarkerMax. Names show from npcNameScale up (nil = never).
	self.npcMarkerPx = options.npcMarkerPx
	self.npcMarkerPerCell = options.npcMarkerPerCell or 8
	self.npcMarkerMin = options.npcMarkerMin or 16
	self.npcMarkerMax = options.npcMarkerMax or 30
	self.npcNameScale = options.npcNameScale

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

function MapView:_layoutNpcMarkers()
	local b = self.bounds
	if not b then return end
	local s = self.scale
	local px = self.npcMarkerPx or math.clamp(math.floor(s * self.npcMarkerPerCell + .5), self.npcMarkerMin, self.npcMarkerMax)
	local named = self.npcNameScale ~= nil and s >= self.npcNameScale
	for _, marker in pairs(self.npcMarkers) do
		marker.holder.Size = UDim2.fromOffset(px, px)
		marker.holder.Position = UDim2.fromOffset((marker.x - b.x0) * s, (marker.z - b.z0) * s)
		marker.name.Visible = named and marker.name.Text ~= ""
	end
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
		tile.ResampleMode = Enum.ResamplerMode.Pixelated
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
			label.Font = Enum.Font.GothamBold
			label.Text = string.upper(zone.name)
			label.TextColor3 = Color3.fromRGB(236, 230, 214)
			label.TextStrokeTransparency = .2
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
