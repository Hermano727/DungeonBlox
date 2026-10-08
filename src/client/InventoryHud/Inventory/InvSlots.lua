--!strict
--  InvSlots -- the Inventory tab's bag (rebuilt 2026-09-30): a parchment page (the Journal's
--  page_paper art) holding all Types.BAG_SLOT_COUNT slots at once, 5 wide, no scrolling, under a
--  "Satchel  N / 30" heading in ink.
--
--  Props are unchanged from the old boxed panel, so InventoryMain's click-to-pick, right-click
--  menu, tooltip and hold-drag wiring all work as before. Every slot (empty ones too) reports
--  enter/leave and carries its index, so empty slots stay drop targets.
--
--  Laid out on a fixed DESIGN canvas in the same large units as before (a 508 px slot), then
--  contain-fit (UIScale): ItemSlot's count text is tuned for that slot size, and the bag passes
--  its own border thickness (BORDER, ~4 px on screen) and icon scale, since the default 8-unit
--  outline vanishes at this scale. PlayerPreview no longer draws square boxes, so there's no
--  second copy of those numbers to keep in step any more.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Types = require(ReplicatedStorage:WaitForChild("ProfileTypes"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local ItemSlot = require(script.Parent:WaitForChild("ItemSlot"))
local Style = require(script.Parent:WaitForChild("Journal"):WaitForChild("Style"))
local Parts = require(script.Parent:WaitForChild("Journal"):WaitForChild("Parts"))
local e = React.createElement

local COLS = 5
local ROWS = math.ceil(Types.BAG_SLOT_COUNT / COLS)
local SLOT = 508
local GAP = 70
local PAD_X, PAD_TOP, PAD_BOTTOM = 230, 320, 230 -- inside the parchment (its border is ornate)
local HEADER_H = 300
-- The heading sits further in than the grid: page_paper's corner ornaments reach about 400
-- units in from each corner, and "Satchel" / "N / 30" used to sit on top of them (2026-10-03).
local HEADER_INSET = 190
-- Rarity readability (2026-10-03): this canvas is contain-fit to ~0.17x, so ItemSlot's default
-- 8-unit outline came out ~1.4 px under an icon filling 92% of the slot. The bag draws a
-- thicker outline (~4 px on screen), a smaller icon, and a faint rarity wash in the pocket.
local BORDER = 22
local ICON_SCALE = 0.8
local RARITY_WASH = 0.2 -- how far the pocket leans toward the item's rarity colour
local GRID_W = COLS * SLOT + (COLS - 1) * GAP
local GRID_H = ROWS * SLOT + (ROWS - 1) * GAP
local DESIGN = Vector2.new(GRID_W + PAD_X * 2, PAD_TOP + HEADER_H + GRID_H + PAD_BOTTOM)

local POCKET = Color3.fromRGB(46, 34, 22) -- the dark well behind each slot, on paper

-- bagSlots arrive from the server as a numeric list or (after a JSON round trip) string keys.
local function bagSlotUuid(bs, i)
	if type(bs) ~= "table" then
		return nil
	end
	local v = bs[i]
	if type(v) == "string" and v ~= "" then
		return v
	end
	v = bs[tostring(i)]
	if type(v) == "string" and v ~= "" then
		return v
	end
	return nil
end

export type InvSlotsProps = {
	bagSlots: { [number]: string }?,
	inventory: { [string]: any }?,
	heldSlotIndex: number?,
	onSlotClick: (slotIndex: number, uuid: string?) -> (),
	onSlotRightClick: (item: any, x: number, y: number) -> (),
	onHoverStart: (item: any, x: number, y: number) -> (),
	onHoverEnd: () -> (),
	onSlotPressStart: (slotIndex: number, uuid: string?, x: number, y: number) -> (),
	onSlotEnter: (slotIndex: number) -> (),
	onSlotLeave: (slotIndex: number) -> (),
}

local function InvSlots(props: InvSlotsProps)
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

	local bagSlots = props.bagSlots or {}
	local inventory = props.inventory or {}

	local used = 0
	local slots: { [string]: any } = {}
	for index = 1, Types.BAG_SLOT_COUNT do
		local row, col = math.floor((index - 1) / COLS), (index - 1) % COLS
		local uuid = bagSlotUuid(bagSlots, index)
		local item = uuid and inventory[uuid] or nil
		if item then used += 1 end
		local rarity = item and ItemDefinitions.GetRarityForItem(item) or nil
		local pocket = rarity and POCKET:Lerp(Types.GetRarityColor(rarity), RARITY_WASH) or POCKET
		slots["Slot" .. index] = e("Frame", {
			Position = UDim2.fromOffset(col * (SLOT + GAP), row * (SLOT + GAP)),
			Size = UDim2.fromOffset(SLOT, SLOT),
			BackgroundColor3 = pocket,
			BackgroundTransparency = item and 0.08 or 0.28,
			BorderSizePixel = 0,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 36) }),
			Item = e(ItemSlot, {
				item = item,
				size = SLOT,
				borderThickness = BORDER,
				iconScale = ICON_SCALE,
				cornerRadius = 36,
				selected = props.heldSlotIndex == index,
				onClick = function()
					props.onSlotClick(index, uuid)
				end,
				onRightClick = function(x, y)
					if item then props.onSlotRightClick(item, x, y) end
				end,
				onHoverStart = function(x, y)
					props.onSlotEnter(index)
					if item then props.onHoverStart(item, x, y) end
				end,
				onHoverEnd = function()
					props.onSlotLeave(index)
					props.onHoverEnd()
				end,
				onPressStart = function(x, y)
					props.onSlotPressStart(index, uuid, x, y)
				end,
			}),
		})
	end

	return e("Frame", {
		ref = hostRef,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		Canvas = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(DESIGN.X, DESIGN.Y),
			BackgroundTransparency = 1,
		}, {
			Scale = e("UIScale", { Scale = scale }),
			Paper = e(Parts.ArtFrame, {
				art = "page_paper",
				flat = { color = Style.Flat.Page, edge = Style.Flat.Edge, edgeTransparency = 0.3, corner = 40 },
				ZIndex = 1,
			}),
			Title = e("TextLabel", {
				Position = UDim2.fromOffset(PAD_X + HEADER_INSET, PAD_TOP),
				Size = UDim2.fromOffset(GRID_W * 0.6 - HEADER_INSET, HEADER_H - 60),
				BackgroundTransparency = 1,
				Text = "Satchel",
				FontFace = Style.Font.Heading,
				TextSize = 170,
				TextColor3 = Style.Text.Heading,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 2,
			}),
			Count = e("TextLabel", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromOffset(PAD_X + GRID_W - HEADER_INSET, PAD_TOP),
				Size = UDim2.fromOffset(GRID_W * 0.4 - HEADER_INSET, HEADER_H - 60),
				BackgroundTransparency = 1,
				Text = ("%d / %d"):format(used, Types.BAG_SLOT_COUNT),
				FontFace = Style.Font.Number,
				TextSize = 140,
				TextColor3 = used >= Types.BAG_SLOT_COUNT and Style.Text.Bad or Style.Text.Body,
				TextXAlignment = Enum.TextXAlignment.Right,
				ZIndex = 2,
			}),
			Rule = e("Frame", {
				Position = UDim2.fromOffset(PAD_X, PAD_TOP + HEADER_H - 50),
				Size = UDim2.fromOffset(GRID_W, 6),
				BackgroundColor3 = Style.Text.Muted,
				BackgroundTransparency = 0.5,
				BorderSizePixel = 0,
				ZIndex = 2,
			}),
			Grid = e("Frame", {
				Position = UDim2.fromOffset(PAD_X, PAD_TOP + HEADER_H),
				Size = UDim2.fromOffset(GRID_W, GRID_H),
				BackgroundTransparency = 1,
				ZIndex = 3,
			}, slots),
		}),
	})
end

return InvSlots
