--[[
	KeyFragmentMilestoneClient
	One-time HUD when the server detects the player first reached 30 T1 Key Fragments in their bag.
	Styled like QuestTrackerClient; anchored middle-right under loot banners.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- LootBannerGui stack: top Y=48, up to 5 banners @40px + 6px gap (see LootClient).
local LOOT_TOP_OFFSET = 48
local LOOT_MAX_BANNERS = 5
local LOOT_BANNER_H = 40
local LOOT_GAP = 6
local PANEL_STACK_PAD = 12
local TOP_Y = LOOT_TOP_OFFSET + LOOT_MAX_BANNERS * (LOOT_BANNER_H + LOOT_GAP) + PANEL_STACK_PAD

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "KeyFragmentMilestoneGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 255
screenGui.Enabled = true
screenGui.Parent = playerGui

local root = Instance.new("CanvasGroup")
root.Name = "MilestonePanel"
root.AnchorPoint = Vector2.new(1, 0)
root.Position = UDim2.new(1, -12, 0, TOP_Y)
root.Size = UDim2.fromOffset(312, 136)
root.BackgroundColor3 = Color3.fromRGB(22, 18, 18)
root.BorderSizePixel = 0
root.GroupTransparency = 0
root.Visible = false
root.Parent = screenGui

Instance.new("UICorner", root).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new("UIStroke", root)
stroke.Thickness = 1
stroke.Color = Color3.fromRGB(95, 75, 70)

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "Close"
closeBtn.AnchorPoint = Vector2.new(1, 0)
closeBtn.Position = UDim2.new(1, -6, 0, 4)
closeBtn.Size = UDim2.fromOffset(30, 30)
closeBtn.BackgroundTransparency = 0.88
closeBtn.BackgroundColor3 = Color3.fromRGB(40, 32, 32)
closeBtn.BorderSizePixel = 0
closeBtn.Text = "×"
closeBtn.TextColor3 = Color3.fromRGB(235, 225, 215)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 20
closeBtn.AutoButtonColor = true
closeBtn.ZIndex = 3
closeBtn.Parent = root
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Name = "Title"
title.Size = UDim2.new(1, -52, 0, 22)
title.Position = UDim2.new(0, 12, 0, 8)
title.Font = Enum.Font.GothamBold
title.TextSize = 15
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(255, 212, 130)
title.Text = "Milestone"
title.Parent = root

local body = Instance.new("TextLabel")
body.BackgroundTransparency = 1
body.Name = "Body"
body.Size = UDim2.new(1, -20, 0, 56)
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
reward.Name = "Hint"
reward.Size = UDim2.new(1, -20, 0, 36)
reward.Position = UDim2.new(0, 12, 0, 92)
reward.Font = Enum.Font.GothamMedium
reward.TextSize = 13
reward.TextXAlignment = Enum.TextXAlignment.Left
reward.TextYAlignment = Enum.TextYAlignment.Top
reward.TextWrapped = true
reward.TextColor3 = Color3.fromRGB(150, 220, 150)
reward.Text = ""
reward.Parent = root

local dismissEv = nil

local function hidePanel()
	root.Visible = false
end

local function bind()
	local ge = ReplicatedStorage:WaitForChild("GameEvents", 120)
	if not ge or not ge:IsA("Folder") then
		warn("[KeyFragmentMilestoneClient] GameEvents missing — milestone UI disabled.")
		return
	end
	local show = ge:WaitForChild("T1KeyFragment30MilestoneShow", 60)
	dismissEv = ge:WaitForChild("T1KeyFragment30MilestoneDismiss", 60)
	if not show or not show:IsA("RemoteEvent") or not dismissEv or not dismissEv:IsA("RemoteEvent") then
		warn("[KeyFragmentMilestoneClient] milestone remotes missing")
		return
	end
	show.OnClientEvent:Connect(function(payload)
		local n = 30
		if type(payload) == "table" then
			local c = tonumber(payload.count)
			if c then
				n = math.max(30, math.floor(c))
			end
		end
		title.Text = "Quest: T1 key fragments"
		body.Text = string.format(
			"You now have %d T1 Key Fragments in your bag. Trade them at the Dungeoneer for a T1 Dungeon Key (costs 30 fragments).",
			n
		)
		reward.Text = "Tip: open the Dungeoneer trade menu and exchange 30 fragments for a key. Tap × when you are done reading."
		root.Visible = true
	end)
	closeBtn.MouseButton1Click:Connect(function()
		if dismissEv then
			dismissEv:FireServer()
		end
		hidePanel()
	end)
end

task.defer(bind)
