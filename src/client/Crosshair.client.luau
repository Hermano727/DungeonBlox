--[[
	Crosshair -- a small plus at the exact screen centre (where the locked mouse aims):

		    |
		  -- --
		    |

	Four thin ticks with a gap in the middle, bone white with a faint dark edge so it reads on
	both sky and stone. Shown only while the mouse is locked for aiming (MouseBehavior
	LockCenter): any menu, dialog or free cursor hides it, and so does a camera takeover
	(cutscenes, spectating, the enchant pan). Full-screen moments hide it with the rest of the
	HUD through HudHider, since it is an ordinary ScreenGui.

	On/off: the crosshair button in the quick-nav row under the minimap (RS/HudQuickNav, right
	of the settings gear). Saved like the Settings sliders: UpdatePlayerSettings("hud",
	"crosshair", 1|0), range in RS/SettingsRanges, read back through RS/SettingsStore.

	The Roblox arrow is a separate thing, handled by CursorIcon.client (hidden whenever the
	mouse is locked).

	Tuning: the constants below.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local TweenService = game:GetService("TweenService")

local CameraOverrideState = require(ReplicatedStorage:WaitForChild("CameraOverrideState"))
local QuickNav = require(ReplicatedStorage:WaitForChild("HudQuickNav"))
local SettingsStore = require(ReplicatedStorage:WaitForChild("SettingsStore"))

local player = Players.LocalPlayer

local COLOR = Color3.fromRGB(236, 230, 214)
local EDGE = Color3.fromRGB(10, 8, 8)
local TICK_LENGTH = 6  -- px
local TICK_WIDTH = 2   -- px
local GAP = 3          -- px from the centre to the start of each tick
local TRANSPARENCY = .1

local gui = Instance.new("ScreenGui")
gui.Name = "Crosshair"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true -- (0.5, 0.5) is then the true viewport centre, where LockCenter holds the mouse
gui.DisplayOrder = 5
gui.Parent = player:WaitForChild("PlayerGui")

local root = Instance.new("Frame")
root.Name = "Centre"
root.AnchorPoint = Vector2.new(.5, .5)
root.Position = UDim2.fromScale(.5, .5)
root.Size = UDim2.fromOffset(0, 0)
root.BackgroundTransparency = 1
root.Parent = gui

-- Draws the plus (four ticks around a gap) into `parent`, centred on it. Used twice: the real
-- crosshair and, smaller, the quick-nav button's icon.
local function drawPlus(parent, length, width, gap)
	local ticks = {}
	local reach = gap + length / 2
	for _, spec in ipairs({
		{ "Up", Vector2.new(0, -reach), false }, { "Down", Vector2.new(0, reach), false },
		{ "Left", Vector2.new(-reach, 0), true }, { "Right", Vector2.new(reach, 0), true },
	}) do
		local frame = Instance.new("Frame")
		frame.Name = spec[1]
		frame.AnchorPoint = Vector2.new(.5, .5)
		frame.Position = UDim2.new(.5, spec[2].X, .5, spec[2].Y)
		frame.Size = spec[3] and UDim2.fromOffset(length, width) or UDim2.fromOffset(width, length)
		frame.BackgroundColor3 = COLOR
		frame.BackgroundTransparency = TRANSPARENCY
		frame.BorderSizePixel = 0
		frame.ZIndex = parent.ZIndex + 1
		local stroke = Instance.new("UIStroke")
		stroke.Color = EDGE
		stroke.Transparency = .55
		stroke.Thickness = 1
		stroke.Parent = frame
		frame.Parent = parent
		table.insert(ticks, frame)
	end
	return ticks
end

drawPlus(root, TICK_LENGTH, TICK_WIDTH, GAP)

-- On/off, saved per player. Missing (never changed) = on. Loaded below, after the button exists.
local enabled = true

RunService.RenderStepped:Connect(function()
	local show = enabled
		and UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
		and not CameraOverrideState.IsActive()
	if root.Visible ~= show then root.Visible = show end
end)

---------------------------------------------------------------------------------------------
-- Quick-nav toggle (right of the settings gear; same plate and hover as the gear)

local OFF_TRANSPARENCY = .7 -- the button's plus when the crosshair is off

local button = Instance.new("TextButton")
button.Name = "CrosshairToggle"
button.Size = UDim2.fromOffset(QuickNav.BUTTON_SIZE, QuickNav.BUTTON_SIZE)
button.BackgroundColor3 = Color3.fromRGB(14, 13, 16)
button.BackgroundTransparency = .25
button.AutoButtonColor = false
button.Text = ""
button.ZIndex = 10
button.Parent = QuickNav.Slot("Crosshair", QuickNav.ORDER.Crosshair)
Instance.new("UICorner", button).CornerRadius = UDim.new(0, 5)
QuickNav.Tooltip(button, "Toggle Crosshair")

local iconScale = Instance.new("UIScale")
local icon = Instance.new("Frame")
icon.Name = "Icon"
icon.AnchorPoint = Vector2.new(.5, .5)
icon.Position = UDim2.fromScale(.5, .5)
icon.Size = UDim2.fromOffset(20, 20)
icon.BackgroundTransparency = 1
icon.ZIndex = 11
icon.Parent = button
iconScale.Parent = icon
local iconTicks = drawPlus(icon, 6, 2, 2)

local function paintButton()
	for _, t in ipairs(iconTicks) do
		t.BackgroundTransparency = enabled and TRANSPARENCY or OFF_TRANSPARENCY
		t.UIStroke.Transparency = enabled and .55 or .85
	end
end
paintButton()
task.spawn(function()
	local saved = SettingsStore.Get() -- one server round trip per session, shared (cached)
	local value = type(saved.hud) == "table" and tonumber(saved.hud.crosshair)
	if value ~= nil then enabled = value >= .5 end
	paintButton()
end)

local hoverIn = TweenInfo.new(.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
button.MouseEnter:Connect(function()
	TweenService:Create(iconScale, hoverIn, { Scale = 1.2 }):Play()
	TweenService:Create(button, hoverIn, { BackgroundTransparency = .05 }):Play()
end)
button.MouseLeave:Connect(function()
	TweenService:Create(iconScale, hoverIn, { Scale = 1 }):Play()
	TweenService:Create(button, hoverIn, { BackgroundTransparency = .25 }):Play()
end)

local updateSettings = ReplicatedStorage:WaitForChild("UpdatePlayerSettings")
button.Activated:Connect(function()
	enabled = not enabled
	paintButton()
	updateSettings:FireServer("hud", "crosshair", enabled and 1 or 0)
end)
