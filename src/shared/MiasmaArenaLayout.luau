--[[
	MiasmaArenaLayout -- THE placement source for the T1 Miasma arena (player-scale layout pass,
	2026-09-25). Everything that needs to know where something is in the room reads this:

		MiasmaArenaAnchorData        derives every ANCHOR_* position from it
		MiasmaValveStationPlacement  derives the four station slots from it
		MiasmaArenaResolver          station frames, altars, safe areas, sacks, channels
		MiasmaArenaLayoutBuilder     (edit-time tool) builds the Studio geometry from it

	Arena-local space: origin = top-centre of the realm's arena Baseplate. +Y up. Angles are
	degrees, 0 = arena-local -Z ("north", the entrance), increasing clockwise seen from above
	(90 = +X, "east"). Polar(angle, r, y) = (sin a * r, y, -cos a * r).

	Shape: a regular hexagon with VERTICES at 0/60/120/180/240/300 and FACES centred on
	30/90/150/210/270/330.
		faces 30, 150, 210, 330  monumental flood gates (gates 1-4): valve station on a raised platform
		                         beside each gate, open channel from the gate to the centre basin
		faces 90, 270            cleansing altar recesses
		vertex 0                 entrance corridor -> arrival vestibule (realm SpawnPoint)
		vertices 60/120/240/300  purge safe pads
		centre                   open combat platform + water basin; ceiling latch shaft above

	Sizing rationale (measured 2026-09-25, boss at MobData ModelScale 0.67; the boss was cut to
	0.45 on 2026-09-26 and the arena kept, so every boss figure below is now x0.67):
		boss standing footprint   ~60 x 64 (mesh), ~20 wide colliding core, 46 tall  (now ~40 x 43, 31 tall)
		landing danger radius     49 (Config.BossDropRadius; squash VFX reach ~1.6 x half-width)  (now 33)
		central platform radius   64 = landing danger + escape ring on the platform itself (now 31 wide)
		perimeter ring            platform 64 -> wall 104: 40 wide at faces, 56 at vertices
		ceiling                   underside 61 above the floor (boss 46 tall; latch anchor 53)
	The ceiling latch anchor (0, 53, 0) and cistern pivot (0, 56.4, 0) are NOT moved: the drop
	animation timing is authored against them. The shaft opening is sized around the latch.
]]

local Layout = {}

Layout.FloorY = 1              -- walking surface (floor slab top)
Layout.CeilingY = 61           -- ceiling underside
Layout.CeilingThickness = 4
Layout.Apothem = 104           -- wall inner face, measured at a face centre
Layout.WallThickness = 4
Layout.Circumradius = Layout.Apothem / math.cos(math.rad(30)) -- ~120.1, wall inner corner
Layout.PlatformRadius = 64
Layout.LandingDangerRadius = 33 -- mirror of Config.BossDropRadius, for documentation/tests
Layout.BasinRadius = 12
Layout.ShaftHalfWidth = 46     -- square ceiling opening around the latch (latch disc half-width ~33.4)
Layout.ShaftTop = 80

Layout.Recess = table.freeze({ -- cleansing-altar recesses
	Width = 24,      -- opening, >= 8 stud approach rule with margin
	AltarDepth = 12,
	LintelHeight = 12, -- recess ceiling above the floor
})

