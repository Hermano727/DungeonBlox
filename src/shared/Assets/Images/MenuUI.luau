--[[
	MenuUI -- ReplicatedStorage/Assets/Images

	The dark menu kit (2026-10-11), first used by the Settings screen (client/SettingsClient):
	plates, a title ribbon, slider pieces, a tick box, category glyphs, and the mouse icons every
	keybind display uses (HudQuickNav.KeyCap). Same look as the map's art (MapUI): fine dark
	outline, slim bronze rims, small cream / dusty-rose flowers. Sources in
	assets/UI/settings menu/ (file name next to each id); trimmed, edge-bled and capped at 1024 px
	before upload, so every pixel measurement below is in the UPLOADED image. The panel body is
	MapUI.PANEL and the main button the quick-nav tile (MapUI.BUTTON_PLATE), reused.

	An empty Image means the code draws its old fallback.

		Size        the uploaded image's width, height (px)
		SliceCenter 9-slice: corners and rims stay, the middle stretches
		Band        the ribbon's flat cream band (Y0..Y1), where the title is written
		Rects       sheet cells, { Offset, Size } (Vector2 px): ImageRectOffset / ImageRectSize
]]

local function rect(x0, y0, x1, y1)
	return { Offset = Vector2.new(x0, y0), Size = Vector2.new(x1 - x0, y1 - y0) }
end

return {
	-- Cream ribbon with forked tails, two flowers mid-top: the page title. NOT sliced (the
	-- flowers sit in the middle): drawn whole at its own aspect. "settings_title_ribbon.png"
	TITLE_RIBBON = {
		Image = "rbxassetid://80366731719034",
		Size = Vector2.new(1024, 149),
		Band = { Y0 = 44, Y1 = 122 },
	},
	-- Dark wood plate, slim gold rim, chamfered corners: every row (buttons, sliders, toggles,
	-- the Controls rows). "settings_bar.png"
	BAR = {
		Image = "rbxassetid://80396071355578",
		Size = Vector2.new(1024, 134),
		SliceCenter = Rect.new(40, 40, 984, 94),
	},
	-- A recessed groove with a bronze lip, rounded ends: a slider's track (the gold fill is drawn
	-- in code inside it). Interior Y 13..48. "settings_slider_track.png"
	SLIDER_TRACK = {
		Image = "rbxassetid://97673254605639",
		Size = Vector2.new(1024, 61),
		SliceCenter = Rect.new(32, 29, 992, 32),
		Inner = 13, -- the lip's thickness, px
	},
	-- Domed bronze knob with a cream flower inlay. "settings_slider_knob.png"
	SLIDER_KNOB = { Image = "rbxassetid://82148083365519", Aspect = 369 / 366 },
	-- Off / on tick box. "settings_checkbox.png"
	CHECKBOX = {
		Image = "rbxassetid://115891280215006",
		Rects = { Off = rect(5, 0, 423, 401), On = rect(600, 0, 1020, 401) },
	},
	-- The Settings root's category glyphs, in the bronze nav-glyph style: a speaker, a film
	-- camera, a pointing hand. "settings_icons.png"
	CATEGORY_ICONS = {
		Image = "rbxassetid://132526892328598",
		Rects = { Audio = rect(3, 0, 308, 289), Video = rect(376, 0, 683, 289), Controls = rect(771, 0, 1021, 289) },
	},
	-- A dark plank with pointed ends, iron bands near both ends and a padlock hanging off the left
	-- one: a locked row (the bank's vault, NpcShop/BankBook). Slice it sideways only (the
	-- padlock end and the right band keep their shape): SliceCenter spans the full height. The
	-- plank itself is Y 9..74 (its face 18..65); the padlock hangs below it to the bottom.
	-- "Fantasy Wooden Nameplate Banner.png" (assets/UI/bank/).
	LOCKED_ROW = {
		Image = "rbxassetid://87061918938219",
		Size = Vector2.new(1024, 99),
		SliceCenter = Rect.new(116, 0, 914, 99),
		Plank = { Y0 = 9, Y1 = 74 },
	},
	-- Mouse inputs, drawn to sit beside key caps (cream, gold where you press). "mouse_icons.png.png"
	MOUSE_ICONS = {
		Image = "rbxassetid://134954303329215",
		Rects = {
			Left = rect(2, 0, 178, 234),
			Right = rect(251, 0, 430, 234),
			Scroll = rect(501, 0, 680, 234),
			Drag = rect(746, 0, 1021, 234),
		},
	},
}
