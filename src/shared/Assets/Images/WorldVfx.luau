--[[
	WorldVfx -- ReplicatedStorage/Assets/Images

	Images drawn on parts in the world (SurfaceGui / Billboard / Decal / particle / beam VFX), not
	HUD art. Particle textures are white/grey with real alpha (tools/vfx_assets/process.py), meant to
	be tinted by the emitter's Color, so one texture serves any element.

		WAYSTONE_VORTEX   the golden swirl inside a waystone's ring (WaystoneVortexClient).
		                  Source: assets/builds/SafeZones/waystone model/Golden Hexagonal Energy
		                  Vortex.png, its white wisps masked to transparent on upload.

	Generic VFX textures (source: assets/vfx/FireTornado/side effect images/<same name>.png):
		SMOKE_PUFF_4X4    16 cel-shaded smoke puffs, a Grid4x4 flipbook (use FlipbookMode Random).
		FLAME_STREAK      a horizontal band of flame wisps, tiles left/right (Beam texture).
		SPARK             one sharp vertical streak (Orientation VelocityParallel).
		SHOCK_RING        a wind-swept shockwave ring, empty centre (flat Decal, seen from above).
		CHANNEL_SIGIL     a flame-stroke ring with four outward points (ground Decal).
		ALERT_DOUBLE      the red double exclamation mark: "dodge this" above a caster's head.
		                  Source: Dynamic Red Double Exclamation Icon.png (already transparent).
]]

return table.freeze({
	WAYSTONE_VORTEX = "rbxassetid://139488979468987", -- Golden Hexagonal Energy Vortex.png

	SMOKE_PUFF_4X4 = "rbxassetid://94140595468150", -- T_SmokePuff_4x4.png
	FLAME_STREAK = "rbxassetid://132893131243773", -- T_FlameStreak.png
	SPARK = "rbxassetid://92090743660887", -- T_Spark.png
	SHOCK_RING = "rbxassetid://117480104116450", -- T_ShockRing.png
	CHANNEL_SIGIL = "rbxassetid://71240295297667", -- T_ChannelSigil.png
	ALERT_DOUBLE = "rbxassetid://127400380429153", -- Dynamic Red Double Exclamation Icon.png
})
