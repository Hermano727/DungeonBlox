local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config        = require(ReplicatedStorage:WaitForChild("EnergyConfig"))
local UIFonts       = require(ReplicatedStorage:WaitForChild("UIFonts"))
local HudBarStyle   = require(ReplicatedStorage:WaitForChild("HudBarStyle"))
local States        = require(ReplicatedStorage:WaitForChild("PlayerStateEnum"))
local ProfileMenusState = require(ReplicatedStorage:WaitForChild("ProfileMenusState"))
local EnergyEvents  = ReplicatedStorage:WaitForChild("EnergyEvents")
local GameEvents    = ReplicatedStorage:WaitForChild("GameEvents")
local EnergyChanged = EnergyEvents:WaitForChild("EnergyChanged")
local StateChanged  = GameEvents:WaitForChild("StateChanged")

local player      = Players.LocalPlayer
local character   = player.Character or player.CharacterAdded:Wait()
local humanoid    = character:WaitForChild("Humanoid")
local playerGui   = player:WaitForChild("PlayerGui")
local energyBarGui  = playerGui:WaitForChild("EnergyBarGui")
-- EnergyBarGui's StarterGui default is Enabled=false (2026-09-12, per direct request -- a
-- hand-built StarterGui Instance with Enabled=true previews live in Studio's EDIT-mode
-- viewport, not just in Play, since Studio renders any enabled StarterGui object regardless
-- of play state -- unlike every other HUD element here, which is built at runtime by a
-- LocalScript and so only exists once a real client session is running). Turning it on here
-- means it still shows normally in an actual game session, just not while idly editing.
energyBarGui.Enabled = true
local barBackground = energyBarGui:WaitForChild("BarBackground")
barBackground:SetAttribute("TutorialTarget", "hud_energy") -- the tutorial's spotlight finds it
local barFill       = barBackground:WaitForChild("BarFill")
-- Use FindFirstChild with fallback so script never freezes if label is missing
local lowEnergyLabel = barBackground:FindFirstChild("LowEnergyLabel")
local energyLabel     = barBackground:FindFirstChild("EnergyLabel")

-- EnergyBarGui is a hand-built StarterGui Instance (outside Rojo's synced tree -- see
-- syncbackRules.ignoreTrees in default.project.json), so its FontFace was a permanently baked
-- Studio-side property with no connection to shared/UIFonts.luau. Applying UIFonts.HUDLabel
-- here at runtime instead means this bar's font actually follows the registry like every other
-- HUD element, instead of silently drifting the next time the body font changes.
if lowEnergyLabel and lowEnergyLabel:IsA("TextLabel") then
	lowEnergyLabel.FontFace = UIFonts.HUDLabel
end

-- Remove the "ENERGY" text entirely (2026-09-08, per direct request: "can
-- remove the energy text from teh energy bar"). LowEnergyLabel (the
-- "PANTING..." lockout message) is a separate label and is left untouched.
if energyLabel then
	energyLabel:Destroy()
	energyLabel = nil
end

