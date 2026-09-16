--[[
    DungeonRunService  -- ServerScriptService

    Owns the dungeon run lifecycle: start, mob HP scaling by party size,
    score banking, and the end-of-run cash-out.

    Deliberately self-contained rather than wired into DungeonInstanceService,
    because that service currently cannot launch (it warns that
    Workspace.DungeonRealmTemplate is missing). This gives a testable run loop
    now; folding it into the real instance flow later is a matter of calling
    StartRun / EndRun from there instead of from the dev remotes.

    Drops are granted DIRECTLY to the inventory on cash-out (not spawned as
    world orbs) so the end-of-run summary can list exactly what you got.
]]
local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RunConfig     = require(ReplicatedStorage:WaitForChild("DungeonRunConfig"))
local PityConfig    = require(ReplicatedStorage:WaitForChild("LootPityConfig"))
local Types         = require(ReplicatedStorage:WaitForChild("ProfileTypes"))
local Pity          = require(ServerScriptService:WaitForChild("LootPityService"))
local DungeonScore  = require(ServerScriptService:WaitForChild("DungeonScoreService"))
local DungeonProfile= require(ServerScriptService:WaitForChild("ProfileService"))

local DungeonRunService = {}

local activeRun = nil   -- single shared run for now: { players = {}, size = n, scaling = {} }

------------------------------------------------------------------
-- Remotes
------------------------------------------------------------------
local function ensureRemotes()
    local ge = ReplicatedStorage:FindFirstChild("GameEvents")
    if not ge then
        ge = Instance.new("Folder"); ge.Name = "GameEvents"; ge.Parent = ReplicatedStorage
    end
    local function mk(cls, name)
        local x = ge:FindFirstChild(name)
        if not x then x = Instance.new(cls); x.Name = name; x.Parent = ge end
        return x
    end
    return mk("RemoteEvent", "DungeonRunStart"),
           mk("RemoteEvent", "DungeonRunEnd"),
           mk("RemoteEvent", "DungeonRunSummary"),
           mk("RemoteEvent", "DungeonExitWindow")
end

local evStart, evEnd, evSummary, evExit = ensureRemotes()

------------------------------------------------------------------
-- Public
------------------------------------------------------------------

function DungeonRunService.GetScaling()
    return activeRun and activeRun.scaling or nil
end

function DungeonRunService.IsActive()
    return activeRun ~= nil
end

