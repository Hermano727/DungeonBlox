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
local ServerStorage       = game:GetService("ServerStorage")
local RunService          = game:GetService("RunService")
local ContentProvider     = game:GetService("ContentProvider")

local MobClass      = require(ServerScriptService:WaitForChild("MobClass"))
local MobAnimConfig = require(ReplicatedStorage:WaitForChild("MobAnimConfig"))
local MobAnimController = require(ServerScriptService:WaitForChild("MobAnimController"))
local MiasmaEncounterConfig = require(ReplicatedStorage:WaitForChild("MiasmaEncounterConfig"))

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
    self._encounterControlled = false
    self._encounterDamageMultiplier = 1
    self._encounterLocked = false
    return self
end

-- Load the extra one-shot tracks MobAnimController doesn't know about.
function DungeonBossMobClass:_getExtraTrack(key)
    local animator = MobAnimController.GetAnimator(self.Model)
    if not animator then return nil end

    self._extraTracks = self._extraTracks or {}
    if self._extraTracks[key] then return self._extraTracks[key] end

    local cfg = MobAnimConfig[self.MobID]
    local id = (cfg and cfg[key]) or (self.MobID == "MiasmaBoss" and MiasmaEncounterConfig.Animations[key])
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
function DungeonBossMobClass:LatchAtCeiling(ceilingPosition, floorPosition)
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

    -- Latch-model path: the hang position is DERIVED from the drop clip's geometry, not taken
    -- from the ceiling anchor -- see _latchHangPosition.
    local landing = floorPosition or self.SpawnPosition
    local latchPos = landing and self:_latchHangPosition(landing, ceilingPosition)
    if latchPos and self:_spawnLatchProxy(latchPos) then
        self._latchHoldsBoss = true
        -- The ceiling pose is its own authored model (see _spawnLatchProxy), so the real
        -- boss stays parked and hidden until the bridge swaps it in.
        self.Model:PivotTo(CFrame.new(latchPos))
        self:SetEncounterVisible(false)
        self._ceilingFloorPosition = floorPosition
        self:_prepareDropTracks()
        if not self._dropPlaneY and math.abs(latchPos.Y - ceilingPosition.Y) > 10 then
            warn(("[DungeonBossMobClass] the ceiling-drop clip's geometry hangs the latch model at Y=%.1f " ..
                "(%.1f above the floor), but the ceiling anchor is at Y=%.1f (%.1f above the floor). " ..
                "The drop clips were authored for a ceiling that high; see MiasmaEncounterConfig.BossDropSequence.")
                :format(latchPos.Y, latchPos.Y - landing.Y, ceilingPosition.Y, ceilingPosition.Y - landing.Y))
        end
        return
    end

    -- No latch model configured: pose the boss itself upside-down on the ceiling.
    self.Model:PivotTo(CFrame.new(hangPos) * CFrame.Angles(math.pi, 0, 0))

    local latch = self:_getExtraTrack("CeilingLatch")
    if latch then
        latch.Looped = true
        latch:Play(0.1)
    end

    self._ceilingLatchTrack = latch
    self._ceilingFloorPosition = floorPosition
end

-- The boss's ceiling-hang is a SEPARATE skinned model (Stats.CeilingLatchModelName, in
-- ServerStorage.MobModels) with its own bones/animation, not a pose of the boss mesh. This
-- spawns it at the hang position and loops the CeilingLatch clip on it. Returns false (and
-- leaves everything untouched) when this boss has no latch model or the template is missing,
-- so the caller falls back to posing the boss itself.
function DungeonBossMobClass:_spawnLatchProxy(hangPos)
    local modelName = self.Stats and self.Stats.CeilingLatchModelName
    if not modelName then return false end
    local mobModels = ServerStorage:FindFirstChild("MobModels")
    local template = mobModels and mobModels:FindFirstChild(modelName)
    if not template then
        warn("[DungeonBossMobClass] ceiling latch model not found: " .. tostring(modelName))
        return false
    end

    local latch = template:Clone()
    latch.Name = tostring(self.UID) .. "_CeilingLatch"
    for _, d in ipairs(latch:GetDescendants()) do
        if d:IsA("BasePart") then d.Anchored = true end
    end
    -- The latch model was authored from a top-down view (looking at the splat from above), but
    -- on the ceiling it's seen from below -- flip it 180 degrees about X so its authored top
    -- faces the floor. (The DefeatFlat puddle uses the same model on the GROUND, unflipped.)
    latch:ScaleTo(self:_modelScale())
    latch:PivotTo(CFrame.new(hangPos) * CFrame.Angles(math.pi, 0, 0))
    latch.Parent = workspace
    self._latchModel = latch

    -- Anything that removes the boss (run cleanup, death, encounter reset) destroys its Model
    -- directly rather than through a method here, so tie the proxy's lifetime to it (and stop
    -- any bridge cross-fade that is mid-flight).
    self.Model.Destroying:Connect(function()
        if self._bridge then self._bridge.cancelled = true end
        if latch.Parent then latch:Destroy() end
    end)

    -- Both latch clips load on the LATCH model's own Animator (_getExtraTrack loads onto
    -- self.Model, which is the boss): the looping hang, and the LatchDetach bridge half, kept
    -- ready but not played until the bridge starts.
    local cfg = MobAnimConfig[self.MobID]
    local animator = MobAnimController.GetAnimator(latch)
    local function loadOnLatch(id, looped)
        if not (id and animator) then return nil end
        local anim = Instance.new("Animation")
        anim.AnimationId = id
        local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
        if not ok or not track then
            warn("[DungeonBossMobClass] failed to load latch clip", id)
            return nil
        end
        track.Priority = Enum.AnimationPriority.Action
        track.Looped = looped
        return track
    end
    local hang = loadOnLatch(cfg and cfg.CeilingLatch, true)
    if hang then hang:Play(0.1) end
    self._ceilingLatchTrack = hang
    self._latchDetachTrack = loadOnLatch(cfg and cfg.LatchDetach, false)
    return true
