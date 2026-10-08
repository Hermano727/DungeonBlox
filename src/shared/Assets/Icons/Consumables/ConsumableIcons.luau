--[[
    ConsumableIcons
    Central registry for consumable (potion/food/etc.) icon asset IDs.
    Require this instead of writing rbxassetid:// literals inline.

    Keys match the corresponding itemId in ReplicatedStorage/ItemDefinitions.
]]

return {
	-- 2026-10-02: rendered from the 3D vial (assets/models/potions/T1_MinorPotion/render_icon.py,
	-- T1_MinorPotion_icon.png). Was rbxassetid://74587804866203.
	MINOR_POTION  = "rbxassetid://110613878809743",
	MEDIUM_POTION = "rbxassetid://125556943376418", -- rbxassetid://125556943376418

	-- Fish (2026-10-03; assets/ui/incoming icon_fish_*, uploaded through Studio). Raw fish keyed
	-- by their legacy itemIds.
	FISH = "rbxassetid://133708507444293",
	SWIFT_FISH = "rbxassetid://128038571307153",
	LUCKY_FISH = "rbxassetid://139097861471480",
	GOLDEN_FISH = "rbxassetid://136296963546163",
	-- Cooked fish (assets/ui/incoming icon_fish_*_cooked, uploaded through Studio 2026-10-03).
	T1_COOKED_FISH = "rbxassetid://95185837104030",
	T2_COOKED_SWIFT_FISH = "rbxassetid://137981505464721",
	T2_COOKED_LUCKY_FISH = "rbxassetid://117413271865362",
	T3_COOKED_GOLDEN_FISH = "rbxassetid://122887660882425",
}
