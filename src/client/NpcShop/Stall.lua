--!strict
--  NpcShop/Stall -- a trader's market stall (2026-10-12), the merchant's window in place of the
--  Journal book. Art: RS/Assets/Images/MerchantUI (timber, brass, striped canvas, twine,
--  parchment; no flowers), every piece with a flat fallback.
--
--    e(Stall, { title, sections, selected, onSelect, coins, filter?, goods, counter, status?,
--               statusGood? })
--      top      a striped awning across the stall, the signboard (title) hanging from it
--      under    the section signs hanging in a row (sections = { { id, label, icon? } }, icon =
--               an image id, or { Image, Offset, Size } for a sheet cell), the coin purse right
--      left     `filter` (an optional row, e.g. Stall.FilterSigns) over `goods` (Stall.Shelves)
--      right    `counter` (Stall.Ledger)
--      bottom   the status line (the last action's result)
--
--    Stall.Shelves({ items, empty?, cols? })   goods standing on shelf planks, each with a
--                    price tag hanging under it. items = { { key, item, name, price,
--                    priceColor?, selected, onSelect } }
--    Stall.Ledger(props)    the counter's card: the item, name, kind, description, lines
--                    ({ label, value, good? }), an optional `controls` row (Stall.QtyStepper),
--                    the total on the ruled line, and the action plank ({ text, disabled, onClick })
--    Stall.FilterSigns({ options, selected, onSelect })   small hanging signs (T1..T5)
--    Stall.QtyStepper({ qty, max, setQty })
--
--  Laid out on a fixed DESIGN canvas, contain-fit (UIScale) into whatever the window gives it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local Types = require(ReplicatedStorage:WaitForChild("ProfileTypes"))
local Images = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images")
local MerchantUI = require(Images:WaitForChild("MerchantUI"))
local MenuUI = require(Images:WaitForChild("MenuUI"))
local JournalUI = require(Images:WaitForChild("JournalUI"))
local Inventory = script.Parent.Parent:WaitForChild("InventoryHud"):WaitForChild("Inventory")
local ItemSlot = require(Inventory:WaitForChild("ItemSlot"))
local Style = require(Inventory:WaitForChild("Journal"):WaitForChild("Style"))
local Parts = require(Inventory:WaitForChild("Journal"):WaitForChild("Parts"))
local ShopParts = require(script.Parent:WaitForChild("ShopParts"))

local e = React.createElement
local text = Parts.Text

local Stall = {}

-- The canvas, and where things sit on it (px).
local DESIGN = Vector2.new(1200, 680)
local AWNING_H = 86
local BOARD_TOP = 40
local SIGN_W, SIGN_TOP = 400, 26
local TABS_Y, TAB_W, TAB_GAP = 146, 150, 12
local CONTENT_Y = 218
local GOODS_X, GOODS_W = 40, 760
local LEDGER_X = 842
local LEDGER_H = 446
local STATUS_H = 22

-- Ink and wood colours (the Journal's: ink on paper, chrome on wood).
local INK = Style.Text
local ON_WOOD = Style.Chrome
local BOARD = Color3.fromRGB(42, 30, 21)
local POCKET = Color3.fromRGB(46, 34, 22)
local BRASS = Color3.fromRGB(240, 213, 138)

local function hasArt(art: any): boolean
	return art ~= nil and type(art.Image) == "string" and art.Image ~= ""
end

-- One cut of a sheet / strip as an ImageLabel.
local function cut(image: string, cell: any, props: { [string]: any }): any
	props.BackgroundTransparency = 1
	props.Image = image
	props.ImageRectOffset = cell.Offset
	props.ImageRectSize = cell.Size
	props.ScaleType = Enum.ScaleType.Stretch
	return e("ImageLabel", props)
end

local function iconElement(icon: any, size: number, props: { [string]: any }): any
	if type(icon) == "table" and icon.Image then
		props.Size = UDim2.fromOffset(size, size)
		props.BackgroundTransparency = 1
		props.Image = icon.Image
		props.ImageRectOffset = icon.Offset
		props.ImageRectSize = icon.Size
		props.ScaleType = Enum.ScaleType.Fit
		return e("ImageLabel", props)
	elseif type(icon) == "string" and icon ~= "" then
		props.Size = UDim2.fromOffset(size, size)
		props.BackgroundTransparency = 1
		props.Image = icon
		props.ScaleType = Enum.ScaleType.Fit
		return e("ImageLabel", props)
	end
	return nil
end

-------------------------------------------------------------------------------------------------
-- The frame pieces

-- The awning: left end, the stripe pair repeated (stretched a touch so a whole number fits),
-- right end. Without the art: a plain green band.
local function Awning(props: { width: number })
	local art = MerchantUI.AWNING
	if not hasArt(art) then
		return e("Frame", {
			Position = UDim2.fromOffset(-10, 0), Size = UDim2.fromOffset(props.width, AWNING_H * 0.7),
			BackgroundColor3 = Color3.fromRGB(58, 85, 48), BorderSizePixel = 0,
		})
	end
	local scale = AWNING_H / art.Size.Y
	local leftW = art.LeftCap.Size.X * scale
	local rightW = art.RightCap.Size.X * scale
	local middleW = props.width - leftW - rightW
	local count = math.max(1, math.floor(middleW / (art.Repeat.Size.X * scale) + 0.5))
	local tileW = middleW / count
	local pieces: { [string]: any } = {
		Left = cut(art.Image, art.LeftCap, { Size = UDim2.fromOffset(leftW, AWNING_H) }),
		Right = cut(art.Image, art.RightCap, {
			Position = UDim2.fromOffset(leftW + middleW, 0), Size = UDim2.fromOffset(rightW, AWNING_H),
		}),
	}
	for i = 1, count do
		pieces["S" .. i] = cut(art.Image, art.Repeat, {
			Position = UDim2.fromOffset(leftW + (i - 1) * tileW, 0), Size = UDim2.fromOffset(tileW + 0.5, AWNING_H),
		})
	end
	return e("Frame", {
		Position = UDim2.fromOffset(-10, 0), Size = UDim2.fromOffset(props.width, AWNING_H),
		BackgroundTransparency = 1, ZIndex = 3,
	}, pieces)
end

-- The signboard hanging from the awning, the shop's name on it.
local function Signboard(props: { title: string })
	local art = MerchantUI.SIGNBOARD
	local h = hasArt(art) and math.floor(SIGN_W * art.Size.Y / art.Size.X + 0.5) or 64
	local face = hasArt(art) and art.Face or nil
	return e("Frame", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, hasArt(art) and SIGN_TOP or 70),
		Size = UDim2.fromOffset(SIGN_W, h), BackgroundColor3 = BOARD, BackgroundTransparency = hasArt(art) and 1 or 0,
		ZIndex = 4,
	}, {
		Board = hasArt(art) and e("ImageLabel", {
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = art.Image, ZIndex = 4,
		}) or nil,
		Title = text({
			text = props.title, font = Style.Font.Heading, size = 30, color = ON_WOOD.Selected, ZIndex = 5,
			Position = face and UDim2.fromScale(face.X0 / art.Size.X, face.Y0 / art.Size.Y) or UDim2.new(),
			Size = face and UDim2.fromScale((face.X1 - face.X0) / art.Size.X, (face.Y1 - face.Y0) / art.Size.Y)
				or UDim2.fromScale(1, 1),
		}),
	})
