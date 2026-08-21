local ZoneConfig = require(script.Parent:WaitForChild("ZoneConfig"))
-- Shared client-side volume preferences. Required by both ZoneClient and
-- SettingsClient; Roblox caches ModuleScript results per VM so both scripts
-- read/write the same table instance.
return {
	music = ZoneConfig.ZONE_MUSIC_VOLUME,
	sfx   = 0.5,  -- movement SFX (footsteps/landing/jumping) -- wired to SoundService.Main.Character.Volume
	vfx   = 1.0,  -- TODO: wire to VFX system
}