--[[
    FishermanNpcBootstrap
    Wires Workspace model "Fisherman" into the NPC client factory: attributes, CollectionService tag,
    ProximityPrompt + Head dialog billboard (DialogModule contract).
    Shared boilerplate lives in NPCBootstrapKit — see that module's header for why
    watcher wiring below stays hand-rolled per NPC type instead of also being
    factored out.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local workspace = game:GetService("Workspace")

local NPCBootstrapKit = require(ReplicatedStorage:WaitForChild("NPCBootstrapKit"))

local HEAD_COLORS = {
    text   = Color3.fromRGB(200, 210, 220),
    stroke = Color3.fromRGB(40, 50, 60),
}

-- Wires every Model named "Fisherman" anywhere in Workspace, not just the first one found.
-- Sorted by full path so id assignment (fisherman_01, fisherman_02, ...) stays stable across restarts.
local function findAllFishermanModels()
    return NPCBootstrapKit.FindAllModelsByName("Fisherman")
end

local function setupNpcModel(model, npcName)
    local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
    if root then
        model.PrimaryPart = root
        NPCBootstrapKit.SetupProximityPrompt(root, {
            actionText            = "Talk",
            objectText             = npcName,
            maxActivationDistance  = 14,
        })
    end

    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
    end

    local head = model:FindFirstChild("Head")
    if head then
        NPCBootstrapKit.EnsureHeadGui(head, npcName, HEAD_COLORS, "Fisherman")
    end
end

local function ensureFisherman(model, npcId)
    model:SetAttribute("NpcId", npcId)
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

    if not CollectionService:HasTag(model, "NPC") then
        CollectionService:AddTag(model, "NPC")
    end
end

local function tryBootstrapAll()
    for i, model in ipairs(findAllFishermanModels()) do
        local npcId = (i == 1) and "fisherman_01" or string.format("fisherman_%02d", i)
        local ok, err = pcall(ensureFisherman, model, npcId)
        if ok then
            print("[FishermanNpcBootstrap] wired:", model:GetFullName(), "as", npcId)
        else
            warn("[FishermanNpcBootstrap] bootstrap failed:", err)
        end
    end
end

NPCBootstrapKit.ScheduleRetries(tryBootstrapAll, {0, 0.25, 0.5, 0.75, 1.0}, { sync = false })

workspace.DescendantAdded:Connect(function(inst)
    if inst.Name == "Fisherman" and inst:IsA("Model") then
        task.defer(tryBootstrapAll)
    end
end)

print("[FishermanNpcBootstrap] ready")