end

-- A hanging sign (the sections, and smaller ones for filters): its label, an optional icon.
local function HangingSign(props: { label: string, icon: any?, selected: boolean, width: number, textSize: number?,
	order: number?, onClick: () -> () })
	local art = MerchantUI.TAB_SIGNS
	local hovered, setHovered = React.useState(false)
	local cell = hasArt(art) and art.Cells[props.selected and "Selected" or "Normal"] or nil
	local h = cell and math.floor(props.width * cell.Size.Y / cell.Size.X + 0.5) or math.floor(props.width * 0.32)
	local faceY = cell and art.Face.Y0 / cell.Size.Y or 0
	local faceH = cell and (art.Face.Y1 - art.Face.Y0) / cell.Size.Y or 1
	local iconSize = math.floor(h * faceH * 0.62)
	return e("TextButton", {
		LayoutOrder = props.order, Size = UDim2.fromOffset(props.width, h),
		BackgroundColor3 = props.selected and Color3.fromRGB(110, 80, 52) or BOARD,
		BackgroundTransparency = cell and 1 or 0, AutoButtonColor = false, Text = "",
		[React.Event.Activated] = props.onClick,
		[React.Event.MouseEnter] = function() setHovered(true) end,
		[React.Event.MouseLeave] = function() setHovered(false) end,
	}, {
		Sign = cell and cut(art.Image, cell, {
			Size = UDim2.fromScale(1, 1),
			ImageColor3 = (hovered and not props.selected) and Color3.new(1, 1, 1) or Color3.fromRGB(232, 232, 232),
		}) or nil,
		Face = e("Frame", {
			Position = UDim2.fromScale(0, faceY), Size = UDim2.fromScale(1, faceH), BackgroundTransparency = 1, ZIndex = 2,
		}, {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Icon = iconElement(props.icon, iconSize, { LayoutOrder = 1, ZIndex = 2 }),
			Label = e("TextLabel", {
				LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromScale(0, 1),
				BackgroundTransparency = 1, Text = props.label, FontFace = Style.Font.Chrome,
				TextSize = props.textSize or 16,
				TextColor3 = props.selected and ON_WOOD.Selected or (hovered and ON_WOOD.Selected or ON_WOOD.Label),
				ZIndex = 2,
			}),
		}),
	})
