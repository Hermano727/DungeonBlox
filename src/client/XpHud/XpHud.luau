--!strict
--  XpHud -- React-lua port of the Combat / Mining / Fishing XP bars.
--
--  Replaces three near-identical imperative scripts (CombatXPClient,
--  FishingXPClient, and a copy-pasted block inside WoodenPickaxe/MiningScript)
--  that each ran their own `while task.wait(0.1)` loop walking GetDescendants()
--  on all three frames to juggle ZIndex. That polling is gone: render order is
--  derived from state, and the auto-hide is a single scheduled task.
--
--  This component READS state only. XP accumulation and level-ups still live in
--  the existing scripts, which write into SkillXPShared and stamp
--  player:SetAttribute("Last<Skill>XPGain", tick()). Deliberate -- it keeps the
--  migration reversible and means the StarterPack tool script is untouched.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Workspace         = game:GetService("Workspace")

local React              = require(ReplicatedStorage.Packages.React)
local SkillXPShared      = require(ReplicatedStorage:WaitForChild("SkillXPShared"))
local DecorationIcons    = require(ReplicatedStorage.Assets.Icons.Decorations.DecorationIcons)
local UIDevTuning        = require(ReplicatedStorage:WaitForChild("UIDevTuning"))

local e      = React.createElement
local player = Players.LocalPlayer

local HIDE_DELAY = 5          -- seconds of no XP before a Mining/Fishing bar fades out
-- Combat gets its own, shorter delay (2026-09-13, per direct request: "show for only
-- 2.5s instead of 5") -- Mining/Fishing are untouched, still HIDE_DELAY. Briefly bumped
-- to 3.2 alongside the first pass of the orb-burst hold/release rework, then reverted
-- back to 2.5 once that rework was corrected into the combo/stacking model below -- the
-- combo's own worst-case tail (HOLD_TIME + RELEASE_TEARDOWN_DELAY, see XpGainBurst) is
-- back under 2s, so the original 2.5s already covers it with room to spare.
local COMBAT_HIDE_DELAY = 2.5

-- Sized off EnergyBar's dynamic-viewport-width approach (F6-tuned, see
-- EnergyClient.lua). Originally 1.5x Energy's numbers, scaled back down
-- ~33% 2026-09-07 per feedback that it read too large -- nets out to
-- roughly parity with Energy's own width.
local XP_WIDTH_SCALE = 0.22
local XP_WIDTH_MIN, XP_WIDTH_MAX = 260, 460

