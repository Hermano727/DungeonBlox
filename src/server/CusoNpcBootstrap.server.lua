--[[
    CusoNpcBootstrap
    Wires Workspace model "Cuso" into the NPC client factory: attributes, CollectionService tag,
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
    text   = Color3.fromRGB(255, 220, 150),
    stroke = Color3.fromRGB(80, 60, 20),
}

-- Wires every Model named "Cuso" anywhere in Workspace, not just the first one found.
-- Sorted by full path so id assignment (cuso_01, cuso_02, ...) stays stable across restarts.
local function findAllCusoModels()
    return NPCBootstrapKit.FindAllModelsByName("Cuso")
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
        NPCBootstrapKit.EnsureHeadGui(head, npcName, HEAD_COLORS, "Cuso")
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
NPCBootstrapKit.ScheduleRetries(tryBootstrapAll, {0, 0.25, 0.5, 0.75, 1.0}, { sync = false })

workspace.DescendantAdded:Connect(function(inst)
    if inst.Name == "Cuso" and inst:IsA("Model") then
        task.defer(tryBootstrapAll)
    end
end)

print("[CusoNpcBootstrap] ready")
