-- SkeletonMobClass
-- Subclass of MobClass for skeleton-family mobs. Demonstrates the same
-- override point HoppingMobClass uses for Move(), just for combat sfx
-- instead of movement: only GetHitSoundId() is replaced -- spawning,
-- combat, knockback, animation, death, AI, etc. are all inherited
-- unchanged from MobClass.
--
-- Selection happens in MobClassRegistry, which picks this class for any
-- MobID whose MobData entry has SoundClass = "Skeleton" (see
-- MobData["SmallSkeleton"]).

local ServerScriptService = game:GetService("ServerScriptService")
local MobClass = require(ServerScriptService:WaitForChild("MobClass"))

local SkeletonMobClass = setmetatable({}, { __index = MobClass })
SkeletonMobClass.__index = SkeletonMobClass

-- Bone-rattle hit sounds. Cycled in order (see GetHitSoundId below) rather
-- than picked randomly each hit, so four hits in a row never repeat a clip
-- back-to-back the way pure randomness occasionally would.
local HIT_SOUND_IDS = {
	"rbxassetid://100461404466922",
	"rbxassetid://136105268301506",
	"rbxassetid://125873694741544",
	"rbxassetid://120370096258351",
}

-- Same construction as the base class, just registered under this class's
-- metatable so method lookups resolve here first.
function SkeletonMobClass.new(mobId, spawnPosition, spawnerRef, level)
	return MobClass.new(mobId, spawnPosition, spawnerRef, level, SkeletonMobClass)
end

-- Override: cycle through HIT_SOUND_IDS in order instead of the shared
-- default glass sfx. self._hitSoundIndex is per mob INSTANCE (not shared
-- across all skeletons), so two skeletons hit on the same tick each run
-- their own independent cycle rather than stomping a shared counter.
function SkeletonMobClass:GetHitSoundId()
	self._hitSoundIndex = (self._hitSoundIndex or 0) % #HIT_SOUND_IDS + 1
	return HIT_SOUND_IDS[self._hitSoundIndex]
end

return SkeletonMobClass
