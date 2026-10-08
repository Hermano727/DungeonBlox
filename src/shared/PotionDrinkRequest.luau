-- Client request coordinator shared by O and the held potion. One press can wait
-- for the preloaded animation, but never queues another drink behind an active one.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Action = require(RS:WaitForChild("PotionAction"))
local Config = require(RS:WaitForChild("PotionDrinkConfig"))
local InteractionLock = require(RS:WaitForChild("InteractionLock"))
local player = Players.LocalPlayer
local Request = {Feedback = Instance.new("BindableEvent")}
local pending = false
local serial = 0

local function finish()
	serial += 1
	pending = false
end

function Request.Drink(itemUuid)
	if pending then return end
	local character = player.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	if Action.IsLocked(character) or Action.IsCoolingDown(character) then Request.Feedback:Fire("drinking"); return end
	if InteractionLock.IsLocked() then Request.Feedback:Fire("interaction"); return end
	pending = true
	serial += 1
	local mine = serial
	player:SetAttribute("PotionAnimationPrepare", (player:GetAttribute("PotionAnimationPrepare") or 0) + 1)
	task.spawn(function()
		local deadline = os.clock() + Config.REQUEST_READY_TIMEOUT
		if not player:GetAttribute("PotionAnimationReady") then Request.Feedback:Fire("loading") end
		while mine == serial and player.Character == character and hum.Health > 0
			and not player:GetAttribute("PotionAnimationReady") and os.clock() < deadline do task.wait(0.05) end
		if mine ~= serial then return end
		if player.Character ~= character or hum.Health <= 0 then finish(); return end
		if not player:GetAttribute("PotionAnimationReady") then finish(); Request.Feedback:Fire("load_failed"); return end
		if Action.IsLocked(character) or InteractionLock.IsLocked() then finish(); return end
		local events = RS:FindFirstChild("GameEvents")
		local remote = events and events:FindFirstChild(itemUuid and "DrinkPotionRequest" or "QuickDrinkPotion")
		if not remote then finish(); Request.Feedback:Fire("not_ready"); return end
		Request.Feedback:Fire("sent")
		remote:FireServer(itemUuid)
		-- Never automatically retry a sent request: the server may already have spent it.
		task.delay(Config.REQUEST_READY_TIMEOUT, function()
			if mine == serial then finish(); Request.Feedback:Fire("not_ready") end
		end)
	end)
end

player.CharacterRemoving:Connect(function()
	finish()
	player:SetAttribute("PotionAnimationReady", false)
end)
task.spawn(function()
	local events = RS:WaitForChild("GameEvents")
	events:WaitForChild("PotionDrunk").OnClientEvent:Connect(function(payload)
		if payload.character == player.Character then finish(); Request.Feedback:Fire("sent") end
	end)
	events:WaitForChild("PotionDrinkRejected").OnClientEvent:Connect(function(reason) finish() end)
end)

return Request