end

-- The purse: the coin pouch and what you carry.
local function Purse(props: { coins: number })
	local art = JournalUI.icon_loot_score
	local amount = props.coins == 1 and "1 coin" or (ShopParts.commas(props.coins) .. " coins")
	return e("Frame", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromOffset(DESIGN.X - 40, TABS_Y + 6),
		Size = UDim2.fromOffset(240, 52), BackgroundTransparency = 1, ZIndex = 3,
	}, {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Icon = (type(art) == "table" and art.Image ~= "") and e("ImageLabel", {
			LayoutOrder = 1, Size = UDim2.fromOffset(48, 48), BackgroundTransparency = 1, Image = art.Image,
			ScaleType = Enum.ScaleType.Fit, ZIndex = 3,
		}) or nil,
		Amount = e("TextLabel", {
			LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 40),
			BackgroundTransparency = 1, Text = amount, FontFace = Style.Font.Number, TextSize = 22,
			TextColor3 = ON_WOOD.Selected, ZIndex = 3,
		}),
	})
end

-------------------------------------------------------------------------------------------------
-- Goods on shelves

-- A shelf row: the goods' pocket stands on the plank (its foot tucked behind the plank's lip),
-- the price tag hangs below it, its twine running up behind the plank.
local COL_W = 152
local ROW_H = 142
local SLOT = 66
local POCKET_Y = 8
local PLANK_Y = POCKET_Y + SLOT - 2 -- the plank's top, in a row
local TAG_W = 140

-- One shelf plank across a row: two bracket ends and a stretched middle.
local function ShelfPlank(props: { width: number, y: number })
	local art = MerchantUI.SHELF
	if not hasArt(art) then
		return e("Frame", {
			Position = UDim2.fromOffset(0, props.y), Size = UDim2.fromOffset(props.width, 12),
			BackgroundColor3 = Color3.fromRGB(110, 75, 46), BorderSizePixel = 0, ZIndex = 2,
		})
	end
	local scale = 16 / (art.Plank.Y1 - art.Plank.Y0) -- a 16 px plank
	local h = art.Size.Y * scale
	local capL, capR = art.LeftCap.Size.X * scale, art.RightCap.Size.X * scale
	return e("Frame", {
		Position = UDim2.fromOffset(0, props.y - art.Plank.Y0 * scale), Size = UDim2.fromOffset(props.width, h),
		BackgroundTransparency = 1, ZIndex = 2,
	}, {
		Left = cut(art.Image, art.LeftCap, { Size = UDim2.fromOffset(capL, h), ZIndex = 2 }),
		Middle = cut(art.Image, art.Middle, {
			Position = UDim2.fromOffset(capL, 0), Size = UDim2.new(1, -(capL + capR), 0, h), ZIndex = 2,
		}),
		Right = cut(art.Image, art.RightCap, {
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(capR, h), ZIndex = 2,
		}),
	})
