--!strict
-- Pure-data registry of dialog response action TYPES. Add a new action type
-- by adding one entry here.
--
--   kind = "client" -- no server round-trip; DialogRuntime's
--                       ClientActionHandlers table (client/DialogHud/
--                       DialogRuntime.lua) does the actual work, since that
--                       is the only place that can safely require sibling
--                       client modules like BlacksmithClient.
--
--   kind = "server" -- forwarded to the existing NPCRequest RemoteFunction
--                       as { npcId, action = serverAction, questId = ... }.
--                       The NpcType must list `serverAction` in its
--                       NPCRegistry Interactions for the request to be
--                       allowed -- same whitelist every other NPC
--                       transaction (repairs, purchases, trades) already
--                       goes through. The actual handler lives in
--                       NPCService.server.lua's HANDLERS table.

return {
	OpenMenu    = { kind = "client" },
	AcceptQuest = { kind = "server", serverAction = "AcceptQuest" },
	TurnInQuest = { kind = "server", serverAction = "TurnInQuest" },
}
