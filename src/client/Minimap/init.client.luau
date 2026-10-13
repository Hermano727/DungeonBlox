--[[
	Minimap -- the world map (client). Server side: SSS/MinimapService. Tuning: RS/MinimapConfig.

	  Corner minimap  top right, always on in the overworld, centred on you, north up.
	  Expanded map    Keys.ToggleMap (M). Zoom with the scroll wheel or Keys.MapZoomIn/Out (the
	                  hints sit bottom right); drag to look around; M or Esc closes.

	Fog of war: everything is black except
	  - explored cells: the ground within REVEAL_RADIUS of wherever you have walked (saved on
	    the server; revealed here too as you walk so the map fills in instantly)
	  - zones in MinimapConfig.DefaultRevealed (Oakhaven), shown in full from the start
	  - discovered zones of an AutoRevealAlignments alignment (Lawful: safe towns), in full
	Discovered zones (entered at least once; Oakhaven from the start) also show their outline
	and name, even while their inside is still dark. A first discovery pulses the outline and
	plays the in-world DiscoveryPeek (ZoneEntryNotify.discovered; ZoneClient shows the REGION
	DISCOVERED banner). MinimapReset (the F8 MAP tab) wipes it all and reloads from the server.

	Each map chunk (MinimapConfig.CHUNK cells) is one EditableImage shared by both views; its
	colours are asked from the server once (MinimapChunkRequest) and cached.

	NPC markers: every NPC with an NPCRegistry Nametag shows as its nametag crest + role icon
	(RS/NpcMapMarkers, published by SSS/NpcLocations) on uncovered ground. The corner map never
	names them; the expanded map shows the role name once zoomed to MinimapConfig.NpcNameScale.

	Player markers (your own pins, tracking, the legend): Minimap/PlayerMarkers. The expanded
	map lives in its own ScreenGui at UILayers.WORLD_MAP, above every HUD row, so nothing can
	sit on its controls. Scroll zooms toward the cursor; Keys.MapRecentre goes back to you.
]]

local AssetService = game:GetService("AssetService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("MinimapConfig"))
local Keys = require(ReplicatedStorage:WaitForChild("KeybindConfig"))
local MenuMouse = require(ReplicatedStorage:WaitForChild("CursorUtils"))
local QuickNav = require(ReplicatedStorage:WaitForChild("HudQuickNav"))
local InteractionLock = require(ReplicatedStorage:WaitForChild("InteractionLock"))
local WorldMapRequest = require(ReplicatedStorage:WaitForChild("WorldMapRequest"))
local NpcMapMarkers = require(ReplicatedStorage:WaitForChild("NpcMapMarkers"))
local LOCK_OWNER = "WorldMap"
local MapView = require(script:WaitForChild("MapView"))
local DiscoveryPeek = require(script:WaitForChild("DiscoveryPeek"))
local MapStyle = require(script:WaitForChild("MapStyle"))
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))

local GameEvents = ReplicatedStorage:WaitForChild("GameEvents")
local ZoneStateRequest = GameEvents:WaitForChild("ZoneStateRequest")
local ZoneStateBroadcast = GameEvents:WaitForChild("ZoneStateBroadcast")
local ZoneEntryNotify = GameEvents:WaitForChild("ZoneEntryNotify")
local StateRequest = GameEvents:WaitForChild("MinimapStateRequest")
local ChunkRequest = GameEvents:WaitForChild("MinimapChunkRequest")
local ResetEvent = GameEvents:WaitForChild("MinimapReset")
local MarkerAction = GameEvents:WaitForChild("MinimapMarkerAction")
local UILayers = require(ReplicatedStorage:WaitForChild("UILayers"))
local PlayerMarkers = require(script:WaitForChild("PlayerMarkers"))
local HudHider = require(script.Parent:WaitForChild("HudHider"))

local player = Players.LocalPlayer
local CHUNK, CELL = Config.CHUNK, Config.CELL
local BYTES = Config.BYTES_PER_CHUNK
local RENDERS_PER_FRAME = 2 -- stylizing a chunk costs more than the old raw copy

local PANEL = MapStyle.FOG
local EDGE = Color3.fromRGB(8, 6, 6)       -- the dark line right at the map edge
local BRONZE = QuickNav.STYLE.Edge         -- the shared bronze edge (quick-nav plates)
local TEXT = Color3.fromRGB(226, 220, 204)

-------------------------------------------------------------------------------------------------
-- State

local zones = {}
local bounds
local discovered = {}      -- [zoneId] = true
local chunks = {}          -- [key] = { bits, defaultMask, colours, image, dirty, requested }
local renderQueue = {}     -- keys, in order
local queued = {}
local labelCache = {}      -- [zoneId] = { x, z }
local markers              -- Minimap/PlayerMarkers, created further down once the views exist

local function chunkEntry(key)
	local c = chunks[key]
	if not c then
		c = { bits = buffer.create(BYTES) }
		chunks[key] = c
	end
	return c
end

local function markDirty(key)
	local c = chunks[key]
	if c then c.dirty = true end
	if not queued[key] then
		queued[key] = true
		table.insert(renderQueue, key)
	end
end

local function anyBit(buf)
	if not buf then return false end
	for i = 0, BYTES - 1, 4 do
		if buffer.readu32(buf, i) ~= 0 then return true end
	end
	return false
