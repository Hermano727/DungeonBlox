--[[
	MiasmaValveDevHarness -- DEVELOPMENT ONLY. Studio sessions only unless
	MiasmaValveStationPlacement.Dev.AllowOutsideStudio is set.

	Builds one real valve station (same builder, same MiasmaValveGate, same maze rules,
	same remotes and client UI as the encounter) at Workspace.MiasmaValveDev, standing in
	the master DungeonRealmTemplate arena's Northwest slot, and runs it on a loop:

		corrupt (real MiasmaClog mobs) -> read plate -> operate -> maze -> primed
		-> CompletedDisplay seconds -> corrupt again with a new pattern

	Getting there: a lantern post beside the T1 dungeon portal (prompt "Travel") and one at
	the station (prompts "Return" and "Reset Station").

	Live knobs (attributes on Workspace.MiasmaValveDev, editable in the Server view):
		PartySize  1..8  workload preset (clogs + required runes), restarts the round
		SpawnClogs bool  false = start rounds already unblocked
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Placement = require(ServerScriptService:WaitForChild("MiasmaValveStationPlacement"))
local DEV = Placement.Dev

-- Edit-mode review stations for the other three recesses (layout pass screenshots): never
-- part of a running game.
local reviewPreview = Workspace:FindFirstChild("MiasmaLayoutPreview_TEMP")
if reviewPreview then reviewPreview:Destroy() end
if not DEV.Enabled or (not RunService:IsStudio() and not DEV.AllowOutsideStudio) then
	-- Never leave an Edit-mode preview of the dev station standing in a live server.
	local preview = Workspace:FindFirstChild(DEV.FolderName)
	if preview then preview:Destroy() end
	return
end

local Config = require(ReplicatedStorage:WaitForChild("MiasmaEncounterConfig"))
local DevRoster = require(ReplicatedStorage:WaitForChild("DevRoster"))
local DungeonLevels = require(ReplicatedStorage:WaitForChild("DungeonLevels"))
local Protocol = require(ReplicatedStorage:WaitForChild("MiasmaEncounterProtocol"))
local Runes = require(ReplicatedStorage:WaitForChild("MiasmaRunes"))
local ArenaResolver = require(ServerScriptService:WaitForChild("MiasmaArenaResolver"))
local EncounterService = require(ServerScriptService:WaitForChild("MiasmaEncounterService"))
local MazeService = require(ServerScriptService:WaitForChild("MiasmaMazeService"))
local MobSpawner = require(ServerScriptService:WaitForChild("MobSpawner"))
local StationBuilder = require(ServerScriptService:WaitForChild("MiasmaValveStationBuilder"))
local ValveGate = require(ServerScriptService:WaitForChild("MiasmaValveGate"))

local DEV_ID = "MiasmaValveDev"
local VALVE = Config.Gates.Valve

local function findTemplate()
	for _ = 1, 60 do
		local template = Workspace:FindFirstChild(DEV.TemplateName) or Workspace:FindFirstChild(DEV.TemplateName, true)
		if template then return template end
		task.wait(.5)
	end
	return nil
end

local template = findTemplate()
if not template then
	warn("[MiasmaValveDev] no " .. DEV.TemplateName .. " in Workspace; dev valve station not built")
	return
end

-- Idempotent: a previous build (or an Edit-mode preview) is replaced.
local old = Workspace:FindFirstChild(DEV.FolderName)
if old then old:Destroy() end
local folder = Instance.new("Folder")
folder.Name = DEV.FolderName
folder:SetAttribute("PartySize", DEV.DefaultPartySize)
folder:SetAttribute("SpawnClogs", true)
folder.Parent = Workspace

local override = Workspace:FindFirstChild(DEV.AnchorName, true)
local frame
if override and override:IsA("BasePart") then
	frame = override.CFrame
else
	frame = ArenaResolver.new(template):ValveStationFrame(DEV.StationSlot)
end
local devSlot = Placement.Stations[DEV.StationSlot]
local model = StationBuilder.Build(folder, frame, "ValveStation", { template }, devSlot and devSlot.Name)
frame = model:GetPivot()

local maze = MazeService.new()
local handler = {}
local event = EncounterService.GetEvent()
local clogSpawner = nil
local gate

local function isLivingDev(player)
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0 and DevRoster.IsDev(player)
end

local function newClogSpawner(count)
	if clogSpawner and _G.MobSystem then _G.MobSystem.UnregisterSpawner(clogSpawner) end
	clogSpawner = nil
	if count <= 0 or not _G.MobSystem then return end
	local level = DungeonLevels.BaseLevel(1)
	clogSpawner = MobSpawner.new(frame.Position, "MiasmaClog", math.huge, count, 9999, "T1DungeonMiasmaEncounter", DungeonLevels.SpawnRange(level))
	clogSpawner.Tick = function() end
	_G.MobSystem.RegisterSpawnerObject(clogSpawner)
end

local roundSerial = 0
local function startRound()
	roundSerial += 1
	local size = math.clamp(math.floor(tonumber(folder:GetAttribute("PartySize")) or 1), 1, 8)
	local workload = Config.Gates.Workload[size]
	local clogs = folder:GetAttribute("SpawnClogs") == false and 0 or workload.clogs
	newClogSpawner(clogs)
	gate:Activate(Runes.Pick(workload.symbols), clogs)
end

gate = ValveGate.new({
	index = 1,
	key = DEV_ID,
	displayName = "Test",
	model = model,
	context = {
		encounterId = DEV_ID,
		maze = maze,
		fire = function(eventName, payload, player)
			if not player then return end
			if eventName == Protocol.Events.MazeOpened then EncounterService.BindPlayer(player, handler) end
			event:FireClient(player, DEV_ID, eventName, payload)
			if eventName == Protocol.Events.MazeClosed then EncounterService.UnbindPlayer(player, handler) end
		end,
		isEligible = function(player) return player ~= nil and player.Parent ~= nil and DevRoster.IsDev(player) end,
		canOperate = function() return true end,
		spawnClog = function(position)
			if not clogSpawner then return nil end
			clogSpawner:SetNextSpawnMob("MiasmaClog", position, false)
			local mob = clogSpawner:SpawnMob()
			if mob then mob.IsSpawnStunned = true; mob.IsInvulnerable = false end
			return mob
		end,
		onPrimed = function()
			local serial = roundSerial
			task.delay(VALVE.CompletedDisplay, function()
				if serial == roundSerial and gate.Primed then startRound() end
			end)
		end,
	},
})

function handler:HandleRequest(player, request, payload)
	if request == Protocol.Requests.CancelValve then
		gate:Cancel(player, "Cancelled")
	elseif request == Protocol.Requests.MazeSample and type(payload) == "table" then
		gate:HandleSample(player, payload)
	end
end
EncounterService.RegisterExternal(DEV_ID, handler)

-- Travel posts ---------------------------------------------------------------------------

local function floorBelow(position, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(position + Vector3.new(0, 20, 0), Vector3.new(0, -200, 0), params)
	return hit and hit.Position or position
end

local function makePost(name, position, facing)
	local post = Instance.new("Model")
	post.Name = name
	local base = Instance.new("Part")
	base.Name = "Post"
	base.Anchored = true
	base.Size = Vector3.new(.6, 5, .6)
	base.CFrame = CFrame.lookAt(position + Vector3.new(0, 2.5, 0), position + Vector3.new(0, 2.5, 0) + facing)
	base.Material = Enum.Material.CorrodedMetal
	base.Color = Color3.fromRGB(58, 54, 50)
	base.Parent = post
	local lantern = Instance.new("Part")
	lantern.Name = "Lantern"
	lantern.Anchored = true
	lantern.CanCollide = false
	lantern.Shape = Enum.PartType.Ball
	lantern.Size = Vector3.new(.9, .9, .9)
	lantern.Position = position + Vector3.new(0, 5.4, 0)
	lantern.Material = Enum.Material.Neon
	lantern.Color = Color3.fromRGB(110, 235, 160)
	lantern.Parent = post
	local light = Instance.new("PointLight")
	light.Color = lantern.Color
	light.Range = 10
	light.Parent = lantern
	post.PrimaryPart = base
	post.Parent = folder
	return post, base
end

local function addPrompt(part, action, object, order, callback)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.HoldDuration = .2
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.UIOffset = Vector2.new(0, order * 72)
	prompt.Parent = part
	prompt.Triggered:Connect(function(player)
		if DevRoster.IsDev(player) then callback(player) end
	end)
end

local function teleport(player, cframe)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	pcall(function() player:RequestStreamAroundAsync(cframe.Position) end)
	root.AssemblyLinearVelocity = Vector3.zero
	root.CFrame = cframe
end

local characters = {}
for _, p in ipairs(Players:GetPlayers()) do if p.Character then table.insert(characters, p.Character) end end
local entryPosition = floorBelow(DEV.EntryBeacon, characters)
local returnPosition = frame:PointToWorldSpace(DEV.ReturnOffset)
local _, entryPart = makePost("EntryPost", entryPosition, Vector3.new(0, 0, -1))
local _, returnPart = makePost("ReturnPost", returnPosition, -frame.LookVector)

local arrival = CFrame.lookAt(frame:PointToWorldSpace(Vector3.new(0, 3, 9)), frame:PointToWorldSpace(Vector3.new(0, 3, 0)))
addPrompt(entryPart, "Travel", "Valve Test Station (dev)", 0, function(player) teleport(player, arrival) end)
addPrompt(returnPart, "Return", "Back to the T1 portal", 0, function(player)
	gate:Cancel(player, "Left")
	teleport(player, CFrame.new(entryPosition + Vector3.new(0, 3, 5)))
end)
addPrompt(returnPart, "Reset Station", "Valve Test Station (dev)", 1, function() startRound() end)

folder:GetAttributeChangedSignal("PartySize"):Connect(startRound)
folder:GetAttributeChangedSignal("SpawnClogs"):Connect(startRound)

Players.PlayerRemoving:Connect(function(player)
	gate:Cancel(player, "Left")
	EncounterService.UnbindPlayer(player, handler)
end)

RunService.Heartbeat:Connect(function()
	local living = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if isLivingDev(player) then table.insert(living, player) end
	end
	gate:Update(living)
end)

task.spawn(function()
	for _ = 1, 100 do
		if _G.MobSystem then break end
		task.wait(.1)
	end
	startRound()
end)

print(("[MiasmaValveDev] valve test station ready at %s (travel post near the T1 portal)"):format(tostring(frame.Position)))
