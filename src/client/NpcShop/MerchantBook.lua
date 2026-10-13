--!strict
--  NpcShop/MerchantBook -- the Merchant (rebuilt 2026-10-01 from the old dark-wood window).
--  Sections in the Journal sidebar, each one a spread of the book:
--    Ores      barter ore for tier scrap (2 ore : 1 scrap), then coin sacks   (Catalog)
--    Scrap     enchant scrolls, 30 scrap each, with T1..T5 bookmark tabs on the book's top
--              edge filtering by tier                         (Catalog)
--    Salvage   break down unequipped weapons and armor into scrap (this file)
--    Potions   swap 3 Minor for 1 Medium, or 1 Medium for 3 Minor; nothing is sold (this file)
--  Goods come from NPCRegistry.Get("Merchant").ShopCatalog (RS/ShopCatalogConfig), by ShopTab.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local NPCRegistry = require(ReplicatedStorage:WaitForChild("NPCRegistry"))
local DungeonMenuNet = require(script.Parent.Parent:WaitForChild("DungeonMenuNet"))
local ShopParts = require(script.Parent:WaitForChild("ShopParts"))
local Catalog = require(script.Parent:WaitForChild("Catalog"))
local Inventory = script.Parent.Parent:WaitForChild("InventoryHud"):WaitForChild("Inventory")
local InventoryData = require(Inventory:WaitForChild("InventoryData"))
local Journal = Inventory:WaitForChild("Journal")
local Style = require(Journal:WaitForChild("Style"))
local Parts = require(Journal:WaitForChild("Parts"))
local Book = require(Journal:WaitForChild("Book"))
local Sidebar = require(Journal:WaitForChild("Sidebar"))

local e = React.createElement

local function iconOf(itemId: string): string?
	local icon = ItemDefinitions.GetIconForItem({ itemId = itemId })
	return (type(icon) == "string" and icon ~= "") and icon or nil
end

local SECTIONS = {
	{ id = "Ores",    label = "Ores",    item = "Coal",          heading = "Ore Trade", sub = "Two ore for one scrap. Coin sacks below." },
	{ id = "Scrap",   label = "Scrap",   item = "T1Scrap",       heading = "Scrap Goods", sub = "Enchant scrolls, 30 scrap each." },
	{ id = "Salvage", label = "Salvage", item = "TrainingSword", heading = "Salvage", sub = "Break down gear you aren't wearing." },
	{ id = "Potions", label = "Potions", item = "MinorPotion",   heading = "Potion Swap", sub = "Trade potions up or down a size." },
}
local PAGES = {}
for _, section in ipairs(SECTIONS) do
	table.insert(PAGES, { id = section.id, label = section.label, icon = iconOf(section.item) })
end

-- Scrap a salvaged piece gives, by rarity (display only; the server decides).
local SCRAP_FOR = { Common = 4, Uncommon = 8, Rare = 12, Epic = 16, Legendary = 20 }
local RARITY_RANK = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 }
local TIERS = 5

local function TierTabs(props: { tier: number, setTier: (number) -> () })
	local tabs: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for t = 1, TIERS do
		tabs["T" .. t] = e(Parts.ChromeButton, {
			text = "T" .. t, selected = t == props.tier,
			art = "bookmark_tab", artSelected = "bookmark_tab_active",
			Size = UDim2.fromOffset(96, Style.TAB_H), LayoutOrder = t, textSize = 17,
			onClick = function() props.setTier(t) end,
		})
	end
	return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, tabs)
end

