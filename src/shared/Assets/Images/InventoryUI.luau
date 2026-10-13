--[[
	InventoryUI -- ReplicatedStorage/Assets/Images

	Art for the Inventory tab's character panel (client/InventoryHud/Inventory/PlayerPreview)
	beyond the Journal kit it otherwise uses (2026-10-12). Sources in assets/UI/inventory/
	(file name next to each id); trimmed, edge-bled and capped at 1024 px before upload, so the
	pixel numbers are in the UPLOADED image. Empty Image = draw without it.

		SOCKET_DISCS  one sheet, three engraved wooden discs that sit inside a socket's carved
		              ring for the profession and mount slots (a faint pickaxe / fishing spear /
		              horse head, so an empty socket says what goes there; the item draws on
		              top). Cells by equip slot, { Offset, Size } px.
		TOOL_RACK     the timber rack behind the profession / mount column: three iron bands
		              (centres at Bands, px), one per socket, so each one hangs on a band.
]]

local function rect(x0, y0, x1, y1)
	return { Offset = Vector2.new(x0, y0), Size = Vector2.new(x1 - x0, y1 - y0) }
end

return {
	SOCKET_DISCS = { -- "socket_discs.png"
		Image = "rbxassetid://99483308719744",
		Cells = {
			Pickaxe = rect(2, 2, 316, 321),
			FishingSpear = rect(355, 2, 669, 321),
			Mount = rect(708, 2, 1022, 321),
		},
	},
	-- The item tooltip (Inventory/Tooltip, 2026-10-12). "tooltip_card.png": dark timber card,
	-- slim bronze rim, riveted corner caps; 9-slice.
	TOOLTIP_CARD = {
		Image = "rbxassetid://115227813904489",
		Size = Vector2.new(757, 1024),
		SliceCenter = Rect.new(56, 56, 701, 968),
	},
	-- "tooltip_nameplate.png": the name band, chevron ends, pale greys (tinted per rarity).
	TOOLTIP_NAMEPLATE = {
		Image = "rbxassetid://140700714762074",
		Size = Vector2.new(1024, 121),
		SliceCenter = Rect.new(60, 30, 964, 91),
	},
	-- "tooltip_tags.png": white glyphs, tinted per tag.
	TOOLTIP_TAGS = {
		Image = "rbxassetid://114821290036153",
		Cells = {
			Soulbound = rect(2, 2, 211, 228),
			Untradeable = rect(276, 2, 489, 228),
			Protected = rect(548, 2, 760, 228),
			Broken = rect(826, 2, 1022, 228),
		},
	},
	TOOL_RACK = { -- "tool_rack_plaque.png"
		Image = "rbxassetid://112433449257606",
		Size = Vector2.new(214, 1024),
		Bands = { 206.5, 501, 794.5 },
	},
}
