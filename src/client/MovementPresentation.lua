-- One additive bone layer per client, including observed remote characters.
-- Also the out-of-breath pose (2026-10-04): while a player's replicated EnergyPanting attribute
-- is set (EnergyServer, energy hit 0), their back hunches a little and the chest heaves with
-- each breath, so everyone around can see they're spent. PantingEffects adds the drain, breath and sound.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("MovementPresentationConfig"))
local Motion = require(RS:WaitForChild("MovementPresentationMath"))
local Grounding = require(RS:WaitForChild("CharacterGrounding"))
local GroundState = require(script.Parent:WaitForChild("CharacterGroundState"))
local states = {}
local Presentation = {}
local connections = {}
local function connect(signal, fn)
    table.insert(connections, signal:Connect(fn))
end
local roles = {"Pelvis", "Spine_01", "Spine_02", "Neck", "Thigh_L", "Thigh_R"}
local PANT_HUNCH = math.rad(9) -- forward bend of the back while spent
local PANT_HEAVE = math.rad(3) -- chest rise and fall per breath
local PANT_RATE = 1.6 -- breaths per second
local PANT_BLEND = 4 -- how fast the pose comes and goes

local function restore(state)
    for bone, base in pairs(state.base) do
        if bone.Parent then bone.Transform = base end
    end
    table.clear(state.base)
end
local function resolve(character)
    local root = character:FindFirstChild("HumanoidRootPart")
    local mesh = character:FindFirstChild("Hero_Character")
    local hum = character:FindFirstChildOfClass("Humanoid")
    local animator = hum and hum:FindFirstChildOfClass("Animator")
    if not root or not mesh or not animator then return nil end
    local bones = {}
    for _, name in ipairs(roles) do
        local bone = mesh:FindFirstChild(name, true)
        if not bone or not bone:IsA("Bone") then return nil end
        bones[name] = bone
    end
    return {root=root, hum=hum, animator=animator, bones=bones, base={},
        motion=Motion.New(), params=Grounding.NewRaycastParams(character),
        player=Players:GetPlayerFromCharacter(character), pant=0}
end
local function eligible(character, state)
    local own = Players.LocalPlayer.Character
    local origin = own and own:FindFirstChild("HumanoidRootPart")
    return character.Parent and state.root.Parent and state.hum.Health > 0 and origin
        and (origin.Position-state.root.Position).Magnitude <= Config.Range
end
local elapsed = 0
connect(RunService.Heartbeat, function(dt)
    elapsed += dt
    if elapsed < Grounding.SampleInterval then return end
    elapsed %= Grounding.SampleInterval
    local present = {}
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        if character then
            present[character] = true
            local state = states[character]
            if not state and character:GetAttribute("GroundingCalibrated") then
                state = resolve(character)
                states[character] = state
            end
            if state and eligible(character, state) then
                if player == Players.LocalPlayer then
                    local sample = GroundState.GetState()
                    state.ground = sample and sample.Character == character and sample or nil
                else
                    state.ground = Grounding.Sample(character, state.hum, state.root, state.params)
                end
            end
        end
    end
    for character, state in pairs(states) do
        if not present[character] then restore(state); states[character] = nil end
    end
end)

connect(RunService.PreAnimation, function()
    -- Restore the prior animation pose before Animator writes its next pose.
    -- This also prevents accumulation when Animator skips an evaluation.
    for _, state in pairs(states) do restore(state) end
end)
connect(RunService.PreSimulation, function(dt)
    for character, state in pairs(states) do
        restore(state) -- also safe if several simulation steps run per animation step
        if not eligible(character, state) then
            restore(state)
            state.motion = Motion.New()
            state.ground = nil
            continue
        end
        local ground = state.ground
        local velocity = state.root.AssemblyLinearVelocity - (ground and ground.SurfaceVelocity or Vector3.zero)
        local localVelocity = state.root.CFrame:VectorToObjectSpace(velocity)
        local speed = math.max(1, state.hum.WalkSpeed)
        local attacking = false
        for _, track in ipairs(state.animator:GetPlayingAnimationTracks()) do
            if track.Priority.Value >= Enum.AnimationPriority.Action.Value and track.WeightCurrent > 0.01 then
                attacking = true; break
            end
        end
        local m = Motion.Step(state.motion, dt, -localVelocity.Z/speed, localVelocity.X/speed,
            ground and ground.Grounded == true, character:GetAttribute("IsSprinting") == true,
            state.root:GetAttribute("IsCrouching") == true, attacking)
        -- Out of breath: blend the hunch in and out, and breathe on top of it.
        local spent = state.player ~= nil and state.player:GetAttribute("EnergyPanting") == true
        state.pant += ((spent and 1 or 0) - state.pant) * (1 - math.exp(-PANT_BLEND * dt))
        local breath = math.sin(os.clock() * math.pi * 2 * PANT_RATE)
        local hunch = PANT_HUNCH * state.pant
        local heave = PANT_HEAVE * breath * state.pant
        local rotations = {
            Pelvis = CFrame.Angles(0, -m.Yaw*0.35, 0),
            Spine_01 = CFrame.Angles(-m.Forward*0.5 - hunch*0.6, -m.Yaw*0.325, -m.Side*0.5),
            Spine_02 = CFrame.Angles(-m.Forward*0.5 - hunch*0.4 - heave, -m.Yaw*0.325, -m.Side*0.5),
            Neck = CFrame.Angles(m.Forward + hunch*0.5 + heave*0.5, m.Yaw, m.Side),
            Thigh_L = CFrame.Angles(0, m.Yaw*0.35, 0),
            Thigh_R = CFrame.Angles(0, m.Yaw*0.35, 0),
        }
        -- Parent-first order. Convert character-space offsets using the current
        -- animated orientation, preserving each bone's authored translation.
        for _, role in ipairs(roles) do
            local bone = state.bones[role]
            local base = bone.Transform
            state.base[bone] = base
            local basis = state.root.CFrame.Rotation:Inverse() * bone.TransformedWorldCFrame.Rotation
            bone.Transform = base * basis:Inverse() * rotations[role] * basis
        end
    end
end)
function Presentation.GetLocalMotion()
    local state = states[Players.LocalPlayer.Character]
    return state and state.motion
end
script.Destroying:Connect(function()
    for _, connection in ipairs(connections) do connection:Disconnect() end
    for _, state in pairs(states) do restore(state) end
end)
return Presentation
