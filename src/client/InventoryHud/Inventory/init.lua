--!strict
--  Inventory -- the root component combining the three FigBloxUI pieces
--  (Player Preview / Inv Slots / quick nav) plus the four icon-triggered
--  sub-panels. Everything lives under this ONE component (per request), and
--  navigation is a small stack: {"inventory"} is the base; opening a
--  sub-panel pushes its name on top (hiding the main layout), and that
--  panel's X pops back to "inventory". Tab/Escape (handled by the mount
--  script, InventoryHud) closes the whole thing and -- via resetKey below --
--  resets the stack back to "inventory" for next time it's opened.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local e = React.createElement

local PlayerPreview    = require(script:WaitForChild("PlayerPreview"))
local InvSlots         = require(script:WaitForChild("InvSlots"))
local QuickNav         = require(script:WaitForChild("QuickNav"))
local TitleBanner      = require(script:WaitForChild("TitleBanner"))
local SkillsPanel      = require(script:WaitForChild("SkillsPanel"))
local StatsPanel       = require(script:WaitForChild("StatsPanel"))
local HearthstonePanel = require(script:WaitForChild("HearthstonePanel"))
local PartyPanel       = require(script:WaitForChild("PartyPanel"))
local InventoryData    = require(script:WaitForChild("InventoryData"))
local ContextMenu      = require(script:WaitForChild("ContextMenu"))
local Tooltip          = require(script:WaitForChild("Tooltip"))

local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local Types = require(ReplicatedStorage:WaitForChild("DungeonProfileTypes"))
local DungeonMenuNet = require(script.Parent.Parent:WaitForChild("DungeonMenuNet"))

--  displayName -- shared label used by both the equip-panel item labels and
--  the right-click context menu text ("Equip X" / "Swap equipped Y for this X?").
local function displayName(item)
	if type(item) ~= "table" then
		return ""
	end
	if type(item.name) == "string" and item.name ~= "" then
		return item.name
	end
	if type(item.itemId) == "string" then
		local def = ItemDefinitions.Get(item.itemId)
		if def and type(def.DisplayName) == "string" then
			return def.DisplayName
		end
		return item.itemId
	end
	return "Item"
end

local PANELS: { [string]: any } = {
	skills = SkillsPanel,
	stats = StatsPanel,
	hearthstone = HearthstonePanel,
	party = PartyPanel,
}

local QUICKNAV_H = 110
local GAP = 20 -- a bit more breathing room than the raw Figma export had
local COLUMN_GAP = 10 -- tighter gap between the preview and slots columns specifically, per request
local BANNER_H_GUESS = 150 -- corrected on mount via TitleBanner's onMeasured once its real
                            -- (aspect-locked, width-driven) height is known -- see InventoryMain

