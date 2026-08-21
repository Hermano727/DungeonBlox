-- Fishing XP Client
-- Accumulates fishing XP and stamps gain timestamps for the HUD to read.
--
-- UI ownership moved to XpHud (React, src/client/XpHud) -- this script no
-- longer touches any GUI instance. See CombatXPClient.client.lua for the
-- twin implementation and the reasoning.
--
-- The add-XP/level-up loop lives in SkillXPShared.AddXP now (it used to be
-- hand-rolled here, in CombatXPClient, and in MiningScript, all three
-- copy-pasted) -- see SkillXPShared.lua for the shared implementation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SkillXPShared = require(ReplicatedStorage:WaitForChild("SkillXPShared"))

local fishingXPEvent = ReplicatedStorage:WaitForChild("FishingXPEvent")
fishingXPEvent.OnClientEvent:Connect(function(xpAmount)
	SkillXPShared.AddXP("Fishing", xpAmount)
end)

print("Fishing XP client loaded")
