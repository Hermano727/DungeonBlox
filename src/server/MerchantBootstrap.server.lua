--[[
    MerchantBootstrap
    Ensures all Merchant NPC models in Workspace are valid for MerchantShopClient +
    NPCService: attributes, CollectionService "NPC" tag, ProximityPrompt, Head gui.
    Shared boilerplate (head gui, proximity prompt, attribute/tag wiring, model
    discovery, retry scheduling) lives in NPCBootstrapKit — see that module's header
    for why watcher wiring below stays hand-rolled per NPC type instead of also
    being factored out.

    Multiple merchants are supported — tutorial-area models get NpcId "the_merchant_tutorial"
    while all others keep the canonical "the_merchant_noob", so each gets indexed
    independently in NPCService instead of conflicting on the same key.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local workspace          = game:GetService("Workspace")

local NPCRegistry     = require(ReplicatedStorage:WaitForChild("NPCRegistry"))
local NPCBootstrapKit = require(ReplicatedStorage:WaitForChild("NPCBootstrapKit"))

local NPC_TYPE      = "Merchant"
local NPC_NAME      = "The Merchant"
local CANONICAL_ID  = "the_merchant_noob"
local TUTORIAL_ID   = "the_merchant_tutorial"

local HEAD_COLORS = {
    text   = Color3.fromRGB(255, 210, 140),
    stroke = Color3.fromRGB(80, 40, 0),
}

-- Merchants inside TutorialPathway get a separate NpcId so they don't
-- collide with the canonical one in NPCService's npcIndex.
local function resolveNpcId(model)
    local anc = model.Parent
    while anc and anc ~= workspace do
        if anc.Name == "TutorialPathway" then
            return TUTORIAL_ID
        end
        anc = anc.Parent
    end
    return CANONICAL_ID
end

local function findAllMerchants()
    return NPCBootstrapKit.FindAllModelsByTypeOrName(NPC_TYPE, NPC_NAME)
end

local function setupProximity(root)
    local reg = NPCRegistry.Get(NPC_TYPE)
    NPCBootstrapKit.SetupProximityPrompt(root, {
        actionText            = (reg and reg.OpenShopPrompt) or "Browse Wares",
        objectText             = NPC_NAME,
        maxActivationDistance  = 12,
    })
end

local function bootstrapModel(model)
    if not model or not model:IsA("Model") then return end

    local npcId = resolveNpcId(model)

    local root = NPCBootstrapKit.TagAsNPC(model, npcId, NPC_TYPE, NPC_NAME, 12)
    if not root then
        warn("[MerchantBootstrap] missing HumanoidRootPart/Torso on", model:GetFullName())
        return
    end
    setupProximity(root)

    local head = model:FindFirstChild("Head")
    if head and head:IsA("BasePart") then
        local ok, err = pcall(NPCBootstrapKit.EnsureHeadGui, head, NPC_NAME, HEAD_COLORS)
        if not ok then
            warn("[MerchantBootstrap] Head gui failed:", err)
        end
    end
end

local function bootstrapAll()
    local models = findAllMerchants()
    if #models == 0 then
        warn("[MerchantBootstrap] no Merchant models found in Workspace")
        return
    end
    for _, model in ipairs(models) do
        local ok, err = pcall(bootstrapModel, model)
        if ok then
            print("[MerchantBootstrap] wired:", model:GetFullName(), "as", model:GetAttribute("NpcId"))
        else
            warn("[MerchantBootstrap] failed on", model:GetFullName(), ":", err)
        end
    end
end

NPCBootstrapKit.ScheduleRetries(bootstrapAll, {})

-- Re-wire any merchants added after server start (e.g. dynamic NPC spawning)
workspace.DescendantAdded:Connect(function(inst)
    if inst:IsA("Model")
        and (inst:GetAttribute("NpcType") == NPC_TYPE or inst.Name == NPC_NAME)
        and not CollectionService:HasTag(inst, "NPC")
    then
        task.defer(bootstrapModel, inst)
    end
end)

print("[MerchantBootstrap] ready")
