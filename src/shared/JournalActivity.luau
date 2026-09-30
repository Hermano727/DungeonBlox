--[[
	JournalActivity -- time-bucketed loot activity for the Journal's Activity page.

	Stored on the modern profile at profile.activity (NOT pushed with the profile snapshot:
	ProfileService strips it; the page asks for one window through GameEvents/JournalRequest):

		profile.activity[tierKey][grain][bucketStartKey] = bucket
			tierKey         "1".."5"
			grain           "m5" 5-minute (kept 2 h), "h" hourly (7 days), "d" daily (90 days)
			bucketStartKey  tostring(os.time() bucket start, UTC)
			bucket          { o = overworld score, d = dungeon score, k = kills, r = runs cleared,
			                  w = { drops per rarity x5 }, x = { expected drops per rarity x5 } }

	Every key is a string and every array is dense, so it survives JSON / toSaveForm (the
	same rule the slot lists follow). Buckets older than their grain's keep window are pruned
	whenever a new bucket opens.

	Writers (server): LootService (score + kills, both paths), DungeonRunService (dungeon
	wins/expected at cash-out, runs cleared). "Expected" is exact: LootPityService sums each
	roll's real chance (streak included), so actual vs expected is a true luck measure.

	Readers: JournalActivity.Summary(profile, tier, window) -> current totals for the window,
	chart points, and the average window of the same length over the player's history.
]]

local LootPityConfig = require(script.Parent:WaitForChild("LootPityConfig"))

local JournalActivity = {}

JournalActivity.RARITIES = LootPityConfig.RARITIES
local RARITY_COUNT = #LootPityConfig.RARITIES
local RARITY_INDEX = {}
for i, rarity in ipairs(LootPityConfig.RARITIES) do RARITY_INDEX[rarity] = i end

local GRAINS = {
	m5 = { size = 300,   keep = 2 * 3600 },
	h  = { size = 3600,  keep = 7 * 86400 },
	d  = { size = 86400, keep = 90 * 86400 },
}

-- window -> which grain the current total / chart use, how many slots, how the average is taken
local WINDOWS = {
	["1H"]  = { grain = "m5", slots = 12, length = 3600,       avgGrain = "h", avgBlock = 1,  minSamples = 3 },
	["24H"] = { grain = "h",  slots = 24, length = 86400,      avgGrain = "d", avgBlock = 1,  minSamples = 3 },
	["7D"]  = { grain = "d",  slots = 7,  length = 7 * 86400,  avgGrain = "d", avgBlock = 7,  minSamples = 2 },
	["30D"] = { grain = "d",  slots = 30, length = 30 * 86400, avgGrain = "d", avgBlock = 30, minSamples = 1 },
}
JournalActivity.WINDOWS = { "1H", "24H", "7D", "30D" }

local function newBucket()
	local w, x = {}, {}
	for i = 1, RARITY_COUNT do w[i] = 0; x[i] = 0 end
	return { o = 0, d = 0, k = 0, r = 0, w = w, x = x }
end

local function addInto(into, from)
	into.o += from.o or 0
	into.d += from.d or 0
	into.k += from.k or 0
	into.r += from.r or 0
	for i = 1, RARITY_COUNT do
		into.w[i] += (from.w and from.w[i]) or 0
		into.x[i] += (from.x and from.x[i]) or 0
	end
end

local function isActive(bucket)
	return (bucket.o or 0) + (bucket.d or 0) + (bucket.k or 0) + (bucket.r or 0) > 0
end

local function tierTable(profile, tier, create)
	if type(profile) ~= "table" then return nil end
	if type(profile.activity) ~= "table" then
		if not create then return nil end
		profile.activity = {}
	end
	local key = tostring(math.clamp(math.floor(tonumber(tier) or 1), 1, 5))
	local t = profile.activity[key]
	if type(t) ~= "table" then
		if not create then return nil end
		t = {}
		profile.activity[key] = t
	end
	return t
end

