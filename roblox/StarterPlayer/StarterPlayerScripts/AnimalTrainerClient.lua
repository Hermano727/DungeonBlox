--[[
	AnimalTrainerClient
	Handles the Animal Trainer NPC shop UI.
	Shows all mount saddles in a simple grid (no tabs).
	To change Animal Trainer behaviour: edit THIS file only.
	To change routing:                  edit MerchantShopClient only.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NPCRegistry       = require(ReplicatedStorage:WaitForChild("NPCRegistry"))
local ItemDefinitions   = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local ShopClientBase    = require(script.Parent:WaitForChild("ShopClientBase"))
local gameEvents        = ReplicatedStorage:WaitForChild("GameEvents", 10)
local npcRequest        = gameEvents and gameEvents:WaitForChild("NPCRequest", 10)

local function buildContent(scroll, _tab, npcId, helpers)
	local reg = NPCRegistry.Get("AnimalTrainer")
	if not (reg and reg.ShopCatalog) then
		helpers.emptyLbl.Visible = true; return
	end

	if #reg.ShopCatalog == 0 then helpers.emptyLbl.Visible = true; return end

	for lo, entry in ipairs(reg.ShopCatalog) do
		-- Enrich description with mount speed from ItemDefinitions
		local def = ItemDefinitions.Get(entry.ItemId)
		local enriched = {}
		for k, v in pairs(entry) do enriched[k] = v end
		if def and def.MountSpeed then
			enriched._descOverride = string.format(
				"A mount saddle granting %.0f WalkSpeed. Equip from your hotbar to summon your horse.",
				def.MountSpeed
			)
		end

		ShopClientBase.buildCard(
			scroll, enriched, lo, npcId, npcRequest, helpers.coinsRef,
			function(label, res)
				helpers.updateWallet()
				helpers.flashStatus("Purchased: " .. label, false)
			end
		)
	end
end

local shop = ShopClientBase.create({
	title        = "ANIMAL TRAINER",
	guiName      = "AnimalTrainerUI",
	tabs         = nil,   -- no sidebar; single grid view
	firstTab     = nil,
	buildContent = buildContent,
})

return shop
