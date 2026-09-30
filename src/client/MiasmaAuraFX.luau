--[[
	MiasmaAuraFX -- Miasma's standing menace while it's in the arena (client only, visual only).

		AuraFX.Start(bossModel, parent)
		AuraFX.Stop()
		AuraFX.Quench(seconds)   -- the holy water puts it out for a while (fades back after)
		AuraFX.Restore()

	Two pieces, both following the boss, shrinking with its stun shrink (Model:GetScale()) and
	hidden while it is submerged (its skin goes fully transparent):
	  aura  AURA_POINTS invisible points orbit the body at its edge, bobbing, each trailing
	        purple wisps -- the poison circulating around it
	  ooze  a thick glossy pool of poison around its base, overlapping the bottom of the body
	        so the slime reads as heavier and wetter at the floor, slowly breathing, with fumes
	        bubbling off it
	Sized from AURA_BODY_FRACTION of the model's half-extent (independent of the server's solid
	collider, MiasmaEncounterConfig.Melee.BodyRadiusFraction).
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AuraFX = {}

local AURA_POINTS = 6
local ORBIT_SPEED = .35          -- radians per second
local ORBIT_RADIUS = 1.08        -- x body radius
local OOZE_RADIUS = 1.22         -- x body radius
local OOZE_THICKNESS = 1.4
-- The aura/ooze were tuned against a body radius of 0.6 x the half-extent. Kept here on purpose:
-- Config.Melee.BodyRadiusFraction is the SOLID collider and is tuned separately.
local AURA_BODY_FRACTION = .6
local FLOOR_CHECK_EVERY = 1
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local POISON_LIGHT = Color3.fromRGB(170, 80, 220)
local POISON_MID = Color3.fromRGB(110, 40, 150)
local POISON_DARK = Color3.fromRGB(48, 16, 64)

local active
local quenchUntil = 0

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

local function wispEmitter(parent)
	local e = Instance.new("ParticleEmitter")
	e.Texture = SMOKE
	e.Color = ColorSequence.new(POISON_LIGHT, POISON_DARK)
	e.LightEmission = .35
	e.LightInfluence = .4
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(.5, 6), NumberSequenceKeypoint.new(1, 8) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(.2, .55), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(1.8, 2.8)
	e.Speed = NumberRange.new(.5, 1.5)
	e.SpreadAngle = Vector2.new(40, 40)
	e.Acceleration = Vector3.new(0, 1.8, 0)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-30, 30)
	e.Rate = 7
	e.Parent = parent
	return e
end

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

local function floorBelow(model, position)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { model }
	local vfx = Workspace:FindFirstChild("MiasmaEncounterVFX")
	if vfx then table.insert(ignore, vfx) end
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(position + Vector3.new(0, 6, 0), Vector3.new(0, -80, 0), params)
	return hit and hit.Position.Y or (position.Y - 5)
end

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
	local folder = s.folder
	task.delay(3, function() folder:Destroy() end) -- let the wisps drift out
end

