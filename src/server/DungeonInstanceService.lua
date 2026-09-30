--[[
	DungeonInstanceService  (server-only)

	Party-leader-triggered dungeon runs: leader touches a world portal -> every party
	member's inventory is checked for the tier's dungeon key (ProfileService,
	itemId from DungeonPortalConfig) -> a ready-prompt with live per-member status goes to
	every member's client -> once everyone accepts, the whole party is teleported into a
	private "realm" (a cloned placeholder model parked far beneath the main map, purely a
	cheap same-server workspace offset -- NOT a separate Roblox place/server, see header of
	ensureRealmTemplate/launchDungeon below) -> run duration is tracked -> each member gets
	their own "Leave Dungeon" button that removes only them, teleporting them to their real
	hearthstone location (HearthstoneService.GetHearthstoneLocation) without affecting
	anyone else still inside.

	Portal detection is 100% event-driven (BasePart.Touched + CollectionService tag/instance
	signals) -- nothing here polls proximity every frame via RunService.Heartbeat/Stepped.

	Integrates with real APIs only:
	  PartyService.GetPartyMembers / GetLeaderUserId / IsPartyLeader
	  ProfileService.CountItemId / ConsumeItemId
	  HearthstoneService.GetHearthstoneLocation
]]

local Players             = game:GetService("Players")
local CollectionService    = game:GetService("CollectionService")
local ServerStorage        = game:GetService("ServerStorage")
local Workspace             = game:GetService("Workspace")
local HttpService          = game:GetService("HttpService")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local ServerScriptService  = game:GetService("ServerScriptService")

local RemoteUtils        = require(ReplicatedStorage:WaitForChild("RemoteUtils"))
local DungeonTypes        = require(ReplicatedStorage:WaitForChild("DungeonInstanceTypes"))
local DungeonLevels       = require(ReplicatedStorage:WaitForChild("DungeonLevels"))
local DungeonPortalConfig = require(ServerScriptService:WaitForChild("DungeonPortalConfig"))
local PartyService        = require(ServerScriptService:WaitForChild("PartyService"))
local DungeonProfile      = require(ServerScriptService:WaitForChild("ProfileService"))
local HearthstoneService  = require(ServerScriptService:WaitForChild("HearthstoneService"))
local InventoryAudit      = require(ServerScriptService:WaitForChild("InventoryAudit"))
local StatusCleanse       = require(ServerScriptService:WaitForChild("StatusCleanse"))

local ensureFolder         = RemoteUtils.EnsureFolder
local ensureRemoteEvent    = RemoteUtils.EnsureRemoteEvent

local DungeonInstanceService = {}

----------------------------------------------------------------------
-- Remotes (ReplicatedStorage.GameEvents, matching PartyService/ZoneService convention)
----------------------------------------------------------------------

local ge = ensureFolder(ReplicatedStorage, "GameEvents")
local DungeonReadyPrompt        = ensureRemoteEvent(ge, "DungeonReadyPrompt")        -- server -> clients: initial roster + block state
local DungeonPromptStatusUpdate = ensureRemoteEvent(ge, "DungeonPromptStatusUpdate") -- server -> clients: live per-member status
local DungeonPromptCancelled    = ensureRemoteEvent(ge, "DungeonPromptCancelled")    -- server -> clients: someone rejected / left mid-prompt
local DungeonPromptRespond      = ensureRemoteEvent(ge, "DungeonPromptRespond")      -- client -> server: (instanceId, accepted)
local DungeonInstanceStateUpdate= ensureRemoteEvent(ge, "DungeonInstanceStateUpdate")-- server -> clients: entered / left / ended
local DungeonLeaveRequest       = ensureRemoteEvent(ge, "DungeonLeaveRequest")       -- client -> server: leave MY instance only
local DungeonSpectate           = ensureRemoteEvent(ge, "DungeonSpectate")           -- server -> client: { active, instanceId, memberUserIds }

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------

-- activeInstances[instanceId] = {
--   instanceId, tier, numericTier, dungeonName, keyItemId, realmTemplateName,
--   encounterId, leaderUserId,
--   members = { [userId] = name }, statuses = { [userId] = DungeonTypes.MemberStatus },
--   state = DungeonTypes.State, startTime (os.time(), set on launch),
--   realmModel (Instance?), realmSlot (number?),
-- }
local activeInstances = {}
local playerToInstance = {} -- [userId] = instanceId (covers both PROMPTING and IN_PROGRESS)
local finishInstance

-- Miasma: how long the party can stay (loot, regroup) after the kill before being sent home,
-- and the pause after a party wipe before everyone respawns at their hearthstone.
local MIASMA_EXIT_SECONDS = 15 -- ~4.6s of it is the Dungeon Complete banner
local MIASMA_WIPE_BEAT_SECONDS = 2

----------------------------------------------------------------------
-- Realm template + per-instance far-away offset allocator
----------------------------------------------------------------------

