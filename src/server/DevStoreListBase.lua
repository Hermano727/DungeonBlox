--[[
	DevStoreListBase
	Factory for the "list of rows in one DataStore key, always read in full and
	merged via UpdateAsync, cached in memory between calls" pattern that
	ZoneDevStore, MobDevSpawnStore, and NpcDevSpawnStore each used to hand-roll
	separately (fetch/normalize/update/cache were byte-for-byte identical across
	all three, save for field names). This factors out ONLY that DataStore
	plumbing -- every store still owns its own row shape and its own public API
	(ZoneDevStore.addZone, MobDevSpawnStore.addSpawn, ...); callers outside this
	file never see DevStoreListBase directly.

	Why a closure-returning factory instead of a metatable class: these stores
	don't need inheritance or polymorphism, every caller wants a plain module
	back with domain-named functions, not a shared `:method()` surface. See
	src/shared/Items/*.lua for where this codebase DOES reach for a metatable
	class instead -- genuine per-item-type behavior differences, not "same
	shape, different field names" like this.

	persistenceEnabled() is hardcoded true here, same as it was in all three
	original modules -- their header comments talk about an opt-in
	ServerStorage BoolValue ("...only if ServerStorage contains BoolValue
	XPersistInLive == true") that the code never actually reads. That
	mismatch predates this refactor; it's preserved as-is rather than
	silently "fixed" one way or the other -- see the dev-tooling report for
	this session for a flag on it.
]]

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local DevStoreListBase = {}

-- storeName: DataStore name, e.g. "MobDevSpawns_v1"
-- collectionKey: field in the saved payload holding the row array, e.g. "spawns"
-- logTag: bracketed prefix for warn()/print(), e.g. "[MobDevSpawnStore]"
function DevStoreListBase.new(storeName: string, collectionKey: string, logTag: string)
	local store = DataStoreService:GetDataStore(storeName)

	local function storageKey()
		return "place_" .. tostring(game.PlaceId)
	end

	local function defaultPayload()
		return { v = 1, [collectionKey] = {} }
	end

	local function normalize(raw)
		if type(raw) ~= "table" then
			return defaultPayload()
		end
		if type(raw[collectionKey]) ~= "table" then
			raw[collectionKey] = {}
		end
		if raw.v ~= 1 then
			raw.v = 1
		end
		return raw
	end

	local cachedPayload = nil

	local function fetch()
		local ok, data = pcall(function()
			return store:GetAsync(storageKey())
		end)
		if not ok then
			local err = tostring(data)
			if RunService:IsStudio() and string.find(err, "StudioAccessToApisNotAllowed", 1, true) then
				warn(logTag .. " DataStore blocked in Studio — enable \"Enable Studio Access to API Services\" in Game Settings → Security.")
			else
				warn(logTag .. " GetAsync failed: " .. err)
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
			warn(logTag .. " UpdateAsync failed: " .. tostring(err))
			return false, tostring(err)
		end
		return true, nil
	end

	local base = {}

	function base.persistenceEnabled()
		return true -- always persist in both Studio and live servers
	end

	function base.refreshCacheFromStore()
		cachedPayload = select(1, fetch())
	end

	function base.loadInitial()
		cachedPayload = select(1, fetch())
		return cachedPayload[collectionKey]
	end

	function base.getCachedRows()
		if not cachedPayload or type(cachedPayload[collectionKey]) ~= "table" then
			return {}
		end
		return cachedPayload[collectionKey]
	end

	-- Adds a fully-built `row` (must already contain a unique string `id`) to
	-- the store and the in-memory cache. On success returns (true, row); on
	-- failure returns (false, err) -- EXCEPT in Studio, where a failed write
	-- (e.g. "Enable Studio Access to API Services" is off) falls back to
	-- keeping the row in the cache for this session only, so Finish
	-- Zone / Place Spawner doesn't just silently appear to do nothing while
	-- a dev is iterating locally. Live servers get a hard failure so a real
	-- persistence problem isn't masked.
	function base.addRow(row)
		local ok, err = update(function(p)
			table.insert(p[collectionKey], row)
		end)
		if ok then
			if not cachedPayload then
				cachedPayload = defaultPayload()
			end
			table.insert(cachedPayload[collectionKey], row)
			return true, row
		end
		if RunService:IsStudio() then
			warn(logTag .. " DataStore save failed — row kept for this session only: " .. tostring(err))
			if not cachedPayload then
				cachedPayload = defaultPayload()
			end
			table.insert(cachedPayload[collectionKey], row)
			return true, row
		end
		return false, err
	end

	-- Removes the row whose `id` field equals rowId from the store + cache.
	function base.removeRow(rowId)
		if type(rowId) ~= "string" or rowId == "" then
			return false
		end
		local ok = update(function(p)
			for i = #p[collectionKey], 1, -1 do
				local r = p[collectionKey][i]
				if r and r.id == rowId then
					table.remove(p[collectionKey], i)
				end
			end
		end)
		if ok and cachedPayload and type(cachedPayload[collectionKey]) == "table" then
			for i = #cachedPayload[collectionKey], 1, -1 do
				local r = cachedPayload[collectionKey][i]
				if r and r.id == rowId then
					table.remove(cachedPayload[collectionKey], i)
				end
			end
		end
		return ok
	end

	-- Patches the row whose `id` field equals rowId in place, via
	-- `mutateRow(row)`, both in the store and the cache. Same Studio-session
	-- fallback as addRow. Used by ZoneDevStore.setZoneMusic; exposed
	-- generically in case a future store needs the same "edit one field on
	-- one existing row" shape.
	function base.updateRow(rowId, mutateRow)
		if type(rowId) ~= "string" or rowId == "" then
			return false
		end
		local ok, err = update(function(p)
			for _, r in ipairs(p[collectionKey]) do
				if r.id == rowId then
					mutateRow(r)
				end
			end
		end)
		if ok then
			if cachedPayload and type(cachedPayload[collectionKey]) == "table" then
				for _, r in ipairs(cachedPayload[collectionKey]) do
					if r.id == rowId then
						mutateRow(r)
					end
				end
			end
			return true
		end
		if RunService:IsStudio() then
			warn(logTag .. " DataStore save failed — change kept for this session only: " .. tostring(err))
			if cachedPayload and type(cachedPayload[collectionKey]) == "table" then
				for _, r in ipairs(cachedPayload[collectionKey]) do
					if r.id == rowId then
						mutateRow(r)
					end
				end
			end
			return true
		end
		return false
	end

	return base
end

return DevStoreListBase
