--!strict
--  Inventory -- the root component combining the three FigBloxUI pieces
--  (Player Preview / Inv Slots / quick nav) plus the four icon-triggered
--  sub-panels. Everything lives under this ONE component (per request).
--
--  Navigation (reworked 2026-09-13 into a persistent header, per direct
--  request + reference screenshots): QuickNav now sits at the very top of
--  this component, ABOVE whatever's showing below it, instead of being
--  nested inside the main bag/equip screen -- so it stays visible and
--  selectable no matter which destination is open. `selectedKey` is a flat
--  string ("inventory" | "skills" | "stats" | "hearthstone" | "party") owned
--  by QuickNav's own carousel state and reported up via onSelect; this
--  replaced the old push/pop stack, since there's no "the main screen is the
--  base of the stack" special case anymore -- Inventory is just another
--  selectable destination now. The sub-panels lost their own X close button
--  for the same reason: cycling QuickNav back to "Inventory" (click, or
--  Left/Right arrows) is how you leave them. Tab/Escape (handled by the
--  mount script, InventoryHud) closes the whole thing and -- via resetKey,
--  passed through to QuickNav -- resets the carousel back to "inventory" for
--  next time it's opened.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local React = require(ReplicatedStorage.Packages.React)
local e = React.createElement

local PlayerPreview    = require(script:WaitForChild("PlayerPreview"))
local InvSlots         = require(script:WaitForChild("InvSlots"))
local QuickNav         = require(script:WaitForChild("QuickNav"))
local SkillsPanel      = require(script:WaitForChild("SkillsPanel"))
local StatsPanel       = require(script:WaitForChild("StatsPanel"))
local JournalPanel     = require(script:WaitForChild("JournalPanel"))
local HearthstonePanel = require(script:WaitForChild("HearthstonePanel"))
local PartyPanel       = require(script:WaitForChild("PartyPanel"))
local InventoryData    = require(script:WaitForChild("InventoryData"))
local ContextMenu      = require(script:WaitForChild("ContextMenu"))
local Tooltip          = require(script:WaitForChild("Tooltip"))

local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local Types = require(ReplicatedStorage:WaitForChild("ProfileTypes"))
local ProfileMenusState = require(ReplicatedStorage:WaitForChild("ProfileMenusState"))
local HudVitals = require(ReplicatedStorage:WaitForChild("HudVitals"))
local DungeonMenuNet = require(script.Parent.Parent:WaitForChild("DungeonMenuNet"))
local CenterFlashUI = require(script.Parent.Parent:WaitForChild("CenterFlashUI"))

-- Error -> on-screen text for the Drop/Trash context-menu actions. The server is the
-- sole source of truth for whether either is allowed (ProfileService.DropItem/
-- TrashItem) -- this only turns its error code into something readable.
local function dropTrashErrorText(err)
	if err == "in_combat" then
		return "Can't do that in combat!"
	elseif err == "not_safe_zone" then
		return "Must be in a safe zone!"
	elseif err == "not_owned" then
		return "You don't have that item."
	elseif err == "throttled" then
		return "Too fast -- wait a moment."
	end
	return "Couldn't do that."
end

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
	journal = JournalPanel,
	hearthstone = HearthstonePanel,
	party = PartyPanel,
}

-- QuickNav's icons/backing scale with SIZE_MULTIPLIER in QuickNav.lua (first tripled, then
-- dialed back to 2x same day after an actual playtest ran too big -- see that file), so this
-- row's own height tracks it 1:1 (110 * SIZE_MULTIPLIER) so the carousel never gets clipped by
-- its own container.
local QUICKNAV_H = 220
local GAP = 20 -- a bit more breathing room than the raw Figma export had
local COLUMN_GAP = 10 -- tighter gap between the preview and slots columns specifically, per request

