--!strict
--  NpcShop/BankBook -- the bank at the Treasure Chest (rebuilt 2026-10-01 from the old
--  1,260-line window).
--    left   the Vault: the chest grid (Types.CHEST_GRID_COLUMNS x ROWS). Rows past
--           chestUnlockedRows are locked; the next one shows "Unlock row N" for
--           CHEST_ROW_UNLOCK_COIN_COST coins.
--    right  Your bags: everything you can store (not equipped, not on the hotbar), and the
--           coins: wallet vs coins carried in your bags, "Deposit all" and a withdraw box.
--  One click moves an item: a bag item goes into the first free vault slot, a vault item goes
--  back to your bags (the old window was select-then-click-a-slot). Hovering an item names it.
--  Server: DungeonInventoryAct ChestDeposit / ChestWithdraw / ChestUnlockRow
--  (DungeonMenuNet.requestInventoryAct) and BankRequest DepositAll / Withdraw (SSS/BankService).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Types = require(ReplicatedStorage:WaitForChild("ProfileTypes"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local DungeonMenuNet = require(script.Parent.Parent:WaitForChild("DungeonMenuNet"))
local ShopParts = require(script.Parent:WaitForChild("ShopParts"))
local Inventory = script.Parent.Parent:WaitForChild("InventoryHud"):WaitForChild("Inventory")
local InventoryData = require(Inventory:WaitForChild("InventoryData"))
local ItemSlot = require(Inventory:WaitForChild("ItemSlot"))
local Journal = Inventory:WaitForChild("Journal")
local Style = require(Journal:WaitForChild("Style"))
local Parts = require(Journal:WaitForChild("Parts"))
local Book = require(Journal:WaitForChild("Book"))

local e = React.createElement
local text = Parts.Text

local COLS, ROWS = Types.CHEST_GRID_COLUMNS, Types.CHEST_GRID_ROWS
local UNLOCK_COST = Types.CHEST_ROW_UNLOCK_COIN_COST
local CELL, GAP = 46, 4
local BAG_COLS = 8
local COIN_ITEM = "Coins"

local ERRORS = {
	equipped = "Unequip it first.",
	not_owned = "That's no longer in your bags.",
	chest_full = "The vault is full.",
	locked = "That row is locked.",
	empty = "That slot is empty.",
	throttled = "Too fast. Wait a moment.",
	invoke_failed = "The bank isn't answering. Try again.",
	no_coins_in_bags = "You carry no coins.",
	empty_wallet = "Your wallet is empty.",
	insufficient_wallet = "Not that many coins in your wallet.",
	insufficient_funds = "Not enough coins.",
	invalid_amount = "Enter a whole number.",
	no_room = "Your bags are full. A coin note needs one free slot.",
	bad_amount = "Enter a whole number.",
}
local function errorText(code: any): string
	return (type(code) == "string" and ERRORS[code]) or "That didn't work."
end

local function slotUuid(slots: any, i: number): string?
	if type(slots) ~= "table" then return nil end
	local v = slots[i] or slots[tostring(i)]
	return (type(v) == "string" and v ~= "") and v or nil
end

local function bagCoins(profile: any): number
	local total = 0
	for _, item in pairs(profile and profile.inventory or {}) do
		if type(item) == "table" and item.itemId == COIN_ITEM then
			total += math.max(0, math.floor(tonumber(item.count) or 1))
		end
	end
	-- Coins inside the coin sacks in your bag slots (the Bank empties those too).
	for i = 1, 30 do
		local uuid = slotUuid(profile and profile.bagSlots, i)
		local item = uuid and profile.inventory and profile.inventory[uuid]
		if type(item) == "table" and ItemDefinitions.GetCoinCapacity(item.itemId) then
			total += math.max(0, math.floor(tonumber(item.coins) or 0))
		end
	end
	return total
end

local function describe(item: any): string
	local rarity = ItemDefinitions.GetRarityForItem(item)
	local count = math.floor(tonumber(item.count) or 1)
	return ItemDefinitions.GetDisplayNameForItem(item)
		.. (count > 1 and (" x" .. count) or "")
		.. (rarity and (", " .. rarity) or "")
end

local function bankRequest(payload: { [string]: any }): any
	local remote = ReplicatedStorage:FindFirstChild("BankRequest")
	if not remote then return { ok = false, err = "invoke_failed" } end
	local ok, res = pcall(function() return (remote :: RemoteFunction):InvokeServer(payload) end)
	if not ok or type(res) ~= "table" then return { ok = false, err = "invoke_failed" } end
	return res
end

-- A grid cell: the item (or an empty / locked socket), click and hover wired.
local function Cell(props: { item: any?, locked: boolean?, order: number, onClick: (() -> ())?, onHover: ((string?) -> ())? })
	local item = props.item
	return e("Frame", { LayoutOrder = props.order, Size = UDim2.fromOffset(CELL, CELL), BackgroundTransparency = 1 }, {
		Slot = e(ItemSlot, {
			item = item, size = CELL,
			onClick = (not props.locked) and props.onClick or nil,
			onHoverStart = item and props.onHover and function() props.onHover(describe(item)) end or nil,
			onHoverEnd = props.onHover and function() props.onHover(nil) end or nil,
		}),
		Lock = props.locked and e("Frame", {
			Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45,
			BorderSizePixel = 0, ZIndex = 10,
		}, { Corner = e("UICorner", { CornerRadius = UDim.new(0, 6) }) }) or nil,
	})
end

local function grid(cells: { [string]: any }, cols: number): { [string]: any }
	cells.Grid = e("UIGridLayout", {
		CellSize = UDim2.fromOffset(CELL, CELL),
		CellPadding = UDim2.fromOffset(GAP, GAP),
		FillDirectionMaxCells = cols,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	return cells
end

local function BankBook(_props: { npcId: string })
	local snapshot = InventoryData.useSnapshot()
	local profile = snapshot and snapshot.profile
	-- The snapshot can lag a successful unlock; never show fewer rows than we know we have.
	local knownRows, setKnownRows = React.useState(1)
	local hovered, setHovered = React.useState(nil :: string?)
	local busy, setBusy = React.useState(false)
	local amount, setAmount = React.useState("")
	local status, statusGood, setStatus = ShopParts.useStatus()

	local unlocked = math.clamp(math.max(math.floor(tonumber(profile and profile.chestUnlockedRows) or 1), knownRows), 1, ROWS)
	local chestInv = profile and profile.chestInventory or {}
	local chestSlots = profile and profile.chestSlots or {}
	local wallet = ShopParts.coins(profile)
	local carried = bagCoins(profile)

	local function act(payload: { [string]: any }, done: string, after: (() -> ())?)
		if busy then return end
		setBusy(true)
		local ok, err = DungeonMenuNet.requestInventoryAct(payload)
		setBusy(false)
		if ok then
			setStatus(done, true)
			if after then after() end
		else
			setStatus(errorText(err), false)
		end
		DungeonMenuNet.requestSync()
	end

	-- The vault.
	local used, firstFree = 0, nil
	local vaultCells: { [string]: any } = {}
	for i = 1, COLS * ROWS do
		local row = math.ceil(i / COLS)
		local uuid = slotUuid(chestSlots, i)
		local item = uuid and chestInv[uuid] or nil
		if item then used += 1 end
		if row <= unlocked and not item and not firstFree then firstFree = i end
		local slotIndex = i
		vaultCells["S" .. i] = e(Cell, {
			item = item, locked = row > unlocked, order = i, onHover = setHovered,
			onClick = item and function()
				act({ kind = "ChestWithdraw", slot = slotIndex }, ItemDefinitions.GetDisplayNameForItem(item) .. " is back in your bags.")
			end or nil,
		})
	end
	local gridH = ROWS * CELL + (ROWS - 1) * GAP
	local nextRow = unlocked < ROWS and unlocked + 1 or nil
	local left = e(ShopParts.Page, {
		heading = "Vault",
		sub = ("%d of %d slots used"):format(used, unlocked * COLS),
		help = "Click an item in your bags to store it here, and click it here to take it back. Unlock more rows with coins.",
		body = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
			Grid = e("Frame", { Size = UDim2.new(1, 0, 0, gridH), BackgroundTransparency = 1 }, grid(vaultCells, COLS)),
			-- "Unlock row N" across the first locked row.
			Unlock = nextRow and e(Parts.ChromeButton, {
				text = ("Unlock row %d, %s"):format(nextRow, ShopParts.priceText(UNLOCK_COST, "Coins")),
				art = "chip", artSelected = "chip_selected",
				selected = wallet >= UNLOCK_COST, disabled = busy or wallet < UNLOCK_COST,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(240, (nextRow - 1) * (CELL + GAP) + CELL / 2),
				Size = UDim2.fromOffset(250, 38), textSize = 15,
				onClick = function()
					act({ kind = "ChestUnlockRow", row = nextRow }, ("Row %d unlocked."):format(nextRow), function()
						setKnownRows(nextRow)
					end)
				end,
			}) or nil,
			Hover = text({
				text = hovered or "", size = 15, color = Style.Text.Body, truncate = true,
				Position = UDim2.fromOffset(0, gridH + 12), Size = UDim2.new(1, 0, 0, 20),
			}),
			Status = text({
				text = status, size = 14, color = statusGood and Style.Text.Good or Style.Text.Bad,
				Position = UDim2.fromOffset(0, gridH + 36), Size = UDim2.new(1, 0, 0, 20),
			}),
		}),
	})

	-- Your bags: what can be stored (coins included; equipped and hotbar items stay put).
	local held: { [string]: boolean } = {}
	for _, uuid in pairs(profile and profile.equipped or {}) do held[uuid] = true end
	for _, uuid in pairs(profile and profile.hotbar or {}) do held[uuid] = true end
	local storable = {}
	for uuid, item in pairs(profile and profile.inventory or {}) do
		if type(uuid) == "string" and type(item) == "table" and not held[uuid] then
			table.insert(storable, { uuid = uuid, item = item })
		end
	end
	table.sort(storable, function(a, b)
		local ta, tb = tostring(a.item.type or ""), tostring(b.item.type or "")
		if ta ~= tb then return ta < tb end
		return ItemDefinitions.GetDisplayNameForItem(a.item) < ItemDefinitions.GetDisplayNameForItem(b.item)
	end)
	local bagCells: { [string]: any } = {}
	for i, entry in ipairs(storable) do
		bagCells[entry.uuid] = e(Cell, {
			item = entry.item, order = i, onHover = setHovered,
			onClick = function()
				if not firstFree then
					setStatus(nextRow and "The vault is full. Unlock another row." or "The vault is full.", false)
					return
				end
				act({ kind = "ChestDeposit", uuid = entry.uuid, slot = firstFree },
					ItemDefinitions.GetDisplayNameForItem(entry.item) .. " is in the vault.")
			end,
		})
	end
	local bagRows = math.max(1, math.ceil(#storable / BAG_COLS))

	local function coinCall(payload: { [string]: any }, done: (any) -> string)
		if busy then return end
		setBusy(true)
		local res = bankRequest(payload)
		setBusy(false)
		if res.ok then
			setStatus(done(res), true)
		else
			setStatus(errorText(res.err), false)
		end
		DungeonMenuNet.requestSync()
	end
	local withdrawAmount = math.floor(tonumber(amount) or 0)

	local right = e(ShopParts.Page, {
		heading = "Your bags",
		sub = "Click an item to store it.",
		body = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
			Bags = e("Frame", { Size = UDim2.new(1, 0, 0, 196), BackgroundTransparency = 1 }, {
				Scroll = #storable > 0 and e("ScrollingFrame", {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					CanvasSize = UDim2.fromOffset(0, bagRows * (CELL + GAP)),
					ScrollBarThickness = 4,
					ScrollBarImageColor3 = Style.Text.Muted,
				}, grid(bagCells, BAG_COLS)) or text({
					text = "Nothing in your bags to store.", size = 16, color = Style.Text.Muted, Size = UDim2.new(1, 0, 0, 60),
				}),
			}),
			Rule = e("Frame", { Position = UDim2.fromOffset(0, 202), Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1 }, {
				Line = e(Parts.Divider, { width = 0.7 }),
			}),
			Wallet = ShopParts.Wallet(wallet, { Position = UDim2.fromOffset(40, 222) }),
			Carried = text({
				text = ("Carrying %s in your bags"):format(ShopParts.priceText(carried, "Coins")),
				size = 14, color = Style.Text.Muted, align = Enum.TextXAlignment.Right,
				AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 226), Size = UDim2.fromOffset(220, 20),
			}),
			Deposit = e(Parts.ChromeButton, {
				text = carried > 0 and ("Deposit " .. ShopParts.priceText(carried, "Coins")) or "Deposit coins",
				art = "chip", artSelected = "chip_selected",
				selected = carried > 0, disabled = busy or carried <= 0,
				AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 256),
				Size = UDim2.fromOffset(300, 40), textSize = 15,
				onClick = function()
					coinCall({ action = "DepositAll" }, function(res)
						return ("Deposited %s."):format(ShopParts.priceText(res.amount or carried, "Coins"))
					end)
				end,
			}),
			Amount = e(ShopParts.Input, {
				placeholder = "Coins to withdraw", numeric = true,
				Position = UDim2.fromOffset(20, 310), Size = UDim2.fromOffset(200, 36),
				onChanged = setAmount,
				onSubmit = function()
					if withdrawAmount > 0 then
						coinCall({ action = "Withdraw", amount = withdrawAmount }, function(res)
							return ("Wrote a coin note for %s. Right-click it in your bags to redeem."):format(ShopParts.priceText(res.amount or withdrawAmount, "Coins"))
						end)
					end
				end,
			}),
			Withdraw = e(Parts.ChromeButton, {
				text = "Withdraw", art = "chip", artSelected = "chip_selected",
				selected = withdrawAmount > 0 and withdrawAmount <= wallet,
				disabled = busy or withdrawAmount <= 0 or withdrawAmount > wallet,
				Position = UDim2.fromOffset(230, 312), Size = UDim2.fromOffset(110, 34), textSize = 15,
				onClick = function()
					coinCall({ action = "Withdraw", amount = withdrawAmount }, function(res)
						return ("Wrote a coin note for %s. Right-click it in your bags to redeem."):format(ShopParts.priceText(res.amount or withdrawAmount, "Coins"))
					end)
				end,
			}),
			All = e(Parts.ChromeButton, {
				text = "All", art = "chip", artSelected = "chip_selected",
				disabled = busy or wallet <= 0,
				Position = UDim2.fromOffset(350, 312), Size = UDim2.fromOffset(90, 34), textSize = 15,
				onClick = function()
					coinCall({ action = "Withdraw", amount = wallet }, function(res)
						return ("Wrote a coin note for %s. Right-click it in your bags to redeem."):format(ShopParts.priceText(res.amount or wallet, "Coins"))
					end)
				end,
			}),
		}),
	})

	return e(Book, { left = left, right = right })
end

return BankBook
