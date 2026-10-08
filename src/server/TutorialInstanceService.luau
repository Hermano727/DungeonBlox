--[[
	TutorialInstanceService (server)

	Each player in the tutorial gets their own copy of the tutorial area, so its one-time spawns
	(the first mobs, the coal ore, the one-fish pond, the elite) are theirs alone.

	The template is a hand-built Model named "TutorialRealmTemplate" anywhere under Workspace
	(built in Studio, parked out of the way like the dungeon realm template). It needs:
	  - a PrimaryPart, and a part named "SpawnPoint" (where the player first wakes up)
	  - Folder "Markers": named, invisible parts the tutorial steps refer to (where an arrow
	    points, where a mob spawns, checkpoints). Any names; see TutorialSteps.
	  - Folder "Zones" (optional): parts carrying zone attributes, turned into TRANSIENT zones
	    for this copy (ZoneService.AddTransientZone; never saved or put on the minimap):
	      ZoneName (string), Alignment ("Lawful"/"Neutral"/"Chaotic"), Radius (studs, else
	      half the part's X size), IsEliteZone (bool), EliteMobId (string), MusicId (string)

	Copies are parked far off the map (TUTORIAL_BASE, one slot each) and destroyed when the
	player leaves, finishes, or the tutorial is reset.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

local ZoneService = require(ServerScriptService:WaitForChild("ZoneService"))

local TEMPLATE_NAME = "TutorialRealmTemplate"
local TUTORIAL_BASE = Vector3.new(0, 50, 100000) -- live copies: +Z, far from the map and the dungeon realms (+X)
local SLOT_SPACING = 1500

local TutorialInstanceService = {}

local instances = {} -- [userId] = instance
local freeSlots, nextSlot = {}, 0
local folder = Workspace:FindFirstChild("TutorialInstances") or Instance.new("Folder")
folder.Name = "TutorialInstances"
folder.Parent = Workspace

local function template()
	local found = Workspace:FindFirstChild(TEMPLATE_NAME, true)
	if found and found:IsA("Model") and not found:IsDescendantOf(folder) then return found end
	return nil
end

local function allocSlot()
	if #freeSlots > 0 then return table.remove(freeSlots) end
	nextSlot += 1
	return nextSlot
end

local function registerZones(inst)
	local zonesFolder = inst.model:FindFirstChild("Zones")
	if not zonesFolder then return end
	for _, part in ipairs(zonesFolder:GetChildren()) do
		if part:IsA("BasePart") and type(part:GetAttribute("ZoneName")) == "string" then
			local name = part:GetAttribute("ZoneName")
			local id = ("tutorial:%d:%s"):format(inst.userId, name)
			local zone = ZoneService.AddTransientZone({
				id = id,
				name = name,
				alignment = part:GetAttribute("Alignment") or "Lawful",
				radius = tonumber(part:GetAttribute("Radius")) or part.Size.X / 2,
				isEliteZone = part:GetAttribute("IsEliteZone") == true,
				eliteMobId = part:GetAttribute("EliteMobId"),
				musicId = part:GetAttribute("MusicId"),
			}, part.Position)
			if zone then table.insert(inst.zoneIds, id) end
		end
	end
end

-- The player's copy, made if it doesn't exist yet. nil if there's no template.
function TutorialInstanceService.Ensure(player)
	local existing = instances[player.UserId]
	if existing and existing.model.Parent then return existing end
	local source = template()
	if not source then
		warn("[TutorialInstanceService] no '" .. TEMPLATE_NAME .. "' Model under Workspace: build the tutorial area in Studio.")
		return nil
	end
	local slot = allocSlot()
	local model = source:Clone()
	model.Name = "Tutorial_" .. player.UserId
	model:PivotTo(CFrame.new(TUTORIAL_BASE + Vector3.new(slot * SLOT_SPACING, 0, 0)))
	model.Parent = folder
	local inst = {
		userId = player.UserId, model = model, slot = slot,
		zoneIds = {}, spawners = {},
	}
	registerZones(inst)
	instances[player.UserId] = inst
	return inst
end

function TutorialInstanceService.Get(player)
	return instances[player.UserId]
end

-- A named marker part in the player's copy (Markers folder, or anywhere by name).
function TutorialInstanceService.Marker(player, name)
	local inst = instances[player.UserId]
	if not inst or type(name) ~= "string" then return nil end
	local markers = inst.model:FindFirstChild("Markers")
	local part = (markers and markers:FindFirstChild(name)) or inst.model:FindFirstChild(name, true)
	return part and part:IsA("BasePart") and part or nil
end

-- A named model (or part) in the player's copy: an NPC, the altar, the ore. Props first, so a
-- camp sub-model that happens to share a name doesn't win.
function TutorialInstanceService.Find(player, name)
	local inst = instances[player.UserId]
	if not inst or type(name) ~= "string" then return nil end
	local props = inst.model:FindFirstChild("TutorialProps")
	return (props and props:FindFirstChild(name, true)) or inst.model:FindFirstChild(name, true)
end

-- Where the player wakes up / respawns at the start.
function TutorialInstanceService.SpawnCFrame(player)
	local inst = instances[player.UserId]
	if not inst then return nil end
	local spawn = inst.model:FindFirstChild("SpawnPoint", true)
	return spawn and spawn:IsA("BasePart") and spawn.CFrame or inst.model:GetPivot()
end

-- Is this position inside the player's copy? (left it = hearthed out / teleported away)
function TutorialInstanceService.Contains(player, position)
	local inst = instances[player.UserId]
	if not inst then return false end
	return (position - inst.model:GetPivot().Position).Magnitude < SLOT_SPACING * 0.45
end

-- One mob at a marker, for this player's copy only (a one-shot spawner, cleaned up with the
-- copy). Returns the mob, or nil.
-- opts (optional): damage = its hit damage, healthFloor = HP it can't be pushed below (the
-- tutorial's "keep swinging until you pant" slime), offset = Vector3 from the marker.
function TutorialInstanceService.SpawnMob(player, markerName, mobId, level, opts)
	local inst = instances[player.UserId]
	local marker = TutorialInstanceService.Marker(player, markerName)
	local system = rawget(_G, "MobSystem")
	if not inst or not marker or not system then return nil end
	local pos = marker.Position + (opts and opts.offset or Vector3.zero)
	local levelRange = level and { minLevel = level, maxLevel = level } or nil
	local spawner = system.CreateSpawner(pos, mobId, 999999, 1, 150, "Tutorial_" .. player.UserId, levelRange)
	table.insert(inst.spawners, spawner)
	spawner:SetNextSpawnMob(mobId, pos, false)
	local mob = spawner:SpawnMob()
	if mob then
		mob.TutorialPaused = inst.paused == true
		if opts and type(opts.damage) == "number" and mob.Stats then mob.Stats.BaseDamage = opts.damage end
		if opts and type(opts.healthFloor) == "number" then mob.HealthFloor = opts.healthFloor end
	end
	return mob
end

-- Freeze (or release) every mob in the player's copy: they stop moving and attacking (MobClass
-- reads TutorialPaused), used while a spotlight pauses the game.
function TutorialInstanceService.PauseMobs(player, paused)
	local inst = instances[player.UserId]
	if not inst then return end
	inst.paused = paused == true
	for _, spawner in ipairs(inst.spawners) do
		for _, mob in ipairs(spawner.SpawnedMobs or {}) do
			mob.TutorialPaused = inst.paused
		end
	end
end

function TutorialInstanceService.Destroy(player)
	local inst = instances[player.UserId]
	if not inst then return end
	instances[player.UserId] = nil
	for _, id in ipairs(inst.zoneIds) do ZoneService.RemoveTransientZone(id) end
	local system = rawget(_G, "MobSystem")
	for _, spawner in ipairs(inst.spawners) do
		if system then pcall(system.UnregisterSpawner, spawner) end
	end
	inst.model:Destroy()
	table.insert(freeSlots, inst.slot)
end

Players.PlayerRemoving:Connect(TutorialInstanceService.Destroy)

return TutorialInstanceService
