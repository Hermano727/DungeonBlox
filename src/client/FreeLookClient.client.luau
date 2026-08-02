local Keys = require(game:GetService("ReplicatedStorage"):WaitForChild("KeybindConfig"))
--[[
	FreeLookClient
	Hold Left or Right Ctrl to release the cursor from first-person lock.
	Camera stops rotating (FirstPersonViewModel checks MouseBehavior each frame).
	Release Ctrl to snap back to locked / camera-controlled mode.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local CursorManager = require(ReplicatedStorage:WaitForChild("CursorManager"))

local CTRL_KEYS = {
	[Keys.FreeLook[1]] = true,
	[Keys.FreeLook[2]] = true,
}
local held = {}

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if CTRL_KEYS[input.KeyCode] then
		held[input.KeyCode] = true
		CursorManager.setFree("freelook", true)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if CTRL_KEYS[input.KeyCode] then
		held[input.KeyCode] = nil
		if not next(held) then
			CursorManager.setFree("freelook", false)
		end
	end
end)
