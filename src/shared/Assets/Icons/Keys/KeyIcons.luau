--[[
    KeyIcons
    Central registry for dungeon key icon asset IDs.
    Require this instead of writing rbxassetid:// literals inline.

    Keys match the corresponding itemId in ReplicatedStorage/ItemDefinitions.

    2026-10-12: one icon for every tier for now, a faceted old key ("Faceted Wooden Skeleton
    Key.png" in assets/UI/bank/, its solid black background cut out); the slot's rarity outline
    tells the tiers apart. A tier gets its own icon by changing its line.
]]

local DUNGEON_KEY = "rbxassetid://122666539406842"

return {
    T1_DUNGEON_KEY = DUNGEON_KEY,
    T2_DUNGEON_KEY = DUNGEON_KEY,
    T3_DUNGEON_KEY = DUNGEON_KEY,
    T4_DUNGEON_KEY = DUNGEON_KEY,
    T5_DUNGEON_KEY = DUNGEON_KEY,
}
