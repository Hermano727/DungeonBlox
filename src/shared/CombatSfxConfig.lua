--[[
	CombatSfxConfig
	Tweak MELEE_HIT_GLASS_SOUND_ID to your preferred glass / block break clip (short punchy SFX works best).

	Leading silence / padding in the uploaded asset cannot be permanently cropped in Roblox;
	use MELEE_HIT_GLASS_TRIM_START_SEC to skip the first N seconds at playback so the hit lines up.
	For a perfectly tight clip, re-export a trimmed file in an external editor and re-upload.
]]

return {
	-- Short glass / block-tick style hit (swap for your own upload if you want a closer Minecraft match).
	MELEE_HIT_GLASS_SOUND_ID = "rbxassetid://76978789448152",
	-- Seconds to skip from the beginning (leading silence in the asset). Example: 0.08 or 0.12
	MELEE_HIT_GLASS_TRIM_START_SEC = 0.32,
	VOLUME = 0.45,
	PITCH_MIN = 1.02,
	PITCH_MAX = 1.12,
}
