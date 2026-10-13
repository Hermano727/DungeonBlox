--!strict
--  NpcShop/BankBook -- the bank at the Treasure Chest (rebuilt 2026-10-01 from the old
--  1,260-line window; cleaned up 2026-10-12).
--    left   the Vault: one row of pockets per unlocked row (Types.CHEST_GRID_COLUMNS wide). Under
--           them, the NEXT locked row as a single strip with a padlock and its Unlock button
--           (CHEST_ROW_UNLOCK_COIN_COST coins); any rows after that are one quiet line. Then the
--           hovered item's name (in its rarity colour) and the last action's result.
--    right  the Satchel: your bag exactly as it's laid out (bagSlots, Types.BAG_SLOT_COUNT), and
--           the coin ledger: bank vs satchel coins, Deposit, and Withdraw with an amount or All.
--  One click moves an item: a satchel item goes into the first free vault pocket, a vault item
--  back to your satchel. Clicking a coin stack in the satchel deposits your coins instead of
--  filling a vault pocket with them.
--  Slots are drawn like the inventory's bag (a dark pocket washed toward the item's rarity, a thin
--  rarity outline, a slightly smaller icon), at real pixel size, so they pass thin outlines.
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
local BAG_COUNT = Types.BAG_SLOT_COUNT
local BAG_COLS = 6
local CELL, GAP = 42, 5
local BORDER = 2         -- the rarity outline, px (the shop default of 8 swamps a 42 px cell)
local EMPTY_BORDER = 1
local CORNER = 6
local ICON_SCALE = 0.8
local RARITY_WASH = 0.2  -- how far a pocket leans toward its item's rarity colour (as the bag)
local POCKET = Color3.fromRGB(46, 34, 22)
local COIN_ITEM = "Coins"

local ERRORS = {
	equipped = "Unequip it first.",
	not_owned = "That's no longer in your satchel.",
	chest_full = "The vault is full.",
	locked = "That row is locked.",
	empty = "That slot is empty.",
	throttled = "Too fast. Wait a moment.",
	invoke_failed = "The bank isn't answering. Try again.",
	no_coins_in_bags = "You carry no coins.",
	empty_wallet = "Your bank holds no coins.",
	insufficient_wallet = "Not that many coins in the bank.",
	insufficient_funds = "Not enough coins.",
	invalid_amount = "Enter a whole number.",
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
	return total
end

-- "Iron Helm x2" in the item's rarity colour (rich text), for the hover line.
local function describe(item: any): string
	local rarity = ItemDefinitions.GetRarityForItem(item)
	local count = math.floor(tonumber(item.count) or 1)
	local name = ItemDefinitions.GetDisplayNameForItem(item) .. (count > 1 and (" x" .. count) or "")
	if not rarity then return name end
	return ('<font color="#%s">%s</font>  <font color="#%s">%s</font>'):format(
		Types.GetRarityColor(rarity):ToHex(), name, Style.Text.Muted:ToHex(), rarity)
end

local function bankRequest(payload: { [string]: any }): any
	local remote = ReplicatedStorage:FindFirstChild("BankRequest")
	if not remote then return { ok = false, err = "invoke_failed" } end
	local ok, res = pcall(function() return (remote :: RemoteFunction):InvokeServer(payload) end)
	if not ok or type(res) ~= "table" then return { ok = false, err = "invoke_failed" } end
	return res
end

-- One pocket: the dark well (washed toward the item's rarity) with the item on it.
local function Pocket(props: { item: any?, order: number, onClick: (() -> ())?, onHover: ((string?) -> ())? })
	local item = props.item
	local rarity = item and ItemDefinitions.GetRarityForItem(item) or nil
	return e("Frame", {
		LayoutOrder = props.order,
		Size = UDim2.fromOffset(CELL, CELL),
		BackgroundColor3 = rarity and POCKET:Lerp(Types.GetRarityColor(rarity), RARITY_WASH) or POCKET,
		BackgroundTransparency = item and 0.08 or 0.4,
		BorderSizePixel = 0,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0, CORNER) }),
		Slot = e(ItemSlot, {
			item = item, size = CELL,
			borderThickness = BORDER, emptyBorderThickness = EMPTY_BORDER,
			iconScale = ICON_SCALE, cornerRadius = CORNER,
			onClick = props.onClick,
			onHoverStart = item and props.onHover and function() props.onHover(describe(item)) end or nil,
			onHoverEnd = props.onHover and function() props.onHover(nil) end or nil,
		}),
	})
