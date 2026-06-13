--!strict
-- simplified speed coil by s_snaker

local BOOST = 150

local tool = script.Parent
local sound = tool.Handle.CoilSound
local oldSpeed -- speed before equipping is saved in functions
local humanoid -- has to be a global so it can be used in onUnequip()

function onEquip()
	humanoid = tool.Parent:FindFirstChild("Humanoid")
	if (humanoid ~= nil) then
		oldSpeed = humanoid.WalkSpeed
		humanoid.WalkSpeed = oldSpeed + BOOST
		sound:play()
	end
end

function onUnequip()
	humanoid.WalkSpeed = oldSpeed
end

tool.Equipped:Connect(onEquip)
tool.Unequipped:Connect(onUnequip)