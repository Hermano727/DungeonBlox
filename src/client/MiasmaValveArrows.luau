--[[
	MiasmaValveArrows -- "go here": a bouncing light-blue chevron over every active valve that
	still needs working (client only).

		Arrows.Show(gates, positions, parent)  -- "GatesAwaken": gate indices + matching positions
		Arrows.Hide(gateIndex)           -- that valve got primed
		Arrows.Clear()                   -- the cycle ended (stun, re-corruption, purge, end)
		Arrows.IsShowing()               -- any arrow up right now

	Drawn through walls (AlwaysOnTop) at a constant screen size, so it reads from anywhere in the
	arena. It fades out as you reach the valve (it has done its job and would only cover it).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Arrows = {}

local HEIGHT = 9             -- studs above the valve
local SIZE = 49              -- on-screen pixels (constant at any distance); 38 -> 49 (+30%, 2026-09-29)
local BOUNCE = 1             -- studs up and down
local BOUNCE_SPEED = 3.2
local FADE_NEAR, FADE_FAR = 9, 18 -- invisible within FADE_NEAR studs, full beyond FADE_FAR
local CYAN = Color3.fromRGB(96, 214, 255)
local CYAN_BRIGHT = Color3.fromRGB(205, 245, 255)

local arrows = {} -- [gateIndex] = { anchor, gui, parts }
local loop

local function chevron(parent, color, thickness, zIndex, transparency)
	-- Two bars meeting at the bottom: a "v" pointing DOWN at the valve (the tilts were swapped
	-- before 2026-09-29, which drew an upside-down "^").
	local parts = {}
	for _, side in ipairs({ -1, 1 }) do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(.5, .5)
		bar.Position = UDim2.fromScale(.5 + side * .17, .5)
		bar.Size = UDim2.new(0, thickness, .72, 0)
		bar.Rotation = side * 35
		bar.BackgroundColor3 = color
		bar.BackgroundTransparency = transparency or 0
		bar.BorderSizePixel = 0
		bar.ZIndex = zIndex
		bar.Parent = parent
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = bar
		table.insert(parts, bar)
	end
	return parts
end

local function build(position, parent)
	local anchor = Instance.new("Part")
	anchor.Name = "ValveArrowAnchor"
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(.2, .2, .2)
	anchor.CFrame = CFrame.new(position + Vector3.new(0, HEIGHT, 0))
	anchor.Parent = parent

	local gui = Instance.new("BillboardGui")
	gui.Name = "ValveArrow"
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Size = UDim2.fromOffset(SIZE, SIZE)
	gui.Adornee = anchor
	gui.Parent = anchor
	local root = Instance.new("CanvasGroup")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = gui
	-- Soft glow behind, then the crisp chevron, then a bright core line.
	chevron(root, CYAN, 11, 1, .7)
	chevron(root, CYAN, 6, 2, 0)
	chevron(root, CYAN_BRIGHT, 2, 3, 0)
	return { anchor = anchor, gui = gui, root = root, base = position + Vector3.new(0, HEIGHT, 0), phase = math.random() * 6.28 }
end

local function step()
	local t = os.clock()
	local character = Players.LocalPlayer.Character
	local me = character and character:FindFirstChild("HumanoidRootPart")
	for _, a in pairs(arrows) do
		local y = math.abs(math.sin(t * BOUNCE_SPEED + a.phase)) * BOUNCE
		a.anchor.CFrame = CFrame.new(a.base + Vector3.new(0, y, 0))
		local fade = 1
		if me then
			local d = (Vector3.new(a.base.X, 0, a.base.Z) - Vector3.new(me.Position.X, 0, me.Position.Z)).Magnitude
			fade = math.clamp((d - FADE_NEAR) / (FADE_FAR - FADE_NEAR), 0, 1)
		end
		a.root.GroupTransparency = 1 - fade
	end
end

-- True while any valve arrow is up (a gate cycle is asking for valves). Other world markers
-- (client/PoisonIndicators) stand back while this is on, so the screen isn't crowded.
function Arrows.IsShowing()
	return next(arrows) ~= nil
end

function Arrows.Hide(index)
	local a = arrows[index]
	if not a then return end
	arrows[index] = nil
	a.anchor:Destroy()
	if next(arrows) == nil and loop then loop:Disconnect(); loop = nil end
end

function Arrows.Clear()
	for index in pairs(arrows) do Arrows.Hide(index) end
end

function Arrows.Show(gates, positions, parent)
	Arrows.Clear()
	if type(gates) ~= "table" or type(positions) ~= "table" then return end
	for i, index in ipairs(gates) do
		local position = positions[i]
		if typeof(position) == "Vector3" then arrows[index] = build(position, parent or Workspace) end
	end
	if next(arrows) and not loop then loop = RunService.RenderStepped:Connect(step) end
end

return Arrows
