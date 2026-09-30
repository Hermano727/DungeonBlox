--[[
	MiasmaArenaLayoutBuilder -- EDIT-TIME TOOL. Never required by the running game.

	Builds the player-scale Miasma arena (Studio primitives) inside the realm template from
	RS/MiasmaArenaLayout, so the layout data and the geometry cannot drift apart. The result is
	ordinary Studio-owned geometry (Workspace is outside Rojo), cloned into every run with the
	rest of the realm.

	Run it from the command bar / MCP in EDIT mode (loadstring, so edits are never served from a
	stale require cache):

		local RS, SSS = game:GetService("ReplicatedStorage"), game:GetService("ServerScriptService")
		local Layout = loadstring(RS.MiasmaArenaLayout.Source)()
		local build = loadstring(SSS.MiasmaArenaLayoutBuilder.Source)()
		print(build(Layout, { realm = workspace:FindFirstChild("DungeonRealmTemplate", true) }))

	Idempotent: the previous `MiasmaArenaLayout` model is destroyed and rebuilt, the realm
	SpawnPoint is moved (not duplicated), and graybox modules already retired stay retired.

	What it touches inside <realm>/T1 BOSS ROOM/miasma/T1DungeonTemplate:
		- moves the oversized graybox modules (shell, channels, gates, altars, bones, collision
		  proxies, the floating full-graybox preview, the inner SpawnPoint) into
		  ServerStorage.MiasmaArenaBackups.RetiredFromTemplate_20260925
		- keeps Miasma_05_CeilingMechanics (cistern ring, latch base, slime/poison hatches: they
		  already fit the latch height); retires only its oversized purge-disc and sack-hook ring
		- keeps the Baseplate untouched (it defines the arena origin)
		- builds MiasmaArenaLayout: Floor, Walls, Recesses (altars), Altars, Gates (flood-gate
		  collision: piers, aprons, funnels, open channels, bridges, grates, valve platforms,
		  poison pits, gate blockers), SafeAreas, Channels (gameplay liquid + flood effects),
		  Ceiling, Entrance, Anchors (ANCHOR_ValveStation_01..04)
		The primitives are the arena's COLLISION and graybox; the Blender art (arena_v02, placed by
		MiasmaArenaArtAssembler) is visual only and hides them.
	and moves <realm>/SpawnPoint to ANCHOR_RealmSpawn.
]]

local ServerStorage = game:GetService("ServerStorage")

local RETIRE = {
	"Miasma_01_ArenaShell",
	"Miasma_02_ChannelsAndWater",
	"Miasma_03_GatesValvesAndEntrance",
	"Miasma_04_CleanseAltars",
	"Miasma_06_BoneDressing",
	"Miasma_10_CollisionProxies",
	"Miasma_Arena_GrayboxMVP_BasicMaterials",
	"SpawnPoint",
}
-- Matched as substrings: the exported mesh names are truncated with "..." in the middle.
local RETIRE_FROM_CEILING = { "urgeLandmarks", "oisonSackHooks" }
local RETIRED_FOLDER = "RetiredFromTemplate_20260925"

local C = {
	Floor = Color3.fromRGB(66, 66, 60),
	Platform = Color3.fromRGB(92, 90, 82),
	PlatformEdge = Color3.fromRGB(46, 46, 42),
	Stone = Color3.fromRGB(80, 78, 72),
	StoneDark = Color3.fromRGB(54, 54, 50),
	Brick = Color3.fromRGB(96, 76, 64),
	Iron = Color3.fromRGB(58, 54, 50),
	Rust = Color3.fromRGB(110, 62, 36),
	ChannelBed = Color3.fromRGB(38, 40, 36),
	Sludge = Color3.fromRGB(66, 80, 34),
	Water = Color3.fromRGB(96, 196, 236),
	Cleanse = Color3.fromRGB(120, 235, 220),
	Safe = Color3.fromRGB(82, 225, 225),
	Torch = Color3.fromRGB(255, 176, 96),
	Poison = Color3.fromRGB(122, 48, 150),
	Crack = Color3.fromRGB(28, 30, 26),
	Recess = Color3.fromRGB(58, 58, 52),
}

