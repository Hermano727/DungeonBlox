--[[
	MiasmaStunFX -- "dazed" star rings, and Miasma's vulnerable outline (client only).

	Ring: four small yellow neon stars joined by curved lines (* - * - * - *) closing a full
	circle above a head. It spins and wobbles like a dizzy halo. Stars are 3-bar asterisks
	turned to face the camera, so they read as "*" from any angle.

	Two users, each with its own slot:
	  Boss    StunFX.Start(bossModel, { duration, vulnerable }) / StunFX.Stop()
	          Rides the crown bone and sizes itself off the boss's mesh width every frame, so it
	          follows the water stun's shrink on its own. vulnerable = also a Highlight drawn
	          through walls with a pulsing warm fill (the pure-water stun only).
	  Players StunFX.StartPlayers({ Player }, duration) / StunFX.StopPlayers()
	          A small fixed-size ring over each listed player's head (the landing-slam freeze).
	Starting a slot replaces whatever that slot was showing.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local StunFX = {}

local STAR_COUNT = 4
local SEGMENTS_PER_ARC = 5         -- straight pieces that make up each curved line between two stars
local STAR_COLOR = Color3.fromRGB(255, 221, 64)
local LINE_COLOR = Color3.fromRGB(255, 200, 40)
local LINE_GAP = 1.6               -- clear space left around each star, in star-arm lengths
local SPIN_SPEED = 1.9             -- rad/s, the ring around the head
local STAR_SPIN_SPEED = 4          -- rad/s, each star about its own centre
local WOBBLE = math.rad(13)        -- halo tilt
local WOBBLE_SPEED = 2.3
local GROW_TIME = .25
local FADE_TIME = .3

-- Proportions, all in ring radii.
local BOSS_STYLE = {
	starArm = .15, starThickness = .045, lineThickness = .03, lift = .3,
	minThick = .1, minLineThick = .08, lightBrightness = 1.6, minLightRange = 6,
}
local PLAYER_STYLE = {
	starArm = .24, starThickness = .07, lineThickness = .045, lift = .15,
	minThick = .05, minLineThick = .04, lightBrightness = .6, minLightRange = 3,
}

-- Boss sizing.
local RING_RADIUS_PER_WIDTH = .2   -- ring radius as a share of the boss mesh's width
local CROWN_BONE = "Crown_Center_Core"
-- Player sizing.
local PLAYER_RING_RADIUS = 1.4
local PLAYER_HEAD_CLEARANCE = .5   -- studs from the top of the head to the ring

local OUTLINE_COLOR = Color3.fromRGB(255, 246, 205)
local FILL_COLOR = Color3.fromRGB(255, 196, 70)
local FILL_PULSE_SPEED = 5

local function neonPart(name, color, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Size = Vector3.new(.2, .2, .2)
	part.Parent = parent
	return part
end

local function vfxRoot()
	return Workspace:FindFirstChild("MiasmaEncounterVFX") or Workspace
end

--[[
	ring(spec) -> fx. spec:
	  anchor()  -> Vector3?   top of the head; nil ends the ring (target gone)
	  radius()  -> number     ring radius this frame
	  style                   BOSS_STYLE / PLAYER_STYLE
	  outline                 optional Highlight adornee (vulnerable pulse)
	  duration                optional auto-stop (seconds)
	fx:Stop() fades it out and cleans up.
]]
local function ring(spec)
	local style = spec.style
	local folder = Instance.new("Folder")
	folder.Name = "MiasmaStunRing"
	folder.Parent = vfxRoot()

	local stars, lines = {}, {}
	for i = 1, STAR_COUNT do
		local bars = {}
		for b = 1, 3 do bars[b] = neonPart("StarBar", STAR_COLOR, folder) end
		stars[i] = bars
		for k = 1, SEGMENTS_PER_ARC do
			table.insert(lines, { part = neonPart("Line", LINE_COLOR, folder), star = i, segment = k })
		end
	end
	local glow = neonPart("Glow", STAR_COLOR, folder)
	glow.Transparency = 1
	local light = Instance.new("PointLight")
	light.Color = STAR_COLOR
	light.Brightness = style.lightBrightness
	light.Parent = glow

	local fx = { started = os.clock(), stopping = false, stopAt = 0 }
	function fx:Stop()
		if self.stopping then return end
		self.stopping = true
		self.stopAt = os.clock()
	end

	local outline
	if spec.outline then
		outline = Instance.new("Highlight")
		outline.Name = "MiasmaVulnerableOutline"
		outline.Adornee = spec.outline
		outline.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		outline.OutlineColor = OUTLINE_COLOR
		outline.OutlineTransparency = 0
		outline.FillColor = FILL_COLOR
		outline.FillTransparency = 1
		outline.Parent = folder
	end

	if spec.duration and spec.duration > 0 then
		task.delay(spec.duration + .25, function() fx:Stop() end)
	end

	local parts, cframes = {}, {}
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local fade = fx.stopping and math.clamp((now - fx.stopAt) / FADE_TIME, 0, 1) or 0
		local head = folder.Parent and spec.anchor()
		if fade >= 1 or not head then
			connection:Disconnect()
			folder:Destroy()
			fx.stopping = true
			return
		end

		local t = now - fx.started
		local grow = math.clamp(t / GROW_TIME, 0, 1)
		grow = 1 - (1 - grow) ^ 3
		local radius = spec.radius() * grow
		local thick = math.max(style.minThick, radius * style.starThickness)
		local lineThick = math.max(style.minLineThick, radius * style.lineThickness)
		local starArm = radius * style.starArm
		local transparency = fade

		local centre = head + Vector3.new(0, radius * style.lift + starArm, 0)
		local frame = CFrame.new(centre)
			* CFrame.Angles(math.sin(t * WOBBLE_SPEED) * WOBBLE, 0, math.cos(t * WOBBLE_SPEED) * WOBBLE)
			* CFrame.Angles(0, t * SPIN_SPEED, 0)
		local camera = Workspace.CurrentCamera
		local eye = camera and camera.CFrame.Position or centre + Vector3.new(0, 0, 10)

		table.clear(parts); table.clear(cframes)
		local step = 2 * math.pi / STAR_COUNT
		for i, bars in ipairs(stars) do
			local angle = (i - 1) * step
			local pos = (frame * CFrame.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)).Position
			local face = CFrame.lookAt(pos, eye) * CFrame.Angles(0, 0, t * STAR_SPIN_SPEED + i)
			for b, bar in ipairs(bars) do
				bar.Size = Vector3.new(thick, starArm * 2, thick)
				bar.Transparency = transparency
				table.insert(parts, bar)
				table.insert(cframes, face * CFrame.Angles(0, 0, (b - 1) * math.pi / 3))
			end
		end
		-- Lines: each gap between two stars is an arc of short straight pieces, ending a little
		-- short of both stars so each star stays readable.
		local gap = math.min(step * .3, (starArm * LINE_GAP) / math.max(radius, .01))
		local arcSpan = (step - 2 * gap) / SEGMENTS_PER_ARC
		for _, line in ipairs(lines) do
			local a0 = (line.star - 1) * step + gap + (line.segment - 1) * arcSpan
			local p0 = Vector3.new(math.cos(a0) * radius, 0, math.sin(a0) * radius)
			local p1 = Vector3.new(math.cos(a0 + arcSpan) * radius, 0, math.sin(a0 + arcSpan) * radius)
			local len = (p1 - p0).Magnitude
			line.part.Size = Vector3.new(lineThick, lineThick, len + lineThick) -- overlap hides the joints
			line.part.Transparency = transparency
			table.insert(parts, line.part)
			table.insert(cframes, frame * CFrame.lookAt((p0 + p1) * .5, p1))
		end
		table.insert(parts, glow)
		table.insert(cframes, CFrame.new(centre))
		Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)

		light.Range = math.max(style.minLightRange, radius * 2.2)
		light.Brightness = style.lightBrightness * (1 - fade)

		if outline then
			local pulse = (math.sin(t * FILL_PULSE_SPEED) + 1) * .5
			outline.FillTransparency = 1 - (1 - (.55 + .3 * (1 - pulse))) * (1 - fade) * grow
			outline.OutlineTransparency = fade
		end
	end)
	return fx
