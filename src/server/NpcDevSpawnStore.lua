--[[
	NpcDevSpawnStore
	Persists F8 DevPlacer NPC spawners across server restarts via DataStore.
	Always enabled in both Studio and live servers.
	Requires Game Settings -> Security -> "Enable Studio Access to API Services" for Studio.

	DataStore fetch/update/cache plumbing lives in DevStoreListBase (shared with
	ZoneDevStore / MobDevSpawnStore, which had the identical pattern hand-rolled
	three times over). Behavior note: routing through the shared base also
	gives NPC dev-spawns the same Studio-session-only fallback that Zone/Mob
	dev-spawns already had when the DataStore write itself fails (e.g. "Enable
	Studio Access to API Services" is off) -- previously THIS store alone had
	no such fallback, so a placed NPC marker silently got no DevSpawnId
	attribute in that case and couldn't be deleted from the Managed Spawners
	list afterwards. Flagged explicitly in the dev-tooling refactor report;
	this only changes behavior for devs without Studio API access enabled.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")

local DevStoreListBase = require(ServerScriptService:WaitForChild("DevStoreListBase"))
local base = DevStoreListBase.new("DevNpcSpawns_v1", "spawns", "[NpcDevSpawnStore]")

local NpcDevSpawnStore = {}

function NpcDevSpawnStore.loadInitial()
	return base.loadInitial()
end

function NpcDevSpawnStore.getCachedSpawns()
	return base.getCachedRows()
end

-- attrs: { NpcId, NpcType, NpcName }
function NpcDevSpawnStore.addSpawn(attrs, position)
	local id = HttpService:GenerateGUID(false)
	local row = {
		id      = id,
		npcId   = attrs.NpcId,
		npcType = attrs.NpcType,
		npcName = attrs.NpcName,
		x = position.X,
		y = position.Y,
		z = position.Z,
	}
	local ok, err = base.addRow(row)
	return ok, ok and id or err
end

function NpcDevSpawnStore.removeSpawn(spawnId)
	if type(spawnId) ~= "string" or spawnId == "" then
		return false
	end
	return base.removeRow(spawnId)
end

return NpcDevSpawnStore
