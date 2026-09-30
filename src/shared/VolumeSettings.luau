local ZoneConfig = require(script.Parent:WaitForChild("ZoneConfig"))
local SettingsStore = require(script.Parent:WaitForChild("SettingsStore"))
-- Shared client-side volume preferences. Required by both ZoneClient and
-- SettingsClient; Roblox caches ModuleScript results per VM so both scripts
-- read/write the same table instance.
--
-- Renamed sfx/vfx -> movement/effects (2026-09): both were always sound
-- buses, never anything visual -- "VFX" was a naming leftover that confused
-- players (see SettingsClient's tab). `master` is new: it scales
-- SoundService.Main.Volume (the umbrella group both movement and effects
-- nest under) plus the music sound directly, since ZoneMusic lives outside
-- the Main tree and can't inherit a group multiplier.
--
-- Persistence (2026-09): values below are only the FALLBACK defaults for a
-- brand new player. SettingsStore.Get().volume (server-saved, via
-- SettingsDataService's own DataStore -- deliberately NOT the profile
-- systems in ProfileService.lua/PlayerDataManager.lua, see that file's
-- header) overrides whichever of these fields the player has actually
-- changed before, so this table always reflects their last-saved values.
local defaults = {
	master = 1.0,     -- SoundService.Main.Volume, and multiplies ZoneMusic directly.
	music  = ZoneConfig.ZONE_MUSIC_VOLUME,
	movement = 0.5,   -- footsteps/landing/jumping -- wired to SoundService.Main.Character.Volume.
	                  -- (was named "sfx")
	effects  = 1.0,   -- one-shot effect sounds: melee hits, crit hits, item pickups
	                  -- (see SfxService.PlayEffect) -- wired to SoundService.Main.Effects.Volume.
	                  -- (was named "vfx" -- there is no real visual-effects/particle
	                  -- quality setting; src/shared/VFX/ is an unrelated particle-asset
	                  -- folder, not a settings hook.)
}

local saved = SettingsStore.Get().volume
if type(saved) == "table" then
	for key, value in pairs(saved) do
		if type(value) == "number" and defaults[key] ~= nil then
			defaults[key] = value
		end
	end
end

-- Fixed output gain between the sliders and the engine (NOT a setting, never saved):
-- every volume this game drives is slider value x OUTPUT_GAIN. 2026-09-26: at 1.0 the game
-- was so loud that bearable meant Master at ~3%, which squeezed the whole usable range of
-- every slider into 1-5%. At 0.2, 100% on a slider is what 20% used to be, so the
-- percentages mean something again. Consumers: SettingsClient (Main SoundGroup + music),
-- ZoneClient (music), and everything else routed under SoundService.Main (see SoundRouter).
defaults.OUTPUT_GAIN = 0.2

return defaults
