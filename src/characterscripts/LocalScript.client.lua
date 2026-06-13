local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local player   = Players.LocalPlayer
local char     = player.Character or player.CharacterAdded:Wait()
local humanoid = char:WaitForChild("Humanoid")

local WeaponData    = require(ReplicatedStorage:WaitForChild("WeaponData"))
local SWING_ANIM_ID = "rbxassetid://98847827358249"

-- Stamp SwingAnimId on any melee weapon tool so CombatClient uses this animation.
-- WeaponData.ShouldUseClientHitDetection returns true for AttackType == "Melee",
-- covering every sword/axe/scythe/mace entry in the weapon table.
local function stampMeleeAnim(tool)
	local weaponId = WeaponData.GetWeaponIdFromTool(tool)
	if weaponId and WeaponData.ShouldUseClientHitDetection(weaponId) then
		tool:SetAttribute("SwingAnimId", SWING_ANIM_ID)
	end
end

for _, child in ipairs(char:GetChildren()) do
	if child:IsA("Tool") then
		stampMeleeAnim(child)
	end
end

char.ChildAdded:Connect(function(child)
	if child:IsA("Tool") then
		stampMeleeAnim(child)
	end
end)

humanoid.CameraOffset = Vector3.new(0, 0, -1)

for _, v in pairs(char:GetChildren()) do
	if v:IsA("BasePart") and v.Name ~= "Head" then
		v:GetPropertyChangedSignal("LocalTransparencyModifier"):Connect(function()
			v.LocalTransparencyModifier = v.Transparency
		end)
		v.LocalTransparencyModifier = v.Transparency
	end
end

local raycastParams = RaycastParams.new()
raycastParams.FilterDescendantsInstances = char:GetChildren()
raycastParams.FilterType                 = Enum.RaycastFilterType.Exclude

RunService.RenderStepped:Connect(function()
	local head = char:FindFirstChild("Head")
	if not head then return end
	local result = workspace:Raycast(head.Position, head.CFrame.LookVector, raycastParams)
	if result then
		humanoid.CameraOffset = Vector3.new(0, 0, -(head.Position - result.Position).Magnitude)
	else
		humanoid.CameraOffset = Vector3.new(0, 0, -1)
	end
end)