end

-- The price tag under a piece of goods: its name, and the price (or what you get) in ink.
local function PriceTag(props: { name: string, price: string, priceColor: Color3?, y: number })
	local art = MerchantUI.PRICE_TAG
	local h = hasArt(art) and math.floor(TAG_W * art.Size.Y / art.Size.X + 0.5) or 44
	local face = hasArt(art) and art.Face or nil
	local children: { [string]: any } = {
		Name = text({
			text = props.name, font = Style.Font.Heading, size = 12, color = INK.Heading, truncate = true, ZIndex = 4,
			Size = UDim2.fromScale(1, 0.5),
		}),
		Price = text({
			text = props.price, font = Style.Font.BodyBold, size = 13, color = props.priceColor or INK.Value,
			truncate = true, ZIndex = 4, Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromScale(1, 0.5),
		}),
	}
	return e("Frame", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 8, 0, props.y),
		Size = UDim2.fromOffset(TAG_W, h), BackgroundColor3 = Color3.fromRGB(233, 221, 191),
		BackgroundTransparency = hasArt(art) and 1 or 0, ZIndex = 1,
	}, {
		Tag = hasArt(art) and e("ImageLabel", {
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = art.Image, ZIndex = 3,
		}) or nil,
		Face = e("Frame", {
			Position = face and UDim2.fromScale(face.X0 / art.Size.X, face.Y0 / art.Size.Y) or UDim2.new(),
			Size = face and UDim2.fromScale((face.X1 - face.X0) / art.Size.X, (face.Y1 - face.Y0) / art.Size.Y)
				or UDim2.fromScale(1, 1),
			BackgroundTransparency = 1, ZIndex = 4,
		}, children),
	})
end

-- One piece of goods: the pocket with the item (brass ring when selected), its tag below.
local function Goods(props: { entry: any, x: number, y: number })
	local entry = props.entry
	local rarity = entry.item and ItemDefinitions.GetRarityForItem(entry.item) or nil
	local pocket = rarity and POCKET:Lerp(Types.GetRarityColor(rarity), 0.2) or POCKET
	-- The whole spot (pocket and tag) is one button, not just the icon.
	return e("TextButton", {
		Position = UDim2.fromOffset(props.x, props.y), Size = UDim2.fromOffset(COL_W, ROW_H),
		BackgroundTransparency = 1, AutoButtonColor = false, Text = "",
		[React.Event.Activated] = entry.onSelect,
	}, {
		Pocket = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, POCKET_Y),
			Size = UDim2.fromOffset(SLOT, SLOT), BackgroundColor3 = pocket, BackgroundTransparency = 0.1,
			BorderSizePixel = 0, ZIndex = 3,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 7) }),
			Chosen = entry.selected and e("UIStroke", { Color = BRASS, Thickness = 3 }) or nil,
			Slot = e(ItemSlot, {
				item = entry.item, size = SLOT, borderThickness = 2, emptyBorderThickness = 1,
				iconScale = 0.8, cornerRadius = 7, onClick = entry.onSelect,
			}),
		}),
		Tag = e(PriceTag, { name = entry.name, price = entry.price, priceColor = entry.priceColor, y = PLANK_Y + 4 }),
	})
end

function Stall.Shelves(props: { items: { any }, empty: string?, height: number? })
	if #props.items == 0 then
		return text({
			text = props.empty or "Nothing for sale here right now.", size = 17, color = ON_WOOD.Label, wrap = true,
			Size = UDim2.new(1, 0, 0, 80),
		})
	end
	local cols = math.max(1, math.floor(GOODS_W / COL_W))
	local rows = math.ceil(#props.items / cols)
	local children: { [string]: any } = {}
	for r = 1, rows do
		children["Shelf" .. r] = e(ShelfPlank, { width = GOODS_W - 12, y = (r - 1) * ROW_H + PLANK_Y })
	end
	local padX = (GOODS_W - 12 - cols * COL_W) / 2
	for i, entry in ipairs(props.items) do
		local r, c = math.floor((i - 1) / cols), (i - 1) % cols
		children[entry.key or ("G" .. i)] = e(Goods, { entry = entry, x = padX + c * COL_W, y = r * ROW_H })
	end
	return e("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, rows * ROW_H + 8), ScrollBarThickness = 5,
		-- (shelves are siblings drawn over the goods frames: the plank's lip covers each pocket's
		-- foot and the tag's twine)
		ScrollBarImageColor3 = ON_WOOD.Label, ScrollingDirection = Enum.ScrollingDirection.Y,
	}, children)
end

function Stall.FilterSigns(props: { options: { any }, selected: any, onSelect: (any) -> () })
	local children: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Left,
			Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for i, option in ipairs(props.options) do
		children["F" .. i] = e(HangingSign, {
			label = option.label, selected = option.id == props.selected, width = 92, textSize = 14, order = i,
			onClick = function() props.onSelect(option.id) end,
		})
	end
	return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, children)
