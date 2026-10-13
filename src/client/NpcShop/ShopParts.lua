--!strict
--  NpcShop/ShopParts -- the pieces every NPC shop book is made of (Merchant, Blacksmith, the
--  Animal Trainer's stable). All drawn from the Journal kit (Journal/Style, Parts) and the
--  bag's ItemSlot, so a shop reads as a page of the same book as the Journal.
--
--    ShopParts.Page(props)         a page frame: heading, a muted line under it, a divider, and
--                                  a body that fills the rest (a list or a detail)
--    ShopParts.ItemRow(props)      one list row: the item in its slot, name, a second line
--    ShopParts.Detail(props)       the right page: the selected item large, its text, info lines,
--                                  one action button, a status line, the wallet at the bottom
--    ShopParts.Wallet(coins)       coin icon + amount
--    ShopParts.countOf(profile, itemId), ShopParts.priceText(price, currency),
--    ShopParts.request(npcId, payload) -> ok, res, ShopParts.errorText(code)
--
--  Every page lays out on the Journal's PAGE_DESIGN canvas (480 x 440), scaled by Journal/Book.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local Types = require(ReplicatedStorage:WaitForChild("ProfileTypes"))

local Inventory = script.Parent.Parent:WaitForChild("InventoryHud"):WaitForChild("Inventory")
local ItemSlot = require(Inventory:WaitForChild("ItemSlot"))
local Journal = Inventory:WaitForChild("Journal")
local Style = require(Journal:WaitForChild("Style"))
local Parts = require(Journal:WaitForChild("Parts"))

local e = React.createElement
local text = Parts.Text

local ShopParts = {}

local ROW_H = 64
local ROW_SLOT = 52
local HEAD_H = 74 -- heading + sub line + divider, above a page's body

local ERRORS = {
	insufficient_funds = "Not enough coins or materials.",
	insufficient_items = "You don't have enough to swap.",
	receive_failed     = "Your bags are full.",
	bad_trade_index    = "That swap isn't offered.",
	not_in_catalog     = "That isn't sold here.",
	no_profile         = "Still loading. Try again.",
	throttled          = "Too fast. Wait a moment.",
	remove_failed      = "Couldn't take the payment from your bags.",
	grant_failed       = "Your bags are full.",
	not_salvageable    = "Only unequipped weapons or armor can be salvaged.",
	equipped           = "Unequip it first.",
	in_raid            = "Not during a dungeon run.",
	not_owned          = "That's no longer in your bags.",
	bad_item_uuid      = "Couldn't find that item. Reopen the shop.",
	bad_uuid           = "Couldn't find that item. Reopen the shop.",
	salvage_failed     = "Salvage failed. Try again.",
	unknown_item       = "That can't be salvaged.",
	action_not_allowed = "This shop can't do that.",
	npc_not_found      = "Step closer and reopen the shop.",
	too_far            = "You're too far away.",
	not_stackable      = "Your bags are full.",
	merge_failed       = "Your bags are full.",
	server_error       = "Something went wrong. Try again.",
	bad_request        = "Something went wrong. Try again.",
	unavailable        = "The shop isn't answering. Try again.",
}

function ShopParts.errorText(code: any): string
	return (type(code) == "string" and ERRORS[code]) or "That didn't work."
end

-- NPCRequest (GameEvents) round trip. ok is the server's `ok`; res is the whole reply.
function ShopParts.request(npcId: string, payload: { [string]: any }): (boolean, any)
	local events = ReplicatedStorage:FindFirstChild("GameEvents")
	local remote = events and events:FindFirstChild("NPCRequest")
	if not remote then return false, { err = "unavailable" } end
	payload.npcId = npcId
	local ok, res = pcall(function() return (remote :: RemoteFunction):InvokeServer(payload) end)
	if not ok or type(res) ~= "table" then return false, { err = "unavailable" } end
	return res.ok == true, res
end

function ShopParts.coins(profile: any): number
	return math.floor(tonumber(profile and profile.currencies and profile.currencies.Coins) or 0)
end

-- How many of a stackable item the player holds (what a barter price is paid in).
function ShopParts.countOf(profile: any, itemId: string): number
	if itemId == "Coins" then return ShopParts.coins(profile) end
	local total = 0
	for _, item in pairs(profile and profile.inventory or {}) do
		if type(item) == "table" and item.itemId == itemId then
			total += math.floor(tonumber(item.count) or 1)
		end
	end
	return total
end

function ShopParts.displayName(itemId: string): string
	local def = ItemDefinitions.Get(itemId)
	return def and def.DisplayName or itemId
end

-- 12345 -> "12,345"
function ShopParts.commas(n: number): string
	local digits = tostring(math.floor(n))
	local out = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""):gsub("^%-,", "-"))
