--[[
	MapUI -- ReplicatedStorage/Assets/Images

	The map's own art (2026-10-11): the explorer's-map look of thin bronze rules with small
	flowering vines, parchment notes and cartographer's ink icons. Sources in
	assets/UI/incoming/map/ (file name next to each id); trimmed, edge-bled and capped at 1024 px
	before upload, so every pixel measurement below is in the UPLOADED image. Prompts and the
	rejected first attempt: docs/art-direction.md (UI pieces).

	An empty Image means the code draws its old fallback.

		Size       the uploaded image's width, height (px)
		Window     a frame's rule: X0/Y0/X1/Y1 = the CENTRE of the left/top/right/bottom rule
		           line. The map's edge is laid under it, so the rule covers it.
		Body       a plate's visible face (the sprig sticks out past it): X0/Y0/X1/Y1
		SliceCenter / SliceScale   9-slice panels; corners hold every ornament
		Circle     the pin ring's round part: centre X/Y and diameter D; Disc = the empty dark
		           middle's diameter (an icon goes there)
		Rects      sheet cells, { Offset, Size } (Vector2 px): ImageRectOffset / ImageRectSize
]]

local function rect(x0, y0, x1, y1)
	return { Offset = Vector2.new(x0, y0), Size = Vector2.new(x1 - x0, y1 - y0) }
end

return {
	-- Corner minimap: square double rule, a flowering vine at each corner. "Minimap Preview Frame.png"
	MINIMAP_FRAME = {
		Image = "rbxassetid://84895399737743",
		Size = Vector2.new(1024, 1006),
		Window = { X0 = 44, Y0 = 59.5, X1 = 979.5, Y1 = 957 },
	},
	-- The M map: the same frame, wide, a crest sprig mid-top. "Minimap Expanded Frame.png"
	WORLD_MAP_FRAME = {
		Image = "rbxassetid://79987727385413",
		Size = Vector2.new(1024, 632),
		Window = { X0 = 29.5, Y0 = 42.5, X1 = 993.5, Y1 = 599 },
	},
	-- Every quick-nav button's tile: dark wood, gold rim, a leaf and flower top left.
	-- "Map Button Background.png"
	BUTTON_PLATE = {
		Image = "rbxassetid://99846915233112",
		Size = Vector2.new(817, 791),
		Body = { X0 = 31, Y0 = 26, X1 = 811, Y1 = 786 },
	},
	-- The settings gear, in the bronze glyph set. "Settings Icon.png"
	SETTINGS_GLYPH = { Image = "rbxassetid://74066148923770", Aspect = 967 / 941 },

	-- A player marker's badge: a pale ring (tinted per type in code) round an empty dark disc,
	-- a pin point below. "Map Pin Marker Icon.png"
	PIN_RING = {
		Image = "rbxassetid://117174003856413",
		Size = Vector2.new(569, 632),
		Circle = { X = 284, Y = 284, D = 558 },
		Disc = 465,
	},
	-- The General marker's icon: a planted pennant. "General Marker Icon.png"
	MARKER_GENERAL = { Image = "rbxassetid://109893883397954", Aspect = 724 / 866 },
	-- You (and other players, tinted) on the map, pointing up. "Player ARrow.png"
	PLAYER_ARROW = { Image = "rbxassetid://116517054825087", Aspect = 653 / 948 },

	-- Dark panel, slim bronze rule, sprig top left: the M map's key hints. "Small Map Panel.png"
	PANEL = {
		Image = "rbxassetid://114425486225058",
		Size = Vector2.new(1024, 703),
		SliceCenter = Rect.new(120, 100, 904, 603),
	},
	-- Parchment slip pinned top left: the picker, the marker card, the tooltip and the toast.
	-- "map_note_panel.png"
	NOTE = {
		Image = "rbxassetid://140237227577904",
		Size = Vector2.new(1024, 684),
		SliceCenter = Rect.new(130, 110, 894, 574),
	},
	-- The legend: parchment cartouche, a blank ribbon across the top for the title, a sprig at
	-- the bottom. Only its height may stretch: draw it at Size.X * scale wide. "map_legend_cartouche.png"
	CARTOUCHE = {
		Image = "rbxassetid://110220313981249",
		Size = Vector2.new(686, 1024),
		SliceCenter = Rect.new(80, 160, 606, 870),
		Ribbon = { Y0 = 7, Y1 = 71 }, -- the banner's flat middle, for the title
	},
	-- The menus' ink icons, one sheet. "map_menu_icons.png"
	MENU_ICONS = {
		Image = "rbxassetid://101623445356915",
		Rects = {
			Track = rect(2, 0, 90, 130),
			StopTracking = rect(156, 0, 252, 130),
			ChangeType = rect(318, 0, 405, 130),
			Remove = rect(472, 0, 553, 130),
			Shown = rect(610, 0, 718, 130),
			Hidden = rect(768, 0, 870, 130),
			Centre = rect(917, 0, 1022, 130),
		},
	},
	-- A small leaf pointing right, beside the hovered row. "map_row_pointer.png"
	ROW_POINTER = { Image = "rbxassetid://134223050966090", Aspect = 752 / 331 },
}
