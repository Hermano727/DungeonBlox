-- EnergyConfig: Single source of truth for all energy system constants.
-- Change a value here and it automatically updates everywhere.
return {
	MAX_ENERGY         = 100,   -- Maximum energy a player can have
	REGEN_RATE         = 10,     -- Energy restored per second (when not in lockout)
	SPRINT_COST        = 15,    -- Energy drained per second while sprinting
	DASH_COST          = 25,    -- Energy consumed per dash (requires at least this much)
	DASH_COOLDOWN      = 4.0,   -- Seconds between dashes
	SWING_COST         = 10,    -- Energy drained per swing (Sword baseline)
	WEAPON_SWING_MULT  = { Sword=1.00, Scythe=1.05, Axe=1.10, Mace=1.15, Bow=1.20 },
	PANT_WALK_SPEED    = 8,     -- WalkSpeed while panting (0 energy) until stamina is full
	LOCKOUT_DURATION   = 3,     -- Deprecated: panting lasts until energy refills (kept for compatibility)
	REGEN_IN_LOCKOUT   = false, -- Deprecated; panting uses normal regen to refill
	SPRINT_SPEED       = 24,    -- WalkSpeed while sprinting
	NORMAL_SPEED       = 16,    -- Default WalkSpeed
	CROUCH_SPEED        = 7,     -- WalkSpeed while crouching
	CROUCH_CAM_OFFSET   = -0.8,  -- Additional Y camera offset on top of HipHeight drop
	CROUCH_HIP_REDUCTION = 1.4,  -- How many studs to lower HipHeight (drives the physical duck)
	CROUCH_ANIM_ID      = "",    -- rbxassetid://XXXXXXX  (leave empty to skip animation)
	CROUCH_TWEEN_TIME   = 0.18,  -- Seconds for crouch-in / stand-up transition
}