end

----------------------------------------------------------------------
-- Boss slot
----------------------------------------------------------------------

local bossRing

function StunFX.Stop()
	if bossRing then bossRing:Stop(); bossRing = nil end
end

function StunFX.Start(boss, options)
	StunFX.Stop()
	if typeof(boss) ~= "Instance" or not boss:IsA("Model") or not boss.Parent then return end
	options = options or {}

	-- The skinned mesh (the widest MeshPart) sizes the ring; the crown bone carries it.
	local skin, crown
	for _, d in ipairs(boss:GetDescendants()) do
		if d:IsA("MeshPart") and (not skin or d.Size.X > skin.Size.X) then skin = d end
		if d:IsA("Bone") and d.Name == CROWN_BONE then crown = d end
	end

	bossRing = ring({
		style = BOSS_STYLE,
		duration = tonumber(options.duration),
		outline = options.vulnerable and boss or nil,
		anchor = function()
			if not boss.Parent then return nil end
			if crown and crown.Parent then return crown.TransformedWorldCFrame.Position end
			local cf, size = boss:GetBoundingBox()
			return cf.Position + Vector3.new(0, size.Y * .5, 0)
		end,
		radius = function()
			return math.max(1, (skin and skin.Size.X or 20) * RING_RADIUS_PER_WIDTH)
		end,
	})
end

----------------------------------------------------------------------
-- Player slot
----------------------------------------------------------------------

local playerRings = {}

function StunFX.StopPlayers()
	for _, fx in ipairs(playerRings) do fx:Stop() end
	table.clear(playerRings)
end

function StunFX.StartPlayers(players, duration)
	StunFX.StopPlayers()
	if type(players) ~= "table" then return end
	for _, player in ipairs(players) do
		if typeof(player) == "Instance" and player:IsA("Player") then
			local character = player.Character
			table.insert(playerRings, ring({
				style = PLAYER_STYLE,
				duration = tonumber(duration),
				-- Bound to THIS character: a respawn mid-stun ends the ring instead of moving it.
				anchor = function()
					local head = character and character.Parent and character:FindFirstChild("Head")
					if not head then return nil end
					return head.Position + Vector3.new(0, head.Size.Y * .5 + PLAYER_HEAD_CLEARANCE, 0)
				end,
				radius = function() return PLAYER_RING_RADIUS end,
			}))
		end
	end
end

return StunFX
