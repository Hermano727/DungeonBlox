--[[
	LoadingArt -- ReplicatedFirst/LoadingScreen/LoadingArt

	Asset ids for the loading screen. This is the one registry that lives outside
	ReplicatedStorage/Assets: the loading screen runs from ReplicatedFirst before ReplicatedStorage
	has arrived, so it can't require the normal registries. Ids copied from them are marked.

	Source art: assets/UI/loading screen/ (prompts in docs/loading-screen.md), uploaded after the
	usual trim / edge bleed / 1024 cap (tools/ui_assets/process.py helpers). Pixel numbers below
	are in the uploaded (processed) images. An empty Image = no art; the screen draws its stand-in.
]]

return {
	-- The painted backdrop ("Loading Screen 1.png", 1747x900), split down the middle so each half
	-- stays under the 1024 px UI cap at full resolution. Drawn cover-fit, centred.
	Background = {
		Left = "rbxassetid://106532409134538",
		Right = "rbxassetid://80638321607978",
		Aspect = 1747 / 900,
		Split = 873 / 1747, -- the left half's share of the width
	},

	-- The bar's frame ("Ornate Golden Double-Rail UI Frame.png", 1024x83 uploaded): two bronze
	-- rails (rows 10-25 and 60-75) between scrolled end caps (~75 px each). The slice centre is a
	-- thin band in the empty gap between the rails, so only the gap and the rails' length stretch.
	-- SliceScale 0.41 draws it 34 px tall (the screen's BAR_H). FillInset = px from the frame's edge
	-- to the fill at that size: the fill sits between the rails and tucks under the scrolls.
	BarFrame = {
		Image = "rbxassetid://132134143478482",
		SliceCenter = Rect.new(80, 41, 944, 42), SliceScale = 0.41, FillInset = Vector2.new(26, 11),
	},
	-- Stand-in until then: the Journal's bar trough (JournalUI.bar_trough).
	BarFrameFallback = {
		Image = "rbxassetid://102104005930659",
		SliceCenter = Rect.new(32, 18, 992, 39), SliceScale = 0.28, FillInset = Vector2.new(10, 5),
	},

	-- A small golden leaf that rides the fill's leading edge ("Golden Autumn Leaf Game Icon.png").
	BarHead = { Image = "rbxassetid://108239144384880", Aspect = 683 / 885 },

	-- Leaves drifting down across the screen, picked at random. Gold and green are cut from one
	-- sheet ("Autumn Maple Leaf Icon Trio.png", 1024x283; its half-green leaf isn't used) through
	-- an ImageRect; brown and orange are whole images (Size zero = the whole image).
	Leaves = {
		{ Image = "rbxassetid://94855054982811", Offset = Vector2.new(0, 0), Size = Vector2.new(287, 281) }, -- gold
		{ Image = "rbxassetid://94855054982811", Offset = Vector2.new(371, 4), Size = Vector2.new(283, 277) }, -- green
		{ Image = "rbxassetid://76668222740142", Offset = Vector2.zero, Size = Vector2.zero }, -- brown ("Glossy Autumn Maple Leaf Sticker.png")
		{ Image = "rbxassetid://89987830334239", Offset = Vector2.zero, Size = Vector2.zero }, -- orange ("Autumn Maple Leaf Sticker.png")
	},

	-- Shared HUD art (copied from RS/Assets/Images/HudArt).
	Glow = "rbxassetid://119483079370092", -- HudArt.GLOW_SOFT: white radial glow
	Grain = "rbxassetid://100183735763345", -- HudArt.BAR_GRAIN: seamless dark swirls for bar fills
}
