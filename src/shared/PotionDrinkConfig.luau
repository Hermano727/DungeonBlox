-- Cosmetic tuning only. Gameplay charges/healing and per-item colours live in PotionConfig.
return {
	-- Read from the published clip's CorkPop marker (frame 16 at 60 fps).
	CORK_POP_TIME = 0.25,
	CORK_POP_MARKER = "CorkPop",
	ANIMATION_DURATION = 1.10,
	DRINK_COOLDOWN = 1.5, -- seconds from one drink's start to the earliest next drink
	ANIMATION_FADE_IN = 0.06,
	ANIMATION_FADE_OUT = 0.10,
	ANIMATION_LOAD_TIMEOUT = 3,
	REQUEST_READY_TIMEOUT = 10,
	MARKER_FALLBACK_GRACE = 0.08,
	ANIMATED_VFX_TIME_SCALE = 1.0, -- the burst runs at its own pace, overlapping the lower
	-- Preserve the idle eye position while drinking. The walk/sprint camera's
	-- extra forward offset otherwise passes the real animated hands.
	DRINK_CAMERA_FORWARD = 0,
	-- Converted from the measured Blender Hand_R frame into the live bone's axes.
	BONE_GRIP = CFrame.fromMatrix(Vector3.new(-0.025, 0.23, 0.025),
		Vector3.new(0, 1, 0), Vector3.new(-0.794811666, 0, -0.606856167)),
	-- Standard Tool grip is kept as a fallback; the custom mesh uses BONE_GRIP.
	TOOL_GRIP = CFrame.new(0, -0.05, 0),
	AUDIENCE_RADIUS = 90,
	MAX_BURSTS = 10, -- at most ~130 orb billboards and 10 corks per client
	MAX_EVENT_AGE = 1.5,
	-- The burst (2026-10-03): uncorking releases a stream of red light orbs that rise out of
	-- the vial, spiral around the body (alternating directions, a double helix) and sink into
	-- the chest, which glows brighter with each one absorbed. About 1.4 s, into the 1.5 s cooldown.
	ORB_COUNT = 18,
	ORB_COUNT_REMOTE = 12, -- what other players see of your drink
	ORB_RELEASE_DELAY = 0.05,
	ORB_STAGGER = 0.028, -- the stream: one orb leaves the vial every this many seconds
	ORB_TRAVEL_MIN = 0.60,
	ORB_TRAVEL_MAX = 0.85,
	ORB_EASE = 1.5, -- >1: slow out of the vial, quick into the body
	ORB_POP_TIME = 0.08,
	ORB_SIZE_MIN = 0.12, -- studs (the bright core; the halo is HALO_SCALE times this)
	ORB_SIZE_MAX = 0.22,
	ORB_LIFT_MIN = 0.35, -- studs each orb rises above its straight path, mid-flight
	ORB_LIFT_MAX = 0.85,
	ORB_TURN_MIN = 2.2, -- radians each orb sweeps around the body on the way in
	ORB_TURN_MAX = 3.6,
	ORB_BULGE_MIN = 0.25, -- studs each orb swings out from the body mid-spiral
	ORB_BULGE_MAX = 0.5,
	ORB_STRETCH = 1.6,
	ORB_SHRINK = 0.35,
	CORE_COLOR = Color3.fromRGB(255, 226, 218),
	OUTLINE_COLOR = Color3.new(0, 0, 0),
	OUTLINE_TRANSPARENCY = 0.9,
	OUTLINE_THICKNESS = 1,
	HALO_SCALE = 3.2,
	HALO_TRANSPARENCY = 0.2,
	BILLBOARD_SIZE = 2.0, -- studs; room for the stretched streak, the halo and the absorb pulse
	ABSORB_GLOW_SIZE = 2.4, -- studs, the chest glow as the orbs land
	ABSORB_GLOW_GAIN = 0.16, -- per orb absorbed (0..1)
	ABSORB_GLOW_DECAY = 3.5, -- per second
	PULSE_TIME = 0.16,
	PULSE_SCALE = 2.8,
	CORK_TIME = 0.72,
	CORK_FADE_START = 0.38,
	CORK_UP_SPEED = 3.4,
	CORK_SIDE_SPEED = 0.65,
	CORK_GRAVITY = 12,
	CORK_SPIN = Vector3.new(5, 8, 3), -- radians/second
	CHEST_OFFSET = Vector3.new(0, 0.05, -0.5),
	-- World-space absorption proxy below the first-person sightline. The actual chest
	-- is behind the eye camera; pulling through it would send streaks through the lens.
	FIRST_PERSON_CHEST = Vector3.new(0.22, -0.85, -1.35),
	CAMERA_FADE_DEPTH = 0.55,
	CAMERA_FADE_RANGE = 0.35,
	POP_VOLUME = 0.35,
	ABSORB_VOLUME = 0.18,
	SOUND_MIN_DISTANCE = 5,
	SOUND_MAX_DISTANCE = 60,
}
