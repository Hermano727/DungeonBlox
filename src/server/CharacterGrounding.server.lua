-- Server-owned support height; clients keep Roblox's native Humanoid movement.
local Players = game:GetService("Players")
local Grounding = require(game:GetService("ReplicatedStorage"):WaitForChild("CharacterGrounding"))
local connections = {}
local calibrated = setmetatable({}, { __mode = "k" })

local function configureCharacter(player, character)
    local mesh = character:WaitForChild("Hero_Character", 10)
    local root = character:WaitForChild("HumanoidRootPart", 10)
    local humanoid = character:WaitForChild("Humanoid", 10)
    local head = character:WaitForChild("Head", 10)
    if not mesh or not root or not humanoid or not humanoid:IsA("Humanoid") then return end
    if not head or not head:IsA("BasePart") then return end
    if not mesh:WaitForChild("Root", 10) then return end
    if player.Character ~= character or not character.Parent or calibrated[character] then return end
    if humanoid.RigType ~= Enum.HumanoidRigType.R15 then return end

    local measurement, reason = Grounding.MeasureRig(character)
    if not measurement then
        warn("[CharacterGrounding] " .. character.Name .. ": " .. reason)
        return
    end
    calibrated[character] = true
    humanoid.AutomaticScalingEnabled = false
    humanoid.HipHeight = measurement.HipHeight
    -- Position edits update the existing weld offsets without moving the
    -- connected root (CFrame edits would move the whole welded assembly).
    -- Move the mesh and camera helper together, once, without yielding.
    local offset = root.CFrame.UpVector * measurement.VisualOffsetY
    mesh.Position += offset
    head.Position += offset
    character:SetAttribute("GroundingRootToSole", measurement.RootToSole - measurement.VisualOffsetY)
    character:SetAttribute("GroundingHipHeight", measurement.HipHeight)
    character:SetAttribute("GroundingVisualOffsetY", measurement.VisualOffsetY)
    -- Publish readiness last, so local sampling cannot start on old dimensions.
    character:SetAttribute("GroundingCalibrated", true)
end

local function onPlayerAdded(player)
    if connections[player] then return end
    connections[player] = player.CharacterAdded:Connect(function(character)
        configureCharacter(player, character)
    end)
    if player.Character then task.spawn(configureCharacter, player, player.Character) end
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
    if connections[player] then connections[player]:Disconnect() end
    connections[player] = nil
end)
for _, player in ipairs(Players:GetPlayers()) do onPlayerAdded(player) end
