-- Presentation only. Never changes support height, collisions, or movement speed.
return table.freeze({
    Range = 120,
    BlendSpeed = 12,
    ForwardLean = math.rad(6), BackwardLean = math.rad(3), SideLean = math.rad(4),
    StrafeYaw = math.rad(20), SprintLean = math.rad(3), BurstDuration = 0.3,
    CrouchScale = 0.35,
    CameraRoll = math.rad(1.5), CameraSprintPitch = math.rad(1),
    LandingDip = 0.06, LandingPitch = math.rad(1), LandingFullSpeed = 35,
    LandingMinSpeed = 5, LandingDecay = 14,
    CrouchCameraY = -0.8, CrouchBlendSpeed = 16,
    CrouchFreefallTime = 0.35,
})
