--[[
	MobDevSpawnStore
	Persists F8 DevPlacer mob spawners across Studio Stop / server restarts via DataStore.
	(Editing ModuleScript.Source during Play does not survive Studio Stop.)

	Studio: always reads/writes.
	Live servers: only if ServerStorage contains BoolValue MobDevSpawnsPersistInLive == true.

	Requires Game Settings → Security → "Enable Studio Access to API Services" for Studio persistence.

	DataStore fetch/update/cache plumbing lives in DevStoreListBase (shared with
	ZoneDevStore / NpcDevSpawnStore) -- this module only owns the mob-spawn row
	shape and the runtime-spawner-object bookkeeping (spawnerBySpawnId) that's
	unique to mobs: MobManager needs a live handle back to the _G.MobSystem
	spawner object a saved row produced, not just the saved row itself.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")

local DevStoreListBase = require(ServerScriptService:WaitForChild("DevStoreListBase"))
local base = DevStoreListBase.new("MobDevSpawns_v1", "spawns", "[MobDevSpawnStore]")

-- [spawnId] = spawner object returned by _G.MobSystem.CreateSpawner. Kept
-- outside DevStoreListBase since it's runtime-only state, never saved.
local spawnerBySpawnId = {}

local MobDevSpawnStore = {}

function MobDevSpawnStore.persistenceEnabled()
	return base.persistenceEnabled()
end

function MobDevSpawnStore.refreshCacheFromStore()
	base.refreshCacheFromStore()
end

-- Called once by MobManager at server boot: loads every saved F8 mob camp
-- and re-registers it via `registerSpawner` (MobManager's RegisterSpawner),
-- rebuilding spawnerBySpawnId so later DevService deletes can find the live
-- spawner object again.
function MobDevSpawnStore.applySavedSpawns(registerSpawner)
	if not base.persistenceEnabled() then
		spawnerBySpawnId = {}
		return
	end
	base.loadInitial()
	spawnerBySpawnId = {}
	for _, row in ipairs(base.getCachedRows()) do
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
	return base.getCachedRows()
end

function MobDevSpawnStore.addSpawn(attrs, position)
	if not base.persistenceEnabled() then
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
	local ok, err = base.addRow(row)
	return ok, ok and id or err
end

function MobDevSpawnStore.attachRuntimeSpawner(spawnId, spawnerObj)
	if type(spawnId) == "string" and spawnId ~= "" then
		spawnerBySpawnId[spawnId] = spawnerObj
	end
end

function MobDevSpawnStore.removeSpawn(spawnId)
	if not base.persistenceEnabled() or type(spawnId) ~= "string" or spawnId == "" then
		return false
	end
	local ok = base.removeRow(spawnId)
	spawnerBySpawnId[spawnId] = nil
	return ok
end

return MobDevSpawnStore
