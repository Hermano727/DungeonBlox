--[[
	FireTornadoVFX -- client visuals for Kane's Fire Tornado (draw only: the server owns the hitbox,
	damage and timing, see SSS/FireTornadoCast). Timeline and path come from RS/FireTornadoConfig,
	evaluated against workspace:GetServerTimeNow(), so what you see is where the hitbox is.

	Layers, in the order they play:
	  CHANNEL (0 .. WINDUP)
	    - ALERT_DOUBLE "!!" above the caster's head: pops in, pulses and trembles
	    - CHANNEL_SIGIL on the ground: grows and heats from dark red to hot orange, turning slowly
	    - the four paths: dashes light up from the caster outward (the telegraph)
	    - sparks rush inward to the caster, embers rise, a light swells
	    (meanwhile the server plays Kane's Groundbreaker Slam wind-up on the caster)
	  RELEASE = the slam's impact, at the impact point just in front of the caster
	    - the ground breaks: ground-matched slabs and flung rocks (MiasmaLandingSlamFX.Crumble)
	    - a column of fire plus eight jets licking outward, a flash
	    - SHOCK_RING bursts out, sparks spray, smoke, the KaneGroundSlam sound, camera shake
	  TORNADOES (WINDUP .. +TRAVEL), no mesh: the column is drawn by STRANDS, invisible points
	  that orbit the axis while climbing the funnel profile (RS/FireTornadoConfig FunnelRadius,
	  AxisOffset), each dragging a glowing Trail, so dozens of spiral strokes make the tornado.
	    - strand groups inside out: hot thin core, the silhouette (many slow-climbing rings on the
	      funnel surface), dark-red outer sheets, wind (thin pale streaks whipping around outside),
	      smoke wisps
	    - a spinning swirl on the ground, smoke at the base, embers up the column, sparks flung
	      off the lip, a flickering light, the FireTornadoWind loop (positional)
	    No tall beams: three of them read as three little tornadoes inside the big one.
	    - the drag: the local player is pulled into nearby tornadoes and carried along (dragLocalPlayer)
	  COLLAPSE (+COLLAPSE)
	    - shrinks where it ended, then a small shock ring + spark burst

	One RenderStepped connection runs every live cast; it disconnects when none are left.
]]

local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local localPlayer = Players.LocalPlayer

local Config = require(ReplicatedStorage:WaitForChild("FireTornadoConfig"))
local WorldVfx = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images"):WaitForChild("WorldVfx"))
local ArenaShake = require(script.Parent:WaitForChild("ArenaShake"))
local CastEvent = ReplicatedStorage:WaitForChild("GameEvents"):WaitForChild("FireTornadoCast")
local LandingSlamFX = require(script.Parent:WaitForChild("MiasmaLandingSlamFX"))
local SfxService = require(ReplicatedStorage:WaitForChild("SfxService"))
local SoundEffects = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Sounds"):WaitForChild("SoundEffects"))

local FIRE_TEXTURE = "rbxasset://textures/particles/fire_main.dds" -- Roblox's built-in flame

local V = Config.VISUAL

task.spawn(function()
	local list = {}
	for _, key in ipairs({ "SMOKE_PUFF_4X4", "FLAME_STREAK", "SPARK", "SHOCK_RING", "CHANNEL_SIGIL", "ALERT_DOUBLE" }) do
		table.insert(list, WorldVfx[key])
	end
	pcall(ContentProvider.PreloadAsync, ContentProvider, list)
end)

---------------------------------------------------------------- small helpers

local function seq(points)
	local keys = {}
	for _, p in ipairs(points) do
		table.insert(keys, NumberSequenceKeypoint.new(p[1], p[2], p[3] or 0))
	end
	return NumberSequence.new(keys)
end

local function colors(points)
	local keys = {}
	for _, p in ipairs(points) do
		table.insert(keys, ColorSequenceKeypoint.new(p[1], p[2]))
	end
	return ColorSequence.new(keys)
end

local FIRE_SEQ = colors({ { 0, V.HOT_COLOR }, { 0.35, V.FIRE_COLOR }, { 1, V.EMBER_COLOR } })

local function easeOutBack(x)
	local c1 = 1.70158
	local c3 = c1 + 1
	return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

local function easeOut(x)
	return 1 - (1 - x) ^ 2
end

