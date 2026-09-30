--[[
	DamageNumberClient
	Server sends post-armor damage via DamageNumberEvent; we show a floating,
	arcing damage number above the target (mob or player character).

	Event payload: (amount, targetModel, maxHealth?, isCrit?, enchantFeedback?, source?)

	Behavior:
	1. Pop-in: transparency 1 -> 0 with a scale "pop" (Back easing overshoot).
	2. Black drop-shadow behind clean white text (a real offset shadow, not
	   just a stroke).
	3/5. Floats up in a short arc, then falls away past the start point and
	     fades out -- like it's thrown up and over, then drops.
	4. Fades out (opacity -> 0) as the sequence ends.
	6. Size scales with % of the target's max HP dealt in one hit -- see
	     SIZE_TIERS for the current bands and the measurements behind them.
	7. Crits show "CRITICAL" (orange) popping in with the crit number (yellow,
	     slight orange, sized the same way as (6)) at the same time, number
	     positioned just below the label -- then a quick white slash wipes the
	     "CRITICAL" label away while the number keeps floating on its own.
	     The crit SFX (SfxService "CriticalHit") fires the instant the server
	     confirms the crit, in DamageNumberEvent's handler -- decoupled from
	     this whole visual sequence, so it's never waiting on an animation.
	8. CPS-aware pacing: faster clicking speeds the whole sequence up (and
	     numbers are allowed to overlap); slower clicking relaxes the arc.
	9. Random left/right spread and drift, clamped to a sane range.
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local SfxService = require(ReplicatedStorage:WaitForChild("SfxService"))
local DamageNumberStyles = require(ReplicatedStorage:WaitForChild("DamageNumberStyles"))
local EnchantHitEffects = require(script.Parent:WaitForChild("EnchantHitEffects"))

local DamageNumberEvent = ReplicatedStorage:WaitForChild("DamageNumberEvent", 60)
if not DamageNumberEvent then
	warn("[DamageNumberClient] DamageNumberEvent missing after 60s")
	return
end

------------------------------------------------------------
-- Tunables
------------------------------------------------------------

local BASE_FLOAT_TIME = 0.55 -- baseline full lifetime of a number at "normal" CPS
local MIN_FLOAT_TIME = 0.32
local MAX_FLOAT_TIME = 0.85

local RISE_STUDS = 2.0 -- height of the initial upward arc
local FALL_STUDS = 3.4 -- how far it drops after the peak (further than the rise, so it ends below start)
local RISE_FRACTION = 0.28 -- portion of the lifetime spent rising

-- Crit number spawns this far below the "CRITICAL" label's own start point so
-- the two don't overlap while popping in together (see playCritSequence).
local CRIT_NUMBER_BELOW_LABEL_OFFSET = 1.1

-- Spread scales with the target's own footprint so a tiny slime doesn't get
-- console-wide scatter and a boss doesn't get numbers glued to its center.
local MIN_SPREAD = 1.4
local MAX_SPREAD = 5.0
local SPREAD_SIZE_FRACTION = 0.6 -- fraction of the model's half-width/depth used as spread radius
local DRIFT_MULT = 1.6 -- how much further a number drifts than its spawn spread, over its life

-- Base billboard footprint at sizeMult 1.0, in SCREEN PIXELS. A BillboardGui
-- sized purely in offset is a constant on-screen size with no distance falloff,
-- so this is the floor for every number in the game regardless of tier -- it was
-- 220x90, which made even the smallest tier a 72px-tall TextScaled number.
local BASE_GUI_WIDTH = 130
local BASE_GUI_HEIGHT = 54

local SHADOW_COLOR = Color3.fromRGB(0, 0, 0)
local CRIT_LABEL_COLOR = Color3.fromRGB(255, 140, 20) -- "CRITICAL" orange
local CRIT_NUMBER_COLOR = Color3.fromRGB(255, 205, 60) -- yellow, slight orange
local SLASH_COLOR = Color3.fromRGB(255, 255, 255)

-- Scaled by sizeMult at build time so the shadow stays proportional instead of
-- reading heavier the smaller the number gets.
local SHADOW_OFFSET = Vector2.new(3, 3)

-- Size tiers by % of target max HP dealt in this hit. Purely threshold-driven
-- so future rebalancing never needs new code, just new numbers here.
--
-- Calibrated 2026-09-18 against what a hit actually is. A tier-matched COMMON
-- weapon does 10-25% of a regular mob's max HP at every tier (T1 sword 7-9 vs
-- Plains Slime 40 HP; T4 ~122 vs 500-600; T5 ~250 vs 1200-2000). The old bands
-- assumed a normal hit was under 10%, so an ordinary swing rendered in the
-- "large" 2.5x band and the tiering communicated nothing. A normal hit is now
-- the visual baseline and only genuine burst damage gets big.
local SIZE_TIERS = {
	{ max = 0.08, mult = 0.60 }, -- chip: bleed ticks, cleave splash
	{ max = 0.22, mult = 0.85 }, -- a normal hit -- the common case
	{ max = 0.40, mult = 1.15 }, -- strong hit / crit
	{ max = 0.65, mult = 1.55 }, -- big hit
	{ max = math.huge, mult = 2.10 }, -- burst: two thirds of the bar in one blow
}

------------------------------------------------------------
-- CPS tracking (drives arc speed / feel)
------------------------------------------------------------

local recentHitTimes = {}
local MAX_TRACKED_HITS = 6

local function recordHitAndGetSpeedMult()
	local now = os.clock()
	table.insert(recentHitTimes, now)
	while #recentHitTimes > MAX_TRACKED_HITS do
		table.remove(recentHitTimes, 1)
	end

	if #recentHitTimes < 2 then
		return 1.0
	end

	local span = recentHitTimes[#recentHitTimes] - recentHitTimes[1]
	local intervals = #recentHitTimes - 1
	local avgInterval = span / intervals
	if avgInterval <= 0 then
		return 2.1
	end

	local cps = 1 / avgInterval
	-- ~2 cps reads as "normal" pacing (speedMult 1.0); faster clicking speeds
	-- the arc up so hits feel punchier, slower clicking relaxes it (but never
	-- crawls -- even a single slow hit should resolve quickly).
	local speedMult = cps / 2
	return math.clamp(speedMult, 0.8, 2.1)
end

------------------------------------------------------------
-- Helpers
------------------------------------------------------------

local function getSizeMult(amount, maxHealth)
	local pct
	if type(maxHealth) == "number" and maxHealth > 0 then
		pct = amount / maxHealth
	else
		-- No max HP given (shouldn't normally happen) -- fall back to a
		-- rough absolute-damage guess so numbers still scale sensibly.
		pct = amount / 150
	end

	for _, tier in ipairs(SIZE_TIERS) do
		if pct < tier.max then
			return tier.mult
		end
	end
	return SIZE_TIERS[#SIZE_TIERS].mult
end

-- Builds one BillboardGui with a colored main label and a black shadow
-- label offset behind it. Returns (gui, mainLabel, shadowLabel).
local function buildNumberGui(root, text, textColor, sizeMult, startOffset)
	local gui = Instance.new("BillboardGui")
	gui.Name = "DmgNum"
	gui.Size = UDim2.new(0, BASE_GUI_WIDTH * sizeMult, 0, BASE_GUI_HEIGHT * sizeMult)
	gui.StudsOffset = startOffset
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 120
	gui.Adornee = root
	gui.Parent = root

	local shadow = Instance.new("TextLabel")
	shadow.Name = "Shadow"
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.Position = UDim2.fromOffset(SHADOW_OFFSET.X * sizeMult, SHADOW_OFFSET.Y * sizeMult)
	shadow.BackgroundTransparency = 1
	shadow.FontFace = UIFonts.Damage
	shadow.TextScaled = true
	shadow.TextColor3 = SHADOW_COLOR
	shadow.TextTransparency = 1
	shadow.TextStrokeTransparency = 1
	shadow.ZIndex = 1
	shadow.Text = text
	shadow.Parent = gui

	local lbl = Instance.new("TextLabel")
	lbl.Name = "Main"
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.FontFace = UIFonts.Damage
	lbl.TextScaled = true
	lbl.TextColor3 = textColor
	lbl.TextStrokeTransparency = 1
	lbl.TextTransparency = 1
	lbl.ZIndex = 2
	lbl.Text = text
	lbl.Parent = gui

	return gui, lbl, shadow
end

-- Runs the pop-in -> arc -> fade sequence on an already-built gui/label/shadow.
local POP_SCALE_START = 0.4
local POP_SCALE_END   = 1.0

local function animateArcAndFade(gui, lbl, shadow, startOffset, duration, peakScale, driftRange)
	-- peakScale only sizes the BillboardGui itself (the tier system). The
	-- UIScale bounce below is a fixed cosmetic pop, NOT another multiply by
	-- peakScale -- otherwise tiers compound quadratically (see header note).
	local scale = Instance.new("UIScale")
	scale.Scale = POP_SCALE_START
	scale.Parent = lbl

	local shadowScale = Instance.new("UIScale")
	shadowScale.Scale = POP_SCALE_START
	shadowScale.Parent = shadow

	local popTime = math.min(0.10, duration * 0.22)
	local riseTime = duration * RISE_FRACTION
	local fallTime = duration - riseTime

	local driftDir = (startOffset.X >= 0) and 1 or -1
	local driftAmount = driftRange * (0.5 + math.random() * 0.5) * driftDir

	local peakOffset = startOffset + Vector3.new(driftAmount * 0.35, RISE_STUDS, 0)
	local endOffset = startOffset + Vector3.new(driftAmount, RISE_STUDS - FALL_STUDS, 0)

	-- Pop in: transparent -> visible, with a little overshoot scale punch.
	TweenService:Create(lbl, TweenInfo.new(popTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextTransparency = 0 }):Play()
	TweenService:Create(shadow, TweenInfo.new(popTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextTransparency = 0.25 }):Play()
	TweenService:Create(scale, TweenInfo.new(popTime * 1.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = POP_SCALE_END }):Play()
	TweenService:Create(shadowScale, TweenInfo.new(popTime * 1.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = POP_SCALE_END }):Play()

	-- Rise: thrown up, easing out as it slows near the peak.
	TweenService:Create(gui, TweenInfo.new(riseTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = peakOffset }):Play()

	-- Fall: arcs over and drops past the start point, fading out near the end.
	task.delay(riseTime, function()
		if not gui or not gui.Parent then
			return
		end
		TweenService:Create(gui, TweenInfo.new(fallTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { StudsOffset = endOffset }):Play()

		local fadeStart = fallTime * 0.35
		task.delay(fadeStart, function()
			if not lbl or not lbl.Parent then
				return
			end
			local fadeTime = fallTime - fadeStart
			TweenService:Create(lbl, TweenInfo.new(fadeTime, Enum.EasingStyle.Linear), { TextTransparency = 1 }):Play()
			TweenService:Create(shadow, TweenInfo.new(fadeTime, Enum.EasingStyle.Linear), { TextTransparency = 1 }):Play()
		end)
	end)

	task.delay(duration + 0.05, function()
		if gui and gui.Parent then
			gui:Destroy()
		end
	end)
end

-- Uses the target's actual bounding box so spread feels proportional --
-- a slime shouldn't scatter numbers as wide as a boss, and a boss shouldn't
-- have every number glued to one spot.
local function getSpreadForModel(model)
	local ok, _, size = pcall(function()
		return model:GetBoundingBox()
	end)
	if not ok or not size then
		return MIN_SPREAD, MIN_SPREAD
	end
	local sx = math.clamp(size.X * SPREAD_SIZE_FRACTION, MIN_SPREAD, MAX_SPREAD)
	local sz = math.clamp(size.Z * SPREAD_SIZE_FRACTION, MIN_SPREAD, MAX_SPREAD)
	return sx, sz
end

local function randomStartOffset(spreadX, spreadZ)
	local rx = (math.random() - 0.5) * 2 * spreadX
	local rz = (math.random() - 0.5) * 2 * spreadZ
	return Vector3.new(rx, 2.2, rz)
end

------------------------------------------------------------
-- Crit sequence: "CRITICAL" + crit number pop in together -> slash wipes
-- "CRITICAL" away, number keeps floating on its own arc
------------------------------------------------------------

local function playCritSequence(root, amt, sizeMult, startOffset, duration, speedMult, driftRange)
	local introSpeed = math.clamp(speedMult, 0.85, 1.8)
	local popTime = math.clamp(0.09 / introSpeed, 0.06, 0.13)
	local holdTime = math.clamp(0.16 / introSpeed, 0.10, 0.24)
	local slashTime = math.clamp(0.10 / introSpeed, 0.07, 0.14)

	local labelSize = sizeMult * 0.85
	local labelGui, labelMain, labelShadow = buildNumberGui(root, "CRITICAL", CRIT_LABEL_COLOR, labelSize, startOffset)

	-- Same fix as animateArcAndFade: labelSize already sizes the BillboardGui
	-- itself, so the pop bounce must NOT also target labelSize.
	local labelScale = Instance.new("UIScale")
	labelScale.Scale = POP_SCALE_START
	labelScale.Parent = labelMain
	local labelShadowScale = Instance.new("UIScale")
	labelShadowScale.Scale = POP_SCALE_START
	labelShadowScale.Parent = labelShadow

	TweenService:Create(labelMain, TweenInfo.new(popTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextTransparency = 0 }):Play()
	TweenService:Create(labelShadow, TweenInfo.new(popTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextTransparency = 0.25 }):Play()
	TweenService:Create(labelScale, TweenInfo.new(popTime * 1.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = POP_SCALE_END }):Play()
	TweenService:Create(labelShadowScale, TweenInfo.new(popTime * 1.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = POP_SCALE_END }):Play()

	-- Crit number now pops in immediately alongside "CRITICAL" (same moment,
	-- not after the slash finishes), positioned just below the label so the
	-- two don't overlap. Uses the normal arc/fade sequence, same as a
	-- non-crit number.
	local numberStartOffset = startOffset - Vector3.new(0, CRIT_NUMBER_BELOW_LABEL_OFFSET, 0)
	local numGui, numLbl, numShadow = buildNumberGui(root, tostring(amt), CRIT_NUMBER_COLOR, sizeMult, numberStartOffset)
	animateArcAndFade(numGui, numLbl, numShadow, numberStartOffset, duration, sizeMult, driftRange)

	task.delay(popTime + holdTime, function()
		if not labelGui or not labelGui.Parent then
			return
		end

		-- Slash: a thin white bar that sweeps across the "CRITICAL" text.
		local slashGui = Instance.new("BillboardGui")
		slashGui.Name = "CritSlash"
		slashGui.Size = labelGui.Size
		slashGui.StudsOffset = labelGui.StudsOffset
		slashGui.AlwaysOnTop = true
		slashGui.LightInfluence = 0
		slashGui.MaxDistance = 120
		slashGui.Adornee = root
		slashGui.Parent = root

		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.new(0, 0, 0, 6 * labelSize)
		bar.Rotation = -18
		bar.BackgroundColor3 = SLASH_COLOR
		bar.BorderSizePixel = 0
		bar.Parent = slashGui

		TweenService:Create(bar, TweenInfo.new(slashTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.new(1.15, 0, 0, 6 * labelSize) }):Play()
		TweenService:Create(labelMain, TweenInfo.new(slashTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 }):Play()
		TweenService:Create(labelShadow, TweenInfo.new(slashTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 }):Play()

		task.delay(slashTime + 0.05, function()
			if bar and bar.Parent then
				TweenService:Create(bar, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 }):Play()
			end
			task.delay(0.14, function()
				if slashGui then slashGui:Destroy() end
				if labelGui then labelGui:Destroy() end
			end)
		end)
	end)
end

------------------------------------------------------------
-- Event handler
------------------------------------------------------------

DamageNumberEvent.OnClientEvent:Connect(function(damage, targetModel, maxHealth, isCrit, enchantFeedback, source)
	local amt = math.floor(tonumber(damage) or 0)
	if amt <= 0 then
		return
	end
	-- Saved world-space feedback still plays if a killing blow removed the model.
	EnchantHitEffects.PlayHit(enchantFeedback, targetModel)
	if typeof(targetModel) ~= "Instance" or not targetModel:IsA("Model") then
		return
	end

	local root = targetModel:FindFirstChild("HumanoidRootPart")
		or targetModel.PrimaryPart
		or targetModel:FindFirstChildWhichIsA("BasePart")
	if not root then
		return
	end

	local speedMult = recordHitAndGetSpeedMult()
	local duration = math.clamp(BASE_FLOAT_TIME / speedMult, MIN_FLOAT_TIME, MAX_FLOAT_TIME)

	local sizeMult = getSizeMult(amt, maxHealth)
	local spreadX, spreadZ = getSpreadForModel(targetModel)
	local startOffset = randomStartOffset(spreadX, spreadZ)
	local driftRange = spreadX * DRIFT_MULT

	if isCrit then
		-- Fires the instant the server confirms this hit was a crit -- fully
		-- decoupled from the "CRITICAL" text/slash sequence's own pop-in
		-- delays below, so the sound never waits on the animation.
		SfxService.PlayEffect("CriticalHit")
		playCritSequence(root, amt, sizeMult, startOffset, duration, speedMult, driftRange)
	else
		-- Crit colours win when both apply; bleed ticks always arrive with
		-- isCrit = false, so in practice the two never contend.
		local gui, lbl, shadow = buildNumberGui(root, tostring(amt), DamageNumberStyles.Get(source).Color, sizeMult, startOffset)
		animateArcAndFade(gui, lbl, shadow, startOffset, duration, sizeMult, driftRange)
	end
end)
