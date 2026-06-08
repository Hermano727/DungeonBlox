--[[
	DungeoneerClient
	Handles the Dungeoneer NPC shop UI.
	Tabs: Keys (trade key fragments for dungeon keys) | Scrolls (protection scrolls)
	To change Dungeoneer behaviour: edit THIS file only.
	To change routing:              edit MerchantShopClient only.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NPCRegistry       = require(ReplicatedStorage:WaitForChild("NPCRegistry"))
local ShopClientBase    = require(script.Parent:WaitForChild("ShopClientBase"))
local gameEvents        = ReplicatedStorage:WaitForChild("GameEvents", 10)
local npcRequest        = gameEvents and gameEvents:WaitForChild("NPCRequest", 10)

local function buildContent(scroll, tab, npcId, helpers)
	local reg = NPCRegistry.Get("Dungeoneer")
	if not (reg and reg.ShopCatalog) then
		helpers.emptyLbl.Visible = true; return
	end

	local entries = {}
	for _, entry in ipairs(reg.ShopCatalog) do
		if (entry.ShopTab or "Keys") == tab then
			table.insert(entries, entry)
		end
	end

	if #entries == 0 then helpers.emptyLbl.Visible = true; return end

	for lo, entry in ipairs(entries) do
		ShopClientBase.buildCard(
			scroll, entry, lo, npcId, npcRequest, helpers.coinsRef,
			function(label, res)
				helpers.updateWallet()
				helpers.flashStatus("Received: " .. label, false)
			end
		)
	end
end

local shop = ShopClientBase.create({
	title        = "DUNGEONEER",
	guiName      = "DungeoneerUI",
	tabs         = { "Keys", "Scrolls" },
	firstTab     = "Keys",
	buildContent = buildContent,
})

return shop
