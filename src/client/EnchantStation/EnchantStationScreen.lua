--!strict
--[[
	EnchantStationScreen
	The Enchanting Station overlay: inventory grid on the LEFT half of the
	screen, the altar (camera-panned into the RIGHT half, see
	EnchantStationClient's yaw offset) with a Gear slot + an Enchant (scroll)
	slot on the right, an arrow to a live preview of the post-enchant item,
	green "X% success" above the arrow / red "Y% failure" below.

	This IS the only way to enchant now -- the old right-click-in-bag flow
	for enchant scrolls specifically was removed from SkillsTabClient.client.lua
	(Protection Scrolls / Crafting Orbs still work the old way there; those
	aren't "enchanting" and weren't asked to move).

	Selection is hold-drag from the left grid onto the Gear/Enchant slot on
	the right -- same gesture shape as InventoryHud/Inventory/init.lua's own
	hold-drag (DRAG_THRESHOLD, a plain React.useRef for the high-frequency
	InputChanged tracking instead of state, ghost position written directly
	onto the Instance) -- re-implemented locally rather than required, same
	reasoning that file's own header comment gives for not sharing
	InventoryDragController: the hover-tracking here is keyed to this
	screen's two named targets ("gear"/"enchant"), not that controller's bag/
	hotbar/equip instance-naming scheme.

	Odds/preview are computed fully client-side (EnchantScrollApply.
	GetSuccessChanceForNextLevel / PreviewNextSubStats are pure, no server
	round trip needed just to look). The actual apply reuses the EXISTING
	ApplyEnchantScroll DungeonInventoryAct kind via
	DungeonMenuNet.requestInventoryAct -- already wired server-side.

	2026-09-29: the second slot also takes CRAFTING ORBS (ApplyCraftingOrb act, same
	server path the old right-click flow uses). Wisdom previews the exact next-level
	stats (CraftingOrbApply.PreviewWisdom); Alteration shows the item with "?" (its
	reroll is random); orb kinds with no rules yet (CraftingOrbApply.IsImplemented)
	are accepted into the slot but refused with "no effect yet" (the server refuses
	them too, before consuming). The left panel is narrower and shows the player's
	EQUIPPED gear above the bag, so worn pieces can be enchanted without unequipping.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local UITheme = require(ReplicatedStorage:WaitForChild("UITheme"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local EnchantScrollApply = require(ReplicatedStorage:WaitForChild("EnchantScrollApply"))
local CraftingOrbApply = require(ReplicatedStorage:WaitForChild("CraftingOrbApply"))

local StarterPlayerScripts = script.Parent.Parent
local DungeonMenuNet = require(StarterPlayerScripts:WaitForChild("DungeonMenuNet"))
local InventoryComponents = StarterPlayerScripts:WaitForChild("InventoryHud"):WaitForChild("Inventory")
local ItemSlot = require(InventoryComponents:WaitForChild("ItemSlot"))
-- The REAL bag grid (same one InventoryHud's own Inventory tab renders), not a hand-rolled
-- duplicate -- fixes two problems at once: no second grid implementation to keep in sync,
-- and it already handles the bagSlots string-vs-number key quirk (see its own header
-- comment) that a naive `bagSlots[i]` loop here silently missed, which is why the grid was
-- rendering as all-empty before this.
local InvSlots = require(InventoryComponents:WaitForChild("InvSlots"))
local SfxService = require(ReplicatedStorage:WaitForChild("SfxService"))
local EnchantEffects = require(script.Parent:WaitForChild("EnchantEffects"))
-- Same item-stats tooltip the Inventory tab shows on hover -- reused, not copied.
local Tooltip = require(InventoryComponents:WaitForChild("Tooltip"))

local e = React.createElement

local THEME = {
	Backdrop = Color3.fromRGB(0, 0, 0),
	PanelBg = Color3.fromRGB(26, 18, 11),
	HeaderBg = Color3.fromRGB(34, 24, 15),
	Border = UITheme.Gold,
	Title = Color3.fromRGB(240, 230, 210),
	Muted = Color3.fromRGB(170, 160, 145),
	Success = Color3.fromRGB(110, 220, 120),
	Failure = Color3.fromRGB(220, 90, 90),
	CloseBg = Color3.fromRGB(48, 28, 28),
	SlotLabel = Color3.fromRGB(200, 190, 175),
	SlotBg = Color3.fromRGB(20, 15, 12),
	SlotBgHover = Color3.fromRGB(48, 62, 40),
}

local SLOT_SIZE = 92
local DRAG_THRESHOLD = 5
local GHOST_SIZE = 84
local EQUIP_CELL = 52
-- Worn gear shown above the bag, in this order (tools -- Pickaxe/FishingSpear -- aren't gear).
local GEAR_EQUIP_SLOTS = { "Weapon", "Bow", "Helm", "Chest", "Legs", "Boots", "Shield" }

local function shallowCopy(t)
	local out = {}
	for k, v in pairs(t) do
		out[k] = v
	end
	return out
end

local function formatPrimaryStat(item, subs)
	if type(item) ~= "table" or type(subs) ~= "table" then
		return ""
	end
	if item.type == "Weapon" then
		local lo = math.floor(tonumber(subs.dmgMin) or 0)
		local hi = math.floor(tonumber(subs.dmgMax) or 0)
		return string.format("DMG %d - %d", lo, hi)
	elseif item.type == "Armor" then
		return string.format("HP %d", math.floor(tonumber(subs.hp) or 0))
	end
	return ""
end

local function isGearEligible(item)
	return type(item) == "table" and (item.type == "Weapon" or item.type == "Armor")
end

-- The second slot: enchant scrolls and crafting orbs.
local function isScrollEligible(item)
	return type(item) == "table"
		and (ItemDefinitions.IsEnchantScroll(item.itemId) or ItemDefinitions.IsCraftingOrb(item.itemId))
end

-- The single routing rule for "which station slot does this item belong in". Click-to-place
-- and drag-and-drop both go through this, so the two gestures can't disagree about what's
-- allowed where. Returns "gear" | "enchant" | nil (not usable at the station).
local function slotForItem(item): string?
	if isScrollEligible(item) then
		return "enchant"
	end
	if isGearEligible(item) then
		return "gear"
	end
	return nil
end

--------------------------------------------------------------------------
-- A small hand-built right-pointing arrow (two rotated diamonds' worth of
-- geometry via a clip trick, not text) -- no arrow-glyph asset exists yet,
-- this is a first pass built from plain Frames so it needs no new asset.
--------------------------------------------------------------------------
local function ArrowGraphic()
	local HEAD = 22
	return e("Frame", {
		Size = UDim2.fromOffset(58, 28),
		BackgroundTransparency = 1,
	}, {
		Shaft = e("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(30, 6),
			BackgroundColor3 = THEME.Border,
			BorderSizePixel = 0,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
		}),
		HeadClip = e("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(28, 14),
			Size = UDim2.fromOffset(16, 26),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
		}, {
			-- A square rotated 45 degrees, centered on the clip window's left edge --
			-- only its right-pointing tip pokes into the visible window, reading as a
			-- clean triangular arrowhead with no trig needed to position it.
			Diamond = e("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0, 0.5),
				Size = UDim2.fromOffset(HEAD, HEAD),
				Rotation = 45,
				BackgroundColor3 = THEME.Border,
				BorderSizePixel = 0,
			}),
		}),
	})
end

local function SlotBox(props: {
	label: string,
	item: any?,
	badge: string?,
	onClick: (() -> ())?,
	isDropTarget: boolean?,
	hovered: boolean?,
	onDragEnter: (() -> ())?,
	onDragLeave: (() -> ())?,
	layoutOrder: number?,
	onHoverItem: ((item: any, x: number, y: number) -> ())?,
	onHoverEnd: (() -> ())?,
})
	return e("Frame", {
		LayoutOrder = props.layoutOrder or 0,
		Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE + 22),
		BackgroundTransparency = 1,
	}, {
		Slot = e("Frame", {
			Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE),
			BackgroundColor3 = props.hovered and THEME.SlotBgHover or THEME.SlotBg,
			BorderSizePixel = 0,
			Active = true, -- belt-and-suspenders: MouseEnter/Leave fire on a plain Frame
			-- regardless, but Active=true guarantees it rather than relying on that.
			[React.Event.MouseEnter] = props.onDragEnter,
			[React.Event.MouseLeave] = props.onDragLeave,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 6) }),
			Stroke = props.isDropTarget and e("UIStroke", {
				Color = props.hovered and THEME.Success or THEME.Border,
				Thickness = props.hovered and 2.5 or 1.5,
				Transparency = props.hovered and 0 or 0.4,
			}) or nil,
			Item = e(ItemSlot, {
				item = props.item,
				size = SLOT_SIZE,
				hideEnchant = true, -- this box draws its own badge (the preview shows the NEXT +N)
				onClick = props.onClick,
				onHoverStart = props.onHoverItem and function(x, y)
					if props.item and props.onHoverItem then
						props.onHoverItem(props.item, x, y)
					end
				end or nil,
				onHoverEnd = props.onHoverEnd,
			}),
			Badge = props.badge and e("TextLabel", {
				ZIndex = 6,
				Position = UDim2.fromOffset(4, 4),
				Size = UDim2.fromOffset(34, 18),
				BackgroundColor3 = Color3.fromRGB(20, 15, 12),
				BackgroundTransparency = 0.15,
				BorderSizePixel = 0,
				FontFace = UIFonts.BodyBold,
				TextSize = 13,
				TextColor3 = Color3.fromRGB(255, 220, 130),
				Text = props.badge,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, 4) }),
			}) or nil,
		}),
		Label = e("TextLabel", {
			Position = UDim2.fromOffset(0, SLOT_SIZE + 2),
			Size = UDim2.new(1, 0, 0, 18),
			BackgroundTransparency = 1,
			FontFace = UIFonts.BodyMedium,
			TextSize = 13,
			TextColor3 = THEME.SlotLabel,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = props.label,
		}),
	})