end

-------------------------------------------------------------------------------------------------
-- The counter

-- A small plate button (the menu kit's wood bar).
local function SmallButton(props: { text: string, width: number, disabled: boolean?, order: number?, onClick: () -> () })
	local bar = MenuUI.BAR
	return e("TextButton", {
		LayoutOrder = props.order, Size = UDim2.fromOffset(props.width, 26), BackgroundColor3 = BOARD,
		BackgroundTransparency = hasArt(bar) and 1 or 0, AutoButtonColor = false, Text = "",
		Active = not props.disabled,
		[React.Event.Activated] = function() if not props.disabled then props.onClick() end end,
	}, {
		Plate = hasArt(bar) and e("ImageLabel", {
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = bar.Image,
			ScaleType = Enum.ScaleType.Slice, SliceCenter = bar.SliceCenter, SliceScale = 0.19,
		}) or nil,
		Label = text({
			text = props.text, font = Style.Font.Chrome, size = 14, ZIndex = 2,
			color = props.disabled and ON_WOOD.Dim or ON_WOOD.Selected, Size = UDim2.fromScale(1, 1),
		}),
	})
end

function Stall.QtyStepper(props: { qty: number, max: number, setQty: (number) -> () })
	local max = math.max(1, props.max)
	return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Less = e(SmallButton, { text = "-", width = 30, order = 1, disabled = props.qty <= 1,
			onClick = function() props.setQty(math.max(1, props.qty - 1)) end }),
		Qty = e("TextLabel", {
			LayoutOrder = 2, Size = UDim2.fromOffset(54, 26), BackgroundTransparency = 1,
			Text = "x" .. props.qty, FontFace = Style.Font.Number, TextSize = 17, TextColor3 = INK.Heading,
		}),
		More = e(SmallButton, { text = "+", width = 30, order = 3, disabled = props.qty >= max,
			onClick = function() props.setQty(math.min(max, props.qty + 1)) end }),
		Max = e(SmallButton, { text = "Max", width = 56, order = 4, disabled = props.qty >= max,
			onClick = function() props.setQty(max) end }),
	})
end

-- The action plank (Buy / Salvage): timber with brass corners; lighter while hovered.
local function ActionPlank(props: { text: string, disabled: boolean?, icon: any?, onClick: () -> () })
	local art = MerchantUI.BUY_BUTTON
	local hovered, setHovered = React.useState(false)
	local cell = hasArt(art) and art.Cells[(hovered and not props.disabled) and "Hover" or "Normal"] or nil
	local w = 236
	local h = cell and math.floor(w * cell.Size.Y / cell.Size.X + 0.5) or 40
	return e("TextButton", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = BOARD, BackgroundTransparency = cell and 1 or 0, AutoButtonColor = false, Text = "",
		Active = not props.disabled,
		[React.Event.Activated] = function() if not props.disabled then props.onClick() end end,
		[React.Event.MouseEnter] = function() setHovered(true) end,
		[React.Event.MouseLeave] = function() setHovered(false) end,
	}, {
		Plank = cell and cut(art.Image, cell, {
			Size = UDim2.fromScale(1, 1), ImageColor3 = props.disabled and Color3.fromRGB(150, 150, 150) or Color3.new(1, 1, 1),
		}) or nil,
		Row = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2 }, {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Icon = iconElement(props.icon, h - 12, { LayoutOrder = 1, ZIndex = 2 }),
			Label = e("TextLabel", {
				LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, h),
				BackgroundTransparency = 1, Text = props.text, FontFace = Style.Font.Chrome, TextSize = 19,
				TextColor3 = props.disabled and ON_WOOD.Dim or ON_WOOD.Selected, ZIndex = 2,
			}),
		}),
	})
