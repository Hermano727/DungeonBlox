--[[
	KaneAxeFire -- client: Kane's axe burns, always.

	Kane's axe is not a separate part: it is baked into his one skinned mesh and follows the Hand_R
	bone. So the fire hangs off three extra Bones parented to Hand_R (they deform nothing, they only
	follow the hand), placed on the axe head:
	  AxeFire       the head's centre: flames, embers, smoke, a warm light
	  AxeEdgeA/B    the two ends of the blade's cutting edge: a fire Trail between them, so every
	                swing (ordinary slash, the combo, the Groundbreaker Slam) leaves a fire arc
	The offsets are Hand_R-local, measured from Kane_Groundbreaker_Slam.blend's mesh (the vertices
	weighted to Hand_R, at rest) and converted on the live rig in Studio (2026-10-08). Re-measure if
	Kane's mesh or rig is rebuilt.

	Purely visual and local: every client decorates its own copy of each Kane model it sees
	(mobs are parented straight to Workspace with a MobID attribute, MobClass).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local WorldVfx = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images"):WaitForChild("WorldVfx"))

local MOB_ID = "Kane"
local HAND_BONE = "Hand_R"
local AXE_CENTER = Vector3.new(0.009, 0.411, -1.656)
local AXE_EDGE_A = Vector3.new(0.012, -0.121, -1.589)
local AXE_EDGE_B = Vector3.new(0.000, 0.820, -2.012)
local FIRE_TEXTURE = "rbxasset://textures/particles/fire_main.dds"
local FIND_TIMEOUT = 15 -- seconds to wait for the rig to stream in

local FIRE = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 214, 140)),
	ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 120, 40)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 40, 15)),
})

local function seq(points)
	local keys = {}
	for _, p in ipairs(points) do
		table.insert(keys, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(keys)
end

local function bone(name, hand, offset)
	local b = Instance.new("Bone")
	b.Name = name
	b.CFrame = CFrame.new(offset)
	b.Parent = hand
	return b
end

local function flames(parent, rate)
	local e = Instance.new("ParticleEmitter")
	e.Name = "AxeFlames"
	e.Texture = FIRE_TEXTURE
	e.Color = FIRE
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Rate = rate
	e.Lifetime = NumberRange.new(0.25, 0.45)
	e.Speed = NumberRange.new(0.5, 1.5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, 9, 0) -- flames rise in world space whatever the axe is doing
	e.Size = seq({ { 0, 0.9 }, { 1, 0.25 } })
	e.Transparency = seq({ { 0, 0.15 }, { 0.7, 0.4 }, { 1, 1 } })
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-120, 120)
	e.ZOffset = 0.3
	e.Parent = parent
	return e
end

local function decorate(model)
	local hand
	local deadline = os.clock() + FIND_TIMEOUT
	repeat
		hand = model:FindFirstChild(HAND_BONE, true)
		if not hand then task.wait(0.5) end
	until hand or os.clock() > deadline or not model.Parent
	if not hand or hand:FindFirstChild("AxeFire") then return end

	local center = bone("AxeFire", hand, AXE_CENTER)
	local edgeA = bone("AxeEdgeA", hand, AXE_EDGE_A)
	local edgeB = bone("AxeEdgeB", hand, AXE_EDGE_B)

	flames(center, 25)
	flames(edgeA, 12)
	flames(edgeB, 12)

	local embers = Instance.new("ParticleEmitter")
	embers.Name = "AxeEmbers"
	embers.Texture = WorldVfx.SPARK
	embers.Color = FIRE
	embers.LightEmission = 1
	embers.LightInfluence = 0
	embers.Orientation = Enum.ParticleOrientation.VelocityParallel
	embers.Rate = 6
	embers.Lifetime = NumberRange.new(0.5, 0.9)
	embers.Speed = NumberRange.new(2, 4)
	embers.SpreadAngle = Vector2.new(60, 60)
	embers.Acceleration = Vector3.new(0, 6, 0)
	embers.Size = seq({ { 0, 0.3 }, { 1, 0.05 } })
	embers.Parent = center

	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "AxeSmoke"
	smoke.Texture = WorldVfx.SMOKE_PUFF_4X4
	smoke.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
	smoke.FlipbookMode = Enum.ParticleFlipbookMode.Random
	smoke.Color = ColorSequence.new(Color3.fromRGB(46, 38, 36))
	smoke.LightInfluence = 0.6
	smoke.Rate = 3
	smoke.Lifetime = NumberRange.new(0.8, 1.2)
	smoke.Speed = NumberRange.new(0.5, 1)
	smoke.Acceleration = Vector3.new(0, 3, 0)
	smoke.Size = seq({ { 0, 0.8 }, { 1, 2 } })
	smoke.Transparency = seq({ { 0, 1 }, { 0.2, 0.6 }, { 1, 1 } })
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.ZOffset = -0.5
	smoke.Parent = center

	local light = Instance.new("PointLight")
	light.Name = "AxeGlow"
	light.Color = Color3.fromRGB(255, 120, 40)
	light.Brightness = 1.6
	light.Range = 9
	light.Shadows = false
	light.Parent = center

	local trail = Instance.new("Trail")
	trail.Name = "AxeSwing"
	trail.Attachment0, trail.Attachment1 = edgeA, edgeB
	trail.Texture = WorldVfx.FLAME_STREAK
	trail.TextureMode = Enum.TextureMode.Stretch
	trail.Color = FIRE
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Lifetime = 0.2
	trail.MinLength = 0.15 -- only draws while the axe actually moves
	trail.Transparency = seq({ { 0, 0.15 }, { 1, 1 } })
	trail.WidthScale = seq({ { 0, 1 }, { 1, 0.4 } })
	trail.Parent = center
end

-- Live mobs carry MobID; the dev animation showcase's display copies (Workspace.AnimationShowcase,
-- SSS/AnimationShowcase) carry ShowcaseMobID instead, so nothing else mistakes them for mobs.
local function consider(child)
	if child:IsA("Model") and (child:GetAttribute("MobID") == MOB_ID or child:GetAttribute("ShowcaseMobID") == MOB_ID) then
		task.spawn(decorate, child)
	end
end

local function watchShowcase(folder)
	if not (folder:IsA("Folder") and folder.Name == "AnimationShowcase") then return end
	for _, child in ipairs(folder:GetChildren()) do
		consider(child)
	end
	folder.ChildAdded:Connect(consider)
end

for _, child in ipairs(Workspace:GetChildren()) do
	consider(child)
	watchShowcase(child)
end
Workspace.ChildAdded:Connect(function(child)
	consider(child)
	watchShowcase(child)
end)
