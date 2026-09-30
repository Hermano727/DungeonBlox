--[[
	MinimapConfig -- the world map's grid, tuning and the maths both sides share.

	The map is a fixed world grid of CELL-stud cells (one map pixel each), grouped into
	CHUNK x CHUNK chunks. Each chunk is one image on the client and one bitset of explored
	cells in the profile (profile.map.revealed[chunkKey] = base64 of CHUNK*CHUNK/8 bytes).
	Colours come from the server raycasting the world top-down per cell (SSS/MinimapService),
	so the map follows whatever is built without a re-bake step.

	Only the area around the zones exists on the map (their bounding box + BOUNDS_MARGIN), so
	the dungeon realms far away never create chunks.

	Server (MinimapService) and client (Minimap) both reveal cells within REVEAL_RADIUS of
	the player: the client for instant feedback, the server for what is saved. They use the
	same functions below, so they agree.
]]

local MinimapConfig = {}

MinimapConfig.CELL = 4            -- studs per map pixel
MinimapConfig.CHUNK = 64          -- cells per chunk side (one 64x64 image, 256 studs)
MinimapConfig.REVEAL_RADIUS = 48  -- studs around the player that get explored as you walk
MinimapConfig.BOUNDS_MARGIN = 200 -- studs of map around the zones' bounding box
MinimapConfig.SERVER_TICK = 0.5   -- server reveal / save cadence
MinimapConfig.CLIENT_TICK = 0.15  -- client reveal cadence

-- By zone NAME: always discovered (outline + name), and fully explored from the start.
MinimapConfig.DefaultDiscovered = { Oakhaven = true }
MinimapConfig.DefaultRevealed = { Oakhaven = true }
-- Zones of these alignments show in full as soon as they're discovered, no walking needed:
-- safe towns shouldn't be gated behind exploring them (only the wilds are fog of war).
MinimapConfig.AutoRevealAlignments = { Lawful = true }

-- The in-world "sneak peek" on a first discovery (client/Minimap/DiscoveryPeek): a curtain of
-- yellow light rays along the zone's whole real outline. They shoot up out of the ground, hold,
-- then lift off and fade. A bright band on the ground traces the outline through terrain too.
MinimapConfig.Peek = {
	Color = Color3.fromRGB(255, 214, 96),
	RayHeight = 140,      -- studs the rays reach
	RayBrightness = 2,    -- additive glow at full strength (halved 2026-09-29: was 4)
	GrowSeconds = .6,     -- shooting up
	HoldSeconds = 1.3,    -- standing at full height
	FadeSeconds = 1.8,    -- lifting off + fading out
	LiftOff = 60,         -- studs the rays rise while fading
	BandHeight = 6,       -- the see-through ground band (studs)
	BandPeakTransparency = .625, -- its fill at brightest (1 = invisible); halved 2026-09-29 (was .25 = 75% opaque)
	BandOutlineStrength = .4,    -- the band's outline at brightest (0..1; was .8)
	BandPartOpacity = .2,        -- the neon slabs themselves at brightest (was .4)
	PieceLength = 24,     -- the outline is split into pieces this long (one ray each)
	-- No glow right in the discoverer's face: outline pieces within SafeRadius (flat studs) of
	-- the player get nothing, then over SafeRamp more studs the rays and band grow to full
	-- height ( -----_    o    _----- ).
	SafeRadius = 28,
	SafeRamp = 32,
}

-- Views. Scale = screen pixels per map cell.
MinimapConfig.MiniSize = 190          -- corner minimap, square, pixels
MinimapConfig.MiniScale = 2           -- 95 cells = 380 studs across
MinimapConfig.BigMinScale = .5
MinimapConfig.BigMaxScale = 8
MinimapConfig.ZoomStep = 1.25         -- per scroll notch / key press

MinimapConfig.BYTES_PER_CHUNK = MinimapConfig.CHUNK * MinimapConfig.CHUNK / 8

-------------------------------------------------------------------------------------------------
-- Grid

function MinimapConfig.CellOf(x, z)
	return math.floor(x / MinimapConfig.CELL), math.floor(z / MinimapConfig.CELL)
end

function MinimapConfig.ChunkOfCell(cx, cz)
	return math.floor(cx / MinimapConfig.CHUNK), math.floor(cz / MinimapConfig.CHUNK)
end

function MinimapConfig.ChunkKey(kx, kz)
	return kx .. "," .. kz
end

function MinimapConfig.ParseKey(key)
	local kx, kz = string.match(key, "^(%-?%d+),(%-?%d+)$")
	return tonumber(kx), tonumber(kz)
end

-- 0-based bit index of a cell inside its chunk (row-major, z rows).
function MinimapConfig.BitIndex(cx, cz)
	local n = MinimapConfig.CHUNK
	return (cz % n) * n + (cx % n)
end

