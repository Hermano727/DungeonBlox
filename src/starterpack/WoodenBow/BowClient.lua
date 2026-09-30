local Players = game:GetService("Players")

local tool = script.Parent
local player = Players.LocalPlayer
local bowFire = tool:WaitForChild("BowFire")

local AimRay = require(game:GetService("ReplicatedStorage"):WaitForChild("AimRay"))

local function getAimPosition()
    local camera = workspace.CurrentCamera
    if not camera then
        return tool.Handle.Position + tool.Handle.CFrame.LookVector * 100
    end

    local mouse = player:GetMouse()
    local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)
    -- Front view: the camera looks back at the player; shoot where the character faces.
    local frontOrigin, frontDirection = AimRay.FrontView()
    if frontOrigin then ray = Ray.new(frontOrigin, frontDirection) end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude

    local character = player.Character
    if character then
        params.FilterDescendantsInstances = {character, tool}
    else
        params.FilterDescendantsInstances = {tool}
    end

    local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
    if result then
        return result.Position
    end

    return ray.Origin + ray.Direction * 1000
end

tool.Activated:Connect(function()
    if not tool.Enabled then
        return
    end

    if player:GetAttribute("EnergyPanting") == true then
        return
    end

    bowFire:FireServer(getAimPosition())
end)
