script.Parent.Equipped:Connect(function(Mouse)
	Mouse.Button1Down:Connect(function()
		local Animation = game.Players.LocalPlayer.Character.Humanoid:LoadAnimation(script.Parent.Animation)
		Animation:Play()
		script.Disabled = true
		wait (1.5)
		script.Disabled = false
	end)
end)

