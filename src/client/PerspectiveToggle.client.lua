--!strict
--[[
	PerspectiveToggle -- SUPERSEDED, left Disabled.

	This used to be the active R-toggle: flip Player.CameraMode between
	stock Classic and LockFirstPerson, specifically to avoid fighting the
	movement system the way FirstPersonViewModel.client.lua's custom
	Scriptable camera once did. The trade-off cost two things players
	noticed: Ctrl-freelook couldn't actually free the cursor while in true
	first person (Roblox's stock LockFirstPerson camera re-locks
	MouseBehavior itself every frame, fighting CursorManager), and third
	person was Classic's free-scroll instead of a fixed Minecraft-style
	over-the-shoulder distance.

	Re-tested and confirmed FirstPersonViewModel's custom camera no longer
	fights movement -- see FirstPersonViewModel.client.lua, now the active
	system again. This script is disabled and kept only for reference; do
	not re-enable both at once, they'll fight over CameraType/CameraMode.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Keys = require(ReplicatedStorage:WaitForChild("KeybindConfig"))

local player = Players.LocalPlayer

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode ~= Keys.TogglePerspective then
		return
	end

	if player.CameraMode == Enum.CameraMode.LockFirstPerson then
		player.CameraMode = Enum.CameraMode.Classic
	else
		player.CameraMode = Enum.CameraMode.LockFirstPerson
	end
end)
