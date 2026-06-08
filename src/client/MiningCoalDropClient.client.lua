-- Listens for server-approved coal drops and spawns a client-only Coal pickup.
-- Physics run only on your machine (still not on the server), so it can fall with gravity and land on terrain.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local MiningCoalDrop = ReplicatedStorage:WaitForChild("MiningCoalDrop")
local MiningCoalCollect = ReplicatedStorage:WaitForChild("MiningCoalCollect")

local function spawnLocalCoalPickup(payload)
	if type(payload) ~= "table" then
		return
	end
	local pos = payload.position
	local nonce = payload.nonce
	if typeof(pos) ~= "Vector3" or type(nonce) ~= "string" or nonce == "" then
		return
	end

	local template = ReplicatedStorage:WaitForChild("Coal")
	if not template:IsA("Tool") then
		return
	end

	local coal = template:Clone()
	coal.Name = "CoalPickupLocal"
	coal.CanBeDropped = false

	local handle = coal:FindFirstChild("Handle") or coal:FindFirstChildWhichIsA("BasePart", true)
	if not handle then
		coal:Destroy()
		return
	end

	for _, d in ipairs(coal:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = true
			pcall(function()
				d.CanTouch = true
			end)
		end
	end

	local jitter = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 2
	local spawnCf = CFrame.new(pos + jitter)

	coal.Parent = Workspace
	handle.CFrame = spawnCf
	-- Small upward bias so it clears the ore, then gravity pulls it to the floor.
	handle.AssemblyLinearVelocity = Vector3.new(0, 3, 0)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Collect"
	prompt.ObjectText = "Coal"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = handle

	local collected = false
	prompt.Triggered:Connect(function(who)
		if collected or who ~= player then
			return
		end
		collected = true
		MiningCoalCollect:FireServer(nonce)
		coal:Destroy()
	end)
end

MiningCoalDrop.OnClientEvent:Connect(spawnLocalCoalPickup)
