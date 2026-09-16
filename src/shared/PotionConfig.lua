--[[
	PotionConfig
	Single source of truth for potion tiers, matching the Config/Service split already used by
	MiningExcavationConfig, EnergyConfig and HungerConfig (tuned numbers + display metadata live
	in shared/, the runtime logic that reads them lives in the server script). Previously these
	values lived as a local table inline in PotionService.server.luau, and PotionClient had its
	own hand-copied list of the same itemIds + display labels for its charge HUD -- meaning a new
	potion tier had to be added in two disconnected places to actually show up client-side.
	PotionClient now reads Order/displayName from here instead of keeping its own copy.

	2026-09-10 rework (direct request: "the pot system right now allows for using 3 minor
	potions in addition to 3 medium potions, it should be 3 potions IN GENERAL"): maxCharges/
	regenInterval used to live PER TIER, so a player could drink 3 Minor AND 3 Medium potions
	back to back -- 6 total heals, not 3. Charges are now tracked as ONE shared pool across
	every tier (see SharedCharges below) -- drinking any potion, of any tier, consumes from the
	same count. healPerSecond/duration are unchanged and still per-tier, since different tiers
	still heal for different amounts.
]]

return {
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

	-- itemId -> { healPerSecond, duration (seconds healed), displayName (short label) }.
	-- maxCharges/regenInterval used to live here per-tier -- moved to SharedCharges above.
	Tiers = {
		MinorPotion = {
			healPerSecond = 30,
			duration = 5,
			displayName = "Minor",
		},
		MediumPotion = {
			healPerSecond = 60,
			duration = 5,
			displayName = "Medium",
		},
	},
}
