local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local tool = script.Parent
local player = Players.LocalPlayer
local SpearFishRequest = ReplicatedStorage:WaitForChild("SpearFishRequest")

local lastSend = 0
local SEND_DEBOUNCE = 0.12

local function aimWorldFromMouse()
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil, nil
	end

	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local char = player.Character
	rayParams.FilterDescendantsInstances = char and { char } or {}
	rayParams.IgnoreWater = false

	local result = Workspace:Raycast(ray.Origin, ray.Direction * 2048, rayParams)
	if not result then
		return nil, nil
	end

	return result.Position, result.Material
end

-- Left click while spear is equipped: Roblox marks many tool clicks as gameProcessed,
-- so do not rely on UserInputService.InputBegan here.
tool.Activated:Connect(function()
	if tool.Parent ~= player.Character then
		return
	end

	local now = os.clock()
	if now - lastSend < SEND_DEBOUNCE then
		return
	end

	local pos, mat = aimWorldFromMouse()
	if not pos or not mat then
		return
	end

	lastSend = now
	SpearFishRequest:FireServer(pos, mat.Name)
end)