end

local function EnchantStationScreen(props: { onClose: () -> (), resetKey: number? })
	local snapshot, setSnapshot = React.useState(DungeonMenuNet.getLastSnapshot())
	local gearUuid, setGearUuid = React.useState(nil :: string?)
	local scrollUuid, setScrollUuid = React.useState(nil :: string?)
	local status, setStatus = React.useState("")
	local busy, setBusy = React.useState(false)

	-- Drag gesture state -- pressRef/hoveredTargetRef are plain refs so the very-high-
	-- frequency InputChanged handler below never triggers a React re-render per pixel of
	-- mouse movement (same reasoning as InventoryHud/Inventory/init.lua's own hold-drag).
	-- `drag` (state) only flips once, to mount/unmount the ghost; `hoveredTarget` (state)
	-- only changes on MouseEnter/Leave boundary crossings (cheap), driving the drop-target
	-- highlight -- hoveredTargetRef is the authoritative fast-path read InputEnded uses.
	local containerRef = React.useRef(nil :: Frame?)
	local containerAbsPosRef = React.useRef(Vector2.new(0, 0))
	local pressRef = React.useRef(nil :: { uuid: string, item: any, startX: number, startY: number, dragging: boolean }?)
	local hoveredTargetRef = React.useRef(nil :: string?) -- "gear" | "enchant" | nil
	local drag, setDrag = React.useState(nil :: { item: any }?)
	local dragGhostRef = React.useRef(nil :: ImageLabel?)
	local hoveredTarget, setHoveredTarget = React.useState(nil :: string?)
	local hover, setHover = React.useState(nil :: { item: any, position: Vector2 }?)

	local function onHoverItem(item: any, x: number, y: number)
		setHover({ item = item, position = Vector2.new(x, y) })
	end
	local function onHoverEnd()
		setHover(nil)
	end

	-- Cursor-relative tooltip placement, same flip-then-clamp logic as Inventory/init.lua's
	-- clampedOverlayPosition (Tooltip.EstimateSize predicts the box size before it renders).
	-- Result is container-local; this screen's root sits at the screen origin, but the
	-- container offset is subtracted anyway so it stays right if that ever changes.
	local function tooltipPosition(cursor: Vector2, size: Vector2): Vector2
		local camera = Workspace.CurrentCamera
		local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
		local edge = 18
		local x = cursor.X + edge
		if x + size.X > viewport.X then
			x = cursor.X - edge - size.X
		end
		x = math.clamp(x, 0, math.max(0, viewport.X - size.X))
		local y = cursor.Y + edge
		if y + size.Y > viewport.Y then
			y = cursor.Y - edge - size.Y
		end
		y = math.clamp(y, 0, math.max(0, viewport.Y - size.Y))
		local c = containerAbsPosRef.current
		return Vector2.new(x - c.X, y - c.Y)
	end

	React.useEffect(function()
		local container = containerRef.current
		if not container then
			return
		end
		local function recompute()
			containerAbsPosRef.current = container.AbsolutePosition
		end
		recompute()
		local conn = container:GetPropertyChangedSignal("AbsolutePosition"):Connect(recompute)
		return function()
			conn:Disconnect()
		end
	end, {})

	React.useEffect(function()
		return DungeonMenuNet.addSnapshotListener(setSnapshot)
	end, {})

	-- Reopening the station (resetKey bumps on every close) should start clean rather than
	-- resuming whatever was picked last time.
	React.useEffect(function()
		setGearUuid(nil)
		setScrollUuid(nil)
		setStatus("")
		setBusy(false)
	end, { props.resetKey })

	-- Places `uuid` into the station slot `target` if the item is legal for it. The only place
	-- gearUuid/scrollUuid get set from an inventory item; click and drop both call this.
	-- (setState functions are stable, so it's safe for the connect-once InputEnded closure below.)
	local function placeInSlot(target: string, uuid: string, item: any): boolean
		if slotForItem(item) ~= target then
			return false
		end
		if target == "gear" then
			setGearUuid(uuid)
		else
			setScrollUuid(uuid)
		end
		setStatus("")
		setHover(nil)
		return true
	end

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
			local target = hoveredTargetRef.current
			if not target then
				return
			end
			-- Guard against a drop resolving after the screen's already been closed mid-drag.
			local player = Players.LocalPlayer
			local playerGui = player and player:FindFirstChild("PlayerGui")
			local gui = playerGui and playerGui:FindFirstChild("EnchantStationGui")
			if gui and gui:IsA("ScreenGui") and not gui.Enabled then
				return
			end
			placeInSlot(target, press.uuid, press.item)
		end)

		return function()
			changedConn:Disconnect()
			endedConn:Disconnect()
		end
	end, {})

	local profile = snapshot and snapshot.profile
	local inv = profile and profile.inventory
	local gearItem = (inv and gearUuid) and inv[gearUuid] or nil
	local scrollItem = (inv and scrollUuid) and inv[scrollUuid] or nil

	local currentEnchant = gearItem and math.floor(tonumber(gearItem.enchantLevel) or 0) or 0
	local successChance = gearItem and EnchantScrollApply.GetSuccessChanceForNextLevel(currentEnchant) or nil
	local atMax = gearItem ~= nil and successChance == nil

	local isOrb = scrollItem ~= nil and ItemDefinitions.IsCraftingOrb(scrollItem.itemId)
	local orbKind = isOrb and ItemDefinitions.GetOrbKind(scrollItem.itemId) or nil
	local orbDef = isOrb and ItemDefinitions.Get(scrollItem.itemId) or nil
	local gearLevel = gearItem and math.floor(tonumber(gearItem.level) or 1) or 1
	local wisdomLevel, wisdomSubs
	if gearItem and orbKind == "Wisdom" then
		wisdomLevel, wisdomSubs = CraftingOrbApply.PreviewWisdom(gearItem)
	end

	local mismatchReason = nil :: string?
	if gearItem and scrollItem and isOrb then
		if not orbDef or math.floor(tonumber(orbDef.Tier) or 1) ~= math.floor(tonumber(gearItem.tier) or 1) then
			mismatchReason = "Orb tier doesn't match gear tier"
		elseif not CraftingOrbApply.IsImplemented(orbKind) then
			mismatchReason = "This orb has no effect yet"
		elseif orbKind == "Wisdom" and not wisdomLevel then
			mismatchReason = "Already at max level (" .. tostring(gearLevel) .. ")"
		end
	elseif gearItem and scrollItem then
		if not ItemDefinitions.IsEnchantScroll(scrollItem.itemId) then
			mismatchReason = "Not an enchant scroll"
		else
			local scrollDef = ItemDefinitions.Get(scrollItem.itemId)
			local target = ItemDefinitions.GetScrollTarget(scrollItem.itemId)
			if target == "Weapon" and gearItem.type ~= "Weapon" then
				mismatchReason = "Scroll only works on weapons"
			elseif target == "Armor" and gearItem.type ~= "Armor" then
				mismatchReason = "Scroll only works on armor"
			elseif not scrollDef or math.floor(tonumber(scrollDef.Tier) or 1) ~= math.floor(tonumber(gearItem.tier) or 1) then
				mismatchReason = "Scroll tier doesn't match gear tier"
			end
		end
	end

	local previewSubs, previewItem, previewBadge
	if isOrb then
		-- Orbs: Wisdom shows the exact next level; Alteration's reroll is random ("?").
		if gearItem and orbKind == "Wisdom" and wisdomSubs then
			previewSubs = wisdomSubs
			previewItem = shallowCopy(gearItem)
			previewItem.subStats = wisdomSubs
			previewItem.level = wisdomLevel
			previewItem.count = 1
			previewBadge = "Lv" .. tostring(wisdomLevel)
		elseif gearItem and orbKind == "Alteration" then
			previewItem = shallowCopy(gearItem)
			previewItem.count = 1
			previewBadge = "?"
		end
	else
		previewSubs = gearItem and EnchantScrollApply.PreviewNextSubStats(gearItem) or nil
		if gearItem and previewSubs then
			previewItem = shallowCopy(gearItem)
			previewItem.subStats = previewSubs
			previewItem.enchantLevel = currentEnchant + 1
			previewItem.count = 1
			previewBadge = "+" .. tostring(currentEnchant + 1)
		end
	end

	local canEnchant = gearItem ~= nil and scrollItem ~= nil and mismatchReason == nil
		and (isOrb or not atMax) and not busy

	local function onEnchant()
		if not canEnchant then
			return
		end
		setBusy(true)
		setStatus(isOrb and "Using orb..." or "Enchanting...")
		local levelBefore = currentEnchant
		local targetUuid = gearUuid
		local ok, err = DungeonMenuNet.requestInventoryAct({
			kind = isOrb and "ApplyCraftingOrb" or "ApplyEnchantScroll",
			scrollUuid = scrollUuid,
			targetUuid = targetUuid,
		})
		setBusy(false)
		if ok and isOrb then
			-- An orb always takes (the server refuses anything it can't apply before consuming).
			setStatus(orbKind == "Alteration" and "Substats rerolled" or "Level increased")
			SfxService.PlayEffect("EnchantSuccess")
			EnchantEffects.PlaySuccess()
		elseif ok then
			setStatus("")
			-- The server RPC only says "the attempt was legal", not whether the roll passed.
			-- requestInventoryAct has already pulled a fresh snapshot by the time it returns,
			-- so the outcome is readable off the item: success is exactly +1; anything else
			-- (reset to +0, or unchanged when a Protection Scroll ate the failure) is a fail.
			local snap = DungeonMenuNet.getLastSnapshot()
			local after = snap and snap.profile and snap.profile.inventory and snap.profile.inventory[targetUuid]
			local levelAfter = after and math.floor(tonumber(after.enchantLevel) or 0) or levelBefore
			if levelAfter == levelBefore + 1 then
				SfxService.PlayEffect("EnchantSuccess")
				EnchantEffects.PlaySuccess()
			else
				SfxService.PlayEffect("EnchantFail")
				EnchantEffects.PlayFail()
			end
		else
			setStatus("Failed: " .. tostring(err))
		end
	end

	-- Odds only mean something once BOTH slots are filled with a legal pairing -- before that
	-- there's no attempt to quote odds for, so the text stays blank rather than showing a
	-- gear-only "100% success".
	local showOdds = gearItem ~= nil and scrollItem ~= nil and mismatchReason == nil
	local successText = ""
	local failureText = ""
	if showOdds and isOrb then
		if orbKind == "Wisdom" then
			successText = "Lv " .. tostring(gearLevel) .. " > " .. tostring(wisdomLevel)
		elseif orbKind == "Alteration" then
			successText = "Reroll"
			failureText = "all substats"
		end
	elseif showOdds then
		if atMax then
			successText = "MAXED"
			failureText = "+9 is the cap"
		elseif successChance then
			successText = string.format("%d%% success", math.floor(successChance * 100 + 0.5))
			failureText = string.format("%d%% failure", math.floor((1 - successChance) * 100 + 0.5))
		end
	end

	----------------------------------------------------------------
	-- Left panel: the real bag grid (InvSlots), hold-drag source. Every callback InvSlots
	-- requires but this screen has no use for (click-to-pick, right-click menu, tooltip,
	-- plain hover) is a no-op -- only onSlotPressStart matters here, arming the same
	-- pressRef the InputChanged/InputEnded connections above already drive.
	----------------------------------------------------------------
	local noop = function() end
	local bagGrid = e(InvSlots, {
		bagSlots = (profile and profile.bagSlots) or {},
		inventory = inv or {},
		heldSlotIndex = nil,
		-- Click-to-place: clicking a bag item sends it straight to whichever station slot it
		-- belongs in (gear -> Gear, scroll -> Enchant), no drag needed.
		onSlotClick = function(_slotIndex, uuid)
			if type(uuid) ~= "string" or uuid == "" then
				return
			end
			local item = inv and inv[uuid]
			if not item then
				return
			end
			local target = slotForItem(item)
			if target then
				placeInSlot(target, uuid, item)
			else
				setStatus("That can't be used at the enchanting station")
			end
		end,
		onSlotRightClick = noop,
		onHoverStart = onHoverItem,
		onHoverEnd = onHoverEnd,
		onSlotEnter = noop,
		onSlotLeave = noop,
		onSlotPressStart = function(_slotIndex, uuid, x, y)
			if type(uuid) ~= "string" or uuid == "" then
				return
			end
			local item = inv and inv[uuid]
			if not item then
				return
			end
			pressRef.current = { uuid = uuid, item = item, startX = x, startY = y, dragging = false }
		end,
	})

	-- Worn gear cells (click -> Gear slot; press + drag -> same drag as the bag grid).
	local equipCells: { [string]: any } = {
		Grid = e("UIGridLayout", {
			CellSize = UDim2.fromOffset(EQUIP_CELL, EQUIP_CELL),
			CellPadding = UDim2.fromOffset(6, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	local equipped = profile and profile.equipped
	local anyEquipped = false
	for order, slotName in ipairs(GEAR_EQUIP_SLOTS) do
		local uuid = type(equipped) == "table" and equipped[slotName] or nil
		local item = (type(uuid) == "string" and inv) and inv[uuid] or nil
		if item and isGearEligible(item) then
			anyEquipped = true
			equipCells[slotName] = e("Frame", {
				LayoutOrder = order,
				BackgroundTransparency = 1,
			}, {
				Item = e(ItemSlot, {
					item = item,
					size = EQUIP_CELL,
					selected = uuid == gearUuid,
					onClick = function()
						placeInSlot("gear", uuid, item)
					end,
					onPressStart = function(x, y)
						pressRef.current = { uuid = uuid, item = item, startX = x, startY = y, dragging = false }
					end,
					onHoverStart = function(x, y)
						onHoverItem(item, x, y)
					end,
					onHoverEnd = onHoverEnd,
				}),
			})
		end
	end
	if not anyEquipped then
		equipCells.None = e("TextLabel", {
			BackgroundTransparency = 1,
			FontFace = UIFonts.Body,
			TextSize = 12,
			TextColor3 = THEME.Muted,
			Text = "Nothing equipped",
		})
	end

	return e("Frame", {
		ref = containerRef,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		LeftPanel = e("Frame", {
			Position = UDim2.fromScale(0.02, 0.08),
			Size = UDim2.fromScale(0.3, 0.84),
			BackgroundColor3 = THEME.PanelBg,
			BackgroundTransparency = 0.05,
			BorderSizePixel = 0,
		}, {
			Stroke = e("UIStroke", { Color = THEME.Border, Thickness = 2 }),
			EquipHeader = e("TextLabel", {
				Position = UDim2.fromOffset(16, 10),
				Size = UDim2.new(1, -32, 0, 22),
				BackgroundTransparency = 1,
				FontFace = UIFonts.DisplayBold,
				TextSize = 15,
				TextColor3 = THEME.Title,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = "EQUIPPED",
			}),
			-- Worn gear, up to two rows of small cells. Click or drag one onto the altar.
			EquipGrid = e("Frame", {
				Position = UDim2.fromOffset(16, 36),
				Size = UDim2.new(1, -32, 0, EQUIP_CELL * 2 + 6),
				BackgroundTransparency = 1,
			}, equipCells),
			Header = e("TextLabel", {
				Position = UDim2.fromOffset(16, 36 + EQUIP_CELL * 2 + 16),
				Size = UDim2.new(1, -32, 0, 22),
				BackgroundTransparency = 1,
				FontFace = UIFonts.DisplayBold,
				TextSize = 15,
				TextColor3 = THEME.Title,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = "INVENTORY",
			}),
			Hint = e("TextLabel", {
				Position = UDim2.fromOffset(16, 36 + EQUIP_CELL * 2 + 38),
				Size = UDim2.new(1, -32, 0, 16),
				BackgroundTransparency = 1,
				FontFace = UIFonts.Body,
				TextSize = 12,
				TextColor3 = THEME.Muted,
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = "Click or drag gear, a scroll or an orb onto the altar",
			}),
			-- InvSlots sizes itself off ITS PARENT's AbsoluteSize (see its own useEffect), so it
			-- just needs a plain sized Frame here, not the ScrollingFrame this used to be --
			-- InvSlots already has its own internal mouse-wheel row-scrolling.
			GridArea = e("Frame", {
				Position = UDim2.fromOffset(16, 36 + EQUIP_CELL * 2 + 60),
				Size = UDim2.new(1, -32, 1, -(36 + EQUIP_CELL * 2 + 76)),
				BackgroundTransparency = 1,
			}, {
				Bag = bagGrid,
			}),
		}),

		RightPanel = e("Frame", {
			Position = UDim2.fromScale(0.48, 0),
			Size = UDim2.fromScale(0.5, 1),
			BackgroundTransparency = 1,
		}, {
			Row = e("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.42),
				Size = UDim2.fromOffset(480, SLOT_SIZE + 22),
				BackgroundTransparency = 1,
			}, {
				Layout = e("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					VerticalAlignment = Enum.VerticalAlignment.Top,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					Padding = UDim.new(0, 18),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),

				-- Explicit LayoutOrder on every child: UIListLayout leaves ties in undefined order
				-- (React builds children from a dictionary), which is what shuffled the result
				-- preview onto the left. Left to right: Gear, Enchant, arrow, Result.
				GearSlot = e(SlotBox, {
					layoutOrder = 1,
					onHoverItem = onHoverItem,
					onHoverEnd = onHoverEnd,
					label = "Gear",
					item = gearItem,
					badge = currentEnchant > 0 and ("+" .. tostring(currentEnchant)) or nil,
					isDropTarget = true,
					hovered = hoveredTarget == "gear",
					onDragEnter = function()
						hoveredTargetRef.current = "gear"
						setHoveredTarget("gear")
					end,
					onDragLeave = function()
						if hoveredTargetRef.current == "gear" then
							hoveredTargetRef.current = nil
						end
						setHoveredTarget(function(v)
							return v == "gear" and nil or v
						end)
					end,
					onClick = gearItem and function()
						setGearUuid(nil)
						setHover(nil)
					end or nil,
				}),

				-- Extra gap between Gear and Enchant (on top of the layout's own Padding).
				GearEnchantSpacer = e("Frame", {
					LayoutOrder = 2,
					Size = UDim2.fromOffset(16, 1),
					BackgroundTransparency = 1,
				}),

				ScrollSlot = e(SlotBox, {
					layoutOrder = 3,
					onHoverItem = onHoverItem,
					onHoverEnd = onHoverEnd,
					label = "Scroll / Orb",
					item = scrollItem,
					isDropTarget = true,
					hovered = hoveredTarget == "enchant",
					onDragEnter = function()
						hoveredTargetRef.current = "enchant"
						setHoveredTarget("enchant")
					end,
					onDragLeave = function()
						if hoveredTargetRef.current == "enchant" then
							hoveredTargetRef.current = nil
						end
						setHoveredTarget(function(v)
							return v == "enchant" and nil or v
						end)
					end,
					onClick = scrollItem and function()
						setScrollUuid(nil)
						setHover(nil)
					end or nil,
				}),

				ArrowColumn = e("Frame", {
					LayoutOrder = 4,
					Size = UDim2.fromOffset(70, SLOT_SIZE + 22),
					BackgroundTransparency = 1,
				}, {
					SuccessText = e("TextLabel", {
						Position = UDim2.fromOffset(0, 4),
						Size = UDim2.new(1, 0, 0, 18),
						BackgroundTransparency = 1,
						FontFace = UIFonts.BodyBold,
						TextSize = 14,
						TextColor3 = THEME.Success,
						TextXAlignment = Enum.TextXAlignment.Center,
						Text = successText,
					}),
					Arrow = e("Frame", {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.47),
						Size = UDim2.fromOffset(58, 28),
						BackgroundTransparency = 1,
					}, {
						Graphic = e(ArrowGraphic, {}),
					}),
					FailureText = e("TextLabel", {
						Position = UDim2.fromOffset(0, SLOT_SIZE - 14),
						Size = UDim2.new(1, 0, 0, 18),
						BackgroundTransparency = 1,
						FontFace = UIFonts.BodyMedium,
						TextSize = 13,
						TextColor3 = THEME.Failure,
						TextXAlignment = Enum.TextXAlignment.Center,
						Text = failureText,
					}),
				}),

				PreviewSlot = e(SlotBox, {
					layoutOrder = 5,
					onHoverItem = onHoverItem,
					onHoverEnd = onHoverEnd,
					label = (previewItem and previewSubs) and formatPrimaryStat(previewItem, previewSubs)
						or (previewItem and "New substats") or "Result",
					item = previewItem,
					badge = previewBadge,
				}),
			}),

			Status = e("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0.68),
				Size = UDim2.fromOffset(420, 20),
				BackgroundTransparency = 1,
				FontFace = UIFonts.Body,
				TextSize = 13,
				TextColor3 = mismatchReason and THEME.Failure or THEME.Muted,
				TextXAlignment = Enum.TextXAlignment.Center,
				Text = mismatchReason or status,
			}),

			EnchantButton = e("TextButton", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0.76),
				Size = UDim2.fromOffset(180, 36),
				BackgroundColor3 = canEnchant and Color3.fromRGB(60, 90, 60) or Color3.fromRGB(40, 40, 40),
				BackgroundTransparency = canEnchant and 0 or 0.15,
				BorderSizePixel = 0,
				FontFace = UIFonts.BodyBold,
				TextSize = 15,
				TextColor3 = canEnchant and Color3.new(1, 1, 1) or Color3.fromRGB(120, 120, 120),
				Text = isOrb and "Use Orb" or "Enchant",
				AutoButtonColor = canEnchant,
				[React.Event.Activated] = canEnchant and onEnchant or nil,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, 8) }),
			}),
		}),

		CloseButton = e("TextButton", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 18),
			Size = UDim2.fromOffset(30, 30),
			BackgroundColor3 = THEME.CloseBg,
			BorderSizePixel = 0,
			FontFace = UIFonts.BodyBold,
			TextSize = 16,
			TextColor3 = Color3.fromRGB(230, 180, 180),
			Text = "X",
			[React.Event.Activated] = props.onClose,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 6) }),
		}),

		-- Hidden while dragging so it doesn't trail the ghost.
		TooltipOverlay = (hover and not drag) and e(Tooltip.Component, {
			item = hover.item,
			position = tooltipPosition(hover.position, Tooltip.EstimateSize(hover.item)),
		}) or nil,

		DragGhost = drag and e("ImageLabel", {
			ref = dragGhostRef,
			Image = ItemDefinitions.GetIconForItem(drag.item),
			Size = UDim2.fromOffset(GHOST_SIZE, GHOST_SIZE),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			ImageTransparency = 0.35,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 100,
		}) or nil,
	})
end

return EnchantStationScreen