end

local function hList(children: { [string]: any }, padding: number, valign: Enum.VerticalAlignment?): { [string]: any }
	children.Layout = e("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, padding),
		VerticalAlignment = valign or Enum.VerticalAlignment.Center,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	return children
end

local function vList(children: { [string]: any }, padding: number): { [string]: any }
	children.Layout = e("UIListLayout", {
		Padding = UDim.new(0, padding),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	return children
end

local VAULT_W = COLS * CELL + (COLS - 1) * GAP

-- The next locked row: one strip with the row's name and its Unlock button, centred together on
-- it. The button is part of the strip (not laid over locked cells), so nothing sits on top of it.
-- With the art (MenuUI.LOCKED_ROW) the strip is the iron-banded plank with its padlock, drawn
-- STRIP_H tall so the button fits on the plank's face, in three plain pieces: the two ends at
-- their own shape and the middle stretched. (As one 9-sliced image Roblox squashed the plank to
-- the strip's full height and cut the padlock off, 2026-10-12.) Without it, a flat dark strip.
local MenuUI = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images"):WaitForChild("MenuUI"))
local PLANK = MenuUI.LOCKED_ROW
local STRIP_H = 62

local function plankPieces(scale: number): { [string]: any }
	local h = PLANK.Size.Y
	local leftW = PLANK.SliceCenter.Min.X
	local rightX = PLANK.SliceCenter.Max.X
	local rightW = PLANK.Size.X - rightX
	local function piece(x: number, w: number, props: { [string]: any })
		props.BackgroundTransparency = 1
		props.Image = PLANK.Image
		props.ImageRectOffset = Vector2.new(x, 0)
		props.ImageRectSize = Vector2.new(w, h)
		props.ScaleType = Enum.ScaleType.Stretch
		return e("ImageLabel", props)
	end
	return {
		Left = piece(0, leftW, { Size = UDim2.fromOffset(leftW * scale, STRIP_H) }),
		Middle = piece(leftW, rightX - leftW, {
			Position = UDim2.fromOffset(leftW * scale, 0),
			Size = UDim2.new(1, -(leftW + rightW) * scale, 0, STRIP_H),
		}),
		Right = piece(rightX, rightW, {
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromOffset(rightW * scale, STRIP_H),
		}),
	}
end

local function UnlockStrip(props: { row: number, order: number, canPay: boolean, busy: boolean, onUnlock: () -> () })
	local hasPlank = PLANK and PLANK.Image ~= ""
	local scale = STRIP_H / (hasPlank and PLANK.Size.Y or STRIP_H)
	-- The plank's face, where the label and button sit (centred on it, top to bottom too).
	local faceY = hasPlank and PLANK.Plank.Y0 * scale or 0
	local faceH = hasPlank and (PLANK.Plank.Y1 - PLANK.Plank.Y0) * scale or STRIP_H
	local lockArt = (not hasPlank) and Style.Art("lock_icon") or nil
	local children: { [string]: any } = hasPlank and plankPieces(scale) or {
		Corner = e("UICorner", { CornerRadius = UDim.new(0, CORNER) }),
		Edge = e("UIStroke", { Color = Style.Flat.Edge, Transparency = 0.55, Thickness = 1 }),
	}
	children.Face = e("Frame", {
		Position = UDim2.fromOffset(0, faceY), Size = UDim2.new(1, 0, 0, faceH),
		BackgroundTransparency = 1, ZIndex = 2,
	}, hList({
		Lock = lockArt and e("ImageLabel", {
			LayoutOrder = 0, Size = UDim2.fromOffset(18, 22),
			BackgroundTransparency = 1, Image = lockArt.Image, ScaleType = Enum.ScaleType.Fit, ZIndex = 2,
		}) or nil,
		Label = e("TextLabel", {
			LayoutOrder = 1, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, faceH),
			BackgroundTransparency = 1, Text = ("Row %d is locked"):format(props.row),
			FontFace = Style.Font.Chrome, TextSize = 15,
			TextColor3 = hasPlank and Style.Chrome.Label or Style.Text.Muted, ZIndex = 2,
		}),
		Unlock = e(Parts.ChromeButton, {
			LayoutOrder = 2,
			text = props.canPay and ("Unlock for %s"):format(ShopParts.priceText(UNLOCK_COST, "Coins"))
				or ("Needs %s"):format(ShopParts.priceText(UNLOCK_COST, "Coins")),
			art = "chip", artSelected = "chip_selected",
			selected = props.canPay, disabled = props.busy or not props.canPay,
			Size = UDim2.fromOffset(168, math.min(30, faceH - 4)), textSize = 14,
			onClick = props.onUnlock,
		}),
	}, 16))
	return e("Frame", {
		LayoutOrder = props.order,
		Size = UDim2.fromOffset(VAULT_W, STRIP_H),
		BackgroundColor3 = POCKET,
		BackgroundTransparency = hasPlank and 1 or 0.55,
		BorderSizePixel = 0,
	}, children)
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
	local inventory = profile and profile.inventory or {}
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
	local function depositCoins()
		coinCall({ action = "DepositAll" }, function(res)
			return ("Deposited %s."):format(ShopParts.priceText(res.amount or carried, "Coins"))
		end)
	end
	local function withdraw(n: number)
		if n <= 0 then return end
		coinCall({ action = "Withdraw", amount = n }, function(res)
			return ("Withdrew %s."):format(ShopParts.priceText(res.amount or n, "Coins"))
		end)
	end

	-- The vault: unlocked rows of pockets, then the next locked row's strip.
	local used, firstFree = 0, nil
	local rows: { [string]: any } = {}
	for row = 1, unlocked do
		local pockets: { [string]: any } = {}
		for col = 1, COLS do
			local i = (row - 1) * COLS + col
			local uuid = slotUuid(chestSlots, i)
			local item = uuid and chestInv[uuid] or nil
			if item then used += 1 elseif not firstFree then firstFree = i end
			pockets["S" .. col] = e(Pocket, {
				item = item, order = col, onHover = setHovered,
				onClick = item and function()
					act({ kind = "ChestWithdraw", slot = i }, ItemDefinitions.GetDisplayNameForItem(item) .. " is back in your satchel.")
				end or nil,
			})
		end
		rows["Row" .. row] = e("Frame", {
			LayoutOrder = row, Size = UDim2.fromOffset(VAULT_W, CELL), BackgroundTransparency = 1,
		}, hList(pockets, GAP))
	end
	local nextRow = unlocked < ROWS and unlocked + 1 or nil
	if nextRow then
		rows.Unlock = e(UnlockStrip, {
			row = nextRow, order = ROWS + 1, canPay = wallet >= UNLOCK_COST, busy = busy,
			onUnlock = function()
				act({ kind = "ChestUnlockRow", row = nextRow }, ("Row %d unlocked."):format(nextRow), function()
					setKnownRows(nextRow)
				end)
			end,
		})
		local after = ROWS - nextRow
		if after > 0 then
			rows.More = text({
				order = ROWS + 2, text = ("%d more %s after this one"):format(after, after == 1 and "row" or "rows"),
				size = 13, color = Style.Text.Muted, Size = UDim2.fromOffset(VAULT_W, 16),
			})
		end
	end

	local left = e(ShopParts.Page, {
		heading = "Vault",
		sub = ("%d of %d pockets used"):format(used, unlocked * COLS),
		help = "Click an item in your satchel to store it here, and click it here to take it back. Unlock more rows with coins.",
		body = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
			Rows = e("Frame", {
				Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 1, -52), BackgroundTransparency = 1,
			}, vList(rows, GAP)),
			-- What the cursor is on, and what the last click did.
			Hover = text({
				text = hovered or "", rich = true, size = 15, color = Style.Text.Body, truncate = true,
				AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -24), Size = UDim2.new(1, 0, 0, 20),
			}),
			Status = text({
				text = status, size = 14, color = statusGood and Style.Text.Good or Style.Text.Bad,
				AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -2), Size = UDim2.new(1, 0, 0, 20),
			}),
		}),
	})

	-- The satchel, as it's laid out in the inventory (equipped gear and the hotbar stay put).
	local bagSlots = profile and profile.bagSlots or {}
	local satchel: { [string]: any } = {}
	local inSatchel = 0
	for i = 1, BAG_COUNT do
		local uuid = slotUuid(bagSlots, i)
		local item = uuid and inventory[uuid] or nil
		if item then inSatchel += 1 end
		satchel["B" .. i] = e(Pocket, {
			item = item, order = i, onHover = setHovered,
			onClick = item and function()
				if item.itemId == COIN_ITEM then
					depositCoins() -- coins go to the bank, not into a vault pocket
					return
				end
				if not firstFree then
					setStatus(nextRow and "The vault is full. Unlock another row." or "The vault is full.", false)
					return
				end
				act({ kind = "ChestDeposit", uuid = uuid, slot = firstFree },
					ItemDefinitions.GetDisplayNameForItem(item) .. " is in the vault.")
			end or nil,
		})
	end
	satchel.Grid = e("UIGridLayout", {
		CellSize = UDim2.fromOffset(CELL, CELL),
		CellPadding = UDim2.fromOffset(GAP, GAP),
		FillDirectionMaxCells = BAG_COLS,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	local bagRows = math.ceil(BAG_COUNT / BAG_COLS)
	local bagH = bagRows * CELL + (bagRows - 1) * GAP

	local withdrawAmount = math.floor(tonumber(amount) or 0)
	local coinArt = Style.Art("fx_coinfind")
	local ledgerY = bagH + 22

	local right = e(ShopParts.Page, {
		heading = "Satchel",
		sub = ("%d of %d pockets used. Click an item to store it."):format(inSatchel, BAG_COUNT),
		body = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
			Bag = e("Frame", { Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, bagH), BackgroundTransparency = 1 }, satchel),
			Rule = e("Frame", { Position = UDim2.fromOffset(0, bagH + 8), Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1 }, {
				Line = e(Parts.Divider, { width = 0.7 }),
			}),
			-- The ledger: what the bank holds and what you carry.
			Ledger = e("Frame", { Position = UDim2.fromOffset(20, ledgerY), Size = UDim2.new(1, -40, 0, 26), BackgroundTransparency = 1 }, {
				Coin = coinArt and e("ImageLabel", {
					AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromOffset(24, 24),
					BackgroundTransparency = 1, Image = coinArt.Image, ScaleType = Enum.ScaleType.Fit,
				}) or nil,
				Bank = text({
					text = ('In the bank  <font color="#%s"><b>%s</b></font>'):format(Style.Text.Value:ToHex(), ShopParts.commas(wallet)),
					rich = true, size = 15, color = Style.Text.Muted, align = Enum.TextXAlignment.Left,
					Position = UDim2.fromOffset(coinArt and 30 or 0, 0), Size = UDim2.new(0.55, 0, 1, 0),
				}),
				Carried = text({
					text = ('In your satchel  <font color="#%s"><b>%s</b></font>'):format(Style.Text.Value:ToHex(), ShopParts.commas(carried)),
					rich = true, size = 15, color = Style.Text.Muted, align = Enum.TextXAlignment.Right,
					AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.45, 0, 1, 0),
				}),
			}),
			Deposit = e(Parts.ChromeButton, {
				text = carried > 0 and ("Deposit %s"):format(ShopParts.priceText(carried, "Coins")) or "No coins to deposit",
				art = "chip", artSelected = "chip_selected",
				selected = carried > 0, disabled = busy or carried <= 0,
				AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, ledgerY + 32),
				Size = UDim2.fromOffset(300, 34), textSize = 15,
				onClick = depositCoins,
			}),
			-- Withdraw: an amount, or everything.
			Withdraw = e("Frame", {
				AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, ledgerY + 72),
				Size = UDim2.fromOffset(380, 34), BackgroundTransparency = 1,
			}, hList({
				Amount = e(ShopParts.Input, {
					placeholder = "Amount", numeric = true, LayoutOrder = 1,
					Size = UDim2.fromOffset(150, 34),
					onChanged = setAmount,
					onSubmit = function() withdraw(withdrawAmount) end,
				}),
				Take = e(Parts.ChromeButton, {
					text = "Withdraw", art = "chip", artSelected = "chip_selected", LayoutOrder = 2,
					selected = withdrawAmount > 0 and withdrawAmount <= wallet,
					disabled = busy or withdrawAmount <= 0 or withdrawAmount > wallet,
					Size = UDim2.fromOffset(120, 34), textSize = 15,
					onClick = function() withdraw(withdrawAmount) end,
				}),
				All = e(Parts.ChromeButton, {
					text = "All", art = "chip", artSelected = "chip_selected", LayoutOrder = 3,
					disabled = busy or wallet <= 0,
					Size = UDim2.fromOffset(80, 34), textSize = 15,
					onClick = function() withdraw(wallet) end,
				}),
			}, 8)),
		}),
	})

	return e(Book, { left = left, right = right })
end

return BankBook
