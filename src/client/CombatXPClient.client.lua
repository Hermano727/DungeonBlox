-- Combat XP Client Script
-- Accumulates combat XP and stamps gain timestamps for the HUD to read.
--
-- UI ownership moved to XpHud (React, src/client/XpHud) -- this script no
-- longer touches any GUI instance. It only mutates SkillXPShared state and
-- stamps player:SetAttribute("LastCombatXPGain", tick()), which is what
-- XpHud.luau's lastGain() reads to decide which bar is visible/on top.
--
-- The actual add-XP/level-up loop lives in SkillXPShared.AddXP now (it used
-- to be hand-rolled here and duplicated verbatim in FishingXPClient and
-- MiningScript) -- see SkillXPShared.lua for the shared implementation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SkillXPShared = require(ReplicatedStorage:WaitForChild("SkillXPShared"))

-- Listen for combat XP events from server
local combatXPEvent = ReplicatedStorage:WaitForChild("CombatXPEvent")
combatXPEvent.OnClientEvent:Connect(function(xpAmount)
    SkillXPShared.AddXP("Combat", xpAmount)
end)

print("Combat XP client loaded")