--[[
	Flood gates (arena art v02, assets/builds/MiasmaBossRoom/arena_v02). All values FACE-LOCAL:
	origin at the face centre on the floor (y 0 = FloorY), +X along the wall, +Z into the room
	(the arena centre is at z = Apothem). Layout.FaceFrame(angle) maps them to arena-local.
	The Blender build mirrors these numbers (build_gate_section.py / build_arena_v02.py).
]]
Layout.Gate = table.freeze({
	OpeningHalfWidth = 10,        -- clear opening 20 wide
	OpeningHeight = 30,           -- to the crown of the pointed arch
	PlaneZ = -4,                  -- gate leaf plane, inside the reveal
	SlideDistance = 24,           -- the leaf rises this far when the gate primes
	Pier = { 10, 17 }, PierZ = { -2, 7 }, PierTop = 47,
	Buttress = { 12, 16.5 }, ButtressZ = { 6, 10.5 }, ButtressTop = 20,
	ApronStep = -1.4, ApronFloor = -2.8, ApronHalfWidth = 12, ApronEnd = 20, FunnelEnd = 32,
	RetainingWall = { 12, 16 }, RetainingTop = 1.0,
	ChannelHalfWidth = 5,         -- open channel 10 wide (half the gate)
	ChannelWall = 8,              -- channel walls from 5 to 8
	ChannelBed = -2.4, ChannelTop = 0.4, -- players can fall in and jump back out
	Bridge = { Z = { 35, 45 }, HalfWidth = 9, Top = 0.5, ParapetTop = 1.2 },
	-- Small walkable grates across each open channel (z of the grate centre), per gate index.
	-- MIRRORED in arena_v02/build_arena_v02.py GRATE_Z -- keep them equal.
	GrateZ = { { 51, 77 }, { 57, 82 }, { 48.5, 71 }, { 60, 84 } },
	GrateHalfLength = 1.5, GrateTop = 0.46,
	Platform = { X = { -40, -17 }, Z = { 0, 16 }, Top = 1.2 },
	Pit = { X = { 24, 40 }, Z = { 0, 8 }, Floor = -0.3, KerbTop = 0.9 },
	WallEndButtress = 48,
	Station = Vector3.new(-28, 1.2, 5.3), -- station frame origin (operator spot); faces the wall
})
Layout.BasinFloor = -0.8 -- centre basin floor, relative to FloorY

Layout.Entrance = table.freeze({
	Angle = 0,
	Width = 16,            -- primary route, >= 10
	Height = 16,
	CorridorEnd = 158,     -- corridor runs from the room corner out to this radius
	VestibuleDepth = 28,   -- arrival hall behind the corridor
	VestibuleWidth = 44,   -- 8 arriving players are spread 4 studs apart along X
	SealRadius = 124,
	ThresholdRadius = 130,
	GatherRadius = 90,
	SpawnRadius = 172,
	SpawnOffsetX = -14,    -- party spread runs +X from here (DungeonInstanceService)
})

-- Gate index order is fixed: it is the encounter's gate index (1..4).
Layout.Stations = table.freeze({
	table.freeze({ Name = "NorthEast", DisplayName = "Northeast", Angle = 30 }),
	table.freeze({ Name = "SouthEast", DisplayName = "Southeast", Angle = 150 }),
	table.freeze({ Name = "SouthWest", DisplayName = "Southwest", Angle = 210 }),
	table.freeze({ Name = "NorthWest", DisplayName = "Northwest", Angle = 330 }),
})

-- Legacy anchor names kept so existing code keeps working: "NW" is the WEST recess and "SE"
-- the EAST recess in this layout (altar index 1 and 2 respectively).
Layout.Altars = table.freeze({
	table.freeze({ Anchor = "ANCHOR_CleanseAltar_NW", Angle = 270, Inset = 6 }),
	table.freeze({ Anchor = "ANCHOR_CleanseAltar_SE", Angle = 90, Inset = 6 }),
})

Layout.SafeAreas = table.freeze({ 60, 120, 240, 300 })
Layout.SafeAreaRadius = 12 -- mirror of Config.Arena.SafeAreaRadius
Layout.SafeAreaDistance = 94

Layout.SackAngles = table.freeze({ 22.5, 67.5, 112.5, 157.5, 202.5, 247.5, 292.5, 337.5 })
Layout.SackDistance = 98
Layout.SackHeight = 35

function Layout.Polar(angle, radius, y)
	local a = math.rad(angle)
	return Vector3.new(math.sin(a) * radius, y or Layout.FloorY, -math.cos(a) * radius)
