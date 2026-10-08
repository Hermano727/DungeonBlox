--!strict
-- Merchant dialog tree. Module Name = NpcType (see DialogTreeLoader).
-- Portrait: the Blacksmith's for now (placeholder until each NPC has its own).
-- NPCRegistry.Merchant.SkipDialog sends the prompt straight to the shop; this tree is
-- used if that switch is turned off.
local PORTRAIT = "rbxassetid://115394827256387"

return {
	start = "greeting",
	nodes = {
		greeting = {
			text = "The markets thin out here, but my wares are sound. What do you need?",
			image = PORTRAIT,
			responses = {
				{ text = "Show me your wares.", action = { type = "OpenMenu", client = "MerchantClient" }, exit = true },
				{ text = "Where does all this come from?", next = "lore" },
				{ text = "Nothing today.", exit = true },
			},
		},
		lore = {
			text = "Ore from the hills, scrap from the dead, brews from whoever still knows how. Everything ends up on my table sooner or later.",
			image = PORTRAIT,
			responses = {
				{ text = "Let me see it, then.", action = { type = "OpenMenu", client = "MerchantClient" }, exit = true },
				{ text = "Another time.", exit = true },
			},
		},
	},
}
