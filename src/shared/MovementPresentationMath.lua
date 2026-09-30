local Config = require(script.Parent:WaitForChild("MovementPresentationConfig"))
local Motion = {}
function Motion.New()
    return { Forward = 0, Side = 0, Yaw = 0, Burst = 0, Sprinting = false, CameraSide = 0 }
end
function Motion.Step(state, dt, forward, side, grounded, sprinting, crouching, attacking)
    dt = math.max(0, dt)
    forward, side = math.clamp(forward, -1, 1), math.clamp(side, -1, 1)
    local moving = grounded and (math.abs(forward) + math.abs(side) > 0.05)
    sprinting = moving and sprinting and forward > 0.05 and not crouching
    if sprinting and not state.Sprinting then state.Burst = 1 end
    state.Sprinting = sprinting
    if not sprinting then state.Burst = 0 end
    local burst = state.Burst
    state.Burst *= math.exp(-dt * 3 / Config.BurstDuration)
    local scale = moving and (crouching and Config.CrouchScale or 1) or 0
    if attacking then scale = 0 end
    local blend = 1 - math.exp(-Config.BlendSpeed * dt)
    local lean = forward * (forward >= 0 and Config.ForwardLean or Config.BackwardLean)
    local turn = side * Config.StrafeYaw * (forward < -0.1 and -1 or 1)
    state.Forward += ((lean + burst * Config.SprintLean) * scale - state.Forward) * blend
    state.Side += (side * Config.SideLean * scale - state.Side) * blend
    state.Yaw += (turn * scale - state.Yaw) * blend
    state.CameraSide += ((moving and side or 0) - state.CameraSide) * blend
    return state
end
function Motion.LandingStrength(speed)
    return math.clamp((speed - Config.LandingMinSpeed) / (Config.LandingFullSpeed - Config.LandingMinSpeed), 0, 1)
end
return Motion
