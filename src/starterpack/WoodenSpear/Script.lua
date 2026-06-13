local tool = script.Parent

local canDamage = false

local function onTouch(otherPart)
	local humanoid = otherPart.Parent:FindFirstChild("Humanoid")
	if not humanoid then
		return
	end
	if humanoid.Parent ~= tool.Parent and canDamage then
		humanoid:TakeDamage(5)
	else
		return
	end
	canDamage = false
end

local function slash()
	local str = Instance.new("StringValue")
	str.Name = "toolanim"
	str.Value = "Slash"
	str.Parent = tool
	canDamage = true
end

tool.Activated:Connect(slash)
tool.Handle.Touched:Connect(onTouch)