local function ghostPart(name, size, cframe, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Transparency = 1
	part.Parent = parent
	return part
end

-- A flat image lying on the ground: a thin invisible part with the texture on its top face.
local function groundDecal(name, texture, size, position, parent)
	local part = ghostPart(name, Vector3.new(size, 0.05, size), CFrame.new(position), parent)
	local decal = Instance.new("Decal")
	decal.Texture = texture
	decal.Face = Enum.NormalId.Top
	decal.Transparency = 1
	decal.Parent = part
	return part, decal
end

local function sparkEmitter(props)
	local e = Instance.new("ParticleEmitter")
	e.Texture = WorldVfx.SPARK
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Orientation = Enum.ParticleOrientation.VelocityParallel
	e.Color = FIRE_SEQ
	e.Enabled = false
	for k, v in pairs(props) do
		e[k] = v
	end
	return e
end

local function smokeEmitter(props)
	local e = Instance.new("ParticleEmitter")
	e.Texture = WorldVfx.SMOKE_PUFF_4X4
	e.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
	e.FlipbookMode = Enum.ParticleFlipbookMode.Random
	e.Color = ColorSequence.new(V.SMOKE_COLOR)
	e.LightEmission = 0
	e.LightInfluence = 0.6
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-40, 40)
	e.Enabled = false
	for k, v in pairs(props) do
		e[k] = v
	end
	return e
end

-- One-shot: an expanding ring on the ground.
local function shockRing(position, fromSize, toSize, duration, parent)
	local part, decal = groundDecal("ShockRing", WorldVfx.SHOCK_RING, fromSize, position + Vector3.new(0, 0.1, 0), parent)
	decal.Color3 = V.FIRE_COLOR
	decal.Transparency = 0.05
	local info = TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	TweenService:Create(part, info, { Size = Vector3.new(toSize, 0.05, toSize), CFrame = part.CFrame * CFrame.Angles(0, math.rad(50), 0) }):Play()
	TweenService:Create(decal, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1, Color3 = V.EMBER_COLOR }):Play()
	Debris:AddItem(part, duration + 0.1)
end

-- One-shot: sparks sprayed outward plus a puff of smoke.
local function burst(position, sparks, smoke, speed, parent)
	local part = ghostPart("Burst", Vector3.new(1, 1, 1), CFrame.new(position + Vector3.new(0, 1, 0)), parent)
	local s = sparkEmitter({
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
		Speed = NumberRange.new(speed * 0.5, speed),
		Lifetime = NumberRange.new(0.35, 0.7),
		Size = seq({ { 0, 1.6 }, { 1, 0.2 } }),
		Transparency = seq({ { 0, 0 }, { 0.7, 0.2 }, { 1, 1 } }),
		Drag = 4,
	})
	s.Parent = part
	s:Emit(sparks)
	if smoke > 0 then
		local m = smokeEmitter({
			Shape = Enum.ParticleEmitterShape.Sphere,
			ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
			Speed = NumberRange.new(4, 9),
			Lifetime = NumberRange.new(0.9, 1.5),
			Size = seq({ { 0, 2 }, { 1, 6 } }),
			Transparency = seq({ { 0, 0.3 }, { 0.6, 0.55 }, { 1, 1 } }),
			Drag = 3,
			Acceleration = Vector3.new(0, 3, 0),
		})
		m.Parent = part
		m:Emit(smoke)
	end
	Debris:AddItem(part, 2)
end

---------------------------------------------------------------- the channel

