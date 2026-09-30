-- HoppingMobClass
-- Subclass of MobClass for mobs that move in discrete leaps instead of a
-- smooth walk (e.g. slimes). Demonstrates the override point: only Move()
-- is replaced -- spawning, combat, knockback, animation, death, etc. are
-- all inherited unchanged from MobClass.
--
-- Selection happens in MobSpawner, which picks this class for any MobID
-- whose MobData entry has JumpHeight > 0.

local ServerScriptService = game:GetService("ServerScriptService")
local MobClass = require(ServerScriptService:WaitForChild("MobClass"))

local HoppingMobClass = setmetatable({}, { __index = MobClass })
HoppingMobClass.__index = HoppingMobClass

local HOP_PAUSE = 0.15 -- seconds standing still between hops
local MIN_HOP_HEIGHT = 1.5 -- studs, floor for visibly-arced hops even if MobData.JumpHeight is small

-- Same construction as the base class, just registered under this class's
-- metatable so method lookups resolve here first.
function HoppingMobClass.new(mobId, spawnPosition, spawnerRef, level)
	return MobClass.new(mobId, spawnPosition, spawnerRef, level, HoppingMobClass)
end

function HoppingMobClass:GetHopDistance()
	-- Roughly one hop per second's worth of MoveSpeed, clamped to a sane range.
	return math.clamp(self:GetEffectiveMoveSpeed(), 3, 10)
end

function HoppingMobClass:GetHopHeight()
	return math.max(self.Stats.JumpHeight or 0, MIN_HOP_HEIGHT)
end

