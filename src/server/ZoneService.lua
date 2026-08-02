--[[
	ZoneService
	Runtime registry for all placed zones plus the spatial-query API used by the
	PvP gate and per-tick occupancy tracking.

	Responsibilities:
	  - Load persisted zones from ZoneDevStore on boot
	  - Expose CRUD that keeps the in-memory cache, DataStore, and clients in sync
	  - Track which zones each player is currently inside via a Heartbeat-driven
	    poll (XZ distance only; Y ignored — zones are infinite vertical columns)
	  - Fire ZoneEntryFlash to a player when they enter a zone whose
	    bannedAlignments set contains their alignment
	  - Provide IsAnyZoneLawfulAtPlayer() for the PvP gate

	Broadcast model:
	  ZoneStateBroadcast (ReplicatedStorage.GameEvents)
	    - server -> all clients
	    - args: { zones = { plainTableRows... } }
	    - fired on player join + on add/remove
	ZoneEntryFlash
	    - server -> one client
	    - args: { zoneName, zoneAlignment, playerAlignment }
]]

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ZoneConfig   = require(ReplicatedStorage:WaitForChild("ZoneConfig"))
local ZoneDevStore = require(ServerScriptService:WaitForChild("ZoneDevStore"))
local MobData      = require(ReplicatedStorage:WaitForChild("MobData"))

-- Lazy: avoid a require cycle through DungeonProfileService at boot time.
local _profileSvc
local function profileSvc()
	if not _profileSvc then
		_profileSvc = require(ServerScriptService:WaitForChild("DungeonProfileService"))
	end
	return _profileSvc
end

local ZoneService = {}

----------------------------------------------------------------------
-- Remote events
----------------------------------------------------------------------

local function ensureFolder(parent, name)
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f
end

local function ensureRemoteEvent(parent, name)
	local e = parent:FindFirstChild(name)
	if e and e:IsA("RemoteEvent") then return e end
	if e then e:Destroy() end
	local ev = Instance.new("RemoteEvent")
	ev.Name = name
	ev.Parent = parent
	return ev
end

local GameEvents      = ensureFolder(ReplicatedStorage, "GameEvents")
local ZoneBroadcast   = ensureRemoteEvent(GameEvents, "ZoneStateBroadcast")
local ZoneEntryFlash  = ensureRemoteEvent(GameEvents, "ZoneEntryFlash")
local ZoneEntryNotify = ensureRemoteEvent(GameEvents, "ZoneEntryNotify")
local function ensureRemoteFunction(parent, name)
	local e = parent:FindFirstChild(name)
	if e and e:IsA("RemoteFunction") then return e end
	if e then e:Destroy() end
	local rf = Instance.new("RemoteFunction")
	rf.Name = name
	rf.Parent = parent
	return rf
end

local ZoneStateRequest = ensureRemoteFunction(GameEvents, "ZoneStateRequest")
local ZoneMusicSync    = ensureRemoteEvent(GameEvents, "ZoneMusicSync")

----------------------------------------------------------------------
-- In-memory registry
----------------------------------------------------------------------

-- zones: array of normalized zone tables:
--   { id, name, alignment, bannedAlignments (set), center (Vector3),
--     points ({x,z}[])?, radius (number)? legacy circle }
local zones = {}
local zoneById = {}

-- Per-player state for entry detection:
--   { inside = { [zoneId]=true, ... }, lastFlash = { [zoneId]=os.clock() } }
local playerState = {}

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function bannedSetFromRow(rawBanned)
	local set = {}
	if type(rawBanned) == "table" then
		-- Accept both array form { "Chaotic" } and set form { Chaotic=true }
		for k, v in pairs(rawBanned) do
			if type(k) == "number" and type(v) == "string" and ZoneConfig.VALID_ALIGNMENTS[v] then
				set[v] = true
			elseif type(k) == "string" and v == true and ZoneConfig.VALID_ALIGNMENTS[k] then
				set[k] = true
			end
		end
	end
	return set
end

local function cleanPolygonPoints(raw)
	local out = {}
	if type(raw) ~= "table" then
		return out
	end
	for _, p in ipairs(raw) do
		if type(p) == "table" then
			local x = tonumber(p.x)
			local z = tonumber(p.z)
			if x and z then
				table.insert(out, { x = x, z = z })
			end
		end
	end
	return out
end

local function polygonCentroid(points)
	local cx, cz = 0, 0
	for _, p in ipairs(points) do
		cx += p.x
		cz += p.z
	end
	local n = #points
	if n == 0 then
		return 0, 0
	end
	return cx / n, cz / n
end