end

-- Zones shown in full regardless of exploring: Oakhaven by name, and every discovered safe zone.
local function revealsAll(zone)
	return Config.DefaultRevealed[zone.name] == true
		or (discovered[zone.id] == true and Config.AutoRevealAlignments[zone.alignment] == true)
end

-- Cells of this chunk inside a fully shown zone (see revealsAll).
local function defaultMaskFor(kx, kz)
	local mask
	local x0, z0 = kx * CHUNK * CELL, kz * CHUNK * CELL
	local x1, z1 = x0 + CHUNK * CELL, z0 + CHUNK * CELL
	for _, zone in ipairs(zones) do
		local overlaps = false
		if revealsAll(zone) then
			local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
			for _, p in ipairs(Config.ZoneOutline(zone)) do
				minX, maxX = math.min(minX, p.x), math.max(maxX, p.x)
				minZ, maxZ = math.min(minZ, p.z), math.max(maxZ, p.z)
			end
			overlaps = maxX >= x0 and minX <= x1 and maxZ >= z0 and minZ <= z1
		end
		if overlaps then
			for row = 0, CHUNK - 1 do
				for col = 0, CHUNK - 1 do
					local cx, cz = kx * CHUNK + col, kz * CHUNK + row
					if Config.ZoneContains(zone, (cx + .5) * CELL, (cz + .5) * CELL) then
						mask = mask or buffer.create(BYTES)
						Config.SetBit(mask, Config.BitIndex(cx, cz))
					end
				end
			end
		end
	end
	return mask
end

-- Where a zone's name goes: the point inside it farthest from its edges (and not inside
-- another zone), so a ring-shaped zone around a town doesn't put its name on the town.
local function labelPoint(zone)
	if labelCache[zone.id] then return labelCache[zone.id].x, labelCache[zone.id].z end
	local outline = Config.ZoneOutline(zone)
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, p in ipairs(outline) do
		minX, maxX = math.min(minX, p.x), math.max(maxX, p.x)
		minZ, maxZ = math.min(minZ, p.z), math.max(maxZ, p.z)
	end
	local function edgeDistance(x, z)
		local best = math.huge
		for i = 1, #outline do
			local a, b = outline[i], outline[i % #outline + 1]
			local dx, dz = b.x - a.x, b.z - a.z
			local len2 = dx * dx + dz * dz
			local t = len2 > 0 and math.clamp(((x - a.x) * dx + (z - a.z) * dz) / len2, 0, 1) or 0
			local ex, ez = a.x + dx * t - x, a.z + dz * t - z
			best = math.min(best, ex * ex + ez * ez)
		end
		return best
	end
	local bestX, bestZ, bestScore = (minX + maxX) / 2, (minZ + maxZ) / 2, -1
	local steps = 24
	for i = 0, steps do
		for j = 0, steps do
			local x = minX + (maxX - minX) * i / steps
			local z = minZ + (maxZ - minZ) * j / steps
			if Config.ZoneContains(zone, x, z) then
				local inOther = false
				for _, other in ipairs(zones) do
					if other ~= zone and Config.ZoneContains(other, x, z) then inOther = true break end
				end
				if not inOther then
					local score = edgeDistance(x, z)
					if score > bestScore then bestX, bestZ, bestScore = x, z, score end
				end
			end
		end
	end
	labelCache[zone.id] = { x = bestX, z = bestZ }
	return bestX, bestZ
end

-------------------------------------------------------------------------------------------------
-- UI

local gui = Instance.new("ScreenGui")
gui.Name = "MinimapGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 30
gui.Parent = player:WaitForChild("PlayerGui")

local function stroke(parent, colour, thickness)
	local s = Instance.new("UIStroke")
	s.Color = colour
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

-- Frames (2026-10-11): the map's own art, RS/Assets/Images/MapUI: a thin double bronze rule with
-- small flowering vines at the corners, like the margin of an explorer's map. Each frame is laid
-- so its rule runs right over the map's edge (MapUI Window = the rule's centre lines); the vines
-- reach outside the map. Without the art, the old plain bronze stroke.
local MapUI = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images"):WaitForChild("MapUI"))

local function hasArt(art)
	return art ~= nil and art.Image ~= ""
end

-- How far the frame art reaches past `size` (px) on each side: left, top, right, bottom.
local function frameOutset(art, size)
	local w = art.Window
	local kx, ky = size.X / (w.X1 - w.X0), size.Y / (w.Y1 - w.Y0)
	return w.X0 * kx, w.Y0 * ky, (art.Size.X - w.X1) * kx, (art.Size.Y - w.Y1) * ky
end

local function mapFrame(target, art, zIndex)
	local w = art.Window
	local spanX, spanY = w.X1 - w.X0, w.Y1 - w.Y0
	local frame = Instance.new("ImageLabel")
	frame.Name = "MapFrame"
	frame.BackgroundTransparency = 1
	frame.Image = art.Image
	frame.Size = UDim2.fromScale(art.Size.X / spanX, art.Size.Y / spanY)
	frame.Position = UDim2.fromScale(-w.X0 / spanX, -w.Y0 / spanY)
	frame.ZIndex = zIndex
	frame.Parent = target
	return frame
