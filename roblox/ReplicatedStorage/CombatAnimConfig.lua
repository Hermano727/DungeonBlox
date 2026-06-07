-- CombatAnimConfig
-- Single source of truth for all combat animation and hitbox parameters.
-- Change SWING_ANIM_ID here to swap the global swing animation.
-- Animation must be published under the same Roblox account/group as this game.

return {
	-- ── Animation ────────────────────────────────────────────────────────────────────
	-- Asset ID of the swing animation. Swap this value to update globally.
	-- THIS IS THE OLD ANIMATION ID: SWING_ANIM_ID   = "rbxassetid://98847827358249",
	SWING_ANIM_ID   = "rbxassetid://102139503888423",


	-- Playback speed multiplier applied after Play().
	-- 4.0 = 4x for high-CPS feel. Lower values = slower, more visible arc.
	ANIM_SPEED_MULT = 4.0,

	-- Animation priority. Action overrides Movement and Idle tracks.
	-- Raise to Enum.AnimationPriority.Action4 to also beat other Action tracks.
	ANIM_PRIORITY   = Enum.AnimationPriority.Action,

	-- Fade-out time (seconds) when cancelling an in-progress swing.
	CANCEL_FADE     = 0.05,

	-- ── Hit Detection ──────────────────────────────────────────────────────────
	-- Overlap box size for the secondary hitbox sweep (used when raycast misses).
	HITBOX_SIZE     = Vector3.new(3, 3, 3),

	-- ── Debug ──────────────────────────────────────────────────────────────────────
	-- Set DEBUG = true to enable verbose per-swing logging.
	-- Logs: rig type, anim ID, track length, IsPlaying state, playback speed.
	DEBUG           = false,
}
