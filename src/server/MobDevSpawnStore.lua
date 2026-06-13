--[[
	MobDevSpawnStore
	Persists F8 DevPlacer mob spawners across Studio Stop / server restarts via DataStore.
	(Editing ModuleScript.Source during Play does not survive Studio Stop.)

	Studio: always reads/writes.
	Live servers: only if ServerStorage contains BoolValue MobDevSpawnsPersistInLive == true.

	Requires Game Settings → Security → "Enable Studio Access to API Services" for Studio persistence.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local STORE_NAME = "MobDevSpawns_v1"
local store = DataStoreService:GetDataStore(STORE_NAME)

local function storageKey()
	return "place_" .. tostring(game.PlaceId)
end

local function defaultPayload()
	return { v = 1, spawns = {} }
end

local function persistenceEnabled()
	return true  -- always persist in both Studio and live servers
end

local cachedPayload = nil
local spawnerBySpawnId = {}

local function normalizePayload(raw)
	if type(raw) ~= "table" then
		return defaultPayload()
	end
	if type(raw.spawns) ~= "table" then
		raw.spawns = {}
	end
	if raw.v ~= 1 then
		raw.v = 1
	end
	return raw
end

local function fetchFromDataStore()
	if not persistenceEnabled() then
		return defaultPayload(), nil
	end
	local ok, data = pcall(function()
		return store:GetAsync(storageKey())
	end)
	if not ok then
		local err = tostring(data)
		if RunService:IsStudio() and string.find(err, "StudioAccessToApisNotAllowed", 1, true) then
			warn(
				"[MobDevSpawnStore] DataStore blocked in Studio — enable \"Enable Studio Access to API Services\" in Game Settings → Security to persist F8 mob spawners after Stop."
			)
		else
			warn("[MobDevSpawnStore] GetAsync failed: " .. err)
		end
		return defaultPayload(), err
	end
	return normalizePayload(data), nil
end

local function updateDataStore(mutate)
	if not persistenceEnabled() then
		return false, "persistence_disabled"
	end
	local ok, err = pcall(function()
		store:UpdateAsync(storageKey(), function(old)
			local p = normalizePayload(old)
			mutate(p)
			return p
		end)
	end)
	if not ok then
		warn("[MobDevSpawnStore] UpdateAsync failed: " .. tostring(err))
		return false, tostring(err)
	end
	return true, nil
end

local MobDevSpawnStore = {}

function MobDevSpawnStore.persistenceEnabled()
	return persistenceEnabled()
end

function MobDevSpawnStore.refreshCacheFromStore()
	cachedPayload = select(1, fetchFromDataStore())
end

function MobDevSpawnStore.applySavedSpawns(registerSpawner)
	if not persistenceEnabled() then
		cachedPayload = defaultPayload()
		spawnerBySpawnId = {}
		return
	end
	local payload = select(1, fetchFromDataStore())
	cachedPayload = payload
	spawnerBySpawnId = {}
	for _, row in ipairs(payload.spawns) do
		if type(row) == "table" and type(row.id) == "string" and type(row.mobId) == "string" then
			local px = tonumber(row.x) or 0
			local py = tonumber(row.y) or 0
			local pz = tonumber(row.z) or 0
			local delay = math.clamp(math.floor(tonumber(row.respawnDelay) or 10), 1, 300)
			local count = math.clamp(math.floor(tonumber(row.count) or 3), 1, 20)
			local radius = math.clamp(math.floor(tonumber(row.activationRadius) or 100), 10, 500)
			local zone = type(row.zoneName) == "string" and row.zoneName ~= "" and row.zoneName or "Default"
			local sp = registerSpawner(Vector3.new(px, py, pz), row.mobId, delay, count, radius, zone, nil)
			spawnerBySpawnId[row.id] = sp
		end
	end
end

function MobDevSpawnStore.getSpawner(spawnId)
	return spawnerBySpawnId[spawnId]
end

function MobDevSpawnStore.getCachedSpawns()
	if not cachedPayload or type(cachedPayload.spawns) ~= "table" then
		return {}
	end
	return cachedPayload.spawns
end

function MobDevSpawnStore.addSpawn(attrs, position)
	if not persistenceEnabled() then
		return false, "persistence_disabled"
	end
	local id = HttpService:GenerateGUID(false)
	local zone = attrs.ZoneName or "Default"
	local row = {
		id = id,
		mobId = attrs.MobId,
		x = position.X,
		y = position.Y,
		z = position.Z,
		count = attrs.Count,
		respawnDelay = attrs.RespawnDelay,
		activationRadius = attrs.ActivationRadius,
		zoneName = zone,
	}
	local ok, err = updateDataStore(function(p)
		table.insert(p.spawns, row)
	end)
	if ok then
		if not cachedPayload then
			cachedPayload = defaultPayload()
		end
		table.insert(cachedPayload.spawns, row)
	end
	return ok, ok and id or err
end

function MobDevSpawnStore.attachRuntimeSpawner(spawnId, spawnerObj)
	if type(spawnId) == "string" and spawnId ~= "" then
		spawnerBySpawnId[spawnId] = spawnerObj
	end
end

function MobDevSpawnStore.removeSpawn(spawnId)
	if not persistenceEnabled() or type(spawnId) ~= "string" or spawnId == "" then
		return false
	end
	local ok = updateDataStore(function(p)
		for i = #p.spawns, 1, -1 do
			if p.spawns[i] and p.spawns[i].id == spawnId then
				table.remove(p.spawns, i)
			end
		end
	end)
	if ok and cachedPayload and type(cachedPayload.spawns) == "table" then
		for i = #cachedPayload.spawns, 1, -1 do
			if cachedPayload.spawns[i] and cachedPayload.spawns[i].id == spawnId then
				table.remove(cachedPayload.spawns, i)
			end
		end
	end
	spawnerBySpawnId[spawnId] = nil
	return ok
end

return MobDevSpawnStore
