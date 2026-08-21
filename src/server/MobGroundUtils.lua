-- MobGroundUtils
-- Ground-snapping / rig-measurement raycast helpers shared by MobClass and
-- its subclasses. Pulled out of MobClass because none of this actually needs
-- AI or combat state -- it only ever reads a Model (and, for the ground
-- probes, an instance to exclude from the raycast) and returns
-- numbers/Vector3s. Kept as free functions rather than a class since there
-- is no per-instance state to carry between calls.

local MobGroundUtils = {}

-- Height from the model's true geometric bottom (feet) up to its
-- PrimaryPart, measured on the model in its current pose (translation does
-- not affect this, so it is safe to call before or after positioning).
function MobGroundUtils.GetFeetToRootHeight(model)
    local primaryPart = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
    if not primaryPart then
        return nil
    end

    local boxCFrame, boxSize = model:GetBoundingBox()
    local bottomY = boxCFrame.Position.Y - (boxSize.Y / 2)
    return primaryPart.Position.Y - bottomY
end

-- Raycast straight down from above `position` to find the nearest surface,
-- then return a position with the model's feet resting exactly on it (a
-- small drop from there is fine -- gravity will settle it the rest of the
-- way once Humanoid.HipHeight is set correctly). Falls back to `position`
-- unchanged if nothing is hit (e.g. a void) or feetToRootHeight is unknown.
function MobGroundUtils.ResolveGroundedSpawnPosition(model, position, feetToRootHeight)
    if not feetToRootHeight then
        return position
    end

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = {model}

    local hit = workspace:Raycast(
        position + Vector3.new(0, 50, 0),
        Vector3.new(0, -150, 0),
        rayParams
    )
    if not hit then
        return position
    end

    return Vector3.new(hit.Position.X, hit.Position.Y + feetToRootHeight, hit.Position.Z)
end

-- Raycast straight down from above (x, z) to find the nearest surface.
-- Falls back to fallbackY (unchanged) if nothing is hit, e.g. a void --
-- never let a momentary missed raycast yank a mob's height around.
-- `excludeInstance` is typically the mob's own Model, so the raycast doesn't
-- hit the mob itself.
function MobGroundUtils.FindGroundY(excludeInstance, x, z, fallbackY)
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = {excludeInstance}

    local hit = workspace:Raycast(
        Vector3.new(x, fallbackY + 10, z),
        Vector3.new(0, -50, 0),
        rayParams
    )
    if hit then
        return hit.Position.Y
    end
    return fallbackY
end

return MobGroundUtils
