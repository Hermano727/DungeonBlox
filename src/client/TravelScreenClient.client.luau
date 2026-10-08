--[[
	TravelScreenClient

	The screen that covers a hearthstone jump (GameEvents/TravelScreen from HearthstoneService):
	the loading screen's painting, the destination's name, a slowly filling bar and drifting
	leaves, faded in before the move and out once the destination has streamed in.
	Art is the loading screen's own registry (ReplicatedFirst/LoadingScreen/LoadingArt).

	Also lights a hearthstone totem up when you attune to it (GameEvents/HearthTotemLit).
]]

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local SfxService = require(ReplicatedStorage:WaitForChild("SfxService"))
local CenterFlashUI = require(script.Parent:WaitForChild("CenterFlashUI"))

local player = Players.LocalPlayer
local Art = require(ReplicatedFirst:WaitForChild("LoadingScreen"):WaitForChild("LoadingArt"))

local FONT = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold)
local BONE = Color3.fromRGB(236, 226, 208)
local INK = Color3.fromRGB(26, 18, 12)
local FADE = 0.5
local BAR_W, BAR_H = 420, 34

local function make(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do inst[k] = v end
	inst.Parent = parent
	return inst
end

-- Built once, kept hidden. A CanvasGroup so the whole thing fades as one.
local gui = make("ScreenGui", {
	Name = "TravelScreen", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 9000, Enabled = false,
}, player:WaitForChild("PlayerGui"))
local root = make("CanvasGroup", {
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(14, 11, 18), BorderSizePixel = 0, GroupTransparency = 1,
}, gui)
local bg = Art.Background
local painting = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1,
}, root)
make("ImageLabel", {
	Size = UDim2.new(bg.Split, 1, 1, 0), BackgroundTransparency = 1, Image = bg.Left, ScaleType = Enum.ScaleType.Stretch,
}, painting)
make("ImageLabel", {
	Position = UDim2.fromScale(bg.Split, 0), Size = UDim2.fromScale(1 - bg.Split, 1), BackgroundTransparency = 1,
	Image = bg.Right, ScaleType = Enum.ScaleType.Stretch,
}, painting)
local shade = make("Frame", {
	AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0.42),
	BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0,
}, root)
make("UIGradient", {
	Rotation = 90,
	Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.25) }),
}, shade)
local title = make("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -110), Size = UDim2.fromOffset(600, 48),
	BackgroundTransparency = 1, FontFace = FONT, TextSize = 36, TextColor3 = BONE, Text = "",
}, root)
make("UIStroke", { Color = INK, Thickness = 2, Transparency = 0.2 }, title)
local bar = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -60), Size = UDim2.fromOffset(BAR_W, BAR_H),
	BackgroundTransparency = 1,
}, root)
local frameArt = Art.BarFrame.Image ~= "" and Art.BarFrame or Art.BarFrameFallback
local inset = frameArt.FillInset
local fillHost = make("Frame", {
	Position = UDim2.fromOffset(inset.X, inset.Y), Size = UDim2.new(1, -inset.X * 2, 1, -inset.Y * 2),
	BackgroundColor3 = Color3.fromRGB(20, 14, 10), BackgroundTransparency = 0.2, BorderSizePixel = 0, ClipsDescendants = true,
}, bar)
local fill = make("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, fillHost)
make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 232, 160), Color3.fromRGB(200, 138, 58)) }, fill)
make("ImageLabel", {
	Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = frameArt.Image, ScaleType = Enum.ScaleType.Slice,
	SliceCenter = frameArt.SliceCenter, SliceScale = frameArt.SliceScale, ZIndex = 2,
}, bar)

local function fit()
	local camera = workspace.CurrentCamera
	local vp = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local w, h = vp.X, vp.X / bg.Aspect
	if h < vp.Y then w, h = vp.Y * bg.Aspect, vp.Y end
	painting.Size = UDim2.fromOffset(math.ceil(w) + 2, math.ceil(h) + 2)
end

local token = 0
local fillConn

local function show(name)
	token += 1
	fit()
	title.Text = (type(name) == "string" and name ~= "") and ("Travelling to " .. name) or "Travelling"
	fill.Size = UDim2.fromScale(0, 1)
	gui.Enabled = true
	TweenService:Create(root, TweenInfo.new(FADE), { GroupTransparency = 0 }):Play()
	-- The bar creeps toward full while the destination loads; hide() snaps it the rest of the way.
	if fillConn then fillConn:Disconnect() end
	local started = os.clock()
	fillConn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		fill.Size = UDim2.fromScale(0.9 * (1 - math.exp(-t * 1.2)), 1)
	end)
end

local function hide()
	token += 1
	local mine = token
	if fillConn then fillConn:Disconnect(); fillConn = nil end
	TweenService:Create(fill, TweenInfo.new(0.2), { Size = UDim2.fromScale(1, 1) }):Play()
	task.wait(0.25)
	if mine ~= token then return end
	local fade = TweenService:Create(root, TweenInfo.new(FADE), { GroupTransparency = 1 })
	fade:Play()
	fade.Completed:Wait()
	if mine == token then gui.Enabled = false end
end

local events = ReplicatedStorage:WaitForChild("GameEvents")
events:WaitForChild("TravelScreen").OnClientEvent:Connect(function(data)
	if type(data) ~= "table" then return end
	if data.phase == "show" then
		show(data.name)
	elseif data.phase == "hide" then
		task.spawn(hide)
	end
end)
-- Safety: never leave it up past a respawn.
player.CharacterAdded:Connect(function()
	if gui.Enabled then task.spawn(hide) end
end)

---------------------------------------------------------------------------
-- A totem lighting up when you attune to it
---------------------------------------------------------------------------

local GLOW = Color3.fromRGB(120, 200, 255)

events:WaitForChild("HearthTotemLit").OnClientEvent:Connect(function(totem, first)
	if typeof(totem) ~= "Instance" or not totem.Parent then return end
	local part = totem:IsA("BasePart") and totem or totem:FindFirstChildWhichIsA("BasePart", true)
	if part and not part:FindFirstChild("TotemGlow") then
		local light = make("PointLight", { Name = "TotemGlow", Color = GLOW, Range = 0, Brightness = 2.5, Shadows = false }, part)
		TweenService:Create(light, TweenInfo.new(1.2), { Range = 18 }):Play()
		local highlight = make("Highlight", {
			Name = "TotemGlow", FillColor = GLOW, OutlineColor = GLOW, FillTransparency = 1, OutlineTransparency = 1,
			DepthMode = Enum.HighlightDepthMode.Occluded, Adornee = totem,
		}, totem)
		TweenService:Create(highlight, TweenInfo.new(1.2), { FillTransparency = 0.75, OutlineTransparency = 0.3 }):Play()
	end
	SfxService.PlayEffect("EnchantSuccess")
	if first then
		CenterFlashUI.Show("Hearthstone attuned. Open your Journal to use it.")
	end
end)
