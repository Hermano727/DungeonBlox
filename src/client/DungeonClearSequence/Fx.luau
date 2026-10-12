--[[
	Fx -- small building blocks shared by the clear sequence's stages (see init.client.luau).

	Everything here is client-local and code-built (docs/vfx-pipeline.md: no shaders; streaks
	from Beams/Trails/Particles, solid things from parts or uploaded meshes). Stages compute
	their look from `t` (seconds since the show's server start), so these helpers are plain
	setters, never tweens: a tween would drift from the shared clock.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("ProfileTypes"))
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local SfxService = require(ReplicatedStorage:WaitForChild("SfxService"))
local WorldVfx = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images"):WaitForChild("WorldVfx"))
local ClearArt = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images"):WaitForChild("ClearSequenceArt"))

local Fx = {}

-- Textures. ClearSequenceArt entries are the bespoke art (asset requests); each falls back to
-- a bundled Roblox particle or an existing WorldVfx texture until it exists.
local function art(key, fallback)
	local id = ClearArt[key]
	return (type(id) == "string" and id ~= "") and id or fallback
end
Fx.TEX = {
	Sparkle = art("SPARKLE", "rbxasset://textures/particles/sparkles_main.dds"),
	Fire = art("FIRE", "rbxasset://textures/particles/fire_main.dds"),
	Smoke = art("SMOKE", WorldVfx.SMOKE_PUFF_4X4),
	Spark = WorldVfx.SPARK,
	ShockRing = WorldVfx.SHOCK_RING,
	Feather = art("FEATHER", ""),       -- a feather strip for the wing Beams ("" = solid band)
	LightShaft = art("LIGHT_SHAFT", ""), -- the god-ray gradient on the shaft Beams
	Ember = art("EMBER", WorldVfx.SPARK),
	ShroudBurn = art("SHROUD_BURN", ""), -- burning cloth scraps ("" = the shroud just burns with fire)
}
Fx.SMOKE_IS_FLIPBOOK = (Fx.TEX.Smoke == WorldVfx.SMOKE_PUFF_4X4)
-- Textures that are 4x4 flipbooks (docs/dungeon-clear-asset-requests.md): an emitter using one
-- gets FlipbookLayout Grid4x4 + FlipbookMode Random automatically. The bundled fallbacks aren't.
local FLIPBOOKS = {}
if Fx.TEX.Fire ~= "rbxasset://textures/particles/fire_main.dds" then FLIPBOOKS[Fx.TEX.Fire] = true end
if Fx.TEX.ShroudBurn ~= "" then FLIPBOOKS[Fx.TEX.ShroudBurn] = true end

Fx.GOLD = Color3.fromRGB(255, 214, 140)
Fx.PALE = Color3.fromRGB(255, 244, 214)
Fx.IRON = Color3.fromRGB(46, 42, 40)
Fx.ASH = Color3.fromRGB(120, 116, 112)
Fx.FIRE = Color3.fromRGB(255, 140, 50)
Fx.INK = Color3.fromRGB(20, 16, 14)

-- Where hidden pieces wait (far ABOVE the map: anything below FallenPartsDestroyHeight could be
-- culled, and the realms are parked far along X, so nothing is up here).
Fx.HIDDEN = CFrame.new(0, 1e5, 0)

function Fx.rarityColor(rarity)
	return Types.GetRarityColor(rarity)
end

----------------------------------------------------------------------
-- Maths
----------------------------------------------------------------------

function Fx.clamp01(x)
	return math.clamp(x, 0, 1)
end

-- 0 before a, 1 after b, linear between.
function Fx.alpha(t, a, b)
	if b <= a then return t >= a and 1 or 0 end
	return math.clamp((t - a) / (b - a), 0, 1)
end

function Fx.outCubic(x) return 1 - (1 - x) ^ 3 end
function Fx.inCubic(x) return x ^ 3 end
function Fx.inOutSine(x) return -(math.cos(math.pi * x) - 1) / 2 end
function Fx.outBack(x)
	local c1, c3 = 1.70158, 2.70158
	return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

function Fx.lerp(a, b, x) return a + (b - a) * x end

-- Deterministic per-index noise in [0, 1): the same jitter on every client.
function Fx.hash(n)
	local x = math.sin(n * 12.9898 + 78.233) * 43758.5453
	return x - math.floor(x)
end

----------------------------------------------------------------------
-- Instances
----------------------------------------------------------------------

function Fx.part(parent, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props or {}) do p[k] = v end
	p.Parent = parent
	return p
end

function Fx.attachment(parent, position)
	local a = Instance.new("Attachment")
	if position then a.Position = position end
	a.Parent = parent
	return a
end

function Fx.make(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props or {}) do inst[k] = v end
	inst.Parent = parent
	return inst
end

function Fx.light(parent, color, range, brightness)
	return Fx.make("PointLight", { Color = color, Range = range or 16, Brightness = brightness or 1, Shadows = false }, parent)
end

-- A glowing particle emitter: LightEmission 1, no world lighting on it.
function Fx.emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Rate = 0
	e.Texture = Fx.TEX.Sparkle
	for k, v in pairs(props or {}) do e[k] = v end
	if FLIPBOOKS[e.Texture] then
		e.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
		e.FlipbookMode = Enum.ParticleFlipbookMode.Random
	end
	e.Parent = parent
	return e
end

function Fx.smoke(parent, props)
	local e = Fx.emitter(parent, props)
	e.Texture = Fx.TEX.Smoke
	e.LightEmission = 0
	e.LightInfluence = 1
	if Fx.SMOKE_IS_FLIPBOOK then
		e.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
		e.FlipbookMode = Enum.ParticleFlipbookMode.Random
	end
	return e
end

-- A soft glowing Beam between two attachments.
function Fx.beam(parent, a0, a1, props)
	local b = Instance.new("Beam")
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.LightEmission = 1
	b.LightInfluence = 0
	b.FaceCamera = true
	b.Segments = 12
	for k, v in pairs(props or {}) do b[k] = v end
	b.Parent = parent
	return b
end

function Fx.seq(a, b)
	return NumberSequence.new(a, b)
end

-- Uploaded VFX model (RS.VfxModels, loaded by SSS/VfxModelLoader) or nil.
function Fx.vfxModel(key)
	local folder = ReplicatedStorage:FindFirstChild("VfxModels")
	local source = folder and folder:FindFirstChild(key)
	return source and source:Clone() or nil
end

-- A loot display prefab (ServerStorage.LootDropVisuals, mirrored by WorldLootService) or nil.
function Fx.lootPrefab(name)
	if type(name) ~= "string" then return nil end
	local folder = ReplicatedStorage:FindFirstChild("LootDisplayPrefabs")
	local source = folder and folder:FindFirstChild(name)
	if not source then return nil end
	local clone = source:Clone()
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false end
	end
	if clone:IsA("BasePart") then clone.Anchored = true; clone.CanCollide = false; clone.CanQuery = false; clone.CanTouch = false end
	return clone
end

-- Moves a part or model.
function Fx.place(inst, cf)
	if inst:IsA("BasePart") then inst.CFrame = cf else inst:PivotTo(cf) end
end

-- Sets a part's / model's transparency (a model's parts keep their relative base values).
function Fx.fade(inst, transparency)
	if inst:IsA("BasePart") then
		local base = inst:GetAttribute("BaseTransparency")
		if base == nil then base = inst.Transparency; inst:SetAttribute("BaseTransparency", base) end
		inst.Transparency = base + (1 - base) * transparency
		return
	end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then Fx.fade(d, transparency) end
	end
end

----------------------------------------------------------------------
-- Billboard plaques (the NpcNametags pattern: in PlayerGui, Adornee'd to a part)
----------------------------------------------------------------------

function Fx.plaque(adornee, props)
	props = props or {}
	local gui = Instance.new("BillboardGui")
	gui.Name = "ClearSequencePlaque"
	gui.Adornee = adornee
	gui.AlwaysOnTop = props.alwaysOnTop == true
	gui.LightInfluence = 0
	gui.MaxDistance = props.maxDistance or 400
	gui.Size = props.size or UDim2.fromOffset(260, 64)
	gui.StudsOffsetWorldSpace = props.offset or Vector3.zero
	gui.ResetOnSpawn = false
	local lines = {}
	for index, line in ipairs(props.lines or {}) do
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, line.height or 0.5, 0)
		label.Position = UDim2.new(0, 0, line.y or (index - 1) * 0.5, 0)
		label.FontFace = line.font or UIFonts.SerifBold
		label.TextScaled = true
		label.TextColor3 = line.color or Fx.PALE
		label.Text = line.text or ""
		local stroke = Instance.new("UIStroke")
		stroke.Color = Fx.INK
		stroke.Thickness = line.stroke or 2
		stroke.Parent = label
		label.Parent = gui
		lines[index] = label
	end
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return gui, lines
end

-- Fades every label (and its stroke) of a plaque.
function Fx.fadePlaque(gui, transparency)
	for _, label in ipairs(gui:GetChildren()) do
		if label:IsA("TextLabel") then
			label.TextTransparency = transparency
			local stroke = label:FindFirstChildOfClass("UIStroke")
			if stroke then stroke.Transparency = transparency end
		end
	end
	gui.Enabled = transparency < 0.99
end

----------------------------------------------------------------------
-- One-shot moments on the shared clock
--
-- `once:at(key, when, t, fn)` fires fn the first frame t passes `when`, unless the frame is more
-- than `window` late (a late joiner skips past moments instead of replaying a stack of them).
----------------------------------------------------------------------

local Once = {}
Once.__index = Once

function Fx.Once()
	return setmetatable({ fired = {} }, Once)
end

function Once:at(key, when, t, fn, window)
	if self.fired[key] or t < when then return end
	self.fired[key] = true
	if t - when <= (window or 0.5) then fn() end
end

-- Positional one-shot (SoundEffects key; "" plays nothing until the asset exists).
function Fx.sound(key, position, volume, speed)
	SfxService.PlayEffect(key, {
		Position = position,
		Volume = volume or 0.8,
		PlaybackSpeed = speed,
		RollOffMinDistance = 40,
		RollOffMaxDistance = 400,
	})
end

return Fx
