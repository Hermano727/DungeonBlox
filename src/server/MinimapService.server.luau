--[[
	MinimapService -- the server side of the world map (client: StarterPlayerScripts/Minimap).

	  Discovery   first entry into a zone marks it discovered (profile.map.discovered[zoneId]);
	              ZoneService's entry banner then carries discovered = true. Zones named in
	              MinimapConfig.DefaultDiscovered (Oakhaven) are discovered from the start.
	  Exploring   every SERVER_TICK, the cells within REVEAL_RADIUS of each player are marked in
	              per-chunk bitsets, saved as base64 in profile.map.revealed[chunkKey]. The
	              client does the same locally for instant feedback; this is the saved copy.
	  Colours     MinimapChunkRequest: a chunk's colours, raycast top-down per cell on first
	              request and cached for the server's lifetime (so the map shows whatever is
	              built, no bake step). Height shading like a Minecraft map: a cell higher than
	              the one north of it is lighter, lower is darker.

	Remotes (ReplicatedStorage.GameEvents):
	  MinimapStateRequest  RF  -> { discovered = { [zoneId] = true }, revealed = { [key] = buffer } }
	  MinimapChunkRequest  RF  (keys) -> { [key] = buffer of CHUNK*CHUNK*3 bytes RGB }
	  MinimapDevAction     RF  ("reset") -> ok, err   dev-only (DevRoster): wipes YOUR map
	  MinimapReset         RE  S -> C: the map was reset; the client forgets and reloads

	A part can pick its own map colour with a Color3 attribute "MapColor" (on it or any ancestor
	Model); textured meshes otherwise fall back to a colour for their Material.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("MinimapConfig"))
local ZoneService = require(ServerScriptService:WaitForChild("ZoneService"))
local ProfileService = require(ServerScriptService:WaitForChild("ProfileService"))
local DevRoster = require(ReplicatedStorage:WaitForChild("DevRoster"))

local CHUNK, CELL = Config.CHUNK, Config.CELL
local BYTES = Config.BYTES_PER_CHUNK
local RAY_TOP, RAY_DEPTH = 1500, 3000
local MAX_KEYS_PER_REQUEST = 16

local GameEvents = ReplicatedStorage:WaitForChild("GameEvents")
local function remoteFunction(name)
	local rf = GameEvents:FindFirstChild(name)
	if rf and not rf:IsA("RemoteFunction") then rf:Destroy(); rf = nil end
	if not rf then
		rf = Instance.new("RemoteFunction")
		rf.Name = name
		rf.Parent = GameEvents
	end
	return rf
end
local StateRequest = remoteFunction("MinimapStateRequest")
local ChunkRequest = remoteFunction("MinimapChunkRequest")
local DevAction = remoteFunction("MinimapDevAction")
local ResetEvent = GameEvents:FindFirstChild("MinimapReset")
if not ResetEvent then
	ResetEvent = Instance.new("RemoteEvent")
	ResetEvent.Name = "MinimapReset"
	ResetEvent.Parent = GameEvents
end

-------------------------------------------------------------------------------------------------
-- Zones / bounds

local function zones()
	local out = {}
	for _, zone in ipairs(ZoneService.GetAllZones()) do table.insert(out, zone) end
	return out
end

local function bounds()
	return Config.CellBounds(zones())
end

-------------------------------------------------------------------------------------------------
-- Per-player map state (bitsets live decoded here; the profile holds their base64)

local states = {} -- [player] = { profile, chunks = { [key] = buffer }, dirty = { [key] = true } }

local function mapOf(profile)
	profile.map = type(profile.map) == "table" and profile.map or {}
	local map = profile.map
	map.discovered = type(map.discovered) == "table" and map.discovered or {}
	map.revealed = type(map.revealed) == "table" and map.revealed or {}
	return map
end

local function stateFor(player)
	local profile = ProfileService.Get(player)
	if not profile then return nil end
	local st = states[player]
	if st and st.profile == profile then return st end
	local map = mapOf(profile)
	st = { profile = profile, map = map, chunks = {}, dirty = {} }
	for key, text in pairs(map.revealed) do
		if type(key) == "string" and Config.ParseKey(key) then
			st.chunks[key] = Config.DecodeToBuffer(text, BYTES)
		end
	end
	for _, zone in ipairs(ZoneService.GetAllZones()) do
		if Config.DefaultDiscovered[zone.name] then map.discovered[zone.id] = true end
	end
	states[player] = st
	return st
end

-- Records a first entry. Returns true only the first time.
local function discover(player, zone)
	local st = stateFor(player)
	if not st or not zone or type(zone.id) ~= "string" then return false end
	if Config.DefaultDiscovered[zone.name] then st.map.discovered[zone.id] = true return false end
	if st.map.discovered[zone.id] then return false end
	st.map.discovered[zone.id] = true
	return true
end

ZoneService.SetDiscoveryHandler(discover)