return function(Layout, options)
	options = options or {}
	local realm = assert(options.realm, "realm required")
	local miasma = realm["T1 BOSS ROOM"].miasma
	local arena = miasma.T1DungeonTemplate
	local base = arena.Baseplate
	local origin = base.CFrame * CFrame.new(0, base.Size.Y * .5, 0)
	local report = {}
	local count = 0

	-- Retire the oversized graybox modules (kept intact in ServerStorage). ---------------------
	local backups = ServerStorage:FindFirstChild("MiasmaArenaBackups") or Instance.new("Folder")
	backups.Name = "MiasmaArenaBackups"
	backups.Parent = ServerStorage
	local retired = backups:FindFirstChild(RETIRED_FOLDER) or Instance.new("Folder")
	retired.Name = RETIRED_FOLDER
	retired.Parent = backups
	for _, name in ipairs(RETIRE) do
		local item = arena:FindFirstChild(name)
		if item then
			item.Parent = retired
			table.insert(report, "retired " .. name)
		end
	end
	local ceiling = arena:FindFirstChild("Miasma_05_CeilingMechanics")
	if ceiling then
		local ceilingRetired = retired:FindFirstChild("Miasma_05_CeilingMechanics_Retired") or Instance.new("Folder")
		ceilingRetired.Name = "Miasma_05_CeilingMechanics_Retired"
		ceilingRetired.Parent = retired
		for _, part in ipairs(ceiling:GetDescendants()) do
			if part:IsA("BasePart") then
				for _, key in ipairs(RETIRE_FROM_CEILING) do
					if string.find(part.Name, key, 1, true) then
						part.Parent = ceilingRetired
						table.insert(report, "retired ceiling part " .. part.Name)
					end
				end
				-- One hatch mesh was exported with its origin at the arena centre (floor level);
				-- put it back with its three siblings at the ceiling.
				if part.Parent ~= ceilingRetired and string.sub(part.Name, -#"DropHatch_04_Part01.001") == "DropHatch_04_Part01.001" then
					local localPosition = origin:PointToObjectSpace(part.Position)
					if localPosition.Y < 10 then
						part.CFrame = origin * CFrame.new(-50, 60.1, -49) * (origin:Inverse() * part.CFrame).Rotation
						table.insert(report, "re-seated slime hatch 04 frame at the ceiling")
					end
				end
				part.CanCollide = false
			end
		end
	end

	-- Fresh layout model. -----------------------------------------------------------------------
	local old = arena:FindFirstChild("MiasmaArenaLayout")
	if old then old:Destroy() end
	local model = Instance.new("Model")
	model.Name = "MiasmaArenaLayout"
	model:SetAttribute("GeneratedBy", "SSS/MiasmaArenaLayoutBuilder")
	model:SetAttribute("Spec", "RS/MiasmaArenaLayout")

	local function folder(name, parent)
		local f = Instance.new(parent == model and "Model" or "Folder")
		f.Name = name
		f.Parent = parent or model
		return f
	end

	-- props: collide (default true), transparency, shape, shadow (default true)
	local function part(parent, name, size, localCf, material, color, props)
		props = props or {}
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		if props.shape then p.Shape = props.shape end
		p.Size = size
		p.CFrame = origin * localCf
		p.Material = material
		p.Color = color
		p.CanCollide = props.collide ~= false
		p.CanQuery = props.collide ~= false or props.query == true
		p.CanTouch = false
		p.CastShadow = props.shadow ~= false
		p.Transparency = props.transparency or 0
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = parent
		count += 1
		return p
	end
	local DECOR = { collide = false, shadow = false }

	local function disc(parent, name, diameter, top, thickness, material, color, props, centre)
		centre = centre or Vector3.zero
		return part(parent, name, Vector3.new(thickness, diameter, diameter),
			CFrame.new(centre.X, top - thickness / 2, centre.Z) * CFrame.Angles(0, 0, math.rad(90)),
			material, color, props or DECOR)
	end

	local function light(parent, color, range, brightness)
		local l = Instance.new("PointLight")
		l.Color = color
		l.Range = range
		l.Brightness = brightness
		l.Shadows = false
		l.Parent = parent
		return l
	end

	-- Strip along a floor path (arena-local points on the floor), top at `top`.
	local function strip(parent, name, a, b, width, top, thickness, material, color, props)
		local flatA = Vector3.new(a.X, 0, a.Z)
		local flatB = Vector3.new(b.X, 0, b.Z)
		local centre = (flatA + flatB) / 2 + Vector3.new(0, top - thickness / 2, 0)
		local length = (flatB - flatA).Magnitude
		return part(parent, name, Vector3.new(width, thickness, length),
			CFrame.lookAt(centre, centre + (flatB - flatA)), material, color, props or DECOR)
	end

	local FY = Layout.FloorY
	local A = Layout.Apothem
	local T = Layout.WallThickness
	local H = Layout.CeilingY - FY
	local R = Layout.Recess
	local E = Layout.Entrance
	local G = Layout.Gate
	local R12 = Layout.BasinRadius
	local gateFaces = {}
	for index, slot in ipairs(Layout.Stations) do gateFaces[slot.Angle] = index end

	local function wedge(parent, name, size, cf, material, color)
		local w = Instance.new("WedgePart")
		w.Name = name
		w.Anchored = true
		w.Size = size
		w.CFrame = origin * cf
		w.Material = material
		w.Color = color
		w.CanTouch = false
		w.TopSurface = Enum.SurfaceType.Smooth
		w.BottomSurface = Enum.SurfaceType.Smooth
		w.Parent = parent
		count += 1
		return w
	end

	-- A triangle whose TOP face lies on a, b, c (arena-local), `thickness` deep: two WedgeParts.
	local function triangle(parent, name, a, b, c, thickness, material, color)
		local ab, ac, bc = b - a, c - a, c - b
		local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
		if abd > acd and abd > bcd then
			c, a = a, c
		elseif acd > bcd and acd > abd then
			a, b = b, a
		end
		ab, ac, bc = b - a, c - a, c - b
		local right = ac:Cross(ab).Unit
		local up = bc:Cross(right).Unit
		local back = bc.Unit
		local height = math.abs(ab:Dot(up))
		local down = (right.Y > 0 and -right or right) * (thickness / 2)
		wedge(parent, name, Vector3.new(thickness, height, math.abs(ab:Dot(back))), CFrame.fromMatrix((a + b) / 2 + down, right, up, back), material, color)
		wedge(parent, name, Vector3.new(thickness, height, math.abs(ac:Dot(back))), CFrame.fromMatrix((a + c) / 2 + down, -right, up, -back), material, color)
	end

	-- Face-local helpers (see Layout.Gate: origin at the face centre on the floor, +Z into the room).
	local function faceCF(angle, x, y, z)
		return Layout.FaceFrame(angle) * CFrame.new(x, y, z)
	end
	local function faceBox(parent, name, angle, x0, y0, z0, x1, y1, z1, material, color, props)
		local size = Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0))
		return part(parent, name, size, faceCF(angle, (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), material, color, props)
	end
	local function faceTri(parent, name, angle, p, q, r, material, color)
		local function at(v) return faceCF(angle, v[1], 0, v[2]).Position end
		triangle(parent, name, at(p), at(q), at(r), 1, material, color)
	end
	-- Is arena-local point p within `half` of a channel's centre line (on that channel's side)?
	local function inChannel(p, half)
		for _, slot in ipairs(Layout.Stations) do
			local n = Layout.Outward(slot.Angle)
			local t = Vector3.new(math.cos(math.rad(slot.Angle)), 0, math.sin(math.rad(slot.Angle)))
			local flat = Vector3.new(p.X, 0, p.Z)
			if flat:Dot(n) > 0 and math.abs(flat:Dot(t)) < half then return true end
		end
		return false
	end
	-- Which end (face-local X sign) of face `angle` meets the entrance vertex; 0 if neither.
	local function entranceSide(angle)
		local lp = Layout.FaceFrame(angle):PointToObjectSpace(Layout.Polar(E.Angle, Layout.Circumradius, FY))
		if math.abs(lp.Z) < 1 and math.abs(math.abs(lp.X) - A * math.tan(math.rad(30))) < 1 then
			return lp.X > 0 and 1 or -1
		end
		return 0
	end

	-- Floor -----------------------------------------------------------------------------------
	-- One sector per wall face (centre to both corners), built from boxes and wedge triangles so
	-- the open channels, aprons, poison pits and the basin are real holes players can fall into.
	local floor = folder("Floor")
	part(floor, "SafetyNet", Vector3.new(300, 2, 300), CFrame.new(0, FY - 8, 0), Enum.Material.Slate, C.Floor)
	local half = A * math.tan(math.rad(30))
	local edgeLength = math.sqrt(half * half + A * A)
	local tip = { R12 * half / edgeLength, A - R12 * A / edgeLength } -- sector edge meets the basin circle
	local slate = Enum.Material.Slate
	for k = 0, 5 do
		local angle = 30 + 60 * k
		for _, sx in ipairs({ -1, 1 }) do
			if gateFaces[angle] then
				local x32 = half * (1 - G.FunnelEnd / A)
				local zc = A - math.sqrt(R12 * R12 - G.ChannelHalfWidth ^ 2)
				do
					local P = G.Pit
					if sx < 0 then
						faceBox(floor, "Sector", angle, -x32, -1, 0, -16, 0, G.FunnelEnd, slate, C.Floor)
					else
						faceBox(floor, "Sector", angle, 16, -1, 0, P.X[1], 0, G.FunnelEnd, slate, C.Floor)
						faceBox(floor, "Sector", angle, P.X[1], -1, P.Z[2], P.X[2], 0, G.FunnelEnd, slate, C.Floor)
						faceBox(floor, "Sector", angle, P.X[2], -1, 0, x32, 0, G.FunnelEnd, slate, C.Floor)
					end
				end
				faceTri(floor, "Sector", angle, { sx * half, 0 }, { sx * x32, 0 }, { sx * x32, G.FunnelEnd }, slate, C.Floor)
				faceTri(floor, "Sector", angle, { sx * x32, G.FunnelEnd }, { sx * G.ChannelHalfWidth, G.FunnelEnd }, { sx * G.ChannelHalfWidth, zc }, slate, C.Floor)
				faceTri(floor, "Sector", angle, { sx * x32, G.FunnelEnd }, { sx * G.ChannelHalfWidth, zc }, { sx * tip[1], tip[2] }, slate, C.Floor)
			else
				faceTri(floor, "Sector", angle, { sx * half, 0 }, { 0, 0 }, { 0, A - R12 }, slate, C.Floor)
				faceTri(floor, "Sector", angle, { sx * half, 0 }, { 0, A - R12 }, { sx * tip[1], tip[2] }, slate, C.Floor)
			end
		end
	end
	-- Neighbouring sectors meet on a zero-width line at each hex corner; a narrow strip under each
	-- seam keeps ray probes (floor snaps, hazard placement) from threading the joint.
	for k = 0, 5 do
		strip(floor, "Sector", Layout.Polar(60 * k, R12 + .5), Layout.Polar(60 * k, Layout.Circumradius), .8, FY, 1, slate, C.Floor, { collide = true })
	end
	-- Shallow centre basin (Miasma lands here) with a kerb, open where the channels pour in.
	disc(floor, "BasinFloor", R12 * 2 + 1, FY + Layout.BasinFloor, 1, slate, C.ChannelBed, { collide = true })
	for i = 0, 31 do
		local a0, a1 = i * 11.25, (i + 1) * 11.25
		if not inChannel(Layout.Polar((a0 + a1) / 2, R12 + .6), G.ChannelHalfWidth + 1.5) then
			strip(floor, "BasinRim", Layout.Polar(a0, R12 + .6), Layout.Polar(a1, R12 + .6), 3.2, FY + .7, 1.5, slate, C.Stone, { collide = true })
		end
	end
	local ringSegments = 40
	for i = 0, ringSegments - 1 do
		local a0 = i / ringSegments * 360
		local a1 = (i + 1) / ringSegments * 360
		if not inChannel(Layout.Polar((a0 + a1) / 2, Layout.PlatformRadius), G.ChannelWall + 1) then
			strip(floor, "PlatformEdge", Layout.Polar(a0, Layout.PlatformRadius), Layout.Polar(a1, Layout.PlatformRadius), 1.8, FY + .065, .1, slate, C.PlatformEdge)
		end
	end
	-- The corridor mouth between the room corner and the entrance floor.
	local mouthCentre = Layout.Polar(E.Angle, Layout.Circumradius + 8, FY - .5)
	part(floor, "EntranceMouth", Vector3.new(E.Width + 2, 1, 30), CFrame.lookAt(mouthCentre, mouthCentre + Layout.Outward(E.Angle)), slate, C.Floor)

	-- Walls -----------------------------------------------------------------------------------
	local walls = folder("Walls")
	local openFaces = {}
	for _, slot in ipairs(Layout.Stations) do openFaces[slot.Angle] = "Gate" end
	for _, altar in ipairs(Layout.Altars) do openFaces[altar.Angle] = "Altar" end
	local halfLength = (A + T) * math.tan(math.rad(30))
	local faceInnerHalf = A * math.tan(math.rad(30))
	for k = 0, 5 do
		local theta = 30 + 60 * k
		local n = Layout.Outward(theta)
		local t = Vector3.new(math.cos(math.rad(theta)), 0, math.sin(math.rad(theta)))
		local segments = { { -halfLength, halfLength } }
		local lintels = {}
		local function cut(a, b, lintelBottom)
			local nextSegments = {}
			for _, seg in ipairs(segments) do
				if seg[2] <= a or seg[1] >= b then
					table.insert(nextSegments, seg)
				else
					if seg[1] < a then table.insert(nextSegments, { seg[1], a }) end
					if seg[2] > b then table.insert(nextSegments, { b, seg[2] }) end
				end
			end
			segments = nextSegments
			table.insert(lintels, { a, b, lintelBottom })
		end
		if openFaces[theta] == "Gate" then
			cut(-G.OpeningHalfWidth, G.OpeningHalfWidth, FY + G.OpeningHeight)
		elseif openFaces[theta] then
			cut(-R.Width / 2, R.Width / 2, FY + R.LintelHeight)
		end
		-- Entrance at vertex `E.Angle`: trim the two faces that meet there where |x| < width/2.
		local toVertex = ((E.Angle - theta + 540) % 360) - 180
		if math.abs(math.abs(toVertex) - 30) < 1e-3 then
			-- Lateral position (perpendicular to the entrance axis) along the face's inner line:
			-- zero at the shared corner, so trim where it reaches +-width/2 on the corner side.
			local axisRight = Vector3.new(math.cos(math.rad(E.Angle)), 0, math.sin(math.rad(E.Angle)))
			local lateral0 = (n * A):Dot(axisRight)
			local lateralPerS = t:Dot(axisRight)
			local sCorner = -lateral0 / lateralPerS
			local sTrim = ((E.Width / 2) * (lateral0 > 0 and 1 or -1) - lateral0) / lateralPerS
			if sCorner < 0 then cut(-halfLength - 1, sTrim, FY + E.Height) else cut(sTrim, halfLength + 1, FY + E.Height) end
		end
		for _, seg in ipairs(segments) do
			local sc = (seg[1] + seg[2]) / 2
			local position = n * (A + T / 2) + t * sc + Vector3.new(0, FY + H / 2, 0)
			part(walls, "Wall", Vector3.new(seg[2] - seg[1], H + 1, T), CFrame.lookAt(position, position + n), Enum.Material.Brick, C.Brick)
		end
		for _, lintel in ipairs(lintels) do
			local a, b, bottom = math.max(lintel[1], -halfLength), math.min(lintel[2], halfLength), lintel[3]
			local height = Layout.CeilingY + 1 - bottom
			local sc = (a + b) / 2
			local position = n * (A + T / 2) + t * sc + Vector3.new(0, bottom + height / 2, 0)
			part(walls, "Lintel", Vector3.new(b - a, height, T), CFrame.lookAt(position, position + n), Enum.Material.Brick, C.Brick)
			-- Arch stone over an altar opening
			if bottom == FY + R.LintelHeight then
				local arch = n * (A - .3) + t * sc + Vector3.new(0, bottom + .5, 0)
				part(walls, "ArchStone", Vector3.new(b - a + 2, 1, 1.2), CFrame.lookAt(arch, arch + n), Enum.Material.Slate, C.StoneDark, DECOR)
			end
		end
		-- Shallow pilasters and a base course along the face.
		for _, s in ipairs({ -38, 38 }) do
			local inSegment = false
			for _, seg in ipairs(segments) do if s > seg[1] + 2 and s < seg[2] - 2 then inSegment = true end end
			if inSegment then
				local position = n * (A - .6) + t * s + Vector3.new(0, FY + H / 2, 0)
				part(walls, "Pilaster", Vector3.new(3, H, 1.2), CFrame.lookAt(position, position + n), Enum.Material.Slate, C.StoneDark)
			end
		end
		for _, seg in ipairs(segments) do
			local sc = (seg[1] + seg[2]) / 2
			local position = n * (A - .3) + t * sc + Vector3.new(0, FY + .5, 0)
			part(walls, "BaseCourse", Vector3.new(seg[2] - seg[1], 1, .6), CFrame.lookAt(position, position + n), Enum.Material.Slate, C.StoneDark, DECOR)
		end
	end
	-- Corner buttresses (not at the entrance corner).
	for k = 0, 5 do
		local angle = 60 * k
		if math.abs(((angle - E.Angle + 540) % 360) - 180) > 1 then
			local position = Layout.Polar(angle, Layout.Circumradius + 1.5, FY + H / 2)
			local out = Layout.Outward(angle)
			local cf = CFrame.lookAt(position, position + out)
			part(walls, "Buttress", Vector3.new(6, H + 1, 6), cf, Enum.Material.Slate, C.StoneDark)
			local torch = part(walls, "Sconce", Vector3.new(.8, 1.2, .8), cf * CFrame.new(0, 8 - H / 2, 3.6), Enum.Material.Neon, C.Torch, DECOR)
			light(torch, C.Torch, 22, .7)
		end
	end

	-- Recesses (stations + altars) ------------------------------------------------------------
	local recesses = folder("Recesses")
	local function recess(angle, depth, kind)
		local n = Layout.Outward(angle)
		local t = Vector3.new(math.cos(math.rad(angle)), 0, math.sin(math.rad(angle)))
		local group = folder(kind .. "Recess_" .. angle, recesses)
		local halfW = R.Width / 2
		local height = R.LintelHeight
		for _, side in ipairs({ -1, 1 }) do
			local position = n * (A + depth / 2) + t * (side * (halfW + 1)) + Vector3.new(0, FY + height / 2, 0)
			part(group, "SideWall", Vector3.new(2, height, depth), CFrame.lookAt(position, position + n), Enum.Material.Brick, C.Brick)
		end
		local backPosition = n * (A + depth + 1) + Vector3.new(0, FY + height / 2, 0)
		part(group, "BackWall", Vector3.new(R.Width + 4, height, 2), CFrame.lookAt(backPosition, backPosition + n), Enum.Material.Brick, C.Brick)
		local roofPosition = n * (A + (depth + 2) / 2) + Vector3.new(0, FY + height + .75, 0)
		part(group, "Roof", Vector3.new(R.Width + 4, 1.5, depth + 2), CFrame.lookAt(roofPosition, roofPosition + n), Enum.Material.Slate, C.StoneDark)
		local floorPosition = n * (A + depth / 2) + Vector3.new(0, FY + .03, 0)
		local slab = floorPosition - Vector3.new(0, .53, 0) + n * .5 -- top at FloorY, reaches under the wall line
		part(group, "RecessFloor", Vector3.new(R.Width + 4, 1, depth + 1), CFrame.lookAt(slab, slab + n), Enum.Material.Slate, C.Recess)
		return group, n, t
	end

	-- Altars ----------------------------------------------------------------------------------
	local altars = folder("Altars")
	for index, altar in ipairs(Layout.Altars) do
		recess(altar.Angle, R.AltarDepth, "Altar")
		local centre = Layout.AltarPosition(index)
		local group = folder("CleanseAltar_" .. index, altars)
		local facing = CFrame.lookAt(centre, centre - Layout.Outward(altar.Angle))
		part(group, "Plinth", Vector3.new(7, .4, 7), facing * CFrame.new(0, .2, 0), Enum.Material.Slate, C.Stone)
		part(group, "Pedestal", Vector3.new(2.6, 3.6, 2.6), facing * CFrame.new(0, 2.2, 0), Enum.Material.Slate, C.StoneDark)
		disc(group, "Basin", 4.4, FY + 4.6, .6, Enum.Material.Slate, C.Stone, { collide = true }, centre)
		local water = disc(group, "CleanseWater", 3.6, FY + 4.66, .1, Enum.Material.Neon, C.Cleanse, DECOR, centre)
		light(water, C.Cleanse, 16, 1.1)
		disc(group, "RuneRing", 11, FY + .05, .06, Enum.Material.Neon, C.Cleanse, { collide = false, shadow = false, transparency = .45 }, centre)
		disc(group, "RuneRingInner", 10, FY + .07, .06, Enum.Material.Slate, C.Recess, DECOR, centre)
	end

	-- Purge safe pads -------------------------------------------------------------------------
	local safe = folder("SafeAreas")
	for index, angle in ipairs(Layout.SafeAreas) do
		local centre = Layout.Polar(angle, Layout.SafeAreaDistance, FY)
		local group = folder(("PurgeSafe_%02d"):format(index), safe)
		disc(group, "Ring", Layout.SafeAreaRadius * 2, FY + .05, .06, Enum.Material.Neon, C.Safe, { collide = false, shadow = false, transparency = .3 }, centre)
		disc(group, "Pad", Layout.SafeAreaRadius * 2 - 1.6, FY + .07, .06, Enum.Material.Slate, C.Stone, DECOR, centre)
		for spoke = 0, 5 do
			local a = spoke * 60 + 30
			strip(group, "Rune", centre + Layout.Outward(a) * 2.5, centre + Layout.Outward(a) * 8, .5, FY + .09, .04, Enum.Material.Neon, C.Safe, { collide = false, shadow = false, transparency = .35 })
		end
		local lamp = disc(group, "Lamp", 2, FY + .1, .06, Enum.Material.Neon, C.Safe, DECOR, centre)
		light(lamp, C.Safe, 18, .6)
	end

	-- Flood gates: collision for everything around each gate --------------------------------------
	local gates = folder("Gates")
	for index, slot in ipairs(Layout.Stations) do
		local angle = slot.Angle
		local g = folder(("GateStructure_%02d"):format(index), gates)
		local function box(name, x0, y0, z0, x1, y1, z1, color, props)
			return faceBox(g, name, angle, x0, y0, z0, x1, y1, z1, Enum.Material.Slate, color or C.StoneDark, props)
		end
		-- The art leaf lifts; this never does, so nobody walks into the culvert behind it.
		local blocker = box("GateBlocker", -G.OpeningHalfWidth - .5, G.ApronFloor, G.PlaneZ - .5, G.OpeningHalfWidth + .5, G.OpeningHeight, G.PlaneZ + .5, C.Iron, { transparency = 1, shadow = false })
		blocker.CanQuery = false
		for _, sx in ipairs({ -1, 1 }) do
			local function sbox(name, xa, y0, z0, xb, y1, z1, color)
				return box(name, math.min(sx * xa, sx * xb), y0, z0, math.max(sx * xa, sx * xb), y1, z1, color)
			end
			sbox("Pier", G.Pier[1], G.ApronFloor, G.PierZ[1], G.Pier[2], G.PierTop, G.PierZ[2])
			sbox("Buttress", G.Buttress[1], G.ApronFloor, G.ButtressZ[1], G.Buttress[2], G.ButtressTop, G.ButtressZ[2])
			sbox("ApronSide", G.OpeningHalfWidth, G.ApronFloor, G.PierZ[2], G.ApronHalfWidth, 0, G.ButtressZ[2])
			sbox("RetainingWall", G.RetainingWall[1], G.ApronFloor, G.ButtressZ[2], G.RetainingWall[2], G.RetainingTop, G.ApronEnd)
			local slices = 6 -- the funnel walls converge from the apron to the channel
			for i = 0, slices - 1 do
				local z0 = G.ApronEnd + (G.FunnelEnd - G.ApronEnd) * i / slices
				local z1 = G.ApronEnd + (G.FunnelEnd - G.ApronEnd) * (i + 1) / slices
				local f = (i + .5) / slices
				local inner = G.ApronHalfWidth + (G.ChannelHalfWidth - G.ApronHalfWidth) * f
				sbox("FunnelWall", inner, G.ApronFloor, z0, G.RetainingWall[2], G.RetainingTop + (G.ChannelTop - G.RetainingTop) * f, z1)
			end
			sbox("ChannelWall", G.ChannelHalfWidth, G.ChannelBed, G.FunnelEnd, G.ChannelWall, G.ChannelTop, A - (R12 + 1.3))
		end
		box("ApronStep", -G.OpeningHalfWidth, G.ApronStep - 1, -2, G.OpeningHalfWidth, G.ApronStep, 3)
		box("ApronFloor", -G.ApronHalfWidth, G.ApronFloor - 1, 3, G.ApronHalfWidth, G.ApronFloor, G.ApronEnd)
		box("FunnelFloor", -G.ApronHalfWidth, G.ApronFloor - 1, G.ApronEnd, G.ApronHalfWidth, (G.ApronFloor + G.ChannelBed) / 2, G.FunnelEnd)
		box("ChannelBed", -G.ChannelHalfWidth, G.ChannelBed - 1, G.FunnelEnd, G.ChannelHalfWidth, G.ChannelBed, A - R12 + .6)
		-- Crossings: one broad bridge at the platform edge, small grates elsewhere (open between).
		local B = G.Bridge
		box("Bridge", -B.HalfWidth, B.Top - .8, B.Z[1], B.HalfWidth, B.Top, B.Z[2], C.Stone)
		box("BridgeParapet", -B.HalfWidth, B.Top, B.Z[1], B.HalfWidth, B.ParapetTop, B.Z[1] + .7, C.Stone)
		box("BridgeParapet", -B.HalfWidth, B.Top, B.Z[2] - .7, B.HalfWidth, B.ParapetTop, B.Z[2], C.Stone)
		for _, z in ipairs(G.GrateZ[index]) do
			box("Grate", -G.ChannelHalfWidth - .7, G.GrateTop - .3, z - G.GrateHalfLength, G.ChannelHalfWidth + .7, G.GrateTop, z + G.GrateHalfLength, C.Iron)
		end
		-- The raised dry platform the valve station stands on, with broad steps.
		local P = G.Platform
		box("ValvePlatform", P.X[1], 0, P.Z[1], P.X[2], P.Top, P.Z[2], C.Stone)
		box("PlatformStep", P.X[1], 0, P.Z[2], P.X[2], P.Top * 2 / 3, P.Z[2] + 1.4, C.Stone)
		box("PlatformStep", P.X[1], 0, P.Z[2] + 1.4, P.X[2], P.Top / 3, P.Z[2] + 2.8, C.Stone)
		box("PlatformStep", P.X[1] - 1.4, 0, P.Z[1], P.X[1], P.Top * 2 / 3, P.Z[2] + 1.4, C.Stone)
		box("PlatformStep", P.X[1] - 2.8, 0, P.Z[1], P.X[1] - 1.4, P.Top / 3, P.Z[2], C.Stone)
		-- Poison catch pit: wading depth, kerbed, decorative (no damage).
		local Q = G.Pit
		box("PitFloor", Q.X[1], Q.Floor - 1, Q.Z[1], Q.X[2], Q.Floor, Q.Z[2], C.Poison)
		box("PitKerb", Q.X[1], Q.Floor, Q.Z[2] - .8, Q.X[2], Q.KerbTop, Q.Z[2], C.Stone)
		box("PitKerb", Q.X[1], Q.Floor, Q.Z[1], Q.X[1] + .8, Q.KerbTop, Q.Z[2] - .8, C.Stone)
		box("PitKerb", Q.X[2] - .8, Q.Floor, Q.Z[1], Q.X[2], Q.KerbTop, Q.Z[2] - .8, C.Stone)
		local side = entranceSide(angle)
		for _, sx in ipairs({ -1, 1 }) do
			if sx ~= side then
				local bx = sx * G.WallEndButtress
				box("WallButtress", bx - 4, 0, 0, bx + 4, 22, 8)
				box("WallButtress", bx - 3.2, 22, 0, bx + 3.2, 52, 3.8)
			end
		end
	end

	-- Channels: the gameplay liquid (MiasmaArenaChannels) + flood effects ------------------------
	local channels = folder("Channels")
	local split = A - Layout.PlatformRadius
	local basinEdge = A - R12 + .6
	local function particles(parent, name, cf, settings)
		local att = Instance.new("Attachment")
		att.Name = name
		att.Parent = parent -- parent FIRST: WorldCFrame on an unparented attachment is taken as local
		att.WorldCFrame = origin * cf
		local e = Instance.new("ParticleEmitter")
		e.Name = name
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.EmissionDirection = Enum.NormalId.Back -- face-local +Z: out of the gate, down the channel
		e.Enabled = false
		for key, value in pairs(settings) do e[key] = value end
		e.Parent = att
		return e
	end
	for index, slot in ipairs(Layout.Stations) do
		local angle = slot.Angle
		local group = folder(("MiasmaChannel_%02d"):format(index), channels)
		group:SetAttribute("GateIndex", index)
		local function liquid(name, x0, y0, z0, x1, y1, z1, water)
			return faceBox(group, name, angle, x0, y0, z0, x1, y1, z1, water and Enum.Material.Glass or Enum.Material.SmoothPlastic,
				water and C.Water or C.Sludge, { collide = false, shadow = false, transparency = water and 1 or 0 })
		end
		-- OUTER turns clean when this gate primes: apron, funnel, channel to the platform edge.
		liquid("OuterSludge_Apron", -11.8, G.ApronFloor, 3.2, 11.8, G.ApronFloor + .6, G.ApronEnd, false)
		liquid("OuterSludge_Funnel", -8.5, G.ApronFloor, G.ApronEnd, 8.5, G.ApronFloor + .7, G.FunnelEnd, false)
		liquid("OuterSludge_Channel", -4.9, G.ChannelBed, G.FunnelEnd, 4.9, G.ChannelBed + .5, split, false)
		local outerWater = liquid("OuterWater_Apron", -11.8, G.ApronFloor, 3.2, 11.8, -.35, G.ApronEnd, true)
		liquid("OuterWater_Step", -9.8, G.ApronStep, -2, 9.8, -.3, 3.2, true)
		liquid("OuterWater_Funnel", -8.5, G.ApronFloor, G.ApronEnd, 8.5, -.3, G.FunnelEnd, true)
		liquid("OuterWater_Channel", -4.9, G.ChannelBed, G.FunnelEnd, 4.9, -.25, split, true)
		-- INNER fills when every active gate is primed: across the platform into the basin.
		liquid("InnerSludge_Channel", -4.9, G.ChannelBed, split, 4.9, G.ChannelBed + .5, basinEdge, false)
		local innerWater = liquid("InnerWater_Channel", -4.9, G.ChannelBed, split, 4.9, -.25, basinEdge, true)
		light(outerWater, C.Water, 20, .9).Enabled = false
		light(innerWater, C.Water, 16, .7).Enabled = false
		local anchor = faceBox(group, "FloodFXAnchor", angle, -.5, 0, 0, .5, 1, 1, Enum.Material.SmoothPlastic, C.Water, { collide = false, shadow = false, transparency = 1 })
		anchor.CanQuery = false
		local face = Layout.FaceFrame(angle)
		local spray = {
			Color = ColorSequence.new(Color3.fromRGB(235, 250, 255), Color3.fromRGB(150, 205, 230)),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 7) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .35), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(1.1, 1.8), Rate = 70, Speed = NumberRange.new(18, 28),
			SpreadAngle = Vector2.new(35, 18), Acceleration = Vector3.new(0, -35, 0), LightInfluence = .6,
		}
		particles(anchor, "OuterSurge", face * CFrame.new(-5, 5, -1), spray)
		particles(anchor, "OuterSurge", face * CFrame.new(5, 5, -1), spray)
		local foam = {
			Color = ColorSequence.new(Color3.fromRGB(225, 240, 245)),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 2.6) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .45), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(.9, 1.3), Rate = 22, Speed = NumberRange.new(12, 16),
			SpreadAngle = Vector2.new(12, 3), LightInfluence = .7,
		}
		for z = G.ApronEnd, split - 2, 6 do particles(anchor, "OuterFoam", face * CFrame.new(0, -.2, z), foam) end
		for z = split + 2, basinEdge - 3, 8 do particles(anchor, "InnerFoam", face * CFrame.new(0, -.2, z), foam) end
	end
	local basin = folder("MiasmaCenterBasin", channels)
	disc(basin, "Sludge", R12 * 2 - 1, FY + Layout.BasinFloor + .5, .5, Enum.Material.SmoothPlastic, C.Sludge)
	local basinWater = disc(basin, "Water", R12 * 2 - 1, FY - .05, .8, Enum.Material.Glass, C.Water, { collide = false, shadow = false, transparency = 1 })
	light(basinWater, C.Water, 34, 1.2).Enabled = false

	-- Ceiling ---------------------------------------------------------------------------------
	local ceilingFolder = folder("Ceiling")
	local CY, CT, S = Layout.CeilingY, Layout.CeilingThickness, Layout.ShaftHalfWidth
	local span = 135
	part(ceilingFolder, "CeilingNorth", Vector3.new(span * 2, CT, span - S), CFrame.new(0, CY + CT / 2, -(S + span) / 2), Enum.Material.Slate, C.StoneDark)
	part(ceilingFolder, "CeilingSouth", Vector3.new(span * 2, CT, span - S), CFrame.new(0, CY + CT / 2, (S + span) / 2), Enum.Material.Slate, C.StoneDark)
	part(ceilingFolder, "CeilingWest", Vector3.new(span - S, CT, S * 2), CFrame.new(-(S + span) / 2, CY + CT / 2, 0), Enum.Material.Slate, C.StoneDark)
	part(ceilingFolder, "CeilingEast", Vector3.new(span - S, CT, S * 2), CFrame.new((S + span) / 2, CY + CT / 2, 0), Enum.Material.Slate, C.StoneDark)
	local shaftHeight = Layout.ShaftTop - CY
	for _, side in ipairs({ { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
		local x, z = side[1] * (S + 1.5), side[2] * (S + 1.5)
		local size = side[1] == 0 and Vector3.new(S * 2 + 6, shaftHeight, 3) or Vector3.new(3, shaftHeight, S * 2 + 6)
		part(ceilingFolder, "ShaftWall", size, CFrame.new(x, CY + shaftHeight / 2, z), Enum.Material.Brick, C.Brick)
		local rimSize = side[1] == 0 and Vector3.new(S * 2 + 6, 2.5, 3) or Vector3.new(3, 2.5, S * 2 + 6)
		part(ceilingFolder, "ShaftRimBeam", rimSize, CFrame.new(x, CY - 1.25, z), Enum.Material.Slate, C.Stone)
	end
	part(ceilingFolder, "ShaftCap", Vector3.new(S * 2 + 6, 2, S * 2 + 6), CFrame.new(0, Layout.ShaftTop + 1, 0), Enum.Material.Slate, C.StoneDark)
	local cisternGlow = part(ceilingFolder, "CisternGlow", Vector3.new(1, 1, 1), CFrame.new(0, CY + 4, 0), Enum.Material.SmoothPlastic, C.Poison, { collide = false, shadow = false, transparency = 1 })
	light(cisternGlow, C.Poison, 45, .9)
	-- Shallow radial ribs from the shaft to each wall corner.
	for k = 0, 5 do
		local angle = 60 * k
		local a = Layout.Polar(angle, S + 5, 0)
		local b = Layout.Polar(angle, Layout.Circumradius, 0)
		local centre = (a + b) / 2 + Vector3.new(0, CY - 1.25, 0)
		part(ceilingFolder, "Rib", Vector3.new(3, 2.5, (b - a).Magnitude), CFrame.lookAt(centre, centre + (b - a)), Enum.Material.Slate, C.Stone)
	end
	-- Fracture lines on the underside (dressing only).
	local cracks = { { 20, 70, 18 }, { 95, 62, 22 }, { 160, 80, 16 }, { 230, 66, 20 }, { 300, 74, 14 } }
	for _, crack in ipairs(cracks) do
		local a = Layout.Polar(crack[1], crack[2] - crack[3] / 2, 0)
		local b = Layout.Polar(crack[1] + 8, crack[2] + crack[3] / 2, 0)
		local centre = (a + b) / 2 + Vector3.new(0, CY - .03, 0)
		part(ceilingFolder, "Fracture", Vector3.new(.6, .06, (b - a).Magnitude), CFrame.lookAt(centre, centre + (b - a)), Enum.Material.Slate, C.Crack, DECOR)
	end

	-- Poison-sack entry pipes, high on the walls ------------------------------------------------
	local sackPipes = folder("SackEntries")
	for index, angle in ipairs(Layout.SackAngles) do
		local nearestFace = 30 + 60 * math.floor(((angle - 30) % 360 + 30) / 60)
		local wallDistance = A / math.cos(math.rad(((angle - nearestFace + 540) % 360) - 180))
		local out = Layout.Outward(angle)
		local position = out * (wallDistance - 1) + Vector3.new(0, Layout.SackHeight, 0)
		local cf = CFrame.lookAt(position, position + out)
		part(sackPipes, ("SackPipe_%02d"):format(index), Vector3.new(4.4, 4.4, 3), cf, Enum.Material.CorrodedMetal, C.Rust, DECOR)
		part(sackPipes, "SackPipeMouth", Vector3.new(3.4, 3.4, .2), cf * CFrame.new(0, 0, 1.55), Enum.Material.SmoothPlastic, C.Crack, DECOR)
	end

	-- Entrance corridor + arrival vestibule ------------------------------------------------------
	local entrance = folder("Entrance")
	local axis = CFrame.lookAt(Vector3.zero, Layout.Outward(E.Angle)) -- -Z of this frame points out
	local function eLocal(x, y, r) return axis * CFrame.new(x, y, -r) end -- r measured outward
	local halfW = E.Width / 2
	local cornerR = Layout.Circumradius
	local corridorStart = cornerR - 5
	local corridorLength = E.CorridorEnd - corridorStart
	local vestHalfW = E.VestibuleWidth / 2
	local vestEnd = E.CorridorEnd + E.VestibuleDepth
	-- Starts where the room floor (a 270-stud square) ends, so the two never overlap.
	part(entrance, "EntranceFloor", Vector3.new(E.VestibuleWidth + 8, 1, vestEnd + 4 - 135), eLocal(0, FY - .5, (135 + vestEnd + 4) / 2), Enum.Material.Slate, C.Floor)
	for _, side in ipairs({ -1, 1 }) do
		part(entrance, "CorridorWall", Vector3.new(T, E.Height, corridorLength), eLocal(side * (halfW + T / 2), FY + E.Height / 2, corridorStart + corridorLength / 2), Enum.Material.Brick, C.Brick)
		part(entrance, "VestibuleSideWall", Vector3.new(T, E.Height, E.VestibuleDepth + T), eLocal(side * (vestHalfW + T / 2), FY + E.Height / 2, E.CorridorEnd + E.VestibuleDepth / 2), Enum.Material.Brick, C.Brick)
		local frontWidth = vestHalfW - halfW
		part(entrance, "VestibuleFrontWall", Vector3.new(frontWidth + T, E.Height, T), eLocal(side * (halfW + frontWidth / 2 + T / 2), FY + E.Height / 2, E.CorridorEnd - T / 2), Enum.Material.Brick, C.Brick)
		part(entrance, "SealJamb", Vector3.new(2, E.Height, 2.4), eLocal(side * (halfW + 1), FY + E.Height / 2, E.SealRadius), Enum.Material.CorrodedMetal, C.Iron)
		local sconce = part(entrance, "CorridorSconce", Vector3.new(.8, 1.2, .8), eLocal(side * (halfW - .4), FY + 8, corridorStart + corridorLength * .6), Enum.Material.Neon, C.Torch, DECOR)
		light(sconce, C.Torch, 18, .6)
	end
	part(entrance, "VestibuleBackWall", Vector3.new(E.VestibuleWidth + 2 * T, E.Height, T), eLocal(0, FY + E.Height / 2, vestEnd + T / 2), Enum.Material.Brick, C.Brick)
	part(entrance, "CorridorRoof", Vector3.new(E.Width + 2 * T, 2, corridorLength), eLocal(0, FY + E.Height + 1, corridorStart + corridorLength / 2), Enum.Material.Slate, C.StoneDark)
	part(entrance, "VestibuleRoof", Vector3.new(E.VestibuleWidth + 2 * T, 2, E.VestibuleDepth + T), eLocal(0, FY + E.Height + 1, E.CorridorEnd + E.VestibuleDepth / 2), Enum.Material.Slate, C.StoneDark)
	part(entrance, "SealHeader", Vector3.new(E.Width + 4, 2, 2.4), eLocal(0, FY + E.Height - 1, E.SealRadius), Enum.Material.CorrodedMetal, C.Rust, DECOR)
	part(entrance, "ThresholdMark", Vector3.new(E.Width, .06, 1.2), eLocal(0, FY + .03, E.ThresholdRadius), Enum.Material.CorrodedMetal, C.Rust, DECOR)
	local vestLamp = part(entrance, "VestibuleLamp", Vector3.new(1, 1, 1), eLocal(0, FY + 12, E.CorridorEnd + E.VestibuleDepth / 2), Enum.Material.Neon, C.Torch, DECOR)
	light(vestLamp, C.Torch, 30, .7)

	-- Explicit station placement anchors -----------------------------------------------------
	local anchors = folder("Anchors")
	for index = 1, #Layout.Stations do
		local anchor = part(anchors, ("ANCHOR_ValveStation_%02d"):format(index), Vector3.new(2, .2, 2), Layout.StationFrame(index), Enum.Material.SmoothPlastic, C.Safe, { collide = false, shadow = false, transparency = 1 })
		anchor.CanQuery = false
		anchor:SetAttribute("GateIndex", index)
		anchor:SetAttribute("Front", "LookVector = operator facing (toward the recess back wall)")
	end

	model.Parent = arena

	-- Realm arrival point -----------------------------------------------------------------------
	local spawn = realm:FindFirstChild("SpawnPoint")
	local spawnLocal = Layout.Anchors().ANCHOR_RealmSpawn
	if spawn and spawn:IsA("BasePart") then
		spawn.CFrame = origin * CFrame.new(spawnLocal)
		table.insert(report, "moved realm SpawnPoint to " .. tostring(spawnLocal))
	end

	table.insert(report, ("built MiasmaArenaLayout with %d parts"):format(count))

	-- Blender art bays (MiasmaValveBayAssembler) hide the primitives they enclose; the rebuild
	-- just brought those back, so hide them again.
	local artBays = arena:FindFirstChild("MiasmaArtBays")
	if artBays and #artBays:GetChildren() > 0 then
		local ok, result = pcall(function()
			local assembler = loadstring(game:GetService("ServerScriptService").MiasmaValveBayAssembler.Source)()
			return assembler.ApplyCovers(arena)
		end)
		table.insert(report, ok and result or ("WARNING art bays present but covers not re-applied: " .. tostring(result)))
	end
	-- Same for the arena art v02 (MiasmaArenaArtAssembler).
	if arena:FindFirstChild("MiasmaArtV2") then
		local ok, result = pcall(function()
			local art = loadstring(game:GetService("ServerScriptService").MiasmaArenaArtAssembler.Source)()
			return art.ReapplyHides(arena)
		end)
		table.insert(report, ok and result or ("WARNING art v2 present but hides not re-applied: " .. tostring(result)))
	end
	-- Same for the older modular art kit v01 (MiasmaArenaKitAssembler).
	if arena:FindFirstChild("MiasmaArtKit") then
		local ok, result = pcall(function()
			local kit = loadstring(game:GetService("ServerScriptService").MiasmaArenaKitAssembler.Source)()
			return kit.ReapplyHides(arena)
		end)
		table.insert(report, ok and result or ("WARNING art kit present but hides not re-applied: " .. tostring(result)))
	end
	return table.concat(report, "\n")
end