-- Ornament border art (rbxassetid://70994554497816) -- same full-wrap
-- single-image treatment HealthBar/EnergyBar use (one image stretched over
-- the whole pill). This is the v2 asset, re-exported at 1023x341 (closer to
-- the pill's own aspect ratio than the original 1024x512 one) to reduce the
-- stretch-squash at small bar heights. Parented inside the Pill and sized as
-- pill-size-plus-padding, so it tracks the pill's own dynamic viewport-based
-- width automatically -- no resize listener needed.
local BRANCH_IMAGE = DecorationIcons.XP_BAR_BRANCH
local XP_BORDER_PAD_X, XP_BORDER_PAD_Y = 30, 12 -- base overhang at Border.Scale == 1, tune via F6

-- Combat bar only (2026-09-07, per direct request): replaces the "COMBAT" text
-- label with this icon, level number to its right, above the bar. The XP
-- amount moves from below the bar to centered inside it, HP-bar style.
local COMBAT_ICON_IMAGE = "rbxassetid://71642300678008"

local XpBorderTuning = UIDevTuning.Register("XpBar", {
    -- Approved 2026-09-07 via UIDevTool (F6) snapshot was Scale=2.130,
    -- OffsetX=-1, OffsetY=3 -- scaled down ~33% here to match the bar's own
    -- size reduction (see XP_WIDTH_*/PILL_H) so the ornament keeps the same
    -- proportions relative to the now-smaller pill.
    Border = { Scale = 1.420, OffsetX = -1, OffsetY = 2, Rotation = 0 },
})

-- Combat bar visibility (2026-09-13, per direct request): the "always visible for
-- review" TEMP override is gone, and so is a later "also force-show while the Skills
-- tab is open" version of that same idea -- that one caused this floating kill-triggered
-- bar to render at the same time as SkillsPanel's own Combat bar inside the Skills tab
-- (two Combat bars on screen at once, reported and reverted same day). The Combat bar
-- now ONLY shows for COMBAT_HIDE_DELAY after an actual kill, same lastGain/hideDelayFor
-- machinery every other skill bar uses -- no menu-open special case.
local COMBAT_POSITION = UDim2.new(0.5, 0, 0, 20)  -- top-center of the screen, per direct feedback (was dead-center, blocking the view)
local COMBAT_ANCHOR   = Vector2.new(0.5, 0)
local DEFAULT_POSITION = UDim2.new(0, 10, 1, -10)
local DEFAULT_ANCHOR   = Vector2.new(0, 1)

-- Palette lives in one table so the zone-theming work can swap it wholesale
-- rather than hunting Color3 literals. Semantic names, never geometry.
local THEME = {
    TrackBg     = Color3.fromRGB(20, 16, 13),   -- #14100D, pill interior
    PillBorder  = Color3.fromRGB(107, 66, 38),  -- #6B4226
    XpGreen     = Color3.fromRGB(78, 124, 54),  -- #4E7C36
    XpDot       = Color3.fromRGB(0, 0, 0),
    TextPrimary = Color3.fromRGB(240, 230, 210), -- #F0E6D2
}

local SKILLS = {
    { key = "Combat",  label = "Combat",  fill = Color3.fromRGB(150, 52, 40) },
    { key = "Mining",  label = "Mining",  fill = Color3.fromRGB(120, 104, 78) },
    { key = "Fishing", label = "Fishing", fill = Color3.fromRGB(64, 104, 118) },
}

local function lastGain(key: string): number
    return (player:GetAttribute("Last" .. key .. "XPGain") :: number?) or 0
end

local function hideDelayFor(key: string): number
    return key == "Combat" and COMBAT_HIDE_DELAY or HIDE_DELAY
end

--------------------------------------------------------------------------------

type BarProps = {
    label: string,
    fill: Color3,
    level: number,
    xp: number,
    xpNeeded: number,
    zIndex: number,
    position: UDim2,
    anchorPoint: Vector2,
    isCombat: boolean,
}

local function merge(a: { [string]: any }, b: { [string]: any }): { [string]: any }
    local out = table.clone(a)
    for k, v in pairs(b) do
        out[k] = v
    end
    return out
end

-- actual height dimension of xp bar shape -- was EnergyBar's 15px * 1.5,
-- scaled back down ~33% 2026-09-07, landing back close to EnergyBar's own
-- 15px trough height.
local PILL_H = 15
local DOT_COUNT = 12

-- Small evenly-spaced stars across the pill so the fill reads as segmented
-- "XP" progress rather than a plain solid gauge, matching the v5 mockup ask.
-- Text glyph, not an asset -- "*" renders fine in Gotham with no new art.
local function buildDots(zIndex: number)
    local dots: { [string]: any } = {}
    for i = 1, DOT_COUNT do
        local frac = i / (DOT_COUNT + 1)
        dots["Dot" .. i] = e("TextLabel", {
            Size = UDim2.fromOffset(10, 10),
            Position = UDim2.new(frac, 0, 0.5, 0),
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundTransparency = 1,
            Text = "\226\152\133", -- "★" (U+2605)
            TextColor3 = THEME.XpDot,
            TextTransparency = 0.45,
            TextScaled = true,
            Font = Enum.Font.GothamBold,
            ZIndex = zIndex,
        })
    end
    return dots
end

--------------------------------------------------------------------------------
--  XpGainBurst -- a COMBO effect (corrected 2026-09-13 after an initial misread of the
--  request -- see below): every kill adds a handful of small light-blue orbs to ONE
--  shared, growing pool and resets a single shared hold timer. Only once that timer
--  actually runs out with no further kill does the WHOLE accumulated pool feed into
--  the bar together, with a small flash on the bar once they land. Kill 10 mobs
--  back-to-back with the timer never lapsing, and all 10 kills' worth of orbs stack up
--  and sink into the bar as one payoff -- not 10 separate little bursts. Combat-only,
--  per direct request (2026-09-13): "light blue orbs appearing around the xp bar...
--  and then they quickly feed into the bar as if they were funneling into it...
--  varying sizes and random placement (but still kind of marble bag placement)".
--
--  First pass (still 2026-09-13) gave every kill its OWN independent hold-then-feed
--  timeline running in parallel, which fixed the original replay bug (a kill landing
--  before the previous burst finished was correctly no longer dropped) but wasn't the
--  actual ask -- direct follow-up: "i meant of it as kind of a combo effect... if the
--  player kills say 10 mobs and not a single time the 2.0 timer lets up between all
--  those 10 kills, then the result will be the blue orbs stacking 10 fold before
--  sinking it." This version keeps the "never drop a kill" fix (still listens for
--  player:GetAttributeChangedSignal("LastCombatXPGain") directly rather than firing
--  once per mount) but replaces the parallel-batches model with one growing `pool`
--  (a plain ref, not React state -- see `bump()`) that every kill appends to and
--  resets the shared HOLD_TIME countdown for, via a token-based debounce (`holdToken`)
--  so only the LAST scheduled check (from the most recent kill) actually fires the
--  release. A kill landing after a release has already started (pool handed off to
--  `releases`, a separate generation-keyed set so multiple releases could in principle
--  overlap) just starts accumulating a brand new pool from zero.
--------------------------------------------------------------------------------
-- Tuned 2026-09-13 per direct request: dots last 50% longer, spawn 2x farther out
-- ("right now its too close"), plus a small flash on the bar itself when they converge.
-- Orb look, redesigned 2026-09-14 (2nd pass -- 1st pass's flat fill + same-hue "glow"
-- stroke bled into a light-blue sky with zero contrast; the follow-up dark-ring fix for
-- that then looked like a bland ball with a cartoon outline, no depth, per direct
-- feedback). This pass builds an actual lit-sphere look instead of a flat tinted disc:
--   * Shade    -- a vertical light-to-dark gradient across the fill (lit top, shaded
--                 bottom), so the orb reads as a rounded 3D marble, not a flat circle.
--   * Rim      -- a thin, mostly-opaque dark-navy stroke. This is the actual fix for the
--                 original sky-blend bug: a real contrast edge against ANY background,
--                 kept thin/soft so it reads as shading rather than a pen outline.
--   * Highlight-- a small bright dot offset toward one corner (a genuine specular glint,
--                 not a gradient stop -- a subtle gradient alone doesn't read at 5-15px).
local BURST_COLOR       = Color3.fromRGB(110, 190, 255) -- core tone
local BURST_COLOR_LIGHT = Color3.fromRGB(220, 242, 255) -- lit top of the sphere
local BURST_COLOR_DARK  = Color3.fromRGB(30, 105, 185)  -- shaded underside of the sphere
local BURST_RIM_COLOR   = Color3.fromRGB(8, 32, 64)     -- dark navy rim -- the contrast fix
local BURST_RIM_THICKNESS = 1
local BURST_RIM_TRANSPARENCY = 0.25
local BURST_HIGHLIGHT_COLOR = Color3.fromRGB(255, 255, 255)
-- Soft glow halo -- a "lit particle" look, not lighting. A bigger, very transparent
-- circle sitting behind the fill (child, so it auto-shrinks/fades in lockstep with the
-- orb's own convergence tween with no extra ref/tween needed) -- reads as a gentle bloom
-- around the orb, like Roblox's glow-on-an-object look, without an image asset or a
-- real light source.
local BURST_GLOW_SCALE = 2.1
local BURST_GLOW_TRANSPARENCY = 0.8

-- Tightened 2026-09-14 (was 190/100) -- per direct feedback the dots should hug the bar
-- like a "marble bag" scattered just around it, not spray across the whole screen.
-- getSafeBounds below additionally clamps this per-kill to whatever room actually exists
-- between the bar and the real screen edges, so orbs can never spawn off-viewport
-- regardless of window size or how close to the top of the screen the bar itself sits.
local BURST_SPREAD_X, BURST_SPREAD_Y = 130, 80 -- was 190, 100 -- scatter radius around the bar's center, px
local BURST_EDGE_MARGIN = 24 -- keep orbs at least this many px clear of the true screen edge
local BURST_MIN_SIZE, BURST_MAX_SIZE = 5, 15
local BURST_CONVERGE_TIME = 0.57 -- was 0.38 (*1.5)
local BURST_MAX_STAGGER = 0.16 -- per-orb random extra delay once a release starts feeding --
                                -- this is what makes a release "stream" in one after another
                                -- instead of every orb in it snapping inward on the same frame

-- Every kill adds ORBS_PER_KILL orbs to the shared pool and resets HOLD_TIME (2026-09-13,
-- per direct request, combo-corrected as described above). ORBS_PER_KILL was cut to
-- roughly a third of the old flat 17-orb count ("decrease the number of orbs by 2/3 per
-- kill (so 33% of what it is now)") since a real combo can now stack several kills'
-- worth at once -- a 10-kill streak still lands ~60 orbs in one release even at this
-- lower per-kill rate. HOLD_TIME cut from 2.0 to 1.0, also per direct request.
local ORBS_PER_KILL = 6 -- was a flat 17-orb burst; 17 * (1/3) = 5.67, rounded up
local HOLD_TIME = 1.0 -- was 2.0

-- The bar's own visible content (icon + "LVL n" row above the pill, plus the pill
-- itself) must never have orbs spawn on top of it (2026-09-13, per direct request:
-- "right now the orbs are able to spawn OVER the combat xp bar... this should not be
-- the case, avoid that area... if its easier to just make a rectangle of where in the
-- viewport its not able to spawn... do that"). Implemented as a keepout BAND across
-- the orb scatter's full width rather than a box matched to the bar's actual (viewport-
-- dependent) rendered width -- simpler, and BURST_SPREAD_X already scatters wider than
-- the bar in most viewports anyway, so a full-width vertical band covers it regardless
-- of the exact bar width at runtime. Coordinates are dy offsets from the Burst frame's
-- local origin, which sits at the PILL's own center (title row sits above that origin,
-- hence the asymmetric top/bottom numbers) -- see rollOrbY below for how orbs avoid it.
local BAR_KEEPOUT_TOP, BAR_KEEPOUT_BOTTOM = -60, 12

-- Bar-flash fires once a release has mostly converged -- timed at the average landing
-- moment across that release's staggered orbs (not the first orb in, not the last).
local FLASH_TRIGGER_DELAY = BURST_CONVERGE_TIME + BURST_MAX_STAGGER * 0.5
local FLASH_FADE_TIME = 0.18
local FLASH_COLOR = Color3.fromRGB(255, 255, 255)
local FLASH_TWEEN_INFO = TweenInfo.new(FLASH_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- How long after a release starts its Frames can be torn down -- long enough to clear
-- both the longest-tailed orb's convergence tween AND the flash fade it triggers,
-- whichever finishes later, or one of them gets cut off mid-animation. Unlike the old
-- per-batch version, HOLD_TIME has already elapsed BEFORE a release starts (it's what
-- triggers the release), so it's not part of this tail at all.
local RELEASE_TEARDOWN_DELAY = math.max(BURST_MAX_STAGGER + BURST_CONVERGE_TIME, FLASH_TRIGGER_DELAY + FLASH_FADE_TIME) + 0.1
local BURST_TWEEN_INFO = TweenInfo.new(BURST_CONVERGE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

-- Per-kill safe scatter bounds: the intersection of the "desired" tight spread
-- (BURST_SPREAD_X/Y) with however much room actually exists between the bar's real
-- on-screen position and the true viewport edges right now. Fixes orbs spawning off the
-- top/sides of the screen (2026-09-14, per direct feedback) -- the bar sits close to the
-- top of the screen (COMBAT_POSITION), so a fixed pixel spread could push orbs above y=0
-- on some window sizes with no regard for how little room was actually there. Falls back
-- to the plain fixed spread if the root Frame hasn't laid out yet (e.g. the very first
-- kill firing before the ref/AbsoluteSize are valid) rather than producing garbage bounds.
local function getSafeBounds(rootRef: { current: Frame? }): (number, number, number, number)
    local root = rootRef.current
    local camera = Workspace.CurrentCamera
    if not root or not camera or root.AbsoluteSize.X <= 0 or root.AbsoluteSize.Y <= 0 then
        return -BURST_SPREAD_X, BURST_SPREAD_X, -BURST_SPREAD_Y, BURST_SPREAD_Y
    end
    local viewport = camera.ViewportSize
    local centerX = root.AbsolutePosition.X + root.AbsoluteSize.X * 0.5
    local centerY = root.AbsolutePosition.Y + root.AbsoluteSize.Y * 0.5
    local minDx = math.max(-BURST_SPREAD_X, -(centerX - BURST_EDGE_MARGIN))
    local maxDx = math.min(BURST_SPREAD_X, viewport.X - centerX - BURST_EDGE_MARGIN)
    local minDy = math.max(-BURST_SPREAD_Y, -(centerY - BURST_EDGE_MARGIN))
    local maxDy = math.min(BURST_SPREAD_Y, viewport.Y - centerY - BURST_EDGE_MARGIN)
    return minDx, maxDx, minDy, maxDy
end

-- Rolls a Y offset within [minDy, maxDy] and, if it landed inside the bar's own keepout
-- band, pushes it out to whichever side of that band it started closer to (a
-- deterministic push, not an unbounded reroll loop) -- clamped to whatever span still
-- fits within the safe bounds on that side, so this stays correct even on a cramped
-- viewport where one side of the keepout band has little or no room left.
local function rollOrbY(minDy: number, maxDy: number): number
    if maxDy <= minDy then
        return minDy
    end
    local dy = minDy + math.random() * (maxDy - minDy)
    if dy > BAR_KEEPOUT_TOP and dy < BAR_KEEPOUT_BOTTOM then
        local topLo, topHi = minDy, math.min(BAR_KEEPOUT_TOP, maxDy)
        local bottomLo, bottomHi = math.max(BAR_KEEPOUT_BOTTOM, minDy), maxDy
        local topSpan = math.max(topHi - topLo, 0)
        local bottomSpan = math.max(bottomHi - bottomLo, 0)
        if dy < (BAR_KEEPOUT_TOP + BAR_KEEPOUT_BOTTOM) / 2 and topSpan > 0 then
            dy = topLo + math.random() * topSpan
        elseif bottomSpan > 0 then
            dy = bottomLo + math.random() * bottomSpan
        elseif topSpan > 0 then
            dy = topLo + math.random() * topSpan
        else
            dy = minDy -- degenerate: no room on either side of the keepout band at all
        end
    end
    return dy
end

-- "marble bag" placement: independent random (x, y) offsets and sizes per orb, not a
-- grid/ring -- rolled once per kill (within this kill's safe bounds) and appended to the
-- shared pool.
local function makeKillOrbs(minDx: number, maxDx: number, minDy: number, maxDy: number)
    local list = {}
    for i = 1, ORBS_PER_KILL do
        list[i] = {
            dx = minDx + math.random() * math.max(maxDx - minDx, 0),
            dy = rollOrbY(minDy, maxDy),
            size = BURST_MIN_SIZE + math.random() * (BURST_MAX_SIZE - BURST_MIN_SIZE),
            startDelay = math.random() * BURST_MAX_STAGGER,
            startTransparency = 0.05 + math.random() * 0.25,
        }
    end
    return list
end

-- Shared visual for one orb Frame -- used for both the accumulating pool and every
-- in-flight release below so the two never drift apart (they used to be two separately
-- hand-written e("Frame", {...}) blocks). `setRef` is whichever per-orb ref-capture
-- closure that call site needs (pool vs. a specific release's frame list).
local function renderOrb(orb, setRef)
    return e("Frame", {
        ref = setRef,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, orb.dx, 0.5, orb.dy),
        Size = UDim2.fromOffset(orb.size, orb.size),
        BackgroundColor3 = BURST_COLOR,
        BackgroundTransparency = orb.startTransparency,
        BorderSizePixel = 0,
        ZIndex = 20,
    }, {
        Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
        -- Glow halo -- a child (not a sibling) so its Scale-based Size shrinks/fades
        -- automatically as the parent orb's own Size/Transparency tween down during
        -- convergence, with no separate ref or tween of its own. Drawn first among the
        -- Frame children (ZIndex 1) so Rim/Highlight stay crisp on top of it.
        Glow = e("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromScale(BURST_GLOW_SCALE, BURST_GLOW_SCALE),
            BackgroundColor3 = BURST_COLOR_LIGHT,
            BackgroundTransparency = BURST_GLOW_TRANSPARENCY,
            BorderSizePixel = 0,
            ZIndex = 1,
        }, {
            Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
        }),
        -- Sphere shading -- lit top fading to a shaded underside -- so the fill reads as
        -- a rounded lit marble instead of a flat tinted disc.
        Shade = e("UIGradient", {
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, BURST_COLOR_LIGHT),
                ColorSequenceKeypoint.new(0.5, BURST_COLOR),
                ColorSequenceKeypoint.new(1, BURST_COLOR_DARK),
            }),
            Rotation = 90,
        }),
        -- Rim: the actual contrast-against-any-background fix, kept thin/soft so it
        -- reads as shading rather than a cartoon ink outline.
        Rim = e("UIStroke", {
            Color = BURST_RIM_COLOR,
            Transparency = BURST_RIM_TRANSPARENCY,
            Thickness = BURST_RIM_THICKNESS,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        }),
        -- Specular glint -- a distinct small bright shape reads as "shiny" even at these
        -- pixel sizes, where a gradient stop alone was too subtle to notice.
        Highlight = e("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.3, 0.28),
            Size = UDim2.fromScale(0.42, 0.42),
            BackgroundColor3 = BURST_HIGHLIGHT_COLOR,
            BackgroundTransparency = 0.35,
            BorderSizePixel = 0,
            ZIndex = 2,
        }, {
            Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
        }),
    })
