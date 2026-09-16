local Keys = require(game:GetService("ReplicatedStorage"):WaitForChild("KeybindConfig"))
--[[
	InventoryDragController — move items between bag, equipment, and hotbar.
	Minecraft-style model: all 9 hotbar slots behave identically, no reserved weapon slot.
	Two supported gestures, both ending at the same performDrop dispatch:
	  1. Click-to-pick-up / click-to-place: click once to pick an item up (it follows the
	     cursor), click a destination to place it there (swaps if occupied). Click the same
	     slot again, or right-click, to cancel. Nothing is mutated server-side until the
	     placing click, so cancelling is free.
	  2. Press-and-hold-drag: press and hold on an occupied slot, move past a small
	     threshold, release over the destination. Releasing without crossing the threshold
	     is treated as a plain click instead (falls through to gesture 1).
]]

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("ProfileTypes"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local DungeonMenuNet = require(script.Parent:WaitForChild("DungeonMenuNet"))
local InventoryHotbarRules = require(script.Parent:WaitForChild("InventoryHotbarRules"))

local InventoryDragController = {}

local function hotbarSlotUuid(hb, i)
	if type(hb) ~= "table" then return nil end
	i = math.floor(tonumber(i) or -1)
	if i < 1 or i > 9 then return nil end
	local v = hb[i]
	if type(v) == "string" and v ~= "" then return v end
	v = hb[tostring(i)]
	if type(v) == "string" and v ~= "" then return v end
	return nil
end

local state = {
	refs = nil,
	getSnapshot = nil,
	ghost = nil,
}

local function destroyGhost()
	if state.ghost then
		state.ghost:Destroy()
		state.ghost = nil
	end
end

local function resolveHotbarSlotIndex(btn, fallback)
	if typeof(btn) ~= "Instance" then return fallback end
	local parsed = tonumber(btn:GetAttribute("HotbarSlot"))
		or tonumber(tostring(btn.Name):match("^HB(%d+)$"))
	if parsed then
		local slot = math.floor(parsed)
		if slot >= 1 and slot <= 9 then return slot end
	end
	return fallback
end

local function getItemFromProfile(profile, uuid)
	if not profile or type(uuid) ~= "string" or uuid == "" then
		return nil
	end
	return profile.inventory and profile.inventory[uuid]
end

local function allowedEquipSlotForItem(item)
	if not item then
		return nil
	end
	local slot = Types.GetAllowedEquipSlot(item)
	if slot == "Armor" then
		local def = ItemDefinitions.Get(item.itemId)
		return def and def.Slot or "Chest"
	end
	return slot
end

local DRAG_THRESHOLD = 5

local function resolveUuidFrom(profile, from)
	if from.kind == "bag" then
		return from.uuid
	end
	if from.kind == "equip" and type(from.slot) == "string" then
		local u = profile.equipped and profile.equipped[from.slot]
		return type(u) == "string" and u ~= "" and u or nil
	end
	if from.kind == "hotbar" and type(from.hotbarIndex) == "number" then
		local u = profile.hotbar and hotbarSlotUuid(profile.hotbar, from.hotbarIndex)
		return type(u) == "string" and u ~= "" and u or nil
	end
	return nil
end

-- Shared by drag-and-drop and the hover+number-key path (section 3 of the hotbar refactor):
-- both must dispatch the exact same server actions, not a third code path.
local function performHotbarToHotbarSwap(fromIdx, targetSlot)
	if fromIdx == targetSlot then
		return
	end
	DungeonMenuNet.requestInventoryAct({ kind = "SwapHotbar", a = fromIdx, b = targetSlot })
end

local function performAssignToHotbar(uuid, targetSlot, it)
	if not InventoryHotbarRules.mayAssignToHotbarSlot(targetSlot, it) then
		return
	end
	DungeonMenuNet.requestInventoryAct({ kind = "SetHotbar", slot = targetSlot, uuid = uuid })
end

local function performDrop(from, targetKind, targetSlot)
	local snap = state.getSnapshot and state.getSnapshot()
	local profile = snap and snap.profile
	if not profile then
		return
	end

	if targetKind == "equip" and targetSlot then
		local uuid = resolveUuidFrom(profile, from)
		if not uuid then
			return
		end
		local it = getItemFromProfile(profile, uuid)
		if not it then
			return
		end
		local want = allowedEquipSlotForItem(it)
		if want and targetSlot ~= want then
			return
		end
		DungeonMenuNet.requestEquip(uuid)
		return
	end

	if targetKind == "hotbar" and type(targetSlot) == "number" then
		local uuid = resolveUuidFrom(profile, from)
		if not uuid then return end
		local it = getItemFromProfile(profile, uuid)
		-- Hotbar -> hotbar drag: swap the two slots instead of overwriting.
		-- The old behavior (SetHotbar) silently kicked the target item out of the hotbar
		-- (back to bag) which looked like two slots being unequipped at once.
		if from.kind == "hotbar" and type(from.hotbarIndex) == "number" then
			performHotbarToHotbarSwap(from.hotbarIndex, targetSlot)
			return
		end
		performAssignToHotbar(uuid, targetSlot, it)
		return
	end

	if targetKind == "bag" and type(targetSlot) == "number" then
		local uuid = resolveUuidFrom(profile, from)
		if not uuid then
			return
		end
		-- Bag -> bag: swap the two slots instead of overwriting (same reasoning as the
		-- hotbar -> hotbar swap above).
		if from.kind == "bag" and type(from.bagSlot) == "number" then
			if from.bagSlot == targetSlot then
				return
			end
			DungeonMenuNet.requestInventoryAct({ kind = "SwapBagSlot", a = from.bagSlot, b = targetSlot })
			return
		end
		DungeonMenuNet.requestInventoryAct({ kind = "SetBagSlot", slot = targetSlot, uuid = uuid })
		return
	end
end

function InventoryDragController.install(refs, getSnapshot)
	state.refs = refs
	state.getSnapshot = getSnapshot
end

-- ── Hover + number-key hotbar assign/swap (Minecraft-style) ────────────────────────────
-- Reuses the exact MouseEnter/MouseLeave enumeration DungeonMenuUI already builds for
-- tooltips (it calls setHoveredBag/setHoveredHotbar from those same callbacks) instead of
-- standing up a second hover-tracking system.

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local hover = { kind = nil, bagUuid = nil, bagSlot = nil, hotbarIndex = nil, equipSlot = nil }

-- `uuid` may be nil (an empty bag slot is still a valid hover target -- it's a valid
-- click-to-place / drag-release destination, just not a pickup source).
function InventoryDragController.setHoveredBag(uuid, bagSlot)
	hover.kind = "bag"
	hover.bagUuid = uuid
	hover.bagSlot = bagSlot
	hover.hotbarIndex = nil
end

function InventoryDragController.clearHoveredBag(bagSlot)
	if hover.kind == "bag" and hover.bagSlot == bagSlot then
		hover.kind = nil
		hover.bagUuid = nil
		hover.bagSlot = nil
	end
end

function InventoryDragController.setHoveredHotbar(slotIndex)
	hover.kind = "hotbar"
	hover.hotbarIndex = slotIndex
	hover.bagUuid = nil
end

function InventoryDragController.clearHoveredHotbar(slotIndex)
	if hover.kind == "hotbar" and hover.hotbarIndex == slotIndex then
		hover.kind = nil
		hover.hotbarIndex = nil
	end
end

function InventoryDragController.setHoveredEquip(slotName)
	hover.kind = "equip"
	hover.equipSlot = slotName
	hover.bagUuid = nil
	hover.hotbarIndex = nil
end

function InventoryDragController.clearHoveredEquip(slotName)
	if hover.kind == "equip" and hover.equipSlot == slotName then
		hover.kind = nil
		hover.equipSlot = nil
	end
end

local function isMenuOpen()
	local g = playerGui:FindFirstChild("SkillsPopupUI", true)
	return g and g:IsA("ScreenGui") and g.Enabled
end

-- Hover + number-key QUICK-EQUIP (post hotbar-refactor shape): Keys.ToolSlot maps a
-- keycode to an equip-panel SLOT NAME ("Weapon"|"Bow"|"Pickaxe"|"FishingSpear"), not a
-- 1-9 hotbar index -- the freeform 9-slot hotbar this used to key off of
-- (Keys.HotbarSlot, SetHotbar/SwapHotbar) no longer exists: KeybindConfig dropped
-- HotbarSlot for ToolSlot, and ProfileBootstrap.server.lua's DungeonInventoryAct
-- dispatcher never implemented SetHotbar/SwapHotbar in the first place (only
-- SetBagSlot/SwapBagSlot). Indexing the old (now-nil) Keys.HotbarSlot table crashed with
-- "attempt to index nil with EnumItem" every time a 1-4 key was pressed with the Skills
-- menu open. Rewritten to equip the hovered bag item into its matching tool slot via the
-- same real DungeonMenuNet.requestEquip(...) call the drag-to-equip gesture already uses.
local KEY_TO_TOOL_SLOT = Keys.ToolSlot

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	local targetToolSlot = KEY_TO_TOOL_SLOT[input.KeyCode]
	if not targetToolSlot then
		return
	end
	if not isMenuOpen() then
		return
	end
	if hover.kind == "bag" and type(hover.bagUuid) == "string" and hover.bagUuid ~= "" then
		local snap = state.getSnapshot and state.getSnapshot()
		local profile = snap and snap.profile
		if not profile then
			return
		end
		local it = getItemFromProfile(profile, hover.bagUuid)
		if it and allowedEquipSlotForItem(it) == targetToolSlot then
			DungeonMenuNet.requestEquip(hover.bagUuid)
		end
	end
end)

