--[[
	MerchantUI -- ReplicatedStorage/Assets/Images

	The merchant's stall (2026-10-12, NpcShop/Stall + NpcShop/MerchantBook): a travelling
	trader's look, timber, brass, striped canvas, twine and parchment, no flowers. Sources in
	assets/UI/npcs/merchant/ (file name next to each id); trimmed, edge-bled and capped at 1024 px
	before upload, so every pixel number below is in the UPLOADED image. The coin purse is the
	Journal's own (JournalUI.icon_loot_score).

	Pieces are drawn at their own shape (no 9-slice: as one sliced image Roblox squashed a
	similar plank, see BankBook), or in plain pieces (caps + a stretched / repeated middle).

		Size     the uploaded image's width, height (px)
		Face     where text goes: X0/Y0/X1/Y1 in px
		Cells    sheet cells, { Offset, Size } (Vector2 px): ImageRectOffset / ImageRectSize
]]

local function rect(x0, y0, x1, y1)
	return { Offset = Vector2.new(x0, y0), Size = Vector2.new(x1 - x0, y1 - y0) }
end

return {
	-- Green and cream striped canvas on a timber rod, scalloped hem. Drawn as the left end, the
	-- repeating stripe pair (one green, one cream) stretched to fill, and the right end.
	-- "merchant_awning.png"
	AWNING = {
		Image = "rbxassetid://111488113805912",
		Size = Vector2.new(1024, 147),
		LeftCap = rect(0, 0, 160, 147),
		Repeat = rect(160, 0, 361, 147),
		RightCap = rect(964, 0, 1024, 147),
	},
	-- Hanging timber sign on two chains, brass rim, a balance scale carved at the left end; the
	-- plank is Y 120..269 (chains above). "merchant_signboard.png"
	SIGNBOARD = {
		Image = "rbxassetid://114202428145350",
		Size = Vector2.new(1024, 271),
		Face = { X0 = 180, Y0 = 140, X1 = 975, Y1 = 250 },
	},
	-- A shelf plank (Y 3..54) on two iron brackets that hang below it. Drawn as two ends (with
	-- the brackets) and a stretched middle. "merchant_shelf.png"
	SHELF = {
		Image = "rbxassetid://103221234746720",
		Size = Vector2.new(1024, 121),
		LeftCap = rect(0, 0, 112, 121),
		Middle = rect(112, 0, 912, 121),
		RightCap = rect(912, 0, 1024, 121),
		Plank = { Y0 = 3, Y1 = 54 },
	},
	-- A parchment price tag, pointed at the left with a punched hole and a twine loop curling
	-- up off the top; the tag body is Y 121..427. "merchant_price_tag.png"
	PRICE_TAG = {
		Image = "rbxassetid://97361752137685",
		Size = Vector2.new(1024, 432),
		Face = { X0 = 250, Y0 = 140, X1 = 990, Y1 = 410 },
	},
	-- The section signs: a timber shingle on two twine cords; Selected is lighter with a brass
	-- rim. Each cell's plank is Y 59..190 (cords above). "merchant_tab_signs.png"
	TAB_SIGNS = {
		Image = "rbxassetid://93452321408323",
		Cells = { Normal = rect(3, 0, 467, 192), Selected = rect(557, 0, 1021, 192) },
		Face = { Y0 = 63, Y1 = 185 }, -- within a cell
	},
	-- The ledger card on the counter: parchment held by a brass clip at the top centre, two ruled
	-- lines near the bottom (Y 904 and 945), a curled bottom-right corner; paper X 11..726.
	-- Drawn at its own shape. "merchant_ledger.png"
	LEDGER = {
		Image = "rbxassetid://110249615461438",
		Size = Vector2.new(737, 1024),
		PaperTop = 66,
		Rules = { 904, 945 },
	},
	-- The Buy plank: timber with brass corner caps; Normal on top, Hover below. Drawn at its own
	-- shape (about 6.25:1). "merchant_buy_button.png"
	BUY_BUTTON = {
		Image = "rbxassetid://114561348768208",
		Cells = { Normal = rect(9, 7, 1016, 168), Hover = rect(9, 193, 1016, 352) },
	},
	-- Icons: (a coin purse, unused: JournalUI.icon_loot_score is the purse), a hammer striking an
	-- anvil (Salvage), a brass balance scale. "merchant_icons.png"
	ICONS = {
		Image = "rbxassetid://98601544714848",
		Cells = { Salvage = rect(352, 2, 663, 304), Scale = rect(701, 2, 1022, 304) },
	},
}
