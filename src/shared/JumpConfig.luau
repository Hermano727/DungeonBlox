--[[
	JumpConfig -- the player's jump: how high, how heavy, and the timings of its state machine
	(src/characterscripts/JumpMotion, clips in RS/Assets/Animations/JumpAnimations).

	Roblox's default jump (a ~7 stud leap at full world gravity) is replaced by a shorter, weightier
	one. Workspace gravity is NOT touched (mobs and dropped loot use it); instead, while a character
	is airborne an upward force cancels most of it, so the player alone falls at GRAVITY_RISE going up
	and GRAVITY_FALL coming down (both far below Workspace.Gravity, 196.2). The launch speed is then
	solved so the jump peaks at HEIGHT:   v0 = sqrt(2 * GRAVITY_RISE * HEIGHT).
	With the defaults: ~4 studs high, ~0.38 s up and ~0.32 s down, about 0.7 s in the air.
]]

return {
	HEIGHT = 12.0,           -- studs from the ground to the top of a standing jump
	GRAVITY_RISE = 55,      -- studs/s^2 on the way up
	GRAVITY_FALL = 80,      -- studs/s^2 on the way down: a quicker fall than rise reads as weight

	WINDUP = 0.12,          -- seconds of squat between pressing jump and leaving the ground
	JUMP_COOLDOWN = 0.5,   -- after a landing starts, how soon the next jump may begin

	LONG_SPEED = 22,        -- horizontal speed (studs/s) at takeoff from which the jump is a long one: above any
	                        -- walk or sprint (9.6 / 14.4 plus speed bonuses), so an ordinary jump is never "long"
	APEX_SPEED = 3,         -- upward speed below which the rise is over and the fall begins
	WALKOFF_AIR_TIME = 0.16, -- airborne this long without jumping (a ledge, not a stair) = fall pose

	-- Landing: the clip is played at a weight from the impact speed (how fast you were falling).
	LAND_MIN_AIR = 0.22,    -- shorter, gentler hops than this land without a landing clip
	LAND_IMPACT_SOFT = 20,  -- studs/s: weight LAND_WEIGHT_MIN at or below
	LAND_IMPACT_HARD = 70,  -- studs/s: full weight at or above
	LAND_WEIGHT_MIN = 0.35,
	HARD_LANDING_IMPACT = 55, -- studs/s: from here a landing also slows you for a moment
	HARD_LANDING_SLOW = 0.45, -- walk speed multiplier during it
	HARD_LANDING_SECONDS = 0.30,

	FADE_IN = 0.08,
	FADE_OUT = 0.12,
	TAKEOFF_LENGTH = 0.60,  -- seconds from the press until the air pose takes over. The Takeoff clip's motion is
	                        -- 0.40 s and then holds its last pose, so any value >= 0.40 is safe (shorter cuts it off)
	LAND_LENGTH = 0.52,     -- the Land clip's motion; the landing ends (fades to the run / idle) after this
}
