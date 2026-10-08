--[[
	MerchantClient
	The Merchant: ore trade, scrap goods (by tier), salvage, potions. The window is NpcShop (a
	Journal-style book with the sections in its sidebar), the spreads are NpcShop/MerchantBook.
	Opened by MerchantShopClient (the router) with .open(npcId).
]]

local NpcShop = require(script.Parent:WaitForChild("NpcShop"))
local MerchantBook = require(script.Parent.NpcShop:WaitForChild("MerchantBook"))

return NpcShop.window("Merchant", MerchantBook, { sidebar = true })
