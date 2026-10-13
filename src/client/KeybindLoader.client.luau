--[[
	KeybindLoader -- puts the player's saved keys (Settings > Controls, settings category "keys")
	on top of KeybindConfig's defaults once per session. It runs on its own thread so nothing
	waits on the settings round trip: until it lands every key is its default, and the scripts
	that bind a key once re-bind on KeybindConfig.Changed when it does.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Keys = require(ReplicatedStorage:WaitForChild("KeybindConfig"))
local SettingsStore = require(ReplicatedStorage:WaitForChild("SettingsStore"))

task.spawn(function()
	local saved = SettingsStore.Get().keys
	if type(saved) == "table" and next(saved) then
		Keys.ApplySaved(saved)
	end
end)
