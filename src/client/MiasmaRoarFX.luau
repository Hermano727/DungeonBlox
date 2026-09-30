--[[
	MiasmaRoarFX -- the roar at the end of Miasma's landing slam (client only).

	Played by MiasmaEncounterVFX on the "BossRoar" presentation, which the server fires at frame 65
	of the slam clip and holds to frame 100 (MiasmaEncounterConfig.BossDropSequence.SlamRoar*).

	  Breath   a blast of streaks, foul mist and pressure rings pouring out of the open mouth.
	           Rides the jaw bones every frame, so it follows the head as it moves; the forward
	           direction comes from the jaw's front bone vs its core bone, not the model's pivot.
	  Shake    ArenaShake rumble for everyone (mostly vertical), strongest near the boss.
	  Rocks    CeilingDebrisFX rock rain across the arena for the whole roar.
	  Dust     grit and dust shaken loose from the ceiling over the whole arena (found by a
	           raycast up from the boss, so it follows whatever roof the arena has).
	  Sound    RoarFX.PlaySound(): the roar itself (SoundEffects.MiasmaRoar), non-positional,
	           Effects bus. Cued separately ("BossRoarSound"), 0.5s ahead of the visuals.

	Every size is authored for a boss ~40 studs wide (ModelScale 0.45) and scaled by its real
	mesh width, so resizing Miasma again keeps the proportions.

	  RoarFX.Play(bossModel, duration, arenaPosition, parent)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local SfxService = require(ReplicatedStorage:WaitForChild("SfxService"))
local ArenaShake = require(script.Parent:WaitForChild("ArenaShake"))
local CeilingDebris = require(script.Parent:WaitForChild("CeilingDebrisFX"))
local SoundEffects = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Sounds"):WaitForChild("SoundEffects"))

local RoarFX = {}

local AUTHORED_WIDTH = 40

local TEX = {
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	spark = "rbxasset://textures/particles/sparkles_main.dds",
	ring = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
}

local JAW_FRONT = "LowerJaw_Center_Front"
local JAW_CORE = "LowerJaw_Center_Core"
local UPPER_FRONT = "Throat_Center_Front"

local BREATH_UP_ANGLE = math.rad(8)   -- the blast leans a little upward
local MOUTH_FORWARD = 2               -- studs (authored) in front of the jaw line

-- The roar's rumble (ArenaShake) and rock rain (CeilingDebrisFX). Mostly vertical heave.
local SHAKE = { amplitude = .9, rotation = 1.1, rampIn = .12, decay = .6, frequency = 14, fullRadius = 70 }
local ROCKS_PER_SECOND = 22
local ROCK_RADIUS = 75

local DUST_RATE = 160
local DUST_PLATE = 190   -- studs across the dust plate under the ceiling

local function part(name, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.new(.2, .2, .2)
	p.Parent = parent
	return p
end

local function emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.EmissionDirection = Enum.NormalId.Front
	e.LightInfluence = 0
	for k, v in pairs(props) do e[k] = v end
	e.Parent = parent
	return e
end

local function numberRange(a, b, s) return NumberRange.new(a * s, b * s) end
local function sizeSeq(a, b, s) return NumberSequence.new(a * s, b * s) end

local function findBones(boss)
	local bones = {}
	for _, d in ipairs(boss:GetDescendants()) do
		if d:IsA("Bone") and (d.Name == JAW_FRONT or d.Name == JAW_CORE or d.Name == UPPER_FRONT) then
			bones[d.Name] = d
		end
	end
	return bones
end

local function widest(boss)
	local skin
	for _, d in ipairs(boss:GetDescendants()) do
		if d:IsA("MeshPart") and (not skin or d.Size.X > skin.Size.X) then skin = d end
	end
	return skin
end

-- Mouth position + forward direction this frame, or nil if the rig is gone.
local function mouthFrame(boss, bones, scale)
	local front, core, upper = bones[JAW_FRONT], bones[JAW_CORE], bones[UPPER_FRONT]
	local root = boss.PrimaryPart
	if not (front and front.Parent) then
		if not root then return nil end
		local cf, size = boss:GetBoundingBox()
		local look = root.CFrame.LookVector
		return CFrame.lookAt(cf.Position + look * size.Z * .5, cf.Position + look * (size.Z * .5 + 1))
	end
	local jaw = front.TransformedWorldCFrame.Position
	local top = upper and upper.Parent and upper.TransformedWorldCFrame.Position or jaw
	local mouth = (jaw + top) * .5
	local forward
	if core and core.Parent then
		local flat = jaw - core.TransformedWorldCFrame.Position
		flat = Vector3.new(flat.X, 0, flat.Z)
		if flat.Magnitude > .01 then forward = flat.Unit end
	end
	forward = forward or (root and root.CFrame.LookVector) or Vector3.new(0, 0, -1)
	forward = (forward * math.cos(BREATH_UP_ANGLE) + Vector3.new(0, math.sin(BREATH_UP_ANGLE), 0)).Unit
	mouth += forward * MOUTH_FORWARD * scale
	return CFrame.lookAt(mouth, mouth + forward)
end

local function buildBreath(parent, s)
	local nozzle = part("RoarMouth", parent)
	local streaks = emitter(nozzle, {
		Name = "Streaks", Texture = TEX.spark, Rate = 110,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Squash = NumberSequence.new(2.4),
		Color = ColorSequence.new(Color3.fromRGB(225, 240, 205), Color3.fromRGB(170, 205, 150)),
		LightEmission = .6,
		Size = sizeSeq(1, 2.6, s),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .25), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(.35, .55),
		Speed = numberRange(80, 120, s),
		SpreadAngle = Vector2.new(16, 16),
		Drag = 2,
	})
	local mist = emitter(nozzle, {
		Name = "Mist", Texture = TEX.smoke, Rate = 50,
		Color = ColorSequence.new(Color3.fromRGB(160, 200, 125), Color3.fromRGB(115, 75, 135)),
		LightEmission = .15,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3 * s), NumberSequenceKeypoint.new(1, 17 * s) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .5), NumberSequenceKeypoint.new(.6, .75), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(.8, 1.15),
		Speed = numberRange(38, 58, s),
		SpreadAngle = Vector2.new(22, 22),
		Drag = 3,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-90, 90),
	})
	local rings = emitter(nozzle, {
		Name = "PressureRings", Texture = TEX.ring, Rate = 6,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		Color = ColorSequence.new(Color3.fromRGB(215, 235, 200)),
		LightEmission = .4,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2 * s), NumberSequenceKeypoint.new(1, 20 * s) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .35), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(.55, .6),
		Speed = numberRange(50, 50, s),
		SpreadAngle = Vector2.new(0, 0),
	})
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(170, 215, 140)
	light.Range = 18 * s
	light.Brightness = 1.2
	light.Parent = nozzle
	return nozzle, { streaks, mist, rings }, light
