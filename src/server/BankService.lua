--[[
  BankService (Server)
  Server-authoritative bank logic. Moves Coins between wallet (currencies.Coins)
  and bank (bank.Coins) on the DungeonProfileService session profile.
  All mutations go through DungeonProfileService.PushProfile so the client
  tab menu stays in sync.
]]

local ServerScriptService = game:GetService("ServerScriptService")

local DungeonProfile = require(ServerScriptService:WaitForChild("DungeonProfileService"))

local BankService = {}

local function getProfile(player)
	local profile = DungeonProfile.Get(player)
	if not profile then
		profile = DungeonProfile.Load(player)
	end
	if not profile then
		return nil
	end
	-- Ensure bank sub-table exists (safety for profiles loaded before bank feature)
	if type(profile.bank) ~= "table" then
		profile.bank = { Coins = 0 }
	end
	if type(profile.bank.Coins) ~= "number" then
		profile.bank.Coins = 0
	end
	return profile
end

function BankService.Deposit(player, amount)
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 or math.floor(amount) ~= amount then
		return false, "invalid_amount"
	end

	local profile = getProfile(player)
	if not profile then
		return false, "no_profile"
	end

	if profile.currencies.Coins < amount then
		return false, "insufficient_wallet"
	end

	profile.currencies.Coins = profile.currencies.Coins - amount
	profile.bank.Coins = profile.bank.Coins + amount

	DungeonProfile.PushProfile(player)
	return true, nil
end

function BankService.Withdraw(player, amount)
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 or math.floor(amount) ~= amount then
		return false, "invalid_amount"
	end

	local profile = getProfile(player)
	if not profile then
		return false, "no_profile"
	end

	if profile.bank.Coins < amount then
		return false, "insufficient_bank"
	end

	profile.bank.Coins = profile.bank.Coins - amount
	profile.currencies.Coins = profile.currencies.Coins + amount

	DungeonProfile.PushProfile(player)
	return true, nil
end

function BankService.GetBalances(player)
	local profile = getProfile(player)
	if not profile then
		return { wallet = 0, bank = 0 }
	end
	return {
		wallet = profile.currencies.Coins or 0,
		bank   = profile.bank.Coins or 0,
	}
end

return BankService