local function buildChannel(cast, folder)
	local ch = {}

	-- "!!" over the caster's head
	local caster = cast.caster
	local anchor = caster and caster.PrimaryPart
	if anchor then
		local boxCFrame, boxSize = caster:GetBoundingBox()
		local top = boxCFrame.Position.Y + boxSize.Y / 2 - anchor.Position.Y
		local gui = Instance.new("BillboardGui")
		gui.Name = "FireTornadoAlert"
		gui.Adornee = anchor
		gui.Size = UDim2.fromScale(2.4, 3.6) -- studs; the art is 676x1024
		gui.StudsOffsetWorldSpace = Vector3.new(0, top + 2.6, 0)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.MaxDistance = 220
		local image = Instance.new("ImageLabel")
		image.BackgroundTransparency = 1
		image.Size = UDim2.fromScale(1, 1)
		image.Image = WorldVfx.ALERT_DOUBLE
		image.ScaleType = Enum.ScaleType.Fit
		image.Parent = gui
		local scale = Instance.new("UIScale")
		scale.Scale = 0
		scale.Parent = image
		gui.Parent = folder
		ch.alert, ch.alertImage, ch.alertScale = gui, image, scale
	end

	-- the heating ground sigil
	ch.sigil, ch.sigilDecal = groundDecal("Sigil", WorldVfx.CHANNEL_SIGIL, V.SIGIL_SIZE * 0.55, cast.origin + Vector3.new(0, 0.08, 0), folder)

	-- path telegraph: dashes along each tornado's route, lighting up outward
	ch.dashes = {}
	for index = 0, Config.COUNT - 1 do
		for k = 1, V.PATH_DASHES do
			local tA = (k - 0.5) / V.PATH_DASHES * Config.TRAVEL
			local a = Config.PathPoint(cast.origin, cast.angle, index, tA)
			local b = Config.PathPoint(cast.origin, cast.angle, index, tA + 0.05)
			local dash = ghostPart("Dash", Vector3.new(0.55, 0.06, 1.5), CFrame.lookAt(a, b) + Vector3.new(0, 0.08, 0), folder)
			dash.Material = Enum.Material.Neon
			dash.Color = V.FIRE_COLOR
			table.insert(ch.dashes, { part = dash, revealAt = (k / V.PATH_DASHES) * 0.7 })
		end
	end

	-- sparks rushing in from the rim, embers rising, a light swelling
	local source = ghostPart("ChannelSource", Vector3.new(V.SIGIL_SIZE * 0.9, 0.2, V.SIGIL_SIZE * 0.9), CFrame.new(cast.origin + Vector3.new(0, 0.4, 0)), folder)
	ch.inward = sparkEmitter({
		Shape = Enum.ParticleEmitterShape.Disc,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		EmissionDirection = Enum.NormalId.Top,
		Speed = NumberRange.new(16, 22),
		Lifetime = NumberRange.new(0.45, 0.6),
		Size = seq({ { 0, 0.5 }, { 0.5, 1.4 }, { 1, 0.3 } }),
		Transparency = seq({ { 0, 1 }, { 0.2, 0.1 }, { 1, 0.6 } }),
		Rate = 15,
		Enabled = true,
	})
	ch.inward.Parent = source
	ch.rising = sparkEmitter({
		EmissionDirection = Enum.NormalId.Top,
		Speed = NumberRange.new(3, 7),
		SpreadAngle = Vector2.new(15, 15),
		Acceleration = Vector3.new(0, 5, 0),
		Lifetime = NumberRange.new(0.9, 1.5),
		Size = seq({ { 0, 0.4 }, { 1, 0.1 } }),
		Transparency = seq({ { 0, 0.2 }, { 1, 1 } }),
		Rate = 10,
		Enabled = true,
	})
	ch.rising.Parent = source
	ch.light = Instance.new("PointLight")
	ch.light.Color = V.FIRE_COLOR
	ch.light.Range = 20
	ch.light.Brightness = 0
	ch.light.Shadows = false
	ch.light.Parent = source
	ch.source = source
	return ch
end

local function updateChannel(cast, ch, now)
	local elapsed = now - cast.startAt
	local p = math.clamp(elapsed / Config.WINDUP, 0, 1)

	if ch.alert then
		local pop = elapsed < 0.22 and math.max(0, easeOutBack(elapsed / 0.22)) or 1
		ch.alertScale.Scale = pop * (1 + 0.07 * math.sin(now * 16))
		ch.alertImage.Rotation = 5 * math.sin(now * 23) * p
	end

	local size = V.SIGIL_SIZE * (0.55 + 0.45 * easeOut(p))
	ch.sigil.Size = Vector3.new(size, 0.05, size)
	ch.sigil.CFrame = CFrame.new(cast.origin + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, elapsed * 0.8, 0)
	ch.sigilDecal.Transparency = 1 - 0.9 * math.min(1, elapsed / 0.35)
	ch.sigilDecal.Color3 = p < 0.6 and V.DARK_COLOR:Lerp(V.FIRE_COLOR, p / 0.6) or V.FIRE_COLOR:Lerp(V.HOT_COLOR, (p - 0.6) / 0.4)

	for _, dash in ipairs(ch.dashes) do
		if p >= dash.revealAt then
			dash.part.Transparency = 0.25 + 0.2 * math.sin(now * 14 + dash.revealAt * 30)
		end
	end

	ch.inward.Rate = 15 + 95 * p
	ch.rising.Rate = 10 + 30 * p
	ch.light.Brightness = 0.5 + 5 * p
