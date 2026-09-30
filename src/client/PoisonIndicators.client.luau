--[[
	PoisonIndicators -- makes Miasma's poison readable at a glance (client only).

	Reads the player attribute the server keeps current (MiasmaPoisonService sets
	Protocol.Attributes.PoisonStacks on every change), so there is no remote of its own.

	  Stack counter  above the health bar (HealthBarGui.HPBarBackground): the poison icon and
	                 "x/5". At the max it flashes red: the next ticks hurt the most.
	  Altar markers  while you're poisoned, each cleanse altar (tagged "MiasmaCleanseAltar" by
	                 MiasmaCleanseAltar) shows ONE small thing above it, through walls:
	                   on cooldown  the time until it's ready (the anchor's CooldownEndsAt)
	                   usable       the poison icon, crossed out (its prompt is enabled)
	                   otherwise    nothing
	                 Kept quiet on purpose: see-through, fades out as you walk up to it, and while
	                 valve arrows are up (MiasmaValveArrows.IsShowing) it only appears from
	                 BUSY_MIN_STACKS, so arrows, altar markers and timers don't all pile up at once.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Protocol = require(ReplicatedStorage:WaitForChild("MiasmaEncounterProtocol"))
local ValveArrows = require(script.Parent:WaitForChild("MiasmaValveArrows"))
local Config = require(ReplicatedStorage:WaitForChild("MiasmaEncounterConfig"))
local HudIcons = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Icons"):WaitForChild("Hud"):WaitForChild("HudIcons"))

local player = Players.LocalPlayer
local ATTR = Protocol.Attributes.PoisonStacks
local MAX = Config.Poison.MaxStacks
local ALTAR_TAG = "MiasmaCleanseAltar"
local PROMPT_NAME = "MiasmaCleansePrompt"
local MARKER_SIZE = 36          -- pixels
local MARKER_TRANSPARENCY = .35 -- the whole marker, at full strength
local BUSY_MIN_STACKS = 3       -- while valve arrows are up, altar markers wait for this many stacks
local FADE_NEAR, FADE_FAR = 10, 20 -- studs: gone within FADE_NEAR of the altar, full past FADE_FAR

local POISON = Color3.fromRGB(150, 230, 90)
local TEXT = Color3.fromRGB(240, 236, 226)
local RED = Color3.fromRGB(235, 60, 55)
local PANEL = Color3.fromRGB(14, 13, 16)

local function stacks()
	return math.floor(tonumber(player:GetAttribute(ATTR)) or 0)
end

-------------------------------------------------------------------------------------------------
-- Stack counter above the health bar

local counter = Instance.new("Frame")
counter.Name = "PoisonStacks"
counter.AnchorPoint = Vector2.new(.5, 1)
counter.Position = UDim2.new(.5, 0, 0, -10)
counter.Size = UDim2.fromOffset(0, 26)
counter.AutomaticSize = Enum.AutomaticSize.X
counter.BackgroundColor3 = PANEL
counter.BackgroundTransparency = .25
counter.BorderSizePixel = 0
counter.Visible = false
Instance.new("UICorner", counter).CornerRadius = UDim.new(0, 6)
local counterStroke = Instance.new("UIStroke", counter)
counterStroke.Color = POISON
counterStroke.Thickness = 1.5
counterStroke.Transparency = .3
local pad = Instance.new("UIPadding", counter)
pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 6), UDim.new(0, 8)
local row = Instance.new("UIListLayout", counter)
row.FillDirection = Enum.FillDirection.Horizontal
row.VerticalAlignment = Enum.VerticalAlignment.Center
row.Padding = UDim.new(0, 5)
row.SortOrder = Enum.SortOrder.LayoutOrder

local counterIcon = Instance.new("ImageLabel")
counterIcon.Size = UDim2.fromOffset(20, 20)
counterIcon.BackgroundTransparency = 1
counterIcon.Image = HudIcons.POISON
counterIcon.LayoutOrder = 1
counterIcon.Parent = counter

local counterText = Instance.new("TextLabel")
counterText.Size = UDim2.fromOffset(0, 20)
counterText.AutomaticSize = Enum.AutomaticSize.X
counterText.BackgroundTransparency = 1
counterText.Font = Enum.Font.GothamBold
counterText.TextSize = 15
counterText.TextColor3 = TEXT
counterText.TextStrokeTransparency = .4
counterText.LayoutOrder = 2
counterText.Parent = counter

-- Hang it off the health bar itself, so it follows wherever HealthClient puts the bar.
task.spawn(function()
	local gui = player:WaitForChild("PlayerGui"):WaitForChild("HealthBarGui", 30)
	local bar = gui and gui:WaitForChild("HPBarBackground", 30)
	if bar then counter.Parent = bar end
end)

-------------------------------------------------------------------------------------------------
-- Altar markers: the poison icon crossed out, over every cleanse altar

local markers = {} -- [anchor] = BillboardGui

