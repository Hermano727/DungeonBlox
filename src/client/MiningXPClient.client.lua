-- Mining XP Client
-- Applies the server's mining XP totals for the HUD (XpHud reads SkillXPShared).
-- Twin of FishingXPClient. Until 2026-10-03 this lived inside the pickaxe tool's MiningScript,
-- which the mining session (src/client/Professions/MiningClient) replaced.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SkillXPShared = require(ReplicatedStorage:WaitForChild("SkillXPShared"))

local miningXPEvent = ReplicatedStorage:WaitForChild("MiningXPEvent")
miningXPEvent.OnClientEvent:Connect(function(xpAmount, totals)
	SkillXPShared.ApplyServerGain("Mining", xpAmount, totals)
end)
