--!strict
--  XpHud -- the floating Combat / Mining / Fishing XP bars (React-lua).
--
--  This component READS state only. XP accumulation and level-ups live in the server and
--  the scripts that write into SkillXPShared and stamp player:SetAttribute("Last<Skill>XPGain",
--  tick()). A bar shows for a few seconds after a gain, then hides.
--
--  Look (rebuilt 2026-10-01): the same thin hairline bar as HP / energy (RS/HudBarStyle), a
--  luminous gold fill (experience is light). The combat bar, top-centre, adds a medallion on
--  the bar's left end (a dark disc with the sword-and-shield icon, ringed by the oak wreath
--  HudArt.XP_MEDALLION_FRAME), "Level n" and the XP count, plus the kill effect below. When the
--  orbs land, a soft light swells inside the disc.
--
--  Kill effect (XpGainBurst): every kill drops a handful of orbs of light around the bar
--  (a soft glow sprite, HudArt.GLOW_SOFT, tinted warm gold, popping in and hovering). Kills
--  stack into one pool while they keep coming; HOLD_TIME after the last one the whole pool is
--  pulled in, like into a black hole: each orb spirals toward the fill's leading edge,
--  accelerating, stretching along its path and shrinking, while a glowing well swells at that
--  edge. When the last orb lands the well flares out, the bar flashes, and the fill rises to
--  the new value (it holds the old value until then, so the XP visibly arrives with the orbs;
--  a level-up fills to the end, wraps to empty and pulses the medallion).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local Workspace         = game:GetService("Workspace")

local React              = require(ReplicatedStorage.Packages.React)
local SkillXPShared      = require(ReplicatedStorage:WaitForChild("SkillXPShared"))
local HudBottomLeftStack = require(ReplicatedStorage:WaitForChild("HudBottomLeftStack"))
local HudBarStyle        = require(ReplicatedStorage:WaitForChild("HudBarStyle"))
local HudTopCentre       = require(ReplicatedStorage:WaitForChild("HudTopCentre"))
local UIFonts            = require(ReplicatedStorage:WaitForChild("UIFonts"))
local Assets             = ReplicatedStorage:WaitForChild("Assets")
local HudArt             = require(Assets:WaitForChild("Images"):WaitForChild("HudArt"))
local HudIcons           = require(Assets:WaitForChild("Icons"):WaitForChild("Hud"):WaitForChild("HudIcons"))

local e      = React.createElement
local player = Players.LocalPlayer

local HIDE_DELAY = 5          -- seconds of no XP before a Mining/Fishing bar hides
local COMBAT_HIDE_DELAY = 2.5 -- covers the kill effect's worst-case tail (HOLD_TIME + the pull-in)

-- Width follows the viewport like the vitals bars.
local XP_WIDTH_SCALE = 0.22
local XP_WIDTH_MIN, XP_WIDTH_MAX = 260, 460

local BAR_H = 8
local TITLE_H = 22
local BAR_Y = TITLE_H + 8 -- top of the bar inside a bar's container
local CONTAINER_H = BAR_Y + BAR_H + 6
local DISC = 42 -- the combat medallion's dark disc, centred on the bar's left end
-- The wreath around it, sized so its branch tucks just over the disc's edge.
local HAS_WREATH = HudArt.XP_MEDALLION_FRAME ~= ""
local WREATH_W = HAS_WREATH and DISC * 1.05 / HudArt.XP_MEDALLION_FRAME_HOLE.D or DISC
local WREATH_H = HAS_WREATH and WREATH_W / HudArt.XP_MEDALLION_FRAME_ASPECT or DISC
local TITLE_INSET = WREATH_W / 2 + 6 -- combat title text starts past the medallion

local COMBAT_TOP      = 20 -- top-centre, out of the way of the view
local COMBAT_ANCHOR   = Vector2.new(0.5, 0)
-- Below whatever holds the top-centre (RS/HudTopCentre: the named-elite pity plate), with room
-- for the medallion's wreath, which rises a little above the bar's own frame.
local TOP_CENTRE_GAP  = 14
local function combatPosition(reservedBottom: number): UDim2
	return UDim2.new(0.5, 0, 0, math.max(COMBAT_TOP, reservedBottom + TOP_CENTRE_GAP))
