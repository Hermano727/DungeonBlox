-- Rig calibration and ground observations. Never moves the character or bones.
local Grounding = {}
Grounding.SampleInterval = 1 / 20
local CONTACT_TOLERANCE = 0.35
-- The fixed Hero rig previously walked with this clearance. Zero lets the
-- root collider rest on terrain while the Humanoid can remain in Freefall.
local MINIMUM_HIP_HEIGHT = 1
local State = Enum.HumanoidStateType

function Grounding.MeasureRig(character)
    local root = character:FindFirstChild("HumanoidRootPart")
    local mesh = character:FindFirstChild("Hero_Character")
    local bone = mesh and mesh:FindFirstChild("Root")
    if not root or not root:IsA("BasePart") or not mesh or not mesh:IsA("MeshPart")
        or not bone or not bone:IsA("Bone") then
        return nil, "unsupported or incomplete skinned rig"
    end

    -- Only the body mesh's undeformed bounds count. Equipment, accessories,
    -- animation poses, and the character's world rotation cannot change this.
    local relative = root.CFrame:ToObjectSpace(mesh.CFrame)
    local half = mesh.Size * 0.5
    local extent = math.abs(relative.RightVector.Y) * half.X
        + math.abs(relative.UpVector.Y) * half.Y + math.abs(relative.LookVector.Y) * half.Z
    local rootToSole = extent - relative.Position.Y
    local hipHeight = rootToSole - root.Size.Y * 0.5
    if hipHeight < -0.001 then
        return nil, "root collider extends below the body soles; adjust the rig geometry"
    end
    local supportHipHeight = math.max(MINIMUM_HIP_HEIGHT, hipHeight)
    return table.freeze({
        RootToSole = rootToSole,
        HipHeight = supportHipHeight,
        -- Align the visuals to the native support plane, not vice versa.
        VisualOffsetY = hipHeight - supportHipHeight,
    })
end

function Grounding.NewRaycastParams(character)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = { character }
    params.RespectCanCollide = true
    params.IgnoreWater = true
    return params
end

function Grounding.Sample(character, humanoid, root, params)
    params.CollisionGroup = root.CollisionGroup
    local clearance = root.Size.Y * 0.5 + math.max(0, humanoid.HipHeight)
    local hit = workspace:Raycast(root.Position, Vector3.new(0, -clearance - CONTACT_TOLERANCE, 0), params)
    local surfaceVelocity = Vector3.zero
    if hit and not hit.Instance:IsA("Terrain") and hit.Instance:IsA("BasePart") then
        surfaceVelocity = hit.Instance:GetVelocityAtPosition(hit.Position)
    end
    local state = humanoid:GetState()
    local supportingState = state == State.Running or state == State.RunningNoPhysics or state == State.Landed
    local grounded = humanoid.Health > 0 and not humanoid.Sit and not humanoid.PlatformStand
        and supportingState and humanoid.FloorMaterial ~= Enum.Material.Air and hit ~= nil
        and hit.Normal.Y > 0
    return table.freeze({
        Character = character,
        Grounded = grounded,
        Position = hit and hit.Position or nil,
        Normal = hit and hit.Normal or nil,
        Material = hit and hit.Material or Enum.Material.Air,
        Instance = hit and hit.Instance or nil,
        Distance = hit and hit.Distance or nil,
        SurfaceVelocity = surfaceVelocity,
        Velocity = root.AssemblyLinearVelocity,
        RelativeVelocity = root.AssemblyLinearVelocity - surfaceVelocity,
        HumanoidState = state,
        LandingSuppressed = humanoid.Health <= 0 or humanoid.Sit or humanoid.PlatformStand
            or not (supportingState or state == State.Jumping or state == State.Freefall),
    })
end

-- Pure transition tracker, also usable by future non-camera consumers.
-- A landing requires a known grounded sample followed by observed air time.
function Grounding.NewTracker()
    local previousGrounded = nil
    local armed = false
    local airVelocity = nil
    return {
        Update = function(_, sample)
            local changed = previousGrounded ~= nil and previousGrounded ~= sample.Grounded
            previousGrounded = sample.Grounded
            local impactSpeed = nil
            if sample.LandingSuppressed then
                armed, airVelocity = false, nil
            elseif sample.Grounded then
                if armed and airVelocity then
                    impactSpeed = math.max(0, -(airVelocity - sample.SurfaceVelocity):Dot(sample.Normal))
                end
                armed, airVelocity = true, nil
            elseif armed and (sample.HumanoidState == State.Jumping or sample.HumanoidState == State.Freefall) then
                airVelocity = sample.Velocity
            end
            return changed, impactSpeed
        end,
    }
end

return Grounding
