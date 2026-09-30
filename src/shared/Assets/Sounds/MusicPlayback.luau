--[[
	MusicPlayback -- ReplicatedStorage/Assets/Sounds

	Per-track playback tuning for looped music, keyed by the same normalized
	`rbxassetid://` string the music registries hand out (ZoneService's zone
	musicId, NamedEliteSoundtracks). ZoneClient plays every looped track through
	ZoneMusic, so this is the one place a track can say "skip my intro" or "I was
	mastered quieter than everything else".

	Keyed by id rather than by zone or mob on purpose: the tuning belongs to the
	AUDIO FILE, so the same track carries it wherever it is used. The tradeoff is
	that one asset can't have two different offsets in two places; author a
	second upload if that ever comes up.

		StartTime   seconds into the clip to begin, including after each loop.
		            Needs the asset loaded before it takes effect, which
		            ZoneClient handles.
		VolumeScale multiplied onto the player's own music volume. 1 = unchanged.
		            The player's Master/Music sliders still apply on top, so this
		            never overrides their settings, it just re-balances one track
		            against the rest.
]]

local MusicPlayback = {}

local DEFAULTS = { StartTime = 0, VolumeScale = 1 }

MusicPlayback.Tracks = {
	-- Kane the Enraged's theme (RS/Assets/Sounds/NamedEliteSoundtracks).
	-- Starts 2s in to skip the intro, and sits noticeably louder than the
	-- ambient zone tracks it interrupts.
	["rbxassetid://102529790211447"] = { StartTime = 2, VolumeScale = 1.5 },
	-- Miasma phase 1 (EncounterSoundtracks.MiasmaPhase1): an ominous "why is nothing
	-- here" bed, kept at half volume on purpose so it sits under the room.
	["rbxassetid://87781103686342"] = { VolumeScale = 0.5 },
}

-- Always returns a table, so callers never branch on nil.
function MusicPlayback.Get(musicId)
	if type(musicId) ~= "string" or musicId == "" then
		return DEFAULTS
	end
	return MusicPlayback.Tracks[musicId] or DEFAULTS
end

return MusicPlayback
