--[[
	MiasmaLobFX -- Miasma's poison lob, client side (visual only; the server decides hits).

	Three Telegraph events per cast, tied together by castId:
	  LobTarget  { castId, target (Player), duration, radius }
	             A red target reticle on the ground under the marked player, FOLLOWING them and
	             closing in over `duration`. The marked player also gets a red pulse around the
	             screen edges -- in first person you rarely look at your own feet.
	  LobLaunch  { castId, position, radius, flight, boss }
	             The reticle LOCKS where they stood and fills toward impact; a poison glob arcs
	             out of Miasma's mouth and lands there after `flight` seconds. Move or dash off
	             the locked spot to dodge.
	  LobImpact  { castId, position, radius }
	             Splash on the landing spot; the reticle goes.
	Every piece expires on its own, so a cancelled cast never leaves a reticle behind.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local LobFX = {}

local RED = Color3.fromRGB(255, 50, 45)
local RED_DARK = Color3.fromRGB(120, 10, 10)
local GLOB = Color3.fromRGB(140, 255, 90)
local GLOB_EDGE = Color3.fromRGB(150, 60, 190)
local ARC_HEIGHT = 16           -- studs above the straight line at the arc's peak
local TRACK_START_SCALE = 2.2   -- the reticle starts this much wider and closes in
local GRACE = .6                -- extra lifetime before an orphaned piece cleans itself up

local TEX = {
	spark = "rbxasset://textures/particles/sparkles_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	ring = "rbxasset://textures/particles/explosion01_shockwave_main.dds",
}

local casts = {} -- [castId] = { reticle = {...}, ... }
local player = Players.LocalPlayer

local function part(name, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.new(.2, .2, .2)
	p.Parent = parent
	return p
end

local function floorBelow(position, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list = { ignore }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(list, p.Character) end
	end
	params.FilterDescendantsInstances = list
	local hit = Workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -40, 0), params)
	return hit and hit.Position.Y or (position.Y - 3)
end

----------------------------------------------------------------------
-- Reticle: ring + crosshair ticks + centre dot, drawn flat on the floor
----------------------------------------------------------------------

local function buildReticle(parent, radius)
	local diameter = radius * 2 * TRACK_START_SCALE
	local disk = part("LobReticle", parent)
	disk.Size = Vector3.new(diameter, .05, diameter)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = math.clamp(math.floor(420 / diameter), 6, 40)
	gui.LightInfluence = 0
	gui.Brightness = 2
	gui.AlwaysOnTop = false
	gui.Parent = disk

	local root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = gui

	-- The closing ring (scaled from TRACK_START_SCALE down to the true radius).
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(.5, .5)
	ring.Position = UDim2.fromScale(.5, .5)
	ring.Size = UDim2.fromScale(1, 1)
	ring.BackgroundTransparency = 1
	ring.Parent = root
	Instance.new("UICorner", ring).CornerRadius = UDim.new(.5, 0)
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Color = RED
	ringStroke.Thickness = math.max(3, diameter * gui.PixelsPerStud * .018)
	ringStroke.Parent = ring

	-- The impact zone (true radius): faint fill that becomes solid as the glob falls.
	local zoneScale = 1 / TRACK_START_SCALE
	local zone = Instance.new("Frame")
	zone.AnchorPoint = Vector2.new(.5, .5)
	zone.Position = UDim2.fromScale(.5, .5)
	zone.Size = UDim2.fromScale(zoneScale, zoneScale)
	zone.BackgroundColor3 = RED_DARK
	zone.BackgroundTransparency = .75
	zone.BorderSizePixel = 0
	zone.Parent = root
	Instance.new("UICorner", zone).CornerRadius = UDim.new(.5, 0)
	local zoneStroke = Instance.new("UIStroke")
	zoneStroke.Color = RED
	zoneStroke.Thickness = math.max(2, diameter * gui.PixelsPerStud * .01)
	zoneStroke.Transparency = .35
	zoneStroke.Parent = zone

	-- Crosshair ticks on the zone edge + a centre dot.
	for i = 0, 3 do
		local tick = Instance.new("Frame")
		tick.AnchorPoint = Vector2.new(.5, .5)
		local angle = i * math.pi / 2
		tick.Position = UDim2.fromScale(.5 + math.cos(angle) * zoneScale * .5, .5 + math.sin(angle) * zoneScale * .5)
		tick.Size = UDim2.fromScale(i % 2 == 0 and zoneScale * .18 or zoneScale * .045, i % 2 == 0 and zoneScale * .045 or zoneScale * .18)
		tick.BackgroundColor3 = RED
		tick.BorderSizePixel = 0
		tick.Parent = root
	end
	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(.5, .5)
	dot.Position = UDim2.fromScale(.5, .5)
	dot.Size = UDim2.fromScale(zoneScale * .1, zoneScale * .1)
	dot.BackgroundColor3 = RED
	dot.BorderSizePixel = 0
	dot.Parent = root
	Instance.new("UICorner", dot).CornerRadius = UDim.new(.5, 0)

	local light = Instance.new("PointLight")
	light.Color = RED
	light.Range = radius * 2.5
	light.Brightness = 1.2
	light.Parent = disk

	return { disk = disk, ring = ring, zone = zone, zoneStroke = zoneStroke, root = root, light = light }
end

----------------------------------------------------------------------
-- "You are targeted": red pulse around the screen edges (marked player only)
----------------------------------------------------------------------

local function screenWarning(duration)
	local gui = Instance.new("ScreenGui")
	gui.Name = "MiasmaLobWarning"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 45
	local edges = {}
	local specs = {
		{ anchor = Vector2.new(.5, 0), pos = UDim2.fromScale(.5, 0), size = UDim2.fromScale(1, .16), rot = 90 },
		{ anchor = Vector2.new(.5, 1), pos = UDim2.fromScale(.5, 1), size = UDim2.fromScale(1, .16), rot = -90 },
		{ anchor = Vector2.new(0, .5), pos = UDim2.fromScale(0, .5), size = UDim2.fromScale(.12, 1), rot = 0 },
		{ anchor = Vector2.new(1, .5), pos = UDim2.fromScale(1, .5), size = UDim2.fromScale(.12, 1), rot = 180 },
	}
	for _, spec in ipairs(specs) do
		local f = Instance.new("Frame")
		f.AnchorPoint, f.Position, f.Size = spec.anchor, spec.pos, spec.size
		f.BackgroundColor3 = RED
		f.BorderSizePixel = 0
		f.BackgroundTransparency = 1
		local g = Instance.new("UIGradient")
		g.Rotation = spec.rot
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
		g.Parent = f
		f.Parent = gui
		table.insert(edges, f)
	end
	gui.Parent = player:WaitForChild("PlayerGui")
	local started = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		if t > duration or not gui.Parent then
			conn:Disconnect()
			gui:Destroy()
			return
		end
		-- Pulses faster as the lock approaches.
		local rate = 3 + 9 * (t / duration)
		local pulse = (math.sin(t * rate * math.pi) + 1) * .5
		for _, f in ipairs(edges) do f.BackgroundTransparency = .45 + .45 * (1 - pulse) end
	end)
	return gui
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------

local function cleanup(castId)
	local cast = casts[castId]
	if not cast then return end
	casts[castId] = nil
	if cast.conn then cast.conn:Disconnect() end
	if cast.folder then cast.folder:Destroy() end
	if cast.warning then cast.warning:Destroy() end
end

function LobFX.Target(payload, parent)
	local castId = payload.castId
	local target = payload.target
	if castId == nil or typeof(target) ~= "Instance" or not target:IsA("Player") then return end
	cleanup(castId)
	local radius = math.max(1, tonumber(payload.radius) or 6)
	local duration = math.max(.1, tonumber(payload.duration) or 1.4)
	local folder = Instance.new("Folder")
	folder.Name = "MiasmaLob" .. tostring(castId)
	folder.Parent = parent or Workspace
	local reticle = buildReticle(folder, radius)
	local cast = { folder = folder, reticle = reticle, radius = radius, locked = false, startedAt = os.clock(), duration = duration }
	casts[castId] = cast
	if target == player then cast.warning = screenWarning(duration) end

	local startScale = 1
	cast.conn = RunService.RenderStepped:Connect(function()
		if cast.locked then return end
		local t = os.clock() - cast.startedAt
		if t > duration + GRACE then cleanup(castId) return end
		local character = target.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			local y = floorBelow(root.Position, folder)
			reticle.disk.CFrame = CFrame.new(root.Position.X, y + .12, root.Position.Z)
		end
		-- Close the outer ring in on the true radius; slow spin for life.
		local u = math.clamp(t / duration, 0, 1)
		local scale = startScale + (1 / TRACK_START_SCALE - startScale) * (1 - (1 - u) ^ 2)
		reticle.ring.Size = UDim2.fromScale(scale, scale)
		reticle.root.Rotation = t * 60
	end)
end

-- Where the glob leaves from: the open mouth (jaw bones) when the rig has them.
local function mouthPosition(boss)
	if typeof(boss) ~= "Instance" or not boss.Parent then return nil end
	local jaw, throat
	for _, d in ipairs(boss:GetDescendants()) do
		if d:IsA("Bone") then
			if d.Name == "LowerJaw_Center_Front" then jaw = d elseif d.Name == "Throat_Center_Front" then throat = d end
		end
	end
	if jaw and throat then
		return (jaw.TransformedWorldCFrame.Position + throat.TransformedWorldCFrame.Position) * .5
	end
	local cf, size = boss:GetBoundingBox()
	return cf.Position + Vector3.new(0, size.Y * .25, 0)
end

local function buildGlob(parent)
	local glob = part("LobGlob", parent)
	glob.Shape = Enum.PartType.Ball
	glob.Size = Vector3.new(3.2, 3.2, 3.2)
	glob.Material = Enum.Material.Neon
	glob.Color = GLOB
	glob.Transparency = .1
	local light = Instance.new("PointLight")
	light.Color = GLOB
	light.Range = 12
	light.Brightness = 2
	light.Parent = glob
	local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0, 1, 0); a0.Parent = glob
	local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, -1, 0); a1.Parent = glob
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Color = ColorSequence.new(GLOB, GLOB_EDGE)
	trail.LightEmission = .8
	trail.Lifetime = .3
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .1), NumberSequenceKeypoint.new(1, 1) })
	trail.Parent = glob
	local drips = Instance.new("ParticleEmitter")
	drips.Texture = TEX.spark
	drips.Color = ColorSequence.new(GLOB, GLOB_EDGE)
	drips.LightEmission = .8
	drips.Rate = 45
	drips.Lifetime = NumberRange.new(.4, .8)
	drips.Speed = NumberRange.new(0, 2)
	drips.Acceleration = Vector3.new(0, -40, 0)
	drips.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
	drips.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .2), NumberSequenceKeypoint.new(1, 1) })
	drips.Parent = glob
	return glob