function InventoryDragController.bindStaticSources(refs)
	for slot, btn in pairs(refs.equipButtons or {}) do
		InventoryDragController.hookSource("equip", btn, { equipSlot = slot })
	end
	local row = refs.hotbarRow
	if row then
		for _, child in ipairs(row:GetChildren()) do
			if child:IsA("GuiButton") then
				local slot = resolveHotbarSlotIndex(child, nil)
				if slot then
					child:SetAttribute("HotbarSlot", slot)
					if refs.hotbarButtons then
						refs.hotbarButtons[slot] = child
					end
					if not child:GetAttribute("_InvDragHooked") then
						InventoryDragController.hookSource("hotbar", child, {})
					end
				end
			end
		end
	end
end

-- ── Shared slot-identity resolution (used by both the click and hold-drag gestures) ──────

-- Reads the static identity of a hooked button: which hotbar slot / bag slot it is.
-- Bag buttons are rebuilt every redraw, so this always reads live attributes rather than
-- anything captured at hook time.
local function resolveSlotIdentity(kind, guiObject)
	local hotbarIndex, bagSlot, bagUuid
	if kind == "hotbar" then
		hotbarIndex = resolveHotbarSlotIndex(guiObject, nil)
	elseif kind == "bag" then
		bagSlot = tonumber(guiObject:GetAttribute("BagSlot"))
		local bu = guiObject:GetAttribute("BagUUID")
		bagUuid = (type(bu) == "string" and bu ~= "") and bu or nil
	end
	return hotbarIndex, bagSlot, bagUuid
