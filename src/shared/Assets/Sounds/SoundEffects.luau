--[[
	SoundEffects
	Registry of one-shot effect-sound asset ids, keyed by a short logical name
	so callers never hardcode a raw rbxassetid:// string. Played through
	SfxService.PlayEffect(key), which routes every sound through the shared
	SoundService.Main.Effects SoundGroup -- that's what lets a single settings
	slider ("VFX" in SettingsClient) ramp every effect sound down at once,
	instead of each system managing its own volume.

	Add a new effect by adding a line here; nothing else needs to change
	unless the new effect also needs per-play pitch/volume variance (see
	SfxService.PlayEffect for where that would go).
]]

return {
	ItemPickup = "rbxassetid://134602992766192",
	CriticalHit = "rbxassetid://77076686405925",
	CombatXPGain = "rbxassetid://127206748417528",
}
