--[[
	ItemBinding -- ReplicatedStorage (2026-10-12)

	How tightly an item is tied to its owner. One rule, asked everywhere:

	  nil            a normal item: tradeable, droppable (it lands on the ground for anyone),
	                 lost from the bag on death.
	  "untradeable"  can't change hands. Can't be auctioned; dropped (or lost on death) it
	                 VANISHES instead of landing on the ground, so it can't be passed on.
	                 Trashing still works. Training gear, anything with `Untradeable = true`.
	  "bound"        profile-bound: untradeable, and there's no way to lose it at all: can't
	                 be dropped or trashed, never lost on death. Profession tools (Pickaxe /
	                 FishingSpear slots) and saddles (the Mount slot), or `Soulbound = true`.

	Asked by: DeathProtection (bound survives), DeathLootService (untradeable vanishes instead
	of dropping), ProfileService.DropItem / TrashItem, AuctionHouseService, and the inventory UI
	(right-click menu, tooltip).

		ItemBinding.Level(item)          nil | "untradeable" | "bound"
		ItemBinding.IsBound(item)        profile-bound
		ItemBinding.IsUntradeable(item)  untradeable OR bound (neither can change hands)
	`item` = an owned item table, or an itemId string.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local ItemBinding = {}

ItemBinding.UNTRADEABLE = "untradeable"
ItemBinding.BOUND = "bound"

-- Equip slots whose items are always profile-bound.
ItemBinding.BOUND_SLOTS = { Pickaxe = true, FishingSpear = true, Mount = true }

local function parts(item: any): (any?, any?)
	local itemId = type(item) == "string" and item or (type(item) == "table" and item.itemId) or nil
	local def = type(itemId) == "string" and ItemDefinitions.Get(itemId) or nil
	return (type(item) == "table") and item or nil, def
end

function ItemBinding.IsBound(item: any): boolean
	local record, def = parts(item)
	if record and type(record.equipSlot) == "string" and ItemBinding.BOUND_SLOTS[record.equipSlot] then
		return true
	end
	if not def then return false end
	if def.Soulbound == true then return true end
	if type(def.Slot) == "string" and ItemBinding.BOUND_SLOTS[def.Slot] then return true end
	return tonumber(def.MountSpeed) ~= nil -- a saddle, even one minted before saddles had a Slot
end

function ItemBinding.Level(item: any): string?
	if ItemBinding.IsBound(item) then return ItemBinding.BOUND end
	local record, def = parts(item)
	if (record and record.untradeable == true) or (def and def.Untradeable == true) then
		return ItemBinding.UNTRADEABLE
	end
	return nil
end

function ItemBinding.IsUntradeable(item: any): boolean
	return ItemBinding.Level(item) ~= nil
end

return ItemBinding
