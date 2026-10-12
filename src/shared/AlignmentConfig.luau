--[[
	AlignmentConfig -- ReplicatedStorage. The player's PvP alignment: Lawful / Neutral / Chaotic.

	Saved in profile.alignment = { current, cooldownUntil }, owned by SSS/ProfileService
	(SetAlignment, ForceLawfulOnDeath, CanPvP); replicated as the `PlayerAlignment` player
	attribute. Picked on the Journal's Alignment page (client AlignmentPage).

	Rules (2026-10-11):
	  - Changing it is only allowed inside a safe (Lawful) zone and out of combat.
	  - Dying as Neutral or Chaotic sets you back to Lawful, and you can't pick a non-Lawful
	    alignment again for DEATH_LOCKOUT seconds (by what you died as). Lawful is always allowed.
	    profile.alignment.cooldownUntil is that lockout (os.time()).
	  - Lawful players can't hit or be hit by other players; Neutral and Chaotic fight each
	    other anywhere outside a safe zone (ProfileService.CanPvP, MobCombat).
	  - The other per-alignment numbers live with their systems: the shard hop channel
	    (ShardConfig.CHANNEL_SECONDS) and the hearthstone channel (HearthstoneConfig.CHANNEL_SECONDS).
]]

local AlignmentConfig = {}

AlignmentConfig.ORDER = { "Lawful", "Neutral", "Chaotic" }

-- Seconds you're held to Lawful after dying as this alignment.
AlignmentConfig.DEATH_LOCKOUT = {
	Neutral = 120,
	Chaotic = 300,
}

-- The nametag colours (client/Nametags), so the page and the name over your head agree.
-- Lawful is a plain white name (no marking); only the PvP alignments stand out.
AlignmentConfig.COLORS = {
	Lawful = Color3.fromRGB(255, 255, 255),
	Neutral = Color3.fromRGB(255, 221, 51),
	Chaotic = Color3.fromRGB(255, 70, 64),
}

-- PvP hits (MobCombat.ApplyPvPDamage): both players stay in combat this long after a hit
-- (the PvE timer is 5 s, CombatStateService), and the target is knocked back like a mob hit
-- (SSS/PlayerKnockback) times this.
AlignmentConfig.PVP_COMBAT_SECONDS = 10
AlignmentConfig.PVP_KNOCKBACK_MULTIPLIER = 1.5

-- One line each, shown under the name on the Journal page.
AlignmentConfig.BLURB = {
	Lawful = "Protected. You can't attack other players and they can't attack you.",
	Neutral = "Open to fights. Outside safe zones you can attack, and be attacked by, any Neutral or Chaotic player.",
	Chaotic = "Open to fights, and slowest to escape. Same fights as Neutral, longer channels.",
}

return table.freeze(AlignmentConfig)
