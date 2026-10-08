-- Listens for server-approved coal drops and spawns a client-only Coal pickup.
-- Physics run only on your machine (still not on the server), so it can fall with gravity and land on terrain.
-- Since 2026-10-03 the pickup is the coal shard model (ReplicatedStorage.MiningVisuals.T1_CoalShard,
-- procedural: assets/models/environment/ores): a small crystal cluster with a baked gleam, a touch
-- of reflectance and the odd glint. The old black "Coal" handle is only the fallback.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local MiningCoalDrop = ReplicatedStorage:WaitForChild("MiningCoalDrop")
local MiningCoalCollect = ReplicatedStorage:WaitForChild("MiningCoalCollect")

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

-- The shard, dressed as a pickup: falls, lands, now and then catches the light.
local function shardPickup()
	local visuals = ReplicatedStorage:FindFirstChild("MiningVisuals")
	local template = visuals and visuals:FindFirstChild("T1_CoalShard")
	if not template then return nil end
	local shard = template:Clone()
	shard.Name = "CoalPickupLocal"
	shard.Anchored = false
	shard.CanCollide = true
	shard.CanTouch = true
	local glint = Instance.new("ParticleEmitter")
	glint.Texture = SPARKLE
	glint.Color = ColorSequence.new(Color3.fromRGB(220, 230, 255))
	glint.LightEmission = 1
	glint.LightInfluence = 0
	glint.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, 0.35), NumberSequenceKeypoint.new(1, 0) })
	glint.Lifetime = NumberRange.new(0.35, 0.5)
	glint.Rate = 0.6
	glint.Speed = NumberRange.new(0)
	glint.Rotation = NumberRange.new(0, 90)
	glint.ZOffset = 0.5
	glint.Parent = shard
	return shard, shard
end

-- The old block (a Tool template), if the shard model isn't there.
local function legacyPickup()
	local template = ReplicatedStorage:FindFirstChild("Coal")
	if not template or not template:IsA("Tool") then return nil end
	local coal = template:Clone()
	coal.Name = "CoalPickupLocal"
	coal.CanBeDropped = false
	local handle = coal:FindFirstChild("Handle") or coal:FindFirstChildWhichIsA("BasePart", true)
	if not handle then
		coal:Destroy()
		return nil
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
	return coal, handle
end

local function spawnLocalCoalPickup(payload)
	if type(payload) ~= "table" then
		return
	end
	local pos = payload.position
	local nonce = payload.nonce
	if typeof(pos) ~= "Vector3" or type(nonce) ~= "string" or nonce == "" then
		return
	end

	local pickup, handle = shardPickup()
	if not pickup then
		pickup, handle = legacyPickup()
	end
	if not pickup then
		return
	end

	local jitter = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 2
	pickup.Parent = Workspace
	handle.CFrame = CFrame.new(pos + jitter) * CFrame.Angles(math.random() * 0.6, math.random() * 6.28, math.random() * 0.6)
	handle.AssemblyLinearVelocity = Vector3.new(0, 3, 0)
	handle.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 6

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Collect"
	local amt = payload.amount
	if type(amt) == "number" and amt > 1 then
		prompt.ObjectText = "Coal x" .. tostring(math.floor(amt))
	else
		prompt.ObjectText = "Coal"
	end
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
		pickup:Destroy()
	end)
end

MiningCoalDrop.OnClientEvent:Connect(spawnLocalCoalPickup)
