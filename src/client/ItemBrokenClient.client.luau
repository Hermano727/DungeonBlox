--[[
	ItemBrokenClient

	Tells you when a piece of your gear breaks (it wore down to 0, a death took the last of its
	durability, or a +4 or higher enchant failed): a centre flash and a sound. The server
	(SSS/DurabilityService) has already taken it off and docked its enchant levels.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CenterFlashUI = require(script.Parent:WaitForChild("CenterFlashUI"))
local SfxService = require(ReplicatedStorage:WaitForChild("SfxService"))

local event = ReplicatedStorage:WaitForChild("ItemBrokenNotify")
event.OnClientEvent:Connect(function(itemName)
	local name = (type(itemName) == "string" and itemName ~= "") and itemName or "Your gear"
	CenterFlashUI.Show(name .. " broke! Repair it at a Blacksmith.")
	SfxService.PlayEffect("ItemBreak")
end)
