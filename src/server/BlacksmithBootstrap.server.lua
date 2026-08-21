--[[
	BlacksmithBootstrap
	Wires any Model named "Blacksmith" in Workspace into the NPC system:
	attributes, CollectionService "NPC" tag, ProximityPrompt, Head.gui (name label).
	Mirrors InnkeeperBootstrap — place/paste the Blacksmith model anywhere in
	Workspace and this script wires it automatically.
	Shared boilerplate lives in NPCBootstrapKit — see that module's header for why
	watcher wiring below stays hand-rolled per NPC type instead of also being
	factored out.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NPCRegistry     = require(ReplicatedStorage:WaitForChild("NPCRegistry"))
local NPCBootstrapKit = require(ReplicatedStorage:WaitForChild("NPCBootstrapKit"))

local NPC_ID_BASE = "blacksmith_01"
local NPC_TYPE    = "Blacksmith"
local NPC_NAME    = "Blacksmith"

local HEAD_COLORS = {
	text   = Color3.fromRGB(255, 230, 200),
	stroke = Color3.fromRGB(60, 40, 25),
}

-- Wires every Model named "Blacksmith" anywhere in Workspace, not just the first one found.
-- Sorted by full path so id assignment (blacksmith_01, blacksmith_02, ...) stays stable across restarts.
local function findAllModels()
	return NPCBootstrapKit.FindAllModelsByName("Blacksmith")
end

local function setupProximity(root)
	local reg = NPCRegistry.Get(NPC_TYPE)
	NPCBootstrapKit.SetupProximityPrompt(root, {
		actionText            = (reg and reg.OpenRepairPrompt) or "Repair Equipment",
		objectText             = NPC_NAME,
		maxActivationDistance  = 12,
	})
end

local function bootstrap(model, npcId)
	if not model or not model:IsA("Model") then return end

	local root = NPCBootstrapKit.TagAsNPC(model, npcId, NPC_TYPE, NPC_NAME, 12)
	if not root then
		warn("[BlacksmithBootstrap] missing HumanoidRootPart/Torso on", model:GetFullName())
		return
	end
	setupProximity(root)

	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local ok, err = pcall(NPCBootstrapKit.EnsureHeadGui, head, NPC_NAME, HEAD_COLORS)
		if not ok then warn("[BlacksmithBootstrap] Head.gui failed:", err) end
	else
		warn("[BlacksmithBootstrap] missing Head on", model:GetFullName())
	end
end

local function tryBootstrap()
	local models = findAllModels()
	for i, m in ipairs(models) do
		local npcId = (i == 1) and NPC_ID_BASE or string.format("blacksmith_%02d", i)
		local ok, err = pcall(bootstrap, m, npcId)
		if ok then
			print("[BlacksmithBootstrap] wired:", m:GetFullName(), "as", npcId)
		else
			warn("[BlacksmithBootstrap] bootstrap failed:", err)
		end
	end
end

NPCBootstrapKit.ScheduleRetries(tryBootstrap, {0, 1.0, 3.0})

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

print("[BlacksmithBootstrap] ready")
