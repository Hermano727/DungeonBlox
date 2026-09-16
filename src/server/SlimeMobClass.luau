-- SlimeMobClass
-- Subclass of HoppingMobClass (not MobClass directly) for slime-family mobs:
-- keeps the inherited hop movement (Move/GetHopDistance/GetHopHeight) but
-- overrides GetHitSoundId() to play a random squelch instead of the shared
-- default glass sfx. Same override-point idea as SkeletonMobClass, just
-- chained off Hopping instead of the base class -- Hopping is used by
-- several unrelated mobs (Forest Goblin, Cave Bat, Shadow Wolf, ...) via the
-- JumpHeight > 0 heuristic, so the sound override can't just live on
-- HoppingMobClass itself without leaking a slime noise onto all of them.
--
-- Selection happens in MobClassRegistry, which picks this class for any
-- MobID whose MobData entry has MovementClass = "Slime" (see
-- MobData["PlainsSlime"]/["PlainsSlimeElite"]). Set as MovementClass, not
-- SoundClass, so it wins ahead of the JumpHeight heuristic in Resolve() --
-- SoundClass alone would have worked too (SlimeMobClass still hops, since it
-- inherits Move() from HoppingMobClass either way), but MovementClass is the
-- semantically correct field since this class also determines movement.

local ServerScriptService = game:GetService("ServerScriptService")
local HoppingMobClass = require(ServerScriptService:WaitForChild("HoppingMobClass"))
local MobClass = require(ServerScriptService:WaitForChild("MobClass"))

local SlimeMobClass = setmetatable({}, { __index = HoppingMobClass })
SlimeMobClass.__index = SlimeMobClass

-- Squelch/splat hit sounds, picked at random (not cycled -- unlike
-- SkeletonMobClass's deliberate no-repeat cycle, per direct request for
-- genuine randomness here) each time the slime takes a hit.
local HIT_SOUND_IDS = {
	"rbxassetid://133611890641003",
	"rbxassetid://84189322633207",
	"rbxassetid://122806880301120",
}

local rng = Random.new()

-- Same construction as HoppingMobClass/SkeletonMobClass, just registered
-- under this class's metatable so method lookups resolve here (then
-- HoppingMobClass, then MobClass) first.
function SlimeMobClass.new(mobId, spawnPosition, spawnerRef, level)
	return MobClass.new(mobId, spawnPosition, spawnerRef, level, SlimeMobClass)
end

-- Override: random pick every hit instead of the shared default glass sfx.
function SlimeMobClass:GetHitSoundId()
	return HIT_SOUND_IDS[rng:NextInteger(1, #HIT_SOUND_IDS)]
end

return SlimeMobClass
