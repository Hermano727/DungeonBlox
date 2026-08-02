--[[
    HealthClient
    Builds the top-center HP bar and keeps it synced to the local character's Humanoid.
    Layout:  [♥  [bar fill]  47 / 100]
    Reconnects automatically on every character respawn.
]]

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local StarterGui   = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HungerConfig = require(ReplicatedStorage:WaitForChild("HungerConfig"))
local MobData = require(ReplicatedStorage:WaitForChild("MobData"))

-- Disable Roblox's built-in top-right health bar
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

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

-- Outer container (centered top)
local container = Instance.new("Frame", gui)
container.Name             = "Container"
container.AnchorPoint      = Vector2.new(0.5, 0)
container.Position         = UDim2.new(0.5, 0, 0.03, 0)
container.Size             = UDim2.fromOffset(510, 98)
container.BackgroundTransparency = 1
container.BorderSizePixel  = 0

local elitePityTitle = Instance.new("TextLabel", container)
elitePityTitle.Name = "ElitePityTitle"
elitePityTitle.Size = UDim2.fromOffset(440, 16)
elitePityTitle.Position = UDim2.fromOffset(26, 0)
elitePityTitle.BackgroundTransparency = 1
elitePityTitle.Font = Enum.Font.GothamBold
elitePityTitle.TextSize = 12
elitePityTitle.TextColor3 = Color3.fromRGB(222, 188, 255)
elitePityTitle.TextStrokeTransparency = 0.35
elitePityTitle.TextStrokeColor3 = Color3.fromRGB(58, 26, 92)
elitePityTitle.TextXAlignment = Enum.TextXAlignment.Left
elitePityTitle.Text = "Lvl -- [Elite]"
elitePityTitle.ZIndex = 3
elitePityTitle.Visible = false

local elitePityBarBg = Instance.new("Frame", container)
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

local elitePityText = Instance.new("TextLabel", container)
elitePityText.Name = "ElitePityText"
elitePityText.Size = UDim2.fromOffset(98, 18)
elitePityText.Position = UDim2.fromOffset(412, 12)
elitePityText.BackgroundTransparency = 1
elitePityText.Font = Enum.Font.GothamBold
elitePityText.TextSize = 11
elitePityText.TextColor3 = Color3.fromRGB(222, 188, 255)
elitePityText.TextStrokeTransparency = 0.4
elitePityText.TextStrokeColor3 = Color3.fromRGB(58, 26, 92)
elitePityText.TextXAlignment = Enum.TextXAlignment.Left
elitePityText.Text = "Elite 1%"
elitePityText.ZIndex = 3
elitePityText.Visible = false

-- Heart icon
local heart = Instance.new("TextLabel", container)
heart.Name                   = "Heart"
heart.Size                   = UDim2.fromOffset(22, 26)
heart.Position               = UDim2.fromOffset(95, 28)
heart.BackgroundTransparency = 1
heart.Font                   = Enum.Font.GothamBold
heart.TextSize               = 16
heart.TextColor3             = Color3.fromRGB(220, 60, 60)
heart.TextStrokeTransparency = 0.3
heart.TextStrokeColor3       = Color3.fromRGB(80, 0, 0)
heart.Text                   = "\xe2\x99\xa5"
heart.ZIndex                 = 3

-- Bar background
local barBg = Instance.new("Frame", container)
barBg.Name             = "BarBackground"
barBg.Position         = UDim2.fromOffset(121, 31)
barBg.Size             = UDim2.fromOffset(190, 20)
barBg.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
barBg.BackgroundTransparency = 0.3
barBg.BorderSizePixel  = 0
barBg.ZIndex           = 2
Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 4)
local barStroke = Instance.new("UIStroke", barBg)
barStroke.Thickness = 1
barStroke.Color     = Color3.fromRGB(100, 30, 30)
barStroke.Transparency = 0.4

-- Bar fill (red)
local barFill = Instance.new("Frame", barBg)
barFill.Name             = "BarFill"
barFill.Position         = UDim2.new(0, 0, 0, 0)
barFill.Size             = UDim2.new(1, 0, 1, 0)
barFill.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
barFill.BorderSizePixel  = 0
barFill.ZIndex           = 3
Instance.new("UICorner", barFill).CornerRadius = UDim.new(0, 4)

-- HP text (right of bar)
local hpText = Instance.new("TextLabel", container)
hpText.Name                   = "HPText"
hpText.Size                   = UDim2.fromOffset(98, 26)
hpText.Position               = UDim2.fromOffset(315, 28)
hpText.BackgroundTransparency = 1
hpText.Font                   = Enum.Font.GothamBold
hpText.TextSize               = 13
hpText.TextColor3             = Color3.new(1, 1, 1)
hpText.TextStrokeTransparency = 0.4
hpText.TextStrokeColor3       = Color3.fromRGB(80, 0, 0)
hpText.TextXAlignment         = Enum.TextXAlignment.Left
hpText.Text                   = "-- / --"
hpText.ZIndex                 = 3

