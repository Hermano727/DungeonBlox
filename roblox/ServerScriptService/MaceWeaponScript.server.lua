local Players = game:GetService("Players")

-- Configuration
local DAMAGE = 25
local COOLDOWN = 0.8 -- seconds between attacks
local HIT_RANGE = 4 -- studs

-- Track cooldowns for each player
local cooldowns = {}

-- Function to handle mace hit detection
local function onMaceActivated(player, maceHead)
    -- Check cooldown
    if cooldowns[player] and tick() - cooldowns[player] < COOLDOWN then
        return
    end
    cooldowns[player] = tick()

    -- Get player's character
    local character = player.Character
    if not character then return end

    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then return end

    -- Find all nearby characters and check for hits
    for _, otherPlayer in ipairs(Players:GetPlayers()) do
        if otherPlayer ~= player then
            local otherCharacter = otherPlayer.Character
            if otherCharacter then
                local otherHumanoid = otherCharacter:FindFirstChildOfClass("Humanoid")
                local otherRootPart = otherCharacter:FindFirstChild("HumanoidRootPart")

                if otherHumanoid and otherRootPart and otherHumanoid.Health > 0 then
                    -- Check distance
                    local distance = (humanoidRootPart.Position - otherRootPart.Position).Magnitude
                    if distance <= HIT_RANGE then
                        -- Apply damage
                        otherHumanoid:TakeDamage(DAMAGE)

                        -- Visual feedback (optional)
                        print(player.Name .. " hit " .. otherPlayer.Name .. " with mace for " .. DAMAGE .. " damage")
                    end
                end
            end
        end
    end
end

-- Function to set up mace tool
local function setupMaceTool(tool)
    local maceHead = tool:FindFirstChild("MaceHead")
    if not maceHead then
        warn("MaceHead not found in tool")
        return
    end

    -- Connect to tool activation
    tool.Activated:Connect(function()
        local player = Players:GetPlayerFromCharacter(tool.Parent)
        if player then
            onMaceActivated(player, maceHead)
        end
    end)

    -- Add touch detection for more precise hits
    maceHead.Touched:Connect(function(otherPart)
        local player = Players:GetPlayerFromCharacter(tool.Parent)
        if not player then return end

        -- Check cooldown
        if cooldowns[player] and tick() - cooldowns[player] < COOLDOWN then
            return
        end
        cooldowns[player] = tick()

        -- Find the character that was touched
        local character = otherPart.Parent
        if not character then return end

        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.Health > 0 then
            -- Don't damage the player wielding the mace
            local hitPlayer = Players:GetPlayerFromCharacter(character)
            if hitPlayer == player then return end

            -- Apply damage
            humanoid:TakeDamage(DAMAGE)
            print(player.Name .. " hit " .. (hitPlayer and hitPlayer.Name or "NPC") .. " with mace for " .. DAMAGE .. " damage")
        end
    end)
end

-- Handle existing tools in StarterPack
for _, tool in ipairs(game:GetService("StarterPack"):GetChildren()) do
    if tool.Name == "Mace" then
        setupMaceTool(tool)
    end
end

-- Handle tools added later
game:GetService("StarterPack").ChildAdded:Connect(function(child)
    if child:IsA("Tool") and child.Name == "Mace" then
        setupMaceTool(child)
    end
end)

-- Handle when players equip the mace
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(character)
        -- Wait for the tool to be equipped
        local function onChildAdded(child)
            if child:IsA("Tool") and child.Name == "Mace" then
                setupMaceTool(child)
            end
        end
        character.ChildAdded:Connect(onChildAdded)
    end)
end)

-- Handle players already in the game
for _, player in ipairs(Players:GetPlayers()) do
    if player.Character then
        player.Character.ChildAdded:Connect(function(child)
            if child:IsA("Tool") and child.Name == "Mace" then
                setupMaceTool(child)
            end
        end)
    end
end

print("Mace weapon script loaded successfully")
