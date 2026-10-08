--[[
	BuffHudClient
	Active buffs down the left middle of the screen (2026-10-03), the way some Minecraft mods
	list potion effects: an icon, the buff's name and strength, and the time left. The last ten
	seconds blink.

	Data: BuffService's GameEvents/ActiveBuffsSync (fired on every apply and expiry) and
	RequestActiveBuffs at start. Buffs of one type are merged: amounts add up (as BuffService
	applies them), the time shown is the longest left. Names, icons and colours: RS/BuffDisplay.
	Until the icons are uploaded each row shows a coloured square instead.
	Hides behind full-screen menus on its own (HudHider hides every plain ScreenGui).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuffDisplay = require(ReplicatedStorage:WaitForChild("BuffDisplay"))
local HudBarStyle = require(ReplicatedStorage:WaitForChild("HudBarStyle"))
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))

local player = Players.LocalPlayer
local gameEvents = ReplicatedStorage:WaitForChild("GameEvents")
local ActiveBuffsSync = gameEvents:WaitForChild("ActiveBuffsSync")
local RequestActiveBuffs = gameEvents:WaitForChild("RequestActiveBuffs")

local ROW_H = 36
local ICON = 30
local BLINK_UNDER = 10 -- seconds

local gui = Instance.new("ScreenGui")
gui.Name = "BuffHud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 30
gui.Parent = player:WaitForChild("PlayerGui")

local list = Instance.new("Frame")
list.Name = "Buffs"
list:SetAttribute("TutorialTarget", "hud_buffs") -- the tutorial points at it
list.AnchorPoint = Vector2.new(0, 0.5)
list.Position = UDim2.new(0, 16, 0.5, 0)
list.Size = UDim2.fromOffset(220, 0)
list.AutomaticSize = Enum.AutomaticSize.Y
list.BackgroundTransparency = 1
list.Parent = gui
local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 6)
layout.Parent = list

local function text(parent, size, color)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.FontFace = UIFonts.HUDLabel
	t.TextSize = size
	t.TextColor3 = color
	t.TextStrokeTransparency = 0.35
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.Parent = parent
	return t
end

local rows = {} -- [type] = { frame, nameText, timeText, expires }

local function newRow(buffType)
	local spec = BuffDisplay[buffType]
	local color = spec and spec.color or HudBarStyle.BONE
	local frame = Instance.new("Frame")
	frame.Name = buffType
	frame.Size = UDim2.new(1, 0, 0, ROW_H)
	frame.BackgroundTransparency = 1
	frame.Parent = list

	local plate = Instance.new("Frame")
	plate.Size = UDim2.fromOffset(ICON + 6, ICON + 6)
	plate.Position = UDim2.fromOffset(0, (ROW_H - ICON - 6) / 2)
	plate.BackgroundColor3 = HudBarStyle.TROUGH
	plate.BackgroundTransparency = HudBarStyle.TROUGH_TRANSPARENCY
	plate.Parent = frame
	Instance.new("UICorner", plate).CornerRadius = UDim.new(0, 4)
	local ring = Instance.new("UIStroke")
	ring.Color = HudBarStyle.BRONZE
	ring.Transparency = 0.2
	ring.Parent = plate

	local icon = spec and spec.icon or ""
	if icon ~= "" then
		local image = Instance.new("ImageLabel")
		image.BackgroundTransparency = 1
		image.Image = icon
		image.ScaleType = Enum.ScaleType.Fit
		image.Position = UDim2.fromOffset(3, 3)
		image.Size = UDim2.fromOffset(ICON, ICON)
		image.Parent = plate
	else
		local swatch = Instance.new("Frame")
		swatch.AnchorPoint = Vector2.new(0.5, 0.5)
		swatch.Position = UDim2.fromScale(0.5, 0.5)
		swatch.Size = UDim2.fromScale(0.5, 0.5)
		swatch.BackgroundColor3 = color
		swatch.Rotation = 45
		swatch.Parent = plate
	end

	local nameText = text(frame, 15, color)
	nameText.Position = UDim2.fromOffset(ICON + 14, 2)
	nameText.Size = UDim2.new(1, -(ICON + 14), 0, 17)
	local timeText = text(frame, 13, HudBarStyle.BONE)
	timeText.Position = UDim2.fromOffset(ICON + 14, 19)
	timeText.Size = UDim2.new(1, -(ICON + 14), 0, 15)
	return { frame = frame, nameText = nameText, timeText = timeText, plate = plate, expires = 0 }
end

local function clock(seconds)
	seconds = math.max(0, math.ceil(seconds))
	return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

local function apply(buffs)
	if type(buffs) ~= "table" then return end
	-- Merge by type.
	local merged = {}
	for _, b in ipairs(buffs) do
		if type(b) == "table" and type(b.type) == "string" then
			local m = merged[b.type] or { amount = 0, remaining = 0 }
			m.amount += tonumber(b.amount) or 0
			m.remaining = math.max(m.remaining, tonumber(b.remaining) or 0)
			merged[b.type] = m
		end
	end
	for buffType, row in pairs(rows) do
		if not merged[buffType] then
			row.frame:Destroy()
			rows[buffType] = nil
		end
	end
	local order = {}
	for buffType in pairs(merged) do table.insert(order, buffType) end
	table.sort(order)
	for i, buffType in ipairs(order) do
		local m = merged[buffType]
		local row = rows[buffType] or newRow(buffType)
		rows[buffType] = row
		row.frame.LayoutOrder = i
		row.expires = os.clock() + m.remaining
		local spec = BuffDisplay[buffType]
		local amount = math.floor(m.amount + 0.5)
		row.nameText.Text = spec and ("%s  +%d%s"):format(spec.name, amount, spec.unit) or ("%s  +%d"):format(buffType, amount)
	end
end

ActiveBuffsSync.OnClientEvent:Connect(apply)
task.spawn(function()
	local ok, buffs = pcall(RequestActiveBuffs.InvokeServer, RequestActiveBuffs)
	if ok then apply(buffs) end
end)

-- Count down. The server's expiry sync removes the row; this only draws the time.
task.spawn(function()
	while true do
		local now = os.clock()
		for _, row in pairs(rows) do
			local left = row.expires - now
			row.timeText.Text = clock(left)
			local blink = left < BLINK_UNDER and (math.floor(now * 3) % 2 == 0)
			row.frame.Visible = left > -1
			row.plate.BackgroundTransparency = blink and 0.85 or HudBarStyle.TROUGH_TRANSPARENCY
			row.timeText.TextTransparency = blink and 0.5 or 0
		end
		task.wait(0.15)
	end
end)
