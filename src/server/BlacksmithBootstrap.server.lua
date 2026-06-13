--[[
	BlacksmithBootstrap
	Wires any Model named "Blacksmith" in Workspace into the NPC system:
	attributes, CollectionService "NPC" tag, ProximityPrompt, Head.gui (name label).
	Mirrors InnkeeperBootstrap — place/paste the Blacksmith model anywhere in
	Workspace and this script wires it automatically.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NPCRegistry = require(ReplicatedStorage:WaitForChild("NPCRegistry"))

local NPC_ID   = "blacksmith_01"
local NPC_TYPE = "Blacksmith"
local NPC_NAME = "Blacksmith"

local function findModel()
	local direct = workspace:FindFirstChild("Blacksmith")
	if direct and direct:IsA("Model") then return direct end
	local deep = workspace:FindFirstChild("Blacksmith", true)
	if deep and deep:IsA("Model") then return deep end
	return nil
end

local function ensureHeadGui(head, displayName)
	if head:FindFirstChild("gui") then return end

	local bb = Instance.new("BillboardGui")
	bb.Name         = "gui"
	bb.Size         = UDim2.new(8, 0, 1.5, 0)
	bb.StudsOffset  = Vector3.new(0, 2.2, 0)
	bb.AlwaysOnTop  = false
	bb.Parent       = head

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name                  = "name"
	nameLabel.Size                  = UDim2.new(1, 0, 0.45, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font                  = Enum.Font.GothamBold
	nameLabel.TextSize              = 16
	nameLabel.TextColor3            = Color3.fromRGB(255, 230, 200)
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.Text                  = displayName
	nameLabel.Parent                = bb
	pcall(function()
		local s = Instance.new("UIStroke")
		s.Color = Color3.fromRGB(60, 40, 25)
		s.Parent = nameLabel
	end)

	local arrow = Instance.new("TextLabel")
	arrow.Name                  = "arrow"
	arrow.Size                  = UDim2.new(1, 0, 0.3, 0)
	arrow.Position              = UDim2.new(0, 0, 0.45, 0)
	arrow.BackgroundTransparency = 1
	arrow.Font                  = Enum.Font.GothamBold
	arrow.TextSize              = 13
	arrow.TextColor3            = Color3.fromRGB(255, 230, 200)
	arrow.Text                  = "\226\150\188"
	arrow.Parent                = bb
	pcall(function()
		local s = Instance.new("UIStroke")
		s.Color = Color3.fromRGB(60, 40, 25)
		s.Parent = arrow
	end)

	local dialog = Instance.new("TextLabel")
	dialog.Name                  = "dialog"
	dialog.Size                  = UDim2.new(1, 0, 1, 0)
	dialog.BackgroundTransparency = 1
	dialog.Font                  = Enum.Font.GothamMedium
	dialog.TextSize              = 13
	dialog.TextColor3            = Color3.new(1, 1, 1)
	dialog.TextWrapped           = true
	dialog.Visible               = false
	dialog.Text                  = ""
	dialog.Parent                = bb
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
		pp.Name   = "NpcTalkPrompt"
		pp.Parent = root
	end
	local reg = NPCRegistry.Get(NPC_TYPE)
	pp.ActionText             = (reg and reg.OpenRepairPrompt) or "Repair Equipment"
	pp.ObjectText             = NPC_NAME
	pp.KeyboardKeyCode        = Enum.KeyCode.E
	pp.GamepadKeyCode         = Enum.KeyCode.ButtonX
	pp.MaxActivationDistance  = math.max(pp.MaxActivationDistance, 12)
	pp.HoldDuration           = 0
	pp.RequiresLineOfSight    = false
	pp.Enabled                = true
	pp.ClickablePrompt        = true
	if not CollectionService:HasTag(pp, "NPCprompt") then
		CollectionService:AddTag(pp, "NPCprompt")
	end
end

local function bootstrap(model)
	if not model or not model:IsA("Model") then return end

	model:SetAttribute("NpcId",   NPC_ID)
	model:SetAttribute("NpcType", NPC_TYPE)
	model:SetAttribute("NpcName", NPC_NAME)
	model:SetAttribute("MaxActivationDistance",
		math.max(tonumber(model:GetAttribute("MaxActivationDistance")) or 0, 12))

	local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
	if not (root and root:IsA("BasePart")) then
		warn("[BlacksmithBootstrap] missing HumanoidRootPart/Torso on Blacksmith")
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
		local ok, err = pcall(ensureHeadGui, head, NPC_NAME)
		if not ok then warn("[BlacksmithBootstrap] Head.gui failed:", err) end
	else
		warn("[BlacksmithBootstrap] missing Head on Blacksmith")
	end
end

local function tryBootstrap()
	local m = findModel()
	if not m then return end
	local ok, err = pcall(bootstrap, m)
	if ok then
		print("[BlacksmithBootstrap] wired:", m:GetFullName())
	else
		warn("[BlacksmithBootstrap] bootstrap failed:", err)
	end
end

tryBootstrap()

workspace.ChildAdded:Connect(function(ch)
	if ch.Name == "Blacksmith" and ch:IsA("Model") then
		task.defer(tryBootstrap)
	end
end)

workspace.DescendantAdded:Connect(function(inst)
	if inst:IsA("Model") and inst.Name == "Blacksmith" then
		task.defer(tryBootstrap)
	end
end)

task.defer(tryBootstrap)
task.delay(1.0, tryBootstrap)
task.delay(3.0, tryBootstrap)

print("[BlacksmithBootstrap] ready")