-- Playback lifecycle regressions with a fake Animator and deterministic task clock.
return function(source)
    local checks, now = 0, 100
    local function check(value, label) assert(value, label); checks += 1 end
    local function signal()
        local callbacks = {}
        return {Connect = function(_, fn) callbacks[fn] = true; return {Disconnect = function() callbacks[fn] = nil end} end,
            Fire = function(_, ...) for fn in pairs(table.clone(callbacks)) do if callbacks[fn] then fn(...) end end end}
    end
    local jobs = {}
    local function advance(dt)
        local target = now + dt
        while true do
            local index, soonest
            for i, job in ipairs(jobs) do if job.time <= target and (not soonest or job.time < soonest) then index, soonest = i, job.time end end
            if not index then break end
            now = soonest
            table.remove(jobs, index).fn()
        end
        now = target
    end
    local attrs, statuses = {}, {}
    local prepareSignal = signal()
    local player = {GetAttributeChangedSignal = function() return prepareSignal end, CharacterAdded = signal(), CharacterRemoving = signal(), SetAttribute = function(_, key, value) attrs[key] = value end}
    local tracks, animator = {}, {AnimationPlayed = signal()}
    local action = {Value = 2}
    animator.LoadAnimation = function(_, anim)
        local marker = signal()
        local track = {Length = 0, IsPlaying = false, Priority = action, Animation = anim, plays = 0, stops = 0, marker = marker}
        track.Play = function() track.IsPlaying = true; track.plays += 1; animator.AnimationPlayed:Fire(track) end
        track.Stop = function() track.IsPlaying = false; track.stops += 1 end
        track.Destroy = function() track.IsPlaying = false end
        track.GetMarkerReachedSignal = function() return marker end
        track.loaded = signal()
        track.GetPropertyChangedSignal = function() return track.loaded end
        table.insert(tracks, track)
        return track
    end
    animator.GetPlayingAnimationTracks = function()
        local result = {}
        for _, track in ipairs(tracks) do if track.IsPlaying then table.insert(result, track) end end
        return result
    end
    local hum = {Health = 100, Died = signal(), FindFirstChildOfClass = function() return animator end}
    local hasMesh = false
    local mesh = {FindFirstChild = function() return {} end}
    local char = {Parent = true, DescendantAdded = signal(), FindFirstChildOfClass = function() return hum end,
        FindFirstChild = function(_, name) return name == 'Hero_Character' and hasMesh and mesh or nil end,
        SetAttribute = function(_, key, value) statuses[key] = value end}
    player.Character = char
    local interruptedAt, activeTrack, equipObserver = 0, nil, nil
    local presentation = {Prepare = function() end,
        TrackStarted = function(_, track) activeTrack = track end,
        InterruptedAfter = function(_, sentAt) return interruptedAt >= sentAt end,
        Interrupt = function() interruptedAt = now; if activeTrack then activeTrack:Stop() end; attrs.PotionDrinkCameraUntil = nil end}
    local effects = {}
    local assets = {T1_POTION_DRINK = 'published'}
    local modules = {PotionDrinkConfig = {ANIMATION_LOAD_TIMEOUT = 3, ANIMATION_DURATION = 1.1, ANIMATION_FADE_IN = .06,
            ANIMATION_FADE_OUT = .1, MAX_EVENT_AGE = 1.5, CORK_POP_TIME = .25, CORK_POP_MARKER = 'CorkPop',
            MARKER_FALLBACK_GRACE = .08, ANIMATED_VFX_TIME_SCALE = .7},
        PotionAnimations = assets, PotionPresentation = presentation,
        PotionAction = {ATTRIBUTE = "PotionDrinkingUntil", IsLocked = function() return (statuses.PotionDrinkingUntil or 0) > now end},
        PotionDrinkEffect = {Play = function(payload) effects[payload.drinkId] = (effects[payload.drinkId] or 0) + 1 end,
            Cancel = function() end, Clear = function() end},
        ActiveEquipment = {GetTool = function() return nil end, Observe = function(_, cb) equipObserver = cb; return function() end end}}
    local remote = {OnClientEvent = signal()}
    local function node(name)
        return {name = name, WaitForChild = function(_, child) if child == 'PotionDrunk' then return remote end; return node(child) end}
    end
    local services = {Players = {LocalPlayer = player}, ReplicatedStorage = node('RS'), ContentProvider = {PreloadAsync = function() end}}
    local env = setmetatable({game = {GetService = function(_, name) return services[name] end},
        script = {Parent = node('Scripts'), Destroying = signal()},
        require = function(n) return assert(modules[n.name], n.name) end,
        workspace = {GetServerTimeNow = function() return now end},
        task = {spawn = function(fn) fn() end, delay = function(dt, fn) table.insert(jobs, {time = now + dt, fn = fn}) end},
        Enum = {AnimationPriority = {Action = action}},
        Instance = {new = function() return {Destroy = function() end} end}, warn = function() end,
    }, {__index = getfenv()})
    local chunk = assert(loadstring(source, 'PotionDrinkClient.mock'))
    setfenv(chunk, env); chunk()
    check(#tracks == 0, 'missing mesh does not create a wrong-rig track')
    hasMesh = true
    char.DescendantAdded:Fire({Name = 'Hand_R', IsA = function() return false end})
    check(#tracks == 1, 'late rig replication retries animation load')
    local track = tracks[1]
    local nextId = 0
    local function drink(character)
        nextId += 1
        local payload = {character = character or char, sentAt = now, finishAt = now + 1.1, animated = true, drinkId = nextId, itemUuid = 'potion'}
        remote.OnClientEvent:Fire(payload)
        return nextId
    end
    check(attrs.PotionAnimationReady == false, 'request readiness false until clip loads')
    advance(4)
    track.Length = 1.1; track.loaded:Fire()
    check(attrs.PotionAnimationReady == true, 'slow clip load enables requests without respawn')
    local combat = {IsPlaying = true, Priority = action}
    combat.Stop = function() combat.IsPlaying = false end
    table.insert(tracks, combat)
    local first = drink()
    check(track.plays == 1 and track.IsPlaying and not combat.IsPlaying, 'accepted drink starts even during a prior attack')
    advance(.25); track.marker:Fire(); advance(.1)
    check(effects[first] == 1, 'marker and timed fallback produce one burst')
    combat.IsPlaying = true; animator.AnimationPlayed:Fire(combat)
    check(not combat.IsPlaying and track.IsPlaying, 'new action track cannot interrupt drinking')
    advance(.76)
    check(not track.IsPlaying and attrs.PotionDrinkCameraUntil == nil, 'deadline releases track and camera')
    local second = drink()
    check(track.plays == 2, 'another drink starts after previous action completes')
    advance(1.11)
    local before = track.plays
    local observer = {Parent = true, FindFirstChildOfClass = function() return hum end}
    local observerId = drink(observer)
    advance(.34)
    check(track.plays == before and effects[observerId] == 1, 'observers run VFX without replaying local animation')
    assets.T1_POTION_DRINK = ''
    local emptyId = drink()
    check(effects[emptyId] == 1 and not track.IsPlaying, 'empty registry retains safe VFX fallback')
    hum.Died:Fire()
    check(attrs.PotionAnimationReady == false and attrs.PotionDrinkCameraUntil == nil, 'death clears readiness and camera')
    return checks
end
