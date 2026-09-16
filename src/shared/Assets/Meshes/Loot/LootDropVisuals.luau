--[[
	LootDropVisuals
	Registry of world-dropped-loot visuals: which real mesh (if any) a drop
	shows instead of the generic floating Neon ball, keyed the same way
	WorldLootService already identifies a drop.

	No entry (or an unresolvable prefab) falls back to the default ball --
	that is the intended behavior for everything not listed here, not an
	error state.

	MeshPart.MeshId cannot be assigned at runtime (Roblox capability
	restriction -- see the Rojo limitations section of .claude/CLAUDE.md), so
	`AssetId` below is documentation/provenance only (what was imported, so a
	future re-import or asset audit doesn't need to go spelunking through
	Studio for it). The actually-usable reference is `PrefabName`: a single
	BasePart already imported by hand into ServerStorage.LootDropVisuals
	(same "ServerStorage.DungeonToolPrefabsArchive" pattern ItemDefinitions'
	ToolPrefabName already uses). Studio owns that tree -- it's in Rojo's
	syncbackRules.ignoreTrees -- so it is never touched by a disk sync, and
	adding an entry here is only half the job: the prefab has to exist under
	ServerStorage.LootDropVisuals with a matching name, pre-scaled to its
	final in-world size and anchored/non-collidable, or the lookup silently
	falls back to the ball.

	Three lookup shapes, matching the three ways WorldLootService.SpawnMobDrop
	identifies a drop:
		ByCurrency[currencyName]        -- kind = "coins" (currencyName = "Coins")
		ByItemId[itemId]                -- kind = "item_id" (key fragments today, Ore/Scrap/... later)
		ByGearItemId[itemId] /
		ByGearTag[tag]                  -- kind = "item_template" (rolled gear); itemId checked
		                                    first (a specific catalog entry), then tags so a whole
		                                    weapon/armor family can share one visual without an
		                                    entry per rolled instance. Nothing populates these yet --
		                                    rolled gear still drops as the default ball -- but the
		                                    lookup path already exists so wiring one in later is just
		                                    a data addition, no code change.
]]

export type VisualEntry = {
	AssetId: string, -- documentation only, see note above -- not used at runtime
	PrefabName: string, -- name of the BasePart under ServerStorage.LootDropVisuals
}

local LootDropVisuals = {}

LootDropVisuals.ByCurrency = {
	Coins = { AssetId = "125197850111990", PrefabName = "GoldCoin" },
} :: { [string]: VisualEntry }

-- T1KeyFragment's pristine source lives at ServerStorage.MaterialModels.T1KeyFragment
-- (same untouched-import convention as ArmorModels/WeaponModels); its
-- ground-display clone is ServerStorage.LootDropVisuals.T1KeyFragment, scaled
-- 1.2x from native -- same reasoning as the ByGearTag armor pieces above
-- (native import scale reads uniformly tiny), kept the SMALLEST of every
-- scaled drop since a key fragment should read as the least significant pickup.
-- Kind = "item_id" drops (WorldLootService.SpawnMobDrop) resolve through THIS
-- table, not ByGearTag -- key fragments/Ore/Scrap/... carry a real itemId,
-- unlike rolled gear.
LootDropVisuals.ByItemId = {
	T1KeyFragment = { AssetId = "107802065311979", PrefabName = "T1KeyFragment" },
} :: { [string]: VisualEntry }

LootDropVisuals.ByGearItemId = {} :: { [string]: VisualEntry }

