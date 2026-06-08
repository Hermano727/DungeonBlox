-- Combat XP Client Script
-- Handles the combat XP UI updates

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local SkillXPShared = require(ReplicatedStorage:WaitForChild("SkillXPShared"))

-- Configuration
local UI_HIDE_DELAY = 5 -- Seconds before UI hides after last XP gain

-- HUD visibility (popup uses its own cloned bars)
local uiShown = false
local uiHideTask = nil
local priorityLoopRunning = false

-- Function to hide the UI after delay
local function startHideTimer()
    if uiHideTask then
        task.cancel(uiHideTask)
        uiHideTask = nil
    end

    uiHideTask = task.delay(UI_HIDE_DELAY, function()
        local gui = PlayerGui:FindFirstChild("CombatXPUI")
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
    local gui = PlayerGui:FindFirstChild("CombatXPUI")
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
        player:SetAttribute("LastCombatXPGain", tick())
    end

    -- Reset hide timer and start a new one
    startHideTimer()

    local xpBackground = mainFrame:FindFirstChild("XPBackground")
    local xpFill = xpBackground and xpBackground:FindFirstChild("XPFill")
    local levelLabel = mainFrame:FindFirstChild("LevelLabel")
    local xpLabel = mainFrame:FindFirstChild("XPLabel")

    local xpNeeded = SkillXPShared.GetXPForLevel(SkillXPShared.Combat.Level)
    local progress = math.clamp(SkillXPShared.Combat.XP / xpNeeded, 0, 1)

    -- Update fill bar
    if xpFill then
        xpFill.Size = UDim2.new(progress, 0, 1, -4)
    end

    -- Update labels
    if levelLabel then
        levelLabel.Text = "Level " .. SkillXPShared.Combat.Level
    end
    if xpLabel then
        xpLabel.Text = SkillXPShared.Combat.XP .. " / " .. xpNeeded .. " XP"
    end
end

-- Function to add XP and check for level up
local function addXP(amount)
    SkillXPShared.Combat.XP = SkillXPShared.Combat.XP + (tonumber(amount) or 0)
    local xpNeeded = SkillXPShared.GetXPForLevel(SkillXPShared.Combat.Level)

    -- Check for level up
    while SkillXPShared.Combat.XP >= xpNeeded do
        SkillXPShared.Combat.XP = SkillXPShared.Combat.XP - xpNeeded
        SkillXPShared.Combat.Level = SkillXPShared.Combat.Level + 1
        xpNeeded = SkillXPShared.GetXPForLevel(SkillXPShared.Combat.Level)
        print("Combat level up! Now level " .. SkillXPShared.Combat.Level)
    end

    SkillXPShared.Notify()
    updateXPUI()
end

-- Listen for combat XP events from server
local combatXPEvent = ReplicatedStorage:WaitForChild("CombatXPEvent")
combatXPEvent.OnClientEvent:Connect(function(xpAmount)
    addXP(xpAmount)
end)

-- Start the priority loop when script loads
startPriorityLoop()

task.defer(function()
	SkillXPShared.ApplyXPHudLayout(PlayerGui)
end)

PlayerGui.ChildAdded:Connect(function(child)
	if child.Name == "CombatXPUI" or child.Name == "MiningXPUI" or child.Name == "FishingXPUI" then
		task.defer(function()
			SkillXPShared.ApplyXPHudLayout(PlayerGui)
		end)
	end
end)

print("Combat XP client loaded")
