--[[
	WaystoneVortexClient

	Draws the spinning golden vortex inside every waystone's ring. A waystone carries an
	invisible flat part tagged `WaystoneVortex` sized to the ring's hole; this builds two
	SurfaceGuis on it (front and back, unlit so it glows) and turns them: the main swirl
	slowly, a fainter copy over it the other way, so it reads as moving energy rather than
	a rotating sticker. Only vortices within SPIN_RANGE are animated.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local WorldVfx = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images"):WaitForChild("WorldVfx"))

local TAG = "WaystoneVortex"
local SPIN_SPEED = 25 -- degrees per second, main swirl
local OVERLAY_SPEED = -40 -- the faint copy turns the other way
local SPIN_RANGE = 200
local PULSE_PERIOD = 3

local camera = workspace.CurrentCamera
local vortices = {} -- part -> { labels = { {label, speed} }, guis }

local function buildFace(part, face)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "VortexGui"
	gui.Face = face
	gui.LightInfluence = 0
	gui.Brightness = 1.4
	gui.CanvasSize = Vector2.new(512, 512)
	gui.ClipsDescendants = false
	gui.Adornee = part
	gui.Parent = part

	local main = Instance.new("ImageLabel")
	main.AnchorPoint = Vector2.new(0.5, 0.5)
	main.Position = UDim2.fromScale(0.5, 0.5)
	main.Size = UDim2.fromScale(1, 1)
	main.BackgroundTransparency = 1
	main.Image = WorldVfx.WAYSTONE_VORTEX
	main.Parent = gui

	local overlay = main:Clone()
	overlay.Size = UDim2.fromScale(0.85, 0.85)
	overlay.ImageTransparency = 0.65
	overlay.ZIndex = 2
	overlay.Parent = gui

	return gui, main, overlay
end

local function add(part)
	if not part:IsA("BasePart") or vortices[part] then return end
	local entry = { labels = {}, guis = {} }
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local gui, main, overlay = buildFace(part, face)
		table.insert(entry.guis, gui)
		table.insert(entry.labels, { main, SPIN_SPEED })
		table.insert(entry.labels, { overlay, OVERLAY_SPEED })
	end
	vortices[part] = entry
end

local function remove(part)
	local entry = vortices[part]
	if not entry then return end
	for _, gui in ipairs(entry.guis) do gui:Destroy() end
	vortices[part] = nil
end

CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(remove)
for _, part in ipairs(CollectionService:GetTagged(TAG)) do add(part) end

RunService.RenderStepped:Connect(function()
	if not next(vortices) then return end
	local t = os.clock()
	local camPos = camera.CFrame.Position
	local pulse = 1.3 + 0.25 * math.sin(t * math.pi * 2 / PULSE_PERIOD)
	for part, entry in pairs(vortices) do
		if (part.Position - camPos).Magnitude <= SPIN_RANGE then
			for _, pair in ipairs(entry.labels) do
				pair[1].Rotation = (t * pair[2]) % 360
			end
			for _, gui in ipairs(entry.guis) do
				gui.Brightness = pulse
			end
		end
	end
end)
