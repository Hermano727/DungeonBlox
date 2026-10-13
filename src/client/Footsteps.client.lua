local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local StarterPlayer = game:GetService("StarterPlayer")

local DefaultWalkspeed = StarterPlayer.CharacterWalkSpeed
local MaxFPS = 1/30 -- 1/FPS -- this only applies to raycasting!! raycasting is used for comparing speed on moving platforms
local FootstepsPerSecond = 2.5
-- ElapsedSinceLastFootstep (below) accumulates actual distance travelled, not
-- time, so FootstepTimer is really "studs per stride" -- this multiplier
-- stretches that distance uniformly, which stretches the TIME gap between
-- footsteps by the same 10% at any speed, walk or sprint alike, without
-- touching the sound assets themselves.
local FOOTSTEP_GAP_SCALE = 1.1
local MaxDistance = 250 -- if any character is beyond this distance they wont make any sound

-- Riding (2026-10-11): the horse has no hoof sounds of its own yet, so the rider's footsteps ARE
-- the hoofbeats. At mount speed they came out at 2x volume plus the local bass layer, far too
-- loud: while the character's player has the Mounted attribute they play quieter, deeper, spaced
-- out like a stride, with no bass layer, and through the Mount bucket (Settings > Audio > Mount).
local MOUNT_VOLUME_SCALE = 0.35
local MOUNT_PITCH_SCALE = 0.78
local MOUNT_GAP_SCALE = 1.35

-- Synced footsteps (2026-10-12): the scripted walk / run / run-start clips carry a "Footstep" KeyframeMarker
-- (value "L" / "R") on the exact frame each foot lands (author_locomotion.py). While one of them is the main
-- locomotion track, every footstep comes from its marker, so the sound lands with the foot at any playback
-- speed. The distance timer below only runs when no marked clip is playing (riding, NPCs).
local MARKER_NAME = "Footstep"
local MARKER_MIN_WEIGHT = 0.5 -- in a crossfade only the incoming clip steps, never both
local MARKER_MIN_GAP = 0.1    -- seconds; a safety net against a double step

local LocalPlayer = Players.LocalPlayer

local AudioCategories = require(ReplicatedStorage:WaitForChild("AudioCategories"))
local CharacterAnimProfiles = require(ReplicatedStorage:WaitForChild("CharacterAnimProfiles"))

-- The clips that carry Footstep markers: every profile's Walk / RunStart / RunLoop / CrouchWalk.
local MARKED_IDS = {}
for _, profile in pairs(CharacterAnimProfiles.Profiles) do
	for _, field in ipairs({ "Walk", "RunStart", "RunLoop", "CrouchWalk" }) do
		if profile[field] and profile[field] ~= "" then MARKED_IDS[profile[field]] = true end
	end
end
local Modules = ReplicatedStorage:WaitForChild("Modules")
local FootstepModule = require(Modules:WaitForChild("FootstepModule"))

local FootstepsSoundGroup = SoundService:WaitForChild("Main").Character.Footsteps
local LandingSoundGroup = SoundService:WaitForChild("Main").Character.Landing
local JumpingSoundGroup = SoundService:WaitForChild("Main").Character.Jumping

local CachedFootsteps = FootstepModule:GetCached(FootstepsSoundGroup, "Footsteps")
local CachedLanding = FootstepModule:GetCached(LandingSoundGroup, "Landing")
local CachedJumping = FootstepModule:GetCached(JumpingSoundGroup, "Jumping")

local ValidStates = {
	Enum.HumanoidStateType.Running,
	Enum.HumanoidStateType.Climbing
}

