--[[
	TutorialClient

	Draws the tutorial the server is running for you (SSS/TutorialService, GameEvents/
	TutorialState). It decides nothing: no step can be completed or skipped from here and no
	reward comes from here. It shows:

	  - the objective: a plate at the top (under the top-centre HUD) with "OBJECTIVE" and one
	    short line; it slides in with a chime whenever it changes
	  - key hints under it: plates with the key (or mouse icon) and a word
	  - the path: glowing blue chevrons on the ground along a walkable route (PathfindingService,
	    recomputed as you move) to the target, pulsing toward it, plus a marker over the target
	    and a pointer on the screen's edge when it's behind you
	  - focus: the screen greys slightly EXCEPT the UI element to press (found by its
	    TutorialTarget attribute, or "item:<uuid>" for a bag slot). Clicks still go through.
	  - spotlight: like focus but the game pauses (your controls, and the server freezes your
	    copy's mobs), with a caption and "Press Space to continue" (a key, not a click: the
	    player is often spam-clicking a fight). That press is the one thing sent back
	    (TutorialAck "ack" + the step's token); only a step waiting on it accepts it.
	  - the objective plate and hints use the Journal's art (JournalUI sidebar_row_selected,
	    chip) and its serif, so the tutorial reads as part of the same book.
	  - the thing to use (merchant, altar, ore, blacksmith, totem): a pulsing gold glow on its
	    model (the step's `highlight`)
	  - named moments: "wake" (eyes opening: dark lids part, blink, focus).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local PathfindingService = game:GetService("PathfindingService")
local Lighting = game:GetService("Lighting")

local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local HudTopCentre = require(ReplicatedStorage:WaitForChild("HudTopCentre"))
local HudIcons = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Icons"):WaitForChild("Hud"):WaitForChild("HudIcons"))
local SfxService = require(ReplicatedStorage:WaitForChild("SfxService"))
local JournalUI = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images"):WaitForChild("JournalUI"))
local UILayers = require(ReplicatedStorage:WaitForChild("UILayers"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gameEvents = ReplicatedStorage:WaitForChild("GameEvents")
local stateEvent = gameEvents:WaitForChild("TutorialState")
local ackEvent = gameEvents:WaitForChild("TutorialAck")

-- The Journal's look (Journal/Style): light chrome text on dark leather and bronze, its serif.
local BONE = Color3.fromRGB(246, 230, 190) -- Style.Chrome.Selected
local LABEL = Color3.fromRGB(214, 200, 172) -- Style.Chrome.Label
local GOLD = Color3.fromRGB(255, 214, 120)
local PLATE = Color3.fromRGB(16, 12, 9)
local BRONZE = Color3.fromRGB(170, 134, 80)
local SERIF = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold) -- UIFonts.SerifBold
local TRAIL = Color3.fromRGB(80, 170, 255)

-- the path
local TRAIL_SPACING = 3.2 -- studs between chevrons
local TRAIL_MAX = 45 -- chevrons drawn at most (~145 studs ahead)
local TRAIL_START = 3 -- studs ahead of you where the first one sits
local TRAIL_ARRIVE = 7 -- studs from the target where the trail is no longer needed
local PATH_EVERY = 0.8 -- seconds between route updates
local MARKER_HEIGHT = 6 -- studs above the target
local EDGE_MARGIN = 70


local function make(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do inst[k] = v end
	inst.Parent = parent
	return inst
end

local gui = make("ScreenGui", {
	-- Above every menu and HUD row (UILayers.TUTORIAL), so the objective stays readable inside
	-- the Tab menu and the focus box can sit over the button it points at.
	Name = "Tutorial", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = UILayers.TUTORIAL,
}, playerGui)
game:GetService("CollectionService"):AddTag(gui, "OverMenus") -- stays up over the Tab menu

---------------------------------------------------------------------------
-- Objective plate + key hints
---------------------------------------------------------------------------

local header = make("Frame", {
	Name = "Objective", AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(0, 0),
	AutomaticSize = Enum.AutomaticSize.XY, BackgroundTransparency = 1, Visible = false, ZIndex = 20,
}, gui)
make("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical, HorizontalAlignment = Enum.HorizontalAlignment.Center,
	Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
}, header)
-- Backed by the Journal's bronze plaque (JournalUI.sidebar_row_selected, 9-sliced so its riveted
-- ends keep their shape at any width); a plain dark plate if the art is missing.
local plaqueArt = JournalUI.sidebar_row_selected
local hasPlaque = plaqueArt and plaqueArt.Image ~= ""
local plate = make(hasPlaque and "ImageLabel" or "Frame", {
	LayoutOrder = 1, Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY,
	BackgroundColor3 = PLATE, BackgroundTransparency = hasPlaque and 1 or 0.2, BorderSizePixel = 0, ZIndex = 20,
}, header)
if hasPlaque then
	plate.Image = plaqueArt.Image
	plate.ScaleType = Enum.ScaleType.Slice
	plate.SliceCenter = plaqueArt.SliceCenter
	plate.SliceScale = 0.45
else
	make("UICorner", { CornerRadius = UDim.new(0, 8) }, plate)
end
local plateStroke = make("UIStroke", { Color = BRONZE, Thickness = 2, Transparency = hasPlaque and 1 or 0.1 }, plate)
make("UIPadding", {
	PaddingLeft = UDim.new(0, 58), PaddingRight = UDim.new(0, 58), PaddingTop = UDim.new(0, 22), PaddingBottom = UDim.new(0, 22),
}, plate)
make("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical, HorizontalAlignment = Enum.HorizontalAlignment.Center,
	Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder,
}, plate)
make("TextLabel", {
	LayoutOrder = 1, Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1,
	FontFace = SERIF, TextSize = 13, TextColor3 = GOLD, Text = "OBJECTIVE", ZIndex = 21,
}, plate)
local objective = make("TextLabel", {
	LayoutOrder = 2, Size = UDim2.fromOffset(0, 32), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1,
	FontFace = SERIF, TextSize = 24, TextColor3 = BONE, TextStrokeTransparency = 0.55, Text = "", ZIndex = 21,
}, plate)
local plateScale = make("UIScale", { Scale = 1 }, plate)
local hintRow = make("Frame", {
	LayoutOrder = 2, Size = UDim2.fromOffset(0, 36), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, ZIndex = 20,
}, header)
make("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder,
}, hintRow)

local function placeHeader()
	header.Position = UDim2.new(0.5, 0, 0, HudTopCentre.Bottom() + 12)
end
placeHeader()
HudTopCentre.Changed:Connect(placeHeader)

local chipArt = JournalUI.chip
local hasChip = chipArt and chipArt.Image ~= ""

local function hintPlate(order, key, text)
	-- The Journal's riveted chip (JournalUI.chip), 9-sliced; a plain plate without the art.
	local p = make(hasChip and "ImageLabel" or "Frame", {
		LayoutOrder = order, Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = PLATE, BackgroundTransparency = hasChip and 1 or 0.2, BorderSizePixel = 0, ZIndex = 20,
	}, hintRow)
	if hasChip then
		p.Image = chipArt.Image
		p.ScaleType = Enum.ScaleType.Slice
		p.SliceCenter = chipArt.SliceCenter
		p.SliceScale = 0.17
	else
		make("UICorner", { CornerRadius = UDim.new(0, 7) }, p)
	end
	local stroke = make("UIStroke", { Color = GOLD, Transparency = hasChip and 1 or 0.3, Thickness = 2 }, p)
	make("UIPadding", { PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 22) }, p)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
	}, p)
	if key == "MouseLeft" and HudIcons.MOUSE_LEFT ~= "" then
		make("ImageLabel", {
			LayoutOrder = 1, Size = UDim2.fromOffset(24, 24), BackgroundTransparency = 1, ZIndex = 21,
			Image = HudIcons.MOUSE_LEFT, ImageColor3 = BONE, ScaleType = Enum.ScaleType.Fit,
		}, p)
	else
		local chip = make("Frame", {
			LayoutOrder = 1, Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = Color3.fromRGB(46, 36, 26), BorderSizePixel = 0, ZIndex = 21,
		}, p)
		make("UICorner", { CornerRadius = UDim.new(0, 4) }, chip)
		make("UIStroke", { Color = GOLD, Thickness = 1.5 }, chip)
		make("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) }, chip)
		make("TextLabel", {
			Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, ZIndex = 22,
			FontFace = SERIF, TextSize = 15, TextColor3 = BONE, Text = tostring(key),
		}, chip)
	end
	local label = make("TextLabel", {
		LayoutOrder = 2, Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1,
		FontFace = SERIF, TextSize = 17, TextColor3 = LABEL, TextStrokeTransparency = 0.6, ZIndex = 21,
		Text = tostring(text or ""),
	}, p)
	-- a gentle pulse so the eye finds it (the label brightens and dims; the stroke without art)
	TweenService:Create(label, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { TextColor3 = BONE }):Play()
	if not hasChip then
		TweenService:Create(stroke, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.75 }):Play()
	end
