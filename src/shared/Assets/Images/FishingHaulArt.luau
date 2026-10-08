--[[
	FishingHaulArt -- ReplicatedStorage/Assets/Images

	Art for the spear-fishing haul bar (src/client/Professions/HaulBar). Painted pieces from
	assets/ui/incoming/fishing pass/ (2026-10-03), processed by tools/ui_assets/process.py into
	assets/ui/journal/haul_*.png and uploaded through the Studio MCP.

		Image        rbxassetid
		Aspect       width / height of the processed PNG
		SliceCenter  9-slice rect in the PNG's own pixels (corners never stretch), nil = plain

	The water itself is a code gradient, not art. haul_rays was cleaned by script before
	processing (the generated one had speckled noise round the shafts).
]]

return {
	-- Driftwood frame with brass corner caps round the whole bar (walls ~60 px of 264).
	Frame = { Image = "rbxassetid://72373190252981", Aspect = 264 / 1024, SliceCenter = Rect.new(72, 76, 192, 948) },
	-- Rope-net catch zone, square: the knotted rope border round a 3x4 net, drawn whole (Stretch).
	-- Built from haul_zone.png by tools/ui_assets/haul_pieces.py (the 9-sliced original stretched
	-- one net cell across the whole zone).
	Zone = { Image = "rbxassetid://109712695209682", Aspect = 1 },
	-- Rope-edged dark trough for the line's progress.
	Progress = { Image = "rbxassetid://135516417039469", Aspect = 138 / 1024, SliceCenter = Rect.new(30, 52, 108, 972) },
	-- The reel that sits on top of the progress trough, without its crank (haul_reel_body.png).
	Reel = { Image = "rbxassetid://70557605484670", Aspect = 1024 / 709 },
	-- The crank (lever, arm, handle) on a square canvas centred on its nut, so Rotation turns it
	-- about the nut. Pivot = the nut in Reel's own 0..1 space; Size = the canvas in Reel's scale.
	-- Both pieces come from haul_reel.png (whole reel: 128464646612559) via haul_pieces.py.
	ReelCrank = {
		Image = "rbxassetid://129086053239984", Aspect = 1,
		Pivot = Vector2.new(727 / 1024, 376 / 709), Size = Vector2.new(960 / 1024, 960 / 709),
	},
	-- Seabed strip along the bottom of the water.
	Sand = { Image = "rbxassetid://114158608316790", Aspect = 1024 / 125 },
	-- Tall kelp strand and a bushier clump, rooted at their bottom centre.
	KelpTall = { Image = "rbxassetid://86702482584972", Aspect = 309 / 1024 },
	KelpBush = { Image = "rbxassetid://136629449554278", Aspect = 630 / 1024 },
	-- One air bubble (transparent inside).
	Bubble = { Image = "rbxassetid://105056544764250", Aspect = 742 / 740 },
	-- Soft light shafts from the surface.
	Rays = { Image = "rbxassetid://71508897367022", Aspect = 1024 / 706 },
}
