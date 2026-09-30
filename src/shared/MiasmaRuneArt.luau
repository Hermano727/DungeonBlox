--[[
	MiasmaRuneArt -- how each Miasma rune LOOKS. Identity lives in MiasmaRunes.

	MVP art is built from GUI primitives (rounded line strokes, arcs made of short strokes,
	dots) inside a unit square, so it renders crisply at any size in both the world tablet
	(SurfaceGui) and the maze (ScreenGui) with no uploaded images.

	Replacing the art later: set `Images[<runeId>] = "rbxassetid://..."`. Render() then
	shows that image instead of the strokes. Nothing else changes.

	Design rule: every rune must be identifiable by SILHOUETTE alone at ~24px, in a single
	colour. Current set: closed ring + pupil (Eye), downward triangle (Fang), three-peak
	crown (Crown), stacked zigzags (Tide), open C (Moon), square spiral (Coil), six-spoke
	asterisk (Ward), stem + crossbar + hook (Anchor).
]]

local RuneArt = {}

-- Optional per-rune image overrides. Leave nil to use the stroke art below.
RuneArt.Images = {
	Eye = nil,
	Fang = nil,
	Crown = nil,
	Tide = nil,
	Moon = nil,
	Coil = nil,
	Ward = nil,
	Anchor = nil,
}

local function p(x, y) return Vector2.new(x, y) end

-- Primitive kinds, all in a 0..1 box with y pointing DOWN:
--   { "poly", {points...}, closed? }   connected strokes
--   { "arc", centre, radius, fromDeg, toDeg }   (0 deg = right, 90 deg = down)
--   { "dot", centre, radius }
-- `weight` scales the stroke thickness for that rune.
RuneArt.Strokes = {
	Eye = { weight = 1, parts = {
		{ "arc", p(.5, .5), .34, 0, 360 },
		{ "dot", p(.5, .5), .1 },
	} },
	Fang = { weight = 1, parts = {
		{ "poly", { p(.16, .22), p(.84, .22), p(.5, .86) }, true },
	} },
	Crown = { weight = 1, parts = {
		{ "poly", { p(.16, .78), p(.16, .3), p(.33, .56), p(.5, .18), p(.67, .56), p(.84, .3), p(.84, .78) }, true },
	} },
	Tide = { weight = 1, parts = {
		{ "poly", { p(.12, .42), p(.31, .24), p(.5, .42), p(.69, .24), p(.88, .42) } },
		{ "poly", { p(.12, .76), p(.31, .58), p(.5, .76), p(.69, .58), p(.88, .76) } },
	} },
	Moon = { weight = 1.45, parts = {
		{ "arc", p(.54, .5), .32, 48, 312 },
	} },
	Coil = { weight = 1, parts = {
		{ "poly", { p(.18, .2), p(.82, .2), p(.82, .8), p(.3, .8), p(.3, .42), p(.62, .42), p(.62, .62) } },
	} },
	Ward = { weight = 1, parts = {
		{ "poly", { p(.5, .12), p(.5, .88) } },
		{ "poly", { p(.17, .31), p(.83, .69) } },
		{ "poly", { p(.17, .69), p(.83, .31) } },
	} },
	Anchor = { weight = 1, parts = {
		{ "dot", p(.5, .14), .08 },
		{ "poly", { p(.5, .2), p(.5, .82) } },
		{ "poly", { p(.3, .34), p(.7, .34) } },
		{ "arc", p(.5, .54), .3, 15, 165 },
	} },
}

local DEFAULT_THICKNESS = .085
local ARC_STEP_DEG = 15

local function addStroke(container, a, b, thickness, zIndex)
	local delta = b - a
	local length = delta.Magnitude
	local stroke = Instance.new("Frame")
	stroke.Name = "Stroke"
	stroke.AnchorPoint = Vector2.new(.5, .5)
	stroke.Position = UDim2.fromScale((a.X + b.X) * .5, (a.Y + b.Y) * .5)
	-- Length + thickness so the rounded caps sit centred on each endpoint.
	stroke.Size = UDim2.fromScale(length + thickness, thickness)
	stroke.Rotation = math.deg(math.atan2(delta.Y, delta.X))
	stroke.BorderSizePixel = 0
	stroke.ZIndex = zIndex
	stroke:SetAttribute("RuneStroke", true)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(.5, 0)
	corner.Parent = stroke
	stroke.Parent = container
end

