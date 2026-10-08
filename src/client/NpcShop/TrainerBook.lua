--!strict
--  NpcShop/TrainerBook -- the Skill Trainer's wares (2026-10-01; was the old NPCClient shop
--  panel): a Catalog spread over NPCRegistry.Get("SkillTrainer").ShopCatalog.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local NPCRegistry = require(ReplicatedStorage:WaitForChild("NPCRegistry"))
local Catalog = require(script.Parent:WaitForChild("Catalog"))
local InventoryData = require(script.Parent.Parent:WaitForChild("InventoryHud"):WaitForChild("Inventory"):WaitForChild("InventoryData"))

local e = React.createElement

local function TrainerBook(props: { npcId: string })
	local snapshot = InventoryData.useSnapshot()
	local reg = NPCRegistry.Get("SkillTrainer")
	return e(Catalog, {
		npcId = props.npcId,
		snapshot = snapshot,
		entries = reg and reg.ShopCatalog or {},
		heading = "Skill Trainer",
		sub = "Tools of the trade.",
	})
end

return TrainerBook
