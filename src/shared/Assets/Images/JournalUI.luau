--[[
	JournalUI -- ReplicatedStorage/Assets/Images

	Art for the Journal (and the look the rest of the UI overhaul reuses). Every piece is a
	separate transparent PNG, processed by tools/ui_assets/process.py from
	assets/ui/incoming/<key>.png and uploaded through the Studio MCP (see
	docs/ui-and-networking.md, "UI art pipeline").

		Image        "rbxassetid://..."; "" = not made yet: the component draws its flat
		             grey-box stand-in, so art drops in one piece at a time without layout changes
		SliceCenter  Rect in the image's own pixels for 9-slice pieces (corners never stretch),
		             nil for plain images
		SliceScale   how big the 9-slice corners draw relative to the image's pixels (0.3 =
		             a 230 px cap draws at ~70 px); the component can still override it
		Aspect       width / height of the processed PNG
		TileSize     for tiling textures (paper): the on-screen size of one tile, in px

	Keys are the incoming file names (lower snake case, matching the prompts).
]]

local function piece(fields)
	return {
		Image = fields.Image or "",
		SliceCenter = fields.SliceCenter,
		SliceScale = fields.SliceScale,
		Aspect = fields.Aspect or 1,
		TileSize = fields.TileSize,
	}
end

return {
	-- Batch 1: structure
	-- the leather around the pages, bronze corner caps (9-slice); caps reach ~220 px
	book_cover = piece({
		Image = "rbxassetid://74983544391835",
		SliceCenter = Rect.new(230, 230, 794, 753),
		SliceScale = 0.3,
		Aspect = 1024 / 983,
	}),
	-- optional art for the centre strip; without it the Book draws a soft gutter shadow
	book_spine = piece({}),
	-- one page of parchment, worn edges + ink corner flourishes. Plain stretch, no 9-slice:
	-- the book is locked at 2:1, so a page is always close to this image's square shape, and
	-- 9-slicing showed a seam where the stretched centre met the (uneven) darkened edges.
	page_paper = piece({
		Image = "rbxassetid://84929950628081",
		Aspect = 1024 / 1022,
	}),
	-- tall leather/wood panel beside the book, vine down its left side (9-slice); caps ~100 px.
	-- SliceScale ~ sidebar width / 389 so the vine keeps its width; only the middle stretches.
	sidebar_panel = piece({
		Image = "rbxassetid://112313288107144",
		SliceCenter = Rect.new(100, 105, 289, 919),
		SliceScale = 0.49,
		Aspect = 389 / 1024,
	}),
	sidebar_vines = piece({}), -- unused: the vine is painted into sidebar_panel

	-- Batch 2: controls
	sidebar_row          = piece({}), -- page row, normal (9-slice)
	sidebar_row_selected = piece({}), -- page row, selected, bronze outline + glow (9-slice)
	bookmark_tab         = piece({}), -- tier tab, inactive (9-slice)
	bookmark_tab_active  = piece({}), -- tier tab, active green (9-slice)
	lock_icon            = piece({}),
	chip                 = piece({}), -- window filter chip, normal (9-slice)
	chip_selected        = piece({}), -- window filter chip, selected (9-slice)
	split_bar_frame      = piece({}), -- ornate-ended frame around the overworld / dungeon bar (9-slice)
	bar_trough           = piece({}), -- thin recessed bar track (9-slice)
	divider              = piece({}), -- ink rule with a small diamond

	-- Batch 3: gems and icons
	gem_common     = piece({}), -- small dull rough grey stone
	gem_uncommon   = piece({}),
	gem_rare       = piece({}),
	gem_epic       = piece({}),
	gem_legendary  = piece({}),
	gem_glow       = piece({}), -- soft white halo, tinted per rarity behind Epic / Legendary
	icon_loot_score = piece({}), -- coin pouch
	icon_records    = piece({}), -- scroll
}
