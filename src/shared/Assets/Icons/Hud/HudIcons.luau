--[[
    HudIcons
    Registry for always-on HUD readout icons (combat timer, dungeon timer). Require this
    instead of writing rbxassetid:// literals inline.

    An empty string means the art isn't uploaded yet: consumers hide the icon and show
    their text alone.
]]

return {
    -- THE combat icon, used everywhere combat is shown (XP bar, combat timer, Skills,
    -- Records...): the sword and shield (2026-10-01; same asset as JournalUI icon_stats).
    -- Replaced the white axe, rbxassetid://71642300678008.
    COMBAT = "rbxassetid://99426945678481",
    HOURGLASS = "rbxassetid://101689122909149", -- dungeon run timer
    POISON = "rbxassetid://129079944361419",    -- Miasma poison stacks (client/PoisonIndicators)
    SKULL = "rbxassetid://129025213075574",     -- named-elite pity counter (HealthClient)
}
