-- Single source of truth for every persisted Settings-menu value's valid
-- range. Read by SettingsClient (slider min/max) AND SettingsDataService
-- (server-side clamp on every value before it's saved), so client display
-- and server validation can never drift apart. Also doubles as the
-- server-side whitelist of which (category, key) pairs are legal to save --
-- SettingsDataService rejects anything not listed here.
local AudioCategories = require(script.Parent:WaitForChild("AudioCategories"))

-- Every sound bucket's slider is a 0..1 volume (2026-10-11: derived, so a new bucket in
-- AudioCategories.CATEGORIES saves with no edit here).
local volume = {}
for _, category in ipairs(AudioCategories.CATEGORIES) do
	volume[category.id] = { min = 0, max = 1 }
end

return {
	volume = volume, -- one key per AudioCategories bucket (built above)
	video = {
		fov         = { min = 60, max = 100 },
		sensitivity = { min = 0.0012, max = 0.006 },
		brightness  = { min = -0.15, max = 0.15 },
	},
	hud = {
		crosshair = { min = 0, max = 1 }, -- 1 shown (default), 0 hidden; the quick-nav toggle (client/Crosshair)
	},
}
