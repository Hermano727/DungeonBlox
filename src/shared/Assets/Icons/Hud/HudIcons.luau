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
    SKULL = "rbxassetid://129025213075574",     -- named-elite pity plate (ElitePityHud)
    -- Input hints (2026-10-03, white so they can be tinted; drawn on dark plates):
    MOUSE_LEFT = "rbxassetid://82241361103402", -- left mouse button (mouse left button.png)
    KEY_ESC = "rbxassetid://94528884584792",    -- Esc keycap (Escape Icon.png)
    COOK = "rbxassetid://74813060783837", -- the COOK prompt emblem (CookingClient): fish skewered over a fire
    BUFF_SWIFTNESS = "rbxassetid://96006343438403", -- buff list (BuffHudClient): WalkSpeedPct (blue feather)
    BUFF_FORTUNE = "rbxassetid://116817189453595", -- buff list: LuckPct (four-leaf clover)
    DASH = "rbxassetid://119848204870988", -- the dash cooldown disc under the crosshair (DashClient) ("White Fast-Forward Speed Icon.png")
}
