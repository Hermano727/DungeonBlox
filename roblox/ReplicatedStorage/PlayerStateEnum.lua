-- PlayerStateEnum: All valid player states.
-- Require this on both server and client to reference states by name, not string literals.
return {
	IDLE       = "IDLE",       -- standing still, no input
	WALKING    = "WALKING",    -- moving, not sprinting
	SPRINTING  = "SPRINTING",  -- moving + Shift held + energy available
	ATTACKING  = "ATTACKING",  -- mid-swing, hitbox active
	CROUCHING  = "CROUCHING",  -- crouched; reduced speed, sprint blocked, attack allowed
	LOW_ENERGY = "LOW_ENERGY", -- energy 0: panting (slowed, no attacks) until stamina is full
	DEAD       = "DEAD",       -- HP = 0; awaiting respawn
}
