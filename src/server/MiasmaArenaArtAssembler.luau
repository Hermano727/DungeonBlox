--[[
	MiasmaArenaArtAssembler -- EDIT-TIME TOOL. Never required by the running game.

	Puts the Blender arena art v02 (assets/builds/MiasmaBossRoom/arena_v02/export, one FBX per
	group) into the arena template:

		Gates     flood-gate walls, surrounds, passages, galleries, valve platforms, water routes,
		          poison outfalls, walkable channel grates
		Station   the valve wheel and flood-gate leaf (the parts that move) -> the valve-station PREFAB
		Mechanism the static valve machinery at every gate: cabinet, gearbox, drive pipe, corner
		          gearbox, pier shaft, winch -- visible in Edit mode, not part of the prefab
		Altars    altar face walls, recess arches, alcoves, cleanse fonts
		Hub       centre basin, deck, boss ring, platform band, drain crown
		Floor     floor flags, one sector per wall face
		Entrance  entrance portal, corridor bays, corner shafts
		Ceiling   slabs, ribs, wall arches, fractured shaft rim, shaft walls
		Dressing  bones, chains, rubble, leaks, puddles, slime
		Lighting  medieval wall torches and standing torches (flames + flickering light added here)
		Props     sewer-works props (assets/builds/MiasmaBossRoom/props_v01): iron outfall pipes (they
		          REPLACE the gate kit's Gate_PipeOutfall), chains, caged lanterns, roof catwalks,
		          shoring, scaffolds, a windlass, barrels. Placed by MiasmaArenaPropsPlacements.
		PropsStream  the poison fall out of each outfall pipe (its own FBX; drips/splash/mist added here)

	The art is VISUAL ONLY. Collision stays the MiasmaArenaLayoutBuilder primitives: the ones a
	group covers are made invisible (collision kept) -- Kit.Hides. Gameplay parts (channel
	liquid, basin liquid, CleanseWater, RuneRing, safe pads, anchors, gate blockers) never change.

	Steps (Edit mode; see the arena_v02 README for the import settings):

		local Art = loadstring(game:GetService("ServerScriptService").MiasmaArenaArtAssembler.Source)()
		-- 1. every group except Station:
		print(Art.Register({ import = workspace.MiasmaArenaV2_Gates, group = "Gates" }))
		-- 2. the station group becomes the prefab used by all four gates:
		print(Art.BuildStationPrefab({ import = workspace.MiasmaArenaV2_Station }))
		-- 3. place everything:
		print(Art.Dress({ realm = workspace:FindFirstChild("DungeonRealmTemplate", true) }))

	Undo: Art.Undress({ realm = ..., groups = { "Floor" } }). Replaced things go to
	ServerStorage.MiasmaArenaBackups.ArtV2History.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Art = {}

Art.FolderName = "MiasmaArtV2"          -- inside T1DungeonTemplate
Art.StorageName = "MiasmaArenaArtV2"    -- ServerStorage
Art.PlacementsModule = "MiasmaArenaKitV2Placements"
Art.PrefabName = "MiasmaValveStationPrefab" -- shared by every gate slot
Art.Groups = { "Gates", "Mechanism", "Altars", "Hub", "Floor", "Entrance", "Ceiling", "Dressing", "Lighting", "Props", "PropsStream" }
-- More placement modules, merged into the generated one (their groups must not overlap it).
Art.ExtraPlacements = { "MiasmaArenaPropsPlacements" }

-- A module that another group's module replaces: while the replacement is registered, the old
-- one is not placed, and dressing the replacing group retires copies already placed.
-- Undressing Props does NOT bring the old outfalls back (unregister Props, then re-dress Gates).
Art.Supersedes = {
	Gate_PipeOutfall = { group = "Props", module = "Prop_PipeOutfall" },
}

-- Modules that keep collision (convex hull): floor props players would otherwise walk through.
-- Everything else stays visual only.
Art.Solid = { Prop_Scaffold = true, Prop_Shoring = true, Prop_Windlass = true, Prop_GongCluster = true }

-- Layout primitives each group covers (paths under MiasmaArenaLayout; "*" any, "Prefix*").
Art.Hides = {
	Gates = {
		"Gates/GateStructure_*/Pier", "Gates/GateStructure_*/Buttress", "Gates/GateStructure_*/ApronSide",
		"Gates/GateStructure_*/RetainingWall", "Gates/GateStructure_*/FunnelWall", "Gates/GateStructure_*/ChannelWall",
		"Gates/GateStructure_*/ApronStep", "Gates/GateStructure_*/ApronFloor", "Gates/GateStructure_*/FunnelFloor",
		"Gates/GateStructure_*/ChannelBed", "Gates/GateStructure_*/Bridge", "Gates/GateStructure_*/BridgeParapet",
		"Gates/GateStructure_*/Grate", "Gates/GateStructure_*/ValvePlatform", "Gates/GateStructure_*/PlatformStep",
		"Gates/GateStructure_*/PitFloor", "Gates/GateStructure_*/PitKerb", "Gates/GateStructure_*/WallButtress",
		"Walls/Pilaster", "Walls/BaseCourse",
	},
	Altars = {
		"Altars/CleanseAltar_*/Plinth", "Altars/CleanseAltar_*/Pedestal", "Altars/CleanseAltar_*/Basin",
		"Recesses/AltarRecess_*/SideWall", "Recesses/AltarRecess_*/BackWall", "Recesses/AltarRecess_*/Roof",
		"Recesses/AltarRecess_*/RecessFloor", "Walls/ArchStone",
	},
	Hub = { "Floor/BasinFloor", "Floor/BasinRim", "Floor/PlatformEdge" },
	Floor = { "Floor/Sector", "Floor/EntranceMouth" },
	Entrance = { "Walls/Buttress" },
	Ceiling = {
		"Ceiling/CeilingNorth", "Ceiling/CeilingSouth", "Ceiling/CeilingWest", "Ceiling/CeilingEast",
		"Ceiling/Rib", "Ceiling/ShaftRimBeam", "Ceiling/Fracture", "Ceiling/ShaftWall",
	},
	Dressing = {},
	Mechanism = {},
	Lighting = { "Walls/Sconce" }, -- the old neon corner sconces (their lights switch off too)
	Props = {},
	PropsStream = {},
}

-- Module-local light points the meshes cannot carry. `torch = true` adds the layered flame,
-- sparks and smoke, and tags the light for TorchFlicker.client.
local FIRE = Color3.fromRGB(255, 150, 70)
local POISON = Color3.fromRGB(170, 70, 230)
Art.TorchLightTag = "MiasmaTorchLight"
Art.Lights = {
	Torch_Wall = { { position = Vector3.new(0, 2.338, 1.647), color = FIRE, range = 24, brightness = 1.7, torch = true } },
	Torch_Stand = { { position = Vector3.new(0, 6.436, 0), color = FIRE, range = 26, brightness = 1.8, torch = true } },
	EntranceArch_16 = {
		{ position = Vector3.new(-14.4, 11.3, 10.6), color = FIRE, range = 22, brightness = 1.4, torch = true },
		{ position = Vector3.new(14.4, 11.3, 10.6), color = FIRE, range = 22, brightness = 1.4, torch = true },
	},
	Gate_Poison = { { position = Vector3.new(32, 6, 4), color = POISON, range = 20, brightness = 1.2 } },
	Gate_PipeOutfall = { { position = Vector3.new(55, 20, 5), color = POISON, range = 16, brightness = .9 } },
	Gate_ValvePlatform = { { position = Vector3.new(-38, 7, 3), color = FIRE, range = 18, brightness = 1.1 } },
	Prop_PipeOutfall = { { position = Vector3.new(0, 2.5, 7.8), color = POISON, range = 14, brightness = .9 } },
	Prop_PoisonStream = { { position = Vector3.new(0, -30.5, 0), color = POISON, range = 16, brightness = 1.1 } },
	-- flicker = true: tagged for TorchFlicker like a torch, without the torch flames
	Prop_CageLantern = { { position = Vector3.new(0, -9.85, 0), color = FIRE, range = 26, brightness = 1.3, flicker = true } },
}

local REF_BACK = Vector3.new(0, 0, -5)
local REF_UP = Vector3.new(0, 5, 0)

-------------------------------------------------------------------------------------------------

local function freshRequire(moduleScript)
	local copy = moduleScript:Clone()
	copy.Name = moduleScript.Name .. "_ArtCopy"
	copy.Parent = moduleScript.Parent
	local ok, result = pcall(require, copy)
	copy:Destroy()
	if not ok then error(result, 2) end
	return result
end

local function arenaOf(realm)
	local room = realm:FindFirstChild("T1 BOSS ROOM")
	local miasma = room and room:FindFirstChild("miasma")
	local arena = miasma and miasma:FindFirstChild("T1DungeonTemplate")
	assert(arena, "no <realm>/T1 BOSS ROOM/miasma/T1DungeonTemplate")
	return arena
end

local function retire(instance)
	local backups = ServerStorage:FindFirstChild("MiasmaArenaBackups") or Instance.new("Folder")
	backups.Name = "MiasmaArenaBackups"
	backups.Parent = ServerStorage
	local history = backups:FindFirstChild("ArtV2History") or Instance.new("Folder")
	history.Name = "ArtV2History"
	history.Parent = backups
	instance.Name = instance.Name .. "_" .. os.date("!%Y%m%d_%H%M%S")
	instance.Parent = history
	return instance.Name
end

local function findPart(model, name)
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") and item.Name == name then return item end
	end
	return nil
end

-- Moves an import so its REF markers sit at the origin (identity frame); fixes uniform scale.
local function alignToOrigin(model, report)
	local function frameOf()
		local origin, back, up = findPart(model, "REF_Origin"), findPart(model, "REF_Back"), findPart(model, "REF_Up")
		assert(origin and back and up, model.Name .. ": REF markers missing (Merge Meshes on?)")
		local toBack, toUp = back.Position - origin.Position, up.Position - origin.Position
		local scale = toBack.Magnitude / REF_BACK.Magnitude
		assert(math.abs(toUp.Magnitude / REF_UP.Magnitude - scale) < .01 * scale, model.Name .. ": non-uniform import scale")
		assert(math.abs(toBack.Unit:Dot(toUp.Unit)) < .01, model.Name .. ": REF axes not perpendicular")
		return CFrame.lookAt(origin.Position, origin.Position + toBack, toUp.Unit), scale
	end
	local frame, scale = frameOf()
	if math.abs(scale - 1) > .002 then
		model:ScaleTo(model:GetScale() / scale)
		table.insert(report, ("%s imported at %.4fx; rescaled to studs"):format(model.Name, scale))
		frame = frameOf()
	end
	local delta = frame:Inverse()
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then part.CFrame = delta * part.CFrame end
	end
end

local function setVisual(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	pcall(function() part.CollisionFidelity = Enum.CollisionFidelity.Box end)
end

local function untextured(part)
	return not part:FindFirstChildOfClass("SurfaceAppearance") and not (part:IsA("MeshPart") and part.TextureID ~= "")
end

-------------------------------------------------------------------------------------------------
-- Register (every group except Station)

function Art.Register(options)
	local import = assert(options.import, "import (the imported model) required")
	local group = assert(options.group, "group required")
	assert(table.find(Art.Groups, group), "unknown group " .. tostring(group) .. " (Station uses BuildStationPrefab)")
	local report = {}
	alignToOrigin(import, report)
	local storage = ServerStorage:FindFirstChild(Art.StorageName) or Instance.new("Folder")
	storage.Name = Art.StorageName
	storage.Parent = ServerStorage
	local groupFolder = storage:FindFirstChild(group) or Instance.new("Folder")
	groupFolder.Name = group
	groupFolder.Parent = storage
	local modules, bare = {}, {}
	for _, part in ipairs(import:GetDescendants()) do
		if part:IsA("BasePart") and not string.match(part.Name, "^REF_") then
			local moduleName = string.match(part.Name, "^(.-)__") or part.Name
			local model = modules[moduleName]
			if not model then
				model = Instance.new("Model")
				model.Name = moduleName
				modules[moduleName] = model
			end
			setVisual(part)
			part.CastShadow = not (string.find(part.Name, "__Residue") or string.find(part.Name, "__Slime") or string.find(part.Name, "__Stream"))
			if Art.Solid[moduleName] then
				part.CanCollide = true
				pcall(function() part.CollisionFidelity = Enum.CollisionFidelity.Hull end)
			end
			if untextured(part) then table.insert(bare, part.Name) end
			part.Parent = model
		end
	end
	local count = 0
	for name, model in pairs(modules) do
		local old = groupFolder:FindFirstChild(name)
		if old then retire(old) end
		model.WorldPivot = CFrame.identity
		model.Parent = groupFolder
		count += 1
	end
	import:Destroy()
	table.insert(report, ("registered %d %s modules"):format(count, group))
	if #bare > 0 then table.insert(report, "WARNING untextured: " .. table.concat(bare, ", ")) end
	return table.concat(report, "\n")
end

-------------------------------------------------------------------------------------------------
-- Station prefab

-- Primitive station parts that stay exactly as built (gameplay hosts and state visuals).
local KEEP = {
	["Pivot"] = true, ["Valve/Interact"] = true, ["Indicator/Lamp"] = true, ["Indicator/Plaque"] = true,
	["RuneDisplay/PlateGlow"] = true,
}
local HOSTS = { ["Valve/WheelRoot"] = true, ["Sluice/GateRoot"] = true, ["RuneDisplay/Tablet"] = true }
local KEEP_FOLDERS = { Growth = true }
-- Primitive collision that no longer applies beside a flood gate (the platform, wall and gate
-- blocker come from the layout now).
local DROP_FOLDERS = { Structure = true, Channel = true, Dressing = true }
local DROP = { ["Sluice/GateCollision"] = true }

local function pathOf(instance, root)
	local names = {}
	local node = instance
	while node and node ~= root do
		table.insert(names, 1, node.Name)
		node = node.Parent
	end
	return table.concat(names, "/")
end

function Art.BuildStationPrefab(options)
	local import = assert(options.import, "import (the imported MiasmaArenaV2_Station) required")
	local Builder = freshRequire(ServerScriptService:WaitForChild("MiasmaValveStationBuilder"))
	local Layout = require(ReplicatedStorage:WaitForChild("MiasmaArenaLayout"))
	assert(Builder.BuildPrimitive, "MiasmaValveStationBuilder is out of date (Rojo not synced?)")
	assert(Layout.Gate, "MiasmaArenaLayout has no Gate table (Rojo not synced?)")
	local report = {}
	-- The station export's REF markers sit at the station frame, so this lands station-local.
	alignToOrigin(import, report)
	local temp = Instance.new("Folder")
	temp.Name = "MiasmaArenaArtAssembler_Temp"
	temp.Parent = ServerStorage
	local prefab = Builder.BuildPrimitive(temp, CFrame.identity, Art.PrefabName)

	local removed, blockers = 0, 0
	for _, part in ipairs(prefab:GetDescendants()) do
		if part:IsA("BasePart") then
			local path = pathOf(part, prefab)
			local top = string.split(path, "/")[1]
			if DROP_FOLDERS[top] or DROP[path] then
				part:Destroy()
				removed += 1
			elseif KEEP[path] or KEEP_FOLDERS[top] then
				-- unchanged
			elseif HOSTS[path] then
				part.Transparency = 1
				part.CastShadow = false
				part.CanCollide = false
			elseif part.CanCollide then
				part.Transparency = 1
				part.CastShadow = false
				blockers += 1
			else
				part:Destroy()
				removed += 1
			end
		end
	end
	for _, item in ipairs(prefab:GetDescendants()) do
		if (item:IsA("Model") or item:IsA("Folder")) and not item:FindFirstChildWhichIsA("BasePart", true) then item:Destroy() end
	end
	table.insert(report, ("prefab: %d primitive parts removed, %d kept as invisible collision"):format(removed, blockers))

	local art = Instance.new("Folder")
	art.Name = "Art"
	art.Parent = prefab
	local moving = { Valve_Wheel = "Valve/WheelRoot", Gate_Flood_20x30 = "Sluice/GateRoot" }
	local bare = {}
	for _, part in ipairs(import:GetDescendants()) do
		if part:IsA("BasePart") and not string.match(part.Name, "^REF_") then
			local moduleName = string.match(part.Name, "^(.-)__") or part.Name
			local hostPath = moving[moduleName]
			if hostPath then
				local folderName, hostName = table.unpack(string.split(hostPath, "/"))
				local host = assert(prefab:FindFirstChild(folderName) and prefab[folderName]:FindFirstChild(hostName), "prefab has no " .. hostPath)
				part.Anchored = false
				part.Massless = true
				part.CanCollide = false
				part.CanQuery = false
				part.CanTouch = false
				part.Parent = host.Parent
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = host
				weld.Part1 = part
				weld.Parent = part
			else
				setVisual(part)
				part.Parent = art
			end
			if untextured(part) then table.insert(bare, part.Name) end
		end
	end
	prefab.Sluice.GateRoot:SetAttribute("SlideDistance", Layout.Gate.SlideDistance)
	prefab:SetAttribute("ArtSource", "arena_v02")
	import:Destroy()
	local old = ServerStorage:FindFirstChild(Art.PrefabName)
	if old then table.insert(report, "previous prefab moved to " .. retire(old)) end
	prefab.Parent = ServerStorage
	temp:Destroy()
	table.insert(report, "built ServerStorage." .. Art.PrefabName .. " (all four gates)")
	if #bare > 0 then table.insert(report, "WARNING untextured: " .. table.concat(bare, ", ")) end

	-- Refresh the Edit-mode dev station preview if one is standing.
	local dev = Workspace:FindFirstChild("MiasmaValveDev")
	local realm = Workspace:FindFirstChild("DungeonRealmTemplate", true)
	if dev and dev:FindFirstChild("ValveStation") and realm then
		local Resolver = freshRequire(ServerScriptService:WaitForChild("MiasmaArenaResolver"))
		Builder.Build(dev, Resolver.new(realm):ValveStationFrame(4), "ValveStation", { realm }, "NorthWest")
		table.insert(report, "rebuilt Workspace.MiasmaValveDev.ValveStation with the new prefab")
	end
	return table.concat(report, "\n")
end

-------------------------------------------------------------------------------------------------
-- Hides

local function segmentMatches(pattern, name)
	if pattern == "*" then return true end
	if string.sub(pattern, -1) == "*" then
		local prefix = string.sub(pattern, 1, -2)
		return string.sub(name, 1, #prefix) == prefix
	end
	return pattern == name
end

local function matchPath(root, path)
	local nodes = { root }
	for _, segment in ipairs(string.split(path, "/")) do
		local nextNodes = {}
		for _, node in ipairs(nodes) do
			for _, child in ipairs(node:GetChildren()) do
				if segmentMatches(segment, child.Name) then table.insert(nextNodes, child) end
			end
		end
		nodes = nextNodes
	end
	return nodes
end

local function hideGroup(arena, group)
	local layout = arena:FindFirstChild("MiasmaArenaLayout")
	if not layout then return 0 end
	local hidden = 0
	for _, path in ipairs(Art.Hides[group] or {}) do
		for _, part in ipairs(matchPath(layout, path)) do
			if part:IsA("BasePart") then
				if part:GetAttribute("ArtV2Hidden") == nil then
					part:SetAttribute("ArtV2OriginalTransparency", part.Transparency)
					part:SetAttribute("ArtV2OriginalShadow", part.CastShadow)
				end
				part:SetAttribute("ArtV2Hidden", group)
				part.Transparency = 1
				part.CastShadow = false
				for _, light in ipairs(part:GetChildren()) do
					if light:IsA("Light") then light.Enabled = false end
				end
				hidden += 1
			end
		end
	end
	return hidden
end

local function unhideGroup(arena, group)
	local layout = arena:FindFirstChild("MiasmaArenaLayout")
	if not layout then return 0 end
	local restored = 0
	for _, part in ipairs(layout:GetDescendants()) do
		if part:IsA("BasePart") and part:GetAttribute("ArtV2Hidden") == group then
			part.Transparency = part:GetAttribute("ArtV2OriginalTransparency") or 0
			part.CastShadow = part:GetAttribute("ArtV2OriginalShadow") ~= false
			for _, light in ipairs(part:GetChildren()) do
				if light:IsA("Light") then light.Enabled = true end
			end
			part:SetAttribute("ArtV2Hidden", nil)
			part:SetAttribute("ArtV2OriginalTransparency", nil)
			part:SetAttribute("ArtV2OriginalShadow", nil)
			restored += 1
		end
	end
	return restored
end

-- Idempotent; MiasmaArenaLayoutBuilder calls this after a rebuild.
function Art.ReapplyHides(arena)
	local folder = arena:FindFirstChild(Art.FolderName)
	if not folder then return "art v2: nothing dressed" end
	local total = 0
	for _, group in ipairs(Art.Groups) do
		if folder:FindFirstChild(group) then total += hideGroup(arena, group) end
	end
	return ("art v2: %d layout parts hidden (collision kept)"):format(total)
end

-------------------------------------------------------------------------------------------------
-- Dress

local function scaleInPlace(model, scale)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local rotation = part.CFrame.Rotation
			part.Size = part.Size * scale
			part.CFrame = CFrame.new(part.Position * scale) * rotation
		end
	end
end

local function emitter(parent, name, props)
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	for key, value in pairs(props) do e[key] = value end
	e.Parent = parent
	return e
end

-- A living torch flame: two flame layers, sparks, a thread of smoke.
local function torchFire(holder)
	local keys = NumberSequenceKeypoint.new
	emitter(holder, "FlameCore", {
		Texture = "rbxasset://textures/particles/fire_main.dds",
		Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 236, 170)), ColorSequenceKeypoint.new(.45, Color3.fromRGB(255, 140, 50)), ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 40, 10)) }),
		LightEmission = 1, LightInfluence = 0,
		Size = NumberSequence.new({ keys(0, .55), keys(.4, .75), keys(1, .1) }),
		Transparency = NumberSequence.new({ keys(0, .15), keys(.7, .4), keys(1, 1) }),
		Lifetime = NumberRange.new(.35, .6), Rate = 45, Speed = NumberRange.new(1.4, 2.4),
		SpreadAngle = Vector2.new(9, 9), Acceleration = Vector3.new(0, 3, 0),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-40, 40), EmissionDirection = Enum.NormalId.Top,
	})
	emitter(holder, "FlameOuter", {
		Texture = "rbxasset://textures/particles/fire_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(255, 120, 40), Color3.fromRGB(110, 25, 5)),
		LightEmission = .8, LightInfluence = 0,
		Size = NumberSequence.new({ keys(0, .9), keys(1, .25) }),
		Transparency = NumberSequence.new({ keys(0, .55), keys(1, 1) }),
		Lifetime = NumberRange.new(.45, .8), Rate = 18, Speed = NumberRange.new(1.8, 2.8),
		SpreadAngle = Vector2.new(14, 14), Acceleration = Vector3.new(0, 2.5, 0),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-25, 25), EmissionDirection = Enum.NormalId.Top,
	})
	emitter(holder, "Sparks", {
		Texture = "rbxasset://textures/particles/fire_sparks_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(255, 190, 90)), LightEmission = 1, LightInfluence = 0,
		Size = NumberSequence.new({ keys(0, .12), keys(1, .02) }),
		Transparency = NumberSequence.new({ keys(0, 0), keys(1, 1) }),
		Lifetime = NumberRange.new(.9, 1.6), Rate = 3, Speed = NumberRange.new(2, 4),
		SpreadAngle = Vector2.new(30, 30), Acceleration = Vector3.new(0, 1.5, 0), EmissionDirection = Enum.NormalId.Top,
	})
	emitter(holder, "Smoke", {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(40, 36, 32)), LightInfluence = 1,
		Size = NumberSequence.new({ keys(0, .5), keys(1, 2.4) }),
		Transparency = NumberSequence.new({ keys(0, .82), keys(1, 1) }),
		Lifetime = NumberRange.new(2, 3), Rate = 4, Speed = NumberRange.new(1.5, 2.5),
		SpreadAngle = Vector2.new(10, 10), Acceleration = Vector3.new(0, .8, 0), EmissionDirection = Enum.NormalId.Top,
	})
