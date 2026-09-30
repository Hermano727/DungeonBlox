--[[
	EncounterSoundtracks -- ReplicatedStorage/Assets/Sounds

	Looped tracks that boss ENCOUNTERS (scripted multi-phase fights, not named elites) push
	onto their members for part of the fight, via ZoneService.SetEncounterMusic. That layer
	outranks both the named-elite override and the zone soundtrack.

	Same registry rule as NamedEliteSoundtracks: asset ids live here, never inline.
	Per-track intro skip / loudness tuning goes in MusicPlayback, keyed by the same id.
]]

return {
	-- Miasma: phase 1, from walking into the arena (the empty-room grace period) through the
	-- slime waves, until the ceiling drop starts. Deliberately quiet: see MusicPlayback.
	MiasmaPhase1 = "rbxassetid://87781103686342",
	-- Miasma: from phase 2 (the slam and roar have finished, the gate cycle begins) until the
	-- fight ends. See MiasmaEncounterController:_setPhaseMusic.
	MiasmaPhase2 = "rbxassetid://100533680829762",
}
