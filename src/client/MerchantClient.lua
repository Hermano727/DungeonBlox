--[[
	MerchantClient
	The Merchant: ore trade, scrap goods (by tier), salvage, potions. The window is NpcShop; the
	content is NpcShop/MerchantBook, a market stall (NpcShop/Stall) with its sections as signs
	under the awning, so the window has no Journal sidebar.
	Opened by MerchantShopClient (the router) with .open(npcId).
]]

local NpcShop = require(script.Parent:WaitForChild("NpcShop"))
local MerchantBook = require(script.Parent.NpcShop:WaitForChild("MerchantBook"))

return NpcShop.window("Merchant", MerchantBook)
