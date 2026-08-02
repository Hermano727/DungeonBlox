--[[
	AnimalTrainerBootstrap
	Ensures Workspace "Animal Trainer" is a valid NPC for MerchantShopClient + NPCService:
	attributes, CollectionService "NPC" tag, ProximityPrompt, Head.gui (DialogModule).
]]

local CollectionService = game:GetService("CollectionService")
local workspace = game:GetService("Workspace")

local NPC_ID_BASE = "animal_trainer_01"
local NPC_TYPE    = "AnimalTrainer"
local NPC_NAME    = "Animal Trainer"

-- Wires every Model named "Animal Trainer" anywhere in Workspace, not just the first one found.
-- Sorted by full path so id assignment (animal_trainer_01, animal_trainer_02, ...) stays stable across restarts.
local function findAllAnimalTrainerModels()
	local found = {}
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst.Name == "Animal Trainer" and inst:IsA("Model") then
			table.insert(found, inst)
		end
	end
	table.sort(found, function(a, b) return a:GetFullName() < b:GetFullName() end)
	return found
end

local function ensureHeadGui(head, displayName)
	if head:FindFirstChild("gui") then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "gui"
	bb.Size = UDim2.new(8, 0, 1.5, 0)
	bb.StudsOffset = Vector3.new(0, 2.2, 0)
	bb.AlwaysOnTop = false
	bb.Parent = head

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "name"
	nameLabel.Size = UDim2.new(1, 0, 0.45, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 16
	nameLabel.TextColor3 = Color3.fromRGB(255, 220, 150)
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.Text = displayName
	nameLabel.Parent = bb
	pcall(function()
		local s = Instance.new("UIStroke")
		s.Color = Color3.fromRGB(80, 60, 20)
		s.Parent = nameLabel
	end)

	local arrow = Instance.new("TextLabel")
	arrow.Name = "arrow"
	arrow.Size = UDim2.new(1, 0, 0.3, 0)
	arrow.Position = UDim2.new(0, 0, 0.45, 0)
	arrow.BackgroundTransparency = 1
	arrow.Font = Enum.Font.GothamBold
	arrow.TextSize = 13
	arrow.TextColor3 = Color3.fromRGB(255, 220, 150)
	arrow.Text = "\226\150\188"
	arrow.Parent = bb
	pcall(function()
		local s = Instance.new("UIStroke")
		s.Color = Color3.fromRGB(80, 60, 20)
		s.Parent = arrow
	end)

	local dialog = Instance.new("TextLabel")
	dialog.Name = "dialog"
	dialog.Size = UDim2.new(1, 0, 1, 0)
	dialog.BackgroundTransparency = 1
	dialog.Font = Enum.Font.GothamMedium
	dialog.TextSize = 13
	dialog.TextColor3 = Color3.new(1, 1, 1)
	dialog.TextWrapped = true
	dialog.Visible = false
	dialog.Text = ""
	dialog.Parent = bb
	pcall(function()
		local s = Instance.new("UIStroke")
		s.Color = Color3.fromRGB(0, 0, 0)
		s.Parent = dialog
	end)
end

local function setupProximity(root)
	local pp = root:FindFirstChildOfClass("ProximityPrompt")
	if not pp then
		pp = Instance.new("ProximityPrompt")
		pp.Name = "NpcTalkPrompt"
		pp.Parent = root
	end
	pp.ActionText = "Browse saddles"
	pp.ObjectText = NPC_NAME
	pp.KeyboardKeyCode = Enum.KeyCode.E
	pp.GamepadKeyCode = Enum.KeyCode.ButtonX
	pp.MaxActivationDistance = math.max(pp.MaxActivationDistance, 12)
	pp.HoldDuration = 0
	pp.RequiresLineOfSight = false
	pp.Enabled = true
	pp.ClickablePrompt = true
	if not CollectionService:HasTag(pp, "NPCprompt") then
		CollectionService:AddTag(pp, "NPCprompt")
	end
end

local function bootstrap(model, npcId)
	if not model or not model:IsA("Model") then
		return
	end

	model:SetAttribute("NpcId", npcId)
	model:SetAttribute("NpcType", NPC_TYPE)
	model:SetAttribute("NpcName", NPC_NAME)
	model:SetAttribute("MaxActivationDistance", math.max(tonumber(model:GetAttribute("MaxActivationDistance")) or 0, 12))

	local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
	if not (root and root:IsA("BasePart")) then
		warn("[AnimalTrainerBootstrap] missing HumanoidRootPart/Torso on", model:GetFullName())
		return
	end
	model.PrimaryPart = root
	setupProximity(root)

	if not CollectionService:HasTag(model, "NPC") then
		CollectionService:AddTag(model, "NPC")
	end

	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local okGui, errGui = pcall(function()
			ensureHeadGui(head, NPC_NAME)
		end)
		if not okGui then
			warn("[AnimalTrainerBootstrap] Head.gui setup failed:", errGui)
		end
	else
		warn("[AnimalTrainerBootstrap] missing Head on", model:GetFullName())
	end
end

local function tryBootstrap()
	local models = findAllAnimalTrainerModels()
	for i, m in ipairs(models) do
		local npcId = (i == 1) and NPC_ID_BASE or string.format("animal_trainer_%02d", i)
		local ok, err = pcall(function()
			bootstrap(m, npcId)
		end)
		if ok then
			print("[AnimalTrainerBootstrap] wired:", m:GetFullName(), "as", npcId)
		else
			warn("[AnimalTrainerBootstrap] bootstrap failed:", err)
		end
	end
end

tryBootstrap()

workspace.ChildAdded:Connect(function(ch)
	if ch.Name == "Animal Trainer" and ch:IsA("Model") then
		task.defer(tryBootstrap)
	end
end)

workspace.DescendantAdded:Connect(function(inst)
	if inst:IsA("Model") and inst.Name == "Animal Trainer" then
		task.defer(tryBootstrap)
	end
end)

task.defer(tryBootstrap)
task.delay(1.0, tryBootstrap)
task.delay(3.0, tryBootstrap)

print("[AnimalTrainerBootstrap] ready")