-- Salvage: every unequipped weapon / armor piece in your bags.
local function Salvage(props: { npcId: string, snapshot: any, side: any })
	local profile = props.snapshot and props.snapshot.profile
	local selectedUuid, setSelectedUuid = React.useState(nil :: string?)
	local busy, setBusy = React.useState(false)
	local status, statusGood, setStatus = ShopParts.useStatus()

	local equipped: { [string]: boolean } = {}
	for _, uuid in pairs(profile and profile.equipped or {}) do equipped[uuid] = true end
	local pieces = {}
	for key, item in pairs(profile and profile.inventory or {}) do
		if type(item) == "table" and (item.type == "Weapon" or item.type == "Armor") then
			local uuid = (type(key) == "string" and key ~= "") and key or item.uuid
			if type(uuid) == "string" and uuid ~= "" and not equipped[uuid] then
				table.insert(pieces, { uuid = uuid, item = item })
			end
		end
	end
	table.sort(pieces, function(a, b)
		local ra = RARITY_RANK[ItemDefinitions.GetRarityForItem(a.item) or ""] or 0
		local rb = RARITY_RANK[ItemDefinitions.GetRarityForItem(b.item) or ""] or 0
		if ra ~= rb then return ra > rb end
		return ItemDefinitions.GetDisplayNameForItem(a.item) < ItemDefinitions.GetDisplayNameForItem(b.item)
	end)

	local current = pieces[1]
	for _, piece in ipairs(pieces) do
		if piece.uuid == selectedUuid then current = piece end
	end

	local rows: { [string]: any } = {}
	for i, piece in ipairs(pieces) do
		local rarity = ItemDefinitions.GetRarityForItem(piece.item) or "Common"
		rows[piece.uuid] = e(ShopParts.ItemRow, {
			item = piece.item,
			name = ItemDefinitions.GetDisplayNameForItem(piece.item),
			nameColor = ShopParts.rarityColor(piece.item),
			sub = ("%s, Tier %d"):format(rarity, tonumber(piece.item.tier) or 1),
			selected = current ~= nil and piece.uuid == current.uuid,
			order = i,
			onSelect = function() setSelectedUuid(piece.uuid) end,
		})
	end
	local left = e(ShopParts.Page, {
		heading = "Salvage", sub = "Break down gear you aren't wearing.",
		body = ShopParts.List(rows, "No unequipped weapons or armor in your bags."),
	})

	local detail: { [string]: any }
	if current then
		local item = current.item
		local rarity = ItemDefinitions.GetRarityForItem(item) or "Common"
		local tier = tonumber(item.tier) or 1
		local scrap = SCRAP_FOR[rarity] or 4
		local name = ItemDefinitions.GetDisplayNameForItem(item)
		local function salvage()
			if busy then return end
			setBusy(true)
			local ok, res = ShopParts.request(props.npcId, { action = "SalvageGear", itemUuid = current.uuid })
			setBusy(false)
			if ok then
				setStatus("Salvaged " .. name .. ".", true)
				setSelectedUuid(nil)
				DungeonMenuNet.requestSync()
			else
				setStatus(ShopParts.errorText(res and res.err), false)
			end
		end
		detail = {
			item = item,
			name = name,
			nameColor = ShopParts.rarityColor(item),
			kind = ("%s, Tier %d"):format(rarity, tier),
			body = "Salvaging destroys the item for good and gives you scrap of its tier.",
			lines = { { "You get", ("%d T%d Scrap"):format(scrap, tier), true } },
			action = { text = busy and "Salvaging..." or "Salvage", disabled = busy, onClick = salvage },
		}
	else
		detail = { emptyText = "Unequipped weapons and armor show up here." }
	end
	detail.status, detail.statusGood = status, statusGood
	detail.coins = ShopParts.coins(profile)

	return e(Book, { side = props.side, left = left, right = e(ShopParts.Detail, detail) })
end

