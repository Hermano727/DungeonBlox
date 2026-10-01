--[[
    HearthstoneService  (server-only)
    Handles teleport, location swap, and Innkeeper purchase logic.
    All functions are server-authoritative and push profile snapshots on success.

    Using the hearthstone is a CHANNEL (2026-10-01): StartChannel(player) checks you're out of
    combat (CombatStateService.IsInCombat) and off cooldown, then counts down
    HearthstoneConfig.CHANNEL_SECONDS[alignment] (Lawful 10 / Neutral 20 / Chaotic 30) before
    Teleport() fires. Any hit taken breaks it (CombatStateService.OnHit), as do death and
    respawn; CancelChannel(player) for the player's own cancel. The client sees it through two
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
                return CFrame.new(seed.position + Vector3.new(0, 3, 0))
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

    return CFrame.new(loc.position + Vector3.new(0, 3, 0))
end

-- Teleport player to their active hearthstone location (5-min cooldown).
function HearthstoneService.Teleport(player)
    local profile = getProfile(player)
    if not profile then return false, "no_profile" end

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

    hrp.CFrame = CFrame.new(loc.position + Vector3.new(0, 3, 0))
    hs.cooldownUntil = now + HearthstoneConfig.COOLDOWN
    DungeonProfile.PushProfile(player)
    return true, hs.cooldownUntil
end

-- ---------------------------------------------------------------------------
-- The channel
-- ---------------------------------------------------------------------------

local channels = {} -- [userId] = { thread, conns }

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
    end
    return true
end

function HearthstoneService.IsChanneling(player)
    return channels[player.UserId] ~= nil
end

-- Returns ok, seconds | false, reason ("in_combat", "cooldown", "already_channeling", ...).
function HearthstoneService.StartChannel(player)
    if channels[player.UserId] then return false, "already_channeling" end
    local profile = getProfile(player)
    if not profile then return false, "no_profile" end
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

    local ch = { conns = {} }
    channels[player.UserId] = ch
    table.insert(ch.conns, humanoid.Died:Connect(function() HearthstoneService.CancelChannel(player, "died") end))
    table.insert(ch.conns, player.CharacterRemoving:Connect(function() HearthstoneService.CancelChannel(player, "died") end))
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
