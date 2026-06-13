--[[
	NpcDevSpawnStore
	Persists F8 DevPlacer NPC spawners across server restarts via DataStore.
	Always enabled in both Studio and live servers.
	Requires Game Settings -> Security -> "Enable Studio Access to API Services" for Studio.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService      = game:GetService("HttpService")
local RunService       = game:GetService("RunService")

local STORE_NAME = "DevNpcSpawns_v1"
local store      = DataStoreService:GetDataStore(STORE_NAME)

local function storageKey()
	return "place_" .. tostring(game.PlaceId)
end

local function defaultPayload()
	return { v = 1, spawns = {} }
end

local cachedPayload = nil

local function normalize(raw)
	if type(raw) ~= "table" then return defaultPayload() end
	if type(raw.spawns) ~= "table" then raw.spawns = {} end
	if raw.v ~= 1 then raw.v = 1 end
	return raw
end

local function fetch()
	local ok, data = pcall(function()
		return store:GetAsync(storageKey())
	end)
	if not ok then
		local err = tostring(data)
		if RunService:IsStudio() and string.find(err, "StudioAccessToApisNotAllowed", 1, true) then
			warn("[NpcDevSpawnStore] DataStore blocked in Studio — enable 'Enable Studio Access to API Services' in Game Settings -> Security.")
		else
			warn("[NpcDevSpawnStore] GetAsync failed: " .. err)
		end
		return defaultPayload(), err
	end
	return normalize(data), nil
end

local function update(mutate)
	local ok, err = pcall(function()
		store:UpdateAsync(storageKey(), function(old)
			local p = normalize(old)
			mutate(p)
			return p
		end)
	end)
	if not ok then
		warn("[NpcDevSpawnStore] UpdateAsync failed: " .. tostring(err))
		return false, tostring(err)
	end
	return true, nil
end

local NpcDevSpawnStore = {}

function NpcDevSpawnStore.loadInitial()
	cachedPayload = select(1, fetch())
	return cachedPayload.spawns
end

function NpcDevSpawnStore.getCachedSpawns()
	if not cachedPayload or type(cachedPayload.spawns) ~= "table" then return {} end
	return cachedPayload.spawns
end

-- attrs: { NpcId, NpcType, NpcName }
function NpcDevSpawnStore.addSpawn(attrs, position)
	local id  = HttpService:GenerateGUID(false)
	local row = {
		id      = id,
		npcId   = attrs.NpcId,
		npcType = attrs.NpcType,
		npcName = attrs.NpcName,
		x = position.X,
		y = position.Y,
		z = position.Z,
	}
	local ok, err = update(function(p)
		table.insert(p.spawns, row)
	end)
	if ok then
		if not cachedPayload then cachedPayload = defaultPayload() end
		table.insert(cachedPayload.spawns, row)
	end
	return ok, ok and id or err
end

function NpcDevSpawnStore.removeSpawn(spawnId)
	if type(spawnId) ~= "string" or spawnId == "" then return false end
	local ok = update(function(p)
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
	return ok
end

return NpcDevSpawnStore