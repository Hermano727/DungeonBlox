local Keys = require(game:GetService("ReplicatedStorage"):WaitForChild("KeybindConfig"))
--[[
	FreeLookClient
	Hold Keys.FreeLook (Left or Right Ctrl by default; rebindable on Settings > Controls) to
	release the cursor from first-person lock.
	Camera stops rotating (FirstPersonViewModel checks MouseBehavior each frame).
	Release Ctrl to snap back to locked / camera-controlled mode.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local CursorManager = require(ReplicatedStorage:WaitForChild("CursorManager"))

local held = {}

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if Keys.Matches(Keys.FreeLook, input.KeyCode) then
		held[input.KeyCode] = true
		CursorManager.setFree("freelook", true)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if held[input.KeyCode] then -- whatever was held (even if rebound meanwhile) lets go
		held[input.KeyCode] = nil
		if not next(held) then
			CursorManager.setFree("freelook", false)
		end
	end
end)
