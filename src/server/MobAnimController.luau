-- MobAnimController
-- Loads and drives animations for a mob instance.
-- Called by MobClass on spawn (attach), every AI tick (update), and on attack (playAttack).
-- Reads MobAnimConfig keyed by mob.MobID — mobs with no config entry are silently skipped.

local RS = game:GetService("ReplicatedStorage")
local MobAnimConfig = require(RS:WaitForChild("MobAnimConfig"))
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local MobScriptedBodyAnim = require(script.Parent:WaitForChild("MobScriptedBodyAnim"))

local MobAnimController = {}

-- Cache of {assetId -> sorted array of keyframe Times} so repeated spawns of
-- the same MobID don't refetch the same KeyframeSequence every time.
local frameTimeCache = {}

-- Resolves cfg.AttackHitFrame (a 0-indexed frame, matching however the clip
-- was authored -- frame 0 is its first keyframe) to a real seconds-offset
-- into the clip, by reading the animation's own KeyframeSequence instead of
-- assuming a fixed frame rate. Returns nil (and warns) if the fetch fails or
-- the requested frame doesn't exist, so callers can fall back gracefully.
local function getFrameTime(assetId, frameIndex)
	local times = frameTimeCache[assetId]
	if not times then
		local ok, seqOrErr = pcall(function()
			return KeyframeSequenceProvider:GetKeyframeSequenceAsync(assetId)
		end)
		if not ok then
			warn("[MobAnimController] Failed to fetch KeyframeSequence for", assetId, seqOrErr)
			return nil
		end
		local kfs = seqOrErr:GetKeyframes()
		table.sort(kfs, function(a, b) return a.Time < b.Time end)
		times = {}
		for i, kf in ipairs(kfs) do
			times[i] = kf.Time
		end
		frameTimeCache[assetId] = times
	end

	-- frame 0 is the first authored keyframe, i.e. times[1] in this 1-indexed array.
	local i = frameIndex + 1
	if not times[i] then
		warn("[MobAnimController] Frame", frameIndex, "out of range for", assetId, "(", #times, "keyframes)")
		return nil
	end
	return times[i]
end

-- Load a single animation track on the given Animator.
local function loadTrack(animator, assetId, priority)
	local anim = Instance.new("Animation")
	anim.AnimationId = assetId
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if not ok then
		warn("[MobAnimController] Failed to load animation", assetId, track)
		return nil
	end
	track.Priority = priority
	return track
end

-- The Animator a mob's clips play on. R15/R6 rigs keep it under their Humanoid; skinned-mesh
-- models (Miasma, "moving away from R15") have no Humanoid and use an AnimationController
-- instead. Creates the Animator if the model has the driver but not yet the Animator.
-- Returns nil for a model with neither (nothing to animate).
function MobAnimController.GetAnimator(model)
	if not model then return nil end
	local driver = model:FindFirstChildOfClass("Humanoid")
		or model:FindFirstChildOfClass("AnimationController")
	if not driver then return nil end
	local animator = driver:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = driver
	end
	return animator
end

-- Attach animation tracks to a mob after its model has been spawned.
function MobAnimController.attach(mob)
	local cfg = MobAnimConfig[mob.MobID]
	if not cfg then return end

	local model = mob.Model
	if not model then return end

	local animator = MobAnimController.GetAnimator(model)
	if not animator then return end

	local tracks = {}

	-- Scripted-body mobs (no skeletal rig at all -- just a single "Body" part,
	-- see MobScriptedBodyAnim) get a squash-and-stretch driver instead of
	-- loaded Animation tracks, and their attack-hit timing comes from a flat
	-- AttackHitDelay instead of a KeyframeSequence frame lookup (there is no
	-- animation asset to read frames from).
	if cfg.ScriptedBody then
		MobScriptedBodyAnim.attach(mob)
		if cfg.AttackHitDelay ~= nil then
			mob._attackHitDelay = cfg.AttackHitDelay
		end
		-- MobClass:PerformAttack locks the mob in place for exactly this
		-- long so the attack plays out atomically (see HandleAttacking) --
		-- read from the module itself rather than duplicated here so the
		-- two can never drift out of sync.
		mob._attackAnimDuration = MobScriptedBodyAnim.ATTACK_DURATION
	end

	-- Walk: accepts a single ID string or a table of IDs for random variety.
	if cfg.Walk then
		if type(cfg.Walk) == "table" then
			tracks.WalkList = {}
			for _, id in ipairs(cfg.Walk) do
				local t = loadTrack(animator, id, Enum.AnimationPriority.Movement)
				if t then table.insert(tracks.WalkList, t) end
			end
		else
			tracks.Walk = loadTrack(animator, cfg.Walk, Enum.AnimationPriority.Movement)
		end
	end

	if cfg.Attack then
		tracks.Attack = loadTrack(animator, cfg.Attack, Enum.AnimationPriority.Action)
		if tracks.Attack and cfg.AttackHitFrame ~= nil then
			mob._attackHitDelay = getFrameTime(cfg.Attack, cfg.AttackHitFrame)
		end
		-- Fallback: an authored-seconds offset into the clip.
		-- REQUIRED for FBX-imported animations. Those upload as curve/channel
		-- animations, and KeyframeSequenceProvider only speaks the older
		-- KeyframeSequence format -- it returns an EMPTY sequence for them (0
		-- keyframes) rather than erroring, so AttackHitFrame silently cannot
		-- resolve no matter who owns the asset. Hit 2026-09-17 with Kane's
		-- imported slash: "Frame 19 out of range ... ( 0 keyframes )".
		-- AttackHitDelay is in the clip's AUTHORED timebase, same as
		-- AttackHitFrame, so AttackSpeed rescales it below either way.
		if tracks.Attack and mob._attackHitDelay == nil and cfg.AttackHitDelay ~= nil then
			mob._attackHitDelay = cfg.AttackHitDelay
		end
		-- Same atomic-attack lock as the ScriptedBody branch above, but for
		-- a real Animator track: its own Length is the true swing duration,
		-- available as soon as it's loaded (no need to play it first).
		-- `not mob._attackAnimDuration` guard is belt-and-suspenders in case
		-- a mob somehow configures both ScriptedBody and a Walk/Attack track.
		if tracks.Attack and not mob._attackAnimDuration then
			local length = tracks.Attack.Length
			if length and length > 0.05 then
				mob._attackAnimDuration = length
			end
		end

		-- AttackSpeed scales playback of the ordinary swing (2 = twice as fast).
		-- Both numbers derived from the clip above are REAL-TIME -- when the hit
		-- lands, and how long the mob is locked in the attack state -- so they
		-- have to shrink by the same factor, or damage lands after the swing has
		-- already finished playing. Ignored by ScriptedBody mobs, whose pulse is
		-- generated rather than played from a clip.
		local attackSpeed = tonumber(cfg.AttackSpeed)
		if tracks.Attack and attackSpeed and attackSpeed > 0 and attackSpeed ~= 1 then
			mob._attackSpeed = attackSpeed
			if mob._attackHitDelay then
				mob._attackHitDelay = mob._attackHitDelay / attackSpeed
			end
			if mob._attackAnimDuration then
				mob._attackAnimDuration = mob._attackAnimDuration / attackSpeed
			end
		end
	end

	-- Moveset: named one-shot clips for hand-authored specials (combos, slams).
	-- Keyed by the same name a MobData Moveset entry's `Id` uses -- see
	-- MobMovesetBehaviour, which drives the playhead and lands the impacts.
	if type(cfg.Moveset) == "table" then
		tracks.Moveset = {}
		for name, id in pairs(cfg.Moveset) do
			local t = loadTrack(animator, id, Enum.AnimationPriority.Action)
			if t then
				t.Looped = false
				tracks.Moveset[name] = t
			end
		end
	end

	if cfg.Idle then
		tracks.Idle = loadTrack(animator, cfg.Idle, Enum.AnimationPriority.Idle)
	end

	mob._animTracks = tracks
	mob._currentWalkTrack = nil
end

-- Stop every walk track (single or list).
local function stopAllWalk(mob)
	local tracks = mob._animTracks
	if not tracks then return end
	if tracks.Walk and tracks.Walk.IsPlaying then
		tracks.Walk:Stop(0.15)
	end
	if tracks.WalkList then
		for _, t in ipairs(tracks.WalkList) do
			if t.IsPlaying then t:Stop(0.15) end
		end
	end
	mob._currentWalkTrack = nil
end

-- Pick a walk track. For lists, choose randomly so mobs in the same group look varied.
local function pickWalk(mob)
	local tracks = mob._animTracks
	if not tracks then return nil end
	if tracks.Walk then return tracks.Walk end
	if tracks.WalkList and #tracks.WalkList > 0 then
		return tracks.WalkList[math.random(1, #tracks.WalkList)]
	end
	return nil
end

-- Called directly by MobClass whenever its AI state changes, instead of
-- being guessed from physics each tick. Both Humanoid.MoveDirection (never
-- populates for server-driven AI) and AssemblyLinearVelocity (noisy, tied to
-- whatever locomotion quirks the engine has that week) turned out to be
-- unreliable signals for "is this mob currently walking." The AI already
-- knows definitively whether it's walking -- just tell the animator.
function MobAnimController.setWalking(mob, isWalking)
	local tracks = mob._animTracks
	if not tracks then return end

	if isWalking then
		if tracks.Idle and tracks.Idle.IsPlaying then
			tracks.Idle:Stop(0.15)
		end
		local cur = mob._currentWalkTrack
		if not cur or not cur.IsPlaying then
			stopAllWalk(mob)
			local next = pickWalk(mob)
			if next then
				next:Play(0.15)
				mob._currentWalkTrack = next
			end
		end
	else
		if mob._currentWalkTrack and mob._currentWalkTrack.IsPlaying then
			stopAllWalk(mob)
		end
		if tracks.Idle and not tracks.Idle.IsPlaying then
			tracks.Idle:Play(0.15)
		end
	end
end

-- Called from MobClass:PerformAttack.
function MobAnimController.playAttack(mob)
	local cfg = MobAnimConfig[mob.MobID]
	if cfg and cfg.ScriptedBody then
		MobScriptedBodyAnim.playAttack(mob)
	end

	local tracks = mob._animTracks
	if not tracks or not tracks.Attack then return end
	if not tracks.Attack.IsPlaying then
		tracks.Attack:Play(0.1)
	end
	tracks.Attack:AdjustSpeed(mob._attackSpeed or 1)
end

-- Loaded special-attack track by name, or nil if this mob has no such clip.
function MobAnimController.getMovesetTrack(mob, name)
	local tracks = mob._animTracks
	if not tracks or not tracks.Moveset then return nil end
	return tracks.Moveset[name]
end

-- Called from MobMovesetBehaviour when a special starts. `speed` is that
-- special's own playback rate (2 = twice as fast); the caller is responsible
-- for scaling anything it measures in real time by the same factor.
function MobAnimController.playMoveset(mob, name, speed)
	local track = MobAnimController.getMovesetTrack(mob, name)
	if not track then return nil end
	MobAnimController.setWalking(mob, false)
	if not track.IsPlaying then
		track:Play(0.1)
	end
	track:AdjustSpeed(speed or 1)
	return track
end

return MobAnimController