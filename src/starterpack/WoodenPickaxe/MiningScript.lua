-- Mining Script for Pickaxe (LocalScript)
-- Left-click to mine ore with cracking animation

local tool = script.Parent
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local miningRewardRequest = ReplicatedStorage:WaitForChild("MiningRewardRequest")
local miningDebrisRequest = ReplicatedStorage:WaitForChild("MiningDebrisRequest")
local MiningXPEvent = ReplicatedStorage:WaitForChild("MiningXPEvent")
local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local SkillXPShared = require(ReplicatedStorage:WaitForChild("SkillXPShared"))

-- Configuration
local MINE_COOLDOWN = 0.5 -- Seconds between mining hits
local CLICKS_TO_MINE = 3 -- Number of clicks to fully mine ore
local MINE_RANGE = 15 -- Maximum range to mine ore
local ORE_RESPAWN_TIME = 10 -- Seconds before ore respawns
local XP_PER_COAL = 5 -- Fallback if server omits amount; server authoritatively grants XP only when coal is granted
local UI_HIDE_DELAY = 5 -- Seconds before UI hides after last XP gain

-- HUD visibility
local uiShown = false
local lastXPGainTime = 0
local uiHideTask = nil
local priorityLoopRunning = false

-- Function to hide the UI after delay
local function startHideTimer()
    -- Cancel any existing hide task
    if uiHideTask then
        task.cancel(uiHideTask)
        uiHideTask = nil
    end

    uiHideTask = task.delay(UI_HIDE_DELAY, function()
        local gui = PlayerGui:FindFirstChild("MiningXPUI")
        if gui then
            local mainFrame = gui:FindFirstChild("MainFrame")
            if mainFrame then
                mainFrame.Visible = false
                uiShown = false
            end
        end
        uiHideTask = nil
    end)
end

-- Function to update ZIndex based on which XP was most recent
local function setBarZ(guiName, z)
    local g = PlayerGui:FindFirstChild(guiName)
    if not g then return end
    local mf = g:FindFirstChild("MainFrame")
    if not mf then return end
    mf.ZIndex = z
    for _, child in pairs(mf:GetDescendants()) do
        if child:IsA("GuiObject") then
            child.ZIndex = z
        end
    end
end

local function updateZIndexPriority()
    local player = Players.LocalPlayer
    if not player then return end

    local combatTime = player:GetAttribute("LastCombatXPGain") or 0
    local miningTime = player:GetAttribute("LastMiningXPGain") or 0
    local fishingTime = player:GetAttribute("LastFishingXPGain") or 0

    local front = "Combat"
    local best = combatTime
    if miningTime >= best then front, best = "Mining", miningTime end
    if fishingTime >= best then front, best = "Fishing", fishingTime end

    setBarZ("CombatXPUI", front == "Combat" and 10 or 5)
    setBarZ("MiningXPUI", front == "Mining" and 10 or 5)
    setBarZ("FishingXPUI", front == "Fishing" and 10 or 5)
end

-- Start continuous priority loop
local function startPriorityLoop()
    if priorityLoopRunning then return end
    priorityLoopRunning = true

    task.spawn(function()
        while task.wait(0.1) do
            updateZIndexPriority()
        end
    end)
end

-- Function to update the XP UI
local function updateXPUI()
    local gui = PlayerGui:FindFirstChild("MiningXPUI")
    if not gui then return end

    local mainFrame = gui:FindFirstChild("MainFrame")
    if not mainFrame then return end

    -- Show UI if not already shown
    if not uiShown then
        mainFrame.Visible = true
        uiShown = true
    end

    -- Update timestamp for priority system
    local player = Players.LocalPlayer
    if player then
        player:SetAttribute("LastMiningXPGain", tick())
    end

    -- Reset hide timer and start a new one
    lastXPGainTime = tick()
    startHideTimer()

    local xpBackground = mainFrame:FindFirstChild("XPBackground")
    local xpFill = xpBackground and xpBackground:FindFirstChild("XPFill")
    local levelLabel = mainFrame:FindFirstChild("LevelLabel")
    local xpLabel = mainFrame:FindFirstChild("XPLabel")

    local xpNeeded = SkillXPShared.GetXPForLevel(SkillXPShared.Mining.Level)
    local progress = math.clamp(SkillXPShared.Mining.XP / xpNeeded, 0, 1)

    -- Update fill bar (leave 4 pixels padding on each side)
    if xpFill then
        xpFill.Size = UDim2.new(progress, 0, 1, -4)
    end

    -- Update labels
    if levelLabel then
        levelLabel.Text = "Level " .. SkillXPShared.Mining.Level
    end
    if xpLabel then
        xpLabel.Text = SkillXPShared.Mining.XP .. " / " .. xpNeeded .. " XP"
    end
end

