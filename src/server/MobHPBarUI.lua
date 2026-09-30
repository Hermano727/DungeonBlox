-- MobHPBarUI
-- Builds and refreshes the floating name/level + health-bar BillboardGui
-- shown above a mob. Split out of MobClass so the AI/combat/spawning logic
-- there isn't tangled up with UI construction -- this module only ever reads
-- from a mob (Model, Stats, Level, MobID, CurrentHealth, MaxHealth, HPBar)
-- and returns/mutates Instances; it never touches AI state or combat.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local HealthBarFX = require(ReplicatedStorage:WaitForChild("HealthBarFX"))

local MobHPBarUI = {}

-- Nameplate width as a fraction of the billboard, held CONSTANT across both
-- states below. Earlier this was 1.0 (full billboard width) multiplied by a
-- 3x UIScale while idle -- which stretched the panel to 3x the ENTIRE
-- billboard's width (15 studs), reading as a giant black bar. Fixing the
-- width once, here, and varying only HEIGHT between states (see below)
-- avoids that blowing-up-sideways failure mode entirely.
local NAMEPLATE_WIDTH_SCALE = 0.62

-- Nameplate height as a fraction of the billboard. Idle (never hit): tall,
-- so TextScaled auto-renders both labels large -- this is the "only its
-- name, tripled" state, achieved by giving the panel lots of vertical room
-- rather than a blanket UIScale (which is what caused the width bug above).
-- Hit (took damage at least once): shorter -- a "slight decrease", not a
-- collapse -- freeing the strip below it for the HP bar. The nameplate
-- stays visible in both states; only the HP bar's visibility toggles (see
-- the hasBeenHit latch in MobHPBarUI.Update).
local NAMEPLATE_IDLE_HEIGHT_SCALE = 0.62
local NAMEPLATE_HIT_HEIGHT_SCALE = 0.40

