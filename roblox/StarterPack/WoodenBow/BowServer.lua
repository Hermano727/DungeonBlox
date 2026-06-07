local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local tool = script.Parent
local handle = tool:WaitForChild("Handle")
local bowFire = tool:WaitForChild("BowFire")

local MobCombat = require(ServerScriptService:WaitForChild("MobCombat"))
local WeaponData = require(ReplicatedStorage:WaitForChild("WeaponData"))
local EnergyData = require(ServerScriptService:WaitForChild("EnergyData"))

local WEAPON_ID = "WoodenBow"

local function getMobUID(part)
    local model = part:FindFirstAncestorOfClass("Model")
    if model then
        return model:GetAttribute("MobUID")
    end
    return nil
end

-- Returns the Player whose character the arrow hit, or nil. Used to route the
-- arrow into the PvP damage path (alignment-gated server-side).
local function getHitPlayer(part)
    local model = part:FindFirstAncestorOfClass("Model")
    if not model then return nil end
    return Players:GetPlayerFromCharacter(model)
end

local function fireArrow(shooter, aimPosition)
    local stats = WeaponData.GetStats(WEAPON_ID)
    local spawnPosition = (handle.CFrame * CFrame.new(0, 0, -3)).Position
    local direction = aimPosition - spawnPosition
    if direction.Magnitude < 0.1 then
        return
    end

    direction = direction.Unit

    local arrow = Instance.new("Part")
    arrow.Name = "Arrow"
    arrow.Size = Vector3.new(0.25, 0.25, 2)
    arrow.Material = Enum.Material.Wood
    arrow.Color = Color3.fromRGB(139, 90, 43)
    arrow.CanCollide = false
    arrow.CanTouch = false
    arrow.CanQuery = false
    arrow.Anchored = true
    arrow.CFrame = CFrame.lookAt(spawnPosition, spawnPosition + direction)
    arrow.Parent = workspace
    Debris:AddItem(arrow, 5)

    local speed = stats.ProjectileSpeed or 150
    local maxDistance = stats.MaxRange or 100
    local traveled = 0
    local position = spawnPosition

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude

    local ignore = {arrow, tool}
    local character = shooter.Character
    if character then
        table.insert(ignore, character)
    end
    rayParams.FilterDescendantsInstances = ignore

    local connection
    connection = RunService.Heartbeat:Connect(function(dt)
        if not arrow.Parent then
            connection:Disconnect()
            return
        end

        local step = speed * dt
        if traveled + step > maxDistance then
            step = maxDistance - traveled
        end

        local displacement = direction * step
        local result = workspace:Raycast(position, displacement, rayParams)
        if result then
            local mobUID = getMobUID(result.Instance)
            if mobUID then
                MobCombat.ApplyWeaponDamage(shooter, mobUID, WEAPON_ID, result.Position)
            else
                local hitPlayer = getHitPlayer(result.Instance)
                if hitPlayer and hitPlayer ~= shooter then
                    -- PvP gate (alignment / same-player / distance) is enforced
                    -- inside ApplyPvPDamage. Arrow consumes on any solid hit
                    -- regardless — a Lawful target still stops the arrow, it
                    -- just takes no damage.
                    MobCombat.ApplyPvPDamage(shooter, hitPlayer, WEAPON_ID, result.Position)
                end
            end

            arrow:Destroy()
            connection:Disconnect()
            return
        end

        traveled += step
        position += displacement
        arrow.CFrame = CFrame.lookAt(position, position + direction)

        if traveled >= maxDistance then
            arrow:Destroy()
            connection:Disconnect()
        end
    end)
end

bowFire.OnServerEvent:Connect(function(player, aimPosition)
    if typeof(aimPosition) ~= "Vector3" then
        return
    end

    if not tool.Enabled then
        return
    end

    local owner = Players:GetPlayerFromCharacter(tool.Parent)
    if owner ~= player then
        return
    end

    if EnergyData.isPanting(player) then
        return
    end

    tool.Enabled = false
    fireArrow(player, aimPosition)

    local cooldownValue = tool:FindFirstChild("Cooldown")
    local cooldown = cooldownValue and cooldownValue.Value or WeaponData.GetStats(WEAPON_ID).Cooldown or 0.5
    task.wait(cooldown)
    tool.Enabled = true
end)
