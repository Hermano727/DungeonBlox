--[[
	MenuShortcuts

	Inventory, Journal and Hearthstone as buttons in the quick-nav row under the minimap
	(RS/HudQuickNav), so touch players (no Tab key) can open the menu, and anyone can jump
	straight to a tab. Tapping the tab that's already open closes the menu
	(ProfileMenusState.RequestOpen).

	The Hearthstone button only appears once it's unlocked (profile.flags.hearthstoneUnlocked;
	the tutorial's totem), like its tab. Each button carries a TutorialTarget attribute
	("shortcut_<id>") so the tutorial can point at it.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuickNav = require(ReplicatedStorage:WaitForChild("HudQuickNav"))
local ProfileMenusState = require(ReplicatedStorage:WaitForChild("ProfileMenusState"))
local JournalUI = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images"):WaitForChild("JournalUI"))
local DungeonMenuNet = require(script.Parent:WaitForChild("DungeonMenuNet"))

local _ = Players.LocalPlayer

local SHORTCUTS = {
	{ id = "inventory", order = QuickNav.ORDER.Inventory, label = "Inventory", glyph = "nav_glyph_inventory", key = "SkillsTab" }, -- an action id: the tooltip shows its current key
	{ id = "journal", order = QuickNav.ORDER.Journal, label = "Journal", glyph = "nav_glyph_journal" },
	{ id = "hearthstone", order = QuickNav.ORDER.Hearthstone, label = "Hearthstone", glyph = "nav_glyph_hearthstone", unlockFlag = "hearthstoneUnlocked" },
}

local buttons = {}

for _, spec in ipairs(SHORTCUTS) do
	local art = JournalUI[spec.glyph]
	-- The shared quick-nav button; the key ("Tab") becomes the standard keycap badge on its corner.
	local button = QuickNav.Button({
		name = spec.label,
		slot = "Menu_" .. spec.id,
		order = spec.order,
		tooltip = spec.label,
		key = spec.key,
		image = art and art.Image or "",
		onActivated = function()
			ProfileMenusState.RequestOpen(spec.id)
		end,
	})
	button:SetAttribute("TutorialTarget", "shortcut_" .. spec.id)
	buttons[spec] = button.Parent
end

-- Locked destinations stay hidden until the profile unlocks them.
local function refresh(snapshot)
	local flags = snapshot and snapshot.profile and snapshot.profile.flags
	for spec, slot in pairs(buttons) do
		slot.Visible = not spec.unlockFlag or (type(flags) == "table" and flags[spec.unlockFlag] == true)
	end
end
DungeonMenuNet.addSnapshotListener(refresh)
refresh(DungeonMenuNet.getLastSnapshot())
