--!strict
-- Dungeoneer dialog tree. Module Name = NpcType (see DialogTreeLoader).
-- Portrait: the Blacksmith's for now (placeholder until each NPC has its own).

local PORTRAIT = "rbxassetid://115394827256387"

return {
	start = "greeting",
	nodes = {
		greeting = {
			text = "You want dungeon work? Bring me fragments and I'll make you a key. What's behind the door is your problem.",
			image = PORTRAIT,
			responses = {
				{ text = "Let's trade.", action = { type = "OpenMenu", client = "DungeoneerClient" }, exit = true },
				{ text = "How do keys work?", next = "keys" },
				{ text = "Not yet.", exit = true },
			},
		},
		keys = {
			text = "Bring me enough fragments of one tier and I forge a key for that tier's dungeon. Higher tiers bite harder.",
			image = PORTRAIT,
			responses = {
				{ text = "Let's trade.", action = { type = "OpenMenu", client = "DungeoneerClient" }, exit = true },
				{ text = "I'll be back.", exit = true },
			},
		},
	},
}
