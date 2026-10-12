--[[
	FireTornadoConfig -- ReplicatedStorage

	Kane's Fire Tornado special: one timeline and one path, shared by the server (hitbox, damage)
	and every client (visuals), so the two can never disagree about where a tornado is. Nothing
	streams per frame: the server sends the cast's origin, facing and start time once
	(GameEvents/FireTornadoCast), and both sides evaluate PathPoint against
	workspace:GetServerTimeNow().

	Timeline, in seconds from the cast:
		0 .. WINDUP                  the channel: the caster stands still playing the Groundbreaker
		                             Slam wind-up, "!!" over its head, the ground sigil heats up,
		                             sparks rush inward, the four paths light up
		WINDUP                       the axe hits the ground (IMPACT): slam damage around the impact
		                             point, the ground crumbles, a fire burst, and four tornadoes
		                             appear at the caster
		WINDUP .. +RECOVERY          the slam's recovery frames: the caster is still committed
		WINDUP .. +TRAVEL            the tornadoes spiral outward together, DAMAGE_DELAY after release
		                             until the end of TRAVEL they damage anyone inside HIT_RADIUS
		+TRAVEL .. +COLLAPSE         each one collapses where it ended and bursts

	Damage (slam and per tick) and the cooldown are the MobData Moveset entry's (data per mob);
	everything here is shape and timing. Visual-only tuning sits in the VISUAL table.
]]

local Config = {}

Config.WINDUP = 1.0
Config.TRAVEL = 4.5
Config.COLLAPSE = 0.45
Config.DAMAGE_DELAY = 0.2     -- after release: let them appear before they hurt

-- The Groundbreaker Slam clip (MobAnimConfig.Kane.Moveset.GroundbreakerSlam, exported by
-- assets/models/mobs/named elites/kane animation/export_kane_clip.py) is 2 s long and its axe hits
-- the ground at authored frame 30 of 24 fps. It plays at SLAM_SPEED so that hit lands exactly on
-- WINDUP, then its recovery frames hold the caster for RECOVERY more seconds.
Config.SLAM_CLIP_LENGTH = 2.0
Config.SLAM_IMPACT_AT = 29 / 24                       -- clip seconds (the "Impact" marker)
Config.SLAM_SPEED = Config.SLAM_IMPACT_AT / Config.WINDUP
Config.RECOVERY = (Config.SLAM_CLIP_LENGTH - Config.SLAM_IMPACT_AT) / Config.SLAM_SPEED

-- The impact: the axe head lands just in front of the caster's feet (measured on the rig at the
-- impact frame). Slam damage reaches SLAM_RADIUS from that point, same vertical band as the hitbox.
Config.IMPACT_FORWARD = 0.8
Config.SLAM_RADIUS = 8
Config.SLAM_KNOCKBACK_DEFAULT = 2.5

-- Path: four tornadoes, 90 degrees apart, the first straight ahead of the caster. Each moves
-- out from START_RADIUS to END_RADIUS while the whole pinwheel turns SWEEP radians, so a player
-- standing still at any radius gets swept by at most one arm and can step between arms.
Config.COUNT = 4
Config.START_RADIUS = 2
Config.END_RADIUS = 30
Config.SWEEP = math.rad(150)

-- Hitbox (server): horizontal distance from the tornado's axis, and the vertical band it covers
-- above the ground point.
Config.HIT_RADIUS = 3.2
Config.HIT_BELOW = 4
Config.HIT_ABOVE = 13
Config.TICK_INTERVAL_DEFAULT = 0.5 -- used when the Moveset entry sets no TickInterval
Config.TICK_SOUND = "FireTornadoBurn" -- SoundEffects key, at the player, on each tick that lands

