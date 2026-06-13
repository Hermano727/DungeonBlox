local parent = script.Parent
local Handle = parent:WaitForChild("Handle")
local Creator = parent:WaitForChild("Creator")
CanDmg = false
Can = true
parent.Equipped:Connect(function()
	Handle.Equip:Play()
	if Creator.Value == nil then
	Creator.Value = parent.Parent end
end)
parent.Unequipped:Connect(function()
	Handle.UnEquip:Play()
end)
repeat wait() until Creator.Value ~= nil
parent.Activated:Connect(function()
	if Handle.Transparency == 1 then return end
	function slash()
		print("hip")
		local creator = Creator.Value
		local Animations = parent:WaitForChild("Animations")
		local AnimChild = Animations:GetChildren()
		local AnimRad = math.random(1,#AnimChild)
		local AnimSel = AnimChild[AnimRad]
		local AP = creator:WaitForChild("Humanoid"):LoadAnimation(AnimSel)
		if Can == true then
		Can = false
		AP:Play()
		wait(0.15)
		CanDmg = true
		Handle.Swing:Play()
		Handle.SlashTrail.Enabled = true
		wait(0.25)
		CanDmg = false
		Handle.SlashTrail.Enabled = false
		wait(0.06)
		Can = true
		end
	end
	slash()
end)
function on(t)
	local h = t.Parent:FindFirstChildOfClass("Humanoid")
	if h ~= nil and CanDmg == true then
		CanDmg = false
		local cre = Creator.Value
		h:TakeDamage(parent.Dmg.Value)
		Handle.Swing:Stop()
		Handle.Hit:Play()
		if h.Health>0 then
		if not h:FindFirstChild("creator") then
	        local ov = Instance.new("ObjectValue",h)
	        ov.Name = "creator"
	        ov.Value = game.Players:WaitForChild(cre.Name)
	        else
			local ovs = h:GetChildren()
			for i = 1,#ovs do
			if (ovs[i].Name == "creator") then
	        ovs[i].Value = game.Players:WaitForChild(cre.Name) end
			end
			end
		end
	end
end
Handle.Touched:Connect(on)