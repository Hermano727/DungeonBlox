local Protocol = {}

Protocol.States = {
	Dormant = "Dormant",
	EntranceGrace = "EntranceGrace",
	Act1Survival = "Act1Survival",
	Act1Cleanup = "Act1Cleanup",
	BossDrop = "BossDrop",
	Act2Puzzle = "Act2Puzzle",
	PureWaterStun = "PureWaterStun",
	CycleResetWarning = "CycleResetWarning",
	Act3Enrage = "Act3Enrage",
	Defeated = "Defeated",
	Failed = "Failed",
	Destroyed = "Destroyed",
}

Protocol.Requests = {
	BeginAltar = "BeginAltar",
	CancelAltar = "CancelAltar",
	ReserveValve = "ReserveValve",
	CancelValve = "CancelValve",
	MazeSample = "MazeSample",
}

Protocol.Events = {
	Snapshot = "Snapshot",
	Telegraph = "Telegraph",
	MazeOpened = "MazeOpened",
	MazeProgress = "MazeProgress",
	MazeReset = "MazeReset",
	MazeClosed = "MazeClosed",
	MazeBlob = "MazeBlob", -- { session, position, radius, hits } spawned | { session, hp } rammed | { session, popped = true }
	Presentation = "Presentation",
	PoisonChanged = "PoisonChanged",
}

Protocol.Attributes = {
	EncounterId = "MiasmaEncounterId",
	State = "MiasmaState",
	StateEndsAt = "MiasmaStateEndsAt",
	StartingPartySize = "MiasmaStartingPartySize",
	AlivePlayers = "MiasmaAlivePlayers",
	BossVulnerability = "MiasmaBossVulnerability",
	Enraged = "MiasmaEnraged",
	Cycle = "MiasmaCycle",
	CycleEndsAt = "MiasmaCycleEndsAt",
	ActiveGates = "MiasmaActiveGates",
	PoisonStacks = "MiasmaPoisonStacks",
}

Protocol.Tags = {
	EntranceThreshold = "MiasmaEntranceThreshold",
	EntranceGate = "MiasmaEntranceGate",
	BossLatch = "MiasmaBossLatch",
	BossLanding = "MiasmaBossLanding",
	CisternRing = "MiasmaCisternRing",
	PressureRing = "MiasmaPressureRing",
	Altar = "MiasmaCleanseAltar",
	Gate = "MiasmaGate",
	Valve = "MiasmaValve",
	PressurePlate = "MiasmaPressurePlate",
	ClogSocket = "MiasmaClogSocket",
	WaterChannel = "MiasmaWaterChannel",
	SafeArea = "MiasmaPurgeSafeArea",
	PoisonDrop = "MiasmaPoisonDrop",
	SlimeDrop = "MiasmaSlimeDrop",
	SackEntry = "MiasmaSackEntry",
}

return table.freeze(Protocol)
