--[[
  BankService (Server)
  Coin bank: inventory coin items <-> wallet (currencies.Coins).
  DepositAll moves every Coins stack AND the contents of every coin sack in the bags into the
  spendable wallet (sacks stay in the bag, emptied).
  Withdraw / WithdrawAll take coins out of the wallet and hand them over as ONE coin note
  (ProfileService.GrantCoinNote): a single bag item worth that many coins, redeemable anywhere
  and tradeable. They need one free bag slot and refuse ("no_room") before touching the wallet.
]]

local ServerScriptService = game:GetService("ServerScriptService")

local DungeonProfile = require(ServerScriptService:WaitForChild("ProfileService"))

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
	return total + DungeonProfile.CoinsInSacks(profile)
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

	local amount = removeAllCoinsFromInventory(profile) + DungeonProfile.TakeCoinsFromSacks(profile)
	if amount <= 0 then
		return false, "no_coins_in_bags", 0
	end

	profile.currencies.Coins = math.floor((profile.currencies.Coins or 0) + amount)
	DungeonProfile.PushProfile(player)
	return true, nil, amount
end

-- Takes `amount` out of the wallet and mints a coin note for it. Returns ok, err, amount.
local function writeNote(player, profile, amount)
	local wallet = math.floor(profile.currencies.Coins or 0)
	profile.currencies.Coins = wallet - amount
	local ok, err = DungeonProfile.GrantCoinNote(player, amount)
	if not ok then
		profile.currencies.Coins = wallet -- nothing was written; the wallet is whole again
		DungeonProfile.PushProfile(player)
		return false, err == "no_room" and "no_room" or (err or "grant_failed"), 0
	end
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

	return writeNote(player, profile, amount)
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

	return writeNote(player, profile, amount)
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