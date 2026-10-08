---
title: Items, Loot & Progression
tags: [items, loot, progression]
aliases: [Item Generation, Loot]
---

# Items, Loot & Progression

## Item pipeline

```
ItemConfig (RS) -- raw stat tables
  -> ItemGenerator (SSS) -- rolls rarity/stats -> ItemClass
  -> ItemClass (SSS) -- getFinalStats(), toGrantTemplate()
  -> LootService (SSS) -- MobManager.ProcessMobDeath -> grant -> ItemDropNotify
  -> LootClient -- top-right banner
```

`ItemConfig`: TIER_MEDIANS, ARMOR_*_RANGES[tier][rarity], WEAPON_DMG_RANGES, WEAPON_MULTIPLIERS (Sword 1.00..Bow 1.20), TIER_DROP_CHANCE (server-side only!), TIER_RARITY_WEIGHTS.

Scale formula (`SSS/ItemGenerator.scaleStat`): `base*(1+(lvl-tierMedian)*0.01)`, floor; if lvl>100 also floor at `base*(1+(lvl-100)*0.05)`. Armor hps=floor(hp*0.5). Energy is float, 2dp.

GrantItem template: `{name, type, rarity, tier, enchantLevel, subStats={}, equipSlot, tags={}}`.

`RS/ProfileTypes`: `DefaultProfile()`, `ValidateItemTemplate`, `VALID_SLOTS`, `GetAllowedEquipSlot(item)`.

`SSS/StatsService.RecomputeRuntimeHp(profile)` — call after every GrantItem.

## Loot & scoring

- **Loot:** private, visual "flying keys" mob→world chests (Food/Green, Normal/White, Elite/Purple).
- **Score:** 1 Score = 1 Loot Roll. Damage-weighted kill credit; base score 1 (world) / 4 (dungeon) to all party.
- **Dungeons:** instanced 8-player, tier keys + difficulty mods. Auto-Scrap low-tier loot.

## Enchanting

- Safe to +3. From +4 a failed enchant BREAKS the item: -3 enchant levels (min +0), durability 0, unequipped, 3x repair cost. Max +9.
- Protection scrolls (Dungeoneer, applied at the Enchanting Station, always succeed) stop the break for attempts up to +8 (`EnchantScrollApply.PROTECTION_MAX_LEVEL`). The attempt uses the protection up whether it passes or fails.
- Durability: every weapon and armor piece wears (-1 per hit dealt or taken). Death costs every EQUIPPED piece 30% of its max; bag items and profession tools are spared. At 0 it breaks (same rule as above). Repair at a Blacksmith.
- Implementation-level gotchas (RNG duck-typing, validation, sync race) live in [Enchant Scrolls](./enchanting.md).

## Level scaling

- Damage penalty if mob 5+ levels above; XP penalty if mob 5+ levels below.

## Professions

- Mining + Spear-Fishing. Tools roll substats. 2:1 Ore→Scrap.

## Related

- [Inventory & Equipment](./inventory-and-equipment.md) — the two profile/ownership systems, hotbar/bag placement, equip rules.
- [Asset & Naming Conventions](./asset-conventions.md) — tiering naming scheme (`T1_Sword` etc.) and the icon/mesh asset registries.
- [Combat, Energy & Death](./combat.md) — what survives on death.

## Crafting orbs (`RS/CraftingOrbApply`, applied at the Enchanting Station)

Only **Wisdom** and **Alteration** do anything yet; the other orbs are refused before they're consumed.

- **Wisdom:** item level +1 (cap tier x 20). It raises the BASE stats, scaled from the raw rolled base like a drop at that level (`scaleStat`): weapons dmgMin/dmgMax, armor hp (+ hps on shields only). Unlike an enchant scroll (x1.05 of the CURRENT value), it never compounds on itself. On an enchanted item the level goes onto the pre-enchant snapshot (`baseSubStats`) and the enchant is replayed on top (`EnchantScrollApply.RebuildEnchantOwned`), so it keeps the enchant bonus and a later break doesn't undo it.
- **Alteration:** wipes and rerolls the substats (never base stats). 50/50 win or lose sets the count: win = `WIN_SUBSTAT_DIST` by tier (T1 1/2/3 at 40/40/20%); lose = `LOSE_SUBSTAT_RANGE` for weapons (T1 always 1), always 1 for armor.
  - Weapons: 75% elemental damage first, then picks weighted by base weight x weapon-type modifier, melee/ranged filtered.
  - Armor: slots 1-2 each 50/50 stat pool (VIT/STR/DEX/INT, max 2) vs bonus pool; slot 3+ from everything left.
  - Every roll uses the `Random` the caller passes (`ProfileService` gives `Random.new()`), so a seeded one reproduces a roll.
- Enchant breaks only rebuild the stats the enchant owns, so orb rolls survive a break.
