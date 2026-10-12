--[[
	MountService -- the horse mount, server side (rewritten 2026-10-11 for the rigged HorseMount).

	Calling it: GameEvents/MountToggle (RemoteFunction, client/MountClient on Keys.Mount, H) ->
	ok, reason. The old saddle-tool path (GameEvents/MountRequest, the saddle Tool's Activate)
	toggles the same way. Rules and numbers: RS/MountConfig.
	  - Allowed when alive, out of combat, not in a dungeon, past the summon cooldown, and the
	    player owns a saddle (the fastest one owned sets the speed).
	  - Combat of any kind throws the rider off and the horse bolts (checked every tick), and so
	    does an arrow from someone allowed to attack the rider (OnMountShot, from BowService).
	  - Death, respawn, leaving, entering a dungeon: the horse goes.

	How it rides: the character keeps its own Humanoid and controls. The horse (a clone of
	ServerStorage.HorseMount, massless, non-colliding, still hittable by rays) is welded under the
	character's root, and the character is lifted (Humanoid.HipHeight) so its hip joints sit
	MountConfig.SEAT_ABOVE_FLOOR above the floor, on the saddle. Speed: the MountSpeed player
	attribute, which EnergyServer turns into WalkSpeed. Jumping is off while mounted. The server
	plays the horse's clips from the rider's speed (Idle / RunStart -> RunLoop, the gallop sped up
	with the speed) and the rider's matching clip on the character (RideIdle / RideStart / RideRun,
	switched and sped together with the horse's, so the rider rides its bob); one Heartbeat for
	every mount.

	Sounds and dust go to nearby clients through GameEvents/MountFx (client/MountClient).
	Player attributes: Mounted (bool), MountSpeed (number), MountReadyAt (server clock, the
	summon cooldown's end) + MountCooldown (its length), for the HUD slot.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local MountConfig = require(ReplicatedStorage:WaitForChild("MountConfig"))
local AlignmentConfig = require(ReplicatedStorage:WaitForChild("AlignmentConfig"))
local AudioCategories = require(ReplicatedStorage:WaitForChild("AudioCategories"))
local RemoteUtils = require(ReplicatedStorage:WaitForChild("RemoteUtils"))
local MountRiderGuiCleanup = require(ReplicatedStorage:WaitForChild("MountRiderGuiCleanup"))
local DungeonProfile = require(ServerScriptService:WaitForChild("ProfileService"))
local CombatStateService = require(ServerScriptService:WaitForChild("CombatStateService"))

local MountService = {}

local FX_RADIUS = 160
local TICK = 0.1
local RATE = 0.25 -- seconds between two toggles from one player

local mounts = {} -- [Player] = { horse, weld, tracks, riderTracks, saved, state, ... }
local lastToggle = {} -- [userId] = os.clock()
local readyAt = {} -- [userId] = workspace:GetServerTimeNow() when the horse can be called again

local gameEvents = RemoteUtils.EnsureFolder(ReplicatedStorage, "GameEvents")
local mountToggle = RemoteUtils.EnsureRemoteFunction(gameEvents, "MountToggle")
local mountRequest = RemoteUtils.EnsureRemoteEvent(gameEvents, "MountRequest") -- the saddle Tool (legacy path)
local riderCleanupRemote = RemoteUtils.EnsureRemoteEvent(gameEvents, "MountRiderCleanup")
local mountFx = RemoteUtils.EnsureRemoteEvent(gameEvents, "MountFx")
local centerFlash = gameEvents:FindFirstChild("CenterFlashNotify")

local function mountFolder()
	return RemoteUtils.EnsureFolder(Workspace, MountConfig.FOLDER_NAME)
end

local function flash(player, text)
	centerFlash = centerFlash or gameEvents:FindFirstChild("CenterFlashNotify")
	if centerFlash then pcall(centerFlash.FireClient, centerFlash, player, text) end
end

-- Sound + dust for everyone near `position`. kind: "summon" | "dismiss" | "thrown" | "idle".
local function fx(kind, position)
	if typeof(position) ~= "Vector3" then return end
	for _, plr in ipairs(Players:GetPlayers()) do
		local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - position).Magnitude <= FX_RADIUS then
			mountFx:FireClient(plr, kind, position)
		end
	end
end

local function rootAndHumanoid(player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	return root, hum, char
end

-- A bone's REST world frame (its own and every ancestor's Bone.CFrame from the mesh part):
-- Bone.WorldCFrame already carries the parent bones' animation while a clip plays.
local function bindWorld(bone)
	local parent = bone.Parent
	local base = parent:IsA("Bone") and bindWorld(parent) or parent.CFrame
	return base * bone.CFrame
end

-- The rider's hip joints above its root part, from the character's own bones (any rig that has a
-- Thigh_L bone), else a plain R15/R6 estimate.
local function hipAboveRoot(char, root)
	local thigh = char:FindFirstChild("Thigh_L", true)
	if thigh and thigh:IsA("Bone") then
		return bindWorld(thigh).Position.Y - root.Position.Y
	end
	local upperLeg = char:FindFirstChild("LeftUpperLeg")
	if upperLeg then return upperLeg.Position.Y + upperLeg.Size.Y / 2 - root.Position.Y end
	return 0
end

local function loadTrack(animator, id, priority, looped)
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
	if not ok or not track then return nil end
	track.Priority = priority
	track.Looped = looped
	return track
end

local function randomIn(range)
	return range.Min + math.random() * (range.Max - range.Min)
end

----------------------------------------------------------------------------------------------
-- Mount / dismount

local function dismount(player, reason)
	local m = mounts[player]
	if not m then return end
	mounts[player] = nil
	local root, hum = rootAndHumanoid(player)
	local position = m.horse.PrimaryPart and m.horse.PrimaryPart.Position
	for _, track in pairs(m.riderTracks or {}) do pcall(function() track:Stop(0.2) end) end
	if hum and hum.Parent and m.humanoid == hum then
		hum.HipHeight = m.saved.hipHeight
		hum.JumpPower = m.saved.jumpPower
		hum.JumpHeight = m.saved.jumpHeight
		-- Set the rider straight down by the lift, so they stand instead of dropping off.
		if root and reason ~= "removed" then
			root.CFrame -= Vector3.new(0, math.max(0, m.rise - 0.1), 0)
		end
	end
	if m.weld then m.weld:Destroy() end
	if m.horse then m.horse:Destroy() end
	player:SetAttribute("Mounted", nil)
	player:SetAttribute("MountSpeed", nil)
	local cooldown = (reason == "combat" or reason == "shot") and MountConfig.THROWN_COOLDOWN or MountConfig.SUMMON_COOLDOWN
	readyAt[player.UserId] = Workspace:GetServerTimeNow() + cooldown
	player:SetAttribute("MountCooldown", cooldown) -- its length, so the HUD fill starts empty
	player:SetAttribute("MountReadyAt", readyAt[player.UserId])
	if reason == "combat" or reason == "shot" then
		fx("thrown", position)
		flash(player, MountConfig.THROWN_MESSAGES[reason])
	elseif reason ~= "removed" then
		fx("dismiss", position)
	end
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if pg then MountRiderGuiCleanup.Clean(pg) end
	pcall(riderCleanupRemote.FireClient, riderCleanupRemote, player)
end

local function canMount(player)
	local root, hum = rootAndHumanoid(player)
	if not root or not hum or hum.Health <= 0 then return false, "no_character" end
	if CombatStateService.IsInCombat(player) then return false, "in_combat" end
	if player:GetAttribute("InDungeon") then return false, "in_dungeon" end
	if Workspace:GetServerTimeNow() < (readyAt[player.UserId] or 0) then return false, "cooldown" end
	if hum.SeatPart then return false, "busy" end
	local profile = DungeonProfile.Get(player)
	local saddle = MountConfig.BestSaddle(profile)
	if not saddle then return false, "no_saddle" end
	if not ServerStorage:FindFirstChild(MountConfig.MODEL_NAME) then return false, "no_horse" end
	return true, saddle
end

local function mount(player)
	local ok, saddle = canMount(player)
	if not ok then return false, saddle end
	local root, hum, char = rootAndHumanoid(player)

	local horse = ServerStorage[MountConfig.MODEL_NAME]:Clone()
	horse.Name = "HorseMount_" .. player.UserId
	horse:SetAttribute("DungeonHorseMount", true)
	horse:SetAttribute("OwnerUserId", player.UserId)
	for _, d in ipairs(horse:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanTouch = false
			d.Massless = true
		end
	end
	local horseRoot = horse.PrimaryPart

	-- Lift the rider so its hips sit on the saddle; the horse's floor stays on the ground.
	local saved = { hipHeight = hum.HipHeight, jumpPower = hum.JumpPower, jumpHeight = hum.JumpHeight }
	local hip = hipAboveRoot(char, root)
	local standing = hum.HipHeight + root.Size.Y / 2         -- root centre above the floor now
	local rise = MountConfig.SEAT_ABOVE_FLOOR - hip - standing
	hum.HipHeight += rise
	hum.JumpPower = 0
	hum.JumpHeight = 0
	local floorY = root.Position.Y - standing
	local yaw = root.CFrame - root.CFrame.Position
	local riderAt = CFrame.new(root.Position.X, floorY + standing + rise, root.Position.Z) * yaw
	root.CFrame = riderAt
	local offset = CFrame.new(MountConfig.SEAT_OFFSET_XZ.X,
		MountConfig.HORSE_CENTRE_ABOVE_FLOOR - (standing + rise), MountConfig.SEAT_OFFSET_XZ.Y)
	horse:PivotTo(riderAt * offset)
	horse.Parent = mountFolder()
	local weld = Instance.new("Weld")
	weld.Name = "MountWeld"
	weld.Part0, weld.Part1 = root, horseRoot
	weld.C0 = offset
	weld.Parent = horseRoot

	local m = {
		horse = horse, weld = weld, humanoid = hum, saved = saved, rise = rise, state = "Idle", runStartedAt = 0,
		nextIdleSound = os.clock() + randomIn(MountConfig.IDLE_SOUND_EVERY), tracks = {},
	}
	local animator = horse:FindFirstChildWhichIsA("Animator", true)
	if animator then
		m.tracks.Idle = loadTrack(animator, MountConfig.Animations.Idle, Enum.AnimationPriority.Idle, true)
		m.tracks.RunStart = loadTrack(animator, MountConfig.Animations.RunStart, Enum.AnimationPriority.Movement, false)
		m.tracks.RunLoop = loadTrack(animator, MountConfig.Animations.RunLoop, Enum.AnimationPriority.Movement, true)
		if m.tracks.Idle then m.tracks.Idle:Play(0) end
	end
	-- The rider's clips mirror the horse's (same lengths, started and sped together in setState).
	-- The idle sits at Action, the run clips one priority up so they fully replace it while playing
	-- (two tracks at one priority would blend), just as the horse's run clips sit over its idle.
	m.riderTracks = {}
	local riderAnimator = hum:FindFirstChildOfClass("Animator")
	if riderAnimator then
		local A = MountConfig.Animations
		m.riderTracks.Idle = loadTrack(riderAnimator, A.RideIdle, Enum.AnimationPriority.Action, true)
		m.riderTracks.RunStart = loadTrack(riderAnimator, A.RideStart, Enum.AnimationPriority.Action2, false)
		m.riderTracks.RunLoop = loadTrack(riderAnimator, A.RideRun, Enum.AnimationPriority.Action2, true)
		if m.riderTracks.Idle then m.riderTracks.Idle:Play(0.15) end
	end
	-- The gallop's hoofbeats, looped on the horse while it runs (silent until a sound is chosen).
	local SoundEffects = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Sounds"):WaitForChild("SoundEffects"))
	local gallopId = SoundEffects[MountConfig.Sounds.Gallop.key]
	if type(gallopId) == "string" and gallopId ~= "" then
		local s = Instance.new("Sound")
		s.Name = "Gallop"
		s.SoundId = gallopId
		s.Looped = true
		s.Volume = 0.25 -- under the rider, so keep it low (2026-10-11: footsteps were too loud)
		s.RollOffMaxDistance = 120
		AudioCategories.Tag(s, "mount") -- the Mount slider (client/SoundRouter applies the group)
		s.Parent = horseRoot
		m.gallop = s
	end

	mounts[player] = m
	player:SetAttribute("Mounted", true)
	player:SetAttribute("MountSpeed", saddle.speed)
	fx("summon", horseRoot.Position)
	return true
end

function MountService.Toggle(player)
	local now = os.clock()
	if now - (lastToggle[player.UserId] or 0) < RATE then return false, "busy" end
	lastToggle[player.UserId] = now
	if mounts[player] then
		dismount(player, "toggle")
		return true, "dismounted"
	end
	return mount(player)
end

-- For existing callers (MobManager calls it the moment a player strikes a mob): in combat that's
-- the rider thrown off (dust, the bolt, the message), otherwise a plain dismount.
function MountService.dismount(player)
	dismount(player, CombatStateService.IsInCombat(player) and "combat" or "toggle")
end

-- Unseat only: with the welded horse there is no separate seat, so this is the same as dismount.
function MountService.unseat(player)
	dismount(player, "toggle")
end

function MountService.IsMounted(player)
	return mounts[player] ~= nil
end

-- BowService: an arrow hit `horseModel`. Throws its rider off when `shooter` may attack them
-- (the same gates as an arrow hitting the rider: alignment and safe zones), and both fight.
function MountService.OnMountShot(shooter, horseModel)
	local ownerId = horseModel and horseModel:GetAttribute("OwnerUserId")
	local owner = ownerId and Players:GetPlayerByUserId(ownerId)
	if not owner or owner == shooter or not mounts[owner] then return end
	if not DungeonProfile.CanPvP(shooter, owner) then return end
	local zones = ServerScriptService:FindFirstChild("ZoneService")
	local zs = zones and require(zones)
	if zs and (zs.IsAnyZoneLawfulAtPlayer(shooter) or zs.IsAnyZoneLawfulAtPlayer(owner)) then return end
	dismount(owner, "shot")
	CombatStateService.Flag(owner, AlignmentConfig.PVP_COMBAT_SECONDS)
	CombatStateService.Flag(shooter, AlignmentConfig.PVP_COMBAT_SECONDS)
end

-- The horse model a hit part belongs to, if any.
function MountService.HorseOf(part)
	local model = part and part:FindFirstAncestorWhichIsA("Model")
	while model do
		if model:GetAttribute("DungeonHorseMount") then return model end
		model = model.Parent and model.Parent:FindFirstAncestorWhichIsA("Model")
	end
	return nil
end

----------------------------------------------------------------------------------------------
-- The ride: one Heartbeat for every mount

-- The horse's tracks and the rider's matching ones change together, so the rider stays in step.
local function setState(m, state)
	if m.state == state then return end
	m.state = state
	for _, t in ipairs({ m.tracks, m.riderTracks or {} }) do
		if state == "Idle" then
			if t.RunStart then t.RunStart:Stop(0.25) end
			if t.RunLoop then t.RunLoop:Stop(0.3) end
		elseif state == "Starting" then
			if t.RunStart then t.RunStart:Play(0.1, 1, MountConfig.RUN_START_PLAYBACK) end
		elseif state == "Running" then
			if t.RunLoop then t.RunLoop:Play(t.RunStart and 0.05 or 0.2) end
			if t.RunStart then t.RunStart:Stop(0.1) end
		end
	end
	if state == "Idle" then
		if m.gallop then m.gallop:Stop() end
	elseif state == "Starting" then
		m.runStartedAt = os.clock()
		if m.gallop then m.gallop:Play() end
	end
end

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	accumulator += dt
	if accumulator < TICK then return end
	accumulator = 0
	for player, m in pairs(mounts) do
		local root, hum = rootAndHumanoid(player)
		if not root or not hum or hum.Health <= 0 or hum ~= m.humanoid or not m.horse.Parent then
			dismount(player, "removed")
		elseif CombatStateService.IsInCombat(player) then
			dismount(player, "combat")
		elseif player:GetAttribute("InDungeon") then
			dismount(player, "removed")
		else
			local v = root.AssemblyLinearVelocity
			local speed = Vector3.new(v.X, 0, v.Z).Magnitude
			local moving = speed > MountConfig.MOVING_SPEED
			if moving then
				m.slowSince = nil
			elseif m.state ~= "Idle" then
				m.slowSince = m.slowSince or os.clock()
				-- still galloping through a short dip (turns, bumps); only a real stop settles it
				moving = os.clock() - m.slowSince < MountConfig.STOP_GRACE
			end
			if not moving then
				setState(m, "Idle")
				if os.clock() >= m.nextIdleSound then
					m.nextIdleSound = os.clock() + randomIn(MountConfig.IDLE_SOUND_EVERY)
					fx("idle", m.horse.PrimaryPart.Position)
				end
			elseif m.state == "Idle" then
				setState(m, "Starting")
			elseif m.state == "Starting" then
				local length = m.tracks.RunStart and m.tracks.RunStart.Length / MountConfig.RUN_START_PLAYBACK or 0
				if os.clock() - m.runStartedAt >= math.max(length, 0.2) - 0.05 then setState(m, "Running") end
			end
			if m.state == "Running" and m.tracks.RunLoop then
				local rate = math.clamp(speed / MountConfig.NOMINAL_RUN_SPEED, MountConfig.RUN_PLAYBACK_MIN, MountConfig.RUN_PLAYBACK_MAX)
				m.tracks.RunLoop:AdjustSpeed(rate)
				local riderRun = m.riderTracks and m.riderTracks.RunLoop
				if riderRun then riderRun:AdjustSpeed(rate) end
				if m.gallop then m.gallop.PlaybackSpeed = 0.85 + rate * 0.2 end
			end
		end
	end
end)

----------------------------------------------------------------------------------------------
-- Remotes and lifecycle

mountToggle.OnServerInvoke = function(player)
	return MountService.Toggle(player)
end

-- The saddle Tool's Activate (EquippedHotbar's DungeonMountSaddleTool) still works: same toggle.
mountRequest.OnServerEvent:Connect(function(player)
	MountService.Toggle(player)
end)

local function hookPlayer(player)
	player.CharacterRemoving:Connect(function() dismount(player, "removed") end)
	player:SetAttribute("MountReadyAt", 0)
end
Players.PlayerAdded:Connect(hookPlayer)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(hookPlayer, p) end
Players.PlayerRemoving:Connect(function(p)
	dismount(p, "removed")
	lastToggle[p.UserId] = nil
	readyAt[p.UserId] = nil
end)

print("[MountService] ready")

return MountService
