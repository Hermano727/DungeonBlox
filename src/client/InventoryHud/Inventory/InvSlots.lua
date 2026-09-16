--!strict
--  InvSlots -- the inventory grid (StarterGui.Inv Slots' FigBloxUI export), wired to real
--  profile.bagSlots/profile.inventory via props from Inventory.lua, with working mouse-wheel
--  scrolling: 30 slots (ProfileTypes.BAG_SLOT_COUNT), 25 visible at once, so
--  the scrollbar thumb only travels a little -- matches the "barely move by default" ask.
--
--  BAG_SLOT_COUNT was 27 (didn't divide evenly into COLS(5): the last row only had 2 real
--  slots, so the other 3 cells there rendered as ordinary-looking empty slots that
--  silently rejected every drop -- read as "3 empty slots that don't accept pickup").
--  Fixed 2026-09-13 by raising BAG_SLOT_COUNT to 30 (an even 5x6) instead of hiding those
--  cells -- the guard below (`slotIndex <= Types.BAG_SLOT_COUNT`) is now just a safety net
--  for if the two ever drift apart again, not something that should normally trigger.
--
--  The raw export had a duplicated row (Frame 39-43 and Frame 44-48 shared
--  identical bounds -- a Figma/plugin export glitch, not a real 6th row) and
--  ~10px of row-to-row jitter (887->1655 is 768px, but 1655->2413 measured
--  758px). Both cleaned up here: exactly 5 wide, uniform 768px row stride.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Types = require(ReplicatedStorage:WaitForChild("ProfileTypes"))
local ItemSlot = require(script.Parent:WaitForChild("ItemSlot"))
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
local e = React.createElement

local DESIGN_W, DESIGN_H = 3997, 3809

local THEME = {
	PanelBg        = Color3.fromRGB(26, 18, 11),
	SlotBg         = Color3.fromRGB(44, 36, 27),
	Scrollbar      = Color3.fromRGB(60, 50, 40),
	ScrollbarThumb = Color3.fromRGB(200, 130, 40),
}

local COLS = 5
local ROWS_VISIBLE = 5
local SLOT_SIZE = 508
local COL_LEFT_START, COL_STRIDE = 127, 753
local ROW_TOP_START, ROW_STRIDE = 119, 768

local ROWS_TOTAL = math.ceil(Types.BAG_SLOT_COUNT / COLS)
local MAX_SCROLL_ROW = math.max(0, ROWS_TOTAL - ROWS_VISIBLE)

--  bagSlots crosses a RemoteEvent on its way from server to client, and Roblox's remote-argument
--  marshalling turns a sparse/mixed-key array into a table whose keys arrive as strings, not
--  numbers -- profile.bagSlots[5] (number) misses entirely even though profile.bagSlots["5"]
--  (string) has the uuid. Same dual-key read the legacy DungeonMenuUI already uses.
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
	-- Hold-drag support (see InventoryMain). onSlotEnter/onSlotLeave fire for EVERY slot,
	-- empty or not -- an empty slot is still a valid drop target -- unlike onHoverStart/
	-- onHoverEnd above, which only fire for the tooltip and so only make sense when occupied.
	onSlotPressStart: (slotIndex: number, uuid: string?, x: number, y: number) -> (),
	onSlotEnter: (slotIndex: number) -> (),
	onSlotLeave: (slotIndex: number) -> (),
}

