--[[
	AuctionHouseClient
	The Auction House: Browse, Sell, My Listings. The window is NpcShop (a Journal-style book
	with the sections in its sidebar), the spreads are NpcShop/AuctionBook (rebuilt 2026-10-01;
	the old hand-built window was ~1,900 lines). Opened by MerchantShopClient (the router) on
	the Auctioneer's prompt with .open(npcId).
]]

local NpcShop = require(script.Parent:WaitForChild("NpcShop"))
local AuctionBook = require(script.Parent.NpcShop:WaitForChild("AuctionBook"))

return NpcShop.window("AuctionHouse", AuctionBook, { sidebar = true })
