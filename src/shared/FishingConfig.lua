--[[
	FishingConfig
	Single source of truth for the spear-fishing catch table, matching the Config/Service split
	already used by MiningExcavationConfig, EnergyConfig and HungerConfig. Previously this
	weighted table (and its roll function) lived as a local in SpearFishHandler.server.lua;
	moving it here makes it a config-driven data table like the rest of the profession systems
	instead of the one outlier still hardcoded inside its service script, and gives it an
	obvious spot to grow into (new fish tiers, seasonal tables, per-zone tables, etc.) without
	touching handler logic.

	NOT changed: ids/weights/tiers are copied verbatim from the previous inline table -- this is
	a structural move, not a drop-rate change.

	All entries must reference Food/SubKind="Fish" ItemDefinitions.
]]

local FishingConfig = {}

FishingConfig.FishDropTable = {
	{ id = "Fish",       weight = 60, tier = 1 },
	{ id = "SwiftFish",  weight = 18, tier = 2 },
	{ id = "LuckyFish",  weight = 18, tier = 2 },
	{ id = "GoldenFish", weight = 4,  tier = 4 },
}

-- Weighted random pick from FishDropTable. Kept alongside the data (same convention as
-- MiningExcavationConfig.rollTileOreAmount) rather than duplicated at each call site.
function FishingConfig.RollFishEntry()
	local total = 0
	for _, e in ipairs(FishingConfig.FishDropTable) do
		total = total + e.weight
	end
	local r = math.random() * total
	local cum = 0
	for _, e in ipairs(FishingConfig.FishDropTable) do
		cum = cum + e.weight
		if r <= cum then
			return e
		end
	end
	return FishingConfig.FishDropTable[1]
end

return FishingConfig
