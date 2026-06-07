-- Fishing XP Client
-- Fishing XP HUD + shared state (mirrors CombatXPClient / mining pickaxe flow).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local SkillXPShared = require(ReplicatedStorage:WaitForChild("SkillXPShared"))

local UI_HIDE_DELAY = 5

local uiShown = false
local uiHideTask = nil
local priorityLoopRunning = false

local function setBarZ(guiName, z)
	local g = PlayerGui:FindFirstChild(guiName)
	if not g then return end
	local mf = g:FindFirstChild("MainFrame")
	if not mf then return end
	mf.ZIndex = z
	for _, child in pairs(mf:GetDescendants()) do
		if child:IsA("GuiObject") then
			child.ZIndex = z
		end
	end
end

local function updateZIndexPriority()
	local player = Players.LocalPlayer
	if not player then return end

	local combatTime = player:GetAttribute("LastCombatXPGain") or 0
	local miningTime = player:GetAttribute("LastMiningXPGain") or 0
	local fishingTime = player:GetAttribute("LastFishingXPGain") or 0

	local front = "Combat"
	local best = combatTime
	if miningTime >= best then front, best = "Mining", miningTime end
	if fishingTime >= best then front, best = "Fishing", fishingTime end

	setBarZ("CombatXPUI", front == "Combat" and 10 or 5)
	setBarZ("MiningXPUI", front == "Mining" and 10 or 5)
	setBarZ("FishingXPUI", front == "Fishing" and 10 or 5)
end

local function startPriorityLoop()
	if priorityLoopRunning then return end
	priorityLoopRunning = true
	task.spawn(function()
		while task.wait(0.1) do
			updateZIndexPriority()
		end
	end)
end

local function startHideTimer()
	if uiHideTask then
		task.cancel(uiHideTask)
		uiHideTask = nil
	end

	uiHideTask = task.delay(UI_HIDE_DELAY, function()
		local gui = PlayerGui:FindFirstChild("FishingXPUI")
		if gui then
			local mainFrame = gui:FindFirstChild("MainFrame")
			if mainFrame then
				mainFrame.Visible = false
				uiShown = false
			end
		end
		uiHideTask = nil
	end)
end

local function updateXPUI()
	local gui = PlayerGui:FindFirstChild("FishingXPUI")
	if not gui then return end

	local mainFrame = gui:FindFirstChild("MainFrame")
	if not mainFrame then return end

	if not uiShown then
		mainFrame.Visible = true
		uiShown = true
	end

	local player = Players.LocalPlayer
	if player then
		player:SetAttribute("LastFishingXPGain", tick())
	end

	startHideTimer()

	local xpBackground = mainFrame:FindFirstChild("XPBackground")
	local xpFill = xpBackground and xpBackground:FindFirstChild("XPFill")
	local levelLabel = mainFrame:FindFirstChild("LevelLabel")
	local xpLabel = mainFrame:FindFirstChild("XPLabel")

	local xpNeeded = SkillXPShared.GetXPForLevel(SkillXPShared.Fishing.Level)
	local progress = math.clamp(SkillXPShared.Fishing.XP / xpNeeded, 0, 1)

	if xpFill then
		xpFill.Size = UDim2.new(progress, 0, 1, -4)
	end
	if levelLabel then
		levelLabel.Text = "Level " .. SkillXPShared.Fishing.Level
	end
	if xpLabel then
		xpLabel.Text = SkillXPShared.Fishing.XP .. " / " .. xpNeeded .. " XP"
	end
end

local function addXP(amount)
	SkillXPShared.Fishing.XP = SkillXPShared.Fishing.XP + amount
	local xpNeeded = SkillXPShared.GetXPForLevel(SkillXPShared.Fishing.Level)

	while SkillXPShared.Fishing.XP >= xpNeeded do
		SkillXPShared.Fishing.XP = SkillXPShared.Fishing.XP - xpNeeded
		SkillXPShared.Fishing.Level = SkillXPShared.Fishing.Level + 1
		xpNeeded = SkillXPShared.GetXPForLevel(SkillXPShared.Fishing.Level)
		print("Fishing level up! Now level " .. SkillXPShared.Fishing.Level)
	end

	SkillXPShared.Notify()
	updateXPUI()
end

local fishingXPEvent = ReplicatedStorage:WaitForChild("FishingXPEvent")
fishingXPEvent.OnClientEvent:Connect(function(xpAmount)
	addXP(tonumber(xpAmount) or 0)
end)

startPriorityLoop()

task.defer(function()
	SkillXPShared.ApplyXPHudLayout(PlayerGui)
end)

print("Fishing XP client loaded")
