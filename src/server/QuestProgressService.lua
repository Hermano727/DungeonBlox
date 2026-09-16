--[[
	QuestProgressService
	Central place for quest counters: combat kills (Cuso), mining coal (Miner), spear fishing (Fisherman).
]]

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DungeonProfile = require(ServerScriptService:WaitForChild("ProfileService"))
local QuestRegistry = require(ReplicatedStorage:WaitForChild("QuestRegistry"))

local QuestProgress = {}

local function grantQuestCoins(player, amount)
	local add = math.max(0, math.floor(tonumber(amount) or 0))
	if add <= 0 then
		return true
	end
	local ok = DungeonProfile.GrantItemId(player, 'Coins', add)
	return ok == true
end

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
			local add = math.max(0, math.floor(tonumber(q.rewardCoins) or 10))
			if grantQuestCoins(player, add) then
				q.rewardPaid = true
			end
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
			local add = math.max(0, math.floor(tonumber(q.rewardCoins) or 10))
			if grantQuestCoins(player, add) then
				q.rewardPaid = true
			end
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
			local add = math.max(0, math.floor(tonumber(q.rewardCoins) or 10))
			if grantQuestCoins(player, add) then
				q.rewardPaid = true
			end
		end
	end
	DungeonProfile.PushProfile(player)
end

---------------------------------------------------------------------------
-- Generic quest bucket (profile.flags.quests[id]) -- for quests declared in
-- QuestRegistry, as opposed to the three legacy named-flag quests above.
-- Kept as a separate, additive path so nothing about the legacy quests'
-- shape or hooks needs to change. Dialog trees call these via
-- NPCService's AcceptQuest/TurnInQuest handlers (see DialogActions.lua).
---------------------------------------------------------------------------

local function getGenericQuestTable(profile, questId)
	if type(profile.flags) ~= "table" then
		profile.flags = {}
	end
	if type(profile.flags.quests) ~= "table" then
		profile.flags.quests = {}
	end
	local q = profile.flags.quests[questId]
	if type(q) ~= "table" then
		q = { active = false, completed = false, rewardPaid = false }
		profile.flags.quests[questId] = q
	end
	return q
end

--- Marks a QuestRegistry-declared quest active for the player.
--- Returns true, or false + an error code string.
function QuestProgress.AcceptQuest(player, questId)
	local def = QuestRegistry.Get(questId)
	if not def then
		return false, "unknown_quest"
	end

	local profile = DungeonProfile.Get(player) or DungeonProfile.Load(player)
	if not profile then
		return false, "no_profile"
	end

	if def.Prereq then
		local prereqQ = getGenericQuestTable(profile, def.Prereq)
		if not prereqQ.completed then
			return false, "prereq_incomplete"
		end
	end

	local q = getGenericQuestTable(profile, questId)
	if q.active or q.completed then
		return false, "already_active_or_complete"
	end

	q.active = true
	DungeonProfile.PushProfile(player)
	return true
end

--- Checks the quest's objective, consumes/grants as needed, and marks it
--- completed. Returns true, or false + an error code string (including
--- "objective_incomplete" when the player hasn't met the objective yet --
--- the caller is expected to retry later, same as an unaffordable repair).
function QuestProgress.TurnInQuest(player, questId)
	local def = QuestRegistry.Get(questId)
	if not def then
		return false, "unknown_quest"
	end

	local profile = DungeonProfile.Get(player) or DungeonProfile.Load(player)
	if not profile then
		return false, "no_profile"
	end

	local q = getGenericQuestTable(profile, questId)
	if q.completed then
		return false, "already_active_or_complete"
	end
	if not q.active then
		return false, "not_active"
	end

	local obj = def.Objective
	if obj and obj.Type == "HaveItemCount" then
		local have = DungeonProfile.CountItemId(player, obj.ItemId)
		if have < obj.Count then
			return false, "objective_incomplete"
		end
		local consumedOk = DungeonProfile.ConsumeItemId(player, obj.ItemId, obj.Count)
		if not consumedOk then
			return false, "consume_failed"
		end
	end

	q.active = false
	q.completed = true

	if not q.rewardPaid then
		local coins = math.max(0, math.floor(tonumber(def.RewardCoins) or 0))
		if coins > 0 then
			DungeonProfile.GrantItemId(player, "Coins", coins)
		end
		if def.RewardItemId then
			DungeonProfile.GrantItemId(player, def.RewardItemId, def.RewardItemCount or 1)
		end
		q.rewardPaid = true
	end

	DungeonProfile.PushProfile(player)
	return true
end

return QuestProgress