end
local DEFAULT_POSITION = UDim2.new(0, 10, 1, -10)
local DEFAULT_ANCHOR   = Vector2.new(0, 1)
-- The non-combat bars share the bottom-left corner with RS/HudBottomLeftStack (combat timer,
-- dungeon timer); they sit this far above whatever the stack is currently showing.
local STACK_CLEARANCE  = 8
local function defaultPosition(stackHeight: number): UDim2
	if stackHeight <= 0 then return DEFAULT_POSITION end
	return DEFAULT_POSITION + UDim2.fromOffset(0, -(stackHeight + HudBottomLeftStack.MARGIN + STACK_CLEARANCE) + 10)
end

-- Semantic palette, so zone theming can swap it wholesale.
local THEME = {
	XpFill      = Color3.fromRGB(226, 186, 104), -- luminous gold: experience is light
	TextPrimary = HudBarStyle.BONE,
	TextMuted   = Color3.fromRGB(196, 184, 162),
	TextStroke  = Color3.fromRGB(14, 10, 8),
	Disc        = HudBarStyle.DISC,              -- the medallion's dark centre
	DiscEdge    = Color3.fromRGB(42, 28, 18),    -- the wreath art's outline colour
	LightCore   = Color3.fromRGB(255, 247, 228), -- an orb's hot centre
	LightGlow   = Color3.fromRGB(255, 186, 92),  -- its warm halo, and the well
}

local SKILLS = {
	{ key = "Combat",  label = "Combat" },
	{ key = "Mining",  label = "Mining" },
	{ key = "Fishing", label = "Fishing" },
}

local function lastGain(key: string): number
	return (player:GetAttribute("Last" .. key .. "XPGain") :: number?) or 0
end

local function hideDelayFor(key: string): number
	return key == "Combat" and COMBAT_HIDE_DELAY or HIDE_DELAY
end

-- What each bar last showed, kept across a bar hiding and showing again: a bar mounts at this
-- value (not the new one), so the first kill of a streak still visibly fills it. XP that
-- changes without a gain (a profile sync, no Last<Skill>XPGain stamp) settles silently.
type Shown = { level: number, pct: number }
local settled: { [string]: Shown } = {}

local function currentOf(key: string): Shown
	local state = SkillXPShared[key]
	return {
		level = state.Level,
		pct = math.clamp(state.XP / math.max(SkillXPShared.GetXPForLevel(state.Level), 1), 0, 1),
	}
end

local function settleQuietChanges()
	local now = tick()
	for _, s in ipairs(SKILLS) do
		if now - lastGain(s.key) > hideDelayFor(s.key) then
			settled[s.key] = currentOf(s.key)
		end
	end
end

local function withCommas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

--------------------------------------------------------------------------------
--  XpGainBurst -- the kill effect (see the header). Imperative on purpose: the orbs move on
--  curved, accelerating paths every frame, which tweens can't express. React owns only the
--  root Frame; the effect builds its own layer inside it and tears it down on unmount.
--------------------------------------------------------------------------------

