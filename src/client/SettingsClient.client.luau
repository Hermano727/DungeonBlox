--[[
	SettingsClient
	Gear icon (top-right) that opens a Volume panel.
	Music volume is live; SFX and VFX are placeholder sliders pending those systems.
]]

local Players          = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local SoundService     = game:GetService("SoundService")

local VolumeSettings = require(ReplicatedStorage:WaitForChild("VolumeSettings"))
local CursorManager  = require(ReplicatedStorage:WaitForChild("CursorManager"))

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

----------------------------------------------------------------------
-- Root ScreenGui
----------------------------------------------------------------------

local sg = Instance.new("ScreenGui")
sg.Name           = "SettingsGui"
sg.ResetOnSpawn   = false
sg.IgnoreGuiInset = true
sg.DisplayOrder   = 250
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.Parent         = playerGui

----------------------------------------------------------------------
-- Gear button
----------------------------------------------------------------------

local gearBtn = Instance.new("TextButton")
gearBtn.Name                 = "GearButton"
gearBtn.AnchorPoint          = Vector2.new(1, 0)
gearBtn.Position             = UDim2.new(1, -14, 0, 14)
gearBtn.Size                 = UDim2.fromOffset(30, 30)
gearBtn.BackgroundTransparency = 1
gearBtn.Text                 = "⚙"
gearBtn.TextColor3           = Color3.fromRGB(210, 195, 175)
gearBtn.TextTransparency     = 0
gearBtn.TextSize             = 22
gearBtn.Font                 = Enum.Font.GothamBold
gearBtn.ZIndex               = 10
gearBtn.Parent               = sg
local gearStroke = Instance.new("UIStroke", gearBtn)
gearStroke.Thickness    = 1.5
gearStroke.Color        = Color3.fromRGB(110, 98, 82)
gearStroke.Transparency = 0.35

----------------------------------------------------------------------
-- Settings panel
----------------------------------------------------------------------

local PANEL_W = 252
local PANEL_H = 160

local panel = Instance.new("Frame")
panel.Name                   = "SettingsPanel"
panel.AnchorPoint            = Vector2.new(1, 0)
panel.Position               = UDim2.new(1, -14, 0, 52)
panel.Size                   = UDim2.fromOffset(PANEL_W, PANEL_H)
panel.BackgroundColor3       = Color3.fromRGB(16, 14, 12)
panel.BackgroundTransparency = 0.1
panel.BorderSizePixel        = 0
panel.Visible                = false
panel.ZIndex                 = 9
panel.Parent                 = sg
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)
local panelStroke = Instance.new("UIStroke", panel)
panelStroke.Thickness    = 1
panelStroke.Color        = Color3.fromRGB(70, 60, 50)
panelStroke.Transparency = 0.3

-- Section header
local header = Instance.new("TextLabel")
header.BackgroundTransparency = 1
header.Position    = UDim2.fromOffset(14, 10)
header.Size        = UDim2.fromOffset(PANEL_W - 28, 18)
header.Font        = Enum.Font.GothamBold
header.TextSize    = 12
header.TextColor3  = Color3.fromRGB(190, 175, 150)
header.TextXAlignment = Enum.TextXAlignment.Left
header.Text        = "VOLUME"
header.Parent      = panel

local divider = Instance.new("Frame")
divider.Position         = UDim2.fromOffset(14, 31)
divider.Size             = UDim2.new(1, -28, 0, 1)
divider.BackgroundColor3 = Color3.fromRGB(70, 60, 50)
divider.BackgroundTransparency = 0.4
divider.BorderSizePixel  = 0
divider.Parent           = panel

----------------------------------------------------------------------
-- Slider factory
----------------------------------------------------------------------

local LABEL_W  = 50
local TRACK_GAP = 8
local VAL_W    = 28
local TRACK_H  = 4
local KNOB_D   = 13
local ROW_H    = 36
local trackW   = PANEL_W - 28 - LABEL_W - TRACK_GAP - VAL_W - 8

