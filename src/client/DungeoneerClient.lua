--[[
	DungeoneerClient
	The Dungeoneer: dungeon keys (paid in key fragments) and protection scrolls. The window is
	NpcShop (a Journal-style book with the sections in its sidebar), the spreads are
	NpcShop/DungeoneerBook. Opened from the Dungeoneer's dialog (DialogSystem/Trees/Dungeoneer)
	or the router with .open(npcId).
]]

local NpcShop = require(script.Parent:WaitForChild("NpcShop"))
local DungeoneerBook = require(script.Parent.NpcShop:WaitForChild("DungeoneerBook"))

return NpcShop.window("Dungeoneer", DungeoneerBook, { sidebar = true })