end

-- Corner minimap. With the frame art it moves in from the screen's corner by however far the
-- vines reach, so they aren't cut off.
local MINI_SIZE = Vector2.new(Config.MiniSize, Config.MiniSize)
local miniArt = hasArt(MapUI.MINIMAP_FRAME) and MapUI.MINIMAP_FRAME or nil
local miniPadRight, miniPadTop = QuickNav.MARGIN, QuickNav.MARGIN
if miniArt then
	local _, top, right = frameOutset(miniArt, MINI_SIZE)
	miniPadRight = math.max(miniPadRight, math.ceil(right) + 2)
	miniPadTop = math.max(miniPadTop, math.ceil(top) + 2)
end
local mini = Instance.new("Frame")
mini.Name = "Minimap"
mini.AnchorPoint = Vector2.new(1, 0)
mini.Position = UDim2.new(1, -miniPadRight, 0, miniPadTop)
mini.Size = UDim2.fromOffset(Config.MiniSize, Config.MiniSize)
mini.BackgroundColor3 = PANEL
mini.BorderSizePixel = 0
mini.Visible = false
mini.Parent = gui
if not miniArt then
	local miniCorner = Instance.new("UICorner")
	miniCorner.CornerRadius = UDim.new(0, 6)
	miniCorner.Parent = mini
end
local miniView = MapView.new(mini, {
	scale = Config.MiniScale, labelScale = 5, labelMin = 13, labelMax = 18,
	npcMarkerPx = Config.NpcMarkerMiniPx, -- no npcNameScale: never named on the corner map
	playerMarkerPx = Config.PlayerMarkerMiniPx,
	cornerRadius = (not miniArt) and 6 or nil,
})
-- The frame over the map (ZIndex 12: over the NPC markers 5..8 and arrows 9, 10). No key badge:
-- hovering the minimap names it with its key (QuickNav tooltip) and a click opens the M map.
if miniArt then
	mapFrame(mini, miniArt, 12)
else
	local edge = stroke(miniView.clip, QuickNav.STYLE.Edge, 2)
	edge.ZIndex = 12
end

-- The quick-nav buttons (settings, ...) hang under the minimap's bottom-right corner, clear of
-- the frame's vines.
if miniArt then
	local _, _, _, bottom = frameOutset(miniArt, MINI_SIZE)
	QuickNav.GAP = math.max(QuickNav.GAP, math.ceil(bottom) + 4)
end
QuickNav.FollowBelow(mini)

-- Expanded map. With the frame art it keeps the art's shape (UIAspectRatioConstraint, so the
-- vines and the crest never stretch) inside the same share of the screen.
local bigArt = hasArt(MapUI.WORLD_MAP_FRAME) and MapUI.WORLD_MAP_FRAME or nil
local big = Instance.new("Frame")
big.Name = "WorldMap"
big.AnchorPoint = Vector2.new(.5, .5)
big.Position = UDim2.fromScale(.5, .5)
big.Size = UDim2.fromScale(.78, .82)
big.BackgroundColor3 = PANEL
big.BorderSizePixel = 0
big.Visible = false
big.Active = true
-- Its own ScreenGui above every HUD row and banner (UILayers.WORLD_MAP): at the minimap's
-- layer (30) most of the HUD drew over it and ate its controls' input.
local bigGui = Instance.new("ScreenGui")
bigGui.Name = "WorldMapGui"
bigGui.ResetOnSpawn = false
bigGui.IgnoreGuiInset = true
bigGui.DisplayOrder = UILayers.WORLD_MAP
bigGui.Parent = player:WaitForChild("PlayerGui")
big.Parent = bigGui
if bigArt then
	local w = bigArt.Window
	local shape = Instance.new("UIAspectRatioConstraint")
	shape.AspectRatio = (w.X1 - w.X0) / (w.Y1 - w.Y0)
	shape.Parent = big
else
	local bigCorner = Instance.new("UICorner")
	bigCorner.CornerRadius = UDim.new(0, 8)
	bigCorner.Parent = big
end
local bigView = MapView.new(big, {
	scale = 2, labelScale = 7, labelMin = 12, labelMax = 40,
	npcMarkerPerCell = Config.NpcMarkerPerCell, npcMarkerMin = Config.NpcMarkerBigMin,
	npcMarkerMax = Config.NpcMarkerBigMax, npcNameScale = Config.NpcNameScale,
	playerMarkerPerCell = Config.PlayerMarkerPerCell, playerMarkerMin = Config.PlayerMarkerBigMin,
	playerMarkerMax = Config.PlayerMarkerBigMax,
	cornerRadius = (not bigArt) and 8 or nil,
})
if bigArt then
	mapFrame(big, bigArt, 25) -- over the map's own layers, under the panels (40+)
else
	stroke(bigView.clip, EDGE, 2)
	stroke(big, QuickNav.STYLE.Edge, 2)
end
bigView.clip.Active = true

