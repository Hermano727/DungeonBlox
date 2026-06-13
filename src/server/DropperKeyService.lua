-- DropperKeyService: mobs dying near a Dropper can spawn a floating key that unlocks the nearest Dropper for a coin payout.
local DropperKeyService = {}

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Debris = game:GetService("Debris")

local DungeonProfile = require(ServerScriptService:WaitForChild("DungeonProfileService"))

local DROP_RADIUS = 40
local DROP_CHANCE = 1
local COIN_REWARD = 100
local KEY_FLOAT_Y = 3
local KEY_HOMING_SPEED = 48
local ARRIVE_DISTANCE = 3
local FLOAT_AMP = 0.35
local FLOAT_FREQ = 2.2

local TEMPLATE_FOLDER = ServerStorage:WaitForChild("DropperKeyTemplates")
local TEMPLATE_NAME = "KeyMesh"

local activeFolder = Workspace:FindFirstChild("ActiveDropperKeys")
if not activeFolder then
	activeFolder = Instance.new("Folder")
	activeFolder.Name = "ActiveDropperKeys"
	activeFolder.Parent = Workspace
end

local closedCfCache = setmetatable({}, { __mode = "k" })

local function ensureItemDropNotify()
	local ge = ReplicatedStorage:FindFirstChild("GameEvents")
	if not ge then
		return nil
	end
	local ev = ge:FindFirstChild("ItemDropNotify")
	if ev and ev:IsA("RemoteEvent") then
		return ev
	end
	return nil
end

local function collectDroppers()
	local out = {}
	for _, inst in ipairs(Workspace:GetDescendants()) do
		if inst:IsA("Model") and inst.Name == "Dropper" then
			table.insert(out, inst)
		end
	end
	return out
end

local function nearestDropper(pos, droppers)
	local best, bestD = nil, math.huge
	for _, d in ipairs(droppers) do
		local p = d:GetPivot().Position
		local dist = (p - pos).Magnitude
		if dist < bestD then
			best, bestD = d, dist
		end
	end
	return best, bestD
end

local function ensureClosedCf(dropper)
	if closedCfCache[dropper] then
		return
	end
	local top = dropper:FindFirstChild("WoodTop")
	if top and top:IsA("BasePart") then
		closedCfCache[dropper] = top.CFrame
	end
end

local function tweenOpen(dropper)
	local top = dropper:FindFirstChild("WoodTop")
	if not top or not top:IsA("BasePart") then
		return
	end
	ensureClosedCf(dropper)
	local closed = closedCfCache[dropper] or top.CFrame
	local openCf = closed * CFrame.new(0, 2.35, 0) * CFrame.Angles(math.rad(-28), 0, 0)
	local tw = TweenService:Create(top, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = openCf })
	tw:Play()
	tw.Completed:Wait()
end

local function tweenClose(dropper)
	local top = dropper:FindFirstChild("WoodTop")
	if not top or not top:IsA("BasePart") then
		return
	end
	local closed = closedCfCache[dropper]
	if not closed then
		return
	end
	local tw = TweenService:Create(top, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = closed })
	tw:Play()
	tw.Completed:Wait()
end

local function grantCoins(player, amount)
	local profile = DungeonProfile.Load(player)
	if not profile then
		return
	end
	if type(profile.currencies) ~= "table" then
		profile.currencies = {}
	end
	profile.currencies.Coins = math.floor((tonumber(profile.currencies.Coins) or 0) + amount)
	DungeonProfile.PushProfile(player)
	local ev = ensureItemDropNotify()
	if ev then
		ev:FireClient(player, { kind = "Coins", amount = amount })
	end
end

local function runDropperReward(dropper, player, keyModel)
	task.spawn(function()
		local prompt = dropper:FindFirstChild("ProximityPrompt")
		local wasEnabled = prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.Enabled = false
		end

		tweenOpen(dropper)
		grantCoins(player, COIN_REWARD)
		task.wait(0.12)
		tweenClose(dropper)

		if prompt and prompt:IsA("ProximityPrompt") and wasEnabled then
			prompt.Enabled = true
		end
		if keyModel and keyModel.Parent then
			keyModel:Destroy()
		end
	end)
