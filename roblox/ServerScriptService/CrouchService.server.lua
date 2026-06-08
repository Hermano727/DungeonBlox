--[[
    CrouchService
    Handles server-side crouch state: WalkSpeed and sprint blocking.
    Toggle with C key (client fires RequestCrouch).

    Rules:
      - Crouching reduces WalkSpeed to CROUCH_SPEED (7)
      - Sprint is blocked while crouching (client guards first, server enforces)
      - Attacking is allowed while crouching
      - LOW_ENERGY lockout does not prevent crouching
      - DEAD state prevents crouching
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config     = require(ReplicatedStorage:WaitForChild("EnergyConfig"))
local EnergyEvts = ReplicatedStorage:WaitForChild("EnergyEvents")

-- Create the RemoteEvent
local RequestCrouch = Instance.new("RemoteEvent")
RequestCrouch.Name   = "RequestCrouch"
RequestCrouch.Parent = EnergyEvts

-- Per-player state
local isCrouching = {}   -- [userId] = bool

local function getHumanoid(player)
    local char = player.Character
    return char and char:FindFirstChildOfClass("Humanoid")
end

local function setSpeed(player, speed)
    local hum = getHumanoid(player)
    if hum and hum.Health > 0 then
        hum.WalkSpeed = speed
    end
end

RequestCrouch.OnServerEvent:Connect(function(player, wantCrouch)
    if type(wantCrouch) ~= "boolean" then return end

    local hum = getHumanoid(player)
    if not hum or hum.Health <= 0 then return end  -- dead, ignore

    local userId = player.UserId

    if wantCrouch then
        -- Block: don't crouch if already crouching
        if isCrouching[userId] then return end
        isCrouching[userId] = true
        setSpeed(player, Config.CROUCH_SPEED)
        print("[CrouchService] " .. player.Name .. " crouched")
    else
        if not isCrouching[userId] then return end
        isCrouching[userId] = false
        setSpeed(player, Config.NORMAL_SPEED)
        print("[CrouchService] " .. player.Name .. " stood up")
    end
end)

-- Also listen to RequestSprint: if player sprints while crouching, stand them up
local RequestSprint = EnergyEvts:WaitForChild("RequestSprint", 5)
if RequestSprint then
    RequestSprint.OnServerEvent:Connect(function(player, isHeld)
        if isHeld and isCrouching[player.UserId] then
            -- Sprint cancels crouch server-side
            isCrouching[player.UserId] = false
            -- Speed will be set by EnergyServer's sprint handler
        end
    end)
end

-- Clean up on leave
Players.PlayerRemoving:Connect(function(player)
    isCrouching[player.UserId] = nil
end)

-- Reset crouch on character respawn
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function()
        isCrouching[player.UserId] = nil
    end)
end)
for _, player in ipairs(Players:GetPlayers()) do
    player.CharacterAdded:Connect(function()
        isCrouching[player.UserId] = nil
    end)
end

print("[CrouchService] ready")
