--[[
	DevMenu/TabList -- which tabs the F8 menu has, in order. A new tab is a module in Tabs/ (see the
	tab contract at the top of DevMenu/init) plus one name here; the shell groups and lays it out.
]]

local Tabs = script.Parent:WaitForChild("Tabs")

local ORDER = {
	-- World
	"Mob", "Npc", "Elite", "Zone", "Time",
	-- Items
	"Gear", "Items", "Mythic",
	-- Dungeon
	"Dungeon",
	-- Player
	"Profile", "Map",
	-- Media
	"Capture", "Showcase",
}

local list = {}
for _, name in ipairs(ORDER) do
	table.insert(list, require(Tabs:WaitForChild(name)))
end
return list
