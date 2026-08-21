local anim = Instance.new("Animation") anim.AnimationId = "rbxassetid://98772997953918"
local playAnim = script.Parent.Humanoid:LoadAnimation(anim)

script.Parent.Humanoid.StateChanged:Connect(function(_,state)
	if state == Enum.HumanoidStateType.Landed then
		playAnim:Play()
		wait(1)
		playAnim:Stop()
	end

end)
