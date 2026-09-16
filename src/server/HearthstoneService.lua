--[[
    HearthstoneService  (server-only)
    Handles teleport, location swap, and Innkeeper purchase logic.
    All functions are server-authoritative and push profile snapshots on success.
]]

local CollectionService   = game:GetService("CollectionService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local HearthstoneConfig   = require(ReplicatedStorage:WaitForChild("HearthstoneConfig"))
local HearthstoneRegistry = require(ServerScriptService:WaitForChild("HearthstoneRegistry"))
local DungeonProfile      = require(ServerScriptService:WaitForChild("ProfileService"))

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
