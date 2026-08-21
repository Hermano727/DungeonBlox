--[[
	InnkeeperBootstrap
	Ensures Workspace "Innkeeper" is a valid NPC for MerchantShopClient + NPCService:
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

local NPC_ID = "innkeeper_01"
local NPC_TYPE = "Innkeeper"
local NPC_NAME = "Innkeeper"

local HEAD_COLORS = {
	text   = Color3.fromRGB(255, 230, 200),
	stroke = Color3.fromRGB(60, 40, 25),
}

local function findInnkeeperModel()
	local direct = workspace:FindFirstChild("Innkeeper")
	if direct and direct:IsA("Model") then
		return direct
	end
	local deep = workspace:FindFirstChild("Innkeeper", true)
	if deep and deep:IsA("Model") then
		return deep
	end
	return nil
end

local function setupProximity(root)
	local reg = NPCRegistry.Get(NPC_TYPE)
	NPCBootstrapKit.SetupProximityPrompt(root, {
		actionText            = (reg and reg.OpenShopPrompt) or "Book passage",
		objectText             = NPC_NAME,
		maxActivationDistance  = 12,
	})
end

local function bootstrap(model)
	if not model or not model:IsA("Model") then
		return
	end

	local root = NPCBootstrapKit.TagAsNPC(model, NPC_ID, NPC_TYPE, NPC_NAME, 12)
	if not root then
		warn("[InnkeeperBootstrap] missing HumanoidRootPart/Torso on Innkeeper")
		return
	end
	setupProximity(root)

	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local okGui, errGui = pcall(function()
			NPCBootstrapKit.EnsureHeadGui(head, NPC_NAME, HEAD_COLORS)
		end)
		if not okGui then
			warn("[InnkeeperBootstrap] Head.gui setup failed:", errGui)
		end
	else
		warn("[InnkeeperBootstrap] missing Head on Innkeeper")
	end
end

local function tryBootstrap()
	local m = findInnkeeperModel()
	if not m then
		return
	end
	local ok, err = pcall(function()
		bootstrap(m)
	end)
	if ok then
		print("[InnkeeperBootstrap] wired:", m:GetFullName())
	else
		warn("[InnkeeperBootstrap] bootstrap failed:", err)
	end
end

NPCBootstrapKit.ScheduleRetries(tryBootstrap, {0, 1.0, 3.0})

workspace.ChildAdded:Connect(function(ch)
	if ch.Name == "Innkeeper" and ch:IsA("Model") then
		task.defer(tryBootstrap)
	end
end)

workspace.DescendantAdded:Connect(function(inst)
	if inst:IsA("Model") and inst.Name == "Innkeeper" then
		task.defer(tryBootstrap)
	end
end)

print("[InnkeeperBootstrap] ready")