-- The drag (client, each player's own character, FireTornadoVFX): while a tornado is active,
-- anyone within PULL_RADIUS of its axis is pulled toward it at up to PULL_SPEED studs/s and
-- carried along with it at CARRY x its own speed, both fading to nothing at PULL_RADIUS. Strong
-- enough to drag you into it if you stand still, weak enough to walk out of.
Config.PULL_RADIUS = 10
Config.PULL_SPEED = 5
Config.CARRY = 0.35
Config.PULL_MIN_DISTANCE = 0.8 -- no pull this close to the axis (stops jitter at the centre)

-- Clients farther than this from the cast's origin skip the visuals entirely.
Config.VISIBLE_DISTANCE = 320

-- Where tornado `index` (0-based) is `t` seconds after release, at ground height of `origin`.
-- `angle` is the caster's facing as an XZ angle: atan2(look.Z, look.X).
function Config.PathPoint(origin: Vector3, angle: number, index: number, t: number): Vector3
	local a = math.clamp(t / Config.TRAVEL, 0, 1)
	local radius = Config.START_RADIUS + (Config.END_RADIUS - Config.START_RADIUS) * a
	local theta = angle + index * (2 * math.pi / Config.COUNT) + Config.SWEEP * a
	return origin + Vector3.new(math.cos(theta) * radius, 0, math.sin(theta) * radius)
end

local FIRE_COLOR = Color3.fromRGB(255, 120, 40)
local HOT_COLOR = Color3.fromRGB(255, 214, 140)
local EMBER_COLOR = Color3.fromRGB(255, 70, 25)
local DARK_COLOR = Color3.fromRGB(110, 14, 8)
local SMOKE_COLOR = Color3.fromRGB(46, 38, 36)
local WIND_COLOR = Color3.fromRGB(255, 240, 222)
local WIND_TAIL_COLOR = Color3.fromRGB(255, 196, 150)

-- The tornado is not a mesh: it is STRANDS, invisible points that orbit the axis while climbing it,
-- each dragging a glowing Trail, so the column is drawn by dozens of spiral strokes (plus
-- particles and a light). A mesh can't do this look in Roblox: MeshPart.TextureID ignores alpha,
-- so a textured tube always renders solid (see docs/vfx-pipeline.md).
Config.VISUAL = table.freeze({
	HEIGHT = 12.5,             -- studs, ground to lip at full size
	GROW_TIME = 0.35,          -- release: size 0 -> 1 (with a little overshoot)

	-- Funnel radius at height fraction h (0 ground .. 1 lip):
	--   NECK + FLARE * h^FLARE_POW + SKIRT * e^(-SKIRT_FALL * h)
	-- a ground skirt, a narrow neck low down, a wide flared top (the Blender profile).
	NECK = 0.7, FLARE = 3.8, FLARE_POW = 2.4, SKIRT = 2.3, SKIRT_FALL = 12,

	-- The axis is not straight: it swings WOBBLE studs off-centre, turning WOBBLE_TURNS times from
	-- ground to lip, and the whole bend rotates at WOBBLE_SPEED. That off-centre lean is what makes it
	-- read as a tornado rather than a vase.
	WOBBLE = 1.3, WOBBLE_TURNS = 1.1, WOBBLE_SPEED = 1.6,

	-- Strand groups, inside out. radius: multiple of the funnel radius, pad: extra studs outward.
	-- width: studs at full size. orbit: radians/s around the axis (faster where the funnel is
	-- narrow). rise: lip-climbs per second; LOW rise = near-horizontal rings, which is what traces
	-- the funnel's outline (steep strands read as separate little columns). lifetime: trail length
	-- in seconds (orbit x lifetime = how much of a ring one stroke covers). textured: the
	-- FLAME_STREAK texture, or false for a plain tapered line (wind).
	STRANDS = table.freeze({
		-- hot inner core
		table.freeze({ count = 5, radius = 0.45, pad = 0, width = 0.3, orbit = 13, rise = 0.9, lifetime = 0.2,
			colorFrom = HOT_COLOR, colorTo = FIRE_COLOR, transparency = 0, emission = 1, textured = true }),
		-- the silhouette: many slow-climbing rings right on the funnel surface
		table.freeze({ count = 18, radius = 1.0, pad = 0, width = 0.45, orbit = 10, rise = 0.3, lifetime = 0.5,
			colorFrom = FIRE_COLOR, colorTo = EMBER_COLOR, transparency = 0, emission = 1, textured = true }),
		-- darker sheets just outside it, for depth
		table.freeze({ count = 6, radius = 1.08, pad = 0, width = 0.9, orbit = 8, rise = 0.3, lifetime = 0.4,
			colorFrom = EMBER_COLOR, colorTo = DARK_COLOR, transparency = 0.25, emission = 0.6, textured = true }),
		-- wind: thin pale streaks whipping around outside the fire, faster than it
		table.freeze({ count = 10, radius = 1.0, pad = 1.4, width = 0.14, orbit = 15, rise = 0.22, lifetime = 0.3,
			colorFrom = WIND_COLOR, colorTo = WIND_TAIL_COLOR, transparency = 0.2, emission = 0.6, textured = false }),
		-- smoke wisps
		table.freeze({ count = 3, radius = 1.2, pad = 0, width = 1.2, orbit = 6.5, rise = 0.45, lifetime = 0.45,
			colorFrom = SMOKE_COLOR, colorTo = SMOKE_COLOR, transparency = 0.45, emission = 0, textured = true }),
	}),
	SPIN_SPEED = 7,               -- radians/s the base swirl turns

	CRUMBLE_RADIUS = 7,           -- slam: the ring of slabs breaking out of the ground, studs
	CRUMBLE_SCALE = 0.3,          -- slam: slab and rock size (MiasmaLandingSlamFX.Crumble)

	SIGIL_SIZE = 22,              -- channel ring diameter at full heat
	PATH_DASHES = 14,             -- telegraph dashes per path
	FIRE_COLOR = FIRE_COLOR,
	HOT_COLOR = HOT_COLOR,
	EMBER_COLOR = EMBER_COLOR,
	DARK_COLOR = DARK_COLOR,
	SMOKE_COLOR = SMOKE_COLOR,
})

-- Funnel radius at height fraction h, at full size.
function Config.FunnelRadius(h: number): number
	local V = Config.VISUAL
	return V.NECK + V.FLARE * h ^ V.FLARE_POW + V.SKIRT * math.exp(-V.SKIRT_FALL * h)
end

-- Off-centre offset of the axis at height fraction h, `t` seconds into the tornado's life.
function Config.AxisOffset(h: number, t: number): Vector3
	local V = Config.VISUAL
	local amp = V.WOBBLE * math.sin(math.pi * 0.85 * h)
	local a = 2 * math.pi * V.WOBBLE_TURNS * h + t * V.WOBBLE_SPEED
	return Vector3.new(math.cos(a) * amp, 0, math.sin(a) * amp)
end

return table.freeze(Config)