-- The controls, bottom right, on the small dark map panel (MapUI.PANEL, 9-slice): one row per
-- action, its name on the left and its keys on the right as key caps (QuickNav.KeyCap). The
-- panel and the rows are siblings, so the list layout only ever sees the rows.
local HINT_INSET = 22 -- px in from the map's edge, clear of the frame's rule
local HINT_ROW_H, HINT_GAP, HINT_KEY_H = 20, 4, 18
-- Keys by KeybindConfig action id where rebindable (drawn with the CURRENT key, redrawn on a
-- rebind), else as written ("Scroll" and the other mouse inputs draw the mouse icons).
local HINTS = {
	{ "Zoom", { "Scroll", "MapZoomIn", "MapZoomOut" } },
	{ "Look around", { "Drag" } },
	{ "Place marker", { "Right click" } },
	{ "Marker options", { "Click" } },
	{ "Remove marker", { "MapDeleteMarker" } },
	{ "Centre on me", { "MapRecentre" } },
	{ "Close", { "ToggleMap", "Esc" } },
}
local hintKeyRows = {} -- { frame, names }
local hints = Instance.new("Frame")
hints.Name = "Hints"
hints.AnchorPoint = Vector2.new(1, 1)
hints.Position = UDim2.new(1, -HINT_INSET, 1, -HINT_INSET)
hints.Size = UDim2.fromOffset(268, 0)
hints.AutomaticSize = Enum.AutomaticSize.Y
hints.BackgroundTransparency = 1
hints.BorderSizePixel = 0
hints.ZIndex = 20
hints.Parent = big
if hasArt(MapUI.PANEL) then
	local plate = Instance.new("ImageLabel")
	plate.Name = "Panel"
	plate.BackgroundTransparency = 1
	plate.Image = MapUI.PANEL.Image
	plate.ScaleType = Enum.ScaleType.Slice
	plate.SliceCenter = MapUI.PANEL.SliceCenter
	plate.SliceScale = .16
	plate.Size = UDim2.fromScale(1, 1)
	plate.ZIndex = 20
	plate.Parent = hints
else
	hints.BackgroundColor3 = PANEL
	hints.BackgroundTransparency = .15
	stroke(hints, BRONZE, 1)
end
local hintRows = Instance.new("Frame")
hintRows.Name = "Rows"
hintRows.Size = UDim2.fromScale(1, 0)
hintRows.AutomaticSize = Enum.AutomaticSize.Y
hintRows.BackgroundTransparency = 1
hintRows.ZIndex = 21
hintRows.Parent = hints
do
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, HINT_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = hintRows
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 15), UDim.new(0, 12)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 18), UDim.new(0, 15)
	pad.Parent = hintRows
end
for order, hint in ipairs(HINTS) do
	local row = Instance.new("Frame")
	row.Name = hint[1]
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, HINT_ROW_H)
	row.BackgroundTransparency = 1
	row.ZIndex = 21
	row.Parent = hintRows
	local label = Instance.new("TextLabel")
	label.Name = "Action"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(.5, 1)
	label.FontFace = UIFonts.SerifBold
	label.TextSize = 13
	label.TextColor3 = TEXT
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = hint[1]
	label.ZIndex = 22
	label.Parent = row
	local keys = Instance.new("Frame")
	keys.Name = "Keys"
	keys.AnchorPoint = Vector2.new(1, 0)
	keys.Position = UDim2.fromScale(1, 0)
	keys.Size = UDim2.fromScale(.5, 1)
	keys.BackgroundTransparency = 1
	keys.ZIndex = 22
	keys.Parent = row
	local keyLayout = Instance.new("UIListLayout")
	keyLayout.FillDirection = Enum.FillDirection.Horizontal
	keyLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	keyLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	keyLayout.SortOrder = Enum.SortOrder.LayoutOrder
	keyLayout.Padding = UDim.new(0, 4)
	keyLayout.Parent = keys
	table.insert(hintKeyRows, { frame = keys, names = hint[2] })
end
local function drawHintKeys()
	for _, entry in ipairs(hintKeyRows) do
		for _, old in ipairs(entry.frame:GetChildren()) do
			if old.Name == "KeyCap" then old:Destroy() end
		end
		for i, name in ipairs(entry.names) do
			local cap = QuickNav.KeyCap(entry.frame, QuickNav.KeyName(name), HINT_KEY_H)
			cap.LayoutOrder = i
			cap.ZIndex = 23
			cap.Face.ZIndex = 24
		end
	end
end
drawHintKeys()
Keys.Changed:Connect(drawHintKeys)

-------------------------------------------------------------------------------------------------
-- Rendering chunks

local function rebuildZones()
	miniView:SetZones(zones, discovered, labelPoint)
	bigView:SetZones(zones, discovered, labelPoint)
end

-- Recomputes every chunk's fully-shown mask (after the zones, the discovered set or a
-- reset changes) and re-renders what changed.
local function refreshMasks()
	for key, c in pairs(chunks) do
		local kx, kz = Config.ParseKey(key)
		local mask = defaultMaskFor(kx, kz)
		if mask ~= c.defaultMask then
			c.defaultMask = mask
			markDirty(key)
		end
	end
end

