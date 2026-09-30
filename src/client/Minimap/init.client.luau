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
local LOCK_OWNER = "WorldMap"
local MapView = require(script:WaitForChild("MapView"))
local DiscoveryPeek = require(script:WaitForChild("DiscoveryPeek"))

local GameEvents = ReplicatedStorage:WaitForChild("GameEvents")
local ZoneStateRequest = GameEvents:WaitForChild("ZoneStateRequest")
local ZoneStateBroadcast = GameEvents:WaitForChild("ZoneStateBroadcast")
local ZoneEntryNotify = GameEvents:WaitForChild("ZoneEntryNotify")
local StateRequest = GameEvents:WaitForChild("MinimapStateRequest")
local ChunkRequest = GameEvents:WaitForChild("MinimapChunkRequest")
local ResetEvent = GameEvents:WaitForChild("MinimapReset")

local player = Players.LocalPlayer
local CHUNK, CELL = Config.CHUNK, Config.CELL
local BYTES = Config.BYTES_PER_CHUNK
local RENDERS_PER_FRAME = 3

local PANEL = Color3.fromRGB(14, 13, 16)
local EDGE = Color3.fromRGB(70, 66, 60)
local TEXT = Color3.fromRGB(226, 220, 204)
local MUTED = Color3.fromRGB(150, 144, 132)

-------------------------------------------------------------------------------------------------
-- State

local zones = {}
local bounds
local discovered = {}      -- [zoneId] = true
local chunks = {}          -- [key] = { bits, defaultMask, colours, image, dirty, requested }
local renderQueue = {}     -- keys, in order
local queued = {}
local labelCache = {}      -- [zoneId] = { x, z }

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

-- Corner minimap
local mini = Instance.new("Frame")
mini.Name = "Minimap"
mini.AnchorPoint = Vector2.new(1, 0)
mini.Position = UDim2.new(1, -QuickNav.MARGIN, 0, QuickNav.MARGIN) -- the very top-right corner
mini.Size = UDim2.fromOffset(Config.MiniSize, Config.MiniSize)
mini.BackgroundColor3 = PANEL
mini.BorderSizePixel = 0
mini.Visible = false
mini.Parent = gui
stroke(mini, EDGE, 2)
local miniView = MapView.new(mini, { scale = Config.MiniScale, labelScale = 5, labelMin = 10, labelMax = 14 })

-- "[M] Map", inside the map's bottom-right corner on a soft dark pill so it reads over any
-- ground colour.
local miniHint = Instance.new("TextLabel")
miniHint.Name = "Hint"
miniHint.AnchorPoint = Vector2.new(1, 1)
miniHint.Position = UDim2.new(1, -5, 1, -5)
miniHint.Size = UDim2.fromOffset(0, 18)
miniHint.AutomaticSize = Enum.AutomaticSize.X
miniHint.BackgroundColor3 = Color3.new(0, 0, 0)
miniHint.BackgroundTransparency = .45
miniHint.BorderSizePixel = 0
miniHint.Font = Enum.Font.GothamBold
miniHint.TextSize = 12
miniHint.TextColor3 = Color3.fromRGB(245, 243, 238)
miniHint.TextStrokeTransparency = .55
miniHint.Text = "[" .. Keys.ToggleMap.Name .. "] Map"
miniHint.ZIndex = 5
miniHint.Parent = mini
local hintCorner = Instance.new("UICorner")
hintCorner.CornerRadius = UDim.new(0, 4)
hintCorner.Parent = miniHint
local hintPadding = Instance.new("UIPadding")
hintPadding.PaddingLeft, hintPadding.PaddingRight = UDim.new(0, 6), UDim.new(0, 6)
hintPadding.Parent = miniHint

-- The quick-nav buttons (settings, ...) hang under the minimap's bottom-left corner.
QuickNav.FollowBelow(mini)

-- Expanded map
local big = Instance.new("Frame")
big.Name = "WorldMap"
big.AnchorPoint = Vector2.new(.5, .5)
big.Position = UDim2.fromScale(.5, .5)
big.Size = UDim2.fromScale(.78, .82)
big.BackgroundColor3 = PANEL
big.BorderSizePixel = 0
big.Visible = false
big.Active = true
big.Parent = gui
stroke(big, EDGE, 3)
local bigView = MapView.new(big, { scale = 2, labelScale = 7, labelMin = 12, labelMax = 40 })
bigView.clip.Active = true