end

function DungeonBossMobClass:_clearLatchProxy()
    if self._ceilingLatchTrack and self._ceilingLatchTrack.IsPlaying then
        self._ceilingLatchTrack:Stop(0.1)
    end
    if self._latchModel then
        self._latchModel:Destroy()
        self._latchModel = nil
    end
    self._ceilingLatchTrack = nil
    self._latchDetachTrack = nil
end

-- World position for the latch model's pivot (before its 180-degree flip). Derived from the
-- boss's LANDING root position plus the measured geometry of CeilingToBody's first frame (the
-- folded disc sits 136.15 above the upright boss's root; the flipped latch's bone plane is 4.1
-- above its pivot), so the two forms coincide when the bridge starts. Deliberately NOT the
-- ceiling anchor: CeilingToBody already contains its own starting altitude, and adding an anchor
-- offset on top would count it twice.
--
-- With BossDropSequence.CompensateToCeilingAnchor (default) the latch instead hangs at the REAL
-- ceiling anchor, so it is visible in phase 1; the boss root is then offset to meet it (see
-- ReleaseFromCeiling / _driveDropRoot) and this only records where the latch's bone plane is.
function DungeonBossMobClass:_latchHangPosition(floorPosition, ceilingPosition)
    local seq = MiasmaEncounterConfig.BossDropSequence
    local scale = self:_modelScale()
    if seq.CompensateToCeilingAnchor and ceilingPosition then
        self._dropPlaneY = ceilingPosition.Y + seq.LatchBonePlaneAbovePivotFlipped * scale
        return ceilingPosition
    end
    self._dropPlaneY = nil
    local gx, gz = floorPosition.X, floorPosition.Z
    local groundY = self:FindGroundY(gx, gz, floorPosition.Y)
    local rootY = groundY + (self._feetToRootHeight or 0)
    -- The measured offsets are at scale 1; the boss and latch models are both scaled by the same
    -- Stats.ModelScale, so the offsets scale with them.
    return Vector3.new(gx, rootY + self:_discCentreAboveRoot() - seq.LatchBonePlaneAbovePivotFlipped * scale, gz)
end

-- How far above the boss's root part the folded disc (CeilingToBody's first frame) sits, at this
-- boss's scale. BodyMotion scales with the model only if the animation's translations do
-- (AnimTranslationScalesWithModel); the folded body's own height always does.
function DungeonBossMobClass:_discCentreAboveRoot()
    local seq = MiasmaEncounterConfig.BossDropSequence
    local bodyMotion = seq.BodyMotionAltitude * (seq.AnimTranslationScalesWithModel and self:_modelScale() or 1)
    return bodyMotion + seq.DiscCentreFromRig * self:_modelScale()
end

-- Size multiplier applied to this mob's model at spawn (MobData ModelScale); 1 when unset.
function DungeonBossMobClass:_modelScale()
    local s = tonumber(self.Stats and self.Stats.ModelScale)
    return (s and s > 0) and s or 1
end

-- The model's current size relative to its spawn size: 1 normally, less while an encounter has
-- shrunk it (SetEncounterShrink).
function DungeonBossMobClass:_encounterScale()
    return self._encounterScaleFactor or 1
end

