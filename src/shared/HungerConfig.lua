-- HungerConfig: Minecraft-style exhaustion -> hunger pipeline.
-- Replaces the old flat 0-100 passive-drain model (2026-09-07, per direct
-- request) with real Minecraft exhaustion costs mapped onto our own
-- movement/combat systems. See HungerData for the accumulator itself.
--
-- Saturation was tried as a second buffer stat (matching vanilla Minecraft)
-- but removed the same day per direct feedback -- overcomplicated things for
-- little benefit here. Exhaustion now drains Hunger directly.
return {
	MAX_HUNGER = 5, -- visible hunger pips (was 100 on the old flat scale)

	-- Exhaustion needed to drain one pip. Minecraft's real per-icon cost is
	-- 8.0 (2 food points * 4.0 exhaustion/point) -- we kept that unscaled at
	-- first (5 pips instead of 10 was meant to be the only speedup), but
	-- playtesting showed the whole bar draining in ~2 minutes, way too fast.
	-- Tripled here (2026-09-07, per direct feedback: "make the rates slower
	-- by 3x") on top of the pip-count halving, so the bar now takes roughly
	-- 6x longer to empty than an unscaled 1:1 Minecraft mapping would.
	EXHAUSTION_PER_PIP = 24.0,

	-- Below this many hunger pips, sprinting is blocked server-side (was 18
	-- out of 100, ~18%; 1 out of 5 pips is the closest equivalent).
	MIN_HUNGER_TO_SPRINT = 1,

	-- Per-action exhaustion costs, taken directly from Minecraft's real
	-- values (unscaled) and mapped onto our own movement/combat systems.
	-- Standing completely still costs nothing, same as Minecraft.
	EXHAUSTION = {
		WALK_PER_STUD = 0.01,
		SPRINT_PER_STUD = 0.1,
		SWIM_PER_STUD = 0.015,
		JUMP = 0.2,
		ATTACK_HIT = 0.3,
		DAMAGE_TAKEN = 0.3,
		BLOCK_BROKEN = 0.025, -- not wired in yet -- no central mining/block-break
		                      -- server hook found so far; fast-follow once located
	},
}
