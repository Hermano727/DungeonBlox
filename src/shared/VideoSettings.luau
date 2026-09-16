local SettingsStore = require(script.Parent:WaitForChild("SettingsStore"))

-- Shared client-side video/graphics preferences. Required by SettingsClient
-- (writes these when a slider moves) and by every system whose camera
-- behaviour depends on them; Roblox caches ModuleScript results per VM so
-- all of them read/write the same table instance -- same pattern as
-- VolumeSettings.luau.
--
-- Every value here is a LIVE default: nothing reads these once and caches
-- them forever except where noted next to that read site (Animate2's
-- run/walk FOV boost and Crouching's crouch-FOV delta both add a fixed
-- offset on top of `fov`, so raising the base FOV scales those too instead
-- of leaving them stuck relative to the old 70 default).
--
-- Persistence (2026-09): these are only the FALLBACK defaults for a brand
-- new player. SettingsStore.Get().video (server-saved, via
-- SettingsDataService's own DataStore) overrides whichever fields the
-- player has actually changed before.
local defaults = {
	fov = 70,          -- Camera.FieldOfView at rest (first person). Matches every
	                   -- pre-existing hardcoded default across Crouching/Animate2/
	                   -- DialogModule, so introducing this setting is a no-op until
	                   -- the player actually moves the slider.
	sensitivity = 0.003, -- FirstPersonViewModel's mouse-look radians-per-pixel scalar.
	brightness = 0,    -- ColorCorrectionEffect.Brightness applied by SettingsClient
	                   -- (client-local post-process, range roughly -0.15..0.15).
	                   -- Deliberately NOT Lighting.Brightness: DayNightService drives
	                   -- Lighting.ClockTime authoritatively every Heartbeat, and a
	                   -- ColorCorrectionEffect sidesteps that entirely instead of
	                   -- fighting it for one property.
}

local saved = SettingsStore.Get().video
if type(saved) == "table" then
	for key, value in pairs(saved) do
		if type(value) == "number" and defaults[key] ~= nil then
			defaults[key] = value
		end
	end
end

return defaults
