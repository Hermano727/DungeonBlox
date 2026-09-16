--[[
	CenterFlashUI
	Small reusable center-screen flash message: fades in, holds briefly, fades out.
	One place owns the visual so passive server-pushed warnings (inventory full) and
	immediate action failures (drop/trash denied) share the same look instead of every
	caller hand-rolling its own banner. See CenterFlashClient.client.lua for the
	RemoteEvent listener that drives this for server-pushed warnings.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "CenterFlashGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 150
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local frame = Instance.new("Frame")
frame.Name = "FlashFrame"
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.Position = UDim2.new(0.5, 0, 0.3, 0)
frame.Size = UDim2.fromOffset(440, 54)
frame.BackgroundColor3 = Color3.fromRGB(16, 12, 10)
frame.BackgroundTransparency = 1
frame.BorderSizePixel = 0
frame.Parent = gui

local corner = Instance.new("UICorner", frame)
corner.CornerRadius = UDim.new(0, 8)

local stroke = Instance.new("UIStroke", frame)
stroke.Thickness = 1.5
stroke.Color = Color3.fromRGB(200, 70, 60)
stroke.Transparency = 1

local label = Instance.new("TextLabel")
label.Name = "FlashText"
label.Size = UDim2.new(1, -24, 1, 0)
label.Position = UDim2.new(0, 12, 0, 0)
label.BackgroundTransparency = 1
label.Font = Enum.Font.GothamBold
label.TextSize = 22
label.TextColor3 = Color3.fromRGB(235, 210, 200)
label.TextTransparency = 1
label.TextStrokeTransparency = 1
label.TextWrapped = true
label.Text = ""
label.Parent = frame

local FADE_IN = 0.18
local FADE_OUT = 0.35
local HOLD_TIME = 1.4

local CenterFlashUI = {}

-- Bumped on every Show() call; a queued fade-out only fires if it's still the most
-- recent call by the time its delay elapses, so two flashes in quick succession don't
-- fight over the frame's transparency (the older one's fade-out would otherwise hide
-- text the newer call just set).
local activeToken = 0

function CenterFlashUI.Show(text)
	if type(text) ~= "string" or text == "" then
		return
	end
	activeToken += 1
	local myToken = activeToken
	label.Text = text
	TweenService:Create(frame, TweenInfo.new(FADE_IN), { BackgroundTransparency = 0.25 }):Play()
	TweenService:Create(stroke, TweenInfo.new(FADE_IN), { Transparency = 0.3 }):Play()
	TweenService:Create(label, TweenInfo.new(FADE_IN), { TextTransparency = 0, TextStrokeTransparency = 0.5 }):Play()
	task.delay(FADE_IN + HOLD_TIME, function()
		if activeToken ~= myToken then
			return
		end
		TweenService:Create(frame, TweenInfo.new(FADE_OUT), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(stroke, TweenInfo.new(FADE_OUT), { Transparency = 1 }):Play()
		TweenService:Create(label, TweenInfo.new(FADE_OUT), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
end

return CenterFlashUI
