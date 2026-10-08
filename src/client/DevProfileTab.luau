--[[
	DevProfileTab -- the F8 dev panel's PROFILE tab (DevClient mode "Profile").

	Set your own Combat / Mining / Fishing level exactly (0 XP into it, saved to the profile),
	and refill Health / Energy / Hunger, all via the admin-gated DevProfileAction remote
	(ProfileBootstrap). Every button acts on its own; DevClient hides its shared confirm button
	on this tab. Lives outside DevClient because that script is at Luau's 200-locals limit.

	Build(ctx) -> section Frame (starts hidden; DevClient toggles Visible with the tab).
	ctx: parent, y, w, h, lbl, mkB, mkI (DevClient's UI helpers), acc, gold, status(msg, isErr).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkillXPShared = require(ReplicatedStorage:WaitForChild("SkillXPShared"))

local DevProfileTab = {}

local SKILLS = {
	{ key = "Combat", branch = "combat" },
	{ key = "Mining", branch = "mining" },
	{ key = "Fishing", branch = "fishing" },
}

local REFILLS = {
	{ label = "Health", action = "refillHp", ok = "Health refilled", color = Color3.fromRGB(120, 40, 40) },
	{ label = "Energy", action = "refillEnergy", ok = "Energy refilled", color = Color3.fromRGB(150, 120, 30) },
	{ label = "Hunger", action = "refillHunger", ok = "Hunger refilled", color = Color3.fromRGB(60, 110, 50) },
	{ label = "All", action = "refillAll", ok = "Refilled everything and cleansed debuffs", color = Color3.fromRGB(70, 70, 120) },
}

function DevProfileTab.Build(ctx)
	local lbl, mkB, mkI, status = ctx.lbl, ctx.mkB, ctx.mkI, ctx.status
	local W = ctx.w

	local sec = Instance.new("Frame")
	sec.Name = "ProfileSection"
	sec.Position = UDim2.fromOffset(0, ctx.y)
	sec.Size = UDim2.fromOffset(W, ctx.h)
	sec.BackgroundTransparency = 1
	sec.Visible = false
	sec.Parent = ctx.parent

	local function act(action, args, okMsg)
		local rf = ReplicatedStorage:FindFirstChild("DevProfileAction")
		if not rf then status("DevProfileAction remote missing", true) return end
		local pOk, ok, err = pcall(function() return rf:InvokeServer(action, args) end)
		if not pOk then
			status("Failed: " .. tostring(ok), true)
		elseif ok then
			status(okMsg)
		else
			status("Failed: " .. tostring(err), true)
		end
	end

	lbl(sec, "SKILL LEVELS", 12, 2, 200, 16, 11, ctx.acc, true)
	lbl(sec, "Sets the level exactly, with 0 XP into it. Saved to your profile.", 12, 18, W - 24, 14, 10, Color3.fromRGB(150, 135, 120))

	local levelLabels = {}
	for i, sk in ipairs(SKILLS) do
		local y = 40 + (i - 1) * 36
		lbl(sec, sk.key, 12, y, 90, 28, 13, Color3.new(1, 1, 1), true)
		levelLabels[sk.key] = lbl(sec, "", 104, y, 90, 28, 12, ctx.gold)
		local box = mkI(sec, "level", 200, y, 70, 28, "")
		local set = mkB(sec, "Set", 278, y, 56, 28, Color3.fromRGB(40, 80, 40))
		local minus = mkB(sec, "-1", 340, y, 40, 28)
		local plus = mkB(sec, "+1", 386, y, 40, 28)

		local function apply(level)
			level = math.floor(tonumber(level) or 0)
			if level < 1 then status("Enter a level of 1 or more", true) return end
			act("setSkill", { branch = sk.branch, level = level }, sk.key .. " set to level " .. level)
		end
		set.Activated:Connect(function() apply(box.Text) end)
		box.FocusLost:Connect(function(enter) if enter then apply(box.Text) end end)
		minus.Activated:Connect(function() apply((SkillXPShared[sk.key].Level or 1) - 1) end)
		plus.Activated:Connect(function() apply((SkillXPShared[sk.key].Level or 1) + 1) end)
	end

	-- Current levels from the synced display cache (SkillXPSync keeps it equal to the save).
	local function refreshLevels()
		for key, label in pairs(levelLabels) do
			local st = SkillXPShared[key]
			label.Text = st and ("Lv " .. tostring(st.Level)) or "Lv ?"
		end
	end
	refreshLevels()
	SkillXPShared.Subscribe(refreshLevels)

	local y2 = 40 + #SKILLS * 36 + 14
	lbl(sec, "REFILL", 12, y2, 200, 16, 11, ctx.acc, true)
	local bw = (W - 24 - 3 * 8) / #REFILLS
	for i, r in ipairs(REFILLS) do
		local b = mkB(sec, r.label, 12 + (i - 1) * (bw + 8), y2 + 20, bw, 32, r.color)
		b.Activated:Connect(function() act(r.action, nil, r.ok) end)
	end

	-- Debuffs: clear them all, or put some on to test (slow, blind, bleed, 2 poison stacks).
	local y3 = y2 + 64
	lbl(sec, "DEBUFFS", 12, y3, 200, 16, 11, ctx.acc, true)
	local half = (W - 24 - 8) / 2
	local cleanseBtn = mkB(sec, "Cleanse", 12, y3 + 20, half, 32, Color3.fromRGB(40, 100, 90))
	cleanseBtn.Activated:Connect(function() act("cleanse", nil, "All debuffs cleansed") end)
	local debuffBtn = mkB(sec, "Debuff", 12 + half + 8, y3 + 20, half, 32, Color3.fromRGB(110, 50, 120))
	debuffBtn.Activated:Connect(function() act("debuff", nil, "Slowed, blinded, bleeding, +2 poison") end)

	-- Journal Activity page: fake 30 days of T1 history, or wipe it (RS/JournalActivity).
	local y4 = y3 + 64
	lbl(sec, "JOURNAL ACTIVITY", 12, y4, 200, 16, 11, ctx.acc, true)
	local seedBtn = mkB(sec, "Seed activity", 12, y4 + 20, half, 32, Color3.fromRGB(60, 80, 110))
	seedBtn.Activated:Connect(function() act("seedActivity", nil, "Seeded 30 days of T1 activity") end)
	local clearBtn = mkB(sec, "Clear activity", 12 + half + 8, y4 + 20, half, 32, Color3.fromRGB(110, 60, 50))
	clearBtn.Activated:Connect(function() act("clearActivity", nil, "Activity history cleared") end)

	-- The tutorial (SSS/TutorialService). Reset WIPES your whole profile (ProfileService.
	-- WipeProfile: items, coins, skills, map) and starts the tutorial as a new player. Skip ends
	-- it here; Jump starts at a step by its id (TutorialSteps).
	local y5 = y4 + 64
	lbl(sec, "TUTORIAL", 12, y5, 200, 16, 11, ctx.acc, true)
	-- Two clicks within 3 s: it wipes everything.
	local resetBtn = mkB(sec, "Wipe + restart", 12, y5 + 20, half, 32, Color3.fromRGB(130, 50, 40))
	local armedAt = 0
	resetBtn.Activated:Connect(function()
		if os.clock() - armedAt > 3 then
			armedAt = os.clock()
			resetBtn.Text = "Click again to wipe"
			status("This wipes your whole profile. Click again to confirm.", true)
			task.delay(3, function() resetBtn.Text = "Wipe + restart" end)
			return
		end
		armedAt = 0
		resetBtn.Text = "Wipe + restart"
		act("tutorialReset", nil, "Profile wiped, tutorial restarted")
	end)
	local skipBtn = mkB(sec, "Skip tutorial", 12 + half + 8, y5 + 20, half, 32, Color3.fromRGB(110, 60, 50))
	skipBtn.Activated:Connect(function() act("tutorialSkip", nil, "Tutorial skipped") end)
	local stepBox = mkI(sec, "step id", 12, y5 + 60, W - 24 - 90, 28, "")
	local stepBtn = mkB(sec, "Jump", W - 12 - 82, y5 + 60, 82, 28, Color3.fromRGB(60, 80, 110))
	local function jump()
		local id = stepBox.Text:match("^%s*(.-)%s*$")
		if id == "" then status("Enter a step id", true) return end
		act("tutorialStep", { step = id }, "Jumped to " .. id)
	end
	stepBtn.Activated:Connect(jump)
	stepBox.FocusLost:Connect(function(enter) if enter then jump() end end)

	return sec
end

return DevProfileTab
