--[[
	ZoneDevStore
	Persists F8 DevPlacer zones across Studio Stop / server restarts via DataStore.
	Mirrors the design of MobDevSpawnStore.

	Studio: always reads/writes (requires "Enable Studio Access to API Services").
	Live servers: only if ServerStorage contains BoolValue ZoneDevPersistInLive == true.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService      = game:GetService("HttpService")
local RunService       = game:GetService("RunService")
local ServerStorage    = game:GetService("ServerStorage")

local STORE_NAME = "DevZones_v1"
local store = DataStoreService:GetDataStore(STORE_NAME)

local function storageKey()
	return "place_" .. tostring(game.PlaceId)
end

local function defaultPayload()
	return { v = 1, zones = {} }
end

local function persistenceEnabled()
	return true  -- always persist in both Studio and live servers
end

local cachedPayload = nil

local function normalize(raw)
	if type(raw) ~= "table" then return defaultPayload() end
	if type(raw.zones) ~= "table" then raw.zones = {} end
	if raw.v ~= 1 then raw.v = 1 end
	return raw
end

local function fetch()
	if not persistenceEnabled() then
		return defaultPayload(), nil
	end
	local ok, data = pcall(function()
		return store:GetAsync(storageKey())
	end)
	if not ok then
		local err = tostring(data)
		if RunService:IsStudio() and string.find(err, "StudioAccessToApisNotAllowed", 1, true) then
			warn("[ZoneDevStore] DataStore blocked in Studio — enable 'Enable Studio Access to API Services' in Game Settings → Security.")
		else
			warn("[ZoneDevStore] GetAsync failed: " .. err)
		end
		return defaultPayload(), err
	end
	return normalize(data), nil
end

local function update(mutate)
	if not persistenceEnabled() then
		return false, "persistence_disabled"
	end
	local ok, err = pcall(function()
		store:UpdateAsync(storageKey(), function(old)
			local p = normalize(old)
			mutate(p)
			return p
		end)
	end)
	if not ok then
		warn("[ZoneDevStore] UpdateAsync failed: " .. tostring(err))
		return false, tostring(err)
	end
	return true, nil
end

local ZoneDevStore = {}

function ZoneDevStore.persistenceEnabled()
	return persistenceEnabled()
end

function ZoneDevStore.refreshCacheFromStore()
	cachedPayload = select(1, fetch())
end

-- Returns the cached zone rows. Each row is the raw saved table:
--   polygon: { id, name, alignment, bannedAlignments, y, points = { {x,z}, ... } }
--   legacy circle: { id, name, alignment, bannedAlignments, x, y, z, radius }
function ZoneDevStore.getCachedZones()
	if not cachedPayload or type(cachedPayload.zones) ~= "table" then
		return {}
	end
	return cachedPayload.zones
end

function ZoneDevStore.loadInitial()
	cachedPayload = select(1, fetch())
	return cachedPayload.zones
end

-- attrs: {
--   name: string?, alignment: string, bannedAlignments: { string },
--   radius: number? (legacy circle), points: { { x, z } }? (polygon)
-- }
-- position: Vector3
function ZoneDevStore.addZone(attrs, position)
	if not persistenceEnabled() then
		return false, "persistence_disabled"
	end
	local id = HttpService:GenerateGUID(false)
	local row = {
		id               = id,
		name             = attrs.name or ("Zone_" .. id:sub(1,6)),
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
	local ok, err = update(function(p)
		table.insert(p.zones, row)
	end)
	if ok then
		if not cachedPayload then cachedPayload = defaultPayload() end
		table.insert(cachedPayload.zones, row)
		return true, row
	end
	-- Studio session fallback when DataStore is blocked (Finish Zone appeared to do nothing).
	if RunService:IsStudio() then
		warn("[ZoneDevStore] DataStore save failed — zone kept for this session only: " .. tostring(err))
		if not cachedPayload then cachedPayload = defaultPayload() end
		table.insert(cachedPayload.zones, row)
		return true, row
	end
	return false, err
end

function ZoneDevStore.setZoneMusic(zoneId, musicId)
	if type(zoneId) ~= "string" or zoneId == "" then return false end
	local ok, err = update(function(p)
		for _, row in ipairs(p.zones) do
			if row.id == zoneId then
				row.musicId = musicId
			end
		end
	end)
	if ok then
		if cachedPayload and type(cachedPayload.zones) == "table" then
			for _, row in ipairs(cachedPayload.zones) do
				if row.id == zoneId then row.musicId = musicId end
			end
		end
		return true
	end
	-- Studio session fallback when DataStore is blocked, mirroring addZone.
	if RunService:IsStudio() then
		warn("[ZoneDevStore] DataStore save failed — music kept for this session only: " .. tostring(err))
		if cachedPayload and type(cachedPayload.zones) == "table" then
			for _, row in ipairs(cachedPayload.zones) do
				if row.id == zoneId then row.musicId = musicId end
			end
		end
		return true
	end
	return false
end

function ZoneDevStore.removeZone(zoneId)
	if not persistenceEnabled() or type(zoneId) ~= "string" or zoneId == "" then
		return false
	end
	local ok = update(function(p)
		for i = #p.zones, 1, -1 do
			if p.zones[i] and p.zones[i].id == zoneId then
				table.remove(p.zones, i)
			end
		end
	end)
	if ok and cachedPayload and type(cachedPayload.zones) == "table" then
		for i = #cachedPayload.zones, 1, -1 do
			if cachedPayload.zones[i] and cachedPayload.zones[i].id == zoneId then
				table.remove(cachedPayload.zones, i)
			end
		end
	end
	return ok
end

return ZoneDevStore
