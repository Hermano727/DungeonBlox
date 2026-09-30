-- First-pass tunables. Percent item values are proc chances except Life Steal,
-- which is the percent of actual health removed returned to the attacker.
return {
	CleaveDamageFraction = 0.30,
	CleaveRadius = 5,
	CleaveMaxTargets = 3,
	-- A bleed deals this share of the hit that applied it, spread evenly over
	-- BleedTicks ticks BleedInterval apart (0.5 over 3x1s = 50% of the hit over
	-- 3 seconds). Scaling off the hit means a bleed is worth what the weapon is
	-- worth, with no per-tier damage table to maintain.
	BleedDamageFraction = 0.50,
	BleedTicks = 3,
	BleedInterval = 1,
	-- Bleeds STACK: every proc is its own independent bleed. The cap only exists
	-- so a very fast weapon can't pile up unbounded timers; the oldest is dropped.
	BleedMaxStacks = 5,
	BlindDuration = 2,
	BlindMissChance = 0.50,
	SlowDuration = 3,
	SlowMultiplier = 0.80, -- -20% movement speed while slowed
	-- Elemental damage chills on its own, independent of the Slowness substat:
	-- a flat per-hit chance for any hit that dealt elemental damage. Same
	-- non-stacking status, so an elemental proc and a Slowness proc can only
	-- ever refresh the one timer.
	ElementalSlowChance = 5,
}