-- Cheap same-server isolation: every dungeon instance is a clone of one placeholder model,
-- parked far out along the X axis from the main map (never streamed in for players who
-- aren't there, and far enough apart from other concurrent instances to never overlap).
-- This is deliberately NOT a separate Roblox place/server (no TeleportService involved,
-- unlike ShardService's shard-hopping feature) -- just a workspace offset, which is all a
-- single private party dungeon run needs.
--
-- Offset SIDEWAYS (X), not DOWNWARD (Y): an earlier version parked realms miles below the
-- map (Y = -10000), which sits well below Workspace.FallenPartsDestroyHeight's default of
-- -500 -- the engine silently destroys anything below that height, so the realm floor and
-- whatever player stood on it got killed within seconds of every launch (looked exactly
-- like an instant, silent teleport back to Oakhaven). The fix-for-that then tried to raise
-- FallenPartsDestroyHeight from this script at runtime, which is WORSE: that property is
-- locked behind Plugin-level permission, a regular Script throws trying to write it, and
-- since that throw happened at module load time it took down this entire require() (and
-- therefore ProfileBootstrap's require of it, and everything after that line in
-- ProfileBootstrap -- starter gear, hotbar setup, profile push, this file's own
-- ensurePlaceholderPortal() call, all silently skipped for the rest of that session).
-- A large horizontal offset at a normal Y sidesteps the whole problem: nowhere near any
-- fall-kill height, no Workspace property needs touching, ever. Do not go back to a deep
-- negative Y here.
local REALM_BASE_X = 100000
local REALM_Y = 50
local REALM_X_SPACING = 500

-- DungeonRealmTemplate is a real, hand-built model living directly in Workspace (built in
-- Studio, not generated in code) -- this just looks it up. It's parked at (-100000, 50, 0),
-- the mirror opposite side from where live cloned instances get parked (REALM_BASE_X =
-- +100000+), specifically so the master build never gets confused with a live clone. It has
-- to live in Workspace rather than ServerStorage because ServerStorage's contents don't
-- render in the 3D viewport at all (even in Edit mode) -- only Workspace descendants do, so
-- building it visually in Studio requires it to be here. It must have a PrimaryPart and a
-- part named "SpawnPoint" (used to position the party on launch); no other structure is
-- required by this script. Returns nil if it hasn't been built yet -- callers must handle
-- that instead of assuming a template always exists.
local function ensureRealmTemplate(templateName)
	if type(templateName) ~= "string" or templateName == "" then
		return nil
	end
	-- Found by NAME ANYWHERE under Workspace, not only as a direct child: the template gets
	-- filed into organising folders in Studio (it now lives at Workspace.T1Dungeon.
	-- DungeonRealmTemplate), and a root-only lookup made every launch report "no realm
	-- template" the moment it was moved. Live instances are named by instanceId and parked
	-- under realmsFolder, so they can never be mistaken for the template. A direct child still
	-- wins if there is one.
	local existing = Workspace:FindFirstChild(templateName) or Workspace:FindFirstChild(templateName, true)
	if not existing then
		warn("[DungeonInstanceService] no '" .. templateName .. "' Model anywhere under Workspace"
			.. " -- build the dungeon realm in Studio (a Model with a "
			.. "PrimaryPart and a \"SpawnPoint\" part) before dungeons can launch.")
		return nil
	end
	if not existing:IsA("Model") then
		warn("[DungeonInstanceService] " .. existing:GetFullName() .. " must be a Model")
		return nil
	end
	return existing
end

local freeRealmSlots = {}
local nextRealmSlot = 0
local function allocRealmSlot()
	if #freeRealmSlots > 0 then
		return table.remove(freeRealmSlots)
	end
	nextRealmSlot += 1
	return nextRealmSlot
end
local function releaseRealmSlot(slot)
	table.insert(freeRealmSlots, slot)
end

local realmsFolder = ensureFolder(Workspace, "DungeonInstances")

----------------------------------------------------------------------
-- Placeholder portal (code-first, matching ProfileBootstrap's "ensure exists" idiom)
----------------------------------------------------------------------

-- Only a T1 portal is ensured here (T2/T3 rows in DungeonPortalConfig are ready for real
-- portal parts placed in Studio later -- just tag them "DungeonPortal" and set their
-- DungeonTier attribute, no code changes needed). This is explicitly a placeholder per the
-- task scope: no real dungeon content, just enough infra to test the flow end-to-end.
local function ensurePlaceholderPortal()
	local t1Config = DungeonPortalConfig.Get("T1")
	local portalsFolder = Workspace:FindFirstChild("DungeonPortals")
	if not portalsFolder then
		portalsFolder = Instance.new("Folder")
		portalsFolder.Name = "DungeonPortals"
		portalsFolder.Parent = Workspace
	end
	local existing = portalsFolder:FindFirstChild("T1Portal")
	if existing and existing:IsA("BasePart") then
		existing:SetAttribute("DungeonTier", "T1")
		existing:SetAttribute("DungeonName", t1Config.DungeonName)
		if not CollectionService:HasTag(existing, "DungeonPortal") then
			CollectionService:AddTag(existing, "DungeonPortal")
		end
		return
	end

	local part = Instance.new("Part")
	part.Name = "T1Portal"
	part.Size = Vector3.new(8, 10, 2)
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 0.35
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(120, 60, 200)
	-- Placeholder location near Oakhaven so it's reachable for testing; swap for a real
	-- dungeon-entrance model/position in Studio whenever art exists -- this service only
	-- cares about the "DungeonPortal" tag + DungeonTier attribute, never this exact part.
	part.CFrame = CFrame.new(-1160, 8.5, 60)
	part.Parent = portalsFolder

	part:SetAttribute("DungeonTier", "T1")
	part:SetAttribute("DungeonName", t1Config.DungeonName)
	CollectionService:AddTag(part, "DungeonPortal")
end

----------------------------------------------------------------------
-- Roster / status helpers
----------------------------------------------------------------------

local function buildRoster(instance)
	local rows = {}
	for userId, name in pairs(instance.members) do
		table.insert(rows, {
			userId = userId,
			name = name,
			status = instance.statuses[userId] or DungeonTypes.MemberStatus.WAITING,
		})
	end
	table.sort(rows, function(a, b) return a.name < b.name end)
	return rows
end

local function acceptanceCounts(instance)
	local accepted, total = 0, 0
	for _, status in pairs(instance.statuses) do
		total += 1
		if status == DungeonTypes.MemberStatus.ACCEPTED then
			accepted += 1
		end
	end
	return accepted, total
end

local function buildPromptPayload(instance, blocked, blockedReason)
	local accepted, total = acceptanceCounts(instance)
	return {
		instanceId = instance.instanceId,
		dungeonName = instance.dungeonName,
		tier = instance.tier,
		blocked = blocked or false,
		blockedReason = blockedReason or "",
		members = buildRoster(instance),
		acceptedCount = accepted,
		totalCount = total,
	}
end

local function fireToAllMembers(instance, remote, payload)
	for userId in pairs(instance.members) do
		local plr = Players:GetPlayerByUserId(userId)
		if plr then
			remote:FireClient(plr, payload)
		end
	end
end

----------------------------------------------------------------------
-- Teardown
----------------------------------------------------------------------

-- TODO (loot rewards -- explicitly out of scope for this pass): hook point for awarding
-- dungeon completion loot. Called whenever an instance's realm is torn down (last member
-- left/disconnected). Wire a real loot table here in a future pass.
local function onInstanceComplete(_instance)
end

----------------------------------------------------------------------
-- Spectating (dying during the boss encounter)
--
-- A member who dies while the instance's encounter is live does NOT leave the run: there are
-- no revives in the boss fight, so they watch the rest of the party instead (client:
-- SpectatorClient). Their respawned body is parked out of reach -- far above the realm,
-- anchored, invisible, no collision -- and the encounter excludes anyone with the
-- SPECTATE_ATTR attribute from every living-player check (no hits, no poison, and a party
-- wipe still triggers once everyone else is down). Leaving, or the run ending, respawns them
-- normally at their hearthstone.
----------------------------------------------------------------------

local SPECTATE_ATTR = "DungeonSpectating" -- = instanceId while spectating
local SPECTATE_PARK_HEIGHT = 600          -- studs above the realm pivot

-- Streaming follows the character by default. A spectator's new body spawns in the overworld
-- before it's parked, and their client then streamed the realm (and everyone in it) out: after
-- ~5 s (the respawn) they had "no one to spectate". Pin their streaming focus on the realm.
local function realmFocusPart(instance)
	local realm = instance and instance.realmModel
	if not realm then return nil end
	local part = realm:FindFirstChild("SpawnPoint")
	if part and part:IsA("BasePart") then return part end
	return realm.PrimaryPart or realm:FindFirstChildWhichIsA("BasePart", true)
end

local function isSpectating(player)
	return player ~= nil and player:GetAttribute(SPECTATE_ATTR) ~= nil
end

local function parkSpectatorBody(player, instance, char)
	local hrp = char:WaitForChild("HumanoidRootPart", 5)
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not isSpectating(player) then return end
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Transparency = 1
			d.CanCollide, d.CanTouch, d.CanQuery = false, false, false
		elseif d:IsA("Decal") then
			d.Transparency = 1
		end
	end
	if humanoid then humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None end
	local base = instance.realmModel and instance.realmModel:GetPivot().Position or hrp.Position
	char:PivotTo(CFrame.new(base + Vector3.new(0, SPECTATE_PARK_HEIGHT, 0)))
	hrp.Anchored = true
end

-- Ends spectating (Leave, or the realm is torn down): respawn normally at the hearthstone.
local function endSpectating(player)
	if not isSpectating(player) then return false end
	player:SetAttribute(SPECTATE_ATTR, nil)
	player.ReplicationFocus = nil
	DungeonSpectate:FireClient(player, { active = false })
	local conn
	conn = player.CharacterAdded:Connect(function(newChar)
		conn:Disconnect()
		local root = newChar:WaitForChild("HumanoidRootPart", 5)
		if root then newChar:PivotTo(HearthstoneService.GetHearthstoneLocation(player)) end
	end)
	task.spawn(function()
		local ok, err = pcall(function() player:LoadCharacter() end)
		if not ok then warn("[DungeonInstanceService] respawn after spectating failed for " .. player.Name .. ": " .. tostring(err)) end
	end)
	return true
end

-- EVERY way a player stops being in a realm (Leave, disconnect, the absence watchdog, the
-- instance ending cleared or failed) passes through here exactly once: the InDungeon flag
-- goes and every debuff / effect is wiped (SSS/StatusCleanse). A new dungeon type or exit
-- path gets this for free as long as it removes members through removePlayerFromInstance
-- or finishInstance; nothing dungeon-specific has to remember its own cleanup.
local function releaseMember(player, reason)
	if not player then return end
	player:SetAttribute("InDungeon", nil)
	StatusCleanse.All(player, reason)
end

-- Puts a still-connected member back at their hearthstone BEFORE their realm is destroyed.
-- The realm hangs in empty sky, so deleting it with anyone still inside dropped them into the
-- void until the fall killed them (the "float in the sky" after a run ended). Alive: moved now.
-- Dead: respawned now and landed at the hearthstone, instead of lying in a deleted realm until
-- the engine's own respawn timer.
local function evacuateMember(player)
	if not player or not player.Parent then return end
	InventoryAudit.Note(player, "sent home: dungeon realm torn down")
	if endSpectating(player) then return end -- parked body: respawn fresh at the hearthstone
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if humanoid and hrp and humanoid.Health > 0 then
		char:PivotTo(HearthstoneService.GetHearthstoneLocation(player))
		return
	end
	local conn
	conn = player.CharacterAdded:Connect(function(newChar)
		conn:Disconnect()
		local root = newChar:WaitForChild("HumanoidRootPart", 5)
		if root then newChar:PivotTo(HearthstoneService.GetHearthstoneLocation(player)) end
	end)
	task.spawn(function()
		local ok, err = pcall(function() player:LoadCharacter() end)
		if not ok then warn("[DungeonInstanceService] respawn after run failed for " .. player.Name .. ": " .. tostring(err)) end
	end)
end

local function destroyInstanceRealm(instance, outcome)
	outcome = outcome or "failed"
	-- Cash out every member's banked loot before anything else. This is where
	-- the run's drops are finally rolled and granted.
	do
		local okRun, runSvc = pcall(require, ServerScriptService:WaitForChild("DungeonRunService", 5))
		if okRun and runSvc and runSvc.EndRunFor then
			for _, uid in ipairs(instance.memberUserIds or {}) do
				local plr = Players:GetPlayerByUserId(uid)
				if plr then
					pcall(runSvc.EndRunFor, plr, outcome)
				end
			end
		end
	end
	if instance.encounterController then
		local ok, svc = pcall(require, ServerScriptService:WaitForChild("MiasmaEncounterService", 5))
		if ok and svc and svc.Destroy then pcall(svc.Destroy, instance.instanceId) end
		instance.encounterController = nil
	end

	-- Tear down this instance's spawners BEFORE the realm goes, so their mobs
	-- are destroyed rather than orphaned in a deleted model.
	if instance.spawnerHandle then
		local ok, svc = pcall(require, ServerScriptService:WaitForChild("DungeonMobSpawnService", 5))
		if ok and svc and svc.UnregisterForRealm then
			pcall(svc.UnregisterForRealm, instance.spawnerHandle)
		end
		instance.spawnerHandle = nil
	end
	-- Everyone still here goes home first: the realm floats in empty sky. Cleansed first
	-- (the encounter above is gone, so nothing re-applies anything).
	for _, uid in ipairs(instance.memberUserIds or {}) do
		local plr = Players:GetPlayerByUserId(uid)
		if plr and instance.members[uid] then
			pcall(releaseMember, plr, "DungeonEnded")
			local ok, err = pcall(evacuateMember, plr)
			if not ok then warn("[DungeonInstanceService] evacuating " .. plr.Name .. " failed: " .. tostring(err)) end
		end
	end
	if instance.realmModel then
		instance.realmModel:Destroy()
		instance.realmModel = nil
	end
	if instance.realmSlot then
		releaseRealmSlot(instance.realmSlot)
		instance.realmSlot = nil
	end
end

finishInstance = function(instance, outcome, reason)
	if not instance or instance._finishing then return end
	instance._finishing = true
	instance.state = DungeonTypes.State.ENDED
	fireToAllMembers(instance, DungeonInstanceStateUpdate, {
		instanceId = instance.instanceId,
		state = DungeonTypes.State.ENDED,
		outcome = outcome,
		reason = reason or "",
	})
	for userId in pairs(instance.members) do playerToInstance[userId] = nil end
	destroyInstanceRealm(instance, outcome)
	activeInstances[instance.instanceId] = nil
	onInstanceComplete(instance)
end

local function cancelInstance(instance, reason)
	instance.state = DungeonTypes.State.ENDED
	fireToAllMembers(instance, DungeonPromptCancelled, { instanceId = instance.instanceId, reason = reason or "" })
	for userId in pairs(instance.members) do
		playerToInstance[userId] = nil
	end
	activeInstances[instance.instanceId] = nil
end

----------------------------------------------------------------------
-- Launch: teleport the accepted party into the realm
----------------------------------------------------------------------

local function launchDungeon(instance)
	-- Consume one key per member now (not at prompt time) -- this is the moment the run
	-- actually starts. Two-pass on purpose: verify every member still has a key BEFORE
	-- consuming anyone's, so a mid-race failure (someone traded/sold their key between
	-- accepting and launch) never shows up as an abort *after* another member's key has
	-- already been irreversibly removed with no refund.
	-- Check the realm template exists BEFORE touching anyone's keys -- no point consuming
	-- a party's keys only to fail on a dungeon that hasn't been built in Studio yet.
	local template = ensureRealmTemplate(instance.realmTemplateName)
	if not template then
		cancelInstance(instance, "This dungeon does not have a realm template yet.")
		return
	end

	for userId in pairs(instance.members) do
		local plr = Players:GetPlayerByUserId(userId)
		if not plr or DungeonProfile.CountItemId(plr, instance.keyItemId) < 1 then
			cancelInstance(instance, "Could not verify dungeon key -- please re-enter the portal.")
			return
		end
	end
	for userId in pairs(instance.members) do
		local plr = Players:GetPlayerByUserId(userId)
		-- Defensive only -- just verified above for everyone. A fresh failure here is a
		-- genuine rare race the verify pass can't fully close, but the common case (a
		-- stale check) is exactly what the two-pass split eliminates.
		if not plr or not DungeonProfile.ConsumeItemId(plr, instance.keyItemId, 1) then
			cancelInstance(instance, "Could not consume dungeon key -- please re-enter the portal.")
			return
		end
	end

	local slot = allocRealmSlot()
	local clone = template:Clone()
	clone.Name = instance.instanceId
	clone:PivotTo(CFrame.new(REALM_BASE_X + (slot * REALM_X_SPACING), REALM_Y, 0))
	clone.Parent = realmsFolder

	instance.realmModel = clone
	instance.realmSlot = slot

	-- The run's mob level, decided ONCE here and handed to every spawner below.
	-- instance.modifiers is the hook for future difficulty modifiers -- empty
	-- today, so this is the tier's base (T1 = 15). See RS/DungeonLevels.
	instance.modifiers = instance.modifiers or {}
	instance.runLevel = DungeonLevels.Resolve(instance.numericTier or 1, instance.modifiers)

	-- Populate THIS clone with its own mob spawners. Registration is
	-- per-instance rather than at boot because every run gets its own copy of
	-- the realm parked at a different X offset -- spawners registered against
	-- the master template would spawn mobs in a room nobody is ever in.
	-- Start the loot run for every member. Without this DungeonScoreService
	-- never knows they are inside a dungeon, so kills fall through to the
	-- OVERWORLD path and drop gear on the floor immediately -- defeating the
	-- whole point of banking loot until the run ends.
	do
		local okRun, runSvc = pcall(require, ServerScriptService:WaitForChild("DungeonRunService", 5))
		if okRun and runSvc and runSvc.StartRun then
			local members = {}
			for _, uid in ipairs(instance.memberUserIds or {}) do
				local plr = Players:GetPlayerByUserId(uid)
				if plr then table.insert(members, plr) end
			end
			if #members == 0 then
				for _, plr in ipairs(Players:GetPlayers()) do table.insert(members, plr) end
			end
			pcall(runSvc.StartRun, members, instance.numericTier or 1)
		end
	end

	do
		local ok, svc = pcall(require, ServerScriptService:WaitForChild("DungeonMobSpawnService", 5))
		if ok and svc and svc.RegisterForRealm then
			local ok2, handle = pcall(svc.RegisterForRealm, clone, instance.tier, instance.encounterId, instance.runLevel)
			if ok2 then
				instance.spawnerHandle = handle
			else
				warn("[DungeonInstanceService] RegisterForRealm failed: ", handle)
			end
		end
	end
	instance.state = DungeonTypes.State.IN_PROGRESS
	instance.startTime = os.time()

	local spawnPart = clone:FindFirstChild("SpawnPoint")
	local spawnPos = spawnPart and spawnPart.Position or clone:GetPivot().Position

	local i = 0
	for userId in pairs(instance.members) do
		local plr = Players:GetPlayerByUserId(userId)
		local char = plr and plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			-- Small per-member horizontal spread so the party doesn't land stacked exactly
			-- on top of each other.
			hrp.CFrame = CFrame.new(spawnPos + Vector3.new(i * 4, 3, 0))
			plr:SetAttribute("InDungeon", true) -- cleared by releaseMember
			InventoryAudit.Note(plr, ("entered dungeon %s (tier %s)"):format(tostring(instance.dungeonName), tostring(instance.tier)))
		end
		i += 1
	end

	-- Start after placement: the boss spawner now sees the party inside its
	-- activation radius, while the controller can safely wait for that boss.
	if instance.encounterId == "Miasma" then
		local ok, service = pcall(require, ServerScriptService:WaitForChild("MiasmaEncounterService", 5))
		if ok and service and service.Start then
			local ok2, controller = pcall(service.Start, {
				instanceId = instance.instanceId,
				realm = clone,
				memberUserIds = instance.memberUserIds,
				spawnerHandle = instance.spawnerHandle,
				runLevel = instance.runLevel,
				onFinished = function(outcome, reason)
					-- Cleared: cash everyone out NOW (the summary shows the moment Miasma dies)
					-- and start the exit countdown with its Leave Now button; when it runs out
					-- the instance finishes and anyone left is sent home. Failed (party wipe):
					-- a short beat on the last death, then everyone respawns at home.
					local delaySeconds = outcome == "cleared" and MIASMA_EXIT_SECONDS or MIASMA_WIPE_BEAT_SECONDS
					if outcome == "cleared" then
						local okRun, runSvc = pcall(require, ServerScriptService:WaitForChild("DungeonRunService", 5))
						local present = {}
						for uid in pairs(instance.members) do
							local plr = Players:GetPlayerByUserId(uid)
							if plr then
								table.insert(present, plr)
								if okRun and runSvc and runSvc.EndRunFor then pcall(runSvc.EndRunFor, plr, "cleared") end
							end
						end
						if okRun and runSvc and runSvc.ShowExitCountdown then pcall(runSvc.ShowExitCountdown, present, delaySeconds) end
					end
					task.delay(delaySeconds, function()
						if activeInstances[instance.instanceId] == instance then finishInstance(instance, outcome, reason) end
					end)
				end,
			})
			if ok2 then instance.encounterController = controller else warn("[DungeonInstanceService] Miasma encounter start failed: ", controller) end
		elseif not ok then
			warn("[DungeonInstanceService] MiasmaEncounterService require failed: ", service)
		end
	end

	fireToAllMembers(instance, DungeonInstanceStateUpdate, {
		instanceId = instance.instanceId,
		state = DungeonTypes.State.IN_PROGRESS,
		dungeonName = instance.dungeonName,
		tier = instance.tier,
		level = instance.runLevel,
		startTime = instance.startTime,
	})
