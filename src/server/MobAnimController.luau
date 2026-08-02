-- MobAnimController
-- Loads and drives animations for a mob instance.
-- Called by MobClass on spawn (attach), every AI tick (update), and on attack (playAttack).
-- Reads MobAnimConfig keyed by mob.MobID — mobs with no config entry are silently skipped.

local RS = game:GetService("ReplicatedStorage")
local MobAnimConfig = require(RS:WaitForChild("MobAnimConfig"))

local MobAnimController = {}

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

-- Attach animation tracks to a mob after its model has been spawned.
function MobAnimController.attach(mob)
	local cfg = MobAnimConfig[mob.MobID]
	if not cfg then return end

	local model = mob.Model
	if not model then return end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local tracks = {}

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
	local tracks = mob._animTracks
	if not tracks or not tracks.Attack then return end
	if not tracks.Attack.IsPlaying then
		tracks.Attack:Play(0.1)
	end
end

return MobAnimController