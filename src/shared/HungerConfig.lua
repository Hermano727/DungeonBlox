-- HungerConfig: passive drain + sprint gate (single source of truth).
return {
	MAX_HUNGER = 100,
	-- Hunger lost per second at all times (tune for session length).
	PASSIVE_DRAIN_PER_SEC = 0.6,
	-- Below this value (0..MAX) shift-sprint is blocked server-side.
	MIN_HUNGER_TO_SPRINT = 18,
}