-- BarBackground's base footprint, Position and UISizeConstraint are baked
-- Studio-side properties on this hand-built instance (outside Rojo's synced
-- tree), so this Rojo-synced script overrides them at runtime instead.
-- 2026-09-08: briefly matched HP's size exactly ("mke the energy bar the
-- same size as the hp bar"), but the ornament border art couldn't wrap the
-- bigger bar even at Border.Scale 3.0, so per direct follow-up feedback
-- it's now 33% smaller than that HP-matching size instead ("its okay that
-- its smaller than the health bar"). Also shifted up 15 ("move all 3 up by
-- a lil bit"). These numbers MUST be kept in sync with
-- HealthClient.client.lua's ENERGY_WIDTH_SCALE/ENERGY_WIDTH_MIN/
-- ENERGY_WIDTH_MAX/ENERGY_HEIGHT/ENERGY_BOTTOM_OFFSET.
local BAR_SIZE_MULTIPLIER = 1.33 * 0.67 -- ~0.8911
local BAR_WIDTH_SCALE = 0.22 * BAR_SIZE_MULTIPLIER -- ~0.1960
local BAR_WIDTH_MIN = 260 * BAR_SIZE_MULTIPLIER    -- ~231.7
local BAR_WIDTH_MAX = 460 * BAR_SIZE_MULTIPLIER    -- ~409.9
local BAR_HEIGHT = 7 -- thin hairline bar since 2026-10-01 (HudBarStyle); HealthClient ENERGY_HEIGHT
local BAR_BOTTOM_OFFSET = -145                     -- was -96, then -111, shifted up again 2026-09-10
                                                    -- to clear the Hotbar diamond slots below (keep in
                                                    -- sync with HealthClient.client.lua's ENERGY_BOTTOM_OFFSET)

barBackground.Size = UDim2.new(BAR_WIDTH_SCALE, 0, 0, BAR_HEIGHT)
barBackground.Position = UDim2.new(0.5, 0, 1, BAR_BOTTOM_OFFSET)
local DEFAULT_ENERGY_ANCHOR, DEFAULT_ENERGY_POS = barBackground.AnchorPoint, barBackground.Position

local energySizeConstraint = barBackground:FindFirstChildOfClass("UISizeConstraint")
if energySizeConstraint then
	energySizeConstraint.MinSize = Vector2.new(BAR_WIDTH_MIN, BAR_HEIGHT)
	energySizeConstraint.MaxSize = Vector2.new(BAR_WIDTH_MAX, BAR_HEIGHT)
end

-- Changed 2026-09-09 (direct request, alongside making the HP bar green):
-- a soft, muted gold instead of the old green -- reads clearly as "not the
-- HP bar" without being a harsh/neon yellow.
-- Muted further for the thin bars (2026-10-01): tarnished gold, and a dark red lockout.
local COLOR_NORMAL  = Color3.fromRGB(190, 150, 64)
local COLOR_LOCKOUT = Color3.fromRGB(170, 40, 36)
local barTweenInfo   = TweenInfo.new(0.08, Enum.EasingStyle.Linear)
local flashTweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local flashTween     = TweenService:Create(barFill, flashTweenInfo, {BackgroundTransparency=0.6})

-- The same gentle top-light/bottom-dark sheen as the HP bar (HudBarStyle). Re-tinted (not
-- replaced) on lockout so it carries through the red flash too.
local gradientForColor = HudBarStyle.GradientFor

local barFillGradient = Instance.new("UIGradient")
barFillGradient.Rotation = 90
barFillGradient.Color = gradientForColor(COLOR_NORMAL)
barFillGradient.Parent = barFill

-- Trough, bronze hairline, end caps and the drifting grain (shared with the HP bar).
HudBarStyle.Apply(barBackground, barFill)

-- "Panting..." is too tall to sit above the thin bar (it would land on the HP bar): it goes
-- left of the bar, mirroring the number on the right (HudBarStyle.PlaceReadout).
if lowEnergyLabel and lowEnergyLabel:IsA("TextLabel") then
	lowEnergyLabel.AnchorPoint = Vector2.new(1, 0.5)
	lowEnergyLabel.Position = UDim2.new(0, -HudBarStyle.SideOffset(barBackground), 0.5, 0)
	lowEnergyLabel.Size = UDim2.fromOffset(120, 16)
	lowEnergyLabel.TextXAlignment = Enum.TextXAlignment.Right
end

-- Numeric energy readout (2026-09-08, per direct request: "add a numeric to
-- the energy bar ... just display that number", not a fraction -- Energy is
-- already a 0-100 scale per EnergyConfig.MAX_ENERGY). Same centered-in-bar +
-- black drop-shadow treatment HealthClient uses for its HP number.
local energyText = Instance.new("TextLabel")
energyText.Name                   = "EnergyText"
energyText.Size                   = UDim2.fromScale(1, 1)
energyText.BackgroundTransparency = 1
energyText.FontFace               = UIFonts.HUDLabel
energyText.TextSize               = 13
energyText.TextColor3             = Color3.new(1, 1, 1)
energyText.TextStrokeTransparency = 0.4
energyText.TextStrokeColor3       = Color3.fromRGB(20, 50, 10)
energyText.TextXAlignment         = Enum.TextXAlignment.Center
energyText.TextYAlignment         = Enum.TextYAlignment.Center
energyText.Text                   = "--"
energyText.ZIndex                 = 7
energyText.Parent                 = barBackground

local energyTextShadow = energyText:Clone()
energyTextShadow.Name = "EnergyTextShadow"
energyTextShadow.Position = UDim2.fromScale(0, 0) + UDim2.fromOffset(1, 2)
energyTextShadow.TextColor3 = Color3.new(0, 0, 0)
energyTextShadow.TextTransparency = 0.5
energyTextShadow.TextStrokeTransparency = 1
energyTextShadow.ZIndex = 6
energyTextShadow.Parent = barBackground
HudBarStyle.PlaceReadout(barBackground, energyText, energyTextShadow)

local function setLabelVisible(v)
	if not lowEnergyLabel then return end
	TweenService:Create(lowEnergyLabel, TweenInfo.new(0.2), {TextTransparency = v and 0 or 1}):Play()
end

local isInLockout  = false
local currentBarTween = nil

local function updateBar(e)
	local ratio = math.clamp(e / Config.MAX_ENERGY, 0, 1)
	if currentBarTween then currentBarTween:Cancel() end
	currentBarTween = TweenService:Create(barFill, barTweenInfo, {Size=UDim2.new(ratio,0,1,0)})
	currentBarTween:Play()

	local displayValue = tostring(math.clamp(math.floor(e + 0.5), 0, math.floor(Config.MAX_ENERGY)))
	energyText.Text = displayValue
	energyTextShadow.Text = displayValue
end

local function enterLockout()
	flashTween:Cancel()
	barFill.BackgroundTransparency = 0
	barFill.BackgroundColor3 = COLOR_LOCKOUT
	barFillGradient.Color = gradientForColor(COLOR_LOCKOUT)
	flashTween:Play()
	if lowEnergyLabel and lowEnergyLabel:IsA("TextLabel") then
		lowEnergyLabel.Text = "PANTING..."
	end
	setLabelVisible(true)
end

local function exitLockout()
	flashTween:Cancel()
	barFill.BackgroundTransparency = 0
	barFill.BackgroundColor3 = COLOR_NORMAL
	barFillGradient.Color = gradientForColor(COLOR_NORMAL)
	setLabelVisible(false)
end

---------------------------------------------------------------------------
-- ProfileMenus-open layout -- Energy relocates alongside HP/Hunger/Potions while the
-- Inventory/Skills/Stats/Hearthstone/Party panel is open. First pass (2026-09-13) anchored
-- this to the screen's top-right corner; per direct follow-up feedback the same day, this now
-- hangs directly beneath the QuickNav carousel instead, reading its live position from
-- ProfileMenusState.GetCarouselAnchor() (published by the Inventory tab's InventoryMain since
-- 2026-10-01, the top-centre of the bag's column) rather than a fixed
-- corner offset -- see HealthClient.client.lua's matching section and ProfileMenusState's doc
-- comment for the full reasoning. This bar's Y target has to land right below HP's in that
-- stack, so MIRROR_HP_HEIGHT/
-- MIRROR_GAP_HP_TO_ENERGY/MENU_PAD_TOP still mirror HealthClient.client.lua's own constants --
-- MUST stay in sync with that file, same convention as BAR_SIZE_MULTIPLIER and friends above.
---------------------------------------------------------------------------

local MENU_ANCHOR = Vector2.new(0.5, 0) -- top-center -- hangs off the carousel's own bottom-center anchor
-- MUST match HealthClient's MENU_PAD_TOP / MENU_DROP_SCALE (2026-10-01: both 0, the anchor is
-- the top of the HP bar). While a menu is open this bar is hidden anyway (HudHider: the energy
-- GUI isn't an overlay); the position below only matters if that changes.
local MENU_PAD_TOP = 0
local MENU_DROP_SCALE = 0
local MENU_MOVE_TWEEN = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local MIRROR_HP_HEIGHT = 10 -- HealthClient's HP_HEIGHT
local MIRROR_GAP_HP_TO_ENERGY = 8 -- HealthClient's GAP_HP_TO_ENERGY

-- Valve-puzzle layout: mirrors HealthClient's (MAZE_TOP_LEFT + the HP->Energy stacking MUST
-- match that file). While the Miasma valve maze is open the bars sit top-left, off the puzzle.
local MAZE_ANCHOR = Vector2.new(0, 0)
local MAZE_TOP_LEFT = Vector2.new(20, 76)

local function applyProfileMenusLayout()
	if Players.LocalPlayer:GetAttribute("MiasmaMazeOpen") == true then
		TweenService:Create(barBackground, MENU_MOVE_TWEEN, {
			AnchorPoint = MAZE_ANCHOR,
			Position = UDim2.fromOffset(MAZE_TOP_LEFT.X, MAZE_TOP_LEFT.Y + MIRROR_HP_HEIGHT + MIRROR_GAP_HP_TO_ENERGY),
		}):Play()
		return
	end
	local open = ProfileMenusState.IsOpen()
	local anchor = ProfileMenusState.GetCarouselAnchor()

	local energyPos: UDim2? = nil
	if anchor then
		-- HP is the first bar under the carousel now: the elite pity bar moved to the
		-- top of the screen and left the menu stack (mirrors HealthClient).
		local hpY = anchor.Y + MENU_PAD_TOP
		local energyY = hpY + MIRROR_HP_HEIGHT + MIRROR_GAP_HP_TO_ENERGY
		energyPos = UDim2.new(0, anchor.X, MENU_DROP_SCALE, energyY)
	end

	if open and not energyPos then
		-- Carousel hasn't published a position yet -- shouldn't normally happen, but don't
		-- yank the bar to the screen's top-left corner if it somehow is nil.
		return
	end

	TweenService:Create(barBackground, MENU_MOVE_TWEEN, {
		AnchorPoint = open and MENU_ANCHOR or DEFAULT_ENERGY_ANCHOR,
		Position = open and (energyPos :: UDim2) or DEFAULT_ENERGY_POS,
	}):Play()
end

ProfileMenusState.Subscribe(applyProfileMenusLayout)
Players.LocalPlayer:GetAttributeChangedSignal("MiasmaMazeOpen"):Connect(applyProfileMenusLayout)

EnergyChanged.OnClientEvent:Connect(function(newEnergy, lockout)
	updateBar(newEnergy)
	if lockout and not isInLockout then
		isInLockout = true
		enterLockout()
	elseif not lockout and isInLockout then
		isInLockout = false
		exitLockout()
	end
end)

StateChanged.OnClientEvent:Connect(function(new, prev)
	if new == States.LOW_ENERGY and not isInLockout then
		isInLockout = true enterLockout()
	elseif prev == States.LOW_ENERGY and isInLockout then
		isInLockout = false exitLockout()
	end
end)

-- Paint the real color/gradient immediately instead of leaving whatever flat
-- color was baked into the hand-built instance until the first server event.
exitLockout()

-- Vitals hide while a menu is up (RS/HudVitals, same rule HealthClient follows). This script
-- re-runs every life, so the subscription is dropped when it goes.
do
	local HudVitals = require(ReplicatedStorage:WaitForChild("HudVitals"))
	local function applyVitals(hidden) barBackground.Visible = not hidden end
	applyVitals(HudVitals.IsHidden())
	local unsubscribe = HudVitals.Subscribe(applyVitals)
	script.Destroying:Connect(unsubscribe)
	character.Destroying:Connect(unsubscribe)
end