-- Encounter-driven resize on top of the spawn ModelScale: factor 1 is normal size, 0.5 is half.
-- Tweens over `seconds` (0 = instant) and keeps the feet on the ground the whole way: ScaleTo
-- scales about the pivot (the root), so the root is re-placed at ground + feet-to-root at every
-- step. Size-derived values (feet-to-root, hit radius, separation) follow the new size. A newer
-- call cancels one still tweening.
function DungeonBossMobClass:SetEncounterShrink(factor, seconds)
    local model = self.Model
    if not (model and model:IsA("Model") and model.PrimaryPart) then return end
    factor = math.clamp(tonumber(factor) or 1, 0.1, 1)
    seconds = math.max(0, tonumber(seconds) or 0)

    -- Capture the full-size values once, before anything is shrunk.
    if not self._fullSize then
        self._fullSize = {
            feet = self._feetToRootHeight or 0,
            hit = self:GetHitRadius(),
            sep = self:SeparationRadius(),
            crowd = self:CrowdRadius(),
        }
    end
    local full = self._fullSize
    local base = self:_modelScale()
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    local groundY = model:GetPivot().Position.Y - (self._feetToRootHeight or 0)
    local from = self:_encounterScale()

    local function apply(f)
        model:ScaleTo(base * f)
        self._encounterScaleFactor = f
        self._feetToRootHeight = full.feet * f
        -- GetHitRadius credits only the radius beyond 3 studs; scale the raw half-width.
        self._hitRadius = math.max(0, (full.hit + 3) * f - 3)
        self._sepRadius = full.sep * f
        self._crowdRadius = full.crowd * f
        self._crowdMass = nil -- recomputed from the new footprint
        if humanoid then humanoid.HipHeight = self._feetToRootHeight end
        local pivot = model:GetPivot()
        model:PivotTo(CFrame.new(pivot.X, groundY + self._feetToRootHeight, pivot.Z) * pivot.Rotation)
    end

    self._shrinkSerial = (self._shrinkSerial or 0) + 1
    local serial = self._shrinkSerial
    if seconds <= 0 or math.abs(factor - from) < 1e-3 then
        apply(factor)
        return
    end
    task.spawn(function()
        local started = os.clock()
        while self._shrinkSerial == serial and self.Model == model and model.Parent do
            local u = math.min(1, (os.clock() - started) / seconds)
            local eased = 1 - (1 - u) ^ 3 -- fast start, soft settle
            apply(from + (factor - from) * eased)
            if u >= 1 then break end
            RunService.Heartbeat:Wait()
        end
    end)
end

-- Load every clip the drop needs while phase 1 is still running (a fresh LoadAnimation is not
-- instantly playable), preload their assets, and sanity-check the published lengths against
-- the timeline config. Nothing waits on this: if a clip isn't ready when the bridge starts,
-- StartCeilingBridge reports failure and the drop degrades to a direct reveal.
function DungeonBossMobClass:_prepareDropTracks()
    local seq = MiasmaEncounterConfig.BossDropSequence
    local expected = {
        { self:_getExtraTrack("CeilingToBody"), seq.BridgeSeconds, "CeilingToBody" },
        { self._latchDetachTrack, seq.BridgeSeconds, "LatchDetach" },
        { self:_getExtraTrack("LandingSlam"), seq.SlamLength, "LandingSlam" },
    }
    task.spawn(function()
        local anims = {}
        for _, e in ipairs(expected) do
            if e[1] then table.insert(anims, e[1].Animation) end
        end
        pcall(function() ContentProvider:PreloadAsync(anims) end)
        for _, e in ipairs(expected) do
            local track, want, name = e[1], e[2], e[3]
            if track and track.Length > 0 and math.abs(track.Length - want) > 0.05 then
                warn(("[DungeonBossMobClass] %s is %.3fs but the drop timeline assumes %.3fs; retime MiasmaEncounterConfig.BossDropSequence")
                    :format(name, track.Length, want))
            elseif not track then
                warn("[DungeonBossMobClass] drop clip not loaded: " .. name)
            end
        end
    end)
end

