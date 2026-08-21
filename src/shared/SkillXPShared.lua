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
-- Skills tab panel, etc).
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
		return
	end

	state.XP = state.XP + (tonumber(amount) or 0)
	local xpNeeded = SkillXPShared.GetXPForLevel(state.Level)

	while state.XP >= xpNeeded do
		state.XP = state.XP - xpNeeded
		state.Level = state.Level + 1
		xpNeeded = SkillXPShared.GetXPForLevel(state.Level)
		print(skillKey .. " level up! Now level " .. state.Level)
	end

	local player = Players.LocalPlayer
	if player then
		player:SetAttribute("Last" .. skillKey .. "XPGain", tick())
	end

	SkillXPShared.Notify()
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
