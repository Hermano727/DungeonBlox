--[[
	MiasmaValveBayAssembler -- EDIT-TIME TOOL. Never required by the running game.

	Turns the two imported Blender models of a valve/gate art bay
	(assets/builds/MiasmaBossRoom/valve_gate_bay_v01/export) into:

	  1. ServerStorage.MiasmaValveStationPrefab_<SlotName>
	     The primitive station with its replaced visuals stripped (anything that collided stays
	     as an invisible blocker, so collision is unchanged) plus the imported station art.
	     The Blender wheel and gate are welded to Valve/WheelRoot and Sluice/GateRoot, so
	     MiasmaValveStation turns and lifts them exactly as before. Every named-contract part
	     and attachment is the primitive builder's own, so gameplay code sees no difference.
	  2. <arena>/MiasmaArtBays/ValveBay_<SlotName>
	     The static shell (arch, vault, walls, floor, dressing) at that slot's station frame,
	     plus its COL_* proxies as invisible collision. Layout primitives it fully encloses are
	     made invisible (collision kept), so nothing z-fights with the art.

	Run from the command bar / MCP in EDIT mode, after File > Import 3D of both FBX files
	(see the bay's README.md for the import settings):

		local SSS = game:GetService("ServerScriptService")
		local Assembler = loadstring(SSS.MiasmaValveBayAssembler.Source)()
		print(Assembler.Assemble({
			realm = workspace:FindFirstChild("DungeonRealmTemplate", true),
			slots = { 1, 2, 3, 4 },                 -- every station recess (or slot = 4 for NorthWest only)
			station = workspace.ValveBay_Station_v01, -- the imported models, anywhere in Workspace
			shell = workspace.ValveBay_Shell_v01,
		}))

	The imports are consumed (their parts are moved; the empty models are destroyed). Anything
	replaced (an older prefab or bay) goes to ServerStorage.MiasmaArenaBackups.ArtBayHistory.
	Undo: Assembler.Remove({ realm = ..., slot = 4 }).

	Alignment uses the REF_Origin / REF_Back / REF_Up markers exported with both models
	(station-local (0,0,0), (0,0,-5), (0,5,0)), so wherever the importer drops them, and at
	whatever uniform scale, they land in the right place; a wrong scale is corrected and
	reported, a mirrored import is refused.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Assembler = {}

Assembler.ArtBayFolderName = "MiasmaArtBays"
Assembler.PrefabName = "MiasmaValveStationPrefab"
Assembler.SourceTag = "valve_gate_bay_v01"
Assembler.GateSlideDistance = 7.6 -- the Blender gate is 7.6 tall and hides fully in the wall slot

-- Station-local box the shell covers; layout parts entirely inside it are hidden.
Assembler.CoverMin = Vector3.new(-19.6, -1, -8)
Assembler.CoverMax = Vector3.new(17.6, 20.6, 16.4)

local REF_BACK = Vector3.new(0, 0, -5)
local REF_UP = Vector3.new(0, 5, 0)

-- Primitive station parts that stay exactly as built (gameplay hosts and state visuals).
local KEEP = {
	["Pivot"] = true,
	["Valve/Interact"] = true,
	["Indicator/Lamp"] = true,
	["Indicator/Plaque"] = true,
	["RuneDisplay/PlateGlow"] = true,
	["Channel/Sludge"] = true,
	["Channel/Water"] = true,
	["Sluice/GateCollision"] = true,
}
-- Kept but invisible: the art is welded to / drawn over them.
local HOSTS = {
	["Valve/WheelRoot"] = true,
	["Sluice/GateRoot"] = true,
	["RuneDisplay/Tablet"] = true, -- its SurfaceGui still renders over the Blender stele face
}
local KEEP_FOLDERS = { Growth = true } -- corruption blobs toggled by state

-- Moving art: mesh name -> contract part it is welded to.
local MOVING = {
	Bay_ValveWheel = "Valve/WheelRoot",
	Bay_SluiceGate = "Sluice/GateRoot",
}

-------------------------------------------------------------------------------------------------

-- require() caches for the whole Edit session; a fresh clone always runs the current source.
local function freshRequire(moduleScript)
	local copy = moduleScript:Clone()
	copy.Name = moduleScript.Name .. "_AssemblerCopy"
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

local function backupFolder()
	local backups = ServerStorage:FindFirstChild("MiasmaArenaBackups") or Instance.new("Folder")
	backups.Name = "MiasmaArenaBackups"
	backups.Parent = ServerStorage
	local history = backups:FindFirstChild("ArtBayHistory") or Instance.new("Folder")
	history.Name = "ArtBayHistory"
	history.Parent = backups
	return history
end

local function stamp()
	return os.date("!%Y%m%d_%H%M%S")
end

local function pathOf(instance, root)
	local names = {}
	local node = instance
	while node and node ~= root do
		table.insert(names, 1, node.Name)
		node = node.Parent
	end
	return table.concat(names, "/")
end

local function findPart(model, name)
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") and item.Name == name then return item end
	end
	return nil
end

-- The import's own station frame from its three reference cubes (their centres are exact).
-- Returns frame, scale (import studs per authored stud).
local function importFrame(model)
	local origin, back, up = findPart(model, "REF_Origin"), findPart(model, "REF_Back"), findPart(model, "REF_Up")
	assert(origin and back and up, model.Name .. ": REF_Origin / REF_Back / REF_Up not found (were they deleted, or was Merge Meshes on?)")
	local toBack = back.Position - origin.Position
	local toUp = up.Position - origin.Position
	local scale = toBack.Magnitude / REF_BACK.Magnitude
	assert(scale > 1e-3, model.Name .. ": REF markers coincide")
	assert(math.abs(toUp.Magnitude / REF_UP.Magnitude - scale) < .01 * scale, model.Name .. ": non-uniform scale on import")
	assert(math.abs(toBack.Unit:Dot(toUp.Unit)) < .01, model.Name .. ": REF axes are not perpendicular")
	return CFrame.lookAt(origin.Position, origin.Position + toBack, toUp.Unit), scale
end

-- Moves every part of `model` so its station frame lands on `target`. Fixes uniform scale.
local function alignImport(model, target, report)
	local frame, scale = importFrame(model)
	if math.abs(scale - 1) > .002 then
		model:ScaleTo(model:GetScale() / scale)
		table.insert(report, ("%s imported at %.4fx scale; rescaled to studs (check Scale Unit next time)"):format(model.Name, scale))
		frame, scale = importFrame(model)
	end
	local delta = target * frame:Inverse()
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then part.CFrame = delta * part.CFrame end
	end
end

-- A mirrored import passes the REF check (two axes only); catch it on a known asymmetric mesh.
local function assertNotMirrored(part, target, expected, label)
	assert(part, label .. " not found in the import")
	local localPosition = target:PointToObjectSpace(part.Position)
	assert((localPosition - expected).Magnitude < .6, ("%s landed at %s, expected about %s: mirrored or wrong axes on import"):format(label, tostring(localPosition), tostring(expected)))
end

local function setVisual(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	pcall(function() part.CollisionFidelity = Enum.CollisionFidelity.Box end)
end

local function setCollisionProxy(part)
	part.Anchored = true
	part.CanCollide = true
	part.CanQuery = true
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	pcall(function() part.CollisionFidelity = Enum.CollisionFidelity.Box end)
end

local function textureNote(part)
	if part:FindFirstChildOfClass("SurfaceAppearance") then return nil end
	if part:IsA("MeshPart") and part.TextureID ~= "" then return part.Name .. " (TextureID only, no SurfaceAppearance)" end
	return part.Name .. " (no texture)"
end

-------------------------------------------------------------------------------------------------
-- Covers: hide layout primitives an art bay fully encloses.

local function insideBox(part, frame, min, max)
	local half = part.Size / 2
	for _, sx in ipairs({ -1, 1 }) do
		for _, sy in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				local corner = frame:PointToObjectSpace(part.CFrame:PointToWorldSpace(half * Vector3.new(sx, sy, sz)))
				if corner.X < min.X or corner.Y < min.Y or corner.Z < min.Z or corner.X > max.X or corner.Y > max.Y or corner.Z > max.Z then
					return false
				end
			end
		end
	end
	return true
end

local function isGameplayLayout(part, layout)
	local node = part.Parent
	while node and node ~= layout do
		if node.Name == "Channels" or node.Name == "Anchors" then return true end
		node = node.Parent
	end
	return false
end

-- Idempotent; call after rebuilding MiasmaArenaLayout (the layout builder does it itself).
function Assembler.ApplyCovers(arena)
	local layout = arena:FindFirstChild("MiasmaArenaLayout")
	local bays = arena:FindFirstChild(Assembler.ArtBayFolderName)
	if not (layout and bays) then return "covers: nothing to do" end
	local hidden = 0
	for _, bay in ipairs(bays:GetChildren()) do
		local min, max = bay:GetAttribute("CoverMin"), bay:GetAttribute("CoverMax")
		if bay:IsA("Model") and typeof(min) == "Vector3" and typeof(max) == "Vector3" then
			local frame = bay:GetPivot()
			for _, part in ipairs(layout:GetDescendants()) do
				if part:IsA("BasePart") and not isGameplayLayout(part, layout) and insideBox(part, frame, min, max) then
					if part:GetAttribute("ArtBayHidden") == nil then
						part:SetAttribute("ArtBayOriginalTransparency", part.Transparency)
						part:SetAttribute("ArtBayOriginalShadow", part.CastShadow)
					end
					part:SetAttribute("ArtBayHidden", bay.Name)
					part.Transparency = 1
					part.CastShadow = false
					for _, light in ipairs(part:GetChildren()) do
						if light:IsA("Light") then light.Enabled = false end
					end
					hidden += 1
				end
			end
		end
	end
	return ("covers: %d layout parts hidden (collision kept)"):format(hidden)
end

local function removeCovers(arena, bayName)
	local layout = arena:FindFirstChild("MiasmaArenaLayout")
	if not layout then return 0 end
	local restored = 0
	for _, part in ipairs(layout:GetDescendants()) do
		if part:IsA("BasePart") and part:GetAttribute("ArtBayHidden") == bayName then
			part.Transparency = part:GetAttribute("ArtBayOriginalTransparency") or 0
			part.CastShadow = part:GetAttribute("ArtBayOriginalShadow") ~= false
			for _, light in ipairs(part:GetChildren()) do
				if light:IsA("Light") then light.Enabled = true end
			end
			part:SetAttribute("ArtBayHidden", nil)
			part:SetAttribute("ArtBayOriginalTransparency", nil)
			part:SetAttribute("ArtBayOriginalShadow", nil)
			restored += 1
		end
	end
	return restored
end

-------------------------------------------------------------------------------------------------
-- Station prefab

local function stripPrimitiveVisuals(prefab, report)
	local blockers, removed = 0, 0
	for _, part in ipairs(prefab:GetDescendants()) do
		if part:IsA("BasePart") then
			local path = pathOf(part, prefab)
			local top = string.split(path, "/")[1]
			if KEEP[path] or KEEP_FOLDERS[top] then
				-- unchanged
			elseif HOSTS[path] then
				part.Transparency = 1
				part.CastShadow = false
			elseif part.CanCollide then
				part.Transparency = 1
				part.CastShadow = false
				part:SetAttribute("ArtReplaced", true)
				blockers += 1
			else
				part:Destroy()
				removed += 1
			end
		end
	end
	-- Containers the strip emptied (e.g. Valve/Wheel, Dressing).
	for _, item in ipairs(prefab:GetDescendants()) do
		if (item:IsA("Model") or item:IsA("Folder")) and not item:FindFirstChildWhichIsA("BasePart", true) then
			item:Destroy()
		end
	end
	table.insert(report, ("prefab: %d primitive visuals removed, %d kept as invisible collision"):format(removed, blockers))
end

local function addStationArt(prefab, station, report)
	local art = Instance.new("Folder")
	art.Name = "Art"
	art.Parent = prefab
	local missingTextures = {}
	for _, part in ipairs(station:GetDescendants()) do
		if part:IsA("BasePart") and not string.match(part.Name, "^REF_") then
			local hostPath = MOVING[part.Name]
			if hostPath then
				local host = prefab:FindFirstChild(string.split(hostPath, "/")[1])
				host = host and host:FindFirstChild(string.split(hostPath, "/")[2])
				assert(host, "prefab has no " .. hostPath)
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
			local note = textureNote(part)
			if note then table.insert(missingTextures, note) end
		end
	end
	local gateRoot = prefab.Sluice:FindFirstChild("GateRoot")
	gateRoot:SetAttribute("SlideDistance", Assembler.GateSlideDistance)
	if #missingTextures > 0 then
		table.insert(report, "WARNING untextured station meshes: " .. table.concat(missingTextures, ", "))
	end
end

-------------------------------------------------------------------------------------------------

--[[
	Assemble({ realm, slot | slots, station?, shell? }) -> report string
	`slots` (e.g. { 1, 2, 3, 4 }) dresses several recesses from one import: one shell per slot and
	ONE shared prefab `MiasmaValveStationPrefab` (all slots); a single `slot` makes the per-slot
	prefab `MiasmaValveStationPrefab_<Slot>`. Either import may be omitted to redo only the other half.
]]
function Assembler.Assemble(options)
	local realm = assert(options.realm, "realm required")
	local slots = options.slots or { assert(tonumber(options.slot), "slot (1..4) or slots required") }
	local Layout = require(game:GetService("ReplicatedStorage"):WaitForChild("MiasmaArenaLayout"))
	for _, slot in ipairs(slots) do assert(Layout.Stations[slot], "no station slot " .. tostring(slot)) end
	local Builder = freshRequire(ServerScriptService:WaitForChild("MiasmaValveStationBuilder"))
	local Resolver = freshRequire(ServerScriptService:WaitForChild("MiasmaArenaResolver"))
	assert(Builder.BuildPrimitive and Builder.ArtBayFolderName == Assembler.ArtBayFolderName, "MiasmaValveStationBuilder is out of date (Rojo not synced?)")

	local arena = arenaOf(realm)
	local report = {}
	local history = backupFolder()
	local bays = arena:FindFirstChild(Assembler.ArtBayFolderName) or Instance.new("Folder")
	bays.Name = Assembler.ArtBayFolderName
	bays.Parent = arena
	local resolver = Resolver.new(realm)
	-- Snap exactly like the runtime does (the snap looks through art bays).
	local function frameOf(slot)
		return Builder.SnapToFloor(resolver:ValveStationFrame(slot), { realm })
	end

	if options.station then
		local station = options.station
		alignImport(station, CFrame.identity, report)
		assertNotMirrored(findPart(station, "Bay_SluiceGate"), CFrame.identity, Vector3.new(5, 3.8, -4.55), "Bay_SluiceGate")
		local shared = #slots > 1
		local prefabName = shared and Assembler.PrefabName or (Assembler.PrefabName .. "_" .. Layout.Stations[slots[1]].Name)
		local temp = Instance.new("Folder")
		temp.Name = "MiasmaValveBayAssembler_Temp"
		temp.Parent = ServerStorage
		local prefab = Builder.BuildPrimitive(temp, CFrame.identity, prefabName)
		stripPrimitiveVisuals(prefab, report)
		addStationArt(prefab, station, report)
		prefab:SetAttribute("ArtSource", Assembler.SourceTag)
		prefab:SetAttribute("Slot", shared and "All" or Layout.Stations[slots[1]].Name)
		local old = ServerStorage:FindFirstChild(prefab.Name)
		if old then
			old.Name = old.Name .. "_" .. stamp()
			old.Parent = history
			table.insert(report, "previous prefab moved to ArtBayHistory/" .. old.Name)
		end
		prefab.Parent = ServerStorage
		temp:Destroy()
		station:Destroy()
		table.insert(report, "built ServerStorage." .. prefab.Name)
	end

	if options.shell then
		local shell = options.shell
		alignImport(shell, CFrame.identity, report)
		assertNotMirrored(findPart(shell, "COL_SluiceOpening"), CFrame.identity, Vector3.new(5, 3.7, -4.6), "COL_SluiceOpening")
		local template = Instance.new("Model")
		local visuals = Instance.new("Folder")
		visuals.Name = "Visual"
		visuals.Parent = template
		local collision = Instance.new("Folder")
		collision.Name = "Collision"
		collision.Parent = template
		local missingTextures = {}
		for _, part in ipairs(shell:GetDescendants()) do
			if part:IsA("BasePart") and not string.match(part.Name, "^REF_") then
				if string.match(part.Name, "^COL_") then
					setCollisionProxy(part)
					part.Parent = collision
				else
					setVisual(part)
					part.Parent = visuals
					local note = textureNote(part)
					if note then table.insert(missingTextures, note) end
				end
			end
		end
		template.WorldPivot = CFrame.identity
		template:SetAttribute("ArtSource", Assembler.SourceTag)
		template:SetAttribute("CoverMin", Assembler.CoverMin)
		template:SetAttribute("CoverMax", Assembler.CoverMax)
		shell:Destroy()
		for _, slot in ipairs(slots) do
			local bayName = "ValveBay_" .. Layout.Stations[slot].Name
			local old = bays:FindFirstChild(bayName)
			if old then
				removeCovers(arena, bayName)
				old.Name = old.Name .. "_" .. stamp()
				old.Parent = history
				table.insert(report, "previous bay moved to ArtBayHistory/" .. old.Name)
			end
			local bay = template:Clone()
			bay.Name = bayName
			bay:SetAttribute("Slot", Layout.Stations[slot].Name)
			bay:PivotTo(frameOf(slot))
			bay.Parent = bays
			table.insert(report, ("placed %s (%d visual, %d collision parts)"):format(bay:GetFullName(), #visuals:GetChildren(), #collision:GetChildren()))
		end
		template:Destroy()
		if #missingTextures > 0 then
			table.insert(report, "WARNING untextured shell meshes: " .. table.concat(missingTextures, ", "))
		end
	end

	table.insert(report, Assembler.ApplyCovers(arena))

	-- Refresh the Edit-mode dev station preview so the result is visible without Play.
	local dev = Workspace:FindFirstChild("MiasmaValveDev")
	local devSlot = 4
	if dev and dev:FindFirstChild("ValveStation") and table.find(slots, devSlot) then
		Builder.Build(dev, frameOf(devSlot), "ValveStation", { realm }, Layout.Stations[devSlot].Name)
		table.insert(report, "rebuilt Workspace.MiasmaValveDev.ValveStation preview with the new prefab")
	end
	return table.concat(report, "
")
end

-- Undo for one slot: the bay and the prefab go to ArtBayHistory, the layout is un-hidden.
function Assembler.Remove(options)
	local realm = assert(options.realm, "realm required")
	local Layout = require(game:GetService("ReplicatedStorage"):WaitForChild("MiasmaArenaLayout"))
	local slotInfo = assert(Layout.Stations[tonumber(options.slot)], "no station slot " .. tostring(options.slot))
	local arena = arenaOf(realm)
	local history = backupFolder()
	local report = {}
	local bayName = "ValveBay_" .. slotInfo.Name
	table.insert(report, ("restored %d layout parts"):format(removeCovers(arena, bayName)))
	local bays = arena:FindFirstChild(Assembler.ArtBayFolderName)
	local bay = bays and bays:FindFirstChild(bayName)
	if bay then
		bay.Name = bay.Name .. "_" .. stamp()
		bay.Parent = history
		table.insert(report, "bay moved to ArtBayHistory/" .. bay.Name)
	end
	local prefab = ServerStorage:FindFirstChild(Assembler.PrefabName .. "_" .. slotInfo.Name)
	if prefab then
		prefab.Name = prefab.Name .. "_" .. stamp()
		prefab.Parent = history
		table.insert(report, "prefab moved to ArtBayHistory/" .. prefab.Name)
	end
	return table.concat(report, "\n")
end

return Assembler
