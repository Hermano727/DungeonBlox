--[[
	MobTelegraphConfig -- ReplicatedStorage

	Attack telegraphs: the ground shape a mob is ABOUT to hit, drawn during the
	windup so the swing can be read and dodged instead of just absorbed.

	Opt-in per attack, from MobData -- a mob with no `Telegraph` key never draws
	one, which is why every ordinary mob is unaffected:

		MobData[1]["Kane"] = {
			Telegraph = "KaneSlash",          -- the ORDINARY swing
			Moveset = {
				{ Id = "AxeCombo3Hit", Telegraph = "KaneCombo", ... },
			},
		}

	THE WINDUP IS THE TELEGRAPH. There is deliberately no "lead time" constant.
	The shape appears when the attack starts and its sweep reaches full radius at
	the exact instant damage lands, because the server hands the client the same
	hit offsets the damage itself uses (MobClass's `_attackHitDelay`, and
	MobMovesetBehaviour's `HitTimes`). Retune AttackSpeed or Speed and the
	telegraph re-times itself; a hand-authored lead would silently become a lie.
	It also means a telegraph can never be longer than the windup -- Kane's
	ordinary swing commits ~0.40s after it starts, so that is all the warning
	there is. Lengthen the tell by slowing the clip, not by editing this file.

	THE SHAPE IS THE REAL HITBOX, not a decorative ring. The server sends the
	radius straight out of `AttackRange + GetHitRadius()` (times the moveset's
	RangeMultiplier) and the half-angle straight out of `HalfAngleDegrees`, so
	what is drawn is what `IsTargetWithinMeleeReach` will actually test, and the
	client traces that region's actual BOUNDARY:

	  ordinary swing  a plain distance check, so the hit area is a full disc and
	                  the outline is a circle.
	  the combo       that disc intersected with a 140-degree frontal cone, so the
	                  hit area is a pie SECTOR -- apex at Kane, two straight edges
	                  out to the arc. The straight edges matter: they are what says
	                  "step outside these and it misses", which is the whole lesson
	                  that you can walk behind him mid-combo but not mid-swing.

	Styling only lives here. Timing and geometry arrive per-attack as attributes,
	because they come from data that changes.
]]

local MobTelegraphConfig = {}

-- CollectionService tag written next to the attributes below. Tags and
-- attributes both replicate, so this needs no remote of its own and every
-- client sees every telegraph -- the same pattern CombatEnchantStatus uses for
-- the slow status.
MobTelegraphConfig.TAG = "MobTelegraph"

-- Attribute names, named here so the server writer and the client reader cannot
-- drift on a typo.
MobTelegraphConfig.ATTR = {
	Kind = "TelegraphKind",       -- string, keys into Styles below
	Start = "TelegraphStart",     -- Workspace:GetServerTimeNow() at attack start
	Hits = "TelegraphHits",       -- comma-joined REAL seconds after Start
	Radius = "TelegraphRadius",   -- studs, matches the melee reach test
	HalfAngle = "TelegraphHalfAngle", -- degrees; 0 or absent = full ring
}

--[[
	DEBUG -- set false once the telegraph is confirmed working.

	Turns every telegraph into an unmissable opaque wall of colour floating at
	chest height, and makes both halves of the system announce themselves in the
	output. It exists because a telegraph that is drawing perfectly but is sunk
	into a hillside looks exactly like one that never fired -- two very different
	causes with no way to tell them apart by looking. That is not hypothetical:
	it is what happened on 2026-09-18, and it is why the shipped style is now a
	raised band rather than a flat marking.

	The two prints are the bisect:
	  [MobTelegraph] Begin ...   server wrote the tag
	  [MobTelegraphs] built ...  client received it and built the shape
	Server only        -> replication or the client renderer
	Neither            -> the attack never reached MobTelegraph.Begin
	Both, nothing seen -> it is drawing somewhere you are not looking
]]
MobTelegraphConfig.DEBUG = false

local DEFAULT = {
	-- Outline: the danger zone, held dim for the whole windup.
	Color = Color3.fromRGB(122, 18, 20),
	-- Sweep: expands from the mob to the outline, arriving exactly on impact.
	Accent = Color3.fromRGB(255, 138, 54),
	-- Impact flash, and how long it lingers after the last hit before fading.
	Flash = Color3.fromRGB(255, 226, 180),
	-- Pieces the boundary is chopped into. Spread evenly by ARC LENGTH along the
	-- whole outline, so a sector's straight edges and its arc each get density in
	-- proportion to their real length.
	Segments = 18,
	Thickness = 0.28,   -- radial width of a segment, studs

	-- Height/Lift together make this a low glowing BAND rather than a flat decal
	-- on the floor, and that is a terrain fix, not a style choice. At the
	-- original 0.08 studs tall sitting exactly on the foot plane, the far side of
	-- a 5-stud ring disappeared into any rising ground -- the mark was drawing
	-- correctly and was simply underneath the hill (confirmed 2026-09-18: the
	-- DEBUG wall below was visible in the same spot the flat version was not).
	--
	-- Lift is the band's CENTRE above the foot plane, Height its total span, so
	-- these values put the bottom edge ~0.15 studs under the feet and the top
	-- ~1.05 above. That tolerates about a stud of terrain rise across the ring
	-- before any of it is swallowed, which covers the rolling ground in T1.
	-- Steeper ground than that needs the segments raycast down individually --
	-- more correct, but a raycast per segment per frame, so not done until
	-- something actually demands it.
	Height = 1.2,
	Lift = 0.45,

	-- Transparency, so HIGHER is fainter. Kept deliberately see-through: the band
	-- is tall enough now to cover real screen area, and a telegraph that blocks
	-- your view of the boss is worse than one you have to look for.
	OutlineAlpha = 0.42,
	SweepAlpha = 0.18,
	Tail = 0.35,        -- seconds the mark lingers past the final impact
}

-- Applied on top of any style while DEBUG is on. Deliberately hideous.
local DEBUG_OVERRIDE = {
	Color = Color3.fromRGB(255, 0, 220),   -- magenta outline
	Accent = Color3.fromRGB(0, 255, 255),  -- cyan sweep
	Flash = Color3.fromRGB(255, 255, 255),
	Thickness = 1.2,
	Height = 6,        -- a wall, not a floor marking -- terrain cannot hide it
	Lift = 3,          -- floats at chest height, clear of any hillside
	OutlineAlpha = 0,  -- fully opaque
	SweepAlpha = 0,
	Tail = 1.5,        -- lingers far longer, so a 0.4s swing is still catchable
}

MobTelegraphConfig.Styles = {
	-- Miasma's ordinary swing: a thick poison ring the size of its reach.
	MiasmaMaul = {
		Color = Color3.fromRGB(96, 22, 128),
		Accent = Color3.fromRGB(190, 110, 255),
		Segments = 44,
		Thickness = 0.5,
		OutlineAlpha = 0.3,
		Tail = 0.4,
	},

	-- Kane's ordinary diagonal slash. Full ring: IsTargetWithinMeleeReach has no
	-- cone for the base attack, so anywhere in this circle is genuinely hit.
	-- Short by nature -- see the windup note above.
	KaneSlash = {
		-- Segment budget is spread along the whole boundary by arc length, so a
		-- full circle at ~5 studs gets pieces a bit over a stud each.
		Segments = 26,
		Thickness = 0.24,
	},

	-- Kane's three-hit axe combo. Drawn as his real 140-degree frontal cone, and
	-- the sweep replays once per impact, so the three beats are visible as three
	-- separate expansions rather than one long fill.
	KaneCombo = {
		Color = Color3.fromRGB(142, 20, 16),
		Accent = Color3.fromRGB(255, 108, 36),
		-- More than the ring: a sector's boundary is its arc PLUS both straight
		-- edges, so the same radius has noticeably more outline to cover.
		Segments = 30,
		Thickness = 0.36,
		OutlineAlpha = 0.32,
		Tail = 0.45,
	},
}

-- Always returns a complete table, so the client never branches on nil.
function MobTelegraphConfig.Get(kind)
	-- An unknown kind still merges rather than returning DEFAULT directly, or it
	-- would skip the DEBUG override below and be the one telegraph you cannot see.
	local style = (type(kind) == "string" and MobTelegraphConfig.Styles[kind]) or {}
	local out = {}
	for key, value in pairs(DEFAULT) do
		out[key] = value
	end
	for key, value in pairs(style) do
		out[key] = value
	end
	if MobTelegraphConfig.DEBUG then
		for key, value in pairs(DEBUG_OVERRIDE) do
			out[key] = value
		end
	end
	return out
end

-- Hit offsets travel as a string because Roblox attributes cannot hold tables.
function MobTelegraphConfig.EncodeHits(offsets)
	local parts = {}
	for index, seconds in ipairs(offsets) do
		parts[index] = string.format("%.4f", math.max(0, seconds))
	end
	return table.concat(parts, ",")
end

function MobTelegraphConfig.DecodeHits(encoded)
	local out = {}
	if type(encoded) ~= "string" then
		return out
	end
	for piece in string.gmatch(encoded, "[^,]+") do
		local seconds = tonumber(piece)
		if seconds then
			table.insert(out, seconds)
		end
	end
	return out
end

return MobTelegraphConfig
