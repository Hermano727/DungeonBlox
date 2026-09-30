--[[
	DiscoveryPeek -- the in-world "sneak peek" when a region is first discovered: a curtain of
	yellow light rays along the zone's whole real outline. The rays shoot up out of the ground,
	hold, then lift off and fade. Client only, a few seconds. Tuning: MinimapConfig.Peek.

		DiscoveryPeek.Play(zone)   -- a ZoneService wire row (points or legacy circle)

	Two layers per piece of outline (pieces are PieceLength studs, so it follows the ground):
	  ray   a Beam from the ground straight up, facing the camera, additive (LightEmission 1),
	        solid at the base and fading out toward the top. Tall, so it clears hills.
	  band  a thin neon slab on the ground; all slabs share one Highlight with DepthMode
	        AlwaysOnTop, so the outline also shows through terrain and walls.
	Around the player there's a gap: nothing within Peek.SafeRadius, then both ramp up to full
	height over Peek.SafeRamp ( -----_    o    _----- ), so it never flares in their face.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("MinimapConfig"))

local DiscoveryPeek = {}

local function easeOut(u) return 1 - (1 - u) ^ 3 end
local function easeIn(u) return u * u end

function DiscoveryPeek.Play(zone)
	local cfg = Config.Peek
	local outline = Config.ZoneOutline(zone)
	if #outline < 2 then return end

	local terrain = Workspace.Terrain
	local folder = Instance.new("Folder")
	folder.Name = "RegionPeek"
	local band = Instance.new("Model")
	band.Name = "Band"
	band.Parent = folder

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { folder, Players.LocalPlayer.Character }
	local fallbackY = typeof(zone.center) == "Vector3" and zone.center.Y or 0
	local character = Players.LocalPlayer.Character
	local me = character and character:FindFirstChild("HumanoidRootPart")
	-- 0 right next to the player, 1 past the ramp (smoothstep): scales each piece's height.
	local function strengthAt(x, z)
		if not me then return 1 end
		local d = Vector2.new(x - me.Position.X, z - me.Position.Z).Magnitude
		local u = math.clamp((d - cfg.SafeRadius) / math.max(1, cfg.SafeRamp), 0, 1)
		return u * u * (3 - 2 * u)
	end
	local function groundY(x, z)
		local hit = Workspace:Raycast(Vector3.new(x, 1500, z), Vector3.new(0, -3000, 0), params)
		return hit and hit.Position.Y or fallbackY
	end

	-- Solid near the ground, fading out toward the top of the ray.
	local rayFade = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(.25, .15),
		NumberSequenceKeypoint.new(.7, .65),
		NumberSequenceKeypoint.new(1, 1),
	})

	local rays = {}      -- { beam, bottom, top, ground }
	local slabs = {}
	for i = 1, #outline do
		local a, b = outline[i], outline[i % #outline + 1]
		local dx, dz = b.x - a.x, b.z - a.z
		local length = math.sqrt(dx * dx + dz * dz)
		if length > .1 then
			local pieces = math.max(1, math.ceil(length / cfg.PieceLength))
			local pieceLength = length / pieces
			local angle = math.atan2(dz, dx)
			for k = 0, pieces - 1 do
				local u = (k + .5) / pieces
				local x, z = a.x + dx * u, a.z + dz * u
				local scale = strengthAt(x, z)
				if scale < .02 then continue end -- inside the player's safe gap
				local y = groundY(x, z)

				local bottom = Instance.new("Attachment")
				bottom.Position = Vector3.new(x, y, z) -- Terrain's frame is the world frame
				bottom.Parent = terrain
				local top = Instance.new("Attachment")
				top.Position = Vector3.new(x, y, z)
				top.Parent = terrain
				local beam = Instance.new("Beam")
				beam.Attachment0, beam.Attachment1 = bottom, top
				beam.FaceCamera = true
				beam.Color = ColorSequence.new(cfg.Color)
				beam.LightEmission = 1
				beam.LightInfluence = 0
				beam.Brightness = 0
				beam.Transparency = rayFade
				beam.Width0 = pieceLength + 2
				beam.Width1 = pieceLength + 2
				beam.Segments = 1
				beam.Parent = folder
				table.insert(rays, { beam = beam, bottom = bottom, top = top, ground = Vector3.new(x, y, z), scale = scale })

				local slab = Instance.new("Part")
				slab.Anchored, slab.CanCollide, slab.CanQuery, slab.CanTouch = true, false, false, false
				slab.CastShadow = false
				slab.Material = Enum.Material.Neon
				slab.Color = cfg.Color
				slab.Transparency = 1
				local bandHeight = cfg.BandHeight * scale
				slab.Size = Vector3.new(pieceLength + .4, bandHeight, .4)
				slab.CFrame = CFrame.new(x, y + bandHeight / 2, z) * CFrame.Angles(0, -angle, 0)
				slab.Parent = band
				table.insert(slabs, slab)
			end
		end
	end

	local highlight = Instance.new("Highlight")
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = cfg.Color
	highlight.OutlineColor = cfg.Color
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.Adornee = band
	highlight.Parent = band
	folder.Parent = Workspace

	local total = cfg.GrowSeconds + cfg.HoldSeconds + cfg.FadeSeconds
	local started = os.clock()
	local conn
	local function cleanup()
		if conn then conn:Disconnect() end
		for _, ray in ipairs(rays) do
			ray.bottom:Destroy()
			ray.top:Destroy()
		end
		folder:Destroy()
	end
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		if t >= total then cleanup() return end
		local height, lift, strength
		if t < cfg.GrowSeconds then
			local u = easeOut(t / cfg.GrowSeconds)
			height, lift, strength = cfg.RayHeight * u, 0, math.min(1, t / (cfg.GrowSeconds * .5))
		elseif t < cfg.GrowSeconds + cfg.HoldSeconds then
			height, lift, strength = cfg.RayHeight, 0, 1
		else
			local u = (t - cfg.GrowSeconds - cfg.HoldSeconds) / cfg.FadeSeconds
			height, lift, strength = cfg.RayHeight, cfg.LiftOff * easeIn(u), 1 - easeOut(u)
		end
		local brightness = cfg.RayBrightness * strength
		for _, ray in ipairs(rays) do
			ray.bottom.Position = ray.ground + Vector3.new(0, lift, 0)
			ray.top.Position = ray.ground + Vector3.new(0, lift + height * ray.scale, 0)
			ray.beam.Brightness = brightness
		end
		highlight.FillTransparency = 1 - (1 - cfg.BandPeakTransparency) * strength
		highlight.OutlineTransparency = 1 - cfg.BandOutlineStrength * strength
		local own = 1 - cfg.BandPartOpacity * strength
		for _, slab in ipairs(slabs) do slab.Transparency = own end
	end)
end

return DiscoveryPeek
