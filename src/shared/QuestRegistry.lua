--[[
	QuestRegistry
	Shared data-only module, same pattern as NPCRegistry/ShopCatalogConfig.
	Declares quest definitions so dialog trees (and anything else) can ask
	generic questions -- "is this available / active / completed" -- instead
	of hardcoding quest-specific checks per NPC.

	This does NOT replace the three legacy named quests in ProfileTypes.flags
	(cusoBanditQuest / minerCoalQuest / fisherFishQuest) -- those keep working
	exactly as before, driven by QuestProgressService's existing counter
	hooks (OnMobKilledByPlayer / OnCoalCollected / OnSpearFishCaught). New
	quests live under the generic profile.flags.quests[id] bucket and are
	declared here; see QuestProgressService.AcceptQuest/TurnInQuest.

	Objective.Type:
	  "HaveItemCount" -- turn-in checks (and consumes) Count of ItemId from
	                     the player's inventory. No progress hook needed
	                     elsewhere -- the check happens at turn-in time.
	  Add new types here as needed (e.g. "MobKill" wired to a hook call at
	  the relevant kill site, mirroring the legacy quests above) -- nothing
	  about QuestProgressService's Accept/TurnIn flow needs to change for a
	  HaveItemCount-shaped quest; only TurnInQuest's per-type branch grows.
]]

local QuestRegistry = {}

QuestRegistry.Quests = {

	BlacksmithScrapRun = {
		NpcType     = "Blacksmith",
		DisplayName = "Scrap Run",
		Objective   = { Type = "HaveItemCount", ItemId = "T1Scrap", Count = 5 },
		RewardCoins = 25,
		-- Prereq = "<otherQuestId>", -- optional: gate behind another quest's completion
	},

}

function QuestRegistry.Get(questId)
	return QuestRegistry.Quests[questId]
end

--- All quest ids declared for a given NpcType, in table order (unordered pairs()).
function QuestRegistry.GetForNpcType(npcType)
	local out = {}
	for id, def in pairs(QuestRegistry.Quests) do
		if def.NpcType == npcType then
			table.insert(out, id)
		end
	end
	return out
end

return QuestRegistry
