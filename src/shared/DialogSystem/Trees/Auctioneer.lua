--!strict
-- Auctioneer dialog tree. Module Name = NpcType (see DialogTreeLoader).
-- Portrait: the Blacksmith's for now (placeholder until each NPC has its own).

local PORTRAIT = "rbxassetid://81085082188087"

return {
	start = "greeting",
	nodes = {
		greeting = {
			text = "Welcome, traveler. What goods are you looking for today?",
			image = PORTRAIT,
			responses = {
				{ text = "Open the auction house.", action = { type = "OpenMenu", client = "AuctionHouseClient" }, exit = true },
				{ text = "How does selling work?", next = "selling" },
				{ text = "Just looking around.", exit = true },
			},
		},
		selling = {
			text = "Name your price and how long you want the listing up. The item stays with me until someone pays or you cancel the listing.",
			image = PORTRAIT,
			responses = {
				{ text = "Open the auction house.", action = { type = "OpenMenu", client = "AuctionHouseClient" }, exit = true },
				{ text = "Understood.", exit = true },
			},
		},
	},
}
