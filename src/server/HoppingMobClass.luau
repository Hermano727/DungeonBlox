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
	return math.clamp(self.Stats.MoveSpeed or 8, 3, 10)
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
			-- Land exactly on the precomputed (already separation-resolved,
			-- ground-snapped) end position.
			self.Model:PivotTo(CFrame.lookAt(self._hopGoalPos, Vector3.new(goalPosition.X, self._hopGoalPos.Y, goalPosition.Z)))
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

		self.Model:PivotTo(CFrame.lookAt(pos, Vector3.new(goalPosition.X, pos.Y, goalPosition.Z)))
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
	local endX = pos.X + dir.X * hopDist
	local endZ = pos.Z + dir.Z * hopDist
	endX, endZ = self:ResolveMobSeparation(endX, endZ)

	local groundY = self:FindGroundY(endX, endZ, pos.Y)
	local endPos = Vector3.new(endX, groundY + (self._feetToRootHeight or 0), endZ)

	self._hopStartPos = pos
	self._hopGoalPos = endPos
	self._hopStartTime = now
	local moveSpeed = self.Stats.MoveSpeed or 8
	self._hopEndTime = now + (hopDist / math.max(moveSpeed, 1))
end

return HoppingMobClass
