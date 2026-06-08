--[[
    SpawnerService
    Reads spawner marker Parts from Workspace/Spawners/ and wires them into
    the existing MobManager pipeline via _G.MobSystem.CreateSpawner.

    F8 DevPlacer mob markers live under Workspace/Spawners/DevMobMarkers/ (visual only);
    DevService persists mob camps via DataStore (ServerScriptService.MobDevSpawnStore) and MobManager loads them on boot.

    NPC model workflow:
      1. Drop any character model into ServerStorage/NPCModels/
      2. Name it <NpcType>Template, <NpcType>NPC, or just <NpcType>
         (e.g. BlacksmithTemplate, BlacksmithNPC, or Blacksmith)
      3. That is all -- SpawnerService adds ProximityPrompt + BillboardGui at runtime

    MobSpawner Part attributes (Workspace/Spawners/MobSpawners/):
      MobId, Count, RespawnDelay, ActivationRadius, ZoneName, Active

    NPCSpawner Part attributes (Workspace/Spawners/NPCSpawners/):
      NpcId, NpcType, NpcName
]]

local CollectionService = game:GetService("CollectionService")
local ServerStorage     = game:GetService("ServerStorage")

local function waitForMobSystem(timeout)
    local t = 0
    while not _G.MobSystem do
        task.wait(0.1); t += 0.1
        if t >= timeout then
            warn("[SpawnerService] _G.MobSystem not available after "..timeout.."s")
            return false
        end
    end
    return true
end

---------------------------------------------------------------------------
-- Workspace folder setup
---------------------------------------------------------------------------

local spawnersRoot = workspace:FindFirstChild("Spawners")
if not spawnersRoot then
    spawnersRoot = Instance.new("Folder")
    spawnersRoot.Name = "Spawners"
    spawnersRoot.Parent = workspace
end

local mobFolder = spawnersRoot:FindFirstChild("MobSpawners")
if not mobFolder then
    mobFolder = Instance.new("Folder")
    mobFolder.Name = "MobSpawners"
    mobFolder.Parent = spawnersRoot
end

local npcFolder = spawnersRoot:FindFirstChild("NPCSpawners")
if not npcFolder then
    npcFolder = Instance.new("Folder")
    npcFolder.Name = "NPCSpawners"
    npcFolder.Parent = spawnersRoot
end

---------------------------------------------------------------------------
-- NPC component builder
-- Adds ProximityPrompt + BillboardGui to any raw character model.
-- No manual model prep required.
---------------------------------------------------------------------------

local function setupNpcModel(model, npcName)
    -- Find root part: prefer HumanoidRootPart, fall back to Torso
    local root = model:FindFirstChild("HumanoidRootPart")
        or model:FindFirstChild("Torso")
    if root then
        model.PrimaryPart = root
        -- Add ProximityPrompt if missing
        if not root:FindFirstChildOfClass("ProximityPrompt") then
            local pp = Instance.new("ProximityPrompt")
            pp.ActionText = "Talk"
            pp.ObjectText = npcName
            pp.KeyboardKeyCode = Enum.KeyCode.E
            pp.MaxActivationDistance = 10
            pp.Parent = root
            CollectionService:AddTag(pp, "NPCprompt")
        end
    end

    -- Disable built-in Humanoid name/health display to avoid duplicate labels
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
    end

    -- Add BillboardGui to Head if missing (DialogModule reads from Head.gui)
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

---------------------------------------------------------------------------
-- NPC template lookup
---------------------------------------------------------------------------

local npcModelsFolder = ServerStorage:FindFirstChild("NPCModels")

local function getNpcTemplate(npcType)
    if not npcModelsFolder then
        npcModelsFolder = ServerStorage:FindFirstChild("NPCModels")
    end
    if not npcModelsFolder then return nil end
    -- Trim whitespace from npcType to be resilient against attribute typos
    local t = npcType:match("^%s*(.-)%s*$")
    -- Flexible naming: <NpcType>Template, <NpcType>NPC, <NpcType>, or generic NPCTemplate
    -- Also try trimmed model names in case the model itself has leading/trailing spaces
    for _, suffix in ipairs({"Template", "NPC", ""}) do
        local name = t .. suffix
        for _, child in ipairs(npcModelsFolder:GetChildren()) do
            if child.Name:match("^%s*(.-)%s*$") == name then
                return child
            end
        end
    end
    return npcModelsFolder:FindFirstChild("NPCTemplate")
end

---------------------------------------------------------------------------
-- Active spawner tracking
---------------------------------------------------------------------------

local mobSpawnerMap = {}  -- [Part] = MobSpawner object
local npcModelMap   = {}  -- [Part] = spawned NPC Model

---------------------------------------------------------------------------
-- Mob spawner
---------------------------------------------------------------------------

