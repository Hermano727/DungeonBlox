--[[
	MiasmaArenaPropsPlacements -- where the sewer-works props go (assets/builds/MiasmaBossRoom/props_v01).
	Read by the edit-time tool SSS/MiasmaArenaArtAssembler next to MiasmaArenaKitV2Placements; same
	row format: { module, x, y, z, R00..R22 } in arena-local space (origin = top-centre of the arena
	Baseplate). Written by hand (not generated), from MiasmaArenaLayout's face frames, so a layout
	change moves the props with it.

	Face frames (Layout.FaceFrame): origin on the floor at the face centre, +X along the wall, +Z into
	the room. Gates are the station faces (30/150/210/330), altars 90/270. Measured 2026-09-29:
	  gate faces   the old Gate_PipeOutfall sat at x = 55; flat wall (z = 0) only for x 52.5..57.5
	  altar faces  recess |x| < 12, pilasters at x = +-38, wall torches at x = +-21.5 (y 8.5) and +-48
	  ceiling      flat underside y = 61 arena-local (60 face-local); the corner ribs dip lower, so
	               nothing hangs from them. The ceiling shaft is the square |x|,|z| < 46.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Layout = require(ReplicatedStorage:WaitForChild("MiasmaArenaLayout"))

local CEILING_FACE_Y = Layout.CeilingY - Layout.FloorY -- ceiling underside, face-local
local OUTFALL_X = 55
local MOUTH = Vector3.new(0, 32.8, 7.8)               -- the pipe mouth, Prop_PipeOutfall-local
local CATWALK_HANG = 7.8                              -- catwalk deck to the ceiling cleats
local CATWALK_Z = 7

local function row(name, cf)
	return { name, cf:GetComponents() }
end

local function face(angle, x, y, z, yaw)
	return Layout.FaceFrame(angle) * CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(yaw or 0), 0)
end

-- Ceiling point at a polar angle/radius, turned like that angle's face frame (+X along the wall).
local function ceilingAt(angle, radius)
	return CFrame.new(Layout.Polar(angle, radius, Layout.CeilingY)) * Layout.FaceFrame(angle).Rotation
end

local props, stream = {}, {}

-- Gate 330 has the entrance arch on its +X side (the gate kit gave it no outfall), so its pipe
-- goes in the mirror bay on -X; that side is clear down to the corner the same way.
local OUTFALL_SIDE = { [330] = -1 }

for _, station in ipairs(Layout.Stations) do
	local a = station.Angle
	-- The outfall replaces the gate kit's Gate_PipeOutfall (see Art.Supersedes). It fits the ~5-stud
	-- flat bay between the gate buttress (x < 52.5) and the corner (x > 57.5).
	local x = OUTFALL_X * (OUTFALL_SIDE[a] or 1)
	table.insert(props, row("Prop_PipeOutfall", face(a, x, 0, 0)))
	table.insert(stream, row("Prop_PoisonStream", face(a, x + MOUTH.X, MOUTH.Y, MOUTH.Z)))
	-- A chain slung over the gate, clear of the surround (top ~47) and gallery.
	table.insert(props, row("Prop_ChainSwag_24", face(a, 0, CEILING_FACE_Y, 14)))
end

for _, altar in ipairs(Layout.Altars) do
	local a = altar.Angle
	local mirror = a == 270 and -1 or 1
	-- Maintenance catwalk along the wall under the ceiling, rail on the room side.
	for _, x in ipairs({ -24, -8, 8, 24 }) do
		table.insert(props, row("Prop_Catwalk_16", face(a, x, CEILING_FACE_Y - CATWALK_HANG, CATWALK_Z)))
	end
	-- Floor works in the bays between the recess and the pilasters (clear of the wall torches).
	table.insert(props, row("Prop_Scaffold", face(a, 29 * mirror, 0, 0)))
	if a == 90 then
		table.insert(props, row("Prop_Shoring", face(a, -31, 0, 0)))
		table.insert(props, row("Prop_GongCluster", face(a, -19, 0, 3)))
	else
		table.insert(props, row("Prop_Windlass", face(a, 26, 0, 6)))
		table.insert(props, row("Prop_Shoring", face(a, 33, 0, 0)))
	end
end

-- Caged lanterns over the walkway ring (outside the shaft), one per face.
for _, angle in ipairs({ 30, 90, 150, 210, 270, 330 }) do
	table.insert(props, row("Prop_CageLantern", ceilingAt(angle, 66)))
end
-- Hook chains between the faces, off the ribs.
for _, angle in ipairs({ 15, 75, 135, 195, 255, 315 }) do
	table.insert(props, row("Prop_ChainHook_12", ceilingAt(angle, 80)))
end

return {
	Kit = "props_v01",
	Groups = {
		Props = props,
		PropsStream = stream,
	},
}
