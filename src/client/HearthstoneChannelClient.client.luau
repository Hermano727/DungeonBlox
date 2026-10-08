--[[
	HearthstoneChannelClient -- the cast bar while your hearthstone channels.

	The server (SSS/HearthstoneService.StartChannel) runs the channel and publishes it as two
	attributes on your Player: HearthChannelEnd (workspace:GetServerTimeNow() it completes at)
	and HearthChannelLength (seconds); both clear when it ends, completed or broken. This only
	draws them: a bronze plate in the middle of the screen, just under the crosshair (a channel
	is the thing you're doing right now), with the countdown and a filling bar. Out of combat
	only, Lawful 10 / Neutral 20 / Chaotic 30 s (3 s in the tutorial); moving or entering combat
	cancels it (the server decides and flashes why).

	Art: RS/Assets/Images/JournalUI nav_plaque (the plate) and bar_trough (the track).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local JournalUI = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images"):WaitForChild("JournalUI"))

local player = Players.LocalPlayer

local WIDTH, HEIGHT = 380, 74
local BELOW_CENTRE = 90 -- px under the screen's centre, clear of the crosshair
local FILL = Color3.fromRGB(214, 172, 84)

local function slice(target, key)
	local art = JournalUI[key]
	if type(art) == "table" and art.Image ~= "" then
		target.Image = art.Image
		if art.SliceCenter then
			target.ScaleType = Enum.ScaleType.Slice
			target.SliceCenter = art.SliceCenter
			target.SliceScale = art.SliceScale or 1
		end
		return true
	end
	return false
end

local gui = Instance.new("ScreenGui")
gui.Name = "HearthstoneChannel"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 140
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local plate = Instance.new("ImageLabel")
plate.Name = "Plate"
plate.AnchorPoint = Vector2.new(0.5, 0)
plate.Position = UDim2.new(0.5, 0, 0.5, BELOW_CENTRE)
plate.Size = UDim2.fromOffset(WIDTH, HEIGHT)
plate.BackgroundColor3 = Color3.fromRGB(22, 16, 11)
plate.BackgroundTransparency = slice(plate, "nav_plaque") and 1 or 0.1
plate.Parent = gui

local label = Instance.new("TextLabel")
label.Name = "Label"
label.BackgroundTransparency = 1
label.Position = UDim2.fromOffset(0, 8)
label.Size = UDim2.new(1, 0, 0, 22)
label.FontFace = UIFonts.SerifBold
label.TextSize = 18
label.TextColor3 = Color3.fromRGB(240, 220, 172)
label.TextStrokeTransparency = 0.6
label.Text = "Hearthstone"
label.Parent = plate

local track = Instance.new("ImageLabel")
track.Name = "Track"
track.AnchorPoint = Vector2.new(0.5, 0)
track.Position = UDim2.new(0.5, 0, 0, 36)
track.Size = UDim2.new(1, -56, 0, 16)
track.BackgroundColor3 = Color3.fromRGB(20, 15, 10)
track.BackgroundTransparency = slice(track, "bar_trough") and 1 or 0
track.Parent = plate

local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Position = UDim2.fromOffset(4, 4)
fill.Size = UDim2.new(0, 0, 1, -8)
fill.BackgroundColor3 = FILL
fill.BorderSizePixel = 0
fill.Parent = track
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 3)
corner.Parent = fill

local renderConn

local function stop()
	if renderConn then renderConn:Disconnect(); renderConn = nil end
	gui.Enabled = false
end

local function refresh()
	local endsAt = player:GetAttribute("HearthChannelEnd")
	local length = player:GetAttribute("HearthChannelLength")
	if type(endsAt) ~= "number" or type(length) ~= "number" or length <= 0 then
		stop()
		return
	end
	gui.Enabled = true
	if renderConn then return end
	renderConn = RunService.RenderStepped:Connect(function()
		local left = math.max(0, endsAt - workspace:GetServerTimeNow())
		local done = 1 - left / length
		fill.Size = UDim2.new(math.clamp(done, 0, 1), -8 * math.clamp(done, 0, 1), 1, -8)
		label.Text = ("Hearthstone  %.1fs"):format(left)
		endsAt = player:GetAttribute("HearthChannelEnd") or endsAt
	end)
end

player:GetAttributeChangedSignal("HearthChannelEnd"):Connect(refresh)
player:GetAttributeChangedSignal("HearthChannelLength"):Connect(refresh)
refresh()
