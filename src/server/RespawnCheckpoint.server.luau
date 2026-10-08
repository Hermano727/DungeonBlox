--[[
	RespawnCheckpoint (server)

	A respawn override for the tutorial: while a player's tutorial is active (server-side flag,
	ScriptedRigs.TutorialActive), and server code has set their `RespawnAt` attribute (a
	CFrame or Vector3, e.g. the next camp), they come back to life there instead of at the
	world spawn. It's a player attribute set only by the server; outside the tutorial it's
	ignored and cleared.
]]

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local ScriptedRigs = require(ServerScriptService:WaitForChild("ScriptedRigs"))

local ATTRIBUTE = "RespawnAt"

local function onCharacter(player, character)
	local spot = player:GetAttribute(ATTRIBUTE)
	if spot == nil then return end
	if not ScriptedRigs.TutorialActive(player) then
		player:SetAttribute(ATTRIBUTE, nil)
		return
	end
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root then return end
	task.wait() -- after the engine's own spawn placement
	local at = typeof(spot) == "CFrame" and spot or (typeof(spot) == "Vector3" and CFrame.new(spot)) or nil
	if at then character:PivotTo(at + Vector3.new(0, 3, 0)) end
end

local function watch(player)
	player.CharacterAdded:Connect(function(character) onCharacter(player, character) end)
end

for _, player in ipairs(Players:GetPlayers()) do watch(player) end
Players.PlayerAdded:Connect(watch)
