--[[
	MiasmaShroudFX -- the enrage shroud: Miasma's breath rolls out to the arena edge and becomes a
	closing ring of poison mist (client visuals only; the server stacks poison on anyone outside
	it -- MiasmaEncounterController:_updateShroud, numbers in MiasmaEncounterConfig.Enrage.Shroud).

		Shroud.Start(payload, parent)   payload = the "Shroud" presentation:
			centre, origin     arena centre; where the breath starts (Miasma)
			waveAt, landsAt    server times: breath leaves the mouth / reaches the edge
			startRadius, endRadius, shrinkSeconds
		Shroud.Stop()

	Pieces, all driven by the SAME radius formula as the server (so what you see is what hits):
	  wave    ANCHORS points on a ring expanding from `origin` to startRadius, trailing mist
	  wall    the same points parked on the ring, emitting a tall purple mist wall that
	          creeps inward, radius closing to endRadius over shrinkSeconds
	  edge    a glowing purple boundary line drawn on the floor at the current radius
	  inside  purple screen tint + edge vignette while YOU stand outside the ring
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shroud = {}

local ANCHORS = 52
local MIST = Color3.fromRGB(125, 55, 165)
local MIST_DARK = Color3.fromRGB(60, 25, 80)
local EDGE = Color3.fromRGB(175, 80, 230)
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local EDGE_RESIZE_HZ = 8 -- the floor ring is a big SurfaceGui disc; resizing it every frame is wasteful

local active

local function serverNow() return Workspace:GetServerTimeNow() end

local function radiusAt(p, now)
	if now < p.landsAt then return nil end
	local u = math.clamp((now - p.landsAt) / math.max(p.shrinkSeconds, 1), 0, 1)
	return p.startRadius + (p.endRadius - p.startRadius) * u
end

local function floorY(centre)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {}
	for _, pl in ipairs(Players:GetPlayers()) do if pl.Character then table.insert(ignore, pl.Character) end end
	local vfx = Workspace:FindFirstChild("MiasmaEncounterVFX")
	if vfx then table.insert(ignore, vfx) end
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(centre + Vector3.new(0, 6, 0), Vector3.new(0, -60, 0), params)
	return hit and hit.Position.Y or centre.Y
end

local function anchorPart(parent)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Transparency = 1
	p.Size = Vector3.new(.2, .2, .2)
	p.Parent = parent
	return p
end

local function wallEmitter(part)
	local e = Instance.new("ParticleEmitter")
	e.Texture = SMOKE
	e.Color = ColorSequence.new(MIST, MIST_DARK)
	e.LightEmission = .25
	e.LightInfluence = .3
	-- Taller + thicker (2026-09-27): bigger, denser puffs that live longer and rise higher.
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 10), NumberSequenceKeypoint.new(.5, 20), NumberSequenceKeypoint.new(1, 26) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(.15, .3), NumberSequenceKeypoint.new(.7, .5), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(3, 4.2)
	e.Speed = NumberRange.new(5, 10)
	e.SpreadAngle = Vector2.new(18, 18)
	e.EmissionDirection = Enum.NormalId.Top
	e.Acceleration = Vector3.new(0, 3, 0)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-25, 25)
	e.Rate = 0
	e.Parent = part
	return e
end

local function buildEdge(parent, diameter)
	local disc = anchorPart(parent)
	disc.Name = "ShroudEdge"
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(1024, 1024)
	gui.LightInfluence = 0
	gui.Brightness = 2.2
	gui.Parent = disc
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(.5, .5)
	ring.Position = UDim2.fromScale(.5, .5)
	ring.Size = UDim2.fromScale(.985, .985)
	ring.BackgroundTransparency = 1
	ring.Parent = gui
	Instance.new("UICorner", ring).CornerRadius = UDim.new(.5, 0)
	local stroke = Instance.new("UIStroke")
	stroke.Color = EDGE
	stroke.Thickness = 7
	stroke.Transparency = .1
	stroke.Parent = ring
	-- Soft inner glow band just inside the line.
	local glow = Instance.new("Frame")
	glow.AnchorPoint = Vector2.new(.5, .5)
	glow.Position = UDim2.fromScale(.5, .5)
	glow.Size = UDim2.fromScale(.985, .985)
	glow.BackgroundTransparency = 1
	glow.Parent = gui
	Instance.new("UICorner", glow).CornerRadius = UDim.new(.5, 0)
	local glowStroke = Instance.new("UIStroke")
	glowStroke.Color = MIST
	glowStroke.Thickness = 22
	glowStroke.Transparency = .7
	glowStroke.Parent = glow
	disc.Size = Vector3.new(diameter, .05, diameter)
	return disc, stroke
end