end

local function setObjective(text, hints, announce)
	for _, child in ipairs(hintRow:GetChildren()) do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	if type(text) ~= "string" or text == "" then
		header.Visible = false
		return
	end
	objective.Text = text
	for i, hint in ipairs(type(hints) == "table" and hints or {}) do
		hintPlate(i, hint.key, hint.text)
	end
	header.Visible = true
	if announce then
		-- New objective: pop in, flash the border gold, chime.
		plateScale.Scale = 1.25
		TweenService:Create(plateScale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		if hasPlaque then
			plate.ImageColor3 = Color3.fromRGB(255, 236, 170)
			TweenService:Create(plate, TweenInfo.new(1.2), { ImageColor3 = Color3.new(1, 1, 1) }):Play()
		else
			plateStroke.Color = GOLD
			TweenService:Create(plateStroke, TweenInfo.new(1.2), { Color = BRONZE }):Play()
		end
		SfxService.PlayEffect("TabSwitch")
	end
end

---------------------------------------------------------------------------
-- The path: chevrons on the ground, a marker over the target, an edge pointer
---------------------------------------------------------------------------

local target: Vector3? = nil
local trailFolder = Instance.new("Folder")
trailFolder.Name = "TutorialTrail"
local chevrons = {} -- pool: { left, right }
local route = {} -- polyline points from you to the target

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function armPart()
	return make("Part", {
		Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
		Material = Enum.Material.Neon, Color = TRAIL, Size = Vector3.new(0.28, 0.08, 1.5), Transparency = 1,
	}, trailFolder)
end

local function chevronAt(i)
	local c = chevrons[i]
	if not c then
		c = { armPart(), armPart() }
		chevrons[i] = c
	end
	return c
end

-- Ground height under a point (or the point itself).
local function ground(p)
	rayParams.FilterDescendantsInstances = { player.Character, trailFolder }
	local hit = workspace:Raycast(p + Vector3.new(0, 6, 0), Vector3.new(0, -20, 0), rayParams)
	return hit and (hit.Position + Vector3.new(0, 0.12, 0)) or p
end

-- One ">" pointing along `dir` with its tip at `p`.
local function placeChevron(c, p, dir)
	local right = dir:Cross(Vector3.yAxis)
	if right.Magnitude < 1e-3 then right = Vector3.xAxis end
	right = right.Unit
	for s, arm in ipairs(c) do
		local side = s == 1 and -1 or 1
		local armDir = (dir - right * side * 0.85).Unit
		local centre = p - armDir * 0.75
		arm.CFrame = CFrame.lookAt(centre, p)
	end
end

local marker = make("BillboardGui", {
	Name = "TutorialMarker", AlwaysOnTop = true, Size = UDim2.fromOffset(54, 54), LightInfluence = 0, Enabled = false,
}, gui)
local markerAnchor = make("Part", {
	Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2),
}, nil)
local markerDiamond = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(26, 26),
	Rotation = 45, BackgroundColor3 = TRAIL, BorderSizePixel = 0,
}, marker)
make("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2 }, markerDiamond)
local edgePointer = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(40, 40), BackgroundTransparency = 1, ZIndex = 20,
	Text = ">", FontFace = UIFonts.HUDLabel, TextScaled = true, TextColor3 = TRAIL, TextStrokeTransparency = 0.1, Visible = false,
}, gui)