end

function ShopParts.priceText(price: number, currency: string): string
	if price <= 0 then return "Free" end
	if currency == "Coins" then return price == 1 and "1 coin" or (ShopParts.commas(price) .. " coins") end
	return ShopParts.commas(price) .. " " .. ShopParts.displayName(currency)
end

-- The catalog entry as an item record ItemSlot can draw (icon, rarity, bundle count).
function ShopParts.catalogItem(entry: any): any
	return { itemId = entry.ItemId, count = entry.Qty or 1 }
end

function ShopParts.rarityColor(item: any): Color3
	local rarity = ItemDefinitions.GetRarityForItem(item)
	return rarity and Types.GetRarityColor(rarity) or Style.Text.Heading
end

function ShopParts.Wallet(coins: number, props: { Position: UDim2?, AnchorPoint: Vector2? }?)
	local coinArt = Style.Art("fx_coinfind")
	return e("Frame", {
		Position = props and props.Position,
		AnchorPoint = props and props.AnchorPoint,
		Size = UDim2.fromOffset(220, 26),
		BackgroundTransparency = 1,
	}, {
		Coin = coinArt and e("ImageLabel", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(24, 24),
			BackgroundTransparency = 1,
			Image = coinArt.Image,
			ScaleType = Enum.ScaleType.Fit,
		}) or nil,
		Amount = text({
			text = (coins == 1 and "1 coin" or (ShopParts.commas(coins) .. " coins")),
			font = Style.Font.Number, size = 17, color = Style.Text.Value,
			align = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(coinArt and 30 or 0, 0), Size = UDim2.new(1, -30, 1, 0),
		}),
	})
end

-- A page: heading, a muted line, a divider, then `body` filling the rest.
function ShopParts.Page(props: { heading: string, sub: string?, body: any, help: string? })
	return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
		Heading = e(Parts.Heading, { text = props.heading, size = 26, height = 34 }),
		Help = props.help and e(Parts.HelpIcon, {
			text = props.help, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 6),
		}) or nil,
		Sub = text({
			text = props.sub or "", size = 14, color = Style.Text.Muted,
			Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 0, 20),
		}),
		Rule = e("Frame", { Position = UDim2.fromOffset(0, 56), Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1 }, {
			Line = e(Parts.Divider, { width = 1 }),
		}),
		Body = e("Frame", {
			Position = UDim2.fromOffset(0, HEAD_H),
			Size = UDim2.new(1, 0, 1, -HEAD_H),
			BackgroundTransparency = 1,
		}, { Content = props.body }),
	})
end

-- A scrolling list of rows (children keyed however the caller likes), or `empty` text.
function ShopParts.List(rows: { [string]: any }, empty: string?)
	if next(rows) == nil then
		return text({ text = empty or "Nothing here.", size = 16, color = Style.Text.Muted, wrap = true, Size = UDim2.new(1, 0, 0, 60) })
	end
	rows.Layout = e("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder })
	return e("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Style.Text.Muted,
	}, rows)
end