end

-- Resolves the uuid currently occupying a slot, given the profile snapshot.
local function resolveItemUuidAt(profile, kind, srcSlot, hotbarIndex, bagUuid)
	if kind == "bag" then
		return bagUuid
	elseif kind == "hotbar" then
		return hotbarSlotUuid(profile.hotbar, hotbarIndex)
	elseif kind == "equip" then
		local u = profile.equipped and profile.equipped[srcSlot]
		return (type(u) == "string" and u ~= "") and u or nil
	end
	return nil
end

-- ── Click-to-pick-up / click-to-place state machine ────────────────────────────────────

local held = nil -- { kind, uuid, slot (equip name), hotbarIndex, bagSlot }

local function clearHeld()
	held = nil
	destroyGhost()
end

local function sameSlot(a, b)
	if a.kind ~= b.kind then
		return false
	end
	if a.kind == "hotbar" then
		return a.hotbarIndex == b.hotbarIndex
	end
	if a.kind == "bag" then
		return a.bagSlot == b.bagSlot
	end
	if a.kind == "equip" then
		return a.slot == b.slot
	end
	return false
end

local function showGhost()
	destroyGhost()
	local lp = Players.LocalPlayer
	local pg = lp and lp:FindFirstChildOfClass("PlayerGui")
	if not pg or not held then
		return
	end
	local snap = state.getSnapshot and state.getSnapshot()
	local prof = snap and snap.profile
	local it = prof and held.uuid and prof.inventory and prof.inventory[held.uuid]
	local sg = Instance.new("ScreenGui")
	sg.Name = "InventoryDragGhost"
	sg.DisplayOrder = 1000
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	local f = Instance.new("Frame")
	f.Size = UDim2.fromOffset(56, 56)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BackgroundColor3 = Color3.fromRGB(40, 34, 34)
	f.BorderSizePixel = 0
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, 8)
	local t = Instance.new("TextLabel", f)
	t.BackgroundTransparency = 1
	t.Size = UDim2.new(1, -4, 1, -4)
	t.Font = Enum.Font.GothamMedium
	t.TextSize = 9
	t.TextWrapped = true
	t.TextColor3 = Color3.new(1, 1, 1)
	t.Text = it and (it.name or it.itemId or "") or "?"
	local m = UserInputService:GetMouseLocation()
	f.Position = UDim2.fromOffset(m.X, m.Y)
	f.Parent = sg
	sg.Parent = pg
	state.ghost = sg