end

function LobFX.Launch(payload, parent)
	local castId = payload.castId
	if castId == nil or typeof(payload.position) ~= "Vector3" then return end
	local radius = math.max(1, tonumber(payload.radius) or 6)
	local flight = math.max(.1, tonumber(payload.flight) or .75)
	local cast = casts[castId]
	if not cast then
		-- Joined mid-cast or missed the mark: still show the lock + glob.
		local folder = Instance.new("Folder")
		folder.Name = "MiasmaLob" .. tostring(castId)
		folder.Parent = parent or Workspace
		cast = { folder = folder, reticle = buildReticle(folder, radius), radius = radius }
		casts[castId] = cast
	end
	cast.locked = true
	if cast.warning then cast.warning:Destroy(); cast.warning = nil end

	-- Lock the reticle on the spot, ring snapped to the zone, fill darkening toward impact.
	local target = payload.position
	local y = floorBelow(target, cast.folder)
	local landing = Vector3.new(target.X, y, target.Z)
	local reticle = cast.reticle
	reticle.disk.CFrame = CFrame.new(landing + Vector3.new(0, .12, 0))
	reticle.ring.Size = UDim2.fromScale(1 / TRACK_START_SCALE, 1 / TRACK_START_SCALE)
	TweenService:Create(reticle.zone, TweenInfo.new(flight, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		BackgroundTransparency = .25, BackgroundColor3 = RED,
	}):Play()
	reticle.zoneStroke.Transparency = 0

	local from = mouthPosition(payload.boss) or (landing + Vector3.new(0, 20, 0))
	local glob = buildGlob(cast.folder)
	glob.Position = from
	local startedAt = os.clock()
	if cast.conn then cast.conn:Disconnect() end
	cast.conn = RunService.RenderStepped:Connect(function()
		local u = (os.clock() - startedAt) / flight
		if u >= 1 then
			glob.Position = landing
			if cast.conn then cast.conn:Disconnect(); cast.conn = nil end
			glob.Transparency = 1
			for _, d in ipairs(glob:GetDescendants()) do
				if d:IsA("ParticleEmitter") then d.Enabled = false elseif d:IsA("PointLight") then d.Enabled = false end
			end
			-- Safety: if the impact event never comes, clean up anyway.
			task.delay(GRACE + 1, function() cleanup(castId) end)
			return
		end
		local p = from:Lerp(landing, u) + Vector3.new(0, ARC_HEIGHT * 4 * u * (1 - u), 0)
		glob.CFrame = CFrame.new(p) * CFrame.Angles(u * 9, u * 5, 0)
		reticle.root.Rotation = (os.clock() - startedAt) * 240 -- spins up as it drops
	end)
