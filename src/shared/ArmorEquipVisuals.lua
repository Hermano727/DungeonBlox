--!strict
--[[
	ArmorEquipVisuals
	Slot -> physical armor prefab under ServerStorage.ArmorModels.<Slot>, for the
	"wear what you have equipped" system. Mirrors LootDropVisuals' ByItemId/BySlot
	fallback shape (see ReplicatedStorage.Assets.Meshes.Loot.LootDropVisuals) so a
	specific item can later override the shared per-slot look without a code change.

	No entry (or an unresolvable prefab) means that slot shows nothing physical --
	intended behavior for every slot not listed here yet, not an error state.
]]

export type VisualEntry = {
	PrefabName: string, -- name of the Model/BasePart under ServerStorage.ArmorModels.<Slot>
	-- Which BasePart on the character to weld to. Defaults to "UpperTorso" (nil = that
	-- default) -- override per-entry for anything that should track a different bone,
	-- e.g. Helm -> "Head" so it turns with the head instead of riding the torso. Still
	-- a single rigid weld either way -- picking a different bone doesn't add deformation,
	-- it just picks which ONE bone's motion the whole piece rigidly follows.
	AttachPart: string?,
	-- Both optional, both nil by default (= identity C0 / the prefab's own cloned
	-- Size, exactly the old hardcoded behavior in ArmorVisualsService.ApplyVisual).
	-- Dialed in per-entry with UIDevTool (F6, Model mode -- see ArmorVisualsService's
	-- header comment for why a prefab needs this at all): equip it, tune by eye,
	-- Enter to print a paste-ready snapshot, paste the two lines it prints here.
	WornC0: CFrame?,
	WornSize: Vector3?,
}

local ArmorEquipVisuals = {}

ArmorEquipVisuals.ByItemId = {} :: { [string]: VisualEntry }

-- 2026-08: Chest and Helm are tuned and live. Legs/Boots are DELIBERATELY not
-- registered right now -- see the big comment below the table for why. Shield still
-- has no prefab at all yet. (Helm ALSO still has ServerStorage.ArmorModels.Helm."T1
-- Helm" -- a real Accessory meant for Humanoid:AddAccessory(), not this path --
-- deliberately left alone; the new prefab is named "T1Helm" (no space) precisely so
-- it doesn't collide with that older Accessory entry.)
ArmorEquipVisuals.BySlot = {
	-- Tuned live in Studio via UIDevTool (F6, Model mode) -- Enter there prints
	-- exactly this shape. Both pieces are a single rigid Motor6D weld (Chest to
	-- UpperTorso, Helm to Head via AttachPart below) -- fine for Chest (UpperTorso
	-- doesn't rotate relative to itself) and close enough for Helm (the head doesn't
	-- swing far from the torso in normal animation).
	Chest = {
		PrefabName = "T1Chestplate",
		WornC0 = CFrame.new(0.000, -0.240, 0.000),
		WornSize = Vector3.new(1.3356, 1.7366, 1.0909),
	},
	Helm = {
		PrefabName = "T1Helm",
		AttachPart = "Head",
		WornC0 = CFrame.new(0.020, 0.380, -0.080),
		WornSize = Vector3.new(0.8880, 1.0779, 0.9809),
	},
} :: { [string]: VisualEntry }

-- Legs and Boots are OFF on purpose (no BySlot entry -> ArmorVisualsService.ApplyVisual
-- silently shows nothing physical for those slots -- see this file's header comment).
-- A single rigid mesh anchored to one bone genuinely cannot follow either slot: each
-- leg bends at the hip AND the knee independently during the walk cycle, and each foot
-- swings independently of the other, so T1Leggings/T1Boots (still sitting in
-- ServerStorage.ArmorModels.Legs/.Boots, untouched) would visibly float/clip off the
-- body the moment the character moves, not just look slightly off. Chest and Helm
-- don't have that problem (single bone, doesn't bend), which is exactly why only
-- those two are live.
--
-- The real fix is Layered Clothing: an official retopo'd/rigged/weighted model
-- (LeftShoe/RightShoe accessories for Boots, a cage-deformed garment for Legs/pants)
-- that's skinned to the R15 skeleton so it bends with each joint instead of riding
-- one rigid bone -- a proper asset-pipeline pass, not a script change. Once that
-- exists, re-add BySlot.Legs / BySlot.Boots (PrefabName + AttachPart as needed) the
-- same way Chest/Helm are set up above.
--
-- ArmorEquipVisuals.BySlot.Legs = { PrefabName = "T1Leggings" }
-- ArmorEquipVisuals.BySlot.Boots = { PrefabName = "T1Boots" }

function ArmorEquipVisuals.Get(itemId: any, slot: string): VisualEntry?
	if type(itemId) == "string" then
		local byId = ArmorEquipVisuals.ByItemId[itemId]
		if byId then
			return byId
		end
	end
	return ArmorEquipVisuals.BySlot[slot]
end

return ArmorEquipVisuals