end

local function spawnFloatingKey(deathPos, killer)
	local tmpl = TEMPLATE_FOLDER:FindFirstChild(TEMPLATE_NAME)
	if not tmpl or not tmpl:IsA("BasePart") then
		warn("[DropperKeyService] Missing ServerStorage.DropperKeyTemplates.KeyMesh")
		return
	end

	local key = tmpl:Clone()
	key.Name = "DropperKeyPickup"
	key.Anchored = true
	key.CanCollide = false
	key.CanTouch = false
	key.Massless = true

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(120, 255, 140)
	light.Brightness = 1.6
	light.Range = 12
	light.Parent = key

	local pe = Instance.new("ParticleEmitter")
	pe.Name = "GreenAura"
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Rate = 18
	pe.Lifetime = NumberRange.new(0.35, 0.75)
	pe.Speed = NumberRange.new(0.3, 1.4)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Rotation = NumberRange.new(0, 360)
	pe.RotSpeed = NumberRange.new(-120, 120)
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Color = ColorSequence.new(Color3.fromRGB(70, 255, 120), Color3.fromRGB(180, 255, 200))
	pe.LightEmission = 0.85
	pe.Parent = key

	local model = Instance.new("Model")
	model.Name = "DropperKeyPickup"
	key.Parent = model
	model.PrimaryPart = key
	model.Parent = activeFolder
	Debris:AddItem(model, 240)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Take Key"
	prompt.ObjectText = "Dropper Key"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = key

	local baseXZ = Vector3.new(deathPos.X, deathPos.Y + KEY_FLOAT_Y, deathPos.Z)
	local floatT0 = tick()
	local phase = "Float"
	local targetDropper = nil

	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not model.Parent then
			if conn then conn:Disconnect() end
			return
		end
		if phase == "Float" then
			local t = tick() - floatT0
			local bob = math.sin(t * FLOAT_FREQ) * FLOAT_AMP
			key.CFrame = CFrame.new(baseXZ + Vector3.new(0, bob, 0))
		elseif phase == "Homing" then
			if not targetDropper or not targetDropper.Parent then
				if conn then conn:Disconnect() end
				model:Destroy()
				return
			end
			local goal = targetDropper:GetPivot().Position + Vector3.new(0, 1.25, 0)
			local pos = key.Position
			local delta = goal - pos
			local dist = delta.Magnitude
			if dist <= ARRIVE_DISTANCE then
				if conn then conn:Disconnect() end
				pe.Enabled = false
				light.Enabled = false
				runDropperReward(targetDropper, killer, model)
				return
			end
			local step = math.min(dist, KEY_HOMING_SPEED * dt)
			local newPos = pos + delta.Unit * step
			key.CFrame = CFrame.lookAt(newPos, goal)
		end
	end)

	prompt.Triggered:Connect(function(player)
		if player ~= killer then
			return
		end
		if phase ~= "Float" then
			return
		end
		local droppers = collectDroppers()
		local nearest = select(1, nearestDropper(key.Position, droppers))
		if not nearest then
			model:Destroy()
			return
		end
		phase = "Homing"
		targetDropper = nearest
		prompt:Destroy()
		pe.Enabled = true
	end)
end

function DropperKeyService.onMobDied(mob, killingBlowPlayer)
	if not killingBlowPlayer or not killingBlowPlayer.Parent then
		return
	end
	if not mob or not mob.GetPosition then
		return
	end
	local deathPos = mob:GetPosition()
	if typeof(deathPos) ~= "Vector3" then
		return
	end

	local droppers = collectDroppers()
	if #droppers == 0 then
		return
	end

	local _, dist = nearestDropper(deathPos, droppers)
	if not dist or dist > DROP_RADIUS then
		return
	end

	local rollChance = DROP_CHANCE
	if rollChance > 1 then
		rollChance = rollChance / 100
	end
	rollChance = math.clamp(rollChance, 0, 1)
	if math.random() > rollChance then
		return
	end

	spawnFloatingKey(deathPos, killingBlowPlayer)
end

return DropperKeyService
