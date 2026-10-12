--[[
	ClearSequenceArt -- ReplicatedStorage/Assets/Images

	Bespoke textures for the dungeon clear sequence (client/DungeonClearSequence). An empty entry
	falls back to a bundled Roblox particle or an existing WorldVfx texture (DungeonClearSequence/Fx).
	Prompts: docs/dungeon-clear-asset-requests.md. Particle textures follow the WorldVfx rule
	(white/grey with real alpha, tinted by the emitter's Color).

	Sources: assets/vfx/DungeonClear/incoming/<file named below>, processed by
	tools/vfx_assets/process.py (lum, or grid4 for the 4x4 sheets), uploaded 2026-10-10. The beam
	textures and the two single sprites were also trimmed to their content (sprites padded back to
	square); there is no processed copy in the repo.

		FEATHER      one feather, quill on the LEFT (the wing Beams' core end), stretched along each
		             wing Beam (TextureMode Stretch)
		LIGHT_SHAFT  rays running left to right; LEFT = the ceiling end of the Benediction's shaft Beam
		EMBER        a hot ember, tip up and tail down (sparks with Orientation VelocityParallel)
		FIRE         16 flame licks, a 4x4 flipbook (FlipbookMode Random); flames point up, so fire
		             emitters keep Rotation near 0
		SPARKLE      a four-point star glint (dust motes, wing glints, reveal bursts)
		SHROUD_BURN  16 burning cloth scraps, a 4x4 flipbook: what flies off a relic as its shroud burns
		SMOKE        unused: the show uses WorldVfx.SMOKE_PUFF_4X4 (Kane's smoke sheet)
]]

return table.freeze({
	FEATHER = "rbxassetid://81402226241447", -- Ornamental Monochrome Feather Emblem.png
	LIGHT_SHAFT = "rbxassetid://132828130219206", -- Monochrome Energy Flow Streaks.png
	EMBER = "rbxassetid://78892450900135", -- Centered Monochrome Energy Flame.png
	FIRE = "rbxassetid://102419353183873", -- Grayscale Flame Sprite Sheet.png (4x4)
	SPARKLE = "rbxassetid://128744427771876", -- Minimalist Monochrome Starburst Sparkle.png
	SHROUD_BURN = "rbxassetid://98245405604945", -- Monochrome Burning Rag Sprite Sheet.png (4x4)
	SMOKE = "",
})