end

local function fadeChannel(ch, instant)
	if ch.done then return end
	ch.done = true
	ch.inward.Enabled = false
	ch.rising.Enabled = false
	if instant then return end
	local info = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	if ch.alert then
		TweenService:Create(ch.alertImage, TweenInfo.new(0.15), { ImageTransparency = 1 }):Play()
	end
	TweenService:Create(ch.sigilDecal, TweenInfo.new(0.6), { Transparency = 1 }):Play()
	TweenService:Create(ch.light, info, { Brightness = 0 }):Play()
	for _, dash in ipairs(ch.dashes) do
		TweenService:Create(dash.part, info, { Transparency = 1 }):Play()
	end
end

---------------------------------------------------------------- the tornadoes

local function strandTrail(group, a0, a1, parent)
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	if group.textured then
		trail.Texture = WorldVfx.FLAME_STREAK
		trail.TextureMode = Enum.TextureMode.Stretch
	end
	trail.Lifetime = group.lifetime
	trail.MinLength = 0.05
	trail.FaceCamera = true
	trail.LightEmission = group.emission
	trail.LightInfluence = 1 - group.emission
	trail.Color = colors({ { 0, group.colorFrom }, { 1, group.colorTo } })
	trail.Transparency = seq({ { 0, group.transparency }, { 0.6, math.min(1, group.transparency + 0.15) }, { 1, 1 } })
	trail.WidthScale = seq({ { 0, 1 }, { 1, 0.15 } })
	trail.Parent = parent
	return trail
end

local function buildTornado(cast, index, folder)
	local tw = { index = index }

	-- Everything hangs off one unrotated carrier at the tornado's base, so attachment positions
	-- are plain world-aligned offsets from the ground point.
	local carrier = ghostPart("Carrier", Vector3.new(4.5, 1, 4.5), CFrame.new(cast.origin), folder)
	tw.carrier = carrier

	tw.strands = {}
	local rng = Random.new(cast.id * 31 + index)
	for _, group in ipairs(V.STRANDS) do
		for n = 1, group.count do
			local a0 = Instance.new("Attachment")
			local a1 = Instance.new("Attachment")
			a0.Parent, a1.Parent = carrier, carrier
			table.insert(tw.strands, {
				group = group,
				a0 = a0,
				a1 = a1,
				trail = strandTrail(group, a0, a1, carrier),
				theta = rng:NextNumber(0, 2 * math.pi),
				-- spread evenly up the column so it is full from the first frame
				h0 = (n - 1) / group.count + rng:NextNumber(0, 0.5 / group.count),
				speed = rng:NextNumber(0.85, 1.15),
				jitter = rng:NextNumber(0, 2 * math.pi),
			})
		end
	end

	tw.swirl, tw.swirlDecal = groundDecal("BaseSwirl", WorldVfx.SHOCK_RING, 1, cast.origin, folder)
	tw.swirlDecal.Color3 = V.EMBER_COLOR
	tw.swirlDecal.Transparency = 0.3

	tw.smoke = smokeEmitter({
		EmissionDirection = Enum.NormalId.Top,
		Speed = NumberRange.new(2, 4),
		SpreadAngle = Vector2.new(35, 35),
		Lifetime = NumberRange.new(1.1, 1.7),
		Size = seq({ { 0, 2.4 }, { 1, 6 } }),
		Transparency = seq({ { 0, 1 }, { 0.15, 0.4 }, { 0.6, 0.6 }, { 1, 1 } }),
		Acceleration = Vector3.new(0, 2.5, 0),
		Drag = 1,
		Rate = 12,
		ZOffset = -1,
		Enabled = true,
	})
	tw.smoke.Parent = carrier
	tw.embers = sparkEmitter({
		EmissionDirection = Enum.NormalId.Top,
		Speed = NumberRange.new(7, 13),
		SpreadAngle = Vector2.new(25, 25),
		Acceleration = Vector3.new(0, 4, 0),
		Lifetime = NumberRange.new(0.7, 1.3),
		Size = seq({ { 0, 0.5 }, { 1, 0.1 } }),
		Transparency = seq({ { 0, 0.1 }, { 0.8, 0.4 }, { 1, 1 } }),
		Rate = 30,
		Enabled = true,
	})
	tw.embers.Parent = carrier
	tw.lip = Instance.new("Attachment")
	tw.lip.Parent = carrier
	tw.lipSparks = sparkEmitter({
		EmissionDirection = Enum.NormalId.Top,
		Speed = NumberRange.new(8, 14),
		SpreadAngle = Vector2.new(75, 75),
		Acceleration = Vector3.new(0, -8, 0),
		Lifetime = NumberRange.new(0.4, 0.7),
		Size = seq({ { 0, 0.7 }, { 1, 0.15 } }),
		Transparency = seq({ { 0, 0 }, { 0.7, 0.3 }, { 1, 1 } }),
		Drag = 2,
		Rate = 18,
		Enabled = true,
	})
	tw.lipSparks.Parent = tw.lip
	tw.light = Instance.new("PointLight")
	tw.light.Color = V.FIRE_COLOR
	tw.light.Range = 18
	tw.light.Brightness = 0
	tw.light.Shadows = false
	tw.light.Parent = carrier

	-- wind howling around each tornado, positional (not PlayEffect: that one is one-shot only)
	local windId = SoundEffects.FireTornadoWind
	if type(windId) == "string" and windId ~= "" then
		local wind = Instance.new("Sound")
		wind.Name = "Wind"
		wind.SoundId = windId
		wind.Looped = true
		wind.Volume = 0.55
		wind.PlaybackSpeed = 0.94 + 0.04 * index -- four tornadoes don't phase into one drone
		wind.RollOffMinDistance = 10
		wind.RollOffMaxDistance = 90
		wind.SoundGroup = SfxService.GetGroupFor("FireTornadoWind") -- the Creatures slider
		wind.Parent = carrier
		wind:Play()
		tw.wind = wind
	end
	return tw
