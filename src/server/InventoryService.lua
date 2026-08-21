-- InventoryService
-- All inventory mutations live here. The client only ever sends a Request
-- (Move slot A to slot B, Use slot N). The server looks up what is actually
-- in those slots from sessionData and decides whether the action is legal.
-- The client is never trusted with item identity.
--
-- SECOND PROFILE SYSTEM (audited 2026-08-21): this module is the mutation
-- layer for DungeonBlox's OLDER, slot-indexed inventory (PlayerDataManager /
-- DataSchema.Inventory), which coexists with the current DungeonProfileService
-- inventory that InventoryHud's UI actually renders. Full picture is in the
-- header comment at the top of shared/DataSchema.lua. Two things to know
-- before touching this file:
--
--   1. The InventoryReplicate/InventoryRequest RemoteEvents this module fires
--      and listens on have NO client-side listener anywhere in src/client
--      anymore (confirmed by grep across the whole client tree) -- the current
--      UI (InventoryHud -> DungeonMenuUI/DungeonMenuNet) talks to
--      DungeonProfileService instead. Replicate() below still runs correctly,
--      it just replicates into a void: no LocalScript is listening. This
--      module's *outward-facing remote plumbing* is effectively dead; its
--      *data mutation functions* (AddItem/RemoveItem/RecomputeArmor/
--      GetEquippedWeapon) are NOT dead -- see point 2.
--
--   2. AddItem/RemoveItem are called directly (not via the remotes) by
--      PlayerBootstrap.server.lua (starter kit + catch-up grants) and by
--      NPCService.server.lua's buy/sell flow, which deliberately reads and
--      writes BOTH this legacy Inventory AND DungeonProfileService's
--      inventory (see NPCService's countLegacySlots/countDungeonStacks/
--      removeItemAcrossStores) so a player's items don't go missing depending
--      on which store they landed in historically. RecomputeArmor is also
--      the ONLY thing that ever updates Combat.Armor, which DamageService
--      reads for every hit's damage mitigation -- but RecomputeArmor is only
--      ever called from this legacy path (starter-kit equip), never from the
--      live DungeonProfileService-backed equip UI. That is a real gameplay
--      bug (armor mitigation goes stale after the first equip change of the
--      session) that this audit found but did NOT fix, since the fix belongs
--      in DamageService.lua / DungeonBootstrap.server.lua, both outside this
--      pass's scope.
--
-- Net: do not delete this file. It still owns real, live gameplay state.

