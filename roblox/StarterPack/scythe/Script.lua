local Tool = script.Parent
local MyRoot

--Variables
local Event
local state = nil
local idleAnim1
local idleAnim2

-- Animations
local idle = Tool.Handle.Idle
local walk = Tool.Handle.IdleMoving

Tool.Equipped:Connect(function()
	MyRoot = Tool.Parent:FindFirstChild('HumanoidRootPart')
	local humanoid = Tool.Parent:FindFirstChildWhichIsA('Humanoid')
	if humanoid then
		idleAnim1 = humanoid:LoadAnimation(idle)
		idleAnim1:Play()

		--// Check for movement
		Event = humanoid:GetPropertyChangedSignal("MoveDirection"):Connect(function()

			local magnitude = humanoid.MoveDirection.Magnitude

			if magnitude <= 0.1 and state ~= "idle" then
				state = "idle"
				idleAnim1 = humanoid:LoadAnimation(idle)
				idleAnim1:Play()

				if idleAnim2 then
					idleAnim2:Stop()
				end
			elseif state ~= "other" then
				state = "other"
				idleAnim2 = humanoid:LoadAnimation(walk)
				idleAnim2:Play()

				if idleAnim1 then
					idleAnim1:Stop()
				end
			end

		end)
	else
		print('no humanoid')
	end
end)


Tool.Unequipped:Connect(function()
	Event:Disconnect()
	if idleAnim1 then idleAnim1:Stop() end
	if idleAnim2 then idleAnim2:Stop() end
end)