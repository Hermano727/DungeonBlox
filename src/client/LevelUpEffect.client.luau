--[[
	LevelUpEffect (client)

	A skill level-up, seen by everyone nearby: ribbons of translucent golden light swirl round the
	player and rise past their head (light trails on a spiral, some turning each way), inside a
	warm drifting haze, while their body glows gold in two pulses (a Highlight) and a warm light
	swells on everything around them. No sparkles: that look belongs to the region-discovery
	banner.

	The server fires GameEvents/LevelUpEffect to ALL clients from ProfileService.AddSkillXP (and
	the F8 level setter) with (player, branch, level). Each client draws it if the player is
	within VIEW_RADIUS. The ribbons are world objects, so the levelling player sees them sweep
	past their own first-person view too; they also get a faint warm wash at the screen's edges.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local SfxService = require(ReplicatedStorage:WaitForChild("SfxService"))

local localPlayer = Players.LocalPlayer

local GOLD = Color3.fromRGB(255, 196, 80)
local PALE_GOLD = Color3.fromRGB(255, 240, 190)
local HAZE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local VIEW_RADIUS = 250 -- studs from the camera
local DURATION = 2.2 -- seconds, the whole effect

-- The ribbons: each a short light trail drawn by a point that spirals up round the body.
local RIBBONS = 7
local RIBBON_LIFE = 1.4 -- seconds from the feet to above the head
local RIBBON_STAGGER = 0.45 -- the last ribbon starts this long after the first
local RIBBON_FROM, RIBBON_TO = -2.6, 4.2 -- height relative to the root
local RIBBON_RADIUS = { 2.0, 3.4 } -- studs out from the body (random per ribbon)
local RIBBON_SPIN = { 4.5, 6.5 } -- radians per second (random per ribbon, alternate ways)
local RIBBON_WIDTH = 0.55 -- studs
local TRAIL_LIFETIME = 0.5 -- how long a ribbon's tail lingers

-- The haze: big soft blobs of warm light drifting out from the body.
local HAZE_BURSTS = { { at = 0, count = 10 }, { at = 0.5, count = 7 } }

-- The body glow: two pulses, the second softer.
local GLOW_PULSES = { { at = 0, peak = 0.45 }, { at = 0.6, peak = 0.7 } } -- peak = lowest fill transparency
local GLOW_PULSE_TIME = 0.9

local LIGHT_RANGE, LIGHT_PEAK = 20, 3

local rng = Random.new()

local function easeInOut(u)
	return u * u * (3 - 2 * u)
end

-- 0 at the start of a pulse, 1 at its peak (1/3 in), back to 0 at its end.
local function pulse(u)
	if u <= 0 or u >= 1 then return 0 end
	if u < 1 / 3 then return u * 3 end
	return 1 - (u - 1 / 3) * 1.5
end

local function anchorPart(parent)
	local part = Instance.new("Part")
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide, part.CanTouch, part.CanQuery = false, false, false
	part.CastShadow = false
	part.Parent = parent
	return part
end

local function newRibbon(folder, index)
	local part = anchorPart(folder)
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	a0.Position = Vector3.new(0, RIBBON_WIDTH / 2, 0)
	a1.Position = Vector3.new(0, -RIBBON_WIDTH / 2, 0)
	a0.Parent, a1.Parent = part, part
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.FaceCamera = true
	trail.Lifetime = TRAIL_LIFETIME
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Color = ColorSequence.new(PALE_GOLD, GOLD)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(0.5, 0.55), NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
	pcall(function() trail.Brightness = 2 end) -- newer property; harmless if missing
	trail.Enabled = false
	trail.Parent = part
	return {
		part = part, trail = trail,
		delay = (index - 1) / math.max(1, RIBBONS - 1) * RIBBON_STAGGER,
		phase = rng:NextNumber(0, math.pi * 2),
		radius = rng:NextNumber(RIBBON_RADIUS[1], RIBBON_RADIUS[2]),
		spin = rng:NextNumber(RIBBON_SPIN[1], RIBBON_SPIN[2]) * (index % 2 == 0 and -1 or 1),
		wobble = rng:NextNumber(0.2, 0.5), -- the radius breathes a little, so the paths aren't perfect circles
	}
end

-- A faint warm wash at the top and bottom of the leveller's own screen, breathing with the glow.
local function screenWash()
	local gui = Instance.new("ScreenGui")
	gui.Name = "LevelUpWash"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 5
	gui.ResetOnSpawn = false
	local wash = Instance.new("Frame")
	wash.Size = UDim2.fromScale(1, 1)
	wash.BackgroundColor3 = GOLD
	wash.BackgroundTransparency = 1
	wash.BorderSizePixel = 0
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.4, 0.9),
		NumberSequenceKeypoint.new(0.6, 0.9), NumberSequenceKeypoint.new(1, 0.2),
	})
	gradient.Parent = wash
	wash.Parent = gui
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
	return gui, wash