local function buildMarker(anchor)
	local gui = Instance.new("BillboardGui")
	gui.Name = "PoisonCleanseMarker"
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Size = UDim2.fromOffset(MARKER_SIZE + 24, MARKER_SIZE)
	gui.StudsOffset = Vector3.new(0, 6, 0)
	gui.MaxDistance = 1000
	gui.Adornee = anchor
	gui.Enabled = false

	local root = Instance.new("CanvasGroup") -- one transparency for the whole marker
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = gui

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.AnchorPoint = Vector2.new(.5, .5)
	icon.Position = UDim2.fromScale(.5, .5)
	icon.Size = UDim2.fromOffset(MARKER_SIZE, MARKER_SIZE)
	icon.BackgroundTransparency = 1
	icon.Image = HudIcons.POISON
	icon.Parent = root

	-- A thin red slash corner to corner over the icon.
	local slash = Instance.new("Frame")
	slash.AnchorPoint = Vector2.new(.5, .5)
	slash.Position = UDim2.fromScale(.5, .5)
	slash.Size = UDim2.new(1.1, 0, 0, 3)
	slash.Rotation = -45
	slash.BackgroundColor3 = RED
	slash.BorderSizePixel = 0
	slash.ZIndex = 2
	slash.Parent = icon
	Instance.new("UICorner", slash).CornerRadius = UDim.new(1, 0)

	local timer = Instance.new("TextLabel")
	timer.Name = "Timer"
	timer.Size = UDim2.fromScale(1, 1)
	timer.BackgroundTransparency = 1
	timer.Font = Enum.Font.GothamBold
	timer.TextSize = 16
	timer.TextColor3 = TEXT
	timer.TextStrokeTransparency = .35
	timer.Visible = false
	timer.Parent = root

	gui.Parent = player:WaitForChild("PlayerGui")
	return { gui = gui, root = root, icon = icon, timer = timer, anchor = anchor }
end

local function addAltar(anchor)
	if markers[anchor] or not anchor:IsA("BasePart") then return end
	markers[anchor] = buildMarker(anchor)
end

local function removeAltar(anchor)
	local marker = markers[anchor]
	markers[anchor] = nil
	if marker then marker.gui:Destroy() end
end

for _, anchor in ipairs(CollectionService:GetTagged(ALTAR_TAG)) do addAltar(anchor) end
CollectionService:GetInstanceAddedSignal(ALTAR_TAG):Connect(addAltar)
CollectionService:GetInstanceRemovedSignal(ALTAR_TAG):Connect(removeAltar)

-------------------------------------------------------------------------------------------------
-- Update

local function refresh()
	local n = stacks()
	counter.Visible = n > 0
	counterText.Text = ("%d/%d"):format(n, MAX)
end

local function formatSeconds(seconds)
	seconds = math.max(0, math.ceil(seconds))
	if seconds >= 60 then return ("%d:%02d"):format(seconds // 60, seconds % 60) end
	return tostring(seconds)
end

-- One marker per altar, or none: see the header for the rules.
local function updateMarkers(n)
	local character = player.Character
	local me = character and character:FindFirstChild("HumanoidRootPart")
	local showAny = n > 0 and (n >= BUSY_MIN_STACKS or not ValveArrows.IsShowing())
	local now = workspace:GetServerTimeNow()
	local bob = Vector3.new(0, 6 + math.sin(os.clock() * 3) * .4, 0)
	for anchor, marker in pairs(markers) do
		local mode = nil
		if showAny and anchor.Parent then
			local endsAt = tonumber(anchor:GetAttribute("CooldownEndsAt")) or 0
			local prompt = anchor:FindFirstChild(PROMPT_NAME)
			if endsAt > now then
				mode = "timer"
				marker.timer.Text = formatSeconds(endsAt - now)
			elseif prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled then
				mode = "icon"
			end
		end
		marker.gui.Enabled = mode ~= nil
		if mode then
			marker.icon.Visible = mode == "icon"
			marker.timer.Visible = mode == "timer"
			marker.gui.StudsOffset = bob
			local fade = 1
			if me then
				local d = (me.Position - anchor.Position).Magnitude
				fade = math.clamp((d - FADE_NEAR) / (FADE_FAR - FADE_NEAR), 0, 1)
			end
			marker.root.GroupTransparency = 1 - (1 - MARKER_TRANSPARENCY) * fade
		end
	end
end

player:GetAttributeChangedSignal(ATTR):Connect(refresh)
refresh()

-- At the max the counter flashes red; the altar markers update (mode, fade, gentle bob).
RunService.RenderStepped:Connect(function()
	local n = stacks()
	local t = os.clock()
	if counter.Visible then
		if n >= MAX then
			local pulse = .5 + .5 * math.sin(t * 10)
			counter.BackgroundColor3 = PANEL:Lerp(RED, pulse * .85)
			counterStroke.Color = RED
			counterText.TextColor3 = TEXT:Lerp(RED, 1 - pulse)
		else
			counter.BackgroundColor3 = PANEL
			counterStroke.Color = POISON
			counterText.TextColor3 = TEXT
		end
	end
	updateMarkers(n)
end)
