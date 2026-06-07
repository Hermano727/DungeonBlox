-- SkillXPShared
-- Client-side XP state shared between HUD scripts and the Tab skills popup.

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