end

local function play(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	if not root or not camera then return end
	if (root.Position - camera.CFrame.Position).Magnitude > VIEW_RADIUS then return end

	local folder = Instance.new("Folder")
	folder.Name = "LevelUpEffect"
	folder.Parent = workspace

	local ribbons = {}
	for i = 1, RIBBONS do
		ribbons[i] = newRibbon(folder, i)
	end

	-- The haze rides on the root (so it follows a moving player) and is emitted in bursts.
	local hazeAt = Instance.new("Attachment")
	hazeAt.Parent = root
	local haze = Instance.new("ParticleEmitter")
	haze.Texture = HAZE_TEXTURE
	haze.Color = ColorSequence.new(PALE_GOLD, GOLD)
	haze.LightEmission = 1
	haze.LightInfluence = 0
	haze.Rate = 0
	haze.Lifetime = NumberRange.new(0.7, 1.1)
	haze.Speed = NumberRange.new(1.5, 3.5)
	haze.SpreadAngle = Vector2.new(180, 60)
	haze.Drag = 2
	haze.Acceleration = Vector3.new(0, 2.5, 0)
	haze.Rotation = NumberRange.new(0, 360)
	haze.RotSpeed = NumberRange.new(-40, 40)
	haze.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 6) })
	haze.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.78), NumberSequenceKeypoint.new(1, 1),
	})
	haze.Parent = hazeAt

	local glow = Instance.new("Highlight")
	glow.FillColor = GOLD
	glow.OutlineColor = PALE_GOLD
	glow.FillTransparency, glow.OutlineTransparency = 1, 1
	glow.DepthMode = Enum.HighlightDepthMode.Occluded
	glow.Adornee = character
	glow.Parent = folder

	local light = Instance.new("PointLight")
	light.Color = GOLD
	light.Range = LIGHT_RANGE
	light.Brightness = 0
	light.Shadows = false
	light.Parent = root

	local washGui, wash
	if player == localPlayer then
		washGui, wash = screenWash()
	end

	SfxService.PlayEffect("LevelUp", { Position = root.Position })

	local start = os.clock()
	local burstsDone = 0
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		if t >= DURATION or not root.Parent then
			conn:Disconnect()
			folder:Destroy()
			hazeAt:Destroy()
			light:Destroy()
			if washGui then washGui:Destroy() end
			return
		end
		local centre = root.Position

		-- The ribbons: a point spiralling up, its trail drawing the light behind it.
		for _, r in ipairs(ribbons) do
			local u = (t - r.delay) / RIBBON_LIFE
			if u >= 0 and u <= 1 then
				local angle = r.phase + r.spin * (t - r.delay)
				local radius = r.radius * (1 + math.sin(u * math.pi * 2 + r.phase) * r.wobble * 0.3)
					* (1 - 0.35 * u) -- drawing in a little as it rises
				local height = RIBBON_FROM + (RIBBON_TO - RIBBON_FROM) * easeInOut(u)
				r.part.CFrame = CFrame.new(centre + Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius))
				r.trail.Enabled = true
			else
				r.trail.Enabled = false
			end
		end

		while burstsDone < #HAZE_BURSTS and t >= HAZE_BURSTS[burstsDone + 1].at do
			burstsDone += 1
			haze:Emit(HAZE_BURSTS[burstsDone].count)
		end

		-- The body glow and the light, pulsing together.
		local strongest, fill = 0, 1
		for _, p in ipairs(GLOW_PULSES) do
			local k = pulse((t - p.at) / GLOW_PULSE_TIME)
			fill = math.min(fill, 1 - (1 - p.peak) * k)
			strongest = math.max(strongest, k)
		end
		glow.FillTransparency = fill
		glow.OutlineTransparency = 1 - strongest * 0.8
		light.Brightness = LIGHT_PEAK * strongest
		if wash then
			wash.BackgroundTransparency = 1 - strongest * 0.4
		end
	end)
end

task.spawn(function()
	local event = ReplicatedStorage:WaitForChild("GameEvents"):WaitForChild("LevelUpEffect")
	event.OnClientEvent:Connect(function(player)
		if typeof(player) == "Instance" and player:IsA("Player") then
			play(player)
		end
	end)
end)