end

----------------------------------------------------------------------
-- Portal -> ready prompt
----------------------------------------------------------------------

local function initiateDungeon(leader, tier, cfg)
	-- No party at all -> solo run: synthesize a party-of-one from the leader's
	-- own name, same {userId, name} row shape PartyService.GetPartyMembers
	-- returns for a real party, so nothing downstream needs to special-case it.
	local memberRows = PartyService.GetPartyMembers(leader)
	if not memberRows then
		memberRows = {
			{ userId = leader.UserId, name = (leader.DisplayName ~= "" and leader.DisplayName or leader.Name) },
		}
	end
	if #memberRows == 0 then
		return
	end
	local leaderUserId = PartyService.GetLeaderUserId(leader)
	if leaderUserId ~= nil and leaderUserId ~= leader.UserId then
		return -- defensive; onPortalTouched already filters to leaders only
	end
	-- Refuse to start a new instance if any intended member is already tracked in
	-- another one (prompting or mid-run elsewhere) -- onPortalTouched only checks the
	-- toucher, not the rest of the party, so without this a stale party member would get
	-- silently overwritten into this new instance, orphaning whatever they were already in.
	for _, row in ipairs(memberRows) do
		if playerToInstance[row.userId] then
			return
		end
	end

	local instanceId = HttpService:GenerateGUID(false)
	local instance = {
		instanceId = instanceId,
		tier = tier,
		numericTier = cfg.NumericTier,
		dungeonName = cfg.DungeonName,
		keyItemId = cfg.KeyItemId,
		realmTemplateName = cfg.RealmTemplateName,
		encounterId = cfg.EncounterId,
		leaderUserId = leader.UserId,
		members = {},
		statuses = {},
		state = DungeonTypes.State.PROMPTING,
		memberUserIds = {},
	}

	local missingNames = {}
	for _, row in ipairs(memberRows) do
		table.insert(instance.memberUserIds, row.userId)
		instance.members[row.userId] = row.name
		local plr = Players:GetPlayerByUserId(row.userId)
		local hasKey = plr and DungeonProfile.CountItemId(plr, cfg.KeyItemId) >= 1
		if hasKey then
			instance.statuses[row.userId] = DungeonTypes.MemberStatus.WAITING
		else
			instance.statuses[row.userId] = DungeonTypes.MemberStatus.MISSING_KEY
			table.insert(missingNames, row.name)
		end
	end

	local blocked = #missingNames > 0
	local blockedReason = ""
	if blocked then
		if #missingNames == 1 then
			blockedReason = missingNames[1] .. " is missing dungeon key. Cannot start the dungeon."
		else
			blockedReason = table.concat(missingNames, ", ") .. " are missing dungeon key. Cannot start the dungeon."
		end
	end

	local payload = buildPromptPayload(instance, blocked, blockedReason)
	fireToAllMembers(instance, DungeonReadyPrompt, payload)

	if blocked then
		-- Transient / informational only: don't hold the party hostage to a pending
		-- instance while someone goes to buy fragments. The leader can just walk back into
		-- the portal once everyone has a key.
		return
	end

	activeInstances[instanceId] = instance
	for userId in pairs(instance.members) do
		playerToInstance[userId] = instanceId
	end
