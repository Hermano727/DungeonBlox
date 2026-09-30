-- SkillXPShared
-- Client-side XP state shared between HUD scripts and the Tab skills popup.

local Players = game:GetService("Players")

local SkillXPShared = {}

SkillXPShared.BASE_XP_REQUIREMENT = 5

SkillXPShared.Combat = {
	XP = 0,
	Level = 1,
}

SkillXPShared.Mining = {
	XP = 0,
	Level = 1,
}

SkillXPShared.Fishing = {
	XP = 0,
	Level = 1,
}

local listeners = {}

-- SetSkillsMenuOpen/IsSkillsMenuOpen used to live here (force-showing the floating
-- Combat bar while SkillsPanel.lua was open) but caused two Combat bars to render at
-- once -- the floating kill-triggered one AND SkillsPanel's own inline bar -- so that
-- whole mechanism was removed 2026-09-13. The Combat bar now only ever shows on an
-- actual kill, same as Mining/Fishing.

function SkillXPShared.GetXPForLevel(level)
	return SkillXPShared.BASE_XP_REQUIREMENT * (2 ^ (level - 1))
end

function SkillXPShared.Subscribe(callback)
	table.insert(listeners, callback)
	return function()
		for i = #listeners, 1, -1 do
			if listeners[i] == callback then
				table.remove(listeners, i)
			end
		end
	end
end

function SkillXPShared.Notify()
	for _, cb in ipairs(listeners) do
		task.defer(cb)
	end
end

-- Add XP to a named skill track, rolling over as many level-ups as the gain
-- warrants, then stamps the Last<Skill>XPGain attribute XpHud.luau reads to
-- decide which floating bar to show/raise, and notifies subscribers (the
-- Skills tab panel, etc). Returns true if at least one level-up happened
-- (2026-09-13, per direct request -- see CombatXPClient's use of this return
-- value to gate its level-up sound; Mining/Fishing callers still just ignore
-- the return and keep their existing every-gain behavior).
--
-- skillKey must be the exact key of one of the tables above ("Combat",
-- "Mining", "Fishing") -- CombatXPClient/FishingXPClient/MiningScript used to
-- each hand-roll this same while-loop independently (add XP, pop levels
-- while XP >= requirement, print, stamp attribute, notify); this is that
-- logic in one place so the three skills can't drift out of sync with each
-- other's level-up behavior.
function SkillXPShared.AddXP(skillKey, amount)
	local state = SkillXPShared[skillKey]
	if type(state) ~= "table" then
		warn("[SkillXPShared] AddXP: unknown skill '" .. tostring(skillKey) .. "'")
		return false
	end

	state.XP = state.XP + (tonumber(amount) or 0)
	local xpNeeded = SkillXPShared.GetXPForLevel(state.Level)
	local leveledUp = false

	while state.XP >= xpNeeded do
		state.XP = state.XP - xpNeeded
		state.Level = state.Level + 1
		xpNeeded = SkillXPShared.GetXPForLevel(state.Level)
		leveledUp = true
		print(skillKey .. " level up! Now level " .. state.Level)
	end

	local player = Players.LocalPlayer
	if player then
		player:SetAttribute("Last" .. skillKey .. "XPGain", tick())
	end

	SkillXPShared.Notify()

	return leveledUp
end

--[[
	Server-authoritative sync (2026-09-27). The server has always saved skill XP in the profile
	(profile.stats.combat/mining/fishing, via ProfileService.AddSkillXP), but this module used to
	start every session at Level 1 / XP 0 and only ever ADD the per-kill amounts from the XP
	events -- so after a rejoin the HUD and the Skills panel showed level 1 again even though the
	saved level was fine. Now:
	  SyncFromStats(stats)  sets all three tracks from a profile snapshot's `stats` table. Run
	                        by SkillXPSync.client on every DungeonProfilePush / requestSync.
	  ApplyServerGain(key, amount, totals)
	                        for the XP events: when the server sent its post-gain totals
	                        ({ level, xp, levelsGained }), SET the track to them instead of
	                        adding; falls back to AddXP for an event without totals.
	Both are absolute, so a profile push and the XP event for the same gain can arrive in either
	order without double-counting.
]]
local PROFILE_KEYS = { Combat = "combat", Mining = "mining", Fishing = "fishing" }

-- Returns true if the stored values changed.
local function setTrack(skillKey, level, xp)
	local state = SkillXPShared[skillKey]
	level = math.max(1, math.floor(tonumber(level) or 1))
	xp = math.max(0, tonumber(xp) or 0)
	if state.Level == level and state.XP == xp then
		return false
	end
	state.Level = level
	state.XP = xp
	return true
end

function SkillXPShared.SyncFromStats(stats)
	if type(stats) ~= "table" then return end
	local changed = false
	for skillKey, profileKey in pairs(PROFILE_KEYS) do
		local bucket = stats[profileKey]
		if type(bucket) == "table" and tonumber(bucket.level) then
			if setTrack(skillKey, bucket.level, bucket.xp) then changed = true end
		end
	end
	-- No Last<Skill>XPGain stamp here: a sync is not a gain, so it must not pop the XP bars.
	if changed then SkillXPShared.Notify() end
end

-- Returns true if at least one level-up happened (same contract as AddXP).
function SkillXPShared.ApplyServerGain(skillKey, amount, totals)
	if type(SkillXPShared[skillKey]) ~= "table" then
		warn("[SkillXPShared] ApplyServerGain: unknown skill '" .. tostring(skillKey) .. "'")
		return false
	end
	if type(totals) ~= "table" or not tonumber(totals.level) then
		return SkillXPShared.AddXP(skillKey, amount)
	end
	setTrack(skillKey, totals.level, totals.xp)
	local player = Players.LocalPlayer
	if player then
		player:SetAttribute("Last" .. skillKey .. "XPGain", tick())
	end
	SkillXPShared.Notify()
	return (tonumber(totals.levelsGained) or 0) > 0
end

-- Place Combat / Mining / Fishing XP bars in the same bottom-left slot (world HUD).
-- Z-order is handled by the per-skill clients (most recent XP gain on top).
function SkillXPShared.ApplyXPHudLayout(playerGui)
	if typeof(playerGui) ~= "Instance" or not playerGui:IsA("PlayerGui") then
		return
	end
	local names = { "CombatXPUI", "MiningXPUI", "FishingXPUI" }
	local left = 10
	local bottom = 10
	for _, name in ipairs(names) do
		local sg = playerGui:FindFirstChild(name)
		if sg and sg:IsA("ScreenGui") then
			sg.IgnoreGuiInset = true
			local mf = sg:FindFirstChild("MainFrame")
			if mf and mf:IsA("GuiObject") then
				mf.AnchorPoint = Vector2.new(0, 1)
				mf.Position = UDim2.new(0, left, 1, -bottom)
			end
		end
	end
end

return SkillXPShared
