--!strict
--  NpcShop/StableBook -- the Animal Trainer's stable (rebuilt 2026-10-01): mount saddles as a
--  Catalog spread, each showing its ride speed (ItemDefinitions MountSpeed). Goods come from
--  NPCRegistry.Get("AnimalTrainer").ShopCatalog (RS/ShopCatalogConfig).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local NPCRegistry = require(ReplicatedStorage:WaitForChild("NPCRegistry"))
local Catalog = require(script.Parent:WaitForChild("Catalog"))
local InventoryData = require(script.Parent.Parent:WaitForChild("InventoryHud"):WaitForChild("Inventory"):WaitForChild("InventoryData"))

local e = React.createElement

local function StableBook(props: { npcId: string })
	local snapshot = InventoryData.useSnapshot()
	local reg = NPCRegistry.Get("AnimalTrainer")
	return e(Catalog, {
		npcId = props.npcId,
		snapshot = snapshot,
		entries = reg and reg.ShopCatalog or {},
		heading = "Stable",
		sub = "Saddles for your horse.",
		emptyText = "No saddles for sale right now.",
		describe = function(_entry, def)
			if def and def.MountSpeed then
				return "A saddle for your horse. Put it on your hotbar and use it to ride."
			end
			return nil
		end,
		extraLines = function(_entry, def)
			if def and def.MountSpeed then
				return { { "Ride speed", tostring(def.MountSpeed) } }
			end
			return {}
		end,
	})
end

return StableBook
