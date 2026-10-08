-- Actual request coordinator under deterministic client/network/asset-loading mocks.
return function(source)
    local checks, now, jobs = 0, 0, {}
    local function check(value, label) assert(value, label); checks += 1 end
    local function signal()
        local listeners = {}
        return {Connect = function(_, fn) table.insert(listeners, fn); return {Disconnect = function() end} end,
            Fire = function(_, ...) for _, fn in ipairs(listeners) do fn(...) end end}
    end
    local function resume(thread)
        local ok, waitFor = coroutine.resume(thread)
        assert(ok, waitFor)
        if coroutine.status(thread) ~= 'dead' then table.insert(jobs, {time = now + waitFor, thread = thread}) end
    end
    local function advance(dt)
        local target = now + dt
        while true do
            local index, earliest
            for i, job in ipairs(jobs) do if job.time <= target and (not earliest or job.time < earliest) then index, earliest = i, job.time end end
            if not index then break end
            now = earliest; resume(table.remove(jobs, index).thread)
        end
        now = target
    end
    local attrs = {}
    local hum = {Health = 100}
    local character = {FindFirstChildOfClass = function() return hum end}
    local player = {Character = character, CharacterRemoving = signal(),
        GetAttribute = function(_, key) return attrs[key] end, SetAttribute = function(_, key, value) attrs[key] = value end}
    local remotes = {}
    for _, name in ipairs({'PotionDrunk','PotionDrinkRejected','QuickDrinkPotion','DrinkPotionRequest'}) do
        local remote = {OnClientEvent = signal(), sent = 0}
        remote.FireServer = function(_, uuid) remote.sent += 1; remote.uuid = uuid end
        remotes[name] = remote
    end
    local events = {WaitForChild = function(_, name) return remotes[name] end, FindFirstChild = function(_, name) return remotes[name] end}
    local rs = {WaitForChild = function(_, name) return name == 'GameEvents' and events or name end,
        FindFirstChild = function(_, name) return name == 'GameEvents' and events or nil end}
    local locked, menu = false, false
    local modules = {PotionAction = {IsLocked = function() return locked end},
        PotionDrinkConfig = {REQUEST_READY_TIMEOUT = 10}, InteractionLock = {IsLocked = function() return menu end}}
    local services = {Players = {LocalPlayer = player}, ReplicatedStorage = rs}
    local env = setmetatable({game = {GetService = function(_, name) return services[name] end},
        require = function(name) return modules[name] end,
        Instance = {new = function() local event = signal(); return {Event = event, Fire = function(_, ...) event:Fire(...) end} end},
        os = {clock = function() return now end},
        task = {spawn = function(fn) resume(coroutine.create(fn)) end, wait = function(dt) return coroutine.yield(dt) end,
            delay = function(dt, fn) table.insert(jobs, {time = now + dt, thread = coroutine.create(fn)}) end}}, {__index = getfenv()})
    local chunk = assert(loadstring(source)); setfenv(chunk, env); local request = chunk()
    local feedback
    request.Feedback.Event:Connect(function(reason) feedback = reason end)
    request.Drink(); request.Drink(); advance(2)
    check(remotes.QuickDrinkPotion.sent == 0 and feedback == 'loading', 'one press waits for animation without sending or spending')
    attrs.PotionAnimationReady = true; advance(.1)
    check(remotes.QuickDrinkPotion.sent == 1, 'queued press fires once when animation is ready')
    request.Drink()
    check(remotes.QuickDrinkPotion.sent == 1, 'repeat press during network request is not queued')
    locked = true; remotes.PotionDrunk.OnClientEvent:Fire({character = character}); request.Drink()
    check(remotes.QuickDrinkPotion.sent == 1 and feedback == 'drinking', 'active drink refuses another press')
    locked = false; request.Drink('held-uuid')
    check(remotes.DrinkPotionRequest.sent == 1 and remotes.DrinkPotionRequest.uuid == 'held-uuid', 'held potion uses same coordinator after unlock')
    remotes.PotionDrinkRejected.OnClientEvent:Fire()
    menu = true; request.Drink()
    check(remotes.QuickDrinkPotion.sent == 1 and feedback == 'interaction', 'modal interaction prevents requests')
    menu = false; attrs.PotionAnimationReady = false; request.Drink(); advance(11)
    check(remotes.QuickDrinkPotion.sent == 1 and feedback == 'load_failed', 'unavailable animation times out without consuming')
    request.Drink(); player.CharacterRemoving:Fire(); player.Character = nil; advance(1)
    check(remotes.QuickDrinkPotion.sent == 1 and attrs.PotionAnimationReady == false, 'respawn cancels queued request and old readiness')
    return checks
end