-- Hunger row (below health bar)
local hungerIcon = Instance.new("TextLabel", container)
hungerIcon.Name = "HungerIcon"
hungerIcon.Size = UDim2.fromOffset(22, 22)
hungerIcon.Position = UDim2.fromOffset(95, 58)
hungerIcon.BackgroundTransparency = 1
hungerIcon.Font = Enum.Font.GothamBold
hungerIcon.TextSize = 16
hungerIcon.Text = "🍖"
hungerIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
hungerIcon.ZIndex = 3

local hungerBarBg = Instance.new("Frame", container)
hungerBarBg.Name = "HungerBarBg"
hungerBarBg.Size = UDim2.fromOffset(190, 16)
hungerBarBg.Position = UDim2.fromOffset(121, 61)
hungerBarBg.BackgroundColor3 = Color3.fromRGB(40, 28, 18)
hungerBarBg.BorderSizePixel = 0
hungerBarBg.ZIndex = 2
Instance.new("UICorner", hungerBarBg).CornerRadius = UDim.new(0, 4)

local hungerFill = Instance.new("Frame", hungerBarBg)
hungerFill.Name = "Fill"
hungerFill.AnchorPoint = Vector2.new(0, 0.5)
hungerFill.Position = UDim2.new(0, 0, 0.5, 0)
hungerFill.Size = UDim2.new(1, 0, 1, 0)
hungerFill.BackgroundColor3 = Color3.fromRGB(139, 90, 43)
hungerFill.BorderSizePixel = 0
hungerFill.ZIndex = 3
Instance.new("UICorner", hungerFill).CornerRadius = UDim.new(0, 4)

local hungerText = Instance.new("TextLabel", container)
hungerText.Name = "HungerText"
hungerText.Size = UDim2.fromOffset(98, 22)
hungerText.Position = UDim2.fromOffset(315, 56)
hungerText.BackgroundTransparency = 1
hungerText.Font = Enum.Font.GothamBold
hungerText.TextSize = 12
hungerText.TextColor3 = Color3.new(1, 1, 1)
hungerText.TextStrokeTransparency = 0.4
hungerText.TextStrokeColor3 = Color3.fromRGB(60, 40, 20)
hungerText.TextXAlignment = Enum.TextXAlignment.Left
hungerText.Text = "-- / --"
hungerText.ZIndex = 3


---------------------------------------------------------------------------
-- Update logic
---------------------------------------------------------------------------

local barTweenInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local currentTween = nil
local currentHungerTween = nil
local currentElitePityTween = nil

local function updateHealth(current, max)
    if max <= 0 then return end
    local ratio = math.clamp(current / max, 0, 1)

    -- Tween the bar fill
    if currentTween then currentTween:Cancel() end
    currentTween = TweenService:Create(barFill, barTweenInfo, {
        Size = UDim2.new(ratio, 0, 1, 0)
    })
    currentTween:Play()

    -- Update colour: green > yellow > red
    local fillColor
    if ratio > 0.6 then
        fillColor = Color3.fromRGB(200, 40, 40)        -- healthy red
    elseif ratio > 0.3 then
        fillColor = Color3.fromRGB(210, 120, 30)       -- warning orange
    else
        fillColor = Color3.fromRGB(220, 30, 30)        -- critical red (brighter)
    end
    barFill.BackgroundColor3 = fillColor

    -- Update text
    hpText.Text = math.floor(current) .. " / " .. math.floor(max)
end

local function updateHunger(current, max)
    if max <= 0 then return end
    local ratio = math.clamp(current / max, 0, 1)

    if currentHungerTween then currentHungerTween:Cancel() end
    currentHungerTween = TweenService:Create(hungerFill, barTweenInfo, {
        Size = UDim2.new(ratio, 0, 1, 0),
    })
    currentHungerTween:Play()

    hungerText.Text = math.floor(current) .. " / " .. math.floor(max)
end

local function refreshElitePityBar()
    local inEliteZone = player:GetAttribute("IsInEliteZone") == true
    local eliteActive = player:GetAttribute("EliteActive") == true
    local chancePercent = tonumber(player:GetAttribute("ElitePityChance")) or 1
    local eliteMobId = player:GetAttribute("CurrentEliteMobId")
    chancePercent = math.clamp(chancePercent, 1, 100)

    local shouldShow = inEliteZone or eliteActive
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

    local fillRatio
    if eliteActive then
        local hp = tonumber(player:GetAttribute("EliteCurrentHealth")) or 0
        local maxHp = tonumber(player:GetAttribute("EliteMaxHealth")) or 0
        if maxHp <= 0 then maxHp = 1 end
        fillRatio = math.clamp(hp / maxHp, 0, 1)
        elitePityText.Text = string.format("HP %d/%d", math.floor(hp + 0.5), math.floor(maxHp + 0.5))
        elitePityTitle.Text = string.format("Lvl %s [%s]", level, name)
    else
        fillRatio = chancePercent / 100
        elitePityText.Text = string.format("Elite %d%%", math.floor(chancePercent + 0.5))
        elitePityTitle.Text = string.format("Lvl %s [%s]", level, name)
    end

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
        updateHunger(hungerVal.Value, HungerConfig.MAX_HUNGER)
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