local function pointInPolygon(x, z, points)
	local inside = false
	local j = #points
	for i = 1, #points do
		local xi, zi = points[i].x, points[i].z
		local xj, zj = points[j].x, points[j].z
		local denom = zj - zi
		if denom == 0 then
			denom = 1e-9
		end
		local intersect = ((zi > z) ~= (zj > z))
			and (x < (xj - xi) * (z - zi) / denom + xi)
		if intersect then
			inside = not inside
		end
		j = i
	end
	return inside
end

local function bannedSetToArray(set)
	local out = {}
	for name in pairs(set) do
		table.insert(out, name)
	end
	table.sort(out)
	return out
end

local function normalizeRow(row)
	if type(row) ~= "table" then return nil end
	local id = row.id
	local alignment = row.alignment
	if type(id) ~= "string" or id == "" then return nil end
	if type(alignment) ~= "string" or not ZoneConfig.VALID_ALIGNMENTS[alignment] then
		return nil
	end
	local points = cleanPolygonPoints(row.points)
	if #points >= ZoneConfig.MIN_POLYGON_POINTS then
		local cx, cz = polygonCentroid(points)
		local centerY = tonumber(row.y) or 0
		return {
			id               = id,
			name             = type(row.name) == "string" and row.name ~= "" and row.name or ("Zone_" .. id:sub(1, 6)),
			alignment        = alignment,
			bannedAlignments = bannedSetFromRow(row.bannedAlignments),
			center           = Vector3.new(cx, centerY, cz),
			points           = points,
			radius           = nil,
			musicId          = ZoneConfig.NormalizeMusicId(row.musicId),
			isEliteZone      = row.isEliteZone == true,
			eliteMobId       = type(row.eliteMobId) == "string" and row.eliteMobId or "",
		}
	end
	local radius = tonumber(row.radius) or ZoneConfig.DEFAULT_RADIUS
	radius = math.clamp(radius, ZoneConfig.MIN_RADIUS, ZoneConfig.MAX_RADIUS)
	local center = Vector3.new(tonumber(row.x) or 0, tonumber(row.y) or 0, tonumber(row.z) or 0)
	return {
		id               = id,
		name             = type(row.name) == "string" and row.name ~= "" and row.name or ("Zone_" .. id:sub(1, 6)),
		alignment        = alignment,
		bannedAlignments = bannedSetFromRow(row.bannedAlignments),
		center           = center,
		points           = nil,
		radius           = radius,
		musicId          = ZoneConfig.NormalizeMusicId(row.musicId),
		isEliteZone      = row.isEliteZone == true,
		eliteMobId       = type(row.eliteMobId) == "string" and row.eliteMobId or "",
	}
end

-- Serialize a zone for the wire (Vector3, set -> array).
local function zoneForWire(z)
	return {
		id               = z.id,
		name             = z.name,
		alignment        = z.alignment,
		bannedAlignments = bannedSetToArray(z.bannedAlignments),
		center           = z.center,
		points           = z.points,
		radius           = z.radius,
		musicId          = z.musicId,
		isEliteZone      = z.isEliteZone == true,
		eliteMobId       = z.eliteMobId,
	}
end

local function snapshotForWire()
	local out = {}
	for _, z in ipairs(zones) do
		table.insert(out, zoneForWire(z))
	end
	return { zones = out }
end

ZoneStateRequest.OnServerInvoke = function(_player)
	return snapshotForWire()
end
local function broadcastAll()
	local snap = snapshotForWire()
	for _, p in ipairs(Players:GetPlayers()) do
		ZoneBroadcast:FireClient(p, snap)
	end
end

local function broadcastTo(player)
	ZoneBroadcast:FireClient(player, snapshotForWire())
end

-- XZ-only containment. Y is intentionally ignored (zones are infinite columns).
local function zoneContainsXZ(z, x, zz)
	if type(z.points) == "table" and #z.points >= ZoneConfig.MIN_POLYGON_POINTS then
		return pointInPolygon(x, zz, z.points)
	end
	local dx = x - z.center.X
	local dz = zz - z.center.Z
	return (dx * dx + dz * dz) <= (z.radius * z.radius)
end

local function playerHRP(player)
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") or nil
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function ZoneService.GetAllZones()
	return zones
end

function ZoneService.GetZone(zoneId)
	return zoneById[zoneId]
end

-- All zones containing the world point (x, y, z). y is unused.
function ZoneService.GetZonesAtPoint(pos)
	local out = {}
	for _, z in ipairs(zones) do
		if zoneContainsXZ(z, pos.X, pos.Z) then
			table.insert(out, z)
		end
	end
	return out
end

function ZoneService.GetZonesAtPlayer(player)
	local hrp = playerHRP(player)
	if not hrp then return {} end
	return ZoneService.GetZonesAtPoint(hrp.Position)
