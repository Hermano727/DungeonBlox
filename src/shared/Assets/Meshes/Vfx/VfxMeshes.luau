--[[
	VfxMeshes -- ReplicatedStorage/Assets/Meshes/Vfx

	Uploaded VFX models (Open Cloud, tools/roblox_upload.py), KEY = asset id. SSS/VfxModelLoader
	loads each one at server start with InsertService:LoadAsset and parents it to
	ReplicatedStorage.VfxModels under its KEY, so clients clone `VfxModels:WaitForChild(KEY)`. No
	Studio-owned copy: the id here is the only reference. Every upload is a new asset, so a
	re-export means a new id here.

	The first entry was the fire tornado's mesh (FIRE_TORNADO, 131524924689551), retired
	2026-10-08 for a trail-built tornado: MeshPart.TextureID ignores alpha, so a textured tube
	always rendered solid. See docs/vfx-pipeline.md.

	Dungeon clear sequence (client/DungeonClearSequence), 2026-10-10: the Tripo models, cleaned by
	assets/models/dungeons/build_clear_props.py (renamed, no Tripo ids left; scaled in studs; the
	coal bed and the glow shell added). The textured parts keep their texture; the client only
	styles the untextured helpers.
		CLEAR_BRAZIER   MeshParts Brazier (textured) + Coals (Neon in game), origin at the floor,
		                4.8 studs tall
		CLEAR_RELIC     MeshParts Relic (textured) + EmberGlow (a faint Neon shell), 3 studs
		CLEAR_WINGS     MeshParts WingL + WingR (the right a mirror; assets/models/dungeons/build_angel_wings.py),
		                11 studs shoulder to tip, each origin its shoulder; the Benediction's wings
		CLEAR_ANGEL     MeshPart Angel (assets/models/dungeons/build_angel_figure.py): the hooded figure that
		                replaces the Benediction's orb, 9 studs tall, origin at its bounding-box centre
	(Superseded placeholders: 119260802896138 / 91495451561410, assets/vfx/DungeonClear/build_placeholders.py.)
]]

return table.freeze({
	CLEAR_BRAZIER = 137597446518185,
	CLEAR_RELIC = 84405465677004,
	CLEAR_WINGS = 98492432526974,
	CLEAR_ANGEL = 128070856186491,
})