-- Per request, then increased further same day after a playtest showed "still a ton of space
-- at the top": move the quicknav row up (as a % of screen height, so it tracks with screen
-- size), and move whatever profilemenu content is currently selected up too, to free room for
-- it (the inventory bag/equip screen especially -- reported as "way too small" with the
-- original, smaller shift). The two shifts are deliberately independent (NOT compounded /
-- stacked on top of each other) -- each is a shift off its own original position, not off the
-- other's shifted position. Both are still eyeballed estimates -- check visually and nudge
-- again if either under- or overshoots.
local QUICKNAV_UP_SHIFT = -0.17
local CONTENT_UP_SHIFT = -0.08

-- Direction-aware slide when switching profilemenu tabs (skills/stats/party/etc, per
-- request item 4). See SlidingBody below.
local SLIDE_TWEEN = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

--[[
	Hold-drag-and-drop. Adds a second gesture on top of the existing click-to-pick/
	click-to-place (`held` state below) rather than replacing it: press on an occupied slot
	and release without moving is still a plain click, handled entirely by onBagSlotClick/
	onEquipSlotClick/Activated as before. Only once the cursor moves past DRAG_THRESHOLD
	pixels does this become a drag -- a translucent icon then follows the cursor (DragGhost,
	near the bottom of this file) and releasing over a slot resolves the drop.

	Iteration 1 was bag <-> bag only. Iteration 2 (this pass) adds PlayerPreview's equip
	boxes as both drag sources and drop targets, so bag <-> equip works directly instead of
	only via click-to-pick-then-click-equip-slot. Both InvSlots (bag, keyed by numeric slot
	index) and PlayerPreview (equip, keyed by slot NAME) report press/enter/leave through the
	same three callbacks below, so pressRef/hoveredSlotRef hold a small tagged union --
	{kind="bag", index=number} or {kind="equip", slotName=string} -- and the drop resolver
	switches on the (source.kind, target.kind) pair:
	  bag -> bag     SwapBagSlot (same act the click path uses)
	  bag -> equip   requestEquip, but only if the item's own allowed slot matches the
	                 target box (same legality check onEquipSlotClick already does) --
	                 otherwise the drop is silently rejected, same as clicking the wrong box.
	  equip -> bag   requestUnequip(source.slotName) -- the server always returns the item to
	                 the first empty bag slot regardless of which one you dropped on (same as
	                 the existing right-click "Unequip" option), so the target bag index isn't
	                 sent, only used to confirm the drop landed inside the bag grid at all.
	  equip -> equip no-op: an equipped item's allowed slot is always its OWN slot name, so it
	                 can never legally match a different equip box.

	Modeled on the legacy src/client/InventoryDragController.lua's press/threshold/ghost
	shape (same DRAG_THRESHOLD=5, same "release-without-crossing-threshold falls through to
	a plain click" rule) -- that controller drives the OLD imperative equip/hotbar UI
	(DungeonMenuUI, still wired into SkillsTabClient) and was never ported to this React
	panel. Re-implemented here rather than required directly because its hover-tracking
	(setHoveredBag/setHoveredHotbar/setHoveredEquip) is keyed to DungeonMenuUI's own
	instance-naming scheme, not this component's React state.

	Threshold/press state lives in a plain React.useRef, not React state -- InputChanged
	fires on every pixel of mouse movement while dragging, and routing that through
	setState would mean a full component re-render per pixel. The ghost's Position is
	written directly onto the live Instance via dragGhostRef for the same reason; `dragging`
	(React state) only flips once, to mount/unmount the ghost element itself.
]]
local DRAG_THRESHOLD = 5
local GHOST_SIZE = 100

local function InventoryMain()
	local snapshot = InventoryData.useSnapshot()
	local profile = snapshot and snapshot.profile
	local inventory = (profile and profile.inventory) or {}
	local bagSlots = (profile and profile.bagSlots) or {}
	local equipped = (profile and profile.equipped) or {}

	local held, setHeld = React.useState(nil :: { uuid: string, slotIndex: number }?)
	local contextMenu, setContextMenu = React.useState(nil :: { key: string, position: Vector2, options: { any } }?)
	local hover, setHover = React.useState(nil :: { item: any, position: Vector2 }?)

	--  Tooltip/ContextMenu/DragGhost below are all positioned in raw screen-space
	--  (UDim2.fromOffset straight off MouseEnter/InputChanged's absolute mouse
	--  coordinates), but they render as CHILDREN of this component's own root Frame --
	--  which itself sits somewhere other than the screen's (0,0) corner once nested
	--  under QuickNav's ContentArea (2026-09-13 fix: the tooltip rendering "way too
	--  far" from the cursor was exactly this -- the root's own AbsolutePosition was
	--  getting added on top of an already-absolute mouse position). containerRef/
	--  containerAbsPos read that offset once so every overlay below can subtract it
	--  and land at the real cursor position. containerAbsPosRef mirrors the same value
	--  into a ref for the InputChanged closure below, which is connected once (empty
	--  dep array) and would otherwise close over a stale value.
	local containerRef = React.useRef(nil :: Frame?)
	local containerAbsPos, setContainerAbsPos = React.useState(Vector2.new(0, 0))
	local containerAbsPosRef = React.useRef(Vector2.new(0, 0))

	React.useEffect(function()
		local container = containerRef.current
		if not container then
			return
		end
		local function recompute()
			containerAbsPosRef.current = container.AbsolutePosition
			setContainerAbsPos(container.AbsolutePosition)
		end
		recompute()
		local conn = container:GetPropertyChangedSignal("AbsolutePosition"):Connect(recompute)
		return function()
			conn:Disconnect()
		end
	end, {})

	--  Converts a desired on-screen popup (top-left at `cursorAbs + edgeOffset`, sized
	--  `size`) into this component's local coordinate space, flipping to the opposite
	--  side of the cursor -- and failing that, clamping outright -- whenever the default
	--  placement would run off the viewport. `size` comes from each popup's own
	--  EstimateSize (Tooltip/ContextMenu) since an AutomaticSize frame's real size isn't
	--  known until after it already rendered once -- too late to decide where to put it.
	local function clampedOverlayPosition(cursorAbs: Vector2, size: Vector2, edgeOffset: number): Vector2
		local camera = Workspace.CurrentCamera
		local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)

		local x = cursorAbs.X + edgeOffset
		if x + size.X > viewport.X then
			x = cursorAbs.X - edgeOffset - size.X
		end
		x = math.clamp(x, 0, math.max(0, viewport.X - size.X))

		local y = cursorAbs.Y + edgeOffset
		if y + size.Y > viewport.Y then
			y = cursorAbs.Y - edgeOffset - size.Y
		end
		y = math.clamp(y, 0, math.max(0, viewport.Y - size.Y))

		return Vector2.new(x - containerAbsPos.X, y - containerAbsPos.Y)
	end

	-- Hold-drag session state -- see the DRAG_THRESHOLD doc comment above. pressRef/hoveredSlotRef
	-- are plain refs (no re-render per mouse-move); `drag` is real state because it drives whether
	-- the ghost ImageLabel exists at all. DragSource/DragTarget are the tagged union described
	-- above -- a bag slot by index, or an equip box by slot name.
	type DragLocation = { kind: "bag", index: number } | { kind: "equip", slotName: string }
	local pressRef = React.useRef(nil :: { source: DragLocation, uuid: string, item: any, startX: number, startY: number, dragging: boolean }?)
	local hoveredSlotRef = React.useRef(nil :: DragLocation?)
	local drag, setDrag = React.useState(nil :: { item: any }?)
	local dragGhostRef = React.useRef(nil :: ImageLabel?)

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

	--  Bag right-click: Equip/Swap (if the item has a slot) plus Drop/Trash, always.
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
		local options = {}
		if slotName then
			local currentUuid = equipped[slotName]
			local currentItem = currentUuid and inventory[currentUuid]
			local optionText
			if currentItem then
				optionText = string.format("Swap equipped %s for this %s?", displayName(currentItem), displayName(item))
			else
				optionText = "Equip " .. displayName(item)
			end
			table.insert(options, {
				text = optionText,
				onClick = function()
					DungeonMenuNet.requestEquip(item.uuid)
				end,
			})
		end
		-- Drop/Trash are offered for every item; the server is the one that actually
		-- enforces "not in combat" (both) and "in a safe zone" (trash) -- see
		-- ProfileService.DropItem/TrashItem. A denial just surfaces via the center
		-- flash the RF error already drives (see CenterFlashUI below).
		table.insert(options, {
			text = "Drop " .. displayName(item),
			onClick = function()
				local ok, err = DungeonMenuNet.requestDropItem(item.uuid)
				if not ok then
					CenterFlashUI.Show(dropTrashErrorText(err))
				end
			end,
		})
		table.insert(options, {
			text = "Trash " .. displayName(item),
			onClick = function()
				local ok, err = DungeonMenuNet.requestTrashItem(item.uuid)
				if not ok then
					CenterFlashUI.Show(dropTrashErrorText(err))
				end
			end,
		})
		setContextMenu({
			key = key,
			position = Vector2.new(x, y),
			options = options,
		})
	end

	--  Equip-panel right-click: Unequip/Drop/Trash (nothing to offer on an empty slot).
	local function onEquipSlotRightClick(slotName: string, uuid: string?, x: number, y: number)
		if not uuid then
			return
		end
		local key = "equip:" .. slotName
		if contextMenu and contextMenu.key == key then
			dismissContextMenu()
			return
		end
		local equippedItem = inventory[uuid]
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
				{
					text = "Drop " .. displayName(equippedItem),
					onClick = function()
						local ok, err = DungeonMenuNet.requestDropItem(uuid)
						if not ok then
							CenterFlashUI.Show(dropTrashErrorText(err))
						end
					end,
				},
				{
					text = "Trash " .. displayName(equippedItem),
					onClick = function()
						local ok, err = DungeonMenuNet.requestTrashItem(uuid)
						if not ok then
							CenterFlashUI.Show(dropTrashErrorText(err))
						end
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

	--  Hold-drag: pressing down on an occupied slot (bag or equip) arms a possible drag
	--  (doesn't start it yet -- that happens once InputChanged sees movement past
	--  DRAG_THRESHOLD, below). Ignored while click-to-pick (`held`) already has something
	--  up, so the two gestures never fight over the same item.
	local function armPress(source: DragLocation, uuid: string, item: any, x: number, y: number)
		pressRef.current = {
			source = source,
			uuid = uuid,
			item = item,
			startX = x,
			startY = y,
			dragging = false,
		}
	end

	local function onBagSlotPressStart(slotIndex: number, uuid: string?, x: number, y: number)
		if held or not uuid then
			return
		end
		local item = inventory[uuid]
		if not item then
			return
		end
		armPress({ kind = "bag", index = slotIndex }, uuid, item, x, y)
	end

	local function onBagSlotEnter(slotIndex: number)
		hoveredSlotRef.current = { kind = "bag", index = slotIndex }
	end

	local function onBagSlotLeave(slotIndex: number)
		local h = hoveredSlotRef.current
		if h and h.kind == "bag" and h.index == slotIndex then
			hoveredSlotRef.current = nil
		end
	end

	local function onEquipSlotPressStart(slotName: string, uuid: string?, x: number, y: number)
		if held or not uuid then
			return
		end
		local item = inventory[uuid]
		if not item then
			return
		end
		armPress({ kind = "equip", slotName = slotName }, uuid, item, x, y)
	end

	local function onEquipSlotEnter(slotName: string)
		hoveredSlotRef.current = { kind = "equip", slotName = slotName }
	end

	local function onEquipSlotLeave(slotName: string)
		local h = hoveredSlotRef.current
		if h and h.kind == "equip" and h.slotName == slotName then
			hoveredSlotRef.current = nil
		end
	end

	--  InputChanged/InputEnded connections for the drag gesture. Connected once (empty dep
	--  array) since InventoryMain can persist across opens/closes -- see InventoryHud/init.client.lua,
	--  which only toggles the ScreenGui's .Enabled -- so the cleanup function below matters mainly
	--  for the (rarer) case this component itself gets unmounted (e.g. navigating into a sub-panel).
	React.useEffect(function()
		local changedConn = UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			local press = pressRef.current
			if not press then
				return
			end
			local x, y = input.Position.X, input.Position.Y
			if not press.dragging then
				local dx, dy = x - press.startX, y - press.startY
				if (dx * dx + dy * dy) < (DRAG_THRESHOLD * DRAG_THRESHOLD) then
					return
				end
				press.dragging = true
				setDrag({ item = press.item })
			end
			local ghost = dragGhostRef.current
			if ghost then
				local c = containerAbsPosRef.current
				ghost.Position = UDim2.fromOffset(x - c.X, y - c.Y)
			end
		end)

		local endedConn = UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			local press = pressRef.current
			pressRef.current = nil
			if not press or not press.dragging then
				return
			end
			setDrag(nil)
			local target = hoveredSlotRef.current
			if not target then
				return
			end
			-- Guard against a drop resolving after the panel's already been closed mid-drag
			-- (gui.Enabled flips false on close, independently of this component's lifecycle).
			local player = Players.LocalPlayer
			local playerGui = player and player:FindFirstChild("PlayerGui")
			local gui = playerGui and playerGui:FindFirstChild("ProfileMenusReact")
			if gui and gui:IsA("ScreenGui") and not gui.Enabled then
				return
			end

			local source = press.source
			if source.kind == "bag" and target.kind == "bag" then
				if target.index ~= source.index then
					DungeonMenuNet.requestInventoryAct({ kind = "SwapBagSlot", a = source.index, b = target.index })
				end
			elseif source.kind == "bag" and target.kind == "equip" then
				if Types.GetAllowedEquipSlot(press.item) == target.slotName then
					DungeonMenuNet.requestEquip(press.uuid)
				end
			elseif source.kind == "equip" and target.kind == "bag" then
				DungeonMenuNet.requestUnequip(source.slotName)
			end
			-- equip -> equip: intentionally left as a no-op -- see the doc comment above.
		end)

		return function()
			changedConn:Disconnect()
			endedConn:Disconnect()
		end
	end, {})

	-- QuickNav moved out of this component entirely (2026-09-13, per direct request -- see
	-- the persistent-header rework in this file's header comment) -- it now lives once in
	-- the outer Inventory component, above whatever this renders. TopRow fills this whole
	-- component's given area, since the space for QuickNav is already carved out one level
	-- up.
	return e("Frame", {
		ref = containerRef,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		TopRow = e("Frame", {
			Size = UDim2.fromScale(1, 1),
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
					onSlotPressStart = onEquipSlotPressStart,
					onSlotEnter = onEquipSlotEnter,
					onSlotLeave = onEquipSlotLeave,
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
					onSlotPressStart = onBagSlotPressStart,
					onSlotEnter = onBagSlotEnter,
					onSlotLeave = onBagSlotLeave,
				}),
			}),
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

		-- Position/size: EstimateSize predicts the AutomaticSize box's real footprint so
		-- clampedOverlayPosition can flip/clamp it before it ever renders (see that
		-- function's doc comment) -- an exact "0 offset, opens right at the click" for
		-- the menu, matching its previous behavior when there's room for it.
		ContextMenuOverlay = contextMenu and e(ContextMenu.Component, {
			position = clampedOverlayPosition(contextMenu.position, ContextMenu.EstimateSize(#contextMenu.options), 0),
			options = contextMenu.options,
			onDismiss = dismissContextMenu,
		}) or nil,

		-- Suppressed entirely while a context menu is open (2026-09-13, per direct
		-- request): the two used to stack and overlap since both can be showing for the
		-- same item at once -- the menu takes priority since it's the one the player
		-- actually asked for.
		TooltipOverlay = (hover and not contextMenu) and e(Tooltip.Component, {
			item = hover.item,
			position = clampedOverlayPosition(hover.position, Tooltip.EstimateSize(hover.item), 18),
		}) or nil,

		-- Hold-drag ghost: a translucent copy of the dragged item's icon that follows the
		-- cursor. Positioned in local (container-relative) space, imperatively updated via
		-- dragGhostRef -- see the InputChanged connection above, which subtracts
		-- containerAbsPosRef the same way clampedOverlayPosition does above.
		DragGhost = drag and e("ImageLabel", {
			ref = dragGhostRef,
			Image = ItemDefinitions.GetIconForItem(drag.item),
			Size = UDim2.fromOffset(GHOST_SIZE, GHOST_SIZE),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			ImageTransparency = 0.5,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 100,
		}) or nil,
	})
end

--  renderBody -- picks which panel a given destination key shows. Pulled out of the old
--  inline if/else in Inventory() so both the settled view and SlidingBody's outgoing/
--  incoming halves (mid-transition) can call the same thing.
local function renderBody(key: string)
	if key == "inventory" then
		return e(InventoryMain)
	end
	local PanelComponent = PANELS[key]
	return PanelComponent and e(PanelComponent, {})
end

--[[
	SlidingBody -- direction-aware slide transition between profilemenu tabs (request item 4:
	"add a 'sliding' animation when changing tabs... to the left or right dependent on
	direction"). QuickNav already computes which way the selection moved (see its
	`computeOffset`/`prevIndexRef`-based onSelect(key, direction) in QuickNav.lua) and hands
	that straight through here as `props.direction` (-1 left, 0 none/reset, 1 right).

	`current` is the settled, fully-displayed key (matches the old plain "body" var this
	replaced). `transition` is only set while a slide is actually animating -- while set, BOTH
	the outgoing and incoming panel are mounted side by side inside a ClipsDescendants wrapper
	and tweened across it via refs (imperative Position writes, same convention as the rest of
	this codebase's hover/drag tweens) rather than through React state, so the tween runs at
	full frame rate instead of one React re-render per frame.

	Sign convention: direction > 0 means the user moved right (e.g. clicked the right arrow /
	scrolled right), so the NEW panel should enter FROM the right and the OLD one should exit
	to the left -- direction < 0 mirrors this.

	Rapid re-selection (spamming the arrow keys before a tween finishes): the effect below
	folds a new incoming activeKey into the existing transition's toKey rather than waiting for
	the in-flight tween to finish first, so the display never lags behind the carousel.
]]
local function SlidingBody(props: { activeKey: string, direction: number, renderBody: (string) -> any })
	local current, setCurrent = React.useState(props.activeKey)
	local transition, setTransition = React.useState(nil :: { fromKey: string, toKey: string, direction: number }?)

	-- Refs mirroring the two states above so the effect below always sees the latest value
	-- without needing to list them as deps (which would refire it on every settle).
	local currentRef = React.useRef(current)
	local transitionRef = React.useRef(transition)
	currentRef.current = current
	transitionRef.current = transition

	local outgoingRef = React.useRef(nil :: Frame?)
	local incomingRef = React.useRef(nil :: Frame?)

	-- Kicks off (or redirects) a slide whenever the reported activeKey actually changes.
	React.useEffect(function()
		local liveTransition = transitionRef.current
		local displayedKey = (liveTransition and liveTransition.toKey) or currentRef.current
		if props.activeKey == displayedKey then
			return
		end
		if props.direction == 0 then
			-- Programmatic reset (e.g. resetKey snapping the carousel back to "inventory") --
			-- no meaningful direction to slide in, so just snap.
			setTransition(nil)
			setCurrent(props.activeKey)
			return
		end
		setTransition({ fromKey = displayedKey, toKey = props.activeKey, direction = props.direction })
	end, { props.activeKey })

	-- Drives the actual tween + finalization whenever a new transition is (re)armed.
	React.useEffect(function()
		if not transition then
			return
		end
		local dir = transition.direction
		local outEnd = UDim2.fromScale(dir > 0 and -1 or 1, 0)
		local inStart = UDim2.fromScale(dir > 0 and 1 or -1, 0)

		if outgoingRef.current then
			outgoingRef.current.Position = UDim2.fromScale(0, 0)
			TweenService:Create(outgoingRef.current, SLIDE_TWEEN, { Position = outEnd }):Play()
		end
		if incomingRef.current then
			incomingRef.current.Position = inStart
			TweenService:Create(incomingRef.current, SLIDE_TWEEN, { Position = UDim2.fromScale(0, 0) }):Play()
		end

		local toKey = transition.toKey
		local finishThread = task.delay(SLIDE_TWEEN.Time, function()
			-- Only finalize if this is still the live transition -- a rapid re-selection may
			-- have already replaced it with a newer one (see the effect above), in which case
			-- that newer transition's own finishThread is the one that should finalize.
			local live = transitionRef.current
			if live and live.toKey == toKey then
				setCurrent(toKey)
				setTransition(nil)
			end
		end)

		return function()
			task.cancel(finishThread)
		end
	end, { transition })

	if transition then
		return e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
		}, {
			Outgoing = e("Frame", {
				ref = outgoingRef,
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
			}, {
				Content = props.renderBody(transition.fromKey),
			}),
			Incoming = e("Frame", {
				ref = incomingRef,
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
			}, {
				Content = props.renderBody(transition.toKey),
			}),
		})
	end

	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		Content = props.renderBody(current),
	})
