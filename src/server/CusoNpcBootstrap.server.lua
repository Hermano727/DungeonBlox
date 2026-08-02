--[[
    CusoNpcBootstrap
    Wires Workspace model "Cuso" into the NPC client factory: attributes, CollectionService tag,
    ProximityPrompt + Head dialog billboard (DialogModule contract).
]]

local CollectionService = game:GetService("CollectionService")
local workspace = game:GetService("Workspace")

-- Wires every Model named "Cuso" anywhere in Workspace, not just the first one found.
-- Sorted by full path so id assignment (cuso_01, cuso_02, ...) stays stable across restarts.
local function findAllCusoModels()
	local found = {}
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst.Name == "Cuso" and inst:IsA("Model") then
			table.insert(found, inst)
		end
	end
	table.sort(found, function(a, b) return a:GetFullName() < b:GetFullName() end)
	return found
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
		-- Always refresh interaction settings (older prompts may block triggers).
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
		nameLabel.TextColor3 = Color3.fromRGB(255, 220, 150)
		nameLabel.TextStrokeTransparency = 0.3
		nameLabel.Text = npcName
		Instance.new("UIStroke", nameLabel).Color = Color3.fromRGB(80, 60, 20)

		local arrow = Instance.new("TextLabel", bb)
		arrow.Name = "arrow"
		arrow.Size = UDim2.new(1, 0, 0.3, 0)
		arrow.Position = UDim2.new(0, 0, 0.45, 0)
		arrow.BackgroundTransparency = 1
		arrow.Font = Enum.Font.GothamBold
		arrow.TextSize = 13
		arrow.TextColor3 = Color3.fromRGB(255, 220, 150)
		arrow.Text = "\xe2\x96\xbc"
		Instance.new("UIStroke", arrow).Color = Color3.fromRGB(80, 60, 20)

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

local function ensureCuso(model, npcId)
	model:SetAttribute("NpcId", npcId)
	model:SetAttribute("NpcType", "QuestGiver")
	model:SetAttribute("NpcName", "Cuso")
	model:SetAttribute("MaxActivationDistance", 14)

	local ok, err = pcall(function()
		model:WaitForChild("Humanoid", 5)
		model:WaitForChild("Head", 5)
		setupNpcModel(model, "Cuso")
	end)
	if not ok then
		warn("[CusoNpcBootstrap] setup failed:", err)
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

local function tryBootstrapAll()
	for i, model in ipairs(findAllCusoModels()) do
		local npcId = (i == 1) and "cuso_01" or string.format("cuso_%02d", i)
		local ok, err = pcall(ensureCuso, model, npcId)
		if ok then
			print("[CusoNpcBootstrap] wired:", model:GetFullName(), "as", npcId)
		else
			warn("[CusoNpcBootstrap] bootstrap failed:", err)
		end
	end
end

-- Run a few times to beat streaming/replication ordering in Play Solo.
for i = 1, 5 do
	task.delay(0.25 * (i - 1), tryBootstrapAll)
end

workspace.DescendantAdded:Connect(function(inst)
	if inst.Name == "Cuso" and inst:IsA("Model") then
		task.defer(tryBootstrapAll)
	end
end)

print("[CusoNpcBootstrap] ready")
