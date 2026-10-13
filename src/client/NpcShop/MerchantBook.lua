--!strict
--  NpcShop/MerchantBook -- the Merchant (rebuilt 2026-10-01 from the old dark-wood window; a
--  market stall since 2026-10-12, NpcShop/Stall, in place of the Journal book).
--  Sections hang as signs under the awning:
--    Ores      barter ore for tier scrap
--    Scrap     orbs and enchant scrolls, with T1..T5 signs filtering by tier
--    Salvage   break down unequipped weapons and armor into scrap (the tag shows what you get)
--    Potions
--  The goods stand on shelves with a price tag each (red when you can't pay for one); the
--  selected one is on the ledger card on the counter: its text, the price, what you hold, a
--  quantity stepper (1..99, the server's cap; Max = what you can pay for), the total written on
--  the ruled line, and the Buy plank. Goods come from NPCRegistry.Get("Merchant").ShopCatalog
--  (RS/ShopCatalogConfig), by ShopTab. Buying is NPCRequest BuyItem with qty; the server checks
--  the price, so the red / disabled states here are only a hint. A one-time tutorial price
--  (ScriptedRigs "price:<itemId>", mirrored as the RigPrice_<itemId> attribute) is shown instead,
--  and holds the quantity at 1 (the server only honours it for one).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local NPCRegistry = require(ReplicatedStorage:WaitForChild("NPCRegistry"))
local MerchantUI = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images"):WaitForChild("MerchantUI"))
local DungeonMenuNet = require(script.Parent.Parent:WaitForChild("DungeonMenuNet"))
local ShopParts = require(script.Parent:WaitForChild("ShopParts"))
local Stall = require(script.Parent:WaitForChild("Stall"))
local Inventory = script.Parent.Parent:WaitForChild("InventoryHud"):WaitForChild("Inventory")
local InventoryData = require(Inventory:WaitForChild("InventoryData"))
local Style = require(Inventory:WaitForChild("Journal"):WaitForChild("Style"))

local e = React.createElement
local localPlayer = game:GetService("Players").LocalPlayer

local MAX_QTY = 99 -- NPCService BuyItem's cap

local function iconOf(itemId: string): string?
	local icon = ItemDefinitions.GetIconForItem({ itemId = itemId })
	return (type(icon) == "string" and icon ~= "") and icon or nil
end

local function salvageIcon(): any
	local sheet = MerchantUI.ICONS
	local cell = sheet.Image ~= "" and sheet.Cells.Salvage or nil
	return cell and { Image = sheet.Image, Offset = cell.Offset, Size = cell.Size } or iconOf("TrainingSword")
end

local SECTIONS = {
	{ id = "Ores",    label = "Ores",    icon = iconOf("Coal") },
	{ id = "Scrap",   label = "Scrap",   icon = iconOf("T1Scrap") },
	{ id = "Salvage", label = "Salvage", icon = salvageIcon() },
	{ id = "Potions", label = "Potions", icon = iconOf("MinorPotion") },
}
local TIERS = { { id = 1, label = "T1" }, { id = 2, label = "T2" }, { id = 3, label = "T3" }, { id = 4, label = "T4" }, { id = 5, label = "T5" } }

-- Scrap a salvaged piece gives, by rarity (display only; the server decides).
local SCRAP_FOR = { Common = 4, Uncommon = 8, Rare = 12, Epic = 16, Legendary = 20 }
local RARITY_RANK = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 }

-- The price to show: the server's one-time override if there is one, else the catalog's.
local function priceOf(entry: any): (number, string, boolean)
	local rig = localPlayer:GetAttribute("RigPrice_" .. tostring(entry.ItemId))
	if type(rig) == "string" then
		local amount, currency = rig:match("^(%d+) (%S+)$")
		if amount then return tonumber(amount) :: number, currency :: string, true end
	end
	return math.max(0, math.floor(tonumber(entry.Price) or 0)), entry.Currency or "Coins", false
end

-- "Rare, Tier 2" (whichever of the two the item has).
local function kindLine(item: any, tier: any): string
	local bits = {}
	local rarity = ItemDefinitions.GetRarityForItem(item)
	if rarity then table.insert(bits, rarity) end
	if tonumber(tier) then table.insert(bits, "Tier " .. tier) end
	return table.concat(bits, ", ")
end

local function MerchantBook(props: { npcId: string })
	local snapshot = InventoryData.useSnapshot()
	local profile = snapshot and snapshot.profile
	local sectionId, setSection = React.useState("Ores")
	local tier, setTier = React.useState(1)
	local selected, setSelected = React.useState(nil :: string?)
	local qty, setQty = React.useState(1)
	local busy, setBusy = React.useState(false)
	local status, statusGood, setStatus = ShopParts.useStatus()
	-- re-render when a one-time price appears or is used up
	local _, setRigTick = React.useState(0)
	React.useEffect(function()
		local conn = localPlayer.AttributeChanged:Connect(function(name)
			if name:sub(1, 9) == "RigPrice_" then setRigTick(function(n) return n + 1 end) end
		end)
		return function() conn:Disconnect() end
	end, {})

	local function pickSection(id: string)
		setSection(id)
		setSelected(nil)
		setQty(1)
	end
	local function pickTier(t: number)
		setTier(t)
		setSelected(nil)
		setQty(1)
	end
	local function choose(key: string)
		if key ~= selected then setQty(1) end
		setSelected(key)
	end

	local goods: { any } = {}
	local counter: any

	if sectionId == "Salvage" then
		-- Every unequipped weapon / armor piece in your bags, best first.
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
		local current = nil
		for _, piece in ipairs(pieces) do
			local rarity = ItemDefinitions.GetRarityForItem(piece.item) or "Common"
			local pieceTier = tonumber(piece.item.tier) or 1
			if piece.uuid == selected then current = piece end
			table.insert(goods, {
				key = piece.uuid, item = piece.item, name = ItemDefinitions.GetDisplayNameForItem(piece.item),
				price = ("+%d T%d Scrap"):format(SCRAP_FOR[rarity] or 4, pieceTier), priceColor = Style.Text.Good,
				selected = piece.uuid == (current and current.uuid or selected),
				onSelect = function() choose(piece.uuid) end,
			})
		end
		if current then
			local item = current.item
			local rarity = ItemDefinitions.GetRarityForItem(item) or "Common"
			local pieceTier = tonumber(item.tier) or 1
			local scrap = SCRAP_FOR[rarity] or 4
			local name = ItemDefinitions.GetDisplayNameForItem(item)
			counter = Stall.Ledger({
				item = item, name = name, nameColor = ShopParts.rarityColor(item), kind = kindLine(item, pieceTier),
				body = "Salvaging destroys the piece for good and gives you scrap of its tier.",
				lines = { { "You get", ("%d T%d Scrap"):format(scrap, pieceTier), true } },
				action = {
					text = busy and "Salvaging..." or "Salvage", icon = salvageIcon(), disabled = busy,
					onClick = function()
						if busy then return end
						setBusy(true)
						local ok, res = ShopParts.request(props.npcId, { action = "SalvageGear", itemUuid = current.uuid })
						setBusy(false)
						if ok then
							setStatus("Salvaged " .. name .. ".", true)
							setSelected(nil)
							DungeonMenuNet.requestSync()
						else
							setStatus(ShopParts.errorText(res and res.err), false)
						end
					end,
				},
			})
		else
			counter = Stall.Ledger({
				emptyText = #pieces > 0 and "Pick a piece off the shelves to see what it's worth."
					or "Unequipped weapons and armor show up here.",
			})
		end
	else
		-- Goods for sale in this section (Scrap: of the chosen tier).
		local entries = {}
		local reg = NPCRegistry.Get("Merchant")
		for _, entry in ipairs(reg and reg.ShopCatalog or {}) do
			if (entry.ShopTab or "Scrap") == sectionId and (sectionId ~= "Scrap" or (entry.Tier or 1) == tier) then
				table.insert(entries, entry)
			end
		end
		local current = nil
		for i, entry in ipairs(entries) do
			local key = "E" .. i
			local price, currency = priceOf(entry)
			local bundle = entry.Qty or 1
			local afford = ShopParts.countOf(profile, currency) >= price
			if key == selected then current = entry end
			table.insert(goods, {
				key = key, item = ShopParts.catalogItem(entry), name = entry.Label or ShopParts.displayName(entry.ItemId),
				price = (bundle > 1 and ("%d for "):format(bundle) or "") .. ShopParts.priceText(price, currency),
				priceColor = (not afford) and Style.Text.Bad or nil,
				selected = key == selected,
				onSelect = function() choose(key) end,
			})
		end
		if current then
			local entry = current
			local item = ShopParts.catalogItem(entry)
			local def = ItemDefinitions.Get(entry.ItemId)
			local name = entry.Label or ShopParts.displayName(entry.ItemId)
			local price, currency, rigged = priceOf(entry)
			local have = ShopParts.countOf(profile, currency)
			local bundle = entry.Qty or 1
			-- How many you can pay for (1..99); a one-time price is for one only.
			local maxQty = rigged and 1 or (price > 0 and math.clamp(math.floor(have / price), 1, MAX_QTY) or MAX_QTY)
			local n = math.clamp(qty, 1, maxQty)
			local cost = price * n
			local lines = {
				{ "Price", ShopParts.priceText(price, currency) .. (bundle > 1 and (" for " .. bundle) or "") },
				{ "You have", currency == "Coins" and ShopParts.priceText(have, "Coins") or (ShopParts.commas(have) .. " " .. ShopParts.displayName(currency)), have >= cost },
			}
			if bundle * n > 1 then table.insert(lines, { "You get", tostring(bundle * n) }) end
			counter = Stall.Ledger({
				item = item, name = name, nameColor = ShopParts.rarityColor(item), kind = kindLine(item, def and def.Tier),
				body = (def and def.Description) or "",
				lines = lines,
				controls = (not rigged) and Stall.QtyStepper({ qty = n, max = maxQty, setQty = setQty }) or nil,
				total = ('Total  <font color="#%s">%s</font>'):format(
					(have >= cost and Style.Text.Value or Style.Text.Bad):ToHex(), ShopParts.priceText(cost, currency)),
				action = {
					text = busy and "Buying..." or "Buy", disabled = busy or have < cost,
					onClick = function()
						if busy then return end
						setBusy(true)
						local ok, res = ShopParts.request(props.npcId, { action = "BuyItem", itemId = entry.ItemId, qty = n })
						setBusy(false)
						if ok then
							setStatus(("Bought %s%s."):format(n > 1 and (n .. " x ") or "", name), true)
							setQty(1)
							DungeonMenuNet.requestSync() -- the push can race; pull the new bags and purse
						else
							setStatus(ShopParts.errorText(res and res.err), false)
						end
					end,
				},
			})
		else
			counter = Stall.Ledger({
				emptyText = #entries > 0 and "Pick something off the shelves." or "Nothing for sale here right now.",
			})
		end
	end

	return e(Stall.Stall, {
		title = "Merchant",
		sections = SECTIONS,
		selected = sectionId,
		onSelect = pickSection,
		coins = ShopParts.coins(profile),
		filter = sectionId == "Scrap" and Stall.FilterSigns({ options = TIERS, selected = tier, onSelect = pickTier }) or nil,
		goods = Stall.Shelves({
			items = goods,
			empty = sectionId == "Salvage" and "No unequipped weapons or armor in your bags." or "Nothing for sale here right now.",
		}),
		counter = counter,
		status = status,
		statusGood = statusGood,
	})
end

return MerchantBook