end

local function addLights(model, name)
	local host = model:FindFirstChildWhichIsA("BasePart", true)
	if not host then return end
	for _, spec in ipairs(Art.Lights[name] or {}) do
		local holder = Instance.new("Attachment")
		holder.Name = spec.torch and "TorchFlame" or "ArtLight"
		holder.Parent = host -- parent FIRST: WorldPosition on an unparented attachment is taken as local
		holder.WorldPosition = model:GetPivot():PointToWorldSpace(spec.position)
		local light = Instance.new("PointLight")
		light.Color = spec.color
		light.Range = spec.range
		light.Brightness = spec.brightness
		light.Shadows = false
		light.Parent = holder
		if spec.torch or spec.flicker then
			light:SetAttribute("BaseBrightness", spec.brightness)
			light:SetAttribute("BaseRange", spec.range)
			CollectionService:AddTag(light, Art.TorchLightTag)
		end
		if spec.torch then torchFire(holder) end
	end
end

-- The poison fall: streaks sliding down the stream, droplets bursting off the pool, a low mist.
-- Positions are Prop_PoisonStream-local (origin = the pipe mouth, the pool STREAM_DROP below).
local STREAM_DROP = 31.9
-- The stream's own streak map (imported with MiasmaArenaV2_PropsStream; read off the mesh's
-- SurfaceAppearance when present, this is the fallback). Vertical streaks, tiles both ways.
local STREAM_STREAK_TEXTURE = "rbxassetid://93312679867529"
local STREAM_FLOW_LAYERS = {
	{ tileU = 3.2, tileV = 9, speed = 7, transparency = .05, tint = Color3.fromRGB(255, 255, 255) },
	{ tileU = 2.1, tileV = 5, speed = 12, transparency = .55, tint = Color3.fromRGB(235, 200, 255) },
	-- Reads from across the arena, where the fine streaks above blur to flat purple: big soft
	-- bright blobs rolling down fast (the engine's smoke puff, alpha-cut, tinted).
	{ texture = "rbxasset://textures/particles/smoke_main.dds", tileU = 3.4, tileV = 7, speed = 16, transparency = .2, tint = Color3.fromRGB(240, 185, 255) },
}
local function poisonFall(model)
	local host = model:FindFirstChild("Prop_PoisonStream__Stream", true) or model:FindFirstChildWhichIsA("BasePart", true)
	if not host then return end
	host.CastShadow = false
	-- The running surface: the imported streak map as scrolling Textures (two layers at different
	-- speed and tiling, for depth) on all four sides, animated by ScrollingTextures.client. The
	-- static SurfaceAppearance would show under them as frozen streaks, so the base goes plain.
	local streaks = STREAM_STREAK_TEXTURE
	local sa = host:FindFirstChildOfClass("SurfaceAppearance")
	if sa then
		if sa.ColorMap ~= "" then streaks = sa.ColorMap end
		sa:Destroy()
	end
	host.Color = Color3.fromRGB(78, 24, 112)
	host.Material = Enum.Material.SmoothPlastic
	host.Reflectance = .08
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right }) do
		for _, layer in ipairs(STREAM_FLOW_LAYERS) do
			local texture = Instance.new("Texture")
			texture.Name = "Flow"
			texture.Texture = layer.texture or streaks
			texture.Face = face
			texture.StudsPerTileU = layer.tileU
			texture.StudsPerTileV = layer.tileV
			texture.Transparency = layer.transparency
			texture.Color3 = layer.tint
			texture:SetAttribute("ScrollV", layer.speed)
			CollectionService:AddTag(texture, "ScrollingTexture")
			texture.Parent = host
		end
	end
	local keys = NumberSequenceKeypoint.new
	local pivot = model:GetPivot()
	local function at(name, localPos)
		local a = Instance.new("Attachment")
		a.Name = name
		a.Parent = host -- parent FIRST (see addLights)
		a.WorldCFrame = pivot * CFrame.new(localPos)
		return a
	end
	local light, dark = Color3.fromRGB(205, 130, 255), Color3.fromRGB(120, 45, 170)
	for i = 0, 3 do
		local angle = i * math.pi / 2 + .4
		emitter(at("FallStreaks", Vector3.new(math.cos(angle) * 1.35, -.4, math.sin(angle) * 1.35)), "Streaks", {
			Texture = "rbxasset://textures/particles/sparkles_main.dds",
			Color = ColorSequence.new(light, dark), LightEmission = .85, LightInfluence = .2,
			Size = NumberSequence.new({ keys(0, .7), keys(1, 1.2) }),
			Squash = NumberSequence.new(-1.5),
			Transparency = NumberSequence.new({ keys(0, .3), keys(.85, .5), keys(1, 1) }),
			Orientation = Enum.ParticleOrientation.VelocityParallel,
			EmissionDirection = Enum.NormalId.Bottom, Speed = NumberRange.new(7, 9), SpreadAngle = Vector2.new(2, 2),
			Acceleration = Vector3.new(0, -40, 0), Lifetime = NumberRange.new(1, 1.05), Rate = 24,
		})
	end
	local pool = at("PoolSplash", Vector3.new(0, -STREAM_DROP + .4, 0))
	emitter(pool, "Splash", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(light, dark), LightEmission = .5,
		Size = NumberSequence.new({ keys(0, .35), keys(1, .1) }),
		Transparency = NumberSequence.new({ keys(0, .1), keys(1, 1) }),
		EmissionDirection = Enum.NormalId.Top, Speed = NumberRange.new(6, 11), SpreadAngle = Vector2.new(55, 55),
		Acceleration = Vector3.new(0, -40, 0), Lifetime = NumberRange.new(.45, .8), Rate = 24,
	})
	emitter(pool, "Mist", {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new(dark), LightEmission = .25, LightInfluence = .6,
		Size = NumberSequence.new({ keys(0, 2), keys(1, 6) }),
		Transparency = NumberSequence.new({ keys(0, .75), keys(1, 1) }),
		EmissionDirection = Enum.NormalId.Top, Speed = NumberRange.new(.8, 2), SpreadAngle = Vector2.new(70, 70),
		Acceleration = Vector3.new(0, .8, 0), Lifetime = NumberRange.new(2, 3), Rate = 5,
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-15, 15),
	})
