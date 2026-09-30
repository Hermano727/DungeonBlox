--[[
	ZoneDevVisuals
	Yellow zone overlays (polygons or legacy circles) visible only while DevPlacer
	is open. Mob spawner markers stay red/blue.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local ZoneConfig = require(ReplicatedStorage:WaitForChild("ZoneConfig"))
local GameEvents = ReplicatedStorage:WaitForChild("GameEvents")
local ZoneBroadcast = GameEvents:WaitForChild("ZoneStateBroadcast")

local player = Players.LocalPlayer
local YELLOW = ZoneConfig.DEV_ZONE_COLOR
local EDGE_H = ZoneConfig.DEV_ZONE_EDGE_THICKNESS
local CORNER = ZoneConfig.DEV_ZONE_CORNER_SIZE

local container = Instance.new("Folder")
container.Name   = "ZoneDevVisuals_" .. player.UserId
container.Parent = nil

local modelsByZoneId = {}
local currentZones = {}

local function applyPartDefaults(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = YELLOW
end

local function makeEdge(x1, z1, x2, z2, groundY, parent)
	local p1 = Vector3.new(x1, groundY + EDGE_H * 0.5, z1)
	local p2 = Vector3.new(x2, groundY + EDGE_H * 0.5, z2)
	local delta = p2 - p1
	local len = delta.Magnitude
	if len < 0.05 then
		return
	end
	local mid = p1 + delta * 0.5
	local part = Instance.new("Part")
	part.Name = "Edge"
	part.Size = Vector3.new(len, EDGE_H, EDGE_H)
	part.CFrame = CFrame.new(mid, p2) * CFrame.Angles(0, math.rad(90), 0)
	part.Transparency = 0.35
	applyPartDefaults(part)
	part.Parent = parent
end

local function addLabel(parent, adornee, zone, extra)
	local bb = Instance.new("BillboardGui")
	bb.Name = "ZoneLabel"
	bb.Adornee = adornee
	bb.AlwaysOnTop = true
	bb.Size = UDim2.fromOffset(260, 52)
	bb.StudsOffset = Vector3.new(0, 3, 0)
	bb.Parent = parent

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 13
	lbl.TextStrokeTransparency = 0.35
	lbl.TextColor3 = ZoneConfig.ALIGNMENT_COLORS[zone.alignment] or YELLOW
	lbl.Text = string.format("%s\n%s  %s", zone.name, ZoneConfig.DisplayAlignment(zone.alignment), extra or "")
	lbl.Parent = bb
end

local function makePolygonModel(zone)
	local model = Instance.new("Model")
	model.Name = "ZoneViz_" .. zone.id
	local groundY = zone.center.Y
	local pts = zone.points
	local n = #pts

	for i, p in ipairs(pts) do
		local corner = Instance.new("Part")
		corner.Name = "Corner"
		corner.Shape = Enum.PartType.Ball
		corner.Size = Vector3.new(CORNER, CORNER, CORNER)
		corner.Position = Vector3.new(p.x, groundY + CORNER * 0.25, p.z)
		corner.Transparency = 0.25
		applyPartDefaults(corner)
		corner.Parent = model

		local nextPt = pts[(i % n) + 1]
		makeEdge(p.x, p.z, nextPt.x, nextPt.z, groundY, model)
	end

	local anchor = Instance.new("Part")
	anchor.Name = "LabelAnchor"
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Position = zone.center + Vector3.new(0, 1, 0)
	applyPartDefaults(anchor)
	anchor.Parent = model
	addLabel(model, anchor, zone, string.format("%d pts", n))
	model.Parent = container
	return model
end

local function makeCircleModel(zone)
	local part = Instance.new("Part")
	part.Name = "ZoneViz_" .. zone.id
	part.Shape = Enum.PartType.Cylinder
	part.Transparency = ZoneConfig.DEV_CYLINDER_TRANSPARENCY
	applyPartDefaults(part)
	local d = (zone.radius or ZoneConfig.DEFAULT_RADIUS) * 2
	part.Size = Vector3.new(ZoneConfig.DEV_CYLINDER_HEIGHT, d, d)
	part.CFrame = CFrame.new(zone.center) * CFrame.Angles(0, 0, math.rad(90))
	addLabel(part, part, zone, string.format("r=%d", zone.radius or 0))
	part.Parent = container
	return part
end

local function makeZoneVisual(zone)
	if type(zone.points) == "table" and #zone.points >= ZoneConfig.MIN_POLYGON_POINTS then
		return makePolygonModel(zone)
	end
	return makeCircleModel(zone)
end

local function refresh()
	local seen = {}
	for _, z in ipairs(currentZones) do
		seen[z.id] = true
		local existing = modelsByZoneId[z.id]
		if existing and existing.Parent then
			existing:Destroy()
		end
		modelsByZoneId[z.id] = makeZoneVisual(z)
	end
	for id, inst in pairs(modelsByZoneId) do
		if not seen[id] then
			if inst then inst:Destroy() end
			modelsByZoneId[id] = nil
		end
	end
end

local function isMobDevMarker(part)
	return part:IsA("BasePart") and part:GetAttribute("SpawnerType") == "Mob"
end

local function setMobMarkerVisible(part, visible)
	part.LocalTransparencyModifier = visible and 0 or 1
	local bb = part:FindFirstChild("SpawnerLabel")
	if bb and bb:IsA("BillboardGui") then
		bb.Enabled = visible
	end
end

local function applyMobMarkerVisibility(visible)
	for _, part in ipairs(CollectionService:GetTagged("SpawnerMarker")) do
		if isMobDevMarker(part) then
			setMobMarkerVisible(part, visible)
		end
	end
end

local function applyVisibility()
	local visible = player:GetAttribute("DevPlacerOpen") == true
	container.Parent = visible and workspace or nil
	applyMobMarkerVisibility(visible)
end

local ZoneStateRequest = GameEvents:FindFirstChild("ZoneStateRequest")

local function normalizeZoneCenter(zone)
	local c = zone.center
	if typeof(c) == "Vector3" then return c end
	if type(c) == "table" then
		return Vector3.new(tonumber(c.X or c.x) or 0, tonumber(c.Y or c.y) or 0, tonumber(c.Z or c.z) or 0)
	end
	return Vector3.zero
end

local function applyZonePayload(payload)
	if type(payload) ~= "table" or type(payload.zones) ~= "table" then return end
	for _, z in ipairs(payload.zones) do
		if type(z) == "table" then
			z.center = normalizeZoneCenter(z)
		end
	end
	currentZones = payload.zones
	refresh()
	applyVisibility()
end

local function requestZoneSync()
	local rf = ZoneStateRequest
	if not rf or not rf:IsA("RemoteFunction") then
		rf = GameEvents:WaitForChild("ZoneStateRequest", 15)
		ZoneStateRequest = rf
	end
	if not rf then return end
	task.spawn(function()
		local ok, payload = pcall(function()
			return rf:InvokeServer()
		end)
		if ok then applyZonePayload(payload) end
	end)
end

local function onDevPlacerOpenChanged()
	applyVisibility()
	if player:GetAttribute("DevPlacerOpen") == true then
		requestZoneSync()
	end
end

applyVisibility()
player:GetAttributeChangedSignal("DevPlacerOpen"):Connect(onDevPlacerOpenChanged)

CollectionService:GetInstanceAddedSignal("SpawnerMarker"):Connect(function(part)
	if isMobDevMarker(part) then
		setMobMarkerVisible(part, player:GetAttribute("DevPlacerOpen") == true)
	end
end)

ZoneBroadcast.OnClientEvent:Connect(applyZonePayload)
task.defer(requestZoneSync)