end

-- ── Hold-and-drag gesture ──────────────────────────────────────────────────────
-- A press that crosses DRAG_THRESHOLD before release adopts `held`/the ghost (the same
-- state the click gesture uses) so both gestures share one visual + one performDrop call.
-- A press that DOESN'T cross the threshold is left alone here -- it falls through to the
-- source button's own MouseButton1Click (the plain click-to-pick-up/place handler below).

local dragSession = nil -- { kind, uuid, slot, hotbarIndex, bagSlot, startPos, dragging }

local function clearDragSession()
	dragSession = nil
end

-- Ghost follows the cursor continuously while something is held, whether it got there via
-- a discrete click or a drag that just crossed the threshold.
UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseMovement then
		return
	end
	if dragSession and not dragSession.dragging then
		local now = UserInputService:GetMouseLocation()
		local start = dragSession.startPos
		if (Vector2.new(now.X, now.Y) - Vector2.new(start.X, start.Y)).Magnitude >= DRAG_THRESHOLD then
			dragSession.dragging = true
			-- A fresh drag-out always takes over from whatever was previously held by a
			-- discrete click -- only one item can be "in hand" at a time.
			held = {
				kind = dragSession.kind, uuid = dragSession.uuid, slot = dragSession.slot,
				hotbarIndex = dragSession.hotbarIndex, bagSlot = dragSession.bagSlot,
			}
			showGhost()
		end
	end
	if not held or not state.ghost then
		return
	end
	local fr = state.ghost:FindFirstChildWhichIsA("Frame")
	if fr then
		local m = UserInputService:GetMouseLocation()
		fr.Position = UDim2.fromOffset(m.X, m.Y)
	end
end)

