--[[
	ZoneConfig
	Shared constants for the Zone system. Required by both server and client.

	A Zone is a 2D circle on the XZ plane (Y is stored for visualization but
	ignored in distance checks — you can't escape a zone by climbing).

	Zone properties:
	  alignment       "Lawful" | "Neutral" | "Chaotic". Lawful zones block ALL
	                  PvP regardless of player alignment. The rest (Neutral,
	                  Chaotic) don't gate PvP themselves — player alignment does.
	  bannedAlignments  Set keyed by alignment name. Players whose alignment
	                  is in this set get an on-screen flash when they enter.
	                  Entry is NOT actually prevented yet (per scope decision).
	  radius          Circle radius in studs.
]]

local ZoneConfig = {}

ZoneConfig.VALID_ALIGNMENTS = { Lawful = true, Neutral = true, Chaotic = true }
ZoneConfig.ALIGNMENTS_ORDERED = { "Lawful", "Neutral", "Chaotic" }

-- Colors used for both the dev visualization cylinder and the entry-flash UI tint.
ZoneConfig.ALIGNMENT_COLORS = {
	Lawful  = Color3.fromRGB( 80, 170, 255),  -- blue
	Neutral = Color3.fromRGB(255, 200,  80),  -- gold
	Chaotic = Color3.fromRGB(255,  90,  90),  -- red
}

-- Radius bounds (studs). Min keeps placements visible; max keeps DataStore lean.
ZoneConfig.MIN_RADIUS     = 8
ZoneConfig.MAX_RADIUS     = 500
ZoneConfig.DEFAULT_RADIUS = 60

-- Server polls each player's zone occupancy this often. Cheap (linear over
-- (#zones × #players)); a fraction of a second is plenty since walking speed
-- is ~16 studs/sec.
ZoneConfig.OCCUPANCY_TICK_SEC = 0.25

-- Flash UI display duration and per-zone retrigger guard so jittering on a
-- boundary doesn't strobe the screen.
ZoneConfig.FLASH_DURATION_SEC      = 2.0
ZoneConfig.FLASH_REENTRY_COOLDOWN  = 5.0

-- Dev-only visualization tuning.
ZoneConfig.DEV_CYLINDER_HEIGHT    = 1    -- thin disc lying flat on the ground
ZoneConfig.DEV_CYLINDER_TRANSPARENCY = 0.75

return ZoneConfig
