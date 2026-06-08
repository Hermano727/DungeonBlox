--[[
	FishermanNpcBootstrap
	Wires Workspace model "Fisherman" into the NPC client factory: attributes, CollectionService tag,
	ProximityPrompt + Head dialog billboard (DialogModule contract).
]]

local CollectionService = game:GetService("CollectionService")
local workspace = game:GetService("Workspace")

local function findFishermanModel()
	local direct = workspace:FindFirstChild("Fisherman")
	if direct and direct:IsA("Model") then
		return direct
	end
	local deep = workspace:FindFirstChild("Fisherman", true)
	if deep and deep:IsA("Model") then
		return deep
	end
	return nil
end

local function setupNpcModel(model, npcName)
	local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
	if root then
		model.PrimaryPart = root
		local pp = root:FindFirstChildOfClass("ProximityPrompt")
		if not pp then
			pp = Instance.new("ProximityPrompt")
			pp.Name = "NpcTalkPrompt"
			pp.ActionText = "Talk"
			pp.ObjectText = npcName
			pp.KeyboardKeyCode = Enum.KeyCode.E
			pp.GamepadKeyCode = Enum.KeyCode.ButtonX
			pp.MaxActivationDistance = 14
			pp.HoldDuration = 0
			pp.RequiresLineOfSight = false
			pp.Enabled = true
			pp.ClickablePrompt = true
			pp.Parent = root
		end
		pp = root:FindFirstChildOfClass("ProximityPrompt")
		if pp then
			pp.Enabled = true
			pp.RequiresLineOfSight = false
			pp.HoldDuration = 0
			pp.MaxActivationDistance = math.max(pp.MaxActivationDistance, 12)
			if not CollectionService:HasTag(pp, "NPCprompt") then
				CollectionService:AddTag(pp, "NPCprompt")
			end
		end
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	local head = model:FindFirstChild("Head")
	if head and not head:FindFirstChild("gui") then
		local bb = Instance.new("BillboardGui")
		bb.Name = "gui"
		bb.Size = UDim2.new(8, 0, 1.5, 0)
		bb.StudsOffset = Vector3.new(0, 2.2, 0)
		bb.AlwaysOnTop = false
		bb.Parent = head

		local nameLabel = Instance.new("TextLabel", bb)
		nameLabel.Name = "name"
		nameLabel.Size = UDim2.new(1, 0, 0.45, 0)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextSize = 16
		nameLabel.TextColor3 = Color3.fromRGB(200, 210, 220)
		nameLabel.TextStrokeTransparency = 0.3
		nameLabel.Text = npcName
		Instance.new("UIStroke", nameLabel).Color = Color3.fromRGB(40, 50, 60)

		local arrow = Instance.new("TextLabel", bb)
		arrow.Name = "arrow"
		arrow.Size = UDim2.new(1, 0, 0.3, 0)
		arrow.Position = UDim2.new(0, 0, 0.45, 0)
		arrow.BackgroundTransparency = 1
		arrow.Font = Enum.Font.GothamBold
		arrow.TextSize = 13
		arrow.TextColor3 = Color3.fromRGB(200, 210, 220)
		arrow.Text = "\xe2\x96\xbc"
		Instance.new("UIStroke", arrow).Color = Color3.fromRGB(40, 50, 60)

		local dialog = Instance.new("TextLabel", bb)
		dialog.Name = "dialog"
		dialog.Size = UDim2.new(1, 0, 1, 0)
		dialog.BackgroundTransparency = 1
		dialog.Font = Enum.Font.GothamMedium
		dialog.TextSize = 13
		dialog.TextColor3 = Color3.new(1, 1, 1)
		dialog.TextWrapped = true
		dialog.Visible = false
		dialog.Text = ""
		Instance.new("UIStroke", dialog).Color = Color3.fromRGB(0, 0, 0)
	end
end

local function ensureFisherman()
	local model = findFishermanModel()
	if not model then
		return
	end

	model:SetAttribute("NpcId", "fisherman_01")
	model:SetAttribute("NpcType", "Fisherman")
	model:SetAttribute("NpcName", "Fisherman")
	model:SetAttribute("MaxActivationDistance", 14)

	local ok, err = pcall(function()
		model:WaitForChild("Humanoid", 5)
		model:WaitForChild("Head", 5)
		setupNpcModel(model, "Fisherman")
	end)
	if not ok then
		warn("[FishermanNpcBootstrap] setup failed:", err)
	end

	local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
	if root then
		local pp = root:FindFirstChildOfClass("ProximityPrompt")
		if pp and not CollectionService:HasTag(pp, "NPCprompt") then
			CollectionService:AddTag(pp, "NPCprompt")
		end
	end

	if not CollectionService:HasTag(model, "NPC") then
		CollectionService:AddTag(model, "NPC")
	end
end

for i = 1, 5 do
	task.delay(0.25 * (i - 1), ensureFisherman)
end

workspace.DescendantAdded:Connect(function(inst)
	if inst.Name == "Fisherman" and inst:IsA("Model") then
		task.defer(ensureFisherman)
	end
end)

print("[FishermanNpcBootstrap] ready")
