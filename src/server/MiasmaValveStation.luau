--[[
	MiasmaValveStation -- the physical station's STATE and PRESENTATION (server side).

	Owns one built station model (MiasmaValveStationBuilder) and drives what players see:
	the state lamp and plaque, the corruption growth, the rune tablet, the pressure-plate
	glow, the wheel turning, the sluice gate and the channel water. It knows nothing about
	mazes, clogs or encounter rules; MiasmaValveGate tells it what to show.

	States:
		Dormant    gate not used this cycle: dark lamp, dry sludge channel, tablet blank
		Blocked    slime growth chokes the valve (clogs alive): violet lamp, growth shown
		Available  clogs cleared, valve can be reserved: amber lamp, prompt enabled
		Occupied   someone is operating: red lamp, prompt disabled
		Completed  primed: blue lamp, sluice raised, clean water in the channel

	Rune tablet: the target runes are only CREATED while the tablet is revealed (someone is
	on the pressure plate) and destroyed again when it goes dark, so the pattern is not
	sitting in the world for anyone to read while nobody is standing on the plate.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("MiasmaEncounterConfig"))
local RuneArt = require(ReplicatedStorage:WaitForChild("MiasmaRuneArt"))
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))

local VALVE = Config.Gates.Valve

local Station = {}
Station.__index = Station

Station.States = table.freeze({
	Dormant = "Dormant",
	Blocked = "Blocked",
	Available = "Available",
	Occupied = "Occupied",
	Completed = "Completed",
})

local STYLE = {
	Dormant = { lamp = Color3.fromRGB(46, 46, 44), light = false, title = "SEALED", sub = "Not called this cycle", text = Color3.fromRGB(128, 122, 110) },
	Blocked = { lamp = Color3.fromRGB(176, 78, 222), light = true, title = "CHOKED", sub = "Clear the growth", text = Color3.fromRGB(206, 160, 230) },
	Available = { lamp = Color3.fromRGB(245, 176, 82), light = true, title = "READY", sub = "Read the plate, then turn", text = Color3.fromRGB(240, 210, 150) },
	Occupied = { lamp = Color3.fromRGB(232, 92, 56), light = true, title = "IN USE", sub = "Hold the line", text = Color3.fromRGB(240, 170, 140) },
	Completed = { lamp = Color3.fromRGB(128, 214, 255), light = true, title = "FLOWING", sub = "Channel primed", text = Color3.fromRGB(170, 228, 255) },
}

local RUNE_LIT = Color3.fromRGB(214, 244, 214)
local RUNE_GLOW = Color3.fromRGB(96, 230, 150)
local PLATE_IDLE = Color3.fromRGB(60, 70, 58)
local PLATE_LIT = Color3.fromRGB(110, 235, 160)

