--[[
	MiasmaTelegraphArt -- VFX for the Miasma encounter's ground warnings and hazards.

	Built from Roblox VFX (ParticleEmitters, Beams, PointLights) using only textures that ship
	with Roblox (rbxasset://textures/particles/*), so no uploads are needed. Each marking is:

		- a thin, crisp edge ring (SurfaceGui on an invisible floor part) so the exact danger
		  boundary is always readable;
		- a per-kind VFX recipe: ground glow, collapsing shockwave ring (reaches the centre
		  exactly when the hit lands: the timing cue), falling droplets, swirling vortex,
		  growing shadow, bubbles, mist, light pillars, and an impact burst when it resolves.

	Shared by both sides:
		client (MiasmaEncounterVFX)   transient warnings: Build + Animate, Shockwave
		server (encounter controller) persistent hazards (puddles, clouds): Build { static = true }
		                              (continuous emitters only, so it replicates cleanly)

	Flat-on-the-ground particles use Orientation = VelocityPerpendicular with a tiny upward
	velocity, emitted from an attachment at the marking's centre.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")


local Art = {}

local TEX = {
	Glow = "rbxasset://textures/particles/forcefield_glow_main.dds",
	Vortex = "rbxasset://textures/particles/forcefield_vortex_main.dds",
	Ring = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
	Core = "rbxasset://textures/particles/explosion01_core_main.dds",
	Implosion = "rbxasset://textures/particles/explosion01_implosion_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Spark = "rbxasset://textures/particles/sparkles_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
	Embers = "rbxasset://textures/particles/fire_sparks_main.dds",
}
Art.Textures = TEX

-- edge: ring + light colour; fill: ground tint. (No centre rune any more: 2026-09-27, the
-- runes read as valve-puzzle runes and confused players about what the circle meant.)
Art.STYLES = {
	PoisonDrop = { edge = Color3.fromRGB(196, 92, 255), fill = Color3.fromRGB(96, 24, 130) },
	SlimeLanding = { edge = Color3.fromRGB(150, 255, 90), fill = Color3.fromRGB(46, 110, 26) },
	BossDrop = { edge = Color3.fromRGB(235, 96, 255), fill = Color3.fromRGB(80, 16, 96) },
	SubmergePool = { edge = Color3.fromRGB(215, 245, 110), fill = Color3.fromRGB(58, 14, 86) },
	PurgeSafe = { edge = Color3.fromRGB(110, 250, 240), fill = Color3.fromRGB(20, 90, 96) },
	PoisonPuddle = { edge = Color3.fromRGB(150, 230, 70), fill = Color3.fromRGB(62, 96, 20) },
	PoisonCloud = { edge = Color3.fromRGB(170, 110, 220), fill = Color3.fromRGB(70, 40, 90) },
	PureWater = { edge = Color3.fromRGB(150, 235, 255), fill = Color3.fromRGB(40, 120, 160) },
	Shockwave = { edge = Color3.fromRGB(200, 90, 240), fill = Color3.fromRGB(60, 20, 80) },
}
local DEFAULT_STYLE = { edge = Color3.fromRGB(180, 80, 230), fill = Color3.fromRGB(60, 20, 80) }

-- Helpers ---------------------------------------------------------------------------------

local function seq(points)
	local keys = {}
	for _, p in ipairs(points) do table.insert(keys, NumberSequenceKeypoint.new(p[1], p[2])) end
	return NumberSequence.new(keys)
end

local function emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.LightEmission = 1
	e.LightInfluence = 0
	for key, value in pairs(props) do e[key] = value end
	e.Parent = parent
	return e
end

-- Horizontal (ground-plane) particles: plane perpendicular to a tiny upward velocity.
local function flat(e)
	e.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
	e.EmissionDirection = Enum.NormalId.Top
	e.Speed = NumberRange.new(.01)
	e.SpreadAngle = Vector2.zero
	e.LockedToPart = true
	return e
end

local function attachmentAt(part, offset)
	local a = Instance.new("Attachment")
	a.Position = offset or Vector3.zero
	a.Parent = part
	return a
end

-- Floor height under `position` (collidable geometry only, characters ignored).
function Art.GroundY(position, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local list = table.clone(ignore or {})
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then table.insert(list, player.Character) end
	end
	params.FilterDescendantsInstances = list
	local hit = Workspace:Raycast(position + Vector3.new(0, 4, 0), Vector3.new(0, -40, 0), params)
	return hit and hit.Position.Y or position.Y
end

-- Layers -----------------------------------------------------------------------------------

local Layers = {}

-- Soft tinted glow pooled on the floor (continuous, overlapping pulses).
function Layers.GroundGlow(h, color, scale, alpha)
	return flat(emitter(h.centre, {
		Texture = TEX.Glow, Color = ColorSequence.new(color), LightEmission = .7,
		Size = seq({ { 0, h.diameter * (scale or 1.05) }, { 1, h.diameter * (scale or 1.05) * 1.04 } }),
		Transparency = seq({ { 0, 1 }, { .3, alpha or .55 }, { .7, alpha or .55 }, { 1, 1 } }),
		Lifetime = NumberRange.new(1.4), Rate = 1.6, Rotation = NumberRange.new(0, 360),
	}))
end

-- A ring that collapses from the edge to the centre over `duration`: the hit timing cue.
function Layers.Collapse(h, color, duration)
	local e = flat(emitter(h.centre, {
		Texture = TEX.Ring, Color = ColorSequence.new(color), LightEmission = 1,
		Size = seq({ { 0, h.diameter * 1.02 }, { 1, h.diameter * .06 } }),
		Transparency = seq({ { 0, .75 }, { .1, .15 }, { .85, 0 }, { 1, .3 } }),
		Lifetime = NumberRange.new(duration),
	}))
	table.insert(h.emitOnStart, { e, 1 })
	return e
end

-- Shadow growing under something about to land.
function Layers.Shadow(h, duration)
	local e = flat(emitter(h.centre, {
		Texture = TEX.Glow, Color = ColorSequence.new(Color3.new(0, 0, 0)), LightEmission = 0,
		Size = seq({ { 0, h.diameter * .15 }, { 1, h.diameter * .9 } }),
		Transparency = seq({ { 0, .85 }, { 1, .15 } }),
		Lifetime = NumberRange.new(duration),
	}))
	table.insert(h.emitOnStart, { e, 1 })
	return e
end

function Layers.Vortex(h, color, rate)
	return flat(emitter(h.centre, {
		Texture = TEX.Vortex, Color = ColorSequence.new(color), LightEmission = .8,
		Size = seq({ { 0, h.diameter * .75 }, { 1, h.diameter * 1.05 } }),
		Transparency = seq({ { 0, 1 }, { .25, .35 }, { .75, .45 }, { 1, 1 } }),
		Lifetime = NumberRange.new(1.6), Rate = rate or 1.5, Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(140, 200),
	}))
end

-- Sparks drifting up across the whole area.
function Layers.Motes(h, color, rate, speed)
	return emitter(h.part, {
		Texture = TEX.Spark, Color = ColorSequence.new(color), LightEmission = 1,
		Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		EmissionDirection = Enum.NormalId.Top, Speed = NumberRange.new(speed or 1.5, (speed or 1.5) * 1.8),
		Size = seq({ { 0, .35 }, { 1, 0 } }), Transparency = seq({ { 0, .2 }, { 1, 1 } }),
		Lifetime = NumberRange.new(.9, 1.6), Rate = rate, SpreadAngle = Vector2.new(10, 10),
	})
end

function Layers.Bubbles(h, color, rate)
	return emitter(h.part, {
		Texture = TEX.Glow, Color = ColorSequence.new(color), LightEmission = .6,
		Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		EmissionDirection = Enum.NormalId.Top, Speed = NumberRange.new(.4, 1.2),
		Size = seq({ { 0, .2 }, { .7, .7 }, { 1, 1.1 } }), Transparency = seq({ { 0, .5 }, { .8, .3 }, { 1, 1 } }),
		Lifetime = NumberRange.new(.6, 1.1), Rate = rate,
	})
end

function Layers.Mist(h, color, rate, height)
	return emitter(h.part, {
		Texture = TEX.Smoke, Color = ColorSequence.new(color), LightEmission = .15, LightInfluence = .4,
		Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		EmissionDirection = Enum.NormalId.Top, Speed = NumberRange.new(.3, height or 1),
		Size = seq({ { 0, h.radius * .35 }, { 1, h.radius * .75 } }), Transparency = seq({ { 0, 1 }, { .3, .55 }, { 1, 1 } }),
		Lifetime = NumberRange.new(2.5, 4), Rate = rate, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-15, 15),
	})
end

-- Droplets falling from `height` studs up into the area.
function Layers.Rain(h, color, height, rate)
	local source = Instance.new("Part")
	source.Name = "RainSource"
	source.Anchored = true
	source.CanCollide = false
	source.CanQuery = false
	source.CanTouch = false
	source.Transparency = 1
	source.Size = Vector3.new(h.diameter * .7, .1, h.diameter * .7)
	source.CFrame = h.part.CFrame + Vector3.new(0, height, 0)
	source.Parent = h.part
	local speed = 55
	return emitter(source, {
		Texture = TEX.Spark, Color = ColorSequence.new(color), LightEmission = 1,
		Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		EmissionDirection = Enum.NormalId.Bottom, Speed = NumberRange.new(speed),
		Size = seq({ { 0, .55 }, { 1, .35 } }), Transparency = seq({ { 0, .1 }, { 1, .4 } }),
		Lifetime = NumberRange.new(height / speed), Rate = rate, SpreadAngle = Vector2.new(4, 4),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
	})
end

-- Vertical beam of light from the floor.
function Layers.Pillar(h, color, height, width)
	local top = attachmentAt(h.part, Vector3.new(0, height, 0))
	local beam = Instance.new("Beam")
	beam.Attachment0 = h.centre
	beam.Attachment1 = top
	beam.Texture = TEX.Glow
	beam.TextureMode = Enum.TextureMode.Stretch
	beam.Color = ColorSequence.new(color)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Width0 = width
	beam.Width1 = width * .5
	beam.Transparency = seq({ { 0, .35 }, { 1, 1 } })
	beam.Parent = h.part
	return beam
end

-- Impact bursts ----------------------------------------------------------------------------

local function burstAttachment(h)
	local a = attachmentAt(h.part, Vector3.new(0, .3, 0))
	return a
end

local IMPACTS = {}

function IMPACTS.PoisonDrop(h)
	local a = burstAttachment(h)
	emitter(a, { Texture = TEX.Core, Color = ColorSequence.new(h.style.edge), Size = seq({ { 0, h.diameter * .6 }, { 1, h.diameter * 1.3 } }), Transparency = seq({ { 0, .1 }, { 1, 1 } }), Lifetime = NumberRange.new(.35), Speed = NumberRange.new(0) }):Emit(1)
	emitter(a, { Texture = TEX.Spark, Color = ColorSequence.new(h.style.edge), Size = seq({ { 0, .6 }, { 1, 0 } }), Lifetime = NumberRange.new(.4, .7), Speed = NumberRange.new(14, 24), SpreadAngle = Vector2.new(70, 70), Acceleration = Vector3.new(0, -40, 0) }):Emit(22)
	emitter(a, { Texture = TEX.Smoke, Color = ColorSequence.new(h.style.fill), LightEmission = .2, Size = seq({ { 0, 1.5 }, { 1, 3.5 } }), Transparency = seq({ { 0, .4 }, { 1, 1 } }), Lifetime = NumberRange.new(.8, 1.2), Speed = NumberRange.new(2, 5), SpreadAngle = Vector2.new(80, 80) }):Emit(6)
end

function IMPACTS.SlimeLanding(h)
	local a = burstAttachment(h)
	emitter(a, { Texture = TEX.Glow, Color = ColorSequence.new(h.style.edge), Size = seq({ { 0, .5 }, { 1, .1 } }), Lifetime = NumberRange.new(.5, .8), Speed = NumberRange.new(10, 18), SpreadAngle = Vector2.new(60, 60), Acceleration = Vector3.new(0, -35, 0) }):Emit(20)
	emitter(a, { Texture = TEX.Smoke, Color = ColorSequence.new(h.style.fill), LightEmission = .2, Size = seq({ { 0, 1.5 }, { 1, 3 } }), Transparency = seq({ { 0, .45 }, { 1, 1 } }), Lifetime = NumberRange.new(.7, 1), Speed = NumberRange.new(3, 6), SpreadAngle = Vector2.new(85, 85) }):Emit(5)
end

function IMPACTS.SubmergePool(h)
	local a = burstAttachment(h)
	emitter(a, { Texture = TEX.Fire, Color = ColorSequence.new(h.style.fill, h.style.edge), Size = seq({ { 0, 2.5 }, { 1, .5 } }), Transparency = seq({ { 0, .1 }, { 1, 1 } }), Lifetime = NumberRange.new(.5, .8), Speed = NumberRange.new(28, 42), SpreadAngle = Vector2.new(14, 14), Acceleration = Vector3.new(0, -30, 0) }):Emit(34)
	emitter(a, { Texture = TEX.Spark, Color = ColorSequence.new(h.style.edge), Size = seq({ { 0, .6 }, { 1, 0 } }), Lifetime = NumberRange.new(.5, .9), Speed = NumberRange.new(18, 30), SpreadAngle = Vector2.new(35, 35), Acceleration = Vector3.new(0, -40, 0) }):Emit(30)
	flat(emitter(a, { Texture = TEX.Ring, Color = ColorSequence.new(h.style.edge), Size = seq({ { 0, 1 }, { 1, h.diameter * 1.4 } }), Transparency = seq({ { 0, .05 }, { 1, 1 } }), Lifetime = NumberRange.new(.45) })):Emit(1)
	emitter(a, { Texture = TEX.Smoke, Color = ColorSequence.new(h.style.fill), LightEmission = .2, Size = seq({ { 0, 3 }, { 1, 6 } }), Transparency = seq({ { 0, .35 }, { 1, 1 } }), Lifetime = NumberRange.new(1, 1.4), Speed = NumberRange.new(4, 9), SpreadAngle = Vector2.new(60, 60) }):Emit(8)
end

-- Recipes (per kind) -------------------------------------------------------------------------

local RECIPES = {}

function RECIPES.PoisonDrop(h, duration)
	Layers.GroundGlow(h, h.style.edge, 1.1, .45)
	Layers.Collapse(h, h.style.edge, duration)
	Layers.Rain(h, h.style.edge, 22, 14)
end

function RECIPES.SlimeLanding(h, duration)
	Layers.GroundGlow(h, h.style.edge, 1.05, .55)
	Layers.Shadow(h, duration)
	Layers.Collapse(h, h.style.edge, duration)
	Layers.Motes(h, h.style.edge, 10, 1)
end

function RECIPES.BossDrop(h, duration)
	Layers.GroundGlow(h, h.style.edge, 1.02, .6)
	Layers.Shadow(h, duration)
	Layers.Collapse(h, h.style.edge, duration)
	Layers.Mist(h, h.style.fill, 10, 3)
	Layers.Rain(h, Color3.fromRGB(150, 140, 130), 45, 18)
end

function RECIPES.SubmergePool(h, duration)
	Layers.GroundGlow(h, h.style.fill, 1.05, .22)
	Layers.Vortex(h, h.style.edge, 1.8)
	Layers.Collapse(h, h.style.edge, duration)
	Layers.Bubbles(h, h.style.edge, 30)
end

function RECIPES.PurgeSafe(h)
	Layers.GroundGlow(h, h.style.edge, 1.02, .45)
	Layers.Motes(h, h.style.edge, 22, 2)
	Layers.Pillar(h, h.style.edge, 18, h.diameter * .55)
end

function RECIPES.PoisonPuddle(h)
	Layers.GroundGlow(h, h.style.edge, 1.05, .4)
	Layers.Bubbles(h, h.style.edge, math.clamp(h.radius * 3, 8, 30))
	Layers.Mist(h, h.style.fill, math.clamp(h.radius * .6, 3, 8), .8)
end

function RECIPES.PoisonCloud(h)
	Layers.GroundGlow(h, h.style.edge, 1.05, .45)
	Layers.Mist(h, h.style.edge, math.clamp(h.radius * 1.4, 10, 26), 2.2)
	Layers.Motes(h, h.style.edge, 14, 1.2)
end

--[[
	Build(parent, position, radius, kind, options) -> handle
	options.ignore: extra instances the floor probe should ignore
	options.static: persistent hazard (server): continuous emitters only, visible at once
	options.duration: warning length, for timed layers (client)
]]
function Art.Build(parent, position, radius, kind, options)
	options = options or {}
	local style = Art.STYLES[kind] or DEFAULT_STYLE
	local y = Art.GroundY(position, options.ignore)
	local diameter = radius * 2

	local part = Instance.new("Part")
	part.Name = kind .. "Marking"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(diameter, .05, diameter)
	part.CFrame = CFrame.new(position.X, y + .15, position.Z)

	-- Crisp boundary: faint fill + edge ring.
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = math.clamp(math.floor(480 / diameter), 4, 48)
	gui.LightInfluence = 0
	gui.Brightness = 1.4
	gui.Parent = part
	local canvas = diameter * gui.PixelsPerStud
	local group = Instance.new("CanvasGroup")
	group.Name = "Art"
	group.Size = UDim2.fromScale(1, 1)
	group.BackgroundTransparency = 1
	group.GroupTransparency = options.static and 0 or 1
	group.Parent = gui
	local fill = Instance.new("Frame")
	fill.AnchorPoint = Vector2.new(.5, .5)
	fill.Position = UDim2.fromScale(.5, .5)
	fill.Size = UDim2.fromScale(.97, .97)
	fill.BackgroundColor3 = style.fill
	fill.BackgroundTransparency = .8
	fill.BorderSizePixel = 0
	Instance.new("UICorner", fill).CornerRadius = UDim.new(.5, 0)
	fill.Parent = group
	local edge = Instance.new("Frame")
	edge.AnchorPoint = Vector2.new(.5, .5)
	edge.Position = UDim2.fromScale(.5, .5)
	edge.Size = UDim2.fromScale(.97, .97)
	edge.BackgroundTransparency = 1
	Instance.new("UICorner", edge).CornerRadius = UDim.new(.5, 0)
	local edgeStroke = Instance.new("UIStroke")
	edgeStroke.Color = style.edge
	edgeStroke.Thickness = math.max(2, canvas * .012)
	edgeStroke.Transparency = .1
	edgeStroke.Parent = edge
	edge.Parent = group

	local light = Instance.new("PointLight")
	light.Color = style.edge
	light.Range = math.clamp(radius * 1.6, 8, 40)
	light.Brightness = options.static and .7 or 0
	light.Shadows = false
	light.Parent = part

	local handle = {
		part = part, group = group, edgeStroke = edgeStroke, light = light, style = style, kind = kind,
		radius = radius, diameter = diameter, emitOnStart = {},
	}
	handle.centre = attachmentAt(part, Vector3.new(0, .1, 0))
	local recipe = RECIPES[kind]
	if recipe then recipe(handle, math.max(.1, options.duration or 1)) end
	part.Parent = parent
	return handle
end

--[[
	Animate(handle, duration): client warning lifecycle. Fades the boundary in, fires the
	one-shot timed layers (collapsing ring, shadow), pulses the light, then on impact stops
	the continuous layers, plays the kind's impact burst, fades and cleans up.
	Build the handle with options.duration = duration so timed layers match.
]]
function Art.Animate(handle, duration)
	local part = handle.part
	duration = math.max(.1, duration)
	TweenService:Create(handle.group, TweenInfo.new(math.min(.15, duration * .25)), { GroupTransparency = 0 }):Play()
	for _, pending in ipairs(handle.emitOnStart) do pending[1]:Emit(pending[2]) end
	TweenService:Create(handle.light, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Brightness = 2.2 }):Play()
	TweenService:Create(handle.edgeStroke, TweenInfo.new(.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = .45 }):Play()
	task.delay(duration, function()
		if not part.Parent then return end
		for _, item in ipairs(part:GetDescendants()) do
			if item:IsA("ParticleEmitter") then item.Enabled = false end
			if item:IsA("Beam") then TweenService:Create(item, TweenInfo.new(.3), { Width0 = 0, Width1 = 0 }):Play() end
		end
		local impact = IMPACTS[handle.kind]
		if impact then impact(handle) end
		TweenService:Create(handle.group, TweenInfo.new(.3), { GroupTransparency = 1 }):Play()
		TweenService:Create(handle.light, TweenInfo.new(.6), { Brightness = 0 }):Play()
		Debris:AddItem(part, 1.6)
	end)
end

-- Expanding ring burst (pure water, stagger, growth, enrage).
function Art.Shockwave(parent, position, radius, kind, duration)
	local style = Art.STYLES[kind] or DEFAULT_STYLE
	local y = Art.GroundY(position, {})
	local part = Instance.new("Part")
	part.Name = kind .. "Shockwave"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(1, .05, 1)
	part.CFrame = CFrame.new(position.X, y + .2, position.Z)
	part.Parent = parent
	local centre = attachmentAt(part, Vector3.new(0, .1, 0))
	local diameter = radius * 2
	local ring = function(delay, scale, alpha)
		task.delay(delay, function()
			if not part.Parent then return end
			flat(emitter(centre, {
				Texture = TEX.Ring, Color = ColorSequence.new(style.edge),
				Size = seq({ { 0, 2 }, { 1, diameter * scale } }), Transparency = seq({ { 0, alpha }, { .6, alpha + .2 }, { 1, 1 } }),
				Lifetime = NumberRange.new(duration),
			})):Emit(1)
		end)
	end
	ring(0, 1, .05)
	ring(.12, .8, .3)
	emitter(centre, {
		Texture = TEX.Glow, Color = ColorSequence.new(style.edge), Size = seq({ { 0, .8 }, { 1, 0 } }),
		Lifetime = NumberRange.new(.6, 1.2), Speed = NumberRange.new(radius * .8, radius * 1.4),
		SpreadAngle = Vector2.new(80, 80), Acceleration = Vector3.new(0, -20, 0),
	}):Emit(40)
	emitter(centre, {
		Texture = TEX.Smoke, Color = ColorSequence.new(style.fill), LightEmission = .3,
		Size = seq({ { 0, 3 }, { 1, 8 } }), Transparency = seq({ { 0, .5 }, { 1, 1 } }),
		Lifetime = NumberRange.new(1, 1.6), Speed = NumberRange.new(radius * .4, radius * .7), SpreadAngle = Vector2.new(88, 88),
	}):Emit(14)
	local light = Instance.new("PointLight")
	light.Color = style.edge
	light.Range = math.clamp(radius * 1.5, 10, 60)
	light.Brightness = 4
	light.Parent = part
	TweenService:Create(light, TweenInfo.new(duration), { Brightness = 0 }):Play()
	Debris:AddItem(part, duration + 1.8)
	return { part = part }
end

return Art
