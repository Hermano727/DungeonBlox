-- Animate2 (LocalScript) - Custom skinned-rig locomotion state machine
-- Place in StarterPlayer > StarterCharacterScripts
--
-- Profile-driven state machine (Idle / Walk / RunStart / RunLoop) for the
-- 52-bone skinned-mesh player rig (Hero_Character -- see
-- CharacterAnimProfiles.lua). Each state swaps between an Unarmed and an
-- Armed (weapon-specific) track pair depending on whether a Tool is
-- currently equipped (CharacterAnimProfiles.GetProfileForTool). Missing
-- clips (jump, fall, landing, run-stop -- see CharacterAnimProfiles'
-- header) fall back to holding whatever pose/state was already showing
-- rather than substituting a wrong-rig animation.
--
-- Sprint input, FOV tweening, crouch gating, and backwards-walk detection
-- don't depend on rig body-part names, so the animation *selection* below
-- is the only thing that changed for the new rig.

local Figure = script.Parent

-- Delete the default Animate script (unchanged from before)
local defaultAnimate = Figure:FindFirstChild("Animate")
if defaultAnimate then
	defaultAnimate:Destroy()
end
Figure.ChildAdded:Connect(function(child)
	if child.Name == "Animate" and child:IsA("LocalScript") then child:Destroy() end
end)

local Humanoid = Figure:WaitForChild("Humanoid")
local HumanoidRootPart = Figure:WaitForChild("HumanoidRootPart")

-- Destroying the default Animate script above does NOT stop any
-- AnimationTracks it already started playing -- tracks live on the
-- Animator and outlive the script that created them. Stop anything
-- already playing before we take over (unchanged from before).
local function stopOrphanedTracks()
	local existingAnimator = Humanoid:FindFirstChildOfClass("Animator")
	if existingAnimator then
		for _, track in ipairs(existingAnimator:GetPlayingAnimationTracks()) do
			track:Stop(0)
		end
	end
end
stopOrphanedTracks()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")
local camera = workspace.CurrentCamera
local VideoSettings = require(ReplicatedStorage:WaitForChild("VideoSettings"))
local function defaultFOV()
	return VideoSettings.fov
end
local fovTween

local EnergyEvents = ReplicatedStorage:WaitForChild("EnergyEvents")
local RequestSprint = EnergyEvents:WaitForChild("RequestSprint")
local EnergyChanged = EnergyEvents:WaitForChild("EnergyChanged")

local CharacterAnimProfiles = require(ReplicatedStorage:WaitForChild("CharacterAnimProfiles"))
local ActiveEquipment = require(ReplicatedStorage:WaitForChild("ActiveEquipment"))

-- ============================================
-- SPEED / RUNNING CONFIGURATION (unchanged from before)
-- ============================================
local WALK_ANIM_SPEED = 1.0
local WALK_SPEED_SCALE = 8.7
local BACKWARDS_WALK_SPEED = 1.0

local isRunning = false

local FOV_TWEEN_TIME = 0.5
local RUN_FOV_BOOST = 15

local function IsCrouching()
	if HumanoidRootPart then
		return HumanoidRootPart:GetAttribute("IsCrouching") == true
	end
	return false
end

