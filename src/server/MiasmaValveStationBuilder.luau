--[[
	MiasmaValveStationBuilder -- GEOMETRY of one valve station, built from primitives at real
	player scale (player rig 5.82 studs tall). Placement comes from
	MiasmaValveStationPlacement; state/visual behaviour from MiasmaValveStation.

	Replacing the art: put a Model named `MiasmaValveStationPrefab_<SlotName>` (one slot, e.g.
	`MiasmaValveStationPrefab_NorthWest`) or `MiasmaValveStationPrefab` (every slot) in
	ServerStorage. Build() clones it instead of generating primitives, as long as it keeps the
	named contract below (authored in the same station frame: origin = operator spot on the
	floor, -Z = operator facing / back wall). MiasmaValveBayAssembler makes the per-slot prefab
	from imported Blender art.

	Named contract (what MiasmaValveStation looks up):
		Pivot (PrimaryPart)             attachments: OperatorSpot, WheelCentre, PlateCentre,
		                                 StationCentre, ChannelMouth, Clog1..Clog4
		Valve/WheelRoot                 anchored; the wheel parts are welded to it (rotates)
		Valve/Interact                  invisible; hosts the ProximityPrompt
		Sluice/GateRoot                 anchored; gate bars welded to it (slides up by its
		                                 SlideDistance attribute, default 4.4)
		Channel/Sludge, Channel/Water   state liquids
		RuneDisplay/Tablet              SurfaceGui host, face = Right (+X, toward the plate)
		RuneDisplay/PlateGlow           lights while someone reads
		Indicator/Lamp (+PointLight), Indicator/Plaque (SurfaceGui host, face = Back)
		Growth/*                        corruption dressing, shown while choked

	Everything is anchored except welded moving parts. Decorative parts never collide,
	query or touch, so chains, growth and grates cannot snag a player.

	Layout, station-local (studs):
		back wall     z -5.3..-3.9, x -9.5..7.5, 9 tall, with a sluice opening at x 3.4..6.6
		valve         x 0: wheel centre 3.8 up, 1.45 in front of the operator
		sluice+drain  right side, x 3.6..6.4, running from the wall to z 7.7 (toward the arena)
		plate+tablet  left side: plate centred (-6, 2.6), tablet at x -9 facing +X
		              (about 106 degrees behind the operator's view: unreadable while operating)
		approach      open along +Z
]]

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Placement = require(script.Parent:WaitForChild("MiasmaValveStationPlacement"))

local Builder = {}

Builder.PrefabName = "MiasmaValveStationPrefab"
-- Static art-bay shells (Blender architecture around a station) live in a folder of this name
-- inside the arena. The floor snap looks through them: their collision floor sits on top of
-- the real floor, and the station prefab is authored against the real floor.
Builder.ArtBayFolderName = "MiasmaArtBays"

local PALETTE = {
	Stone = Color3.fromRGB(78, 76, 70),
	StoneDark = Color3.fromRGB(52, 52, 48),
	Brick = Color3.fromRGB(92, 72, 60),
	Iron = Color3.fromRGB(58, 54, 50),
	Rust = Color3.fromRGB(110, 62, 36),
	Wood = Color3.fromRGB(72, 52, 36),
	Bone = Color3.fromRGB(196, 186, 160),
	Culvert = Color3.fromRGB(12, 14, 12),
	Sludge = Color3.fromRGB(66, 78, 34),
	Water = Color3.fromRGB(96, 190, 230),
	Growth = Color3.fromRGB(96, 150, 58),
	GrowthDark = Color3.fromRGB(88, 44, 110),
	Stain = Color3.fromRGB(34, 44, 26),
}

local WHEEL_CENTRE = Vector3.new(0, 3.8, -1.45)
local WHEEL_RADIUS = 1.45

local function applyProps(part, opts)
	opts = opts or {}
	part.Anchored = opts.anchored ~= false
	part.CanCollide = opts.collide == true
	part.CanQuery = opts.query == true or opts.collide == true
	part.CanTouch = false
	part.CastShadow = opts.shadow ~= false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Transparency = opts.transparency or 0
	if opts.anchored == false then part.Massless = true end
end

local function newPart(parent, name, size, cframe, material, color, opts, shape)
	local part = Instance.new("Part")
	part.Name = name
	if shape then part.Shape = shape end
	part.Size = size
	part.CFrame = cframe
	part.Material = material
	part.Color = color
	applyProps(part, opts)
	part.Parent = parent
	return part
end

local function group(parent, name, className)
	local item = Instance.new(className or "Model")
	item.Name = name
	item.Parent = parent
	return item
end

local function weld(root, part)
	local w = Instance.new("WeldConstraint")
	w.Part0 = root
	w.Part1 = part
	w.Parent = part
end

-- Every helper takes STATION-LOCAL positions; `frame` maps them into the world.
local function makeBuilder(frame)
	local b = {}

	function b.block(parent, name, size, localPos, material, color, opts, rotation)
		local cf = frame * CFrame.new(localPos) * (rotation or CFrame.identity)
		return newPart(parent, name, size, cf, material, color, opts)
	end

	-- Cylinder along a station-local axis ("X", "Y" or "Z").
	function b.cyl(parent, name, diameter, length, localPos, axis, material, color, opts)
		local rotation = CFrame.identity
		if axis == "Y" then rotation = CFrame.Angles(0, 0, math.rad(90))
		elseif axis == "Z" then rotation = CFrame.Angles(0, math.rad(90), 0) end
		local cf = frame * CFrame.new(localPos) * rotation
		return newPart(parent, name, Vector3.new(length, diameter, diameter), cf, material, color, opts, Enum.PartType.Cylinder)
	end

	function b.ball(parent, name, diameter, localPos, material, color, opts)
		local cf = frame * CFrame.new(localPos)
		return newPart(parent, name, Vector3.new(diameter, diameter, diameter), cf, material, color, opts, Enum.PartType.Ball)
	end

	return b
end

local DECOR = { collide = false, shadow = false }

local function buildStructure(model, b)
	local structure = group(model, "Structure", "Folder")
	local solid = { collide = true }
	-- Flagstone floor, split around the drain channel so the channel reads as sunk into it.
	b.block(structure, "FloorLeft", Vector3.new(13.1, .16, 13), Vector3.new(-2.95, .08, 1.2), Enum.Material.Slate, PALETTE.Stone, solid)
	b.block(structure, "FloorRight", Vector3.new(1.1, .16, 13), Vector3.new(6.95, .08, 1.2), Enum.Material.Slate, PALETTE.Stone, solid)

	-- Back wall with the sluice opening (x 3.4..6.6, 5 tall).
	b.block(structure, "WallLeft", Vector3.new(12.9, 9, 1.4), Vector3.new(-3.05, 4.5, -4.6), Enum.Material.Brick, PALETTE.Brick, solid)
	b.block(structure, "WallRight", Vector3.new(.9, 9, 1.4), Vector3.new(7.05, 4.5, -4.6), Enum.Material.Brick, PALETTE.Brick, solid)
	b.block(structure, "WallLintel", Vector3.new(3.2, 4, 1.4), Vector3.new(5, 7, -4.6), Enum.Material.Brick, PALETTE.Brick, solid)
	b.block(structure, "WallCoping", Vector3.new(18.6, .6, 2), Vector3.new(-1, 9.3, -4.6), Enum.Material.Slate, PALETTE.StoneDark, solid)
	b.block(structure, "PierLeft", Vector3.new(.9, 9.6, 2.2), Vector3.new(-9.95, 4.8, -4.4), Enum.Material.Slate, PALETTE.StoneDark, solid)
	b.block(structure, "PierRight", Vector3.new(.9, 9.6, 2.2), Vector3.new(7.95, 4.8, -4.4), Enum.Material.Slate, PALETTE.StoneDark, solid)
	b.block(structure, "PierSluice", Vector3.new(.5, 9, 1.8), Vector3.new(3.15, 4.5, -4.4), Enum.Material.Slate, PALETTE.StoneDark, solid)
	b.block(structure, "SluiceArchStone", Vector3.new(3.8, .5, 1.7), Vector3.new(5, 5.25, -4.45), Enum.Material.Slate, PALETTE.StoneDark, solid)
	-- Culvert behind the opening so it is dark, not see-through.
	b.block(structure, "CulvertBack", Vector3.new(3.4, 5.2, .3), Vector3.new(5, 2.6, -5.45), Enum.Material.Slate, PALETTE.Culvert, solid)
	b.block(structure, "CulvertFloor", Vector3.new(3.2, .1, 1.5), Vector3.new(5, .05, -4.6), Enum.Material.Slate, PALETTE.Culvert, DECOR)
end

local function buildValve(model, b)
	local valve = group(model, "Valve")
	local solid = { collide = true }
	b.cyl(valve, "WallFlange", 2.1, .3, Vector3.new(0, 3.8, -3.75), "Z", Enum.Material.CorrodedMetal, PALETTE.Rust, DECOR)
	b.cyl(valve, "Pipe", 1.1, 1.9, Vector3.new(0, 3.8, -2.95), "Z", Enum.Material.CorrodedMetal, PALETTE.Iron, solid)
	b.cyl(valve, "PipeCollar", 1.5, .35, Vector3.new(0, 3.8, -2.15), "Z", Enum.Material.CorrodedMetal, PALETTE.Rust, DECOR)
	b.cyl(valve, "Stem", .36, .6, Vector3.new(0, 3.8, -1.75), "Z", Enum.Material.Metal, PALETTE.Iron, DECOR)
	b.block(valve, "Support", Vector3.new(.5, 3.25, .5), Vector3.new(0, 1.625, -2.8), Enum.Material.CorrodedMetal, PALETTE.Iron, solid)
	b.block(valve, "SupportFoot", Vector3.new(1.3, .3, 1.1), Vector3.new(0, .31, -2.8), Enum.Material.CorrodedMetal, PALETTE.Rust, DECOR)
	b.block(valve, "SupportStrap", Vector3.new(1.3, .18, .6), Vector3.new(0, 3.2, -2.8), Enum.Material.CorrodedMetal, PALETTE.Rust, DECOR)
	b.cyl(valve, "Gauge", .7, .14, Vector3.new(1.05, 4.75, -3.72), "Z", Enum.Material.Metal, PALETTE.Bone, DECOR)
	b.block(valve, "GaugeNeedle", Vector3.new(.05, .28, .04), Vector3.new(1.05, 4.8, -3.63), Enum.Material.Metal, PALETTE.Culvert, DECOR, CFrame.Angles(0, 0, math.rad(-35)))

	-- Wheel: an anchored hub the rest is welded to, so turning the hub turns the wheel.
	local wheel = group(valve, "Wheel")
	local root = b.cyl(valve, "WheelRoot", .85, .45, WHEEL_CENTRE, "Z", Enum.Material.CorrodedMetal, PALETTE.Iron, { collide = false })
	local loose = { anchored = false, collide = false }
	local segments = 14
	local segmentLength = 2 * WHEEL_RADIUS * math.sin(math.pi / segments) + .06
	for i = 0, segments - 1 do
		local angle = i * (2 * math.pi / segments)
		local offset = Vector3.new(math.cos(angle) * WHEEL_RADIUS, math.sin(angle) * WHEEL_RADIUS, 0)
		local part = b.block(wheel, "Rim", Vector3.new(segmentLength, .26, .26), WHEEL_CENTRE + offset, Enum.Material.CorrodedMetal, PALETTE.Rust, loose, CFrame.Angles(0, 0, angle + math.pi / 2))
		weld(root, part)
	end
	for i = 0, 3 do
		local angle = math.rad(45 + i * 90)
		local offset = Vector3.new(math.cos(angle), math.sin(angle), 0) * (WHEEL_RADIUS / 2)
		local spoke = b.block(wheel, "Spoke", Vector3.new(WHEEL_RADIUS, .18, .18), WHEEL_CENTRE + offset, Enum.Material.CorrodedMetal, PALETTE.Iron, loose, CFrame.Angles(0, 0, angle))
		weld(root, spoke)
		local handleAngle = math.rad(i * 90)
		local handleOffset = Vector3.new(math.cos(handleAngle), math.sin(handleAngle), 0) * WHEEL_RADIUS + Vector3.new(0, 0, .28)
		local handle = b.cyl(wheel, "Handle", .3, .55, WHEEL_CENTRE + handleOffset, "Z", Enum.Material.Wood, PALETTE.Wood, loose)
		weld(root, handle)
	end

	local interact = b.block(valve, "Interact", Vector3.new(3.2, 3.2, .6), WHEEL_CENTRE + Vector3.new(0, 0, .2), Enum.Material.SmoothPlastic, PALETTE.Iron, { collide = false, transparency = 1, shadow = false })
	interact.CanQuery = false
end

local function buildSluiceAndChannel(model, b)
	local sluice = group(model, "Sluice")
	local root = b.block(sluice, "GateRoot", Vector3.new(3.2, .35, .4), Vector3.new(5, 4.75, -4.05), Enum.Material.CorrodedMetal, PALETTE.Rust, { collide = true })
	local loose = { anchored = false, collide = false }
	for i = 0, 4 do
		local bar = b.block(sluice, "Bar", Vector3.new(.22, 4.55, .22), Vector3.new(3.7 + i * .65, 2.3, -4.05), Enum.Material.CorrodedMetal, PALETTE.Iron, loose)
		weld(root, bar)
	end
	for _, y in ipairs({ 1.2, 3.4 }) do
		local rail = b.block(sluice, "Rail", Vector3.new(3.1, .22, .26), Vector3.new(5, y, -4.05), Enum.Material.CorrodedMetal, PALETTE.Rust, loose)
		weld(root, rail)
	end
	-- Invisible blocker so nobody walks into the culvert while the gate is shut.
	b.block(sluice, "GateCollision", Vector3.new(3.2, 5, .3), Vector3.new(5, 2.5, -4.05), Enum.Material.SmoothPlastic, PALETTE.Iron, { collide = true, transparency = 1, shadow = false })

	local channel = group(model, "Channel")
	b.block(channel, "Bed", Vector3.new(2.8, .06, 12.9), Vector3.new(5, .03, 1.25), Enum.Material.Slate, PALETTE.StoneDark, DECOR)
	b.block(channel, "CurbLeft", Vector3.new(.35, .42, 12.9), Vector3.new(3.775, .21, 1.25), Enum.Material.Slate, PALETTE.Stone, DECOR)
	b.block(channel, "CurbRight", Vector3.new(.35, .42, 12.9), Vector3.new(6.225, .21, 1.25), Enum.Material.Slate, PALETTE.Stone, DECOR)
	b.block(channel, "Sludge", Vector3.new(2.1, .16, 12.9), Vector3.new(5, .1, 1.25), Enum.Material.SmoothPlastic, PALETTE.Sludge, { collide = false, shadow = false, transparency = .05 })
	b.block(channel, "Water", Vector3.new(2.1, .24, 12.9), Vector3.new(5, .14, 1.25), Enum.Material.Glass, PALETTE.Water, { collide = false, shadow = false, transparency = 1 })
	for i = 0, 3 do
		b.block(channel, "MouthGrate", Vector3.new(.12, .1, 1.2), Vector3.new(4.25 + i * .5, .44, 7.1), Enum.Material.CorrodedMetal, PALETTE.Iron, DECOR)
	end
end

local function buildRuneDisplay(model, b)
	local display = group(model, "RuneDisplay")
	b.block(display, "PlateBase", Vector3.new(4, .16, 4), Vector3.new(-6, .24, 2.6), Enum.Material.Slate, PALETTE.StoneDark, { collide = true })
	b.block(display, "PlateGlow", Vector3.new(3.1, .04, 3.1), Vector3.new(-6, .33, 2.6), Enum.Material.Neon, Color3.fromRGB(60, 70, 58), { collide = false, shadow = false, transparency = .35 })
	for _, offset in ipairs({ Vector3.new(0, 0, 1.85), Vector3.new(0, 0, -1.85) }) do
		b.block(display, "PlateRim", Vector3.new(4, .1, .3), Vector3.new(-6, .36, 2.6) + offset, Enum.Material.CorrodedMetal, PALETTE.Iron, DECOR)
	end
	for _, offset in ipairs({ Vector3.new(1.85, 0, 0), Vector3.new(-1.85, 0, 0) }) do
		b.block(display, "PlateRim", Vector3.new(.3, .1, 3.4), Vector3.new(-6, .36, 2.6) + offset, Enum.Material.CorrodedMetal, PALETTE.Iron, DECOR)
	end

	b.block(display, "TabletPlinth", Vector3.new(1.7, .8, 5.8), Vector3.new(-9.05, .56, 2.6), Enum.Material.Slate, PALETTE.Stone, { collide = true })
	b.block(display, "Tablet", Vector3.new(.9, 4.4, 5.1), Vector3.new(-9.05, 3.16, 2.6), Enum.Material.Slate, PALETTE.StoneDark, { collide = true })
	b.block(display, "TabletCap", Vector3.new(1.3, .4, 5.6), Vector3.new(-9.05, 5.56, 2.6), Enum.Material.Slate, PALETTE.Stone, { collide = true })
	for _, z in ipairs({ .1, 5.1 }) do
		b.block(display, "TabletBand", Vector3.new(1.05, 4.4, .16), Vector3.new(-9.05, 3.16, z), Enum.Material.CorrodedMetal, PALETTE.Rust, DECOR)
	end
end

local function buildIndicator(model, b)
	local indicator = group(model, "Indicator")
	b.block(indicator, "LampBracket", Vector3.new(.2, .2, 1), Vector3.new(0, 7.2, -3.45), Enum.Material.CorrodedMetal, PALETTE.Iron, DECOR)
	b.block(indicator, "LampCageTop", Vector3.new(.95, .14, .95), Vector3.new(0, 7.78, -2.95), Enum.Material.CorrodedMetal, PALETTE.Iron, DECOR)
	b.block(indicator, "LampCageBottom", Vector3.new(.95, .14, .95), Vector3.new(0, 6.62, -2.95), Enum.Material.CorrodedMetal, PALETTE.Iron, DECOR)
	for _, offset in ipairs({ Vector3.new(.42, 0, .42), Vector3.new(-.42, 0, .42), Vector3.new(.42, 0, -.42), Vector3.new(-.42, 0, -.42) }) do
		b.block(indicator, "LampCageBar", Vector3.new(.08, 1.1, .08), Vector3.new(0, 7.2, -2.95) + offset, Enum.Material.CorrodedMetal, PALETTE.Iron, DECOR)
	end
	local lamp = b.ball(indicator, "Lamp", .72, Vector3.new(0, 7.2, -2.95), Enum.Material.Neon, Color3.fromRGB(40, 40, 40), DECOR)
	local light = Instance.new("PointLight")
	light.Name = "StateLight"
	light.Range = 14
	light.Brightness = 1.6
	light.Shadows = false
	light.Enabled = false
	light.Parent = lamp

	b.block(indicator, "Plaque", Vector3.new(3.4, 1, .14), Vector3.new(0, 5.85, -3.83), Enum.Material.Wood, PALETTE.Wood, DECOR)
	b.block(indicator, "PlaqueFrame", Vector3.new(3.6, 1.2, .08), Vector3.new(0, 5.85, -3.88), Enum.Material.CorrodedMetal, PALETTE.Iron, DECOR)
end

local function buildGrowth(model, b)
	local growth = group(model, "Growth", "Folder")
	local soft = { collide = false, shadow = false }
	local blobs = {
		{ Vector3.new(.85, 3.25, -2.55), 1.05, PALETTE.Growth },
		{ Vector3.new(-.9, 4.35, -2.85), .85, PALETTE.GrowthDark },
		{ Vector3.new(.25, 4.55, -2.3), .6, PALETTE.Growth },
		{ Vector3.new(-.2, 1.6, -2.55), .75, PALETTE.Growth },
		{ Vector3.new(.3, .55, -2.45), 1, PALETTE.GrowthDark },
		{ Vector3.new(4.3, 1.1, -3.7), 1.5, PALETTE.Growth },
		{ Vector3.new(5.7, 2.6, -3.7), 1.1, PALETTE.GrowthDark },
		{ Vector3.new(5.1, .5, -3.3), 1.2, PALETTE.Growth },
	}
	for index, blob in ipairs(blobs) do
		b.ball(growth, "Growth" .. index, blob[2], blob[1], Enum.Material.SmoothPlastic, blob[3], soft)
	end
	b.block(growth, "GrowthDrip", Vector3.new(.35, 2.4, .1), Vector3.new(-.7, 2.6, -3.86), Enum.Material.SmoothPlastic, PALETTE.Growth, soft)
end

local function buildDressing(model, b)
	local dressing = group(model, "Dressing", "Folder")
	-- Hanging chain off the coping.
	for i = 0, 8 do
		local rotation = CFrame.Angles(0, (i % 2) * math.rad(90), 0)
		b.block(dressing, "ChainLink", Vector3.new(.1, .38, .22), Vector3.new(-6.5, 8.8 - i * .34, -3.75), Enum.Material.CorrodedMetal, PALETTE.Iron, DECOR, rotation)
	end
	-- Iron straps across the brickwork.
	b.block(dressing, "Strap", Vector3.new(.2, 7.5, .1), Vector3.new(-4, 4.2, -3.86), Enum.Material.CorrodedMetal, PALETTE.Rust, DECOR, CFrame.Angles(0, 0, math.rad(28)))
	b.block(dressing, "Strap", Vector3.new(.2, 7.5, .1), Vector3.new(-4, 4.2, -3.87), Enum.Material.CorrodedMetal, PALETTE.Rust, DECOR, CFrame.Angles(0, 0, math.rad(-28)))
	-- Stains under the pipe and the drain.
	b.block(dressing, "Stain", Vector3.new(.9, 3.2, .05), Vector3.new(0, 1.9, -3.88), Enum.Material.SmoothPlastic, PALETTE.Stain, { collide = false, shadow = false, transparency = .35 })
	b.block(dressing, "Stain", Vector3.new(2.6, 1.4, .05), Vector3.new(5, 5.9, -3.88), Enum.Material.SmoothPlastic, PALETTE.Stain, { collide = false, shadow = false, transparency = .45 })
	-- Floor drain grate beside the operator.
	for i = 0, 3 do
		b.block(dressing, "DrainGrate", Vector3.new(.1, .05, 1.3), Vector3.new(-2.8 + i * .32, .18, -1.6), Enum.Material.CorrodedMetal, PALETTE.Iron, DECOR)
	end
	-- Bones at the tablet foot.
	b.cyl(dressing, "Bone", .22, 1.3, Vector3.new(-8, .3, 5.2), "X", Enum.Material.SmoothPlastic, PALETTE.Bone, DECOR)
	b.cyl(dressing, "Bone", .2, 1, Vector3.new(-7.7, .3, 4.8), "Z", Enum.Material.SmoothPlastic, PALETTE.Bone, DECOR)
	b.ball(dressing, "Skull", .7, Vector3.new(-8.5, .45, 4.6), Enum.Material.SmoothPlastic, PALETTE.Bone, DECOR)
end

local function buildPivot(model, frame)
	local pivot = newPart(model, "Pivot", Vector3.new(.4, .4, .4), frame, Enum.Material.SmoothPlastic, PALETTE.Iron, { collide = false, transparency = 1, shadow = false })
	pivot.CanQuery = false
	model.PrimaryPart = pivot
	local anchors = {
		OperatorSpot = Vector3.new(0, 0, 0),
		WheelCentre = WHEEL_CENTRE,
		PlateCentre = Vector3.new(-6, .3, 2.6),
		StationCentre = Vector3.new(-1, 0, 1.2),
		ChannelMouth = Vector3.new(5, .3, 7.6),
		Clog1 = Vector3.new(-1.3, 0, .3),
		Clog2 = Vector3.new(1.3, 0, .3),
		Clog3 = Vector3.new(0, 0, 2.8),
		Clog4 = Vector3.new(-3.2, 0, -1.6),
	}
	for name, position in pairs(anchors) do
		local attachment = Instance.new("Attachment")
		attachment.Name = name
		attachment.Position = position
		attachment.Parent = pivot
	end
	pivot:SetAttribute("PlateHalfSize", 2.1)
end

-- Drops `frame` onto the floor under it, searching only `floorRoots`.
function Builder.SnapToFloor(frame, floorRoots)
	if not floorRoots or #floorRoots == 0 then return frame end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = floorRoots
	params.RespectCanCollide = true
	local bottom = frame.Position.Y - Placement.FloorProbeDown
	local origin = frame.Position + Vector3.new(0, Placement.FloorProbeUp, 0)
	for _ = 1, 8 do
		local hit = Workspace:Raycast(origin, Vector3.new(0, bottom - origin.Y, 0), params)
		if not hit then return frame end
		if not hit.Instance:FindFirstAncestor(Builder.ArtBayFolderName) then
			return frame - frame.Position + hit.Position
		end
		-- Art-bay collision: continue from just inside it (a ray never hits a part it starts in).
		origin = hit.Position - Vector3.new(0, .01, 0)
	end
	return frame
end

function Builder.FindPrefab(slotName)
	local prefab = slotName and ServerStorage:FindFirstChild(Builder.PrefabName .. "_" .. slotName)
	if not (prefab and prefab:IsA("Model") and prefab.PrimaryPart) then
		prefab = ServerStorage:FindFirstChild(Builder.PrefabName)
	end
	if prefab and prefab:IsA("Model") and prefab.PrimaryPart then return prefab end
	return nil
end

--[[
	Build(parent, frame, name, floorRoots?, slotName?) -> Model
	`frame` is the station frame (see header). `floorRoots` (optional) are the instances the
	floor raycast may hit; pass the realm so a station never lands on a player or on itself.
	`slotName` (optional, e.g. "NorthWest") picks a per-slot art prefab when one exists.
	Idempotent per name: an existing child with the same name is destroyed first.
]]
function Builder.Build(parent, frame, name, floorRoots, slotName)
	local existing = parent:FindFirstChild(name)
	if existing then existing:Destroy() end
	frame = Builder.SnapToFloor(frame, floorRoots)

	local prefab = Builder.FindPrefab(slotName)
	if prefab then
		local model = prefab:Clone()
		model.Name = name
		model:PivotTo(frame)
		model.Parent = parent
		return model
	end
	return Builder.BuildPrimitive(parent, frame, name)
end

-- The primitive station, never a prefab (the assembler starts every art prefab from this).
function Builder.BuildPrimitive(parent, frame, name)
	local model = Instance.new("Model")
	model.Name = name
	local b = makeBuilder(frame)
	buildPivot(model, frame)
	buildStructure(model, b)
	buildValve(model, b)
	buildSluiceAndChannel(model, b)
	buildRuneDisplay(model, b)
	buildIndicator(model, b)
	buildGrowth(model, b)
	buildDressing(model, b)
	model:SetAttribute("MiasmaValveStation", true)
	model.Parent = parent
	return model
end

return Builder
