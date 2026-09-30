--[[
	MiasmaValveStationPlacement -- WHERE the valve stations go. Geometry lives in
	MiasmaValveStationBuilder; rules in MiasmaValveGate / MiasmaMazeService.

	Station frame convention (used by every placement below and by the builder):
		origin     = the operator's standing spot, on the floor
		LookVector = the direction the operator faces while turning the valve
		             (toward the station's back wall, i.e. AWAY from the arena centre)
	so the open approach, the drain channel and the clogs all sit on the arena-centre side.

	The four slots come from RS/MiasmaArenaLayout (the one placement source): each station
	stands on the raised valve platform beside the flood gate in one of the hexagon's diagonal
	faces (Layout.Gate.Station), its back flush with the room
	wall. The layout builder also places an explicit Part per station, ANCHOR_ValveStation_0N,
	inside the realm template; MiasmaArenaResolver prefers that part's CFrame when present.

	Relocating a station:
	  1. Edit MiasmaArenaLayout (moves the station, its gate, channel and protection together),
	     then rebuild the Studio geometry with MiasmaArenaLayoutBuilder; or
	  2. Drag its ANCHOR_ValveStation_0N part in Studio (moves only the station itself).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Layout = require(ReplicatedStorage:WaitForChild("MiasmaArenaLayout"))

local stations = {}
for index, slot in ipairs(Layout.Stations) do
	stations[index] = table.freeze({ Name = slot.Name, DisplayName = slot.DisplayName, Angle = slot.Angle })
end

return table.freeze({
	Stations = table.freeze(stations),
	AnchorNamePattern = "ANCHOR_ValveStation_%02d",

	-- The builder drops each station onto whatever floor is under its origin (raycast
	-- against the realm only), so a slightly wrong frame height never leaves it floating.
	FloorProbeUp = 8,
	FloorProbeDown = 20,

	-- Development-only station (MiasmaValveDevHarness). Built OUTSIDE the realm template so
	-- dungeon clones never copy it, standing in the master template's Northwest station
	-- gate platform, so it is tested in real surroundings.
	Dev = table.freeze({
		Enabled = true,              -- still only runs in Studio unless AllowOutsideStudio
		AllowOutsideStudio = false,
		FolderName = "MiasmaValveDev",
		TemplateName = "DungeonRealmTemplate",
		StationSlot = 4,             -- which Stations[] entry to copy (NorthWest)
		AnchorName = "MiasmaValveDevAnchor", -- optional Workspace Part overriding the dev station frame
		-- Travel beacons: one beside the T1 dungeon portal (-1160, 8.5, 60), one at the
		-- dev station's approach. Snapped to the floor under these points.
		EntryBeacon = Vector3.new(-1148, 30, 66),
		ReturnOffset = Vector3.new(6, 0, 16), -- station-local: in front of the platform steps
		DefaultPartySize = 1,        -- workload preset; change the folder's PartySize attribute live
	}),
})
