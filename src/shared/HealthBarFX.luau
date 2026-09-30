--[[
	HealthBarFX
	Shared "juicy bar" behavior for any bar built the way this project's
	HP/Energy bars are: a `background` trough Frame containing a
	left-anchored `fill` Frame whose Size.X.Scale is the value's ratio,
	plus whatever ornament art or labels are ALSO parented under
	`background` (so a single UIScale on `background` punches everything
	together -- no separate ornament list needed).

	One controller per bar: HealthBarFX.new(config), then call
	controller:Update(current, max) every time the underlying value
	changes. The controller remembers the previous value itself and picks
	damage / heal / heal-to-full behavior from the sign and size of the
	change -- callers never need to know which effects that implies.

	Pure Instance/TweenService/task work, no client-only APIs, so the same
	module runs identically required from a LocalScript (player HP) or a
	Script (mob HP -- server-authoritative like the rest of this project's
	mob systems, see MobHPBarUI).

	hitStyle picks how a damage hit FEELS (default "jitter"):
	  "jitter"  flash + size punch + random positional shake -- the original
	            behaviour, still used by the player's own HP bar.
	  "wobble"  a short hard white flash, THEN a single side-to-side kick
	            (one push out, one swing back) with a touch of rotation, and no size punch. Built for
	            the floating mob bar (see MobHPBarUI), where the punch was the
	            thing making the bar grow sideways on every hit, and now used
	            by the player HP bar and the top-of-screen boss bar too.

	Feature toggles (all default true) let a sparser bar opt out of
	everything but the smooth drain -- e.g. Energy only wants req #1:
		HealthBarFX.new{ fill=.., background=.., chunkPreview=false,
			shake=false, flash=false, punch=false, damageNumber=false,
			healDots=false, fullText=false, colorRamp=false }
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local okFonts, UIFonts = pcall(function()
	return require(ReplicatedStorage:WaitForChild("UIFonts"))
end)

local HealthBarFX = {}
HealthBarFX.__index = HealthBarFX

------------------------------------------------------------
-- Tunables
------------------------------------------------------------

local DRAIN_WAIT = 0.3  -- req 2: pause before the main drain lerp starts
local DRAIN_TIME = 0.35 -- req 1/2: the main drain lerp's own duration
local HEAL_TIME  = 0.30 -- req 8: reverse-lerp duration per heal tick

-- Heal FX (flash/dots/"Full!") only show for a heal that's either forced
-- (opts.forceShowFX -- the hook a future potion-use call site should pass)
-- or landed while "out of combat", meaning no damage in the last this-many
-- seconds. Deliberately NOT wired to any real hp/s or armor-regen number --
-- passive regen (including plain Humanoid regen) firing during a fight
-- would otherwise pop the heal flourish on every tick mid-combat.
local IN_COMBAT_GRACE = 5

local CHUNK_COLOR = Color3.fromRGB(255, 70, 60) -- bright preview red, reads over green/yellow/red fill alike

local FLASH_DAMAGE_COLOR = Color3.fromRGB(255, 255, 255)
local FLASH_TIME = 0.18

local SHAKE_MAX_OFFSET = 6 -- px, at 100% of max value lost in one hit
local SHAKE_MIN_DAMAGE_PCT = 0.03 -- below this %, skip the shake entirely (chip damage shouldn't jitter the bar)
local SHAKE_DURATION = 0.25
local SHAKE_HZ = 30

local PUNCH_SCALE = 1.12
local PUNCH_TIME = 0.18

-- hitStyle = "wobble". Amplitude is a FRACTION OF THE BAR'S OWN WIDTH, so the
-- swing is proportional on every bar: a 5-stud floating mob bar, the player HP
-- bar, and the half-width boss segments all move by the same share of
-- themselves. See _wobble for how that fraction is turned into real units.
local WOBBLE_AMOUNT = 0.035   -- at a 100%-of-max hit
local WOBBLE_FLOOR = 0.6      -- fraction of WOBBLE_AMOUNT even the tiniest hit gets
local WOBBLE_DEGREES = 3      -- rotation at full amplitude
-- ONE cycle, not a buzz: a single push one way, one swing back the other, then
-- rest. It used to run ~4 oscillations over 0.32s (13Hz), which read as a
-- glitching bar rather than a bar that just got hit. The whole cycle is this
-- long; shorten it for a snappier kick.
local WOBBLE_DURATION = 0.18

local DMG_NUMBER_COLOR = Color3.fromRGB(255, 90, 90)
local FULL_TEXT_COLOR = Color3.fromRGB(110, 255, 120)
local FLOAT_TEXT_TIME = 0.6
local FLOAT_TEXT_RISE = 26 -- px

-- 2026-09-10 pass (direct feedback: "right now it just looks cluttered" -- decrease dot count
-- ~6x, spread them further apart, and let them rise further/dissipate slower):
--
-- 2026-09-10, later pass (direct feedback with a reference screenshot: a clean diagonal trail --
-- small dots of visibly VARYING size, spaced so none touch, fading as they rise, more solid near
-- the bar -- vs. our cluttered same-size overlapping blob): widened size range for real visible
-- variety (was 4-9).
local HEAL_DOT_SIZE_MIN, HEAL_DOT_SIZE_MAX = 3, 12
local HEAL_DOT_TRANSPARENCY_MIN, HEAL_DOT_TRANSPARENCY_MAX = 0.25, 0.65
local HEAL_DOT_RISE = 34 -- px -- was 14; rises further before despawning
local HEAL_DOT_TIME_MIN, HEAL_DOT_TIME_MAX = 0.8, 1.15 -- was 0.35, 0.55 -- slower, so the
	-- longer rise above reads as a gentle float-and-fade instead of a quick, cluttered dart
local HEAL_DOT_COLOR = Color3.fromRGB(110, 255, 130)
-- Dots scatter across [regenStart, regenEnd] (see _spawnHealDots) -- this is a floor on that
-- band's width so a tiny passive-regen tick (e.g. 0.1% maxHp/s) still gets a visible band to
-- scatter across instead of a near-zero-width sliver no dot placement could land inside.
local HEAL_DOT_MIN_BAND = 0.09 -- was 0.03
-- 2026-09-10: several "wave" variants (a whole batch of 8-15 dots spawned together, staggered
-- across the band -- with or without row-stacking), AND a throttled single-dot-at-a-time
-- variant that waited a dot's FULL LIFETIME between spawns (~1.35s) were all tried and reverted
-- per direct feedback -- batches read as clumps or a stutter of bursts-with-a-pause, and the
-- full-lifetime throttle read as "1 dot every 3 seconds ... terrible". Spawning on every single
-- heal tick with NO throttle at all (direct feedback: "idc if the clutter is back") then turned
-- out too dense -- Update() can fire fast enough during real regen that dots piled up and
-- overlapped (the cluttered same-size blob in that feedback's reference screenshot).
--
-- The fix isn't "more throttle" (that's what made it feel gappy before) -- it's a MUCH shorter
-- cooldown than the old full-lifetime one, short enough that dots still feel continuous
-- (several per second). Together with each dot's own rise-and-fade, that's what produces the
-- reference's diagonal trail: older dots higher and fainter, newer ones lower and more solid.
--
-- 2026-09-10, direct feedback: double the rate, and it's fine for 2-3 dots to land at the same
-- x at once -- since they spawn at different moments they're at different points along their
-- own rise, i.e. different heights, so sharing an x still reads as separate dots rather than a
-- single overlapping blob. Dropped the min-x-separation retry logic entirely -- plain random x
-- per dot again.
local HEAL_DOT_COUNT = 1 -- dots spawned per eligible heal tick
local HEAL_DOT_SPAWN_COOLDOWN = 0.075 -- seconds between spawns -- was 0.15, halved for 2x rate
-- regenStart is the ratio from this many seconds ago (see _ratioSecondsAgo), not just the
-- immediately-preceding tick's ratio -- frequent small regen ticks (e.g. every Heartbeat) would
-- otherwise each get their own near-zero-width band back-to-back, reading as a choppy sliver
-- rather than one continuous wave (2026-09-10, direct request: "make the dots maybe [oldratio
-- - last second, newratio] so it flows a bit better").
local HEAL_DOT_TRAIL_SECONDS = 1

------------------------------------------------------------
-- Color ramp (req 7): green 66-100%, yellow 33-65%, red <=33%
------------------------------------------------------------

local COLOR_GREEN  = Color3.fromRGB(60, 195, 75)
local COLOR_YELLOW = Color3.fromRGB(212, 185, 45)
local COLOR_RED    = Color3.fromRGB(205, 50, 50)

function HealthBarFX.DefaultColorRamp(ratio)
	if ratio > 0.65 then
		return COLOR_GREEN
	elseif ratio > 0.33 then
		return COLOR_YELLOW
	end
	return COLOR_RED
end

local function shiftColor(c, amt)
	return Color3.new(
		math.clamp(c.R + amt, 0, 1),
		math.clamp(c.G + amt, 0, 1),
		math.clamp(c.B + amt, 0, 1)
	)
end

-- Same top(bright)/bottom(dark) sheen both HealthClient and EnergyClient
-- already built inline (now the one copy both -- and MobHPBarUI -- share).
function HealthBarFX.GradientForColor(baseColor)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, shiftColor(baseColor, 0.28)),
		ColorSequenceKeypoint.new(0.35, baseColor),
		ColorSequenceKeypoint.new(1, shiftColor(baseColor, -0.35)),
	})
