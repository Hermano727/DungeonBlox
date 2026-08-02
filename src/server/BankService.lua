--[[
  BankService (Server)
  Coin bank: inventory coin items <-> wallet (currencies.Coins).
  DepositAll moves every Coins stack from bags into the spendable wallet.
  WithdrawAll moves the full wallet back into inventory as Coins items (max stack 100).
]]

local ServerScriptService = game:GetService("ServerScriptService")

local DungeonProfile = require(ServerScriptService:WaitForChild("DungeonProfileService"))

local COIN_ITEM_ID = "Coins"

local BankService = {}

local function getProfile(player)
	local profile = DungeonProfile.Get(player)
	if not profile then
		profile = DungeonProfile.Load(player)
	end
	if not profile then
		return nil
	end
	if type(profile.currencies) ~= "table" then
		profile.currencies = { Coins = 0 }
	end
	if type(profile.currencies.Coins) ~= "number" then
		profile.currencies.Coins = 0
	end
	return profile
end

local function countCoinsInInventory(profile)
	local total = 0
	if type(profile) ~= "table" or type(profile.inventory) ~= "table" then
		return 0
	end
	for _, it in pairs(profile.inventory) do
		if type(it) == "table" and it.itemId == COIN_ITEM_ID then
			total = total + math.max(0, math.floor(tonumber(it.count) or 1))
		end
	end
	return total
end

local function removeAllCoinsFromInventory(profile)
	local total = 0
	local removed = {}
	for uuid, it in pairs(profile.inventory or {}) do
		if type(it) == "table" and it.itemId == COIN_ITEM_ID then
			total = total + math.max(0, math.floor(tonumber(it.count) or 1))
			removed[#removed + 1] = uuid
		end
	end
	local removedSet = {}
	for _, uuid in ipairs(removed) do
		profile.inventory[uuid] = nil
		removedSet[uuid] = true
	end
	if type(profile.hotbar) == "table" then
		for i = 1, 9 do
			local u = profile.hotbar[i]
			if type(u) == "string" and removedSet[u] then
				profile.hotbar[i] = nil
			end
		end
	end
	return total
end

function BankService.DepositAll(player)
	local profile = getProfile(player)
	if not profile then
		return false, "no_profile", 0
	end

	local amount = removeAllCoinsFromInventory(profile)
	if amount <= 0 then
		return false, "no_coins_in_bags", 0
	end

	profile.currencies.Coins = math.floor((profile.currencies.Coins or 0) + amount)
	DungeonProfile.PushProfile(player)
	return true, nil, amount
end

function BankService.Withdraw(player, amount)
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 or math.floor(amount) ~= amount then
		return false, "invalid_amount", 0
	end

	local profile = getProfile(player)
	if not profile then
		return false, "no_profile", 0
	end

	local wallet = math.floor(profile.currencies.Coins or 0)
	if amount > wallet then
		return false, "insufficient_wallet", 0
	end

	profile.currencies.Coins = wallet - amount
	local ok, err = DungeonProfile.GrantItemId(player, COIN_ITEM_ID, amount)
	if not ok then
		profile.currencies.Coins = wallet
		DungeonProfile.PushProfile(player)
		return false, err or "grant_failed", 0
	end

	return true, nil, amount
end

function BankService.WithdrawAll(player)
	local profile = getProfile(player)
	if not profile then
		return false, "no_profile", 0
	end

	local amount = math.floor(profile.currencies.Coins or 0)
	if amount <= 0 then
		return false, "empty_wallet", 0
	end

	profile.currencies.Coins = 0
	local ok, err = DungeonProfile.GrantItemId(player, COIN_ITEM_ID, amount)
	if not ok then
		profile.currencies.Coins = amount
		DungeonProfile.PushProfile(player)
		return false, err or "grant_failed", 0
	end

	return true, nil, amount
end

function BankService.GetBalances(player)
	local profile = getProfile(player)
	if not profile then
		return { wallet = 0, inventoryCoins = 0 }
	end
	return {
		wallet = math.floor(profile.currencies.Coins or 0),
		inventoryCoins = countCoinsInInventory(profile),
	}
end

return BankService