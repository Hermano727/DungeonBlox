--[[
	DashFx -- what a dash looks and sounds like, drawn on whichever client sees it.

	The dasher calls it straight from DashClient (no wait on the server); everyone else nearby gets it
	through GameEvents/DashFx (EnergyServer's RequestDash, client/DashFxClient). Client-local parts only,
	under Workspace.DashFx, cleaned up a second later.

		DashFx.Play(character, direction, { duration = 0.16, inAir = false })

	Layers (particles, Trails, a ring: no shaders, docs/vfx-pipeline.md):
	  * air burst    where the dash started: a puff of pale air flung backward and a shock ring around
	                 the body, standing across the line of travel, opening as the character leaves it
	  * dust         kicked up behind the feet (ground dashes only), plus a low skid out to the sides;
	                 a smaller puff where the dash stops
	  * speed lines  while it lasts: thin streaks thrown backward off a box around the body, and four
	                 Trails at the shoulders and hips drawing lines behind the character
	  * sound        DashWhoosh at the start point

	A future dash style (a class's flash step, a teleport) is another Play-like function here, picked by
	the same callers.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local WorldVfx = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images"):WaitForChild("WorldVfx"))
local SfxService = require(ReplicatedStorage:WaitForChild("SfxService"))

local DashFx = {}
DashFx.DEFAULT_DURATION = 0.16

local DUST = Color3.fromRGB(150, 132, 108)
local AIR = Color3.fromRGB(232, 238, 244)
local WHITE = Color3.new(1, 1, 1)
local keys = NumberSequenceKeypoint.new
local UP = Vector3.new(0, 1, 0)

local folder
local function fxFolder()
	if folder and folder.Parent then return folder end
	folder = Instance.new("Folder")
	folder.Name = "DashFx"
	folder.Parent = workspace
	return folder
end

local function anchor(cframe, size)
	local part = Instance.new("Part")
	part.Name = "DashFxAnchor"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = size or Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = cframe
	part.Parent = fxFolder()
	Debris:AddItem(part, 1.6)
	return part
end

local function emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	e.LightInfluence = 0.6
	if props.Texture == WorldVfx.SMOKE_PUFF_4X4 then
		e.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
		e.FlipbookMode = Enum.ParticleFlipbookMode.Random
	end
	for key, value in pairs(props) do e[key] = value end
	e.Parent = parent
	return e
end

local function smoke(parent, color, size0, size1, transparency, lifetime, speed, spread, extra)
	local props = {
		Texture = WorldVfx.SMOKE_PUFF_4X4, Color = ColorSequence.new(color),
		Size = NumberSequence.new({ keys(0, size0), keys(0.35, size1 * 0.8), keys(1, size1) }),
		Transparency = NumberSequence.new({ keys(0, transparency), keys(0.5, transparency + (1 - transparency) * 0.4), keys(1, 1) }),
		Lifetime = lifetime, Speed = speed, SpreadAngle = spread, Drag = 7,
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-60, 60),
		EmissionDirection = Enum.NormalId.Front,
	}
	for key, value in pairs(extra or {}) do props[key] = value end
	return emitter(parent, props)
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function groundBelow(character, position)
	rayParams.FilterDescendantsInstances = { character, fxFolder() }
	local hit = workspace:Raycast(position, Vector3.new(0, -7, 0), rayParams)
	return hit and hit.Position or nil
end

-- A part looking `facing`, at `position` (its Front face, and so EmissionDirection Front, points there).
local function facingFrom(position, facing)
	return CFrame.lookAt(position, position + facing)
end

local function dustBurst(character, position, back, big)
	local ground = groundBelow(character, position)
	if not ground then return end
	local part = anchor(facingFrom(ground + UP * 0.3, (back + UP * 0.35).Unit))
	local kick = smoke(part, DUST, big and 1.1 or 0.8, big and 3.8 or 2.6, 0.35,
		NumberRange.new(0.5, 0.9), NumberRange.new(big and 8 or 5, big and 14 or 9), Vector2.new(30, 18),
		{ Acceleration = UP * 3 })
	kick:Emit(big and 14 or 6)
	local skid = smoke(part, DUST, 0.7, 2.4, 0.45, NumberRange.new(0.4, 0.7), NumberRange.new(3, 7), Vector2.new(85, 6))
	skid:Emit(big and 8 or 4)
end

local function airBurst(position, back, inAir)
	local part = anchor(facingFrom(position, back))
	smoke(part, AIR, 1.4, inAir and 6 or 5, 0.5, NumberRange.new(0.28, 0.42), NumberRange.new(10, 18), Vector2.new(50, 50),
		{ LightEmission = 0.25 }):Emit(inAir and 12 or 9)
	-- The ring: emitted backward, VelocityPerpendicular faces it along that, so it stands across the line
	-- of travel around the body.
	emitter(part, {
		Texture = WorldVfx.SHOCK_RING, Color = ColorSequence.new(WHITE),
		Size = NumberSequence.new({ keys(0, 2.2), keys(0.3, 6.5), keys(1, inAir and 10 or 9) }),
		Transparency = NumberSequence.new({ keys(0, 0.3), keys(0.5, 0.6), keys(1, 1) }),
		Lifetime = NumberRange.new(0.3, 0.3), Speed = NumberRange.new(2, 2), SpreadAngle = Vector2.zero,
		EmissionDirection = Enum.NormalId.Front, Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-120, 120),
		LightEmission = 0.5, LightInfluence = 0.2,
	}):Emit(1)
end

local TRAIL_POINTS = { Vector3.new(1.05, 0.9, 0), Vector3.new(-1.05, 0.9, 0), Vector3.new(0.65, -1.2, 0), Vector3.new(-0.65, -1.2, 0) }

local function speedLines(root, direction, duration)
	local follow = anchor(facingFrom(root.Position, direction), Vector3.new(2.6, 4.4, 0.6))
	local lines = emitter(follow, {
		Texture = WorldVfx.SPARK, Color = ColorSequence.new(WHITE),
		Size = NumberSequence.new({ keys(0, 1.9), keys(1, 0.6) }),
		Transparency = NumberSequence.new({ keys(0, 0.25), keys(0.6, 0.55), keys(1, 1) }),
		Lifetime = NumberRange.new(0.14, 0.22), Speed = NumberRange.new(28, 40), SpreadAngle = Vector2.new(4, 4),
		EmissionDirection = Enum.NormalId.Back, Orientation = Enum.ParticleOrientation.VelocityParallel,
		Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Rate = 150, LightEmission = 0.7, LightInfluence = 0.2,
	})
	lines.Enabled = true
	local trails = {}
	for _, offset in ipairs(TRAIL_POINTS) do
		local a0 = Instance.new("Attachment"); a0.Position = offset + Vector3.new(0, 0.12, 0); a0.Parent = follow
		local a1 = Instance.new("Attachment"); a1.Position = offset - Vector3.new(0, 0.12, 0); a1.Parent = follow
		local trail = Instance.new("Trail")
		trail.Attachment0, trail.Attachment1 = a0, a1
		trail.Lifetime = 0.2
		trail.Color = ColorSequence.new(WHITE)
		trail.Transparency = NumberSequence.new({ keys(0, 0.35), keys(1, 1) })
		trail.WidthScale = NumberSequence.new({ keys(0, 1), keys(1, 0) })
		trail.LightEmission = 0.6
		trail.FaceCamera = true
		trail.MinLength = 0.05
		trail.Parent = follow
		table.insert(trails, trail)
	end
	local started = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if not root.Parent or os.clock() - started >= duration then
			conn:Disconnect()
			lines.Enabled = false
			for _, trail in ipairs(trails) do trail.Enabled = false end
			return
		end
		follow.CFrame = facingFrom(root.Position, direction)
	end)
end

function DashFx.Play(character, direction, options)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or typeof(direction) ~= "Vector3" then return end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 1e-3 then return end
	flat = flat.Unit
	options = options or {}
	local duration = math.clamp(tonumber(options.duration) or DashFx.DEFAULT_DURATION, 0.08, 0.3)
	local inAir = options.inAir == true
	local start = root.Position
	local back = -flat

	airBurst(start, back, inAir)
	if not inAir then dustBurst(character, start, back, true) end
	speedLines(root, flat, duration)
	SfxService.PlayEffect("DashWhoosh", { Position = start, Volume = 0.7, PlaybackSpeed = 0.9, RollOffMaxDistance = 120 })
	task.delay(duration, function()
		if root.Parent then dustBurst(character, root.Position, flat, false) end -- a scuff where it stops
	end)
end

return DashFx
