--[[
	AnimalTrainerClient
	The Animal Trainer's stable: mount saddles. The window is NpcShop (a Journal-style book), the
	spread is NpcShop/StableBook. Opened by MerchantShopClient (the router) with .open(npcId).
]]

local NpcShop = require(script.Parent:WaitForChild("NpcShop"))
local StableBook = require(script.Parent.NpcShop:WaitForChild("StableBook"))

return NpcShop.window("AnimalTrainer", StableBook)