-- Bridge (0.6s): LatchDetach on the latch model + CeilingToBody on the boss, started together.
-- The boss stays hidden until its clip has actually been evaluated on the server
-- (TimePosition >= SwapStart), then the two forms cross-fade over SwapStart..SwapEnd. Returns
-- false, touching nothing, if a piece is missing -- StartLandingSlam then reveals the boss
-- directly so the encounter can never hang on a missing clip.
function DungeonBossMobClass:StartCeilingBridge()
    local seq = MiasmaEncounterConfig.BossDropSequence
    local latch, detach = self._latchModel, self._latchDetachTrack
    local body = self:_getExtraTrack("CeilingToBody")
    local animator = MobAnimController.GetAnimator(self.Model)
    if not (latch and detach and body and animator) then
        warn("[DungeonBossMobClass] ceiling bridge unavailable; revealing the boss directly")
        return false
    end

    -- Clean slate on the boss (idle/aggro would otherwise blend into the bridge pose).
    for _, t in ipairs(animator:GetPlayingAnimationTracks()) do t:Stop(0) end
    if self._ceilingLatchTrack then self._ceilingLatchTrack:Stop(0) end
    body.Looped, detach.Looped = false, false
    body:Play(0)
    detach:Play(0)

    local bridge = { cancelled = false }
    self._bridge = bridge

    local bossParts, latchParts = {}, {}
    local states = self._encounterPartState or {}
    for _, d in ipairs(self.Model:GetDescendants()) do
        if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and states[d] then
            bossParts[d] = states[d].transparency
        end
    end
    for _, d in ipairs(latch:GetDescendants()) do
        if d:IsA("BasePart") and d.Name ~= "LatchRoot" then latchParts[d] = d.Transparency end
    end

    task.spawn(function()
        local started = os.clock()
        local span = math.max(0.001, seq.SwapEnd - seq.SwapStart)
        while not bridge.cancelled do
            if not (self.Model and latch.Parent) then return end
            -- No progress after a full bridge length means the clip never really started.
            if os.clock() - started > seq.BridgeSeconds + 0.5 then break end
            local t = body.IsPlaying and body.TimePosition or 0
            local a = math.clamp((t - seq.SwapStart) / span, 0, 1)
            if a > 0 then
                for part, base in pairs(latchParts) do part.Transparency = base + (1 - base) * a end
                for part, orig in pairs(bossParts) do part.Transparency = 1 + (orig - 1) * a end
            end
            if a >= 1 then break end
            RunService.Heartbeat:Wait()
        end
        if not bridge.cancelled then self:_finishSwap() end
    end)
    return true
end

-- Hands visibility to the real boss and removes the latch model. Idempotent.
function DungeonBossMobClass:_finishSwap()
    self._latchHoldsBoss = false
    self:SetEncounterVisible(true) -- restores every part's original transparency/collision + HP bar
    -- While the root is still held below the floor (compensated drop) the HP bar would render
    -- under the ground; _settleDropRoot turns it back on once the boss has landed.
    if self._dropLand and self.HPBar then self.HPBar.Enabled = false end
    self:_clearLatchProxy()
end

-- Immediate, ungraded swap: used when the slam must start but the cross-fade hasn't finished
-- (bridge failed, was skipped, or is still fading).
function DungeonBossMobClass:_revealNow()
    if self._bridge then self._bridge.cancelled = true end
    self:_finishSwap()
end