local ORBS_PER_KILL = 6
local HOLD_TIME = 1.0                 -- after the last kill of a streak, the pool is pulled in
local SPREAD_X, SPREAD_Y = 150, 70    -- scatter around the bar's centre, px
local EDGE_MARGIN = 24                -- keep orbs this far inside the screen
local KEEPOUT_TOP, KEEPOUT_BOTTOM = -36, 12 -- the title row and bar itself (y from the bar's centre)
local ORB_MIN, ORB_MAX = 10, 20       -- core size, px (was 6-13, bumped 2026-10-01)
local GLOW_SCALE = 3.4                -- halo size relative to the core
local POP_TIME = 0.18                 -- an orb's pop-in
local HOVER_PX = 4                    -- gentle bob while it waits
local PULL_MIN, PULL_MAX = 0.55, 0.8  -- one orb's pull-in duration
local PULL_STAGGER = 0.22             -- orbs leave one after another, not all on one frame
local SWIRL = 2.6                     -- radians each orb turns around the well on the way in
local STRETCH = 2.4                   -- how long an orb streaks at full speed
local ORB_OUTLINE_TRANSPARENCY = 0.9 -- a faint dark edge on each orb's core so it reads on bright ground
local WELL_SIZE = 32                  -- the glow at the fill edge while orbs pour in (scaled with the orbs)
local FLASH_TIME = 0.22

type Orb = {
	core: ImageLabel, glow: ImageLabel, size: number,
	x: number, y: number, phase: number, born: number,
	pulling: boolean, t0: number, dur: number, r0: number, a0: number,
}

local function easeOutBack(t: number): number
	local c = 1.7
	return 1 + (c + 1) * (t - 1) ^ 3 + c * (t - 1) ^ 2
end

local function XpGainBurst(props: { pctRef: { current: number }, onAbsorbed: () -> () })
	local rootRef = React.useRef(nil :: Frame?)
	local onAbsorbedRef = React.useRef(props.onAbsorbed)
	onAbsorbedRef.current = props.onAbsorbed

	React.useEffect(function()
		local root = rootRef.current
		if not root then return end

		local layer = Instance.new("Frame")
		layer.Name = "LightLayer"
		layer.Size = UDim2.fromScale(1, 1)
		layer.BackgroundTransparency = 1
		layer.Parent = root

		local function sprite(color: Color3, z: number): ImageLabel
			local img = Instance.new("ImageLabel")
			img.AnchorPoint = Vector2.new(0.5, 0.5)
			img.BackgroundTransparency = 1
			img.Image = HudArt.GLOW_SOFT
			img.ImageColor3 = color
			img.ZIndex = z
			img.Size = UDim2.fromOffset(0, 0)
			img.Parent = layer
			return img
		end

		local well = sprite(THEME.LightGlow, 1)
		well.ImageTransparency = 1
		local flash = Instance.new("Frame")
		flash.Name = "Flash"
		flash.Size = UDim2.fromScale(1, 1)
		flash.BackgroundColor3 = THEME.LightCore
		flash.BackgroundTransparency = 1
		flash.BorderSizePixel = 0
		flash.ZIndex = 4
		flash.Parent = layer

		local orbs: { Orb } = {}
		local pulling = 0 -- orbs currently on their way in
		local wellPulse = 0 -- decays; bumps on every orb that lands
		local conn: RBXScriptConnection? = nil
		local holdToken = 0
		local alive = true

		-- Where the orbs go: the fill's leading edge, in px from the layer's centre.
		local function wellX(): number
			return (math.clamp(props.pctRef.current, 0, 1) - 0.5) * layer.AbsoluteSize.X
		end

		local function place(img: ImageLabel, x: number, y: number, w: number, h: number, rot: number)
			img.Position = UDim2.new(0.5, x, 0.5, y)
			img.Size = UDim2.fromOffset(w, h)
			img.Rotation = rot
		end

		local function finishPull()
			if not alive then return end
			-- The well flares and fades, the bar flashes, the fill rises.
			TweenService:Create(well, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = UDim2.fromOffset(WELL_SIZE * 2.6, WELL_SIZE * 2.6), ImageTransparency = 1,
			}):Play()
			flash.BackgroundTransparency = 0.35
			TweenService:Create(flash, TweenInfo.new(FLASH_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				BackgroundTransparency = 1,
			}):Play()
			onAbsorbedRef.current()
		end

		local function step()
			local now = os.clock()
			local tx = wellX()
			for i = #orbs, 1, -1 do
				local orb = orbs[i]
				if not orb.pulling or now < orb.t0 then
					local pop = easeOutBack(math.clamp((now - orb.born) / POP_TIME, 0, 1))
					local x = orb.x + math.sin(now * 2.1 + orb.phase) * HOVER_PX
					local y = orb.y + math.cos(now * 1.7 + orb.phase) * HOVER_PX
					local s = orb.size * pop
					place(orb.core, x, y, s, s, 0)
					place(orb.glow, x, y, s * GLOW_SCALE, s * GLOW_SCALE, 0)
				else
					local u = (now - orb.t0) / orb.dur
					if u >= 1 then
						orb.core:Destroy()
						orb.glow:Destroy()
						table.remove(orbs, i)
						pulling -= 1
						wellPulse = 1
						if pulling == 0 then finishPull() end
					else
						-- Accelerating spiral: the radius collapses ever faster while the angle
						-- keeps turning, so every orb swirls the same way into the well.
						local k = u ^ 2.3
						local r = orb.r0 * (1 - k)
						local a = orb.a0 + SWIRL * k
						local x, y = tx + math.cos(a) * r, math.sin(a) * r
						-- Direction of travel (spiral tangent + inward pull) for the streak.
						local dx = -math.sin(a) * SWIRL * orb.r0 * (1 - k) - math.cos(a) * orb.r0
						local dy = math.cos(a) * SWIRL * orb.r0 * (1 - k) - math.sin(a) * orb.r0
						local rot = math.deg(math.atan2(dy, dx))
						local s = orb.size * (1 - 0.6 * k)
						local stretch = 1 + STRETCH * k
						place(orb.core, x, y, s * stretch, s, rot)
						place(orb.glow, x, y, s * GLOW_SCALE * (1 + (stretch - 1) * 0.5), s * GLOW_SCALE, rot)
						orb.core.ImageTransparency = 0
						orb.glow.ImageTransparency = 0.35 - 0.2 * k
					end
				end
			end
			-- The well: a glow at the fill edge, alive while orbs pour in, pulsing as each lands.
			if pulling > 0 then
				wellPulse = math.max(wellPulse - 0.12, 0)
				local w = WELL_SIZE * (1 + 0.45 * wellPulse + 0.08 * math.sin(now * 14))
				place(well, tx, 0, w, w, 0)
				well.ImageTransparency = 0.25
			end
			if #orbs == 0 and conn then
				conn:Disconnect()
				conn = nil
			end
		end

		local function ensureLoop()
			if not conn then conn = RunService.RenderStepped:Connect(step) end
		end

		local function getSafeBounds(): (number, number, number, number)
			local camera = Workspace.CurrentCamera
			if not camera or layer.AbsoluteSize.X <= 0 then
				return -SPREAD_X, SPREAD_X, -SPREAD_Y, SPREAD_Y
			end
			local viewport = camera.ViewportSize
			local cx = layer.AbsolutePosition.X + layer.AbsoluteSize.X * 0.5
			local cy = layer.AbsolutePosition.Y + layer.AbsoluteSize.Y * 0.5
			return math.max(-SPREAD_X, -(cx - EDGE_MARGIN)), math.min(SPREAD_X, viewport.X - cx - EDGE_MARGIN),
				math.max(-SPREAD_Y, -(cy - EDGE_MARGIN)), math.min(SPREAD_Y, viewport.Y - cy - EDGE_MARGIN)
		end

		-- A y outside the title row / bar band, on whichever side has room.
		local function rollY(minY: number, maxY: number): number
			local above = math.max(math.min(KEEPOUT_TOP, maxY) - minY, 0)
			local below = math.max(maxY - math.max(KEEPOUT_BOTTOM, minY), 0)
			if above + below <= 0 then return minY end
			local pick = math.random() * (above + below)
			if pick < above then return minY + pick end
			return math.max(KEEPOUT_BOTTOM, minY) + (pick - above)
		end

		local function release()
			local now = os.clock()
			local tx = wellX()
			for _, orb in ipairs(orbs) do
				if not orb.pulling then
					orb.pulling = true
					pulling += 1
					orb.t0 = now + math.random() * PULL_STAGGER
					orb.dur = PULL_MIN + math.random() * (PULL_MAX - PULL_MIN)
					orb.r0 = math.sqrt((orb.x - tx) ^ 2 + orb.y ^ 2)
					orb.a0 = math.atan2(orb.y, orb.x - tx)
				end
			end
			if pulling > 0 then
				well.Size = UDim2.fromOffset(0, 0)
				ensureLoop()
			end
		end

		local function onKill()
			if not alive then return end
			local minX, maxX, minY, maxY = getSafeBounds()
			local now = os.clock()
			for _ = 1, ORBS_PER_KILL do
				local size = ORB_MIN + math.random() * (ORB_MAX - ORB_MIN)
				local core = sprite(THEME.LightCore, 3)
				-- Round (a pill once it streaks) with a faint dark outline: on bright sand or sky the
				-- warm orb alone barely separates from the background.
				local round = Instance.new("UICorner")
				round.CornerRadius = UDim.new(1, 0)
				round.Parent = core
				local outline = Instance.new("UIStroke")
				outline.Color = Color3.new(0, 0, 0)
				outline.Transparency = ORB_OUTLINE_TRANSPARENCY
				outline.Thickness = 1.5
				outline.Parent = core
				local orb: Orb = {
					core = core, glow = sprite(THEME.LightGlow, 2), size = size,
					x = minX + math.random() * math.max(maxX - minX, 0), y = rollY(minY, maxY),
					phase = math.random() * math.pi * 2, born = now + math.random() * 0.08,
					pulling = false, t0 = 0, dur = 0, r0 = 0, a0 = 0,
				}
				orb.glow.ImageTransparency = 0.45
				table.insert(orbs, orb)
			end
			ensureLoop()
			holdToken += 1
			local myToken = holdToken
			task.delay(HOLD_TIME, function()
				-- Only the last kill of a streak releases the pool.
				if alive and holdToken == myToken then release() end
			end)
		end

		-- The kill that mounted this bar fired before we connected, so count it here.
		onKill()
		local killConn = player:GetAttributeChangedSignal("LastCombatXPGain"):Connect(onKill)

		return function()
			alive = false
			killConn:Disconnect()
			if conn then conn:Disconnect() end
			layer:Destroy()
		end
	end, {})

	return e("Frame", {
		ref = rootRef,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	})