-- Keyed by the ARMOR_SLOTS tag (src/shared/ItemConfig.lua) every rolled
-- armor piece carries in template.tags -- rolled armor never gets an itemId
-- (see ItemClass:toGrantTemplate), so tags are the only way an armor drop
-- resolves to a mesh. Each PrefabName below is a reoriented ground-display
-- clone (identity rotation, non-collidable) living under
-- ServerStorage.LootDropVisuals; the pristine imported asset for each slot
-- lives untouched at ServerStorage.ArmorModels.<Slot>.<Name> as the future
-- source for a "wear what you have equipped" system. All these imports come
-- through a pipeline that normalizes every mesh to ~1 stud on its longest
-- axis regardless of what the real object is, so "native scale" reads as
-- uniformly tiny and carries no real relative-size information -- every
-- ground-display clone below is scaled up from its pristine source by hand.
-- Chestplate (3.0x) is the confirmed-correct reference size; everything
-- else is scaled proportionally under that, largest to smallest: Shield
-- (2.5x) > Helm (1.8x) > Leggings (1.7x) > Boots (1.5x).
--
-- Sword/Bow use the SAME tag every rolled weapon of that type carries
-- (ItemClass:toGrantTemplate sets tags={self.weaponType}, e.g. "Sword"/"Bow")
-- -- one entry covers every rolled weapon of that type. Sword's PrefabName
-- reuses the EXISTING ServerStorage.DungeonToolPrefabsArchive.TrainingSword.Handle
-- mesh (see ensureWeaponDropToolPrefabOnItem/WEAPON_DROP_PREFAB_BY_TYPE.Sword --
-- no new asset import there); its long axis was 3.5 studs (a different,
-- non-normalized import, so it never needed the *x scaling the armor pieces
-- above did), then reduced 20% by direct request to 2.8 studs. Bow is a
-- freshly imported model instead -- its pristine source lives at
-- ServerStorage.WeaponModels.Bow.T1Bow (same ArmorModels.<Slot>.<Name>
-- convention, just for weapons), ground-display clone at
-- ServerStorage.LootDropVisuals.T1Bow. Went out at native import scale
-- originally (read tiny on the ground, same as every other unscaled armor
-- import above), scaled up 4x by hand (~4 studs long), then reduced 25% by
-- direct request to its current ~3-stud long axis.
LootDropVisuals.ByGearTag = {
	Chest = { AssetId = "117934682706534", PrefabName = "Chestplate" },
	Legs = { AssetId = "74876512679286", PrefabName = "Leggings" },
	Boots = { AssetId = "136392274325267", PrefabName = "Boots" },
	Helm = { AssetId = "93914571193463", PrefabName = "Helm" },
	Shield = { AssetId = "100262002009944", PrefabName = "Shield" },
	Sword = { AssetId = "DungeonToolPrefabsArchive.TrainingSword.Handle", PrefabName = "TrainingSword" },
	Bow = { AssetId = "99773506801602", PrefabName = "T1Bow" },
} :: { [string]: VisualEntry }

function LootDropVisuals.GetForCoins(): VisualEntry?
	return LootDropVisuals.ByCurrency.Coins
end

function LootDropVisuals.GetForItemId(itemId: any): VisualEntry?
	if type(itemId) ~= "string" then
		return nil
	end
	return LootDropVisuals.ByItemId[itemId]
end

-- template is a grant-template table (WorldLootService dropSpec.template):
-- itemId is checked first since it names one specific catalog entry, tags
-- second since rolled/generated gear often has no catalog itemId at all
-- (see the EnchantScrollApply gotcha in .claude/CLAUDE.md -- same reason
-- ensureWeaponDropToolPrefabOnItem falls back to tags).
function LootDropVisuals.GetForGearTemplate(template: any): VisualEntry?
	if type(template) ~= "table" then
		return nil
	end

	local itemId = template.itemId
	if type(itemId) == "string" then
		local byId = LootDropVisuals.ByGearItemId[itemId]
		if byId then
			return byId
		end
	end

	local tags = template.tags
	if type(tags) == "table" then
		for _, tag in ipairs(tags) do
			local byTag = LootDropVisuals.ByGearTag[tag]
			if byTag then
				return byTag
			end
		end
	end

	return nil
end

return LootDropVisuals
