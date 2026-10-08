--[[
	BlacksmithClient
	The Blacksmith's repairs. The window is NpcShop (a Journal-style book), the spread is
	NpcShop/BlacksmithBook. Opened from the Blacksmith's dialog (DialogSystem/Trees/Blacksmith,
	an OpenMenu action naming this module) with .open(npcId).
]]

local NpcShop = require(script.Parent:WaitForChild("NpcShop"))
local BlacksmithBook = require(script.Parent.NpcShop:WaitForChild("BlacksmithBook"))

return NpcShop.window("Blacksmith", BlacksmithBook)
