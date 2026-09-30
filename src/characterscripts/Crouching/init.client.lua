-- Input only: server owns crouch state/speed; Animate2 owns the pose.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local character = script.Parent
local root = character:WaitForChild("HumanoidRootPart")
local humanoid = character:WaitForChild("Humanoid")
local request = RS:WaitForChild("EnergyEvents"):WaitForChild("RequestCrouch")
local Profiles = require(RS:WaitForChild("CharacterAnimProfiles"))
local CombatConfig = require(RS:WaitForChild("CombatAnimConfig"))
local connections = {}
local lastRequest = 0
local assetsReady = false
if Profiles.CrouchReady() and CombatConfig.CROUCH_SWING_ANIM_ID ~= "" then
    task.spawn(function()
        local animations = {}
        for _, profile in pairs(Profiles.Profiles) do
            for _, key in ipairs({"CrouchIdle", "CrouchWalk"}) do
                if profile[key] and profile[key] ~= "" then
                    local animation = Instance.new("Animation")
                    animation.AnimationId = profile[key]
                    table.insert(animations, animation)
                end
            end
        end
        local swing = Instance.new("Animation")
        swing.AnimationId = CombatConfig.CROUCH_SWING_ANIM_ID
        table.insert(animations, swing)
        local allLoaded = true
        local ok = pcall(function()
            game:GetService("ContentProvider"):PreloadAsync(animations, function(_, status)
                if status ~= Enum.AssetFetchStatus.Success then allLoaded = false end
            end)
        end)
        for _, animation in ipairs(animations) do animation:Destroy() end
        assetsReady = ok and allLoaded
        if not assetsReady then warn("[Crouching] Crouch assets unavailable; retaining standing movement") end
    end)
end
local function syncJump()
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, root:GetAttribute("IsCrouching") ~= true)
end
connections[1] = root:GetAttributeChangedSignal("IsCrouching"):Connect(syncJump)
connections[2] = UIS.InputBegan:Connect(function(input, processed)
    if processed or UIS:GetFocusedTextBox() or Players.LocalPlayer.Character ~= character then return end
    if input.KeyCode ~= Enum.KeyCode.C or os.clock()-lastRequest < 0.1 then return end
    if not Profiles.CrouchReady() or CombatConfig.CROUCH_SWING_ANIM_ID == "" then
        warn("[Crouching] Waiting for published crouch animation IDs")
        return
    end
    if not assetsReady then return end
    lastRequest = os.clock()
    request:FireServer(root:GetAttribute("IsCrouching") ~= true)
end)
syncJump()
script.Destroying:Connect(function()
    for _, connection in ipairs(connections) do connection:Disconnect() end
end)
