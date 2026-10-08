--[[
	FishingConfig
	Single source of truth for the spear-fishing catch table, matching the Config/Service split
	already used by MiningExcavationConfig, EnergyConfig and HungerConfig. Previously this
	weighted table (and its roll function) lived as a local in SpearFishHandler.server.lua;
	moving it here makes it a config-driven data table like the rest of the profession systems
	instead of the one outlier still hardcoded inside its service script, and gives it an
	obvious spot to grow into (new fish tiers, seasonal tables, per-zone tables, etc.) without
	touching handler logic.

	NOT changed: ids/weights/tiers are copied verbatim from the previous inline table -- this is
	a structural move, not a drop-rate change.

	All entries must reference raw-fish ItemDefinitions (Kind "Material", SubKind "RawFish"
	since 2026-10-03: an ingredient, cooked at a fire before it can be eaten).
]]

local FishingConfig = {}

FishingConfig.FishDropTable = {
	{ id = "Fish",       weight = 60, tier = 1 },
	{ id = "SwiftFish",  weight = 18, tier = 2 },
	{ id = "LuckyFish",  weight = 18, tier = 2 },
	{ id = "GoldenFish", weight = 4,  tier = 4 },
}

-- Weighted random pick from FishDropTable. Kept alongside the data (same convention as
-- MiningExcavationConfig.rollTileOreAmount) rather than duplicated at each call site.
function FishingConfig.RollFishEntry()
	local total = 0
	for _, e in ipairs(FishingConfig.FishDropTable) do
		total = total + e.weight
	end
	local r = math.random() * total
	local cum = 0
	for _, e in ipairs(FishingConfig.FishDropTable) do
		cum = cum + e.weight
		if r <= cum then
			return e
		end
	end
	return FishingConfig.FishDropTable[1]
end

---------------------------------------------------------------------------
-- The spear-fishing loop (2026-10-03). SpearFishHandler judges it, FishingClient plays it.
--   1. Approach unseen: fish shadows circle in each pool (a part tagged FishingPool, with a
--      Radius attribute). Sprinting or jumping near a pool spooks them deep for a few seconds.
--   2. Spear: the camera swings over the pool. Hold to draw the spear, release to throw at the
--      cursor. It lands FLIGHT seconds later, so you lead the fish. One hit (HITS_TO_STUN) spears
--      it. Spears are unlimited; the grade counts how many it took.
--   3. Haul: the spear stays in the fish on its line. Keep your catch zone on the fish as
--      it thrashes (hold to raise the zone, release to let it fall) until the line is in.
--   Then the next fish swim in: the session is continuous until Esc, walking off or a hit.
-- Fish paths are a pure function of (seed, fish index, path time), so the server re-simulates
-- exactly what the player saw and judges each throw itself.
---------------------------------------------------------------------------

FishingConfig.POOL_TAG = "FishingPool"
FishingConfig.START_RANGE = 22 -- studs from the pool's edge to start
FishingConfig.SESSION_RANGE = 34 -- walking further than this from the pool ends the session
FishingConfig.SPOOK = { RADIUS = 26, TIME = 4 }
FishingConfig.AMBIENT_FISH = 3 -- shadows per pool before you take aim
FishingConfig.SESSION_FISH = { MIN = 3, MAX = 4 }
-- Base swim speed (Behaviour.speed multiplies it). Was 2.0 (too hard), cut by a third 2026-10-03.
FishingConfig.SWIM_SPEED = 1.34
-- How much the fish change direction: scales the bursts (Behaviour.dart) and the quick side-to-side
-- wiggle on top of the main swim. Cut by a third 2026-10-03.
FishingConfig.TURN_SCALE = 0.67

FishingConfig.THROW = {
	FLIGHT = 0.5, -- seconds from release to impact: the lead you aim for
	HITS_TO_STUN = 1,
	HIT_RADIUS = 1.25, -- studs, scaled by the fish's size
	SLOW_PER_HIT = 0.22, -- each hit takes this off the fish's speed (it never drops below 0.3)
}

