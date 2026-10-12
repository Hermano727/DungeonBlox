--[[
	MountConfig -- ReplicatedStorage. The horse mount (2026-10-11): one place for its numbers.

	Riding: press Keys.Mount (H) out of combat to call your horse; press again to send it away.
	Combat of any kind (taking or dealing a hit, PvP flag) throws you off and it bolts; so does
	an arrow hitting the horse from someone who may attack you (SSS/MountService.OnMountShot).
	You "have a horse" when you own any saddle: the fastest saddle you carry sets the speed
	(ItemDefinitions MountSpeed, T1 20 .. T4 50; sold by the Animal Trainer).

	How it rides (SSS/MountService): the rider keeps their own Humanoid and controls; the horse
	model (ServerStorage.HorseMount, assets/models/mounts/horse) is welded under them, massless
	and non-colliding, and the character is lifted (Humanoid.HipHeight) so its hips sit on the
	saddle. WalkSpeed becomes the saddle's speed (EnergyServer reads the MountSpeed player
	attribute, so sprint/crouch/panting can't fight it). The server plays the horse clips from the
	rider's speed and the rider pose on the character.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local MountConfig = {}

MountConfig.MODEL_NAME = "HorseMount"            -- ServerStorage
MountConfig.FOLDER_NAME = "DungeonHorseMounts"   -- Workspace folder the live horses sit in

MountConfig.Animations = {
	Idle = "rbxassetid://80186941608534",        -- 4 s loop, standing under the rider
	RunStart = "rbxassetid://81969123596220",    -- 1 s, idle -> gallop
	RunLoop = "rbxassetid://124559181067098",    -- 0.6 s loop, one gallop stride
	-- The PLAYER on the horse, one clip per horse clip, same frames and length, posed against the
	-- horse's own back and neck (rider/author_ride_clips.py): legs forward in the stirrups, leaning
	-- forward, hands on the reins, riding the saddle's bob. MountService switches them with the horse.
	RideIdle = "rbxassetid://74611781160733",    -- 4 s loop, with Idle
	RideStart = "rbxassetid://120960169193789",  -- 1 s, with RunStart (same RUN_START_PLAYBACK)
	RideRun = "rbxassetid://114420523064223",    -- 0.6 s loop, with RunLoop (same playback rate)
	Ride = "rbxassetid://128558255884686",       -- the first static pose (rider/author_ride.py); unused now
}

-- Fit (measured on the model, see the horse README): the rider's hip joints sit SEAT_ABOVE_FLOOR
-- above the horse's floor; the horse's root part (its mesh centre) is HORSE_CENTRE_ABOVE_FLOOR up.
MountConfig.SEAT_ABOVE_FLOOR = 5.0
MountConfig.HORSE_CENTRE_ABOVE_FLOOR = 3.6
MountConfig.SEAT_OFFSET_XZ = Vector2.new(0.05, 0.0)  -- horse centre relative to the rider (mesh x / z)

-- The gallop clip covers one stride per 0.6 s at playback speed 1: this ground speed. Faster
-- saddles play it faster (clamped), so the hooves don't slide.
MountConfig.NOMINAL_RUN_SPEED = 30
MountConfig.RUN_PLAYBACK_MIN, MountConfig.RUN_PLAYBACK_MAX = 0.75, 1.6
MountConfig.MOVING_SPEED = 2.5       -- studs/s of the rider's flat velocity: above this it runs
-- 2026-10-11: the 1 s RunStart clip at speed 1 read as "stands idle, then suddenly runs" (the
-- rider is already at full speed). Played this much faster it's a quick gather into the gallop.
MountConfig.RUN_START_PLAYBACK = 2.5
-- Seconds below MOVING_SPEED before the horse settles back to Idle: a dip while turning or
-- bumping something keeps the gallop instead of replaying the wind-up.
MountConfig.STOP_GRACE = 0.3

MountConfig.SUMMON_COOLDOWN = 2.0    -- seconds after the horse leaves before it can be called again
MountConfig.THROWN_COOLDOWN = 5.0    -- after being thrown off (combat / shot)
MountConfig.IDLE_SOUND_EVERY = NumberRange.new(7, 14)   -- seconds between the horse's idle sounds

-- What the horse says (SoundEffects keys) and at what pitch. Lists in SoundEffects = a random one.
MountConfig.Sounds = {
	Summon = { key = "HorseCall", speed = NumberRange.new(0.56, 0.64) },
	Dismiss = { key = "HorseCall", speed = NumberRange.new(0.5, 0.56) },
	Thrown = { key = "HorseThrown", speed = NumberRange.new(0.72, 0.8) },
	Idle = { key = "HorseIdle", speed = NumberRange.new(0.95, 1.05) },
	Gallop = { key = "HorseGallop" },    -- looped on the horse while it runs (empty = silent)
}

-- Why the server refused (the RemoteFunction's reason) -> what the player is told.
MountConfig.REFUSALS = {
	no_saddle = "You need a saddle. The Animal Trainer sells them.",
	in_combat = "You can't call your horse in combat.",
	cooldown = "Your horse isn't ready yet.",
	in_dungeon = "Horses can't come into a dungeon.",
	no_character = "You need to be standing somewhere first.",
	busy = "Not right now.",
	no_horse = "The horse is missing from the game files.",
}
MountConfig.THROWN_MESSAGES = {
	combat = "Your horse bolts!",
	shot = "Your horse was shot and bolts!",
}

-- The fastest saddle `profile` owns: { itemId, name, tier, speed, item } or nil.
function MountConfig.BestSaddle(profile)
	local best
	for _, item in pairs(type(profile) == "table" and profile.inventory or {}) do
		local def = type(item) == "table" and type(item.itemId) == "string" and ItemDefinitions.Get(item.itemId) or nil
		local speed = def and tonumber(def.MountSpeed)
		if speed and speed > 0 and (not best or speed > best.speed) then
			best = { itemId = item.itemId, name = def.DisplayName or item.itemId, tier = def.Tier, speed = speed, item = item }
		end
	end
	return best
end

return table.freeze(MountConfig)
