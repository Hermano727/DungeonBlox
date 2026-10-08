--!strict
-- Innkeeper dialog tree. Module Name = NpcType (see DialogTreeLoader).
-- Portrait: the Blacksmith's for now (placeholder until each NPC has its own).

local PORTRAIT = "rbxassetid://115394827256387"

return {
	start = "greeting",
	nodes = {
		greeting = {
			text = "Rest easy, traveler. I keep the waystones between here and beyond. For a price, one of them can call you home.",
			image = PORTRAIT,
			responses = {
				{ text = "Show me the waystones.", action = { type = "OpenMenu", client = "HearthstoneClient", method = "openInnkeeperShop" }, exit = true },
				{ text = "How does the hearthstone work?", next = "hearthstone" },
				{ text = "Just resting.", exit = true },
			},
		},
		hearthstone = {
			text = "Bind it to a place you own and it takes you back there. It needs quiet to work, so not mid-fight, and it rests a while after.",
			image = PORTRAIT,
			responses = {
				{ text = "Show me the waystones.", action = { type = "OpenMenu", client = "HearthstoneClient", method = "openInnkeeperShop" }, exit = true },
				{ text = "Thanks.", exit = true },
			},
		},
	},
}