end

--------------------------------------------------------------------------------
--  XpBar -- one skill's bar. The fill is moved by tweens (never by the Size prop after
--  mount), so it can hold its old value until the kill effect delivers the XP.
--------------------------------------------------------------------------------

type BarProps = {
	skillKey: string,
	label: string,
	level: number,
	xp: number,
	xpNeeded: number,
	zIndex: number,
	position: UDim2,
	anchorPoint: Vector2,
	isCombat: boolean,
}

local FILL_TWEEN = TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local WRAP_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function XpBar(props: BarProps)
	local pct = math.clamp(props.xp / math.max(props.xpNeeded, 1), 0, 1)

	local fillRef = React.useRef(nil :: Frame?)
	local medallionScaleRef = React.useRef(nil :: UIScale?)
	local discLightRef = React.useRef(nil :: ImageLabel?)
	local latest = React.useRef({ level = props.level, pct = pct })
	latest.current = { level = props.level, pct = pct }
	-- Mount at what this bar last showed (see `settled`), then animate to the new value.
	local shown = React.useRef(settled[props.skillKey] or latest.current)
	local pctRef = React.useRef(shown.current.pct) -- where the orbs aim: the fill edge on screen
	local initialSize = React.useRef(UDim2.fromScale(shown.current.pct, 1)).current

	-- Bring the fill to the latest value (a level-up fills to the end and wraps first).
	local syncFill = React.useCallback(function()
		local fill = fillRef.current
		local target, from = latest.current, shown.current
		shown.current = target
		settled[props.skillKey] = target
		pctRef.current = target.pct
		if not fill then return end
		if target.level > from.level then
			local up = TweenService:Create(fill, WRAP_TWEEN, { Size = UDim2.fromScale(1, 1) })
			up.Completed:Connect(function()
				if not fill.Parent then return end
				fill.Size = UDim2.fromScale(0, 1)
				TweenService:Create(fill, FILL_TWEEN, { Size = UDim2.fromScale(target.pct, 1) }):Play()
			end)
			up:Play()
			local scale = medallionScaleRef.current
			if scale then
				scale.Scale = 1.35
				TweenService:Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end
		elseif target.pct ~= from.pct or target.level ~= from.level then
			TweenService:Create(fill, FILL_TWEEN, { Size = UDim2.fromScale(target.pct, 1) }):Play()
		end
	end, {})

	-- Non-combat bars fill straight away. The combat bar waits for its orbs, with a fallback
	-- for XP that arrives without a kill (or if the bar is about to hide mid-effect).
	React.useEffect(function()
		if not props.isCombat then
			syncFill()
			return
		end
		local cancelled = false
		task.delay(COMBAT_HIDE_DELAY - 0.3, function()
			if not cancelled then syncFill() end
		end)
		return function() cancelled = true end
	end, { pct, props.level } :: { any })

	local z = props.zIndex
	local children: { [string]: any } = {}

	-- Title row: combat has "Level n" past the medallion and the XP count on the right; other
	-- skills have "Mining  n" on the left and the count on the right.
	children.Title = e("TextLabel", {
		Position = UDim2.fromOffset(props.isCombat and TITLE_INSET or 0, 0),
		Size = UDim2.new(1, props.isCombat and -TITLE_INSET or 0, 0, TITLE_H),
		BackgroundTransparency = 1,
		FontFace = UIFonts.SerifBold,
		Text = props.isCombat and string.format("Level %d", props.level)
			or string.format("%s  %d", props.label, props.level),
		TextColor3 = THEME.TextPrimary,
		TextStrokeColor3 = THEME.TextStroke,
		TextStrokeTransparency = 0.35,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		ZIndex = z,
	})
	children.Amount = e("TextLabel", {
		Size = UDim2.new(1, 0, 0, TITLE_H),
		BackgroundTransparency = 1,
		FontFace = UIFonts.HUDLabel,
		Text = string.format("%s / %s", withCommas(props.xp), withCommas(props.xpNeeded)),
		TextColor3 = THEME.TextMuted,
		TextStrokeColor3 = THEME.TextStroke,
		TextStrokeTransparency = 0.45,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		ZIndex = z,
	})

	local troughChildren = HudBarStyle.TroughElements(e, BAR_H, z + 3, { noLeftCap = props.isCombat })
	troughChildren.Fill = e("Frame", {
		ref = fillRef,
		Size = initialSize,
		BackgroundColor3 = THEME.XpFill,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = z + 1,
	}, {
		Sheen = e("UIGradient", { Rotation = 90, Color = HudBarStyle.GradientFor(THEME.XpFill) }),
		Grain = HudBarStyle.GrainElement(e, BAR_H, z + 1),
	})
	children.Bar = e("Frame", {
		Position = UDim2.fromOffset(0, BAR_Y),
		Size = UDim2.new(1, 0, 0, BAR_H),
		BackgroundColor3 = HudBarStyle.TROUGH,
		BackgroundTransparency = HudBarStyle.TROUGH_TRANSPARENCY,
		BorderSizePixel = 0,
		ZIndex = z,
	}, troughChildren)

	if props.isCombat then
		-- Inside the disc: the light that swells when the orbs land, then the icon. The wreath
		-- draws over the disc's edge; without it the disc gets a plain bronze ring.
		local medallionChildren: { [string]: any } = {
			Scale = e("UIScale", { ref = medallionScaleRef }),
			Disc = e("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(DISC, DISC),
				BackgroundColor3 = THEME.Disc,
				BorderSizePixel = 0,
				ClipsDescendants = true,
				ZIndex = 1,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
				Edge = e("UIStroke", {
					Color = HAS_WREATH and THEME.DiscEdge or HudBarStyle.BRONZE,
					Thickness = 2,
				}),
				Light = e("ImageLabel", {
					ref = discLightRef,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromScale(1.3, 1.3),
					BackgroundTransparency = 1,
					Image = HudArt.GLOW_SOFT,
					ImageColor3 = THEME.LightGlow,
					ImageTransparency = 1,
					ZIndex = 1,
				}),
				Icon = e("ImageLabel", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromScale(0.62, 0.62),
					BackgroundTransparency = 1,
					Image = HudIcons.COMBAT,
					ScaleType = Enum.ScaleType.Fit,
					ZIndex = 2,
				}),
			}),
		}
		if HAS_WREATH then
			local hole = HudArt.XP_MEDALLION_FRAME_HOLE
			medallionChildren.Wreath = e("ImageLabel", {
				-- Anchored on the wreath's empty middle, so the disc sits exactly in it.
				AnchorPoint = Vector2.new(hole.X, hole.Y),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(WREATH_W, WREATH_H),
				BackgroundTransparency = 1,
				Image = HudArt.XP_MEDALLION_FRAME,
				ZIndex = 2,
			})
		end
		children.Medallion = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(0, BAR_Y + BAR_H / 2),
			Size = UDim2.fromOffset(DISC, DISC),
			BackgroundTransparency = 1,
			ZIndex = z + 4,
		}, medallionChildren)

		-- The orbs landing: light swells in the disc, then the fill rises.
		local function onAbsorbed()
			local light = discLightRef.current
			if light then
				light.ImageTransparency = 0.1
				light.Size = UDim2.fromScale(1.6, 1.6)
				TweenService:Create(light, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					ImageTransparency = 1, Size = UDim2.fromScale(1.3, 1.3),
				}):Play()
			end
			syncFill()
		end

		-- The kill effect sits exactly over the bar, above everything else in the bar.
		children.Burst = e("Frame", {
			Position = UDim2.fromOffset(0, BAR_Y),
			Size = UDim2.new(1, 0, 0, BAR_H),
			BackgroundTransparency = 1,
			ZIndex = z + 6,
		}, {
			Light = e(XpGainBurst, { pctRef = pctRef, onAbsorbed = onAbsorbed }),
		})
	end

	return e("Frame", {
		Size = UDim2.new(XP_WIDTH_SCALE, 0, 0, CONTAINER_H),
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		BackgroundTransparency = 1,
		ZIndex = z,
	}, {
		WidthConstraint = e("UISizeConstraint", {
			MinSize = Vector2.new(XP_WIDTH_MIN, 0),
			MaxSize = Vector2.new(XP_WIDTH_MAX, math.huge),
		}),
		Content = e("Frame", {
			-- Combat: the medallion hangs half its width left of the bar, so shift everything
			-- right by a quarter of it and the whole group reads centred.
			Position = UDim2.fromOffset(props.isCombat and WREATH_W / 4 or 0, 0),
			Size = UDim2.new(1, props.isCombat and -WREATH_W / 4 or 0, 1, 0),
			BackgroundTransparency = 1,
			ZIndex = z,
		}, children),
	})
