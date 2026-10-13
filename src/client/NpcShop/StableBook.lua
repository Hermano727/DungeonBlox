--!strict
--  NpcShop/StableBook -- the Animal Trainer's stable (rebuilt 2026-10-01): the horses as a
--  Catalog spread, each showing its ride speed (ItemDefinitions MountSpeed). Goods come from
--  NPCRegistry.Get("AnimalTrainer").ShopCatalog (RS/ShopCatalogConfig).
--
--  Mounts are unlocks (2026-10-12, ProfileService UnlockMount / RideMount; profile.mountTier):
--  they unlock in order, T1 then T2 then T3 then T4, and stay unlocked for good. Each row says
--  where you stand with that horse:
--    Riding                the one in your Mount slot
--    Unlocked, ride free   a tier you've unlocked: "Ride" swaps it into the slot at no cost
--    <price>               the next tier: "Buy" unlocks it and you ride it
--    Locked                further up: unlock the one before it first

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local NPCRegistry = require(ReplicatedStorage:WaitForChild("NPCRegistry"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local Keys = require(ReplicatedStorage:WaitForChild("KeybindConfig"))
local Catalog = require(script.Parent:WaitForChild("Catalog"))
local Inventory = script.Parent.Parent:WaitForChild("InventoryHud"):WaitForChild("Inventory")
local InventoryData = require(Inventory:WaitForChild("InventoryData"))
local Style = require(Inventory:WaitForChild("Journal"):WaitForChild("Style"))

local e = React.createElement

-- The tier of the saddle in the Mount slot (0 = none).
local function ridingTier(profile: any): number
	local uuid = profile and profile.equipped and profile.equipped.Mount
	local item = uuid and profile.inventory and profile.inventory[uuid]
	local def = type(item) == "table" and ItemDefinitions.Get(item.itemId) or nil
	return def and math.floor(tonumber(def.Tier) or 0) or 0
end

local function StableBook(props: { npcId: string })
	local snapshot = InventoryData.useSnapshot()
	local reg = NPCRegistry.Get("AnimalTrainer")
	return e(Catalog, {
		npcId = props.npcId,
		snapshot = snapshot,
		entries = reg and reg.ShopCatalog or {},
		heading = "Stable",
		sub = "Horses unlock in order and stay yours.",
		emptyText = "No horses for sale right now.",
		describe = function(_entry, def)
			if def and def.MountSpeed then
				return ("Unlocks this horse for good. It rides in your Mount slot: press %s to call it. "
					.. "Any horse you've unlocked can be ridden again here for free.")
					:format(Keys.DisplayName(Keys.Mount))
			end
			return nil
		end,
		extraLines = function(_entry, def)
			if def and def.MountSpeed then
				return { { "Ride speed", tostring(def.MountSpeed) } }
			end
			return {}
		end,
		entryState = function(entry, profile)
			local def = ItemDefinitions.Get(entry.ItemId)
			if not (def and def.MountSpeed) then return nil end
			local tier = math.floor(tonumber(def.Tier) or 1)
			local unlocked = math.floor(tonumber(profile and profile.mountTier) or 0)
			local name = entry.Label or def.DisplayName or entry.ItemId
			if tier == ridingTier(profile) then
				return { sub = "Riding", subColor = Style.Text.Good, actionText = "Riding", disabled = true }
			elseif tier <= unlocked then
				return { sub = "Unlocked, ride free", subColor = Style.Text.Good, actionText = "Ride", free = true,
					doneText = ("You're riding the %s now."):format(name) }
			elseif tier > unlocked + 1 then
				return { sub = ("Locked: unlock T%d first"):format(tier - 1), subColor = Style.Text.Muted,
					actionText = "Locked", disabled = true }
			end
			return { actionText = "Unlock", doneText = ("Unlocked the %s. It's in your Mount slot."):format(name) }
		end,
	})
end

return StableBook
