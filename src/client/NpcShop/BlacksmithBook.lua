--!strict
--  NpcShop/BlacksmithBook -- the Blacksmith's repairs (rebuilt 2026-10-01 from the old list
--  window), opened from the Blacksmith's dialog (DialogSystem/Trees/Blacksmith OpenMenu).
--    left   every worn or broken piece you own: its slot, name, a durability bar and the
--           cost; "Repair all" under the list
--    right  the selected piece: durability, cost (broken pieces cost 3x), Repair
--  NPCRequest RepairItem / RepairAll. The cost here mirrors the server's formula for display
--  (1 coin per 50 durability lost, rounded up, x3 when broken); the server's charge is final.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local DungeonMenuNet = require(script.Parent.Parent:WaitForChild("DungeonMenuNet"))
local ShopParts = require(script.Parent:WaitForChild("ShopParts"))
local Inventory = script.Parent.Parent:WaitForChild("InventoryHud"):WaitForChild("Inventory")
local InventoryData = require(Inventory:WaitForChild("InventoryData"))
local Journal = Inventory:WaitForChild("Journal")
local Style = require(Journal:WaitForChild("Style"))
local Parts = require(Journal:WaitForChild("Parts"))
local Book = require(Journal:WaitForChild("Book"))

local e = React.createElement

local WORN = Color3.fromRGB(176, 140, 64)   -- the durability bar, worn
local DAMAGED = Color3.fromRGB(150, 44, 34) -- under 30%, or broken

local function isRepairable(item: any): boolean
	if type(item) ~= "table" then return false end
	if item.type ~= "Weapon" and item.type ~= "Armor" and not (item.type == "Material" and item.equipSlot) then
		return false
	end
	return type(item.maxDurability) == "number" and item.maxDurability > 0
end

local function durabilityOf(item: any): (number, number)
	local max = tonumber(item.maxDurability) or 0
	local dur = tonumber(item.durability) or max
	return math.max(0, dur), max
end

local function repairCost(item: any): number
	local dur, max = durabilityOf(item)
	local lost = max - dur
	if lost <= 0 then return 0 end
	local cost = math.max(1, math.ceil(lost / 50))
	return item.broken and cost * 3 or cost
end

local function BlacksmithBook(props: { npcId: string })
	local snapshot = InventoryData.useSnapshot()
	local profile = snapshot and snapshot.profile
	local selectedUuid, setSelectedUuid = React.useState(nil :: string?)
	local busy, setBusy = React.useState(false)
	local status, statusGood, setStatus = ShopParts.useStatus()
	local coins = ShopParts.coins(profile)

	local pieces = {}
	local total = 0
	for uuid, item in pairs(profile and profile.inventory or {}) do
		if isRepairable(item) then
			local cost = repairCost(item)
			if cost > 0 then
				table.insert(pieces, { uuid = uuid, item = item, cost = cost })
				total += cost
			end
		end
	end
	-- Broken first, then the most worn.
	table.sort(pieces, function(a, b)
		if (a.item.broken == true) ~= (b.item.broken == true) then return a.item.broken == true end
		local da, ma = durabilityOf(a.item)
		local db, mb = durabilityOf(b.item)
		return da / ma < db / mb
	end)
	local current = pieces[1]
	for _, piece in ipairs(pieces) do
		if piece.uuid == selectedUuid then current = piece end
	end

	local function run(payload: { [string]: any }, done: string)
		if busy then return end
		setBusy(true)
		local ok, res = ShopParts.request(props.npcId, payload)
		setBusy(false)
		if ok then
			setStatus(done, true)
			DungeonMenuNet.requestSync()
		else
			setStatus(ShopParts.errorText(res and res.err), false)
		end
	end

	local rows: { [string]: any } = {}
	for i, piece in ipairs(pieces) do
		local dur, max = durabilityOf(piece.item)
		local ratio = max > 0 and dur / max or 0
		rows[piece.uuid] = e(ShopParts.ItemRow, {
			item = piece.item,
			name = ItemDefinitions.GetDisplayNameForItem(piece.item),
			nameColor = ShopParts.rarityColor(piece.item),
			sub = (piece.item.broken and "Broken, " or "") .. ShopParts.priceText(piece.cost, "Coins"),
			subColor = piece.item.broken and Style.Text.Bad or nil,
			selected = current ~= nil and piece.uuid == current.uuid,
			order = i,
			onSelect = function() setSelectedUuid(piece.uuid) end,
			rightRoom = 110,
			right = e(Parts.BarTrough, {
				fill = ratio, color = (piece.item.broken or ratio < 0.3) and DAMAGED or WORN,
				AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(96, 12),
			}),
		})
	end

	local left = e(ShopParts.Page, {
		heading = "Repairs",
		sub = "Mend worn and broken gear.",
		help = "Gear wears down as you fight. Broken gear stops working and costs three times as much to mend.",
		body = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
			List = e("Frame", { Size = UDim2.new(1, 0, 1, -56), BackgroundTransparency = 1 }, {
				Rows = ShopParts.List(rows, "Nothing needs mending."),
			}),
			All = #pieces > 0 and e(Parts.ChromeButton, {
				text = "Repair all, " .. ShopParts.priceText(total, "Coins"),
				art = "chip", artSelected = "chip_selected",
				selected = total <= coins, disabled = busy or total > coins,
				AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0),
				Size = UDim2.fromOffset(300, 44), textSize = 16,
				onClick = function() run({ action = "RepairAll" }, "Everything is mended.") end,
			}) or nil,
		}),
	})

	local detail: { [string]: any }
	if current then
		local item = current.item
		local dur, max = durabilityOf(item)
		local name = ItemDefinitions.GetDisplayNameForItem(item)
		detail = {
			item = item,
			name = name,
			nameColor = ShopParts.rarityColor(item),
			kind = item.broken and "Broken" or "Worn",
			body = item.broken and "It's broken and does nothing until it's mended." or "Mending restores it to full durability.",
			lines = {
				{ "Durability", ("%d / %d"):format(dur, max), not item.broken },
				{ "Cost", ShopParts.priceText(current.cost, "Coins") .. (item.broken and " (broken, 3x)" or ""), current.cost <= coins },
			},
			action = {
				text = busy and "Mending..." or "Repair",
				disabled = busy or current.cost > coins,
				onClick = function() run({ action = "RepairItem", itemUuid = current.uuid }, name .. " is mended.") end,
			},
		}
	else
		detail = { emptyText = "Your gear is in good shape." }
	end
	detail.status, detail.statusGood = status, statusGood
	detail.coins = coins

	return e(Book, { left = left, right = e(ShopParts.Detail, detail) })
end

return BlacksmithBook