end

-- Cached-state variant for per-tick checks (hunger gate etc.).
-- Reads playerState[player].inside which is updated every 0.25 s.
function ZoneService.IsPlayerInSafeZone(player)
	local st = playerState[player]
	if not st then return false end
	for zid in pairs(st.inside) do
		local z = zoneById[zid]
		if z and z.alignment == "Lawful" then
			return true
		end
	end
	return false
end

-- Used by the PvP gate. Returns true if `player`'s current location is inside
-- ANY zone with alignment "Lawful". Most-restrictive overlap rule.
function ZoneService.IsAnyZoneLawfulAtPlayer(player)
	local hrp = playerHRP(player)
	if not hrp then return false end
	local x, z = hrp.Position.X, hrp.Position.Z
	for _, z0 in ipairs(zones) do
		if z0.alignment == "Lawful" and zoneContainsXZ(z0, x, z) then
			return true
		end
	end
	return false
end

-- attrs: { name?, alignment, bannedAlignments (array or set), radius }
function ZoneService.AddZone(attrs, position)
	if type(attrs) ~= "table" then return false, "bad_attrs" end
	if typeof(position) ~= "Vector3" then return false, "bad_position" end
	if type(attrs.alignment) ~= "string" or not ZoneConfig.VALID_ALIGNMENTS[attrs.alignment] then
		return false, "bad_alignment"
	end

	local cleanedPoints = nil
	if type(attrs.points) == "table" then
		cleanedPoints = cleanPolygonPoints(attrs.points)
		if #cleanedPoints > ZoneConfig.MAX_POLYGON_POINTS then
			while #cleanedPoints > ZoneConfig.MAX_POLYGON_POINTS do
				table.remove(cleanedPoints)
			end
		end
		if #cleanedPoints < ZoneConfig.MIN_POLYGON_POINTS then
			cleanedPoints = nil
		end
	end

	local eliteMobId = ""
	if type(attrs.eliteMobId) == "string" and attrs.eliteMobId ~= "" then
		if not MobData.FindMobById(attrs.eliteMobId) then
			return false, "bad_elite_mob"
		end
		eliteMobId = attrs.eliteMobId
	end
	if attrs.isEliteZone == true and eliteMobId == "" then
		return false, "missing_elite_mob"
	end

	local saveAttrs = {
		name             = attrs.name,
		alignment        = attrs.alignment,
		bannedAlignments = (type(attrs.bannedAlignments) == "table") and bannedSetToArray(bannedSetFromRow(attrs.bannedAlignments)) or {},
		points           = cleanedPoints,
		radius           = cleanedPoints and nil or math.clamp(tonumber(attrs.radius) or ZoneConfig.DEFAULT_RADIUS, ZoneConfig.MIN_RADIUS, ZoneConfig.MAX_RADIUS),
		isEliteZone      = attrs.isEliteZone == true,
		eliteMobId       = eliteMobId,
	}

	local okSave, rowOrErr = ZoneDevStore.addZone(saveAttrs, position)
	if not okSave then
		return false, rowOrErr
	end

	local z = normalizeRow(rowOrErr)
	if not z then return false, "normalize_failed" end
	table.insert(zones, z)
	zoneById[z.id] = z
	broadcastAll()
	return true, z
end

-- Sets (or clears, with "") the looped soundtrack for an existing zone.
function ZoneService.SetZoneMusic(zoneId, musicId)
	local z = zoneById[zoneId]
	if not z then return false, "not_found" end
	local normalized = ZoneConfig.NormalizeMusicId(musicId)
	local ok = ZoneDevStore.setZoneMusic(zoneId, normalized)
	if not ok then return false, "save_failed" end
	z.musicId = normalized
	broadcastAll()
	return true, z
end

function ZoneService.RemoveZone(zoneId)
	if type(zoneId) ~= "string" or zoneId == "" then return false end
	local idx
	for i, z in ipairs(zones) do
		if z.id == zoneId then idx = i; break end
	end
	if not idx then return false end
	local ok = ZoneDevStore.removeZone(zoneId)
	if not ok then return false end
	table.remove(zones, idx)
	zoneById[zoneId] = nil
	-- Wipe occupancy bookkeeping for this id so a re-added zone with the same
	-- id (unlikely — GUID) wouldn't suppress a flash.
	for _, st in pairs(playerState) do
		st.inside[zoneId]    = nil
		st.lastFlash[zoneId] = nil
	end
	broadcastAll()
	return true
end

----------------------------------------------------------------------
-- Occupancy tracking + flash dispatch
----------------------------------------------------------------------