end

-- 0..1 of full size: grows in with a little overshoot, collapses at the end of the path.
local function sizeAt(t)
	if t < V.GROW_TIME then
		return math.max(0.05, easeOutBack(t / V.GROW_TIME))
	elseif t < Config.TRAVEL then
		return 1
	end
	local c = math.clamp((t - Config.TRAVEL) / Config.COLLAPSE, 0, 1)
	return math.max(0.05, 1 - c * c)
end

-- Strands thin out to nothing at the ground and the lip, so the wrap from the top back to the
-- bottom never shows.
local function strandTaper(h)
	return math.clamp(h / 0.08, 0, 1) * math.clamp((1 - h) / 0.12, 0, 1)
end

local function updateTornado(cast, tw, now, dt, folder)
	local t = now - cast.releaseAt
	local pos = Config.PathPoint(cast.origin, cast.angle, tw.index, math.min(t, Config.TRAVEL))
	local k = sizeAt(t)
	local spin = t * V.SPIN_SPEED
	local height = V.HEIGHT * k

	tw.carrier.CFrame = CFrame.new(pos)

	for _, st in ipairs(tw.strands) do
		local g = st.group
		local h = (st.h0 + g.rise * st.speed * t) % 1
		if st.lastH and h < st.lastH then
			st.trail:Clear() -- wrapped back to the ground: don't draw a stroke down the column
		end
		st.lastH = h
		-- narrower = faster, like a real vortex
		st.theta += g.orbit * st.speed * (1.3 - 0.45 * h) * dt
		local radius = (Config.FunnelRadius(h) * g.radius + g.pad + 0.12 * math.sin(t * 5 + st.jitter)) * k
		local axis = Config.AxisOffset(h, t) * k
		local center = Vector3.new(axis.X + math.cos(st.theta) * radius, h * height, axis.Z + math.sin(st.theta) * radius)
		local half = Vector3.new(0, g.width * k * strandTaper(h) / 2, 0)
		st.a0.Position = center + half
		st.a1.Position = center - half
	end

	local swirlSize = Config.FunnelRadius(0) * 2.4 * k
	tw.swirl.Size = Vector3.new(swirlSize, 0.05, swirlSize)
	tw.swirl.CFrame = CFrame.new(pos + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, -spin * 1.4, 0)
	tw.lip.Position = Config.AxisOffset(1, t) * k + Vector3.new(0, height, 0)
	tw.light.Brightness = (3.2 + 0.8 * math.sin(now * 19 + tw.index) + 0.5 * math.sin(now * 7.3)) * k
	tw.light.Range = 18 * math.max(k, 0.3)

	if t >= Config.TRAVEL and not tw.collapsing then
		tw.collapsing = true
		if tw.wind then
			TweenService:Create(tw.wind, TweenInfo.new(Config.COLLAPSE + 0.3), { Volume = 0 }):Play()
		end
		tw.smoke.Enabled = false
		tw.embers.Enabled = false
		tw.lipSparks.Enabled = false
	end
	if t >= Config.TRAVEL + Config.COLLAPSE then
		shockRing(pos, 3, 16, 0.4, folder)
		burst(pos, 22, 5, 26, folder)
		tw.light.Enabled = false
		tw.swirl:Destroy()
		-- the strands stop moving, so their trails finish fading on their own
		Debris:AddItem(tw.carrier, 0.6)
		tw.done = true
	end
