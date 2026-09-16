-- MobClassRegistry
-- Factory for deciding which MobClass (or subclass) to construct for a given
-- MobID. Pulled out of MobSpawner's one-off if/else so adding a new movement
-- style -- a flyer, a teleporter, whatever comes after HoppingMobClass -- is
-- a `Register` call here plus the new class file, not another branch wedged
-- into the spawn pipeline. Mirrors the factory idea from the item system
-- (src/shared/Items/*.lua): a small table of named implementations plus one
-- lookup function, not a growing chain of conditionals.
--
-- Selection order for MobClassRegistry.Resolve(mobId):
--   1. An explicit MobData[...].MovementClass string naming a registered
--      class (e.g. MovementClass = "Hopping"). Opt-in -- no mob sets this
--      today.
--   2. An explicit MobData[...].SoundClass string naming a registered class
--      (e.g. SoundClass = "Skeleton", see SmallSkeleton). Same opt-in shape
--      as MovementClass, just for a combat-sound override instead of a
--      movement one -- see the Resolve() comment below for the "can't have
--      both" caveat.
--   3. The original heuristic, unchanged: JumpHeight > 0 -> "Hopping".
--   4. "Default" (plain MobClass).
--
-- This keeps 100% of current spawn behavior identical for every existing
-- MobData entry; MovementClass/SoundClass are purely additive for future
-- mobs/classes.

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MobClass = require(ServerScriptService:WaitForChild("MobClass"))
local HoppingMobClass = require(ServerScriptService:WaitForChild("HoppingMobClass"))
local SkeletonMobClass = require(ServerScriptService:WaitForChild("SkeletonMobClass"))
local SlimeMobClass = require(ServerScriptService:WaitForChild("SlimeMobClass"))
local MobData = require(ReplicatedStorage:WaitForChild("MobData"))

local MobClassRegistry = {}

local DungeonBossMobClass = require(ServerScriptService:WaitForChild("DungeonBossMobClass"))

local registeredClasses = {
	Default = MobClass,
	Hopping = HoppingMobClass,
	DungeonBoss = DungeonBossMobClass,
	Skeleton = SkeletonMobClass,
	Slime = SlimeMobClass,
}

-- Register a new mob class under `name` (e.g. a future FlyingMobClass).
-- Once registered, any MobData entry can opt into it via
-- `MovementClass = name` without touching MobSpawner or this module again.
function MobClassRegistry.Register(name, classModule)
	registeredClasses[name] = classModule
end

-- Resolve which class module should be constructed for a given MobID.
-- Never errors on an unknown/missing mob -- falls back to Default, same as
-- the pre-registry behavior did (MobClass.new itself warns and returns nil
-- for a truly unknown MobID).
function MobClassRegistry.Resolve(mobId)
	local baseStats = MobData.FindMobById(mobId)
	if baseStats then
		if type(baseStats.MovementClass) == "string" and registeredClasses[baseStats.MovementClass] then
			return registeredClasses[baseStats.MovementClass]
		end
		-- Same opt-in shape as MovementClass above, just for a combat-sound
		-- override instead of a movement one (see SkeletonMobClass, which
		-- only overrides GetHitSoundId() and inherits everything else --
		-- same template HoppingMobClass uses for Move()). Checked
		-- independently of MovementClass so a mob that only needs a sound
		-- override (SmallSkeleton today) doesn't have to fake a movement
		-- class to get one. NOTE: Resolve can only return ONE class, so a
		-- mob needing BOTH a custom movement class AND a custom sound class
		-- can't have both yet -- same pre-existing limitation MovementClass
		-- vs. the JumpHeight heuristic already has below. Would need real
		-- mixin/composition if that combination ever comes up.
		if type(baseStats.SoundClass) == "string" and registeredClasses[baseStats.SoundClass] then
			return registeredClasses[baseStats.SoundClass]
		end
		if (baseStats.JumpHeight or 0) > 0 then
			return registeredClasses.Hopping
		end
	end
	return registeredClasses.Default
end

-- Convenience one-shot: resolve + construct in one call. Same signature as
-- the MobClass/HoppingMobClass constructors it wraps.
function MobClassRegistry.Create(mobId, spawnPosition, spawnerRef, level)
	local class = MobClassRegistry.Resolve(mobId)
	return class.new(mobId, spawnPosition, spawnerRef, level)
end

return MobClassRegistry