end

-- Enrage variant: the same mouth-tracking nozzle, spewing poison instead of wind -- thick
-- purple mist, poison streaks, and heavy globs that arc out and drip down under gravity.
-- Purple (not green) so it reads as the same stuff as the shroud it becomes.
local POISON_BRIGHT = Color3.fromRGB(205, 120, 255)
local POISON_MID = Color3.fromRGB(150, 70, 200)
local POISON_DARK = Color3.fromRGB(85, 30, 115)
local function buildPoisonBreath(parent, s)
	local nozzle, emitters, light = buildBreath(parent, s)
	local streaks, mist, rings = emitters[1], emitters[2], emitters[3]
	streaks.Color = ColorSequence.new(POISON_BRIGHT, POISON_MID)
	streaks.LightEmission = .7
	mist.Color = ColorSequence.new(POISON_MID, POISON_DARK)
	mist.Rate = 80
	mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .3), NumberSequenceKeypoint.new(.6, .6), NumberSequenceKeypoint.new(1, 1) })
	mist.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4 * s), NumberSequenceKeypoint.new(1, 22 * s) })
	rings.Color = ColorSequence.new(POISON_BRIGHT)
	light.Color = POISON_BRIGHT
	local globs = emitter(nozzle, {
		Name = "Globs", Texture = TEX.spark, Rate = 55,
		Color = ColorSequence.new(POISON_BRIGHT, POISON_DARK),
		LightEmission = .5,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.2 * s), NumberSequenceKeypoint.new(1, .6 * s) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .05), NumberSequenceKeypoint.new(1, .8) }),
		Lifetime = NumberRange.new(.9, 1.4),
		Speed = numberRange(45, 75, s),
		SpreadAngle = Vector2.new(24, 24),
		Acceleration = Vector3.new(0, -110 * s, 0),
		Drag = .4,
	})
	return nozzle, { streaks, mist, rings, globs }, light