end

------------------------------------------------------------
-- Small helpers
------------------------------------------------------------

local function animateFloatText(label, riseAmountPx, duration)
	label.TextTransparency = 1
	TweenService:Create(label, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 0,
	}):Play()

	local startPos = label.Position
	local endPos = startPos - UDim2.fromOffset(0, riseAmountPx)
	TweenService:Create(label, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = endPos,
	}):Play()

	task.delay(duration * 0.4, function()
		if not label.Parent then return end
		TweenService:Create(label, TweenInfo.new(duration * 0.6, Enum.EasingStyle.Linear), {
			TextTransparency = 1,
		}):Play()
	end)

	task.delay(duration + 0.1, function()
		if label.Parent then label:Destroy() end
	end)
end

------------------------------------------------------------
-- Constructor
------------------------------------------------------------

function HealthBarFX.new(config)
	assert(config and config.fill, "HealthBarFX.new: config.fill is required")
	assert(config.background, "HealthBarFX.new: config.background is required")

	local self = setmetatable({}, HealthBarFX)

	self.fill = config.fill
	self.background = config.background
	self.gradient = config.gradient
	self._font = okFonts and UIFonts.HUDLabel or nil
	self._basePosition = self.background.Position

	self.enableChunkPreview = config.chunkPreview ~= false
	self.enableShake        = config.shake ~= false
	self.enableFlash        = config.flash ~= false
	self.enablePunch        = config.punch ~= false
	self.enableDamageNumber = config.damageNumber ~= false
	self.enableHealDots     = config.healDots ~= false
	self.enableFullText     = config.fullText ~= false

	if config.colorRamp == false then
		self.colorRamp = nil
	else
		self.colorRamp = config.colorRamp or HealthBarFX.DefaultColorRamp
	end

	self.shakeMaxOffset = config.shakeMaxOffset or SHAKE_MAX_OFFSET
	self.punchScale = config.punchScale or PUNCH_SCALE
	self.hitStyle = config.hitStyle or "jitter"
	self.flashTime = config.flashTime or FLASH_TIME
	self.flashStartTransparency = config.flashStartTransparency or 0.25
	-- The wobble's own contribution currently applied to the bar -- tracked so
	-- it can be REMOVED again rather than restoring a saved position. See _wobble.
	self._wobbleOffset = UDim2.new()
	self._wobbleRotation = 0

	self._chunk = nil
	self._chunkTween = nil
	self._flashOverlay = nil
	self._punchScaleObj = nil
	self._fillTween = nil
	self._shakeToken = 0
	self._drainToken = 0

	self._current = nil
	self._max = nil
	self._lastDamageTime = -math.huge
	self._externalInCombat = nil
	self._ratioHistory = {} -- {t = os.clock(), ratio = ...}, oldest first -- see _ratioSecondsAgo
	self._lastHealDotSpawnTime = -math.huge -- see HEAL_DOT_SPAWN_COOLDOWN

	return self