-- Slam: straight on from the bridge's last pose (identical to the slam's first pose), no blend
-- and no rest-pose gap. The fall, squash, expansion and roar are all inside this clip.
-- Returns the slam AnimationTrack (nil if the clip isn't configured/loaded).
function DungeonBossMobClass:StartLandingSlam()
    if self._latchHoldsBoss or self._latchModel then self:_revealNow() end
    self._bridge = nil
    local slam = self:PlayEncounterAnimation("LandingSlam", false, 0)
    if self._dropLand then self:_driveDropRoot(slam) end
    local seq = MiasmaEncounterConfig.BossDropSequence
    local stretch = tonumber(seq.SlamRoarStretch) or 1
    if slam and stretch > 0 and stretch ~= 1 then
        self:_slowTrackWindow(slam, seq.SlamRoarStart, seq.SlamRoarEnd, 1 / stretch)
    end
    return slam
end

-- Plays `track` at `speed` between clip times fromT and toT, and at normal speed either side
-- of that window. Follows the track's own TimePosition, so it can't drift from the clip.
function DungeonBossMobClass:_slowTrackWindow(track, fromT, toT, speed)
    task.spawn(function()
        local slowed = false
        while self.Model and track.IsPlaying do
            local t = track.TimePosition
            if t >= toT then break end
            if not slowed and t >= fromT then
                track:AdjustSpeed(speed)
                slowed = true
            end
            RunService.Heartbeat:Wait()
        end
        if slowed then track:AdjustSpeed(1) end
    end)
end

function DungeonBossMobClass:_unanchorIntroParts()
    for _, part in ipairs(self._introAnchoredParts or {}) do
        if part and part.Parent then part.Anchored = false end
    end
    self._introAnchoredParts = nil
end

-- Raises the boss root from its held-low bridge height back to the floor while the slam's own
-- BodyMotion brings the body down: root = floor - lift * (fall remaining). The two motions
-- combine so the body's world height falls from the ceiling plane to the floor (see
-- BossDropSequence.CompensateToCeilingAnchor). Follows the slam track's TimePosition, so it
-- stays in sync with the clip rather than with a separate timer.
function DungeonBossMobClass:_driveDropRoot(slam)
    local plan = self._dropLand
    local seq = MiasmaEncounterConfig.BossDropSequence
    local samples = seq.SlamBodyMotion
    local endTime = samples[#samples][1]
    local function remaining(t)
        for i = 2, #samples do
            local a, b = samples[i - 1], samples[i]
            if t <= b[1] then
                local u = math.clamp((t - a[1]) / (b[1] - a[1]), 0, 1)
                return (a[2] + (b[2] - a[2]) * u) / samples[1][2] -- 1 at the start of the fall
            end
        end
        return 0
    end
    task.spawn(function()
        while self._dropLand == plan and self.Model and slam and slam.IsPlaying do
            local t = slam.TimePosition
            if t >= endTime then break end
            self.Model:PivotTo(CFrame.new(plan.x, plan.landY - plan.lift * remaining(t), plan.z))
            RunService.Heartbeat:Wait()
        end
        self:_settleDropRoot(plan)
    end)
end

-- Puts the boss on the floor and re-enables what the compensated drop suppressed. Idempotent
-- per plan, and a no-op if the plan was already replaced or cancelled.
function DungeonBossMobClass:_settleDropRoot(plan)
    if self._dropLand ~= plan then return end
    self._dropLand = nil
    if self.Model then
        self.Model:PivotTo(CFrame.new(plan.x, plan.landY, plan.z))
        if self.HPBar then self.HPBar.Enabled = true end
    end
    self:_unanchorIntroParts()
end

-- Stops any in-flight drop transition and removes the latch model (encounter destroyed / failed).
function DungeonBossMobClass:CancelDropTransition()
    if self._bridge then self._bridge.cancelled = true; self._bridge = nil end
    self._latchHoldsBoss = false
    if self._latchModel then self:_clearLatchProxy() end
    if self._dropLand then self:_settleDropRoot(self._dropLand) end
end

-- Puts the boss on the floor and shows it. Note the FALL itself is not scripted: for Miasma the
-- authored LandingSlam clip starts with its BodyMotion bone ~107 studs up and brings the body
-- down to the floor by ~0.8s, so the model is placed at floor level and that clip does the drop.
--
-- deferReveal (optional): move the boss to its floor position but keep the latch model up and the
-- real boss HIDDEN. Visibility is then owned by the drop sequence: StartCeilingBridge cross-fades
-- it in, or StartLandingSlam reveals it directly if there is no bridge.
function DungeonBossMobClass:ReleaseFromCeiling(floorPosition, deferReveal)
    if not self:IsAlive() then return false end
    local defer = deferReveal == true and self._latchModel ~= nil
    if not defer then
        if self._ceilingLatchTrack and self._ceilingLatchTrack.IsPlaying then
            self._ceilingLatchTrack:Stop(0.2)
        end
        if self._latchModel then
            self._latchHoldsBoss = false
            self:_clearLatchProxy()
            self:SetEncounterVisible(true)
        end
    end

    floorPosition = floorPosition or self._ceilingFloorPosition or self.SpawnPosition
    if self.Model and floorPosition then
        local gx, gz = floorPosition.X, floorPosition.Z
        local groundY = self:FindGroundY(gx, gz, floorPosition.Y)
        local landY = groundY + (self._feetToRootHeight or 0)
        local rootY = landY
        if defer and self._dropPlaneY then
            -- Compensated drop (see _latchHangPosition): the folded disc must sit at the latch's
            -- plane, i.e. at the REAL ceiling, so the root is held below its landing height by
            -- `lift`; _driveDropRoot raises it back in step with the slam's fall. Lift can never
            -- exceed the clip's own fall (BodyMotion), or the body would rise instead of dropping.
            local seq = MiasmaEncounterConfig.BossDropSequence
            local fall = seq.BodyMotionAltitude * (seq.AnimTranslationScalesWithModel and self:_modelScale() or 1)
            local lift = landY - (self._dropPlaneY - self:_discCentreAboveRoot())
            if lift > fall then
                warn(("[DungeonBossMobClass] the ceiling is too low for this boss's drop (needs %.1f studs of " ..
                    "lift, the clip only falls %.1f); the boss will not fall from the ceiling plane"):format(lift, fall))
                lift = fall
            elseif lift < 0 then
                lift = 0
            end
            rootY = landY - lift
            self._dropLand = { x = gx, z = gz, landY = landY, lift = lift }
        end
        self.Model:PivotTo(CFrame.new(gx, rootY, gz))
    end

    -- A compensated drop keeps the intro anchoring on (the whole model is moved by PivotTo each
    -- frame; unanchored skin parts would lag behind an anchored root) until the drive finishes.
    if not self._dropLand then self:_unanchorIntroParts() end
    self:SetSpawnIntroState(false)
    self._bossIntroDone = true
    return true
end

function DungeonBossMobClass:BeginCeilingIntro(ceilingPosition, floorPosition)
    self:LatchAtCeiling(ceilingPosition, floorPosition)

    task.delay(CEILING_HOLD_SECONDS, function()
        self:ReleaseFromCeiling(floorPosition)
    end)
end

function DungeonBossMobClass:SetEncounterControlled(active)
    self._encounterControlled = active == true
    if self._encounterControlled then
        self.AIState = "Idle"
        self.TargetPlayer = nil
        self._wasAggro = false
        self:_stopAggroLoop()
    end
end

function DungeonBossMobClass:SetEncounterDamageMultiplier(multiplier)
    self._encounterDamageMultiplier = math.max(0, tonumber(multiplier) or 1)
    if self.Model then
        self.Model:SetAttribute("DamageTakenMultiplier", self._encounterDamageMultiplier)
    end
end

function DungeonBossMobClass:SetEncounterProtectedPositions(positions, radius)
    self._encounterProtectedPositions = table.clone(positions or {})
    self._encounterProtectedRadius = math.max(0, tonumber(radius) or 0)
end

function DungeonBossMobClass:Move(goalPosition, deltaTime)
    local radius = self._encounterProtectedRadius or 0
    if radius > 0 and typeof(goalPosition) == "Vector3" then
        for _, center in ipairs(self._encounterProtectedPositions or {}) do
            local offset = Vector3.new(goalPosition.X - center.X, 0, goalPosition.Z - center.Z)
            if offset.Magnitude < radius then
                if offset.Magnitude < .01 and self.Model and self.Model.PrimaryPart then
                    local current = self.Model.PrimaryPart.Position
                    offset = Vector3.new(current.X - center.X, 0, current.Z - center.Z)
                end
                local direction = offset.Magnitude >= .01 and offset.Unit or Vector3.new(1, 0, 0)
                goalPosition = Vector3.new(center.X, goalPosition.Y, center.Z) + direction * radius
            end
        end
    end
    return MobClass.Move(self, goalPosition, deltaTime)
end

function DungeonBossMobClass:SetEncounterLocked(active, invulnerable)
    self._encounterLocked = active == true
    self.IsInvulnerable = invulnerable == true
    if self._encounterLocked then
        self.AIState = "Idle"
        self.TargetPlayer = nil
        self._wasAggro = false
        self:_stopAggroLoop()
    end
end

-- fadeIn (optional, default 0.15s): pass 0 for a clip that must start on its first authored
-- frame with no blend from the current pose (LandingSlam opens 107 studs up).
-- speed (optional, default 1): playback rate, e.g. 0.5 plays the clip twice as slow.
function DungeonBossMobClass:PlayEncounterAnimation(key, looped, fadeIn, speed)
    local track = self:_getExtraTrack(key)
    if not track then return nil end
    -- fadeIn == 0 means a hard cut from the previous clip (LandingSlam follows CeilingToBody's
    -- identical last pose): the outgoing clip must be cut with 0 fade too, or its fade-out
    -- would blend into the new one.
    local outFade = (fadeIn == 0) and 0 or 0.12
    for otherKey, otherTrack in pairs(self._extraTracks or {}) do
        if otherKey ~= key and otherTrack.IsPlaying then otherTrack:Stop(outFade) end
    end
    track.Looped = looped == true
    if track.IsPlaying then track:Stop(0.1) end
    track:Play(fadeIn or 0.15, 1, tonumber(speed) or 1)
    return track
end

local function loadClip(animator, id)
    local anim = Instance.new("Animation")
    anim.AnimationId = id
    local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
    if not ok or not track then
        warn("[DungeonBossMobClass] failed to load defeat clip", id)
        return nil
    end
    track.Priority = Enum.AnimationPriority.Action
    track.Looped = false
    return track
end

-- Shrink curve for the flat puddle: an overall ease to nothing with `pulses` contractions
-- riding on it (each one squeezes, then rebounds a little), so it reads as a puddle
-- convulsing away rather than a straight linear shrink. u is 0..1 through the flat phase.
local function shrinkScale(u, pulses, depth, minScale)
    local base = (1 - u) ^ 1.4
    local pulse = 1 + depth * math.sin(u * pulses * 2 * math.pi) * (1 - u)
    return math.max(minScale, base * pulse)
end

-- Cosmetic death sequence, called by MobClass:Die with the dying boss's Model. Returns true
-- when it took ownership of `mdl` (MobClass then skips its own death effect and destroy);
-- false leaves the ordinary death untouched (boss has no DefeatFlatModelName/clips).
--
-- Timeline (MiasmaEncounterConfig.Defeat): upright `Defeat` clip -> swap to the flat puddle
-- model (hide the upright one) -> `DefeatFlat` clip while the flat model is scaled down in
-- pulses -> remove everything. Server-authoritative gameplay is unaffected: the boss is
-- already dead/defeated the moment Die runs; this only decides when the visuals vanish.
function DungeonBossMobClass:PlayDefeatPresentation(mdl)
    local flatName = self.Stats and self.Stats.DefeatFlatModelName
    local cfg = MobAnimConfig[self.MobID]
    local mobModels = ServerStorage:FindFirstChild("MobModels")
    local template = flatName and mobModels and mobModels:FindFirstChild(flatName)
    local animator = MobAnimController.GetAnimator(mdl)
    if not (template and animator and cfg and cfg.Defeat and cfg.DefeatFlat) then
        return false
    end
    local timing = MiasmaEncounterConfig.Defeat

    local pivot = mdl:GetPivot()
    local groundY = pivot.Position.Y - (self._feetToRootHeight or 0)
    local rotation = pivot - pivot.Position

    local state = { done = false, flat = nil }
    local function cleanup()
        if state.done then return end
        state.done = true
        if state.flat then state.flat:Destroy() end
        if mdl.Parent then mdl:Destroy() end
        self._defeatCancel = nil
    end
    -- Dungeon closing / encounter destroyed calls this (see MiasmaEncounterController:Destroy).
    self._defeatCancel = cleanup

    task.spawn(function()
        -- 1) upright boss collapses
        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do track:Stop(0.1) end
        local defeat = loadClip(animator, cfg.Defeat)
        if defeat then defeat:Play(0.1) end
        task.wait(timing.UprightSeconds)
        if state.done then return end

        -- 2) swap to the flat puddle, sitting on the ground where the boss stood
        local flat = template:Clone()
        flat.Name = tostring(self.UID) .. "_DefeatFlat"
        for _, d in ipairs(flat:GetDescendants()) do
            if d:IsA("BasePart") then d.Anchored = true end
        end
        local height = flat:GetExtentsSize().Y
        -- Same size as the boss it replaces, including an encounter shrink (killed while stunned).
        local baseScale = self:_modelScale() * self:_encounterScale()
        local function place(scale)
            flat:ScaleTo(baseScale * scale)
            flat:PivotTo(CFrame.new(pivot.X, groundY + height * baseScale * scale * 0.5, pivot.Z) * rotation)
        end
        place(1)
        flat.Parent = workspace
        state.flat = flat
        for _, d in ipairs(mdl:GetDescendants()) do
            if d:IsA("BasePart") then d.Transparency = 1; d.CanCollide = false; d.CanTouch = false end
        end

        local flatAnimator = MobAnimController.GetAnimator(flat)
        local flatClip = flatAnimator and loadClip(flatAnimator, cfg.DefeatFlat)
        if flatClip then flatClip:Play(0.05) end

        -- 3) shrink the whole model in pulses until it's gone
        local started = os.clock()
        while not state.done do
            local u = (os.clock() - started) / timing.FlatSeconds
            if u >= 1 then break end
            place(shrinkScale(u, timing.ShrinkPulses, timing.PulseDepth, timing.MinScale))
            task.wait(1 / 30)
        end
        cleanup()
    end)
    return true
