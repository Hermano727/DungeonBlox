--[[
    WeaponMeshes
    Central registry for weapon mesh + texture asset IDs.
    Require this instead of writing rbxassetid:// literals inline or leaving
    IDs stranded on instance properties in the DataModel.

    Keys match the corresponding itemId in ReplicatedStorage/ItemDefinitions
    and the WeaponId attribute on the Tool prefab.

    Each entry:
        MeshId    : mesh asset, applied to the Tool's Handle (a MeshPart)
        TextureId : base colour map applied to that MeshPart
        GripDrop  : studs the authored grip sits below the mesh bounding-box
                    centre. Roblox welds Tools by Handle.CFrame (the bbox
                    centre) and ignores PivotOffset, so Tool.Grip must
                    compensate: Tool.Grip = CFrame.new(0, GripDrop, 0)

    Authoring convention (Blender): origin at the grip point, blade along +Z
    in Blender, which becomes +Y in Roblox after FBX axis conversion. Weapons
    authored this way need no hand-tuned Grip rotation.
]]

return {
	TRAINING_SWORD = {
		MeshId    = "rbxassetid://88260580369470",
		TextureId = "rbxassetid://94891321674818",
		-- 70% overall scale, with 5% extra length along the blade axis.
		GripDrop  = -0.951825,
	},
	-- The T1 bow (2026-10-02, assets/models/armor weapons equipment/T1_Bow). No string in the
	-- mesh: Beams draw it so it can pull back (WeaponAttachClient). Held by the bone visual in
	-- Hand_L at BowConfig.BOW_GRIP, so it has no GripDrop. Studio: ServerStorage.WeaponModels.Bow.T1_Bow.
	WOODEN_BOW = {
		MeshId    = "rbxassetid://137027378165326",
		TextureId = "rbxassetid://120577722678421",
		ModelAssetId = "85213412175206",
	},
	-- Its arrow: tip along the LookVector (-Z), 2.4 studs. ServerStorage.WeaponModels.Bow.T1_Arrow.
	-- (Model 89694579863566 was the first upload, tip-backward: don't use it.)
	T1_ARROW = {
		MeshId    = "rbxassetid://102941307144446",
		TextureId = "rbxassetid://104685580280572",
		ModelAssetId = "77051351201333",
	},
}
