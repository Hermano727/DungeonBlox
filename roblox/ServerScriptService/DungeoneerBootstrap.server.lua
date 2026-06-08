--[[
	DungeoneerBootstrap
	Ensures Workspace "Dungeoneer" is a valid NPC for MerchantShopClient + NPCService:
	attributes, CollectionService "NPC" tag, ProximityPrompt, Head.gui (DialogModule).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local workspace = game:GetService("Workspace")

local NPCRegistry = require(ReplicatedStorage:WaitForChild("NPCRegistry"))

local NPC_ID = "dungeoneer_01"
local NPC_TYPE = "Dungeoneer"
local NPC_NAME = "Dungeoneer"

local function findDungeoneerModel()
	local direct = workspace:FindFirstChild("Dungeoneer")
	if direct and direct:IsA("Model") then
		return direct
	end
	local deep = workspace:FindFirstChild("Dungeoneer", true)
	if deep and deep:IsA("Model") then
		return deep
	end
	return nil
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
	nameLabel.TextColor3 = Color3.fromRGB(200, 210, 255)
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.Text = displayName
	nameLabel.Parent = bb
	pcall(function()
		local s = Instance.new("UIStroke")
		s.Color = Color3.fromRGB(30, 40, 80)
		s.Parent = nameLabel
	end)

	local arrow = Instance.new("TextLabel")
	arrow.Name = "arrow"
	arrow.Size = UDim2.new(1, 0, 0.3, 0)
	arrow.Position = UDim2.new(0, 0, 0.45, 0)
	arrow.BackgroundTransparency = 1
	arrow.Font = Enum.Font.GothamBold
	arrow.TextSize = 13
	arrow.TextColor3 = Color3.fromRGB(200, 210, 255)
	arrow.Text = "\226\150\188"
	arrow.Parent = bb
	pcall(function()
		local s = Instance.new("UIStroke")
		s.Color = Color3.fromRGB(30, 40, 80)
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
	local reg = NPCRegistry.Get(NPC_TYPE)
	pp.ActionText = (reg and reg.OpenShopPrompt) or "Trade key fragments"
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

local function bootstrap(model)
	if not model or not model:IsA("Model") then
		return
	end

	model:SetAttribute("NpcId", NPC_ID)
	model:SetAttribute("NpcType", NPC_TYPE)
	model:SetAttribute("NpcName", NPC_NAME)
	model:SetAttribute("MaxActivationDistance", math.max(tonumber(model:GetAttribute("MaxActivationDistance")) or 0, 12))

	local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
	if not (root and root:IsA("BasePart")) then
		warn("[DungeoneerBootstrap] missing HumanoidRootPart/Torso on Dungeoneer")
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
			warn("[DungeoneerBootstrap] Head.gui setup failed:", errGui)
		end
	else
		warn("[DungeoneerBootstrap] missing Head on Dungeoneer")
	end
end

local function tryBootstrap()
	local m = findDungeoneerModel()
	if not m then
		return
	end
	local ok, err = pcall(function()
		bootstrap(m)
	end)
	if ok then
		print("[DungeoneerBootstrap] wired:", m:GetFullName())
	else
		warn("[DungeoneerBootstrap] bootstrap failed:", err)
	end
end

tryBootstrap()

workspace.ChildAdded:Connect(function(ch)
	if ch.Name == "Dungeoneer" and ch:IsA("Model") then
		task.defer(tryBootstrap)
	end
end)

workspace.DescendantAdded:Connect(function(inst)
	if inst:IsA("Model") and inst.Name == "Dungeoneer" then
		task.defer(tryBootstrap)
	end
end)

task.defer(tryBootstrap)
task.delay(1.0, tryBootstrap)
task.delay(3.0, tryBootstrap)

print("[DungeoneerBootstrap] ready")
