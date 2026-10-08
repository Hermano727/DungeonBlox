--[[
    HearthstoneConfig
    Static seed data for the hearthstone system. Safe to require from both
    server and client. No DataStore calls or side-effects on require.
]]

local HearthstoneConfig = {}

HearthstoneConfig.COOLDOWN     = 300   -- seconds between teleports (5 minutes)

-- Using it is a channel (cast time) you can only START out of combat; taking a hit during it
-- breaks it (SSS/HearthstoneService). Length by the player's OWN alignment
-- (ProfileService.GetAlignment), same idea as the shard hop's ShardConfig.CHANNEL_SECONDS.
HearthstoneConfig.CHANNEL_SECONDS = {
    Lawful = 10,
    Neutral = 20,
    Chaotic = 30,
}
-- During the tutorial (profile.flags.tutorial not done) the channel is just this long.
HearthstoneConfig.TUTORIAL_CHANNEL_SECONDS = 3
HearthstoneConfig.DATASTORE_KEY = "HearthstoneLocations_v1"

-- Replace with your Roblox UserId for admin access to the dev panel.
-- Sourced from DevRoster (single source of truth for dev/admin UserIds).
HearthstoneConfig.ADMIN_IDS = require(script.Parent:WaitForChild("DevRoster")).IDS

local HearthstoneIcons = require(script.Parent.Assets.Icons.Hearthstones.HearthstoneIcons)

-- Seed locations always available; DataStore overlays dynamic additions.
HearthstoneConfig.SEED_LOCATIONS = {
    {
        id       = "oakhaven",
        name     = "Oakhaven",
        cost     = 0,
		position = Vector3.new(-1194.067, 8.39, 31.421),
        icon     = HearthstoneIcons.oakhaven,
    },
}

return HearthstoneConfig