-- Function to add XP and check for level up
local function addXP(amount)
    SkillXPShared.Mining.XP = SkillXPShared.Mining.XP + amount
    local xpNeeded = SkillXPShared.GetXPForLevel(SkillXPShared.Mining.Level)

    -- Check for level up
    while SkillXPShared.Mining.XP >= xpNeeded do
        SkillXPShared.Mining.XP = SkillXPShared.Mining.XP - xpNeeded
        SkillXPShared.Mining.Level = SkillXPShared.Mining.Level + 1
        xpNeeded = SkillXPShared.GetXPForLevel(SkillXPShared.Mining.Level)
        print("Mining level up! Now level " .. SkillXPShared.Mining.Level)
    end

    SkillXPShared.Notify()
    updateXPUI()
end

MiningXPEvent.OnClientEvent:Connect(function(xpAmount)
    local n = (typeof(xpAmount) == "number" and xpAmount > 0) and xpAmount or XP_PER_COAL
    addXP(n)
end)

-- Ore disappear / respawn is handled on the server (MiningRewardHandler) so everyone and mobs stay in sync.

-- Track click counts for each ore
local oreClicks = {}
-- Pristine part colors per ore model (captured on first hit, used in crack effect)
local oreOriginalColors = {}

-- Debounce to prevent spam mining
local canMine = true

-- Function to check if a part is coal ore
local function isCoalOre(part)
    local current = part
    while current do
        if string.find(current.Name, "Coal") then
            return current
        end
        current = current.Parent
    end
    return nil
end

-- Function to create cracking effect on ore
local function createCrackEffect(oreModel, clickProgress)
    -- Flash the ore and add slight shake
    task.spawn(function()
        local partsToFlash = {}
        for _, part in pairs(oreModel:GetDescendants()) do
            if part:IsA("BasePart") then
                table.insert(partsToFlash, {part = part, originalColor = part.Color, originalCFrame = part.CFrame})
                -- Make it darker with each click to show damage
                local darken = 1 - (clickProgress * 0.15)
                part.Color = Color3.new(part.Color.R * darken, part.Color.G * darken, part.Color.B * darken)
            end
        end

        -- Shake effect
        local shakeIntensity = clickProgress * 0.1
        for i = 1, 3 do
            for _, data in pairs(partsToFlash) do
                if data.part and data.originalCFrame then
                    local offset = Vector3.new(
                        math.random() * 2 - 1,
                        math.random() * 2 - 1,
                        math.random() * 2 - 1
                    ) * shakeIntensity
                    data.part.CFrame = data.originalCFrame * CFrame.new(offset)
                end
            end
            task.wait(0.03)
        end

        -- Reset position and restore color after damage flash
        for _, data in pairs(partsToFlash) do
            if data.part and data.originalCFrame then
                data.part.CFrame = data.originalCFrame
            end
            if data.part and data.originalColor then
                data.part.Color = data.originalColor
            end
        end
    end)
end

-- Function to get what player is looking at
local function getTargetOre(player)
    local character = player.Character
    if not character then return nil end

    local camera = workspace.CurrentCamera
    if not camera then return nil end

    -- Raycast from camera in the direction the player is looking
    local rayOrigin = camera.CFrame.Position
    local rayDirection = (camera.CFrame.LookVector * MINE_RANGE)

    local raycastParams = RaycastParams.new()
    raycastParams.FilterDescendantsInstances = {character}
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude

    local raycastResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)

    if raycastResult then
        local hitPart = raycastResult.Instance
        if hitPart:IsA("BasePart") and hitPart.Transparency >= 1 then
            return nil
        end
        return isCoalOre(hitPart)
    end

    return nil
end

-- Handle tool activation (left click)
tool.Activated:Connect(function()
    if not canMine then return end

    local player = Players.LocalPlayer
    if not player then return end

    -- Get the ore the player is looking at
    local oreModel = getTargetOre(player)

    if oreModel then
        canMine = false

        -- Initialize click count for this ore
        if not oreClicks[oreModel] then
            oreClicks[oreModel] = 0
            oreOriginalColors[oreModel] = {}
            for _, p in pairs(oreModel:GetDescendants()) do
                if p:IsA("BasePart") then
                    oreOriginalColors[oreModel][p] = p.Color
                end
            end
        end

        oreClicks[oreModel] = oreClicks[oreModel] + 1
        local clicks = oreClicks[oreModel]
        local progress = clicks / CLICKS_TO_MINE

        print("Mining " .. oreModel.Name .. " - Click " .. clicks .. "/" .. CLICKS_TO_MINE)

        -- Create cracking effect
        createCrackEffect(oreModel, progress)

        local orePart = oreModel:FindFirstChildWhichIsA("BasePart", true)
        if orePart then
            miningDebrisRequest:FireServer(orePart)
        end

        -- Check if ore is fully mined
        if clicks >= CLICKS_TO_MINE then
            print("Ore fully mined!")

            if orePart then
                miningRewardRequest:FireServer(orePart)
            end

            oreClicks[oreModel] = nil
            oreOriginalColors[oreModel] = nil
        end

        -- Cooldown
        task.wait(MINE_COOLDOWN)
        canMine = true
    end
end)

-- Start the priority loop when script loads
startPriorityLoop()

SkillXPShared.ApplyXPHudLayout(PlayerGui)

print("Mining script loaded for " .. tool.Name)