end

local function buildDust(parent, groundPosition)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { parent }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(ignore, p.Character) end
	end
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(groundPosition + Vector3.new(0, 6, 0), Vector3.new(0, 250, 0), params)
	if not hit then return nil end
	local plate = part("RoarCeilingDust", parent)
	plate.Size = Vector3.new(DUST_PLATE, .2, DUST_PLATE)
	plate.CFrame = CFrame.new(Vector3.new(groundPosition.X, hit.Position.Y - 1, groundPosition.Z))
	local dust = emitter(plate, {
		Name = "Dust", Texture = TEX.smoke, Rate = DUST_RATE,
		EmissionDirection = Enum.NormalId.Bottom,
		Shape = Enum.ParticleEmitterShape.Box,
		Color = ColorSequence.new(Color3.fromRGB(120, 112, 104)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, .6), NumberSequenceKeypoint.new(1, 2.2) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .45), NumberSequenceKeypoint.new(.7, .7), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(2, 3),
		Speed = NumberRange.new(6, 12),
		Acceleration = Vector3.new(0, -26, 0),
		SpreadAngle = Vector2.new(10, 10),
		Drag = .6,
	})
	local grit = emitter(plate, {
		Name = "Grit", Texture = TEX.spark, Rate = DUST_RATE * .4,
		EmissionDirection = Enum.NormalId.Bottom,
		Shape = Enum.ParticleEmitterShape.Box,
		Color = ColorSequence.new(Color3.fromRGB(80, 74, 68)),
		Size = NumberSequence.new(.25),
		Transparency = NumberSequence.new(.1),
		Lifetime = NumberRange.new(1.2, 1.8),
		Speed = NumberRange.new(10, 18),
		Acceleration = Vector3.new(0, -70, 0),
	})
	return { dust, grit }
end

local ROAR_SOUND_MAX_SECONDS = 30 -- cleanup safety net if Ended never fires
local ROAR_LOOP_OVERLAP = 0.2      -- each repeat starts this long before the previous one ends, so the join has no gap
local ROAR_LOAD_TIMEOUT = 3

local function playRoarOnce(id)
	local sound = Instance.new("Sound")
	sound.Name = "MiasmaRoar"
	sound.SoundId = id
	sound.SoundGroup = SfxService.GetEffectsGroup() -- Master x Effects sliders
	sound.Parent = SoundService
	local done = false
	local function cleanup()
		if done then return end
		done = true
		sound:Destroy()
	end
	sound.Ended:Connect(cleanup)
	sound:Play()
	task.delay(ROAR_SOUND_MAX_SECONDS, cleanup)
	return sound
end

