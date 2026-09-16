--[[
	ShardEnterClient
	If we arrived on this server via a Shard Hop (TeleportData.viaShardHop),
	show a brief full-screen "Entering Shard..." overlay until the first
	DungeonProfilePush arrives (or a generous timeout elapses), so the player
	never sees a flash of an empty/default inventory while the destination
	server's ProfileService.Load session-lock retry loop is still
	waiting for the source server's lock to release or go stale.
	No-op entirely on a normal join (most common case -- bails out immediately).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local player = Players.LocalPlayer

local ok, teleportData = pcall(function()
	return TeleportService:GetLocalPlayerTeleportData()
end)
if not (ok and type(teleportData) == "table" and teleportData.viaShardHop == true) then
	return
end

local MAX_WAIT = 20

local gui = Instance.new("ScreenGui")
gui.Name = "ShardEnterOverlay"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1000
gui.Parent = player:WaitForChild("PlayerGui")

local bg = Instance.new("Frame")
bg.Size = UDim2.fromScale(1, 1)
bg.BackgroundColor3 = Color3.fromRGB(10, 8, 6)
bg.BorderSizePixel = 0
bg.Parent = gui

local label = Instance.new("TextLabel")
label.AnchorPoint = Vector2.new(0.5, 0.5)
label.Position = UDim2.fromScale(0.5, 0.5)
label.Size = UDim2.fromOffset(400, 40)
label.BackgroundTransparency = 1
label.Font = Enum.Font.GothamBold
label.TextSize = 20
label.TextColor3 = Color3.fromRGB(230, 220, 200)
label.Text = "Entering Shard..."
label.Parent = bg

local done = false
local function finish()
	if done then return end
	done = true
	if gui.Parent then
		gui:Destroy()
	end
end

local pushEvent = ReplicatedStorage:WaitForChild("DungeonProfilePush", 10)
if pushEvent then
	local conn
	conn = pushEvent.OnClientEvent:Connect(function()
		if conn then conn:Disconnect() end
		finish()
	end)
end

task.delay(MAX_WAIT, finish)
