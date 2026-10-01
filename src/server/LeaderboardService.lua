--[[
	LeaderboardService -- cross-server leaderboards for the Journal's Leaderboards page.

	Boards:
		skill   combat / mining / fishing: highest level (then XP), all time
		kills   per tier (1..5) or all tiers, over 1H / 24H / 7D / 30D / All
		score   the same, for score (loot rolls) instead of kills

	Storage:
		All time   OrderedDataStore per board key (LB_v1_<stat>_<tier>, LB_v1_skill_<skill>)
		Windows    MemoryStore sorted maps, one per (stat, tier, bucket): 5-minute buckets (1H,
		           the last 12), hourly (24H, the last 24), daily (7D / 30D, the last 7 / 30).
		           A window is the SUM of its buckets, merged from each bucket's top READ_N, so
		           it's rolling and exact for anyone near the top. Buckets expire on their own.

	Writes are batched: Add() only counts in memory; a flush every FLUSH_EVERY seconds (and on
	shutdown) writes each player's increments. Skill levels are written at flush when they
	changed. Reads are cached for CACHE_SECONDS per board + filter. Everything is pcall'd: with
	no API access (Studio without "Enable Studio Access to API Services") the page just shows
	the board as unavailable.

	Hook: LootService's recordScore (every kill, overworld and dungeon) calls
	LeaderboardService.Add(player, tier, 1, scoreGained). Requests come in through JournalService
	(GameEvents/JournalRequest "leaderboard", board, a, b) -> LeaderboardService.Read.
]]

local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local UserService = game:GetService("UserService")

local LeaderboardService = {}

local VERSION = "v1"
local FLUSH_EVERY = 60
local TOP_N = 25       -- rows sent to the page
local READ_N = 100     -- rows read from each window bucket before summing
local CACHE_SECONDS = 30
local SKILL_PACK = 1e7 -- skill sort value = level * SKILL_PACK + xp (xp capped below it)

LeaderboardService.PERIODS = { "1H", "24H", "7D", "30D", "All" }
LeaderboardService.SKILLS = { "combat", "mining", "fishing" }

-- Window -> bucket length (seconds) and how many recent buckets it sums.
local WINDOWS = {
	["1H"] = { grain = 300, count = 12 },
	["24H"] = { grain = 3600, count = 24 },
	["7D"] = { grain = 86400, count = 7 },
	["30D"] = { grain = 86400, count = 30 },
}
-- Bucket lengths written on every flush, and how long each bucket lives (MemoryStore max 45 d).
local GRAINS = {
	{ grain = 300, ttl = 2 * 3600 },
	{ grain = 3600, ttl = 26 * 3600 },
	{ grain = 86400, ttl = 31 * 86400 },
}

local profileService -- lazy: ProfileService requires half the server
local function profiles()
	profileService = profileService or require(ServerScriptService:WaitForChild("ProfileService"))
	return profileService
end

local function tierKey(tier)
	local t = math.floor(tonumber(tier) or 0)
	return (t >= 1 and t <= 5) and tostring(t) or "all"
end

local function allTimeStore(stat, tk)
	return DataStoreService:GetOrderedDataStore(("LB_%s_%s_%s"):format(VERSION, stat, tk))
end
local function skillStore(skill)
	return DataStoreService:GetOrderedDataStore(("LB_%s_skill_%s"):format(VERSION, skill))
end
local function bucketMap(stat, tk, grain, index)
	return MemoryStoreService:GetSortedMap(("LB_%s_%s_%s_%d_%d"):format(VERSION, stat, tk, grain, index))
end

-------------------------------------------------------------------------------------------
-- Writes
-------------------------------------------------------------------------------------------

local pending = {} -- [userId] = { kills = { [tk] = n }, score = { [tk] = n } }
local lastSkill = {} -- [userId] = { [skill] = value written }

local function bump(uid, stat, tk, n)
	local p = pending[uid]
	if not p then
		p = { kills = {}, score = {} }
		pending[uid] = p
	end
	p[stat][tk] = (p[stat][tk] or 0) + n
end

-- One kill worth `kills` (normally 1) and `score` loot rolls, at `tier`. Memory only; cheap.
function LeaderboardService.Add(player, tier, kills, score)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	local uid = player.UserId
	local tk = tierKey(tier)
	kills = math.max(0, math.floor(tonumber(kills) or 0))
	score = math.max(0, math.floor(tonumber(score) or 0))
	if kills > 0 then bump(uid, "kills", tk, kills); bump(uid, "kills", "all", kills) end
	if score > 0 then bump(uid, "score", tk, score); bump(uid, "score", "all", score) end
end

local function skillValue(profile, skill)
	local s = profile and profile.stats and profile.stats[skill]
	if type(s) ~= "table" then return nil end
	local level = math.max(1, math.floor(tonumber(s.level) or 1))
	local xp = math.clamp(math.floor(tonumber(s.xp) or 0), 0, SKILL_PACK - 1)
	return level * SKILL_PACK + xp
end

local function writeSkills(player)
	local profile = profiles().Get(player)
	if not profile then return end
	local uid = player.UserId
	lastSkill[uid] = lastSkill[uid] or {}
	for _, skill in ipairs(LeaderboardService.SKILLS) do
		local v = skillValue(profile, skill)
		if v and lastSkill[uid][skill] ~= v then
			local ok = pcall(function() skillStore(skill):SetAsync(tostring(uid), v) end)
			if ok then lastSkill[uid][skill] = v end
		end
	end