end

-- Per-module extras, run after the lights (by module name).
Art.Effects = { Prop_PoisonStream = poisonFall }

function Art.Dress(options)
	local realm = assert(options.realm, "realm required")
	local arena = arenaOf(realm)
	local placements = freshRequire(ServerScriptService:WaitForChild(Art.PlacementsModule))
	for _, name in ipairs(Art.ExtraPlacements) do
		for group, rows in pairs(freshRequire(ServerScriptService:WaitForChild(name)).Groups) do
			assert(placements.Groups[group] == nil, name .. " redefines placement group " .. group)
			placements.Groups[group] = rows
		end
	end
	local Layout = require(ReplicatedStorage:WaitForChild("MiasmaArenaLayout"))
	for key, value in pairs(placements.Layout) do
		assert(Layout[key] == value, ("placements were generated for %s = %s but MiasmaArenaLayout has %s"):format(key, tostring(value), tostring(Layout[key])))
	end
	assert(arena:FindFirstChild("MiasmaArenaLayout") and arena.MiasmaArenaLayout:FindFirstChild("Gates"),
		"rebuild the layout first (MiasmaArenaLayoutBuilder): the v2 art needs its collision")
	local Resolver = freshRequire(ServerScriptService:WaitForChild("MiasmaArenaResolver"))
	local origin = Resolver.new(realm).Origin
	local storage = ServerStorage:FindFirstChild(Art.StorageName)
	local report = {}
	local root = arena:FindFirstChild(Art.FolderName) or Instance.new("Folder")
	root.Name = Art.FolderName
	root.Parent = arena
	-- Superseded modules: skipped while their replacement is registered (Art.Supersedes).
	local superseded = {}
	for old, by in pairs(Art.Supersedes) do
		local byGroup = storage and storage:FindFirstChild(by.group)
		if byGroup and byGroup:FindFirstChild(by.module) then superseded[old] = by.group end
	end
	for _, group in ipairs(options.groups or Art.Groups) do
		local source = storage and storage:FindFirstChild(group)
		local rows = placements.Groups[group]
		if not source then
			table.insert(report, group .. ": not registered, skipped")
		elseif rows then
			local old = root:FindFirstChild(group)
			if old then
				unhideGroup(arena, group)
				retire(old)
			end
			local folder = Instance.new("Folder")
			folder.Name = group
			local placed, missing = 0, {}
			local retired = 0
			for old, byGroup in pairs(superseded) do
				if byGroup == group then
					for _, placedModel in ipairs(root:GetDescendants()) do
						if placedModel:IsA("Model") and placedModel.Name == old then
							retire(placedModel)
							retired += 1
						end
					end
				end
			end
			if retired > 0 then table.insert(report, ("%s: retired %d superseded modules"):format(group, retired)) end
			for _, row in ipairs(rows) do
				local module = source:FindFirstChild(row[1])
				if superseded[row[1]] then
					-- replaced by another group's module (Art.Supersedes)
				elseif module then
					local copy = module:Clone()
					if row[14] then scaleInPlace(copy, Vector3.new(row[14], row[15], row[16])) end
					copy:PivotTo(origin * CFrame.new(row[2], row[3], row[4], row[5], row[6], row[7], row[8], row[9], row[10], row[11], row[12], row[13]))
					addLights(copy, row[1])
					if Art.Effects[row[1]] then Art.Effects[row[1]](copy) end
					copy.Parent = folder
					placed += 1
				else
					missing[row[1]] = true
				end
			end
			folder.Parent = root
			local names = {}
			for name in pairs(missing) do table.insert(names, name) end
			table.insert(report, ("%s: placed %d, hid %d layout parts%s"):format(group, placed, hideGroup(arena, group),
				#names > 0 and (", MISSING modules: " .. table.concat(names, ", ")) or ""))
		end
	end
	if not ServerStorage:FindFirstChild(Art.PrefabName) then
		table.insert(report, "NOTE: no " .. Art.PrefabName .. " yet -- run BuildStationPrefab, or the gates play with primitive stations")
	end
	return table.concat(report, "\n")
end

function Art.Undress(options)
	local arena = arenaOf(assert(options.realm, "realm required"))
	local root = arena:FindFirstChild(Art.FolderName)
	local report = {}
	for _, group in ipairs(options.groups or Art.Groups) do
		local folder = root and root:FindFirstChild(group)
		local restored = unhideGroup(arena, group)
		if folder then
			table.insert(report, ("%s: moved to %s, restored %d layout parts"):format(group, retire(folder), restored))
		end
	end
	return table.concat(report, "\n")
end

return Art