local function startMobSpawner(part)
    if not part:IsA("BasePart") then return end
    if mobSpawnerMap[part] then return end
    if part:GetAttribute("Active") == false then return end
    if not _G.MobSystem then return end

    local mobId = part:GetAttribute("MobId")
    if type(mobId) ~= "string" or mobId == "" then
        warn("[SpawnerService] MobSpawner missing MobId: " .. part:GetFullName()); return
    end

    local count   = math.clamp(math.floor(part:GetAttribute("Count")            or 3),  1, 20)
    local delay   = math.clamp(part:GetAttribute("RespawnDelay")                or 10,  1, 300)
    local radius  = math.clamp(part:GetAttribute("ActivationRadius")            or 100, 10, 500)
    local zone    = part:GetAttribute("ZoneName") or "Default"

    -- Optional per-spawner level range
    local minLevelAttr = part:GetAttribute("MinLevel") or part:GetAttribute("MinMobLevel")
    local maxLevelAttr = part:GetAttribute("MaxLevel") or part:GetAttribute("MaxMobLevel")

    local levelRange = nil
    if minLevelAttr ~= nil or maxLevelAttr ~= nil then
        levelRange = {
            minLevel = tonumber(minLevelAttr),
            maxLevel = tonumber(maxLevelAttr),
        }
    end

    local spawnerObj = _G.MobSystem.CreateSpawner(part.Position, mobId, delay, count, radius, zone, levelRange)
    mobSpawnerMap[part] = spawnerObj
    print(string.format("[SpawnerService] MOB spawner: %s x%d at %s", mobId, count, tostring(part.Position)))
end

local function stopMobSpawner(part)
    local spawnerObj = mobSpawnerMap[part]
    if not spawnerObj then return end
    for i = #spawnerObj.SpawnedMobs, 1, -1 do
        local mob = spawnerObj.SpawnedMobs[i]
        if mob and mob:IsAlive() then mob:Die() end
    end
    local active = _G.MobSystem and _G.MobSystem.GetActiveSpawners()
    if active then
        for i = #active, 1, -1 do
            if active[i] == spawnerObj then table.remove(active, i); break end
        end
    end
    mobSpawnerMap[part] = nil
end

---------------------------------------------------------------------------
-- NPC spawner
---------------------------------------------------------------------------

local function startNpcSpawner(part)
    if not part:IsA("BasePart") then return end
    if npcModelMap[part] then return end

    local npcId   = part:GetAttribute("NpcId")
    local npcType = part:GetAttribute("NpcType")
    local npcName = part:GetAttribute("NpcName")
    if type(npcId) ~= "string" or type(npcType) ~= "string" or type(npcName) ~= "string" then
        warn("[SpawnerService] NPCSpawner missing attributes: " .. part:GetFullName()); return
    end

    local template = getNpcTemplate(npcType)
    if not template then
        warn("[SpawnerService] No template for '"..npcType.."'. Add ServerStorage/NPCModels/"..npcType.."Template (or "..npcType.."NPC / "..npcType..")"); return
    end

    local model = template:Clone()
    model.Name = npcId
    model:SetAttribute("NpcId",                 npcId)
    model:SetAttribute("NpcType",               npcType)
    model:SetAttribute("NpcName",               npcName)
    model:SetAttribute("MaxActivationDistance", part:GetAttribute("MaxActivationDistance") or 10)

    -- Auto-add ProximityPrompt + BillboardGui to any raw model
    setupNpcModel(model, npcName)

    -- Smart ground placement: raycast down from spawner to find walkable surface
    local spawnPos = part.Position
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = {model}
    local rayResult = workspace:Raycast(
        spawnPos + Vector3.new(0, 50, 0),
        Vector3.new(0, -100, 0),
        rayParams
    )
    if rayResult then
        -- Offset up by half the model's height so feet rest on the ground
        local _, modelSize = model:GetBoundingBox()
        spawnPos = rayResult.Position + Vector3.new(0, modelSize.Y / 2, 0)
    else
        -- No ground found; use a safe default offset above the spawner
        spawnPos = spawnPos + Vector3.new(0, 3, 0)
    end

    model:PivotTo(CFrame.new(spawnPos))
    model.Parent = workspace
    CollectionService:AddTag(model, "NPC")

    npcModelMap[part] = model
    print(string.format("[SpawnerService] NPC spawned: %s (%s)", npcName, npcType))
end

local function stopNpcSpawner(part)
    local model = npcModelMap[part]
    if not model then return end
    CollectionService:RemoveTag(model, "NPC")
    model:Destroy()
    npcModelMap[part] = nil
end

---------------------------------------------------------------------------
-- Watch for runtime additions / removals (DevService)
---------------------------------------------------------------------------

local function onAdded(inst)
    if not inst:IsA("BasePart") then return end
    if inst:IsDescendantOf(mobFolder) then startMobSpawner(inst)
    elseif inst:IsDescendantOf(npcFolder) then startNpcSpawner(inst) end
end

local function onRemoving(inst)
    if not inst:IsA("BasePart") then return end
    if mobSpawnerMap[inst] then stopMobSpawner(inst)
    elseif npcModelMap[inst] then stopNpcSpawner(inst) end
end

spawnersRoot.DescendantAdded:Connect(onAdded)
spawnersRoot.DescendantRemoving:Connect(onRemoving)

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------

task.spawn(function()
    local mobReady = waitForMobSystem(10)
    if mobReady then
        for _, part in ipairs(mobFolder:GetChildren()) do startMobSpawner(part) end
    end
    for _, part in ipairs(npcFolder:GetChildren()) do startNpcSpawner(part) end
    print("[SpawnerService] ready -- "..#mobFolder:GetChildren().." mob, "..#npcFolder:GetChildren().." NPC spawner(s)")
end)

