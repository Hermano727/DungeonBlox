-- MobHPBarUI
-- Builds and refreshes the floating name/level + health-bar BillboardGui
-- shown above a mob. Split out of MobClass so the AI/combat/spawning logic
-- there isn't tangled up with UI construction -- this module only ever reads
-- from a mob (Model, Stats, Level, MobID, CurrentHealth, MaxHealth, HPBar)
-- and returns/mutates Instances; it never touches AI state or combat.

local MobHPBarUI = {}

-- HP Bar colors
local HP_BAR_COLOR_FULL = Color3.fromRGB(0, 255, 0)    -- Green at full health
local HP_BAR_COLOR_MID = Color3.fromRGB(255, 255, 0)     -- Yellow at half health
local HP_BAR_COLOR_LOW = Color3.fromRGB(255, 0, 0)      -- Red at low health

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

    -- Create BillboardGui for the name/level + HP bar
    local billboardGui = Instance.new("BillboardGui")
    billboardGui.Name = "HPBar"
    billboardGui.Size = UDim2.new(5, 0, 0.75, 0)
    billboardGui.StudsOffset = Vector3.new(0, 3, 0)
    billboardGui.Adornee = head
    billboardGui.AlwaysOnTop = true
    billboardGui.Parent = mob.Model

    -- Name/Level label above the health bar
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "NameTag"
    titleLabel.Size = UDim2.new(1, 0, 0.25, 0)
    titleLabel.Position = UDim2.new(0, 0, 0, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Font = Enum.Font.GothamBold
    titleLabel.TextSize = 14
    titleLabel.TextColor3 = Color3.fromRGB(255, 220, 150)
    titleLabel.TextStrokeTransparency = 0.3

    local mobName = (mob.Stats and mob.Stats.Name) or mob.MobID
    titleLabel.Text = "Level " .. tostring(mob.Level) .. " " .. tostring(mobName)
    Instance.new("UIStroke", titleLabel).Color = Color3.fromRGB(80, 60, 20)
    titleLabel.Parent = billboardGui

    -- Create background frame (dark background)
    local background = Instance.new("Frame")
    background.Name = "Background"
    background.Size = UDim2.new(1, 0, 0.45, 0)
    background.Position = UDim2.new(0, 0, 0.25, 0)
    background.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    background.BorderSizePixel = 2
    background.BorderColor3 = Color3.fromRGB(20, 20, 20)
    background.Parent = billboardGui

    -- Create health bar fill (green by default)
    local healthBar = Instance.new("Frame")
    healthBar.Name = "HealthBar"
    healthBar.Size = UDim2.new(1, 0, 1, 0)
    healthBar.Position = UDim2.new(0, 0, 0, 0)
    healthBar.BackgroundColor3 = HP_BAR_COLOR_FULL
    healthBar.BorderSizePixel = 0
    healthBar.Parent = background

    -- Create corner radius for rounded look
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 4)
    corner.Parent = background

    local healthCorner = Instance.new("UICorner")
    healthCorner.CornerRadius = UDim.new(0, 4)
    healthCorner.Parent = healthBar

    return billboardGui
end

-- Refresh the health bar fill/color on an already-created HPBar to match
-- mob.CurrentHealth / mob.MaxHealth. No-op if the mob has no HP bar yet.
function MobHPBarUI.Update(mob)
    if not mob.HPBar then return end

    local healthBar = mob.HPBar:FindFirstChild("Background", true)
    if healthBar then
        healthBar = healthBar:FindFirstChild("HealthBar")
    end
    if not healthBar then return end

    -- Calculate health percentage
    local healthPercent = mob.CurrentHealth / mob.MaxHealth

    -- Update bar size
    healthBar.Size = UDim2.new(healthPercent, 0, 1, 0)

    -- Update color based on health percentage
    if healthPercent > 0.5 then
        -- Green to Yellow transition
        healthBar.BackgroundColor3 = HP_BAR_COLOR_FULL:Lerp(HP_BAR_COLOR_MID, (1 - healthPercent) * 2)
    else
        -- Yellow to Red transition
        healthBar.BackgroundColor3 = HP_BAR_COLOR_MID:Lerp(HP_BAR_COLOR_LOW, (0.5 - healthPercent) * 2)
    end
end

return MobHPBarUI