FishingConfig.HAUL = {
	MIN_TIME = 1.7, -- a catch reported sooner than this is refused (a flawless haul takes (1 - START) / FILL)
	ZONE = 0.26, -- the catch zone's share of the bar
	FILL = 0.36, -- progress per second while the fish is in the zone
	DRAIN = 0.28, -- per second while it isn't
	START = 0.3,
	GRACE = 0.6, -- seconds at the start: zone and fish both centred, the zone doesn't sink, the fish doesn't lunge
	RISE = 3.2, -- zone acceleration while held (bar heights / s^2)
	FALL = 2.6,
}

-- How each catch behaves. speed scales the swim, dart how much it bursts and pauses,
-- haulJump how far it leaps along the haul bar. tint colours its shadow.
FishingConfig.Behaviour = {
	Fish = { speed = 1.0, dart = 0.5, size = 1.0, haulJump = 0.3, tint = Color3.fromRGB(16, 22, 26) },
	SwiftFish = { speed = 1.45, dart = 0.75, size = 0.85, haulJump = 0.45, tint = Color3.fromRGB(18, 30, 38) },
	LuckyFish = { speed = 1.15, dart = 0.6, size = 1.0, haulJump = 0.38, tint = Color3.fromRGB(20, 34, 22) },
	GoldenFish = { speed = 1.6, dart = 0.85, size = 1.15, haulJump = 0.55, tint = Color3.fromRGB(70, 56, 12) },
}

function FishingConfig.BehaviourFor(fishId)
	return FishingConfig.Behaviour[fishId] or FishingConfig.Behaviour.Fish
end

-- XP: a catch gives CATCH + TIER per tier above 1, plus a grade bonus. A fish that gets off the
-- line still teaches something (SNAP + ESCAPE_PER_HIT per hit landed).
FishingConfig.XP = { CATCH = 10, TIER = 6, ESCAPE_PER_HIT = 2, SNAP = 3 }
FishingConfig.GRADE_XP_BONUS = { Pristine = 8, Clean = 4, Rough = 0 }
FishingConfig.GRADE_COLORS = {
	Pristine = Color3.fromRGB(150, 220, 255),
	Clean = Color3.fromRGB(150, 230, 140),
	Rough = Color3.fromRGB(230, 200, 120),
	Escaped = Color3.fromRGB(230, 110, 90),
}

-- Grade from how many spears it took: first throw Pristine, second Clean, after that Rough.
function FishingConfig.Grade(throwsUsed)
	if throwsUsed <= FishingConfig.THROW.HITS_TO_STUN then return "Pristine" end
	if throwsUsed <= FishingConfig.THROW.HITS_TO_STUN + 1 then return "Clean" end
	return "Rough"
end

---------------------------------------------------------------------------
-- The catch show (2026-10-03): when a fish is landed, its model leaps out of the water to just
-- above the angler's head, hangs there turning in its effects, then goes into the bag.
-- SpearFishHandler broadcasts it to everyone within SHOW_RADIUS (FishCatchVisuals plays it).
-- Models live in ServerStorage.FishModels (Studio-owned) and are copied to
-- ReplicatedStorage[VISUALS_FOLDER] at server start. A fish without an entry has no show yet.
---------------------------------------------------------------------------

FishingConfig.VISUALS_FOLDER = "FishVisuals"
FishingConfig.SHOW_RADIUS = 150

