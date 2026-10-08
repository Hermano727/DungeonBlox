--!strict
-- AnimalTrainer dialog tree. Module Name = NpcType (see DialogTreeLoader).
-- Portrait: the Blacksmith's for now (placeholder until each NPC has its own).
-- NPCRegistry.AnimalTrainer.SkipDialog sends the prompt straight to the stable; this tree
-- is used if that switch is turned off.
local PORTRAIT = "rbxassetid://115394827256387"

return {
	start = "greeting",
	nodes = {
		greeting = {
			text = "A good horse outruns most of what hunts these roads. Most of it.",
			image = PORTRAIT,
			responses = {
				{ text = "Show me your saddles.", action = { type = "OpenMenu", client = "AnimalTrainerClient" }, exit = true },
				{ text = "How do I ride?", next = "howTo" },
				{ text = "Not today.", exit = true },
			},
		},
		howTo = {
			text = "Put the saddle on your hotbar and use it, and your horse comes to you. Better saddles, faster horses.",
			image = PORTRAIT,
			responses = {
				{ text = "Show me your saddles.", action = { type = "OpenMenu", client = "AnimalTrainerClient" }, exit = true },
				{ text = "Good to know.", exit = true },
			},
		},
	},
}
