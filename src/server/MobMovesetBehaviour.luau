--[[
	MobMovesetBehaviour -- ServerScriptService

	Tier 2 of the two-tier mob combat architecture.

	TIER 1 is MobClass's regular attack state machine, and every ordinary mob
	uses that and nothing else: chase -> in range and facing -> play the
	Attack clip -> damage lands at its authored hit frame (MobAnimConfig's
	AttackHitFrame). Minecraft rules -- if you are in front of it and in
	range, it swings at you.

	TIER 2 is this module: hand-authored SPECIALS (combos, slams, whatever a
	boss gets its own animation for) layered ON TOP of tier 1, not instead of
	it. When a special is off cooldown and the target is inside its reach and
	frontal cone, the mob plays it; otherwise it falls through to the ordinary
	swing. So a boss is never harmless while its special recharges -- it just
	hits you like any other mob in between.

	This replaced Kane's old proximity/"thorns" damage, which dealt damage on
	a timer to anyone standing close with no animation and no facing check.

	It is a MIXIN, not a subclass, so it composes with whatever movement or
	sound class a mob already resolves to -- MobClassRegistry.Resolve picks the
	base class as before and then wraps it here. That sidesteps the registry's
	"can only return ONE class" limit for this axis: a future boss can be a
	DungeonBoss AND have a moveset.

	Opting in from MobData is data only -- no new class file per mob:

		MobData[1]["Kane"] = {
			...
			CombatClass = "Moveset",     -- optional; a Moveset table alone is enough
			Moveset = {
				{
					Id = "AxeCombo3Hit", -- key in MobAnimConfig[MobID].Moveset
					Damage = 100,        -- per connecting impact, before player armor
					SourceDuration = 4,  -- authored clip length in seconds
					HitTimes = { 17/24, 39/24, 66/24 }, -- impacts, in authored time
					HitWindow = 0.2,     -- skip stale strikes after a server stall
					Cooldown = 1.2,      -- before THIS special is offered again
					RangeMultiplier = 1.25, -- of the mob's AttackRange
					HalfAngleDegrees = 70,  -- frontal sweep, half-angle
					Speed = 1,           -- optional playback rate (2 = twice as fast)
					PlayerKnockbackMultiplier = nil, -- optional; defaults to the mob's own
					Chance = 1,          -- optional roll when otherwise eligible
				},
			},
		}

	List several entries to give a boss several specials: the first eligible
	one (off cooldown, in reach, passes its Chance roll) wins, so order the
	array from most situational to most generic.

	NOTE: specials are started from the base class's Attacking state, which
	requires the mob to already be within its ordinary AttackRange. A
	RangeMultiplier above 1 therefore widens where a running special can still
	CONNECT, not where it can open. A true "lunge from out of range" opener
	would need its own entry point in the state machine.
]]

local ServerScriptService = game:GetService("ServerScriptService")

local MobAnimController = require(ServerScriptService:WaitForChild("MobAnimController"))
local DamageService = require(ServerScriptService:WaitForChild("DamageService"))
local MobTelegraph = require(ServerScriptService:WaitForChild("MobTelegraph"))

local MobMovesetBehaviour = {}

-- One extended class per base class, built on demand and reused. Without the
-- cache every spawn would mint a fresh class table for the same base.
local extendedClasses = {}

-- Authoring convenience: a single special may be written as one table instead
-- of a one-element array. Anything without HitTimes/Id is treated as the array.
local function movesetEntries(mob)
	local set = mob.Stats and mob.Stats.Moveset
	if type(set) ~= "table" then return nil end
	if set.HitTimes ~= nil or set.Id ~= nil then
		return { set }
	end
	if #set == 0 then return nil end
	return set
end

