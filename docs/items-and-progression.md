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

- Safe to +3. +4 fail (20%) breaks item (3x repair), resets to +0. Max +9. Protection scrolls block breaking, not failure.
- Implementation-level gotchas (RNG duck-typing, validation, sync race) live in [Enchant Scrolls](./enchanting.md).

## Level scaling

- Damage penalty if mob 5+ levels above; XP penalty if mob 5+ levels below.

## Professions

- Mining + Spear-Fishing. Tools roll substats. 2:1 Ore→Scrap.

## Related

- [Inventory & Equipment](./inventory-and-equipment.md) — the two profile/ownership systems, hotbar/bag placement, equip rules.
- [Asset & Naming Conventions](./asset-conventions.md) — tiering naming scheme (`T1_Sword` etc.) and the icon/mesh asset registries.
- [Combat, Energy & Death](./combat.md) — what survives on death.