function DungeonRunService.StartRun(playerList, tier)
    playerList = playerList or {}
    if #playerList == 0 then return false, "no players" end

    local scaling, size = RunConfig.Get(#playerList)
    activeRun = {
        players = playerList,
        size    = size,
        scaling = scaling,
        tier    = tier or 1,
    }

    for _, p in ipairs(playerList) do
        DungeonScore.StartRun(p, tier or 1, nil, size)
    end

    print(("[DungeonRunService] run started: %d player(s), HP x%.1f, %d score/kill")
        :format(size, scaling.HPMult, scaling.ScorePerKill))
    return true
end

function DungeonRunService.EndRunFor(player, reason)
    if not player then return nil end
    local summary = DungeonScore.EndRun(player, reason or "cleared", nil)
    if not summary then return nil end

    -- Grant straight to inventory and build a display list.
    local granted = {}
    for _, item in ipairs(summary.items or {}) do
        local okTpl, template = pcall(function() return item:toGrantTemplate() end)
        if okTpl and template then
            local valid = Types.ValidateItemTemplate(template)
            if valid then
                local okGrant = pcall(DungeonProfile.GrantItem, player, template, 1)
                if okGrant then
                    table.insert(granted, {
                        name   = template.name,
                        rarity = template.rarity,
                        level  = template.level,
                    })
                end
            end
        end
    end

    -- Pay out banked coins + XP. Both are ZERO unless the run completed --
    -- DungeonScoreService already zeroes them on death/leave and reports the
    -- forfeited amount separately so the summary can show what was lost.
    -- Coins are an ITEM (id "Coins"), not a currency field -- this is exactly
    -- what WorldLootService.grantMobDrop does for a coin pickup. There
    -- is no AddCurrency and no CurrencyService; guessing at one meant the
    -- grant silently did nothing inside its pcall.
    local coins = summary.coins or 0
    if coins > 0 then
        local okCoins, errCoins = DungeonProfile.GrantItemId(player, "Coins", coins)
        if not okCoins then
            warn("[DungeonRunService] coin grant failed: " .. tostring(errCoins))
            coins = 0
        end
    end

    local xp = summary.xp or 0
    if xp > 0 then
        -- Persist first, then the HUD popup. CombatXPClient reads the FIRST
        -- argument as the amount -- firing (name, xp, tier) makes it read a
        -- string and award nothing, which is the bug MobManager's live path
        -- avoids by sending the bare number.
        pcall(DungeonProfile.AddSkillXP, player, "combat", xp)
        local xpEvent = ReplicatedStorage:FindFirstChild("CombatXPEvent")
        if xpEvent then
            xpEvent:FireClient(player, xp)
        end
    end

    evSummary:FireClient(player, {
        reason    = reason,
        score     = summary.finalScore,
        kills     = summary.kills,
        drops     = granted,
        coins     = coins,
        xp        = xp,
        coinsLost = summary.coinsLost or 0,
        xpLost    = summary.xpLost or 0,
    })

    print(("[DungeonRunService] %s ended (%s): %d score, %d kills, %d drop(s)")
        :format(player.Name, tostring(reason), summary.finalScore, summary.kills, #granted))

    -- clear the shared run once everybody is out
    if activeRun then
        local anyLeft = false
        for _, p in ipairs(activeRun.players) do
            if DungeonScore.IsInRun(p) then anyLeft = true break end
        end
        if not anyLeft then activeRun = nil end
    end
    return granted
end

------------------------------------------------------------------
-- Post-clear exit window
--
-- Killing the boss ends the run but does NOT eject anyone. Players get
-- EXIT_WINDOW_SECONDS to loot, regroup and leave via the Leave button; when
-- it expires they're teleported to hearthstone.
--
-- Remaining trash is despawned at clear time (the boss is already dead).
------------------------------------------------------------------

local exitDeadlines = {}   -- [userId] = os.clock() deadline

local function despawnRemainingMobs()
    if not _G.MobSystem or not _G.MobSystem.GetActiveMobs then return 0 end
    local n = 0
    for _, mob in pairs(_G.MobSystem.GetActiveMobs()) do
        local zone = mob.SpawnerRef and mob.SpawnerRef.ZoneName
        if type(zone) == "string" and string.find(zone, "Dungeon", 1, true) then
            if mob.IsAlive and mob:IsAlive() and mob.Model then
                pcall(function() mob.Model:Destroy() end)
                n = n + 1
            end
        end
    end
    return n
end

function DungeonRunService.BeginExitWindow(players)
    local seconds = RunConfig.EXIT_WINDOW_SECONDS or 300

    -- Order matters: retire the spawners FIRST, then despawn. Reversed, a
    -- spawner that hasn't triggered yet still fires during the exit window
    -- and repopulates the dungeon after it was supposedly cleared.
    do
        local ok, svc = pcall(function()
            return require(ServerScriptService:WaitForChild("DungeonMobSpawnService", 5))
        end)
        if ok and svc and svc.UnregisterAll then
            local torn = svc.UnregisterAll()
            if torn > 0 then
                print(("[DungeonRunService] retired %d spawner handle(s) at clear"):format(torn))
            end
        end
    end

    local killed = despawnRemainingMobs()
    print(("[DungeonRunService] clear -- despawned %d remaining mob(s), %ds to exit")
        :format(killed, seconds))

    local deadline = os.clock() + seconds
    for _, plr in ipairs(players or {}) do
        exitDeadlines[plr.UserId] = deadline
        evExit:FireClient(plr, { seconds = seconds })
    end

    task.delay(seconds, function()
        for _, plr in ipairs(players or {}) do
            if plr and plr.Parent and exitDeadlines[plr.UserId] then
                exitDeadlines[plr.UserId] = nil
                -- Hearthstone teleport is the fallback exit; if the service
                -- isn't reachable, DungeonInstanceService's own teardown will
                -- still pull them out when the realm is destroyed.
                local ok = pcall(function()
                    local hs = ServerScriptService:FindFirstChild("HearthstoneService")
                    if hs then require(hs).TeleportToHearth(plr) end
                end)
                if not ok then
                    warn("[DungeonRunService] hearthstone teleport failed for " .. plr.Name)
                end
            end
        end
    end)
end

function DungeonRunService.CancelExitWindow(player)
    if player then exitDeadlines[player.UserId] = nil end
end

------------------------------------------------------------------
-- Dev remotes
------------------------------------------------------------------

evStart.OnServerEvent:Connect(function(player)
    DungeonRunService.StartRun({ player }, 1)
end)

evEnd.OnServerEvent:Connect(function(player)
    DungeonRunService.EndRunFor(player, "cleared")
end)

-- Dying mid-run cashes out at full value (the key was already paid).
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(char)
        local hum = char:WaitForChild("Humanoid", 10)
        if not hum then return end
        hum.Died:Connect(function()
            if DungeonScore.IsInRun(player) then
                DungeonRunService.EndRunFor(player, "died")
            end
        end)
    end)
end)

print("[DungeonRunService] ready")
return DungeonRunService