local function InventoryMain(props: { onSelect: (string) -> () })
	local snapshot = InventoryData.useSnapshot()
	local profile = snapshot and snapshot.profile
	local inventory = (profile and profile.inventory) or {}
	local bagSlots = (profile and profile.bagSlots) or {}
	local equipped = (profile and profile.equipped) or {}

	local held, setHeld = React.useState(nil :: { uuid: string, slotIndex: number }?)
	local contextMenu, setContextMenu = React.useState(nil :: { key: string, position: Vector2, options: { any } }?)
	local hover, setHover = React.useState(nil :: { item: any, position: Vector2 }?)
	local bannerHeight, setBannerHeight = React.useState(BANNER_H_GUESS)

	local function dismissContextMenu()
		setContextMenu(nil)
	end

	--  Bag click: first click on an occupied slot picks it up ("held"); a second
	--  click (on the same slot) puts it back down; a click on any other slot
	--  (occupied or empty) swaps held <-> target via the existing SwapBagSlot act.
	--  This is a click-to-pick/click-to-place substitute for full cursor-follow
	--  drag-and-drop -- a pragmatic first pass, not the final interaction model.
	local function onBagSlotClick(slotIndex: number, uuid: string?)
		if held then
			if held.slotIndex == slotIndex then
				setHeld(nil)
				return
			end
			DungeonMenuNet.requestInventoryAct({ kind = "SwapBagSlot", a = held.slotIndex, b = slotIndex })
			setHeld(nil)
			return
		end
		if uuid then
			setHeld({ uuid = uuid, slotIndex = slotIndex })
		end
	end

	--  Equip-panel click: only meaningful while something is held and it's a
	--  legal fit for that slot (mirrors server-side GetAllowedEquipSlot).
	local function onEquipSlotClick(slotName: string)
		if not held then
			return
		end
		local item = inventory[held.uuid]
		if item and Types.GetAllowedEquipSlot(item) == slotName then
			DungeonMenuNet.requestEquip(held.uuid)
			setHeld(nil)
		end
	end

	--  Bag right-click: first pass only offers Equip / Swap for that item's own
	--  slot, per spec ("Equip Helmet" / "Swap equipped X for this Y?").
	local function onBagSlotRightClick(item: any, x: number, y: number)
		if type(item) ~= "table" then
			return
		end
		-- A second right-click on the same item (while its menu is already open) collapses it
		-- instead of reopening -- a toggle, not a re-fire.
		local key = "bag:" .. tostring(item.uuid)
		if contextMenu and contextMenu.key == key then
			dismissContextMenu()
			return
		end
		local slotName = Types.GetAllowedEquipSlot(item)
		if not slotName then
			return
		end
		local currentUuid = equipped[slotName]
		local currentItem = currentUuid and inventory[currentUuid]
		local optionText
		if currentItem then
			optionText = string.format("Swap equipped %s for this %s?", displayName(currentItem), displayName(item))
		else
			optionText = "Equip " .. displayName(item)
		end
		setContextMenu({
			key = key,
			position = Vector2.new(x, y),
			options = {
				{
					text = optionText,
					onClick = function()
						DungeonMenuNet.requestEquip(item.uuid)
					end,
				},
			},
		})
	end

	--  Equip-panel right-click: single Unequip option (nothing to offer on an
	--  empty slot).
	local function onEquipSlotRightClick(slotName: string, uuid: string?, x: number, y: number)
		if not uuid then
			return
		end
		local key = "equip:" .. slotName
		if contextMenu and contextMenu.key == key then
			dismissContextMenu()
			return
		end
		setContextMenu({
			key = key,
			position = Vector2.new(x, y),
			options = {
				{
					text = "Unequip",
					onClick = function()
						DungeonMenuNet.requestUnequip(slotName)
					end,
				},
			},
		})
	end

	local function onHoverStart(item: any, x: number, y: number)
		setHover({ item = item, position = Vector2.new(x, y) })
	end

	local function onHoverEnd()
		setHover(nil)
	end

	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		Banner = e(TitleBanner, { onMeasured = setBannerHeight }),

		TopRow = e("Frame", {
			Position = UDim2.new(0, 0, 0, bannerHeight + GAP),
			Size = UDim2.new(1, 0, 1, -(bannerHeight + GAP) - (QUICKNAV_H + GAP)),
			BackgroundTransparency = 1,
			ZIndex = 2,
		}, {
			PlayerPreviewCol = e("Frame", {
				Size = UDim2.new(0.46, -COLUMN_GAP / 2, 1, 0),
				BackgroundTransparency = 1,
			}, {
				Preview = e(PlayerPreview, {
					equipped = equipped,
					inventory = inventory,
					onSlotClick = onEquipSlotClick,
					onSlotRightClick = onEquipSlotRightClick,
					onHoverStart = onHoverStart,
					onHoverEnd = onHoverEnd,
				}),
			}),
			InvSlotsCol = e("Frame", {
				Size = UDim2.new(0.54, -COLUMN_GAP / 2, 1, 0),
				Position = UDim2.new(0.46, COLUMN_GAP / 2, 0, 0),
				BackgroundTransparency = 1,
			}, {
				Slots = e(InvSlots, {
					bagSlots = bagSlots,
					inventory = inventory,
					heldSlotIndex = held and held.slotIndex,
					onSlotClick = onBagSlotClick,
					onSlotRightClick = onBagSlotRightClick,
					onHoverStart = onHoverStart,
					onHoverEnd = onHoverEnd,
				}),
			}),
		}),

		QuickNavRow = e("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, QUICKNAV_H),
			BackgroundTransparency = 1,
			ZIndex = 2,
		}, {
			Nav = e(QuickNav, { onSelect = props.onSelect }),
		}),

		-- Sits BELOW TopRow/QuickNavRow (ZIndex 1 < 2) so real item/equip buttons always win
		-- hit-testing over it -- under ZIndexBehavior.Sibling a higher-ZIndex sibling's whole
		-- subtree paints (and hit-tests) above a lower one's, regardless of nested ZIndex values.
		-- Previously this was ZIndex 40 (above everything), which silently ate every click over
		-- the bag/equip panels once a menu was open -- including the second right-click meant to
		-- collapse it, since that click never reached the item button's own handler at all.
		DismissCatcher = contextMenu and e("TextButton", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			ZIndex = 1,
			[React.Event.Activated] = dismissContextMenu,
		}) or nil,

		ContextMenuOverlay = contextMenu and e(ContextMenu, {
			position = contextMenu.position,
			options = contextMenu.options,
			onDismiss = dismissContextMenu,
		}) or nil,

		TooltipOverlay = hover and e(Tooltip, {
			item = hover.item,
			position = hover.position,
		}) or nil,
	})
end

local function Inventory(props: { resetKey: number? })
	local stack, setStack = React.useState({ "inventory" })

	-- resetKey changes every time the mount script closes the panel --
	-- snap the stack back to the main screen so reopening doesn't resume on
	-- whatever sub-panel was last open.
	React.useEffect(function()
		setStack({ "inventory" })
	end, { props.resetKey })

	local function push(name: string)
		setStack(function(prev)
			local nextStack = table.clone(prev)
			table.insert(nextStack, name)
			return nextStack
		end)
	end

	local function pop()
		setStack(function(prev)
			if #prev <= 1 then
				return prev
			end
			local nextStack = table.clone(prev)
			table.remove(nextStack)
			return nextStack
		end)
	end

	local top = stack[#stack]

	local body
	if top == "inventory" then
		body = e(InventoryMain, { onSelect = push })
	else
		local PanelComponent = PANELS[top]
		body = PanelComponent and e(PanelComponent, { onClose = pop })
	end

	return e("Frame", {
		-- "at least 80% of the screen" per request -- 86% both axes.
		Size = UDim2.fromScale(0.86, 0.86),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
	}, {
		Body = body,
	})
end

return Inventory
