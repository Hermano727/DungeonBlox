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
	-- Three recorded sword swishes (2026-10-12) from the licensed Pro Sound Effects library on the
	-- Creator Store ("Swish Med High End Sharp Swords Fast Punches", free for every experience):
	-- a sharp, bright ~0.1 s cut. One at random per swing, never the same one twice in a row.
	-- `start` skips each clip's leading silence (measured: the swish begins at 0.060 / 0.107 /
	-- 0.066 s), `volume` levels them against each other (peaks -3.3 / -4.7 / -9.1 dBFS).
	-- Rejected: the synthesized whooshes (assets/sfx/sword_swing, ids 71726589850791 /
	-- 79354930260005 / 95003456888869) read as blowing wind; the old single clip 72949989842352
	-- (~1 s, played from 0.4 s) is kept here for a quick revert.
	SWORD_SLASH_SOUNDS = {
		{ id = "rbxassetid://9126014020", start = 0.045, volume = 0.80 }, -- brightest, sharpest
		{ id = "rbxassetid://9126013644", start = 0.090, volume = 0.95 }, -- sharp, one clean pass
		{ id = "rbxassetid://9126014082", start = 0.050, volume = 1.40 }, -- fuller, lower
	},
	SWORD_SLASH_START_SEC = 0, -- default start for a plain id entry
	SWORD_SLASH_VOLUME = 0.5,
	SWORD_SLASH_PITCH_MIN = 0.95,   -- small random variation so rapid swings don't sound identical
	SWORD_SLASH_PITCH_MAX = 1.06,
	SWORD_SLASH_MAX_VOICES = 4,     -- overlapping slashes; past this the oldest fades out fast
}
