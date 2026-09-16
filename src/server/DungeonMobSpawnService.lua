--[[
    DungeonMobSpawnService  -- ServerScriptService

    Declarative, MODEL-ANCHORED dungeon spawners, registered PER INSTANCE.

    Every dungeon run clones DungeonRealmTemplate and parks the clone at its
    own far-away X offset. Spawners therefore cannot be registered once at
    boot -- they must be created against each clone, and destroyed with it.
    Registering against the master template would spawn mobs in a room no
    player is ever teleported into.

    Paths are relative to the REALM ROOT, not to Workspace, so the same
    definition resolves correctly inside every clone regardless of offset.

    Lifecycle (driven by DungeonInstanceService):
        launchDungeon        -> RegisterForRealm(clone, tier)  -> handle
        destroyInstanceRealm -> UnregisterForRealm(handle)
]]
local ServerScriptService = game:GetService("ServerScriptService")

local DungeonBossSpawner  = require(ServerScriptService:WaitForChild("DungeonBossSpawner"))
local DungeonTrashSpawner = require(ServerScriptService:WaitForChild("DungeonTrashSpawner"))

local DungeonMobSpawnService = {}

------------------------------------------------------------------
-- Definitions. Path / CeilingPath are RELATIVE TO THE REALM ROOT.
------------------------------------------------------------------

DungeonMobSpawnService.Definitions = {
    {
        Name        = "T1 Miasma Boss",
        Kind        = "Boss",
        MobID       = "MiasmaBoss",
        Path        = 'T1 BOSS ROOM/miasma/T1DungeonTemplate',
        CeilingPath = 'T1 BOSS ROOM/miasma/Miasma Ceiling',
        Radius      = 175,
        RespawnDelay = 30,
        ZoneName    = "T1Dungeon",
        Level       = 21,
    },
    -- Trash pack. Dungeon spawns are FLAT: one-shot, no respawn.
    {
        Name     = "T1 Boss Room Slimes",
        Kind     = "Trash",
        MobID    = "PlainsSlime",
        Path     = 'T1 BOSS ROOM/miasma/T1DungeonTemplate',
        Offset   = Vector3.new(0, 0, 120),
        Count    = 10,
        Radius   = 175,
        ZoneName = "T1Dungeon",
        Level    = 3,
    },
}

------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------

local function resolveFrom(root, path)
    local node = root
    for segment in string.gmatch(path, "[^/]+") do
        if not node then return nil end
        node = node:FindFirstChild(segment)
    end
    return node
end

local function anchorPosition(inst)
    if not inst then return nil end
    if inst:IsA("BasePart") then
        return inst.Position
    elseif inst:IsA("Model") then
        local ok, cf = pcall(function() return inst:GetPivot() end)
        if ok then return cf.Position end
    end
    return nil
end

------------------------------------------------------------------
-- Per-instance registration
------------------------------------------------------------------

local nextHandleId = 0
local handles = {}   -- [handleId] = { spawners = {...}, realm = Model }

function DungeonMobSpawnService.RegisterForRealm(realmRoot, tier)
    if not realmRoot then return nil end
    if not _G.MobSystem then
        warn("[DungeonMobSpawnService] _G.MobSystem not ready")
        return nil
    end

    nextHandleId = nextHandleId + 1
    local id = nextHandleId
    local created = {}

    for _, def in ipairs(DungeonMobSpawnService.Definitions) do
        local anchor = resolveFrom(realmRoot, def.Path)
        local pos = anchorPosition(anchor)
        if pos and def.Offset then pos = pos + def.Offset end

        if not pos then
            warn(("[DungeonMobSpawnService] '%s': unresolved Path '%s' in realm %s")
                :format(def.Name, def.Path, realmRoot.Name))
        else
            local spawner
            if def.Kind == "Boss" then
                local ceilingPos
                if def.CeilingPath then
                    ceilingPos = anchorPosition(resolveFrom(realmRoot, def.CeilingPath))
                end
                spawner = DungeonBossSpawner.new(pos, def.MobID, {
                    ceilingPosition  = ceilingPos,
                    activationRadius = def.Radius or 175,
                    respawnDelay     = def.RespawnDelay or 30,
                    zoneName         = def.ZoneName,
                    level            = def.Level,
                })
            else
                spawner = DungeonTrashSpawner.new(pos, def.MobID, def.Count or 3, {
                    activationRadius = def.Radius or 175,
                    zoneName         = def.ZoneName,
                    level            = def.Level,
                })
            end

            _G.MobSystem.RegisterSpawnerObject(spawner)
            table.insert(created, spawner)
        end
    end

    handles[id] = { spawners = created, realm = realmRoot }
    print(("[DungeonMobSpawnService] realm '%s': registered %d spawner(s) [handle %d]")
        :format(realmRoot.Name, #created, id))
    return id
end

function DungeonMobSpawnService.UnregisterForRealm(handleId)
    local h = handles[handleId]
    if not h then return false end
    local n = 0
    for _, spawner in ipairs(h.spawners) do
        if _G.MobSystem and _G.MobSystem.UnregisterSpawner then
            if _G.MobSystem.UnregisterSpawner(spawner) then n = n + 1 end
        end
    end
    handles[handleId] = nil
    print(("[DungeonMobSpawnService] handle %d torn down (%d spawner(s))"):format(handleId, n))
    return true
end

-- Tear down EVERY live handle. Called when a boss dies: the run is resolved,
-- so nothing should spawn during the victory lap. Without this a trash
-- spawner the party hadn't reached yet still fires when they wander into
-- range, and those kills pay out on the OVERWORLD path because the run has
-- already ended -- which looked like "dungeon XP is leaking".
function DungeonMobSpawnService.UnregisterAll()
    local n = 0
    for id in pairs(handles) do
        if DungeonMobSpawnService.UnregisterForRealm(id) then n = n + 1 end
    end
    return n
end

-- Boot-time no-op: every definition here is instance-scoped. Kept so
-- MobManager's existing call site stays valid.
function DungeonMobSpawnService.RegisterAll()
    print("[DungeonMobSpawnService] definitions are instance-scoped; " ..
          "spawners are created per dungeon run, not at boot")
    return 0
end

return DungeonMobSpawnService