-- Drag-release target resolution reuses the SAME hover state the number-key feature reads,
-- rather than re-deriving "what's under the cursor" via manual AbsolutePosition math: Roblox's
-- own GuiButton MouseEnter/Leave already handles coordinate-space/scaling correctly, so this
-- is more robust than a second, hand-rolled hit-test (which is what used to live here, via
-- dropTargetAt/pointInGui -- removed because it could silently miss the release target).
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	local session = dragSession
	dragSession = nil
	if not session or not session.dragging then
		-- Never crossed the threshold: this was a plain click, already handled (or about to
		-- be handled) by the source button's own MouseButton1Click.
		return
	end
	if held and hover.kind then
		local targetSlot
		if hover.kind == "hotbar" then
			targetSlot = hover.hotbarIndex
		elseif hover.kind == "bag" then
			targetSlot = hover.bagSlot
		elseif hover.kind == "equip" then
			targetSlot = hover.equipSlot
		end
		if targetSlot ~= nil then
			performDrop(held, hover.kind, targetSlot)
		end
	end
	clearHeld()
end)

-- Clear any held/in-progress drag if the menu closes mid-gesture (nothing was mutated
-- server-side during pickup, so this is just dropping client-only state -- no item is lost).
task.spawn(function()
	local popup
	repeat
		popup = playerGui:FindFirstChild("SkillsPopupUI", true)
		if not popup then task.wait(0.5) end
	until popup
	popup:GetPropertyChangedSignal("Enabled"):Connect(function()
		if not popup.Enabled then
			clearHeld()
			clearDragSession()
		end
	end)
end)

function InventoryDragController.hookSource(kind, guiObject, payload)
	if not guiObject or not guiObject:IsA("GuiButton") then
		return
	end
	if guiObject:GetAttribute("_InvDragHooked") then
		return
	end
	guiObject:SetAttribute("_InvDragHooked", true)
	local srcSlot = payload and payload.equipSlot

	-- Drag-start: only arms a dragSession if the slot is occupied (nothing to drag out of
	-- an empty slot). Whether this turns into an actual drag is decided by the global
	-- InputChanged threshold check above.
	guiObject.MouseButton1Down:Connect(function()
		local hotbarIndex, bagSlot, bagUuid = resolveSlotIdentity(kind, guiObject)
		local snap = state.getSnapshot and state.getSnapshot()
		local profile = snap and snap.profile
		if not profile then return end
		local uuid = resolveItemUuidAt(profile, kind, srcSlot, hotbarIndex, bagUuid)
		if type(uuid) ~= "string" or uuid == "" then return end
		dragSession = {
			kind = kind, uuid = uuid, slot = srcSlot, hotbarIndex = hotbarIndex, bagSlot = bagSlot,
			startPos = UserInputService:GetMouseLocation(), dragging = false,
		}
	end)

	guiObject.MouseButton1Click:Connect(function()
		local hotbarIndex, bagSlot, bagUuid = resolveSlotIdentity(kind, guiObject)

		local snap = state.getSnapshot and state.getSnapshot()
		local profile = snap and snap.profile
		if not profile then return end

		local here = { kind = kind, uuid = bagUuid, slot = srcSlot, hotbarIndex = hotbarIndex, bagSlot = bagSlot }

		if not held then
			-- Nothing held yet (and no drag just happened -- the threshold-crossing branch
			-- already populates `held` itself, see InputChanged above): only pick up if this
			-- slot is actually occupied.
			local uuid = resolveItemUuidAt(profile, kind, srcSlot, hotbarIndex, bagUuid)
			if type(uuid) ~= "string" or uuid == "" then return end
			here.uuid = uuid
			held = here
			showGhost()
			return
		end

		-- Something already held: clicking its own source slot again cancels the pickup.
		if sameSlot(held, here) then
			clearHeld()
			return
		end

		local targetSlot = hotbarIndex or bagSlot or srcSlot
		performDrop(held, kind, targetSlot)
		clearHeld()
	end)

	guiObject.MouseButton2Click:Connect(function()
		if held then
			clearHeld()
		end
	end)
end

return InventoryDragController