local function revealAround(st, position, box)
	Config.ForEachCellInRadius(position.X, position.Z, Config.REVEAL_RADIUS, function(cx, cz)
		if not Config.CellInBounds(box, cx, cz) then return end
		local kx, kz = Config.ChunkOfCell(cx, cz)
		local key = Config.ChunkKey(kx, kz)
		local buf = st.chunks[key]
		if not buf then
			buf = buffer.create(BYTES)
			st.chunks[key] = buf
		end
		if Config.SetBit(buf, Config.BitIndex(cx, cz)) then st.dirty[key] = true end
	end)
	for key in pairs(st.dirty) do
		st.map.revealed[key] = Config.EncodeBuffer(st.chunks[key])
	end
	table.clear(st.dirty)
end

task.spawn(function()
	local notify = ZoneService.GetEntryNotifyRemote()
	while true do
		task.wait(Config.SERVER_TICK)
		local box = bounds()
		if box then
			for _, player in ipairs(Players:GetPlayers()) do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				local st = root and stateFor(player)
				if st then
					revealAround(st, root.Position, box)
					-- Standing in a zone the entry banner missed (entered before the profile had
					-- loaded): discover it now, on the same remote the banner listens to.
					for _, zone in ipairs(ZoneService.GetZonesAtPoint(root.Position)) do
						if discover(player, zone) then
							notify:FireClient(player, {
								zoneId = zone.id, zoneName = zone.name, zoneAlignment = zone.alignment, discovered = true,
							})
						end
					end
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player) states[player] = nil end)

-- F8 MAP tab. Wipes the caller's own discoveries and explored cells (the defaults come back
-- on the next stateFor); the reveal loop then re-discovers whatever zone they stand in.
DevAction.OnServerInvoke = function(player, action)
	if not DevRoster.IsDev(player) then return false, "not a dev" end
	if action ~= "reset" then return false, "unknown action" end
	local profile = ProfileService.Get(player)
	if not profile then return false, "profile not loaded" end
	profile.map = { discovered = {}, revealed = {} }
	states[player] = nil
	ResetEvent:FireClient(player)
	return true
end

StateRequest.OnServerInvoke = function(player)
	local deadline = os.clock() + 20
	local st = stateFor(player)
	while not st and os.clock() < deadline and player.Parent do
		task.wait(.5)
		st = stateFor(player)
	end
	if not st then return nil end
	local discovered, revealed = {}, {}
	for id, on in pairs(st.map.discovered) do
		if on == true and type(id) == "string" then discovered[id] = true end
	end
	for key, buf in pairs(st.chunks) do revealed[key] = buf end
	return { discovered = discovered, revealed = revealed }
end

-------------------------------------------------------------------------------------------------
-- Colours

local TEXTURED_COLORS = { -- by Material, for meshes whose look comes from a texture
	[Enum.Material.Grass] = Color3.fromRGB(88, 128, 60),
	[Enum.Material.LeafyGrass] = Color3.fromRGB(84, 120, 58),
	[Enum.Material.Ground] = Color3.fromRGB(110, 90, 64),
	[Enum.Material.Mud] = Color3.fromRGB(84, 68, 50),
	[Enum.Material.Sand] = Color3.fromRGB(190, 172, 128),
	[Enum.Material.Rock] = Color3.fromRGB(110, 108, 104),
	[Enum.Material.Slate] = Color3.fromRGB(92, 94, 96),
	[Enum.Material.Cobblestone] = Color3.fromRGB(118, 116, 110),
	[Enum.Material.Concrete] = Color3.fromRGB(128, 126, 122),
	[Enum.Material.Brick] = Color3.fromRGB(132, 78, 60),
	[Enum.Material.Wood] = Color3.fromRGB(110, 80, 52),
	[Enum.Material.WoodPlanks] = Color3.fromRGB(122, 90, 58),
	[Enum.Material.Metal] = Color3.fromRGB(96, 98, 104),
	[Enum.Material.CorrodedMetal] = Color3.fromRGB(96, 76, 62),
	[Enum.Material.Fabric] = Color3.fromRGB(120, 100, 84),
}
local TEXTURED_FALLBACK = Color3.fromRGB(116, 112, 104)

local terrain = Workspace.Terrain
local function terrainColor(material)
	if material == Enum.Material.Water then
		local c = terrain.WaterColor
		return Color3.new(c.R * .75, c.G * .75, c.B * .9)
	end
	local ok, c = pcall(terrain.GetMaterialColor, terrain, material)
	return ok and c or TEXTURED_FALLBACK
end

local function mapColorAttribute(part)
	local c = part:GetAttribute("MapColor")
	if typeof(c) == "Color3" then return c end
	local model = part:FindFirstAncestorWhichIsA("Model")
	while model do
		c = model:GetAttribute("MapColor")
		if typeof(c) == "Color3" then return c end
		model = model:FindFirstAncestorWhichIsA("Model")
	end
	return nil
end

-- Imported tree/bush meshes are textured Plastic (their colour is all in the texture): read
-- them as foliage by name. Measured 2026-09-29: most textured hits in the overworld are
-- leaves ("Leaf", "Leaves", "Dogwood Trees 01_Leaf", "bush square", the "Árvore" tree kit).
local FOLIAGE = Color3.fromRGB(58, 92, 44)
local FOLIAGE_WORDS = { "leaf", "leaves", "tree", "bush", "foliage", "flower", "hedge", "rvore", "shrub" }
local function looksLikeFoliage(part)
	local model = part:FindFirstAncestorWhichIsA("Model")
	local text = string.lower(part.Name .. " " .. (model and model.Name or ""))
	for _, word in ipairs(FOLIAGE_WORDS) do
		if string.find(text, word, 1, true) then return true end
	end
	return false
