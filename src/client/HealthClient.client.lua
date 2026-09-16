--[[
    HealthClient
    Builds the HP bar, elite-pity indicator, and hunger pip row, and keeps
    them synced to the local character's Humanoid / server-pushed stats.

    Layout (2026-09-08 rework, per direct request): HP, Energy (built by
    EnergyClient/EnergyBarGui, not this script), and Hunger are now stacked
    in the same bottom-center cluster, top to bottom: HP, Energy, Hunger.
    HP and Hunger both use the exact same viewport-relative auto-scaling
    rule EnergyBarGui already used (Scale-based width + a UISizeConstraint
    clamp) instead of the old fixed-pixel-width trough. HP is an extra 33%
    bigger than that shared baseline (bar + ornament scaled up together).

    Reconnects automatically on every character respawn.
]]

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local StarterGui   = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HungerConfig = require(ReplicatedStorage:WaitForChild("HungerConfig"))
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local MobData = require(ReplicatedStorage:WaitForChild("MobData"))
local UIDevTuning = require(ReplicatedStorage:WaitForChild("UIDevTuning"))
local HealthBarFX = require(ReplicatedStorage:WaitForChild("HealthBarFX"))
local ProfileMenusState = require(ReplicatedStorage:WaitForChild("ProfileMenusState"))

-- Disable Roblox's built-in top-right health bar
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

---------------------------------------------------------------------------
-- Shared bottom-cluster layout constants
---------------------------------------------------------------------------