end

function DungeonBossMobClass:CancelDefeatPresentation()
    if self._defeatCancel then self._defeatCancel() end
end

-- Stops a clip started by PlayEncounterAnimation. Needed for looped ones (Stunned): nothing
-- else ends them, so without this the boss would keep "dizzy" looping after the stun is over.
function DungeonBossMobClass:StopEncounterAnimation(key, fadeTime)
    local track = self._extraTracks and self._extraTracks[key]
    if track and track.IsPlaying then track:Stop(fadeTime or 0.2) end
end

function DungeonBossMobClass:SetEncounterVisible(visible)
    if not self.Model then return end
    self._encounterHidden = not visible
    -- While the ceiling-latch model is standing in for the boss (phase 1), nothing may reveal
    -- the real boss mesh -- ReleaseFromCeiling clears the proxy first, then shows the boss.
    if visible and self._latchHoldsBoss then return end
    self._encounterPartState = self._encounterPartState or {}
    for _, descendant in ipairs(self.Model:GetDescendants()) do
        if descendant:IsA("BasePart") then
            if self._encounterPartState[descendant] == nil then
                self._encounterPartState[descendant] = {
                    transparency = descendant.Transparency,
                    canTouch = descendant.CanTouch,
                    canCollide = descendant.CanCollide,
                }
            end
            local original = self._encounterPartState[descendant]
            descendant.Transparency = visible and original.transparency or 1
            descendant.CanTouch = visible and original.canTouch or false
			descendant.CanCollide = visible and original.canCollide or false
        end
    end
	if self.HPBar then self.HPBar.Enabled = visible end
