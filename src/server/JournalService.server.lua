--[[
	JournalService -- data the Journal pages need that isn't in the profile snapshot.

	GameEvents/JournalRequest (RemoteFunction), client -> server:
		"lootScore"                 -> { streaks = { Common = n, Uncommon = n, ... } }
		"activity", tier, window    -> RS/JournalActivity.Summary for that tier and window
		                               ("1H" | "24H" | "7D" | "30D"): current totals, chart
		                               points, and the average window (nil until enough history)

	The per-tier score totals and cleared runs already ride on the profile snapshot
	(profile.stats.tracking: scoreByTier, dungeonScoreByTier, runsClearedByTier); only the
	dry streaks live elsewhere (LootPityService, on the older PlayerDataManager profile),
	so this is the one round trip the Loot Score page makes when it opens. Read-only.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local RemoteUtils = require(ReplicatedStorage:WaitForChild("RemoteUtils"))
local LootPityService = require(ServerScriptService:WaitForChild("LootPityService"))
local ProfileService = require(ServerScriptService:WaitForChild("ProfileService"))
local JournalActivity = require(ReplicatedStorage:WaitForChild("JournalActivity"))

local VALID_WINDOWS = {}
for _, w in ipairs(JournalActivity.WINDOWS) do VALID_WINDOWS[w] = true end

local gameEvents = RemoteUtils.EnsureFolder(ReplicatedStorage, "GameEvents")
local journalRequest = RemoteUtils.EnsureRemoteFunction(gameEvents, "JournalRequest")

journalRequest.OnServerInvoke = function(player, page, tier, window)
	if page == "lootScore" then
		return { streaks = LootPityService.GetStreaks(player) or {} }
	elseif page == "activity" then
		if not VALID_WINDOWS[window] then return nil end
		local profile = ProfileService.Get(player)
		if not profile then return nil end
		tier = math.clamp(math.floor(tonumber(tier) or 1), 1, 5)
		return JournalActivity.Summary(profile, tier, window)
	end
	return nil
end
