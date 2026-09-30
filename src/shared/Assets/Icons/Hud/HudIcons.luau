--[[
    HudIcons
    Registry for always-on HUD readout icons (combat timer, dungeon timer). Require this
    instead of writing rbxassetid:// literals inline.

    An empty string means the art isn't uploaded yet: consumers hide the icon and show
    their text alone.
]]

return {
    COMBAT = "rbxassetid://71642300678008",  -- same art as the Combat XP bar (XpHud COMBAT_ICON_IMAGE)
    HOURGLASS = "rbxassetid://101689122909149", -- dungeon run timer
    POISON = "rbxassetid://129079944361419",    -- Miasma poison stacks (client/PoisonIndicators)
    SKULL = "rbxassetid://129025213075574",     -- named-elite pity counter (HealthClient)
}
