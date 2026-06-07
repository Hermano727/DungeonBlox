--[[
	QuestTrackerClient
	Top-left HUD: Cuso bandit quest, Miner coal quest, Fisherman fish quest progress, coin reward, brief completion notice.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local profilePush = ReplicatedStorage:WaitForChild("DungeonProfilePush", 60)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local DungeonMenuNet = require(script.Parent:WaitForChild("DungeonMenuNet"))

local wasCusoQuestActive = false
local wasMinerQuestActive = false
local wasFisherQuestActive = false
local hideTask = nil

local function cancelHide()
	if hideTask ~= nil then
		task.cancel(hideTask)
		hideTask = nil
	end
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "QuestTrackerHud"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 125
screenGui.Enabled = true
screenGui.Parent = playerGui

local root = Instance.new("CanvasGroup")
root.Name = "BanditQuestTracker"
root.AnchorPoint = Vector2.new(0, 0)
local topInset = GuiService:GetGuiInset().Y
root.Position = UDim2.new(0, 10, 0, topInset + 64)
root.Size = UDim2.fromOffset(312, 122)
root.BackgroundColor3 = Color3.fromRGB(22, 18, 18)
root.BorderSizePixel = 0
root.GroupTransparency = 0
root.Visible = false
root.Parent = screenGui

Instance.new("UICorner", root).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new("UIStroke", root)
stroke.Thickness = 1
stroke.Color = Color3.fromRGB(95, 75, 70)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, -18, 0, 22)
title.Position = UDim2.new(0, 12, 0, 8)
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(255, 212, 130)
title.Text = "Quest"
title.Parent = root

local body = Instance.new("TextLabel")
body.BackgroundTransparency = 1
body.Size = UDim2.new(1, -18, 0, 44)
body.Position = UDim2.new(0, 12, 0, 32)
body.Font = Enum.Font.GothamMedium
body.TextSize = 14
body.TextXAlignment = Enum.TextXAlignment.Left
body.TextYAlignment = Enum.TextYAlignment.Top
body.TextWrapped = true
body.TextColor3 = Color3.fromRGB(225, 215, 205)
body.Text = ""
body.Parent = root

local reward = Instance.new("TextLabel")
reward.BackgroundTransparency = 1
reward.Size = UDim2.new(1, -18, 0, 22)
reward.Position = UDim2.new(0, 12, 0, 86)
reward.Font = Enum.Font.GothamMedium
reward.TextSize = 13
reward.TextXAlignment = Enum.TextXAlignment.Left
reward.TextColor3 = Color3.fromRGB(150, 220, 150)
reward.Text = ""
reward.Parent = root

local CHARACTER_MENU_NAME = "SkillsPopupUI"
local FADE_GROUP_TRANSPARENCY = 0.86
local FADE_TWEEN_INFO = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local characterMenuOpen = false
local fadeTween = nil

local function stopFadeTween()
	if fadeTween ~= nil then
		fadeTween:Cancel()
		fadeTween = nil
	end
end

local function applyQuestHudFade()
	if not root.Visible then
		stopFadeTween()
		root.GroupTransparency = 0
		return
	end
	local target = characterMenuOpen and FADE_GROUP_TRANSPARENCY or 0
	stopFadeTween()
	fadeTween = TweenService:Create(root, FADE_TWEEN_INFO, { GroupTransparency = target })
	fadeTween:Play()
end

local function attachCharacterMenuListener()
	local skills = playerGui:WaitForChild(CHARACTER_MENU_NAME, 120)
	if not skills or not skills:IsA("ScreenGui") then
		return
	end
	local function onEnabledChanged()
		characterMenuOpen = skills.Enabled == true
		applyQuestHudFade()
	end
	skills:GetPropertyChangedSignal("Enabled"):Connect(onEnabledChanged)
	onEnabledChanged()
end
local function readCusoQuest(profile)
	if type(profile) ~= "table" then
		return nil
	end
	local fl = profile.flags
	if type(fl) ~= "table" or type(fl.cusoBanditQuest) ~= "table" then
		return nil
	end
	return fl.cusoBanditQuest
end

local function readMinerQuest(profile)
	if type(profile) ~= "table" then
		return nil
	end
	local fl = profile.flags
	if type(fl) ~= "table" or type(fl.minerCoalQuest) ~= "table" then
		return nil
	end
	return fl.minerCoalQuest
end

local function readFisherQuest(profile)
	if type(profile) ~= "table" then
		return nil
	end
	local fl = profile.flags
	if type(fl) ~= "table" or type(fl.fisherFishQuest) ~= "table" then
		return nil
	end
	return fl.fisherFishQuest
end

local function paintFromProfile(profile)
	local mq = readMinerQuest(profile)
	if mq then
		local mActive = mq.active == true
		local mDone = mq.completed == true
		local mt = math.max(1, math.floor(tonumber(mq.target) or 5))
		local mp = math.min(mt, math.max(0, math.floor(tonumber(mq.progress) or 0)))
		local mrc = math.max(0, math.floor(tonumber(mq.rewardCoins) or 10))

		if mActive then
			cancelHide()
			wasMinerQuestActive = true
			root.Visible = true
			title.Text = "Quest: Coal contract"
			body.Text = string.format("Coal collected: %d / %d", mp, mt)
			reward.Text = string.format("Reward: %d coins", mrc)
			reward.TextColor3 = Color3.fromRGB(150, 220, 150)
			applyQuestHudFade()
			return
		end

		if mDone and wasMinerQuestActive then
			cancelHide()
			root.Visible = true
			title.Text = "Quest complete"
			body.Text = string.format("You earned %d coins. Check your wallet.", mrc)
			reward.Text = ""
			wasMinerQuestActive = false
			applyQuestHudFade()
			hideTask = task.delay(6, function()
				hideTask = nil
				root.Visible = false
				stopFadeTween()
				root.GroupTransparency = 0
			end)
			return
		end

		if not mActive then
			wasMinerQuestActive = false
		end
	end

	local fq = readFisherQuest(profile)
	if fq then
		local fActive = fq.active == true
		local fDone = fq.completed == true
		local ft = math.max(1, math.floor(tonumber(fq.target) or 5))
		local fp = math.min(ft, math.max(0, math.floor(tonumber(fq.progress) or 0)))
		local frc = math.max(0, math.floor(tonumber(fq.rewardCoins) or 10))

		if fActive then
			cancelHide()
			wasFisherQuestActive = true
			root.Visible = true
			title.Text = "Quest: Fresh catch"
			body.Text = string.format("Fish landed: %d / %d", fp, ft)
			reward.Text = string.format("Reward: %d coins", frc)
			reward.TextColor3 = Color3.fromRGB(150, 220, 150)
			applyQuestHudFade()
			return
		end

		if fDone and wasFisherQuestActive then
			cancelHide()
			root.Visible = true
			title.Text = "Quest complete"
			body.Text = string.format("You earned %d coins. Check your wallet.", frc)
			reward.Text = ""
			wasFisherQuestActive = false
			applyQuestHudFade()
			hideTask = task.delay(6, function()
				hideTask = nil
				root.Visible = false
				stopFadeTween()
				root.GroupTransparency = 0
			end)
			return
		end

		if not fActive then
			wasFisherQuestActive = false
		end
	end

	local cq = readCusoQuest(profile)
	if not cq then
		cancelHide()
		stopFadeTween()
		root.GroupTransparency = 0
		root.Visible = false
		wasCusoQuestActive = false
		return
	end

	local active = cq.active == true
	local completed = cq.completed == true
	local target = math.max(1, math.floor(tonumber(cq.target) or 5))
	local prog = math.min(target, math.max(0, math.floor(tonumber(cq.progress) or 0)))
	local rc = math.max(0, math.floor(tonumber(cq.rewardCoins) or 10))

	if active then
		cancelHide()
		wasCusoQuestActive = true
		root.Visible = true
		title.Text = "Quest: Clear the bandits"
		body.Text = string.format("Bandits defeated: %d / %d", prog, target)
		reward.Text = string.format("Reward: %d coins", rc)
		reward.TextColor3 = Color3.fromRGB(150, 220, 150)
		applyQuestHudFade()
		return
	end

	if completed and wasCusoQuestActive then
		cancelHide()
		root.Visible = true
		title.Text = "Quest complete"
		body.Text = string.format("You earned %d coins. Check your wallet.", rc)
		reward.Text = ""
		wasCusoQuestActive = false
		applyQuestHudFade()
		hideTask = task.delay(6, function()
			hideTask = nil
			root.Visible = false
			stopFadeTween()
			root.GroupTransparency = 0
		end)
		return
	end

	cancelHide()
	stopFadeTween()
	root.GroupTransparency = 0
	root.Visible = false
	if not active then
		wasCusoQuestActive = false
	end
end

local function refreshFromSnapshot()
	local snap = DungeonMenuNet.getLastSnapshot()
	local profile = snap and snap.profile
	paintFromProfile(profile)
end

if profilePush and profilePush:IsA("RemoteEvent") then
	profilePush.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and type(payload.profile) == "table" then
			paintFromProfile(payload.profile)
		end
	end)
end

task.defer(function()
	DungeonMenuNet.requestSync()
	refreshFromSnapshot()
	attachCharacterMenuListener()
end)