end

---------------------------------------------------------------- casts

local casts = {}
local connection = nil

-- The Groundbreaker Slam's impact: a column of fire out of the hit, jets licking outward around
-- it, and a flash. (The ground breaking is LandingSlamFX.Crumble.)
local function slamFire(position, parent)
	local part = ghostPart("SlamFire", Vector3.new(1, 1, 1), CFrame.new(position + Vector3.new(0, 0.5, 0)), parent)
	local function fireEmitter(props)
		local e = Instance.new("ParticleEmitter")
		e.Texture = FIRE_TEXTURE
		e.Color = FIRE_SEQ
		e.LightEmission = 1
		e.LightInfluence = 0
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-90, 90)
		e.Enabled = false
		for k, v in pairs(props) do
			e[k] = v
		end
		return e
	end

	local column = fireEmitter({
		EmissionDirection = Enum.NormalId.Top,
		Speed = NumberRange.new(18, 30),
		SpreadAngle = Vector2.new(18, 18),
		Lifetime = NumberRange.new(0.4, 0.7),
		Size = seq({ { 0, 2 }, { 0.3, 5 }, { 1, 1 } }),
		Transparency = seq({ { 0, 0 }, { 0.7, 0.3 }, { 1, 1 } }),
		Acceleration = Vector3.new(0, 8, 0),
		Drag = 3,
	})
	column.Parent = part
	column:Emit(45)

	for i = 0, 7 do
		local att = Instance.new("Attachment")
		-- +Y of the attachment is the emitter's Top, tipped 40 degrees outward
		att.CFrame = CFrame.Angles(0, i / 8 * 2 * math.pi, 0) * CFrame.new(0, 0, -3.5) * CFrame.Angles(-math.rad(40), 0, 0)
		att.Parent = part
		local jet = fireEmitter({
			EmissionDirection = Enum.NormalId.Top,
			Speed = NumberRange.new(14, 22),
			SpreadAngle = Vector2.new(10, 10),
			Lifetime = NumberRange.new(0.3, 0.5),
			Size = seq({ { 0, 1.5 }, { 0.4, 3 }, { 1, 0.5 } }),
			Transparency = seq({ { 0, 0 }, { 0.6, 0.25 }, { 1, 1 } }),
			Drag = 4,
		})
		jet.Parent = att
		jet:Emit(10)
	end

	local flash = Instance.new("PointLight")
	flash.Color = V.FIRE_COLOR
	flash.Range = 26
	flash.Brightness = 8
	flash.Shadows = false
	flash.Parent = part
	TweenService:Create(flash, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()
	Debris:AddItem(part, 2)
end

local function release(cast)
	cast.released = true
	fadeChannel(cast.channel, false)
	Debris:AddItem(cast.channelFolder, 1)

	-- the slam
	local impact = cast.impact
	LandingSlamFX.Crumble(impact, V.CRUMBLE_RADIUS, V.CRUMBLE_SCALE, cast.caster, cast.folder)
	slamFire(impact, cast.folder)
	shockRing(impact, 5, 36, 0.55, cast.folder)
	burst(impact, 55, 14, 40, cast.folder)
	SfxService.PlayEffect("KaneGroundSlam", { Position = impact, Volume = 1.4, RollOffMinDistance = 15, RollOffMaxDistance = 220 })
	ArenaShake.Shake({ amplitude = 0.9, rotation = 1.1, duration = 0.1, decay = 0.6, frequency = 18,
		focus = impact, fullRadius = 25, farRadius = 90, farStrength = 0.2 })
	cast.tornadoes = {}
	for index = 0, Config.COUNT - 1 do
		cast.tornadoes[index + 1] = buildTornado(cast, index, cast.folder)
	end
end

-- The drag: this client's own character is pulled toward every active tornado near it and carried
-- along with it (RS/FireTornadoConfig PULL_*, CARRY). Done here, not on the server, because each
-- player owns their character's physics: a server push would arrive late and stutter. It runs off
-- the same PathPoint as the server's hitbox, so the pull leads into exactly where the ticks land.
-- Moving the root's CFrame directly works with the Humanoid instead of fighting its walk controller,
-- so the player can always walk out against it.
local function dragLocalPlayer(now, dt)
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 or root.Anchored or humanoid.Sit then return end

	local move = Vector3.zero
	for _, cast in pairs(casts) do
		local t = now - cast.releaseAt
		local dy = root.Position.Y - cast.origin.Y
		if cast.released and t >= Config.DAMAGE_DELAY and t <= Config.TRAVEL
			and dy >= -Config.HIT_BELOW and dy <= Config.HIT_ABOVE
		then
			for index = 0, Config.COUNT - 1 do
				local axis = Config.PathPoint(cast.origin, cast.angle, index, t)
				local toAxis = Vector3.new(axis.X - root.Position.X, 0, axis.Z - root.Position.Z)
				local distance = toAxis.Magnitude
				if distance < Config.PULL_RADIUS then
					local falloff = 1 - distance / Config.PULL_RADIUS
					local ahead = Config.PathPoint(cast.origin, cast.angle, index, math.min(t + 0.05, Config.TRAVEL))
					move += (ahead - axis) / 0.05 * Config.CARRY * falloff
					if distance > Config.PULL_MIN_DISTANCE then
						move += toAxis.Unit * Config.PULL_SPEED * falloff
					end
				end
			end
		end
	end
	if move.Magnitude > 0 then
		root.CFrame += Vector3.new(move.X, 0, move.Z) * dt
	end
end

local function step(dt)
	local now = Workspace:GetServerTimeNow()
	dragLocalPlayer(now, dt)
	for id, cast in pairs(casts) do
		if not cast.released then
			if now >= cast.releaseAt then
				release(cast)
			else
				updateChannel(cast, cast.channel, now)
			end
		end
		if cast.released then
			local alive = false
			for _, tw in ipairs(cast.tornadoes) do
				if not tw.done then
					updateTornado(cast, tw, now, dt, cast.folder)
					alive = alive or not tw.done
				end
			end
			if not alive then
				casts[id] = nil
				Debris:AddItem(cast.folder, 2.5)
			end
		end
	end
	if next(casts) == nil and connection then
		connection:Disconnect()
		connection = nil
	end
end

local function begin(payload)
	local origin = payload.origin
	local camera = Workspace.CurrentCamera
	if typeof(origin) ~= "Vector3" or not camera then return end
	if (camera.CFrame.Position - origin).Magnitude > Config.VISIBLE_DISTANCE then return end
	local now = Workspace:GetServerTimeNow()
	local releaseAt = payload.startAt + Config.WINDUP
	if now > releaseAt + Config.TRAVEL then return end -- arrived far too late to show anything

	local folder = Instance.new("Folder")
	folder.Name = "FireTornadoVFX_" .. tostring(payload.id)
	folder.Parent = Workspace
	local channelFolder = Instance.new("Folder")
	channelFolder.Name = "Channel"
	channelFolder.Parent = folder

	local cast = {
		id = payload.id,
		caster = payload.caster,
		origin = origin,
		impact = typeof(payload.impact) == "Vector3" and payload.impact or origin,
		angle = payload.angle,
		startAt = payload.startAt,
		releaseAt = releaseAt,
		folder = folder,
		channelFolder = channelFolder,
		released = false,
	}
	cast.channel = buildChannel(cast, channelFolder)
	casts[cast.id] = cast
	if not connection then
		connection = RunService.RenderStepped:Connect(step)
	end
end

local function cancel(id)
	local cast = casts[id]
	if not cast or cast.released then return end
	casts[id] = nil
	fadeChannel(cast.channel, true)
	cast.folder:Destroy()
end

CastEvent.OnClientEvent:Connect(function(kind, payload)
	if kind == "begin" and type(payload) == "table" then
		begin(payload)
	elseif kind == "cancel" then
		cancel(payload)
	end
end)