end

-- Returns the fill ratio as of roughly `seconds` ago, for the heal-dot trailing band (see
-- HEAL_DOT_TRAIL_SECONDS). Falls back to the oldest sample on hand (or the current ratio if
-- history is empty) rather than extrapolating.
function HealthBarFX:_ratioSecondsAgo(seconds)
	local history = self._ratioHistory
	if not history or #history == 0 then
		return (self._max and self._max > 0) and (self._current / self._max) or 0
	end
	local target = os.clock() - seconds
	local result = history[1].ratio
	for i = 1, #history do
		if history[i].t <= target then
			result = history[i].ratio
		else
			break
		end
	end
	return result
end

-- Records the current ratio for _ratioSecondsAgo's lookback, and prunes samples old enough
-- that no HEAL_DOT_TRAIL_SECONDS lookup will ever need them again.
function HealthBarFX:_recordRatioSample(ratio)
	local history = self._ratioHistory
	table.insert(history, { t = os.clock(), ratio = ratio })
	local cutoff = os.clock() - (HEAL_DOT_TRAIL_SECONDS * 2)
	while #history > 1 and history[1].t < cutoff do
		table.remove(history, 1)
	end
end

-- Lets a caller that has the REAL combat state (e.g. HealthClient listening to the
-- server-authoritative CombatStateEvent) override the internal "did this bar take damage
-- recently" heuristic below. Without this, a heal that nets out to a small positive delta the
-- same tick a hit lands (regen partially masking the hit) reads as "not in combat" even though
-- the player is actively fighting -- see the 2026-09-10 bug report ("re-enter combat, the
-- green dots stay"). Pass nil to fall back to the heuristic (used by bars with no real combat
-- concept, e.g. mob HP / Energy).
function HealthBarFX:SetInCombat(v)
	self._externalInCombat = v