local function GetRandomFromTable(Table:{any})
	return Table[math.random(#Table)]
end

local function PlayRandomSound(Directory:Folder,PlayAt:BasePart|Attachment,Speed:number,Mounted:boolean?)
	local Sound:Sound = GetRandomFromTable(Directory)

	if Sound.IsLoaded then
		Sound = Sound:Clone()
	else
		return
	end

	local IsBass = Sound:GetAttribute("IsBass")
	local DefaultPitch = Sound:GetAttribute("DefaultPitch")
	local DefaultVolume = Sound:GetAttribute("DefaultVolume")
	local DefaultRolloff = Sound:GetAttribute("DefaultRolloff")

	local Speed = Speed or 1
	local function influencemult(num,influence)
		return ((1-influence)+(num*influence))
	end
	local Pitch = DefaultPitch*(math.random(950,1050)/1000)*influencemult(Speed,0.5)
	local Volume = DefaultVolume*(IsBass and math.max((Speed-0.5),0.2) or Speed)
	local Rolloff = DefaultRolloff*influencemult(Speed,0.1)

	Sound.PlaybackSpeed *= Pitch
	Sound.Volume = Volume
	Sound.RollOffMinDistance = Rolloff
	if Mounted then
		Sound.PlaybackSpeed *= MOUNT_PITCH_SCALE
		Sound.Volume *= MOUNT_VOLUME_SCALE
		Sound.SoundGroup = AudioCategories.GetGroup("mount")
	end

	Sound.Parent = PlayAt or SoundService

	Sound:Play()
	Sound.Ended:Once(function()
		Sound:Destroy()
	end)
end

local function OnCharacterAdded(Character:Model)
	if Character:GetAttribute("SetUp") then return end
	Character:SetAttribute("SetUp",true)

	if not Character:GetAttribute("Set") then
		Character:SetAttribute("Set","Default")
	end

	local Humanoid:Humanoid = Character:WaitForChild("Humanoid")
	local Owner = Players:GetPlayerFromCharacter(Character)
	local function IsMounted()
		return Owner ~= nil and Owner:GetAttribute("Mounted") == true
	end
	local HRP = Character:WaitForChild("HumanoidRootPart") --Humanoid.RootPart

	local Stride = "Left"
	local LastFloorRay = nil
	local LastRayFrame, LastLand = time(), time()
	local ElapsedSinceLastFootstep = 0

	local FootstepsDirectory, LandingDirectory, JumpingDirectory = CachedFootsteps[Character:GetAttribute("Set")], CachedLanding[Character:GetAttribute("Set")], CachedJumping[Character:GetAttribute("Set")]

	local Connection
	local Connections = {}

	local FootstepTimer = (DefaultWalkspeed/FootstepsPerSecond) * FOOTSTEP_GAP_SCALE
	local Velocity, MoveDirection, FloorMaterial, HumanoidState, LastFloorMaterial


	HumanoidState = Humanoid:GetState()

	local RayParams = RaycastParams.new()
	RayParams.CollisionGroup = "SoundRays" -- if you have any collision group that only accepts world geometry use that (not required)
	RayParams.IgnoreWater = true
	RayParams.RespectCanCollide = true
	RayParams.FilterDescendantsInstances = {workspace.CurrentCamera,Character} -- terrain may cause issues idk --it will
	RayParams.FilterType = Enum.RaycastFilterType.Exclude

	local function IsWithinRange()
		if LocalPlayer.Character ~= Character and HRP and (HRP.Position-workspace.Camera.CFrame.Position).Magnitude > MaxDistance then return false end
		return true
	end

	local function Raycast(a,b)
		return workspace:Raycast(a,b,RayParams)
	end

	local function GetHipHeightFromHRP()
		return ((HRP.Size.Y/2)+(Humanoid.HipHeight+2)+2)
	end

	local function GetFloorMaterial()
		local ray = workspace:Raycast(HRP.Position, -HRP.CFrame.UpVector*GetHipHeightFromHRP(),RayParams)
		if ray and ray.Instance then
			return ray.Material
		end
	end

	local function UpdateCommon()
		local floorray = nil
		if time()-LastRayFrame >= MaxFPS then
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = {Character}
			floorray = Raycast(HRP.Position,-HRP.CFrame.UpVector*GetHipHeightFromHRP())
			LastFloorRay = floorray
			LastRayFrame = time()
		else
			floorray = LastFloorRay
		end
		local floor:BasePart = (floorray and floorray.Instance)
		if floor and floor:IsA("Terrain") then floor = nil end
		Velocity = floor and HRP.AssemblyLinearVelocity-floor:GetVelocityAtPosition(floorray.Position) or HRP.AssemblyLinearVelocity
		MoveDirection = Humanoid.MoveDirection
		LastFloorMaterial = FloorMaterial ~= Enum.Material.Air and FloorMaterial or LastFloorMaterial
		FloorMaterial = Humanoid.FloorMaterial
	end

	local function IsFooted()
		if (table.find(ValidStates,HumanoidState)) or (FloorMaterial and FloorMaterial ~= Enum.Material.Air) then
			return true
		end
	end

	local function MovingCheck()
		if MoveDirection.Magnitude > 0 then
			return true
		else
			return false
		end
	end

	local function GetFootstepSpeed()
		return (math.min(Velocity.Magnitude,DefaultWalkspeed*2)/DefaultWalkspeed)^1.01
	end

	local function UpdateTimestep(dt)
		ElapsedSinceLastFootstep += dt*math.max(Velocity.Magnitude,7)
	end

	local function step(MaterialSounds)
		local IsRight = Stride == "Right"
		local Speed = GetFootstepSpeed()
		local Mounted = IsMounted()
		PlayRandomSound(MaterialSounds,HRP,Speed*(IsRight and 1.05 or 0.95),Mounted)
		if Character == LocalPlayer.Character and not Mounted then
			PlayRandomSound(FootstepsDirectory["Bass"],HRP,Speed)
		end
		ElapsedSinceLastFootstep = 0
	end

	local function Footstep()
		local IsClimbing = HumanoidState == Enum.HumanoidStateType.Climbing
		local Type = IsClimbing and "Ladder" or FootstepModule.MaterialMap[FloorMaterial]
		local MaterialSounds = FootstepsDirectory[Type]
		if MaterialSounds then
			step(MaterialSounds)
		end
	end

	local function Land(mat)
		local IsRight = Stride == "Right"
		local Speed = GetFootstepSpeed()
		local MaterialSounds = LandingDirectory[FootstepModule.MaterialMap[mat]] or LandingDirectory[FootstepModule.MaterialMap[FloorMaterial]]

		local Mounted = IsMounted()
		PlayRandomSound(MaterialSounds,HRP,Speed*(IsRight and 1.05 or 0.95),Mounted)
		if Character == LocalPlayer.Character and not Mounted then
			PlayRandomSound(LandingDirectory["Bass"],HRP,Speed)
		end
	end

	local function Jump()
		local MaterialSounds = JumpingDirectory[FootstepModule.MaterialMap[FloorMaterial]]

		PlayRandomSound(MaterialSounds,HRP)
	end

	local function CanFootstep()
		return IsFooted() and Velocity.Magnitude > .1 and MovingCheck()
	end

	local function StateChanged(old,new)
		HumanoidState = new
		FloorMaterial = Humanoid.FloorMaterial

		if IsWithinRange() then

			if
				new == Enum.HumanoidStateType.Landed
				or
				(Character ~= LocalPlayer.Character
					and (FloorMaterial == Enum.Material.Air
					and new == Enum.HumanoidStateType.Running)
				)
			then
				if LastLand > time() then return end
				LastLand = time() + .1
				local materialToUse = GetFloorMaterial() or LastFloorMaterial or Humanoid.FloorMaterial
				if materialToUse == Enum.Material.Air then return end
				Land(materialToUse)

			elseif
				(Character == LocalPlayer.Character
					and new == Enum.HumanoidStateType.Jumping)
				or
				(Character ~= LocalPlayer.Character
					and new == Enum.HumanoidStateType.Freefall
					and old == Enum.HumanoidStateType.Running)
			then

				FloorMaterial = GetFloorMaterial() or Humanoid.FloorMaterial
				if FloorMaterial == Enum.Material.Air then return end
				Jump()
			end
		end
	end

	local function AttributeChanged(Attr)
		if Attr == "Set" then
			FootstepsDirectory = CachedFootsteps[Character:GetAttribute("Set")]
			LandingDirectory = CachedLanding[Character:GetAttribute("Set")]
			JumpingDirectory = CachedJumping[Character:GetAttribute("Set")]
		end
	end

	local Animator = Humanoid:WaitForChild("Animator", 10)
	local function IsMarked(track)
		local animation = track.Animation
		return animation ~= nil and MARKED_IDS[animation.AnimationId] == true
	end

	-- A marked clip is carrying the gait right now (the timer must stay out of its way).
	local function MarkerDriven()
		if not Animator or IsMounted() then return false end
		for _, track in ipairs(Animator:GetPlayingAnimationTracks()) do
			if track.WeightCurrent > 0.3 and IsMarked(track) then return true end
		end
		return false
	end

	local LastMarkerStep = 0
	local function OnMarker(track, side)
		if not IsWithinRange() or IsMounted() then return end
		if track.WeightCurrent < MARKER_MIN_WEIGHT then return end
		if time() - LastMarkerStep < MARKER_MIN_GAP then return end
		if not Velocity then UpdateCommon() end
		if not IsFooted() or Velocity.Magnitude < 0.5 then return end
		LastMarkerStep = time()
		Stride = side == "R" and "Right" or "Left"
		Footstep()
	end

	local Hooked = setmetatable({}, { __mode = "k" })
	local function HookTrack(track)
		if Hooked[track] or not IsMarked(track) then return end
		Hooked[track] = true
		table.insert(Connections, track:GetMarkerReachedSignal(MARKER_NAME):Connect(function(side)
			OnMarker(track, side)
		end))
	end

	local function Initialize()
		if Animator then
			for _, track in ipairs(Animator:GetPlayingAnimationTracks()) do HookTrack(track) end
			table.insert(Connections, Animator.AnimationPlayed:Connect(HookTrack))
		end
		table.insert(Connections,RunService.Heartbeat:Connect(function(dt)
			if not IsWithinRange() then return end

			UpdateCommon()
			if MarkerDriven() then
				ElapsedSinceLastFootstep = 0 -- the clip's markers are stepping; the timer restarts when they stop
			elseif CanFootstep() then
				UpdateTimestep(dt)
				if ElapsedSinceLastFootstep >= FootstepTimer * (IsMounted() and MOUNT_GAP_SCALE or 1) then
					Footstep()
				end
			end
		end))
		table.insert(Connections,Humanoid.StateChanged:Connect(StateChanged))
		table.insert(Connections,Character.AttributeChanged:Connect(AttributeChanged))

		local function destroy()
			for _, con in Connections do
				con:Disconnect()
			end
			Connections = nil
			ElapsedSinceLastFootstep = nil
			Stride = nil
			HumanoidState = nil
			HRP = nil
			Humanoid = nil
			Velocity = nil
			task.cancel(Connection)
		end

		table.insert(Connections,Humanoid.Died:Connect(destroy))
		table.insert(Connections,Character.Destroying:Connect(destroy))
	end

	Connection = task.spawn(Initialize)
end

local function OnPlayerAdded(Plr:Player)
	Plr.CharacterAdded:Connect(OnCharacterAdded)
	if Plr.Character then
		OnCharacterAdded(Plr.Character)
	end
end

for _, plr in Players:GetPlayers() do
	OnPlayerAdded(plr)
end

Players.PlayerAdded:Connect(OnPlayerAdded)