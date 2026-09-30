--[[
	SkillXPSync -- keeps SkillXPShared (the client-side Combat/Mining/Fishing levels the XP bars
	and the Skills panel read) equal to the SAVED profile.

	Seeds it from the first profile snapshot on join, then re-syncs on every later push, so a
	rejoin shows the real levels instead of starting back at 1. See SkillXPShared.SyncFromStats.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkillXPShared = require(ReplicatedStorage:WaitForChild("SkillXPShared"))
local DungeonMenuNet = require(script.Parent:WaitForChild("DungeonMenuNet"))

DungeonMenuNet.start() -- idempotent; also asks the server for a fresh snapshot

DungeonMenuNet.addSnapshotListener(function(snapshot)
	local profile = type(snapshot) == "table" and snapshot.profile
	if type(profile) == "table" then
		SkillXPShared.SyncFromStats(profile.stats)
	end
end)
