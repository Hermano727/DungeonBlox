-- EnergyConfig: Single source of truth for all energy system constants.
-- Change a value here and it automatically updates everywhere.
return {
	MAX_ENERGY         = 100,   -- Maximum energy a player can have
	REGEN_RATE         = 10,     -- Fallback only, until the profile loads. The real base is profile.stats.combat.energyRegen (8)
	                             -- plus armor's Energy substat, pushed by ProfileService -> EnergyData.setRegenRate
	SPRINT_COST        = 25,    -- Energy drained per second while sprinting (on top of regen: 8 base + armor must reach 25 to sprint forever)
	DASH_COST          = 25,    -- Energy consumed per dash (requires at least this much)
	DASH_COOLDOWN      = 4.0,   -- Seconds between dashes
	SWING_COST         = 10,    -- Energy drained per swing (Sword baseline)
	WEAPON_SWING_MULT  = { Sword=1.00, Scythe=1.05, Axe=1.10, Mace=1.15, Bow=1.20 },
	PANT_WALK_SPEED    = 8,     -- WalkSpeed while panting (0 energy) until stamina is full
	LOCKOUT_DURATION   = 3,     -- Deprecated: panting lasts until energy refills (kept for compatibility)
	REGEN_IN_LOCKOUT   = false, -- Deprecated; panting uses normal regen to refill
	SPRINT_SPEED       = 14.4,  -- WalkSpeed while sprinting (was 24, -40%)
	NORMAL_SPEED       = 9.6,   -- Default WalkSpeed (was 16, -40%)
	BACKWARD_SPEED_MULT = 0.4,   -- walking backward: 60% slower than the same movement forward, and never a sprint
	BACKWARD_DOT        = -0.3,  -- backward = horizontal velocity at more than ~107 deg from where you face
	CROUCH_SPEED        = 4,     -- WalkSpeed while crouching (was 8; 4 on 2026-10-12: a real sneak, and the speed the
	                             -- crouch walk clip is authored for, so its planted feet don't slide)
	CROUCH_CAM_OFFSET   = -0.8,  -- Additional Y camera offset on top of HipHeight drop
	CROUCH_HIP_REDUCTION = 1.4,  -- How many studs to lower HipHeight (drives the physical duck)
	CROUCH_ANIM_ID      = "",    -- rbxassetid://XXXXXXX  (leave empty to skip animation)
	CROUCH_TWEEN_TIME   = 0.18,  -- Seconds for crouch-in / stand-up transition
}
