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

	A value may be a LIST of ids instead of one string -- variations of the
	same effect. SfxService.PlayEffect picks one at random per call, so a sound
	that fires often (a block proc every few hits) doesn't get grating.
]]

return {
	ItemPickup = "rbxassetid://134602992766192",
	CriticalHit = "rbxassetid://77076686405925",
	CombatXPGain = "rbxassetid://127206748417528",

	-- Enchanting Station (EnchantStationClient / EnchantStationScreen)
	EnchantStationEnter = "rbxassetid://70458889272802",
	EnchantStationExit = "rbxassetid://102474597594958",
	EnchantSuccess = "rbxassetid://101663733274964",
	EnchantFail = "rbxassetid://91534279231521",

	-- Miasma's roar, frames 65-100 of its landing slam (MiasmaRoarFX). Played there directly
	-- rather than through PlayEffect, whose 10s safety cleanup could clip a long roar.
	MiasmaRoar = "rbxassetid://128962677500476",
	-- The drop cutscene's ceiling collapse: rocks falling, then Miasma's slam ~3.0s in. Started so
	-- that mark lands on the impact (MiasmaEncounterVFX, DROP_SOUND_SLAM_AT).
	MiasmaCeilingCollapse = "rbxassetid://116932059282652",

	-- Rolled whenever a hit is blocked outright (see DamageService's block
	-- roll and docs/named-elite-loot.md).
	BlockHit = {
		"rbxassetid://133027289075971",
		"rbxassetid://110305446249138",
		"rbxassetid://136703233495722",
		"rbxassetid://94233869283317",
		"rbxassetid://76886690180038",
	},
}