end

-- The ledger card on the counter. props: item?, name, nameColor?, kind, body, lines, controls?,
-- total? (the text written on the ruled line), action?, emptyText?
function Stall.Ledger(props: any)
	local art = MerchantUI.LEDGER
	local scale = LEDGER_H / (hasArt(art) and art.Size.Y or LEDGER_H)
	local w = hasArt(art) and math.floor(art.Size.X * scale + 0.5) or 322
	local function y(px: number): number return px * scale end
	local top = hasArt(art) and y(art.PaperTop) + 22 or 18
	local rule1 = hasArt(art) and y(art.Rules[1]) or LEDGER_H - 70
	local children: { [string]: any } = {
		Card = hasArt(art) and e("ImageLabel", {
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = art.Image,
		}) or nil,
	}
	if not props.item then
		children.Empty = text({
			text = props.emptyText or "Pick something off the shelves.", size = 16, color = INK.Muted, wrap = true,
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.new(0.75, 0, 0, 60),
			ZIndex = 2,
		})
	else
		local lines: { [string]: any } = {
			Layout = e("UIListLayout", { Padding = UDim.new(0, 0), SortOrder = Enum.SortOrder.LayoutOrder }),
		}
		for i, line in ipairs(props.lines or {}) do
			lines["L" .. i] = e("Frame", { LayoutOrder = i, Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1 }, {
				Label = text({ text = line[1], size = 14, color = INK.Muted, align = Enum.TextXAlignment.Left,
					Size = UDim2.fromScale(0.5, 1), ZIndex = 2 }),
				Value = text({ text = line[2], font = Style.Font.BodyBold, size = 14,
					color = line[3] == false and INK.Bad or (line[3] == true and INK.Good or INK.Value),
					align = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0),
					Size = UDim2.fromScale(0.5, 1), ZIndex = 2 }),
			})
		end
		children.Slot = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, top),
			Size = UDim2.fromOffset(72, 72), BackgroundTransparency = 1, ZIndex = 2,
		}, { Item = e(ItemSlot, { item = props.item, size = 72, borderThickness = 3, iconScale = 0.85, cornerRadius = 8 }) })
		children.Name = text({
			text = props.name, font = Style.Font.Heading, size = 19, color = props.nameColor or INK.Heading, truncate = true,
			Position = UDim2.fromOffset(18, top + 76), Size = UDim2.new(1, -36, 0, 24), ZIndex = 2,
		})
		children.Kind = text({
			text = props.kind or "", size = 13, color = INK.Muted,
			Position = UDim2.fromOffset(18, top + 100), Size = UDim2.new(1, -36, 0, 16), ZIndex = 2,
		})
		children.Body = text({
			text = props.body or "", size = 13, color = INK.Body, wrap = true, alignY = Enum.TextYAlignment.Top,
			Position = UDim2.fromOffset(26, top + 122), Size = UDim2.new(1, -52, 0, 50), ZIndex = 2,
		})
		children.Lines = e("Frame", {
			Position = UDim2.fromOffset(30, top + 176), Size = UDim2.new(1, -60, 0, 64), BackgroundTransparency = 1, ZIndex = 2,
		}, lines)
		children.Controls = props.controls and e("Frame", {
			Position = UDim2.fromOffset(20, rule1 - 62), Size = UDim2.new(1, -40, 0, 28), BackgroundTransparency = 1, ZIndex = 2,
		}, { Row = props.controls }) or nil
		-- The total, written on the first ruled line like a sum on a bill.
		children.Total = props.total and text({
			text = props.total, rich = true, font = Style.Font.Heading, size = 16, color = INK.Heading,
			AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromOffset(30, rule1 - 1), Size = UDim2.new(1, -60, 0, 22),
			ZIndex = 2,
		}) or nil
		children.Action = props.action and e("Frame", {
			Position = UDim2.fromOffset(0, rule1 + 8), Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, ZIndex = 2,
		}, { Plank = e(ActionPlank, props.action) }) or nil
	end
	return e("Frame", {
		Size = UDim2.fromOffset(w, LEDGER_H), BackgroundColor3 = Color3.fromRGB(233, 221, 191),
		BackgroundTransparency = hasArt(art) and 1 or 0,
	}, children)
