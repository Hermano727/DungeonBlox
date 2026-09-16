-- MobDeathEffect
-- Plays a Minecraft-style "death poof" for any mob: clones the mob's final
-- pose into an inert, translucent flat-red silhouette, tips it sideways
-- over a short fall (snapping to the ground below if the kill happened
-- mid-air), then swaps it for a small white particle poof and cleans up.
--
-- Split out of MobClass for the same reason MobHPBarUI is: this is pure
-- cosmetic/Instance-manipulation code with no AI or combat state, so it
-- lives in its own sibling module (require(script.Parent:WaitForChild(...))
-- from MobClass, same pattern as MobHPBarUI/MobAnimController/MobGroundUtils).
--
-- Called from MobClass:Die() with the mob's Model BEFORE that Model is
-- destroyed (Die() defers the real destruction via Debris -- see the
-- comment there -- so at the moment this runs, the source model is still a
-- fully valid, still-posed Instance to clone from).
--
-- Applies uniformly to every mob in the game: no subclass (boss, skeleton,
-- hopper) overrides Die(), so wiring this into the base MobClass.Die() is
-- the ONE death effect for the whole roster.

local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local MobDeathEffect = {}

-- ── Tunables (safe to tweak freely -- nothing else in the codebase reads these) ──
local DEATH_RED_COLOR    = Color3.fromRGB(140, 20, 20) -- flat silhouette color
local DEATH_SILHOUETTE_TRANSPARENCY = 0.55 -- 0 = solid, 1 = fully invisible
local FALL_DURATION      = 0.27 -- seconds to tip over (~33% faster than the original 0.4)
local FALL_ANGLE_DEGREES = 85   -- how far it rolls before stopping (of 90 = fully flat)
local LINGER_AFTER_FALL  = 0.35 -- seconds the fallen silhouette stays before poofing
local POOF_PARTICLE_COUNT = 14
local POOF_LIFETIME       = 0.5 -- seconds the poof anchor part (and its particles) stick around

-- How far below the death position to search for ground before giving up
-- and just playing the effect where the mob actually died (e.g. over a pit).
local GROUND_SNAP_MAX_DISTANCE = 500
-- Studs to start the downward ray above the computed feet point, so a mob
-- whose feet already sit exactly on the surface doesn't graze/miss it.
local GROUND_SNAP_START_LIFT = 0.5

-- Strip a cloned mob model down to an inert, uninteractable translucent
-- flat-red silhouette: no textures/decals/UI, no scripts, no
-- collision/queryability (so the already-fixed geometry-aware hit system in
-- MobCombat/CombatClient never sees it as hittable), and holds its final
-- pose rigidly (no lingering animation fighting the fall tween).
local function stripToSilhouette(clone)
	for _, descendant in ipairs(clone:GetDescendants()) do
		if descendant:IsA("BasePart") then
			-- Parts that were ALREADY fully invisible in the source model
			-- (HumanoidRootPart, hitbox/collision volumes, etc.) stay
			-- invisible instead of getting painted red -- recoloring these
			-- unconditionally is what was drawing a big red rectangle where
			-- the corpse's HumanoidRootPart sits.
			if descendant.Transparency < 1 then
				descendant.Color = DEATH_RED_COLOR
				descendant.Material = Enum.Material.SmoothPlastic
				descendant.Transparency = DEATH_SILHOUETTE_TRANSPARENCY
				descendant.Reflectance = 0
			end
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") or descendant:IsA("SurfaceAppearance") then
			descendant:Destroy()
		elseif descendant:IsA("BillboardGui") or descendant:IsA("SurfaceGui") then
			descendant:Destroy()
		elseif descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		elseif descendant:IsA("Sound") then
			descendant:Stop()
			descendant:Destroy()
		elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Fire") or descendant:IsA("Smoke") or descendant:IsA("Sparkles") then
			descendant.Enabled = false
		elseif descendant:IsA("Animator") then
			-- Freeze whatever pose the mob died in -- an animation still
			-- playing on the clone would fight the rigid roll-over tween.
			local ok, tracks = pcall(function() return descendant:GetPlayingAnimationTracks() end)
			if ok and tracks then
				for _, track in ipairs(tracks) do
					track:Stop(0)
				end
			end
		elseif descendant:IsA("Humanoid") then
			descendant.PlatformStand = true
			descendant.WalkSpeed = 0
			descendant.JumpPower = 0
			descendant.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
	end