end

function LobFX.Impact(payload, parent)
	local castId = payload.castId
	local radius = math.max(1, tonumber(payload.radius) or 6)
	local cast = castId ~= nil and casts[castId] or nil
	if typeof(payload.position) ~= "Vector3" then cleanup(castId) return end
	local folder = Instance.new("Folder")
	folder.Name = "MiasmaLobSplash"
	folder.Parent = parent or Workspace
	local y = floorBelow(payload.position, folder)
	local centre = part("Splash", folder)
	centre.CFrame = CFrame.new(payload.position.X, y + .3, payload.position.Z)

	local goo = Instance.new("ParticleEmitter")
	goo.Texture = TEX.spark
	goo.Color = ColorSequence.new(GLOB, GLOB_EDGE)
	goo.LightEmission = .6
	goo.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, .2) })
	goo.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	goo.Lifetime = NumberRange.new(.5, .9)
	goo.Speed = NumberRange.new(radius * 2, radius * 4)
	goo.SpreadAngle = Vector2.new(70, 70)
	goo.Acceleration = Vector3.new(0, -70, 0)
	goo.EmissionDirection = Enum.NormalId.Top
	goo.Rate = 0
	goo.Parent = centre
	goo:Emit(40)

	local mist = Instance.new("ParticleEmitter")
	mist.Texture = TEX.smoke
	mist.Color = ColorSequence.new(Color3.fromRGB(120, 190, 90), Color3.fromRGB(100, 60, 130))
	mist.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, radius * .6), NumberSequenceKeypoint.new(1, radius * 1.6) })
	mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .45), NumberSequenceKeypoint.new(1, 1) })
	mist.Lifetime = NumberRange.new(.8, 1.3)
	mist.Speed = NumberRange.new(2, 6)
	mist.SpreadAngle = Vector2.new(80, 80)
	mist.EmissionDirection = Enum.NormalId.Top
	mist.Rate = 0
	mist.Parent = centre
	mist:Emit(10)

	local ring = Instance.new("ParticleEmitter")
	ring.Texture = TEX.ring
	ring.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
	ring.EmissionDirection = Enum.NormalId.Top
	ring.Color = ColorSequence.new(GLOB)
	ring.LightEmission = .5
	ring.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, radius * 2.4) })
	ring.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .2), NumberSequenceKeypoint.new(1, 1) })
	ring.Lifetime = NumberRange.new(.35)
	ring.Speed = NumberRange.new(.01)
	ring.Rate = 0
	ring.Parent = centre
	ring:Emit(1)

	local flash = Instance.new("PointLight")
	flash.Color = GLOB
	flash.Range = radius * 3
	flash.Brightness = 4
	flash.Parent = centre
	TweenService:Create(flash, TweenInfo.new(.5), { Brightness = 0 }):Play()

	cleanup(castId)
	task.delay(2, function() folder:Destroy() end)
	return cast ~= nil
end

function LobFX.StopAll()
	for castId in pairs(casts) do cleanup(castId) end
end

return LobFX