local imageWarned = false
local function renderChunk(key)
	local c = chunks[key]
	if not c then return end
	c.dirty = false
	-- Which cells of this chunk lie on the painted map (computed once). Over the art the chunk
	-- image is only the fog of war, so a chunk entirely on it never needs the server's colours.
	if c.artMask == nil then
		local kx, kz = Config.ParseKey(key)
		local mask, any, all = buffer.create(CHUNK * CHUNK), false, true
		for row = 0, CHUNK - 1 do
			for col = 0, CHUNK - 1 do
				if Config.CellHasArt(kx * CHUNK + col, kz * CHUNK + row) then
					buffer.writeu8(mask, row * CHUNK + col, 1)
					any = true
				else
					all = false
				end
			end
		end
		c.artMask = any and mask or false
		c.allArt = any and all
	end
	local visible = anyBit(c.bits) or c.defaultMask ~= nil
	-- A chunk on the painted map always renders: unexplored, it's solid fog over the art.
	if not visible and not c.artMask then
		-- Nothing shown here (any more, after a reset): clear what the image may still hold.
		if c.image then c.image:WritePixelsBuffer(Vector2.zero, Vector2.new(CHUNK, CHUNK), buffer.create(CHUNK * CHUNK * 4)) end
		return
	end
	if not c.colours and not c.allArt then
		c.wantsColours = true
		if not c.artMask then return end -- part art: draw the fog now, the coloured part when they come
	end
	if not c.image then
		local ok, img = pcall(function() return AssetService:CreateEditableImage({ Size = Vector2.new(CHUNK, CHUNK) }) end)
		if not ok or not img then
			if not imageWarned then imageWarned = true; warn("[Minimap] could not create a map image: " .. tostring(img)) end
			return
		end
		c.image = img
		local content = Content.fromObject(img)
		miniView:SetChunkImage(key, content)
		bigView:SetChunkImage(key, content)
	end
	-- Stylize once per chunk (blur, colour bands, ink lines), then only re-apply the reveal mask
	-- and soft fog edge on each re-render, which is the cheap part.
	if not c.styled and c.colours then c.styled = MapStyle.Stylize(c.colours, CHUNK) end
	local shown = buffer.create(CHUNK * CHUNK)
	local kx, kz = Config.ParseKey(key)
	for row = 0, CHUNK - 1 do
		for col = 0, CHUNK - 1 do
			local index = Config.BitIndex(kx * CHUNK + col, kz * CHUNK + row)
			if Config.GetBit(c.bits, index) or (c.defaultMask ~= nil and Config.GetBit(c.defaultMask, index)) then
				buffer.writeu8(shown, row * CHUNK + col, 1)
			end
		end
	end
	local pixels = buffer.create(CHUNK * CHUNK * 4)
	if c.styled then MapStyle.Compose(c.styled, shown, pixels, CHUNK) end
	if c.artMask then
		-- On the painted map: explored = see-through (the art shows), unexplored = fog.
		local fr, fg, fb = math.floor(MapStyle.FOG.R * 255 + .5), math.floor(MapStyle.FOG.G * 255 + .5), math.floor(MapStyle.FOG.B * 255 + .5)
		for i = 0, CHUNK * CHUNK - 1 do
			if buffer.readu8(c.artMask, i) == 1 then
				local at = i * 4
				if buffer.readu8(shown, i) == 1 then
					buffer.writeu32(pixels, at, 0)
				else
					buffer.writeu8(pixels, at, fr); buffer.writeu8(pixels, at + 1, fg); buffer.writeu8(pixels, at + 2, fb); buffer.writeu8(pixels, at + 3, 255)
				end
			end
		end
	end
	c.image:WritePixelsBuffer(Vector2.zero, Vector2.new(CHUNK, CHUNK), pixels)
end

-- Colours for every visible chunk that still lacks them, a batch at a time.
local fetching = false
local function fetchColours()
	if fetching then return end
	local keys = {}
	for key, c in pairs(chunks) do
		if c.wantsColours and not c.colours and not c.requested then
			c.requested = true
			table.insert(keys, key)
			if #keys >= 8 then break end
		end
	end
	if #keys == 0 then return end
	fetching = true
	task.spawn(function()
		local ok, result = pcall(function() return ChunkRequest:InvokeServer(keys) end)
		fetching = false
		for _, key in ipairs(keys) do
			local c = chunks[key]
			local buf = ok and type(result) == "table" and result[key]
			if c and typeof(buf) == "buffer" then
				c.colours = buf
				c.styled = nil
				c.wantsColours = false
				markDirty(key)
			elseif c then
				c.requested = false -- try again later
			end
		end
	end)
end

-------------------------------------------------------------------------------------------------
-- Zones, bounds, saved state

local function setZones(list)
	zones = type(list) == "table" and list or {}
	table.clear(labelCache)
	bounds = Config.CellBounds(zones)
	miniView:SetBounds(bounds)
	bigView:SetBounds(bounds)
	miniView:SetWorldArt(Config.WorldArt.Regions)
	bigView:SetWorldArt(Config.WorldArt.Regions)
	for _, zone in ipairs(zones) do
		if Config.DefaultDiscovered[zone.name] then discovered[zone.id] = true end
	end
	if bounds then
		local kx0, kz0 = Config.ChunkOfCell(bounds.x0, bounds.z0)
		local kx1, kz1 = Config.ChunkOfCell(bounds.x1, bounds.z1)
		for kx = kx0, kx1 do
			for kz = kz0, kz1 do
				chunkEntry(Config.ChunkKey(kx, kz))
			end
		end
	end
	refreshMasks()
	for key in pairs(chunks) do markDirty(key) end
	rebuildZones()
