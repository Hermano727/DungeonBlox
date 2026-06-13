--[[
    HearthstoneIcons
    Central registry for hearthstone location icon asset IDs.
    Require this anywhere you need icon strings instead of scattering
    rbxassetid:// literals through the codebase.

    Keys must match the `id` field of HearthstoneConfig.SEED_LOCATIONS
    and any dynamic location ids you create via HearthstoneRegistry.AddLocation.
]]

return {
    oakhaven = "rbxassetid://83746968337101",
    cyren    = "",   -- no icon assigned yet
}
