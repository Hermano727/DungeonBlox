--[[
    DevService
    Server-side handler for the DevPlacer tool.
    Creates/deletes spawner marker Parts on behalf of authorised developers.

    Mob placements (F8): registers spawns via _G.MobSystem and persists them with
    ServerScriptService.MobDevSpawnStore (DataStore) so camps survive Studio Stop / server restarts.
    Visual markers are recreated on startup under Workspace.Spawners/DevMobMarkers.

    All events are silently dropped for non-dev players.

    Add your Roblox UserId(s) to DEV_USERIDS below.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

-- !! Add every developer's UserId here !!
local DEV_USERIDS = {
	706604079,
	62963717,
	446429007,
	49263337
    -- e.g. 123456789
}

local function isDev(player)
    for _, id in ipairs(DEV_USERIDS) do
        if player.UserId == id then return true end
    end
    -- Also allow in solo Studio sessions (place owner / team create)
    return game:GetService("RunService"):IsStudio()
end

---------------------------------------------------------------------------
-- RemoteEvent / RemoteFunction setup
---------------------------------------------------------------------------

local GameEvents = ReplicatedStorage:WaitForChild("GameEvents", 10)
if not GameEvents then error("[DevService] GameEvents folder missing") end

local function makeEvent(name)
    local e = Instance.new("RemoteEvent")
    e.Name   = name
    e.Parent = GameEvents
    return e
end
local function makeFunc(name)
    local f = Instance.new("RemoteFunction")
    f.Name   = name
    f.Parent = GameEvents
    return f
end

local evPlace    = makeEvent("DevPlaceSpawner")
local evDelete   = makeEvent("DevDeleteSpawner")
local rfList     = makeFunc("DevListSpawners")
local rfPlaceZone = makeFunc("DevPlaceZone")

local MobDevSpawnStore = require(ServerScriptService:WaitForChild("MobDevSpawnStore"))
local NpcDevSpawnStore = require(ServerScriptService:WaitForChild("NpcDevSpawnStore"))
local ZoneService      = require(ServerScriptService:WaitForChild("ZoneService"))

---------------------------------------------------------------------------
-- Spawner folders (created by SpawnerService; wait for them)
---------------------------------------------------------------------------

local spawnersRoot    = workspace:WaitForChild("Spawners",       15)
local mobFolder       = spawnersRoot and spawnersRoot:WaitForChild("MobSpawners",  10)
local npcFolder       = spawnersRoot and spawnersRoot:WaitForChild("NPCSpawners",  10)

if not spawnersRoot or not mobFolder or not npcFolder then
    warn("[DevService] Spawner folders not ready — is SpawnerService running?")
end

-- Visual-only markers for F8 mob spawns (MobManager loads camps from MobDevSpawnStore / DataStore)
local devMobMarkers = spawnersRoot and spawnersRoot:FindFirstChild("DevMobMarkers")
if not devMobMarkers and spawnersRoot then
    devMobMarkers = Instance.new("Folder")
    devMobMarkers.Name = "DevMobMarkers"
    devMobMarkers.Parent = spawnersRoot
end

local devMobSpawnerByPart = {} -- [Part] = spawner object returned by _G.MobSystem.CreateSpawner

local function waitForMobSystem(timeout)
    local t = 0
    while not _G.MobSystem and t < timeout do
        task.wait(0.1)
        t += 0.1
    end
    return _G.MobSystem ~= nil
end

local function registerDevMobWithMobManager(attrs, position)
    if not waitForMobSystem(12) then
        warn("[DevService] _G.MobSystem not ready — mob spawner not registered")
        return nil
    end
    local zone = attrs.ZoneName or "Default"
    return _G.MobSystem.CreateSpawner(
        position,
        attrs.MobId,
        attrs.RespawnDelay,
        attrs.Count,
        attrs.ActivationRadius,
        zone,
        nil
    )
end

local function unregisterMobSpawnerObject(spawnerObj)
    if not spawnerObj then
        return
    end
    for i = #spawnerObj.SpawnedMobs, 1, -1 do
        local mob = spawnerObj.SpawnedMobs[i]
        if mob and mob:IsAlive() then
            mob:Die()
        end
    end
    local active = _G.MobSystem and _G.MobSystem.GetActiveSpawners()
    if active then
        for i = #active, 1, -1 do
            if active[i] == spawnerObj then
                table.remove(active, i)
                break
            end
        end
    end
end

local function stopDevMobSpawner(part)
    local spawnerObj = devMobSpawnerByPart[part]
    if not spawnerObj then
        return
    end
    unregisterMobSpawnerObject(spawnerObj)
    devMobSpawnerByPart[part] = nil
end

local function deleteMobDevSpawnBySpawnId(spawnId)
    if type(spawnId) ~= "string" or spawnId == "" then
        return
    end
    local marker = nil
    if devMobMarkers then
        for _, ch in ipairs(devMobMarkers:GetChildren()) do
            if ch:IsA("BasePart") and ch:GetAttribute("DevSpawnId") == spawnId then
                marker = ch
                break
            end
        end
    end
    if marker then
        stopDevMobSpawner(marker)
        marker:Destroy()
    else
        local sp = MobDevSpawnStore.getSpawner(spawnId)
        if sp then
            unregisterMobSpawnerObject(sp)
            for p, sp0 in pairs(devMobSpawnerByPart) do
                if sp0 == sp then
                    devMobSpawnerByPart[p] = nil
                end
            end
        end
    end
    MobDevSpawnStore.removeSpawn(spawnId)
end

---------------------------------------------------------------------------
-- Billboard label helper
---------------------------------------------------------------------------

local function applyLabel(part, text, color)
    local bb = Instance.new("BillboardGui")
    bb.Name          = "SpawnerLabel"
    bb.Adornee       = part
    bb.AlwaysOnTop   = true
    bb.Size          = UDim2.fromOffset(180, 40)
    bb.StudsOffset   = Vector3.new(0, 2.5, 0)
    bb.Parent        = part

    local lbl = Instance.new("TextLabel", bb)
    lbl.Size                   = UDim2.fromScale(1, 1)
    lbl.BackgroundTransparency = 1
    lbl.Font                   = Enum.Font.GothamBold
    lbl.TextSize               = 14
    lbl.TextColor3             = color or Color3.new(1, 1, 1)
    lbl.TextStrokeTransparency = 0.4
    lbl.Text                   = text
end

---------------------------------------------------------------------------
-- Part factory
---------------------------------------------------------------------------

local function makeMobSpawnerPart(attrs, position, spawnId)
    local part            = Instance.new("Part")
    part.Name             = "SpawnerMarker"
    part.Shape            = Enum.PartType.Cylinder
    part.Size             = Vector3.new(1, attrs.ActivationRadius * 2, attrs.ActivationRadius * 2)
    part.CFrame           = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
    part.Anchored         = true
    part.CanCollide       = false
    part.CanQuery         = false
    part.CanTouch         = false
    part.CastShadow       = false
    part.Transparency     = 0.80
    part.Color            = Color3.fromRGB(220, 60, 60)   -- red = mob
    part.Material         = Enum.Material.Neon

    part:SetAttribute("MobId",            attrs.MobId)
    part:SetAttribute("Count",            attrs.Count)
    part:SetAttribute("RespawnDelay",     attrs.RespawnDelay)
    part:SetAttribute("ActivationRadius", attrs.ActivationRadius)
    part:SetAttribute("ZoneName",         attrs.ZoneName or "Default")
    part:SetAttribute("Active",           true)
    part:SetAttribute("SpawnerType",      "Mob")
    if type(spawnId) == "string" and spawnId ~= "" then
        part:SetAttribute("DevSpawnId", spawnId)
    end

    CollectionService:AddTag(part, "SpawnerMarker")

    local label = string.format("MOB  %s  x%d", attrs.MobId, attrs.Count)
    applyLabel(part, label, Color3.fromRGB(255, 140, 140))

    part.Parent = devMobMarkers or mobFolder
    return part
end

local function makeNpcSpawnerPart(attrs, position, spawnId)
    local part            = Instance.new("Part")
    part.Name             = "SpawnerMarker"
    part.Shape            = Enum.PartType.Cylinder
    part.Size             = Vector3.new(1, 6, 6)
    part.CFrame           = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
    part.Anchored         = true
    part.CanCollide       = false
    part.CanQuery         = false
    part.CanTouch         = false
    part.CastShadow       = false
    part.Transparency     = 0.80
    part.Color            = Color3.fromRGB(60, 140, 220)   -- blue = NPC
    part.Material         = Enum.Material.Neon

    part:SetAttribute("NpcId",   attrs.NpcId)
    part:SetAttribute("NpcType", attrs.NpcType)
    part:SetAttribute("NpcName", attrs.NpcName)
    part:SetAttribute("SpawnerType", "NPC")
    if type(spawnId) == "string" and spawnId ~= "" then
        part:SetAttribute("DevSpawnId", spawnId)
    end

    CollectionService:AddTag(part, "SpawnerMarker")

    local label = string.format("NPC  %s\n%s", attrs.NpcName, attrs.NpcType)
    applyLabel(part, label, Color3.fromRGB(140, 200, 255))

    part.Parent = npcFolder
    return part
end

-------------------------------------------------------------------------
-- Zone placement helper (shared by RemoteEvent + RemoteFunction)
-------------------------------------------------------------------------

local function placeZoneFromClientData(data, position)
	if type(data) ~= "table" then
		return { ok = false, error = "bad_data" }
	end
	if typeof(position) ~= "Vector3" then
		return { ok = false, error = "bad_position" }
	end
	local alignment = data.Alignment
	if type(alignment) ~= "string" then
		return { ok = false, error = "bad_alignment" }
	end
	local banned = type(data.BannedAlignments) == "table" and data.BannedAlignments or {}
	local cleanedBanned = {}
	for _, a in ipairs(banned) do
		if type(a) == "string" then table.insert(cleanedBanned, a) end
	end
	local cleanedPoints = nil
	if type(data.Points) == "table" then
		cleanedPoints = {}
		for _, p in ipairs(data.Points) do
			if type(p) == "table" then
				local x = tonumber(p.x)
				local z = tonumber(p.z)
				if x and z then
					table.insert(cleanedPoints, { x = x, z = z })
				end
			end
		end
		if #cleanedPoints < 3 then
			cleanedPoints = nil
		end
	end
	local attrs = {
		name             = type(data.Name) == "string" and data.Name ~= "" and data.Name or nil,
		alignment        = alignment,
		bannedAlignments = cleanedBanned,
		points           = cleanedPoints,
		radius           = cleanedPoints and nil or (tonumber(data.Radius) or 60),
		isEliteZone      = data.IsEliteZone == true,
		eliteMobId       = type(data.EliteMobId) == "string" and data.EliteMobId or "",
	}
	local ok, zOrErr = ZoneService.AddZone(attrs, position)
	if not ok then
		return { ok = false, error = tostring(zOrErr) }
	end
	return { ok = true, zone = zOrErr }
end

---------------------------------------------------------------------------
-- Event handlers
---------------------------------------------------------------------------

evPlace.OnServerEvent:Connect(function(player, data)
    if not isDev(player) then return end
    if type(data) ~= "table" then return end

    local position = data.Position
    if typeof(position) ~= "Vector3" then return end

    if data.SpawnerType == "Mob" then
        local mobId = data.MobId
        if type(mobId) ~= "string" or mobId == "" then return end
        local attrs = {
            MobId            = mobId,
            Count            = math.clamp(math.floor(tonumber(data.Count)            or 3),  1, 20),
            RespawnDelay     = math.clamp(math.floor(tonumber(data.RespawnDelay)     or 10), 1, 300),
            ActivationRadius = math.clamp(math.floor(tonumber(data.ActivationRadius) or 100),10, 500),
            ZoneName         = type(data.ZoneName) == "string" and data.ZoneName or "Default",
        }
        local sp = registerDevMobWithMobManager(attrs, position)
        if not sp then
            warn("[DevService] Mob spawner not created — MobManager not ready")
            return
        end
        local persist = MobDevSpawnStore.persistenceEnabled()
        local spawnId = nil
        if persist then
            local okSave, idOrErr = MobDevSpawnStore.addSpawn(attrs, position)
            if not okSave then
                warn("[DevService] Mob spawner not persisted: " .. tostring(idOrErr))
                unregisterMobSpawnerObject(sp)
                return
            end
            spawnId = idOrErr
            MobDevSpawnStore.attachRuntimeSpawner(spawnId, sp)
        end
        local part = makeMobSpawnerPart(attrs, position, spawnId)
        devMobSpawnerByPart[part] = sp
        print(
            "[DevService] "
                .. player.Name
                .. " placed MOB spawner: "
                .. mobId
                .. (persist and " (DataStore)" or " (session only — enable Studio API access or MobDevSpawnsPersistInLive)")
        )

    elseif data.SpawnerType == "NPC" then
        local npcType = data.NpcType
        local npcName = data.NpcName
        local npcId   = data.NpcId
        if type(npcType) ~= "string" or type(npcName) ~= "string" or type(npcId) ~= "string" then return end
        if npcName == "" or npcId == "" then return end
        local attrs = { NpcId = npcId, NpcType = npcType, NpcName = npcName }
        local okSave, idOrErr = NpcDevSpawnStore.addSpawn(attrs, position)
        local spawnId = okSave and idOrErr or nil
        if not okSave then
            warn("[DevService] NPC spawner not persisted: " .. tostring(idOrErr))
        end
        makeNpcSpawnerPart(attrs, position, spawnId)
        print("[DevService] " .. player.Name .. " placed NPC spawner: " .. npcName .. " (" .. npcType .. ")" .. (spawnId and " (DataStore)" or " (session only)"))

    elseif data.SpawnerType == "Zone" then
        local result = placeZoneFromClientData(data, position)
        if not result.ok then
            warn("[DevService] Zone add failed: " .. tostring(result.error))
            return
        end
        local z = result.zone
        local shapeLabel = z.points and ("poly " .. #z.points .. " pts") or ("r=" .. tostring(z.radius or "?"))
        print(string.format("[DevService] %s placed ZONE %s (%s, %s) at %s",
            player.Name, z.name, z.alignment, shapeLabel, tostring(position)))
    end
end)

evDelete.OnServerEvent:Connect(function(player, payload)
    if not isDev(player) then return end

    -- Zone deletion path. Routed via Type="Zone" so the same RemoteEvent can
    -- delete both mob spawners (SpawnId) and zones (ZoneId) without ambiguity.
    if type(payload) == "table" and payload.Type == "Zone" and type(payload.ZoneId) == "string" and payload.ZoneId ~= "" then
        local ok = ZoneService.RemoveZone(payload.ZoneId)
        if ok then
            print("[DevService] " .. player.Name .. " deleted zone " .. payload.ZoneId)
        end
        return
    end

    if type(payload) == "table" and type(payload.SpawnId) == "string" and payload.SpawnId ~= "" then
        local sid = payload.SpawnId
        -- Determine type by checking the tagged marker part
        local markerType = nil
        for _, p in ipairs(CollectionService:GetTagged("SpawnerMarker")) do
            if p:GetAttribute("DevSpawnId") == sid then
                markerType = p:GetAttribute("SpawnerType")
                break
            end
        end
        if markerType == "NPC" then
            NpcDevSpawnStore.removeSpawn(sid)
            for _, p in ipairs(CollectionService:GetTagged("SpawnerMarker")) do
                if p:GetAttribute("DevSpawnId") == sid then p:Destroy(); break end
            end
            print("[DevService] " .. player.Name .. " deleted NPC spawn id " .. sid)
        else
            deleteMobDevSpawnBySpawnId(sid)
            print("[DevService] " .. player.Name .. " deleted mob spawn id " .. sid)
        end
        return
    end

    local part = payload
    if not part or not part:IsA("BasePart") then return end

    local sid = part:GetAttribute("DevSpawnId")
    local st = part:GetAttribute("SpawnerType")
    if st == "Mob" and type(sid) == "string" and sid ~= "" then
        deleteMobDevSpawnBySpawnId(sid)
        print("[DevService] " .. player.Name .. " deleted mob spawner (marker)")
        return
    end

    stopDevMobSpawner(part)
    if not spawnersRoot or not part:IsDescendantOf(spawnersRoot) then
        warn("[DevService] Delete rejected — Part not in Spawners folder")
        return
    end
    print("[DevService] " .. player.Name .. " deleted spawner at " .. tostring(part.Position))
    part:Destroy()
end)

rfList.OnServerInvoke = function(player)
    if not isDev(player) then return {} end

    if MobDevSpawnStore.persistenceEnabled() then
        MobDevSpawnStore.refreshCacheFromStore()
    end

    local out = {}
    local seenSpawnId = {}

    -- Zones (added before mobs/NPCs so the dev list sorts naturally by type).
    for _, z in ipairs(ZoneService.GetAllZones()) do
        table.insert(out, {
            SpawnerType = "Zone",
            Label       = z.points and #z.points >= 3
                and string.format("%s [%s %d pts%s]", z.name, z.alignment, #z.points, z.isEliteZone and ", elite" or "")
                or string.format("%s [%s r=%d%s]", z.name, z.alignment, z.radius or 0, z.isEliteZone and ", elite" or ""),
            Position    = z.center,
            Part        = nil,
            SpawnId     = nil,
            ZoneId      = z.id,
        })
    end

    for _, row in ipairs(MobDevSpawnStore.getCachedSpawns()) do
        if type(row) == "table" and type(row.id) == "string" and type(row.mobId) == "string" then
            seenSpawnId[row.id] = true
            local pos = Vector3.new(tonumber(row.x) or 0, tonumber(row.y) or 0, tonumber(row.z) or 0)
            local marker = nil
            if devMobMarkers then
                for _, ch in ipairs(devMobMarkers:GetChildren()) do
                    if ch:IsA("BasePart") and ch:GetAttribute("DevSpawnId") == row.id then
                        marker = ch
                        break
                    end
                end
            end
            table.insert(out, {
                SpawnerType = "Mob",
                Label = row.mobId,
                Position = pos,
                Part = marker,
                SpawnId = row.id,
            })
        end
    end

    for _, p in ipairs(CollectionService:GetTagged("SpawnerMarker")) do
        if p and p.Parent and p:GetAttribute("SpawnerType") == "NPC" then
            local sid = p:GetAttribute("DevSpawnId")
            table.insert(out, {
                SpawnerType = "NPC",
                Label = p:GetAttribute("NpcName") or "?",
                Position = p.Position,
                Part = p,
                SpawnId = (type(sid) == "string" and sid ~= "") and sid or nil,
            })
        end
    end



    if devMobMarkers then
        for _, ch in ipairs(devMobMarkers:GetChildren()) do
            if ch:IsA("BasePart") and ch:GetAttribute("SpawnerType") == "Mob" then
                local dsid = ch:GetAttribute("DevSpawnId")
                if type(dsid) == "string" and dsid ~= "" then
                    if not seenSpawnId[dsid] then
                        table.insert(out, {
                            SpawnerType = "Mob",
                            Label = ch:GetAttribute("MobId") or "?",
                            Position = ch.Position,
                            Part = ch,
                            SpawnId = dsid,
                        })
                    end
                else
                    table.insert(out, {
                        SpawnerType = "Mob",
                        Label = ch:GetAttribute("MobId") or "?",
                        Position = ch.Position,
                        Part = ch,
                        SpawnId = nil,
                    })
                end
            end
        end
    end

    return out
end

rfPlaceZone.OnServerInvoke = function(player, data)
	if not isDev(player) then
		return { ok = false, error = "not_dev" }
	end
	if type(data) ~= "table" then
		return { ok = false, error = "bad_data" }
	end
	return placeZoneFromClientData(data, data.Position)
end

task.defer(function()
    -- Reload NPC spawners from DataStore
    if npcFolder then
        for _, row in ipairs(NpcDevSpawnStore.loadInitial()) do
            if type(row) == "table" and type(row.id) == "string" then
                local attrs = { NpcId = row.npcId, NpcType = row.npcType, NpcName = row.npcName }
                local pos   = Vector3.new(tonumber(row.x) or 0, tonumber(row.y) or 0, tonumber(row.z) or 0)
                makeNpcSpawnerPart(attrs, pos, row.id)
            end
        end
    end

    if not devMobMarkers then
        return
    end
    for _, row in ipairs(MobDevSpawnStore.getCachedSpawns()) do
        if type(row) == "table" and type(row.id) == "string" and type(row.mobId) == "string" then
            local attrs = {
                MobId = row.mobId,
                Count = math.clamp(math.floor(tonumber(row.count) or 3), 1, 20),
                RespawnDelay = math.clamp(math.floor(tonumber(row.respawnDelay) or 10), 1, 300),
                ActivationRadius = math.clamp(math.floor(tonumber(row.activationRadius) or 100), 10, 500),
                ZoneName = type(row.zoneName) == "string" and row.zoneName ~= "" and row.zoneName or "Default",
            }
            local pos = Vector3.new(tonumber(row.x) or 0, tonumber(row.y) or 0, tonumber(row.z) or 0)
            local marker = makeMobSpawnerPart(attrs, pos, row.id)
            local sp = MobDevSpawnStore.getSpawner(row.id)
            if marker and sp then
                devMobSpawnerByPart[marker] = sp
            end
        end
    end
end)

print("[DevService] ready")