local function clearTrail()
	for _, c in ipairs(chevrons) do
		c[1].Transparency, c[2].Transparency = 1, 1
	end
end

local function setTarget(position)
	target = typeof(position) == "Vector3" and position or nil
	route = {}
	if target then
		trailFolder.Parent = workspace
		markerAnchor.Position = target + Vector3.new(0, MARKER_HEIGHT, 0)
		markerAnchor.Parent = workspace
		marker.Adornee = markerAnchor
		marker.Enabled = true
	else
		clearTrail()
		marker.Enabled = false
		edgePointer.Visible = false
		markerAnchor.Parent = nil
	end
end

-- Keep a walkable route from you to the target (straight line if no path is found).
task.spawn(function()
	local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 4 })
	while true do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local goal = target
		if root and goal then
			local ok = pcall(function() path:ComputeAsync(root.Position, goal) end)
			local points = {}
			if ok and path.Status == Enum.PathStatus.Success then
				for _, wp in ipairs(path:GetWaypoints()) do table.insert(points, wp.Position) end
			else
				points = { root.Position, goal }
			end
			if target == goal then route = points end
		end
		task.wait(PATH_EVERY)
	end
end)

-- Lay chevrons along the route, every TRAIL_SPACING studs, pulsing toward the target.
local function drawTrail(rootPos, t)
	local placed = 0
	if #route >= 2 then
		-- start from the route point nearest you, so the trail always begins at your feet
		local startIdx, best = 1, math.huge
		for i, p in ipairs(route) do
			local d = (p - rootPos).Magnitude
			if d < best then best, startIdx = d, i end
		end
		local points = { rootPos }
		for i = startIdx + 1, #route do table.insert(points, route[i]) end
		local carry = TRAIL_START
		for i = 1, #points - 1 do
			local a, b = points[i], points[i + 1]
			local seg = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
			local len = seg.Magnitude
			if len > 1e-3 then
				local dir = seg / len
				local d = carry
				while d <= len and placed < TRAIL_MAX do
					local p = a + (b - a) * (d / len)
					if target and (p - target).Magnitude < 3 then break end
					placed += 1
					local c = chevronAt(placed)
					placeChevron(c, ground(p), dir)
					-- a wave running toward the target
					local wave = 0.5 + 0.5 * math.sin(t * 6 - placed * 0.55)
					local fadeIn = math.clamp(placed / 3, 0.35, 1)
					local alpha = 0.15 + 0.55 * (1 - wave)
					c[1].Transparency = 1 - (1 - alpha) * fadeIn
					c[2].Transparency = c[1].Transparency
					d += TRAIL_SPACING
				end
				carry = d - len
			end
			if placed >= TRAIL_MAX then break end
		end
	end
	for i = placed + 1, #chevrons do
		chevrons[i][1].Transparency, chevrons[i][2].Transparency = 1, 1
	end
