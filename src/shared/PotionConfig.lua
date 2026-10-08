-- Shared charges, total healing per potion, and the ten-second healing schedule.
-- Drinking duration and animation timings live in PotionDrinkConfig.

return {
	-- A completed drink starts ten independent one-second healing ticks.
	HealTicks = 10,
	HealTickInterval = 1,
	-- Canonical display order for HUD rows; also acts as the canonical list of known potion
	-- itemIds (PotionService seeds a charge entry for each one on join).
	Order = { "MinorPotion", "MediumPotion" },

	-- The one shared charge pool every potion tier draws from. Values copied verbatim from
	-- the old per-tier maxCharges/regenInterval (both tiers already used the same numbers), so
	-- this is a structural change (one pool instead of two), not a balance change.
	SharedCharges = {
		maxCharges = 3,
		regenInterval = 40, -- seconds per charge regenerated
	},

	-- itemId -> total healAmount, colour/model and short displayName.
	-- maxCharges/regenInterval used to live here per-tier -- moved to SharedCharges above.
	Tiers = {
		MinorPotion = {
			drinkColor = Color3.fromRGB(150, 18, 24),
			visualModel = "T1_MinorPotion",
			healAmount = 150, -- preserves the previous 30/s for 5s total
			displayName = "Minor",
		},
		MediumPotion = {
			drinkColor = Color3.fromRGB(150, 18, 24), -- independently tunable when its art is ready
			visualModel = "T1_MinorPotion",
			healAmount = 300, -- preserves the previous 60/s for 5s total
			displayName = "Medium",
		},
	},
}
