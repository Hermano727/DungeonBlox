local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("MiasmaEncounterConfig"))
local Math = require(ReplicatedStorage:WaitForChild("MiasmaEncounterMath"))
local Protocol = require(ReplicatedStorage:WaitForChild("MiasmaEncounterProtocol"))
local DungeonRunConfig = require(ReplicatedStorage:WaitForChild("DungeonRunConfig"))
local DungeonLevels = require(game:GetService("ReplicatedStorage"):WaitForChild("DungeonLevels"))
local CleanupBin = require(ServerScriptService:WaitForChild("MiasmaCleanupBin"))
local ArenaResolver = require(ServerScriptService:WaitForChild("MiasmaArenaResolver"))
local ArenaChannels = require(ServerScriptService:WaitForChild("MiasmaArenaChannels"))
local CleanseAltar = require(ServerScriptService:WaitForChild("MiasmaCleanseAltar"))
local TelegraphArt = require(ReplicatedStorage:WaitForChild("MiasmaTelegraphArt"))
local PoisonService = require(ServerScriptService:WaitForChild("MiasmaPoisonService"))
local MazeService = require(ServerScriptService:WaitForChild("MiasmaMazeService"))
local ValveGate = require(ServerScriptService:WaitForChild("MiasmaValveGate"))
local StationBuilder = require(ServerScriptService:WaitForChild("MiasmaValveStationBuilder"))
local StationPlacement = require(ServerScriptService:WaitForChild("MiasmaValveStationPlacement"))
local Runes = require(ReplicatedStorage:WaitForChild("MiasmaRunes"))
local AbilityDirector = require(ServerScriptService:WaitForChild("MiasmaAbilityDirector"))
local DamageService = require(ServerScriptService:WaitForChild("DamageService"))
local MobSpawner = require(ServerScriptService:WaitForChild("MobSpawner"))
local DungeonMobSpawnService = require(ServerScriptService:WaitForChild("DungeonMobSpawnService"))
local ZoneService = require(ServerScriptService:WaitForChild("ZoneService"))
local EncounterSoundtracks = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Sounds"):WaitForChild("EncounterSoundtracks"))
local TitleCards = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images"):WaitForChild("TitleCards"))

local Controller = {}
Controller.__index = Controller

local function createPart(parent, name, position, size, color, transparency)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = transparency or .35
	part.Size = size
	part.Position = position
	part.Parent = parent
	return part
end

-- Projectiles read as glowing globs with a short smear instead of bare neon balls.
local function decorateProjectile(part, color)
	part.Material = Enum.Material.Neon
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 10
	light.Brightness = 2
	light.Parent = part
	local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0, part.Size.Y * .3, 0); a0.Parent = part
	local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, -part.Size.Y * .3, 0); a1.Parent = part
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Color = ColorSequence.new(color)
	trail.LightEmission = 1
	trail.Lifetime = .22
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .15), NumberSequenceKeypoint.new(1, 1) })
	trail.Parent = part
	local drips = Instance.new("ParticleEmitter")
	drips.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	drips.Color = ColorSequence.new(color)
	drips.LightEmission = 1
	drips.Rate = 40
	drips.Lifetime = NumberRange.new(.3, .6)
	drips.Speed = NumberRange.new(0, .5)
	drips.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, part.Size.X * .35), NumberSequenceKeypoint.new(1, 0) })
	drips.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .2), NumberSequenceKeypoint.new(1, 1) })
	drips.Acceleration = Vector3.new(0, -12, 0)
	drips.Parent = part
end

local BOSS_BAR_STATES = {
	BossDrop = true, Act2Puzzle = true, PureWaterStun = true, CycleResetWarning = true, Act3Enrage = true,
}

