--[[
	DungeonPortalConfig
	Static data: dungeon tier -> display name + the DungeonKey itemId (ItemDefinitions,
	already catalogued as T1DungeonKey/T2DungeonKey/.../T5DungeonKey) required to enter.
	No side-effects on require(). DungeonInstanceService reads this to know what a portal
	part tagged "DungeonPortal" with a DungeonTier attribute actually leads to.

	Only T1 has a real (placeholder) portal wired up for this pass -- see
	DungeonInstanceService's ensurePlaceholderPortal(). T2/T3 rows exist so the same portal
	code path (and the same DungeonKey items already in ItemDefinitions.lua) work the moment
	a real portal part for that tier gets tagged in Studio; nothing else needs to change.
]]

local DungeonPortalConfig = {}

DungeonPortalConfig.Tiers = {
	T1 = {
		DungeonName = "Goblin Caverns",
		KeyItemId   = "T1DungeonKey",
	},
	T2 = {
		DungeonName = "Sunken Crypt",
		KeyItemId   = "T2DungeonKey",
	},
	T3 = {
		DungeonName = "Obsidian Depths",
		KeyItemId   = "T3DungeonKey",
	},
}

function DungeonPortalConfig.Get(tier)
	return DungeonPortalConfig.Tiers[tier]
end

return DungeonPortalConfig
