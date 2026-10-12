--[[
	DevMenu/MythicForce -- the "boss Mythic roll" button (Normal / Force win / Force loss), shared by
	the Mythic and Dungeon tabs. Server-held (DevMythicForce remote -> the DevMythicForce player
	attribute, honoured for DevRoster players only by DungeonBossLootService), so both tabs'
	buttons read the same attribute and stay in step.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClearConfig = require(ReplicatedStorage:WaitForChild("DungeonClearConfig"))

local MODES = { { nil, "Normal (real odds)" }, { "win", "Force win" }, { "loss", "Force loss" } }
local ATTR = ClearConfig.MYTHIC_FORCE_ATTR

local MythicForce = {}

-- Adds a heading and the cycling button to `parent` at (x, y); returns the button.
function MythicForce.Build(ctx, parent, x, y, width)
	local player = Players.LocalPlayer
	ctx.lbl(parent, "BOSS MYTHIC ROLL", x, y, width, 16, 12, ctx.acc, true)
	local button = ctx.mkB(parent, "", x, y + 18, width, 28)

	local function show()
		local mode = player:GetAttribute(ATTR)
		for _, m in ipairs(MODES) do
			if m[1] == mode then button.Text = m[2] end
		end
	end

	button.Activated:Connect(function()
		local rf = ctx.GE and ctx.GE:FindFirstChild("DevMythicForce")
		if not rf then ctx.status("DevMythicForce remote missing", true) return end
		local current = player:GetAttribute(ATTR)
		local nextIndex = 1
		for i, m in ipairs(MODES) do
			if m[1] == current then nextIndex = i % #MODES + 1 end
		end
		local ok, result = pcall(function() return rf:InvokeServer(MODES[nextIndex][1]) end)
		if not ok or type(result) ~= "table" or not result.ok then
			ctx.status("Mythic force failed: " .. tostring((type(result) == "table" and result.error) or result), true)
			return
		end
		ctx.status("Boss Mythic roll: " .. MODES[nextIndex][2])
	end)

	local conn = player:GetAttributeChangedSignal(ATTR):Connect(show)
	button.Destroying:Connect(function() conn:Disconnect() end)
	show()
	return button
end

return MythicForce
