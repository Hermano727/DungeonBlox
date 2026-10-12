--[[
	MythicBroadcastClient -- the server-wide Mythic announcement (server: SSS/MythicBroadcast).

	Every Mythic drop anywhere on the server shows here for everyone: an ornate line at the top
	centre (a Mythic-orange rule opening out of a centre diamond, "<Player> has claimed" small
	above, the item name large below, its source under that) with a sting, plus a coloured system
	line in chat so there is a record to scroll back to. Announcements queue; one at a time.

	Sits below whatever HudTopCentre reserves (the elite pity plate) and is tagged OverMenus
	(HudHider.MarkOverlay) so it shows even with the Tab menu open.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local RunService = game:GetService("RunService")

local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local SfxService = require(ReplicatedStorage:WaitForChild("SfxService"))
local Types = require(ReplicatedStorage:WaitForChild("ProfileTypes"))
local HudTopCentre = require(ReplicatedStorage:WaitForChild("HudTopCentre"))
local HudHider = require(script.Parent:WaitForChild("HudHider"))

local player = Players.LocalPlayer
local MYTHIC = Types.GetRarityColor("Mythic")
local PALE = Color3.fromRGB(255, 232, 205)
local INK = Color3.fromRGB(18, 12, 10)

local SHOW_TIME = 5.5  -- seconds on screen
local OPEN_TIME = 0.6  -- the rule opening out of the diamond
local FADE_TIME = 0.7
local TOP_GAP = 70     -- px below HudTopCentre's reserved strip (clears the XP bar)
local WIDTH = 560

local gui = Instance.new("ScreenGui")
gui.Name = "MythicBroadcast"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 115
gui.Enabled = false
HudHider.MarkOverlay(gui) -- tag before parenting (see HudHider)
gui.Parent = player:WaitForChild("PlayerGui")

local root = Instance.new("Frame")
root.AnchorPoint = Vector2.new(0.5, 0)
root.Size = UDim2.fromOffset(WIDTH, 96)
root.BackgroundTransparency = 1
root.Parent = gui

local function label(name, y, height, color, font, size)
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.AnchorPoint = Vector2.new(0.5, 0)
	l.Position = UDim2.new(0.5, 0, 0, y)
	l.Size = UDim2.new(1, 0, 0, height)
	l.FontFace = font
	l.TextSize = size
	l.TextColor3 = color
	l.Text = ""
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = 2
	stroke.Parent = l
	l.Parent = root
	return l, stroke
end

local claimed, claimedStroke = label("Claimed", 0, 20, PALE, UIFonts.Serif, 17)
local itemName, itemStroke = label("Item", 40, 34, MYTHIC, UIFonts.SerifBold, 30)
local source, sourceStroke = label("Source", 76, 18, Color3.fromRGB(205, 180, 160), UIFonts.Serif, 14)

-- The rule: two halves opening from a centre diamond.
local function rule(anchorX)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(anchorX, 0.5)
	f.Position = UDim2.new(0.5, 0, 0, 30)
	f.Size = UDim2.fromOffset(0, 2)
	f.BorderSizePixel = 0
	f.BackgroundColor3 = MYTHIC
	local grad = Instance.new("UIGradient")
	grad.Transparency = NumberSequence.new(anchorX == 1 and 1 or 0, anchorX == 1 and 0 or 1)
	grad.Parent = f
	f.Parent = root
	return f
end
local ruleLeft, ruleRight = rule(1), rule(0)
local diamond = Instance.new("Frame")
diamond.AnchorPoint = Vector2.new(0.5, 0.5)
diamond.Position = UDim2.new(0.5, 0, 0, 30)
diamond.Size = UDim2.fromOffset(9, 9)
diamond.Rotation = 45
diamond.BorderSizePixel = 0
diamond.BackgroundColor3 = MYTHIC
diamond.Parent = root

local function place()
	root.Position = UDim2.new(0.5, 0, 0, HudTopCentre.Bottom() + TOP_GAP)
end
HudTopCentre.Changed:Connect(place)
place()

local queue = {}
local playing = false

local function setAlpha(a) -- 0 = shown, 1 = gone
	claimed.TextTransparency, claimedStroke.Transparency = a, a
	itemName.TextTransparency, itemStroke.Transparency = a, a
	source.TextTransparency, sourceStroke.Transparency = a, a
	ruleLeft.BackgroundTransparency, ruleRight.BackgroundTransparency = a, a
	diamond.BackgroundTransparency = a
end

local function playNext()
	local data = table.remove(queue, 1)
	if not data then
		playing = false
		gui.Enabled = false
		return
	end
	playing = true
	local mine = data.userId == player.UserId
	claimed.Text = mine and "You have claimed" or (tostring(data.playerName) .. " has claimed")
	itemName.Text = tostring(data.itemName)
	source.Text = data.source and ("from " .. tostring(data.source)) or ""
	gui.Enabled = true
	SfxService.PlayEffect("MythicBroadcast", { Volume = 0.8 })

	local started = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		local open = math.clamp(t / OPEN_TIME, 0, 1)
		open = 1 - (1 - open) ^ 3
		ruleLeft.Size = UDim2.fromOffset(WIDTH * 0.5 * open, 2)
		ruleRight.Size = UDim2.fromOffset(WIDTH * 0.5 * open, 2)
		diamond.Rotation = 45 + 90 * (1 - open)
		local fadeIn = 1 - math.clamp((t - OPEN_TIME * 0.4) / 0.4, 0, 1)
		local fadeOut = math.clamp((t - SHOW_TIME + FADE_TIME) / FADE_TIME, 0, 1)
		setAlpha(math.max(fadeIn, fadeOut))
		diamond.BackgroundTransparency = fadeOut
		itemName.TextSize = 30 + 3 * math.max(0, 1 - t / 0.5)
		if t >= SHOW_TIME then
			conn:Disconnect()
			playNext()
		end
	end)
end

-- A plain system line in chat, coloured (rich text; names are escaped).
local function escape(s)
	return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end
local function chatLine(data)
	local channels = TextChatService:FindFirstChild("TextChannels")
	local system = channels and channels:FindFirstChild("RBXSystem")
	if not system then return end
	local hex = MYTHIC:ToHex()
	local text = string.format('<font color="#%s">%s has claimed %s%s.</font>', hex, escape(data.playerName),
		escape(data.itemName), data.source and (" from " .. escape(data.source)) or "")
	pcall(function() system:DisplaySystemMessage(text) end)
end

local function bind(remote)
	remote.OnClientEvent:Connect(function(data)
		if type(data) ~= "table" then return end
		chatLine(data)
		table.insert(queue, data)
		if not playing then playNext() end
	end)
end
-- The server creates the remote at boot; bind whenever it appears, however late.
local GameEvents = ReplicatedStorage:WaitForChild("GameEvents")
local existing = GameEvents:FindFirstChild("MythicBroadcast")
if existing then
	bind(existing)
else
	local conn
	conn = GameEvents.ChildAdded:Connect(function(child)
		if child.Name == "MythicBroadcast" and child:IsA("RemoteEvent") then
			conn:Disconnect()
			bind(child)
		end
	end)
end