end

local function partColor(part)
	local own = mapColorAttribute(part)
	if own then return own end
	local textured = part:FindFirstChildOfClass("SurfaceAppearance") ~= nil
		or (part:IsA("MeshPart") and part.TextureID ~= "")
	if textured then
		if looksLikeFoliage(part) then return FOLIAGE end
		return TEXTURED_COLORS[part.Material] or TEXTURED_FALLBACK
	end
	return part.Color
end

-- Characters, mobs and NPCs are not the map; neither is anything nearly invisible.
local function skip(part)
	if part.Transparency >= .9 then return true end
	local model = part:FindFirstAncestorWhichIsA("Model")
	while model do
		if model:FindFirstChildOfClass("Humanoid") or model:FindFirstChildOfClass("AnimationController") then return true end
		model = model:FindFirstAncestorWhichIsA("Model")
	end
	return false
end

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.IgnoreWater = false

-- Top surface at (x, z): colour + height (nil height = nothing there).
local function sample(x, z)
	local origin = Vector3.new(x, RAY_TOP, z)
	local down = Vector3.new(0, -RAY_DEPTH, 0)
	for _ = 1, 8 do
		local hit = Workspace:Raycast(origin, down, params)
		if not hit then return nil, nil end
		local part = hit.Instance
		if part == terrain then return terrainColor(hit.Material), hit.Position.Y end
		if not skip(part) then return partColor(part), hit.Position.Y end
		origin = hit.Position - Vector3.new(0, .05, 0)
		down = Vector3.new(0, -(RAY_DEPTH - (RAY_TOP - origin.Y)), 0)
		if down.Y > -1 then return nil, nil end
	end
	return nil, nil
end

local colourCache = {} -- [key] = buffer
local pending = {}     -- [key] = { waiting threads }

local function bakeChunk(key)
	local kx, kz = Config.ParseKey(key)
	local out = buffer.create(CHUNK * CHUNK * 3)
	local cx0, cz0 = kx * CHUNK, kz * CHUNK
	-- Heights including one row north (z - 1) for the shading.
	local heights = {}
	local colours = {}
	local done = 0
	for row = -1, CHUNK - 1 do
		local cz = cz0 + row
		heights[row] = {}
		for col = 0, CHUNK - 1 do
			local cx = cx0 + col
			local colour, height = sample((cx + .5) * CELL, (cz + .5) * CELL)
			heights[row][col] = height
			if row >= 0 then colours[row * CHUNK + col] = colour end
			done += 1
			if done % 512 == 0 then task.wait() end -- spread the raycasts over frames
		end
	end
	for row = 0, CHUNK - 1 do
		for col = 0, CHUNK - 1 do
			local colour = colours[row * CHUNK + col]
			local r, g, b = 0, 0, 0
			if colour then
				local h, north = heights[row][col], heights[row - 1][col]
				local shade = 1
				if h and north then shade = 1 + math.clamp((h - north) / 3, -1, 1) * .18 end
				r = math.clamp(math.floor(colour.R * 255 * shade + .5), 1, 255)
				g = math.clamp(math.floor(colour.G * 255 * shade + .5), 1, 255)
				b = math.clamp(math.floor(colour.B * 255 * shade + .5), 1, 255)
			end
			local at = (row * CHUNK + col) * 3
			buffer.writeu8(out, at, r)
			buffer.writeu8(out, at + 1, g)
			buffer.writeu8(out, at + 2, b)
		end
	end
	return out
end

local function chunkColours(key)
	if colourCache[key] then return colourCache[key] end
	if pending[key] then
		table.insert(pending[key], coroutine.running())
		return coroutine.yield()
	end
	pending[key] = {}
	local ok, result = pcall(bakeChunk, key)
	local buf = ok and result or buffer.create(CHUNK * CHUNK * 3)
	if not ok then warn("[MinimapService] chunk " .. key .. " failed: " .. tostring(result)) end
	colourCache[key] = buf
	local waiting = pending[key]
	pending[key] = nil
	for _, thread in ipairs(waiting) do task.spawn(thread, buf) end
	return buf
end

ChunkRequest.OnServerInvoke = function(_player, keys)
	if type(keys) ~= "table" then return {} end
	local box = bounds()
	local out, count = {}, 0
	for _, key in ipairs(keys) do
		if count >= MAX_KEYS_PER_REQUEST then break end
		local kx, kz
		if type(key) == "string" then kx, kz = Config.ParseKey(key) end
		if kx and kz and box
			and (kx + 1) * CHUNK > box.x0 and kx * CHUNK <= box.x1
			and (kz + 1) * CHUNK > box.z0 and kz * CHUNK <= box.z1 then
			out[key] = chunkColours(key)
			count += 1
		end
	end
	return out
end