end

--------------------------------------------------------------------------------

local function XpHud()
	-- bumped whenever XP changes or a bar is due to hide; drives re-render
	local version, setVersion = React.useState(0)
	local stackHeight, setStackHeight = React.useState(HudBottomLeftStack.GetHeight())
	local topBottom, setTopBottom = React.useState(HudTopCentre.Bottom())

	React.useEffect(function()
		local conn = HudTopCentre.Changed:Connect(function()
			setTopBottom(HudTopCentre.Bottom())
		end)
		return function() conn:Disconnect() end
	end, {})

	React.useEffect(function()
		local conn = HudBottomLeftStack.HeightChanged:Connect(setStackHeight)
		return function() conn:Disconnect() end
	end, {})

	React.useEffect(function()
		settleQuietChanges()
		return SkillXPShared.Subscribe(function()
			settleQuietChanges()
			setVersion(function(v) return v + 1 end)
		end)
	end, {})

	-- Schedule ONE re-render for the moment the soonest visible bar expires.
	-- Event-driven, so nothing polls while the HUD is idle.
	React.useEffect(function()
		local soonest: number? = nil
		for _, s in ipairs(SKILLS) do
			local hideAt = lastGain(s.key) + hideDelayFor(s.key)
			if hideAt > tick() and (soonest == nil or hideAt < soonest) then
				soonest = hideAt
			end
		end
		if soonest == nil then
			return
		end
		-- Do NOT use task.cancel here. Once the delay has fired the thread is
		-- dead, and task.cancel on a dead thread raises -- which kills the
		-- effect cleanup and stops every future re-render. Flag instead.
		local cancelled = false
		task.delay(soonest - tick() + 0.05, function()
			if cancelled then
				return
			end
			setVersion(function(v) return v + 1 end)
		end)
		return function()
			cancelled = true
		end
	end, { version })

	-- visible bars, most recently gained last (drawn on top)
	local now = tick()
	local shown = {}
	for _, s in ipairs(SKILLS) do
		local last = lastGain(s.key)
		if now - last < hideDelayFor(s.key) then
			table.insert(shown, { skill = s, last = last })
		end
	end
	table.sort(shown, function(a, b) return a.last < b.last end)

	local children: { [string]: any } = {}
	for i, entry in ipairs(shown) do
		local s = entry.skill
		local state = SkillXPShared[s.key]
		local isCombat = s.key == "Combat"
		children[s.key] = e(XpBar, {
			skillKey = s.key,
			label = s.label,
			level = state.Level,
			xp = state.XP,
			xpNeeded = SkillXPShared.GetXPForLevel(state.Level),
			zIndex = 5 + i * 8,
			position = isCombat and combatPosition(topBottom) or defaultPosition(stackHeight),
			anchorPoint = isCombat and COMBAT_ANCHOR or DEFAULT_ANCHOR,
			isCombat = isCombat,
		})
	end

	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, children)
end

return XpHud