-- Build the BillboardGui for `mob` (expects mob.Model, mob.Stats, mob.Level,
-- mob.MobID to already be set) and parent it under the model. Returns the
-- BillboardGui, or nil if the mob has no model/attach point yet.
function MobHPBarUI.Create(mob)
    if not mob.Model then return nil end

    -- Find the head or primary part to attach the HP bar
    local head = mob.Model:FindFirstChild("Head")
    if not head then
        head = mob.Model.PrimaryPart or mob.Model:FindFirstChildWhichIsA("BasePart")
    end
    if not head then return nil end

    -- Create BillboardGui for the name/level + HP bar. Taller than the
    -- original single-line design (1.2 studs) so the idle-size nameplate
    -- and, once hit, the HP bar beneath it both get proper room instead of
    -- being squeezed into a fixed height built for one smaller state.
    local billboardGui = Instance.new("BillboardGui")
    billboardGui.Name = "HPBar"
    billboardGui.Size = UDim2.new(5, 0, 1.2, 0)
    billboardGui.StudsOffset = Vector3.new(0, 3.4, 0)
    billboardGui.Adornee = head
    billboardGui.AlwaysOnTop = true
    billboardGui.Parent = mob.Model

    local mobName = (mob.Stats and mob.Stats.Name) or mob.MobID

    -- Nameplate: a legible dark panel (readable over sky, grass, cave rock,
    -- anything) holding two stacked labels -- "LVL n" small/gold on top,
    -- the mob's actual name large/bold underneath. Replaces the old single
    -- line "Level 1 Plains Slime" in yellow with no backing panel.
    --
    -- Top-anchored with a FIXED width (NAMEPLATE_WIDTH_SCALE) -- only the
    -- HEIGHT changes between idle/hit (see MobHPBarUI.Update), which is
    -- what keeps the panel from ever stretching sideways into a giant bar.
    local titlePanel = Instance.new("Frame")
    titlePanel.Name = "NamePlate"
    titlePanel.AnchorPoint = Vector2.new(0.5, 0)
    titlePanel.Size = UDim2.new(NAMEPLATE_WIDTH_SCALE, 0, NAMEPLATE_IDLE_HEIGHT_SCALE, 0)
    titlePanel.Position = UDim2.new(0.5, 0, 0.02, 0)
    titlePanel.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
    titlePanel.BackgroundTransparency = 0.35
    titlePanel.BorderSizePixel = 0
    titlePanel.Parent = billboardGui

    local titlePanelCorner = Instance.new("UICorner")
    titlePanelCorner.CornerRadius = UDim.new(0, 6)
    titlePanelCorner.Parent = titlePanel

    local titlePanelStroke = Instance.new("UIStroke")
    titlePanelStroke.Color = Color3.fromRGB(0, 0, 0)
    titlePanelStroke.Transparency = 0.4
    titlePanelStroke.Thickness = 1
    titlePanelStroke.Parent = titlePanel

    -- "LVL n" -- small, gold, its own color so it reads as a distinct
    -- stat rather than part of the name.
    local levelLabel = Instance.new("TextLabel")
    levelLabel.Name = "LevelLabel"
    levelLabel.Size = UDim2.new(1, -8, 0.38, 0)
    levelLabel.Position = UDim2.new(0, 4, 0.02, 0)
    levelLabel.BackgroundTransparency = 1
    levelLabel.FontFace = UIFonts.MobName
    levelLabel.TextSize = 13
    levelLabel.TextScaled = true
    levelLabel.TextColor3 = Color3.fromRGB(255, 196, 64)
    levelLabel.TextStrokeTransparency = 0.4
    levelLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    levelLabel.TextXAlignment = Enum.TextXAlignment.Center
    levelLabel.Text = "LVL " .. tostring(mob.Level)
    levelLabel.Parent = titlePanel

    -- Mob name -- larger, bolder Display font (same family used for panel
    -- headers/callouts elsewhere), near-white so it stays legible against
    -- any environment. TextScaled so long names still fit the panel.
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "NameLabel"
    nameLabel.Size = UDim2.new(1, -8, 0.58, 0)
    nameLabel.Position = UDim2.new(0, 4, 0.40, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.FontFace = UIFonts.DisplayBold
    nameLabel.TextSize = 20
    nameLabel.TextScaled = true
    nameLabel.TextColor3 = Color3.fromRGB(245, 245, 250)
    nameLabel.TextStrokeTransparency = 0.25
    nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    nameLabel.TextXAlignment = Enum.TextXAlignment.Center
    nameLabel.Text = tostring(mobName)
    nameLabel.Parent = titlePanel

    -- Create background frame (dark background). Hidden until the mob's
    -- first hit -- see the hasBeenHit latch in MobHPBarUI.Update -- so an
    -- untouched mob shows only its nameplate, never an idle empty health
    -- bar nobody asked to see yet. Positioned to start right under where
    -- the nameplate sits ONCE SHRUNK to NAMEPLATE_HIT_HEIGHT_SCALE (that's
    -- the only state background is ever visible in), not under the taller
    -- idle height.
    local background = Instance.new("Frame")
    background.Name = "Background"
    -- Centre-anchored on purpose. It was (0, 0), and any size effect on this
    -- frame then grows it away from its TOP-LEFT corner -- which is exactly how
    -- the old hit "punch" (a UIScale) made the whole bar, trough and damage
    -- ghost included, bulge out to the right on every hit. The punch is now off
    -- for this bar (see HealthBarFX.new below), but a centre anchor keeps any
    -- future scale effect symmetric and gives the wobble a sensible pivot.
    background.AnchorPoint = Vector2.new(0.5, 0)
    background.Size = UDim2.new(1, 0, 0.30, 0)
    background.Position = UDim2.new(0.5, 0, NAMEPLATE_HIT_HEIGHT_SCALE + 0.04, 0)
    background.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    background.BorderSizePixel = 2
    background.BorderColor3 = Color3.fromRGB(20, 20, 20)
    background.Visible = false
    background.Parent = billboardGui

    -- Health bar fill. Flat color replaced by a live UIGradient (same
    -- top-bright/bottom-dark sheen as the player HP bar) so HealthBarFX can
    -- re-tint it through the shared green/yellow/red ramp -- see HealthBarFX.
    local healthBar = Instance.new("Frame")
    healthBar.Name = "HealthBar"
    healthBar.Size = UDim2.new(1, 0, 1, 0)
    healthBar.Position = UDim2.new(0, 0, 0, 0)
    healthBar.BackgroundColor3 = Color3.fromRGB(60, 195, 75)
    healthBar.BorderSizePixel = 0
    healthBar.Parent = background

    local healthBarGradient = Instance.new("UIGradient")
    healthBarGradient.Rotation = 90
    healthBarGradient.Color = HealthBarFX.GradientForColor(HealthBarFX.DefaultColorRamp(1))
    healthBarGradient.Parent = healthBar

    -- Create corner radius for rounded look
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 4)
    corner.Parent = background

    local healthCorner = Instance.new("UICorner")
    healthCorner.CornerRadius = UDim.new(0, 4)
    healthCorner.Parent = healthBar

    -- Smooth drain/chunk-preview/shake/flash/punch/damage-number/heal-dots/
    -- "Full!" all live in the shared HealthBarFX module (same one player HP
    -- uses) -- one controller per mob, stored on the mob table itself since
    -- MobHPBarUI is a shared module with no per-mob state of its own.
    mob._hpBarFX = HealthBarFX.new({
        fill = healthBar,
        background = background,
        gradient = healthBarGradient,
        -- A hit on a mob: a short hard white flash, then a fast wobble. No size
        -- punch -- that punch was the bar-grows-sideways bug.
        punch = false,
        hitStyle = "wobble",
        flashTime = 0.2,
        flashStartTransparency = 0.05,
    })

    return billboardGui
end

-- Refresh the health bar fill/color on an already-created HPBar to match
-- mob.CurrentHealth / mob.MaxHealth. No-op if the mob has no HP bar yet.
--
-- Also owns the one-time idle -> hit nameplate transition: a mob spawns
-- showing only its (idle-size) name/level plate with the HP bar hidden,
-- and the first time it takes damage, that flips permanently -- the
-- nameplate shrinks to its (smaller) hit-state height to make room, and
-- the HP bar (fill + trough) becomes visible below it -- for the rest of
-- this mob instance's life. The nameplate itself is NEVER hidden; only its
-- size changes. mob._hasBeenHit is the latch so this only fires once.
function MobHPBarUI.Update(mob)
    if not mob.HPBar or not mob._hpBarFX then return end

    if not mob._hasBeenHit and mob.CurrentHealth < mob.MaxHealth then
        mob._hasBeenHit = true
        local nameplate = mob.HPBar:FindFirstChild("NamePlate")
        if nameplate then
            nameplate.Size = UDim2.new(NAMEPLATE_WIDTH_SCALE, 0, NAMEPLATE_HIT_HEIGHT_SCALE, 0)
        end
        mob._hpBarFX.background.Visible = true
    end

    mob._hpBarFX:Update(mob.CurrentHealth, mob.MaxHealth)
end

return MobHPBarUI
