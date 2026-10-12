--[[
    DungeonBossLootService  -- ServerScriptService
    Boss loot: flat chance per eligible player, independent of score/pity.
    Only players ALIVE when the boss dies are eligible.

    Who is a candidate is the CALLER's call (LootService.tryDropMythic): a dungeon boss rolls
    for its own instance's living, non-spectating members only. This used to roll for every
    player on the server (`Players:GetPlayers()`), so someone in town could receive a Miasma
    Mythic for a fight they were never in.

    Granting is immediate (a disconnect mid-show loses nothing); the clear sequence's Mythic
    Judgement only acts out the result later, and MythicBroadcast announces it then.
]]
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Builder   = require(ServerScriptService:WaitForChild("MythicItemBuilder"))
local ItemIdentity = require(ReplicatedStorage:WaitForChild("ItemIdentity"))
local DevRoster = require(ReplicatedStorage:WaitForChild("DevRoster"))
local ClearConfig = require(ReplicatedStorage:WaitForChild("DungeonClearConfig"))
local DungeonProfile = require(ServerScriptService:WaitForChild("ProfileService"))

local DungeonBossLootService = {}

local function isAlive(player)
    local char = player and player.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    return hum ~= nil and hum.Health > 0
end

-- F8 Mythic tab's forced outcome, honoured for devs only (the attribute is server-set by
-- DevService, but re-checked here so nothing else can ever rig a real player's roll).
local function forcedOutcome(player)
    if not DevRoster.IsDev(player) then return nil end
    local force = player:GetAttribute(ClearConfig.MYTHIC_FORCE_ATTR)
    if force == "win" or force == "loss" then return force end
    return nil
end

-- Rolls the boss's Mythic for each living candidate and grants the wins.
-- Returns { { player, item, template } } for the winners only.
function DungeonBossLootService.OnBossKilled(bossMob, candidates)
    if not bossMob then return {} end
    local mobId = bossMob.MobID or "Unknown"
    local results = {}

    for _, player in ipairs(candidates or {}) do
        if isAlive(player) then
            local item = Builder.TryRollForMob(mobId, forcedOutcome(player))
            if item then
                -- Grant STRAIGHT to inventory rather than spawning a world orb.
                -- SpawnMobDrop requires a dropSpec table whose `kind` is one of
                -- coins/item_template/item_id; passing the raw item object made
                -- it bail to nil, so the Mythic silently never appeared while
                -- the caller still logged success.
                local okTpl, template = pcall(function() return item:toGrantTemplate() end)
                if not okTpl or not template then
                    warn("[DungeonBossLootService] toGrantTemplate failed for " .. tostring(mobId))
                else
                    -- `def` = the Mythic key, so ItemStatRanges can resolve this
                    -- item's authored substat windows rather than the generic ones.
                    local okGrant, errGrant = DungeonProfile.GrantItem(player, template, 1, {
                        by = player,
                        kind = ItemIdentity.SOURCE.DUNGEON_BOSS,
                        src = mobId,
                        def = item.mythicKey,
                    })
                    if okGrant then
                        table.insert(results, { player = player, item = item, template = template })
                    else
                        warn("[DungeonBossLootService] Mythic grant failed: " .. tostring(errGrant))
                    end
                end
            end
        end
    end
    return results
end

return DungeonBossLootService