local function find(model, path)
	local node = model
	for _, name in ipairs(string.split(path, "/")) do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local function tween(instance, seconds, goal, style)
	if not instance then return end
	local t = TweenService:Create(instance, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

function Station.new(model, options)
	options = options or {}
	local self = setmetatable({}, Station)
	self.Model = model
	self.Pivot = model.PrimaryPart or model:FindFirstChild("Pivot")
	self.DisplayName = options.displayName or model.Name
	self.WheelRoot = find(model, "Valve/WheelRoot")
	self.WheelBase = self.WheelRoot and self.WheelRoot.CFrame
	self.GateRoot = find(model, "Sluice/GateRoot")
	self.GateBase = self.GateRoot and self.GateRoot.CFrame
	self.Water = find(model, "Channel/Water")
	self.Sludge = find(model, "Channel/Sludge")
	self.Lamp = find(model, "Indicator/Lamp")
	self.PlateGlow = find(model, "RuneDisplay/PlateGlow")
	self.Tablet = find(model, "RuneDisplay/Tablet")
	self.Growth = model:FindFirstChild("Growth")
	self.WaterTransparency = .3
	self.State = nil
	self.Pattern = nil
	self.Revealed = false
	self.Progress = 0

	local interact = find(model, "Valve/Interact")
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ValvePrompt"
	prompt.ActionText = "Turn Valve"
	prompt.ObjectText = self.DisplayName .. " Sluice Valve"
	prompt.HoldDuration = VALVE.PromptHoldDuration
	prompt.MaxActivationDistance = VALVE.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = interact or self.Pivot
	self.Prompt = prompt

	self:_buildPlaque()
	self:_buildTablet()
	self:_buildBeacon()
	self:SetState(Station.States.Dormant)
	return self
end

function Station:GetAnchor(name)
	local attachment = self.Pivot and self.Pivot:FindFirstChild(name)
	return attachment and attachment.WorldPosition or (self.Pivot and self.Pivot.Position)
end

function Station:GetFrame()
	return self.Pivot and self.Pivot.CFrame or CFrame.identity
end

-- Flat check: is `position` standing on the pressure plate?
function Station:IsOnPlate(position)
	local centre = self:GetAnchor("PlateCentre")
	if not centre or not self.Pivot then return false end
	local half = self.Pivot:GetAttribute("PlateHalfSize") or 2
	local offset = self.Pivot.CFrame:VectorToObjectSpace(position - centre)
	return math.abs(offset.X) <= half and math.abs(offset.Z) <= half
		and offset.Y > -1 and offset.Y < VALVE.PlateHeightTolerance
end

function Station:_buildPlaque()
	local plaque = find(self.Model, "Indicator/Plaque")
	if not plaque then return end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "PlaqueGui"
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 80
	gui.LightInfluence = .35
	gui.Parent = plaque
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Size = UDim2.fromScale(1, .6)
	title.FontFace = UIFonts.DisplayBold
	title.TextScaled = true
	title.Parent = gui
	local titlePad = Instance.new("UIPadding")
	titlePad.PaddingTop = UDim.new(.12, 0)
	titlePad.Parent = title
	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromScale(0, .6)
	sub.Size = UDim2.fromScale(1, .32)
	sub.FontFace = UIFonts.BodyBold
	sub.TextScaled = true
	sub.Parent = gui
	self.PlaqueTitle = title
	self.PlaqueSub = sub
end

function Station:_buildTablet()
	if not self.Tablet then return end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "RuneTabletGui"
	gui.Face = Enum.NormalId.Right
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 1
	gui.Parent = self.Tablet
	local grid = Instance.new("Frame")
	grid.Name = "Slots"
	grid.BackgroundTransparency = 1
	grid.AnchorPoint = Vector2.new(.5, .5)
	grid.Position = UDim2.fromScale(.5, .52)
	grid.Size = UDim2.fromScale(.9, .8)
	grid.Parent = gui
	local layout = Instance.new("UIGridLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	-- Carved hint while dark, so nobody wonders where the pattern is.
	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.BackgroundTransparency = 1
	hint.Position = UDim2.fromScale(.05, .02)
	hint.Size = UDim2.fromScale(.9, .12)
	hint.FontFace = UIFonts.DisplayBold
	hint.Text = "STAND ON THE PLATE TO READ"
	hint.TextColor3 = Color3.fromRGB(150, 140, 118)
	hint.TextScaled = true
	hint.Visible = false
	hint.Parent = gui
	self.TabletHint = hint
	self.TabletGui = gui
	self.TabletSlots = grid
	self.TabletLayout = layout
	local light = Instance.new("SurfaceLight")
	light.Name = "RuneLight"
	light.Face = Enum.NormalId.Right
	light.Color = RUNE_GLOW
	light.Range = 7
	light.Brightness = 1.2
	light.Angle = 110
	light.Enabled = false
	light.Parent = self.Tablet
	self.TabletLight = light
end

-- Carved slots for the current pattern; runes drawn into them only while revealed.
function Station:_renderTablet()
	if not self.TabletSlots then return end
	for _, child in ipairs(self.TabletSlots:GetChildren()) do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	local pattern = self.Pattern
	local count = pattern and #pattern or 0
	if self.TabletHint then self.TabletHint.Visible = count > 0 and not self.Revealed end
	if count == 0 then return end
	local columns = (count == 4) and 2 or math.min(count, 3)
	local rows = math.ceil(count / columns)
	self.TabletLayout.CellSize = UDim2.fromScale(.9 / columns, .9 / rows)
	self.TabletLayout.CellPadding = UDim2.fromScale(.1 / columns, .1 / rows)
	for index = 1, count do
		local slot = Instance.new("Frame")
		slot.Name = "Slot" .. index
		slot.LayoutOrder = index
		slot.BackgroundColor3 = Color3.fromRGB(26, 28, 25)
		slot.BackgroundTransparency = .15
		slot.BorderSizePixel = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(.12, 0)
		corner.Parent = slot
		local square = Instance.new("UIAspectRatioConstraint")
		square.AspectRatio = 1
		square.Parent = slot
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(70, 66, 58)
		stroke.Thickness = 3
		stroke.Parent = slot
		local inner = Instance.new("Frame")
		inner.Name = "Inner"
		inner.BackgroundTransparency = 1
		inner.AnchorPoint = Vector2.new(.5, .5)
		inner.Position = UDim2.fromScale(.5, .5)
		inner.Size = UDim2.fromScale(.78, .78)
		inner.Parent = slot
		if self.Revealed then
			RuneArt.Render(inner, pattern[index], { Color = RUNE_LIT, GlowColor = RUNE_GLOW, GlowTransparency = .72, Thickness = .09 })
			stroke.Color = Color3.fromRGB(90, 150, 110)
		end
		slot.Parent = self.TabletSlots
	end
end

function Station:SetPattern(pattern)
	self.Pattern = pattern and table.clone(pattern) or nil
	self:_renderTablet()
end

function Station:SetRevealed(revealed)
	revealed = revealed == true and self.Pattern ~= nil
	if self.Revealed == revealed then return end
	self.Revealed = revealed
	if self.TabletGui then self.TabletGui.LightInfluence = revealed and 0 or 1 end
	if self.TabletLight then self.TabletLight.Enabled = revealed end
	if self.PlateGlow then
		tween(self.PlateGlow, .25, { Color = revealed and PLATE_LIT or PLATE_IDLE, Transparency = revealed and .1 or .35 })
	end
	self:_renderTablet()
end

-- Wheel angle follows collected runes: a quarter turn each, a full turn on completion.
-- Spins about the station's facing axis through WheelCentre, so it does not depend on how
-- the WheelRoot part itself is oriented (a primitive cylinder or an imported mesh).
function Station:SetProgress(count)
	self.Progress = count
	if not self.WheelRoot or not self.WheelBase then return end
	local angle = -math.rad(90) * count
	local anchor = self.Pivot and self.Pivot:FindFirstChild("WheelCentre")
	local centre = anchor and anchor.WorldPosition or self.WheelBase.Position
	local spin = CFrame.new(centre) * CFrame.fromAxisAngle(self:GetFrame().LookVector, angle) * CFrame.new(-centre)
	tween(self.WheelRoot, count == 0 and .45 or .3, { CFrame = spin * self.WheelBase }, Enum.EasingStyle.Back)
end

-- GateRoot's SlideDistance attribute: how far the gate rises when it opens (art prefabs with
-- a taller gate set their own).
function Station:_setGate(open)
	if not self.GateRoot or not self.GateBase then return end
	local up = self:GetFrame().UpVector
	local slide = tonumber(self.GateRoot:GetAttribute("SlideDistance")) or 4.4
	tween(self.GateRoot, open and 1.4 or .6, { CFrame = open and (self.GateBase + up * slide) or self.GateBase }, Enum.EasingStyle.Sine)
end

-- Tall light pillar just outside the recess mouth, lit while the gate is live this cycle
-- (choked, ready or in use) so players can find it from anywhere in the arena. Recolours
-- with the lamp; dark when sealed or already flowing.
local BEACON_STATES = { Blocked = true, Available = true, Occupied = true }
function Station:_buildBeacon()
	local base = Instance.new("Attachment")
	base.Name = "BeaconBase"
	base.Position = Vector3.new(-1, .2, 10)
	base.Parent = self.Pivot
	local top = Instance.new("Attachment")
	top.Name = "BeaconTop"
	top.Position = Vector3.new(-1, 42, 10)
	top.Parent = self.Pivot
	local beam = Instance.new("Beam")
	beam.Name = "ValveBeacon"
	beam.Attachment0 = base
	beam.Attachment1 = top
	beam.Texture = "rbxasset://textures/particles/forcefield_glow_main.dds"
	beam.TextureMode = Enum.TextureMode.Stretch
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.FaceCamera = true
	beam.Width0 = 5
	beam.Width1 = 2.5
	beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .25), NumberSequenceKeypoint.new(1, 1) })
	beam.Enabled = false
	beam.Parent = self.Pivot
	local motes = Instance.new("ParticleEmitter")
	motes.Name = "BeaconMotes"
	motes.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	motes.LightEmission = 1
	motes.LightInfluence = 0
	motes.Speed = NumberRange.new(6, 10)
	motes.Lifetime = NumberRange.new(2, 3)
	motes.Rate = 10
	motes.SpreadAngle = Vector2.new(6, 6)
	motes.EmissionDirection = Enum.NormalId.Top
	motes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, .45), NumberSequenceKeypoint.new(1, 0) })
	motes.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .2), NumberSequenceKeypoint.new(1, 1) })
	motes.Enabled = false
	motes.Parent = base
	self.Beacon = beam
	self.BeaconMotes = motes
