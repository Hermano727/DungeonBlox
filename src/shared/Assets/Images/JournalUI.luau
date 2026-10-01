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
		Pad          { l, t, r, b } source pixels of glow around the solid plate (selected
		             states): the art is drawn that much bigger than its box, so the plate
		             lines up with the unselected one and the glow spills outside
		Aspect       width / height of the processed PNG
		TileSize     for tiling textures (paper): the on-screen size of one tile, in px

	Keys are the incoming file names (lower snake case, matching the prompts).
]]

local function piece(fields)
	return {
		Image = fields.Image or "",
		SliceCenter = fields.SliceCenter,
		SliceScale = fields.SliceScale,
		Pad = fields.Pad,
		Width = fields.Width, -- processed PNG width in px, for pieces that use Pad without 9-slice
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
	-- tall leather/wood panel beside the book, vine down its left side. NOT 9-sliced: the vine
	-- is leafy its whole length, so any slice line cut through leaves and showed a seam. The
	-- Sidebar keeps this exact shape (UIAspectRatioConstraint) instead of stretching it.
	sidebar_panel = piece({
		Image = "rbxassetid://112313288107144",
		Aspect = 389 / 1024,
	}),
	sidebar_vines = piece({}), -- unused: the vine is painted into sidebar_panel

	-- Batch 2: controls. Caps measured on the processed PNGs; SliceScale ~ on-screen height /
	-- plate height, so rivets and corners stay in proportion.
	sidebar_row = piece({ -- page row, normal; riveted end caps ~55 px
		Image = "rbxassetid://94060803190538",
		SliceCenter = Rect.new(60, 24, 964, 99), SliceScale = 0.4, Aspect = 1024 / 123,
	}),
	sidebar_row_selected = piece({ -- selected: brighter bronze, warm glow, notch on the right
		Image = "rbxassetid://124916721478415",
		SliceCenter = Rect.new(86, 48, 919, 118), SliceScale = 0.4, Aspect = 1024 / 167,
		Pad = { 28, 25, 25, 26 },
	}),
	bookmark_tab = piece({ -- tier tab, inactive; riveted brackets ~75 px, rounded top
		Image = "rbxassetid://139385932189903",
		SliceCenter = Rect.new(80, 70, 705, 90), SliceScale = 0.15, Aspect = 785 / 234,
	}),
	bookmark_tab_active = piece({ -- tier tab, active: forest-green leather, faint glow
		Image = "rbxassetid://106996563884580",
		SliceCenter = Rect.new(109, 104, 736, 124), SliceScale = 0.15, Aspect = 848 / 308,
		Pad = { 29, 34, 32, 35 },
	}),
	lock_icon = piece({ Image = "rbxassetid://113372625458127", Aspect = 206 / 260 }),
	chip = piece({ -- small button (window chips, Activity, Back); riveted corner brackets ~130 px
		Image = "rbxassetid://80618460761291",
		SliceCenter = Rect.new(135, 95, 593, 140), SliceScale = 0.16, Aspect = 728 / 235,
	}),
	chip_selected = piece({ -- selected chip: green leather, brighter bronze, faint glow
		Image = "rbxassetid://125025499697518",
		SliceCenter = Rect.new(162, 132, 625, 177), SliceScale = 0.16, Aspect = 787 / 297,
		Pad = { 27, 37, 27, 33 },
	}),
	split_bar_frame = piece({}), -- optional ornate frame; until then SplitBar uses bar_trough
	bar_trough = piece({ -- thin recessed track with a bronze rim; pointed ends ~30 px
		Image = "rbxassetid://102104005930659",
		SliceCenter = Rect.new(32, 18, 992, 39), SliceScale = 0.28, Aspect = 1024 / 57,
	}),
	divider = piece({ Image = "rbxassetid://115368801234699", Aspect = 1024 / 38 }), -- ink rule with a diamond

	-- Batch 3: gems and icons
	-- Gems escalate (rough grey stone -> radiant orange); Parts.Gem sizes them by rarity too.
	gem_common    = piece({ Image = "rbxassetid://79628861988288",  Aspect = 176 / 207 }),
	gem_uncommon  = piece({ Image = "rbxassetid://124151846447739", Aspect = 208 / 264 }),
	gem_rare      = piece({ Image = "rbxassetid://111495892933135", Aspect = 260 / 307 }),
	gem_epic      = piece({ Image = "rbxassetid://95984238263487",  Aspect = 329 / 372 }),
	gem_legendary = piece({ Image = "rbxassetid://131788090121900", Aspect = 396 / 463 }),
	-- soft white halo tinted per rarity behind Epic / Legendary (generated, not painted:
	-- a radial falloff, see docs/ui-and-networking.md)
	gem_glow        = piece({ Image = "rbxassetid://124669614530343", Aspect = 1 }),
	icon_loot_score = piece({ Image = "rbxassetid://111981563075790", Aspect = 502 / 458 }), -- coin pouch
	-- 2026-10-01: the page-of-notes art (same asset as icon_cat_overview) replaced the sealed
	-- scroll (rbxassetid://111678186607517).
	icon_records    = piece({ Image = "rbxassetid://114756755504191", Aspect = 264 / 340 }),
	icon_leaderboards = piece({ Image = "rbxassetid://137764770279274", Aspect = 1024 / 516 }), -- gold 1-2-3 podium

	-- Per-tier page illustration: bottom of the Activity page's right side (LootScorePage).
	-- Faint ink-and-wash scene on transparent ground so the parchment shows through.
	illustration_t1 = piece({ Image = "rbxassetid://81869725203589", Aspect = 1024 / 525 }), -- cottage beneath an old tree

	-- Batch 4: the Tab menu's top row (QuickNav.lua), same look as the book.
	nav_medallion = piece({ Image = "rbxassetid://130795045169317", Aspect = 1 }), -- carved ring, empty green recess
	nav_medallion_selected = piece({ -- brighter ring + warm glow; the ring matches nav_medallion's size
		Image = "rbxassetid://98456248259699", Aspect = 546 / 548, Pad = { 24, 26, 23, 30 }, Width = 546,
	}),
	nav_plaque = piece({ -- name plaque under each medallion; pointed ends ~60 px
		Image = "rbxassetid://118843587395252",
		SliceCenter = Rect.new(70, 50, 732, 122), SliceScale = 0.15, Aspect = 802 / 172,
	}),
	nav_glyph_inventory   = piece({ Image = "rbxassetid://81539845232861",  Aspect = 313 / 350 }), -- backpack
	nav_glyph_skills      = piece({ Image = "rbxassetid://125671058654812", Aspect = 331 / 356 }), -- bare tree
	nav_glyph_stats       = piece({ Image = "rbxassetid://127211885778508", Aspect = 271 / 292 }), -- bar chart
	nav_glyph_journal     = piece({ Image = "rbxassetid://99968572591327",  Aspect = 345 / 260 }), -- open book
	nav_glyph_hearthstone = piece({ Image = "rbxassetid://78158006215872",  Aspect = 276 / 299 }), -- hearthstone rune
	nav_glyph_party       = piece({ Image = "rbxassetid://133527886675350", Aspect = 332 / 271 }), -- three people

	-- Stats page (2026-09-30). Category ribbons hang off the book's right edge; the vine card
	-- frame holds the portrait and the weapon cards; fx_* are the stat / effect row icons.
	-- Not made yet (components fall back): attribute glyphs, fx_bleeding, fx_blinding.
	ribbon = piece({ Image = "rbxassetid://71185611413897", Aspect = 445 / 722 }), -- notch on the right edge: never 9-sliced
	ribbon_selected = piece({ Image = "rbxassetid://113107004121855", Aspect = 458 / 752, Pad = { 1, 20, 14, 26 }, Width = 458 }),
	card_frame = piece({ -- bronze frame, vines on the corners, EMPTY inside (9-slice); vines reach ~215 px
		Image = "rbxassetid://73383604392715", SliceCenter = Rect.new(215, 275, 809, 455), SliceScale = 0.3, Aspect = 1024 / 750,
	}),
	stats_backdrop = piece({ Image = "rbxassetid://89283189407106", Aspect = 1024 / 768 }), -- painted courtyard behind the portrait
	icon_stats = piece({ Image = "rbxassetid://99426945678481", Aspect = 587 / 626 }),
	icon_cat_overview = piece({ Image = "rbxassetid://114756755504191", Aspect = 264 / 340 }),
	icon_cat_defense = piece({ Image = "rbxassetid://127237297391062", Aspect = 305 / 389 }),
	icon_cat_melee = piece({ Image = "rbxassetid://139067913230305", Aspect = 392 / 375 }),
	icon_cat_ranged = piece({ Image = "rbxassetid://121094809926277", Aspect = 373 / 379 }),
	icon_cat_mount = piece({ Image = "rbxassetid://94637238500839", Aspect = 364 / 390 }),
	fx_critical = piece({ Image = "rbxassetid://105216896046627", Aspect = 297 / 336 }),
	fx_execute = piece({ Image = "rbxassetid://88045605342609", Aspect = 292 / 337 }),
	fx_pierce = piece({ Image = "rbxassetid://78764352736124", Aspect = 369 / 315 }),
	fx_crushing = piece({ Image = "rbxassetid://127322791304818", Aspect = 347 / 320 }),
	fx_shatter = piece({ Image = "rbxassetid://126219560343735", Aspect = 282 / 308 }),
	fx_cleave = piece({ Image = "rbxassetid://103086142568057", Aspect = 349 / 313 }),
	fx_lifesteal = piece({ Image = "rbxassetid://110826516371269", Aspect = 538 / 444 }),
	fx_vsmon = piece({ Image = "rbxassetid://130281120502675", Aspect = 456 / 570 }),
	fx_vsply = piece({ Image = "rbxassetid://72893358912609", Aspect = 581 / 497 }),
	fx_elemental = piece({ Image = "rbxassetid://127037531403488", Aspect = 331 / 502 }),
	fx_slowness = piece({ Image = "rbxassetid://126449399955037", Aspect = 360 / 308 }),
	fx_health = piece({ Image = "rbxassetid://123868161242566", Aspect = 263 / 257 }),
	fx_hpregen = piece({ Image = "rbxassetid://97315209898915", Aspect = 285 / 250 }),
	fx_energy = piece({ Image = "rbxassetid://124810855408482", Aspect = 243 / 336 }),
	fx_armor = piece({ Image = "rbxassetid://105625528851710", Aspect = 372 / 311 }),
	fx_block = piece({ Image = "rbxassetid://93668380299607", Aspect = 299 / 311 }),
	fx_coinfind = piece({ Image = "rbxassetid://108170715481607", Aspect = 597 / 471 }),
	fx_bleeding = piece({}),
	fx_blinding = piece({}),
	attr_str = piece({}), attr_int = piece({}), attr_dex = piece({}), attr_vit = piece({}),

	-- Inventory screen (2026-09-30): the courtyard behind it, one painting per time of day, each
	-- cropped to 16:9 (1448 x 814) and split into a left and right half so it stays sharp under
	-- Roblox's 1024 px cap. A missing time of day falls back to afternoon (InventoryBackdrop).
	inv_bg_afternoon_l = piece({ Image = "rbxassetid://80040945544472", Aspect = 724 / 814 }),
	inv_bg_afternoon_r = piece({ Image = "rbxassetid://91176209285068", Aspect = 724 / 814 }),
	inv_bg_dawn_l = piece({ Image = "rbxassetid://84134259013436", Aspect = 724 / 814 }),
	inv_bg_dawn_r = piece({ Image = "rbxassetid://110288317957035", Aspect = 724 / 814 }),
	inv_bg_dusk_l = piece({ Image = "rbxassetid://129827599883883", Aspect = 724 / 814 }),
	inv_bg_dusk_r = piece({ Image = "rbxassetid://117036561663142", Aspect = 724 / 814 }),
	-- Soft oval under the character's feet (generated, not painted), tinted black in code.
	inv_shadow = piece({ Image = "rbxassetid://91887743415057", Aspect = 4 }),
}
