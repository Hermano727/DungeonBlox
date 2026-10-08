--!strict
--  NpcShop/DungeoneerBook -- the Dungeoneer (2026-10-01; was the old ShopClientBase window).
--  Sections in the Journal sidebar, each a Catalog spread over
--  NPCRegistry.Get("Dungeoneer").ShopCatalog by ShopTab:
--    Keys      dungeon keys, paid in that tier's key fragments
--    Scrolls   protection scrolls

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local NPCRegistry = require(ReplicatedStorage:WaitForChild("NPCRegistry"))
local Catalog = require(script.Parent:WaitForChild("Catalog"))
local Inventory = script.Parent.Parent:WaitForChild("InventoryHud"):WaitForChild("Inventory")
local InventoryData = require(Inventory:WaitForChild("InventoryData"))
local Sidebar = require(Inventory:WaitForChild("Journal"):WaitForChild("Sidebar"))

local e = React.createElement

local function iconOf(itemId: string): string?
	local icon = ItemDefinitions.GetIconForItem({ itemId = itemId })
	return (type(icon) == "string" and icon ~= "") and icon or nil
end

local SECTIONS = {
	{ id = "Keys", label = "Keys", item = "T1DungeonKey", heading = "Dungeon Keys", sub = "Forged from key fragments." },
	{ id = "Scrolls", label = "Scrolls", item = "T1WeaponProtectionScroll", heading = "Protection Scrolls", sub = "Keep an enchant from breaking your gear." },
}
local PAGES = {}
for _, section in ipairs(SECTIONS) do
	table.insert(PAGES, { id = section.id, label = section.label, icon = iconOf(section.item) })
end

local function DungeoneerBook(props: { npcId: string })
	local snapshot = InventoryData.useSnapshot()
	local sectionId, setSection = React.useState("Keys")
	local section = SECTIONS[1]
	for _, s in ipairs(SECTIONS) do
		if s.id == sectionId then section = s end
	end
	local entries = {}
	local reg = NPCRegistry.Get("Dungeoneer")
	for _, entry in ipairs(reg and reg.ShopCatalog or {}) do
		if (entry.ShopTab or "Keys") == sectionId then table.insert(entries, entry) end
	end
	return e(Catalog, {
		key = sectionId,
		npcId = props.npcId,
		snapshot = snapshot,
		entries = entries,
		heading = section.heading,
		sub = section.sub,
		side = e(Sidebar, { pages = PAGES, selected = sectionId, onSelect = setSection }),
	})
end

return DungeoneerBook
