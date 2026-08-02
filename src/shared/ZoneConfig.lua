--[[
	ZoneConfig
	Shared constants for the Zone system. Required by both server and client.

	A Zone is a 2D region on the XZ plane (Y is stored for visualization but
	ignored in distance checks — you can't escape a zone by climbing).

	New zones are freeform polygons (array of XZ points). Legacy saves may
	still use center + radius circles.

	Zone properties:
	  alignment       "Lawful" | "Neutral" | "Chaotic". Lawful zones block ALL
	                  PvP regardless of player alignment. The rest (Neutral,
	                  Chaotic) don't gate PvP themselves — player alignment does.
	  bannedAlignments  Set keyed by alignment name. Players whose alignment
	                  is in this set get an on-screen flash when they enter.
	                  Entry is NOT actually prevented yet (per scope decision).
	  radius          Legacy circle radius in studs (older zones).
	  points          Array of { x, z } polygon corners (preferred).
	  musicId         rbxassetid:// string for looped zone soundtrack. Empty
	                  string = no music (default). Set via ZoneService.SetZoneMusic.
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
ZoneConfig.DEV_ZONE_COLOR = Color3.fromRGB(255, 220, 50) -- yellow dev overlay (distinct from red mob spawners)
ZoneConfig.DEV_ZONE_EDGE_THICKNESS = 0.35
ZoneConfig.DEV_ZONE_CORNER_SIZE = 1.2
ZoneConfig.MIN_POLYGON_POINTS = 3
ZoneConfig.MAX_POLYGON_POINTS = 64

-- Zone soundtrack defaults/tuning.
ZoneConfig.DEFAULT_MUSIC_ID    = "" -- empty = no music
ZoneConfig.ZONE_MUSIC_VOLUME   = 0.05
ZoneConfig.ZONE_MUSIC_FADE_SEC = 1.2

-- Accepts "rbxassetid://123" or a bare numeric id; returns "" (no music) on
-- anything else so a bad id can never become a broken/garbage SoundId.
function ZoneConfig.NormalizeMusicId(id)
	if type(id) ~= "string" then return "" end
	id = id:gsub("%s+", "")
	if id == "" then return "" end
	if id:match("^rbxassetid://%d+$") then return id end
	if id:match("^%d+$") then return "rbxassetid://" .. id end
	return ""
end

-- Legacy circle dev discs (pre-polygon zones).
ZoneConfig.DEV_CYLINDER_HEIGHT = 1
ZoneConfig.DEV_CYLINDER_TRANSPARENCY = 0.75

return ZoneConfig
