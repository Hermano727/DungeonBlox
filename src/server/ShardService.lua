--[[
	ShardService (server-only)

	Shard Hopping: a bounded pool of ShardConfig.NUM_SHARDS parallel server
	instances of THIS place that grinding players can voluntarily teleport
	between via a menu. Entirely separate from Roblox's normal public-server
	matchmaking -- nobody who never opens the Shard menu is affected.

	Architecture:
	  - Reserved Servers (TeleportService:ReserveServer / TeleportToPrivateServer)
	    give a bounded, indexable pool of instances of this place -- the only way
	    to target a specific known instance, since Roblox's default flow can't.
	  - A DataStore (ShardConfig.ACCESS_CODE_STORE) holds each slot's access code,
	    self-healing: any server that needs a slot's code and finds it missing
	    reserves one itself, guarded by UpdateAsync so two servers racing to
	    provision the same slot can't double-reserve (first writer wins; the
	    loser's reservation goes unused -- harmless orphaned reserved server,
	    not a correctness bug).
	  - A MemoryStoreSortedMap (ShardConfig.POPULATION_MAP_NAME) holds live
	    per-shard population, written only by each shard about ITSELF (no leader
	    election needed -- there's no shared state two servers could race to
	    own). Used purely so the menu can show live counts and skip a doomed
	    teleport into a full shard; the real capacity ceiling is each shard
	    server's own Players.MaxPlayers, which we mirror into the map ourselves
	    since a different server can't read another server's Players.MaxPlayers
	    directly.
	  - Channel (cast-time): a hop isn't rate-limited at all -- a player can
	    request one as often as they like -- but each request must sit through a
	    channel before it fires, whose length depends on where/who they are:
	    instant in a safe zone, else 10/30/60s by the player's OWN alignment
	    (Lawful/Neutral/Chaotic -- ProfileService.GetAlignment, NOT zone
	    alignment). Blocked from starting at all while in combat
	    (CombatStateService.IsInCombat), and cancelled the instant the player
	    takes damage (DamageService.ApplyToPlayer calls ShardService.CancelChannel
	    directly -- see that file's hook, added alongside its existing
	    CombatStateService.OnPlayerDamaged call).

	Profile continuity: right before firing the actual teleport we force an
	immediate ProfileService.SaveProfile(player) call so the destination
	server's first Load() attempt has the best possible chance of seeing fresh
	data (see ProfileService's own persistence header comment -- this
	feature is what made that persistence retrofit a hard requirement rather
	than a nice-to-have).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local TeleportService = game:GetService("TeleportService")

local ShardConfig = require(ReplicatedStorage:WaitForChild("ShardConfig"))
local DungeonProfile = require(ServerScriptService:WaitForChild("ProfileService"))
local ZoneService = require(ServerScriptService:WaitForChild("ZoneService"))
local CombatStateService = require(ServerScriptService:WaitForChild("CombatStateService"))

local ShardService = {}

local accessCodeStore = DataStoreService:GetDataStore(ShardConfig.ACCESS_CODE_STORE)
local popMap = MemoryStoreService:GetSortedMap(ShardConfig.POPULATION_MAP_NAME)

local accessCodeCache = {} -- [shardIndex] = { accessCode, privateServerId, createdAt }
local channels = {}       -- [userId] = { thread, targetShardIndex, startedAt, duration }
local myShardIndex = nil  -- nil until detected; "unknown" is not used -- see detectMyShardIndex
local myShardIndexKnown = false

----------------------------------------------------------------------
-- Remotes
----------------------------------------------------------------------

local function ensureRemoteEvent(name)
	local x = ReplicatedStorage:FindFirstChild(name)
	if x and x:IsA("RemoteEvent") then return x end
	if x then x:Destroy() end
	local ev = Instance.new("RemoteEvent")
	ev.Name = name
	ev.Parent = ReplicatedStorage
	return ev
end

local function ensureRemoteFunction(name)
	local x = ReplicatedStorage:FindFirstChild(name)
	if x and x:IsA("RemoteFunction") then return x end
	if x then x:Destroy() end
	local rf = Instance.new("RemoteFunction")
	rf.Name = name
	rf.Parent = ReplicatedStorage
	return rf
end

local rfHopRequest = ensureRemoteFunction("ShardHopRequest")
local rfListRequest = ensureRemoteFunction("ShardListRequest")
local rfReturnToMain = ensureRemoteFunction("ShardReturnToMain")
local evHopStatus = ensureRemoteEvent("ShardHopStatus")

local function fireStatus(player, kind, extra)
	pcall(function()
		evHopStatus:FireClient(player, kind, extra)
	end)
end

----------------------------------------------------------------------
-- Access-code provisioning (self-healing)
----------------------------------------------------------------------

local function reserveFresh()
	local ok, accessCode, privateServerId = pcall(function()
		return TeleportService:ReserveServer(game.PlaceId)
	end)
	if not ok or type(accessCode) ~= "string" or accessCode == "" then
		warn("[ShardService] ReserveServer failed: " .. tostring(accessCode))
		return nil
	end
	return accessCode, privateServerId
end

-- Returns { accessCode, privateServerId, createdAt } for slot i, provisioning
-- it if this is the first time anyone's needed it. Cached in-memory after the
-- first successful lookup per server -- access codes are durable/reusable, so
-- there's no need to re-hit the DataStore on every hop.
local function ensureAccessCode(i)
	if accessCodeCache[i] then return accessCodeCache[i] end

	local key = "shard_" .. i
	local getOk, existing = pcall(function()
		return accessCodeStore:GetAsync(key)
	end)
	if getOk and type(existing) == "table" and type(existing.accessCode) == "string" and existing.accessCode ~= "" then
		accessCodeCache[i] = existing
		return existing
	end

	-- Not provisioned yet (or GetAsync failed transiently). Reserve OUTSIDE the
	-- UpdateAsync transform below so a Roblox-internal retry of that transform
	-- can never double-reserve a server for this slot.
	local accessCode, privateServerId = reserveFresh()
	if not accessCode then return nil end

	local final
	pcall(function()
		accessCodeStore:UpdateAsync(key, function(old)
			if type(old) == "table" and type(old.accessCode) == "string" and old.accessCode ~= "" then
				-- Someone else provisioned this slot while we were reserving.
				-- Keep theirs; ours goes unused (harmless).
				final = old
				return old
			end
			local row = { accessCode = accessCode, privateServerId = privateServerId, createdAt = os.time() }
			final = row
			return row
		end)
	end)
	if final then accessCodeCache[i] = final end
	return final
end

-- Detects which shard slot (1..NUM_SHARDS) THIS running server is, by matching
-- game.PrivateServerId against the provisioned list. Returns nil if this
-- server is the normal public/default server (PrivateServerId == "") or a
-- reserved server that isn't one of our shard slots. Runs lazily off the hot
-- path (task.spawn'd from start()) since it may need several DataStore
-- round-trips the first time any server calls it after a fresh deploy.
local function detectMyShardIndex()
	local pid = game.PrivateServerId
	if pid == "" then
		return nil
	end
	for i = 1, ShardConfig.NUM_SHARDS do
		local row = ensureAccessCode(i)
		if row and row.privateServerId == pid then
			return i
		end
	end
	return nil
end

-- Public: nil until detection finishes; callers should treat "not yet known"
-- and "definitely not a shard" the same way (both just mean "don't show
-- Return to Main yet") -- myShardIndexKnown distinguishes them only for start().
function ShardService.GetCurrentShardIndex()
	return myShardIndex
end

----------------------------------------------------------------------
-- Population
----------------------------------------------------------------------

local function reportMyPopulation()
	if not myShardIndex then return end
	local payload = { count = #Players:GetPlayers(), cap = Players.MaxPlayers }
	pcall(function()
		popMap:SetAsync("shard_" .. myShardIndex, payload, ShardConfig.POPULATION_TTL)
	end)
end

-- Best-effort snapshot across all shards for the UI. A shard with no live
-- entry (never booted, or its entry expired) reports population 0 against
-- this server's own Players.MaxPlayers as a reasonable default -- never
-- treated as full, since Roblox will happily spin up a fresh instance with
-- room on the next teleport into it.
function ShardService.GetPopulationSnapshot()
	local out = {}
	for i = 1, ShardConfig.NUM_SHARDS do
		local ok, value = pcall(function()
			return popMap:GetAsync("shard_" .. i)
		end)
		local count = (ok and type(value) == "table" and tonumber(value.count)) or 0
		local cap = (ok and type(value) == "table" and tonumber(value.cap)) or Players.MaxPlayers
		table.insert(out, {
			index = i,
			population = count,
			cap = cap,
			isFull = count >= cap,
		})
	end
	return out
end

----------------------------------------------------------------------
-- Channel / hop state machine
----------------------------------------------------------------------

-- Cancels any in-progress channel for `player` (called externally by
-- DamageService on every hit taken, and internally on request/complete).
-- Safe to call even if there's no active channel.
function ShardService.CancelChannel(player, reason)
	local ch = channels[player.UserId]
	if not ch then return end
	pcall(task.cancel, ch.thread)
	channels[player.UserId] = nil
	fireStatus(player, "cancelled", reason)
end

local function completeHop(player, targetShardIndex)
	channels[player.UserId] = nil
	if not player.Parent then return end

	-- Defensive re-check: combat could have started in the same frame the
	-- channel's delay fired.
	if CombatStateService.IsInCombat(player) then
		fireStatus(player, "cancelled", "in_combat")
		return
	end

	local snap = ShardService.GetPopulationSnapshot()
	local row = snap[targetShardIndex]
	if row and row.isFull then
		fireStatus(player, "shard_full", targetShardIndex)
		return
	end

	local access = ensureAccessCode(targetShardIndex)
	if not access then
		fireStatus(player, "error", "provisioning_failed")
		return
	end

	-- Flush the profile now (see this file's header + SaveProfile's own
	-- comment) -- best effort, teleport proceeds either way.
	pcall(function()
		DungeonProfile.SaveProfile(player)
	end)

	fireStatus(player, "teleporting", targetShardIndex)
	local ok, err = pcall(function()
		-- Signature is (placeId, accessCode, players, spawnName?, teleportData?, ...) --
		-- teleportData.viaShardHop lets ShardEnterClient on the destination server
		-- show a brief "Entering Shard..." overlay instead of a flash of an
		-- empty/default inventory while Load's session-lock retry is still working.
		TeleportService:TeleportToPrivateServer(game.PlaceId, access.accessCode, { player }, nil, { viaShardHop = true })
	end)
	if not ok then
		warn("[ShardService] TeleportToPrivateServer failed: " .. tostring(err))
		fireStatus(player, "error", "teleport_failed")
	end
end

-- Returns ok, durationOrErr. On ok=true, durationOrErr is the channel length
-- in seconds (0 means it already resolved instantly -- safe zone).
function ShardService.RequestHop(player, targetShardIndex)
	targetShardIndex = math.floor(tonumber(targetShardIndex) or -1)
	if targetShardIndex < 1 or targetShardIndex > ShardConfig.NUM_SHARDS then
		return false, "bad_shard"
	end
	if channels[player.UserId] then
		return false, "already_channeling"
	end
	if CombatStateService.IsInCombat(player) then
		return false, "in_combat"
	end

	local duration
	if ZoneService.IsPlayerInSafeZone(player) then
		duration = ShardConfig.SAFE_ZONE_CHANNEL_SECONDS
	else
		local alignment = DungeonProfile.GetAlignment(player)
		duration = ShardConfig.CHANNEL_SECONDS[alignment] or ShardConfig.CHANNEL_SECONDS.Neutral
	end

	if duration <= 0 then
		completeHop(player, targetShardIndex)
		return true, 0
	end

	local thread = task.delay(duration, completeHop, player, targetShardIndex)
	channels[player.UserId] = {
		thread = thread,
		targetShardIndex = targetShardIndex,
		startedAt = os.clock(),
		duration = duration,
	}
	fireStatus(player, "channeling", duration)
	return true, duration
end

----------------------------------------------------------------------
-- Remote wiring
----------------------------------------------------------------------

rfHopRequest.OnServerInvoke = function(player, targetShardIndex)
	return ShardService.RequestHop(player, targetShardIndex)
end

rfListRequest.OnServerInvoke = function(_player)
	return {
		shards = ShardService.GetPopulationSnapshot(),
		currentShardIndex = myShardIndex,
	}
end

-- Leaves the shard pool entirely and rejoins Roblox's normal public
-- matchmaking for this place (ordinary Teleport, no access code -- ONLY
-- meaningful when currently on a shard; the client hides this action
-- otherwise, but it's a harmless no-op-ish call if invoked elsewhere too).
rfReturnToMain.OnServerInvoke = function(player)
	pcall(function()
		DungeonProfile.SaveProfile(player)
	end)
	local ok, err = pcall(function()
		TeleportService:Teleport(game.PlaceId, player)
	end)
	if not ok then
		return false, "teleport_failed"
	end
	return true
end

Players.PlayerRemoving:Connect(function(p)
	channels[p.UserId] = nil
end)

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

function ShardService.start()
	-- Detection can take several DataStore round-trips on a cold cache (first
	-- server of any kind to boot after a fresh deploy) -- run it off to the
	-- side rather than blocking the rest of server boot on it.
	task.spawn(function()
		myShardIndex = detectMyShardIndex()
		myShardIndexKnown = true

		if myShardIndex then
			reportMyPopulation()
			while true do
				task.wait(ShardConfig.POPULATION_REFRESH)
				reportMyPopulation()
			end
		end
	end)
end

return ShardService
