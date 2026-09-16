--[[
	CombatTimerClient
	Shows a small combat indicator in the screen's top-right corner (2026-09-13 --
	was top-center, which overlapped the Combat XP bar).
	  Sword icon + countdown while in combat.
	  Fades out when safe. Shield icon pulses when regen activates.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Build GUI
local gui = Instance.new("ScreenGui")
gui.Name           = "CombatTimerGui"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.DisplayOrder   = 111
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled        = true
gui.Parent         = playerGui

local frame = Instance.new("Frame", gui)
frame.Name             = "CombatFrame"
-- Moved to the top-right corner (2026-09-13, per direct request): was top-center,
-- overlapping the Combat XP bar/orb-burst zone. Top-right instead of top-left since
-- Roblox's own unhideable core UI buttons live top-left. This is ambient status info
-- ("are you flagged, will you regen soon"), not something actively tracked mid-fight
-- like HP/energy, so it doesn't need to compete with either of those busier areas --
-- same 0.08 vertical offset as before, just anchored/offset from the right edge now.
frame.AnchorPoint      = Vector2.new(1, 0)
frame.Position         = UDim2.new(1, -16, 0.08, 0)
frame.Size             = UDim2.fromOffset(160, 22)
frame.BackgroundTransparency = 1
frame.BorderSizePixel  = 0

local bg = Instance.new("Frame", frame)
bg.Size                  = UDim2.new(1, 0, 1, 0)
bg.BackgroundColor3      = Color3.fromRGB(14, 10, 10)
bg.BackgroundTransparency = 0.35
bg.BorderSizePixel       = 0
Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 6)
local bgStroke = Instance.new("UIStroke", bg)
bgStroke.Thickness   = 1
bgStroke.Color       = Color3.fromRGB(180, 60, 60)
bgStroke.Transparency = 0.5

local icon = Instance.new("TextLabel", frame)
icon.Size                  = UDim2.fromOffset(18, 22)
icon.Position              = UDim2.new(0, 4, 0, 0)
icon.BackgroundTransparency = 1
icon.Font                  = Enum.Font.GothamBold
icon.TextSize              = 13
icon.TextColor3            = Color3.fromRGB(220, 80, 80)
icon.Text                  = "\xe2\x9a\94"  -- ⚔

local timerLabel = Instance.new("TextLabel", frame)
timerLabel.Size                  = UDim2.new(1, -26, 1, 0)
timerLabel.Position              = UDim2.new(0, 24, 0, 0)
timerLabel.BackgroundTransparency = 1
timerLabel.Font                  = Enum.Font.GothamMedium
timerLabel.TextSize              = 12
timerLabel.TextColor3            = Color3.fromRGB(220, 180, 180)
timerLabel.TextXAlignment        = Enum.TextXAlignment.Left
timerLabel.Text                  = "In Combat"

-- State
local timeLeft   = 0
local inCombat   = false
local FADE_TIME  = 0.4

local function setVisible(v)
	local targetAlpha = v and 0 or 1
	TweenService:Create(bg, TweenInfo.new(FADE_TIME), { BackgroundTransparency = v and 0.35 or 1 }):Play()
	TweenService:Create(icon, TweenInfo.new(FADE_TIME), { TextTransparency = targetAlpha }):Play()
	TweenService:Create(timerLabel, TweenInfo.new(FADE_TIME), { TextTransparency = targetAlpha }):Play()
	TweenService:Create(bgStroke, TweenInfo.new(FADE_TIME), { Transparency = v and 0.5 or 1 }):Play()
end

setVisible(false)

-- Listen for server events
local ev = ReplicatedStorage:WaitForChild("CombatStateEvent", 30)
if ev then
	ev.OnClientEvent:Connect(function(state, secs)
		if state == "combat" then
			timeLeft = secs
			if not inCombat then
				inCombat = true
				setVisible(true)
				bgStroke.Color = Color3.fromRGB(180, 60, 60)
				icon.Text = "\xe2\x9a\94"  -- ⚔
				icon.TextColor3 = Color3.fromRGB(220, 80, 80)
			end
		elseif state == "safe" then
			timeLeft = 0
			inCombat = false
			-- Briefly show shield icon to signal regen kicked in
			bgStroke.Color = Color3.fromRGB(80, 160, 220)
			icon.Text = "\xf0\x9f\x9b\xa1"  -- 🛡
			icon.TextColor3 = Color3.fromRGB(100, 190, 255)
			timerLabel.Text = "Regenerating"
			task.delay(2, function()
				if not inCombat then
					setVisible(false)
				end
			end)
		end
	end)
end

-- Client-side countdown tick
RunService.Heartbeat:Connect(function(dt)
	if not inCombat then return end
	timeLeft = math.max(0, timeLeft - dt)
	timerLabel.Text = string.format("Combat  %.1fs", timeLeft)
end)

print("[CombatTimerClient] ready")