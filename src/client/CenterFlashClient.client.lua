--[[
	CenterFlashClient
	Listens for server-pushed center-screen warnings (e.g. "Inventory is full!" from
	WorldLootService's pickup denial) and renders them via CenterFlashUI. Purely a
	listener, no decision logic -- the server owns cooldowns/throttling.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CenterFlashUI = require(script.Parent:WaitForChild("CenterFlashUI"))

local ge = ReplicatedStorage:WaitForChild("GameEvents", 30)
local ev = ge and ge:WaitForChild("CenterFlashNotify", 30)
if ev then
	ev.OnClientEvent:Connect(function(text)
		CenterFlashUI.Show(text)
	end)
end
