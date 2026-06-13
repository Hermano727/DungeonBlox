--[[
	QuestProgressService
	Central place for quest counters: combat kills (Cuso), mining coal (Miner), spear fishing (Fisherman).
]]

local ServerScriptService = game:GetService("ServerScriptService")

local DungeonProfile = require(ServerScriptService:WaitForChild("DungeonProfileService"))

local QuestProgress = {}

local function getCusoQuestTable(profile)
	if type(profile.flags) ~= "table" then
		profile.flags = {}
	end
	local q = profile.flags.cusoBanditQuest
	if type(q) ~= "table" then
		q = {
			active = false,
			completed = false,
			target = 5,
			progress = 0,
			rewardCoins = 10,
			rewardPaid = false,
		}
		profile.flags.cusoBanditQuest = q
	end
	if q.rewardCoins == nil then
		q.rewardCoins = 10
	end
	if q.rewardPaid == nil then
		q.rewardPaid = false
	end
	return q
end

local function getMinerCoalQuestTable(profile)
	if type(profile.flags) ~= "table" then
		profile.flags = {}
	end
	local q = profile.flags.minerCoalQuest
	if type(q) ~= "table" then
		q = {
			active = false,
			completed = false,
			started = false,
			target = 5,
			progress = 0,
			rewardCoins = 10,
			rewardPaid = false,
		}
		profile.flags.minerCoalQuest = q
	end
	if q.started == nil then
		q.started = (q.completed == true) or (q.active == true)
	end
	if q.rewardCoins == nil then
		q.rewardCoins = 10
	end
	if q.rewardPaid == nil then
		q.rewardPaid = false
	end
	return q
end

local function getFisherFishQuestTable(profile)
	if type(profile.flags) ~= "table" then
		profile.flags = {}
	end
	local q = profile.flags.fisherFishQuest
	if type(q) ~= "table" then
		q = {
			active = false,
			completed = false,
			started = false,
			target = 5,
			progress = 0,
			rewardCoins = 10,
			rewardPaid = false,
		}
		profile.flags.fisherFishQuest = q
	end
	if q.started == nil then
		q.started = (q.completed == true) or (q.active == true)
	end
	if q.rewardCoins == nil then
		q.rewardCoins = 10
	end
	if q.rewardPaid == nil then
		q.rewardPaid = false
	end
	return q
end

function QuestProgress.OnMobKilledByPlayer(player, mobId)
	if mobId ~= "Bandit" then
		return
	end
	local profile = DungeonProfile.Get(player) or DungeonProfile.Load(player)
	if not profile then
		return
	end
	local q = getCusoQuestTable(profile)
	if q.completed or not q.active then
		return
	end
	local target = math.max(1, math.floor(tonumber(q.target) or 5))
	if q.progress >= target then
		return
	end
	q.progress = math.min(target, math.floor(tonumber(q.progress) or 0) + 1)
	if q.progress >= target then
		q.completed = true
		q.active = false
		if not q.rewardPaid then
			profile.currencies = profile.currencies or { Scrap = 0, Coins = 0 }
			local add = math.max(0, math.floor(tonumber(q.rewardCoins) or 10))
			profile.currencies.Coins = math.floor(tonumber(profile.currencies.Coins) or 0) + add
			q.rewardPaid = true
		end
	end
	DungeonProfile.PushProfile(player)
end

function QuestProgress.OnCoalCollected(player, amount)
	local amt = math.max(1, math.floor(tonumber(amount) or 1))
	local profile = DungeonProfile.Get(player) or DungeonProfile.Load(player)
	if not profile then
		return
	end
	local q = getMinerCoalQuestTable(profile)
	if q.completed or not q.active then
		return
	end
	local target = math.max(1, math.floor(tonumber(q.target) or 5))
	if q.progress >= target then
		return
	end
	q.progress = math.min(target, math.floor(tonumber(q.progress) or 0) + amt)
	if q.progress >= target then
		q.completed = true
		q.active = false
		if not q.rewardPaid then
			profile.currencies = profile.currencies or { Scrap = 0, Coins = 0 }
			local add = math.max(0, math.floor(tonumber(q.rewardCoins) or 10))
			profile.currencies.Coins = math.floor(tonumber(profile.currencies.Coins) or 0) + add
			q.rewardPaid = true
		end
	end
	DungeonProfile.PushProfile(player)
end

-- Called from SpearFishHandler when a spear-caught fish is granted to the player.
function QuestProgress.OnSpearFishCaught(player, amount)
	local amt = math.max(1, math.floor(tonumber(amount) or 1))
	local profile = DungeonProfile.Get(player) or DungeonProfile.Load(player)
	if not profile then
		return
	end
	local q = getFisherFishQuestTable(profile)
	if q.completed or not q.active then
		return
	end
	local target = math.max(1, math.floor(tonumber(q.target) or 5))
	if q.progress >= target then
		return
	end
	q.progress = math.min(target, math.floor(tonumber(q.progress) or 0) + amt)
	if q.progress >= target then
		q.completed = true
		q.active = false
		if not q.rewardPaid then
			profile.currencies = profile.currencies or { Scrap = 0, Coins = 0 }
			local add = math.max(0, math.floor(tonumber(q.rewardCoins) or 10))
			profile.currencies.Coins = math.floor(tonumber(profile.currencies.Coins) or 0) + add
			q.rewardPaid = true
		end
	end
	DungeonProfile.PushProfile(player)
end

return QuestProgress