end

function Station:SetState(state)
	if self.State == state then return end
	local previous = self.State
	self.State = state
	local style = STYLE[state] or STYLE.Dormant

	if self.Beacon then
		local live = BEACON_STATES[state] == true
		self.Beacon.Enabled = live
		self.Beacon.Color = ColorSequence.new(style.lamp)
		self.BeaconMotes.Enabled = live
		self.BeaconMotes.Color = ColorSequence.new(style.lamp)
	end

	if self.Lamp then
		self.Lamp.Color = style.lamp
		local light = self.Lamp:FindFirstChild("StateLight")
		if light then
			light.Color = style.lamp
			light.Enabled = style.light
		end
	end
	if self.PlaqueTitle then
		self.PlaqueTitle.Text = style.title
		self.PlaqueTitle.TextColor3 = style.text
		self.PlaqueSub.Text = style.sub
		self.PlaqueSub.TextColor3 = style.text
	end
	if self.Growth then
		for _, part in ipairs(self.Growth:GetChildren()) do
			if part:IsA("BasePart") then part.Transparency = state == Station.States.Blocked and 0 or 1 end
		end
	end
	self.Prompt.Enabled = state == Station.States.Available

	if state == Station.States.Completed then
		self:SetProgress(4)
		self:_setGate(true)
		if self.Water then tween(self.Water, 1.6, { Transparency = self.WaterTransparency }) end
		if self.Sludge then tween(self.Sludge, 1.2, { Transparency = 1 }) end
	elseif previous == Station.States.Completed or previous == nil then
		self:_setGate(false)
		if self.Water then tween(self.Water, .6, { Transparency = 1 }) end
		if self.Sludge then tween(self.Sludge, .6, { Transparency = .05 }) end
	end
	if state ~= Station.States.Occupied and state ~= Station.States.Completed and self.Progress ~= 0 then
		self:SetProgress(0)
	end
end

function Station:Destroy()
	if self.Prompt then self.Prompt:Destroy() end
	if self.Model then self.Model:Destroy() end
	self.Model = nil
end

return Station