local function makeSlider(label, yOff, initVal, enabled, onChange)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(14, yOff)
	row.Size     = UDim2.new(1, -28, 0, ROW_H)
	row.Parent   = panel

	local dim = not enabled

	local rowLbl = Instance.new("TextLabel")
	rowLbl.BackgroundTransparency = 1
	rowLbl.Position    = UDim2.fromOffset(0, (ROW_H - 16) / 2)
	rowLbl.Size        = UDim2.fromOffset(LABEL_W, 16)
	rowLbl.Font        = Enum.Font.GothamMedium
	rowLbl.TextSize    = 12
	rowLbl.TextColor3  = dim and Color3.fromRGB(100, 92, 82) or Color3.fromRGB(175, 160, 140)
	rowLbl.TextXAlignment = Enum.TextXAlignment.Left
	rowLbl.Text        = label
	rowLbl.Parent      = row

	local trackBg = Instance.new("Frame")
	trackBg.AnchorPoint      = Vector2.new(0, 0.5)
	trackBg.Position         = UDim2.new(0, LABEL_W + TRACK_GAP, 0.5, 0)
	trackBg.Size             = UDim2.fromOffset(trackW, TRACK_H)
	trackBg.BackgroundColor3 = dim and Color3.fromRGB(36, 32, 28) or Color3.fromRGB(55, 48, 42)
	trackBg.BorderSizePixel  = 0
	trackBg.Parent           = row
	Instance.new("UICorner", trackBg).CornerRadius = UDim.new(0, 2)

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = dim and Color3.fromRGB(72, 64, 56) or Color3.fromRGB(175, 140, 80)
	fill.BorderSizePixel  = 0
	fill.Size             = UDim2.new(initVal, 0, 1, 0)
	fill.Parent           = trackBg
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 2)

	local knob = Instance.new("Frame")
	knob.AnchorPoint      = Vector2.new(0.5, 0.5)
	knob.Position         = UDim2.new(initVal, 0, 0.5, 0)
	knob.Size             = UDim2.fromOffset(KNOB_D, KNOB_D)
	knob.BackgroundColor3 = dim and Color3.fromRGB(85, 76, 68) or Color3.fromRGB(215, 175, 105)
	knob.BorderSizePixel  = 0
	knob.ZIndex           = 2
	knob.Parent           = trackBg
	Instance.new("UICorner", knob).CornerRadius = UDim.new(0.5, 0)

	local valLbl = Instance.new("TextLabel")
	valLbl.BackgroundTransparency = 1
	valLbl.AnchorPoint    = Vector2.new(0, 0.5)
	valLbl.Position       = UDim2.new(0, LABEL_W + TRACK_GAP + trackW + 6, 0.5, 0)
	valLbl.Size           = UDim2.fromOffset(VAL_W, 16)
	valLbl.Font           = Enum.Font.GothamMedium
	valLbl.TextSize       = 11
	valLbl.TextColor3     = dim and Color3.fromRGB(85, 76, 68) or Color3.fromRGB(140, 128, 108)
	valLbl.TextXAlignment = Enum.TextXAlignment.Right
	valLbl.Text           = tostring(math.round(initVal * 100))
	valLbl.Parent         = row

	if not enabled then return end -- TODO sliders: drag not wired

	local dragging = false

	local function applyT(absX)
		local tPos  = trackBg.AbsolutePosition.X
		local tSize = trackBg.AbsoluteSize.X
		if tSize == 0 then return end
		local t = math.clamp((absX - tPos) / tSize, 0, 1)
		fill.Size     = UDim2.new(t, 0, 1, 0)
		knob.Position = UDim2.new(t, 0, 0.5, 0)
		valLbl.Text   = tostring(math.round(t * 100))
		onChange(t)
	end

	trackBg.InputBegan:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1
			or inp.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			applyT(inp.Position.X)
		end
	end)
	knob.InputBegan:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1
			or inp.UserInputType == Enum.UserInputType.Touch then
			dragging = true
		end
	end)
	UserInputService.InputChanged:Connect(function(inp)
		if not dragging then return end
		if inp.UserInputType == Enum.UserInputType.MouseMovement
			or inp.UserInputType == Enum.UserInputType.Touch then
			applyT(inp.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1
			or inp.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

----------------------------------------------------------------------
-- Sliders
----------------------------------------------------------------------

makeSlider("Music", 40, VolumeSettings.music, true, function(t)
	VolumeSettings.music = t
	local sound = SoundService:FindFirstChild("ZoneMusic")
	if sound and sound.IsPlaying then
		sound.Volume = t
	end
end)

local movementSfxGroup = SoundService:WaitForChild("Main"):WaitForChild("Character")

makeSlider("SFX", 40 + ROW_H, VolumeSettings.sfx, true, function(t)
	VolumeSettings.sfx = t
	movementSfxGroup.Volume = t
end)

makeSlider("VFX", 40 + ROW_H * 2, VolumeSettings.vfx, false, function(_t)
	-- TODO: wire to VFX system
end)

----------------------------------------------------------------------
-- Open / close
----------------------------------------------------------------------

-- Invisible full-screen click-catcher sits behind the panel; clicking it
-- anywhere outside the panel closes the menu.
local backdrop = Instance.new("TextButton")
backdrop.Name                 = "Backdrop"
backdrop.Size                 = UDim2.new(1, 0, 1, 0)
backdrop.BackgroundTransparency = 1
backdrop.Text                 = ""
backdrop.ZIndex               = 8
backdrop.Visible              = false
backdrop.Parent               = sg

local panelOpen = false
local openTI  = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local closeTI = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function setPanelOpen(open)
	panelOpen = open
	CursorManager.setFree("settings", open)
	if open then
		backdrop.Visible             = true
		panel.BackgroundTransparency = 0.7
		panel.Visible                = true
		TweenService:Create(panel,   openTI, { BackgroundTransparency = 0.1 }):Play()
		TweenService:Create(gearBtn, openTI, { TextTransparency = 0 }):Play()
	else
		backdrop.Visible = false
		local t = TweenService:Create(panel, closeTI, { BackgroundTransparency = 0.7 })
		t:Play()
		t.Completed:Connect(function()
			if not panelOpen then panel.Visible = false end
		end)
		TweenService:Create(gearBtn, closeTI, { TextTransparency = 0.2 }):Play()
	end
end

backdrop.Activated:Connect(function()
	setPanelOpen(false)
end)

gearBtn.Activated:Connect(function()
	setPanelOpen(not panelOpen)
end)