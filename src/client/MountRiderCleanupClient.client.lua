-- Restores player jump after server-side mount teardown (e.g. second saddle click).
-- SetStateEnabled(Jumping) is client-authoritative for the local player; server calls alone are unreliable.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local function cleanupRiderGuiAndJump()
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if pg then
		for _, c in ipairs(pg:GetChildren()) do
			if c:IsA("LocalScript") and c.Name == "LocalControlScript" then
				local hv = c:FindFirstChild("Horse")
				if hv and hv:IsA("ObjectValue") then
					c:Destroy()
				end
			end
		end
		local hg = pg:FindFirstChild("HorseGui")
		if hg then
			hg:Destroy()
		end
	end

	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end

	pcall(function()
		hum.Sit = false
		hum.PlatformStand = false
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		-- Nudge out of seated physics if stuck after instant mount destroy
		hum:ChangeState(Enum.HumanoidStateType.Running)
	end)
end

local ge = ReplicatedStorage:WaitForChild("GameEvents", 60)
if not ge then
	return
end

local ev = ge:WaitForChild("MountRiderCleanup", 60)
if not ev or not ev:IsA("RemoteEvent") then
	return
end

ev.OnClientEvent:Connect(cleanupRiderGuiAndJump)
