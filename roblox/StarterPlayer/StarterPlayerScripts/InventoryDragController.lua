--[[
	InventoryDragController — drag items between bag, equipment, and hotbar.
	Slot 1 mirrors equipped.Weapon on the server; dropping a Weapon onto slot 1 equips it.
]]

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage:WaitForChild("DungeonProfileTypes"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local DungeonMenuNet = require(script.Parent:WaitForChild("DungeonMenuNet"))
local InventoryHotbarRules = require(script.Parent:WaitForChild("InventoryHotbarRules"))

local InventoryDragController = {}

local DRAG_THRESHOLD = 5

-- Client-side bag display order (persists across server snapshots until menu closes)
local _bagOrder = {}

function InventoryDragController.syncBagOrder(allUuids)
	local newSet = {}
	for _, u in ipairs(allUuids) do newSet[u] = true end
	local filtered = {}
	for _, u in ipairs(_bagOrder) do
		if newSet[u] then
			table.insert(filtered, u)
			newSet[u] = nil
		end
	end
	for _, u in ipairs(allUuids) do
		if newSet[u] then table.insert(filtered, u) end
	end
	_bagOrder = filtered
end

function InventoryDragController.swapBagOrder(uuidA, uuidB)
	local ia, ib
	for i, u in ipairs(_bagOrder) do
		if u == uuidA then ia = i
		elseif u == uuidB then ib = i
		end
	end
	if ia and ib then _bagOrder[ia], _bagOrder[ib] = uuidB, uuidA end
end

function InventoryDragController.getSortedBagItems(bagItems)
	if #_bagOrder == 0 then return bagItems end
	local orderMap = {}
	for i, u in ipairs(_bagOrder) do orderMap[u] = i end
	local sorted = {}
	for _, e in ipairs(bagItems) do table.insert(sorted, e) end
	table.sort(sorted, function(a, b)
		local ia2 = orderMap[a.uuid] or 99999
		local ib2 = orderMap[b.uuid] or 99999
		if ia2 ~= ib2 then return ia2 < ib2 end
		return (a.uuid or "") < (b.uuid or "")
	end)
	return sorted
end

local state = {
	refs = nil,
	getSnapshot = nil,
	active = nil,
	ghost = nil,
	connMove = nil,
	connUp = nil,
}

local function destroyGhost()
	if state.ghost then
		state.ghost:Destroy()
		state.ghost = nil
	end
end

local function pointInGui(px, py, gui)
	if not gui or not gui.AbsolutePosition then
		return false
	end
	local ap = gui.AbsolutePosition
	local as = gui.AbsoluteSize
	return px >= ap.X and px <= ap.X + as.X and py >= ap.Y and py <= ap.Y + as.Y
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

local function dropTargetAt(px, py)
	local refs = state.refs
	if not refs then return nil, nil end
	for slot, btn in pairs(refs.equipButtons or {}) do
		if pointInGui(px, py, btn) then return "equip", slot end
	end
	local hb = refs.hotbarButtons
	if type(hb) == "table" then
		for i = 1, 9 do
			if hb[i] and pointInGui(px, py, hb[i]) then return "hotbar", i end
		end
	end
	-- Check individual bag item buttons first (bag-to-bag swap)
	local scroll = refs.inventoryScroll
	if scroll then
		for _, child in ipairs(scroll:GetChildren()) do
			if child:IsA("GuiButton") then
				local bu = child:GetAttribute("BagUUID")
				if bu and bu ~= "" and pointInGui(px, py, child) then
					return "bag_item", bu
				end
			end
		end
		if pointInGui(px, py, scroll) then return "bag", nil end
	end
	return nil, nil
end

local function clearDragConns()
	if state.connMove then
		state.connMove:Disconnect()
		state.connMove = nil
	end
	if state.connUp then
		state.connUp:Disconnect()
		state.connUp = nil
	end
end

local function finishDrag()
	clearDragConns()
	destroyGhost()
	state.active = nil
end

local function resolveUuidFrom(profile, from)
	if from.kind == "bag" then
		return from.uuid
	end
	if from.kind == "equip" and type(from.slot) == "string" then
		local u = profile.equipped and profile.equipped[from.slot]
		return type(u) == "string" and u ~= "" and u or nil
	end
	if from.kind == "hotbar" and type(from.hotbarIndex) == "number" then
		local u = profile.hotbar and profile.hotbar[from.hotbarIndex]
		return type(u) == "string" and u ~= "" and u or nil
	end
	return nil
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
		if not InventoryHotbarRules.mayAssignToHotbarSlot(targetSlot, it) then
			return
		end
		if InventoryHotbarRules.isWeaponMirrorSlot(targetSlot) then
			DungeonMenuNet.requestEquip(uuid)
			return
		end
		-- Hotbar -> hotbar drag: swap the two slots instead of overwriting.
		-- The old behavior (SetHotbar) silently kicked the target item out of the hotbar
		-- (back to bag) which looked like two slots being unequipped at once.
		if from.kind == "hotbar" and type(from.hotbarIndex) == "number" then
			local fromIdx = from.hotbarIndex
			if fromIdx == targetSlot then
				return
			end
			-- Slot 1 mirrors equipped weapon; don't let the user drag it onto a non-weapon slot.
			-- (Slot 1 -> slot 1 already handled above; slot N -> slot 1 with a weapon goes through requestEquip.)
			if InventoryHotbarRules.isWeaponMirrorSlot(fromIdx) then
				return
			end
			DungeonMenuNet.requestInventoryAct({ kind = "SwapHotbar", a = fromIdx, b = targetSlot })
			return
		end
		DungeonMenuNet.requestInventoryAct({ kind = "SetHotbar", slot = targetSlot, uuid = uuid })
		return
	end

	if targetKind == "bag_item" and type(targetSlot) == "string" then
		if from.kind == "bag" then
			local fromUuid = resolveUuidFrom(profile, from)
			if fromUuid and fromUuid ~= targetSlot then
				InventoryDragController.swapBagOrder(fromUuid, targetSlot)
			end
		elseif from.kind == "hotbar" and type(from.hotbarIndex) == "number" then
			if from.hotbarIndex == InventoryHotbarRules.WEAPON_SLOT then
				DungeonMenuNet.requestUnequip("Weapon")
			else
				DungeonMenuNet.requestInventoryAct({ kind = "SetHotbar", slot = from.hotbarIndex, uuid = nil })
			end
		end
		return
	end

	if targetKind == "bag" then
		if from.kind == "equip" and type(from.slot) == "string" then
			DungeonMenuNet.requestUnequip(from.slot)
		elseif from.kind == "hotbar" and type(from.hotbarIndex) == "number" then
			if from.hotbarIndex == InventoryHotbarRules.WEAPON_SLOT then
				DungeonMenuNet.requestUnequip("Weapon")
			else
				DungeonMenuNet.requestInventoryAct({ kind = "SetHotbar", slot = from.hotbarIndex, uuid = nil })
			end
		end
	end
end

function InventoryDragController.install(refs, getSnapshot)
	state.refs = refs
	state.getSnapshot = getSnapshot
end

function InventoryDragController.bindStaticSources(refs)
	for slot, btn in pairs(refs.equipButtons or {}) do
		InventoryDragController.hookSource("equip", btn, { equipSlot = slot })
	end
	for i = 1, 9 do
		local b = refs.hotbarButtons and refs.hotbarButtons[i]
		if b then
			InventoryDragController.hookSource("hotbar", b, { hotbarIndex = i })
		end
	end
end

function InventoryDragController.hookSource(kind, guiObject, payload)
	if not guiObject or not guiObject:IsA("GuiButton") then
		return
	end
	guiObject.MouseButton1Down:Connect(function()
		local start = UserInputService:GetMouseLocation()
		state.active = {
			kind = kind,
			uuid = payload and payload.uuid,
			slot = payload and payload.equipSlot,
			hotbarIndex = payload and payload.hotbarIndex,
			start = start,
			moved = false,
		}
		clearDragConns()
		state.connMove = UserInputService.InputChanged:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseMovement then
				return
			end
			local a = state.active
			if not a then
				return
			end
			local now = UserInputService:GetMouseLocation()
			if (Vector2.new(now.X, now.Y) - Vector2.new(a.start.X, a.start.Y)).Magnitude >= DRAG_THRESHOLD then
				a.moved = true
				if not state.ghost then
					local lp = Players.LocalPlayer
					local pg = lp and lp:FindFirstChildOfClass("PlayerGui")
					if not pg then
						return
					end
					local snap = state.getSnapshot and state.getSnapshot()
					local prof = snap and snap.profile
					local uuid = resolveUuidFrom(prof or {}, a)
					local it = prof and uuid and prof.inventory and prof.inventory[uuid]
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
					f.Parent = sg
					sg.Parent = pg
					state.ghost = sg
				end
			end
			if state.ghost then
				local fr = state.ghost:FindFirstChildWhichIsA("Frame")
				if fr then
					local m = UserInputService:GetMouseLocation()
					fr.Position = UDim2.fromOffset(m.X, m.Y)
				end
			end
		end)
		state.connUp = UserInputService.InputEnded:Connect(function(input, _gp)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
				return
			end
			local a = state.active
			if not a then
				finishDrag()
				return
			end
			-- Consume the drag session before dispatch so a duplicate InputEnded cannot performDrop twice.
			state.active = nil
			clearDragConns()
			local now = UserInputService:GetMouseLocation()
			local dist = (Vector2.new(now.X, now.Y) - Vector2.new(a.start.X, a.start.Y)).Magnitude
			if not a.moved and dist < DRAG_THRESHOLD then
				-- Click-only equip from bag removed: use drag to hotbar (1-9). Legacy equipped.* slots are not assigned from a plain left click.
			else
				local tk, ts = dropTargetAt(now.X, now.Y)
				if tk then
					performDrop(a, tk, ts)
				end
			end
			destroyGhost()
		end)
	end)
end

return InventoryDragController
