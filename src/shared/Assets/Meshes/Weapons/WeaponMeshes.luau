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
}