function MinimapConfig.GetBit(buf, index)
	local byte = buffer.readu8(buf, index // 8)
	return bit32.band(byte, bit32.lshift(1, index % 8)) ~= 0
end

-- Returns true if the bit was newly set.
function MinimapConfig.SetBit(buf, index)
	local at = index // 8
	local byte = buffer.readu8(buf, at)
	local mask = bit32.lshift(1, index % 8)
	if bit32.band(byte, mask) ~= 0 then return false end
	buffer.writeu8(buf, at, bit32.bor(byte, mask))
	return true
end

-- Calls fn(cx, cz) for every cell whose centre is within `radius` studs of (x, z).
function MinimapConfig.ForEachCellInRadius(x, z, radius, fn)
	local cell = MinimapConfig.CELL
	local x0, z0 = MinimapConfig.CellOf(x - radius, z - radius)
	local x1, z1 = MinimapConfig.CellOf(x + radius, z + radius)
	local r2 = radius * radius
	for cz = z0, z1 do
		local dz = (cz + .5) * cell - z
		for cx = x0, x1 do
			local dx = (cx + .5) * cell - x
			if dx * dx + dz * dz <= r2 then fn(cx, cz) end
		end
	end
end

-------------------------------------------------------------------------------------------------
-- Zones (the ZoneService wire rows: points = { {x, z} ... } or legacy center + radius)

function MinimapConfig.PointInPolygon(x, z, points)
	local inside = false
	local j = #points
	for i = 1, #points do
		local xi, zi = points[i].x, points[i].z
		local xj, zj = points[j].x, points[j].z
		if (zi > z) ~= (zj > z) then
			local denom = zj - zi
			if denom == 0 then denom = 1e-9 end
			if x < (xj - xi) * (z - zi) / denom + xi then inside = not inside end
		end
		j = i
	end
	return inside
end

function MinimapConfig.ZoneContains(zone, x, z)
	if type(zone.points) == "table" and #zone.points >= 3 then
		return MinimapConfig.PointInPolygon(x, z, zone.points)
	end
	local c, r = zone.center, zone.radius
	if typeof(c) ~= "Vector3" or type(r) ~= "number" then return false end
	local dx, dz = x - c.X, z - c.Z
	return dx * dx + dz * dz <= r * r
end

-- The zone's outline as a list of {x, z} (a legacy circle becomes a 32-gon).
function MinimapConfig.ZoneOutline(zone)
	if type(zone.points) == "table" and #zone.points >= 3 then return zone.points end
	local c, r = zone.center, zone.radius
	if typeof(c) ~= "Vector3" or type(r) ~= "number" then return {} end
	local out = {}
	for i = 0, 31 do
		local a = i / 32 * math.pi * 2
		table.insert(out, { x = c.X + math.cos(a) * r, z = c.Z + math.sin(a) * r })
	end
	return out
end

-- Map extent in CELLS: { x0, z0, x1, z1 } (inclusive), or nil with no zones.
function MinimapConfig.CellBounds(zones)
	local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
	for _, zone in ipairs(zones) do
		for _, p in ipairs(MinimapConfig.ZoneOutline(zone)) do
			minX, maxX = math.min(minX, p.x), math.max(maxX, p.x)
			minZ, maxZ = math.min(minZ, p.z), math.max(maxZ, p.z)
		end
	end
	if minX == math.huge then return nil end
	local m = MinimapConfig.BOUNDS_MARGIN
	local x0, z0 = MinimapConfig.CellOf(minX - m, minZ - m)
	local x1, z1 = MinimapConfig.CellOf(maxX + m, maxZ + m)
	return { x0 = x0, z0 = z0, x1 = x1, z1 = z1 }
end

function MinimapConfig.CellInBounds(bounds, cx, cz)
	return bounds ~= nil and cx >= bounds.x0 and cx <= bounds.x1 and cz >= bounds.z0 and cz <= bounds.z1
end

-------------------------------------------------------------------------------------------------
-- Base64 (profile storage of the explored-cell bitsets; DataStore JSON must stay valid UTF-8)

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local ENCODE, DECODE = {}, {}
for i = 1, 64 do
	local c = string.sub(ALPHABET, i, i)
	ENCODE[i - 1] = c
	DECODE[string.byte(c)] = i - 1
end

function MinimapConfig.EncodeBuffer(buf)
	local out = {}
	local len = buffer.len(buf)
	for i = 0, len - 1, 3 do
		local a = buffer.readu8(buf, i)
		local b = i + 1 < len and buffer.readu8(buf, i + 1) or 0
		local c = i + 2 < len and buffer.readu8(buf, i + 2) or 0
		local n = a * 65536 + b * 256 + c
		table.insert(out, ENCODE[bit32.extract(n, 18, 6)] .. ENCODE[bit32.extract(n, 12, 6)]
			.. (i + 1 < len and ENCODE[bit32.extract(n, 6, 6)] or "=")
			.. (i + 2 < len and ENCODE[bit32.extract(n, 0, 6)] or "="))
	end
	return table.concat(out)
end

-- Decodes into a buffer of exactly `size` bytes (anything malformed decodes as zeros).
function MinimapConfig.DecodeToBuffer(text, size)
	local buf = buffer.create(size)
	if type(text) ~= "string" then return buf end
	local at = 0
	for i = 1, #text, 4 do
		local n, pad = 0, 0
		for j = 0, 3 do
			local byte = string.byte(text, i + j)
			local v = byte and DECODE[byte]
			if v == nil then v = 0; pad += 1 end
			n = n * 64 + v
		end
		for shift = 16, 0, -8 do
			if at < size and pad < 3 then buffer.writeu8(buf, at, bit32.extract(n, shift, 8)) end
			at += 1
		end
	end
	return buf
end

return MinimapConfig