end

function Layout.Outward(angle)
	local a = math.rad(angle)
	return Vector3.new(math.sin(a), 0, -math.cos(a))
end

-- Face frame for the wall face centred on `angle`: origin at the face centre on the floor,
-- LookVector outward (into the wall), so face-local +Z points into the room.
function Layout.FaceFrame(angle)
	local origin = Layout.Polar(angle, Layout.Apothem, Layout.FloorY)
	return CFrame.lookAt(origin, origin + Layout.Outward(angle))
end

-- Arena-local station frame for gate `index`: on the valve platform beside the gate, facing
-- the wall (the station-local layout -- wheel, plate, tablet, clogs -- is unchanged).
function Layout.StationFrame(index)
	return Layout.FaceFrame(Layout.Stations[index].Angle) * CFrame.new(Layout.Gate.Station)
end

-- Gate `index`'s channel: where the open channel starts (end of the funnel), where it crosses
-- onto the combat platform, and where it meets the centre basin (arena-local, floor height).
function Layout.ChannelPath(index)
	local angle = Layout.Stations[index].Angle
	local mouth = Layout.Polar(angle, Layout.Apothem - Layout.Gate.FunnelEnd, Layout.FloorY)
	local split = Layout.Polar(angle, Layout.PlatformRadius, Layout.FloorY)
	local finish = Layout.Polar(angle, Layout.BasinRadius, Layout.FloorY)
	return mouth, split, finish
end

function Layout.AltarPosition(index)
	local altar = Layout.Altars[index]
	return Layout.Polar(altar.Angle, Layout.Apothem + altar.Inset, Layout.FloorY)
end

-- Centre of the area hazards must avoid and the boss must not stand in, per station:
-- the station footprint plus its approach.
function Layout.StationProtectionCentre(index)
	return Layout.StationFrame(index):PointToWorldSpace(Vector3.new(-1, 0, 4))
end

-- Every named position anchor (arena-local Vector3). Station FRAMES are separate (above).
function Layout.Anchors()
	local e = Layout.Entrance
	local anchors = {
		ANCHOR_Miasma = Vector3.new(0, .3, 0),
		ANCHOR_Miasma_FloorLanding = Vector3.new(0, Layout.FloorY, 0),
		ANCHOR_Miasma_CeilingLatch = Vector3.new(0, 53, 0),
		ANCHOR_CisternLiquidPivot = Vector3.new(0, 56.4, 0),
		ANCHOR_PartyGather = Layout.Polar(e.Angle, e.GatherRadius, Layout.FloorY),
		ANCHOR_EntranceThreshold = Layout.Polar(e.Angle, e.ThresholdRadius, Layout.FloorY + 1),
		ANCHOR_EntranceSeal = Layout.Polar(e.Angle, e.SealRadius, Layout.FloorY + 12),
		ANCHOR_RealmSpawn = Layout.Polar(e.Angle, e.SpawnRadius, Layout.FloorY + .5) + Vector3.new(e.SpawnOffsetX, 0, 0),
	}
	for index, altar in ipairs(Layout.Altars) do
		anchors[altar.Anchor] = Layout.AltarPosition(index)
	end
	for index, angle in ipairs(Layout.SafeAreas) do
		anchors[("ANCHOR_PurgeSafe_%02d"):format(index)] = Layout.Polar(angle, Layout.SafeAreaDistance, Layout.FloorY + .4)
	end
	for index, angle in ipairs(Layout.SackAngles) do
		anchors[("ANCHOR_PoisonSack_%02d"):format(index)] = Layout.Polar(angle, Layout.SackDistance, Layout.SackHeight)
	end
	for index = 1, #Layout.Stations do
		anchors[("ANCHOR_Gate%02d_Protection"):format(index)] = Layout.StationProtectionCentre(index)
	end
	return anchors
end

return table.freeze(Layout)
