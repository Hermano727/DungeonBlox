--[[
	HudBarStyle -- the look of every thin HUD bar: HP (HealthClient), energy (EnergyClient)
	and the skill XP bars (XpHud). One place, so they can't drift apart.

	Thin, Elden-Ring-like bars (2026-10-01): a dark trough, a 1 px tarnished-bronze hairline
	with a soft black edge outside it, an iron diamond on each end, and a muted fill with a
	slow-drifting grain texture (HudArt.BAR_GRAIN). Numbers sit beside the bar, not inside it.

	Imperative bars (HP, energy):
		HudBarStyle.Apply(trough, fill)                   -- once, after building the two frames
		HudBarStyle.PlaceReadout(trough, label, shadow?)  -- move a value label to the bar's right
		HudBarStyle.SideOffset(trough)                    -- px past the bar's end a side label starts
	React bars (XpHud), pass React.createElement as `e`:
		HudBarStyle.TroughElements(e, height, z, opts?)   -- children for the trough frame
		HudBarStyle.GrainElement(e, height, z)            -- the grain, a child of the fill frame
	Both:
		HudBarStyle.GradientFor(color)                    -- the fill's top-light/bottom-dark sheen

	Both paths build from the same specs (troughSpecs / grainSpec) below.
	ZIndex: the hairline and diamonds draw at `z`, which must sit above the fill (imperative
	bars: fill 3, damage chunk 4, frame 6, readout 7).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local HudArt = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images"):WaitForChild("HudArt"))

local HudBarStyle = {}

HudBarStyle.TROUGH = Color3.fromRGB(12, 10, 9)
HudBarStyle.BRONZE = Color3.fromRGB(138, 113, 70)
HudBarStyle.IRON = Color3.fromRGB(46, 39, 31)
HudBarStyle.BONE = Color3.fromRGB(232, 222, 204)
HudBarStyle.DISC = Color3.fromRGB(30, 22, 15) -- a medallion's dark centre (XP bar, elite plate)
HudBarStyle.TROUGH_TRANSPARENCY = 0.15

local GRAIN_TEXTURE_ASPECT = 8 -- bar_grain.png is 256x32
local GRAIN_DRIFT_SECONDS = 9 -- one tile's width of drift
local GRAIN_STRIP_WIDTH = 2400 -- wider than any bar, so the drifting strip never runs out
local READOUT_GAP = 6 -- px between a diamond's tip and a side label

type Spec = { Class: string, Name: string, Props: { [string]: any }, Children: { Spec }? }

-- The diamond: a square a touch taller than the bar, centred on the bar's end.
local function diamondSize(height: number): number
	return height + 1
end

local function troughSpecs(height: number, z: number, opts: { noLeftCap: boolean? }?): { Spec }
	local specs: { Spec } = {
		-- Soft black edge outside the bronze line, so the bar holds against a bright sky.
		{ Class = "UIStroke", Name = "Shadow", Props = { Color = Color3.new(0, 0, 0), Transparency = 0.45, Thickness = 2 } },
		-- The bronze hairline lives on its own frame so it draws above the fill.
		{
			Class = "Frame",
			Name = "Hairline",
			Props = { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = z },
			Children = { { Class = "UIStroke", Name = "Line", Props = { Color = HudBarStyle.BRONZE, Thickness = 1 } } },
		},
	}
	local size = diamondSize(height)
	for _, side in ipairs({ -1, 1 }) do
		if not (side < 0 and opts and opts.noLeftCap) then
			table.insert(specs, {
				Class = "Frame",
				Name = side < 0 and "CapLeft" or "CapRight",
				Props = {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(side < 0 and 0 or 1, 0.5),
					Size = UDim2.fromOffset(size, size),
					Rotation = 45,
					BackgroundColor3 = HudBarStyle.IRON,
					BorderSizePixel = 0,
					ZIndex = z,
				},
				Children = { { Class = "UIStroke", Name = "Edge", Props = { Color = HudBarStyle.BRONZE, Thickness = 1 } } },
			})
		end
	end
	return specs
end

-- Grain: a long tiled strip pinned to the bar's left edge and clipped by the fill
-- (ClipsDescendants), so the texture stays put (never squashes) as the fill shrinks.
local function grainSpec(height: number, z: number): Spec
	return {
		Class = "ImageLabel",
		Name = "Grain",
		Props = {
			BackgroundTransparency = 1,
			Image = HudArt.BAR_GRAIN,
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.fromOffset(math.max(height, 1) * GRAIN_TEXTURE_ASPECT, height),
			Size = UDim2.fromOffset(GRAIN_STRIP_WIDTH, height),
			ZIndex = z,
		},
	}
end

-- Slow sideways drift, like liquid. Once per instance (React may hand the same one over again).
local function startDrift(grain: ImageLabel)
	if grain:GetAttribute("Drifting") then return end
	grain:SetAttribute("Drifting", true)
	TweenService:Create(
		grain,
		TweenInfo.new(GRAIN_DRIFT_SECONDS, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
		{ Position = UDim2.fromOffset(-grain.TileSize.X.Offset, 0) }
	):Play()
end

local function build(spec: Spec, parent: Instance): Instance
	local inst = Instance.new(spec.Class)
	inst.Name = spec.Name
	for key, value in pairs(spec.Props) do
		(inst :: any)[key] = value
	end
	for _, child in ipairs(spec.Children or {}) do
		build(child, inst)
	end
	inst.Parent = parent
	return inst
end

local function toElement(e: any, spec: Spec): any
	local children
	if spec.Children then
		children = {}
		for _, child in ipairs(spec.Children) do
			children[child.Name] = toElement(e, child)
		end
	end
	return e(spec.Class, spec.Props, children)
end

function HudBarStyle.GradientFor(color: Color3): ColorSequence
	local function shift(amount)
		return Color3.new(
			math.clamp(color.R + amount, 0, 1),
			math.clamp(color.G + amount, 0, 1),
			math.clamp(color.B + amount, 0, 1)
		)
	end
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, shift(0.14)),
		ColorSequenceKeypoint.new(0.3, color),
		ColorSequenceKeypoint.new(1, shift(-0.16)),
	})