local function addDot(container, centre, radius, zIndex)
	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(.5, .5)
	dot.Position = UDim2.fromScale(centre.X, centre.Y)
	dot.Size = UDim2.fromScale(radius * 2, radius * 2)
	dot.BorderSizePixel = 0
	dot.ZIndex = zIndex
	dot:SetAttribute("RuneStroke", true)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(.5, 0)
	corner.Parent = dot
	dot.Parent = container
end

local function buildLayer(container, def, thickness, zIndex)
	for _, part in ipairs(def.parts) do
		local kind = part[1]
		if kind == "poly" then
			local points, closed = part[2], part[3]
			for i = 1, #points - 1 do addStroke(container, points[i], points[i + 1], thickness, zIndex) end
			if closed and #points > 2 then addStroke(container, points[#points], points[1], thickness, zIndex) end
		elseif kind == "arc" then
			local centre, radius, fromDeg, toDeg = part[2], part[3], part[4], part[5]
			local steps = math.max(2, math.ceil(math.abs(toDeg - fromDeg) / ARC_STEP_DEG))
			local last
			for i = 0, steps do
				local angle = math.rad(fromDeg + (toDeg - fromDeg) * i / steps)
				local point = centre + Vector2.new(math.cos(angle), math.sin(angle)) * radius
				if last then addStroke(container, last, point, thickness, zIndex) end
				last = point
			end
		elseif kind == "dot" then
			addDot(container, part[2], part[3], zIndex)
		end
	end
end

local function paint(layer, color, transparency)
	for _, child in ipairs(layer:GetChildren()) do
		if child:GetAttribute("RuneStroke") then
			child.BackgroundColor3 = color
			child.BackgroundTransparency = transparency
		end
	end
end

--[[
	Render(parent, runeId, style) -> Frame
	Fills `parent` with a centred square containing the rune. style (all optional):
		Color, Transparency, Thickness (fraction of the box), ZIndex,
		GlowColor, GlowTransparency (a thicker soft underlay; omit GlowColor for none)
]]
function RuneArt.Render(parent, runeId, style)
	style = style or {}
	local zIndex = style.ZIndex or 1
	local container = Instance.new("Frame")
	container.Name = "Rune_" .. tostring(runeId)
	container.AnchorPoint = Vector2.new(.5, .5)
	container.Position = UDim2.fromScale(.5, .5)
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.ZIndex = zIndex
	container:SetAttribute("RuneId", runeId)
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = container

	local image = RuneArt.Images[runeId]
	if image then
		local label = Instance.new("ImageLabel")
		label.Name = "Image"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Image = image
		label.ImageColor3 = style.Color or Color3.new(1, 1, 1)
		label.ImageTransparency = style.Transparency or 0
		label.ZIndex = zIndex
		label.Parent = container
		container.Parent = parent
		return container
	end

	local def = RuneArt.Strokes[runeId]
	if not def then
		container.Parent = parent
		return container
	end
	local thickness = (style.Thickness or DEFAULT_THICKNESS) * (def.weight or 1)

	if style.GlowColor then
		local glow = Instance.new("Frame")
		glow.Name = "Glow"
		glow.Size = UDim2.fromScale(1, 1)
		glow.BackgroundTransparency = 1
		glow.ZIndex = zIndex
		glow.Parent = container
		buildLayer(glow, def, thickness * 2.1, zIndex)
		paint(glow, style.GlowColor, style.GlowTransparency or .7)
	end

	local ink = Instance.new("Frame")
	ink.Name = "Ink"
	ink.Size = UDim2.fromScale(1, 1)
	ink.BackgroundTransparency = 1
	ink.ZIndex = zIndex + 1
	ink.Parent = container
	buildLayer(ink, def, thickness, zIndex + 1)
	paint(ink, style.Color or Color3.new(1, 1, 1), style.Transparency or 0)

	container.Parent = parent
	return container
end

-- Recolours an already-rendered rune (ink, and glow when present).
function RuneArt.SetColor(container, color, transparency, glowColor, glowTransparency)
	if not container then return end
	local image = container:FindFirstChild("Image")
	if image then
		image.ImageColor3 = color
		image.ImageTransparency = transparency or 0
		return
	end
	local ink = container:FindFirstChild("Ink")
	if ink then paint(ink, color, transparency or 0) end
	local glow = container:FindFirstChild("Glow")
	if glow and glowColor then paint(glow, glowColor, glowTransparency or .7) end
end

return RuneArt