end

-------------------------------------------------------------------------------------------------
-- The stall

function Stall.Stall(props: any)
	local scale, setScale = React.useState(1)
	local hostRef = React.useRef(nil :: Frame?)
	React.useEffect(function()
		local host = hostRef.current
		if not host then return end
		local function fit()
			local avail = host.AbsoluteSize
			if avail.X <= 0 or avail.Y <= 0 then return end
			setScale(math.min(avail.X / DESIGN.X, avail.Y / DESIGN.Y))
		end
		fit()
		local conn = host:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		return function() conn:Disconnect() end
	end, {})

	local signs: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, TAB_GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for i, section in ipairs(props.sections) do
		signs[section.id] = e(HangingSign, {
			label = section.label, icon = section.icon, selected = section.id == props.selected, width = TAB_W,
			order = i, onClick = function() props.onSelect(section.id) end,
		})
	end
	local bar = MenuUI.BAR
	local filterH = props.filter and 44 or 0

	return e("Frame", { ref = hostRef, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
		Canvas = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(DESIGN.X, DESIGN.Y), BackgroundTransparency = 1,
		}, {
			Scale = e("UIScale", { Scale = scale }),
			-- The stall's dark timber backboard with its gold rim (the menu kit's plate).
			Board = e("Frame", {
				Position = UDim2.fromOffset(0, BOARD_TOP), Size = UDim2.fromOffset(DESIGN.X, DESIGN.Y - BOARD_TOP),
				BackgroundColor3 = BOARD, BackgroundTransparency = hasArt(bar) and 1 or 0, BorderSizePixel = 0,
			}, {
				Plate = hasArt(bar) and e("ImageLabel", {
					Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = bar.Image,
					ScaleType = Enum.ScaleType.Slice, SliceCenter = bar.SliceCenter, SliceScale = 0.6,
				}) or nil,
			}),
			Awning = e(Awning, { width = DESIGN.X + 20 }),
			Sign = e(Signboard, { title = props.title }),
			Signs = e("Frame", {
				Position = UDim2.fromOffset(GOODS_X, TABS_Y), Size = UDim2.fromOffset(700, 70), BackgroundTransparency = 1, ZIndex = 3,
			}, signs),
			Purse = e(Purse, { coins = props.coins or 0 }),
			Filter = props.filter and e("Frame", {
				Position = UDim2.fromOffset(GOODS_X, CONTENT_Y), Size = UDim2.fromOffset(GOODS_W, filterH - 6),
				BackgroundTransparency = 1, ZIndex = 3,
			}, { Row = props.filter }) or nil,
			Goods = e("Frame", {
				Position = UDim2.fromOffset(GOODS_X, CONTENT_Y + filterH),
				Size = UDim2.fromOffset(GOODS_W, DESIGN.Y - CONTENT_Y - filterH - STATUS_H - 20),
				BackgroundTransparency = 1, ZIndex = 2,
			}, { Shelves = props.goods }),
			Status = text({
				text = props.status or "", size = 15, color = props.statusGood and Color3.fromRGB(150, 196, 120) or Color3.fromRGB(226, 120, 100),
				align = Enum.TextXAlignment.Left, ZIndex = 3,
				Position = UDim2.fromOffset(GOODS_X + 6, DESIGN.Y - STATUS_H - 14), Size = UDim2.fromOffset(GOODS_W, STATUS_H),
			}),
			Counter = e("Frame", {
				Position = UDim2.fromOffset(LEDGER_X, CONTENT_Y - 6), Size = UDim2.fromOffset(DESIGN.X - LEDGER_X - 30, LEDGER_H),
				BackgroundTransparency = 1, ZIndex = 3,
			}, { Ledger = props.counter }),
		}),
	})
end

return Stall
