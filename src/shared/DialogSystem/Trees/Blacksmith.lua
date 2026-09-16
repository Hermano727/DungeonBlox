--!strict
-- Blacksmith dialog tree. Module Name ("Blacksmith") = NpcType, so any
-- Blacksmith model in the world shares this tree (see DialogTreeLoader).
-- Pilot content for the new tree-based dialog system: a greeting, the
-- repair menu routed through as a response instead of opening instantly,
-- and a small fetch quest exercising QuestRegistry/AcceptQuest/TurnInQuest.

return {
	start = "greeting",
	nodes = {

		greeting = {
			-- Same flavor line NPCClient's old GREETINGS table already used for
			-- Blacksmith, kept for continuity.
			text = "I can restore what the dungeon breaks. Bring your gear.",
			image = "rbxassetid://115394827256387",
			responses = {
				{
					text = "Open the forge (repair gear)",
					action = { type = "OpenMenu", client = "BlacksmithClient" },
					exit = true,
				},
				{
					text = "Any work for me?",
					next = "questOffer",
					condition = { type = "QuestState", quest = "BlacksmithScrapRun", is = "available" },
				},
				{
					text = "I brought the scrap you asked for.",
					next = "questTurnIn",
					condition = { type = "QuestState", quest = "BlacksmithScrapRun", is = "active" },
				},
				{
					text = "Just here for repairs. Thanks again.",
					next = "alreadyDone",
					condition = { type = "QuestState", quest = "BlacksmithScrapRun", is = "completed" },
				},
				{ text = "Just passing through.", exit = true },
			},
		},

		questOffer = {
			text = "My anvil's cold and I'm short on scrap to work it. Bring me 5 T1 Scrap and I'll make it worth your while -- coin on delivery.",
			image = "rbxassetid://115394827256387",
			responses = {
				{
					text = "I'll bring it.",
					action = { type = "AcceptQuest", quest = "BlacksmithScrapRun" },
					next = "questAccepted",
				},
				{ text = "Not right now.", exit = true },
			},
		},

		questAccepted = {
			text = "Good. Five T1 Scrap, whenever you've got it.",
			image = "rbxassetid://115394827256387",
			responses = {
				{ text = "On my way.", exit = true },
			},
		},

		questTurnIn = {
			text = "Let's see it, then.",
			image = "rbxassetid://115394827256387",
			responses = {
				{
					text = "Here's the scrap.",
					action = { type = "TurnInQuest", quest = "BlacksmithScrapRun" },
					next = "questComplete",
				},
				{ text = "Actually, not yet.", exit = true },
			},
		},

		questComplete = {
			text = "That'll do nicely. Here's your coin -- and my thanks.",
			image = "rbxassetid://115394827256387",
			responses = {
				{ text = "Glad to help.", exit = true },
			},
		},

		alreadyDone = {
			text = "The scrap run set me up well. My repairs are yours whenever you need them.",
			image = "rbxassetid://115394827256387",
			responses = {
				{ text = "Good to know.", exit = true },
			},
		},
	},
}
