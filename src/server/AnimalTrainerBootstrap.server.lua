--[[
	AnimalTrainerBootstrap
	Ensures Workspace "Animal Trainer" is a valid NPC for MerchantShopClient + NPCService:
	attributes, CollectionService "NPC" tag, ProximityPrompt, Head.gui (DialogModule).
	Shared boilerplate lives in NPCBootstrapKit — see that module's header for why
	watcher wiring below stays hand-rolled per NPC type instead of also being
	factored out.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local workspace = game:GetService("Workspace")

local NPCBootstrapKit = require(ReplicatedStorage:WaitForChild("NPCBootstrapKit"))

local NPC_ID_BASE = "animal_trainer_01"
local NPC_TYPE    = "AnimalTrainer"
local NPC_NAME    = "Animal Trainer"

local HEAD_COLORS = {
	text   = Color3.fromRGB(255, 220, 150),
	stroke = Color3.fromRGB(80, 60, 20),
}

-- Wires every Model named "Animal Trainer" anywhere in Workspace, not just the first one found.
-- Sorted by full path so id assignment (animal_trainer_01, animal_trainer_02, ...) stays stable across restarts.
local function findAllAnimalTrainerModels()
	return NPCBootstrapKit.FindAllModelsByName("Animal Trainer")
end

local function setupProximity(root)
	-- Note: intentionally hardcoded, not read from NPCRegistry — this file has no
	-- NPCRegistry dependency. The text matches NPCRegistry.AnimalTrainer.OpenShopPrompt.
	NPCBootstrapKit.SetupProximityPrompt(root, {
		actionText            = "Browse saddles",
		objectText             = NPC_NAME,
		maxActivationDistance  = 12,
	})
end

local function bootstrap(model, npcId)
	if not model or not model:IsA("Model") then
		return
	end

	local root = NPCBootstrapKit.TagAsNPC(model, npcId, NPC_TYPE, NPC_NAME, 12)
	if not root then
		warn("[AnimalTrainerBootstrap] missing HumanoidRootPart/Torso on", model:GetFullName())
		return
	end
	setupProximity(root)

	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local okGui, errGui = pcall(function()
			NPCBootstrapKit.EnsureHeadGui(head, NPC_NAME, HEAD_COLORS)
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

NPCBootstrapKit.ScheduleRetries(tryBootstrap, {0, 1.0, 3.0})

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

print("[AnimalTrainerBootstrap] ready")
