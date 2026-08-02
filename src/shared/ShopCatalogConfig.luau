--[[
	ShopCatalogConfig
	Single place for every NPC shop's price list (ShopCatalog) and barter rates
	(TradeRates). NPCRegistry requires this and wires each NpcType's catalog from
	here — change prices/items/currencies here, not in NPCRegistry. NPCRegistry
	still owns non-price config (Interactions, OpenShopPrompt, etc).
]]

return {

	Merchant = {
		ShopCatalog = {
			-- Ores tab: barter ore for tier scrap
			{ ItemId = "T1Scrap", Label = "T1 Scrap", Price = 1, Currency = "Coal", Qty = 1, ShopTab = "Ores" },
			{ ItemId = "T2Scrap", Label = "T2 Scrap", Price = 1, Currency = "Emerald", Qty = 1, ShopTab = "Ores" },
			{ ItemId = "T3Scrap", Label = "T3 Scrap", Price = 1, Currency = "IronOre", Qty = 1, ShopTab = "Ores" },
			{ ItemId = "T4Scrap", Label = "T4 Scrap", Price = 1, Currency = "Diamond", Qty = 1, ShopTab = "Ores" },
			{ ItemId = "T5Scrap", Label = "T5 Scrap", Price = 1, Currency = "Gold", Qty = 1, ShopTab = "Ores" },
			-- Scrap tab: coins and scrap-for-scroll
			{ ItemId = "T1OrbOfWisdom", Label = "T1 Orb of Wisdom", Price = 1, Currency = "Coins", Qty = 30, ShopTab = "Scrap" },
			{ ItemId = "T1OrbOfChaos", Label = "T1 Orb of Chaos", Price = 1, Currency = "Coins", Qty = 30, ShopTab = "Scrap" },
			{ ItemId = "T1OrbOfNullification", Label = "T1 Orb of Nullification", Price = 1, Currency = "Coins", Qty = 30, ShopTab = "Scrap" },
			{ ItemId = "T1OrbOfAlteration", Label = "T1 Orb of Alteration", Price = 1, Currency = "Coins", Qty = 30, ShopTab = "Scrap" },
			{ ItemId = "T1OrbOfTransmutation", Label = "T1 Orb of Transmutation", Price = 1, Currency = "Coins", Qty = 30, ShopTab = "Scrap" },
			{ ItemId = "T1OrbOfReforging", Label = "T1 Orb of Reforging", Price = 1, Currency = "Coins", Qty = 30, ShopTab = "Scrap" },
			{ ItemId = "T1OrbOfDivinity", Label = "T1 Orb of Divinity", Price = 1, Currency = "Coins", Qty = 30, ShopTab = "Scrap" },
			{ ItemId = "T1WeaponScroll", Label = "T1 Weapon Scroll", Price = 0, Currency = "T1Scrap", Qty = 30, ShopTab = "Scrap", Tier = 1 },
			{ ItemId = "T1ArmorScroll",  Label = "T1 Armor Scroll",  Price = 0, Currency = "T1Scrap", Qty = 30, ShopTab = "Scrap", Tier = 1 },
			{ ItemId = "T2WeaponScroll", Label = "T2 Weapon Scroll", Price = 0, Currency = "T2Scrap", Qty = 30, ShopTab = "Scrap", Tier = 2 },
			{ ItemId = "T2ArmorScroll",  Label = "T2 Armor Scroll",  Price = 0, Currency = "T2Scrap", Qty = 30, ShopTab = "Scrap", Tier = 2 },
			{ ItemId = "T3WeaponScroll", Label = "T3 Weapon Scroll", Price = 0, Currency = "T3Scrap", Qty = 30, ShopTab = "Scrap", Tier = 3 },
			{ ItemId = "T3ArmorScroll",  Label = "T3 Armor Scroll",  Price = 0, Currency = "T3Scrap", Qty = 30, ShopTab = "Scrap", Tier = 3 },
			{ ItemId = "T4WeaponScroll", Label = "T4 Weapon Scroll", Price = 0, Currency = "T4Scrap", Qty = 30, ShopTab = "Scrap", Tier = 4 },
			{ ItemId = "T4ArmorScroll",  Label = "T4 Armor Scroll",  Price = 0, Currency = "T4Scrap", Qty = 30, ShopTab = "Scrap", Tier = 4 },
			{ ItemId = "T5WeaponScroll", Label = "T5 Weapon Scroll", Price = 0, Currency = "T5Scrap", Qty = 30, ShopTab = "Scrap", Tier = 5 },
			{ ItemId = "T5ArmorScroll",  Label = "T5 Armor Scroll",  Price = 0, Currency = "T5Scrap", Qty = 30, ShopTab = "Scrap", Tier = 5 },
			-- Potions tab
			{ ItemId = "MinorPotion",  Label = "Minor Potion",  Price = 0, Currency = "Coins", Qty = 1, ShopTab = "Potions", Tier = 1 },
			{ ItemId = "MediumPotion", Label = "Medium Potion", Price = 0, Currency = "Coins", Qty = 1, ShopTab = "Potions", Tier = 3 },
		},
		TradeRates = {
			{ Give = { ItemId = "IronOre", Qty = 5  }, Receive = { ItemId = "T1Scrap", Qty = 10 } },
			{ Give = { ItemId = "Fish",    Qty = 10 }, Receive = { Currency = "Coins", Qty = 25 } },
		},
	},

	SkillTrainer = {
		ShopCatalog = {
			{ ItemId = "TrainingSword", Label = "Training Sword", Price = 100, Currency = "Coins" },
			{ ItemId = "WoodenBow",    Label = "Wooden Bow",     Price = 150, Currency = "Coins" },
		},
	},

	AnimalTrainer = {
		ShopCatalog = {
			{ ItemId = "T1MountSaddle", Label = "T1 Mount Saddle", Price = 1, Currency = "Coins", Qty = 1 },
			{ ItemId = "T2MountSaddle", Label = "T2 Mount Saddle", Price = 1, Currency = "Coins", Qty = 1 },
			{ ItemId = "T3MountSaddle", Label = "T3 Mount Saddle", Price = 1, Currency = "Coins", Qty = 1 },
			{ ItemId = "T4MountSaddle", Label = "T4 Mount Saddle", Price = 1, Currency = "Coins", Qty = 1 },
		},
	},

	Innkeeper = {
		ShopCatalog = {},
		-- Hearthstone locations managed via HearthstoneRegistry + HearthstoneClient ProximityPrompt, not here.
	},

	Dungeoneer = {
		ShopCatalog = {
			{ ItemId = "T1DungeonKey", Label = "T1 Dungeon Key", Price = 30, Currency = "T1KeyFragment", Qty = 1, ShopTab = "Keys" },
			{ ItemId = "T2DungeonKey", Label = "T2 Dungeon Key", Price = 30, Currency = "T2KeyFragment", Qty = 1, ShopTab = "Keys" },
			{ ItemId = "T3DungeonKey", Label = "T3 Dungeon Key", Price = 30, Currency = "T3KeyFragment", Qty = 1, ShopTab = "Keys" },
			{ ItemId = "T4DungeonKey", Label = "T4 Dungeon Key", Price = 30, Currency = "T4KeyFragment", Qty = 1, ShopTab = "Keys" },
			{ ItemId = "T5DungeonKey", Label = "T5 Dungeon Key", Price = 30, Currency = "T5KeyFragment", Qty = 1, ShopTab = "Keys" },
			{ ItemId = "T1WeaponProtectionScroll", Label = "T1 Weapon Protection Scroll", Price = 0, Currency = "Coins", Qty = 30, ShopTab = "Scrolls" },
			{ ItemId = "T1ArmorProtectionScroll", Label = "T1 Armor Protection Scroll", Price = 0, Currency = "Coins", Qty = 30, ShopTab = "Scrolls" },
			{ ItemId = "T2WeaponProtectionScroll", Label = "T2 Weapon Protection Scroll", Price = 0, Currency = "Coins", Qty = 30, ShopTab = "Scrolls" },
			{ ItemId = "T2ArmorProtectionScroll", Label = "T2 Armor Protection Scroll", Price = 0, Currency = "Coins", Qty = 30, ShopTab = "Scrolls" },
			{ ItemId = "T3WeaponProtectionScroll", Label = "T3 Weapon Protection Scroll", Price = 0, Currency = "Coins", Qty = 30, ShopTab = "Scrolls" },
			{ ItemId = "T3ArmorProtectionScroll", Label = "T3 Armor Protection Scroll", Price = 0, Currency = "Coins", Qty = 30, ShopTab = "Scrolls" },
			{ ItemId = "T4WeaponProtectionScroll", Label = "T4 Weapon Protection Scroll", Price = 0, Currency = "Coins", Qty = 30, ShopTab = "Scrolls" },
			{ ItemId = "T4ArmorProtectionScroll", Label = "T4 Armor Protection Scroll", Price = 0, Currency = "Coins", Qty = 30, ShopTab = "Scrolls" },
			{ ItemId = "T5WeaponProtectionScroll", Label = "T5 Weapon Protection Scroll", Price = 0, Currency = "Coins", Qty = 30, ShopTab = "Scrolls" },
			{ ItemId = "T5ArmorProtectionScroll", Label = "T5 Armor Protection Scroll", Price = 0, Currency = "Coins", Qty = 30, ShopTab = "Scrolls" },
		},
	},
}