end

------------------------------------------------------------
-- Overlay builders (lazy -- only created the first time each is used)
------------------------------------------------------------

function HealthBarFX:_ensureChunk()
	if self._chunk then return self._chunk end
	local chunk = Instance.new("Frame")
	chunk.Name = "DamageChunk"
	chunk.BackgroundColor3 = CHUNK_COLOR
	chunk.BorderSizePixel = 0
	chunk.ZIndex = self.fill.ZIndex + 1
	chunk.Visible = false

	local fillCorner = self.fill:FindFirstChildOfClass("UICorner")
	if fillCorner then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = fillCorner.CornerRadius
		corner.Parent = chunk
	end

	chunk.Parent = self.fill.Parent
	self._chunk = chunk
	return chunk
end

function HealthBarFX:_ensureFlashOverlay()
	if self._flashOverlay then return self._flashOverlay end
	local overlay = Instance.new("Frame")
	overlay.Name = "FlashOverlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.new(1, 1, 1)
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.ZIndex = 50 -- above fill, chunk, ornament, and text
	overlay.Parent = self.background
	self._flashOverlay = overlay
	return overlay
end

function HealthBarFX:_ensurePunchScale()
	if self._punchScaleObj then return self._punchScaleObj end
	local scale = Instance.new("UIScale")
	scale.Scale = 1
	scale.Parent = self.background
	self._punchScaleObj = scale
	return scale
end

------------------------------------------------------------
-- Effects
------------------------------------------------------------

