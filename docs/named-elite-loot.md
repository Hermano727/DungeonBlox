---
title: Named Elite Loot
tags: [loot, mobs, named-elite, terminology]
aliases: [High Roll Equivalent, Elite Gear]
---

# Named Elite Loot

Signature gear dropped by named elites (`MobData` `IsNamedElite`). This is **not** the dungeon Mythic system — see the comparison at the bottom.

| Piece | Where |
|---|---|
| Data (who drops what, chance table) | `RS/NamedEliteLootDefs` |
| Roll + build + drop | `SSS/NamedEliteLootService` |
| Hook | `LootService.onMobDied`, after the Mythic roll |
| Base-stat "high roll" | `ItemGenerator` `options.highRoll` |

## Terminology: "high roll <rarity> equivalent gear"

An item generated at a **real rarity**, at that rarity's **maximum base-stat roll**, then scaled by level as usual.

Worked through with Kane's axe — a **high roll Rare equivalent**, T1, level 12:

1. **Rare T1 weapon damage** is `min = {11,12}`, `max = {12,13}` (`ItemConfig.WEAPON_DMG_RANGES`). An ordinary Rare rolls anywhere inside those.
2. **High roll takes the top of each**: min becomes `12`, max becomes `13`. Never 11.
3. **Level scaling then applies**, unchanged: `+1% per level above the tier median`. T1's median is 10 and Kane is level 12, so `x1.02` — `12 -> 12`, `13 -> 13` after flooring.

So a high roll Rare equivalent is always the best Rare of its tier, and is still honestly a Rare — it shows Rare colours, it is not a secret Epic.

Only **base** stats are high-rolled (weapon damage, armor HP/armour/energy). Substats are authored per item as explicit ranges and roll normally inside them, because the author already chose the window they want.

`highRollStandard = true` on a substat means "top of that substat's own standard roll for this tier/rarity" — used for `str`/`vit`, whose values come from `ARMOR_SUBSTAT_RANGE` and the rarity multiplier rather than a hand-written range.

## Drop chance

`BASE_CHANCE_DENOMINATOR` is the chance of a **Rare-equivalent** drop from an elite of that tier:

| Tier | Rare | Epic (x1.3) | Legendary (x1.7) |
|---|---|---|---|
| T1 | 1/32 | 1/42 | 1/55 |
| T2 | 1/64 | 1/84 | 1/109 |
| T3 | 1/96 | 1/125 | 1/164 |
| T4 | 1/128 | 1/167 | 1/218 |
| T5 | 1/192 | 1/250 | 1/327 |

```
chance = 1 / ceil(BASE_CHANCE_DENOMINATOR[tier] * RARITY_DENOMINATOR_MULT[rarity])
```

The multiplier grows the **denominator**, so better gear is rarer. Rounding is always **up**, so a multiplier can only ever make a drop rarer, never (through rounding) more common.

**Every pool entry rolls independently.** The table above really is "the chance to get that drop" — an elite with five authored items is not splitting one roll five ways. Kane's five pieces at 1/32 each work out to roughly a 15% chance of at least one piece per kill.

Drops land on the ground as world loot for the killing player only, like ordinary overworld gear.

## Block

`block` is a real combat stat as of 2026-09-17. It was already in `ARMOR_BONUS_EFFECTS` as inert data.

- Summed across **equipped** gear (`StatsService.SumEquippedSubStat`).
- Rolled on **every incoming hit** in `DamageService.ApplyToPlayer`.
- A blocked hit is **fully negated** — zero damage, and nothing downstream runs for it (no hunger drain, no combat timer, no armour durability loss).
- Capped at `ItemConfig.BLOCK_CHANCE_CAP_PCT` (**30%**). 32% is floored to 30. All-or-nothing negation with no cap trends toward immunity.
- Rolled **before** armour, since armour reduction is irrelevant to a hit that never lands.
- Plays one of five `BlockHit` sound variations, picked at random per proc. Without it a blocked hit is indistinguishable from the mob missing.

