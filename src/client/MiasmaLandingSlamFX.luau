-- Miasma's landing slam: particles + ground-matched debris, played on each client
-- when the boss hits the floor (MiasmaEncounterVFX routes the "BossLanding"
-- presentation here).
--
--   LandingSlamFX.Play(groundPosition, visualRadius, ignore, parent)
--
-- `visualRadius` is how far the effect reaches, sent by the server as ~1.6x the
-- boss's standing half-width (a squished body plus room past it). It is NOT the
-- slam's damage radius, which the server owns. Every layer below is authored at a
-- 50-stud radius and scaled by visualRadius / 50, so a resized boss just works.
--
-- The effect is BUILT HERE IN CODE, not stored as a Studio model: ReplicatedStorage
-- is Rojo-managed, so a hand-placed template there would not survive a sync. The
-- original was prototyped in the "Haruka VFX" place and transcribed into LAYERS.
--
-- Debris is anchored and animated by script (TweenService for the rim slabs, a
-- manual ballistic arc for the flung rocks), never by Roblox physics: no network
-- ownership stutter, no players shoved around, same on every screen.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local LandingSlamFX = {}

local AUTHORED_RADIUS = 50

local TEX = {
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	spark = "rbxasset://textures/particles/sparkles_main.dds",
	ring = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
}

local Config = {
	GroundTintDarken = 0.25, -- tinted dust is this much darker than the floor so it reads against it
	LightRange = 60,
	LightBrightness = 4,

	-- Rings of slabs, radius as a fraction of visualRadius. The squished body edge
	-- is ~0.7, so the first ring hugs it and the second breaks the floor beyond.
	RimRings = {
		{ Radius = 0.72, Count = 26, Size = { Min = Vector3.new(5, 7, 2), Max = Vector3.new(9, 13, 4) } },
		{ Radius = 0.92, Count = 20, Size = { Min = Vector3.new(3, 4, 1.5), Max = Vector3.new(6, 8, 3) } },
	},
	RimTilt = { Min = 25, Max = 50 }, -- degrees, leaning away from the impact
	RimRiseTime = 0.12,
	RimHoldTime = 2.2,
	RimSinkTime = 0.7,

	FlungCount = 55,
	FlungStartRadius = { Min = 0.5, Max = 0.7 }, -- thrown from the body's edge, not its hidden centre
	FlungSize = { Min = 1, Max = 3.5 },
	FlungSpeed = { Min = 40, Max = 80 },
	FlungUpAngle = { Min = 35, Max = 65 }, -- degrees above the floor
	Gravity = 110,
	FlungLinger = 1.2, -- seconds on the floor before shrinking away
	FlungShrinkTime = 0.5,

	Lifetime = 7, -- the whole effect is cleaned up after this, whatever happens
}
LandingSlamFX.Config = Config

local function ns(points)
	local keys = {}
	for _, p in ipairs(points) do table.insert(keys, NumberSequenceKeypoint.new(p[1], p[2])) end
	return NumberSequence.new(keys)
end

