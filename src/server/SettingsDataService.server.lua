--[[
	SettingsDataService
	Persists the Settings menu (audio + video sliders) to its own DataStore.

	Deliberately its OWN store, not folded into PlayerDataManager.lua or
	ProfileService.lua:
	  - PlayerDataManager.lua is the "SECOND PROFILE SYSTEM" (see its header) --
	    legacy HP/Armor/RPG-stat storage, not where new fields should land.
	  - ProfileService.lua (currencies/inventory/equipment -- the CURRENT
	    profile system) has its SaveProfile as a literal no-op right now
	    ("Intentionally empty: wire to ProfileService UpdateAsync in a later
	    milestone") -- so nothing saved through it actually persists yet.
	    Settings needed to actually work today, so it gets a small dedicated
	    store instead of silently inheriting that gap. This mirrors how
	    AuctionHouseService/HearthstoneRegistry/ShardService already each own
	    their own DataStore rather than funneling through one god-module.

	Flow:
	  - GetPlayerSettings (RemoteFunction): client invokes once per session
	    (see SettingsStore.luau); lazily loads+caches on first call for that
	    player, returns the saved sparse table (only fields they've changed).
	  - UpdatePlayerSettings (RemoteEvent): client fires on every slider
	    release (not every drag frame -- see SettingsClient's onCommit).
	    Validates (category, key) against SettingsRanges and clamps the
	    value, updates the in-memory cache, and flags it dirty.
	  - Dirty profiles save on a slow autosave loop and on PlayerRemoving/
	    BindToClose -- settings are low-stakes, so unlike PlayerDataManager
	    there's no session-lock/kick-on-conflict machinery here, just
	    "last write wins."
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SettingsRanges = require(ReplicatedStorage:WaitForChild("SettingsRanges"))

local STORE_NAME = "PlayerSettings_v1"
local AUTOSAVE_INTERVAL = 90

local store = DataStoreService:GetDataStore(STORE_NAME)
local studioFallback = false -- flips on when Studio API access is disabled

local cache = {}   -- [userId] = { volume = {...}, video = {...} }
local dirty = {}   -- [userId] = true

local function keyFor(userId)
	return "u_" .. tostring(userId)
end

local function isApiDisabledError(err)
	return RunService:IsStudio() and string.find(tostring(err), "StudioAccessToApisNotAllowed", 1, true) ~= nil
end

-- Strips anything not in SettingsRanges (unknown categories/keys, non-numbers)
-- so a stale/tampered save can never hand back garbage to the client.
local function sanitize(loaded)
	local clean = {}
	if type(loaded) ~= "table" then
		return clean
	end
	for category, fields in pairs(SettingsRanges) do
		local src = loaded[category]
		if type(src) == "table" then
			local dst = {}
			for key, range in pairs(fields) do
				local v = src[key]
				if type(v) == "number" then
					dst[key] = math.clamp(v, range.min, range.max)
				end
			end
			if next(dst) then
				clean[category] = dst
			end
		end
	end
	return clean
end

-- Loads (or returns the already-cached) settings table for a player. Safe to
-- call from either remote handler -- whichever fires first does the actual
-- DataStore read, everything after just reads the cache.
local function getOrLoad(userId)
	local existing = cache[userId]
	if existing then
		return existing
	end

	if studioFallback then
		cache[userId] = {}
		return cache[userId]
	end

	local ok, result = pcall(function()
		return store:GetAsync(keyFor(userId))
	end)

	if not ok then
		if isApiDisabledError(result) then
			studioFallback = true
		end
		warn("[SettingsDataService] GetAsync failed for " .. keyFor(userId) .. ": " .. tostring(result))
		cache[userId] = {}
		return cache[userId]
	end

	cache[userId] = sanitize(result)
	return cache[userId]
end

local function saveNow(userId)
	if studioFallback then
		return
	end
	local data = cache[userId]
	if not data then
		return
	end
	local ok, err = pcall(function()
		store:SetAsync(keyFor(userId), data)
	end)
	if not ok then
		if isApiDisabledError(err) then
			studioFallback = true
		end
		warn("[SettingsDataService] SetAsync failed for " .. keyFor(userId) .. ": " .. tostring(err))
		return
	end
	dirty[userId] = nil
end

----------------------------------------------------------------------
-- Remotes
----------------------------------------------------------------------

local function ensureRemoteEvent(name)
	local x = ReplicatedStorage:FindFirstChild(name)
	if x and x:IsA("RemoteEvent") then
		return x
	end
	if x then
		x:Destroy()
	end
	local ev = Instance.new("RemoteEvent")
	ev.Name = name
	ev.Parent = ReplicatedStorage
	return ev
end

local function ensureRemoteFunction(name)
	local x = ReplicatedStorage:FindFirstChild(name)
	if x and x:IsA("RemoteFunction") then
		return x
	end
	if x then
		x:Destroy()
	end
	local rf = Instance.new("RemoteFunction")
	rf.Name = name
	rf.Parent = ReplicatedStorage
	return rf
end

local rfGet = ensureRemoteFunction("GetPlayerSettings")
local evUpdate = ensureRemoteEvent("UpdatePlayerSettings")

rfGet.OnServerInvoke = function(player)
	return getOrLoad(player.UserId)
end

-- UpdatePlayerSettings (client -> server)
--   Args: category: "volume" | "video", key: string, value: number
--   Fired once per slider release (SettingsClient's onCommit), not per
--   drag frame -- see that file. Silently drops anything not in
--   SettingsRanges instead of erroring, since a stale client build sending
--   an old field name shouldn't be able to spam warnings.
evUpdate.OnServerEvent:Connect(function(player, category, key, value)
	if type(category) ~= "string" or type(key) ~= "string" or type(value) ~= "number" then
		return
	end
	local ranges = SettingsRanges[category]
	local range = ranges and ranges[key]
	if not range then
		return
	end

	local data = getOrLoad(player.UserId)
	if type(data[category]) ~= "table" then
		data[category] = {}
	end
	data[category][key] = math.clamp(value, range.min, range.max)
	dirty[player.UserId] = true
end)

----------------------------------------------------------------------
-- Save lifecycle
----------------------------------------------------------------------

Players.PlayerRemoving:Connect(function(player)
	if dirty[player.UserId] then
		saveNow(player.UserId)
	end
	cache[player.UserId] = nil
	dirty[player.UserId] = nil
end)

task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		for userId in pairs(dirty) do
			saveNow(userId)
			task.wait(1)
		end
	end
end)

game:BindToClose(function()
	for _, plr in ipairs(Players:GetPlayers()) do
		if dirty[plr.UserId] then
			task.spawn(saveNow, plr.UserId)
		end
	end
	task.wait(3)
end)

print("[SettingsDataService] ready")