local function InvSlots(props: InvSlotsProps)
	local scale, setScale = React.useState(1)
	local containerRef = React.useRef(nil :: Frame?)

	React.useEffect(function()
		local container = containerRef.current
		if not container then
			return
		end
		local parent = container.Parent :: GuiObject
		local function recompute()
			local avail = parent.AbsoluteSize
			if avail.X <= 0 or avail.Y <= 0 then
				return
			end
			setScale(math.min(avail.X / DESIGN_W, avail.Y / DESIGN_H) * 0.94)
		end
		recompute()
		local conn = parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(recompute)
		return function()
			conn:Disconnect()
		end
	end, {})

	local scrollRow, setScrollRow = React.useState(0)
	local bagSlots = props.bagSlots or {}
	local inventory = props.inventory or {}

	local slots: { [string]: any } = {}
	for row = 1, ROWS_VISIBLE do
		for col = 1, COLS do
			local slotIndex = (scrollRow + row - 1) * COLS + col
			-- COLS (5) doesn't evenly divide BAG_SLOT_COUNT (27): the last row only has 2 real
			-- slots (26, 27), so slotIndex can run past 27 into cells that map to no real
			-- bagSlots index at all. Rendering those as ordinary-looking empty slot boxes was
			-- the "3 empty slots that don't accept pickup" bug -- they LOOKED empty but weren't
			-- valid drop targets (SetBagSlot/SwapBagSlot reject any index > BAG_SLOT_COUNT). Skip
			-- them entirely so there's no box there to mislead into thinking it's usable space.
			if slotIndex <= Types.BAG_SLOT_COUNT then
				local left = COL_LEFT_START + (col - 1) * COL_STRIDE
				local top = ROW_TOP_START + (row - 1) * ROW_STRIDE
				local uuid = bagSlotUuid(bagSlots, slotIndex)
				local hasUuid = type(uuid) == "string" and uuid ~= ""
				local item = hasUuid and inventory[uuid] or nil
				slots[string.format("Slot%d_%d", row, col)] = e("Frame", {
					Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE),
					Position = UDim2.fromOffset(left, top),
					BackgroundColor3 = THEME.SlotBg,
					BorderSizePixel = 0,
				}, {
					Item = e(ItemSlot, {
						item = item,
						size = SLOT_SIZE,
						selected = props.heldSlotIndex == slotIndex,
						onClick = function()
							props.onSlotClick(slotIndex, hasUuid and uuid or nil)
						end,
						onRightClick = function(x, y)
							if item then
								props.onSlotRightClick(item, x, y)
							end
						end,
						onHoverStart = function(x, y)
							props.onSlotEnter(slotIndex)
							if item then
								props.onHoverStart(item, x, y)
							end
						end,
						onHoverEnd = function()
							props.onSlotLeave(slotIndex)
							props.onHoverEnd()
						end,
						onPressStart = function(x, y)
							props.onSlotPressStart(slotIndex, hasUuid and uuid or nil, x, y)
						end,
					}),
				})
			end
		end
	end

	local thumbFraction = ROWS_VISIBLE / ROWS_TOTAL
	local thumbTravel = MAX_SCROLL_ROW > 0 and (scrollRow / MAX_SCROLL_ROW) or 0

	return e("Frame", {
		ref = containerRef,
		Size = UDim2.fromOffset(DESIGN_W, DESIGN_H),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = THEME.PanelBg,
		BorderSizePixel = 0,
	}, {
		Scale = e("UIScale", { Scale = scale }),

		-- Simple gold outline around the whole panel, same UITheme.Gold used on every
		-- equipment slot box in PlayerPreview -- just a plain border, no ornate frame art.
		Stroke = e("UIStroke", {
			Color = UITheme.Gold,
			Thickness = 8,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),

		Slots = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			[React.Event.MouseWheelForward] = function()
				setScrollRow(function(prev) return math.clamp(prev - 1, 0, MAX_SCROLL_ROW) end)
			end,
			[React.Event.MouseWheelBackward] = function()
				setScrollRow(function(prev) return math.clamp(prev + 1, 0, MAX_SCROLL_ROW) end)
			end,
		}, slots),

		-- Real scrollbar: thumb height = visible/total rows, position tracks scrollRow.
		-- At MVP (30 slots, 25 visible) that's a small ~17% travel range -- "barely moves".
		ScrollTrack = e("Frame", {
			Size = UDim2.fromOffset(48, 3572),
			Position = UDim2.fromOffset(3783, 119),
			BackgroundColor3 = THEME.Scrollbar,
			BorderSizePixel = 0,
		}, {
			Thumb = e("Frame", {
				Size = UDim2.new(1, 0, thumbFraction, 0),
				Position = UDim2.new(0, 0, thumbTravel * (1 - thumbFraction), 0),
				BackgroundColor3 = THEME.ScrollbarThumb,
				BorderSizePixel = 0,
			}),
		}),
	})
end

return InvSlots
