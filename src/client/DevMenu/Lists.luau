--[[
	DevMenu/Lists -- the catalogues several tabs pick from, reflected off the game data so new
	content shows up with no dev-menu edit.

	MOB_IDS          ordinary mobs the MOB tab may place a camp for (and a zone's elite mob).
	                 Only mobs with a real, fully-authored model (MOB_ID_WHITELIST): MobData keeps
	                 every MobID for natural spawners and loot, this only filters what F8 offers.
	                 Expand the whitelist as mobs get real models.
	NAMED_ELITE_IDS  every MobData entry with IsNamedElite or IsBoss (the ELITE tab). Named elites
	                 are a single server-wide event, not a camp, so they never appear in MOB_IDS.
	NPC_TYPES        every NPCRegistry type (the NPC tab).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MobData = require(ReplicatedStorage:WaitForChild("MobData"))
local NPCRegistry = require(ReplicatedStorage:WaitForChild("NPCRegistry"))

local MOB_ID_WHITELIST = { PlainsSlime = true, SmallSkeleton = true }

local Lists = { MOB_IDS = {}, NAMED_ELITE_IDS = {}, NPC_TYPES = {} }

for tier = 1, 5 do
	local mobs = MobData[tier]
	if type(mobs) == "table" then
		for id, stats in pairs(mobs) do
			if type(stats) == "table" and (stats.IsNamedElite or stats.IsBoss) then
				table.insert(Lists.NAMED_ELITE_IDS, id)
			elseif MOB_ID_WHITELIST[id] then
				table.insert(Lists.MOB_IDS, id)
			end
		end
	end
end
for npcType in pairs(NPCRegistry.Types) do
	table.insert(Lists.NPC_TYPES, npcType)
end
table.sort(Lists.MOB_IDS)
table.sort(Lists.NAMED_ELITE_IDS)
table.sort(Lists.NPC_TYPES)

-- Cycles `index` by `delta` through a list of `count` entries (1-based, wraps).
function Lists.step(index, delta, count)
	if count == 0 then return index end
	return ((index - 1 + delta) % count) + 1
end

return Lists