end

--------------------------------------------------------------------------------
-- Imperative bars
--------------------------------------------------------------------------------

function HudBarStyle.Apply(trough: Frame, fill: Frame)
	local height = trough.Size.Y.Offset
	for _, object in ipairs({ trough, fill }) do
		for _, child in ipairs(object:GetChildren()) do
			if child:IsA("UICorner") or child:IsA("UIStroke") then
				child:Destroy()
			end
		end
	end
	trough.BackgroundColor3 = HudBarStyle.TROUGH
	trough.BackgroundTransparency = HudBarStyle.TROUGH_TRANSPARENCY
	trough.BorderSizePixel = 0
	for _, spec in ipairs(troughSpecs(height, 6)) do
		build(spec, trough)
	end
	fill.ClipsDescendants = true
	if HudArt.BAR_GRAIN ~= "" then
		startDrift(build(grainSpec(height, fill.ZIndex), fill) :: ImageLabel)
	end
end

-- Offset from the bar's end at which a side label (the number, "Panting...") may start.
function HudBarStyle.SideOffset(trough: Frame): number
	return diamondSize(trough.Size.Y.Offset) * 0.71 + READOUT_GAP -- 0.71: half the rotated square's diagonal
end

-- Moves a value label (and its drop-shadow clone) just past the bar's right diamond.
function HudBarStyle.PlaceReadout(trough: Frame, label: TextLabel, shadow: TextLabel?)
	local x = HudBarStyle.SideOffset(trough)
	for i, item in ipairs({ label, shadow }) do
		if item then
			item.AnchorPoint = Vector2.new(0, 0.5)
			item.Position = UDim2.new(1, x + (i == 2 and 1 or 0), 0.5, i == 2 and 1 or 0)
			item.Size = UDim2.fromOffset(120, 16)
			item.TextSize = 13
			item.TextXAlignment = Enum.TextXAlignment.Left
		end
	end
	label.TextColor3 = HudBarStyle.BONE
	label.TextStrokeColor3 = Color3.fromRGB(14, 10, 8)
	label.TextStrokeTransparency = 0.35
end

--------------------------------------------------------------------------------
-- React bars. The trough frame itself takes TROUGH / TROUGH_TRANSPARENCY, BorderSizePixel 0;
-- the fill frame takes ClipsDescendants = true.
--------------------------------------------------------------------------------

function HudBarStyle.TroughElements(e: any, height: number, z: number, opts: { noLeftCap: boolean? }?): { [string]: any }
	local out = {}
	for _, spec in ipairs(troughSpecs(height, z, opts)) do
		out[spec.Name] = toElement(e, spec)
	end
	return out
end

function HudBarStyle.GrainElement(e: any, height: number, z: number): any
	if HudArt.BAR_GRAIN == "" then return nil end
	local spec = grainSpec(height, z)
	spec.Props.ref = function(inst: ImageLabel?)
		if inst then startDrift(inst) end
	end
	return toElement(e, spec)
end

return HudBarStyle
