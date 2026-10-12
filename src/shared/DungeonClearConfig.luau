--[[
	DungeonClearConfig -- the end-of-dungeon clear sequence: Benediction -> Pyres -> Reliquary
	Ring -> Mythic Judgement (docs/dungeon-clear-sequence.md).

	Shared by both sides on purpose: the server (SSS/DungeonClearSequence) lays out the whole
	timeline from these numbers and sends it once; the client (client/DungeonClearSequence) only
	evaluates that timeline against the server clock. Tune pacing HERE, never in either side.

	The rolls themselves are already decided (and granted) by the time any of this plays: a run's
	score is rolled once at the clear (DungeonScoreService.EndRun), the boss Mythic at the kill.
	The show is theatre on top of known results. A rarity "climb" may flicker toward a higher
	colour, but always settles on the real one.
]]

local Config = {}

-- Rarity ladder, low to high. The ring reveals in this order (best last).
Config.RARITY_ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }
local RANK = {}
for index, name in ipairs(Config.RARITY_ORDER) do RANK[name] = index end

function Config.RarityRank(rarity)
	return RANK[rarity] or 1
end

----------------------------------------------------------------------
-- Auto-scrap (DungeonRunService.EndRunFor)
--
-- A run drop at or below this rarity is granted as tier scrap instead of the item, priced by
-- ProfileService.SalvageYield (the Merchant's own formula: Common 4, Uncommon 8, ...). Whatever
-- is NOT scrapped is what the Reliquary Ring reveals. nil = nothing is scrapped at that tier.
----------------------------------------------------------------------
Config.AUTO_SCRAP_MAX_RARITY = {
	[1] = "Uncommon",
	[2] = "Uncommon",
	[3] = "Common",
	[4] = "Common",
	[5] = nil,
}

function Config.IsAutoScrapped(tier, rarity)
	local cap = Config.AUTO_SCRAP_MAX_RARITY[math.clamp(math.floor(tonumber(tier) or 1), 1, 5)]
	if not cap or rarity == "Mythic" then return false end
	return Config.RarityRank(rarity) <= Config.RarityRank(cap)
end

----------------------------------------------------------------------
-- Timeline (seconds). Stage starts are computed by the server from these + the result counts.
----------------------------------------------------------------------

-- Boss death -> sequence start. Miasma's defeat presentation is 3.6 s
-- (MiasmaEncounterConfig.Defeat Upright 1.2 + Flat 2.4); a beat after it.
Config.DEATH_LEAD = 4.2

-- The opening of the show, right after the main boss's death animation: the room goes dark, the
-- boss's spectral echo rises (smoke, burning eyes) and a shockwave of light tears it apart. The
-- Benediction follows that light.
Config.Echo = {
	Blackout = 1.0,   -- every light dies
	Rise = 2.0,       -- the full-size echo rises and roars
	Tear = 1.0,       -- torn apart in a shockwave of light
}

Config.Benediction = {
	Silence = 1.0,   -- music cut, lights dim, nothing
	Descend = 1.4,   -- shaft punches down, the core sinks into it
	Unfurl = 0.9,    -- wings open
	Hold = 3.0,      -- the angel turns two full circles, ending facing the party
	Fade = 2.0,      -- it rises back up the shaft, wings folding, the light thinning behind it
	Beat = 1.5,      -- near silence before the loot starts
	CoreHeight = 26, -- studs above the floor the core settles at
	ShaftTop = 80,   -- arena-local Y the shaft starts from (the ceiling opening)
}

Config.Pyres = {
	Radius = 30,          -- braziers sit on this circle around the arena centre (basin is 12)
	Rise = 1.2,           -- brazier grinds up out of the floor
	EmberPour = 2.4,      -- embers stream in, counter climbs
	Burn = 1.0,           -- fire roars, scrap burns off ("+12 Scrap")
	RelicLift = 1.4,      -- shrouded relics lift out of the fire
	Gutter = 1.0,         -- a brazier with nothing kept gutters to coals over this
	MaxVisibleEmbers = 60,-- ember streams are capped; the counter still reaches the real score
}

Config.Ring = {
	Radius = 20,
	Height = 20,          -- arena-local Y of the ring (was 30; 33% lower)
	Gather = 2.0,         -- relics spiral up from the braziers into the ring
	SpinUp = 1.2,
	BaseSpin = 0.35,      -- rad/s once spun up
	-- Per relic, the SAME for every relic and every drop count (no speeding up when there are many):
	-- the held breath (its glow cycles through random rarities, then settles on the real one), the
	-- shroud burning off, then a short firework in the real rarity's colour; the next relic starts
	-- when that finishes.
	Breath = 1.5,
	Burn = 0.3,           -- shroud burning off
	Settle = 0.25,        -- the reveal firework; the next relic starts after it
	CycleStep = 0.12,     -- the glow picks a new random rarity this often while it breathes
	CycleSettle = 0.2,    -- the last stretch of the breath shows the real rarity's colour
	SlowFrom = "Epic",    -- the ring slows from this rarity up
	StopFrom = "Legendary",-- the ring stops dead (others dim) from this rarity up
	Disperse = 1.6,       -- revealed items streak down to their owners
}

Config.Judgement = {
	Rise = 1.4,           -- a miniboss's echo rises from where it fell
	Shatter = 0.8,        -- echo shatters, relic forms
	-- The relic's roulette hop: first the neutral hops (round every brazier, whoever is eligible, so a
	-- solo test still bounces a lot), then one landing per eligible member where the verdict shows.
	-- Each hop takes HopGrowth times as long as the one before, from HopStart: tick tick tick ... tick.
	Hops = 8,             -- neutral hops before the verdicts
	HopStart = 0.3,       -- seconds for the first hop
	HopGrowth = 1.13,     -- each hop slower than the last
	-- The fake-out on the LAST landing: a winner's relic dies (goes dark and sags) before it roars
	-- back; a loser's relic flares as if it had won, then gutters. Both settle on the real result.
	FakeOut = 1.5,        -- seconds between that landing and its true reveal
	FakeOutChance = 0.5,
	Verdict = 1.6,        -- winners' pillars / losers' grey / crumble
	Gap = 0.8,            -- between judgements
	-- The main boss's judgement, on top of the above (its echo plays at the start of the show: Echo).
	Final = {
		Hops = 12,        -- the main boss: a longer roulette ...
		FakeOutChance = 1, -- ... and always a fake-out
		Descend = 2.4,    -- the relic sinks from the dark above, trailing fire
	},
}

-- The cleared summary panel opens this long after the sequence ends.
Config.SUMMARY_AFTER = 0.6

-- How long the party may linger after the sequence before the realm is torn down.
Config.LEAVE_WINDOW = 20

----------------------------------------------------------------------
-- Dev: forced Mythic outcomes (F8 Mythic tab). Server-checked against DevRoster.
----------------------------------------------------------------------
Config.MYTHIC_FORCE_ATTR = "DevMythicForce" -- player attribute: nil | "win" | "loss"

return Config