-- Potions: swaps only (3 Minor for 1 Medium, 1 Medium for 3 Minor). The Merchant sells no
-- potions. The list comes from the Merchant's TradeRates rows tagged ShopTab = "Potions";
-- the server (NPCService TradeOre) checks and applies them by that row's index.
local function PotionSwaps(props: { npcId: string, snapshot: any, side: any })
	local profile = props.snapshot and props.snapshot.profile
	local selected, setSelected = React.useState(1)
	local busy, setBusy = React.useState(false)
	local status, statusGood, setStatus = ShopParts.useStatus()

	local swaps = {}
	local reg = NPCRegistry.Get("Merchant")
	for index, trade in ipairs(reg and reg.TradeRates or {}) do
		if trade.ShopTab == "Potions" then
			table.insert(swaps, { index = index, give = trade.Give, receive = trade.Receive })
		end
	end

	local rows: { [string]: any } = {}
	for i, swap in ipairs(swaps) do
		local item = { itemId = swap.receive.ItemId, count = swap.receive.Qty }
		local have = ShopParts.countOf(profile, swap.give.ItemId)
		rows["S" .. i] = e(ShopParts.ItemRow, {
			item = item,
			name = ShopParts.displayName(swap.receive.ItemId),
			nameColor = ShopParts.rarityColor(item),
			sub = ("Swap %d %s"):format(swap.give.Qty, ShopParts.displayName(swap.give.ItemId)
				.. (swap.give.Qty > 1 and "s" or "")),
			subColor = have < swap.give.Qty and Style.Text.Bad or nil,
			selected = i == selected,
			order = i,
			onSelect = function() setSelected(i) end,
		})
	end
	local left = e(ShopParts.Page, {
		heading = "Potion Swap", sub = "Trade potions up or down a size.",
		body = ShopParts.List(rows, "No swaps offered right now."),
	})

	local swap = swaps[selected]
	local detail
	if swap then
		local item = { itemId = swap.receive.ItemId, count = swap.receive.Qty }
		local name = ShopParts.displayName(swap.receive.ItemId)
		local giveName = ShopParts.displayName(swap.give.ItemId)
		local have = ShopParts.countOf(profile, swap.give.ItemId)
		local function doSwap()
			if busy then return end
			setBusy(true)
			local ok, res = ShopParts.request(props.npcId, { action = "TradeOre", tradeIndex = swap.index, qty = 1 })
			setBusy(false)
			if ok then
				setStatus(("Swapped for %d %s."):format(swap.receive.Qty, name), true)
				DungeonMenuNet.requestSync()
			else
				setStatus(ShopParts.errorText(res and res.err), false)
			end
		end
		detail = {
			item = item,
			name = name,
			nameColor = ShopParts.rarityColor(item),
			kind = ItemDefinitions.GetRarityForItem(item) or "",
			body = ItemDefinitions.GetDescription(swap.receive.ItemId),
			lines = {
				{ "You give", ("%d %s"):format(swap.give.Qty, giveName) },
				{ "You get", ("%d %s"):format(swap.receive.Qty, name) },
				{ "You have", ("%d %s"):format(have, giveName), have >= swap.give.Qty },
			},
			action = { text = busy and "Swapping..." or "Swap", disabled = busy or have < swap.give.Qty, onClick = doSwap },
		}
	else
		detail = { emptyText = "No swaps offered right now." }
	end
	detail.status, detail.statusGood = status, statusGood
	detail.coins = ShopParts.coins(profile)

	return e(Book, { side = props.side, left = left, right = e(ShopParts.Detail, detail) })
end

local function MerchantBook(props: { npcId: string })
	local snapshot = InventoryData.useSnapshot()
	local sectionId, setSection = React.useState("Ores")
	local tier, setTier = React.useState(1)

	local section = SECTIONS[1]
	for _, s in ipairs(SECTIONS) do
		if s.id == sectionId then section = s end
	end
	local side = e(Sidebar, { pages = PAGES, selected = sectionId, onSelect = setSection })

	if sectionId == "Salvage" then
		return e(Salvage, { key = "Salvage", npcId = props.npcId, snapshot = snapshot, side = side })
	end	if sectionId == "Potions" then
		return e(PotionSwaps, { key = "Potions", npcId = props.npcId, snapshot = snapshot, side = side })
	end

	local entries = {}
	local reg = NPCRegistry.Get("Merchant")
	for _, entry in ipairs(reg and reg.ShopCatalog or {}) do
		if (entry.ShopTab or "Scrap") == sectionId and (sectionId ~= "Scrap" or (entry.Tier or 1) == tier) then
			table.insert(entries, entry)
		end
	end
	return e(Catalog, {
		key = sectionId .. (sectionId == "Scrap" and tier or ""),
		npcId = props.npcId,
		snapshot = snapshot,
		entries = entries,
		heading = section.heading,
		sub = sectionId == "Scrap" and (section.sub .. " Tier " .. tier .. ".") or section.sub,
		side = side,
		tabs = sectionId == "Scrap" and e(TierTabs, { tier = tier, setTier = setTier }) or nil,
	})
end

return MerchantBook