function AuraFX.Start(boss, parent)
	if typeof(boss) ~= "Instance" or not boss:IsA("Model") or not boss.Parent then return end
	if active and active.boss == boss then return end
	AuraFX.Stop()
	local root = boss.PrimaryPart
	if not root then return end

	local size = boss:GetExtentsSize()
	local startScale = boss:GetScale()
	local halfExtent = (math.max(size.X, size.Z) + math.min(size.X, size.Z)) * .25
	local bodyRadius = halfExtent * AURA_BODY_FRACTION

	local folder = Instance.new("Folder")
	folder.Name = "MiasmaAura"
	folder.Parent = parent or Workspace
	local s = { boss = boss, folder = folder, emitters = {}, points = {}, skin = skinOf(boss), started = os.clock() }

	for i = 1, AURA_POINTS do
		local p = anchored("Wisp", folder)
		table.insert(s.points, { part = p, phase = (i - 1) / AURA_POINTS * math.pi * 2, bob = math.random() * 6.28, height = 2 + (i % 3) * 3 })
		table.insert(s.emitters, wispEmitter(p))
	end

	-- The ooze: a thick glossy pool whose axis is vertical (a Cylinder's length runs along X).
	local ooze = Instance.new("Part")
	ooze.Name = "Ooze"
	ooze.Shape = Enum.PartType.Cylinder
	ooze.Anchored, ooze.CanCollide, ooze.CanQuery, ooze.CanTouch = true, false, false, false
	ooze.CastShadow = false
	ooze.Material = Enum.Material.Glass
	ooze.Color = POISON_DARK
	ooze.Reflectance = .12
	ooze.Transparency = .12
	ooze.Parent = folder
	local rim = ooze:Clone() -- a brighter, thinner lip just inside the edge
	rim.Name = "OozeRim"
	rim.Color = POISON_MID
	rim.Transparency = .35
	rim.Parent = folder
	local fumes = Instance.new("ParticleEmitter")
	fumes.Texture = SMOKE
	fumes.Shape = Enum.ParticleEmitterShape.Cylinder
	fumes.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	fumes.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	fumes.Color = ColorSequence.new(POISON_LIGHT, POISON_MID)
	fumes.LightEmission = .3
	fumes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, .6), NumberSequenceKeypoint.new(1, 2.2) })
	fumes.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .4), NumberSequenceKeypoint.new(1, 1) })
	fumes.Lifetime = NumberRange.new(.8, 1.6)
	fumes.Speed = NumberRange.new(1, 3)
	fumes.Acceleration = Vector3.new(0, 3, 0)
	fumes.Rate = 16
	fumes.Parent = ooze
	table.insert(s.emitters, fumes)
	s.ooze, s.rim = ooze, rim

	active = s
	local floorY, nextFloor = nil, 0
	local parts, cframes = {}, {}
	local quench = 0 -- 0 = full menace, 1 = put out by the holy water
	s.conn = RunService.RenderStepped:Connect(function(dt)
		if not boss.Parent or not root.Parent then AuraFX.Stop() return end
		local now = os.clock()
		local t = now - s.started
		local centre = root.Position
		if now >= nextFloor then
			nextFloor = now + FLOOR_CHECK_EVERY
			floorY = floorBelow(boss, centre)
		end
		local scale = boss:GetScale() / startScale
		local r = bodyRadius * scale
		local hidden = s.skin ~= nil and s.skin.Transparency >= .99 -- submerged / not revealed yet
		quench += ((now < quenchUntil and 1 or 0) - quench) * math.min(1, (dt or 0) * 2.5)
		local off = hidden and 1 or quench
		for _, e in ipairs(s.emitters) do e.Enabled = off < .5 end
		ooze.Transparency = .12 + (1 - .12) * off
		rim.Transparency = .35 + (1 - .35) * off

		table.clear(parts); table.clear(cframes)
		for _, point in ipairs(s.points) do
			local a = point.phase + t * ORBIT_SPEED
			local h = (point.height + math.sin(t * .8 + point.bob) * 1.2) * scale
			table.insert(parts, point.part)
			table.insert(cframes, CFrame.new(centre.X + math.cos(a) * r * ORBIT_RADIUS, floorY + h, centre.Z + math.sin(a) * r * ORBIT_RADIUS))
		end
		local breathe = 1 + math.sin(t * 1.1) * .03
		local d = r * OOZE_RADIUS * 2 * breathe
		ooze.Size = Vector3.new(OOZE_THICKNESS * scale, d, d)
		rim.Size = Vector3.new(OOZE_THICKNESS * scale + .1, d * .82, d * .82)
		local flat = CFrame.new(centre.X, floorY + OOZE_THICKNESS * scale * .35, centre.Z) * CFrame.Angles(0, 0, math.pi / 2)
		table.insert(parts, ooze); table.insert(cframes, flat)
		table.insert(parts, rim); table.insert(cframes, flat)
		Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end)
end

return AuraFX