end

-- Every landed MELEE hit on a player goes through here (MobClass.PerformAttack's applyDamage),
-- so the encounter can add to the swing (Miasma: poison) without touching the shared attack.
function DungeonBossMobClass:ApplyPlayerHitstun(playerCharacter, knockbackMultiplier)
    -- Encounter hook: some players take the hit without being shoved (Miasma: whoever is
    -- working a valve, so tanking the boss doesn't knock them off the wheel).
    local target = game:GetService("Players"):GetPlayerFromCharacter(playerCharacter)
    local skipShove = target ~= nil and self.ShouldSkipKnockback ~= nil and self.ShouldSkipKnockback(target) == true
    if not skipShove then
        MobClass.ApplyPlayerHitstun(self, playerCharacter, knockbackMultiplier)
    end
    if self.OnEncounterMeleeHit then
        local player = game:GetService("Players"):GetPlayerFromCharacter(playerCharacter)
        if player then
            local ok, err = pcall(self.OnEncounterMeleeHit, player)
            if not ok then warn("[DungeonBossMobClass] OnEncounterMeleeHit failed: " .. tostring(err)) end
        end
    end
end

function DungeonBossMobClass:TakeDamage(player, amount, weaponSubStats)
    -- Encounter hook (Miasma's solo stagger meter): sees every landed hit with its RAW amount,
    -- before the encounter damage multiplier.
    local raw = tonumber(amount) or 0
    -- Pinned at its HealthFloor (see MobClass.TakeDamage): immune, and the hit doesn't count.
    local floor = tonumber(self.HealthFloor) or 0
    if floor > 0 and self.CurrentHealth <= floor then return false end
    if self.OnEncounterHit and raw > 0 and not self.IsInvulnerable then
        local ok, err = pcall(self.OnEncounterHit, player, raw)
        if not ok then warn("[DungeonBossMobClass] OnEncounterHit failed: " .. tostring(err)) end
    end
    return MobClass.TakeDamage(self, player, raw * (self._encounterDamageMultiplier or 1), weaponSubStats)
end

function DungeonBossMobClass:_stopAggroLoop()
    local loop = self._extraTracks and self._extraTracks.AggroLoop
    if loop and loop.IsPlaying then loop:Stop(0.15) end
end

-- Plays the looping "aggro" clip (AggroLoop) that holds while the boss is chasing.
-- Priority is Movement, deliberately below the Action-priority attack and encounter
-- clips, so a swing or slam overrides it and it resumes underneath afterwards.
function DungeonBossMobClass:_startAggroLoop()
    local loop = self:_getExtraTrack("AggroLoop")
    if not loop then return false end
    loop.Priority = Enum.AnimationPriority.Movement
    loop.Looped = true
    if not loop.IsPlaying then loop:Play(0.2) end
    return true
end

-- One-shot AggroStart on acquiring a target. When an AggroLoop is authored, the loop takes
-- over as soon as the start clip ends (only if the boss is still aggressive by then -- an
-- encounter animation or lost target stops the start clip early, which also fires Stopped).
function DungeonBossMobClass:PlayAggroStart()
    self._lastAggroFire = os.clock()
    local start = self:_getExtraTrack("AggroStart")
    local hasLoop = self:_getExtraTrack("AggroLoop") ~= nil
    if not start then
        if hasLoop then self:_startAggroLoop() end
        return
    end
    start.Looped = false
    if start.IsPlaying then start:Stop(0.1) end
    start:Play(0.15)
    if hasLoop then
        local conn
        conn = start.Stopped:Connect(function()
            conn:Disconnect()
            if self:IsAlive() and self._wasAggro and not (self._encounterControlled or self._encounterLocked) then
                self:_startAggroLoop()
            end
        end)
    end
end

-- Hook the base AI, then layer aggro-animation behaviour on top.
function DungeonBossMobClass:UpdateAI(deltaTime, players, activeMobs)
    if self._encounterControlled or self._encounterLocked then
        return
    end
    MobClass.UpdateAI(self, deltaTime, players, activeMobs)

    local aggro = (self.AIState == "Walking" or self.AIState == "Attacking")
        and self.TargetPlayer ~= nil

    if aggro then
        if not self._wasAggro then
            self._wasAggro = true
            self:PlayAggroStart()                       -- first acquisition
        elseif not self._extraTracks or not self._extraTracks.AggroLoop then
            -- No AggroLoop authored for this boss: fall back to re-firing the start clip.
            if os.clock() - self._lastAggroFire > AGGRO_REFIRE_SECONDS then
                self:PlayAggroStart()
            end
        end
    elseif self._wasAggro then
        self:_stopAggroLoop()                           -- lost the target
    end
    self._wasAggro = aggro
end

return DungeonBossMobClass
