--[[
	MiasmaAuraFX -- Miasma's poison presence while it's in the arena (client only, visual only).

		AuraFX.Start(bossModel, parent)
		AuraFX.Stop()
		AuraFX.Quench(seconds)   -- the holy water puts it out for a while (fades back after)
		AuraFX.Restore()

	Rebuilt 2026-10-11 for the v3 jaw rig: the old orbiting wisps and flat ooze disc read as a
	thin "veil" floating beside the body. Everything here rides the ANIMATED bones, so it moves
	with the surge, the bite and the slam:
	  shroud  poison seeping off the whole body. Vents on the skin (skirt rim, flanks, crown)
	          breathe sickly green vapour that ages to bruise purple. The puffs live in world
	          space, so a moving Miasma leaves a drifting cloud behind it
	  maw     a green glow in the mouth, and drool: drops fall off the fangs (more the wider the
	          jaw is open, measured from the jaw bones every frame), stretch on the way down and
	          hit the floor in a hissing splat of acid smoke
	  trail   glossy poison puddles left on the floor behind it as it slithers, fuming, then
	          drying up
	  eyes    (2026-10-11) its front eyes glow green and leave light streaks behind them as the
	          head moves: the anime "eye trail" when it lunges, surges and slams
	Hidden while it is submerged (skin fully transparent) and while the holy water quenches it.

	Vent and fang positions are measured on the v3 mesh (Blender studs at model scale 1, front -Y,
	up +Z; assets/models/mobs/dungeon bosses/miasma/v3) and scaled by the skin's real width, so
	ModelScale and the stun shrink keep them on the surface. A rig without those bones still gets
	everything, riding the skin instead.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local WorldVfx = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images"):WaitForChild("WorldVfx"))
local HudArt = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images"):WaitForChild("HudArt"))
local SfxService = require(ReplicatedStorage:WaitForChild("SfxService"))

local AuraFX = {}

-- The v3 skin's width at model scale 1 (Miasma_Body.Size.X), and the scale every size below
-- was tuned at (MobData ModelScale 0.45, ~40 studs wide).
local AUTHORED_WIDTH = 89.32
local TUNED_SCALE = .45
-- Blender (x, y, z) -> the skin's local space: Roblox (-x, z, y) around the mesh's own origin.
local MESH_ORIGIN = Vector3.new(1.281157, -34.48192, -1.509623)

-- Poison seeping off the body: { bone, Blender x, y, z } just inside the silhouette.
local VENTS = {
	-- the skirt rim (radius ~46 at the floor)
	{ "Skirt_F", 0, -43, 6 }, { "Skirt_F", 30, -30, 6 }, { "Skirt_L", 43, -1, 6 }, { "Skirt_L", 33, 25, 6 },
	{ "Skirt_B", 6, 46, 6 }, { "Skirt_R", -34, 30, 6 }, { "Skirt_R", -39, -8, 6 }, { "Skirt_R", -32, -27, 6 },
	-- flanks and back
	{ "Body", 31, 5, 14 }, { "Body", -30, 8, 14 }, { "Spine1", 21, 2, 26 }, { "Spine1", -25, 4, 26 },
	{ "Spine1", 4, 23, 26 },
	-- the crown
	{ "Head", 14, -4, 50 }, { "Head", -19, -4, 50 }, { "Head", 0, -5, 66 },
}
-- Where drool leaves the mouth: the lower fang ring and the upper fang tips.
local FANGS = {
	{ "LowerJaw", 0, -42, 31 }, { "LowerJaw", 8, -40, 30 }, { "LowerJaw", -8, -40, 30 },
	{ "LowerJaw", 17, -34, 30 }, { "LowerJaw", -17, -34, 30 },
	{ "Head", 0, -32, 51 }, { "Head", 8, -29, 52 }, { "Head", -3, -30, 51 },
}
local JAW_FRONT, JAW_CORE, UPPER_FRONT = "LowerJaw_Center_Front", "LowerJaw_Center_Core", "Throat_Center_Front"
-- Its eyes: the painted irises on the crown that face the player, found in TEXTURE space (green
-- blobs of the base colour, carried onto the mesh through its UVs; 11 sit on the head) -- the five
-- facing forward plus the big one on top. { Blender x, y, z, outward normal x, y, z, size }.
local EYES = {
	{ -0.4, -19.7, 64.6, -0.26, -0.77, 0.58, 1.0 },  -- the big front eye
	{ 7.2, -22.4, 60.4, 0.28, -0.73, 0.62, .7 },
	{ -7.7, -21.0, 61.5, -0.57, -0.53, 0.62, .6 },
	{ -15.2, -17.7, 58.9, -0.56, -0.65, 0.51, .7 },
	{ 11.4, -14.2, 60.5, 0.93, -0.27, 0.27, .6 },
	{ -2.4, -6.7, 68.7, -0.32, -0.25, 0.91, .9 },    -- the crown's top eye
}
local EYE_LIFT = .6               -- Blender studs out from the surface, so the glow sits on it
local EYE_TRAIL_LIFETIME = .35    -- seconds a streak lingers: long enough to read a lunge as a sweep
local EYE_CORE = Color3.fromRGB(205, 255, 130)
local EYE_EDGE = Color3.fromRGB(70, 210, 70)
-- Drool landing (PoisonDrip): at most one every DRIP_SOUND_GAP seconds, so a gaping mouth's
-- steady rain doesn't machine-gun.
local DRIP_SOUND_GAP = .28

-- Drool. Rate climbs from REST to OPEN with how far the mouth is open: the upper mouth socket's
-- height over the lower one, in Blender studs (measured on the v3 clips: snapped shut -10, the
-- aggro gather -3.5, idle 9..12, the aggro surge 11, the bite's windup 43).
local DROOL_RATE_REST = 1.2     -- drops per second, mouth shut
local DROOL_RATE_OPEN = 9       -- mouth gaping
local GAP_SHUT, GAP_WIDE = 4, 28
local DROP_OUT = 4              -- Blender studs in front of the fang the drop leaves from (clears the skirt)
local DROP_GRAVITY = 70         -- studs/s^2, heavier than real so it reads as thick
local MAX_DROPS = 18
-- Trail puddles.
local TRAIL_STEP = 4            -- studs moved (at TUNED_SCALE) per puddle
local PUDDLE_LIFE = 9           -- seconds, last PUDDLE_FADE of it drying up
local PUDDLE_FADE = 3
local MAX_PUDDLES = 26
local FLOOR_CHECK_EVERY = .5

local SMOKE = WorldVfx.SMOKE_PUFF_4X4
local SPARK = WorldVfx.SPARK
local TOXIC = Color3.fromRGB(150, 235, 80)
local TOXIC_DEEP = Color3.fromRGB(70, 150, 45)
local POISON_MID = Color3.fromRGB(110, 40, 150)
local POISON_DARK = Color3.fromRGB(40, 14, 55)
local ACID_SMOKE = Color3.fromRGB(205, 225, 160)
local ACID_GREY = Color3.fromRGB(95, 100, 90)

local active
local quenchUntil = 0

local function seq(...)
	local points = {}
	local args = { ... }
	for i = 1, #args, 2 do table.insert(points, NumberSequenceKeypoint.new(args[i], args[i + 1])) end
	return NumberSequence.new(points)
end

local function anchored(name, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.new(.2, .2, .2)
	p.Parent = parent
	return p
end

local function smokeEmitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.Texture = SMOKE
	e.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
	e.FlipbookMode = Enum.ParticleFlipbookMode.Random
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-25, 25)
	for k, v in pairs(props) do e[k] = v end
	e.Parent = parent
	return e
end

-- A flat disc on the floor (a Cylinder's length runs along X).
local function disc(name, parent, color, transparency)
	local p = anchored(name, parent)
	p.Shape = Enum.PartType.Cylinder
	p.Material = Enum.Material.SmoothPlastic
	p.Reflectance = .25
	p.Color = color
	p.Transparency = transparency
	return p
end

local FLAT = CFrame.Angles(0, 0, math.pi / 2)

local function skinOf(model)
	local best, bestVolume = nil, 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("MeshPart") then
			local v = d.Size.X * d.Size.Y * d.Size.Z
			if v > bestVolume then best, bestVolume = d, v end
		end
	end
	return best
end

-- Only SOLID ground counts (RespectCanCollide): invisible encounter parts, other effects and
-- hidden models above the arena floor used to catch the ray, and a splat or puddle then
-- appeared up by its head. Rebuilt with the floor check, so respawned characters are excluded.
local function floorParams(boss, folder)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local ignore = { boss, folder }
	local vfx = Workspace:FindFirstChild("MiasmaEncounterVFX")
	if vfx then table.insert(ignore, vfx) end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(ignore, p.Character) end
	end
	params.FilterDescendantsInstances = ignore
	return params
end

-- Belt and braces: a hit more than FLOOR_TOLERANCE above the floor Miasma stands on (its Root
-- bone, the floor centre) is not the floor, so the splat lands on that floor instead.
local FLOOR_TOLERANCE = 2

local function floorAt(s, position, fallbackY)
	local hit = Workspace:Raycast(position + Vector3.new(0, 4, 0), Vector3.new(0, -120, 0), s.params)
	local y = hit and hit.Position.Y or fallbackY
	local standing = s.standingFloorY
	if standing and y > standing + FLOOR_TOLERANCE then
		y = standing
	end
	return y
end

-- A bone's REST world frame: the chain of its own and its ancestors' Bone.CFrame (the static bind
-- offsets) from the skin. NOT Bone.WorldCFrame: while a clip plays that one already carries the
-- parent bones' animation (measured 3 studs off on the Head mid-Idle), so offsets taken from it
-- were relative to whatever pose was playing when Start ran -- every anchor sat off its spot
-- (the eye streaks floated above the eyes, drool fell from beside the mouth; 2026-10-11).
local function bindWorld(bone)
	local parent = bone.Parent
	local base = parent:IsA("Bone") and bindWorld(parent) or (parent :: BasePart).CFrame
	return base * bone.CFrame
end

-- Anchors: a measured Blender point, carried on its bone. `offset` is in the bone's own frame at
-- bind, measured once at Start; scaled by the skin's growth/shrink since then.
local function makeAnchor(s, entry)
	local bone = s.bones[entry[1]]
	local meshLocal = Vector3.new(-entry[2], entry[4], entry[3]) + MESH_ORIGIN
	local pointAtBind = s.skin.CFrame * (meshLocal * s.scale)
	if bone then
		return { bone = bone, offset = bindWorld(bone):PointToObjectSpace(pointAtBind) }
	end
	return { offset = s.skin.CFrame:PointToObjectSpace(pointAtBind) }
end

local function anchorPosition(s, anchor, ratio)
	local frame = anchor.bone and anchor.bone.Parent and anchor.bone.TransformedWorldCFrame or s.skin.CFrame
	return frame * (anchor.offset * ratio)
end

----------------------------------------------------------------------
-- Drool and acid splats
----------------------------------------------------------------------

local function splat(s, position, k)
	local now = os.clock()
	if now - (s.lastDripSound or 0) >= DRIP_SOUND_GAP then
		s.lastDripSound = now
		SfxService.PlayEffect("PoisonDrip", {
			Position = position, Volume = .55, PlaybackSpeed = .85 + math.random() * .3,
			RollOffMinDistance = 12, RollOffMaxDistance = 140,
		})
	end
	local spot = disc("AcidSplat", s.folder, TOXIC, .1)
	spot.Material = Enum.Material.Neon
	local d = (1.2 + math.random() * 1.2) * k
	spot.Size = Vector3.new(.08, d * .5, d * .5)
	spot.CFrame = CFrame.new(position + Vector3.new(0, .06, 0)) * FLAT
	TweenService:Create(spot, TweenInfo.new(.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(.08, d, d) }):Play()
	TweenService:Create(spot, TweenInfo.new(2.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Transparency = 1, Color = TOXIC_DEEP }):Play()
	-- The acid eats into the floor: a quick hiss of pale smoke and a spit of droplets.
	local smoke = smokeEmitter(spot, {
		Color = ColorSequence.new(ACID_SMOKE, ACID_GREY),
		LightEmission = .15,
		LightInfluence = .8,
		Size = seq(0, .8 * k, .4, 2.2 * k, 1, 3.4 * k),
		Transparency = seq(0, .25, .6, .6, 1, 1),
		Lifetime = NumberRange.new(.9, 1.6),
		Speed = NumberRange.new(3 * k, 6 * k),
		SpreadAngle = Vector2.new(18, 18),
		Acceleration = Vector3.new(0, 2, 0),
		Drag = 1.5,
		EmissionDirection = Enum.NormalId.Right, -- the disc's X axis is world up
		Enabled = false,
	})
	smoke:Emit(4)
	local spit = Instance.new("ParticleEmitter")
	spit.Texture = SPARK
	spit.Color = ColorSequence.new(TOXIC)
	spit.LightEmission = .7
	spit.Orientation = Enum.ParticleOrientation.VelocityParallel
	spit.Size = seq(0, .25 * k, 1, 0)
	spit.Lifetime = NumberRange.new(.2, .4)
	spit.Speed = NumberRange.new(6 * k, 11 * k)
	spit.SpreadAngle = Vector2.new(70, 70)
	spit.Acceleration = Vector3.new(0, -50, 0)
	spit.EmissionDirection = Enum.NormalId.Right
	spit.Enabled = false
	spit.Parent = spot
	spit:Emit(5)
	task.delay(2.6, function() spot:Destroy() end)
end

local function newDrop(s, k)
	local p = anchored("Drool", s.folder)
	p.Shape = Enum.PartType.Ball
	p.Material = Enum.Material.Glass
	p.Color = TOXIC
	p.Transparency = .2
	p.Reflectance = .3
	local a0 = Instance.new("Attachment"); a0.Parent = p
	local a1 = Instance.new("Attachment"); a1.Parent = p
	-- A short trail stretches each drop into a strand while it falls.
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Color = ColorSequence.new(TOXIC, TOXIC_DEEP)
	trail.LightEmission = .35
	trail.Lifetime = .12
	trail.FaceCamera = true
	trail.WidthScale = seq(0, 1, 1, .2)
	trail.Transparency = seq(0, .2, 1, 1)
	trail.Parent = p
	return { part = p, a0 = a0, a1 = a1, trail = trail, k = k }
end

local function spawnDrop(s, from, forward, k)
	if #s.drops >= MAX_DROPS then return end
	local drop = table.remove(s.dropPool) or newDrop(s, k)
	local size = (.35 + math.random() * .35) * k
	drop.part.Size = Vector3.new(size, size * 1.35, size)
	drop.a0.Position, drop.a1.Position = Vector3.new(size * .4, 0, 0), Vector3.new(-size * .4, 0, 0)
	drop.part.CFrame = CFrame.new(from)
	drop.trail.Enabled = false
	drop.trail:Clear()
	drop.trail.Enabled = true
	drop.part.Transparency = .2
	drop.pos = from
	drop.vel = forward * (1 + math.random() * 2.5) * k + Vector3.new(0, -math.random() * 2, 0)
	drop.floorY = floorAt(s, from + forward * 2 * k, s.floorY or (from.Y - 20))
	drop.k = k
	table.insert(s.drops, drop)
end

local function stepDrops(s, dt, parts, cframes)
	for i = #s.drops, 1, -1 do
		local drop = s.drops[i]
		drop.vel += Vector3.new(0, -DROP_GRAVITY * dt, 0)
		drop.pos += drop.vel * dt
		if drop.pos.Y <= drop.floorY then
			local landing = Vector3.new(drop.pos.X, drop.floorY, drop.pos.Z)
			splat(s, landing, drop.k)
			drop.part.Transparency = 1
			drop.part.CFrame = CFrame.new(0, -10000, 0)
			table.remove(s.drops, i)
			table.insert(s.dropPool, drop)
		else
			table.insert(parts, drop.part)
			table.insert(cframes, CFrame.new(drop.pos))
		end
	end
end

----------------------------------------------------------------------
-- Trail puddles
----------------------------------------------------------------------

local function spawnPuddle(s, position, k)
	local puddle
	if #s.puddles >= MAX_PUDDLES then
		puddle = table.remove(s.puddles, 1) -- recycle the oldest
	else
		local rim = disc("PoisonPuddleRim", s.folder, TOXIC_DEEP, .55)
		local core = disc("PoisonPuddle", s.folder, POISON_DARK, .15)
		local fumes = smokeEmitter(core, {
			Color = ColorSequence.new(TOXIC, POISON_MID),
			LightEmission = .2,
			LightInfluence = .7,
			Size = seq(0, 1 * k, 1, 3 * k),
			Transparency = seq(0, .55, .5, .7, 1, 1),
			Lifetime = NumberRange.new(1.2, 2),
			Speed = NumberRange.new(1, 2.5),
			SpreadAngle = Vector2.new(30, 30),
			Acceleration = Vector3.new(0, 1.5, 0),
			EmissionDirection = Enum.NormalId.Right,
			Rate = 1.5,
		})
		puddle = { rim = rim, core = core, fumes = fumes }
	end
	local d = (.45 + math.random() * .3) * 46 * s.scale * (s.ratio or 1) -- 0.45..0.75 of the base radius
	puddle.diameter = d
	puddle.born = os.clock()
	puddle.base = CFrame.new(position + Vector3.new(0, .05 + #s.puddles * .002, 0))
		* CFrame.Angles(0, math.random() * math.pi * 2, 0) * FLAT
	puddle.fumes.Enabled = true
	table.insert(s.puddles, puddle)
end

local function stepPuddles(s, now, parts, cframes)
	for i = #s.puddles, 1, -1 do
		local puddle = s.puddles[i]
		local age = now - puddle.born
		if age >= PUDDLE_LIFE then
			puddle.rim:Destroy(); puddle.core:Destroy()
			table.remove(s.puddles, i)
		else
			local grow = math.min(1, age / .35)
			local dry = math.clamp((age - (PUDDLE_LIFE - PUDDLE_FADE)) / PUDDLE_FADE, 0, 1)
			local d = puddle.diameter * (.5 + .5 * grow) * (1 - .35 * dry)
			-- A squashed oval: the core inside a wider, paler rim.
			puddle.core.Size = Vector3.new(.1, d, d * .78)
			puddle.rim.Size = Vector3.new(.08, d * 1.14, d * .9)
			puddle.core.Transparency = .15 + .85 * dry
			puddle.rim.Transparency = .55 + .45 * dry
			puddle.fumes.Enabled = dry < .3
			table.insert(parts, puddle.core); table.insert(cframes, puddle.base * CFrame.new(.01, 0, 0))
			table.insert(parts, puddle.rim); table.insert(cframes, puddle.base)
		end
	end
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

function AuraFX.Quench(seconds)
	quenchUntil = os.clock() + math.max(0, tonumber(seconds) or 0)
end

function AuraFX.Restore()
	quenchUntil = 0
end

function AuraFX.Stop()
	local s = active
	if not s then return end
	active = nil
	if s.conn then s.conn:Disconnect() end
	for _, e in ipairs(s.emitters) do e.Enabled = false end
	for _, puddle in ipairs(s.puddles) do puddle.fumes.Enabled = false end
	for _, eye in ipairs(s.eyes) do eye.trail.Enabled = false end
	if s.light then s.light.Enabled = false end
	if s.eyeLight then s.eyeLight.Enabled = false end
	local folder = s.folder
	task.delay(3, function() folder:Destroy() end) -- let the vapour drift out
end

function AuraFX.Start(boss, parent)
	if typeof(boss) ~= "Instance" or not boss:IsA("Model") or not boss.Parent then return end
	if active and active.boss == boss then return end
	AuraFX.Stop()
	local root = boss.PrimaryPart
	local skin = skinOf(boss)
	if not root or not skin then return end

	local folder = Instance.new("Folder")
	folder.Name = "MiasmaAura"
	folder.Parent = parent or Workspace
	local s = {
		boss = boss, folder = folder, skin = skin, emitters = {}, vents = {}, fangs = {}, eyes = {},
		drops = {}, dropPool = {}, puddles = {}, bones = {},
		scale = skin.Size.X / AUTHORED_WIDTH, startWidth = skin.Size.X,
	}
	s.params = floorParams(boss, folder)
	for _, d in ipairs(boss:GetDescendants()) do
		if d:IsA("Bone") then s.bones[d.Name] = d end
	end
	local k = s.scale / TUNED_SCALE -- particle sizes were tuned at ModelScale 0.45

	for _, entry in ipairs(VENTS) do
		local p = anchored("Vent", folder)
		local low = entry[4] < 10
		table.insert(s.vents, { part = p, anchor = makeAnchor(s, entry) })
		-- The skirt vents hug the floor and roll outward; the upper ones rise off the body.
		table.insert(s.emitters, smokeEmitter(p, {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, TOXIC),
				ColorSequenceKeypoint.new(.35, POISON_MID),
				ColorSequenceKeypoint.new(1, POISON_DARK),
			}),
			LightEmission = .12,
			LightInfluence = .85,
			Size = seq(0, 2 * k, .5, 5 * k, 1, 7.5 * k),
			Transparency = seq(0, 1, .15, .35, .7, .6, 1, 1),
			Lifetime = low and NumberRange.new(2.2, 3.2) or NumberRange.new(1.6, 2.6),
			Speed = low and NumberRange.new(1.5, 3) or NumberRange.new(.8, 2),
			SpreadAngle = low and Vector2.new(80, 80) or Vector2.new(35, 35),
			Acceleration = Vector3.new(0, low and .8 or 2.2, 0),
			Drag = .6,
			EmissionDirection = Enum.NormalId.Top,
			Rate = low and 3.5 or 2.5,
		}))
	end
	for _, entry in ipairs(FANGS) do
		table.insert(s.fangs, makeAnchor(s, entry))
	end
	-- The eyes: a glowing core on each, and a light streak that trails it (Trail between two
	-- attachments, facing the camera). Riding the Head bone, they sweep with every lunge.
	for i, e in ipairs(EYES) do
		local size = e[7]
		local p = anchored("Eye", folder)
		local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
		a0.Position, a1.Position = Vector3.new(0, .28 * k * size, 0), Vector3.new(0, -.28 * k * size, 0)
		a0.Parent, a1.Parent = p, p
		local trail = Instance.new("Trail")
		trail.Attachment0, trail.Attachment1 = a0, a1
		trail.FaceCamera = true
		trail.Lifetime = EYE_TRAIL_LIFETIME
		trail.MinLength = .05
		trail.LightEmission = 1
		trail.LightInfluence = 0
		trail.Brightness = 3
		trail.Color = ColorSequence.new(EYE_CORE, EYE_EDGE)
		trail.Transparency = seq(0, .05, .5, .45, 1, 1)
		trail.WidthScale = seq(0, 1, 1, .1)
		trail.Parent = p
		local glow = Instance.new("ParticleEmitter")
		glow.Texture = HudArt.GLOW_SOFT
		glow.LockedToPart = true
		glow.Rate = 30
		glow.Lifetime = NumberRange.new(.15, .2)
		glow.Speed = NumberRange.new(0)
		glow.Size = seq(0, 1.5 * k * size, 1, 1.1 * k * size)
		glow.Transparency = seq(0, .1, 1, .55)
		glow.LightEmission = 1
		glow.LightInfluence = 0
		glow.Brightness = 2
		glow.ZOffset = .5
		glow.Color = ColorSequence.new(EYE_CORE)
		glow.Parent = p
		table.insert(s.emitters, glow)
		local lifted = { "Head", e[1] + e[4] * EYE_LIFT, e[2] + e[5] * EYE_LIFT, e[3] + e[6] * EYE_LIFT }
		table.insert(s.eyes, { part = p, trail = trail, anchor = makeAnchor(s, lifted) })
		if i == 1 then
			-- One light, on the big eye: a green cast over the crown and fangs.
			local eyeLight = Instance.new("PointLight")
			eyeLight.Color = EYE_CORE
			eyeLight.Range = 9 * k
			eyeLight.Brightness = 1.4
			eyeLight.Shadows = false
			eyeLight.Parent = p
			s.eyeLight = eyeLight
		end
	end
	-- Jaw bones for the mouth: how open it is and which way it faces.
	local front, core, upper = s.bones[JAW_FRONT], s.bones[JAW_CORE], s.bones[UPPER_FRONT]

	-- A sickly glow inside the maw, lighting the fangs and the floor in front of it.
	local glowPart = anchored("MawGlow", folder)
	local light = Instance.new("PointLight")
	light.Color = TOXIC
	light.Range = 16 * k
	light.Brightness = 1.2
	light.Shadows = false
	light.Parent = glowPart
	s.light = light

	active = s
	s.started = os.clock()
	local nextFloor, dropDebt = 0, 0
	local lastTrail
	local parts, cframes = {}, {}
	local quench = 0 -- 0 = full menace, 1 = put out by the holy water
	s.conn = RunService.RenderStepped:Connect(function(dt)
		if not boss.Parent or not root.Parent or not skin.Parent then AuraFX.Stop() return end
		dt = math.min(dt or 0, .1)
		local now = os.clock()
		local centre = root.Position
		if now >= nextFloor then
			nextFloor = now + FLOOR_CHECK_EVERY
			s.params = floorParams(boss, folder)
			local rootBone = s.bones.Root
			s.standingFloorY = rootBone and rootBone.Parent and rootBone.WorldPosition.Y or nil
			s.floorY = floorAt(s, centre, s.standingFloorY or (centre.Y - 15 * k))
		end
		local ratio = skin.Size.X / s.startWidth -- the stun shrink
		s.ratio = ratio
		local hidden = skin.Transparency >= .99 -- submerged / not revealed yet
		quench += ((now < quenchUntil and 1 or 0) - quench) * math.min(1, dt * 2.5)
		local off = hidden and 1 or quench
		local live = off < .5
		for _, e in ipairs(s.emitters) do e.Enabled = live end

		table.clear(parts); table.clear(cframes)
		for _, vent in ipairs(s.vents) do
			table.insert(parts, vent.part)
			table.insert(cframes, CFrame.new(anchorPosition(s, vent.anchor, ratio)))
		end
		-- The eyes turn with the head (the streak's width axis is the part's up).
		local headBone = s.bones.Head
		local headTurn = headBone and headBone.Parent and headBone.TransformedWorldCFrame.Rotation or CFrame.identity
		for _, eye in ipairs(s.eyes) do
			-- Cleared when it comes back on: it may have moved while hidden (the submerge slam
			-- relocates it), and a streak must never join the old spot to the new one.
			if eye.live ~= live then
				eye.live = live
				eye.trail.Enabled = live
				if live then eye.trail:Clear() end
			end
			table.insert(parts, eye.part)
			table.insert(cframes, CFrame.new(anchorPosition(s, eye.anchor, ratio)) * headTurn)
		end
		if s.eyeLight then s.eyeLight.Enabled = live end

		-- The maw: open-ness from the jaw bones, facing from the lower jaw's front vs its core.
		local forward = root.CFrame.LookVector
		local open = 0
		local mouth
		if front and front.Parent and upper and upper.Parent then
			local jaw, top = front.TransformedWorldCFrame.Position, upper.TransformedWorldCFrame.Position
			mouth = (jaw + top) * .5
			local gap = (top - jaw):Dot(root.CFrame.UpVector) / (s.scale * ratio)
			open = math.clamp((gap - GAP_SHUT) / (GAP_WIDE - GAP_SHUT), 0, 1)
			if core and core.Parent then
				local flat = jaw - core.TransformedWorldCFrame.Position
				if Vector3.new(flat.X, 0, flat.Z).Magnitude > .01 then forward = flat end
			end
		end
		forward = Vector3.new(forward.X, 0, forward.Z)
		forward = forward.Magnitude > .01 and forward.Unit or Vector3.new(0, 0, -1)
		mouth = mouth or (centre + forward * 20 * k)
		light.Enabled = live
		light.Brightness = 1 + open * 2.5
		table.insert(parts, glowPart)
		table.insert(cframes, CFrame.new(mouth + forward * 3 * k))

		-- Drool, faster the wider it gapes.
		if live and #s.fangs > 0 then
			dropDebt += dt * (DROOL_RATE_REST + (DROOL_RATE_OPEN - DROOL_RATE_REST) * open)
			while dropDebt >= 1 do
				dropDebt -= 1
				local fang = s.fangs[math.random(1, #s.fangs)]
				local from = anchorPosition(s, fang, ratio) + forward * DROP_OUT * s.scale * ratio
				spawnDrop(s, from, forward, k * ratio)
			end
		else
			dropDebt = 0
		end
		stepDrops(s, dt, parts, cframes)

		-- The trail: a puddle every TRAIL_STEP studs it slithers, dropped at its back edge.
		local flatCentre = Vector3.new(centre.X, 0, centre.Z)
		if not lastTrail then lastTrail = flatCentre end
		local moved = flatCentre - lastTrail
		local step = TRAIL_STEP * k * ratio
		if moved.Magnitude >= step then
			lastTrail = flatCentre
			if live then
				local back = -moved.Unit
				local side = Vector3.new(-back.Z, 0, back.X)
				local bodyRadius = 46 * s.scale * ratio
				local spot = centre + back * bodyRadius * (.55 + math.random() * .3)
					+ side * bodyRadius * (math.random() - .5) * .9
				local y = floorAt(s, spot, s.floorY or (centre.Y - 15 * k))
				spawnPuddle(s, Vector3.new(spot.X, y, spot.Z), k * ratio)
			end
		end
		stepPuddles(s, now, parts, cframes)

		Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end)
end

return AuraFX