end

-- Spawn a small white "poof" burst at `position` and let it clean itself up.
local function spawnPoof(position)
	local anchor = Instance.new("Part")
	anchor.Name = "DeathPoofAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 2.2),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.25, 0.4)
	emitter.Speed = NumberRange.new(4, 8)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Enabled = false
	emitter.Parent = anchor

	emitter:Emit(POOF_PARTICLE_COUNT)
	Debris:AddItem(anchor, POOF_LIFETIME)
end

-- Play the full death effect for `sourceModel` (the mob's real Model,
-- still valid/posed -- call this BEFORE the source is destroyed).
-- Fire-and-forget: does not block or return anything to the caller.
function MobDeathEffect.Play(sourceModel)
	if not sourceModel or not sourceModel:IsA("Model") then
		return
	end

	local ok, clone = pcall(function()
		return sourceModel:Clone()
	end)
	if not ok or not clone then
		return
	end

	clone.Name = sourceModel.Name .. "_DeathFX"
	stripToSilhouette(clone)

	local originalCFrame = clone:GetPivot()

	local ok2, boundsCFrame, boundsSize = pcall(function()
		return clone:GetBoundingBox()
	end)
	if not ok2 or not boundsCFrame then
		clone:Destroy()
		return
	end

	-- Bottom-center of the bounding box, in world space: the ground-contact
	-- point the silhouette tips over around, so it looks like it topples on
	-- its feet rather than rotating in place through the floor.
	local pivotPoint = boundsCFrame:PointToWorldSpace(Vector3.new(0, -boundsSize.Y / 2, 0))

	-- A mob killed mid-air (knocked up, flying, over a ledge) would otherwise
	-- play the whole fall floating in open space. Raycast straight down from
	-- its feet and, if there's ground within range, drop the WHOLE pose
	-- (both the pivot and the model's origin, by the same amount) down to
	-- meet it -- shifting only the pivot would just change the rotation
	-- arc's radius, not actually relocate the corpse. No ground found (e.g.
	-- over a bottomless pit) just leaves it playing where the mob died.
	do
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = { clone }
		rayParams.IgnoreWater = true

		local rayOrigin = pivotPoint + Vector3.new(0, GROUND_SNAP_START_LIFT, 0)
		local rayResult = workspace:Raycast(rayOrigin, Vector3.new(0, -GROUND_SNAP_MAX_DISTANCE, 0), rayParams)

		if rayResult then
			local dropDistance = pivotPoint.Y - rayResult.Position.Y
			if dropDistance > 0.05 then
				local shift = Vector3.new(0, -dropDistance, 0)
				originalCFrame = originalCFrame + shift
				pivotPoint = pivotPoint + shift
				clone:PivotTo(originalCFrame)
			end
		end
	end

	-- A CFrame sitting at the pivot point with the model's original
	-- orientation, plus the model's origin re-expressed relative to that
	-- pivot. Every frame below rebuilds the pose from these two fixed
	-- values (never from the previous frame's), so there is no compounding
	-- drift over the tween.
	local pivotCFrame0 = CFrame.new(pivotPoint) * originalCFrame.Rotation
	local localOriginOffset = pivotCFrame0:PointToObjectSpace(originalCFrame.Position)

	-- Roll left or right at random. Rotating around the model's own local Z
	-- (the roll axis) tips it over sideways onto the ground, matching the
	-- Minecraft reference, rather than pitching forward/backward.
	local direction = (math.random(0, 1) == 0) and -1 or 1
	local fallAngle = math.rad(FALL_ANGLE_DEGREES) * direction

	clone.Parent = workspace

	task.spawn(function()
		local startTime = os.clock()
		local heartbeatConn
		heartbeatConn = RunService.Heartbeat:Connect(function()
			local elapsed = os.clock() - startTime
			local alpha = math.clamp(elapsed / FALL_DURATION, 0, 1)
			local eased = TweenService:GetValue(alpha, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			local angle = fallAngle * eased

			local newCFrame = pivotCFrame0 * CFrame.Angles(0, 0, angle) * CFrame.new(localOriginOffset)
			clone:PivotTo(newCFrame)

			if alpha >= 1 then
				heartbeatConn:Disconnect()

				task.wait(LINGER_AFTER_FALL)

				local poofPos = clone:GetPivot().Position
				spawnPoof(poofPos)
				clone:Destroy()
			end
		end)
	end)
end

return MobDeathEffect
