--[[
    DungeonBossMobClass  -- ServerScriptService
    Subclass of MobClass for dungeon bosses.

    Adds a spawn intro: the boss appears at a ceiling anchor playing its
    CeilingLatch animation, held invulnerable and non-aggressive via the
    existing MobClass:SetSpawnIntroState hook. There is no fall animation
    yet, so when the intro ends it simply teleports to the floor anchor and
    drops into its normal Idle.

    Also fires AggroStart the first time it acquires a target. There is no
    dedicated active-aggro loop authored yet, so AggroStart is re-fired on a
    cooldown while it stays aggressive (per spec: "just spam repeat aggro
    start tbh").
]]
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")

local MobClass      = require(ServerScriptService:WaitForChild("MobClass"))
local MobAnimConfig = require(ReplicatedStorage:WaitForChild("MobAnimConfig"))

local DungeonBossMobClass = setmetatable({}, { __index = MobClass })
DungeonBossMobClass.__index = DungeonBossMobClass

local CEILING_HOLD_SECONDS = 7.0   -- how long the latch plays before it drops
local CEILING_EXTRA_HEIGHT = 0     -- the ceiling anchor already sits ~79 studs above the
                                   -- platform surface; extra lift just parked it in the sky
local AGGRO_REFIRE_SECONDS = 2.5   -- re-trigger AggroStart while chasing

function DungeonBossMobClass.new(mobId, spawnPosition, spawnerRef, level)
    local self = MobClass.new(mobId, spawnPosition, spawnerRef, level, DungeonBossMobClass)
    if not self then return nil end
    self._bossIntroDone   = false
    self._lastAggroFire   = 0
    self._wasAggro        = false
    return self
end

-- Load the extra one-shot tracks MobAnimController doesn't know about.
function DungeonBossMobClass:_getExtraTrack(key)
    local model = self.Model
    if not model then return nil end
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hum then return nil end
    local animator = hum:FindFirstChildOfClass("Animator")
    if not animator then return nil end

    self._extraTracks = self._extraTracks or {}
    if self._extraTracks[key] then return self._extraTracks[key] end

    local cfg = MobAnimConfig[self.MobID]
    local id = cfg and cfg[key]
    if not id then return nil end

    local anim = Instance.new("Animation")
    anim.AnimationId = id
    local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
    if not ok or not track then
        warn("[DungeonBossMobClass] failed to load", key, id)
        return nil
    end
    track.Priority = Enum.AnimationPriority.Action
    self._extraTracks[key] = track
    return track
end

-- Called by DungeonBossSpawner right after the model exists.
-- ceilingCF / floorPos come from the spawner's configured anchors.
function DungeonBossMobClass:BeginCeilingIntro(ceilingPosition, floorPosition)
    if not self.Model or not self.Model.PrimaryPart then return end

    self:SetSpawnIntroState(true)      -- invulnerable + forced Idle

    local hangPos = ceilingPosition + Vector3.new(0, CEILING_EXTRA_HEIGHT, 0)

    -- ANCHOR for the whole intro. Without this the model is unanchored the
    -- instant it spawns and simply free-falls off the ceiling anchor into the
    -- void before the latch animation has even played.
    self._introAnchoredParts = {}
    for _, d in ipairs(self.Model:GetDescendants()) do
        if d:IsA("BasePart") and not d.Anchored then
            d.Anchored = true
            table.insert(self._introAnchoredParts, d)
        end
    end

    self.Model:PivotTo(CFrame.new(hangPos) * CFrame.Angles(math.pi, 0, 0))

    local latch = self:_getExtraTrack("CeilingLatch")
    if latch then
        latch.Looped = true
        latch:Play(0.1)
    end

    task.delay(CEILING_HOLD_SECONDS, function()
        if not self:IsAlive() then return end
        if latch and latch.IsPlaying then latch:Stop(0.2) end

        -- No fall animation authored: teleport straight to the floor anchor,
        -- upright, and hand control back to the normal AI.
        if self.Model then
            -- The floor anchor is a MODEL PIVOT -- the centre of the platform
            -- solid, ~10 studs below its walkable surface. Teleporting the
            -- boss's root there buried it by that plus half its own height,
            -- and the physics solver ejected it: the "rigid ragdoll bounce".
            -- Ground-snap through the same helper normal movement uses.
            local gx, gz = floorPosition.X, floorPosition.Z
            local groundY = self:FindGroundY(gx, gz, floorPosition.Y)
            local landY = groundY + (self._feetToRootHeight or 0)
            self.Model:PivotTo(CFrame.new(gx, landY, gz))
        end

        -- Hand physics back exactly to the parts we took it from.
        for _, part in ipairs(self._introAnchoredParts or {}) do
            if part and part.Parent then part.Anchored = false end
        end
        self._introAnchoredParts = nil

        self:SetSpawnIntroState(false)
        self._bossIntroDone = true
    end)
end

function DungeonBossMobClass:PlayAggroStart()
    local t = self:_getExtraTrack("AggroStart")
    if not t then return end
    t.Looped = false
    if t.IsPlaying then t:Stop(0.1) end
    t:Play(0.15)
    self._lastAggroFire = os.clock()
end

-- Hook the base AI, then layer aggro-animation behaviour on top.
function DungeonBossMobClass:UpdateAI(deltaTime, players, activeMobs)
    MobClass.UpdateAI(self, deltaTime, players, activeMobs)

    local aggro = (self.AIState == "Walking" or self.AIState == "Attacking")
        and self.TargetPlayer ~= nil

    if aggro then
        if not self._wasAggro then
            self:PlayAggroStart()                       -- first acquisition
        elseif os.clock() - self._lastAggroFire > AGGRO_REFIRE_SECONDS then
            self:PlayAggroStart()                       -- keep re-firing
        end
    end
    self._wasAggro = aggro
end

return DungeonBossMobClass