end

local function XpGainBurst()
    -- The pool (accumulating orbs, held until release) and releases (generations
    -- currently feeding into the bar, keyed by an incrementing id) are plain refs, not
    -- React state -- `bump` is what forces a re-render after mutating either one. This
    -- sidesteps ever needing to schedule tweens or touch other refs from inside a
    -- setState updater, which real React (and by extension react-lua) expects to stay
    -- pure. `poolFrameRefs`/`releaseFrameRefs` are the actual Roblox Frame refs TweenService
    -- animates; `holdToken` is a debounce counter -- every kill bumps it, and a
    -- HOLD_TIME-delayed check only releases if no LATER kill has bumped it since.
    local pool = React.useRef({} :: { any })
    local releases = React.useRef({} :: { [number]: { orbs: { any } } })
    local poolFrameRefs = React.useRef({} :: { [number]: Frame })
    local releaseFrameRefs = React.useRef({} :: { [number]: { [number]: Frame } })
    local flashRef = React.useRef(nil :: Frame?)
    local rootRef = React.useRef(nil :: Frame?) -- feeds getSafeBounds' on-screen position/size read
    local holdToken = React.useRef(0)
    local nextReleaseId = React.useRef(0)
    local _tick, setTick = React.useState(0)

    local function bump()
        setTick(function(v)
            return v + 1
        end)
    end

    React.useEffect(function()
        local cancelled = false

        local function releasePool()
            local orbs = pool.current
            if #orbs == 0 then
                return
            end
            pool.current = {}
            poolFrameRefs.current = {}

            nextReleaseId.current += 1
            local id = nextReleaseId.current
            releaseFrameRefs.current[id] = {}
            releases.current[id] = { orbs = orbs }
            bump()

            for i, orb in ipairs(orbs) do
                task.delay(orb.startDelay, function()
                    if cancelled then
                        return
                    end
                    local refs = releaseFrameRefs.current[id]
                    local inst = refs and refs[i]
                    if inst then
                        TweenService:Create(inst, BURST_TWEEN_INFO, {
                            Position = UDim2.fromScale(0.5, 0.5),
                            Size = UDim2.fromOffset(0, 0),
                            BackgroundTransparency = 1,
                        }):Play()
                    end
                end)
            end

            -- Small flash on the bar itself once this release has mostly converged
            -- (2026-09-13, per direct request: "if u can add a small flash on the xp
            -- bar when the orbs reach the bar that would be cool"). One shared Flash
            -- overlay, just retriggered per release -- a second flash while the first
            -- is still fading simply brightens it again, reads fine as "more XP landed."
            task.delay(FLASH_TRIGGER_DELAY, function()
                if cancelled then
                    return
                end
                local flash = flashRef.current
                if not flash then
                    return
                end
                flash.BackgroundTransparency = 0.4
                TweenService:Create(flash, FLASH_TWEEN_INFO, {
                    BackgroundTransparency = 1,
                }):Play()
            end)

            task.delay(RELEASE_TEARDOWN_DELAY, function()
                if cancelled then
                    return
                end
                releaseFrameRefs.current[id] = nil
                releases.current[id] = nil
                bump()
            end)
        end

        local function onKill()
            if cancelled then
                return
            end
            local minDx, maxDx, minDy, maxDy = getSafeBounds(rootRef)
            local newOrbs = makeKillOrbs(minDx, maxDx, minDy, maxDy)
            local orbs = pool.current
            table.move(newOrbs, 1, #newOrbs, #orbs + 1, orbs)
            bump()

            holdToken.current += 1
            local myToken = holdToken.current
            task.delay(HOLD_TIME, function()
                if cancelled then
                    return
                end
                -- Only fires if no later kill has bumped holdToken since this delay was
                -- scheduled -- i.e. this really was the last kill in the combo.
                if holdToken.current == myToken then
                    releasePool()
                end
            end)
        end

        -- The kill that made the Combat bar (and this component) mount in the first
        -- place doesn't fire a change signal -- the attribute already changed before
        -- we connected -- so run it explicitly, then listen for every kill after that.
        onKill()
        local conn = player:GetAttributeChangedSignal("LastCombatXPGain"):Connect(onKill)

        return function()
            cancelled = true
            conn:Disconnect()
        end
    end, {})

    local orbElements: { [string]: any } = {
        -- Full-pill flash overlay, rounded to match the pill's own shape (a plain
        -- Frame doesn't inherit the Pill's UICorner, so it needs its own). Kept
        -- mounted at all times (even with an empty pool) so it doesn't need to be
        -- recreated -- and flashRef re-bound -- on every single kill.
        Flash = e("Frame", {
            ref = function(inst)
                flashRef.current = inst
            end,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromScale(1, 1),
            BackgroundColor3 = FLASH_COLOR,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ZIndex = 21,
        }, {
            Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
        }),
    }
    for i, orb in ipairs(pool.current) do
        orbElements["Pool_Orb" .. i] = renderOrb(orb, function(inst)
            poolFrameRefs.current[i] = inst
        end)
    end
    for releaseId, release in pairs(releases.current) do
        for i, orb in ipairs(release.orbs) do
            local key = string.format("R%d_Orb%d", releaseId, i)
            orbElements[key] = renderOrb(orb, function(inst)
                local refs = releaseFrameRefs.current[releaseId]
                if refs then
                    refs[i] = inst
                end
            end)
        end
    end

    return e("Frame", {
        ref = rootRef,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        ZIndex = 20,
    }, orbElements)
end

local function XpBar(props: BarProps)
    local pct = math.clamp(props.xp / math.max(props.xpNeeded, 1), 0, 1)

    -- Live-tunable via UIDevTool (F6 by default) -- re-renders this bar
    -- whenever the tuning numbers change, no code redeploy needed.
    local borderTuning, setBorderTuning = React.useState(XpBorderTuning:Get())
    React.useEffect(function()
        return XpBorderTuning:Subscribe(function()
            setBorderTuning(XpBorderTuning:Get())
        end)
    end, {})
    local b = borderTuning.Border
    local borderPadX = XP_BORDER_PAD_X * b.Scale
    local borderPadY = XP_BORDER_PAD_Y * b.Scale

    -- Title row above the pill: Combat gets the icon + "LVL n" (2026-09-07,
    -- per direct request); every other skill keeps the plain text label.
    local titleRow
    if props.isCombat then
        titleRow = e("Frame", {
            LayoutOrder = 1,
            Size = UDim2.new(1, 0, 0, 38),
            BackgroundTransparency = 1,
            ZIndex = props.zIndex,
        }, {
            Layout = e("UIListLayout", {
                FillDirection = Enum.FillDirection.Horizontal,
                HorizontalAlignment = Enum.HorizontalAlignment.Center,
                VerticalAlignment = Enum.VerticalAlignment.Center,
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, 8),
            }),
            -- 33% bigger (2026-09-08, per direct request).
            Icon = e("ImageLabel", {
                LayoutOrder = 1,
                Size = UDim2.fromOffset(28 * 1.33, 28 * 1.33),
                BackgroundTransparency = 1,
                Image = COMBAT_ICON_IMAGE,
                ScaleType = Enum.ScaleType.Fit,
                ZIndex = props.zIndex,
            }),
            -- AutomaticSize (2026-09-08, per direct feedback: "the lvl 1 is
            -- perfectly centered but that doesnt put into account the
            -- icon"). The old fixed 100px-wide box left the actual "LVL n"
            -- glyphs sitting at its left edge with empty space trailing --
            -- UIListLayout centered that whole box-plus-whitespace as a
            -- group, so the VISIBLE icon+text combo read as shifted left of
            -- true center. Auto-sizing the box to the text's real width
            -- makes the centered group's box exactly match its visible
            -- content, so icon+text center together correctly.
            LevelText = e("TextLabel", {
                LayoutOrder = 2,
                AutomaticSize = Enum.AutomaticSize.X,
                Size = UDim2.new(0, 0, 0, 28),
                BackgroundTransparency = 1,
                Text = string.format("LVL %d", props.level),
                TextColor3 = THEME.TextPrimary,
                TextStrokeColor3 = Color3.new(0, 0, 0),
                TextStrokeTransparency = 0,
                TextXAlignment = Enum.TextXAlignment.Center,
                TextSize = 26,
                Font = Enum.Font.GothamBold,
                ZIndex = props.zIndex,
            }),
        })
    else
        titleRow = e("TextLabel", {
            LayoutOrder = 1,
            Size = UDim2.new(1, 0, 0, 24),
            BackgroundTransparency = 1,
            Text = string.format("%s  LV %d", string.upper(props.label), props.level),
            TextColor3 = THEME.TextPrimary,
            TextTransparency = 0.25,
            TextStrokeColor3 = Color3.new(0, 0, 0),
            TextStrokeTransparency = 0,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextSize = 26,
            Font = Enum.Font.GothamBold,
            ZIndex = props.zIndex,
        })
    end

    -- Combat only: the XP amount moves INSIDE the pill (centered, HP-bar
    -- style) instead of below it, with the same black drop-shadow treatment
    -- HealthClient uses for its HP number -- an offset clone rather than a
    -- stroke, so it reads as a shadow.
    local inPillAmount = {}
    if props.isCombat then
        local amountStr = string.format("%d / %d", props.xp, props.xpNeeded)
        inPillAmount.AmountShadow = e("TextLabel", {
            Size = UDim2.new(1, 0, 1, 0),
            Position = UDim2.fromOffset(1, 1),
            BackgroundTransparency = 1,
            Text = amountStr,
            TextColor3 = Color3.new(0, 0, 0),
            TextTransparency = 0.5,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextYAlignment = Enum.TextYAlignment.Center,
            TextSize = 13,
            Font = Enum.Font.GothamBold,
            ZIndex = props.zIndex + 4,
        })
        inPillAmount.AmountText = e("TextLabel", {
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundTransparency = 1,
            Text = amountStr,
            TextColor3 = THEME.TextPrimary,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextYAlignment = Enum.TextYAlignment.Center,
            TextSize = 13,
            Font = Enum.Font.GothamBold,
            ZIndex = props.zIndex + 5,
        })
    end

    -- Below-pill amount label: every other skill keeps this; Combat no
    -- longer needs it since its amount now lives inside the pill.
    local belowAmount = nil
    if not props.isCombat then
        belowAmount = e("TextLabel", {
            LayoutOrder = 3,
            Size = UDim2.new(1, 0, 0, 28),
            BackgroundTransparency = 1,
            Text = string.format("%d / %d XP", props.xp, props.xpNeeded),
            TextColor3 = THEME.TextPrimary,
            TextStrokeColor3 = Color3.new(0, 0, 0),
            TextStrokeTransparency = 0,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextSize = 24,
            Font = Enum.Font.GothamBold,
            ZIndex = props.zIndex,
        })
    end

    local pillFrameProps = {
        LayoutOrder = 2,
        Size = UDim2.new(1, 0, 0, PILL_H),
        BackgroundColor3 = THEME.TrackBg,
        BorderSizePixel = 0,
        ZIndex = props.zIndex,
    }

    local pillChildren = merge(merge({
        Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
        Stroke = e("UIStroke", {
            Color = THEME.PillBorder,
            Thickness = 2, -- subtle on purpose -- the BRANCH art is what should read as the wrap, not this line
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        }),
        Fill = e("Frame", {
            Size = UDim2.fromScale(pct, 1),
            BackgroundColor3 = THEME.XpGreen,
            BorderSizePixel = 0,
            ZIndex = props.zIndex + 1,
        }, {
            Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
        }),

        -- Single full-wrap border image, matching HealthBar/EnergyBar's
        -- border style -- stretched over the whole pill instead of two
        -- mirrored corner ornaments.
        Border = e("ImageLabel", {
            Image = BRANCH_IMAGE,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Size = UDim2.new(1, borderPadX * 2, 1, borderPadY * 2),
            Position = UDim2.new(0.5, b.OffsetX, 0.5, b.OffsetY),
            Rotation = b.Rotation,
            BackgroundTransparency = 1,
            ScaleType = Enum.ScaleType.Stretch,
            ZIndex = props.zIndex + 3,
        }),
    }, buildDots(props.zIndex + 2)), inPillAmount)

    -- Funnel-in orb flash -- Combat only (see XpGainBurst's doc comment). Sits inside
    -- the Pill frame (not the outer UIListLayout'd stack) so it can freely position
    -- itself beyond the pill's own bounds without fighting the list layout, same
    -- trick the Border image above already relies on.
    if props.isCombat then
        pillChildren.Burst = e(XpGainBurst)
    end

    -- No panel/card container anymore -- just the stacked label / pill /
    -- amount, per the v5 mockup. AutomaticSize on Y so the stack's total
    -- height follows the UIListLayout instead of a hand-summed constant.
    return e("Frame", {
        Size = UDim2.new(XP_WIDTH_SCALE, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Position = props.position,
        AnchorPoint = props.anchorPoint,
        BackgroundTransparency = 1,
        ZIndex = props.zIndex,
    }, {
        WidthConstraint = e("UISizeConstraint", {
            MinSize = Vector2.new(XP_WIDTH_MIN, 0),
            MaxSize = Vector2.new(XP_WIDTH_MAX, math.huge),
        }),
        Layout = e("UIListLayout", {
            FillDirection = Enum.FillDirection.Vertical,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 6),
        }),

        Label = titleRow,

        Pill = e("Frame", pillFrameProps, pillChildren),

        Amount = belowAmount,
    })
end

--------------------------------------------------------------------------------

local function XpHud()
    -- bumped whenever XP changes or a bar is due to hide; drives re-render
    local version, setVersion = React.useState(0)

    React.useEffect(function()
        return SkillXPShared.Subscribe(function()
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
            label = s.label,
            fill = s.fill,
            level = state.Level,
            xp = state.XP,
            xpNeeded = SkillXPShared.GetXPForLevel(state.Level),
            zIndex = 5 + i * 2,
            position = isCombat and COMBAT_POSITION or DEFAULT_POSITION,
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
