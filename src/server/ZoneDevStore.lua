--[[
	ZoneDevStore
	Persists F8 DevPlacer zones across Studio Stop / server restarts via DataStore.

	Studio: always reads/writes (requires "Enable Studio Access to API Services").
	Live servers: only if ServerStorage contains BoolValue ZoneDevPersistInLive == true.

	DataStore fetch/update/cache plumbing lives in DevStoreListBase (shared with
	MobDevSpawnStore / NpcDevSpawnStore) -- this module only owns the zone row
	shape: polygon vs. legacy circle, alignment, banned alignments, elite flag,
	music id.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")

local DevStoreListBase = require(ServerScriptService:WaitForChild("DevStoreListBase"))
local base = DevStoreListBase.new("DevZones_v1", "zones", "[ZoneDevStore]")

local ZoneDevStore = {}

function ZoneDevStore.persistenceEnabled()
	return base.persistenceEnabled()
end

function ZoneDevStore.refreshCacheFromStore()
	base.refreshCacheFromStore()
end

-- Returns the cached zone rows. Each row is the raw saved table:
--   polygon: { id, name, alignment, bannedAlignments, y, points = { {x,z}, ... } }
--   legacy circle: { id, name, alignment, bannedAlignments, x, y, z, radius }
function ZoneDevStore.getCachedZones()
	return base.getCachedRows()
end

function ZoneDevStore.loadInitial()
	return base.loadInitial()
end

-- attrs: {
--   name: string?, alignment: string, bannedAlignments: { string },
--   radius: number? (legacy circle), points: { { x, z } }? (polygon)
-- }
-- position: Vector3
function ZoneDevStore.addZone(attrs, position)
	if not base.persistenceEnabled() then
		return false, "persistence_disabled"
	end
	local id = HttpService:GenerateGUID(false)
	local row = {
		id               = id,
		name             = attrs.name or ("Zone_" .. id:sub(1, 6)),
		alignment        = attrs.alignment,
		bannedAlignments = attrs.bannedAlignments or {},
		musicId          = type(attrs.musicId) == "string" and attrs.musicId or "",
		isEliteZone      = attrs.isEliteZone == true,
		eliteMobId       = type(attrs.eliteMobId) == "string" and attrs.eliteMobId or "",
	}
	if type(attrs.points) == "table" and #attrs.points >= 3 then
		row.y = position.Y
		row.points = attrs.points
	else
		row.x = position.X
		row.y = position.Y
		row.z = position.Z
		row.radius = attrs.radius
	end
	return base.addRow(row)
end

function ZoneDevStore.setZoneMusic(zoneId, musicId)
	return base.updateRow(zoneId, function(row)
		row.musicId = musicId
	end)
end

function ZoneDevStore.removeZone(zoneId)
	if not base.persistenceEnabled() then
		return false
	end
	return base.removeRow(zoneId)
end

return ZoneDevStore