-- Extend `baseClass` with the moveset layer. Safe to call repeatedly.
function MobMovesetBehaviour.Extend(baseClass)
	local cached = extendedClasses[baseClass]
	if cached then return cached end

	local class = setmetatable({}, { __index = baseClass })
	class.__index = class

	-- Construct through the base class so its own constructor work still runs
	-- (DungeonBossMobClass sets up its ceiling intro there, for instance), then
	-- re-point the metatable at this class so the overrides below win. The base
	-- constructors only set fields -- none of them call the three methods
	-- overridden here -- so doing this after the fact is safe.
	function class.new(mobId, spawnPosition, spawnerRef, level)
		local mob = baseClass.new(mobId, spawnPosition, spawnerRef, level)
		if mob then
			setmetatable(mob, class)
		end
		return mob
	end

	-- Reach test for one special: the base body-height + horizontal check,
	-- widened by RangeMultiplier, plus a frontal cone so stepping behind the
	-- mob mid-swing dodges it.
	function class:IsTargetWithinMovesetReach(targetHumanoid, entry)
		if not targetHumanoid then return false end
		if not self:IsTargetWithinMeleeReach(targetHumanoid, entry.RangeMultiplier or 1) then
			return false
		end
		local halfAngle = entry.HalfAngleDegrees
		if not halfAngle then return true end
		local root = self.Model and self.Model.PrimaryPart
		local character = targetHumanoid.Parent
		local targetRoot = character and character:FindFirstChild("HumanoidRootPart")
		if not root or not targetRoot then return false end
		local offset = targetRoot.Position - root.Position
		local horizontal = Vector3.new(offset.X, 0, offset.Z)
		if horizontal.Magnitude < 0.05 then return true end
		local look = root.CFrame.LookVector
		local forward = Vector3.new(look.X, 0, look.Z)
		if forward.Magnitude < 0.05 then return false end
		return forward.Unit:Dot(horizontal.Unit) >= math.cos(math.rad(halfAngle))
	end

	-- First eligible special, or nil to fall through to the ordinary swing.
	function class:SelectMoveset(targetHumanoid)
		local entries = movesetEntries(self)
		if not entries then return nil end
		local now = tick()
		self._movesetReadyAt = self._movesetReadyAt or {}
		for index, entry in ipairs(entries) do
			if now >= (self._movesetReadyAt[index] or 0)
				and self:IsTargetWithinMovesetReach(targetHumanoid, entry)
				and ((entry.Chance or 1) >= 1 or math.random() < entry.Chance)
			then
				return entry, index
			end
		end
		return nil
	end

	function class:StartMoveset(entry, index)
		local track = MobAnimController.getMovesetTrack(self, entry.Id)
		-- Length stays 0 until the asset loads. Never run a special off an
		-- unloaded clip -- the mob would stand there dealing invisible hits.
		if not track or track.Length <= 0.05 or track.IsPlaying then return false end

		local speed = tonumber(entry.Speed) or 1
		if speed <= 0 then speed = 1 end
		MobAnimController.playMoveset(self, entry.Id, speed)
		-- Two different timebases here, and mixing them up is the easy bug:
		--   * TimePosition still runs 0 -> track.Length whatever the speed is,
		--     so timeScale (authored HitTimes -> track time) ignores speed.
		--   * `duration` is REAL seconds the clip now takes, so the deadline and
		--     the attack lock below do divide by speed.
		local duration = track.Length / speed
		self._moveset = {
			entry = entry,
			index = index,
			track = track,
			nextHit = 1,
			-- Authored HitTimes are in the clip's own timebase; rescale them if
			-- the uploaded animation's real length differs from SourceDuration.
			timeScale = track.Length / (tonumber(entry.SourceDuration) or track.Length),
			deadline = tick() + duration + 0.5,
		}
		-- Same atomic-attack rule a normal swing uses (see HandleAttacking):
		-- the mob may not leave the attack state until the clip has played out.
		self._attackLockedUntil = tick() + duration

		-- Telegraph, if this special opted in. The offsets handed over are the
		-- SAME authored HitTimes UpdateMoveset lands damage on, converted to real
		-- seconds through the same two rescales -- timeScale for a clip whose
		-- uploaded length differs from SourceDuration, then speed. Derive them
		-- here rather than re-authoring them in the telegraph config, or a combo
		-- retune silently desyncs the warning from the swing.
		if entry.Telegraph then
			local offsets = {}
			for index, hitTime in ipairs(entry.HitTimes or {}) do
				offsets[index] = (hitTime * self._moveset.timeScale) / speed
			end
			MobTelegraph.Begin(self, entry.Telegraph, offsets,
				MobTelegraph.ReachFor(self, entry.RangeMultiplier), entry.HalfAngleDegrees)
		end
		return true
	end

	function class:FinishMoveset()
		local active = self._moveset
		if not active then return end
		-- Drop the mark the moment the special ends, including an early exit
		-- (death, interrupt, deadline). The client fades on its own schedule too,
		-- but nothing should be left painted on the ground after the swing.
		MobTelegraph.Clear(self)
		self._moveset = nil
		self._movesetReadyAt = self._movesetReadyAt or {}
		self._movesetReadyAt[active.index] = tick() + (tonumber(active.entry.Cooldown) or 0)
		-- Make the ordinary swing wait a full AttackCooldown after a special,
		-- so a combo never ends with an instant free hit.
		self.LastAttackTime = tick()
		if active.track.IsPlaying then
			active.track:Stop(0.1)
		end
	end

	-- Walk the active clip's playhead and land each authored impact once.
	function class:UpdateMoveset(players)
		local active = self._moveset
		if not active then return end
		if not active.track.IsPlaying or tick() >= active.deadline then
			self:FinishMoveset()
			return
		end

		local entry = active.entry
		local hitTimes = entry.HitTimes
		if type(hitTimes) ~= "table" then return end
		local position = active.track.TimePosition
		while active.nextHit <= #hitTimes do
			local hitTime = hitTimes[active.nextHit] * active.timeScale
			if position < hitTime then break end
			-- Consume each impact once, even on a miss. After a stall, stale
			-- hits are discarded rather than all landing in one frame.
			active.nextHit += 1
			if position <= hitTime + (entry.HitWindow or 0.2) then
				for _, player in ipairs(players) do
					local character = player.Character
					local humanoid = character and character:FindFirstChildOfClass("Humanoid")
					if self:IsTargetWithinMovesetReach(humanoid, entry) and player.Character == character then
						DamageService.ApplyToPlayer(player, entry.Damage or self.Stats.BaseDamage, self)
						-- No PlayerKnockbackMultiplier on the entry means each impact
						-- shoves exactly as hard as this mob's ordinary swing.
						self:ApplyPlayerHitstun(character, entry.PlayerKnockbackMultiplier)
					end
				end
			end
		end
	end

	-- Called by the base attack state once in range and facing the target.
	-- A special when one is ready, an ordinary swing otherwise.
	function class:PerformAttack(targetHumanoid)
		if self._moveset then return false end
		local entry, index = self:SelectMoveset(targetHumanoid)
		if entry and self:StartMoveset(entry, index) then
			return true
		end
		return baseClass.PerformAttack(self, targetHumanoid)
	end

	function class:UpdateAI(deltaTime, players, activeMobs)
		if not movesetEntries(self) then
			return baseClass.UpdateAI(self, deltaTime, players, activeMobs)
		end
		if not self:IsAlive() or not self.Model or not self.Model.Parent or self.IsSpawnStunned then
			self:FinishMoveset()
			return
		end

		self:UpdateMoveset(players)
		if self._moveset then
			-- Committed to this facing and position until the clip ends, so
			-- stepping behind the mob mid-special dodges the rest of it.
			return
		end
		return baseClass.UpdateAI(self, deltaTime, players, activeMobs)
	end

	function class:Die()
		self:FinishMoveset()
		return baseClass.Die(self)
	end

	extendedClasses[baseClass] = class
	return class
end

return MobMovesetBehaviour
