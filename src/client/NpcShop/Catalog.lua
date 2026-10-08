--!strict
--  NpcShop/Catalog -- a "things for sale" spread, shared by the Merchant's buy tabs and the
--  Animal Trainer's stable:
--    left   the goods (ItemRow: icon, name in its rarity colour, bundle size and price; a
--           price you can't pay shows in red)
--    right  the selected item (ShopParts.Detail): description, price, what you hold of the
--           currency, Buy
--
--    e(Catalog, { key = ..., npcId, snapshot, entries, heading, sub?, side?, tabs?,
--                 describe?(entry, def) -> string?, extraLines?(entry, def) -> { {label, value} } })
--
--  Give it a `key` per tab / filter so the selection resets when the list changes.
--  Buying is NPCRequest BuyItem (qty 1); the server checks the price, so the red / disabled
--  states here are only a hint. A one-time tutorial price (ScriptedRigs "price:<itemId>") is
--  mirrored on the player as RigPrice_<itemId> = "<price> <currency>" and shown instead.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local DungeonMenuNet = require(script.Parent.Parent:WaitForChild("DungeonMenuNet"))
local ShopParts = require(script.Parent:WaitForChild("ShopParts"))
local Journal = script.Parent.Parent:WaitForChild("InventoryHud"):WaitForChild("Inventory"):WaitForChild("Journal")
local Style = require(Journal:WaitForChild("Style"))
local Book = require(Journal:WaitForChild("Book"))

local e = React.createElement
local localPlayer = game:GetService("Players").LocalPlayer

-- The price to show: the server's one-time override if there is one, else the catalog's.
local function priceOf(entry: any): (number, string)
	local rig = localPlayer:GetAttribute("RigPrice_" .. tostring(entry.ItemId))
	if type(rig) == "string" then
		local amount, currency = rig:match("^(%d+) (%S+)$")
		if amount then return tonumber(amount) :: number, currency :: string end
	end
	return math.max(0, math.floor(tonumber(entry.Price) or 0)), entry.Currency or "Coins"
end

-- "Rare, Tier 2" (whichever of the two the item has).
local function kindLine(item: any, def: any): string
	local bits = {}
	local rarity = ItemDefinitions.GetRarityForItem(item)
	if rarity then table.insert(bits, rarity) end
	if def and tonumber(def.Tier) then table.insert(bits, "Tier " .. def.Tier) end
	return table.concat(bits, ", ")
end

local function Catalog(props: any)
	local profile = props.snapshot and props.snapshot.profile
	local selected, setSelected = React.useState(1)
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

	local rows: { [string]: any } = {}
	for i, entry in ipairs(props.entries) do
		local item = ShopParts.catalogItem(entry)
		local price, currency = priceOf(entry)
		local qty = entry.Qty or 1
		local afford = ShopParts.countOf(profile, currency) >= price
		rows["E" .. i] = e(ShopParts.ItemRow, {
			item = item,
			name = entry.Label or ShopParts.displayName(entry.ItemId),
			nameColor = ShopParts.rarityColor(item),
			sub = (qty > 1 and ("Bundle of %d, "):format(qty) or "") .. ShopParts.priceText(price, currency),
			subColor = (not afford) and Style.Text.Bad or nil,
			selected = i == selected,
			order = i,
			onSelect = function() setSelected(i) end,
		})
	end
	local left = e(ShopParts.Page, {
		heading = props.heading, sub = props.sub,
		body = ShopParts.List(rows, props.emptyText or "Nothing for sale here right now."),
	})

	local entry = props.entries[selected]
	local detail
	if entry then
		local item = ShopParts.catalogItem(entry)
		local def = ItemDefinitions.Get(entry.ItemId)
		local name = entry.Label or ShopParts.displayName(entry.ItemId)
		local price, currency = priceOf(entry)
		local have = ShopParts.countOf(profile, currency)
		local lines = {
			{ "Price", ShopParts.priceText(price, currency) },
			{ "You have", currency == "Coins" and ShopParts.priceText(have, "Coins") or (have .. " " .. ShopParts.displayName(currency)), have >= price },
		}
		if (entry.Qty or 1) > 1 then table.insert(lines, 2, { "You get", tostring(entry.Qty) }) end
		for _, line in ipairs(props.extraLines and props.extraLines(entry, def) or {}) do
			table.insert(lines, line)
		end
		local function buy()
			if busy then return end
			setBusy(true)
			local ok, res = ShopParts.request(props.npcId, { action = "BuyItem", itemId = entry.ItemId, qty = 1 })
			setBusy(false)
			if ok then
				setStatus("Bought " .. name .. ".", true)
				DungeonMenuNet.requestSync() -- the push can race; pull the new bags and wallet
			else
				setStatus(ShopParts.errorText(res and res.err), false)
			end
		end
		detail = {
			item = item,
			name = name,
			nameColor = ShopParts.rarityColor(item),
			kind = kindLine(item, def),
			body = (props.describe and props.describe(entry, def)) or (def and def.Description) or "",
			lines = lines,
			action = { text = busy and "Buying..." or "Buy", disabled = busy or have < price, onClick = buy },
		}
	else
		detail = { emptyText = "Nothing to show." }
	end
	detail.status, detail.statusGood = status, statusGood
	detail.coins = ShopParts.coins(profile)

	return e(Book, { side = props.side, tabs = props.tabs, left = left, right = e(ShopParts.Detail, detail) })
end

return Catalog
