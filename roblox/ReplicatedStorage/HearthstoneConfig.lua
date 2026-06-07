--[[
    HearthstoneConfig
    Static seed data for the hearthstone system. Safe to require from both
    server and client. No DataStore calls or side-effects on require.
]]

local HearthstoneConfig = {}

HearthstoneConfig.COOLDOWN     = 300   -- seconds between teleports (5 minutes)
HearthstoneConfig.DATASTORE_KEY = "HearthstoneLocations_v1"

-- Replace with your Roblox UserId for admin access to the dev panel.
HearthstoneConfig.ADMIN_IDS = { 706604079 }

-- Seed locations always available; DataStore overlays dynamic additions.
HearthstoneConfig.SEED_LOCATIONS = {
    {
        id       = "cyren",
        name     = "Cyren",
        cost     = 0,
        position = Vector3.new(-31, 4, -69),
    },
}

return HearthstoneConfig
