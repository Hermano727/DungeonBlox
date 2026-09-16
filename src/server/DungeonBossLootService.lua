--[[
    DungeonBossLootService  -- ServerScriptService
    Boss loot: flat chance per eligible player, independent of score/pity.
    Only players ALIVE when the boss dies are eligible.
]]
local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Builder   = require(ServerScriptService:WaitForChild("MythicItemBuilder"))
local DungeonProfile = require(ServerScriptService:WaitForChild("ProfileService"))
local WorldLoot = require(ServerScriptService:WaitForChild("WorldLootService"))

local DungeonBossLootService = {}

local function isAlive(player)
    local char = player and player.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    return hum ~= nil and hum.Health > 0
end

function DungeonBossLootService.OnBossKilled(bossMob, candidates, dropPosition)
    if not bossMob then return {} end
    local mobId = bossMob.MobID or "Unknown"
    local results = {}

    for _, player in ipairs(candidates or {}) do
        if isAlive(player) then
            local item = Builder.TryRollForMob(mobId)
            if item then
                -- Grant STRAIGHT to inventory rather than spawning a world orb.
                -- SpawnMobDrop requires a dropSpec table whose `kind` is one of
                -- coins/item_template/item_id; passing the raw item object made
                -- it bail to nil, so the Mythic silently never appeared while
                -- the caller still logged success. Dungeon rewards shouldn't
                -- hit the floor anyway -- they surface in the run summary.
                local okTpl, template = pcall(function() return item:toGrantTemplate() end)
                if not okTpl or not template then
                    warn("[DungeonBossLootService] toGrantTemplate failed for " .. tostring(mobId))
                else
                    local okGrant, errGrant = DungeonProfile.GrantItem(player, template, 1)
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

function DungeonBossLootService.OnBossKilledForAll(bossMob, dropPosition)
    return DungeonBossLootService.OnBossKilled(bossMob, Players:GetPlayers(), dropPosition)
end

return DungeonBossLootService
