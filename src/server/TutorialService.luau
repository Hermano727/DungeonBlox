--[[
	TutorialService (server)

	Runs the tutorial for every player whose profile.flags.tutorial.done is false (new players).
	It is the only thing that advances that flag.

	  - On join: their private copy of the tutorial area (TutorialInstanceService), placed at the
	    current step's checkpoint (the loading screen holds while the player attribute
	    SpawnPending is set), then that step starts.
	  - Steps (TutorialSteps, server data + logic) run in order. Each has an objective line, an
	    optional arrow target and key hints for the client, an enter() that sets things up
	    (mobs, scripted outcomes via ScriptedRigs) and a done() checked four times a second.
	    The step id is saved as it advances, so a rejoin resumes there.
	  - The client (TutorialClient) only draws what it's told (GameEvents/TutorialState) and can
	    say two things back (GameEvents/TutorialAck): "send me the state" and "I've read this"
	    (for spotlight steps, matched to the step's one-time token). Neither can skip a step that
	    isn't waiting on it, and neither touches rewards: those are ScriptedRigs, server only.
	  - Finishing (leaving the copy by hearthstone): flags.tutorial.done = true, rigs cleared,
	    the copy destroyed.

	Dev (F8 Profile tab, admin only): Reset, Skip, JumpTo(stepId).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileService = require(ServerScriptService:WaitForChild("ProfileService"))
local ScriptedRigs = require(ServerScriptService:WaitForChild("ScriptedRigs"))
local Instances = require(ServerScriptService:WaitForChild("TutorialInstanceService"))
local Steps = require(ServerScriptService:WaitForChild("TutorialSteps"))
local RemoteUtils = require(ReplicatedStorage:WaitForChild("RemoteUtils"))

local gameEvents = RemoteUtils.EnsureFolder(ReplicatedStorage, "GameEvents")
local stateEvent = RemoteUtils.EnsureRemoteEvent(gameEvents, "TutorialState")
local ackEvent = RemoteUtils.EnsureRemoteEvent(gameEvents, "TutorialAck")

local CHECK_EVERY = 0.25

local TutorialService = {}

local runs = {} -- [userId] = { player, stepIndex, ctx, token, acked, startedAt }

local function stepIndexOf(id)
	for i, step in ipairs(Steps.List) do
		if step.id == id then return i end
	end
	return nil
end

local function profileOf(player)
	return ProfileService.Get(player)
end

local function tutorialFlag(player)
	local profile = profileOf(player)
	return profile and type(profile.flags) == "table" and profile.flags.tutorial or nil
end

-- What the client draws for the current step.
local function sendState(run)
	local step = Steps.List[run.stepIndex]
	if not step then return end
	local arrow = nil
	if step.arrow then
		local target = type(step.arrow) == "function" and step.arrow(run.ctx) or Instances.Marker(run.player, step.arrow)
		arrow = typeof(target) == "Instance" and target:IsA("BasePart") and target.Position or (typeof(target) == "Vector3" and target or nil)
	end
	local highlight = nil
	if step.highlight then
		local ok, target = pcall(function()
			return type(step.highlight) == "function" and step.highlight(run.ctx) or Instances.Find(run.player, step.highlight)
		end)
		highlight = ok and typeof(target) == "Instance" and target or nil
	end
	local focus = step.focus
	if type(focus) == "function" then
		local ok, value = pcall(focus, run.ctx)
		focus = ok and value or nil
	end
	local objective = step.objective
	if type(objective) == "function" then
		local ok, value = pcall(objective, run.ctx)
		objective = ok and value or ""
	end
	stateEvent:FireClient(run.player, {
		stepId = step.id,
		objective = objective,
		arrow = arrow,
		highlight = highlight,
		highlightName = type(step.highlight) == "string" and step.highlight or nil, -- not streamed in yet: the client finds it by name
		hints = step.hints,
		focus = (type(focus) == "string" or type(focus) == "table") and focus or nil,
		spotlight = step.spotlight,
		cutscene = step.cutscene,
		token = run.token,
		waitForAck = step.waitForAck == true,
		ackOnClick = step.ackOnClick == true,
	})
end

-- Where this step resumes from (its checkpoint marker, else the copy's spawn point).
local function checkpointFor(player, step)
	local marker = step and step.checkpoint and Instances.Marker(player, step.checkpoint)
	return marker and marker.CFrame or Instances.SpawnCFrame(player)
end

local function enterStep(run, index)
	local player = run.player
	local step = Steps.List[index]
	run.stepIndex = index
	run.token = math.random(1, 2 ^ 30)
	run.acked = false
	run.startedAt = os.clock()
	run.ctx = {
		player = player,
		instances = Instances,
		rigs = ScriptedRigs,
		profile = function() return profileOf(player) end,
		marker = function(name) return Instances.Marker(player, name) end,
		spawnMob = function(markerName, mobId, level, opts) return Instances.SpawnMob(player, markerName, mobId, level, opts) end,
		elapsed = function() return os.clock() - run.startedAt end,
		acked = function() return run.acked end,
		refresh = function() sendState(run) end, -- re-send (the arrow / focus changed)
		state = {}, -- per-step scratch (the mob it spawned, counters)
		shared = run.shared, -- across steps, this session (the slime from the last step)
		-- across steps AND rejoins: saved on the tutorial flag (the sword's uuid, ...)
		data = function()
			local flag = tutorialFlag(player)
			if not flag then return {} end
			flag.data = type(flag.data) == "table" and flag.data or {}
			return flag.data
		end,
	}
	local flag = tutorialFlag(player)
	if flag then flag.step = step.id end
	-- Respawning mid-tutorial brings them back to this step's checkpoint (RespawnCheckpoint).
	player:SetAttribute("RespawnAt", checkpointFor(player, step))
	if step.enter then
		local ok, err = pcall(step.enter, run.ctx)
		if not ok then warn(("[TutorialService] step %s enter failed: %s"):format(step.id, tostring(err))) end
	end
	-- A spotlight pauses the fight: the copy's mobs freeze until the player clicks past it.
	Instances.PauseMobs(player, step.spotlight ~= nil and step.waitForAck == true)
	sendState(run)
end

-- Re-send the state (a step whose arrow / focus moved, e.g. to a fresh drop).
function TutorialService.Refresh(player)
	local run = runs[player.UserId]
	if run then sendState(run) end
end

local function finish(run)
	local player = run.player
	runs[player.UserId] = nil
	local flag = tutorialFlag(player)
	if flag then
		flag.done = true
		flag.step = "done"
	end
	ScriptedRigs.Clear(player)
	player:SetAttribute("RespawnAt", nil)
	player:SetAttribute("RegenPaused", nil)
	Instances.Destroy(player)
	ProfileService.PushProfile(player)
	stateEvent:FireClient(player, { done = true })
end

local function advance(run)
	local nextIndex = run.stepIndex + 1
	if nextIndex > #Steps.List then
		finish(run)
	else
		enterStep(run, nextIndex)
		ProfileService.PushProfile(run.player)
	end
end

-- Puts the player into their copy at the current step and starts it.
local function begin(player)
	if not ScriptedRigs.TutorialActive(player) or runs[player.UserId] then return end
	player:SetAttribute("SpawnPending", true)
	local inst = Instances.Ensure(player)
	if not inst then
		player:SetAttribute("SpawnPending", nil)
		return
	end
	local flag = tutorialFlag(player)
	local index = stepIndexOf(flag and flag.step) or 1
	local run = { player = player, shared = {} }
	runs[player.UserId] = run
	local spot = checkpointFor(player, Steps.List[index])
	player:SetAttribute("RespawnAt", spot)
	pcall(function() player:RequestStreamAroundAsync(spot.Position, 10) end)
	local character = player.Character or player.CharacterAdded:Wait()
	local root = character:WaitForChild("HumanoidRootPart", 15)
	if root then character:PivotTo(spot + Vector3.new(0, 3, 0)) end
	player:SetAttribute("SpawnPending", nil)
	enterStep(run, index)
end

local function onPlayerAdded(player)
	-- Wait for the profile (ProfileBootstrap loads it on join).
	local deadline = os.clock() + 30
	while player.Parent and not profileOf(player) and os.clock() < deadline do task.wait(0.2) end
	if player.Parent and profileOf(player) then
		begin(player)
	end
end

Players.PlayerAdded:Connect(function(player) task.spawn(onPlayerAdded, player) end)
for _, player in ipairs(Players:GetPlayers()) do task.spawn(onPlayerAdded, player) end
Players.PlayerRemoving:Connect(function(player) runs[player.UserId] = nil end)

ackEvent.OnServerEvent:Connect(function(player, kind, token)
	local run = runs[player.UserId]
	if not run then return end
	if kind == "sync" then
		sendState(run)
	elseif kind == "ack" and type(token) == "number" and token == run.token then
		local step = Steps.List[run.stepIndex]
		if step and step.waitForAck then
			run.acked = true
			Instances.PauseMobs(player, false)
		end
	end
end)

local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < CHECK_EVERY then return end
	acc = 0
	for _, run in pairs(runs) do
		local step = Steps.List[run.stepIndex]
		if step and run.player.Parent then
			local ok, done = pcall(step.done, run.ctx)
			if ok and done then
				advance(run)
			elseif not ok then
				warn(("[TutorialService] step %s check failed: %s"):format(step.id, tostring(done)))
			end
		end
	end
end)

---------------------------------------------------------------------------
-- Dev (admin-gated by the caller, ProfileBootstrap's DevProfileAction)
---------------------------------------------------------------------------

-- Start over as a brand-new player: the whole profile is wiped (ProfileService.WipeProfile:
-- items, coins, skills, map, Hearthstone locked) and the tutorial begins in a fresh copy.
function TutorialService.Reset(player)
	if not profileOf(player) then return false, "no_profile" end
	runs[player.UserId] = nil
	ScriptedRigs.Clear(player)
	Instances.Destroy(player)
	player:SetAttribute("RegenPaused", nil)
	local ok, err = ProfileService.WipeProfile(player, "tutorial reset")
	if not ok then return false, err end
	task.spawn(begin, player)
	return true
end

-- End it now (marked done, copy gone) and send them to their hearthstone town.
function TutorialService.Skip(player)
	local run = runs[player.UserId]
	if run then
		finish(run)
	else
		local flag = tutorialFlag(player)
		if flag then flag.done = true; flag.step = "done" end
		Instances.Destroy(player)
	end
	local profile = profileOf(player)
	if profile then profile.flags.hearthstoneUnlocked = true end
	ProfileService.PushProfile(player)
	local okSvc, Hearth = pcall(require, ServerScriptService:WaitForChild("HearthstoneService"))
	local spot = okSvc and Hearth.GetHearthstoneLocation and Hearth.GetHearthstoneLocation(player)
	if typeof(spot) == "CFrame" and player.Character then player.Character:PivotTo(spot) end
	return true
end

-- Jump to a step (by id), from its checkpoint.
function TutorialService.JumpTo(player, stepId)
	local index = stepIndexOf(stepId)
	if not index then return false, "unknown_step" end
	local run = runs[player.UserId]
	if not run then
		local flag = tutorialFlag(player)
		if not flag or flag.done then return false, "not_in_tutorial" end
		flag.step = stepId
		task.spawn(begin, player)
		return true
	end
	ScriptedRigs.Clear(player)
	local spot = checkpointFor(player, Steps.List[index])
	if player.Character then player.Character:PivotTo(spot + Vector3.new(0, 3, 0)) end
	enterStep(run, index)
	return true
end

function TutorialService.StepIds()
	local ids = {}
	for _, step in ipairs(Steps.List) do table.insert(ids, step.id) end
	return ids
end

return TutorialService