local function tweenFOV(targetFOV)
	if fovTween then
		fovTween:Cancel()
	end
	local tweenInfo = TweenInfo.new(FOV_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	fovTween = TweenService:Create(camera, tweenInfo, { FieldOfView = targetFOV })
	fovTween:Play()
end

-- ============================================
-- ANIMATOR / TRACK LOADING
-- ============================================
-- Wait for the template's replicated Animator; a client-created fallback
-- would not give observers the same animation owner.
local animator = Humanoid:WaitForChild("Animator")

-- {profileName -> {Walk=track, RunStart=track, RunLoop=track}}, built
-- lazily per profile the first time it's needed.
local trackCache = {}

local function loadTrack(id)
	if not id then
		return nil
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if not ok then
		warn("[Animate2] Failed to load animation", id, track)
		return nil
	end
	-- Fetch in the background. LoadAnimation can return a track before its
	-- clip is available; transitions below also wait for a nonzero Length.
	task.spawn(function()
		local loaded, err = pcall(function() ContentProvider:PreloadAsync({ anim }) end)
		if not loaded then warn("[Animate2] Animation preload failed", id, err) end
	end)
	return track
end

local function getProfileTracks(profileName)
	local cached = trackCache[profileName]
	if cached then
		return cached
	end

	local cfg = CharacterAnimProfiles.Profiles[profileName]
	if not cfg then
		return nil
	end

	local tracks = {}
	tracks.Idle = loadTrack(cfg.Idle)
	tracks.Walk = loadTrack(cfg.Walk)
	tracks.RunStart = loadTrack(cfg.RunStart)
	tracks.RunLoop = loadTrack(cfg.RunLoop)

	if tracks.Idle then
		tracks.Idle.Priority = Enum.AnimationPriority.Core
		tracks.Idle.Looped = true
	end
	if tracks.Walk then
		tracks.Walk.Priority = Enum.AnimationPriority.Core
		tracks.Walk.Looped = true
	end
	if tracks.RunLoop then
		tracks.RunLoop.Priority = Enum.AnimationPriority.Core
		tracks.RunLoop.Looped = true
	end
	if tracks.RunStart then
		tracks.RunStart.Priority = Enum.AnimationPriority.Core
		tracks.RunStart.Looped = false
	end

	trackCache[profileName] = tracks
	return tracks
end

-- ============================================
-- STATE MACHINE -- "Idle" | "Walk" | "RunStart" | "RunLoop"
-- ============================================
local currentState = "Idle"
local currentTrack = nil
local playingState = nil
local currentProfileName = "Unarmed"
local runStartFinishedConn = nil
local pendingTrackConn = nil
local trackGeneration = 0
local walkPlaybackSpeed = 1
local locomotionSpeed = 0

local function resolveProfileName()
	local tool = ActiveEquipment.GetTool(Figure)
	return CharacterAnimProfiles.GetProfileForTool(tool)
end

local function cancelTransition()
	trackGeneration += 1
	if pendingTrackConn then
		pendingTrackConn:Disconnect()
		pendingTrackConn = nil
	end
	if runStartFinishedConn then
		runStartFinishedConn:Disconnect()
		runStartFinishedConn = nil
	end
end

local function stopCurrentTrack(fadeTime)
	cancelTransition()
	if currentTrack then
		currentTrack:Stop(fadeTime or 0.15)
	end
	currentTrack = nil
	playingState = nil
end

-- Plays `stateName`'s track for the current profile. If `preservePhase` is
-- true and a track was already playing, seeks the new track to the same
-- normalized (0-1) position instead of starting from 0 -- used for
-- armed/unarmed swaps mid-stride and mid-acceleration so equip/unequip
-- never restarts RunStart's burst or resets Walk's foot cycle.
local function playState(stateName, fadeTime, preservePhase)
	cancelTransition()
	local generation = trackGeneration
	local profileName = currentProfileName
	currentState = stateName
	local tracks = getProfileTracks(currentProfileName)
	local track = tracks and tracks[stateName]

	local function startReadyTrack()
		if generation ~= trackGeneration or Humanoid.Health <= 0 or not Figure.Parent then return end
		if pendingTrackConn then pendingTrackConn:Disconnect(); pendingTrackConn = nil end
		local previousTrack = currentTrack
		local previousPhase
		if preservePhase and playingState == stateName and previousTrack and previousTrack.Length > 0 then
			previousPhase = previousTrack.TimePosition / previousTrack.Length
		end
		-- Read the latest gait speed, including movement changes while loading.
		local playbackSpeed = stateName == "Walk" and walkPlaybackSpeed or 1
		if track.IsPlaying then
			-- A quick toggle can return to a track that is still fading out.
			-- Bring its existing weight back instead of restarting from zero.
			track:AdjustWeight(1, fadeTime or 0.15)
			track:AdjustSpeed(playbackSpeed)
		else
			-- Start the loaded replacement BEFORE fading the outgoing pose.
			track:Play(fadeTime or 0.15, 1, playbackSpeed)
		end
		if previousPhase then track.TimePosition = previousPhase * track.Length end
		if previousTrack and previousTrack ~= track then previousTrack:Stop(fadeTime or 0.15) end
		currentTrack = track
		playingState = stateName
		Figure:SetAttribute("LocomotionProfile", profileName)
		Figure:SetAttribute("LocomotionState", stateName)
		Figure:SetAttribute("LocomotionPlaybackSpeed", playbackSpeed)
		Figure:SetAttribute("LocomotionTransitionStatus", "Ready")
		if stateName == "RunStart" then
			runStartFinishedConn = track.Stopped:Connect(function()
				if generation == trackGeneration and currentTrack == track
					and currentState == "RunStart" and isRunning and locomotionSpeed > 0.01 then
					playState("RunLoop", 0)
				end
			end)
		end
	end

	if track and track.Length > 0 then
		startReadyTrack()
		return
	end
	-- Keep looped idle/walk playing while the next clip loads. A one-shot
	-- must hold its current pose instead of finishing and exposing the rest pose.
	if currentTrack and not currentTrack.Looped then
		if currentTrack.IsPlaying then
			currentTrack:AdjustSpeed(0)
		elseif currentTrack.Length > 0 then
			-- RunStart can request RunLoop from its natural Stopped event.
			-- Keep its final pose if that next clip has not loaded yet.
			currentTrack:Play(0, 1, 0)
			currentTrack.TimePosition = math.max(0, currentTrack.Length - 1 / 60)
		end
		Figure:SetAttribute("LocomotionPlaybackSpeed", 0)
	end
	if not track then
		Figure:SetAttribute("LocomotionTransitionStatus", "MissingClip")
		return
	end
	Figure:SetAttribute("LocomotionTransitionStatus", "Loading")
	local startedAt, warned = os.clock(), false
	pendingTrackConn = RunService.Heartbeat:Connect(function()
		if generation ~= trackGeneration then return end
		if track.Length > 0 then
			startReadyTrack()
		elseif not warned and os.clock() - startedAt > 5 then
			warned = true
			warn("[Animate2] Keeping previous pose while waiting for clip", profileName, stateName)
		end
	end)
end

-- Re-resolves the active profile (Unarmed/Sword/...) and, if it changed,
-- swaps the currently-playing state's track to the new profile's
-- equivalent track at the SAME phase -- never restarts Idle/Walk/RunLoop,
-- and never restarts RunStart's acceleration burst. Idle now has real
-- per-profile clips too (armed vs unarmed rest pose), so an equip/unequip
-- while standing still swaps those the same way as any other state.
local function refreshProfile()
	local newProfile = resolveProfileName()
	if newProfile == currentProfileName then
		return
	end
	currentProfileName = newProfile
	playState(currentState, 0.1, true)
end

local stopObservingEquipment = ActiveEquipment.Observe(Figure, refreshProfile)

-- ============================================
-- LOCOMOTION
-- ============================================
local function onRunning(speed)
	if Humanoid.Health <= 0 then return end
	locomotionSpeed = speed
	if speed <= 0.01 then
		if currentState ~= "Idle" then
			playState("Idle", 0.2)
		end
		tweenFOV(defaultFOV())
		return
	end

	local backwards = false
	local velocity = HumanoidRootPart.AssemblyLinearVelocity
	local look = HumanoidRootPart.CFrame.LookVector
	if velocity.Magnitude > 0.1 then
		if velocity.Unit:Dot(look) < -0.1 then
			backwards = true
		end
	end

	if backwards or IsCrouching() then
		-- Never sprint backwards or while crouching -- same rule the old
		-- script enforced.
		tweenFOV(defaultFOV())
		local dirScale = backwards and -1 or 1
		walkPlaybackSpeed = dirScale * (speed / WALK_SPEED_SCALE) * WALK_ANIM_SPEED * BACKWARDS_WALK_SPEED
		if currentState ~= "Walk" then
			playState("Walk", 0.2)
		end
		if currentTrack and playingState == "Walk" then
			currentTrack:AdjustSpeed(walkPlaybackSpeed)
			Figure:SetAttribute("LocomotionPlaybackSpeed", walkPlaybackSpeed)
		end
		return
	end

	if isRunning then
		tweenFOV(defaultFOV() + RUN_FOV_BOOST)
		if currentState == "Idle" or currentState == "Walk" then
			playState("RunStart", 0.15)
		end
		-- else: already RunStart (let it finish -> auto-hands-off to
		-- RunLoop) or already RunLoop (its own authored pace is used as-is,
		-- no per-frame speed scaling needed for a looped cycle).
	else
		tweenFOV(defaultFOV())
		walkPlaybackSpeed = (speed / WALK_SPEED_SCALE) * WALK_ANIM_SPEED
		if currentState ~= "Walk" then
			playState("Walk", 0.2)
		end
		if currentTrack and playingState == "Walk" then
			currentTrack:AdjustSpeed(walkPlaybackSpeed)
			Figure:SetAttribute("LocomotionPlaybackSpeed", walkPlaybackSpeed)
		end
	end
end

local function onDied()
	stopObservingEquipment()
	stopCurrentTrack(0)
end

-- Jump/fall/landing/climb/sit clips were not supplied for this skeleton
-- (see CharacterAnimProfiles.lua) -- deliberately no handlers for those
-- Humanoid states, so the last active locomotion state/track keeps
-- playing straight through a jump or fall instead of snapping to a
-- wrong-rig substitute. Movement itself (Humanoid physics) is entirely
-- unaffected either way.

-- ============================================
-- INPUT HANDLING (unchanged from before)
-- ============================================
local function onInputBegan(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift or input.KeyCode == Enum.KeyCode.ButtonL2 then
		if not isRunning then
			isRunning = true
			RequestSprint:FireServer(true)
			onRunning(locomotionSpeed)
		end
	end
end

local function onInputEnded(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift or input.KeyCode == Enum.KeyCode.ButtonL2 then
		if isRunning then
			isRunning = false
			RequestSprint:FireServer(false)
			onRunning(locomotionSpeed)
		end
	end
end

-- If the server denies/cancels sprint (out of energy, panting, etc.), sync local state
EnergyChanged.OnClientEvent:Connect(function(_, isPanting)
	if isPanting and isRunning then
		isRunning = false
		onRunning(locomotionSpeed)
	end
end)

local function setupInputConnection()
	local player = Players.LocalPlayer
	if player then
		UserInputService = game:GetService("UserInputService")
		if player.Character == Figure or player.CharacterAdded:Wait() == Figure then
			pcall(function()
				UserInputService.InputBegan:Connect(onInputBegan)
				UserInputService.InputEnded:Connect(onInputEnded)
			end)
		end
	end
end

spawn(function()
	wait(1)
	setupInputConnection()
end)

-- ============================================
-- HUMANOID EVENT CONNECTIONS
-- ============================================
Humanoid.Died:Connect(onDied)
script.Destroying:Connect(function()
	stopObservingEquipment()
	stopCurrentTrack(0)
end)
Humanoid.Running:Connect(onRunning)

currentProfileName = resolveProfileName()

-- Humanoid.Running only fires on a movement-state TRANSITION -- a
-- character that spawns already standing still never gets an initial
-- Running(0) call, so without this the mesh would sit in its raw bind
-- pose until the player's first step. Start Idle explicitly instead of
-- waiting on an event that may never come.
playState("Idle", 0)

-- Warm both profiles while idle is playing, reducing first-equip loading.
task.defer(function()
	if Humanoid.Health <= 0 or not Figure.Parent then return end
	for profileName in pairs(CharacterAnimProfiles.Profiles) do getProfileTracks(profileName) end
end)
