--[[
	ShardConfig
	Shared constants for the Shard Hopping feature -- a bounded pool of parallel
	server instances ("shards") of this same place that grinding players can
	voluntarily hop between via a menu, entirely separate from Roblox's normal
	public-server matchmaking (the "blue button" flow is untouched -- this is an
	opt-in extra layered on top, not a replacement).
	See ServerScriptService.ShardService for the provisioning/population/channel logic.
]]

local ShardConfig = {}

-- Number of shard slots. Not hardcoded into any logic beyond this one
-- constant -- bump it and provisioning, the UI list, and population tracking
-- all follow automatically. 10 for now/testing.
ShardConfig.NUM_SHARDS = 10

-- Channel (cast-time) duration in seconds before a hop actually fires, keyed
-- by the PLAYER'S OWN alignment (ProfileService.GetAlignment) -- not
-- zone alignment. Chaotic players eat the longest exposed cast time as the
-- tradeoff for their playstyle. Overridden to SAFE_ZONE_CHANNEL_SECONDS
-- (instant) whenever ZoneService.IsPlayerInSafeZone(player) is true, checked
-- first and taking priority over all of these.
ShardConfig.CHANNEL_SECONDS = {
	Lawful = 10,
	Neutral = 30,
	Chaotic = 60,
}

ShardConfig.SAFE_ZONE_CHANNEL_SECONDS = 0

-- DataStore holding the NUM_SHARDS reserved-server access codes. Self-healing:
-- any server that needs a slot's code and finds it missing reserves one
-- itself (see ShardService.ensureAccessCode).
ShardConfig.ACCESS_CODE_STORE = "ShardAccessCodes_v1"

-- MemoryStoreSortedMap holding live per-shard population counts, written by
-- each shard server about itself only (no leader election needed).
ShardConfig.POPULATION_MAP_NAME = "ShardPopulation_v1"
ShardConfig.POPULATION_TTL = 15     -- seconds before a shard's entry is considered stale
ShardConfig.POPULATION_REFRESH = 5  -- how often each shard server re-writes its own count

return ShardConfig