local hints = Instance.new("Frame")
hints.Name = "Hints"
hints.AnchorPoint = Vector2.new(1, 1)
hints.Position = UDim2.new(1, -12, 1, -12)
hints.Size = UDim2.fromOffset(260, 60)
hints.BackgroundColor3 = PANEL
hints.BackgroundTransparency = .15
hints.BorderSizePixel = 0
hints.ZIndex = 20
hints.Parent = big
stroke(hints, EDGE, 1)
local hintLayout = Instance.new("UIListLayout")
hintLayout.Padding = UDim.new(0, 4)
hintLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
hintLayout.Parent = hints
local hintPad = Instance.new("UIPadding")
hintPad.PaddingTop, hintPad.PaddingBottom = UDim.new(0, 6), UDim.new(0, 6)
hintPad.PaddingLeft, hintPad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
hintPad.Parent = hints

local function keyName(binding)
	local k = typeof(binding) == "EnumItem" and binding or binding[1]
	return ({ Equals = "+", Minus = "-" })[k.Name] or k.Name
end

local function hintRow(text, order)
	local row = Instance.new("TextLabel")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 20)
	row.Font = Enum.Font.GothamMedium
	row.TextSize = 14
	row.TextColor3 = TEXT
	row.TextXAlignment = Enum.TextXAlignment.Right
	row.RichText = true
	row.Text = text
	row.LayoutOrder = order
	row.ZIndex = 21
	row.Parent = hints
	return row
end
hintRow(("Zoom  <font color=\"#968F84\">[Scroll]  [%s]  [%s]</font>"):format(keyName(Keys.MapZoomIn), keyName(Keys.MapZoomOut)), 1)
hintRow(("Close  <font color=\"#968F84\">[%s]</font>"):format(Keys.ToggleMap.Name), 2)

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
	local visible = anyBit(c.bits) or c.defaultMask ~= nil
	if not visible then
		-- Nothing shown here (any more, after a reset): clear what the image may still hold.
		if c.image then c.image:WritePixelsBuffer(Vector2.zero, Vector2.new(CHUNK, CHUNK), buffer.create(CHUNK * CHUNK * 4)) end
		return
	end
	if not c.colours then
		c.wantsColours = true
		return
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
	local pixels = buffer.create(CHUNK * CHUNK * 4)
	local kx, kz = Config.ParseKey(key)
	for row = 0, CHUNK - 1 do
		for col = 0, CHUNK - 1 do
			local index = Config.BitIndex(kx * CHUNK + col, kz * CHUNK + row)
			local shown = Config.GetBit(c.bits, index) or (c.defaultMask ~= nil and Config.GetBit(c.defaultMask, index))
			if shown then
				local src = (row * CHUNK + col) * 3
				local dst = (row * CHUNK + col) * 4
				buffer.writeu8(pixels, dst, buffer.readu8(c.colours, src))
				buffer.writeu8(pixels, dst + 1, buffer.readu8(c.colours, src + 1))
				buffer.writeu8(pixels, dst + 2, buffer.readu8(c.colours, src + 2))
				buffer.writeu8(pixels, dst + 3, 255)
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
local bigScale = 2
local panX, panZ          -- map cell at the centre of the expanded view (nil = follow player)
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
	else
		InteractionLock.Release(LOCK_OWNER)
	end
	if open then
		panX, panZ = nil, nil
		bigScale = math.clamp(math.max(fitScale(), 2), Config.BigMinScale, Config.BigMaxScale)
		bigView:SetScale(bigScale)
		MenuMouse.acquire()
	else
		dragging = false
		MenuMouse.release()
	end
end

-- Another blocking overlay took over (a station, a cutscene lock): close the map.
InteractionLock.Subscribe(function(locked)
	if locked and isOpen and InteractionLock.IsHeldByOther(LOCK_OWNER) then setOpen(false) end
end)

local function zoom(steps)
	bigScale = math.clamp(bigScale * Config.ZoomStep ^ steps, Config.BigMinScale, Config.BigMaxScale)
	bigView:SetScale(bigScale)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if input.UserInputType == Enum.UserInputType.Keyboard then
		if processed then return end
		if input.KeyCode == Keys.ToggleMap then
			if bounds then setOpen(not isOpen) end
		elseif isOpen and input.KeyCode == Keys.CloseMenu then
			setOpen(false)
		elseif isOpen and Keys.Matches(Keys.MapZoomIn, input.KeyCode) then
			zoom(1)
		elseif isOpen and Keys.Matches(Keys.MapZoomOut, input.KeyCode) then
			zoom(-1)
		end
	end
end)

bigView.clip.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragFrom = Vector2.new(input.Position.X, input.Position.Y)
		dragPan = nil
	end
end)
bigView.clip.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseWheel and isOpen then
		zoom(input.Position.Z > 0 and 1 or -1)
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
-- Frame loop

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
		if isOpen then
			bigView:Update(panX or px, panZ or pz, px, pz, look)
		end
	end
end)