-- props: item (record for ItemSlot), name, nameColor?, sub, subColor?, selected, order,
-- onSelect, right? (an element on the row's right end, e.g. a durability bar) + rightRoom
-- (px the text leaves free for it)
function ShopParts.ItemRow(props: any)
	local textW = -(ROW_SLOT + 24 + (props.rightRoom or 0))
	return e("TextButton", {
		LayoutOrder = props.order,
		Size = UDim2.new(1, -6, 0, ROW_H),
		BackgroundColor3 = Style.Text.Muted,
		BackgroundTransparency = props.selected and 0.82 or 1,
		AutoButtonColor = false,
		Text = "",
		[React.Event.Activated] = props.onSelect,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Slot = e("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 4, 0.5, 0),
			Size = UDim2.fromOffset(ROW_SLOT, ROW_SLOT),
			BackgroundTransparency = 1,
		}, {
			Item = e(ItemSlot, { item = props.item, size = ROW_SLOT, onClick = props.onSelect }),
		}),
		Name = text({
			text = props.name, font = Style.Font.Heading, size = 17,
			color = props.nameColor or Style.Text.Heading, truncate = true,
			align = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(ROW_SLOT + 16, 9), Size = UDim2.new(1, textW, 0, 22),
		}),
		Sub = text({
			text = props.sub or "", size = 14, color = props.subColor or Style.Text.Muted, truncate = true,
			align = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(ROW_SLOT + 16, 33), Size = UDim2.new(1, textW, 0, 20),
		}),
		Right = props.right,
		Rule = e("Frame", {
			AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Style.Text.Muted, BackgroundTransparency = 0.8, BorderSizePixel = 0,
		}),
	})
end

-- The right page. props: item (or nil for an empty page), name, nameColor?, kind (the line
-- under the name), body (description; bodySize? for longer text), lines ({ { label, value,
-- good? } }) OR controls (an element in the same 70 px slot, e.g. a price box), action ({ text,
-- disabled?, onClick }), status, statusGood?, coins, emptyText?
function ShopParts.Detail(props: any)
	if not props.item then
		return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
			Empty = text({
				text = props.emptyText or "Pick something on the left.", size = 16, color = Style.Text.Muted, wrap = true,
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.new(0.8, 0, 0, 60),
			}),
			Wallet = props.coins and ShopParts.Wallet(props.coins, {
				AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 40, 1, 0),
			}) or nil,
		})
	end
	local lines: { [string]: any } = {
		Layout = e("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
	}
	for i, line in ipairs(props.lines or {}) do
		lines["L" .. i] = e("Frame", { LayoutOrder = i, Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1 }, {
			Label = text({
				text = line[1], size = 15, color = Style.Text.Muted, align = Enum.TextXAlignment.Left,
				Size = UDim2.fromScale(0.5, 1),
			}),
			Value = text({
				text = line[2], font = Style.Font.BodyBold, size = 15,
				color = line[3] == false and Style.Text.Bad or (line[3] == true and Style.Text.Good or Style.Text.Value),
				align = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0),
				Size = UDim2.fromScale(0.5, 1),
			}),
		})
	end
	local action = props.action
	return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
		Slot = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromOffset(96, 96),
			BackgroundTransparency = 1,
		}, { Item = e(ItemSlot, { item = props.item, size = 96 }) }),
		Name = text({
			text = props.name, font = Style.Font.Heading, size = 22, color = props.nameColor or Style.Text.Heading,
			truncate = true, Position = UDim2.fromOffset(0, 104), Size = UDim2.new(1, 0, 0, 30),
		}),
		Kind = text({
			text = props.kind or "", size = 14, color = Style.Text.Muted,
			Position = UDim2.fromOffset(0, 134), Size = UDim2.new(1, 0, 0, 18),
		}),
		Rule = e("Frame", { Position = UDim2.fromOffset(0, 156), Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1 }, {
			Line = e(Parts.Divider, { width = 0.7 }),
		}),
		Body = text({
			text = props.body or "", size = props.bodySize or 15, color = Style.Text.Body, wrap = true,
			alignY = Enum.TextYAlignment.Top,
			Position = UDim2.fromOffset(10, 176), Size = UDim2.new(1, -20, 0, 66),
		}),
		Lines = e("Frame", {
			Position = UDim2.fromOffset(40, 246), Size = UDim2.new(1, -80, 0, 70), BackgroundTransparency = 1,
		}, props.controls and { Controls = props.controls } or lines),
		Action = action and e(Parts.ChromeButton, {
			text = action.text, art = "chip", artSelected = "chip_selected",
			selected = not action.disabled, disabled = action.disabled,
			AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 324),
			Size = UDim2.fromOffset(260, 44), textSize = 17,
			onClick = action.onClick,
		}) or nil,
		Status = text({
			text = props.status or "", size = 14, color = props.statusGood and Style.Text.Good or Style.Text.Bad,
			Position = UDim2.fromOffset(0, 372), Size = UDim2.new(1, 0, 0, 20),
		}),
		Wallet = props.coins and ShopParts.Wallet(props.coins, {
			AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 40, 1, 0),
		}) or nil,
	})