end

local function flush()
	local batch = pending
	pending = {}
	local now = os.time()
	for uid, stats in pairs(batch) do
		local key = tostring(uid)
		for stat, tiers in pairs(stats) do
			for tk, n in pairs(tiers) do
				for _, g in ipairs(GRAINS) do
					pcall(function()
						bucketMap(stat, tk, g.grain, now // g.grain):UpdateAsync(key, function(old)
							local v = (tonumber(old) or 0) + n
							return v, v
						end, g.ttl)
					end)
				end
				pcall(function() allTimeStore(stat, tk):IncrementAsync(key, n) end)
			end
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		writeSkills(player)
	end
end

-------------------------------------------------------------------------------------------
-- Reads
-------------------------------------------------------------------------------------------

local nameCache = {} -- [userId] = display name
local function names(ids)
	local missing = {}
	for _, id in ipairs(ids) do
		if not nameCache[id] then table.insert(missing, id) end
	end
	if #missing > 0 then
		local ok, infos = pcall(function() return UserService:GetUserInfosByUserIdsAsync(missing) end)
		if ok and type(infos) == "table" then
			for _, info in ipairs(infos) do
				nameCache[info.Id] = (info.DisplayName ~= "" and info.DisplayName) or info.Username
			end
		end
	end
	local out = {}
	for _, id in ipairs(ids) do out[id] = nameCache[id] or ("Player " .. tostring(id)) end
	return out
end

-- { { userId, value } } sorted high to low, or nil when the stores can't be reached.
local function readOrdered(store)
	local ok, rows = pcall(function()
		local page = store:GetSortedAsync(false, TOP_N):GetCurrentPage()
		local out = {}
		for _, entry in ipairs(page) do
			table.insert(out, { userId = tonumber(entry.key), value = entry.value })
		end
		return out
	end)
	return ok and rows or nil
end

local function readWindow(stat, tk, window)
	local spec = WINDOWS[window]
	local now = os.time()
	local totals = {}
	local anyOk = false
	for i = 0, spec.count - 1 do
		local ok, items = pcall(function()
			return bucketMap(stat, tk, spec.grain, now // spec.grain - i):GetRangeAsync(Enum.SortDirection.Descending, READ_N)
		end)
		if ok then
			anyOk = true
			for _, item in ipairs(items) do
				local uid = tonumber(item.key)
				if uid then totals[uid] = (totals[uid] or 0) + (tonumber(item.value) or 0) end
			end
		end
	end
	if not anyOk then return nil end
	local rows = {}
	for uid, v in pairs(totals) do table.insert(rows, { userId = uid, value = v }) end
	table.sort(rows, function(a, b) return a.value > b.value end)
	return rows
end

local cache = {} -- [cacheKey] = { at, rows }

-- board: "skill" (a = skill) | "kills" / "score" (a = period, b = tier 1..5 or nil = all).
-- Returns { available, rows = { { rank, userId, name, value, level?, xp? } }, you = { rank?, value? } }.
function LeaderboardService.Read(player, board, a, b)
	local cacheKey, fetch, decode
	if board == "skill" then
		if not table.find(LeaderboardService.SKILLS, a) then return nil end
		cacheKey = "skill|" .. a
		fetch = function() return readOrdered(skillStore(a)) end
		decode = function(v) return math.floor(v / SKILL_PACK), v % SKILL_PACK end
	elseif board == "kills" or board == "score" then
		if not table.find(LeaderboardService.PERIODS, a) then return nil end
		local tk = tierKey(b)
		cacheKey = board .. "|" .. a .. "|" .. tk
		fetch = function()
			if a == "All" then return readOrdered(allTimeStore(board, tk)) end
			return readWindow(board, tk, a)
		end
	else
		return nil
	end

	local hit = cache[cacheKey]
	if not hit or os.clock() - hit.at > CACHE_SECONDS then
		hit = { at = os.clock(), rows = fetch() }
		cache[cacheKey] = hit
	end
	if not hit.rows then return { available = false, rows = {} } end

	local top, ids = {}, {}
	for i = 1, math.min(TOP_N, #hit.rows) do
		table.insert(ids, hit.rows[i].userId)
	end
	local nameOf = names(ids)
	local you = nil
	for i, row in ipairs(hit.rows) do
		if row.userId == player.UserId then
			you = { rank = i, value = row.value }
		end
		if i <= TOP_N then
			local entry = { rank = i, userId = row.userId, name = nameOf[row.userId], value = row.value }
			if decode then entry.level, entry.xp = decode(row.value) end
			table.insert(top, entry)
		end
	end
	if board == "skill" and not you then
		local v = skillValue(profiles().Get(player), a)
		if v then you = { value = v } end
	end
	if you and decode then you.level, you.xp = decode(you.value) end
	return { available = true, rows = top, you = you }
end

-------------------------------------------------------------------------------------------
-- Lifecycle
-------------------------------------------------------------------------------------------

local started = false
function LeaderboardService.Start()
	if started then return end
	started = true
	task.spawn(function()
		while true do
			task.wait(FLUSH_EVERY)
			flush()
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		writeSkills(player)
		lastSkill[player.UserId] = nil
	end)
	game:BindToClose(flush)
end

return LeaderboardService