end

ZoneStateBroadcast.OnClientEvent:Connect(function(snapshot)
	if type(snapshot) == "table" then setZones(snapshot.zones) end
end)

local function loadSavedState()
	local ok2, state = pcall(function() return StateRequest:InvokeServer() end)
	if ok2 and type(state) == "table" then
		for id, on in pairs(state.discovered or {}) do
			if on then discovered[id] = true end
		end
		for key, buf in pairs(state.revealed or {}) do
			if typeof(buf) == "buffer" and buffer.len(buf) == BYTES and Config.ParseKey(key) then
				local c = chunkEntry(key)
				-- Merge (the client may already have revealed some cells locally).
				for i = 0, BYTES - 1 do
					buffer.writeu8(c.bits, i, bit32.bor(buffer.readu8(c.bits, i), buffer.readu8(buf, i)))
				end
				markDirty(key)
			end
		end
		refreshMasks()
		rebuildZones()
		if markers then markers:Load(state.markers, state.tracked) end
	end
end

task.spawn(function()
	local ok, snapshot = pcall(function() return ZoneStateRequest:InvokeServer() end)
	if ok and type(snapshot) == "table" then setZones(snapshot.zones) end
	loadSavedState()
end)

ZoneEntryNotify.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" or payload.discovered ~= true or type(payload.zoneId) ~= "string" then return end
	if discovered[payload.zoneId] then return end
	discovered[payload.zoneId] = true
	local zone
	for _, z in ipairs(zones) do
		if z.id == payload.zoneId then zone = z break end
	end
	if zone and Config.AutoRevealAlignments[zone.alignment] then refreshMasks() end
	rebuildZones()
	miniView:Glow(payload.zoneId)
	bigView:Glow(payload.zoneId)
	if zone then DiscoveryPeek.Play(zone) end
end)

-- Dev reset (F8 MAP tab): forget everything locally, then reload what the server now has.
-- Colours stay cached: the world didn't change.
ResetEvent.OnClientEvent:Connect(function()
	table.clear(discovered)
	for _, zone in ipairs(zones) do
		if Config.DefaultDiscovered[zone.name] then discovered[zone.id] = true end
	end
	for key, c in pairs(chunks) do
		buffer.fill(c.bits, 0, 0)
		markDirty(key)
	end
	refreshMasks()
	rebuildZones()
	task.spawn(loadSavedState)
end)

-------------------------------------------------------------------------------------------------
-- Exploring (local copy of the server's reveal, for instant feedback)

local function revealAround(position)
	Config.ForEachCellInRadius(position.X, position.Z, Config.REVEAL_RADIUS, function(cx, cz)
		if not Config.CellInBounds(bounds, cx, cz) then return end
		local kx, kz = Config.ChunkOfCell(cx, cz)
		local key = Config.ChunkKey(kx, kz)
		if Config.SetBit(chunkEntry(key).bits, Config.BitIndex(cx, cz)) then markDirty(key) end
	end)
end

-------------------------------------------------------------------------------------------------
-- Expanded map: open/close, zoom, drag

local isOpen = false
local releaseHud          -- HudHider release while the expanded map is open
local bigScale = 2
local panX, panZ          -- map cell at the centre of the expanded view (nil = follow player)
local pin                 -- { x, z } in map cells while a WorldMapRequest pin is shown

-- The pin another screen asked for (WorldMapRequest.ShowAt): a gold General pin badge and a
-- parchment slip with its label (Minimap/MapNote), drawn over the expanded map until it closes.
local MapNote = require(script:WaitForChild("MapNote"))
local pinMarker = Instance.new("Frame")
pinMarker.Name = "RequestPin"
pinMarker.AnchorPoint = Vector2.new(.5, .5)
pinMarker.Size = UDim2.fromOffset(24, 24)
pinMarker.BackgroundTransparency = 1
pinMarker.Visible = false
pinMarker.ZIndex = 12
pinMarker.Parent = bigView.clip
MapView.BuildPlayerMarkerBadge(pinMarker, { id = "General", ring = Color3.fromRGB(214, 172, 84) }, 12)
local pinLabel = Instance.new("Frame")
pinLabel.Name = "RequestPinLabel"
pinLabel.AnchorPoint = Vector2.new(.5, 1)
pinLabel.Size = UDim2.fromOffset(0, 28)
pinLabel.AutomaticSize = Enum.AutomaticSize.X
pinLabel.BackgroundTransparency = 1
pinLabel.Visible = false
pinLabel.ZIndex = 12
pinLabel.Parent = bigView.clip
MapNote.Backing(pinLabel, MapUI.NOTE, .1, 12)
local pinText = MapNote.Label({
	Name = "Text", Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
	FontFace = MapNote.FONT.Heading, TextSize = 14, TextColor3 = MapNote.INK.Heading, ZIndex = 13,
}, pinLabel)
do
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight, pad.PaddingTop = UDim.new(0, 14), UDim.new(0, 12), UDim.new(0, 3)
	pad.Parent = pinText
end
local dragging, dragFrom, dragPan

local function fitScale()
	if not bounds then return 2 end
	local size = big.AbsoluteSize
	local sx = size.X / (bounds.x1 - bounds.x0 + 1)
	local sz = size.Y / (bounds.z1 - bounds.z0 + 1)
	return math.clamp(math.min(sx, sz) * .95, Config.BigMinScale, Config.BigMaxScale)
end

local function setOpen(open)
	if open == isOpen then return end
	-- The expanded map is a BLOCKING overlay (InteractionLock): while it's up, menu hotkeys
	-- (Tab, P, the settings gear) stand down and any open menu closes; gameplay binds still work.
	-- It won't open over another blocking overlay (the Enchanting Station, a cleanse channel).
	if open and InteractionLock.IsHeldByOther(LOCK_OWNER) then return end
	isOpen = open
	big.Visible = open
	if open then
		InteractionLock.Acquire(LOCK_OWNER)
		-- Everything else steps back (the minimap, the quick-nav row, the hotbar...), as behind
		-- the Tab menu; overlays (vitals, centre flashes) stay up.
		releaseHud = HudHider.Acquire(bigGui, { keepOverlays = true, keepCore = true })
		QuickNav.HideTip()
	else
		InteractionLock.Release(LOCK_OWNER)
		if releaseHud then releaseHud(); releaseHud = nil end
	end
	if open then
		panX, panZ = nil, nil
		bigScale = math.clamp(math.max(fitScale(), 2), Config.BigMinScale, Config.BigMaxScale)
		bigView:SetScale(bigScale)
		MenuMouse.acquire()
	else
		dragging = false
		if markers then markers:OnClosed() end
		pin = nil
		pinMarker.Visible, pinLabel.Visible = false, false
		MenuMouse.release()
	end
end

-- The minimap names itself with its key on hover, and a click opens the M map (when the cursor
-- is free: in a menu, or Ctrl).
mini.Active = true
mini.MouseEnter:Connect(function()
	QuickNav.ShowTip("World map", Keys.ToggleMap, mini.AbsolutePosition, mini.AbsoluteSize)
end)
mini.MouseLeave:Connect(QuickNav.HideTip)
mini.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		QuickNav.HideTip()
		setOpen(true)
	end
end)