-- Override: leap toward goalPosition in arcs instead of sliding smoothly.
-- Still ends in exactly one PivotTo per tick, still ground-snapped, still
-- resolves overlap with other mobs -- only the path taken between start and
-- end differs from the base class.
function HoppingMobClass:Move(goalPosition, deltaTime)
	if not self.Model then
		return
	end
	local primaryPart = self.Model.PrimaryPart
	if not primaryPart then
		return
	end

	local now = tick()

	-- Mid-hop: interpolate along the arc.
	if self._hopEndTime then
		if now >= self._hopEndTime then
			-- Land at the precomputed (already separation-resolved,
			-- ground-snapped) spot -- but re-check separation once more
			-- first. A hop commits to its landing point at launch and can't
			-- react mid-flight the way a smooth walk can, so if another mob
			-- moved into that exact spot while this one was airborne, the
			-- old behaviour was to land there anyway and let the NEXT hop's
			-- (unclamped) push shove it back out -- which is exactly the
			-- "teleports when another mob walks into their place" symptom.
			-- Clamping this correction to a normal per-tick step means any
			-- adjustment plays out smoothly instead of snapping.
			local landX, landZ = self:ResolveMobSeparation(self._hopGoalPos.X, self._hopGoalPos.Z)
			landX, landZ = self:ClampSeparationPush(self._hopGoalPos.X, self._hopGoalPos.Z, landX, landZ, deltaTime)
			local landY = self:FindGroundY(landX, landZ, self._hopGoalPos.Y)
			local landPos = Vector3.new(landX, landY, landZ)

			-- CFrame.lookAt needs a non-zero flat direction from landPos to
			-- goalPosition. A hop almost always lands EXACTLY on its goal
			-- (see the hopDist = math.min(GetHopDistance(), dist) clamp
			-- below -- any approach hop within one hop's reach lands with
			-- landX/landZ bit-identical to goalPosition.X/Z), which makes
			-- that direction the zero vector. CFrame.lookAt normalizes it
			-- regardless, producing a NaN CFrame -- Roblox doesn't error on
			-- that, it silently "quarantines" the part by teleporting its
			-- whole assembly to (0, -1000000, 0), which looked exactly like
			-- a mob vanishing into the void the instant it finished closing
			-- distance on a player (2026-09-09, found while verifying the
			-- atomic-attack-lock fix). Fall back to keeping the model's
			-- current facing, same as MobClass:StepToward already does for
			-- its own near-zero case.
			local lookFlat = Vector3.new(goalPosition.X - landPos.X, 0, goalPosition.Z - landPos.Z)
			if lookFlat.Magnitude > 0.05 then
				self.Model:PivotTo(CFrame.lookAt(landPos, Vector3.new(goalPosition.X, landPos.Y, goalPosition.Z)))
			else
				local _, yaw = primaryPart.CFrame:ToEulerAnglesYXZ()
				self.Model:PivotTo(CFrame.new(landPos) * CFrame.Angles(0, yaw, 0))
			end
			self._hopEndTime = nil
			self._hopLandedAt = now
			return
		end

		local t = (now - self._hopStartTime) / (self._hopEndTime - self._hopStartTime)
		t = math.clamp(t, 0, 1)
		local x = self._hopStartPos.X + (self._hopGoalPos.X - self._hopStartPos.X) * t
		local z = self._hopStartPos.Z + (self._hopGoalPos.Z - self._hopStartPos.Z) * t
		local baseY = self._hopStartPos.Y + (self._hopGoalPos.Y - self._hopStartPos.Y) * t
		local arc = math.sin(math.pi * t) * self:GetHopHeight()
		local pos = Vector3.new(x, baseY + arc, z)

		-- Same zero-direction guard as the landing branch above (rare here
		-- since mid-arc x/z only equal goalPosition.X/Z if the hop wasn't
		-- moving in one flat axis at all, but the failure mode -- a NaN
		-- CFrame that Roblox silently teleports to (0,-1000000,0) -- is bad
		-- enough to guard unconditionally rather than rely on it staying rare.
		local lookFlat = Vector3.new(goalPosition.X - pos.X, 0, goalPosition.Z - pos.Z)
		if lookFlat.Magnitude > 0.05 then
			self.Model:PivotTo(CFrame.lookAt(pos, Vector3.new(goalPosition.X, pos.Y, goalPosition.Z)))
		else
			local _, yaw = primaryPart.CFrame:ToEulerAnglesYXZ()
			self.Model:PivotTo(CFrame.new(pos) * CFrame.Angles(0, yaw, 0))
		end
		return
	end

	-- Grounded: either pausing between hops, or ready to start a new one.
	if self._hopLandedAt and (now - self._hopLandedAt) < HOP_PAUSE then
		return
	end

	local pos = primaryPart.Position
	local flat = Vector3.new(goalPosition.X - pos.X, 0, goalPosition.Z - pos.Z)
	local dist = flat.Magnitude
	if dist < 0.3 then
		self:FaceToward(goalPosition)
		return
	end

	local hopDist = math.min(self:GetHopDistance(), dist)
	local dir = flat.Unit
	local baseEndX = pos.X + dir.X * hopDist
	local baseEndZ = pos.Z + dir.Z * hopDist
	local moveSpeed = self:GetEffectiveMoveSpeed()
	local hopDuration = hopDist / math.max(moveSpeed, 1)

	-- Clamp the separation push added to this hop's landing spot, same idea
	-- as MobClass:StepToward -- otherwise a mob overlapping several
	-- neighbours at hop-launch can get sent an unbounded distance for a
	-- single leap. The cap is expressed in terms of the hop's own duration
	-- (so it scales with how far the mob was already jumping) rather than a
	-- single frame's deltaTime, since a hop is a one-shot event, not a
	-- per-tick one.
	local endX, endZ = self:ResolveMobSeparation(baseEndX, baseEndZ)
	endX, endZ = self:ClampSeparationPush(baseEndX, baseEndZ, endX, endZ, hopDuration)

	local groundY = self:FindGroundY(endX, endZ, pos.Y)
	local endPos = Vector3.new(endX, groundY + (self._feetToRootHeight or 0), endZ)

	self._hopStartPos = pos
	self._hopGoalPos = endPos
	self._hopStartTime = now
	self._hopEndTime = now + hopDuration
end

-- Ambient idle: alternate between sitting still and hopping to a random
-- nearby point, so a spawned pack looks alive instead of frozen until a
-- player wanders into aggro range.
--
-- Reuses Move() rather than duplicating the arc/landing maths, which means
-- idle hops go through the same separation and ground-snapping as chase
-- hops -- a stacked pack therefore also unpacks itself while wandering.
local WANDER_RADIUS      = 18   -- max studs from spawn point
local IDLE_PAUSE_MIN     = 0.8  -- seconds of stillness between wanders
local IDLE_PAUSE_MAX     = 3.0
local WANDER_CHANCE      = 0.65 -- else just sit for another beat

function HoppingMobClass:IdleBehaviour(deltaTime, currentPosition)
	if not self.Model or not self.Model.PrimaryPart then
		return
	end

	local now = tick()

	-- Mid-hop: keep interpolating toward the point we already chose.
	if self._hopEndTime and self._wanderGoal then
		self:Move(self._wanderGoal, deltaTime)
		return
	end

	-- Just landed: pick how long to rest before deciding again.
	if self._wanderGoal and not self._hopEndTime then
		self._wanderGoal = nil
		self._nextWanderAt = now + IDLE_PAUSE_MIN
			+ math.random() * (IDLE_PAUSE_MAX - IDLE_PAUSE_MIN)
		return
	end

	if self._nextWanderAt and now < self._nextWanderAt then
		return
	end

	-- Decide: wander, or sit this beat out.
	if math.random() > WANDER_CHANCE then
		self._nextWanderAt = now + IDLE_PAUSE_MIN
			+ math.random() * (IDLE_PAUSE_MAX - IDLE_PAUSE_MIN)
		return
	end

	-- Random bearing, biased back toward the spawn point when we've drifted
	-- far, so a pack loosely holds its room instead of migrating away.
	local home = self.SpawnPosition or currentPosition
	local pos = self.Model.PrimaryPart.Position
	local fromHome = Vector3.new(pos.X - home.X, 0, pos.Z - home.Z)
	local angle = math.random() * math.pi * 2

	if fromHome.Magnitude > WANDER_RADIUS then
		local back = (-fromHome).Unit
		angle = math.atan2(back.Z, back.X) + (math.random() - 0.5) * 1.4
	end

	local dist = 4 + math.random() * (self:GetHopDistance() or 6)
	self._wanderGoal = Vector3.new(
		pos.X + math.cos(angle) * dist,
		pos.Y,
		pos.Z + math.sin(angle) * dist
	)
	self:Move(self._wanderGoal, deltaTime)
end

return HoppingMobClass
