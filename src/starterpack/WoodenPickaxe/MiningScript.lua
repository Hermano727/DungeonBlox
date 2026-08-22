-- Mining Script for Pickaxe (LocalScript)
-- Left-click to mine ore with cracking animation

local tool = script.Parent
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local miningRewardRequest = ReplicatedStorage:WaitForChild("MiningRewardRequest")
local miningDebrisRequest = ReplicatedStorage:WaitForChild("MiningDebrisRequest")
local MiningXPEvent = ReplicatedStorage:WaitForChild("MiningXPEvent")
local SkillXPShared = require(ReplicatedStorage:WaitForChild("SkillXPShared"))

-- Configuration
local MINE_COOLDOWN = 0.5 -- Seconds between mining hits
local CLICKS_TO_MINE = 3 -- Number of clicks to fully mine ore
local MINE_RANGE = 15 -- Maximum range to mine ore
local ORE_RESPAWN_TIME = 10 -- Seconds before ore respawns
local XP_PER_COAL = 5 -- Fallback if server omits amount; server authoritatively grants XP only when coal is granted

-- UI ownership moved to XpHud (React, src/client/XpHud) -- this script no
-- longer touches any GUI instance. addXP only mutates SkillXPShared state
-- and stamps player:SetAttribute("LastMiningXPGain", tick()), which is what
-- XpHud.luau's lastGain() reads to decide which bar is visible/on top.

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

    local player = Players.LocalPlayer
    if player then
        player:SetAttribute("LastMiningXPGain", tick())
    end

    SkillXPShared.Notify()
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

print("Mining script loaded for " .. tool.Name)