-- Another screen (the Journal's "Show on map") asks for a spot: open centred on it, pinned.
WorldMapRequest.Listen(function(position, label)
	if not bounds then return end
	setOpen(true)
	if not isOpen then return end -- refused (another blocking overlay is up)
	pin = { x = position.X / CELL, z = position.Z / CELL }
	panX, panZ = pin.x, pin.z
	pinText.Text = label or ""
	pinLabel.Visible = (label or "") ~= ""
	pinMarker.Visible = true
end)

-- Another blocking overlay took over (a station, a cutscene lock): close the map.
InteractionLock.Subscribe(function(locked)
	if locked and isOpen and InteractionLock.IsHeldByOther(LOCK_OWNER) then setOpen(false) end
end)

-- The map cell at the middle of the expanded view (following you unless panned).
local function viewCentre()
	if panX then return panX, panZ end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then return root.Position.X / CELL, root.Position.Z / CELL end
	return nil, nil
end

-- The map cell under a point (input / AbsolutePosition space) on the expanded map.
local function cellAt(point)
	local cx, cz = viewCentre()
	if not cx then return nil end
	local clip = bigView.clip
	local centre = clip.AbsolutePosition + clip.AbsoluteSize / 2
	return Vector2.new(cx + (point.X - centre.X) / bigScale, cz + (point.Y - centre.Y) / bigScale)
end

-- Zooms by `steps` notches. With `point` (the cursor), the ground under it stays put, like
-- every map app; without one, around the middle.
local function zoom(steps, point)
	local old = bigScale
	bigScale = math.clamp(bigScale * Config.ZoomStep ^ steps, Config.BigMinScale, Config.BigMaxScale)
	if point and bigScale ~= old then
		local cx, cz = viewCentre()
		if cx then
			local clip = bigView.clip
			local d = point - (clip.AbsolutePosition + clip.AbsoluteSize / 2)
			panX = cx + d.X / old - d.X / bigScale
			panZ = cz + d.Y / old - d.Y / bigScale
		end
	end
	bigView:SetScale(bigScale)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if input.UserInputType == Enum.UserInputType.Keyboard then
		if processed then return end
		if input.KeyCode == Keys.ToggleMap then
			if bounds then setOpen(not isOpen) end
		elseif isOpen and input.KeyCode == Keys.CloseMenu then
			if not (markers and markers:HandleEscape()) then setOpen(false) end
		elseif isOpen and input.KeyCode == Keys.MapRecentre then
			panX, panZ = nil, nil
		elseif isOpen and Keys.Matches(Keys.MapZoomIn, input.KeyCode) then
			zoom(1)
		elseif isOpen and Keys.Matches(Keys.MapZoomOut, input.KeyCode) then
			zoom(-1)
		end
	end
end)