function HealthBarFX:_flash(color)
	if not self.enableFlash then return end
	local overlay = self:_ensureFlashOverlay()
	overlay.BackgroundColor3 = color
	overlay.BackgroundTransparency = self.flashStartTransparency
	TweenService:Create(overlay, TweenInfo.new(self.flashTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
end

function HealthBarFX:_punch()
	if not self.enablePunch then return end
	local scale = self:_ensurePunchScale()
	scale.Scale = 1 -- reset in case a previous punch is still tweening down
	TweenService:Create(scale, TweenInfo.new(PUNCH_TIME * 0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = self.punchScale,
	}):Play()
	task.delay(PUNCH_TIME * 0.4, function()
		TweenService:Create(scale, TweenInfo.new(PUNCH_TIME * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Scale = 1,
		}):Play()
	end)
end

-- req 3: shake delta scaled by % of max lost, sqrt-curved so a small hit
-- still reads as a little nudge instead of nothing, without a big hit
-- blowing past a sane cap.
function HealthBarFX:_shake(damagePct)
	if not self.enableShake then return end
	damagePct = math.clamp(damagePct or 0, 0, 1)
	if damagePct < SHAKE_MIN_DAMAGE_PCT then return end

	local magnitude = self.shakeMaxOffset * math.sqrt(damagePct)
	local basePos = self._basePosition
	self._shakeToken += 1
	local myToken = self._shakeToken

	task.spawn(function()
		local elapsed = 0
		local step = 1 / SHAKE_HZ
		while elapsed < SHAKE_DURATION do
			if self._shakeToken ~= myToken then return end -- a newer hit's shake took over
			local decay = 1 - (elapsed / SHAKE_DURATION)
			local ox = (math.random() - 0.5) * 2 * magnitude * decay
			local oy = (math.random() - 0.5) * 2 * magnitude * decay
			self.background.Position = basePos + UDim2.fromOffset(ox, oy)
			task.wait(step)
			elapsed += step
		end
		if self._shakeToken == myToken then
			self.background.Position = basePos
		end
	end)
end

-- hitStyle = "wobble": waits out the flash, then swings the bar side to side
-- on a damped sine with a little rotation. Deterministic rather than random, so
-- it reads as a deliberate wobble instead of noise. Every hit wobbles -- there
-- is no minimum-damage skip like the jitter's, which is what made chip damage
-- on a high-HP mob (Kane) feel like nothing happened. Shares _shakeToken with
-- the jitter so a newer hit always takes over cleanly.
--
-- ADDITIVE, not "save a base position and restore it". Other code owns these
-- bars' placement at runtime -- HealthClient tweens the player HP bar when the
-- profile menu opens, and F6 tuning rewrites the boss bar's Position AND
-- Rotation -- so restoring a position captured at construction would snap a
-- bar back and undo that layout on the next hit. Instead each frame strips the
-- offset this wobble itself applied last frame, leaving whatever the owner set,
-- and lays the new offset on top. A tween running concurrently is at worst off
-- by one frame's (already decaying) offset.
function HealthBarFX:_wobble(damagePct, startDelay)
	if not self.enableShake then return end
	damagePct = math.clamp(damagePct or 0, 0, 1)
	local strength = WOBBLE_FLOOR + (1 - WOBBLE_FLOOR) * math.sqrt(damagePct)
	local amplitude = WOBBLE_AMOUNT * strength
	local degrees = WOBBLE_DEGREES * strength
	self._shakeToken += 1
	local myToken = self._shakeToken
	local bg = self.background

	local function apply(offset, rotation)
		bg.Position = (bg.Position - self._wobbleOffset) + offset
		bg.Rotation = (bg.Rotation - self._wobbleRotation) + rotation
		self._wobbleOffset, self._wobbleRotation = offset, rotation
	end

	-- One swing of `amplitude` bar-widths, in units the bar's Position accepts.
	-- AbsoluteSize is only laid out on a client; mob bars run on the SERVER,
	-- where it reads 0, so fall back to scale units of the parent. That is
	-- exact for the mob bar, which spans its whole BillboardGui.
	local function swingOffset(swing)
		local width = bg.AbsoluteSize.X
		if width > 0 then
			return UDim2.fromOffset(amplitude * width * swing, 0)
		end
		return UDim2.new(amplitude * bg.Size.X.Scale * swing, 0, 0, 0)
	end

	task.delay(startDelay or 0, function()
		if self._shakeToken ~= myToken then return end
		local started = os.clock()
		while true do
			-- A newer hit took over: leave our offset in place, it strips it.
			if self._shakeToken ~= myToken then return end
			-- Real elapsed time, not a fixed per-step increment, so a slow
			-- frame (this runs on the server for mob bars) cannot stretch it.
			local t = os.clock() - started
			if t >= WOBBLE_DURATION then break end
			-- Exactly one sine period: out, back past centre, home. The linear
			-- fade makes the return swing a little smaller than the first push,
			-- so it lands like an impact instead of a pendulum.
			local phase = t / WOBBLE_DURATION
			local swing = math.sin(phase * math.pi * 2) * (1 - 0.35 * phase)
			apply(swingOffset(swing), degrees * swing)
			task.wait()
		end
		if self._shakeToken == myToken then
			apply(UDim2.new(), 0)
		end
	end)
end

-- req 6: positioned at the FINAL ratio (known synchronously from
-- current/max -- no need to wait on the tween to "find out" where it ends).
function HealthBarFX:_showDamageNumber(delta, finalRatio)
	if not self.enableDamageNumber then return end
	local label = Instance.new("TextLabel")
	label.Name = "DamageNumber"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(finalRatio, 0, 0, -4)
	label.Size = UDim2.fromOffset(60, 18)
	label.BackgroundTransparency = 1
	label.FontFace = self._font
	label.TextSize = 14
	label.TextColor3 = DMG_NUMBER_COLOR
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.Text = "-" .. tostring(math.floor(delta + 0.5))
	label.ZIndex = 8
	label.TextTransparency = 1
	label.Parent = self.background
	animateFloatText(label, FLOAT_TEXT_RISE, FLOAT_TEXT_TIME)
end

-- req 9: fires on the specific transition from "not full" to "full",
-- never just because the bar happens to already be sitting at full.
function HealthBarFX:_showFullText()
	if not self.enableFullText then return end
	local goRight = math.random() < 0.5
	local label = Instance.new("TextLabel")
	label.Name = "FullText"
	label.AnchorPoint = Vector2.new(goRight and 0 or 1, 0.5)
	label.Position = goRight and UDim2.new(1, 8, 0.5, 0) or UDim2.new(0, -8, 0.5, 0)
	label.Size = UDim2.fromOffset(70, 20)
	label.BackgroundTransparency = 1
	label.FontFace = self._font
	label.TextSize = 15
	label.TextColor3 = FULL_TEXT_COLOR
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextXAlignment = goRight and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right
	label.Text = "Full!"
	label.ZIndex = 8
	label.TextTransparency = 1
	label.Parent = self.background
	animateFloatText(label, FLOAT_TEXT_RISE, FLOAT_TEXT_TIME)
end

-- req 8: a WAVE of small round dots, varying size/opacity, scattered along
-- the band that's ACTUALLY regenning this tick -- [regenStart, regenEnd],
-- i.e. where the fill just grew from/to -- not the whole filled width from
-- the left edge. Reads as a wave riding the leading edge of the regen
-- instead of a green haze sitting over the entire bar (2026-09-10, direct
-- bug report: "the green dots cover EVERYTHING from the left to the current
-- hp ... it should be ... showing green dots above what is REGENNING").
--
-- 2026-09-10: several "wave" variants (a whole batch of dots spawned together, staggered
-- across the band, with or without row-stacking), a single-dot-per-lifetime throttle, and no
-- throttle at all were all tried and reverted per direct feedback -- see HEAL_DOT_COUNT's
-- comment for the full history. Current design: one dot per eligible tick (HEAL_DOT_COUNT),
-- gated by a SHORT cooldown (HEAL_DOT_SPAWN_COOLDOWN) rather than a full dot lifetime -- random
-- x per dot, no separation enforced between them (direct feedback: sharing an x is fine since
-- each dot is at a different point in its own rise, i.e. a different height).
function HealthBarFX:_spawnHealDots(regenStart, regenEnd)
	if not self.enableHealDots then return end

	local lo = math.clamp(math.min(regenStart, regenEnd), 0, 1)
	local hi = math.clamp(math.max(regenStart, regenEnd), 0, 1)
	-- Widen backward (extend lo further into the past) rather than forward -- hi is the REAL
	-- current fill ratio, and pushing it forward would put the dot floating over the
	-- still-empty part of the bar, past the current HP edge.
	if hi - lo < HEAL_DOT_MIN_BAND then
		lo = math.max(0, hi - HEAL_DOT_MIN_BAND)
	end

	for _ = 1, HEAL_DOT_COUNT do
		local size = math.random(HEAL_DOT_SIZE_MIN, HEAL_DOT_SIZE_MAX)
		local transparency = HEAL_DOT_TRANSPARENCY_MIN
			+ math.random() * (HEAL_DOT_TRANSPARENCY_MAX - HEAL_DOT_TRANSPARENCY_MIN)

		local dot = Instance.new("Frame")
		dot.Name = "HealDot"
		-- Anchored at its own bottom-center, and positioned a few px ABOVE
		-- background's top edge (y=0 in its local space is that top edge)
		-- -- not at 0.5 scale, which sat the dot vertically centered INSIDE
		-- the bar, overlapping/muddying the fill it's supposed to be a
		-- garnish floating above. Rises further upward from that starting
		-- point, same as before.
		dot.AnchorPoint = Vector2.new(0.5, 1)
		dot.Size = UDim2.fromOffset(size, size)
		dot.BackgroundColor3 = HEAL_DOT_COLOR
		dot.BackgroundTransparency = transparency
		dot.BorderSizePixel = 0
		dot.ZIndex = 6
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = dot

		-- Scatter within the regenning band only -- see header comment. Sharing an x with a
		-- recently-spawned dot is fine (direct feedback) since they'll be at different heights.
		local x = lo + math.random() * (hi - lo)
		dot.Position = UDim2.new(x, 0, 0, -4)
		dot.Parent = self.background

		local dur = HEAL_DOT_TIME_MIN + math.random() * (HEAL_DOT_TIME_MAX - HEAL_DOT_TIME_MIN)
		local startPos = dot.Position
		local endPos = startPos - UDim2.fromOffset(0, HEAL_DOT_RISE)
		TweenService:Create(dot, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = endPos,
			BackgroundTransparency = 1,
		}):Play()
		task.delay(dur + 0.05, function()
			if dot.Parent then dot:Destroy() end
		end)
	end
end

------------------------------------------------------------
-- Fill animation
------------------------------------------------------------

-- Sets BOTH the fill's own BackgroundColor3 AND the gradient's ColorSequence
-- to the same ramp color. UIGradient composites against the object's base
-- BackgroundColor3 rather than replacing it outright, so leaving fill.
-- BackgroundColor3 on whatever static placeholder color it was authored
-- with (e.g. HealthClient's bar starts red) darkens/tints every ramp color
-- through that placeholder -- a full-health bar stays reddish instead of
-- reading green, and a low-health mob bar (authored green) reads as a dark
-- muddy color instead of red. Keeping both in sync is what the pre-
-- HealthBarFX inline code did too (see the module doc comment).
function HealthBarFX:_applyRampColor(ratio)
	if not (self.colorRamp and self.gradient) then return end
	local color = self.colorRamp(ratio)
	self.fill.BackgroundColor3 = color
	self.gradient.Color = HealthBarFX.GradientForColor(color)
end

function HealthBarFX:_setFillInstant(ratio)
	self.fill.Size = UDim2.new(ratio, 0, 1, 0)
	self:_applyRampColor(ratio)
end

function HealthBarFX:_animateFillTo(ratio, duration)
	if self._fillTween then
		self._fillTween:Cancel()
	end
	local tween = TweenService:Create(self.fill, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(ratio, 0, 1, 0),
	})
	self._fillTween = tween
	tween:Play()

	-- Re-tint partway through rather than only at the very end, so the
	-- color ramp feels attached to the animating bar, not just the final
	-- value.
	task.delay(duration * 0.5, function()
		self:_applyRampColor(ratio)
	end)
	return tween
end

------------------------------------------------------------
-- Public entry point
------------------------------------------------------------

-- Call every time the underlying value changes. Tracks the previous value
-- itself; the very first call (initial connect / mob spawn) just snaps with
-- no FX, exactly like the pre-existing per-file update functions did.
--
-- opts.forceShowFX: pass true to always show the heal flourish (flash/
-- dots/"Full!") even mid-combat -- the hook a future potion-use call site
-- should set. Nothing calls it yet (there's no potion-heal code in this
-- project today), but the gate below needs an escape hatch the moment
-- there is one, so it's wired in now rather than bolted on later.
function HealthBarFX:Update(current, max, opts)
	max = math.max(max or 0, 0)
	if max <= 0 then return end
	current = math.clamp(current or 0, 0, max)
	local newRatio = current / max

	if self._current == nil then
		self._current, self._max = current, max
		self:_setFillInstant(newRatio)
		self:_recordRatioSample(newRatio)
		return
	end

	local prevCurrent, prevMax = self._current, self._max
	local oldRatio = (prevMax > 0) and math.clamp(prevCurrent / prevMax, 0, 1) or newRatio
	self._current, self._max = current, max
	self:_recordRatioSample(newRatio)

	local delta = current - prevCurrent
	if math.abs(delta) < 0.001 then
		return
	end

	self._drainToken += 1
	local myToken = self._drainToken

	if delta < 0 then
		-- Damage: req 2 (chunk preview + delayed drain), req 3 (shake),
		-- req 4 (flash), req 5 (punch), req 6 (damage number at final pos).
		self._lastDamageTime = os.clock()
		local dmgAmount = -delta
		local dmgPct = dmgAmount / max

		self:_showDamageNumber(dmgAmount, newRatio)
		self:_flash(FLASH_DAMAGE_COLOR)
		if self.hitStyle == "wobble" then
			-- Flash first, wobble after it -- sequenced, not stacked, so each
			-- reads on its own. No punch: see the hitStyle note up top.
			self:_wobble(dmgPct, self.flashTime)
		else
			self:_punch()
			self:_shake(dmgPct)
		end

		if self.enableChunkPreview then
			local chunk = self:_ensureChunk()

			-- Anchor the chunk to the fill's ACTUAL current rendered ratio
			-- (self.fill.Size.X.Scale), not the stored oldRatio. oldRatio
			-- only reflects the last *health value* we saw -- if hits land
			-- faster than DRAIN_WAIT, that previous hit's own drain never
			-- got to run (superseded below), so the fill never visually
			-- moved there and oldRatio silently drifts away from what's on
			-- screen. Reading the live rendered scale means the chunk
			-- always covers exactly [true current ratio, what's actually
			-- visible], however many hits stacked up before it.
			if self._chunkTween then
				self._chunkTween:Cancel()
				self._chunkTween = nil
			end
			local visualRatio = math.max(self.fill.Size.X.Scale, oldRatio)
			chunk.Visible = true
			chunk.BackgroundTransparency = 0
			chunk.Position = UDim2.new(newRatio, 0, 0, 0)
			chunk.Size = UDim2.new(math.max(visualRatio - newRatio, 0), 0, 1, 0)

			task.delay(DRAIN_WAIT, function()
				if self._drainToken ~= myToken then return end -- superseded by a later hit
				self:_animateFillTo(newRatio, DRAIN_TIME)

				-- Shrink the chunk's WIDTH down to nothing (left edge stays
				-- pinned at newRatio) using the exact same TweenInfo as the
				-- fill's own drain, instead of fading it out via
				-- Transparency. The old fade approach kept the chunk
				-- semi-transparent for the whole DRAIN_TIME while it still
				-- visually overlapped the not-yet-drained green fill
				-- underneath -- that alpha blend of red-over-green is what
				-- read as the bar's color/opacity "changing" and looking
				-- dark/muddy. Shrinking width instead means the chunk stays
				-- fully opaque the whole time and its receding right edge
				-- always meets the fill's receding right edge exactly, so
				-- there's never a mixed-color region.
				local shrinkTween = TweenService:Create(chunk, TweenInfo.new(DRAIN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Size = UDim2.new(0, 0, 1, 0),
				})
				self._chunkTween = shrinkTween
				shrinkTween:Play()
				shrinkTween.Completed:Connect(function()
					if self._drainToken == myToken then
						chunk.Visible = false
					end
				end)
			end)
		else
			task.delay(DRAIN_WAIT, function()
				if self._drainToken ~= myToken then return end
				self:_animateFillTo(newRatio, DRAIN_TIME)
			end)
		end
	else
		-- Heal: req 1 (reverse lerp), req 8 (traveling dots), req 9 ("Full!").
		-- A heal landing inside another hit's DRAIN_WAIT window bumped
		-- _drainToken above and silently cancelled that hit's delayed
		-- fill-tween-and-fade -- which otherwise leaves its red chunk stuck
		-- fully visible forever, since nothing else ever clears it. Health
		-- itself (self._current/self._max) stays correct either way; this
		-- just keeps the chunk from lingering as a visual bug.
		if self._chunkTween then
			self._chunkTween:Cancel()
			self._chunkTween = nil
		end
		if self._chunk then
			self._chunk.Visible = false
		end
		self:_animateFillTo(newRatio, HEAL_TIME)

		-- Only show the heal flourish (flash/dots/"Full!") for a potion
		-- (opts.forceShowFX) or a heal that landed out of combat -- not on
		-- every tick of passive/Humanoid regen firing mid-fight. The smooth
		-- fill lerp above always plays regardless; only the garnish is gated.
		-- Prefer the caller-supplied real combat state (SetInCombat) when
		-- given -- see that method's doc comment for why the local-heuristic
		-- fallback below can get stuck reading "not in combat" mid-fight.
		local inCombat
		if self._externalInCombat ~= nil then
			inCombat = self._externalInCombat
		else
			inCombat = (os.clock() - self._lastDamageTime) < IN_COMBAT_GRACE
		end
		local showHealFX = (opts and opts.forceShowFX) or not inCombat

		if showHealFX then
			-- No flash here (2026-09-10, direct request: "remove the flashing effect that
			-- happens during regen ... its too distracting and takes away from the wave of
			-- dots") -- damage still flashes (FLASH_DAMAGE_COLOR above), only the heal
			-- flourish's flash is gone. The dots themselves are the only heal-tick FX now.
			--
			-- Gated by a SHORT cooldown, not a full dot lifetime (2026-09-10, see
			-- HEAL_DOT_SPAWN_COOLDOWN's comment for why that distinction matters) -- Update()
			-- can fire faster than that during real regen, so this still trims the rate without
			-- reintroducing the "1 dot every 3 seconds" gappiness a longer throttle caused.
			local now = os.clock()
			if now - self._lastHealDotSpawnTime >= HEAL_DOT_SPAWN_COOLDOWN then
				self._lastHealDotSpawnTime = now
				-- Trail the band's start back to ~1s ago instead of just the immediately-
				-- preceding tick's ratio, so a regen tick that landed since the last dot spawned
				-- still reads as one continuous wave rather than a thin sliver.
				local trailStart = math.min(oldRatio, self:_ratioSecondsAgo(HEAL_DOT_TRAIL_SECONDS))
				self:_spawnHealDots(trailStart, newRatio)
			end

			local wasFull = prevMax > 0 and prevCurrent >= prevMax
			local isFull = current >= max
			if isFull and not wasFull then
				self:_showFullText()
			end
		end
	end
end

return HealthBarFX