local HttpService       = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerData      = require(ServerScriptService:WaitForChild("PlayerDataManager"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local InventoryReplicate = ReplicatedStorage:WaitForChild("InventoryReplicate")
local InventoryRequest   = ReplicatedStorage:WaitForChild("InventoryRequest")

local MAX_SLOTS = 30

local InventoryService = {}

local function firstFreeSlot(inv)
	for i = 1, MAX_SLOTS do
		if not inv[i] then return i end
	end
	return nil
end

local function makeSlot(itemId, count, stackable)
	return {
		ItemId = itemId,
		Count  = count,
		UID    = (not stackable) and HttpService:GenerateGUID(false) or nil,
	}
end

function InventoryService.AddItem(player, itemId, count)
	local profile = PlayerData.Get(player); if not profile then return false end
	local def = ItemDefinitions.Get(itemId); if not def then return false end
	count = count or 1
	local maxStack = ItemDefinitions.GetMaxStack(itemId)

	if def.Stackable then
		for i = 1, MAX_SLOTS do
			local slot = profile.Inventory[i]
			if slot and slot.ItemId == itemId and slot.Count < maxStack then
				local room = maxStack - slot.Count
				local add  = math.min(room, count)
				slot.Count = slot.Count + add
				count = count - add
				if count <= 0 then break end
			end
		end
	end

	while count > 0 do
		local slotIdx = firstFreeSlot(profile.Inventory)
		if not slotIdx then
			InventoryService.Replicate(player)
			return false
		end
		local add = def.Stackable and math.min(maxStack, count) or 1
		profile.Inventory[slotIdx] = makeSlot(itemId, add, def.Stackable)
		count = count - add
	end

	InventoryService.Replicate(player)
	return true
end

function InventoryService.RemoveItem(player, itemId, count)
	local profile = PlayerData.Get(player); if not profile then return false end
	count = count or 1
	local remaining = count

	for i = 1, MAX_SLOTS do
		if remaining <= 0 then break end
		local slot = profile.Inventory[i]
		if slot and slot.ItemId == itemId then
			local take = math.min(slot.Count, remaining)
			slot.Count = slot.Count - take
			remaining  = remaining - take
			if slot.Count <= 0 then
				profile.Inventory[i] = nil
				for slotName, equippedIdx in pairs(profile.Equipped) do
					if equippedIdx == i then
						profile.Equipped[slotName] = nil
					end
				end
			end
		end
	end

	InventoryService.Replicate(player)
	return remaining == 0
end

function InventoryService.MoveItem(player, fromSlot, toSlot)
	local profile = PlayerData.Get(player); if not profile then return end
	if type(fromSlot) ~= "number" or type(toSlot) ~= "number" then return end
	if fromSlot < 1 or fromSlot > MAX_SLOTS or toSlot < 1 or toSlot > MAX_SLOTS then return end

	local inv = profile.Inventory
	local a, b = inv[fromSlot], inv[toSlot]

	if a and b and a.ItemId == b.ItemId then
		local def = ItemDefinitions.Get(a.ItemId)
		if def and def.Stackable then
			local maxStack = ItemDefinitions.GetMaxStack(a.ItemId)
			local room = maxStack - b.Count
			local moved = math.min(a.Count, room)
			if moved > 0 then
				b.Count = b.Count + moved
				a.Count = a.Count - moved
				if a.Count <= 0 then
					inv[fromSlot] = nil
				end
				for slotName, equippedIdx in pairs(profile.Equipped) do
					if equippedIdx == fromSlot and inv[fromSlot] == nil then
						profile.Equipped[slotName] = nil
					end
				end
				InventoryService.Replicate(player)
				return
			end
		end
	end

	inv[fromSlot], inv[toSlot] = b, a

	for slotName, equippedIdx in pairs(profile.Equipped) do
		if equippedIdx == fromSlot then
			profile.Equipped[slotName] = toSlot
		elseif equippedIdx == toSlot then
			profile.Equipped[slotName] = fromSlot
		end
	end

	InventoryService.Replicate(player)
end

function InventoryService.UseItem(player, slotIdx)
	local profile = PlayerData.Get(player); if not profile then return end
	local slot = profile.Inventory[slotIdx]; if not slot then return end
	local def = ItemDefinitions.Get(slot.ItemId); if not def then return end

	if def.Kind == "Consumable" then
		if def.HealAmount then
			profile.Combat.HP = math.min(profile.Combat.MaxHP, profile.Combat.HP + def.HealAmount)
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if hum then hum.Health = profile.Combat.HP end
		end
		-- TODO: wire EnergyAmount through your Energy state machine.

		slot.Count = slot.Count - 1
		if slot.Count <= 0 then
			profile.Inventory[slotIdx] = nil
		end

	elseif def.Kind == "Weapon" then
		profile.Equipped.Weapon = slotIdx

	elseif def.Kind == "Armor" then
		if def.Slot then
			profile.Equipped[def.Slot] = slotIdx
		end
	end

	InventoryService.RecomputeArmor(player)
	InventoryService.Replicate(player)
end

function InventoryService.RecomputeArmor(player)
	local profile = PlayerData.Get(player); if not profile then return end
	local total = 0
	for _, equippedIdx in pairs(profile.Equipped) do
		if type(equippedIdx) == "number" then
			local slot = profile.Inventory[equippedIdx]
			if slot then
				local def = ItemDefinitions.Get(slot.ItemId)
				if def and def.Kind == "Armor" and def.Armor then
					total = total + def.Armor
				end
			end
		end
	end
	profile.Combat.Armor = total
end

function InventoryService.GetEquippedWeapon(player)
	local profile = PlayerData.Get(player); if not profile then return nil end
	local idx = profile.Equipped.Weapon
	if not idx then return nil end
	local slot = profile.Inventory[idx]
	if not slot then return nil end
	local def = ItemDefinitions.Get(slot.ItemId)
	if not def or def.Kind ~= "Weapon" then return nil end
	return def
end

function InventoryService.Replicate(player)
	local profile = PlayerData.Get(player); if not profile then return end
	InventoryReplicate:FireClient(player, {
		Inventory = profile.Inventory,
		Equipped  = profile.Equipped,
		Combat    = profile.Combat,
		MaxSlots  = MAX_SLOTS,
	})
end

InventoryRequest.OnServerEvent:Connect(function(player, action, a, b)
	if action == "Move" then
		InventoryService.MoveItem(player, a, b)
	elseif action == "Use" then
		InventoryService.UseItem(player, a)
	elseif action == "Refresh" then
		InventoryService.Replicate(player)
	end
end)

return InventoryService
