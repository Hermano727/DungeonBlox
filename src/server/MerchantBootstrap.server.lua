--[[
    MerchantBootstrap
    Ensures all Merchant NPC models in Workspace are valid for MerchantShopClient +
    NPCService: sets attributes, CollectionService "NPC" tag, ProximityPrompt, Head gui.

    Multiple merchants are supported — tutorial-area models get NpcId "the_merchant_tutorial"
    while all others keep the canonical "the_merchant_noob", so each gets indexed
    independently in NPCService instead of conflicting on the same key.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local workspace          = game:GetService("Workspace")

local NPCRegistry = require(ReplicatedStorage:WaitForChild("NPCRegistry"))

local NPC_TYPE      = "Merchant"
local NPC_NAME      = "The Merchant"
local CANONICAL_ID  = "the_merchant_noob"
local TUTORIAL_ID   = "the_merchant_tutorial"

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
    local found = {}
    local seen  = {}
    for _, inst in ipairs(workspace:GetDescendants()) do
        if inst:IsA("Model") and not seen[inst] then
            local hasType = inst:GetAttribute("NpcType") == NPC_TYPE
            local hasName = inst.Name == NPC_NAME
            if hasType or hasName then
                seen[inst] = true
                table.insert(found, inst)
            end
        end
    end
    return found
end

local function ensureHeadGui(head, displayName)
    if head:FindFirstChild("gui") then return end
    local bb = Instance.new("BillboardGui")
    bb.Name           = "gui"
    bb.Size           = UDim2.new(8, 0, 1.5, 0)
    bb.StudsOffset    = Vector3.new(0, 2.2, 0)
    bb.AlwaysOnTop    = false
    bb.Parent         = head

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name                   = "name"
    nameLabel.Size                   = UDim2.new(1, 0, 0.45, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Font                   = Enum.Font.GothamBold
    nameLabel.TextSize               = 16
    nameLabel.TextColor3             = Color3.fromRGB(255, 210, 140)
    nameLabel.TextStrokeTransparency = 0.3
    nameLabel.Text                   = displayName
    nameLabel.Parent                 = bb
    pcall(function()
        local s = Instance.new("UIStroke")
        s.Color  = Color3.fromRGB(80, 40, 0)
        s.Parent = nameLabel
    end)

    local arrow = Instance.new("TextLabel")
    arrow.Name                   = "arrow"
    arrow.Size                   = UDim2.new(1, 0, 0.3, 0)
    arrow.Position               = UDim2.new(0, 0, 0.45, 0)
    arrow.BackgroundTransparency = 1
    arrow.Font                   = Enum.Font.GothamBold
    arrow.TextSize               = 13
    arrow.TextColor3             = Color3.fromRGB(255, 210, 140)
    arrow.Text                   = "\226\150\188"  -- ▼
    arrow.Parent                 = bb
    pcall(function()
        local s = Instance.new("UIStroke")
        s.Color  = Color3.fromRGB(80, 40, 0)
        s.Parent = arrow
    end)

    local dialog = Instance.new("TextLabel")
    dialog.Name                   = "dialog"
    dialog.Size                   = UDim2.new(1, 0, 1, 0)
    dialog.BackgroundTransparency = 1
    dialog.Font                   = Enum.Font.GothamMedium
    dialog.TextSize               = 13
    dialog.TextColor3             = Color3.new(1, 1, 1)
    dialog.TextWrapped            = true
    dialog.Visible                = false
    dialog.Text                   = ""
    dialog.Parent                 = bb
    pcall(function()
        local s = Instance.new("UIStroke")
        s.Color  = Color3.fromRGB(0, 0, 0)
        s.Parent = dialog
    end)
end

local function setupProximity(root)
    local pp = root:FindFirstChildOfClass("ProximityPrompt")
    if not pp then
        pp      = Instance.new("ProximityPrompt")
        pp.Name = "NpcTalkPrompt"
        pp.Parent = root
    end
    local reg = NPCRegistry.Get(NPC_TYPE)
    pp.ActionText             = (reg and reg.OpenShopPrompt) or "Browse Wares"
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

local function bootstrapModel(model)
    if not model or not model:IsA("Model") then return end

    local npcId = resolveNpcId(model)

    model:SetAttribute("NpcId",   npcId)
    model:SetAttribute("NpcType", NPC_TYPE)
    model:SetAttribute("NpcName", NPC_NAME)
    model:SetAttribute("MaxActivationDistance",
        math.max(tonumber(model:GetAttribute("MaxActivationDistance")) or 0, 12))

    local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
    if not (root and root:IsA("BasePart")) then
        warn("[MerchantBootstrap] missing HumanoidRootPart/Torso on", model:GetFullName())
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

bootstrapAll()

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
