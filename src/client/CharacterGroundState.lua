-- One local ground-state owner. Effects subscribe here instead of raycasting
-- separately or writing character/camera transforms from their own loops.
local RunService = game:GetService("RunService")
local Grounding = require(game:GetService("ReplicatedStorage"):WaitForChild("CharacterGrounding"))
local changedEvent = Instance.new("BindableEvent")
local landedEvent = Instance.new("BindableEvent")
local GroundState = {
    GroundedChanged = changedEvent.Event, -- (grounded: boolean, snapshot or nil on detach)
    Landed = landedEvent.Event, -- (approachSpeed: number, snapshot)
}
local connection, currentCharacter, snapshot = nil, nil, nil

function GroundState.GetState()
    return snapshot -- frozen; nil until the server has calibrated a character
end

function GroundState.Stop()
    if connection then connection:Disconnect(); connection = nil end
    local wasGrounded = snapshot and snapshot.Grounded
    currentCharacter, snapshot = nil, nil
    if wasGrounded then changedEvent:Fire(false, nil) end
end

function GroundState.Start(character)
    if currentCharacter == character then return end
    GroundState.Stop()
    currentCharacter = character
    local params = Grounding.NewRaycastParams(character)
    local tracker = Grounding.NewTracker()
    local elapsed = 0
    connection = RunService.Heartbeat:Connect(function(dt)
        if not character.Parent then GroundState.Stop(); return end
        elapsed += dt
        if elapsed < Grounding.SampleInterval then return end
        elapsed %= Grounding.SampleInterval -- one sample, never catch-up raycast bursts
        if character:GetAttribute("GroundingCalibrated") ~= true then return end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        local root = character:FindFirstChild("HumanoidRootPart")
        if not humanoid or not root then return end
        snapshot = Grounding.Sample(character, humanoid, root, params)
        local changed, impactSpeed = tracker:Update(snapshot)
        if changed then changedEvent:Fire(snapshot.Grounded, snapshot) end
        if impactSpeed ~= nil then landedEvent:Fire(impactSpeed, snapshot) end
    end)
end

return GroundState
