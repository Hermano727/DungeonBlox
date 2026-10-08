local PotionAction = require(game:GetService("ReplicatedStorage"):WaitForChild("PotionAction"))
--[[
    HearthstoneService  (server-only)
    Handles teleport, location swap, and Innkeeper purchase logic.
    All functions are server-authoritative and push profile snapshots on success.

    Using the hearthstone is a CHANNEL (2026-10-01): StartChannel(player) checks you're out of
    combat (CombatStateService.IsInCombat) and off cooldown, then counts down
    HearthstoneConfig.CHANNEL_SECONDS[alignment] (Lawful 10 / Neutral 20 / Chaotic 30) before
    Teleport() fires. Any hit taken breaks it (CombatStateService.OnHit), as do death and
    respawn, as does moving more than MOVE_TOLERANCE or entering combat in any way (checked every
    Heartbeat); CancelChannel(player) for the player's own cancel. In the tutorial it's
    HearthstoneConfig.TUTORIAL_CHANNEL_SECONDS (3). The client sees it through two
    player attributes: HearthChannelEnd (workspace:GetServerTimeNow() it completes at) and
    HearthChannelLength (seconds), cleared when it ends; an interruption is also flashed
    (GameEvents/CenterFlashNotify).
]]

local CollectionService   = game:GetService("CollectionService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local HearthstoneConfig   = require(ReplicatedStorage:WaitForChild("HearthstoneConfig"))
local HearthstoneRegistry = require(ServerScriptService:WaitForChild("HearthstoneRegistry"))
local DungeonProfile      = require(ServerScriptService:WaitForChild("ProfileService"))
local CombatStateService  = require(ServerScriptService:WaitForChild("CombatStateService"))
local Players             = game:GetService("Players")

local HearthstoneService = {}

local RemoteUtils = require(ReplicatedStorage:WaitForChild("RemoteUtils"))
local travelEvent = RemoteUtils.EnsureRemoteEvent(RemoteUtils.EnsureFolder(ReplicatedStorage, "GameEvents"), "TravelScreen")
local TRAVEL_FADE = 0.6 -- the screen is up before the move
local TRAVEL_SETTLE = 0.8 -- and stays a moment after, while the destination settles

local function getProfile(player)
    local p = DungeonProfile.Get(player) or DungeonProfile.Load(player)
    if type(p) ~= "table" then return nil end
    -- Back-fill hearthstone block for profiles saved before this feature.
    if type(p.hearthstone) ~= "table" then
        p.hearthstone = { active = "oakhaven", unlocked = { "oakhaven" }, cooldownUntil = 0 }
    end
    if type(p.hearthstone.unlocked) ~= "table" then
        p.hearthstone.unlocked = { "oakhaven" }
    end
    -- Ensure every free seed location is always unlocked for all players.
    local unlocked = p.hearthstone.unlocked
    for _, seed in ipairs(HearthstoneConfig.SEED_LOCATIONS) do
        local found = false
        for _, id in ipairs(unlocked) do
            if id == seed.id then found = true break end
        end
        if not found then
            table.insert(unlocked, seed.id)
        end
    end
    return p
end

-- A town's hearth totem decides where its location puts you: any Workspace model with the
-- attribute HearthLocation = <location id> (Oakhaven's OakHaven_HearthTotem = "oakhaven").
-- You arrive just in front of it, facing out. Without one, the location's saved position.
local ARRIVE_IN_FRONT = 6 -- studs out from the totem's face
local totemCache = {} -- [locationId] = model

local function findTotem(locationId)
    local cached = totemCache[locationId]
    if cached and cached:IsDescendantOf(workspace) and cached:GetAttribute("HearthLocation") == locationId then
        return cached
    end
    totemCache[locationId] = nil
    for _, inst in ipairs(workspace:GetDescendants()) do
        if inst:IsA("Model") and inst:GetAttribute("HearthLocation") == locationId then
            totemCache[locationId] = inst
            return inst
        end
    end
    return nil
end

local function arrivalCFrame(loc)
    local totem = loc.id and findTotem(loc.id)
    if totem then
        local pivot = totem:GetPivot() -- the waystone's pivot sits at its base
        local look = Vector3.new(pivot.LookVector.X, 0, pivot.LookVector.Z).Unit
        local pos = pivot.Position + look * ARRIVE_IN_FRONT + Vector3.new(0, 3, 0)
        return CFrame.lookAt(pos, pos + look)
    end
    return CFrame.new(loc.position + Vector3.new(0, 3, 0))
end

-- Returns the CFrame of `player`'s active hearthstone location (same lookup Teleport()
-- uses, minus the cooldown/mutation), for callers that just need "where does this player's
-- hearthstone point right now" -- e.g. the dungeon system's "Leave Dungeon" button. Falls
-- back to the Oakhaven seed location (HearthstoneConfig.SEED_LOCATIONS) if the profile has
-- no usable hearthstone or the registry lookup fails for any reason, so this never returns
-- nil -- callers can always teleport somewhere sane.
function HearthstoneService.GetHearthstoneLocation(player)
    local function oakhavenFallback()
        for _, seed in ipairs(HearthstoneConfig.SEED_LOCATIONS) do
            if seed.id == "oakhaven" then
                return arrivalCFrame(seed)
            end
        end
        -- Should be unreachable (oakhaven is always seeded), but never return nil.
        return CFrame.new(0, 10, 0)
    end

    local profile = getProfile(player)
    if not profile then
        return oakhavenFallback()
    end

    local hs = profile.hearthstone
    local loc = hs and HearthstoneRegistry.GetLocation(hs.active or "oakhaven")
    if not loc then
        return oakhavenFallback()
    end

    return arrivalCFrame(loc)
end

-- Teleport player to their active hearthstone location (5-min cooldown).
function HearthstoneService.Teleport(player)
    local profile = getProfile(player)
    if not profile then return false, "no_profile" end
    if not HearthstoneService.IsUnlocked(profile) then return false, "locked" end

    local hs  = profile.hearthstone
    local now = os.time()
    if now < (hs.cooldownUntil or 0) then
        return false, "cooldown", hs.cooldownUntil - now
    end

    local loc = HearthstoneRegistry.GetLocation(hs.active or "oakhaven")
    if not loc then return false, "invalid_location" end

    local char = player.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false, "no_character" end

    hs.cooldownUntil = now + HearthstoneConfig.COOLDOWN
    -- The travel screen (TravelScreenClient) covers the jump: shown first, the destination
    -- streams in behind it, then the move, then it lifts.
    travelEvent:FireClient(player, { phase = "show", name = loc.name or loc.id })
    task.wait(TRAVEL_FADE)
    local arrive = arrivalCFrame(loc)
    pcall(function() player:RequestStreamAroundAsync(arrive.Position, 10) end)
    if hrp.Parent then
        hrp.CFrame = arrive
    end
    DungeonProfile.PushProfile(player)
    task.wait(TRAVEL_SETTLE)
    travelEvent:FireClient(player, { phase = "hide" })
    return true, hs.cooldownUntil
end

-- Has this profile unlocked the Hearthstone? (the tutorial's totem; older saves have it)
function HearthstoneService.IsUnlocked(profile)
    return type(profile) == "table" and type(profile.flags) == "table" and profile.flags.hearthstoneUnlocked == true
end

-- ---------------------------------------------------------------------------
-- The channel
-- ---------------------------------------------------------------------------

local channels = {} -- [userId] = { thread, conns }
local MOVE_TOLERANCE = 1.5 -- studs (horizontal) you can drift before moving cancels it
local RunService = game:GetService("RunService")

local function flash(player, text)
    local ge = ReplicatedStorage:FindFirstChild("GameEvents")
    local ev = ge and ge:FindFirstChild("CenterFlashNotify")
    if ev and ev:IsA("RemoteEvent") then
        pcall(ev.FireClient, ev, player, text)
    end
end

local function clearChannel(player)
    local ch = channels[player.UserId]
    if not ch then return nil end
    channels[player.UserId] = nil
    for _, conn in ipairs(ch.conns) do conn:Disconnect() end
    player:SetAttribute("HearthChannelEnd", nil)
    player:SetAttribute("HearthChannelLength", nil)
    return ch
end

-- Stops a channel in progress (no-op without one). `reason` nil = the player's own cancel.
function HearthstoneService.CancelChannel(player, reason)
    local ch = clearChannel(player)
    if not ch then return false end
    if coroutine.running() ~= ch.thread then pcall(task.cancel, ch.thread) end
    if reason == "combat" then
        flash(player, "Hearthstone interrupted!")
    elseif reason == "moved" then
        flash(player, "You moved. Hearthstone cancelled.")
    end
    return true
end

function HearthstoneService.IsChanneling(player)
    return channels[player.UserId] ~= nil
end

-- Returns ok, seconds | false, reason ("in_combat", "cooldown", "already_channeling", ...).
function HearthstoneService.StartChannel(player)
	if PotionAction.IsLocked(player.Character) then return false, "drinking" end
    if channels[player.UserId] then return false, "already_channeling" end
    local profile = getProfile(player)
    if not profile then return false, "no_profile" end
    if not HearthstoneService.IsUnlocked(profile) then return false, "locked" end
    local hs = profile.hearthstone
    local now = os.time()
    if now < (hs.cooldownUntil or 0) then
        return false, "cooldown", hs.cooldownUntil - now
    end
    if CombatStateService.IsInCombat(player) then return false, "in_combat" end
    if not HearthstoneRegistry.GetLocation(hs.active or "oakhaven") then return false, "invalid_location" end
    local char = player.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return false, "no_character" end

    local alignment = DungeonProfile.GetAlignment(player)
    local seconds = HearthstoneConfig.CHANNEL_SECONDS[alignment] or HearthstoneConfig.CHANNEL_SECONDS.Neutral
    -- The tutorial's hearth out is short (from the server's own profile flag).
    local tutorial = type(profile.flags) == "table" and profile.flags.tutorial
    if type(tutorial) == "table" and tutorial.done ~= true then
        seconds = HearthstoneConfig.TUTORIAL_CHANNEL_SECONDS
    end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return false, "no_character" end
    local startPos = root.Position

    local ch = { conns = {} }
    channels[player.UserId] = ch
    table.insert(ch.conns, humanoid.Died:Connect(function() HearthstoneService.CancelChannel(player, "died") end))
    table.insert(ch.conns, player.CharacterRemoving:Connect(function() HearthstoneService.CancelChannel(player, "died") end))
    -- Moving or entering combat (dealing damage too, not only taking a hit) cancels it.
    table.insert(ch.conns, RunService.Heartbeat:Connect(function()
        if channels[player.UserId] ~= ch then return end
        if CombatStateService.IsInCombat(player) then
            HearthstoneService.CancelChannel(player, "combat")
            return
        end
        local drift = root.Position - startPos
        if Vector3.new(drift.X, 0, drift.Z).Magnitude > MOVE_TOLERANCE then
            HearthstoneService.CancelChannel(player, "moved")
        end
    end))
    player:SetAttribute("HearthChannelLength", seconds)
    player:SetAttribute("HearthChannelEnd", workspace:GetServerTimeNow() + seconds)

    ch.thread = task.delay(seconds, function()
        if channels[player.UserId] ~= ch then return end
        clearChannel(player)
        if not player.Parent then return end
        -- Defensive: combat could have started the same frame the timer ran out.
        if CombatStateService.IsInCombat(player) then
            flash(player, "Hearthstone interrupted!")
            return
        end
        local ok = HearthstoneService.Teleport(player)
        if not ok then flash(player, "Your hearthstone fizzles.") end
    end)
    return true, seconds
end

-- A hit breaks the channel (it only works out of combat).
CombatStateService.OnHit(function(player)
    HearthstoneService.CancelChannel(player, "combat")
end)
Players.PlayerRemoving:Connect(function(player)
    HearthstoneService.CancelChannel(player, "left")
end)

-- Swap the player's active hearthstone to a location they already own.
function HearthstoneService.SwapLocation(player, locationId)
    if type(locationId) ~= "string" or locationId == "" then
        return false, "bad_arg"
    end
    local profile = getProfile(player)
    if not profile then return false, "no_profile" end

    local hs    = profile.hearthstone
    local owned = false
    for _, id in ipairs(hs.unlocked) do
        if id == locationId then owned = true break end
    end
    if not owned then return false, "not_owned" end

    hs.active = locationId
    DungeonProfile.PushProfile(player)
    return true
end

-- Purchase a new hearthstone location from an Innkeeper NPC.
-- Player must be within 16 studs of an NPC tagged "NPC" with NpcType == "Innkeeper".
function HearthstoneService.PurchaseLocation(player, locationId)
    if type(locationId) ~= "string" or locationId == "" then
        return false, "bad_arg"
    end

    -- Proximity check against any Innkeeper NPC.
    local char = player.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false, "no_character" end

    local nearInnkeeper = false
    for _, model in ipairs(CollectionService:GetTagged("NPC")) do
        if model:GetAttribute("NpcType") == "Innkeeper" then
            local pp = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
            if pp and (hrp.Position - pp.Position).Magnitude <= 16 then
                nearInnkeeper = true
                break
            end
        end
    end
    if not nearInnkeeper then return false, "too_far" end

    local loc = HearthstoneRegistry.GetLocation(locationId)
    if not loc then return false, "unknown_location" end

    local profile = getProfile(player)
    if not profile then return false, "no_profile" end

    local hs = profile.hearthstone
    for _, id in ipairs(hs.unlocked) do
        if id == locationId then return false, "already_owned" end
    end

    local cost = loc.cost or 0
    if cost > 0 then
        local balance = profile.currencies.Coins or 0
        if balance < cost then return false, "insufficient_funds" end
        profile.currencies.Coins = balance - cost
    end

    table.insert(hs.unlocked, locationId)
    DungeonProfile.PushProfile(player)
    return true, profile.currencies.Coins or 0
end

return HearthstoneService