end

----------------------------------------------------------------------
-- Prompt responses
----------------------------------------------------------------------

DungeonPromptRespond.OnServerEvent:Connect(function(player, instanceId, accepted)
	if type(instanceId) ~= "string" then
		return
	end
	local instance = activeInstances[instanceId]
	if not instance or instance.state ~= DungeonTypes.State.PROMPTING then
		return
	end
	if playerToInstance[player.UserId] ~= instanceId then
		return
	end
	if instance.statuses[player.UserId] == DungeonTypes.MemberStatus.MISSING_KEY then
		return -- can't accept without a key; the prompt already told them so
	end

	if accepted then
		instance.statuses[player.UserId] = DungeonTypes.MemberStatus.ACCEPTED
	else
		instance.statuses[player.UserId] = DungeonTypes.MemberStatus.REJECTED
		local name = instance.members[player.UserId] or player.Name
		cancelInstance(instance, name .. " declined. Dungeon entry cancelled.")
		return
	end

	fireToAllMembers(instance, DungeonPromptStatusUpdate, buildPromptPayload(instance, false, ""))

	local accCount, total = acceptanceCounts(instance)
	if accCount == total and total > 0 then
		launchDungeon(instance)
	end
end)

----------------------------------------------------------------------
-- Leave Dungeon (removes only the requesting player)
----------------------------------------------------------------------