The sound takes the server -> client hop that server-decided one-shots use: `DamageService.PlayEffectFor(player, key)` fires `GameEvents/PlayEffectSfx` with a **key** from the `SoundEffects` registry, and `SfxNetClient` resolves it through `SfxService` so it still routes through that player's own Effects volume. No asset id crosses the wire. A registry entry may now be a list of ids — `PlayEffect` picks one at random, which is what makes the five variations work.

It reads the **modern** `ProfileService` profile, not the legacy `PlayerDataManager` one `DamageService` otherwise uses — equipped gear only exists in the modern one.

## Not the Mythic system

| | Named elite (this) | Dungeon boss Mythic |
|---|---|---|
| Data | `RS/NamedEliteLootDefs` | `RS/MythicItemDefs` |
| Service | `SSS/NamedEliteLootService` | `SSS/DungeonBossLootService` + `MythicItemBuilder` |
| Where | Overworld | Instanced dungeon |
| Who gets it | The killing player | Every player alive at boss death |
| Delivery | World-loot orb on the ground | Straight to inventory, shown in the run summary |
| Rarity | Real rarities, high-rolled | `Mythic`, above Legendary |
| Gated by | Flat per-item chance (elite spawn is what the pity feeds) | Flat chance per player |

Both are deliberately flat-chance with no loot pity. The pity in the named-elite loop is on the elite **spawning** (see [Mob & NPC System](./mob-and-npc-system.md)), not on its drops.

## Track playback tuning

A looped music track can carry per-track playback settings in `RS/Assets/Sounds/MusicPlayback`, keyed by the same `rbxassetid://` string the registries hand out:

- `StartTime` — seconds to skip at the start, applied on first play **and after every loop** (`Looped` restarts at 0, not at the offset). Seeking needs the asset loaded, so `ZoneClient` re-applies it on `Loaded` as well.
- `VolumeScale` — multiplied onto the player's own music volume, so one track can sit louder than the ambient zone tracks without overriding anyone's slider.

Kane's theme uses `StartTime = 2` and `VolumeScale = 1.5`. The scale rides on the `ZoneMusic` Sound as a `TrackVolumeScale` attribute, because `SettingsClient` writes that same `Volume` when a slider moves and has to carry the scale too.

## The `substats` / `subStats` trap

`ItemGenerator.generate` returns an **`ItemClass` instance**, whose substat field is **`substats`** (lowercase) and holds an **array of records** — `{ id, label, value, valueType }`. `subStats` (capital S) is a *different* shape that only exists on the granted **template**: a flat `{ [id] = value }` dict, produced by `ItemClass:toGrantTemplate()` from the array.

Both authored-loot builders used to assign a flat dict to `item.subStats` on the ItemClass. `toGrantTemplate` only ever reads `self.substats`, and both builders pass `substatCount = 0`, so that array was empty — **every authored substat was silently dropped**. Kane's Axe shipped with no critical / elemental / vs-Monsters, and every Mythic with none of its authored stats. Fixed 2026-09-18 in `NamedEliteLootService.rollAuthoredSubStats` and `MythicItemBuilder.Build`, both of which now build the array-of-records shape and take `label`/`valueType` from `ItemConfig.FindSubstatEffect` rather than hand-duplicating them.

Two consequences worth knowing:

- Authored `elemDmg` now correctly picks up the weapon-type multiplier that `getFinalStats()` applies to it (Axe 1.10, Bow 1.20). That is a real change from the broken status quo, not a regression.
- Anything that assigns substats onto an ItemClass must use the lowercase array. Do **not** make `toGrantTemplate` read both fields — that papers over the mismatch and leaves two competing sources of truth.

## Drop provenance

Each dropped template is stamped by `ItemIdentity` at drop time with `origin.d = entry.Key` (`"KaneAxe"`, `"KaneChest"`, ...). That is not cosmetic: `ItemStatRanges` reads it to resolve this piece's **authored** substat window instead of the generic per-tier one. Kane's Axe rolls 6-9% critical where the generic T1 window is 2-3, so without the def key a substat rebalance sweep would clamp every named-elite drop down to the generic maximum. See [Item Identity & Substat Ranges](./item-identity-and-ranges.md).
