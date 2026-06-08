--[[
	ZoneDevVisuals
	Renders translucent colored cylinders for each placed zone, and toggles
	visibility of server mob spawner markers (red discs tagged SpawnerMarker),
	visible ONLY while the F8 DevPlacer panel is open (DevClient sets the attribute
	DevPlacerOpen on the LocalPlayer when it toggles).

	This is a debug aid for placing/iterating zones and mob camps. Regular players
	never see these; non-dev users won't have DevClient running, so the attribute
	stays nil and the visuals stay hidden.
]]

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local RunService         = game:GetService("RunService")
local CollectionService  = game:GetService("CollectionService")

local ZoneConfig = require(ReplicatedStorage:WaitForChild("ZoneConfig"))
local GameEvents = ReplicatedStorage:WaitForChild("GameEvents")
local ZoneBroadcast = GameEvents:WaitForChild("ZoneStateBroadcast")

local player = Players.LocalPlayer

-- Only run for devs. DevClient itself sets DevPlacerOpen; if no DevClient,
-- the attribute never appears, and the rest of this script is a no-op idle.
local function isDev()
	-- The simplest gate: studio always shows; otherwise we wait for the
	-- DevPlacerOpen attribute to ever toggle true (DevClient sets it).
	return RunService:IsStudio() or player:GetAttribute("DevPlacerOpen") ~= nil
end

-- A dedicated folder under workspace so we can mass-toggle visibility cheaply.
local container = Instance.new("Folder")
container.Name   = "ZoneDevVisuals_" .. player.UserId
container.Parent = workspace

local partsByZoneId = {}
local currentZones = {}  -- latest broadcast snapshot

local function makeCylinder(zone)
	local part = Instance.new("Part")
	part.Name        = "ZoneViz_" .. zone.id
	part.Shape       = Enum.PartType.Cylinder
	part.Material    = Enum.Material.ForceField
	part.Anchored    = true
	part.CanCollide  = false
	part.CanQuery    = false
	part.CanTouch    = false
	part.CastShadow  = false
	part.Transparency = ZoneConfig.DEV_CYLINDER_TRANSPARENCY
	part.Color       = ZoneConfig.ALIGNMENT_COLORS[zone.alignment] or Color3.new(1,1,1)
	-- Cylinder shape: axis is along X. Rotate 90° around Z so the axis becomes Y
	-- (the disc lies flat on the ground), like spawner markers.
	local d = zone.radius * 2
	part.Size  = Vector3.new(ZoneConfig.DEV_CYLINDER_HEIGHT, d, d)
	part.CFrame = CFrame.new(zone.center) * CFrame.Angles(0, 0, math.rad(90))

	-- Label with name + alignment + radius for at-a-glance debugging.
	local bb = Instance.new("BillboardGui")
	bb.Name         = "ZoneLabel"
	bb.Adornee      = part
	bb.AlwaysOnTop  = true
	bb.Size         = UDim2.fromOffset(240, 50)
	bb.StudsOffset  = Vector3.new(0, 2.5, 0)
	bb.Parent       = part

	local lbl = Instance.new("TextLabel")
	lbl.Size                   = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font                   = Enum.Font.GothamBold
	lbl.TextSize               = 13
	lbl.TextColor3             = ZoneConfig.ALIGNMENT_COLORS[zone.alignment] or Color3.new(1,1,1)
	lbl.TextStrokeTransparency = 0.4
	lbl.Text = string.format("%s\n%s  r=%d", zone.name, zone.alignment, zone.radius)
	lbl.Parent = bb

	part.Parent = container
	return part
end

local function refresh()
	local seen = {}
	for _, z in ipairs(currentZones) do
		seen[z.id] = true
		local existing = partsByZoneId[z.id]
		if not existing or not existing.Parent then
			if existing then existing:Destroy() end
			partsByZoneId[z.id] = makeCylinder(z)
		else
			-- Update in place (alignment / radius / center may have changed).
			local d = z.radius * 2
			existing.Size  = Vector3.new(ZoneConfig.DEV_CYLINDER_HEIGHT, d, d)
			existing.CFrame = CFrame.new(z.center) * CFrame.Angles(0, 0, math.rad(90))
			existing.Color = ZoneConfig.ALIGNMENT_COLORS[z.alignment] or existing.Color
			local bb  = existing:FindFirstChild("ZoneLabel")
			local lbl = bb and bb:FindFirstChildOfClass("TextLabel")
			if lbl then
				lbl.Text = string.format("%s\n%s  r=%d", z.name, z.alignment, z.radius)
				lbl.TextColor3 = ZoneConfig.ALIGNMENT_COLORS[z.alignment] or lbl.TextColor3
			end
		end
	end
	-- Tear down parts whose zones are gone.
	for id, part in pairs(partsByZoneId) do
		if not seen[id] then
			if part then part:Destroy() end
			partsByZoneId[id] = nil
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

-- Initial hidden state.
applyVisibility()

player:GetAttributeChangedSignal("DevPlacerOpen"):Connect(applyVisibility)

CollectionService:GetInstanceAddedSignal("SpawnerMarker"):Connect(function(part)
	if isMobDevMarker(part) then
		setMobMarkerVisible(part, player:GetAttribute("DevPlacerOpen") == true)
	end
end)

ZoneBroadcast.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" or type(payload.zones) ~= "table" then return end
	currentZones = payload.zones
	if isDev() then
		refresh()
	end
end)