end

-- A text box on the page (a dark trough with a bronze edge). Uncontrolled: `initial` is only
-- the starting text; onChanged(text) fires as you type, onSubmit(text) on Enter.
function ShopParts.Input(props: any)
	return e("Frame", {
		Position = props.Position, AnchorPoint = props.AnchorPoint, Size = props.Size,
		BackgroundColor3 = Style.Flat.Trough, BackgroundTransparency = 0.1, BorderSizePixel = 0,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0, 5) }),
		Edge = e("UIStroke", { Color = Style.Flat.Edge, Transparency = 0.45, Thickness = 1 }),
		Box = e("TextBox", {
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(1, -20, 1, 0),
			BackgroundTransparency = 1,
			ClearTextOnFocus = false,
			Text = props.initial or "",
			PlaceholderText = props.placeholder or "",
			PlaceholderColor3 = Style.Chrome.Dim,
			FontFace = Style.Font.Body,
			TextSize = props.textSize or 16,
			TextColor3 = Style.Chrome.Selected,
			TextXAlignment = Enum.TextXAlignment.Left,
			[React.Change.Text] = function(box: TextBox)
				local value = box.Text
				if props.numeric then
					local digits = value:gsub("%D", "")
					if digits ~= value then box.Text = digits; return end
				end
				if props.onChanged then props.onChanged(value) end
			end,
			[React.Event.FocusLost] = function(box: TextBox, enterPressed: boolean)
				if enterPressed and props.onSubmit then props.onSubmit(box.Text) end
			end,
		}),
	})
end

-- A row of chips: options = { { id, label } }, selected = id, onSelect(id).
function ShopParts.Chips(props: { options: { any }, selected: any, onSelect: (any) -> (), width: number?, height: number?,
	Position: UDim2?, AnchorPoint: Vector2?, Size: UDim2?, align: Enum.HorizontalAlignment? })
	local children: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = props.align or Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for i, option in ipairs(props.options) do
		children["C" .. i] = e(Parts.ChromeButton, {
			text = option.label, selected = option.id == props.selected,
			art = "chip", artSelected = "chip_selected",
			Size = UDim2.fromOffset(props.width or 96, props.height or 30), LayoutOrder = i, textSize = 14,
			onClick = function() props.onSelect(option.id) end,
		})
	end
	return e("Frame", {
		Position = props.Position, AnchorPoint = props.AnchorPoint,
		Size = props.Size or UDim2.new(1, 0, 0, props.height or 30), BackgroundTransparency = 1,
	}, children)
end

-- Bookmark tabs for a Book's top edge: options = { { id, label } }, selected, onSelect(id).
function ShopParts.BookTabs(props: { options: { any }, selected: any, onSelect: (any) -> (), width: number? })
	local tabs: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for i, option in ipairs(props.options) do
		tabs["T" .. i] = e(Parts.ChromeButton, {
			text = option.label, selected = option.id == props.selected,
			art = "bookmark_tab", artSelected = "bookmark_tab_active",
			Size = UDim2.fromOffset(props.width or 96, Style.TAB_H), LayoutOrder = i, textSize = 16,
			onClick = function() props.onSelect(option.id) end,
		})
	end
	return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, tabs)
end

-- A status line that clears itself after a few seconds: status, good, set(text, good).
function ShopParts.useStatus(): (string, boolean, (string, boolean) -> ())
	local state, setState = React.useState({ text = "", good = false, n = 0 })
	local function set(msg: string, good: boolean)
		setState(function(prev) return { text = msg, good = good, n = prev.n + 1 } end)
	end
	React.useEffect(function()
		if state.text == "" then return end
		local alive = true
		task.delay(3, function()
			if alive then setState(function(prev) return prev.n == state.n and { text = "", good = false, n = prev.n } or prev end) end
		end)
		return function() alive = false end
	end, { state.n })
	return state.text, state.good, set
end

return ShopParts