local function buildScreenTint()
	local gui = Instance.new("ScreenGui")
	gui.Name = "MiasmaShroudTint"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 40
	local edges = {}
	for _, spec in ipairs({
		{ Vector2.new(.5, 0), UDim2.fromScale(.5, 0), UDim2.fromScale(1, .22), 90 },
		{ Vector2.new(.5, 1), UDim2.fromScale(.5, 1), UDim2.fromScale(1, .22), -90 },
		{ Vector2.new(0, .5), UDim2.fromScale(0, .5), UDim2.fromScale(.18, 1), 0 },
		{ Vector2.new(1, .5), UDim2.fromScale(1, .5), UDim2.fromScale(.18, 1), 180 },
	}) do
		local f = Instance.new("Frame")
		f.AnchorPoint, f.Position, f.Size = spec[1], spec[2], spec[3]
		f.BackgroundColor3 = MIST
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		local g = Instance.new("UIGradient")
		g.Rotation = spec[4]
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
		g.Parent = f
		f.Parent = gui
		table.insert(edges, f)
	end
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "MiasmaShroudGrade"
	grade.Enabled = true
	grade.Parent = Lighting
	return gui, edges, grade
end

function Shroud.Stop()
	local s = active
	if not s then return end
	active = nil
	if s.conn then s.conn:Disconnect() end
	for _, e in ipairs(s.emitters) do e.Enabled = false; e.Rate = 0 end
	if s.grade then s.grade:Destroy() end
	if s.tintGui then s.tintGui:Destroy() end
	local folder = s.folder
	task.delay(3.5, function() folder:Destroy() end) -- let the mist drift out
end

function Shroud.Start(p, parent)
	Shroud.Stop()
	if type(p) ~= "table" or typeof(p.centre) ~= "Vector3" then return end
	local payload = {
		centre = p.centre,
		origin = typeof(p.origin) == "Vector3" and p.origin or p.centre,
		waveAt = tonumber(p.waveAt) or serverNow(),
		landsAt = tonumber(p.landsAt) or serverNow(),
		startRadius = tonumber(p.startRadius) or 90,
		endRadius = tonumber(p.endRadius) or 46,
		shrinkSeconds = tonumber(p.shrinkSeconds) or 100,
	}
	local folder = Instance.new("Folder")
	folder.Name = "MiasmaShroud"
	folder.Parent = parent or Workspace
	local y = floorY(payload.centre)
	local s = { folder = folder, emitters = {}, anchors = {}, lastEdge = 0 }
	for i = 1, ANCHORS do
		local a = anchorPart(folder)
		a.Name = "ShroudMist"
		local e = wallEmitter(a)
		table.insert(s.anchors, { part = a, angle = (i - 1) / ANCHORS * math.pi * 2 + math.random() * .08 })
		table.insert(s.emitters, e)
	end
	local edge, edgeStroke = buildEdge(folder, payload.startRadius * 2)
	edge.Transparency = 1
	edge.CFrame = CFrame.new(payload.centre.X, y + .15, payload.centre.Z)
	edge.Parent = nil -- appears when the wave lands
	s.edge = edge
	s.tintGui, s.tintEdges, s.grade = buildScreenTint()
	s.outside = false
	active = s

	local player = Players.LocalPlayer
	local parts, cframes = {}, {}
	s.conn = RunService.RenderStepped:Connect(function()
		local now = serverNow()
		local radius = radiusAt(payload, now)
		local wave = now >= payload.waveAt and now < payload.landsAt
		table.clear(parts); table.clear(cframes)

		if now < payload.waveAt then return end
		-- Where the mist sits: rolling out from Miasma during the wave, then on the ring.
		local u = wave and math.clamp((now - payload.waveAt) / math.max(payload.landsAt - payload.waveAt, .01), 0, 1) or 1
		u = 1 - (1 - u) ^ 2
		for i, anchor in ipairs(s.anchors) do
			local dir = Vector3.new(math.cos(anchor.angle), 0, math.sin(anchor.angle))
			local pos
			if wave then
				local startP = payload.origin
				local endP = payload.centre + dir * payload.startRadius
				pos = startP:Lerp(endP, u)
			else
				pos = payload.centre + dir * (radius or payload.startRadius)
			end
			table.insert(parts, anchor.part)
			table.insert(cframes, CFrame.new(pos.X, y + 1, pos.Z))
			s.emitters[i].Rate = wave and 18 or 9
		end
		Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)

		if radius then
			if not s.edge.Parent then
				s.edge.Parent = folder
				edgeStroke.Transparency = 1
				TweenService:Create(edgeStroke, TweenInfo.new(.6), { Transparency = .1 }):Play()
			end
			if os.clock() - s.lastEdge > 1 / EDGE_RESIZE_HZ then
				s.lastEdge = os.clock()
				s.edge.Size = Vector3.new(radius * 2, .05, radius * 2)
			end
			-- Local player outside the ring: purple tint + pulsing edges.
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local outside = false
			if root then
				local flat = Vector3.new(root.Position.X - payload.centre.X, 0, root.Position.Z - payload.centre.Z)
				outside = flat.Magnitude > radius
			end
			if outside ~= s.outside then
				s.outside = outside
				TweenService:Create(s.grade, TweenInfo.new(.4), {
					TintColor = outside and Color3.fromRGB(225, 195, 240) or Color3.new(1, 1, 1),
					Saturation = outside and -.25 or 0,
				}):Play()
			end
			local pulse = outside and ((math.sin(os.clock() * 5) + 1) * .5) or 0
			for _, f in ipairs(s.tintEdges) do f.BackgroundTransparency = outside and (.35 + .35 * (1 - pulse)) or 1 end
		end
	end)
end

return Shroud
