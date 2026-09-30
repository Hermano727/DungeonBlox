--[[
	CombatTimerClient
	The combat-tag readout: [combat icon] Combat: 12.34s, ticking down while you're flagged.

	Lives at the very bottom of the bottom-left HUD stack (RS/HudBottomLeftStack, ORDER.Combat),
	the lowest and most fixed spot on screen, because being tagged matters for PvP and for
	regen. Other bottom-left readouts (the dungeon timer, ...) stack above it. Was a small
	top-right chip until 2026-09-26; before that top-center, where it overlapped the Combat
	XP bar.

	Every fresh hit (the server re-sends "combat" with a new duration) flashes the border so
	re-tagging reads. When the tag drops it shows "Regenerating" in blue for 2s, then leaves.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")

local Stack    = require(ReplicatedStorage:WaitForChild("HudBottomLeftStack"))
local UIFonts  = require(ReplicatedStorage:WaitForChild("UIFonts"))
local HudIcons = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Icons"):WaitForChild("Hud"):WaitForChild("HudIcons"))

local _ = Players.LocalPlayer

local COMBAT_TEXT   = Color3.fromRGB(255, 190, 180)
local COMBAT_STROKE = Color3.fromRGB(200, 55, 55)
local SAFE_TEXT     = Color3.fromRGB(160, 210, 255)
local SAFE_STROKE   = Color3.fromRGB(80, 160, 220)
local FADE_TIME     = 0.3
local SAFE_LINGER   = 2

local slot = Stack.Slot("CombatTimer", Stack.ORDER.Combat)
local pill = Stack.Pill(slot, {
	height = 38,
	iconSize = 28,
	textSize = 20,
	textWidth = 150, -- fixed, so the ticking number doesn't make the pill jitter
	font = UIFonts.HUDLabel,
	image = HudIcons.COMBAT,
	strokeColor = COMBAT_STROKE,
	textColor = COMBAT_TEXT,
})
pill.stroke.Thickness = 2
pill.frame.BackgroundTransparency = .25

local BASE_BG = pill.frame.BackgroundTransparency
local BASE_STROKE = 0.1

local timeLeft = 0
local inCombat = false
local shownSerial = 0

local function tween(inst, props)
	TweenService:Create(inst, TweenInfo.new(FADE_TIME), props):Play()
end

local function setVisible(v)
	shownSerial += 1
	local serial = shownSerial
	if v then
		slot.Visible = true
		tween(pill.frame, { BackgroundTransparency = BASE_BG })
		tween(pill.stroke, { Transparency = BASE_STROKE })
		tween(pill.label, { TextTransparency = 0, TextStrokeTransparency = .6 })
		tween(pill.icon, { ImageTransparency = 0 })
	else
		tween(pill.frame, { BackgroundTransparency = 1 })
		tween(pill.stroke, { Transparency = 1 })
		tween(pill.label, { TextTransparency = 1, TextStrokeTransparency = 1 })
		tween(pill.icon, { ImageTransparency = 1 })
		-- Collapse out of the stack once faded, so the readouts above slide down.
		task.delay(FADE_TIME, function()
			if shownSerial == serial then slot.Visible = false end
		end)
	end
end

-- Border flash on every (re)tag: brighter and thicker, easing back.
local function flash()
	pill.stroke.Thickness = 4
	pill.stroke.Color = Color3.fromRGB(255, 110, 100)
	TweenService:Create(pill.stroke, TweenInfo.new(.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Thickness = 2, Color = COMBAT_STROKE,
	}):Play()
end

local function showCombatStyle()
	pill.label.TextColor3 = COMBAT_TEXT
	pill.icon.ImageColor3 = Color3.new(1, 1, 1)
	pill.stroke.Color = COMBAT_STROKE
end

-- Start hidden.
pill.frame.BackgroundTransparency = 1
pill.stroke.Transparency = 1
pill.label.TextTransparency = 1
pill.label.TextStrokeTransparency = 1
pill.icon.ImageTransparency = 1

local ev = ReplicatedStorage:WaitForChild("CombatStateEvent", 30)
if ev then
	ev.OnClientEvent:Connect(function(state, secs)
		if state == "combat" then
			timeLeft = tonumber(secs) or 0
			if not inCombat then
				inCombat = true
				showCombatStyle()
				setVisible(true)
			end
			flash()
		elseif state == "safe" then
			timeLeft = 0
			inCombat = false
			pill.stroke.Color = SAFE_STROKE
			pill.icon.ImageColor3 = SAFE_TEXT
			pill.label.TextColor3 = SAFE_TEXT
			pill.label.Text = "Regenerating"
			task.delay(SAFE_LINGER, function()
				if not inCombat then setVisible(false) end
			end)
		end
	end)
end

-- Client-side countdown tick (display only; the server owns the real tag).
RunService.Heartbeat:Connect(function(dt)
	if not inCombat then return end
	timeLeft = math.max(0, timeLeft - dt)
	pill.label.Text = string.format("Combat: %.2fs", timeLeft)
end)

print("[CombatTimerClient] ready")
