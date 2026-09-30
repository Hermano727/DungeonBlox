--[[
	AimRay -- where the local player is aiming, for the one camera mode where "the camera's
	look direction" is NOT the aim: the front view (R cycles first person -> over-shoulder ->
	front, FirstPersonViewModel; it publishes Player attribute "PerspectiveMode").

		local origin, direction = AimRay.FrontView()   -- nil unless the front view is on

	In the front view the camera sits in front of the character looking back at its face, so
	its LookVector points exactly opposite the character's aim. Tools that aim with a camera
	ray (CombatClient's melee ray, BowClient, MiningScript, FishClient) ask this first and,
	when it answers, aim from the head along the character's facing instead.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local AimRay = {}

function AimRay.IsFrontView()
	local player = Players.LocalPlayer
	return player ~= nil and player:GetAttribute("PerspectiveMode") == "Front"
end

-- origin, unit direction; or nil when the front view isn't active.
function AimRay.FrontView()
	if not AimRay.IsFrontView() then return nil end
	local camera = Workspace.CurrentCamera
	local character = Players.LocalPlayer.Character
	local head = character and character:FindFirstChild("Head")
	if not camera or not head then return nil end
	return head.Position, -camera.CFrame.LookVector
end

return AimRay