end

local function Inventory(props: { resetKey: number? })
	-- Flat destination key instead of the old push/pop stack -- see this file's header
	-- comment. QuickNav owns the carousel index itself and reports the selected id up
	-- through onSelect; resetKey is threaded straight through to QuickNav so it can snap
	-- its own carousel back to "inventory" on close (see QuickNav.lua).
	local selectedKey, setSelectedKey = React.useState("inventory")
	-- Direction QuickNav reported alongside the most recent selection change (-1/0/1) --
	-- see onNavSelect below and QuickNav.lua's onSelect(key, direction). Threaded through to
	-- SlidingBody so it knows which way to slide.
	local direction, setDirection = React.useState(0)

	local function onNavSelect(key: string, dir: number?)
		setDirection(dir or 0)
		setSelectedKey(key)
	end

	-- Vitals (HP/energy/hunger) stay up on the Inventory tab only; every other tab hides them
	-- (RS/HudVitals). Re-evaluated on open/close too, since reopening may land on this same key.
	React.useEffect(function()
		local function apply()
			HudVitals.SetHidden("ProfileMenuTab", ProfileMenusState.IsOpen() and selectedKey ~= "inventory")
		end
		apply()
		return ProfileMenusState.Subscribe(apply)
	end, { selectedKey })

	-- Full UDim2s (not plain offset numbers) so the scale component can carry the "% of
	-- screen" shift -- see QUICKNAV_UP_SHIFT/CONTENT_UP_SHIFT above. The two shifts are
	-- independent, not stacked: contentY's scale is CONTENT_UP_SHIFT on its own, not
	-- QUICKNAV_UP_SHIFT + CONTENT_UP_SHIFT.
	local quickNavY = UDim2.new(0, 0, QUICKNAV_UP_SHIFT, GAP)
	local contentY = UDim2.new(0, 0, CONTENT_UP_SHIFT, GAP + QUICKNAV_H + GAP)

	return e("Frame", {
		-- "at least 80% of the screen" per request -- 86% both axes.
		Size = UDim2.fromScale(0.86, 0.86),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
	}, {
		QuickNavRow = e("Frame", {
			Position = quickNavY,
			Size = UDim2.new(1, 0, 0, QUICKNAV_H),
			BackgroundTransparency = 1,
			ZIndex = 2,
		}, {
			Nav = e(QuickNav, { onSelect = onNavSelect, resetKey = props.resetKey }),
		}),

		-- Size grows by -CONTENT_UP_SHIFT (a positive amount, since the shift is negative) so
		-- the bottom edge stays put at the parent's 100% mark while the top edge moves up by
		-- CONTENT_UP_SHIFT -- same "shift up without changing where it ends" trick as QuickNavRow.
		ContentArea = e("Frame", {
			Position = contentY,
			Size = UDim2.new(1, 0, 1 - CONTENT_UP_SHIFT, -(GAP + QUICKNAV_H + GAP)),
			BackgroundTransparency = 1,
		}, {
			Body = e(SlidingBody, {
				activeKey = selectedKey,
				direction = direction,
				renderBody = renderBody,
			}),
		}),
	})
end

return Inventory