end

RunService.RenderStepped:Connect(function()
	if not target then return end
	local camera = workspace.CurrentCamera
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not camera or not root then return end
	local t = os.clock()
	local dist = (root.Position - target).Magnitude
	if dist > TRAIL_ARRIVE then drawTrail(root.Position, t) else clearTrail() end
	marker.StudsOffsetWorldSpace = Vector3.new(0, math.sin(t * 3) * 0.5, 0)
	markerDiamond.Rotation = 45 + math.sin(t * 2) * 8
	-- Edge pointer when the target is off-screen.
	local point, onScreen = camera:WorldToViewportPoint(markerAnchor.Position)
	if onScreen and point.Z > 0 then
		edgePointer.Visible = false
		return
	end
	local vp = camera.ViewportSize
	local centre = vp / 2
	local dir = Vector2.new(point.X, point.Y) - centre
	if point.Z < 0 then dir = -dir end
	if dir.Magnitude < 1 then dir = Vector2.new(0, 1) end
	dir = dir.Unit
	local half = centre - Vector2.new(EDGE_MARGIN, EDGE_MARGIN)
	local scale = math.min(math.abs(half.X / (dir.X ~= 0 and dir.X or 1e-6)), math.abs(half.Y / (dir.Y ~= 0 and dir.Y or 1e-6)))
	local pos = centre + dir * scale
	edgePointer.Position = UDim2.fromOffset(pos.X, pos.Y)
	edgePointer.Rotation = math.deg(math.atan2(dir.Y, dir.X))
	edgePointer.Visible = true
end)

---------------------------------------------------------------------------
-- Focus / spotlight: grey everything except one UI element
---------------------------------------------------------------------------

