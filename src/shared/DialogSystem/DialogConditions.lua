--!strict
-- Registry of dialog response condition evaluators. Add a new condition type
-- by adding one function here -- nothing about DialogRuntime's tree-walking
-- needs to change to use it in a tree.
--
-- Every evaluator: function(player: Player, args: table, ctx: table): boolean
-- ctx = { profile = <cached client profile snapshot table, or nil> }
--
-- These run CLIENT-SIDE against the cached profile snapshot (the same
-- snapshot BlacksmithClient/DungeonMenuNet already use) purely to decide
-- which responses to show. They are not a security boundary -- every
-- state-mutating action a response can trigger is re-validated
-- server-side in QuestProgressService/NPCService regardless of what the
-- client displayed.

local DialogConditions = {}

function DialogConditions.Always(_player, _args, _ctx)
	return true
end

--- args = { quest = "<questId>", is = "available" | "active" | "completed" }
-- "available": quest not yet accepted. "active": accepted, not turned in.
-- "completed": turned in. Whether an active quest's objective is actually
-- satisfied is NOT modeled here -- TurnInQuest is attempted optimistically
-- and the server communicates back if it isn't ready yet (see
-- DialogRuntime's FRIENDLY_ERRORS / statusText handling), the same pattern
-- BlacksmithClient already uses for repairs it can't afford.
function DialogConditions.QuestState(_player, args, ctx)
	local profile = ctx.profile
	local q = profile
		and type(profile.flags) == "table"
		and type(profile.flags.quests) == "table"
		and profile.flags.quests[args.quest]

	local state
	if type(q) ~= "table" then
		state = "available"
	elseif q.completed then
		state = "completed"
	elseif q.active then
		state = "active"
	else
		state = "available"
	end

	return state == args.is
end

return DialogConditions