-- EnergyBarGui (StarterGui, hand-built, outside Rojo's synced tree) owns the
-- actual Energy bar and isn't touched by this script -- these mirror its
-- known BarBackground values so HP/Hunger can be positioned relative to it.
local BASE_WIDTH_SCALE = 0.22 -- original (pre-2026-09-08) unscaled Energy footprint
local BASE_WIDTH_MIN, BASE_WIDTH_MAX = 260, 460
local BASE_HEIGHT = 15

-- HP: same auto-scaling rule as the original Energy baseline, then 33%
-- bigger across the board (per direct request: "scale the img ornament and
-- actual bar by the exact same amount").
local HP_SIZE_MULTIPLIER = 1.33
local HP_WIDTH_SCALE = BASE_WIDTH_SCALE * HP_SIZE_MULTIPLIER
local HP_WIDTH_MIN = BASE_WIDTH_MIN * HP_SIZE_MULTIPLIER
local HP_WIDTH_MAX = BASE_WIDTH_MAX * HP_SIZE_MULTIPLIER
local HP_HEIGHT = BASE_HEIGHT * HP_SIZE_MULTIPLIER

-- Energy briefly matched HP's size exactly, but the ornament border art
-- couldn't wrap the bigger bar even at Border.Scale 3.0, so per direct
-- feedback (2026-09-08) it's now 33% smaller than that HP-matching size
-- instead ("make it maybe 33% smaller, its okay that its smaller than the
-- health bar") -- the smaller footprint means the existing fixed-pixel
-- border padding covers proportionally more of the bar again.
-- EnergyClient.client.lua (the Rojo-synced script, since EnergyBarGui
-- itself lives outside Rojo's synced tree) overrides the real instance's
-- Size/UISizeConstraint/Position at runtime to match these same numbers --
-- keep both files in sync.
local ENERGY_SIZE_MULTIPLIER = HP_SIZE_MULTIPLIER * 0.67
local ENERGY_WIDTH_SCALE = BASE_WIDTH_SCALE * ENERGY_SIZE_MULTIPLIER
local ENERGY_WIDTH_MIN, ENERGY_WIDTH_MAX = BASE_WIDTH_MIN * ENERGY_SIZE_MULTIPLIER, BASE_WIDTH_MAX * ENERGY_SIZE_MULTIPLIER
local ENERGY_HEIGHT = BASE_HEIGHT * ENERGY_SIZE_MULTIPLIER
-- EnergyBarGui.BarBackground's own Position Y offset (AnchorPoint 0.5,1).
-- Was -96, then -111 (2026-09-08, "move all 3 up by a lil bit"); shifted up
-- again to -145 (2026-09-10) to clear room for the Hotbar's diamond slots
-- sitting right below this cluster -- EnergyClient.client.lua sets this same
-- real value at runtime, MUST stay in sync.
local ENERGY_BOTTOM_OFFSET = -145

-- Hunger: 20% bigger than the ORIGINAL unscaled baseline (per direct
-- request: "increase the size of the hunger bar by maybe 20%") -- kept
-- separate from HP/Energy's own multiplier since Hunger isn't meant to
-- match their new bigger size, just grow a bit from where it already was.
local HUNGER_SIZE_MULTIPLIER = 1.2

local GAP_HP_TO_ENERGY = 24     -- generous -- HP/Energy's ornate borders overhang their own trough box
local GAP_ENERGY_TO_HUNGER = 10 -- was 5; nudged down another 5px (2026-09-10, "move the hunger
                                 -- bar maybe 5 px down (VERY slight)")
local GAP_ELITEPITY_TO_HP = 10

-- Imported "hp bar border" art (Elden-Ring-style ornate frame). Fixed-size,
-- never resizes with HP -- only the gradient fill below does that. Sized as
-- parent-size-plus-padding (see applyHealthBorderTuning), so it automatically
-- tracks the trough's own dynamic viewport-based width, same trick
-- EnergyClient uses for its border.
local HP_BORDER_IMAGE = "rbxassetid://90368126230600"
local HP_BORDER_PAD_X = 26 * HP_SIZE_MULTIPLIER -- base overhang at Border.Scale == 1, tune via F6
local HP_BORDER_PAD_Y = 12 * HP_SIZE_MULTIPLIER

local HealthBarTuning = UIDevTuning.Register("HealthBar", {
    -- Approved 2026-09-07 via UIDevTool (F6) snapshot at Scale=0.900, base
    -- pad scaled up 33% same day (see HP_SIZE_MULTIPLIER). Re-tuned down to
    -- 0.800 on 2026-09-08 per direct feedback ("just tested that is the
    -- proper size").
    Border = { Scale = 0.800, OffsetX = 0, OffsetY = 3, Rotation = 0 },
})

---------------------------------------------------------------------------
-- Build the ScreenGui (once, persists across respawns)
---------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name           = "HealthBarGui"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.DisplayOrder   = 110
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent         = playerGui

---------------------------------------------------------------------------
-- Elite-pity indicator (sits just above the HP bar, hidden outside elite zones)
---------------------------------------------------------------------------

local ELITEPITY_HEIGHT = 34

local elitePityFrame = Instance.new("Frame")
elitePityFrame.Name = "ElitePityFrame"
elitePityFrame.AnchorPoint = Vector2.new(0.5, 1)
elitePityFrame.Position = UDim2.new(0.5, 0, 1, -(math.abs(ENERGY_BOTTOM_OFFSET) + ENERGY_HEIGHT + GAP_HP_TO_ENERGY + HP_HEIGHT + HP_BORDER_PAD_Y * 2 + GAP_ELITEPITY_TO_HP))
elitePityFrame.Size = UDim2.fromOffset(510, ELITEPITY_HEIGHT)
elitePityFrame.BackgroundTransparency = 1
elitePityFrame.Parent = gui
local DEFAULT_ELITEPITY_ANCHOR, DEFAULT_ELITEPITY_POS = elitePityFrame.AnchorPoint, elitePityFrame.Position

local elitePityTitle = Instance.new("TextLabel", elitePityFrame)
elitePityTitle.Name = "ElitePityTitle"
elitePityTitle.Size = UDim2.fromOffset(440, 16)
elitePityTitle.Position = UDim2.fromOffset(26, 0)
elitePityTitle.BackgroundTransparency = 1
elitePityTitle.FontFace = UIFonts.HUDLabel
elitePityTitle.TextSize = 12
elitePityTitle.TextColor3 = Color3.fromRGB(222, 188, 255)
elitePityTitle.TextStrokeTransparency = 0.35
elitePityTitle.TextStrokeColor3 = Color3.fromRGB(58, 26, 92)
elitePityTitle.TextXAlignment = Enum.TextXAlignment.Left
elitePityTitle.Text = "Lvl -- [Elite]"
elitePityTitle.ZIndex = 3
elitePityTitle.Visible = false

local elitePityBarBg = Instance.new("Frame", elitePityFrame)
elitePityBarBg.Name = "ElitePityBarBg"
elitePityBarBg.Size = UDim2.fromOffset(380, 10)
elitePityBarBg.Position = UDim2.fromOffset(26, 16)
elitePityBarBg.BackgroundColor3 = Color3.fromRGB(38, 20, 52)
elitePityBarBg.BorderSizePixel = 0
elitePityBarBg.ZIndex = 2
elitePityBarBg.Visible = false
Instance.new("UICorner", elitePityBarBg).CornerRadius = UDim.new(0, 4)

local elitePityFill = Instance.new("Frame", elitePityBarBg)
elitePityFill.Name = "Fill"
elitePityFill.Size = UDim2.new(0.01, 0, 1, 0)
elitePityFill.BackgroundColor3 = Color3.fromRGB(176, 92, 255)
elitePityFill.BorderSizePixel = 0
elitePityFill.ZIndex = 3
Instance.new("UICorner", elitePityFill).CornerRadius = UDim.new(0, 4)

local elitePityText = Instance.new("TextLabel", elitePityFrame)
elitePityText.Name = "ElitePityText"
elitePityText.Size = UDim2.fromOffset(98, 18)
elitePityText.Position = UDim2.fromOffset(412, 12)
elitePityText.BackgroundTransparency = 1
elitePityText.FontFace = UIFonts.HUDLabel
elitePityText.TextSize = 11
elitePityText.TextColor3 = Color3.fromRGB(222, 188, 255)
elitePityText.TextStrokeTransparency = 0.4
elitePityText.TextStrokeColor3 = Color3.fromRGB(58, 26, 92)
elitePityText.TextXAlignment = Enum.TextXAlignment.Left
elitePityText.Text = "Elite 1%"
elitePityText.ZIndex = 3
elitePityText.Visible = false

---------------------------------------------------------------------------
-- HP bar -- same auto-scaling architecture as EnergyBarGui.BarBackground
---------------------------------------------------------------------------

local barBg = Instance.new("Frame")
barBg.Name             = "HPBarBackground"
barBg.AnchorPoint      = Vector2.new(0.5, 1)
barBg.Position         = UDim2.new(0.5, 0, 1, ENERGY_BOTTOM_OFFSET - ENERGY_HEIGHT - GAP_HP_TO_ENERGY)
barBg.Size             = UDim2.new(HP_WIDTH_SCALE, 0, 0, HP_HEIGHT)
barBg.BackgroundColor3 = Color3.fromRGB(15, 10, 10)
barBg.BackgroundTransparency = 0.15
barBg.BorderSizePixel  = 0
barBg.ZIndex           = 2
barBg.Parent           = gui
Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 4)
local DEFAULT_HP_ANCHOR, DEFAULT_HP_POS = barBg.AnchorPoint, barBg.Position

local hpWidthConstraint = Instance.new("UISizeConstraint", barBg)
hpWidthConstraint.MinSize = Vector2.new(HP_WIDTH_MIN, HP_HEIGHT)
hpWidthConstraint.MaxSize = Vector2.new(HP_WIDTH_MAX, HP_HEIGHT)

-- Bar fill: a LIVE UIGradient, not baked into any image, so it resizes and
-- recolors cleanly as HP changes. Sized relative to barBg (scale, not
-- offset), so it tracks the trough's dynamic width automatically.
local barFill = Instance.new("Frame", barBg)
barFill.Name             = "BarFill"
barFill.Position         = UDim2.new(0, 0, 0, 0)
barFill.Size             = UDim2.new(1, 0, 1, 0)
barFill.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
barFill.BorderSizePixel  = 0
barFill.ZIndex           = 3
Instance.new("UICorner", barFill).CornerRadius = UDim.new(0, 4)

local barFillGradient = Instance.new("UIGradient", barFill)
barFillGradient.Rotation = 90 -- vertical: bright highlight near the top, darker toward the bottom
barFillGradient.Color = ColorSequence.new(Color3.fromRGB(200, 40, 40))

-- Ornate border (imported art). Sits on top of the fill and masks the
-- fill's straight rectangular edges at the bar's tapered ends.
local barBorder = Instance.new("ImageLabel", barBg)
barBorder.Name                   = "BarBorder"
barBorder.AnchorPoint             = Vector2.new(0.5, 0.5)
barBorder.BackgroundTransparency = 1
barBorder.Image                  = HP_BORDER_IMAGE
barBorder.ScaleType               = Enum.ScaleType.Stretch
barBorder.ZIndex                  = 5

local function applyHealthBorderTuning()
    local b = HealthBarTuning:Get().Border
    local padX = HP_BORDER_PAD_X * b.Scale
    local padY = HP_BORDER_PAD_Y * b.Scale
    barBorder.Size = UDim2.new(1, padX * 2, 1, padY * 2)
    barBorder.Position = UDim2.new(0.5, b.OffsetX, 0.5, b.OffsetY)
    barBorder.Rotation = b.Rotation
end

applyHealthBorderTuning()
HealthBarTuning:Subscribe(applyHealthBorderTuning)

-- HP text: centered on the bar, tracks barBg's own dynamic width via Scale
-- instead of a hardcoded pixel size/position.
local hpText = Instance.new("TextLabel", barBg)
hpText.Name                   = "HPText"
hpText.Size                   = UDim2.fromScale(1, 1)
hpText.BackgroundTransparency = 1
hpText.FontFace                   = UIFonts.HUDLabel
hpText.TextSize               = 13
hpText.TextColor3             = Color3.new(1, 1, 1)
hpText.TextStrokeTransparency = 0.4
hpText.TextStrokeColor3       = Color3.fromRGB(80, 0, 0)
hpText.TextXAlignment         = Enum.TextXAlignment.Center
hpText.TextYAlignment         = Enum.TextYAlignment.Center
hpText.Text                   = "-- / --"
hpText.ZIndex                 = 7

-- Slight black drop shadow behind the HP text -- separate from the dark-red
-- stroke above; an offset clone reads as a shadow rather than an outline.
-- Kept in sync with hpText's Text inside updateHealth().
local hpTextShadow = hpText:Clone()
hpTextShadow.Name = "HPTextShadow"
hpTextShadow.Position = UDim2.fromScale(0, 0) + UDim2.fromOffset(1, 2)
hpTextShadow.TextColor3 = Color3.new(0, 0, 0)
hpTextShadow.TextTransparency = 0.5
hpTextShadow.TextStrokeTransparency = 1
hpTextShadow.ZIndex = 6
hpTextShadow.Parent = barBg

---------------------------------------------------------------------------
-- Hunger pips + potion icons -- ONE combined row, centered as a group under
-- the Energy bar (2026-09-10, direct clarification after a prior pass split
-- them: "no i meant the bread and potions TOGETHER need to be centered" --
-- hunger stays visually left of potions within that one row, but the row
-- itself is centered on screen, same as Energy bar, rather than either
-- piece being independently left- or center-anchored). Parented to the
-- screen (`gui`), like Energy bar itself, not to HP/barBg.
---------------------------------------------------------------------------

-- Real imported icon art (2026-09-07/08). Pips are binary full/empty --
-- the underlying hunger model is integer 0-5, so the half icon (distinct id,
-- still unused) has no state to draw yet.
local HUNGER_ICON_FULL  = "rbxassetid://74630332277849"
local HUNGER_ICON_HALF  = "rbxassetid://98954833986834" -- unused until half-pip granularity is added
local HUNGER_ICON_EMPTY = "rbxassetid://111521579551384"

local HUNGER_PIP_COUNT = HungerConfig.MAX_HUNGER
local PIP_SIZE = 18 * HUNGER_SIZE_MULTIPLIER
local PIP_GAP = 3 * HUNGER_SIZE_MULTIPLIER
local ROW_GROUP_GAP = 14 -- gap between the hunger pip group and the potion icon group

local hungerPotionRow = Instance.new("Frame")
hungerPotionRow.Name = "HungerPotionRow"
hungerPotionRow.AnchorPoint = Vector2.new(0.5, 0)
hungerPotionRow.Position = UDim2.new(0.5, 0, 1, ENERGY_BOTTOM_OFFSET + GAP_ENERGY_TO_HUNGER)
hungerPotionRow.Size = UDim2.new(0, 0, 0, PIP_SIZE)
hungerPotionRow.AutomaticSize = Enum.AutomaticSize.X
hungerPotionRow.BackgroundTransparency = 1
hungerPotionRow.Parent = gui
local DEFAULT_HUNGER_ANCHOR, DEFAULT_HUNGER_POS = hungerPotionRow.AnchorPoint, hungerPotionRow.Position

local hungerPotionRowLayout = Instance.new("UIListLayout")
hungerPotionRowLayout.FillDirection = Enum.FillDirection.Horizontal
hungerPotionRowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
hungerPotionRowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
hungerPotionRowLayout.SortOrder = Enum.SortOrder.LayoutOrder
hungerPotionRowLayout.Padding = UDim.new(0, ROW_GROUP_GAP)
hungerPotionRowLayout.Parent = hungerPotionRow

-- Hunger pip group (left side of the combined row).
local hungerGroup = Instance.new("Frame")
hungerGroup.Name = "HungerGroup"
hungerGroup.LayoutOrder = 1
hungerGroup.Size = UDim2.new(0, 0, 0, PIP_SIZE)
hungerGroup.AutomaticSize = Enum.AutomaticSize.X
hungerGroup.BackgroundTransparency = 1
hungerGroup.Parent = hungerPotionRow

local hungerGroupLayout = Instance.new("UIListLayout")
hungerGroupLayout.FillDirection = Enum.FillDirection.Horizontal
hungerGroupLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
hungerGroupLayout.VerticalAlignment = Enum.VerticalAlignment.Center
hungerGroupLayout.SortOrder = Enum.SortOrder.LayoutOrder
hungerGroupLayout.Padding = UDim.new(0, PIP_GAP)
hungerGroupLayout.Parent = hungerGroup

local hungerPips = {}
for i = 1, HUNGER_PIP_COUNT do
    local pip = Instance.new("ImageLabel", hungerGroup)
    pip.Name = "Pip" .. i
    pip.LayoutOrder = i
    pip.Size = UDim2.fromOffset(PIP_SIZE, PIP_SIZE)
    pip.BackgroundTransparency = 1
    pip.Image = HUNGER_ICON_EMPTY
    pip.ScaleType = Enum.ScaleType.Fit
    pip.ZIndex = 3
    hungerPips[i] = pip
end

local function setPipRow(pips, current)
    current = math.clamp(math.floor(current + 0.5), 0, #pips)
    for i, pip in ipairs(pips) do
        pip.Image = (i <= current) and HUNGER_ICON_FULL or HUNGER_ICON_EMPTY
    end
end

-- Potion icon group (right side of the combined row). PotionClient.client.luau finds this by
-- name (playerGui:FindFirstChild("PotionIconsMount", true)) and builds/updates the actual
-- charge icons here -- potion-charge networking stays owned by that script, this one only
-- owns the row's layout. Replaces the old standalone "Minor x3/3" list box.
local potionMount = Instance.new("Frame")
potionMount.Name = "PotionIconsMount"
potionMount.LayoutOrder = 2
potionMount.Size = UDim2.new(0, 0, 0, PIP_SIZE)
potionMount.AutomaticSize = Enum.AutomaticSize.X
potionMount.BackgroundTransparency = 1
potionMount.Parent = hungerPotionRow

local potionMountLayout = Instance.new("UIListLayout")
potionMountLayout.FillDirection = Enum.FillDirection.Horizontal
potionMountLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
potionMountLayout.VerticalAlignment = Enum.VerticalAlignment.Center
potionMountLayout.SortOrder = Enum.SortOrder.LayoutOrder
potionMountLayout.Padding = UDim.new(0, 4) -- tight gap between the 3 charge icons themselves
potionMountLayout.Parent = potionMount

---------------------------------------------------------------------------
-- ProfileMenus-open layout -- HP, Hunger, and Potions (Energy mirrors this in
-- EnergyClient.client.lua) relocate as one group while the Inventory/Skills/Stats/
-- Hearthstone/Party panel is open. First pass (2026-09-13) anchored these to the screen's
-- top-right corner with hand-copied constants; per direct follow-up feedback the same day
-- ("move ... to be resting beneath the carousel directly in the middle, wherever the
-- carousel's new position will be") this now reads the carousel's ACTUAL live position from
-- ProfileMenusState.GetCarouselAnchor() (published by QuickNav.lua itself, in real screen
-- pixels) instead of re-deriving it by hand -- see that module's doc comment for why a fixed
-- top-right offset couldn't just be nudged to fit instead. Stacked downward in the SAME
-- relative order as bottom-center (Elite Pity, HP, Energy, Hunger+Potions) -- Energy's own Y
-- target MUST stay in sync with this file's copy (EnergyClient.client.lua duplicates
-- MENU_PAD_TOP/the stacking math, same convention as the existing ENERGY_* bottom-center
-- constants above).
---------------------------------------------------------------------------

local MENU_ANCHOR = Vector2.new(0.5, 0) -- top-center -- hangs off the carousel's own bottom-center anchor
local MENU_PAD_TOP = 16 -- gap between the carousel's bottom edge and the first bar (Elite Pity)
local MENU_MOVE_TWEEN = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function setMenuLayout(frame: GuiObject, open: boolean, defaultAnchor: Vector2, defaultPos: UDim2, menuPos: UDim2?)
	if open and not menuPos then
		-- Carousel hasn't published a position yet -- shouldn't normally happen (QuickNav
		-- publishes on mount, well before this can ever be reached), but don't yank the bar to
		-- the screen's top-left corner if it somehow is nil.
		return
	end
	TweenService:Create(frame, MENU_MOVE_TWEEN, {
		AnchorPoint = open and MENU_ANCHOR or defaultAnchor,
		Position = open and (menuPos :: UDim2) or defaultPos,
	}):Play()
end

local function applyProfileMenusLayout()
	local open = ProfileMenusState.IsOpen()
	local anchor = ProfileMenusState.GetCarouselAnchor()

	local elitePityPos, hpPos, hungerPos
	if anchor then
		local elitePityY = anchor.Y + MENU_PAD_TOP
		local hpY = elitePityY + ELITEPITY_HEIGHT + GAP_ELITEPITY_TO_HP
		local energyY = hpY + HP_HEIGHT + GAP_HP_TO_ENERGY -- EnergyClient.client.lua computes this same value
		local hungerY = energyY + ENERGY_HEIGHT + GAP_ENERGY_TO_HUNGER
		elitePityPos = UDim2.fromOffset(anchor.X, elitePityY)
		hpPos = UDim2.fromOffset(anchor.X, hpY)
		hungerPos = UDim2.fromOffset(anchor.X, hungerY)
	end

	setMenuLayout(elitePityFrame, open, DEFAULT_ELITEPITY_ANCHOR, DEFAULT_ELITEPITY_POS, elitePityPos)
	setMenuLayout(barBg, open, DEFAULT_HP_ANCHOR, DEFAULT_HP_POS, hpPos)
	setMenuLayout(hungerPotionRow, open, DEFAULT_HUNGER_ANCHOR, DEFAULT_HUNGER_POS, hungerPos)
end

ProfileMenusState.Subscribe(applyProfileMenusLayout)

---------------------------------------------------------------------------
-- Update logic
---------------------------------------------------------------------------

local barTweenInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local currentElitePityTween = nil

-- Smooth drain/chunk-preview/shake/flash/punch/damage-number/heal-dots/
-- "Full!" all live in HealthBarFX now (shared with MobHPBarUI and, in a
-- pared-down mode, EnergyClient) so the three bars stop duplicating this
-- logic and drifting out of sync with each other -- see that module for the
-- full behavior. Also owns the green/yellow/red color ramp (req 2026-09-09:
-- 66-100% green, 33-65% yellow, <=33% red), replacing the old healthy-red/
-- warning-orange/critical-red scheme.
local hpBarFX = HealthBarFX.new({
    fill = barFill,
    background = barBg,
    gradient = barFillGradient,
})

-- Feed the REAL server-authoritative combat state (same "combat"/"safe" event
-- CombatTimerClient's HUD timer listens to) into HealthBarFX instead of letting it guess from
-- "did this bar's own value drop recently" -- that guess reads "not in combat" whenever a hit
-- lands in the same tick a regen tick partially offsets it, which is exactly the 2026-09-10 bug
-- report ("enter combat, exit, dots appear, re-enter combat, the dots stay").
local combatStateEvent = ReplicatedStorage:WaitForChild("CombatStateEvent", 30)
if combatStateEvent then
    combatStateEvent.OnClientEvent:Connect(function(state)
        if state == "combat" then
            hpBarFX:SetInCombat(true)
        elseif state == "safe" then
            hpBarFX:SetInCombat(false)
        end
    end)
else
    warn("[HealthClient] CombatStateEvent not found -- heal dots will fall back to the local damage-timing heuristic")
end

local function updateHealth(current, max)
    if max <= 0 then return end

    hpBarFX:Update(current, max)

    -- Text (kept in sync with its drop-shadow clone) shows the true value
    -- immediately -- only the bar's own fill is what smoothly lags behind.
    local hpTextValue = math.floor(current) .. " / " .. math.floor(max)
    hpText.Text = hpTextValue
    hpTextShadow.Text = hpTextValue
end

local function updateHunger(current)
    setPipRow(hungerPips, current)
end

local function refreshElitePityBar()
    local inEliteZone = player:GetAttribute("IsInEliteZone") == true
    local eliteActive = player:GetAttribute("EliteActive") == true
    local chancePercent = tonumber(player:GetAttribute("ElitePityChance")) or 1
    local eliteMobId = player:GetAttribute("CurrentEliteMobId")
    chancePercent = math.clamp(chancePercent, 1, 100)

    -- Pre-spawn "chance building up" meter only. This frame used to ALSO
    -- double as a second HP readout once an elite went active -- removed
    -- per direct request ("remove the purple bar that shows up when an
    -- elite spawns, that was the old outdated bad system") now that
    -- BossHealthBar.client.lua's dedicated top-middle bar is the one real
    -- HP readout for named elites. So this frame hides itself entirely the
    -- moment EliteActive flips true, instead of switching modes.
    local shouldShow = inEliteZone and not eliteActive
    elitePityBarBg.Visible = shouldShow
    elitePityText.Visible = shouldShow
    elitePityTitle.Visible = shouldShow
    if not shouldShow then
        return
    end

    local level = "--"
    local name = "Elite"
    if type(eliteMobId) == "string" and eliteMobId ~= "" then
        local mobStats = MobData.FindMobById(eliteMobId)
        if type(mobStats) == "table" then
            if mobStats.Level ~= nil then
                level = tostring(mobStats.Level)
            end
            if type(mobStats.Name) == "string" and mobStats.Name ~= "" then
                name = mobStats.Name
            end
        end
    end

    local fillRatio = chancePercent / 100
    elitePityText.Text = string.format("Elite %d%%", math.floor(chancePercent + 0.5))
    elitePityTitle.Text = string.format("Lvl %s [%s]", level, name)

    if currentElitePityTween then currentElitePityTween:Cancel() end
    currentElitePityTween = TweenService:Create(elitePityFill, barTweenInfo, {
        Size = UDim2.new(fillRatio, 0, 1, 0),
    })
    currentElitePityTween:Play()
end

---------------------------------------------------------------------------
-- Connect to character (reconnects on respawn)
---------------------------------------------------------------------------

local healthConn = nil

local function connectCharacter(character)
    if healthConn then healthConn:Disconnect(); healthConn = nil end

    local humanoid = character:WaitForChild("Humanoid", 5)
    if not humanoid then return end

    -- Immediate update
    updateHealth(humanoid.Health, humanoid.MaxHealth)

    -- Live updates
    healthConn = humanoid.HealthChanged:Connect(function(newHp)
        updateHealth(newHp, humanoid.MaxHealth)
    end)

    -- Also watch MaxHealth changes (gear swaps can change max HP)
    humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
        updateHealth(humanoid.Health, humanoid.MaxHealth)
    end)
end

if player.Character then
    connectCharacter(player.Character)
end
player.CharacterAdded:Connect(connectCharacter)

local hungerVal = player:WaitForChild("Hunger", 60)
if hungerVal then
    local function refreshHunger()
        updateHunger(hungerVal.Value)
    end
    hungerVal.Changed:Connect(refreshHunger)
    task.defer(refreshHunger)
else
    warn("[HealthClient] Hunger NumberValue not found")
end

player:GetAttributeChangedSignal("IsInEliteZone"):Connect(refreshElitePityBar)
player:GetAttributeChangedSignal("ElitePityChance"):Connect(refreshElitePityBar)
player:GetAttributeChangedSignal("CurrentEliteMobId"):Connect(refreshElitePityBar)
player:GetAttributeChangedSignal("EliteActive"):Connect(refreshElitePityBar)
player:GetAttributeChangedSignal("EliteCurrentHealth"):Connect(refreshElitePityBar)
player:GetAttributeChangedSignal("EliteMaxHealth"):Connect(refreshElitePityBar)
task.defer(refreshElitePityBar)

print("[HealthClient] ready")