local function flatDistance(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function humanoidAndRoot(player)
	local character = player and player.Character
	return character and character:FindFirstChildOfClass("Humanoid"), character and character:FindFirstChild("HumanoidRootPart")
end

function Controller.new(options)
	local self = setmetatable({}, Controller)
	self.Id = options.instanceId
	self.Realm = options.realm
	self.MemberUserIds = table.clone(options.memberUserIds or {})
	self.MemberSet = {}
	for _, userId in ipairs(self.MemberUserIds) do self.MemberSet[userId] = true end
	self.StartingPartySize = Math.ClampPartySize(#self.MemberUserIds, Config.MaxPartySize)
	self.SpawnerHandle = options.spawnerHandle
	-- Level every encounter add spawns at: the run's resolved level
	-- (RS/DungeonLevels), so adds match the rest of the dungeon. Falls back to
	-- the T1 base only if a caller forgets to pass it.
	self.RunLevel = tonumber(options.runLevel) or DungeonLevels.BaseLevel(1)
	self.Event = options.event
	self.OnFinished = options.onFinished
	self.Resolver = ArenaResolver.new(self.Realm)
	self.Channels = ArenaChannels.new(self.Resolver)
	self.Bin = CleanupBin.new()
	self.Runtime = Instance.new("Folder")
	self.Runtime.Name = "MiasmaEncounterRuntime"
	self.Runtime.Parent = self.Realm
	self.Bin:Add(self.Runtime)
	self.StateModel = Instance.new("Folder")
	self.StateModel.Name = "MiasmaEncounterState"
	self.StateModel.Parent = self.Realm
	self.Bin:Add(self.StateModel)
	self.StateModel:SetAttribute(Protocol.Attributes.EncounterId, self.Id)
	self.StateModel:SetAttribute(Protocol.Attributes.StartingPartySize, self.StartingPartySize)
	self.State = Protocol.States.Dormant
	self.StateSerial = 0
	self.Finished = false
	self.Enraged = false
	self.Boss = nil
	self.Gates = {} -- cleansing altars ("altar1", "altar2")
	self.ValveGates = {} -- [1..4] MiasmaValveGate
	self.Maze = MazeService.new()
	self.PreviousGateKey = nil
	self.CycleNumber = 0
	self.Hazards = {}
	self.SackThresholdsFired = {}
	self.PendingSackThresholds = {}
	self.NextThresholdEventAt = 0
	self.PendingEnrage = false
	self.AbilitySerial = 0
	self.SlimeProjectileAt = {}
	self:_resetStaggerForCycle()
	self.Poison = PoisonService.new(self.MemberUserIds, self.Event, self.Id)
	self.Bin:Add(self.Poison)
	self.Director = AbilityDirector.new(self)
	self.Bin:Add(self.Director)
	self:_createInteractionAnchors()
	return self
end

function Controller:_forEachMember(callback)
	for userId in pairs(self.MemberSet) do
		local player = Players:GetPlayerByUserId(userId)
		if player then callback(player) end
	end
end

-- The fight's own soundtrack for every member (ZoneService's encounter layer, which outranks
-- zone and named-elite music). musicId "" hands everyone back to their zone track.
function Controller:_setPhaseMusic(musicId)
	self._phaseMusicId = musicId ~= "" and musicId or nil
	self:_forEachMember(function(player) ZoneService.SetEncounterMusic(player, musicId) end)
end

-- Alive, in the world, and not spectating (DungeonInstanceService parks a dead member's next
-- body far above the realm with the DungeonSpectating attribute: never a target, never
-- poisoned, and not counted, so a party wipe still triggers once the rest are down).
function Controller:_livingPlayers()
	local living = {}
	self:_forEachMember(function(player)
		local humanoid, root = humanoidAndRoot(player)
		self._arenaCentre = self._arenaCentre or self.Resolver:Position("ANCHOR_Miasma")
		if humanoid and root and humanoid.Health > 0 and root:IsDescendantOf(workspace)
			and player:GetAttribute("DungeonSpectating") == nil
			and (not self._arenaCentre or flatDistance(root.Position, self._arenaCentre) <= Config.Arena.MemberRadius) then
			table.insert(living, player)
		end
	end)
	return living
end

function Controller:_fire(eventName, payload, target)
	if not self.Event then return end
	payload = payload or {}
	if target then
		self.Event:FireClient(target, self.Id, eventName, payload)
	else
		self:_forEachMember(function(player) self.Event:FireClient(player, self.Id, eventName, payload) end)
	end
end

function Controller:_setState(state, duration)
	if self.Finished and state ~= Protocol.States.Destroyed then return false end
	if state ~= Protocol.States.PureWaterStun then self:_endStunShrink() end
	self.State = state
	self.StateSerial += 1
	self.StateModel:SetAttribute(Protocol.Attributes.State, state)
	self.StateModel:SetAttribute(Protocol.Attributes.StateEndsAt, duration and (workspace:GetServerTimeNow() + duration) or 0)
	self.StateModel:SetAttribute(Protocol.Attributes.Enraged, self.Enraged)
	self:_fire(Protocol.Events.Snapshot, self:GetSnapshot())
	return true
end

function Controller:GetSnapshot()
	local gates = {}
	-- Deliberately no target runes here: the pattern exists only on each station's tablet.
	for index = 1, 4 do
		local gate = self.ValveGates[index]
		gates[index] = { active = gate.Active, clogsRemaining = gate:ClogsRemaining(), requiredCount = #gate.RequiredSymbols, primed = gate.Primed }
	end
	return {
		state = self.State,
		stateEndsAt = self.StateModel:GetAttribute(Protocol.Attributes.StateEndsAt),
		startingPartySize = self.StartingPartySize,
		enraged = self.Enraged,
		cycle = self.CycleNumber,
		gates = gates,
	}
end

function Controller:IsFinished() return self.Finished end
function Controller:IsEnraged() return self.Enraged end
function Controller:CanDirectorAct()
	return (self.State == Protocol.States.Act2Puzzle or self.State == Protocol.States.Act3Enrage)
		and self.Boss and self.Boss.IsAlive and self.Boss:IsAlive() and not self._abilityLocked
end
function Controller:CanUseAbility(_) return #self:_livingPlayers() > 0 end

function Controller:_startAbility()
	self.AbilitySerial += 1
	self._abilityLocked = true
	return self.AbilitySerial
end

function Controller:_cancelAbility()
	self.AbilitySerial += 1
	self._abilityLocked = false
	if self.Boss and self.Boss.SetEncounterVisible then self.Boss:SetEncounterVisible(true) end
end

function Controller:AbortAbility()
	self:_cancelAbility()
	if self.Boss and (self.State == Protocol.States.Act2Puzzle or self.State == Protocol.States.Act3Enrage) then
		self.Boss:SetEncounterControlled(false)
		self.Boss:SetEncounterLocked(false, false)
	end
end

function Controller:_guardedDelay(seconds, callback, serial)
	serial = serial or self.StateSerial
	task.delay(seconds, function()
		if not self.Finished and self.StateSerial == serial then callback() end
	end)
end

function Controller:_createInteractionAnchors()
	self.Altars = {}
	local altarContext = {
		fire = function(eventName, payload, player) self:_fire(eventName, payload, player) end,
		isEligible = function(player) return player ~= nil and self.MemberSet[player.UserId] == true end,
		poison = self.Poison,
		startingPartySize = self.StartingPartySize,
	}
	for i = 1, 2 do
		local altar = CleanseAltar.new({ index = i, resolver = self.Resolver, parent = self.Runtime, context = altarContext })
		self.Altars[i] = altar
		self.Bin:Add(function() altar:Destroy() end)
	end
	self:_createValveStations()
	local sealPos = self.Resolver:Position("ANCHOR_EntranceSeal")
	self.EntranceSeal = createPart(self.Runtime, "EntranceSealCollision", sealPos, Vector3.new(26, 24, 3), Color3.fromRGB(40, 130, 80), .55)
	self.EntranceThreshold = createPart(self.Runtime, "EntranceThreshold", self.Resolver:Position("ANCHOR_EntranceThreshold"), Vector3.new(30, 12, 8), Color3.new(), 1)
	self.EntranceThreshold.CanTouch = true
	local cistern = self.Resolver:Position("ANCHOR_CisternLiquidPivot")
	self.CisternIndicator = createPart(self.Runtime, "CisternPoisonLevel", cistern, Vector3.new(2, 36, 36), Color3.fromRGB(115, 35, 150), .25)
	self.CisternIndicator.Shape = Enum.PartType.Cylinder
	self.CisternIndicator.CFrame = CFrame.new(cistern) * CFrame.Angles(0, 0, math.rad(90))
	local center = self.Resolver:Position("ANCHOR_Miasma")
	self.PressureIndicator = createPart(self.Runtime, "PoisonPressureRing", center + Vector3.new(0, .18, 0), Vector3.new(.15, 8, 8), Color3.fromRGB(105, 20, 135), .35)
	self.PressureIndicator.Shape = Enum.PartType.Cylinder
	self.PressureIndicator.CFrame = CFrame.new(self.PressureIndicator.Position) * CFrame.Angles(0, 0, math.rad(90))
	self.PressureIndicator.Transparency = 1
end

function Controller:_enableAltars(enabled)
	for _, altar in ipairs(self.Altars) do altar:SetEnabled(enabled) end
end

function Controller:_awaitBoss()
	local forced = false
	for _ = 1, 100 do
		if self.Finished then return nil end
		local boss = DungeonMobSpawnService.GetBoss(self.SpawnerHandle)
		if boss then
			self.Boss = boss
			boss.OnEncounterHit = function(player, raw) self:_onBossHit(player, raw) end
			-- Valve operators can tank Miasma: its hits still land, but never shove them off the wheel.
			boss.ShouldSkipKnockback = function(player) return ValveGate.FindByOperator(self.ValveGates, player) ~= nil end
			boss.OnEncounterMeleeHit = function(player)
				if player:GetAttribute("MiasmaInvulnerable") == true then return end
				local stacks = Config.Melee.PoisonStacks or 0
				if stacks > 0 then self.Poison:Add(player, stacks) end
			end
			local scaling = DungeonRunConfig.Get(self.StartingPartySize)
			local levelMultiplier = (boss.Stats.ScaleWithLevel == false or boss.Stats.HPScaleWithLevel == false) and 1
				or (1 + boss.Level * .1)
			boss.MaxHealth = math.floor(boss.Stats.BaseHP * levelMultiplier * scaling.HPMult)
			boss.CurrentHealth = boss.MaxHealth
			-- Can't be pushed below the enrage threshold (the .30 SackThreshold) until the enrage
			-- cutscene has played: a burst during the valve stun (which defers the enrage) used to
			-- kill it outright and skip phase 3. Cleared in BeginEnrage once the cutscene ends.
			boss.HealthFloor = math.floor(boss.MaxHealth * .30)
			local humanoid = boss.Model and boss.Model:FindFirstChildOfClass("Humanoid")
			if humanoid and boss.SyncHumanoidHealth then boss:SyncHumanoidHealth(humanoid) end
			if boss.UpdateHPBar then boss:UpdateHPBar() end
			boss:SetEncounterProtectedPositions(self.Resolver:ProtectedCentres(), Config.Arena.BossProtectedRadius)
			boss:SetEncounterControlled(true)
			boss:SetEncounterDamageMultiplier(Config.Boss.OutsideStunDamageMultiplier)
			boss:SetEncounterLocked(true, true)
			return boss
		end
		if not forced then
			local spawner = DungeonMobSpawnService.GetBossSpawner(self.SpawnerHandle)
			if spawner then forced = true; spawner:SpawnMob() end
		end
		task.wait(.1)
	end
	warn("[MiasmaEncounter] boss did not spawn for " .. self.Id)
	return nil
end

function Controller:Start()
	self:_setState(Protocol.States.Dormant)
	self.EntranceSeal.CanCollide = false
	self.EntranceSeal.Transparency = 1
	task.spawn(function()
		self:_awaitBoss()
		if not self.Finished then
			self.Bin:Add(self.EntranceThreshold.Touched:Connect(function(hit)
				local player = Players:GetPlayerFromCharacter(hit.Parent)
				if player and self.MemberSet[player.UserId] then self:BeginEntranceGrace() end
			end))
			task.delay(2, function() if not self.Finished and self.State == Protocol.States.Dormant then self:BeginEntranceGrace() end end)
		end
	end)
	self.Bin:Add(RunService.Heartbeat:Connect(function(dt) self:_heartbeat(dt) end))
end

function Controller:BeginEntranceGrace()
	if self.State ~= Protocol.States.Dormant then return end
	self:_setState(Protocol.States.EntranceGrace, Config.EntranceGrace)
	self:_setPhaseMusic(EncounterSoundtracks.MiasmaPhase1) -- phase 1's track, until the drop
	self:_fire(Protocol.Events.Presentation, { kind = "EntranceGrace", duration = Config.EntranceGrace })
	local serial = self.StateSerial
	self:_guardedDelay(Config.EntranceGrace, function() self:_sealAndStartAct1() end, serial)
end

function Controller:_sealAndStartAct1()
	local living = self:_livingPlayers()
	if #living == 0 then self:Fail("PartyWipe") return end
	local gather = self.Resolver:Position("ANCHOR_PartyGather")
	for i, player in ipairs(living) do
		local _, root = humanoidAndRoot(player)
		if root then root.CFrame = CFrame.new(gather + Vector3.new((i - 1) * 4, 3, 0)) end
	end
	self.EntranceSeal.CanCollide = true
	self.EntranceSeal.Transparency = .35
	self:_enableAltars(true)
	self:BeginAct1()
end

function Controller:_newEncounterSpawner(mobId, maxSpawns)
	local spawner = MobSpawner.new(self.Resolver:Position("ANCHOR_Miasma"), mobId, math.huge, maxSpawns, 9999, "T1DungeonMiasmaEncounter", DungeonLevels.SpawnRange(self.RunLevel))
	spawner.Tick = function() end
	_G.MobSystem.RegisterSpawnerObject(spawner)
	self.Bin:Add(function() if _G.MobSystem then _G.MobSystem.UnregisterSpawner(spawner) end end)
	return spawner
end

function Controller:_spawnMob(spawner, mobId, position, frozen)
	spawner:SetNextSpawnMob(mobId, position, false)
	local mob = spawner:SpawnMob()
	if mob and frozen then
		mob.IsSpawnStunned = true
		mob.IsInvulnerable = false
	end
	return mob
end

-- A shove that actually moves a player: Roblox's Humanoid controller zeroes a one-off velocity
-- change on the next physics step (see MobClass:ApplyPlayerHitstun), so the push is held for a
-- moment by a BodyVelocity instead. `direction` is flattened; `up` is the hop.
local function shovePlayer(root, direction, speed, seconds, up)
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < .01 then flat = Vector3.new(0, 0, 1) end
	local bv = Instance.new("BodyVelocity")
	bv.Velocity = flat.Unit * speed + Vector3.new(0, up or 0, 0)
	bv.MaxForce = Vector3.new(40000, (up and up > 0) and 6000 or 0, 40000)
	bv.P = 2500
	bv.Parent = root
	game:GetService("Debris"):AddItem(bv, seconds or .15)
end

-- Miasma's body is SOLID (the skinned mesh itself can't collide sensibly -- its collision
-- would be one giant box -- so the skin is CanCollide = false):
--   1. an invisible vertical cylinder the size of its core follows it, and blocks players like
--      a wall. Its own collision group ignores mobs, so Miasma and the slimes pass through it.
--   2. backup: anyone who still ends up inside (spawned there, pushed in) is shoved back out.
-- Only while it stands in the arena: not on the ceiling (Act 1), not mid-drop, not submerged
-- (its skin fully transparent), and the shove never touches an immune (cutscene) player.
local BODY_SOLID_STATES = {
	[Protocol.States.Act2Puzzle] = true, [Protocol.States.PureWaterStun] = true,
	[Protocol.States.CycleResetWarning] = true, [Protocol.States.Act3Enrage] = true,
}
local BODY_COLLIDER_GROUP = "MiasmaBody"
local MOB_COLLISION_GROUP = "DungeonMobs" -- MobClass's group for every mob

local function ensureBodyColliderGroup()
	pcall(function()
		if not PhysicsService:IsCollisionGroupRegistered(BODY_COLLIDER_GROUP) then
			PhysicsService:RegisterCollisionGroup(BODY_COLLIDER_GROUP)
		end
		if not PhysicsService:IsCollisionGroupRegistered(MOB_COLLISION_GROUP) then
			PhysicsService:RegisterCollisionGroup(MOB_COLLISION_GROUP)
		end
		PhysicsService:CollisionGroupSetCollidable(BODY_COLLIDER_GROUP, MOB_COLLISION_GROUP, false)
	end)
end

function Controller:_bossSkin(model)
	if self._skinModel ~= model then
		self._skinModel, self._skin = model, nil
		local volume = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("MeshPart") and d.Size.X * d.Size.Y * d.Size.Z > volume then
				self._skin, volume = d, d.Size.X * d.Size.Y * d.Size.Z
			end
		end
	end
	return self._skin
end

-- The skin's base-ring edge bones (see Config.Melee.BodyEdgeFromBones). nil = fall back.
local EDGE_BONES = { "Base_Center_Front", "Base_Center_Back", "Base_Left_Core", "Base_Right_Core" }

function Controller:_edgeBones(model)
	if self._edgeBonesModel ~= model then
		self._edgeBonesModel, self._edgeBoneList = model, nil
		local list = {}
		for _, name in ipairs(EDGE_BONES) do
			local bone = model:FindFirstChild(name, true)
			if not (bone and bone:IsA("Bone")) then list = nil break end
			table.insert(list, bone)
		end
		self._edgeBoneList = list
	end
	return self._edgeBoneList
end

-- Centre (flat) and radius of the body's current footprint, from the animated edge bones.
function Controller:_bodyFootprint(model, fallbackCentre, fallbackRadius)
	local bones = self:_edgeBones(model)
	if not bones then return fallbackCentre, fallbackRadius end
	local sum = Vector3.zero
	local points = {}
	for _, bone in ipairs(bones) do
		local p = bone.TransformedWorldCFrame.Position
		p = Vector3.new(p.X, 0, p.Z)
		table.insert(points, p)
		sum += p
	end
	local centre = sum / #points
	local spread = 0
	for _, p in ipairs(points) do spread += (p - centre).Magnitude end
	local cfg = Config.Melee
	local radius = spread / #points * (cfg.BodyEdgeFromBones or .93) + (cfg.BodyEdgePadding or 0)
	-- A bone rig gone odd (mid-transition, a broken clip) must never make a wall across the
	-- arena or collapse it to nothing: keep within half..full of the model's box.
	radius = math.clamp(radius, fallbackRadius / (cfg.BodyRadiusFraction * 2), fallbackRadius / cfg.BodyRadiusFraction)
	return Vector3.new(centre.X, fallbackCentre.Y, centre.Z), radius
end

function Controller:_updateBodyContact()
	local boss = self.Boss
	local model = boss and boss.Model
	local root = model and model.PrimaryPart
	local skin = model and self:_bossSkin(model)
	local solid = root ~= nil and BODY_SOLID_STATES[self.State] == true and not (skin and skin.Transparency >= .99)

	local collider = self._bodyCollider
	if not solid then
		if collider then collider.CanCollide = false end
		return
	end
	if not self._bodyHalfExtent then
		local size = model:GetExtentsSize()
		self._bodyHalfExtent = (math.max(size.X, size.Z) + math.min(size.X, size.Z)) * .25 / boss:_encounterScale()
		self._bodyHeight = size.Y / boss:_encounterScale()
	end
	local cfg = Config.Melee
	local scale = boss:_encounterScale()
	local height = self._bodyHeight * scale
	local centre, radius = self:_bodyFootprint(model, root.Position, self._bodyHalfExtent * cfg.BodyRadiusFraction * scale)

	if not collider or not collider.Parent then
		ensureBodyColliderGroup()
		collider = Instance.new("Part")
		collider.Name = "MiasmaBodyCollider"
		collider.Shape = Enum.PartType.Cylinder
		collider.Anchored = true
		collider.CanQuery = false -- weapon rays / arrows pass straight through to the boss mesh
		collider.CanTouch = false
		collider.CastShadow = false
		collider.Transparency = 1
		collider.CollisionGroup = BODY_COLLIDER_GROUP
		collider.Parent = self.Runtime
		self._bodyCollider = collider
	end
	collider.CanCollide = true
	local size = Vector3.new(height, radius * 2, radius * 2) -- a Cylinder's length runs along X
	if (collider.Size - size).Magnitude > .05 then collider.Size = size end
	collider.CFrame = CFrame.new(centre.X, root.Position.Y, centre.Z) * CFrame.Angles(0, 0, math.pi / 2)

	local now = os.clock()
	self._contactAt = self._contactAt or {}
	for _, player in ipairs(self:_livingPlayers()) do
		local _, playerRoot = humanoidAndRoot(player)
		if playerRoot and player:GetAttribute("MiasmaInvulnerable") ~= true then
			local offset = playerRoot.Position - centre
			local flat = Vector3.new(offset.X, 0, offset.Z)
			local above = playerRoot.Position.Y - (root.Position.Y - height * .5)
			if flat.Magnitude < radius + 1 and above > -3 and above < height and now - (self._contactAt[player] or 0) >= cfg.ContactCooldown then
				self._contactAt[player] = now
				-- Deeper in = harder out, so walking into it repeatedly never works.
				local depth = math.clamp(1 - flat.Magnitude / radius, 0, 1)
				shovePlayer(playerRoot, flat, cfg.ContactShoveSpeed * (1 + depth), cfg.ContactShoveSeconds, 6)
				if (cfg.ContactPoisonStacks or 0) > 0 then self.Poison:Add(player, cfg.ContactPoisonStacks) end
			end
		end
	end
end

function Controller:_damageNear(position, radius, rawDamage, poisonStacks, knockback)
	for _, player in ipairs(self:_livingPlayers()) do
		local _, root = humanoidAndRoot(player)
		-- Immune (cutscene / presentation freeze): no damage, and no poison or knockback either.
		if root and flatDistance(root.Position, position) <= radius and player:GetAttribute("MiasmaInvulnerable") ~= true then
			DamageService.ApplyToPlayer(player, rawDamage, { Kind = "MiasmaEncounter", EncounterId = self.Id }, nil, true)
			if poisonStacks and poisonStacks > 0 then self.Poison:Add(player, poisonStacks) end
			if knockback and knockback > 0 and not ValveGate.FindByOperator(self.ValveGates, player) then
				-- (Was a one-off AssemblyLinearVelocity add, which the Humanoid cancels next step.)
				shovePlayer(root, root.Position - position, knockback * 2.2, .2, 10)
			end
		end
	end
end

-- Warnings are drawn client-side (MiasmaEncounterVFX / MiasmaTelegraphArt); the server only
-- decides where and when. `_color` is kept for call-site compatibility.
function Controller:_telegraph(kind, position, radius, duration, _color)
	self:_fire(Protocol.Events.Telegraph, { kind = kind, position = position, radius = radius, duration = duration })
end

function Controller:_spawnSlimeLanding(position)
	self:_telegraph("SlimeLanding", position, 5, Config.SlimeLandingWarning, Color3.fromRGB(95, 220, 60))
	task.delay(Config.SlimeLandingWarning, function()
		if self.Finished or (self.State ~= Protocol.States.Act1Survival and self.State ~= Protocol.States.Act1Cleanup) then return end
		local mob = self:_spawnMob(self.SlimeSpawner, "MiasmaSlime", position + Vector3.new(0, 16, 0), false)
		if mob and mob.Model then
			mob.Model:SetAttribute("MiasmaEncounterId", self.Id)
		end
		self:_damageNear(position, 5, Config.Damage.SlimeLanding, 1, 16)
	end)
end

function Controller:_spawnAct1Wave(count)
	local living = self:_livingPlayers()
	for i = 1, count do
		local target = living[((i - 1) % math.max(1, #living)) + 1]
		local _, root = humanoidAndRoot(target)
		local angle = math.random() * math.pi * 2
		local base = root and root.Position or self.Resolver:Position("ANCHOR_Miasma")
		self:_spawnSlimeLanding(base + Vector3.new(math.cos(angle) * math.random(6, 18), 0, math.sin(angle) * math.random(6, 18)))
	end
end

-- Phase 1 slime lob (Config.SlimeLob): the landing spot is locked to where the target stands
-- when it spits, marked with a green ring for the whole flight; the glob arcs up and drops
-- onto it. Anyone living inside Radius at landing takes the splash + poison.
function Controller:_launchSlimeProjectile(mob, target)
	local cfg = Config.SlimeLob
	local origin = mob and mob.GetPosition and mob:GetPosition()
	local _, targetRoot = humanoidAndRoot(target)
	if not origin or not targetRoot then return end
	origin += Vector3.new(0, 2, 0)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { self.Runtime }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(ignore, p.Character) end
	end
	if mob.Model then table.insert(ignore, mob.Model) end
	params.FilterDescendantsInstances = ignore
	local floor = workspace:Raycast(targetRoot.Position, Vector3.new(0, -30, 0), params)
	local landing = floor and floor.Position or (targetRoot.Position - Vector3.new(0, 3, 0))

	local marker = createPart(self.Runtime, "SlimeLobMarker", landing + Vector3.new(0, .1, 0),
		Vector3.new(.2, cfg.Radius * 2, cfg.Radius * 2), Color3.fromRGB(120, 255, 90), .55)
	marker.Shape = Enum.PartType.Cylinder
	marker.CFrame = CFrame.new(landing + Vector3.new(0, .1, 0)) * CFrame.Angles(0, 0, math.pi / 2)

	local projectile = createPart(self.Runtime, "SlimeProjectile", origin, Vector3.new(2.2, 2.2, 2.2), Color3.fromRGB(75, 230, 65), .1)
	projectile.Shape = Enum.PartType.Ball
	decorateProjectile(projectile, Color3.fromRGB(120, 255, 90))
	task.spawn(function()
		local started = os.clock()
		while projectile.Parent and not self.Finished do
			RunService.Heartbeat:Wait()
			local u = math.min(1, (os.clock() - started) / cfg.FlightTime)
			local lift = 4 * cfg.ArcHeight * u * (1 - u)
			projectile.Position = origin:Lerp(landing, u) + Vector3.new(0, lift, 0)
			marker.Transparency = .55 - .3 * u -- firms up as it comes down
			if u >= 1 then break end
		end
		if not self.Finished then
			for _, player in ipairs(self:_livingPlayers()) do
				local _, root = humanoidAndRoot(player)
				if root and flatDistance(root.Position, landing) <= cfg.Radius and math.abs(root.Position.Y - landing.Y) <= 8 then
					DamageService.ApplyToPlayer(player, cfg.Damage, { Kind = "MiasmaSlimeProjectile" }, nil, true)
					if (cfg.PoisonStacks or 0) > 0 then self.Poison:Add(player, cfg.PoisonStacks) end
				end
			end
		end
		if projectile.Parent then projectile:Destroy() end
		if marker.Parent then marker:Destroy() end
	end)
end

function Controller:_updateSlimeProjectiles(now)
	if not self.SlimeSpawner then return end
	local cfg = Config.SlimeLob
	local living = self:_livingPlayers()
	for _, mob in ipairs(self.SlimeSpawner.SpawnedMobs or {}) do
		if mob and mob:IsAlive() and now >= (self.SlimeProjectileAt[mob] or 0) then
			local position = mob:GetPosition()
			local best, bestDistance
			for _, player in ipairs(living) do
				local _, root = humanoidAndRoot(player)
				local distance = root and position and flatDistance(position,root.Position)
				if distance and distance >= cfg.MinRange and distance <= cfg.MaxRange and (not bestDistance or distance < bestDistance) then best, bestDistance = player, distance end
			end
			if best then self.SlimeProjectileAt[mob]=now+cfg.Cooldown; self:_launchSlimeProjectile(mob,best) end
		end
	end
end

function Controller:_poisonVolley()
	for _, player in ipairs(self:_livingPlayers()) do
		local _, root = humanoidAndRoot(player)
		if root then
			local position = root.Position
			self:_telegraph("PoisonDrop", position, 4, Config.PoisonDropWarning, Color3.fromRGB(145, 35, 180))
			task.delay(Config.PoisonDropWarning, function()
				if not self.Finished and self.State == Protocol.States.Act1Survival then
					self:_damageNear(position, 4, Config.Damage.PoisonDrop, 2, 0)
				end
			end)
		end
	end
end

function Controller:BeginAct1()
	self:_setState(Protocol.States.Act1Survival, Config.Act1Duration)
	self.SlimeSpawner = self:_newEncounterSpawner("MiasmaSlime", Math.SlimeLivingCap(self.StartingPartySize))
	self:_spawnAct1Wave(self.StartingPartySize)
	local serial = self.StateSerial
	task.spawn(function()
		local elapsed, nextWave, nextVolley = 0, Config.Act1InitialWaveDelay, 7
		while not self.Finished and self.StateSerial == serial and elapsed < Config.Act1Duration do
			task.wait(.25)
			elapsed += .25
			if elapsed >= nextWave then
				local room = Math.SlimeLivingCap(self.StartingPartySize) - self.SlimeSpawner:CountAliveMobs()
				if room > 0 then self:_spawnAct1Wave(math.min(room, Math.SlimeWaveSize(self.StartingPartySize))) end
				nextWave = elapsed + Math.SlimeWaveInterval(elapsed, Config.Act1Duration, Config.Act1InitialWaveDelay, Config.Act1FinalWaveDelay)
			end
			if elapsed >= nextVolley then self:_poisonVolley(); nextVolley = elapsed + 8 end
		end
		if not self.Finished and self.StateSerial == serial then self:BeginAct1Cleanup() end
	end)
end

function Controller:BeginAct1Cleanup()
	self:_setState(Protocol.States.Act1Cleanup)
	task.spawn(function()
		while not self.Finished and self.State == Protocol.States.Act1Cleanup do
			if self.SlimeSpawner:CountAliveMobs() <= 0 then self:BeginBossDrop(); return end
			task.wait(.25)
		end
	end)
end

-- Runs `callback` when `track` reaches its "Impact" marker, or `latest` seconds
-- after it starts if the marker never comes (a clip published without one).
-- No track at all (animation id not set yet) fires it straight away.
function Controller:_onAnimationImpact(track, latest, callback, serial)
	local fired = false
	local connection
	local function fire()
		if fired then return end
		fired = true
		if connection then connection:Disconnect() end
		if not self.Finished and self.StateSerial == serial then callback() end
	end
	if track then connection = track:GetMarkerReachedSignal("Impact"):Connect(fire) end
	task.delay(track and latest or 0, fire)
end

-- How far the landing slam VFX reaches: the boss's standing half-width, scaled
-- up for the squish and the debris carrying past it.
function Controller:_bossLandingVisualRadius()
	local model = self.Boss and self.Boss.Model
	if not model then return nil end
	local size = model:GetExtentsSize()
	return math.max(size.X, size.Z) * 0.5 * Config.BossLandingVisualScale
end

-- LandingSlam clip time -> real seconds since the slam started. The clip is slowed to
-- 1 / SlamRoarStretch through the roar (DungeonBossMobClass:StartLandingSlam), so anything at or
-- after the roar lands later than its clip time.
local function slamRealTime(seq, t)
	local stretch = tonumber(seq.SlamRoarStretch) or 1
	local a, b = seq.SlamRoarStart, seq.SlamRoarEnd
	if t <= a then return t end
	if t <= b then return a + (t - a) * stretch end
	return t + (b - a) * (stretch - 1)
end

-- Phase 1 -> 2 as ONE timeline (numbers: MiasmaEncounterConfig.BossDropSequence). Times are
-- seconds from the start of this function:
--   0                     BossDrop state + floor warning circle (Config.BossDropWarning long)
--   bridgeStart           boss moved to the floor (hidden); LatchDetach (latch model) and
--                         CeilingToBody (boss) start together; the forms cross-fade at
--                         SwapStart..SwapEnd of the bridge
--   slamStart             LandingSlam starts straight on from the bridge's last pose. slamStart
--                         is SlamImpactTime before the circle ends, so the landing IS the circle's end
--   slamStart + Impact    damage + BossLanding VFX + player presentation lock
--   slamStart + Growth    BossGrowth VFX (the slam clip's own expansion/roar -- no second animation)
--   slamStart + Settle    slam motion has settled: phase 2 (BeginGateCycle) begins
-- Every delayed step is guarded by the state serial, so a Fail/Destroy/state change cancels the
-- ones still pending; the boss-side pieces are cancelled by Boss:CancelDropTransition().
function Controller:BeginBossDrop()
	local seq = Config.BossDropSequence
	local cut = seq.Cutscene
	local cutscene = cut ~= nil and cut.Enabled == true
	-- Everything below is offset by the cutscene's lead-in (extra time on the ceiling close-up).
	local leadIn = cutscene and cut.LeadIn or 0
	local slamStart = leadIn + math.max(0, Config.BossDropWarning - seq.SlamImpactTime)
	local bridgeStart = math.max(leadIn, slamStart - (seq.BridgeSeconds - seq.SlamLeadSeconds))
	-- The title card holds after the roar only when there is art for it; the fight waits for it.
	local mobId = self.Boss and self.Boss.MobID
	local cardSeconds = (cutscene and TitleCards.Has(mobId)) and cut.TitleCardSeconds or 0
	local settleTime = slamRealTime(seq, seq.SlamSettleTime)
	local roarStart, roarEnd = slamRealTime(seq, seq.SlamRoarStart), slamRealTime(seq, seq.SlamRoarEnd)
	local settleAt = slamStart + settleTime
	local phaseTwoAt = settleAt + cardSeconds
	self:_setState(Protocol.States.BossDrop, phaseTwoAt)
	-- Phase 1's track stops for the drop cutscene (the collapse and roar carry it); phase 2's
	-- starts with the title card, below.
	self:_setPhaseMusic("")
	local center = self.Resolver:Position("ANCHOR_Miasma_FloorLanding")
	local serial = self.StateSerial

	if cutscene then
		-- Frozen + immune from the first frame to the handback: nobody can see the warning
		-- circle through the cutscene camera, so the slam must not be able to hit anyone.
		self:_lockPlayersForPresentation(phaseTwoAt, true)
		local latch = self.Boss and self.Boss._latchModel
		self:_fire(Protocol.Events.Presentation, {
			kind = "BossDropCutscene",
			startsAt = workspace:GetServerTimeNow(),
			bridgeStart = bridgeStart,
			impact = slamStart + seq.SlamImpactTime,
			roarStart = slamStart + roarStart,
			roarEnd = slamStart + roarEnd,
			cardStart = settleAt,
			endsAt = phaseTwoAt,
			landing = center,
			ceiling = latch and latch:GetPivot().Position or (center + Vector3.new(0, 52, 0)),
			facing = self:_bossFacing(),
			boss = self.Boss and self.Boss.Model,
			latch = latch,
			mobId = mobId,
		})
	end

	self:_guardedDelay(leadIn, function()
		self:_telegraph("BossDrop", center, Config.BossDropRadius, Config.BossDropWarning, Color3.fromRGB(175, 45, 195))
	end, serial)

	self:_guardedDelay(bridgeStart, function()
		if not self.Boss then return end
		-- Deferred release: on the floor but hidden, latch model still up; the bridge owns the reveal.
		self.Boss:ReleaseFromCeiling(center, true)
		self.Boss:SetEncounterControlled(true); self.Boss:SetEncounterLocked(true, true)
		self.Boss:StartCeilingBridge() -- false = degrade: StartLandingSlam reveals the boss directly
	end, serial)

	self:_guardedDelay(slamStart, function()
		local slam = self.Boss and self.Boss:StartLandingSlam()
		self:_onAnimationImpact(slam, seq.SlamImpactTime, function()
			self:_damageNear(center, Config.BossDropRadius, Config.Damage.BossDrop, 1, 35)
			self:_lockPlayersForPresentation(settleTime - seq.SlamImpactTime + cardSeconds)
			self:_fire(Protocol.Events.Presentation, {
				kind = "BossLanding", position = center,
				radius = self:_bossLandingVisualRadius(),
				boss = self.Boss and self.Boss.Model, -- so the client's floor check skips the body
			})
		end, serial)
		local growthAt = slamRealTime(seq, seq.SlamGrowthTime)
		local growthSeconds = slamRealTime(seq, seq.SlamGrowthTime + seq.SlamGrowthSeconds) - growthAt
		self:_guardedDelay(growthAt, function()
			self:_fire(Protocol.Events.Presentation, { kind = "BossGrowth", duration = growthSeconds, position = center })
		end, serial)
		-- The roar's sound leads the open mouth a little (its wind-up), so it has its own cue.
		-- `duration` = how long it must cover; the client repeats the clip until it does.
		local soundLead = math.min(seq.SlamRoarSoundLead or 0, roarStart)
		self:_guardedDelay(roarStart - soundLead, function()
			self:_fire(Protocol.Events.Presentation, { kind = "BossRoarSound", duration = soundLead + (roarEnd - roarStart) })
		end, serial)
		-- Frames 65-100 of the slam clip (slowed, see slamRealTime): the mouth is open. Breath
		-- VFX, arena shake, ceiling dust.
		self:_guardedDelay(roarStart, function()
			self:_fire(Protocol.Events.Presentation, {
				kind = "BossRoar", duration = roarEnd - roarStart,
				position = center, boss = self.Boss and self.Boss.Model,
			})
		end, serial)
		-- Phase 2's track starts WITH the title card (or right after the roar when there is none)
		-- and carries on for the rest of the fight.
		self:_guardedDelay(settleTime, function()
			self:_setPhaseMusic(EncounterSoundtracks.MiasmaPhase2)
		end, serial)
		self:_guardedDelay(settleTime + cardSeconds, function()
			self:BeginGateCycle()
		end, serial)
	end, serial)
end

-- Which way Miasma's face points (flat unit vector), from its rest-pose jaw bones: front row
-- minus core row. Used to put the cutscene camera in front of it. Falls back to the pivot.
function Controller:_bossFacing()
	local model = self.Boss and self.Boss.Model
	if not model then return Vector3.new(0, 0, -1) end
	local front, core
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Bone") then
			if d.Name == "LowerJaw_Center_Front" then front = d elseif d.Name == "LowerJaw_Center_Core" then core = d end
		end
	end
	if front and core then
		local v = front.WorldPosition - core.WorldPosition
		v = Vector3.new(v.X, 0, v.Z)
		if v.Magnitude > .01 then return v.Unit end
	end
	local look = model:GetPivot().LookVector
	look = Vector3.new(look.X, 0, look.Z)
	return look.Magnitude > .01 and look.Unit or Vector3.new(0, 0, -1)
end

-- Freezes every living member (no walking/jumping) and makes them immune to the encounter for
-- `duration`, then fires the dazed star rings over their heads -- unless `quiet` (the cutscene's
-- own freeze, which has no stars). A member already frozen by an earlier call is NOT re-frozen
-- (re-capturing their speed would capture the 0 and restore it as 0), but still gets stars.
function Controller:_lockPlayersForPresentation(duration, quiet)
	local frozen = {}
	self:_forEachMember(function(player)
		local humanoid = humanoidAndRoot(player)
		if humanoid and humanoid.Health > 0 then
			table.insert(frozen, player)
			if player:GetAttribute("MiasmaInvulnerable") == true then return end
			local walk, jump = humanoid.WalkSpeed, humanoid.JumpPower
			humanoid.WalkSpeed = 0; humanoid.JumpPower = 0
			player:SetAttribute("MiasmaInvulnerable", true)
			task.delay(duration, function()
				if humanoid.Parent and humanoid.Health > 0 then humanoid.WalkSpeed = walk; humanoid.JumpPower = jump end
				if player.Parent then player:SetAttribute("MiasmaInvulnerable", nil) end
			end)
		end
	end)
	-- Dazed star rings over every frozen member (MiasmaStunFX player slot).
	if #frozen > 0 and not quiet then
		self:_fire(Protocol.Events.Presentation, { kind = "PlayersStunned", duration = duration, players = frozen })
	end
end

function Controller:_chooseGates()
	local count = Math.ActiveGateCount(self.StartingPartySize)
	local indices = { 1, 2, 3, 4 }
	for i = #indices, 2, -1 do local j = math.random(i); indices[i], indices[j] = indices[j], indices[i] end
	local selected = {}
	for i = 1, count do selected[i] = indices[i] end
	local key = Math.EncodeGateSet(selected)
	if count < 4 and key == self.PreviousGateKey then
		selected[count] = indices[count + 1] or ((selected[count] % 4) + 1)
		key = Math.EncodeGateSet(selected)
	end
	self.PreviousGateKey = key
	return selected
end

-- Builds the four player-scale valve stations inside this realm's runtime folder.
-- Placement: MiasmaValveStationPlacement / ANCHOR_ValveStation_0N; geometry: the builder.
function Controller:_createValveStations()
	local folder = Instance.new("Folder")
	folder.Name = "ValveStations"
	folder.Parent = self.Runtime
	local context = {
		encounterId = self.Id,
		maze = self.Maze,
		poison = self.Poison,
		fire = function(eventName, payload, player) self:_fire(eventName, payload, player) end,
		isEligible = function(player) return player ~= nil and self.MemberSet[player.UserId] == true end,
		canOperate = function() return not self.Finished and self.State == Protocol.States.Act2Puzzle end,
		spawnClog = function(position)
			if not self.ClogSpawner then return nil end
			return self:_spawnMob(self.ClogSpawner, "MiasmaClog", position, true)
		end,
		onPrimed = function(gate) self:_onGatePrimed(gate) end,
	}
	for index = 1, 4 do
		local slot = StationPlacement.Stations[index]
		local model = StationBuilder.Build(folder, self.Resolver:ValveStationFrame(index), "ValveStation" .. index, { self.Realm }, slot and slot.Name)
		local gate = ValveGate.new({
			index = index,
			displayName = slot and slot.DisplayName or ("Gate " .. index),
			model = model,
			context = context,
		})
		self.ValveGates[index] = gate
		self.Bin:Add(function() gate:Destroy() end)
	end
end

function Controller:_clearGateCycle(reason)
	for index = 1, 4 do
		local gate = self.ValveGates[index]
		if gate then gate:Deactivate(reason or "CycleReset") end
	end
	self.Maze:Reset()
	self.Channels:Reset()
	if self.ClogSpawner and _G.MobSystem then _G.MobSystem.UnregisterSpawner(self.ClogSpawner); self.ClogSpawner = nil end
end

function Controller:BeginGateCycle()
	if self.PendingEnrage then self:BeginEnrage(); return end
	self:_clearGateCycle()
	self.CycleNumber += 1
	self.StateModel:SetAttribute(Protocol.Attributes.Cycle, self.CycleNumber)
	self:_setState(Protocol.States.Act2Puzzle, Config.Gates.CycleDuration)
	if self.Boss then
		self.Boss:SetEncounterControlled(false)
		self.Boss:SetEncounterLocked(false, false)
		self.Boss:SetEncounterDamageMultiplier(Config.Boss.OutsideStunDamageMultiplier)
	end
	self.Director:Start()
	-- Released into the fight: the boss chases for good from here (MobClass.NeverDeaggro),
	-- even if everyone starts out at the stations beyond its 90-stud aggro range.
	if self.Boss then self.Boss._engaged = true end
	self:_resetStaggerForCycle()
	local workload = Config.Gates.Workload[self.StartingPartySize]
	self.ClogSpawner = self:_newEncounterSpawner("MiasmaClog", workload.clogs * 4)
	local selected = self:_chooseGates()
	local names, positions = {}, {}
	for _, index in ipairs(selected) do
		self.ValveGates[index]:Activate(Runes.Pick(workload.symbols), workload.clogs)
		local slot = StationPlacement.Stations[index]
		table.insert(names, slot and slot.DisplayName or ("Gate " .. index))
		-- Where the client's guide arrows hang: a plain list lined up with `selected` (a sparse
		-- gate-number-keyed table would get mangled crossing the remote).
		table.insert(positions, self.ValveGates[index]:GetPosition())
	end
	-- Which valves woke up this cycle (they move between cycles): named on screen, and each
	-- live station raises a light pillar (MiasmaValveStation beacon).
	self:_fire(Protocol.Events.Presentation, { kind = "GatesAwaken", gates = selected, names = names, positions = positions })
	self.StateModel:SetAttribute(Protocol.Attributes.ActiveGates, Math.EncodeGateSet(selected))
	self.StateModel:SetAttribute(Protocol.Attributes.CycleEndsAt, workspace:GetServerTimeNow() + Config.Gates.CycleDuration)
	self:_fire(Protocol.Events.Snapshot, self:GetSnapshot())
	local serial = self.StateSerial
	self:_guardedDelay(Config.Gates.CycleDuration - Config.Gates.FinalWarningDuration, function()
		self:_fire(Protocol.Events.Presentation, { kind = "CycleFinalWarning", duration = Config.Gates.FinalWarningDuration })
	end, serial)
	self:_guardedDelay(Config.Gates.CycleDuration, function() self:BeginPurge() end, serial)
end

function Controller:CancelValve(player, reason)
	local gate = ValveGate.FindByOperator(self.ValveGates, player)
	if gate then gate:Cancel(player, reason or "Cancelled") end
end

function Controller:_onGatePrimed(gate)
	if self.State ~= Protocol.States.Act2Puzzle then return end
	self:_fire(Protocol.Events.Presentation, { kind = "GatePrimed", gate = gate.Index, position = gate:GetPosition() })
	self.Channels:Prime(gate.Index)
	for index = 1, 4 do
		local other = self.ValveGates[index]
		if other.Active and not other.Primed then return end
	end
	-- This was the LAST required valve: only it triggers the stun (and its cutscene).
	self:BeginPureWaterStun(gate)
end

-- The puzzle stun, opened by a cutscene (Config.Gates.StunCutscene): the final gate opens, the
-- holy water floods down its channel and hits Miasma, which is snapped to the arena centre for
-- it. Timeline from now: cutscene 0 .. Seconds (players frozen + immune, boss invulnerable),
-- the stun proper from ImpactAt (shrink, stunned clip, "PureWater" -> StunFX ring + outline),
-- and StunDuration of real damage time AFTER the cutscene ends.
function Controller:BeginPureWaterStun(finalGate)
	self:_endStagger("Water")
	self.Director:Stop()
	self:_cancelAbility()
	local cut = Config.Gates.StunCutscene
	local cutscene = cut ~= nil and cut.Enabled == true and finalGate ~= nil
	local lead = cutscene and cut.Seconds or 0          -- time before the damage window opens
	local impactAt = cutscene and cut.ImpactAt or 0
	local stunTotal = lead + Config.Gates.StunDuration
	self:_setState(Protocol.States.PureWaterStun, stunTotal)
	self:_clearPoisonHazards()
	local flowing = {}
	for index = 1, 4 do if self.ValveGates[index].Active then table.insert(flowing, index) end end
	self.Channels:Flow(flowing)
	local centre = self.Resolver:Position("ANCHOR_Miasma")
	local bossModel = self.Boss and self.Boss.Model
	if self.Boss then
		self.Boss:SetEncounterControlled(true)
		self.Boss:SetEncounterLocked(true, cutscene) -- invulnerable while the party can't act
		if cutscene and bossModel then
			-- Centre stage for the flood (the camera is on the gate when this happens).
			local pivot = bossModel:GetPivot()
			bossModel:PivotTo(CFrame.new(centre.X, pivot.Position.Y, centre.Z) * pivot.Rotation)
		end
	end
	local serial = self.StateSerial
	if cutscene then
		self:_lockPlayersForPresentation(lead, true)
		local channels = {}
		for _, index in ipairs(flowing) do table.insert(channels, self.Resolver:ChannelModel(index) or false) end -- lined up with `flowing`
		self:_fire(Protocol.Events.Presentation, {
			kind = "PureWaterCutscene", startsAt = workspace:GetServerTimeNow(), duration = lead, impactAt = impactAt,
			gate = finalGate.Index, gatePosition = finalGate:GetPosition(), centre = centre,
			boss = bossModel, flowing = flowing, channels = channels, stunSeconds = stunTotal - impactAt,
		})
	end

	-- The water lands: the stun proper.
	self:_guardedDelay(impactAt, function()
		if self.Boss then
			self.Boss:SetEncounterLocked(true, false)
			self.Boss:SetEncounterDamageMultiplier(Config.Boss.StunnedDamageMultiplier)
			self.Boss:PlayEncounterAnimation("Stunned", true)
			-- The puzzle stun (unlike the solo stagger) also shrinks Miasma: it reads as exposed.
			self.Boss:SetEncounterShrink(Config.Gates.StunShrinkFactor, Config.Gates.StunShrinkSeconds)
			self._stunShrunk = true
		end
		self:_fire(Protocol.Events.Presentation, {
			kind = "PureWater", duration = stunTotal - impactAt,
			position = centre, boss = self.Boss and self.Boss.Model,
		})
	end, serial)
	self:_guardedDelay(stunTotal, function()
		if self.Boss then self.Boss:StopEncounterAnimation("Stunned") end
		if self.PendingEnrage then self:BeginEnrage() else self:BeginCycleResetWarning() end
	end, serial)
end

-- Ends the puzzle stun's shrink (regrow = false when the boss is dead and its defeat
-- presentation owns the model) and tells clients the stun visuals are over. No-op when the boss
-- isn't shrunk. Called from _setState, so every path out of PureWaterStun passes through here.
function Controller:_endStunShrink(regrow)
	if not self._stunShrunk then return end
	self._stunShrunk = false
	if regrow ~= false and self.Boss and self.Boss:IsAlive() then
		self.Boss:SetEncounterShrink(1, Config.Gates.StunShrinkSeconds)
	end
	self:_fire(Protocol.Events.Presentation, { kind = "StunEnded" })
end

function Controller:BeginCycleResetWarning()
	self:_setState(Protocol.States.CycleResetWarning, Config.Gates.NextCycleWarning)
	self.Channels:Reset()
	self:_fire(Protocol.Events.Presentation, { kind = "Recorrupt", duration = Config.Gates.NextCycleWarning })
	local serial = self.StateSerial
	self:_guardedDelay(Config.Gates.NextCycleWarning, function() self:BeginGateCycle() end, serial)
end

function Controller:BeginPurge()
	if self.State ~= Protocol.States.Act2Puzzle then return end
	self:_endStagger("Purge")
	self.Director:Stop()
	self:_cancelAbility()
	self:_setState(Protocol.States.CycleResetWarning, Config.Gates.PurgeWarningDuration + Config.Gates.RecoveryDuration)
	for index = 1, 4 do self.ValveGates[index]:ReleaseOperator("Purge") end
	local safe = self.Resolver:SafeAreaPositions()
	for _, position in ipairs(safe) do self:_telegraph("PurgeSafe", position, Config.Arena.SafeAreaRadius, Config.Gates.PurgeWarningDuration, Color3.fromRGB(90,220,220)) end
	self:_fire(Protocol.Events.Presentation, { kind = "PurgeWarning", duration = Config.Gates.PurgeWarningDuration, safeAreas = safe })
	local serial = self.StateSerial
	self:_guardedDelay(Config.Gates.PurgeWarningDuration, function()
		for _, player in ipairs(self:_livingPlayers()) do
			local _, root = humanoidAndRoot(player); local protected = false
			for _, position in ipairs(safe) do if root and flatDistance(root.Position, position) <= Config.Arena.SafeAreaRadius then protected = true break end end
			if not protected then DamageService.ApplyToPlayer(player, Config.Damage.Purge, { Kind = "MiasmaPurge" }, nil, true); self.Poison:Add(player, 2) end
		end
		self:_clearGateCycle()
		self:_guardedDelay(Config.Gates.RecoveryDuration, function() self:BeginGateCycle() end)
	end, serial)
end

function Controller:_abilityTiming(value)
	if self.Enraged then return math.max(Config.Boss.MinimumTelegraph, value * Config.Boss.EnrageSpeedMultiplier) end
	return value
end

-- Who Miasma's single-target moves go for: the top of its threat list (the same one its melee
-- follows, MobClass threat) among `candidates` (default: every living player); with no threat
-- yet, whoever is nearest to it.
function Controller:_pickTarget(candidates)
	candidates = candidates or self:_livingPlayers()
	if #candidates == 0 then return nil end
	local boss = self.Boss
	if boss and boss.TopThreat then
		local allowed = {}
		for _, player in ipairs(candidates) do allowed[player] = true end
		local top = boss:TopThreat(allowed)
		if top then return top end
	end
	local origin = boss and boss.GetPosition and boss:GetPosition()
	if not origin then return candidates[1] end
	local best, bestDistance
	for _, player in ipairs(candidates) do
		local _, root = humanoidAndRoot(player)
		local distance = root and flatDistance(root.Position, origin)
		if distance and (not bestDistance or distance < bestDistance) then best, bestDistance = player, distance end
	end
	return best or candidates[1]
end

-- Poison lob (Config.Abilities.FastProjectile). Mark -> lock -> lob -> splash:
--   1. A red reticle tracks the chosen player for TrackTime (client: MiasmaLobFX; the marked
--      player also gets a red screen-edge pulse). Miasma turns to face them.
--   2. At lock, the spot they stand on is fixed and the glob launches from Miasma's mouth;
--      clients animate the arc (smooth, no replicated part), landing after FlightTime.
--   3. On landing the server hits everyone within Radius of the locked spot.
-- Moving or dashing off the locked spot during the flight dodges it.
function Controller:CastFastProjectile()
	local cfg = Config.Abilities.FastProjectile
	if not self.Boss then return end
	-- Everyone gets one. A valve operator gets a poison blob in their maze instead of a glob.
	local targets = {}
	for _, player in ipairs(self:_livingPlayers()) do
		if ValveGate.FindByOperator(self.ValveGates, player) then
			local blob = self.Maze:SpawnBlob(player)
			if blob then self:_fire(Protocol.Events.MazeBlob, blob, player) end
		else
			table.insert(targets, player)
		end
	end
	if #targets == 0 then return end
	local focus = self:_pickTarget(targets) or targets[1]

	local abilitySerial = self:_startAbility(); self.Boss:SetEncounterLocked(true, false)
	local function cancelled() return self.Finished or self.AbilitySerial ~= abilitySerial or not self.Boss end
	local track = self:_abilityTiming(cfg.TrackTime)
	local flight = self:_abilityTiming(cfg.FlightTime)
	local lead = math.min(track, self:_abilityTiming(cfg.CastLead))

	local casts = {}
	for _, target in ipairs(targets) do
		self._lobCastId = (self._lobCastId or 0) + 1
		local _, root = humanoidAndRoot(target)
		local cast = { castId = self._lobCastId, target = target, lastPosition = root and root.Position }
		table.insert(casts, cast)
		self:_fire(Protocol.Events.Telegraph, { kind = "LobTarget", castId = cast.castId, target = target, duration = track, radius = cfg.Radius })
	end

	-- Track every target, facing the top-threat one; start the spit clip so its release lines up with the lock.
	local started, clipStarted = os.clock(), false
	while os.clock() - started < track do
		if cancelled() then return end
		for _, cast in ipairs(casts) do
			local _, r = humanoidAndRoot(cast.target)
			if r then cast.lastPosition = r.Position end
		end
		local _, focusRoot = humanoidAndRoot(focus)
		if focusRoot and self.Boss.FaceToward then self.Boss:FaceToward(focusRoot.Position) end
		if not clipStarted and os.clock() - started >= track - lead then
			clipStarted = true
			self.Boss:PlayEncounterAnimation("ProjectileCast", false)
		end
		task.wait(.05)
	end
	if cancelled() then return end
	if not clipStarted then self.Boss:PlayEncounterAnimation("ProjectileCast", false) end

	for _, cast in ipairs(casts) do
		local _, lockRoot = humanoidAndRoot(cast.target)
		cast.lockPos = (lockRoot and lockRoot.Position) or cast.lastPosition
		if cast.lockPos then
			self:_fire(Protocol.Events.Telegraph, {
				kind = "LobLaunch", castId = cast.castId, position = cast.lockPos, radius = cfg.Radius,
				flight = flight, boss = self.Boss.Model,
			})
		end
	end
	task.wait(flight)
	if cancelled() then return end
	local hit = {} -- a player standing in two splashes still takes one
	for _, cast in ipairs(casts) do
		local lockPos = cast.lockPos
		if lockPos then
			for _, player in ipairs(self:_livingPlayers()) do
				local _, pr = humanoidAndRoot(player)
				if not hit[player] and pr and flatDistance(pr.Position, lockPos) <= cfg.Radius
					and math.abs(pr.Position.Y - lockPos.Y) <= cfg.Radius + 4
					and player:GetAttribute("MiasmaInvulnerable") ~= true then
					hit[player] = true
					DamageService.ApplyToPlayer(player, cfg.RawDamage, { Kind = "MiasmaProjectile" }, nil, true)
					self.Poison:Add(player, cfg.PoisonStacks or 1)
				end
			end
			self:_fire(Protocol.Events.Telegraph, { kind = "LobImpact", castId = cast.castId, position = lockPos, radius = cfg.Radius })
		end
	end
	if self.AbilitySerial == abilitySerial then self.Boss:SetEncounterLocked(false, false); self._abilityLocked = false end
end

function Controller:_randomHazardPosition()
	local center = self.Resolver:Position("ANCHOR_Miasma")
	for _ = 1, 30 do
		local angle, radius = math.random()*math.pi*2, math.sqrt(math.random())*Config.Arena.HazardRadius
		local point = center + Vector3.new(math.cos(angle)*radius, 0, math.sin(angle)*radius)
		if not self.Resolver:IsProtected(point) then return point end
	end
	return center + Vector3.new(50,0,0)
end

function Controller:_spawnExposureHazard(kind, position, radius, duration, rawDamage)
	-- Static ground art on a replicated part (bubbles for puddles, smoke for clouds), dropped
	-- onto the floor under `position`; destroying the part removes it for everyone.
	local part = TelegraphArt.Build(self.Runtime, position, radius, kind, { static = true, ignore = { self.Runtime } }).part
	local hazard = { part=part, poison=true }; table.insert(self.Hazards,hazard)
	task.spawn(function()
		local started=os.clock(); local exposure={}
		while part.Parent and not self.Finished and os.clock()-started<duration do
			for _,player in ipairs(self:_livingPlayers()) do local _,root=humanoidAndRoot(player); if root and flatDistance(root.Position,position)<=radius then DamageService.ApplyToPlayer(player,rawDamage,{Kind=kind},nil,true); exposure[player]=(exposure[player] or 0)+1; if exposure[player]%math.max(1,math.floor(Config.Poison.ExposureStackInterval/.5))==0 then self.Poison:Add(player,1) end else exposure[player]=0 end end
			task.wait(.5)
		end
		if part.Parent then part:Destroy() end
	end)
	return hazard
end

function Controller:CastPoisonScatter()
	if not self.Boss then return end
	local abilitySerial=self:_startAbility(); self.Boss:SetEncounterLocked(true,false); self.Boss:PlayEncounterAnimation("PoisonScatter",false)
	local cast=self:_abilityTiming(Config.Abilities.PoisonScatter.CastTime); self:_fire(Protocol.Events.Presentation,{kind="PoisonScatterCast",duration=cast}); task.wait(cast)
	if self.Finished or self.AbilitySerial ~= abilitySerial then return end
	local positions={}
	for _=1,Math.PuddleCount(self.StartingPartySize) do
		local point=self:_randomHazardPosition(); local valid=true
		for _,other in ipairs(positions) do if flatDistance(point,other)<Config.Abilities.PoisonScatter.MinimumSpacing then valid=false break end end
		if valid then table.insert(positions,point); self:_spawnExposureHazard("PoisonPuddle",point,Config.Abilities.PoisonScatter.Radius,Config.Abilities.PoisonScatter.Lifetime,Config.Abilities.PoisonScatter.RawDamage) end
	end
	if self.AbilitySerial == abilitySerial then self.Boss:SetEncounterLocked(false,false); self._abilityLocked=false end
end

function Controller:CastSubmerge()
	if not self.Boss then return end
	local abilitySerial=self:_startAbility(); self.Boss:SetEncounterControlled(true); self.Boss:SetEncounterLocked(true,true); self.Boss:PlayEncounterAnimation("Submerge",false)
	local pools={}; local track=self:_abilityTiming(Config.Abilities.Submerge.TrackTime); local start=os.clock()
	while self.AbilitySerial == abilitySerial and os.clock()-start<track do
		-- Hide the body only once the submerge clip has finished sinking it (clip is 1.2s).
		if os.clock()-start >= math.min(Config.Abilities.Submerge.SubmergeClipSeconds, track) then self.Boss:SetEncounterVisible(false) end
		for _,player in ipairs(self:_livingPlayers()) do local _,root=humanoidAndRoot(player); if root then pools[player]=root.Position end end
		task.wait(.1)
	end
	if self.Finished or self.AbilitySerial ~= abilitySerial then return end
	local warning=self:_abilityTiming(Config.Abilities.Submerge.EruptionWarning)
	for _,position in pairs(pools) do self:_telegraph("SubmergePool",position,Config.Abilities.Submerge.Radius,warning,Color3.fromRGB(90,20,120)) end
	task.wait(warning)
	if self.Finished or self.AbilitySerial ~= abilitySerial then return end
	for _,position in pairs(pools) do self:_damageNear(position,Config.Abilities.Submerge.Radius,Config.Abilities.Submerge.RawDamage,2,18) end
	self.Boss:SetEncounterVisible(true); self.Boss:PlayEncounterAnimation("Emerge",false)
	-- Hold the boss (locked, invulnerable) through the whole 1.2s emerge clip so the AI can't
	-- start chasing/attacking and cut it off; only then hand control back.
	task.wait(Config.Abilities.Submerge.EmergeClipSeconds)
	if self.Finished or self.AbilitySerial ~= abilitySerial or not self.Boss then return end
	self.Boss:SetEncounterControlled(false); self.Boss:SetEncounterLocked(false,false); self._abilityLocked=false
end

function Controller:_spawnSacks(threshold)
	local count=Math.SackCount(self.StartingPartySize); local positions=self.Resolver:SackPositions()
	self.SackSpawner=self.SackSpawner or self:_newEncounterSpawner("MiasmaSack",15)
	self:_fire(Protocol.Events.Presentation,{kind="SackThreshold",threshold=threshold,count=count})
	for i=1,count do
		local mob=self:_spawnMob(self.SackSpawner,"MiasmaSack",positions[i],true)
		if mob then
			task.delay(Config.Sacks.FuseDuration,function()
				if self.Finished then return end
				if mob.IsAlive and mob:IsAlive() then
					local position=mob:GetPosition(); mob.CurrentHealth=0; if mob.Model then mob.Model:Destroy(); mob.Model=nil end
					if position then self:_spawnExposureHazard("PoisonCloud",position,Config.Sacks.CloudRadius,Config.Sacks.CloudDuration,Config.Sacks.RawDamage) end
				end
			end)
		end
	end
end

function Controller:_processSackThresholdQueue()
	if #self.PendingSackThresholds == 0 or self._abilityLocked then return end
	if self.State ~= Protocol.States.Act2Puzzle and self.State ~= Protocol.States.Act3Enrage then return end
	local now = workspace:GetServerTimeNow()
	if now < self.NextThresholdEventAt then return end
	local threshold = table.remove(self.PendingSackThresholds, 1)
	self.NextThresholdEventAt = now + .75
	self:_spawnSacks(threshold)
end

function Controller:_clearPoisonHazards()
	for _,hazard in ipairs(self.Hazards) do if hazard.poison and hazard.part and hazard.part.Parent then hazard.part:Destroy() end end
	table.clear(self.Hazards)
end

-- Enrage (Config.Enrage): cutscene of the Enrage clip for every member (frozen + immune), a
-- poison spew at the jaw thrust, a red outline on Miasma, and the SHROUD -- the breath rolls out
-- to the arena edge and becomes a closing ring of poison mist (see _updateShroud). After the
-- clip the fight resumes with sacks + abilities, and no more gate cycles ever start.
function Controller:BeginEnrage()
	if self.Enraged or self.Finished then return end
	local cfg = Config.Enrage
	self:_endStagger("Enrage")
	self.PendingEnrage=false; self.Enraged=true; self.Director:Stop(); self:_cancelAbility(); self:_clearGateCycle(); self:_setState(Protocol.States.Act3Enrage)
	local duration = cfg.CutsceneSeconds
	self.NextThresholdEventAt = workspace:GetServerTimeNow() + duration
	local centre = self.Resolver:Position("ANCHOR_Miasma")
	local bossModel = self.Boss and self.Boss.Model
	if self.Boss then
		self.Boss:SetEncounterControlled(true); self.Boss:SetEncounterLocked(true, true)
		self.Boss:SetEncounterDamageMultiplier(Config.Boss.EnragedDamageMultiplier or 1)
		self.Boss:PlayEncounterAnimation("Enrage", false, nil, cfg.AnimSpeed)
	end
	if bossModel and not bossModel:FindFirstChild("EnrageOutline") then
		local outline = Instance.new("Highlight")
		outline.Name = "EnrageOutline"
		outline.Adornee = bossModel
		outline.DepthMode = Enum.HighlightDepthMode.Occluded
		outline.OutlineColor = cfg.OutlineColor
		outline.OutlineTransparency = .15
		outline.FillColor = cfg.OutlineColor
		outline.FillTransparency = .9
		outline.Parent = bossModel
	end
	self:_lockPlayersForPresentation(duration, true)

	local now = workspace:GetServerTimeNow()
	local shroud = cfg.Shroud
	self.Shroud = {
		centre = centre,
		origin = (bossModel and bossModel:GetPivot().Position) or centre,
		waveAt = now + cfg.SpewStart,
		landsAt = now + cfg.SpewStart + shroud.WaveSeconds,
		startRadius = shroud.StartRadius, endRadius = shroud.EndRadius, shrinkSeconds = shroud.ShrinkSeconds,
		exposure = {},
	}
	-- "Enrage" keeps the existing listeners (shockwave, warning pulse, stun cleanup) working.
	self:_fire(Protocol.Events.Presentation, { kind = "Enrage", duration = duration, position = centre })
	self:_fire(Protocol.Events.Presentation, {
		kind = "EnrageCutscene", startsAt = now, endsAt = duration,
		spewStart = cfg.SpewStart, spewEnd = cfg.SpewEnd,
		boss = bossModel, landing = self.Boss and self.Boss:GetPosition() or centre, facing = self:_bossFacing(),
	})
	self:_fire(Protocol.Events.Presentation, {
		kind = "Shroud", centre = centre, origin = self.Shroud.origin,
		waveAt = self.Shroud.waveAt, landsAt = self.Shroud.landsAt,
		startRadius = shroud.StartRadius, endRadius = shroud.EndRadius, shrinkSeconds = shroud.ShrinkSeconds,
	})
	local serial=self.StateSerial
	self:_guardedDelay(duration, function()
		if self.Boss then
			self.Boss.HealthFloor = nil -- phase 3 proper: killable from here
			self.Boss:SetEncounterControlled(false); self.Boss:SetEncounterLocked(false,false)
		end
		self:_spawnSacks(.30); self.Director:Start()
	end, serial)
end

-- The shroud's radius at server time `now` (StartRadius until the wave lands, then closing to
-- EndRadius over ShrinkSeconds). nil while the wave is still rolling out.
function Controller:_shroudRadius(now)
	local s = self.Shroud
	if not s or now < s.landsAt then return nil end
	local u = math.clamp((now - s.landsAt) / math.max(s.shrinkSeconds, 1), 0, 1)
	return s.startRadius + (s.endRadius - s.startRadius) * u
end

-- Poison stacks for anyone outside the shroud ring: one per StackInterval spent out there.
function Controller:_updateShroud(dt)
	local s = self.Shroud
	if not s then return end
	local radius = self:_shroudRadius(workspace:GetServerTimeNow())
	if not radius then return end
	local interval = Config.Enrage.Shroud.StackInterval
	for _, player in ipairs(self:_livingPlayers()) do
		local _, root = humanoidAndRoot(player)
		local outside = root ~= nil and flatDistance(root.Position, s.centre) > radius
			and player:GetAttribute("MiasmaInvulnerable") ~= true
		if outside then
			local t = (s.exposure[player] or 0) + dt
			if t >= interval then
				t -= interval
				self.Poison:Add(player, 1)
			end
			s.exposure[player] = t
		else
			s.exposure[player] = nil
		end
	end
end

-- Top-middle boss bar (the named-elite bar) for every member from the drop onward.
function Controller:_updateBossBar()
	local show = self.Boss ~= nil and self.Boss:IsAlive() and BOSS_BAR_STATES[self.State] == true and _G.MobSystem ~= nil
	if show then
		self._bossBarShown = true
		self:_forEachMember(function(player) _G.MobSystem.SetBossBar(player, self.Boss) end)
	elseif self._bossBarShown then
		self:_clearBossBars()
	end
end

function Controller:_clearBossBars(onlyPlayer)
	self._bossBarShown = onlyPlayer ~= nil and self._bossBarShown or false
	local function clear(player)
		if _G.MobSystem and _G.MobSystem.ClearBossBar then _G.MobSystem.ClearBossBar(player, self.Boss) end
		player:SetAttribute("BossStaggerVisible", false)
		player:SetAttribute("BossStaggerState", nil)
	end
	if onlyPlayer then clear(onlyPlayer) else self:_forEachMember(clear) end
end

function Controller:_publishStagger(visible, ratio, state)
	local rounded = math.floor(math.clamp(ratio, 0, 1) * 100 + .5) / 100
	self:_forEachMember(function(player)
		player:SetAttribute("BossStaggerVisible", visible)
		player:SetAttribute("BossStagger", rounded)
		player:SetAttribute("BossStaggerState", state)
	end)
end

function Controller:_isSolo()
	return self.StartingPartySize <= Config.Solo.MaxPartySize
end

-- Every landed hit on Miasma (raw, pre-multiplier) -- set as boss.OnEncounterHit.
function Controller:_onBossHit(player, raw)
	local stagger = self.Stagger
	if not self:_isSolo() or self.State ~= Protocol.States.Act2Puzzle or stagger.active then return end
	local now = os.clock()
	if now < stagger.lockoutUntil or stagger.count >= Config.Solo.MaxStaggersPerCycle then return end
	local key = player and player.UserId or 0
	if now - (stagger.lastHitBy[key] or 0) < Config.Solo.MinHitInterval then return end
	stagger.lastHitBy[key] = now
	stagger.points += math.min(1, raw / Config.Solo.ReferenceHitDamage)
	stagger.lastHitAt = now
	if stagger.points >= Config.Solo.StaggerPoints then self:_beginStagger() end
end

-- The puzzle window: Miasma reels (no attacks, no bonus damage) while the cycle, and the
-- valve, carry on.
function Controller:_beginStagger()
	local stagger = self.Stagger
	stagger.active = true
	stagger.points = 0
	stagger.count += 1
	stagger.serial += 1
	stagger.endsAt = os.clock() + Config.Solo.StaggerDuration
	self.Director:Stop()
	self:_cancelAbility()
	if self.Boss then
		self.Boss:SetEncounterControlled(true)
		self.Boss:SetEncounterLocked(true, false)
		self.Boss:PlayEncounterAnimation("Stunned", true)
	end
	self:_fire(Protocol.Events.Presentation, {
		kind = "Staggered", duration = Config.Solo.StaggerDuration,
		position = self.Resolver:Position("ANCHOR_Miasma"), boss = self.Boss and self.Boss.Model,
	})
	local serial = stagger.serial
	task.delay(Config.Solo.StaggerDuration, function()
		if not self.Finished and stagger.active and stagger.serial == serial then self:_endStagger("Recovered") end
	end)
end

-- reason: "Recovered" (window ran out: Miasma fights again and any open maze closes),
-- or "Water" / "Purge" / "Enrage" / "End" (another path takes the boss over).
function Controller:_endStagger(reason)
	local stagger = self.Stagger
	if not stagger or not stagger.active then return end
	stagger.active = false
	stagger.lockoutUntil = os.clock() + Config.Solo.RecoveryLockout
	if self.Boss then self.Boss:StopEncounterAnimation("Stunned") end
	if reason == "Recovered" and self.State == Protocol.States.Act2Puzzle then
		for index = 1, 4 do self.ValveGates[index]:ReleaseOperator("BossRecovered") end
		if self.Boss then
			self.Boss:SetEncounterControlled(false)
			self.Boss:SetEncounterLocked(false, false)
		end
		self.Director:Start()
		self:_fire(Protocol.Events.Presentation, { kind = "StaggerRecovered" })
	else
		-- Another path took the boss over (water stun, purge, enrage, encounter end): the
		-- stagger's star ring goes. A water stun starts its own right after.
		self:_fire(Protocol.Events.Presentation, { kind = "StunEnded" })
	end
end

function Controller:_resetStaggerForCycle()
	self:_endStagger("End")
	self.Stagger = { points = 0, count = 0, active = false, endsAt = 0, serial = (self.Stagger and self.Stagger.serial or 0) + 1, lockoutUntil = 0, lastHitAt = 0, lastHitBy = {} }
end

-- Meter decay + publishing (solo only). Shown during the gate phases, hidden otherwise.
function Controller:_updateStagger(dt)
	if not self:_isSolo() or not self.Stagger then return end
	local stagger = self.Stagger
	local now = os.clock()
	local inCycle = self.State == Protocol.States.Act2Puzzle or self.State == Protocol.States.PureWaterStun or self.State == Protocol.States.CycleResetWarning
	if not inCycle then
		if self._staggerShown ~= false then self:_publishStagger(false, 0, "Building") end
		self._staggerShown = false
		return
	end
	self._staggerShown = true
	if stagger.active then
		self:_publishStagger(true, math.max(0, stagger.endsAt - now) / Config.Solo.StaggerDuration, "Staggered")
		return
	end
	if now - stagger.lastHitAt > Config.Solo.StaggerDecayDelay then
		stagger.points = math.max(0, stagger.points - Config.Solo.StaggerDecayPerSecond * dt)
	end
	local spent = stagger.count >= Config.Solo.MaxStaggersPerCycle or now < stagger.lockoutUntil or self.State ~= Protocol.States.Act2Puzzle
	self:_publishStagger(true, stagger.points / Config.Solo.StaggerPoints, spent and "Recovering" or "Building")
end

-- pcall one per-frame update; warn once per distinct error message so a persistent failure
-- is visible in the output without spamming it every frame.
function Controller:_guardedUpdate(key, fn, ...)
	local ok, err = pcall(fn, ...)
	if ok then return end
	self._updateErrors = self._updateErrors or {}
	local msg = tostring(err)
	if self._updateErrors[key] ~= msg then
		self._updateErrors[key] = msg
		warn(("[MiasmaEncounter] %s update failed: %s"):format(key, msg))
	end
end

function Controller:_heartbeat(dt)
	if self.Finished then return end
	-- Death first: nothing later in this frame (including an erroring subsystem) may delay it.
	if self.Boss and not self.Boss:IsAlive() then self:Defeat(); return end
	local living=self:_livingPlayers(); self.StateModel:SetAttribute(Protocol.Attributes.AlivePlayers,#living)
	if self.State ~= Protocol.States.Dormant and self.State ~= Protocol.States.EntranceGrace and #living==0 then self:Fail("PartyWipe"); return end
	-- Boss bar + stagger FIRST, and every other per-frame subsystem isolated: this function
	-- is one unprotected Heartbeat connection, so a single erroring update used to skip
	-- everything after it for that frame -- including these two, which is how the boss bar
	-- and stagger meter could vanish mid-fight. A failing subsystem now warns (once per
	-- distinct error) instead of taking the bars down with it.
	self:_guardedUpdate("bossBar", self._updateBossBar, self)
	self:_guardedUpdate("stagger", self._updateStagger, self, dt or 0)
	for index = 1, 4 do self:_guardedUpdate("valve" .. index, self.ValveGates[index].Update, self.ValveGates[index], living) end
	for index, altar in ipairs(self.Altars) do self:_guardedUpdate("altar" .. index, altar.Update, altar) end
	self:_guardedUpdate("shroud", self._updateShroud, self, dt or 0)
	self:_guardedUpdate("bodyContact", self._updateBodyContact, self)
	local now = workspace:GetServerTimeNow()
	if self.State == Protocol.States.Act1Survival or self.State == Protocol.States.Act1Cleanup then self:_updateSlimeProjectiles(now) end
	local endsAt = self.StateModel:GetAttribute(Protocol.Attributes.StateEndsAt) or 0
	if self.State == Protocol.States.Act1Survival and endsAt > now then
		local remaining = math.clamp((endsAt - now) / Config.Act1Duration, 0, 1)
		self.CisternIndicator.Transparency = .25
		self.CisternIndicator.Size = Vector3.new(2, 36 * math.max(.04, remaining), 36 * math.max(.04, remaining))
	else
		self.CisternIndicator.Transparency = 1
	end
	local cycleEnds = self.StateModel:GetAttribute(Protocol.Attributes.CycleEndsAt) or 0
	if self.State == Protocol.States.Act2Puzzle and cycleEnds > now then
		local filled = 1 - math.clamp((cycleEnds - now) / Config.Gates.CycleDuration, 0, 1)
		local diameter = 8 + filled * 42
		self.PressureIndicator.Transparency = .35
		self.PressureIndicator.Size = Vector3.new(.15, diameter, diameter)
	else
		self.PressureIndicator.Transparency = 1
	end
	if self.Boss then
		if not self.Boss:IsAlive() then self:Defeat(); return end
		local fraction=self.Boss.CurrentHealth/math.max(1,self.Boss.MaxHealth)
		for _,threshold in ipairs(Config.Boss.SackThresholds) do
			if fraction<=threshold and not self.SackThresholdsFired[threshold] then
				self.SackThresholdsFired[threshold]=true
				if threshold==.30 then
					if self.State==Protocol.States.PureWaterStun then self.PendingEnrage=true else self:BeginEnrage() end
				else
					table.insert(self.PendingSackThresholds,threshold)
				end
			end
		end
	end
	self:_processSackThresholdQueue()
end

-- Died during the fight: poison gone at once (it would otherwise tick on into their next
-- life), and any valve they were working is released. They remain a member and spectate.
function Controller:OnMemberDied(player)
	if not player then return end
	self.Poison:Clear(player)
	self:CancelValve(player, "Died")
end

-- Out of the fight for good (left, disconnected, walked out). Dropped from MemberSet FIRST:
-- every per-frame push (boss bar, stagger, music) keys off it, and a failing cleanup step
-- used to abort before this line, so a leaver kept receiving Miasma's bar in the overworld.
function Controller:RemovePlayer(player)
	if not player then return end
	self.MemberSet[player.UserId]=nil
	self:_safeStep("leaveValve", self.CancelValve, self, player, "Left")
	self:_safeStep("leaveBossBar", self._clearBossBars, self, player)
	self:_safeStep("leavePoison", function() self.Poison:RemoveMember(player) end)
	if self._phaseMusicId then self:_safeStep("leaveMusic", ZoneService.SetEncounterMusic, player, "") end
end

-- Runs one teardown step, warning instead of throwing. Fail/Defeat set Finished before their
-- cleanup, so a single erroring step used to leave the encounter finished but OnFinished never
-- called: no exit countdown, no teardown, and the party stuck in the realm.
function Controller:_safeStep(label, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then warn(("[MiasmaEncounter] %s failed: %s"):format(label, tostring(err))) end
end

-- Hands every member back their movement and clears the encounter's immunity, in case the
-- fight ended inside a presentation freeze (_lockPlayersForPresentation restores on its own
-- timer, which is fine unless the realm is torn down first).
function Controller:_releasePlayerLocks()
	self:_forEachMember(function(player)
		player:SetAttribute("MiasmaInvulnerable", nil)
		local humanoid = humanoidAndRoot(player)
		if humanoid and humanoid.Health > 0 and humanoid.WalkSpeed == 0 then
			humanoid.WalkSpeed = StarterPlayer.CharacterWalkSpeed
			humanoid.JumpPower = StarterPlayer.CharacterJumpPower
		end
	end)
end

function Controller:_finish(outcome, reason, presentation)
	if self.Finished then return end
	self.Finished = true
	self.State = outcome == "cleared" and Protocol.States.Defeated or Protocol.States.Failed
	-- Queue OnFinished FIRST: nothing below can stop the exit countdown / teardown any more.
	if self.OnFinished then task.defer(self.OnFinished, outcome, reason) end
	if self.Boss then self.Boss.HealthFloor = nil end
	self:_safeStep("state", function() self.StateModel:SetAttribute(Protocol.Attributes.State, self.State) end)
	self:_safeStep("gates", self._clearGateCycle, self, "EncounterOver")
	self:_safeStep("director", function() self.Director:Stop() end)
	self:_safeStep("ability", self._cancelAbility, self)
	self:_safeStep("stagger", self._endStagger, self, "End")
	-- Defeat: the presentation plays at the size it died at (no regrow).
	local regrow = true
	if outcome == "cleared" then regrow = false end
	self:_safeStep("stunShrink", self._endStunShrink, self, regrow)
	self:_safeStep("music", self._setPhaseMusic, self, "")
	self.Shroud = nil
	self:_safeStep("bossBars", self._clearBossBars, self)
	self:_safeStep("playerLocks", self._releasePlayerLocks, self)
	self:_safeStep("presentation", self._fire, self, Protocol.Events.Presentation, presentation)
end

function Controller:Fail(reason)
	self:_finish("failed", reason, { kind = "Failed", reason = reason })
end

function Controller:Defeat()
	self:_finish("cleared", "BossDefeated", { kind = "Defeated" })
end

function Controller:HandleRequest(player, request, payload)
	if not self.MemberSet[player.UserId] then return end
	if request==Protocol.Requests.CancelAltar then
		for _, altar in ipairs(self.Altars) do altar:Cancel(player) end
	elseif request==Protocol.Requests.CancelValve then
		self:CancelValve(player,"Cancelled")
	elseif request==Protocol.Requests.MazeSample and type(payload)=="table" then
		local gate = ValveGate.FindByOperator(self.ValveGates, player)
		if gate and self.State == Protocol.States.Act2Puzzle then gate:HandleSample(player, payload) end
	end
end

function Controller:Destroy()
	if self.State==Protocol.States.Destroyed then return end
	self:_endStagger("End")
	self:_endStunShrink(false)
	if self._phaseMusicId then self:_setPhaseMusic("") end
	self.Shroud = nil
	self.Finished=true; self.Director:Stop(); self.State=Protocol.States.Destroyed
	if self.Boss then self.Boss.OnEncounterHit = nil; self.Boss.OnEncounterMeleeHit = nil end
	if self.Boss and self.Boss.CancelDropTransition then self.Boss:CancelDropTransition() end
	if self.Boss and self.Boss.CancelDefeatPresentation then self.Boss:CancelDefeatPresentation() end
	if self.Boss and self.Boss.SetEncounterVisible then self.Boss:SetEncounterVisible(true) end
	self:_clearBossBars()
	self:_forEachMember(function(player) player:SetAttribute("MiasmaInvulnerable",nil) end)
	self.Bin:Destroy()
end

return Controller
