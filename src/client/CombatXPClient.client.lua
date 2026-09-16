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
local SfxService = require(ReplicatedStorage:WaitForChild("SfxService"))

-- Listen for combat XP events from server
local combatXPEvent = ReplicatedStorage:WaitForChild("CombatXPEvent")
combatXPEvent.OnClientEvent:Connect(function(xpAmount)
    local leveledUp = SkillXPShared.AddXP("Combat", xpAmount)
    -- Plays only on an actual Combat level-up now (2026-09-13, per direct request:
    -- "make the xp sound effect only play on combat level up rather than every
    -- kill" -- was every kill, since this event only fires on a killing blow, see
    -- DamageService.AwardKill / MobManager.server.lua). The Combat XP bar itself
    -- still shows/raises on every kill regardless -- that's driven by the
    -- LastCombatXPGain attribute stamp inside AddXP, untouched by this gate.
    if leveledUp then
        SfxService.PlayEffect("CombatXPGain")
    end
end)

print("Combat XP client loaded")
