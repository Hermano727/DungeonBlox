--[[
	JournalUI -- ReplicatedStorage/Assets/Images

	Art for the Journal (and the look the rest of the UI overhaul reuses). Every piece is a
	separate transparent PNG, processed by tools/ui_assets/process.py from
	assets/ui/incoming/<key>.png and uploaded through the Studio MCP (see
	docs/ui-and-networking.md, "UI art pipeline").

		Image        "rbxassetid://..."; "" = not made yet: the component draws its flat
		             grey-box stand-in, so art drops in one piece at a time without layout changes
		SliceCenter  Rect in the image's own pixels for 9-slice pieces (corners never scale),
		             nil for plain images
		Aspect       width / height of the processed PNG
		TileSize     for tiling textures (paper): the on-screen size of one tile, in px

	Keys are the incoming file names (lower snake case, matching the prompts).
]]

local function piece(fields)
	return {
		Image = fields.Image or "",
		SliceCenter = fields.SliceCenter,
		Aspect = fields.Aspect or 1,
		TileSize = fields.TileSize,
	}
end

return {
	-- Batch 1: structure
	book_cover     = piece({}), -- the open leather spread, bronze corner caps, no pages (9-slice)
	book_spine     = piece({}), -- the centre strip between the pages
	page_paper     = piece({}), -- seamless parchment tile
	sidebar_panel  = piece({}), -- tall leather/wood panel beside the book (9-slice)
	sidebar_vines  = piece({}), -- vine overlay down the sidebar's edge

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
