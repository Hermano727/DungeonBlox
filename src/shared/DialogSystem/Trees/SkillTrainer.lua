--!strict
-- SkillTrainer dialog tree. Module Name = NpcType (see DialogTreeLoader).
-- Portrait: the Blacksmith's for now (placeholder until each NPC has its own).

local PORTRAIT = "rbxassetid://115394827256387"

return {
	start = "greeting",
	nodes = {
		greeting = {
			text = "Looking to get equipped? I keep only tools I'd trust myself.",
			image = PORTRAIT,
			responses = {
				{ text = "Show me your wares.", action = { type = "OpenMenu", client = "SkillTrainerClient" }, exit = true },
				{ text = "Not right now.", exit = true },
			},
		},
	},
}