local veil = make("Frame", { Name = "Focus", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 50 }, gui)
local shades = {}
for i = 1, 4 do
	shades[i] = make("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.55, BorderSizePixel = 0, ZIndex = 50 }, veil)
end
local ring = make("Frame", { BackgroundTransparency = 1, ZIndex = 51 }, veil)
local ringStroke = make("UIStroke", { Color = GOLD, Thickness = 3 }, ring)
make("UICorner", { CornerRadius = UDim.new(0, 8) }, ring)
local caption = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(560, 64), BackgroundTransparency = 1, TextWrapped = true,
	FontFace = SERIF, TextSize = 20, TextColor3 = BONE, TextStrokeTransparency = 0.25, ZIndex = 52, Text = "", Visible = false,
}, veil)
local continueLabel = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(300, 24), BackgroundTransparency = 1, Visible = false,
	FontFace = SERIF, TextSize = 16, TextColor3 = GOLD, TextStrokeTransparency = 0.35, ZIndex = 52,
	Text = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and "Tap to continue" or "Press Space to continue",
}, veil)

local focusKey = nil -- what to keep lit
local focusTarget = nil -- the GuiObject found for it
local focusSearchAt = 0
local spotlightToken = nil -- set while a blocking spotlight waits for the click
local clickAckToken = nil -- set while a step waits for a click ON its focus target (ackOnClick)
local focusIsFirst = false -- the lit target is the first (final) one in the focus list

local function shown(obj)
	if not obj or not obj:IsDescendantOf(playerGui) then return false end
	local node = obj
	while node and node ~= playerGui do
		if node:IsA("GuiObject") and not node.Visible then return false end
		if node:IsA("ScreenGui") and not node.Enabled then return false end
		node = node.Parent
	end
	return obj.AbsoluteSize.X > 0
end

local findTarget
findTarget = function(key)
	-- A list means "the first of these that's on screen" (e.g. the sword's bag slot, else the
	-- Inventory button while the menu is still closed).
	if type(key) == "table" then
		for i, k in ipairs(key) do
			local found = findTarget(k)
			if found then return found, i == 1 end
		end
		return nil, false
	end
	if type(key) ~= "string" then return nil end
	local uuid = key:match("^item:(.+)$")
	for _, d in ipairs(playerGui:GetDescendants()) do
		if d:IsA("GuiObject") and not d:IsDescendantOf(gui) then
			if uuid then
				if d:GetAttribute("ItemUuid") == uuid and shown(d) then return d end
			elseif d:GetAttribute("TutorialTarget") == key and shown(d) then
				return d
			end
		end
	end
	return nil
end

local function controls()
	local ok, module = pcall(function()
		return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")):GetControls()
	end)
	return ok and module or nil
end

local function layoutVeil(p0, size, vp)
	shades[1].Position, shades[1].Size = UDim2.fromOffset(0, 0), UDim2.fromOffset(vp.X, math.max(0, p0.Y))
	shades[2].Position, shades[2].Size = UDim2.fromOffset(0, p0.Y + size.Y), UDim2.fromOffset(vp.X, math.max(0, vp.Y - p0.Y - size.Y))
	shades[3].Position, shades[3].Size = UDim2.fromOffset(0, p0.Y), UDim2.fromOffset(math.max(0, p0.X), size.Y)
	shades[4].Position, shades[4].Size = UDim2.fromOffset(p0.X + size.X, p0.Y), UDim2.fromOffset(math.max(0, vp.X - p0.X - size.X), size.Y)
	ring.Position, ring.Size = UDim2.fromOffset(p0.X, p0.Y), UDim2.fromOffset(size.X, size.Y)
end

