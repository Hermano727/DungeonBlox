--[[
	DungeoneerBootstrap
	Ensures Workspace "Dungeoneer" is a valid NPC for MerchantShopClient + NPCService:
	attributes, CollectionService "NPC" tag, ProximityPrompt, Head.gui (DialogModule).
	Shared boilerplate lives in NPCBootstrapKit — see that module's header for why
	watcher wiring below stays hand-rolled per NPC type instead of also being
	factored out.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local workspace = game:GetService("Workspace")

local NPCRegistry     = require(ReplicatedStorage:WaitForChild("NPCRegistry"))
local NPCBootstrapKit = require(ReplicatedStorage:WaitForChild("NPCBootstrapKit"))

local NPC_ID = "dungeoneer_01"
local NPC_TYPE = "Dungeoneer"
local NPC_NAME = "Dungeoneer"

local HEAD_COLORS = {
	text   = Color3.fromRGB(200, 210, 255),
	stroke = Color3.fromRGB(30, 40, 80),
}

local function resolveNpcId(model)
	local anc = model.Parent
	while anc and anc ~= workspace do
		if anc.Name == "TutorialPathway" then
			return "dungeoneer_tutorial"
		end
		anc = anc.Parent
	end
	return NPC_ID
end

local function findAllDungeoneers()
	return NPCBootstrapKit.FindAllModelsByTypeOrName(NPC_TYPE, NPC_NAME)
end

local function setupProximity(root)
	local reg = NPCRegistry.Get(NPC_TYPE)
	NPCBootstrapKit.SetupProximityPrompt(root, {
		actionText            = (reg and reg.OpenShopPrompt) or "Trade key fragments",
		objectText             = NPC_NAME,
		maxActivationDistance  = 12,
	})
end

local function bootstrap(model, npcId)
	if not model or not model:IsA("Model") then
		return
	end

	local root = NPCBootstrapKit.TagAsNPC(model, npcId or NPC_ID, NPC_TYPE, NPC_NAME, 12)
	if not root then
		warn("[DungeoneerBootstrap] missing HumanoidRootPart/Torso on Dungeoneer")
		return
	end
	setupProximity(root)

	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local okGui, errGui = pcall(function()
			NPCBootstrapKit.EnsureHeadGui(head, NPC_NAME, HEAD_COLORS)
		end)
		if not okGui then
			warn("[DungeoneerBootstrap] Head.gui setup failed:", errGui)
		end
	else
		warn("[DungeoneerBootstrap] missing Head on Dungeoneer")
	end
end

local function tryBootstrapAll()
	for _, m in ipairs(findAllDungeoneers()) do
		local id     = resolveNpcId(m)
		local ok, err = pcall(bootstrap, m, id)
		if ok then
			print("[DungeoneerBootstrap] wired:", m:GetFullName(), "as", id)
		else
			warn("[DungeoneerBootstrap] bootstrap failed:", err)
		end
	end
end

NPCBootstrapKit.ScheduleRetries(tryBootstrapAll, {0, 1.0, 3.0})

workspace.DescendantAdded:Connect(function(inst)
	if inst:IsA("Model")
		and (inst:GetAttribute("NpcType") == NPC_TYPE or inst.Name == NPC_NAME)
		and not CollectionService:HasTag(inst, "NPC")
	then
		task.defer(function() bootstrap(inst, resolveNpcId(inst)) end)
	end
end)

print("[DungeoneerBootstrap] ready")
