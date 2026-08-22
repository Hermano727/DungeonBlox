--[[
    HearthstoneConfig
    Static seed data for the hearthstone system. Safe to require from both
    server and client. No DataStore calls or side-effects on require.
]]

local HearthstoneConfig = {}

HearthstoneConfig.COOLDOWN     = 300   -- seconds between teleports (5 minutes)
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