local function removePlayerFromInstance(player, teleportOut)
	local instanceId = playerToInstance[player.UserId]
	if not instanceId then
		return
	end
	local instance = activeInstances[instanceId]
	playerToInstance[player.UserId] = nil
	if not instance then
		return
	end
	if instance.state == DungeonTypes.State.PROMPTING then
		-- Leaving mid-prompt (before launch) is equivalent to declining -- cancel the
		-- whole pending instance rather than clearing just this player's mapping and
		-- leaving a stale, half-updated instance nothing else ever tears down.
		cancelInstance(instance, (instance.members[player.UserId] or player.Name) .. " left. Dungeon entry cancelled.")
		return
	end
	if instance.state ~= DungeonTypes.State.IN_PROGRESS then
		return
	end
	if instance.encounterId == "Miasma" then
		local ok, service = pcall(require, ServerScriptService:WaitForChild("MiasmaEncounterService", 2))
		if ok and service and service.RemovePlayer then pcall(service.RemovePlayer, player) end
	end
	pcall(releaseMember, player, "DungeonLeft")

	local leftName = instance.members[player.UserId] or player.Name
	instance.members[player.UserId] = nil
	instance.statuses[player.UserId] = nil

	if teleportOut then
		InventoryAudit.Note(player, "left the dungeon (Leave)")
		-- Walking out ends THEIR run now ("left": DungeonScoreService's leave retention). Without
		-- this the run stayed open and was cashed out whenever the instance finished, at the
		-- party's outcome (a later clear paid the leaver in full). A no-op after a clear.
		local okRun, runSvc = pcall(require, ServerScriptService:WaitForChild("DungeonRunService", 5))
		if okRun and runSvc and runSvc.EndRunFor then pcall(runSvc.EndRunFor, player, "left") end
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			char:PivotTo(HearthstoneService.GetHearthstoneLocation(player))
		end
		DungeonInstanceStateUpdate:FireClient(player, { instanceId = instanceId, state = DungeonTypes.State.ENDED })
	end

	local remaining = 0
	for _ in pairs(instance.members) do
		remaining += 1
	end

	if remaining <= 0 then
		finishInstance(instance, "failed", "NoPlayersRemaining")
	else
		fireToAllMembers(instance, DungeonInstanceStateUpdate, {
			instanceId = instanceId,
			state = DungeonTypes.State.IN_PROGRESS,
			dungeonName = instance.dungeonName,
			tier = instance.tier,
			startTime = instance.startTime,
			memberLeftName = leftName,
		})
	end
end

-- True when this character stands in the realm strip (every live realm is parked at
-- X >= REALM_BASE_X, far from the overworld).
local function isInRealmArea(player)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	return hrp ~= nil and hrp.Position.X > REALM_BASE_X - 2000
end

DungeonLeaveRequest.OnServerEvent:Connect(function(player)
	if not playerToInstance[player.UserId] then
		-- No run on record, yet still standing in a realm (a run that ended without sending
		-- them home): Leave must still work, or they're stuck. Only from inside the realm strip,
		-- so this is never a free hearthstone from the overworld.
		if isSpectating(player) then endSpectating(player); return end
		if isInRealmArea(player) then
			InventoryAudit.Note(player, "left a realm with no active run (stuck escape)")
			pcall(releaseMember, player, "DungeonLeft")
			player.Character:PivotTo(HearthstoneService.GetHearthstoneLocation(player))
		end
		return
	end
	if isSpectating(player) then
		-- Their run already ended when they died; just take them out and respawn them home.
		local instanceId = playerToInstance[player.UserId]
		removePlayerFromInstance(player, false)
		if instanceId then
			DungeonInstanceStateUpdate:FireClient(player, { instanceId = instanceId, state = DungeonTypes.State.ENDED })
		end
		endSpectating(player)
		return
	end
	removePlayerFromInstance(player, true)
end)

-- Absence watchdog: a member who got out of the realm by any means other than Leave (a
-- hearthstone, a dev teleport, falling out of the world) for ABSENT_STRIKES seconds has left the
-- run: taken out of the instance and the encounter, their run ended as "left", HUD told ENDED.
-- Without this they stayed a member, and the encounter kept poisoning and targeting them in the
-- overworld. Spectators (parked above the realm) and the dead are skipped.
local ABSENT_DISTANCE = 3000 -- studs from the realm pivot (realms are parked ~100k studs apart)
local ABSENT_STRIKES = 3     -- consecutive one-second checks
local absentStrikes = {}     -- [userId] = n
task.spawn(function()
	while true do
		task.wait(1)
		for _, instance in pairs(activeInstances) do
			local realm = instance.realmModel
			if instance.state == DungeonTypes.State.IN_PROGRESS and realm and realm.Parent then
				local centre = realm:GetPivot().Position
				for userId in pairs(instance.members) do
					local plr = Players:GetPlayerByUserId(userId)
					local char = plr and plr.Character
					local hum = char and char:FindFirstChildOfClass("Humanoid")
					local root = char and char:FindFirstChild("HumanoidRootPart")
					if plr and root and hum and hum.Health > 0 and not isSpectating(plr)
						and (root.Position - centre).Magnitude > ABSENT_DISTANCE then
						absentStrikes[userId] = (absentStrikes[userId] or 0) + 1
						if absentStrikes[userId] >= ABSENT_STRIKES then
							absentStrikes[userId] = nil
							InventoryAudit.Note(plr, "left the dungeon (outside the realm)")
							local instanceId = playerToInstance[userId]
							removePlayerFromInstance(plr, false)
							local okRun, runSvc = pcall(require, ServerScriptService:WaitForChild("DungeonRunService", 5))
							if okRun and runSvc and runSvc.EndRunFor then pcall(runSvc.EndRunFor, plr, "left") end
							if instanceId then
								DungeonInstanceStateUpdate:FireClient(plr, { instanceId = instanceId, state = DungeonTypes.State.ENDED })
							end
						end
					else
						absentStrikes[userId] = nil
					end
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	player:SetAttribute(SPECTATE_ATTR, nil)
	local instanceId = playerToInstance[player.UserId]
	if not instanceId then
		return
	end
	local instance = activeInstances[instanceId]
	if instance and instance.state == DungeonTypes.State.PROMPTING then
		cancelInstance(instance, (instance.members[player.UserId] or player.Name) .. " left the game. Dungeon entry cancelled.")
		return
	end
	removePlayerFromInstance(player, false)
end)

----------------------------------------------------------------------
-- Mid-run character loss while still connected (death, fall damage, and
-- eventually combat once loot/mobs land in a dungeon) -- distinct from
-- PlayerRemoving (disconnect) above and DungeonLeaveRequest (the explicit
-- Leave Dungeon button). Without this, a respawn mid-run leaves a stale
-- playerToInstance/activeInstances entry AND a stuck client HUD, since
-- nothing else ever sends that client the ENDED state it's waiting for.
----------------------------------------------------------------------

local function onCharacterRemoving(player)
	local instanceId = playerToInstance[player.UserId]
	if not instanceId then
		return
	end
	if player:GetAttribute(SPECTATE_ATTR) == instanceId then
		-- Died in the boss fight: stays in the run as a spectator. The next body is parked.
		local instance = activeInstances[instanceId]
		local conn
		conn = player.CharacterAdded:Connect(function(char)
			conn:Disconnect()
			if instance and player:GetAttribute(SPECTATE_ATTR) == instanceId then
				parkSpectatorBody(player, instance, char)
			end
		end)
		return
	end
	local instance = activeInstances[instanceId]
	if not instance or instance.state ~= DungeonTypes.State.IN_PROGRESS then
		-- PROMPTING is handled by whatever caused the removal (PlayerRemoving above
		-- already covers the disconnect case); nothing else to do here.
		return
	end

	removePlayerFromInstance(player, false)
	-- teleportOut=false above skips the CFrame move (there's no valid character to move
	-- mid-removal), but unlike the disconnect path this player is still connected, so
	-- their client's HUD still needs the explicit ENDED signal or it stays stuck on screen.
	DungeonInstanceStateUpdate:FireClient(player, { instanceId = instanceId, state = DungeonTypes.State.ENDED })

	-- Land them at their hearthstone once their next character spawns (matching the normal
	-- Leave Dungeon destination) instead of wherever the engine's default respawn puts them.
	local conn
	conn = player.CharacterAdded:Connect(function(char)
		if conn then
			conn:Disconnect()
		end
		local hrp = char:WaitForChild("HumanoidRootPart", 5)
		if hrp then
			hrp.CFrame = HearthstoneService.GetHearthstoneLocation(player)
		end
	end)
end

local function hookCharacterRemoving(player)
	player.CharacterRemoving:Connect(function()
		onCharacterRemoving(player)
	end)
end
for _, player in ipairs(Players:GetPlayers()) do
	hookCharacterRemoving(player)
end
Players.PlayerAdded:Connect(hookCharacterRemoving)

----------------------------------------------------------------------
-- Portal detection -- EVENT-DRIVEN ONLY (BasePart.Touched + CollectionService signals).
-- No RunService.Heartbeat/Stepped proximity polling anywhere in this file.
----------------------------------------------------------------------

local TOUCH_COOLDOWN = 3
local lastPortalTouch = {} -- [userId] = os.clock()

local function onPortalTouched(portalPart, hit)
	local char = hit and hit.Parent
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	local player = Players:GetPlayerFromCharacter(char)
	if not player then
		return
	end

	local now = os.clock()
	if now - (lastPortalTouch[player.UserId] or 0) < TOUCH_COOLDOWN then
		return
	end
	lastPortalTouch[player.UserId] = now

	if playerToInstance[player.UserId] then
		return -- already prompting or already in a run
	end
	-- Gate: if the toucher is in a party, only the leader's touch triggers the
	-- ready-check. A player with no party at all is solo -- trivially their own
	-- leader -- and is always allowed to enter (per spec: "whether by themselves,
	-- or in a party"). PartyService.GetLeaderUserId returns nil for a soloist,
	-- so only block when they ARE in a party and AREN'T its leader.
	local leaderUserId = PartyService.GetLeaderUserId(player)
	if leaderUserId ~= nil and leaderUserId ~= player.UserId then
		return -- in a party, but not the leader
	end

	local tier = portalPart:GetAttribute("DungeonTier")
	local cfg = type(tier) == "string" and DungeonPortalConfig.Get(tier)
	if not cfg then
		return
	end

	initiateDungeon(player, tier, cfg)
end

local function hookPortal(inst)
	if not inst:IsA("BasePart") then
		return
	end
	inst.Touched:Connect(function(hit)
		onPortalTouched(inst, hit)
	end)
end

for _, inst in ipairs(CollectionService:GetTagged("DungeonPortal")) do
	hookPortal(inst)
end
CollectionService:GetInstanceAddedSignal("DungeonPortal"):Connect(hookPortal)

----------------------------------------------------------------------
-- Boot
----------------------------------------------------------------------

for tier, cfg in pairs(DungeonPortalConfig.Tiers) do
	if cfg.RealmTemplateName and not ensureRealmTemplate(cfg.RealmTemplateName) then
		warn(("[DungeonInstanceService] %s (%s) cannot launch until its realm template exists")
			:format(tier, cfg.DungeonName))
	end
end
ensurePlaceholderPortal()

Players.PlayerRemoving:Connect(function(player)
	lastPortalTouch[player.UserId] = nil
end)

print("[DungeonInstanceService] ready")

-- Called by DeathLootService (the one Humanoid.Died hook) on every player death. During a live
-- boss encounter: poison wiped, and the player becomes a spectator instead of leaving the run.
function DungeonInstanceService.OnPlayerDied(player)
	local instanceId = playerToInstance[player.UserId]
	local instance = instanceId and activeInstances[instanceId]
	if not instance or instance.state ~= DungeonTypes.State.IN_PROGRESS or not instance.members[player.UserId] then
		return
	end
	local controller = instance.encounterController
	if not controller or controller.Finished then return end
	local ok, service = pcall(require, ServerScriptService:WaitForChild("MiasmaEncounterService", 2))
	if ok and service and service.OnPlayerDied then pcall(service.OnPlayerDied, player) end
	player:SetAttribute(SPECTATE_ATTR, instanceId)
	player.ReplicationFocus = realmFocusPart(instance)
	DungeonSpectate:FireClient(player, {
		active = true,
		instanceId = instanceId,
		memberUserIds = instance.memberUserIds,
	})
end

function DungeonInstanceService.IsSpectating(player)
	return isSpectating(player)
end

return DungeonInstanceService
