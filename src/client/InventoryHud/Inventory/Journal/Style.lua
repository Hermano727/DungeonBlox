--!strict
--  Journal/Style -- colours, fonts and art lookup shared by every Journal component.
--
--  Two palettes: while the parchment art isn't uploaded yet the pages are dark grey-box
--  panels, so text is light; once RS/Assets/Images/JournalUI.page_paper has an Image, the
--  pages are parchment and text switches to dark ink. Components read Style.Text.* and never
--  pick colours themselves, so the swap happens in one place.
--
--  Style.Art(key) -> the registry entry when that piece has been uploaded, else nil (the
--  component draws its flat stand-in).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
local JournalUI = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images"):WaitForChild("JournalUI"))

local Style = {}

function Style.Art(key: string): any?
	local entry = (JournalUI :: any)[key]
	if type(entry) == "table" and type(entry.Image) == "string" and entry.Image ~= "" then
		return entry
	end
	return nil
end

local onPaper = Style.Art("page_paper") ~= nil
Style.OnPaper = onPaper

-- Flat stand-ins (used until each piece's art exists).
Style.Flat = {
	Cover     = Color3.fromRGB(28, 20, 14),   -- the leather around the pages
	CoverEdge = UITheme.Gold,
	Page      = Color3.fromRGB(34, 26, 18),
	Spine     = Color3.fromRGB(16, 11, 7),
	Sidebar   = Color3.fromRGB(22, 16, 11),
	Plate     = Color3.fromRGB(44, 33, 22),   -- tabs, chips, buttons
	PlateOn   = Color3.fromRGB(40, 70, 44),   -- selected tab / chip (T1 green)
	Trough    = Color3.fromRGB(20, 15, 10),
	Edge      = UITheme.Gold,
}

Style.Text = onPaper and {
	Heading = Color3.fromRGB(38, 28, 18),
	Body    = Color3.fromRGB(58, 44, 30),
	Muted   = Color3.fromRGB(110, 92, 70),
	Value   = Color3.fromRGB(28, 20, 12),
	Good    = Color3.fromRGB(46, 104, 52),
	Bad     = Color3.fromRGB(140, 52, 36),
} or {
	Heading = Color3.fromRGB(238, 230, 206),
	Body    = Color3.fromRGB(214, 202, 180),
	Muted   = Color3.fromRGB(158, 143, 122),
	Value   = Color3.fromRGB(245, 238, 219),
	Good    = Color3.fromRGB(120, 200, 120),
	Bad     = Color3.fromRGB(226, 120, 100),
}

-- Chrome text (sidebar, tabs, buttons) always sits on dark leather/wood, so it stays light.
Style.Chrome = {
	Label    = Color3.fromRGB(214, 200, 172),
	Selected = Color3.fromRGB(246, 230, 190),
	Dim      = Color3.fromRGB(120, 108, 92),
}

-- The overworld / dungeon split: neutral hues on purpose (rarity colours are global and must
-- never mean anything else).
Style.Split = {
	Overworld = Color3.fromRGB(96, 116, 72),  -- moss
	Dungeon   = Color3.fromRGB(92, 98, 110),  -- iron
}

-- The book is set in a serif (UIFonts.Serif*, Merriweather) like the blueprint; small
-- running text stays in the game's body font for readability.
Style.Font = {
	Heading  = UIFonts.SerifBold,
	Number   = UIFonts.SerifBold,
	Body     = UIFonts.Body,
	BodyBold = UIFonts.SerifBold,
	Chrome   = UIFonts.SerifBold,
}

-- The spread's shape (the blueprint's book is about twice as wide as tall).
Style.BOOK_ASPECT = 2.0
Style.BOOK_MAX = Vector2.new(1500, 750)
Style.SIDEBAR_W = 190
Style.PAGE_PAD = 34 -- inside each page, before content
-- Each page's content is laid out on this fixed design canvas (px) and scaled to fit the page
-- (Journal/Book), so it never overflows on a small window and grows on a large one.
Style.PAGE_DESIGN = Vector2.new(540, 480)
Style.TAB_H = 34    -- bookmark tabs standing on the book's top edge

return Style