--[[
	Add(profile, tier, fields, now?)
	fields: any of
		o, d, k, r          numbers
		won                 list of rarity names (e.g. LootPityService.ResolveScore's result)
		expected            { [rarityName] = expected drops } (ResolveScore's second result)
]]
function JournalActivity.Add(profile, tier, fields, now)
	local t = tierTable(profile, tier, true)
	if not t or type(fields) ~= "table" then return end
	now = now or os.time()

	local delta = newBucket()
	delta.o = math.max(0, tonumber(fields.o) or 0)
	delta.d = math.max(0, tonumber(fields.d) or 0)
	delta.k = math.max(0, tonumber(fields.k) or 0)
	delta.r = math.max(0, tonumber(fields.r) or 0)
	if type(fields.won) == "table" then
		for _, rarity in ipairs(fields.won) do
			local i = RARITY_INDEX[rarity]
			if i then delta.w[i] += 1 end
		end
	end
	if type(fields.expected) == "table" then
		for rarity, value in pairs(fields.expected) do
			local i = RARITY_INDEX[rarity]
			if i then delta.x[i] += math.max(0, tonumber(value) or 0) end
		end
	end
	local anything = isActive(delta)
	for i = 1, RARITY_COUNT do
		if delta.w[i] > 0 or delta.x[i] > 0 then anything = true end
	end
	if not anything then return end

	for grainName, grain in pairs(GRAINS) do
		local buckets = t[grainName]
		if type(buckets) ~= "table" then
			buckets = {}
			t[grainName] = buckets
		end
		local start = now - (now % grain.size)
		local key = tostring(start)
		local bucket = buckets[key]
		if type(bucket) ~= "table" then
			bucket = newBucket()
			buckets[key] = bucket
			-- A new bucket opened: drop the ones that fell out of this grain's window.
			local cutoff = now - grain.keep
			for k in pairs(buckets) do
				if (tonumber(k) or 0) < cutoff then buckets[k] = nil end
			end
		end
		addInto(bucket, delta)
		-- Expected drops are fractional; keep 2 decimals so the save stays small.
		for i = 1, RARITY_COUNT do
			bucket.x[i] = math.floor(bucket.x[i] * 100 + 0.5) / 100
		end
	end
end

local function sumRange(buckets, fromTime, toTime)
	local total = newBucket()
	if type(buckets) ~= "table" then return total end
	for key, bucket in pairs(buckets) do
		local start = tonumber(key)
		if start and start >= fromTime and start < toTime and type(bucket) == "table" then
			addInto(total, bucket)
		end
	end
	return total
end

--[[
	Summary(profile, tier, window, now?) -> {
		window, current = bucket, chart = { { t = slotStart, v = score } oldest first },
		average = bucket or nil, samples = number, minSamples = number,
	}
	current covers the last `length` seconds (the running slot included). average is the mean
	of earlier windows of the same length in which the player did anything; nil until there
	are minSamples of them.
]]
function JournalActivity.Summary(profile, tier, window, now)
	local spec = WINDOWS[window] or WINDOWS["24H"]
	now = now or os.time()
	local t = tierTable(profile, tier, false) or {}
	local grain = GRAINS[spec.grain]
	local buckets = t[spec.grain]

	-- Slots aligned to the grain; the last one is the running slot.
	local lastStart = now - (now % grain.size)
	local firstStart = lastStart - (spec.slots - 1) * grain.size
	local current = sumRange(buckets, firstStart, lastStart + grain.size)

	local chart = {}
	for i = 0, spec.slots - 1 do
		local s = firstStart + i * grain.size
		local b = type(buckets) == "table" and buckets[tostring(s)] or nil
		table.insert(chart, { t = s, v = b and ((b.o or 0) + (b.d or 0)) or 0 })
	end

	-- Average: earlier blocks of the same length, stepping back from the window's start.
	local avgGrain = GRAINS[spec.avgGrain]
	local avgBuckets = t[spec.avgGrain]
	local blockLen = spec.avgBlock * avgGrain.size
	local windowStartAligned = firstStart - (firstStart % avgGrain.size)
	local sum, samples = newBucket(), 0
	local blockEnd = windowStartAligned
	while blockEnd - blockLen >= now - avgGrain.keep do
		local block = sumRange(avgBuckets, blockEnd - blockLen, blockEnd)
		if isActive(block) then
			addInto(sum, block)
			samples += 1
		end
		blockEnd -= blockLen
	end
	local average = nil
	if samples >= spec.minSamples and samples > 0 then
		average = newBucket()
		average.o, average.d = sum.o / samples, sum.d / samples
		average.k, average.r = sum.k / samples, sum.r / samples
		for i = 1, RARITY_COUNT do
			average.w[i] = sum.w[i] / samples
			average.x[i] = sum.x[i] / samples
		end
	end

	-- Summed floats pick up noise (0.060000000000000005); expected drops read to 2 decimals.
	for _, b in ipairs({ current, average }) do
		for i = 1, RARITY_COUNT do
			b.x[i] = math.floor(b.x[i] * 100 + 0.5) / 100
		end
	end

	return {
		window = window,
		grainSize = grain.size,
		current = current,
		chart = chart,
		average = average,
		samples = samples,
		minSamples = spec.minSamples,
	}
end

-- DEV ONLY (F8 Profile tab, "Seed activity"): fills the last 30 days of `tier` with plausible
-- play sessions so the Activity page can be checked without days of real play. Written
-- oldest first through Add, so pruning behaves exactly as it does live.
function JournalActivity.SeedForTesting(profile, tier, now)
	now = now or os.time()
	local rng = Random.new(now)
	local base = LootPityConfig.BASE_CHANCE[math.clamp(tier, 1, 5)]
	for hoursAgo = 30 * 24, 0, -1 do
		-- Evenings are busier; about a third of hours have play at all.
		local at = now - hoursAgo * 3600
		local hour = (at // 3600) % 24
		local active = rng:NextNumber() < ((hour >= 17 and hour <= 23) and 0.6 or 0.2)
		if active or hoursAgo == 0 then
			for _ = 1, 4 do -- spread across the hour so the 5-minute grain has shape too
				local t = at - rng:NextInteger(0, 3599)
				if t > now then t = now end
				local kills = rng:NextInteger(3, 18)
				local overworld = kills
				local dungeon = rng:NextNumber() < 0.15 and rng:NextInteger(20, 60) or 0
				local score = overworld + dungeon
				local won, expected = {}, {}
				for _, rarity in ipairs(LootPityConfig.RARITIES) do
					local chance = base[rarity] or 0
					expected[rarity] = chance * score
					for _ = 1, score do
						if rng:NextNumber() < chance then table.insert(won, rarity) end
					end
				end
				JournalActivity.Add(profile, tier, {
					o = overworld, d = dungeon, k = kills, r = dungeon > 0 and 1 or 0,
					won = won, expected = expected,
				}, t)
			end
		end
	end
end

-- DEV ONLY: forget all activity history for this profile.
function JournalActivity.Clear(profile)
	if type(profile) == "table" then profile.activity = {} end
end

return JournalActivity
