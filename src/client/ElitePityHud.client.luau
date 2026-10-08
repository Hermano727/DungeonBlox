--[[
	ElitePityHud -- the named-elite "omen" plate, top-centre, shown only in an elite zone while
	its elite hasn't spawned: how close your kills have brought it.

	        KANE THE ENRAGED                 42 / 100
	  (skull)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━◆

	Built from the HUD kit (2026-10-01, was a bespoke plate inside HealthClient): the same thin
	bar as HP / energy / XP (RS/HudBarStyle) with a violet fill, and the same dark-disc medallion
	as the combat XP bar, holding the skull. Every kill that moves the count thumps the skull and
	swells a violet light in the disc.

	It reserves its strip in RS/HudTopCentre, so the combat XP bar sits below it instead of on
	top of it. Its own ScreenGui, untagged: it hides behind menus like the rest of the HUD.

	Attributes (set by SSS/MobManager): IsInEliteZone, EliteActive, EliteSpawnLocked,
	ElitePityKills, ElitePityMax, CurrentEliteMobId.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local HudBarStyle = require(ReplicatedStorage:WaitForChild("HudBarStyle"))
local HudTopCentre = require(ReplicatedStorage:WaitForChild("HudTopCentre"))
local MobData = require(ReplicatedStorage:WaitForChild("MobData"))
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local Assets = ReplicatedStorage:WaitForChild("Assets")
local HudArt = require(Assets:WaitForChild("Images"):WaitForChild("HudArt"))
local HudIcons = require(Assets:WaitForChild("Icons"):WaitForChild("Hud"):WaitForChild("HudIcons"))

local player = Players.LocalPlayer

local TOP = 10        -- px from the top of the screen
local WIDTH = 300
local TITLE_H = 22
local BAR_Y = TITLE_H + 8
local BAR_H = 8
local DISC = 38       -- the skull medallion, centred on the bar's left end
local TITLE_INSET = DISC / 2 + 8
local HEIGHT = BAR_Y + BAR_H / 2 + DISC / 2 -- down to the disc's bottom edge

-- A bright violet (2026-10-02, was blood red): reads against grass, sky and stone alike.
local FILL = Color3.fromRGB(150, 72, 222)
local FILL_LIGHT = Color3.fromRGB(196, 130, 255) -- the disc's pulse
local BONE = HudBarStyle.BONE
local MUTED = Color3.fromRGB(196, 184, 162)
local STROKE = Color3.fromRGB(14, 10, 8)
local FILL_TWEEN = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local gui = Instance.new("ScreenGui")
gui.Name = "ElitePityGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 110
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

-- Shifted right by a quarter of the disc so the whole group (the disc hangs half its width
-- left of the bar) reads centred.
local frame = Instance.new("Frame")
frame.Name = "ElitePityFrame"
frame.AnchorPoint = Vector2.new(0.5, 0)
frame.Position = UDim2.new(0.5, DISC / 4, 0, TOP)
frame.Size = UDim2.fromOffset(WIDTH, HEIGHT)
frame.BackgroundTransparency = 1
frame.Visible = false
frame.Parent = gui

local function label(name: string, font: Font, size: number, color: Color3, align: Enum.TextXAlignment): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.BackgroundTransparency = 1
	text.FontFace = font
	text.TextSize = size
	text.TextColor3 = color
	text.TextStrokeColor3 = STROKE
	text.TextStrokeTransparency = 0.35
	text.TextXAlignment = align
	text.TextYAlignment = Enum.TextYAlignment.Bottom
	text.Parent = frame
	return text
end

local title = label("EliteName", UIFonts.SerifBold, 17, BONE, Enum.TextXAlignment.Left)
title.Position = UDim2.fromOffset(TITLE_INSET, 0)
title.Size = UDim2.new(1, -TITLE_INSET, 0, TITLE_H)

local count = label("Count", UIFonts.HUDLabel, 13, MUTED, Enum.TextXAlignment.Right)
count.Size = UDim2.new(1, 0, 0, TITLE_H)

-- The bar: HudBarStyle trough + violet fill.
local trough = Instance.new("Frame")
trough.Name = "Progress"
trough.Position = UDim2.fromOffset(0, BAR_Y)
trough.Size = UDim2.new(1, 0, 0, BAR_H)
trough.ZIndex = 2
trough.Parent = frame
local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(0, 1)
fill.BackgroundColor3 = FILL
fill.BorderSizePixel = 0
fill.ZIndex = 3
fill.Parent = trough
local sheen = Instance.new("UIGradient")
sheen.Rotation = 90
sheen.Color = HudBarStyle.GradientFor(FILL)
sheen.Parent = fill
HudBarStyle.Apply(trough, fill)
local leftCap = trough:FindFirstChild("CapLeft")
if leftCap then leftCap:Destroy() end -- the medallion covers the left end

-- The medallion: a dark disc with a light inside it and the skull on top.
local medallion = Instance.new("Frame")
medallion.Name = "Medallion"
medallion.AnchorPoint = Vector2.new(0.5, 0.5)
medallion.Position = UDim2.fromOffset(0, BAR_Y + BAR_H / 2)
medallion.Size = UDim2.fromOffset(DISC, DISC)
medallion.BackgroundColor3 = HudBarStyle.DISC
medallion.BorderSizePixel = 0
medallion.ClipsDescendants = true
medallion.ZIndex = 5
medallion.Parent = frame
Instance.new("UICorner", medallion).CornerRadius = UDim.new(1, 0)
local ring = Instance.new("UIStroke")
ring.Color = HudBarStyle.BRONZE
ring.Thickness = 2
ring.Parent = medallion
local medallionScale = Instance.new("UIScale")
medallionScale.Parent = medallion

local light = Instance.new("ImageLabel")
light.Name = "Light"
light.AnchorPoint = Vector2.new(0.5, 0.5)
light.Position = UDim2.fromScale(0.5, 0.5)
light.Size = UDim2.fromScale(1.3, 1.3)
light.BackgroundTransparency = 1
light.Image = HudArt.GLOW_SOFT
light.ImageColor3 = FILL_LIGHT
light.ImageTransparency = 1
light.ZIndex = 1
light.Parent = medallion

local skull = Instance.new("ImageLabel")
skull.Name = "Skull"
skull.AnchorPoint = Vector2.new(0.5, 0.5)
skull.Position = UDim2.fromScale(0.5, 0.5)
skull.Size = UDim2.fromScale(0.66, 0.66)
skull.BackgroundTransparency = 1
skull.Image = HudIcons.SKULL
skull.ImageColor3 = BONE
skull.ScaleType = Enum.ScaleType.Fit
skull.ZIndex = 2
skull.Parent = medallion

-- A kill moved the count: the skull thumps and a violet light swells in the disc.
local function pulse()
	medallionScale.Scale = 1.25
	TweenService:Create(medallionScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	light.ImageTransparency = 0.1
	light.Size = UDim2.fromScale(1.6, 1.6)
	TweenService:Create(light, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		ImageTransparency = 1, Size = UDim2.fromScale(1.3, 1.3),
	}):Play()
end

local lastKills: number? = nil

local function refresh()
	-- Only the pre-spawn "omen". Once the elite is up its boss bar takes over
	-- (BossHealthBar), and while any named elite is alive server-wide (EliteSpawnLocked) the
	-- count is frozen, so a bar would be lying.
	local show = player:GetAttribute("IsInEliteZone") == true
		and player:GetAttribute("EliteActive") ~= true
		and player:GetAttribute("EliteSpawnLocked") ~= true
	frame.Visible = show
	HudTopCentre.Reserve("ElitePity", show and (TOP + HEIGHT) or nil)
	if not show then
		lastKills = nil
		return
	end

	local max = math.max(1, tonumber(player:GetAttribute("ElitePityMax")) or 100)
	local kills = math.clamp(tonumber(player:GetAttribute("ElitePityKills")) or 0, 0, max)
	local name = "Elite"
	local mobId = player:GetAttribute("CurrentEliteMobId")
	if type(mobId) == "string" and mobId ~= "" then
		local mob = MobData.FindMobById(mobId)
		if type(mob) == "table" and type(mob.Name) == "string" and mob.Name ~= "" then
			name = mob.Name
		end
	end

	title.Text = string.upper(name)
	count.Text = string.format("%d / %d", kills, max)
	TweenService:Create(fill, FILL_TWEEN, { Size = UDim2.fromScale(kills / max, 1) }):Play()
	if lastKills and kills > lastKills then pulse() end
	lastKills = kills
end

for _, attribute in ipairs({
	"IsInEliteZone", "EliteActive", "EliteSpawnLocked", "ElitePityKills", "ElitePityMax", "CurrentEliteMobId",
}) do
	player:GetAttributeChangedSignal(attribute):Connect(refresh)
end
task.defer(refresh)
