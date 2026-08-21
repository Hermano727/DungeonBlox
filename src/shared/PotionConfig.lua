--[[
	PotionConfig
	Single source of truth for potion tiers, matching the Config/Service split already used by
	MiningExcavationConfig, EnergyConfig and HungerConfig (tuned numbers + display metadata live
	in shared/, the runtime logic that reads them lives in the server script). Previously these
	values lived as a local table inline in PotionService.server.luau, and PotionClient had its
	own hand-copied list of the same itemIds + display labels for its charge HUD -- meaning a new
	potion tier had to be added in two disconnected places to actually show up client-side.
	PotionClient now reads Order/displayName from here instead of keeping its own copy.

	NOT changed: healPerSecond/duration/maxCharges/regenInterval values are copied verbatim from
	the previous inline table -- this is a structural move, not a balance change.
]]

return {
	-- Canonical display order for HUD rows; also acts as the canonical list of known potion
	-- itemIds (PotionService seeds a charge entry for each one on join).
	Order = { "MinorPotion", "MediumPotion" },

	-- itemId -> { healPerSecond, duration (seconds healed), maxCharges, regenInterval (seconds
	-- per charge), displayName (short label for the charge HUD) }
	Tiers = {
		MinorPotion = {
			healPerSecond = 30,
			duration = 5,
			maxCharges = 3,
			regenInterval = 40,
			displayName = "Minor",
		},
		MediumPotion = {
			healPerSecond = 60,
			duration = 5,
			maxCharges = 3,
			regenInterval = 40,
			displayName = "Medium",
		},
	},
}
