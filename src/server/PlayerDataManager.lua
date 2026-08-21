-- PlayerDataManager
-- Owns persistence and the in-memory session cache. Nothing else in the game
-- should touch DataStoreService directly; go through this module.
--
-- SECOND PROFILE SYSTEM: this is the persistence layer for the older of
-- DungeonBlox's two parallel profile systems (see the header comment at the
-- top of shared/DataSchema.lua for the full picture and a known live bug).
-- The short version: DungeonProfileService owns currencies/equipment/the
-- visible inventory UI now, but THIS module is still the only source of
-- truth for a player's HP/MaxHP/Armor and RPG stats, and is still required
-- (live, not dead) by DamageService.lua, InventoryService.lua, and
-- NPCService.server.lua. Do not delete or gut this file without re-tracing
-- every one of those call sites first.
--
-- Session locking:
--   Each profile carries { JobId, UpdatedAt }. A server can only take the
--   lock if the stored Lock is missing, belongs to us, or is stale (no
--   heartbeat in LOCK_STALE_AFTER seconds). A background task refreshes
--   UpdatedAt every LOCK_HEARTBEAT seconds while the session is live.
--
--   For sharding: when the player teleports to another shard, the old
--   server's Release() saves the profile and clears the lock. The 15 second
--   client-side shard wait gives that round-trip plenty of headroom before
--   the new shard tries to Load. If the old server crashed instead of
--   releasing cleanly, the stale-after timeout eventually frees the lock.

local DataStoreService = game:GetService("DataStoreService")
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataSchema = require(ReplicatedStorage:WaitForChild("DataSchema"))

local STORE_NAME        = "PlayerProfile_v1"
local LOCK_STALE_AFTER  = 60
local LOCK_HEARTBEAT    = 20
local LOAD_RETRY_COUNT  = 6
local LOAD_RETRY_DELAY  = 5
local AUTOSAVE_INTERVAL = 120

local store = DataStoreService:GetDataStore(STORE_NAME)

local PlayerDataManager = {}
local sessionData = {}
local heartbeats  = {}
local studioFallback = false -- flips on when Studio API access is disabled

local function jobIdString()
	if game.JobId ~= "" then return game.JobId end
	return "Studio_" .. tostring(game.PlaceId)
end

local function keyFor(player)
	return "u_" .. tostring(player.UserId)
end

local function tryAcquireLock(player)
	local jobId = jobIdString()
	local now   = os.time()
	local profile

	local ok, err = pcall(function()
		store:UpdateAsync(keyFor(player), function(old)
			old = DataSchema.Reconcile(old)
			local lock = old.Lock
			if lock and lock.JobId ~= jobId then
				local age = now - (lock.UpdatedAt or 0)
				if age < LOCK_STALE_AFTER then
					return nil
				end
			end
			old.Lock = { JobId = jobId, UpdatedAt = now }
			profile  = old
			return old
		end)
	end)

	if not ok then
		if RunService:IsStudio() and string.find(tostring(err), "StudioAccessToApisNotAllowed", 1, true) then
			studioFallback = true
		end
		warn("[PlayerDataManager] UpdateAsync failed for " .. player.Name .. ": " .. tostring(err))
		return nil
	end
	return profile
end

local function startHeartbeat(player)
	heartbeats[player.UserId] = task.spawn(function()
		while sessionData[player.UserId] do
			task.wait(LOCK_HEARTBEAT)
			if not sessionData[player.UserId] then break end
			pcall(function()
				store:UpdateAsync(keyFor(player), function(old)
					if type(old) ~= "table" then return nil end
					if not old.Lock or old.Lock.JobId ~= jobIdString() then
						return nil
					end
					old.Lock.UpdatedAt = os.time()
					return old
				end)
			end)
		end
	end)
end

function PlayerDataManager.Get(player)
	return sessionData[player.UserId]
end

function PlayerDataManager.GetTier(profile, tier)
	if not profile then return nil end
	return {
		Kills = profile.Progression["Tier" .. tier .. "Kills"] or 0,
		Score = profile.Progression["Tier" .. tier .. "Score"] or 0,
	}
end

function PlayerDataManager.Load(player)
	for attempt = 1, LOAD_RETRY_COUNT do
		if studioFallback then break end
		local profile = tryAcquireLock(player)
		if profile then
			sessionData[player.UserId] = profile
			startHeartbeat(player)
			return profile
		end
		if attempt < LOAD_RETRY_COUNT then
			task.wait(LOAD_RETRY_DELAY)
		end
	end

	if studioFallback then
		warn("[PlayerDataManager] Studio API access disabled. Using ephemeral profile for " .. player.Name .. " (no persistence).")
		local profile = DataSchema.Default()
		profile.IsEphemeral = true
		sessionData[player.UserId] = profile
		return profile
	end

	warn("[PlayerDataManager] Could not acquire session lock for " .. player.Name)
	player:Kick("Your session is still active on another server. Wait ~30 seconds and try again.")
	return nil
end

function PlayerDataManager.Save(player)
	local profile = sessionData[player.UserId]
	if not profile or profile.IsEphemeral then return end
	local jobId = jobIdString()
	pcall(function()
		store:UpdateAsync(keyFor(player), function(old)
			if type(old) == "table" and old.Lock and old.Lock.JobId ~= jobId then
				return nil
			end
			profile.Lock = { JobId = jobId, UpdatedAt = os.time() }
			return profile
		end)
	end)
end

function PlayerDataManager.Release(player)
	local profile = sessionData[player.UserId]
	if not profile then return end
	if profile.IsEphemeral then
		sessionData[player.UserId] = nil
		heartbeats[player.UserId] = nil
		return
	end
	local jobId = jobIdString()

	pcall(function()
		store:UpdateAsync(keyFor(player), function(old)
			if type(old) == "table" and old.Lock and old.Lock.JobId ~= jobId then
				return nil
			end
			profile.Lock = nil
			return profile
		end)
	end)

	sessionData[player.UserId] = nil
	heartbeats[player.UserId] = nil
end

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		for _, plr in ipairs(Players:GetPlayers()) do
			PlayerDataManager.Save(plr)
			task.wait(1)
		end
	end
end)

game:BindToClose(function()
	for _, plr in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			PlayerDataManager.Release(plr)
		end)
	end
	task.wait(5)
end)

return PlayerDataManager