-- effect: how loud the show is. Golden is the rare one and must be the most obvious.
--   trailRate: sparkles per second off the fish; burst: glints at the top of the leap;
--   size: sparkle size; halo: a big soft glow behind it; light: PointLight range (0 = none);
--   speed: the swift fish's wind trail, tail streaks and speed-line burst; leap: leap seconds.
FishingConfig.CATCH_SHOW = {
	GoldenFish = {
		model = "T3_GoldenFish",
		color = Color3.fromRGB(255, 214, 96), deep = Color3.fromRGB(255, 160, 32),
		trailRate = 55, burst = 60, size = 0.45, halo = true, light = 16, lightBrightness = 1.5, hold = 1.6,
	},
	Fish = {
		-- The common catch: the quietest show, a few water droplets shaken off.
		model = "T1_Fish",
		color = Color3.fromRGB(214, 236, 248), deep = Color3.fromRGB(150, 196, 226),
		trailRate = 6, burst = 8, size = 0.14, halo = false, light = 0, hold = 0.7,
	},
	SwiftFish = {
		model = "T2_SwiftFish",
		color = Color3.fromRGB(150, 216, 255), deep = Color3.fromRGB(60, 140, 210),
		trailRate = 0, burst = 0, size = 0.2, halo = false, light = 8, hold = 1.2,
		speed = true, leap = 0.45, -- wind trail, streaks off the tail, a burst of speed lines
	},
	LuckyFish = {
		model = "T2_LuckyFish",
		color = Color3.fromRGB(150, 232, 120), deep = Color3.fromRGB(70, 170, 60),
		trailRate = 14, burst = 14, size = 0.25, halo = false, light = 0, hold = 1.0,
	},
}

---------------------------------------------------------------------------
-- Deterministic fish movement (server and client run exactly this)
---------------------------------------------------------------------------

-- One fish's swim parameters from the session seed.
function FishingConfig.FishParams(seed, index)
	local rng = Random.new(seed * 7919 + index * 104729)
	return {
		a1 = rng:NextNumber(0.45, 0.7), a2 = rng:NextNumber(0.12, 0.26),
		b1 = rng:NextNumber(0.45, 0.7), b2 = rng:NextNumber(0.12, 0.26),
		w1 = rng:NextNumber(0.28, 0.42), w2 = rng:NextNumber(0.7, 1.1),
		v1 = rng:NextNumber(0.28, 0.42), v2 = rng:NextNumber(0.7, 1.1),
		p1 = rng:NextNumber(0, 6.283), p2 = rng:NextNumber(0, 6.283),
		p3 = rng:NextNumber(0, 6.283), p4 = rng:NextNumber(0, 6.283),
		dartFreq = rng:NextNumber(0.3, 0.55), dartPhase = rng:NextNumber(0, 6.283),
	}
end

-- Path time after hits: each hit (seconds since the session started) slows the fish from then on.
function FishingConfig.PathTime(t, hitTimes)
	local tau, last, factor = 0, 0, 1
	for _, h in ipairs(hitTimes or {}) do
		if t <= h then
			return tau + (t - last) * factor
		end
		tau += (h - last) * factor
		last = h
		factor = math.max(0.3, factor - FishingConfig.THROW.SLOW_PER_HIT)
	end
	return tau + (t - last) * factor
end

-- Where a fish is (pool-local x, z in studs) at path time tau.
function FishingConfig.FishPosition(params, behaviour, tau, radius)
	tau *= behaviour.speed * FishingConfig.SWIM_SPEED
	-- Bursts and pauses: the swim clock runs faster and slower in turn (never backwards).
	local f = params.dartFreq * math.pi * 2
	local turn = FishingConfig.TURN_SCALE
	local warped = tau + behaviour.dart * turn * math.sin(f * tau + params.dartPhase) / f
	local x = params.a1 * math.sin(params.w1 * warped + params.p1) + params.a2 * turn * math.sin(params.w2 * warped + params.p2)
	local z = params.b1 * math.sin(params.v1 * warped + params.p3) + params.b2 * turn * math.cos(params.v2 * warped + params.p4)
	local v = Vector2.new(x, z) * radius
	local limit = radius * 0.88
	if v.Magnitude > limit then
		v = v.Unit * limit
	end
	return v
end

return FishingConfig
