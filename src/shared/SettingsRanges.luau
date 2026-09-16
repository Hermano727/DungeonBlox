-- Single source of truth for every persisted Settings-menu value's valid
-- range. Read by SettingsClient (slider min/max) AND SettingsDataService
-- (server-side clamp on every value before it's saved), so client display
-- and server validation can never drift apart. Also doubles as the
-- server-side whitelist of which (category, key) pairs are legal to save --
-- SettingsDataService rejects anything not listed here.
return {
	volume = {
		master   = { min = 0, max = 1 },
		music    = { min = 0, max = 1 },
		movement = { min = 0, max = 1 },
		effects  = { min = 0, max = 1 },
	},
	video = {
		fov         = { min = 60, max = 100 },
		sensitivity = { min = 0.0012, max = 0.006 },
		brightness  = { min = -0.15, max = 0.15 },
	},
}