-- The roar sound on its own. The server cues it ("BossRoarSound") SlamRoarSoundLead before the
-- visuals because the clip has a wind-up; the title card plays it again. With `coverSeconds`
-- the clip repeats, each copy starting ROAR_LOOP_OVERLAP before the last one ends, until the
-- copies cover that long (the stretched phase 1 -> 2 roar). The last copy plays out in full.
function RoarFX.PlaySound(coverSeconds)
	local id = SoundEffects.MiasmaRoar
	if type(id) ~= "string" or id == "" then return end
	local sound = playRoarOnce(id)
	coverSeconds = tonumber(coverSeconds)
	if not coverSeconds or coverSeconds <= 0 then return end
	local endAt = os.clock() + coverSeconds
	task.spawn(function()
		while true do
			local waitStart = os.clock()
			while not sound.IsLoaded and os.clock() - waitStart < ROAR_LOAD_TIMEOUT do task.wait() end
			if not sound.IsLoaded or sound.TimeLength <= ROAR_LOOP_OVERLAP * 2 then return end
			-- When THIS copy ends, from its own playhead (so a slow load can't skew the join).
			local speed = math.max(sound.PlaybackSpeed, .01)
			local endsAt = os.clock() + (sound.TimeLength - sound.TimePosition) / speed
			if endsAt >= endAt then return end
			task.wait(math.max(0, endsAt - ROAR_LOOP_OVERLAP - os.clock()))
			sound = playRoarOnce(id)
		end
	end)
end

-- opts.style = "poison" swaps the wind breath for the enrage poison spew.
function RoarFX.Play(boss, duration, arenaPosition, parent, opts)
	local poison = type(opts) == "table" and opts.style == "poison"
	duration = math.max(.2, tonumber(duration) or 1.2)
	parent = parent or Workspace
	local bossModel = typeof(boss) == "Instance" and boss:IsA("Model") and boss.Parent and boss or nil
	local focus = arenaPosition
	if bossModel then focus = bossModel:GetPivot().Position end
	if typeof(focus) ~= "Vector3" then return end

	local folder = Instance.new("Folder")
	folder.Name = "MiasmaRoarFX"
	folder.Parent = parent

	ArenaShake.Shake({
		amplitude = SHAKE.amplitude, rotation = SHAKE.rotation, duration = duration, rampIn = SHAKE.rampIn,
		decay = SHAKE.decay, frequency = SHAKE.frequency, focus = focus, fullRadius = SHAKE.fullRadius,
	})
	local arenaCentre = typeof(arenaPosition) == "Vector3" and arenaPosition or focus
	CeilingDebris.Rain(arenaCentre, ROCK_RADIUS, duration, ROCKS_PER_SECOND, parent)
	local dust = buildDust(folder, arenaCentre)

	local nozzle, breath, light
	if bossModel then
		local skin = widest(bossModel)
		local s = math.max(.25, (skin and skin.Size.X or AUTHORED_WIDTH) / AUTHORED_WIDTH)
		local bones = findBones(bossModel)
		nozzle, breath, light = (poison and buildPoisonBreath or buildBreath)(folder, s)
		local frame = mouthFrame(bossModel, bones, s)
		if frame then nozzle.CFrame = frame end
		breath[1]:Emit(25); breath[3]:Emit(2) -- the opening blast
		if breath[4] then breath[4]:Emit(20) end
		local started = os.clock()
		local connection
		connection = RunService.RenderStepped:Connect(function()
			local t = os.clock() - started
			if t > duration or not folder.Parent or not bossModel.Parent then
				connection:Disconnect()
				return
			end
			local cf = mouthFrame(bossModel, bones, s)
			if cf then nozzle.CFrame = cf end
			light.Brightness = 1.2 * (0.75 + .25 * math.sin(t * 30))
		end)
	end

	-- Stop emitting at the end of the roar; let what's airborne finish, then clean up.
	task.delay(duration, function()
		for _, e in ipairs(breath or {}) do e.Enabled = false end
		for _, e in ipairs(dust or {}) do e.Enabled = false end
		if light then light.Enabled = false end
	end)
	task.delay(duration + 3.5, function() folder:Destroy() end)
end

return RoarFX