-- Particle layers, authored at AUTHORED_RADIUS. `Sizes` are scaled with the
-- radius; everything else is used as-is.
--   Ring    { Count, Radius (fraction), Tilt (degrees outward from straight up) }
--           omit for a single emitter at the centre
--   Y       height above the floor
--   Flat    lie on the floor (shockwaves, puddles) instead of facing the camera
--   Tint    recolour to the floor under the impact
--   Count / Delay   particles per emitter, seconds after impact
local LAYERS = {
	{ -- flash pops around the body's edge (its centre is hidden under the boss)
		Name = "Flash", Ring = { 8, 0.62, 0 }, Y = 4, Count = 1, Delay = 0,
		Sizes = { { 0, 10 }, { 1, 30 } },
		Props = {
			Texture = TEX.spark, Color = ColorSequence.new(Color3.fromRGB(245, 225, 255), Color3.fromRGB(200, 120, 255)),
			LightEmission = 1, Brightness = 4, Transparency = ns({ { 0, 0 }, { 0.6, 0.4 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.18, 0.24), Speed = NumberRange.new(0), ZOffset = 2,
		},
	},
	{ -- ground shockwave racing out past the body
		Name = "Shockwave", Y = 0.35, Flat = true, Count = 1, Delay = 0,
		Sizes = { { 0, 40 }, { 0.35, 90 }, { 1, 110 } },
		Props = {
			Texture = TEX.ring, Color = ColorSequence.new(Color3.fromRGB(215, 130, 255), Color3.fromRGB(150, 50, 200)),
			LightEmission = 0.8, Brightness = 2, Transparency = ns({ { 0, 0 }, { 0.5, 0.35 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.55),
		},
	},
	{
		Name = "ShockwaveTrail", Y = 0.3, Flat = true, Count = 1, Delay = 0.06,
		Sizes = { { 0, 50 }, { 0.4, 100 }, { 1, 130 } },
		Props = {
			Texture = TEX.ring, Color = ColorSequence.new(Color3.fromRGB(120, 50, 160)),
			LightEmission = 0.3, Transparency = ns({ { 0, 0.3 }, { 1, 1 } }),
			Lifetime = NumberRange.new(0.9),
		},
	},
	{ -- goo puddle spreading past the body
		Name = "Puddle", Y = 0.2, Flat = true, Count = 2, Delay = 0,
		Sizes = { { 0, 30 }, { 0.08, 80 }, { 1, 86 } },
		Props = {
			Texture = TEX.smoke, Color = ColorSequence.new(Color3.fromRGB(55, 25, 75)),
			LightEmission = 0, Transparency = ns({ { 0, 0.15 }, { 0.7, 0.35 }, { 1, 1 } }),
			Lifetime = NumberRange.new(2.8), ZOffset = -1,
		},
	},
	{ -- dust wall blasting flat and outward from the body's edge
		Name = "DustRing", Ring = { 20, 0.55, 80 }, Y = 1.5, Tint = true, Count = 5, Delay = 0,
		Sizes = { { 0, 8 }, { 0.35, 16 }, { 1, 22 } },
		Props = {
			Texture = TEX.smoke, Color = ColorSequence.new(Color3.fromRGB(105, 75, 125), Color3.fromRGB(70, 55, 80)),
			LightEmission = 0, Transparency = ns({ { 0, 0.2 }, { 0.6, 0.55 }, { 1, 1 } }),
			Lifetime = NumberRange.new(1.1, 1.7), Speed = NumberRange.new(70, 100), Drag = 2.8,
			Acceleration = Vector3.new(0, 3, 0), SpreadAngle = Vector2.new(8, 8),
			RotSpeed = NumberRange.new(-60, 60),
		},
	},
	{ -- goo droplets thrown up and out, raining back down
		Name = "Splash", Ring = { 10, 0.55, 40 }, Y = 2, Count = 10, Delay = 0.02,
		Sizes = { { 0, 3 }, { 1, 1 } },
		Props = {
			Texture = TEX.spark, Color = ColorSequence.new(Color3.fromRGB(190, 90, 240), Color3.fromRGB(80, 25, 120)),
			LightEmission = 0.4, Transparency = ns({ { 0, 0 }, { 0.8, 0.1 }, { 1, 1 } }),
			Lifetime = NumberRange.new(1, 1.5), Speed = NumberRange.new(50, 95), Drag = 0.5,
			Acceleration = Vector3.new(0, -110, 0), SpreadAngle = Vector2.new(30, 30),
		},
	},
	{ -- lingering haze around the edge
		Name = "Haze", Ring = { 10, 0.6, 60 }, Y = 3, Tint = true, Count = 3, Delay = 0.12,
		Sizes = { { 0, 12 }, { 1, 26 } },
		Props = {
			Texture = TEX.smoke, Color = ColorSequence.new(Color3.fromRGB(125, 70, 160), Color3.fromRGB(70, 45, 90)),
			LightEmission = 0.1, Transparency = ns({ { 0, 0.7 }, { 0.3, 0.72 }, { 1, 1 } }),
			Lifetime = NumberRange.new(2.2, 3.2), Speed = NumberRange.new(6, 14), Drag = 1,
			Acceleration = Vector3.new(0, 1.5, 0), SpreadAngle = Vector2.new(30, 30),
			RotSpeed = NumberRange.new(-20, 20),
		},
	},
}

local rng = Random.new()

local function range(r) return rng:NextNumber(r.Min, r.Max) end

local function randomSize(r)
	return Vector3.new(rng:NextNumber(r.Min.X, r.Max.X), rng:NextNumber(r.Min.Y, r.Max.Y), rng:NextNumber(r.Min.Z, r.Max.Z))
end

-- What the floor under `position` looks like. nil when nothing is there.
local function sampleGround(position, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore and { ignore } or {}
	params.IgnoreWater = true

	local hit = Workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -30, 0), params)
	if not hit then return nil end

	local ground = { Position = hit.Position, Material = hit.Material }
	if hit.Instance:IsA("Terrain") then
		ground.Color = Workspace.Terrain:GetMaterialColor(hit.Material)
	else
		ground.Color = hit.Instance.Color
		ground.MaterialVariant = hit.Instance.MaterialVariant
	end
	return ground
end

---------------------------------------------------------------- particles

local function newEmitter(layer, scale, groundColor)
	local e = Instance.new("ParticleEmitter")
	e.Name = layer.Name
	e.Enabled = false
	e.Rate = 0
	e.Rotation = NumberRange.new(0, 360)
	e.EmissionDirection = Enum.NormalId.Top
	for key, value in pairs(layer.Props) do e[key] = value end

	local sizes = {}
	for _, p in ipairs(layer.Sizes) do table.insert(sizes, { p[1], p[2] * scale }) end
	e.Size = ns(sizes)

	if layer.Flat then
		-- Lies on the floor: perpendicular to a tiny upward velocity.
		e.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
		e.Speed = NumberRange.new(0.01)
		e.SpreadAngle = Vector2.zero
		e.Acceleration = Vector3.zero
		e.Drag = 0
	end
	if layer.Tint and groundColor then
		local c = groundColor:Lerp(Color3.new(0, 0, 0), Config.GroundTintDarken)
		e.Color = ColorSequence.new(c:Lerp(Color3.new(1, 1, 1), 0.1), c)
	end
	return e
end

local function emitLayer(anchor, layer, radius, scale, groundColor)
	local attachments = {}
	if layer.Ring then
		local count, frac, tilt = layer.Ring[1], layer.Ring[2], layer.Ring[3]
		for i = 0, count - 1 do
			local att = Instance.new("Attachment")
			-- The attachment's +Y is the emitter's Top, tipped `tilt` degrees outward.
			att.CFrame = CFrame.Angles(0, (i / count) * math.pi * 2, 0)
				* CFrame.new(0, layer.Y, -radius * frac)
				* CFrame.Angles(-math.rad(tilt), 0, 0)
			table.insert(attachments, att)
		end
	else
		local att = Instance.new("Attachment")
		att.Position = Vector3.new(0, layer.Y, 0)
		table.insert(attachments, att)
	end

	local emitters = {}
	for _, att in ipairs(attachments) do
		att.Name = layer.Name
		newEmitter(layer, scale, groundColor).Parent = att
		att.Parent = anchor
		table.insert(emitters, att:FindFirstChildOfClass("ParticleEmitter"))
	end

	local function fire()
		for _, e in ipairs(emitters) do e:Emit(layer.Count) end
	end
	if layer.Delay > 0 then task.delay(layer.Delay, fire) else fire() end
end

---------------------------------------------------------------- debris

local function newChunk(ground, size, cframe, parent)
	local p = Instance.new("Part")
	p.Name = "SlamDebris"
	p.Anchored = true
	p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
	p.CastShadow = true
	p.Size = size
	p.CFrame = cframe
	p.Color = ground.Color
	-- Terrain materials are almost all valid Part materials; the few that aren't
	-- (Water, Air) just keep the default.
	pcall(function() p.Material = ground.Material end)
	if ground.MaterialVariant and ground.MaterialVariant ~= "" then
		p.MaterialVariant = ground.MaterialVariant
	end
	p.Parent = parent
	return p
end

-- One slab bursting out of the floor, leaning away from the impact.
local function spawnSlab(ground, radius, parent, yaw, dist, size)
	local base = CFrame.new(ground.Position) * CFrame.Angles(0, yaw, 0) * CFrame.new(0, 0, -dist)
	local up = base * CFrame.Angles(-math.rad(range(Config.RimTilt)), rng:NextNumber(-0.3, 0.3), rng:NextNumber(-0.2, 0.2))
		* CFrame.new(0, size.Y * 0.25, 0) -- a quarter of it stays buried
	local down = up * CFrame.new(0, -size.Y, 0)

	local chunk = newChunk(ground, size, down, parent)
	task.delay((dist / radius) * 0.05, function() -- the ring ripples outward a touch
		TweenService:Create(chunk, TweenInfo.new(Config.RimRiseTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = up }):Play()
		task.wait(Config.RimRiseTime + Config.RimHoldTime + rng:NextNumber(0, 0.4))
		local sink = TweenService:Create(chunk, TweenInfo.new(Config.RimSinkTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = down })
		sink:Play()
		sink.Completed:Wait()
		chunk:Destroy()
	end)
end

local function spawnRim(ground, radius, scale, parent)
	for _, ring in ipairs(Config.RimRings) do
		local offset = rng:NextNumber(0, math.pi * 2) -- rings don't line up with each other
		for i = 1, ring.Count do
			local yaw = offset + (i / ring.Count) * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
			local dist = radius * ring.Radius * rng:NextNumber(0.92, 1.08)
			spawnSlab(ground, radius, parent, yaw, dist, randomSize(ring.Size) * scale)
		end
	end
end

-- Rocks thrown out on a ballistic arc. One Heartbeat drives all of them.
local function spawnFlung(ground, radius, scale, parent)
	local floorY = ground.Position.Y
	local chunks = {}
	for _ = 1, Config.FlungCount do
		local s = range(Config.FlungSize) * scale
		local size = Vector3.new(s, s * rng:NextNumber(0.6, 1), s * rng:NextNumber(0.7, 1.2))
		local yaw = rng:NextNumber(0, math.pi * 2)
		local pitch = math.rad(range(Config.FlungUpAngle))
		local dir = Vector3.new(math.cos(yaw) * math.cos(pitch), math.sin(pitch), math.sin(yaw) * math.cos(pitch))
		local out = Vector3.new(math.cos(yaw), 0, math.sin(yaw)) * radius * range(Config.FlungStartRadius)
		local start = ground.Position + Vector3.new(0, size.Y / 2, 0) + out
		table.insert(chunks, {
			Part = newChunk(ground, size, CFrame.new(start), parent),
			Start = start,
			Velocity = dir * range(Config.FlungSpeed) * scale,
			Spin = Vector3.new(rng:NextNumber(-12, 12), rng:NextNumber(-12, 12), rng:NextNumber(-12, 12)),
			Rest = floorY + size.Y / 2,
		})
	end

	local t = 0
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		t += dt
		local flying = 0
		for _, c in ipairs(chunks) do
			if not c.Landed and c.Part.Parent then
				local pos = c.Start + c.Velocity * t + Vector3.new(0, -0.5 * Config.Gravity * t * t, 0)
				local falling = c.Velocity.Y - Config.Gravity * t < 0
				if falling and pos.Y <= c.Rest then
					c.Landed = true
					c.Part.CFrame = CFrame.new(pos.X, c.Rest, pos.Z) * c.Part.CFrame.Rotation
					local part = c.Part
					task.delay(Config.FlungLinger + rng:NextNumber(0, 0.5), function()
						if not part.Parent then return end
						local shrink = TweenService:Create(part, TweenInfo.new(Config.FlungShrinkTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = Vector3.new(0.05, 0.05, 0.05) })
						shrink:Play()
						shrink.Completed:Wait()
						part:Destroy()
					end)
				else
					flying += 1
					c.Part.CFrame = CFrame.new(pos) * CFrame.Angles(c.Spin.X * t, c.Spin.Y * t, c.Spin.Z * t)
				end
			end
		end
		if flying == 0 then connection:Disconnect() end
	end)
end

---------------------------------------------------------------- entry

-- `ignore` is the boss model, so the floor check doesn't sample its body.
function LandingSlamFX.Play(groundPosition, visualRadius, ignore, parent)
	local radius = math.max(10, tonumber(visualRadius) or AUTHORED_RADIUS)
	local scale = radius / AUTHORED_RADIUS
	local ground = sampleGround(groundPosition, ignore)
	local floor = ground and ground.Position or groundPosition

	local container = Instance.new("Folder")
	container.Name = "MiasmaLandingSlam"
	container.Parent = parent or Workspace

	local anchor = Instance.new("Part")
	anchor.Name = "SlamAnchor"
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch, anchor.CastShadow = true, false, false, false, false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new(floor)
	anchor.Parent = container

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(200, 120, 255)
	light.Range = Config.LightRange * math.min(scale, 1.5)
	light.Shadows = false
	light.Brightness = Config.LightBrightness
	light.Parent = anchor
	TweenService:Create(light, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()

	local groundColor = ground and ground.Color
	for _, layer in ipairs(LAYERS) do
		emitLayer(anchor, layer, radius, scale, groundColor)
	end

	-- No floor under the impact: particles only.
	if ground then
		spawnRim(ground, radius, scale, container)
		spawnFlung(ground, radius, scale, container)
	end

	task.delay(Config.Lifetime, function() container:Destroy() end)
	return container
end

return LandingSlamFX
