-- Actual server source under mocks: no game instances, networking or gameplay are driven.
return function(sources)
    local checks = 0
    local function check(value, label) assert(value, label); checks += 1 end
    local function signal()
        local callbacks = {}
        return {
            Connect = function(_, fn) table.insert(callbacks, fn); return {Disconnect = function() end} end,
            Fire = function(_, ...) for _, fn in ipairs(callbacks) do fn(...) end end,
        }
    end
    local now = 100
    local identity = {}
    identity.ToObjectSpace = function() return identity end
    setmetatable(identity, {__mul = function() return identity end})
    local function container()
        return {WaitForChild = function(_, name) return name end, FindFirstChild = function() return nil end}
    end
    local configChunk = assert(loadstring(sources.Config))
    setfenv(configChunk, setmetatable({Color3 = {fromRGB = function() return {} end}}, {__index = getfenv()}))
    local config = configChunk()
    local profile = {inventory = {}, chestSlots = {}, hotbar = {}}
    local hum = {Health = 10, MaxHealth = 1000}
    local root = {CFrame = identity, Position = {}}
    local charAttrs = {}
    local character = {GetAttribute = function(_, key) return charAttrs[key] end, SetAttribute = function(_, key, value) charAttrs[key] = value end, Parent = true, GetChildren = function() return {} end,
        FindFirstChildOfClass = function() return hum end,
        FindFirstChild = function(_, name) return name == 'HumanoidRootPart' and root or nil end}
    local player = {UserId = 1, Parent = true, Character = character}
    local players = {PlayerAdded = signal(), PlayerRemoving = signal(),
        GetPlayers = function() return {player} end, GetPlayerByUserId = function() return player end}
    local run = {Heartbeat = signal()}
    local remotes = {}
    local function remote(name)
        local r = {OnServerEvent = signal(), messages = {}}
        r.FireClient = function(_, recipient, ...) table.insert(r.messages, {...}) end
        remotes[name] = r
        return r
    end
    local util = {
        EnsureGameEventsFolder = container,
        EnsureRemoteEvent = function(_, name) return remote(name) end,
        EnsureRemoteFunction = function(_, name) return remote(name) end,
        FindHotbarSlotForUuid = function(_, uuid) return table.find(profile.hotbar, uuid) end,
        NewRateLimiter = function(interval)
            local last = -math.huge
            return {Check = function() if now - last < interval then return false end; last = now; return true end,
                Clear = function() end}
        end,
    }
    local failConsume = false
    local consumed = {}
    local profiles = {Get = function() return profile end, Load = function() return profile end,
        ConsumeFromStack = function(_, uuid, amount)
            if failConsume then return false end
            local item = profile.inventory[uuid]
            if not item or item.count < amount then return false end
            item.count -= amount
            table.insert(consumed, uuid)
            if item.count == 0 then profile.inventory[uuid] = nil end
            return true
        end}
    local modules = {ProfileService = profiles, ConsumableRequestUtil = util, PotionConfig = config,
        PotionDrinkConfig = {AUDIENCE_RADIUS = 90, BONE_GRIP = identity, CORK_POP_TIME = .25, ANIMATION_DURATION = 1.1},
        PotionAnimations = {T1_POTION_DRINK = 'published'}}
    local rs = container()
    rs.WaitForChild = function(_, name)
        if name == 'Assets' then return {WaitForChild = function() return {WaitForChild = function() return 'PotionAnimations' end} end} end
        return name
    end
    local services = {Players = players, RunService = run, ReplicatedStorage = rs,
        ServerScriptService = container(), ServerStorage = container()}
    local env = setmetatable({game = {GetService = function(_, name) return services[name] end},
        workspace = {GetServerTimeNow = function() return now end},
        require = function(name) return assert(modules[name], name) end,
        os = {clock = function() return now end}, task = {defer = function(fn) fn() end},
        Instance = {new = container}, CFrame = {new = function() return identity end}, print = function() end,
    }, {__index = getfenv()})
    local actionChunk = assert(loadstring(sources.Action))
    setfenv(actionChunk, env); modules.PotionAction = actionChunk()
    local server = assert(loadstring(sources.Server, 'PotionService.mock'))
    setfenv(server, env); server()
    local function charges() return remotes.RequestPotionCharges.OnServerInvoke(player) end
    local function quick() remotes.QuickDrinkPotion.OnServerEvent:Fire(player) end
    local function reset()
        players.PlayerRemoving:Fire(player)
        profile.inventory, profile.chestSlots, profile.hotbar = {}, {}, {}
        table.clear(consumed); table.clear(remotes.PotionDrunk.messages)
        table.clear(remotes.PotionDrinkRejected.messages)
        hum.Health = 10
        now += 1000
    end
    local start = now
    check(charges().count == 3, 'one shared initial pool')
    profile.inventory.minor = {itemId = 'MinorPotion', count = 4}
    profile.inventory.medium = {itemId = 'MediumPotion', count = 1}
    profile.inventory.bank = {itemId = 'MediumPotion', count = 20}
    profile.chestSlots[1] = 'bank'
    quick(); quick(); quick()
    check(charges().count == 2 and #consumed == 1, 'spam during animation spends exactly one charge and item')
    check(remotes.PotionDrinkRejected.messages[1][1] == 'drinking', 'busy refusal is explicit')
    check(consumed[1] == 'medium' and profile.inventory.bank.count == 20, 'strongest carried first; bank excluded')
    check(#remotes.PotionDrunk.messages == 1, 'one confirmation for one accepted action')
    check(modules.PotionAction.IsLocked(character), 'server lock active during animation')
    run.Heartbeat:Fire(0)
    check(hum.Health == 10, 'no healing on acceptance')
    now = start + 1.1; run.Heartbeat:Fire(0)
    check(not modules.PotionAction.IsLocked(character) and hum.Health == 10, 'completion unlocks without an instant heal')
    now = start + 2.10001; run.Heartbeat:Fire(0)
    check(hum.Health == 40, 'first tick is one tenth of medium total')
    quick()
    now = start + 3.20002; run.Heartbeat:Fire(0)
    now = start + 4.20003; run.Heartbeat:Fire(0)
    check(hum.Health == 115, 'independent medium and minor healing ticks stack')
    quick()
    now = start + 5.30004; run.Heartbeat:Fire(0)
    check(charges().count == 0 and #consumed == 3, 'three completed sequential actions empty shared pool')
    quick()
    check(#consumed == 3 and #remotes.PotionDrunk.messages == 3, 'empty pool never consumes or animates')
    now = start + 16; run.Heartbeat:Fire(0)
    check(hum.Health == 610, 'slow-frame catch-up gives exactly ten ticks per potion, never extra healing')
    now = start + 39.9; run.Heartbeat:Fire(0)
    check(charges().count == 0, 'no early recharge')
    now = start + 40; run.Heartbeat:Fire(0)
    check(charges().count == 1 and charges().nextChargeAt == start + 80, 'one charge at forty with next absolute deadline')
    now += 8; quick()
    check(charges().count == 0 and math.abs(charges().secondsUntilNext - 32) < .001, 'later drink does not reset recharge clock')
    now = start + 80; run.Heartbeat:Fire(0)
    check(charges().count == 1, 'next charge remains at eighty seconds')
    reset(); quick()
    check(charges().count == 3 and remotes.PotionDrinkRejected.messages[1][1] == 'no_potions', 'empty inventory never locks or spends')
    profile.inventory.last = {itemId = 'MinorPotion', count = 1}
    failConsume = true; quick()
    check(charges().count == 3 and not modules.PotionAction.IsLocked(character), 'failed consumption releases lock and charge reservation')
    failConsume = false; quick()
    check(charges().count == 2 and remotes.PotionDrunk.messages[1][1].itemGone == true, 'last inventory item works without a held tool')
    hum.Health = 0; run.Heartbeat:Fire(0)
    hum.Health = 10; now += 20; run.Heartbeat:Fire(0)
    check(hum.Health == 10 and not modules.PotionAction.IsLocked(character), 'death cancels unfinished healing and releases action')
    reset()
    profile.inventory.only = {itemId = 'MinorPotion', count = 3}
    remotes.DrinkPotionRequest.OnServerEvent:Fire(player, 'only')
    check(charges().count == 3 and #consumed == 0, 'held request validates hotbar/tool')
    quick()
    now += 1.10001 -- No Heartbeat between completion and the next request.
    quick()
    check(charges().count == 1 and #consumed == 2 and #remotes.PotionDrunk.messages == 2,
        'request at animation deadline completes old action before validating the next')
    check(hum.Health == 10, 'back-to-back completion still waits for the first healing tick')
    return checks
end
