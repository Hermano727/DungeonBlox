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

	-- Sword slash whoosh, played CLIENT-side the instant a swing starts (SwordSlashSfx, from
	-- CombatClient's startSwing: one per swing you actually see, follow-up swings included).
	-- The clip is ~1s with the whoosh around 0.5s, so playback starts partway in to land the
	-- whoosh as the blade moves (no need to re-upload a trimmed file; nudge START_SEC instead).
	SWORD_SLASH_SOUND_ID = "rbxassetid://72949989842352",
	SWORD_SLASH_START_SEC = 0.4,
	SWORD_SLASH_VOLUME = 0.5,
	SWORD_SLASH_PITCH_MIN = 0.95,   -- small random variation so rapid swings don't sound identical
	SWORD_SLASH_PITCH_MAX = 1.06,
	SWORD_SLASH_MAX_VOICES = 4,     -- overlapping slashes; past this the oldest fades out fast
}
