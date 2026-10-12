--!strict
--  JournalPanel -- the "Journal" destination: the Sidebar (Journal/Sidebar, the top-level pages)
--  on the open book's left, the book (Journal/Book) the current page draws itself in.
--    Stats         (default) combat stats by category, ribbons on the book's edge -- StatsPage.lua
--    Skills        levels, XP, milestones -- SkillsPage.lua
--    Loot Score    per-tier score, dry streaks, and the Activity view -- LootScorePage.lua
--    Records       lifetime totals, as a ledger -- RecordsPage.lua
--    Leaderboards  cross-server boards: skills, kills, score -- LeaderboardsPage.lua
--    Alignment     Lawful / Neutral / Chaotic, changed in safe zones -- AlignmentPage.lua
--  New page: a component that renders a Journal/Book (carrying `side`), plus one entry in PAGES.
--
--  Size (2026-10-01): the page area runs from the sidebar to RIGHT_ROOM short of the right edge
--  (the Stats ribbons), so the book is as big as the space allows (Style.BOOK_MAX).
--  The Tab menu gives the Journal its full content height (Inventory/init.lua FULL_HEIGHT).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local DungeonMenuNet = require(script.Parent.Parent.Parent:WaitForChild("DungeonMenuNet"))
local LootScorePage = require(script.Parent:WaitForChild("LootScorePage"))
local SkillsPage = require(script.Parent:WaitForChild("SkillsPage"))
local StatsPage = require(script.Parent:WaitForChild("StatsPage"))
local RecordsPage = require(script.Parent:WaitForChild("RecordsPage"))
local LeaderboardsPage = require(script.Parent:WaitForChild("LeaderboardsPage"))
local AlignmentPage = require(script.Parent:WaitForChild("AlignmentPage"))
local JournalParts = script.Parent:WaitForChild("Journal")
local Sidebar = require(JournalParts:WaitForChild("Sidebar"))
local Style = require(JournalParts:WaitForChild("Style"))

local e = React.createElement

-- The first entry is the page the Journal opens on. Every page draws a Journal/Book and carries
-- the sidebar on its left edge (Book.side).
local PAGES = {
	{ id = "stats",        label = "Stats",        iconArt = "icon_stats",        component = StatsPage },
	{ id = "skills",       label = "Skills",       iconArt = "nav_glyph_skills",  component = SkillsPage },
	{ id = "lootScore",    label = "Loot Score",   iconArt = "icon_loot_score",   component = LootScorePage },
	{ id = "records",      label = "Records",      iconArt = "icon_records",      component = RecordsPage },
	{ id = "leaderboards", label = "Leaderboards", iconArt = "icon_leaderboards", component = LeaderboardsPage },
	{ id = "alignment",    label = "Alignment",    iconArt = "icon_cat_defense",  component = AlignmentPage },
}
local GAP = 22
-- Free right of the book on EVERY page (the Stats ribbons hang there), so the book keeps one
-- size as you turn between pages.
local RIGHT_ROOM = 64

local function JournalPanel()
	local pageId, setPageId = React.useState(PAGES[1].id)

	-- Kills etc. don't push a snapshot (see RecordsPage), so pull once on open -- otherwise the
	-- totals would be however stale the last unrelated push left them.
	React.useEffect(function()
		DungeonMenuNet.requestSync()
	end, {})

	local page = PAGES[1]
	for _, entry in ipairs(PAGES) do
		if entry.id == pageId then page = entry end
	end

	local sidebar = e(Sidebar, { pages = PAGES, selected = pageId, onSelect = setPageId })
	local left = Style.SIDEBAR_W + GAP
	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		Page = e("Frame", {
			Position = UDim2.fromOffset(left, 0),
			Size = UDim2.new(1, -(left + RIGHT_ROOM), 1, 0),
			BackgroundTransparency = 1,
		}, {
			Body = e(page.component, { key = page.id, side = sidebar }),
		}),
	})
end

return JournalPanel
