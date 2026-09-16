--[[
	DungeonInstanceTypes
	Shared, data-only enums for the dungeon instance system (portal -> ready-prompt ->
	realm teleport -> run -> leave). Required by both DungeonInstanceService (server) and
	DungeonPromptClient/DungeonHudClient so the state/status strings can never drift between
	the two sides of the wire. No side-effects on require().
]]

local DungeonInstanceTypes = {}

-- Lifecycle of one DungeonInstanceService instance.
DungeonInstanceTypes.State = {
	PROMPTING   = "Prompting",   -- ready-check dialog is up, waiting on Accept/Reject
	IN_PROGRESS = "InProgress",  -- party teleported into the realm, run clock ticking
	ENDED       = "Ended",       -- instance torn down (everyone left / cancelled)
}

-- Per-member status shown in the ready-prompt roster.
DungeonInstanceTypes.MemberStatus = {
	WAITING     = "Waiting",
	ACCEPTED    = "Accepted",
	REJECTED    = "Rejected",
	MISSING_KEY = "MissingKey",
}

-- Display label for a MemberStatus value (used by DungeonPromptClient).
DungeonInstanceTypes.MemberStatusLabel = {
	Waiting    = "Waiting...",
	Accepted   = "Accepted",
	Rejected   = "Rejected",
	MissingKey = "Missing Key",
}

return DungeonInstanceTypes