bigView.clip.InputBegan:Connect(function(input)
	if markers and markers:Covers(Vector2.new(input.Position.X, input.Position.Y)) then return end -- a panel, not the ground
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragFrom = Vector2.new(input.Position.X, input.Position.Y)
		dragPan = nil
	end
end)
bigView.clip.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseWheel and isOpen then
		local point = UserInputService:GetMouseLocation() - Vector2.new(0, game:GetService("GuiService"):GetGuiInset().Y)
		zoom(input.Position.Z > 0 and 1 or -1, point)
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		local now = Vector2.new(input.Position.X, input.Position.Y)
		if not dragPan then
			if (now - dragFrom).Magnitude < 4 then return end
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local px, pz = panX, panZ
			if not px and root then px, pz = root.Position.X / CELL, root.Position.Z / CELL end
			dragPan = Vector2.new(px or 0, pz or 0)
		end
		local delta = (now - dragFrom) / bigScale
		panX, panZ = dragPan.X - delta.X, dragPan.Y - delta.Y
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end)

-------------------------------------------------------------------------------------------------
-- NPC markers (RS/NpcMapMarkers): drawn only where the map is uncovered, so an unexplored
-- town keeps its NPCs to itself. Re-checked on every reveal tick; the views are only touched
-- when the visible set changes.

local function cellShown(cx, cz)
	local c = chunks[Config.ChunkKey(Config.ChunkOfCell(cx, cz))]
	if not c then return false end
	local index = Config.BitIndex(cx, cz)
	return Config.GetBit(c.bits, index) or (c.defaultMask ~= nil and Config.GetBit(c.defaultMask, index))
end

local npcMarkerKey
local npcsVisible = true -- the legend's NPCs toggle (PlayerMarkers)
local function refreshNpcMarkers()
	if not bounds then return end
	local list, keys = {}, {}
	for _, entry in ipairs(npcsVisible and NpcMapMarkers.List() or {}) do
		local x, z = entry.position.X / CELL, entry.position.Z / CELL
		local cx, cz = math.floor(x), math.floor(z)
		if Config.CellInBounds(bounds, cx, cz) and cellShown(cx, cz) then
			table.insert(list, { id = entry.id, x = x, z = z, name = entry.name, icon = entry.icon, npcType = entry.npcType })
			table.insert(keys, ("%s@%d,%d"):format(entry.id, cx, cz))
		end
	end
	table.sort(keys)
	local key = table.concat(keys, "|")
	if key == npcMarkerKey then return end
	npcMarkerKey = key
	miniView:SetNpcMarkers(list)
	bigView:SetNpcMarkers(list)
end
NpcMapMarkers.Changed:Connect(refreshNpcMarkers)

-------------------------------------------------------------------------------------------------
-- Player markers (Minimap/PlayerMarkers)

markers = PlayerMarkers.new({
	big = big,
	bigView = bigView,
	miniView = miniView,
	remote = MarkerAction,
	getScale = function() return bigScale end,
	getBounds = function() return bounds end,
	isOpen = function() return isOpen end,
	cellAt = cellAt,
	recentre = function() panX, panZ = nil, nil end,
	setNpcsVisible = function(visible)
		npcsVisible = visible
		npcMarkerKey = nil
		refreshNpcMarkers()
	end,
})

-------------------------------------------------------------------------------------------------
-- Frame loop

-- Other players near you (Config.OtherPlayerRadius), in map cells. Just positions and facing:
-- no names on the map.
local others = {}
local function collectOthers(rootPosition)
	table.clear(others)
	local radius = Config.OtherPlayerRadius
	for _, other in ipairs(Players:GetPlayers()) do
		local character = other ~= player and other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - rootPosition).Magnitude <= radius then
			table.insert(others, { x = root.Position.X / CELL, z = root.Position.Z / CELL, look = root.CFrame.LookVector })
		end
	end
	return others
end

local nextReveal = 0
RunService.RenderStepped:Connect(function()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local inWorld = false
	local px, pz, look
	if root and bounds then
		px, pz = root.Position.X / CELL, root.Position.Z / CELL
		inWorld = Config.CellInBounds(bounds, math.floor(px), math.floor(pz))
		look = root.CFrame.LookVector
	end

	mini.Visible = inWorld
	if isOpen and not inWorld then setOpen(false) end

	local now = os.clock()
	if inWorld and now >= nextReveal then
		nextReveal = now + Config.CLIENT_TICK
		revealAround(root.Position)
		refreshNpcMarkers()
	end

	for _ = 1, RENDERS_PER_FRAME do
		local key = table.remove(renderQueue, 1)
		if not key then break end
		queued[key] = nil
		renderChunk(key)
	end
	fetchColours()

	if inWorld then
		miniView:Update(px, pz, px, pz, look)
		local near = collectOthers(root.Position)
		miniView:SetOthers(px, pz, near, Config.OtherPlayerColor)
		if isOpen then
			local cx, cz = panX or px, panZ or pz
			bigView:Update(cx, cz, px, pz, look)
			bigView:SetOthers(cx, cz, near, Config.OtherPlayerColor)
			if pin then
				local s = bigView.scale
				local at = UDim2.new(.5, (pin.x - cx) * s, .5, (pin.z - cz) * s)
				pinMarker.Position = at
				pinLabel.Position = at + UDim2.fromOffset(0, -18)
			end
		end
		markers:Update(px, pz, panX or px, panZ or pz)
	else
		markers:Update(nil, nil, nil, nil) -- off the map (a dungeon realm): no pointers, no beacon
	end
end)