RunService.RenderStepped:Connect(function()
	if not focusKey and not spotlightToken then
		veil.Visible = false
		return
	end
	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	-- Re-search often: with a list of targets, a better one (the bag slot) can appear while the
	-- current one (the Inventory button) is still showing.
	if focusKey and (not focusTarget or not shown(focusTarget) or type(focusKey) == "table") and os.clock() >= focusSearchAt then
		focusSearchAt = os.clock() + 0.3
		local found, first = findTarget(focusKey)
		focusTarget = found
		focusIsFirst = type(focusKey) ~= "table" or first == true
	end
	local lit = focusTarget and shown(focusTarget)
	if not lit and not spotlightToken then
		veil.Visible = false -- nothing to point at right now (e.g. the menu isn't open yet)
		return
	end
	veil.Visible = true
	-- AbsolutePosition is ALWAYS measured from below the top bar (measured in play: a frame at
	-- this IgnoreGuiInset gui's top reports y = -58), while this gui's offsets start at the
	-- screen's real top. So every target shifts down by the top inset, whatever gui it's in.
	local inset = game:GetService("GuiService"):GetGuiInset()
	local pad = 6
	local p0, size
	if lit then
		p0 = focusTarget.AbsolutePosition + inset - Vector2.new(pad, pad)
		size = focusTarget.AbsoluteSize + Vector2.new(pad * 2, pad * 2)
	else
		p0, size = vp / 2, Vector2.zero
	end
	layoutVeil(p0, size, vp)
	ring.Visible = lit and true or false
	ringStroke.Transparency = 0.15 + 0.35 * (0.5 + 0.5 * math.sin(os.clock() * 5))
	-- the spotlight's caption: above the hole if there's room, else below
	if spotlightToken then
		-- well clear of the target (HUD pieces sit stacked close together)
		local above = p0.Y > 170
		local cy = above and (p0.Y - 150) or (p0.Y + size.Y + 14)
		caption.Position = UDim2.fromOffset(lit and (p0.X + size.X / 2) or vp.X / 2, lit and cy or vp.Y * 0.4)
		continueLabel.Position = caption.Position + UDim2.fromOffset(0, 68)
	end
end)

local function closeSpotlight()
	if not spotlightToken then return end
	local token = spotlightToken
	spotlightToken = nil
	caption.Visible, continueLabel.Visible = false, false
	for _, s in ipairs(shades) do s.BackgroundTransparency = 0.55 end
	local c = controls()
	if c then c:Enable() end
	ackEvent:FireServer("ack", token)
end

local function openSpotlight(spec, token)
	focusKey = spec.target
	focusTarget = nil
	focusSearchAt = 0
	caption.Text = tostring(spec.caption or "")
	caption.Visible, continueLabel.Visible = true, true
	for _, s in ipairs(shades) do s.BackgroundTransparency = 0.4 end
	spotlightToken = token
	spotlightOpenedAt = os.clock()
	local c = controls()
	if c then c:Disable() end
end

-- ackOnClick: a click on the final focus target (the Loot Score page) completes the step.
UserInputService.InputBegan:Connect(function(input)
	if not clickAckToken or not focusTarget or not focusIsFirst then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
	-- input.Position and AbsolutePosition are in the same (below-the-top-bar) space.
	local p = Vector2.new(input.Position.X, input.Position.Y)
	local a = focusTarget.AbsolutePosition
	local b = a + focusTarget.AbsoluteSize
	if p.X >= a.X and p.X <= b.X and p.Y >= a.Y and p.Y <= b.Y then
		ackEvent:FireServer("ack", clickAckToken)
		clickAckToken = nil
	end
end)

-- Spotlights continue on a KEY (Space, Enter, gamepad A), never a mouse click: the player is often
-- spam-clicking a fight when one opens. Touch-only devices tap, after a short pause for the same reason.
local TOUCH_GRACE = 1.2
local spotlightOpenedAt = 0
UserInputService.InputBegan:Connect(function(input)
	if not spotlightToken then return end
	local key = input.KeyCode
	if key == Enum.KeyCode.Space or key == Enum.KeyCode.Return or key == Enum.KeyCode.ButtonA then
		closeSpotlight()
	elseif input.UserInputType == Enum.UserInputType.Touch and not UserInputService.KeyboardEnabled
		and os.clock() - spotlightOpenedAt > TOUCH_GRACE then
		closeSpotlight()
	end
end)

---------------------------------------------------------------------------
-- Moments
---------------------------------------------------------------------------

-- "wake": the screen starts black, the lids part, close again (a blink), then open with the
-- world coming into focus.
local function playWake()
	local lids = {}
	for i, anchorY in ipairs({ 0, 1 }) do
		lids[i] = make("Frame", {
			AnchorPoint = Vector2.new(0, anchorY), Position = UDim2.fromScale(0, anchorY), Size = UDim2.fromScale(1, 0.5),
			BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 60,
		}, gui)
	end
	local blur = Instance.new("BlurEffect")
	blur.Size = 24
	blur.Parent = Lighting
	local function lidsTo(openness, time)
		for _, lid in ipairs(lids) do
			TweenService:Create(lid, TweenInfo.new(time, Enum.EasingStyle.Sine), { Size = UDim2.fromScale(1, 0.5 * (1 - openness)) }):Play()
		end
		task.wait(time)
	end
	task.spawn(function()
		task.wait(0.6)
		lidsTo(0.35, 0.8)
		lidsTo(0, 0.25)
		task.wait(0.3)
		TweenService:Create(blur, TweenInfo.new(1.6), { Size = 0 }):Play()
		lidsTo(1, 1.0)
		for _, lid in ipairs(lids) do lid:Destroy() end
		task.wait(0.8)
		blur:Destroy()
	end)
end

---------------------------------------------------------------------------
-- The thing to use (the merchant, the altar, the ore): a soft gold glow on its model.
-- The server sends the instance; if it hasn't streamed in yet, the nearest one by name
-- is picked up as soon as it does.
---------------------------------------------------------------------------

local HIGHLIGHT_COLOR = Color3.fromRGB(255, 205, 110)
local HIGHLIGHT_SEARCH = 400 -- studs: only this player's own tutorial copy is that close
local glow = make("Highlight", {
	Name = "TutorialGlow", FillColor = HIGHLIGHT_COLOR, OutlineColor = HIGHLIGHT_COLOR,
	FillTransparency = 1, OutlineTransparency = 1, DepthMode = Enum.HighlightDepthMode.Occluded,
	Enabled = false,
}, workspace.CurrentCamera) -- client-only, and a Highlight renders from here with an Adornee
local glowName, glowTarget = nil, nil

local function findByName(name)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	local best, bestDist = nil, HIGHLIGHT_SEARCH
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst.Name == name and (inst:IsA("Model") or inst:IsA("BasePart")) then
			local pos = inst:IsA("Model") and inst:GetPivot().Position or inst.Position
			local dist = (pos - root.Position).Magnitude
			if dist < bestDist then best, bestDist = inst, dist end
		end
	end
	return best
end

local function setHighlight(target, name)
	glowTarget = typeof(target) == "Instance" and target or nil
	glowName = type(name) == "string" and name or nil
	glow.Adornee = glowTarget
	glow.Enabled = glowTarget ~= nil
end

local nextGlowSearch = 0
RunService.RenderStepped:Connect(function()
	if glowTarget and not glowTarget:IsDescendantOf(workspace) then
		glowTarget = nil -- streamed out or the copy went away: look again by name
		glow.Adornee, glow.Enabled = nil, false
	end
	if not glowTarget and glowName and os.clock() >= nextGlowSearch then
		nextGlowSearch = os.clock() + 1
		local found = findByName(glowName)
		if found then setHighlight(found, glowName) end
	end
	if glow.Enabled then
		local pulse = 0.5 + 0.5 * math.sin(os.clock() * 3)
		glow.FillTransparency = 0.82 - 0.12 * pulse
		glow.OutlineTransparency = 0.35 * (1 - pulse)
	end
end)

---------------------------------------------------------------------------
-- State from the server
---------------------------------------------------------------------------

local lastStep = nil
stateEvent.OnClientEvent:Connect(function(state)
	if type(state) ~= "table" then return end
	if state.done then
		setObjective(nil)
		setTarget(nil)
		setHighlight(nil, nil)
		focusKey, focusTarget = nil, nil
		if spotlightToken then spotlightToken = nil; local c = controls(); if c then c:Enable() end end
		lastStep = nil
		return
	end
	local fresh = state.stepId ~= lastStep
	lastStep = state.stepId
	setObjective(state.objective, state.hints, fresh)
	setTarget(state.arrow)
	setHighlight(state.highlight, state.highlightName)
	if fresh and state.cutscene == "wake" then playWake() end
	clickAckToken = (state.waitForAck and state.ackOnClick) and state.token or nil
	if type(state.spotlight) == "table" and state.waitForAck then
		openSpotlight(state.spotlight, state.token)
	elseif not spotlightToken then
		focusKey = state.focus
		focusTarget = nil
		focusSearchAt = 0
	end
end)

ackEvent:FireServer("sync") -- in case a step started before this script was listening
