--[[
    BossHealthBar
    Top-middle screen HP bar shown while a named elite (e.g. Kane the
    Enraged) is active for this player -- added 2026-09-14 alongside the
    first named-elite mob. Distinct from:
      - MobHPBarUI's floating BillboardGui bar above the mob in 3D space --
        named elites (MobData's IsNamedElite flag) explicitly SKIP that one
        now (see MobClass.lua's CreateHPBar), so this is their only HP
        readout, not an addition to it.
      - HealthClient's bottom-stack "ElitePityFrame" (that one shows the
        PRE-spawn pity/chance build-up only now -- it used to also double as
        a small HP readout once active, removed per direct request now that
        this bar is the one real HP readout for named elites).

    Reads the same server-authoritative attributes MobManager.server.lua
    already broadcasts every Heartbeat for the bottom-stack bar:
      EliteActive, EliteCurrentHealth, EliteMaxHealth, CurrentEliteMobId
    (CurrentEliteMobId is kept pointed at the REAL active mob's own MobID
    while EliteActive is true, not just whichever id the current zone is
    configured for -- see MobManager.server.lua's OnHeartbeat comment).

    2026-09-14 rework (direct request, "make a VERY LONG health bar... add
    the ornament... you can imagine the bar goes INSIDE the slot of the
    ornament"): grown from a modest 320-560px readout to a near-full-
    viewport boss bar, framed by the gold/dragon ornament art
    (rbxassetid://86385543900543), with the REAL bar living inside the
    ornament's own dark trough -- not two separate bracket end-caps (an
    earlier pass here tried that; direct feedback: "you messed up the point
    of the ornament... it goes OVER the bar and we just draw the hp bar of
    the boss inside the holder").

    Inspected the actual asset via EditableImage/ReadPixelsBuffer (Studio
    command bar) to get this right instead of eyeballing a screenshot:
      - True size 1023x341px (aspect ratio exactly 3.0) -- ornamentRow's
        height is driven off this so ScaleType.Stretch is safe (never
        distorts the art) at ANY bar width -- see updateOrnamentRowHeight.
      - The trough is BAKED-IN opaque art (flat dark color), not a
        transparent cutout, in the source asset.

    2026-09-14, second pass (direct request): the bar is TWO independent
    segments, not one continuous fill:
      - RIGHT segment = the FIRST 50% of HP (100%->50%): full at full HP,
        drains to empty as HP drops from 100% to 50%.
      - LEFT segment = the LAST 50% of HP (50%->0%): stays full the whole
        time the right segment is draining, then itself drains from full to
        empty as HP drops from 50% to 0%.
      Each half is its own HealthBarFX controller fed its own (current, max)
      pair scoped to that half's HP range (see refresh()) -- NOT the same
      controller fed a pre-split ratio -- so each half's shake/flash/chunk-
      preview correctly reacts only to damage that actually lands within
      its own range, and stays inert otherwise (e.g. a hit that only drops
      HP from 90% to 70% never touches the left/last-50% bar at all). This
      is deliberately plain data (no "phase" state machine) so a future
      Rage-mode trigger (e.g. "once the left segment starts draining") has
      an obvious, cheap read: whether the right segment's ratio has hit 0.
      Nothing consumes that yet -- rage mode itself does nothing for now.

    2026-09-14, third pass (direct request, "I want to do this properly...
    cleanly integrated with the image", after discussing and rejecting a
    10-image sprite-sheet approach as the wrong tool here): the fill bars
    now render BEHIND the ornament, with the ornament's own trough made
    genuinely transparent at runtime -- see buildMaskedOrnamentImage()
    below -- instead of the fill sitting on top approximating the trough's
    color/shape. This is the same layering HealthClient's HP_BORDER_IMAGE
    already uses for the player's own HP bar (frame on top masks the fill's
    edges), just generated procedurally: EditableImage can both read AND
    write pixels, and ImageLabel.ImageContent can point at a live
    EditableImage via Content.fromObject -- confirmed working live in
    Studio (screenshot-verified against a bright test backdrop) before this
    was wired in, no external image editor or asset re-upload needed. The
    dragon's snout, being real opaque art sitting on the now-topmost
    ornament layer, naturally occludes the fill wherever it overlaps --
    the small gap between the two segments (SLOT_GAP_FRACTION) is now just
    a light aesthetic buffer, not load-bearing for dragon visibility the
    way it was in the second pass above.

    The HP text moved from overlaying the bar to its own line directly under
    the name (titleBlock below) once the bar became two segments -- there's
    no single natural place to overlay one "current/max" string across a
    split bar.

    Registered with UIDevTuning ("BossHealthBar") so F6's UIDevTool can
    live-nudge the overall bar and the trough's slot placement independently
    -- see UIDevTool.client.lua's header comment for controls. The Slot
    target scales/positions the WHOLE composite (both halves + the gap
    between them) symmetrically, same as when it was one piece. The SLOT_*
    constants below are measured/eyeballed, not gospel -- nudge live and
    hand-copy a snapshot back here once it lines up exactly.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetService = game:GetService("AssetService")

local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local MobData = require(ReplicatedStorage:WaitForChild("MobData"))
local UIDevTuning = require(ReplicatedStorage:WaitForChild("UIDevTuning"))
local HealthBarFX = require(ReplicatedStorage:WaitForChild("HealthBarFX"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Near-full-viewport per direct request ("enlarge it so it spawns almost
-- the whole viewport"). MIN/MAX still clamp it sane on very small/ultrawide
-- windows -- same auto-scaling pattern as HealthClient/EnergyClient.
-- Baked in from a live UIDevTool (F6) snapshot approved 2026-09-14
-- (Scale=0.570, OffsetY=-12 on top of the previous 0.82/900/1500/24) --
-- "Bar"'s registered default below is reset back to identity so future
-- tuning starts fresh from this new baseline.
local BAR_WIDTH_SCALE = 0.467
local BAR_WIDTH_MIN, BAR_WIDTH_MAX = 513, 855
local TOP_OFFSET = 12

-- Real pixel size of rbxassetid://86385543900543, measured via
-- EditableImage in Studio -- see header comment. Locks ornamentRow's own
-- aspect ratio so ScaleType.Stretch never distorts the art.
local ORNAMENT_IMAGE = "rbxassetid://86385543900543"
local ORNAMENT_ASPECT_RATIO = 1023 / 341

-- The trough's rectangle as a fraction of the ornament image's own
-- width/height, measured off the real pixels then hand-tuned live twice
-- (widened 5%, height shortened 20% then another 10% -- both centered).
-- Live-tunable via F6's "Slot" target on top of these -- not gospel.
local SLOT_BASE_X_MIN, SLOT_BASE_X_MAX = 0.08, 0.92
local SLOT_BASE_Y_MIN, SLOT_BASE_Y_MAX = 0.408, 0.557
local SLOT_BASE_CENTER_X = (SLOT_BASE_X_MIN + SLOT_BASE_X_MAX) / 2
local SLOT_BASE_CENTER_Y = (SLOT_BASE_Y_MIN + SLOT_BASE_Y_MAX) / 2
local SLOT_BASE_W = SLOT_BASE_X_MAX - SLOT_BASE_X_MIN
local SLOT_BASE_H = SLOT_BASE_Y_MAX - SLOT_BASE_Y_MIN

-- Fraction of the composite slot's width left open as a gap between the two
-- halves. Small now that the ornament (see below) genuinely occludes the
-- fill via real alpha compositing -- this is just a light aesthetic buffer
-- between the two segments, not load-bearing for dragon visibility the way
-- it was before the trough became transparent. Not F6-tunable (yet); a
-- plain constant since it's a one-time layout choice.
local SLOT_GAP_FRACTION = 0.03

-- Trough alpha-cutout -- see header comment (third pass) for why this is
-- generated at runtime instead of a hand-edited asset. Region is a generous
-- pixel rect around the measured trough (SLOT_* above is the tighter
-- placement rect for our own fill bars, in fractional coordinates -- this
-- is the same area in raw pixel coordinates, padded a bit wider so no edge
-- pixel is missed).
local MASK_REGION_X, MASK_REGION_Y = 20, 115
local MASK_REGION_W, MASK_REGION_H = 1000, 100
-- Reference sample column for the per-row background-subtraction below --
-- measured this session to sit inside the trough band the whole way down
-- without ever intersecting the dragon (dragon's own measured horizontal
-- extent is x=371..650).
local MASK_REF_X = 150
-- Channel-distance tolerance for "this pixel matches this row's background
-- color" (sum of |dr|+|dg|+|db|, 0-765 range). Tuned live in Studio
-- (screenshot-verified against a bright test backdrop): 40 left visible
-- fleck residue along the trough's top/bottom edge highlight line, 70
-- cleaned up the top edge with no visible damage to the dragon/diamonds; a
-- faint line remains along the very bottom edge but reads as intentional
-- inset-panel shading, not masking failure.
local MASK_THRESHOLD = 70

-- Builds a mutated COPY of the ornament asset (never touches the real
-- asset/id) with its trough background made transparent. Background
-- subtraction per pixel ROW, not hand-picked rectangles -- the trough has
-- its own subtle gold sheen (brightness varies row to row), so one global
-- flat-color threshold doesn't work, and rectangular "dragon keep-zone"
-- exclusions leave dead-corner artifacts. For each row, sample a reference
-- color at MASK_REF_X and make any pixel in that row within MASK_THRESHOLD
-- of the reference transparent; anything further off (dragon, diamond
-- accents) is left untouched -- both its color AND its original alpha.
local function buildMaskedOrnamentImage()
    local editable = AssetService:CreateEditableImageAsync(Content.fromUri(ORNAMENT_IMAGE))
    local buf = editable:ReadPixelsBuffer(
        Vector2.new(MASK_REGION_X, MASK_REGION_Y),
        Vector2.new(MASK_REGION_W, MASK_REGION_H)
    )

    for row = 0, MASK_REGION_H - 1 do
        local refIdx = (row * MASK_REGION_W + (MASK_REF_X - MASK_REGION_X)) * 4
        local refR = buffer.readu8(buf, refIdx)
        local refG = buffer.readu8(buf, refIdx + 1)
        local refB = buffer.readu8(buf, refIdx + 2)
        for col = 0, MASK_REGION_W - 1 do
            local idx = (row * MASK_REGION_W + col) * 4
            if buffer.readu8(buf, idx + 3) > 10 then
                local r = buffer.readu8(buf, idx)
                local g = buffer.readu8(buf, idx + 1)
                local b = buffer.readu8(buf, idx + 2)
                local dist = math.abs(r - refR) + math.abs(g - refG) + math.abs(b - refB)
                if dist < MASK_THRESHOLD then
                    buffer.writeu8(buf, idx + 3, 0)
                end
            end
        end
    end

    editable:WritePixelsBuffer(
        Vector2.new(MASK_REGION_X, MASK_REGION_Y),
        Vector2.new(MASK_REGION_W, MASK_REGION_H),
        buf
    )
    return editable
end

local ornamentEditable = buildMaskedOrnamentImage()

local BossHealthBarTuning = UIDevTuning.Register("BossHealthBar", {
    -- Overall bar: Scale multiplies BAR_WIDTH_SCALE/MIN/MAX together (keeps
    -- the auto-scaling proportional instead of just changing one axis).
    -- OffsetX/OffsetY nudge the whole bar from its default top-center dock.
    Bar = { Scale = 1.0, OffsetX = 0, OffsetY = 0, Rotation = 0 },
    -- The trough sub-rect inside the ornament art -- Scale grows/shrinks it
    -- (centered on itself), OffsetX/OffsetY nudge it in pixels so it can be
    -- lined up exactly against the real rendered art. Applies to both
    -- halves symmetrically (see applySlotTuning).
    Slot = { Scale = 1.0, OffsetX = 0, OffsetY = 0, Rotation = 0 },
})

---------------------------------------------------------------------------
-- Build the ScreenGui (once, persists across respawns)
---------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "BossHealthBarGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 105
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local root = Instance.new("Frame")
root.Name = "BossHealthRoot"
root.AnchorPoint = Vector2.new(0.5, 0)
root.Position = UDim2.new(0.5, 0, 0, TOP_OFFSET)
root.Size = UDim2.new(BAR_WIDTH_SCALE, 0, 0, 0)
root.AutomaticSize = Enum.AutomaticSize.Y
root.BackgroundTransparency = 1
root.Visible = false
root.Parent = gui

-- Shrinks the whole bar in valve-puzzle mode (see applyBarTuning); 1 otherwise.
local rootScale = Instance.new("UIScale", root)

local widthConstraint = Instance.new("UISizeConstraint", root)
widthConstraint.MinSize = Vector2.new(BAR_WIDTH_MIN, 0)
widthConstraint.MaxSize = Vector2.new(BAR_WIDTH_MAX, math.huge)

local rootLayout = Instance.new("UIListLayout", root)
rootLayout.FillDirection = Enum.FillDirection.Vertical
rootLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
rootLayout.SortOrder = Enum.SortOrder.LayoutOrder
-- Negative: the ornament art has a sizable transparent margin above its own
-- visible top edge (the dragon horns are the tallest opaque point, at
-- roughly 25% down the source image) -- a positive/zero padding here reads
-- as a big empty gap under the title block before anything visible
-- appears. This pulls ornamentRow up into that dead space instead. Offset
-- by titleBlock's own PaddingTop below (-40 -8 -16) so nudging the title
-- text down doesn't also drag the ornament down with it -- ornamentRow's
-- absolute position stays fixed either way.
rootLayout.Padding = UDim.new(0, -64)

---------------------------------------------------------------------------
-- Title block -- boss name + "current / max" HP text, stacked tight
-- together (own small UIListLayout, separate from rootLayout's -40 hack
-- above, which is only about closing the gap to the ornament art below).
---------------------------------------------------------------------------

local titleBlock = Instance.new("Frame")
titleBlock.Name = "TitleBlock"
titleBlock.LayoutOrder = 1
titleBlock.Size = UDim2.new(1, 0, 0, 0)
titleBlock.AutomaticSize = Enum.AutomaticSize.Y
titleBlock.BackgroundTransparency = 1
titleBlock.Parent = root

-- Nudges the name/HP text down a little (per direct request, then doubled
-- again per direct request: 8px -> +16 more = 24px total) without moving
-- the ornament art -- rootLayout.Padding above is offset by this same
-- amount so ornamentRow's own position stays put.
local titlePadding = Instance.new("UIPadding", titleBlock)
titlePadding.PaddingTop = UDim.new(0, 24)

local titleLayout = Instance.new("UIListLayout", titleBlock)
titleLayout.FillDirection = Enum.FillDirection.Vertical
titleLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
titleLayout.SortOrder = Enum.SortOrder.LayoutOrder
titleLayout.Padding = UDim.new(0, 2)

local nameLabel = Instance.new("TextLabel")
nameLabel.Name = "BossName"
nameLabel.LayoutOrder = 1
nameLabel.Size = UDim2.new(1, 0, 0, 30)
nameLabel.BackgroundTransparency = 1
nameLabel.FontFace = UIFonts.HUDLabel
nameLabel.TextSize = 26
nameLabel.TextColor3 = Color3.fromRGB(255, 225, 200)
nameLabel.TextStrokeTransparency = 0.15
nameLabel.TextStrokeColor3 = Color3.fromRGB(40, 10, 5)
nameLabel.TextXAlignment = Enum.TextXAlignment.Center
nameLabel.Text = "Elite"
nameLabel.Parent = titleBlock

-- "current / max" HP readout -- moved here (was overlaid on the bar itself)
-- since a single centered string no longer has one natural home once the
-- bar is two separate segments with a gap in the middle.
local hpText = Instance.new("TextLabel")
hpText.Name = "HPText"
hpText.LayoutOrder = 2
hpText.Size = UDim2.new(1, 0, 0, 20)
hpText.BackgroundTransparency = 1
hpText.FontFace = UIFonts.HUDLabel
hpText.TextSize = 16
hpText.TextColor3 = Color3.fromRGB(245, 235, 225)
hpText.TextStrokeTransparency = 0.3
hpText.TextStrokeColor3 = Color3.new(0, 0, 0)
hpText.TextXAlignment = Enum.TextXAlignment.Center
hpText.Text = "0 / 0"
hpText.Parent = titleBlock

---------------------------------------------------------------------------
-- Ornament row -- aspect-locked to the real art so it's never distorted
-- regardless of how wide the bar is tuned.
---------------------------------------------------------------------------

local ornamentRow = Instance.new("Frame")
ornamentRow.Name = "OrnamentRow"
ornamentRow.LayoutOrder = 2
ornamentRow.Size = UDim2.new(1, 0, 0, 0)
ornamentRow.BackgroundTransparency = 1
ornamentRow.Parent = root

-- Height driven explicitly from root's real rendered width instead of a
-- UIAspectRatioConstraint: with AspectType's default (ScaleWithParentSize),
-- the constraint picks the largest rect that (a) matches AspectRatio and
-- (b) fits inside the object's OWN existing Size -- since ornamentRow's
-- Size.Y was set to 0 above, that bounding box is zero-height, so the
-- "largest rect that fits" is 0x0 too, collapsing the whole row (found live
-- in Studio: name/HP text rendered, but no bar/ornament at all). Computing
-- the height directly from AbsoluteSize sidesteps that entirely.
local function updateOrnamentRowHeight()
    local w = root.AbsoluteSize.X
    if w <= 0 then
        return
    end
    ornamentRow.Size = UDim2.new(1, 0, 0, w / ORNAMENT_ASPECT_RATIO)
end
root:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateOrnamentRowHeight)
task.defer(updateOrnamentRowHeight)

---------------------------------------------------------------------------
-- The real bar -- TWO independent segments rendered BEHIND the ornament
-- (see below), inside its now-transparent trough. Each is its own
-- HealthBarFX controller (same module MobHPBarUI uses for mob HP bars) for
-- the fill/shake/flash/punch/damage-number/heal-dot/color-ramp effects.
---------------------------------------------------------------------------

local function buildSegment(name)
    local background = Instance.new("Frame")
    background.Name = name .. "Background"
    background.BackgroundColor3 = Color3.fromRGB(20, 14, 12)
    background.BorderSizePixel = 0
    background.ZIndex = 1
    background.Parent = ornamentRow
    Instance.new("UICorner", background).CornerRadius = UDim.new(0, 4)

    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.Size = UDim2.new(1, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(60, 195, 75)
    fill.BorderSizePixel = 0
    fill.ZIndex = 2
    fill.Parent = background
    Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 4)

    local gradient = Instance.new("UIGradient", fill)
    gradient.Color = HealthBarFX.GradientForColor(HealthBarFX.DefaultColorRamp(1))

    return background, fill, gradient
end

-- Left = LAST 50% of HP (50%->0%), Right = FIRST 50% of HP (100%->50%) --
-- see header comment and refresh() below for the current/max split fed to
-- each controller.
local backgroundLeft, fillLeft, gradientLeft = buildSegment("Left")
local backgroundRight, fillRight, gradientRight = buildSegment("Right")

-- The ornament art itself -- built LAST and given the highest ZIndex so it
-- draws on top of both fill segments, with its own trough made transparent
-- (see buildMaskedOrnamentImage above) so the fill genuinely shows through
-- rather than the frame just approximating the trough's look.
local ornamentImage = Instance.new("ImageLabel")
ornamentImage.Name = "Art"
ornamentImage.Size = UDim2.fromScale(1, 1)
ornamentImage.BackgroundTransparency = 1
ornamentImage.ImageContent = Content.fromObject(ornamentEditable)
ornamentImage.ScaleType = Enum.ScaleType.Stretch
ornamentImage.ZIndex = 5
ornamentImage.Parent = ornamentRow

---------------------------------------------------------------------------
-- UIDevTool (F6) live tuning
---------------------------------------------------------------------------

-- Valve-puzzle mode (2026-09-27): while the Miasma valve maze is open (MiasmaMazeOpen, set
-- by MiasmaValveMazeUI) the bar would cover the top of the centred puzzle, so it moves to the
-- left edge, below the HP/Energy/Hunger group HealthClient parks top-left in the same mode
-- (that group starts at y=76 and ends ~y=180), and shrinks. Tweened both ways.
local MAZE_POSITION = UDim2.fromOffset(12, 196)
local MAZE_SCALE = 0.55
local MAZE_TWEEN = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function applyBarTuning()
    local t = BossHealthBarTuning:Get().Bar
    root.Size = UDim2.new(BAR_WIDTH_SCALE * t.Scale, 0, 0, 0)
    widthConstraint.MinSize = Vector2.new(BAR_WIDTH_MIN * t.Scale, 0)
    widthConstraint.MaxSize = Vector2.new(BAR_WIDTH_MAX * t.Scale, math.huge)
    root.Rotation = t.Rotation
    local inMaze = player:GetAttribute("MiasmaMazeOpen") == true
    TweenService:Create(root, MAZE_TWEEN, {
        AnchorPoint = inMaze and Vector2.new(0, 0) or Vector2.new(0.5, 0),
        Position = inMaze and MAZE_POSITION or UDim2.new(0.5, t.OffsetX, 0, TOP_OFFSET + t.OffsetY),
    }):Play()
    TweenService:Create(rootScale, MAZE_TWEEN, { Scale = inMaze and MAZE_SCALE or 1 }):Play()
end

player:GetAttributeChangedSignal("MiasmaMazeOpen"):Connect(applyBarTuning)

-- Centered scaling: grows/shrinks the composite slot rect around its own
-- base center (rather than off the top-left corner), then splits THAT
-- scaled/offset rect into two segments with a symmetric gap between them
-- -- so nudging Scale/Offset in F6 moves/resizes both halves together,
-- exactly like when this was one piece.
local function applySlotTuning()
    local t = BossHealthBarTuning:Get().Slot
    local w = SLOT_BASE_W * t.Scale
    local h = SLOT_BASE_H * t.Scale
    local xMin = SLOT_BASE_CENTER_X - w / 2
    local xMax = SLOT_BASE_CENTER_X + w / 2
    local yPos = SLOT_BASE_CENTER_Y - h / 2
    local segmentW = w * (1 - SLOT_GAP_FRACTION) / 2

    local function place(bg, segXMin)
        bg.Size = UDim2.new(segmentW, 0, h, 0)
        bg.Position = UDim2.new(segXMin, t.OffsetX, yPos, t.OffsetY)
        bg.Rotation = t.Rotation
    end

    place(backgroundLeft, xMin)
    place(backgroundRight, xMax - segmentW)
end

applyBarTuning()
applySlotTuning()
BossHealthBarTuning:Subscribe(function()
    applyBarTuning()
    applySlotTuning()
end)

-- HealthBarFX reads background.Position as its shake anchor at construction
-- time, so build these only after the slot is placed.
local hpBarFXLeft = HealthBarFX.new({
    fill = fillLeft,
    background = backgroundLeft,
    gradient = gradientLeft,
    -- Same hit feel as the floating mob bars: hard white flash, then a fast
    -- wobble, no size punch. See HealthBarFX's hitStyle note.
    punch = false, hitStyle = "wobble", flashTime = 0.2, flashStartTransparency = 0.05,
})
local hpBarFXRight = HealthBarFX.new({
    fill = fillRight,
    background = backgroundRight,
    gradient = gradientRight,
    -- Same hit feel as the floating mob bars: hard white flash, then a fast
    -- wobble, no size punch. See HealthBarFX's hitStyle note.
    punch = false, hitStyle = "wobble", flashTime = 0.2, flashStartTransparency = 0.05,
})

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

local function refresh()
    local active = player:GetAttribute("EliteActive") == true
    root.Visible = active
    if not active then
        return
    end

    local hp = tonumber(player:GetAttribute("EliteCurrentHealth")) or 0
    local maxHp = tonumber(player:GetAttribute("EliteMaxHealth")) or 0
    if maxHp <= 0 then
        maxHp = 1
    end

    local mobId = player:GetAttribute("CurrentEliteMobId")
    local name = "Elite"
    if type(mobId) == "string" and mobId ~= "" then
        local stats = MobData.FindMobById(mobId)
        if type(stats) == "table" and type(stats.Name) == "string" and stats.Name ~= "" then
            name = stats.Name
            -- Optional epithet (MobData Title, e.g. Miasma's "the Scourge").
            if type(stats.Title) == "string" and stats.Title ~= "" then
                name = name .. " " .. stats.Title
            end
        end
    end
    nameLabel.Text = string.upper(name)
    hpText.Text = string.format("%d / %d", math.floor(hp + 0.5), math.floor(maxHp + 0.5))

    -- Right = first 50% (100%->50%), Left = last 50% (50%->0%). Each
    -- controller gets its own (current, max) scoped to its own half of the
    -- total HP range -- see header comment for why (correct per-half
    -- shake/flash/chunk-preview instead of both halves reacting to every
    -- hit).
    local halfMax = maxHp / 2
    local rightCurrent = math.clamp(hp - halfMax, 0, halfMax)
    local leftCurrent = math.clamp(hp, 0, halfMax)
    hpBarFXRight:Update(rightCurrent, halfMax)
    hpBarFXLeft:Update(leftCurrent, halfMax)
end

---------------------------------------------------------------------------
-- Stagger meter (solo Miasma, 2026-09-25): a slim bar tucked under the
-- trough inside the ornament row, shown only while the server publishes
-- BossStaggerVisible. BossStagger is 0..1 (damage built up toward the
-- stagger); BossStaggerState "Staggered" while the boss is reeling.
---------------------------------------------------------------------------

local staggerFrame = Instance.new("Frame")
staggerFrame.Name = "StaggerMeter"
staggerFrame.AnchorPoint = Vector2.new(0.5, 0)
staggerFrame.Position = UDim2.fromScale(0.5, 0.63)
staggerFrame.Size = UDim2.new(0.36, 0, 0, 22)
staggerFrame.BackgroundTransparency = 1
staggerFrame.Visible = false
staggerFrame.ZIndex = 20
staggerFrame.Parent = ornamentRow

local staggerLabel = Instance.new("TextLabel")
staggerLabel.Name = "Label"
staggerLabel.Size = UDim2.new(1, 0, 0, 12)
staggerLabel.BackgroundTransparency = 1
staggerLabel.FontFace = UIFonts.HUDLabel
staggerLabel.TextSize = 12
staggerLabel.TextColor3 = Color3.fromRGB(190, 240, 255)
staggerLabel.TextStrokeTransparency = 0.3
staggerLabel.Text = "STAGGER"
staggerLabel.ZIndex = 21
staggerLabel.Parent = staggerFrame

local staggerTrack = Instance.new("Frame")
staggerTrack.Name = "Track"
staggerTrack.Position = UDim2.new(0, 0, 0, 14)
staggerTrack.Size = UDim2.new(1, 0, 0, 6)
staggerTrack.BackgroundColor3 = Color3.fromRGB(20, 26, 30)
staggerTrack.BackgroundTransparency = 0.2
staggerTrack.BorderSizePixel = 0
staggerTrack.ZIndex = 21
staggerTrack.Parent = staggerFrame
Instance.new("UICorner", staggerTrack).CornerRadius = UDim.new(1, 0)
local staggerStroke = Instance.new("UIStroke", staggerTrack)
staggerStroke.Color = Color3.fromRGB(70, 110, 130)
staggerStroke.Thickness = 1

local staggerFill = Instance.new("Frame")
staggerFill.Name = "Fill"
staggerFill.Size = UDim2.fromScale(0, 1)
staggerFill.BackgroundColor3 = Color3.fromRGB(120, 210, 255)
staggerFill.BorderSizePixel = 0
staggerFill.ZIndex = 22
staggerFill.Parent = staggerTrack
Instance.new("UICorner", staggerFill).CornerRadius = UDim.new(1, 0)

local function refreshStagger()
    local visible = player:GetAttribute("BossStaggerVisible") == true
    staggerFrame.Visible = visible
    if not visible then return end
    local ratio = math.clamp(tonumber(player:GetAttribute("BossStagger")) or 0, 0, 1)
    local staggered = player:GetAttribute("BossStaggerState") == "Staggered"
    staggerFill.Size = UDim2.fromScale(ratio, 1)
    if player:GetAttribute("BossStaggerState") == "Recovering" then
        staggerLabel.Text = "STAGGER"
        staggerFill.BackgroundColor3 = Color3.fromRGB(80, 96, 104)
        staggerStroke.Color = Color3.fromRGB(50, 64, 72)
    elseif staggered then
        staggerLabel.Text = "STAGGERED"
        staggerFill.BackgroundColor3 = Color3.fromRGB(235, 250, 255)
        staggerStroke.Color = Color3.fromRGB(200, 240, 255)
    else
        staggerLabel.Text = "STAGGER"
        -- Warms toward white as it nears the break point.
        staggerFill.BackgroundColor3 = Color3.fromRGB(120, 210, 255):Lerp(Color3.fromRGB(230, 250, 255), ratio * ratio)
        staggerStroke.Color = Color3.fromRGB(70, 110, 130)
    end
end

player:GetAttributeChangedSignal("BossStaggerVisible"):Connect(refreshStagger)
player:GetAttributeChangedSignal("BossStagger"):Connect(refreshStagger)
player:GetAttributeChangedSignal("BossStaggerState"):Connect(refreshStagger)
task.defer(refreshStagger)

player:GetAttributeChangedSignal("EliteActive"):Connect(refresh)
player:GetAttributeChangedSignal("EliteCurrentHealth"):Connect(refresh)
player:GetAttributeChangedSignal("EliteMaxHealth"):Connect(refresh)
player:GetAttributeChangedSignal("CurrentEliteMobId"):Connect(refresh)
task.defer(refresh)

print("[BossHealthBar] ready")