local function getPlayerState(p)
	local st = playerState[p]
	if not st then
		st = { inside = {}, lastFlash = {}, musicId = "" }
		playerState[p] = st
	end
	return st
end

local function pollPlayer(p)
	local hrp = playerHRP(p)
	if not hrp then return end
	local x, z = hrp.Position.X, hrp.Position.Z
	local st = getPlayerState(p)
	local now = os.clock()

	-- Build the new inside-set. Active music = first occupied zone (placement
	-- order) that has a musicId set; overlap ties go to whichever zone was
	-- added first.
	local newInside = {}
	local activeMusicId = ""
	local foundMusic = false
	local activeEliteZoneName = ""
	local activeEliteMobId = ""
	local foundEliteZone = false
	for _, zoneObj in ipairs(zones) do
		if zoneContainsXZ(zoneObj, x, z) then
			newInside[zoneObj.id] = zoneObj
			if not foundMusic and type(zoneObj.musicId) == "string" and zoneObj.musicId ~= "" then
				activeMusicId = zoneObj.musicId
				foundMusic = true
			end
			if not foundEliteZone and zoneObj.isEliteZone == true then
				activeEliteZoneName = zoneObj.name
				activeEliteMobId = type(zoneObj.eliteMobId) == "string" and zoneObj.eliteMobId or ""
				foundEliteZone = true
			end
		end
	end
	if activeMusicId ~= st.musicId then
		st.musicId = activeMusicId
		ZoneMusicSync:FireClient(p, { musicId = activeMusicId })
	end
	p:SetAttribute("CurrentEliteZone", activeEliteZoneName)
	p:SetAttribute("CurrentEliteMobId", activeEliteMobId)
	p:SetAttribute("IsInEliteZone", activeEliteZoneName ~= "")

	-- Diff: detect new entries (in newInside but not in st.inside).
	local playerAlignment
	for zid, zoneObj in pairs(newInside) do
		if not st.inside[zid] then
			-- Entry transition: always notify the client so the zone name banner can show.
			ZoneEntryNotify:FireClient(p, {
				zoneId        = zoneObj.id,
				zoneName      = zoneObj.name,
				zoneAlignment = zoneObj.alignment,
			})
			-- If this zone bans anyone, look up the player's alignment
			-- (lazily, once per tick) and fire the ENTRY DENIED flash if matched.
			if next(zoneObj.bannedAlignments) ~= nil then
				if not playerAlignment then
					playerAlignment = profileSvc().GetAlignment(p)
				end
				if zoneObj.bannedAlignments[playerAlignment] then
					local lf = st.lastFlash[zid] or 0
					if now - lf >= ZoneConfig.FLASH_REENTRY_COOLDOWN then
						st.lastFlash[zid] = now
						ZoneEntryFlash:FireClient(p, {
							zoneId          = zoneObj.id,
							zoneName        = zoneObj.name,
							zoneAlignment   = zoneObj.alignment,
							playerAlignment = playerAlignment,
						})
					end
				end
			end
		end
	end

	-- Replace inside set with id-only refs (don't hold zone objects long-term).
	local newInsideIds = {}
	for zid in pairs(newInside) do newInsideIds[zid] = true end
	st.inside = newInsideIds
end

local pollAccumulator = 0
RunService.Heartbeat:Connect(function(dt)
	pollAccumulator = pollAccumulator + dt
	if pollAccumulator < ZoneConfig.OCCUPANCY_TICK_SEC then return end
	pollAccumulator = 0
	if #zones == 0 then return end -- nothing to check; cheap early out
	for _, p in ipairs(Players:GetPlayers()) do
		pollPlayer(p)
	end
end)

----------------------------------------------------------------------
-- Lifecycle: load saved zones, broadcast to joining players
----------------------------------------------------------------------

local function initialLoad()
	local saved = ZoneDevStore.loadInitial()
	for _, row in ipairs(saved) do
		local z = normalizeRow(row)
		if z then
			table.insert(zones, z)
			zoneById[z.id] = z
		end
	end
	print(string.format("[ZoneService] loaded %d zones (persistence=%s)",
		#zones, tostring(ZoneDevStore.persistenceEnabled())))
end
initialLoad()

Players.PlayerAdded:Connect(function(p)
	-- Send the current snapshot. CharacterAdded fires later — we don't need it
	-- here; the heartbeat picks up the new player automatically.
	task.defer(function()
		broadcastTo(p)
	end)
end)
Players.PlayerRemoving:Connect(function(p)
	playerState[p] = nil
	p:SetAttribute("CurrentEliteZone", "")
	p:SetAttribute("CurrentEliteMobId", "")
	p:SetAttribute("IsInEliteZone", false)
end)

return ZoneService
