-- CombatAnimConfig
-- Single source of truth for all combat animation and hitbox parameters.
-- Change SWING_ANIM_ID here to swap the global swing animation.
-- Animation must be published under the same Roblox account/group as this game.

return {
	-- ── Animation ────────────────────────────────────────────────────────────────────
	-- Asset ID of the swing animation. Swap this value to update globally.
	SWING_ANIM_ID   = "rbxassetid://127678330702421",


	-- Visual cadence only; damage and energy remain driven by attack input.
	-- Smooth inter-click intervals (EMA), seeded for the expected MVP cadence.
	SWING_DEFAULT_CPS = 4.5,
	SWING_INTERVAL_ALPHA = 0.5,
	SWING_IDLE_RESET_SEC = 1.0,
	SWING_MIN_CPS = 1.0,
	SWING_MAX_CPS = 10.0,
	-- Finish slightly before the expected next click. Use loaded track.Length,
	-- not a guessed frame rate for the 25-frame source animation.
	SWING_CYCLE_FRACTION = 0.9,
	SWING_MIN_PLAYBACK_SPEED = 0.5,
	SWING_MAX_PLAYBACK_SPEED = 10.0,
	SWING_FADE_IN = 0.025,
	SWING_QUEUE_MAX_AGE_SEC = 0.3,

	-- Animation priority. Action overrides Movement and Idle tracks.
	-- Raise to Enum.AnimationPriority.Action4 to also beat other Action tracks.
	ANIM_PRIORITY   = Enum.AnimationPriority.Action,

	-- Fade-out time when unequipping, dying, or cancelling a swing for a menu.
	CANCEL_FADE     = 0.05,

	-- ── Hit Detection ──────────────────────────────────────────────────────────
	-- Existing CombatClient fallback sweep still consumes this legacy size.
	HITBOX_SIZE = Vector3.new(3, 3, 3),
	-- Both hit checks below are geometry-aware: they test the aim ray against
	-- the ACTUAL target model's own bounding box (CombatClient's fallback
	-- sweep client-side, MobCombat.ApplyWeaponDamage's validation
	-- server-side) rather than a generic box/radius floating near the
	-- player. These margins are just forgiveness added on top of that real
	-- box, for near-misses and network jitter -- not a substitute for it.

	-- Studs added to a candidate's own bounding box (client-side) when the
	-- primary raycast misses. Keeps the fallback sweep a genuine "just
	-- barely missed" catch rather than a free-fire zone independent of aim.
	CLIENT_HITBOX_FORGIVENESS_STUDS = 1.5,

	-- Studs added to the mob/player's own bounding box (server-side) when
	-- validating a claimed hitPosition. Larger than the client margin on
	-- purpose -- covers network latency and mob movement between the
	-- client's swing and the server processing it, not aim imprecision
	-- (that's already covered client-side).
	SERVER_HIT_FORGIVENESS_STUDS = 3,

	-- ── Debug ──────────────────────────────────────────────────────────────────────
	-- Set DEBUG = true to enable verbose per-swing logging.
	-- Logs: rig type, anim ID, track length, IsPlaying state, playback speed.
	DEBUG           = false,
}
