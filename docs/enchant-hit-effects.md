---
title: Enchant Hit Effects
tags: [combat, enchants, vfx]
aliases: [Enchant Effects, Shatter, Crushing, Cleave]
---

# Enchant hit effects

Attacker-local world effects driven by **confirmed** combat outcomes, plus the gameplay several of those enchants gained along the way. Every proc is rolled on the server; cosmetic code never rolls anything.

| Piece | Where |
|---|---|
| Effect geometry (all 10) | `client/EnchantHitEffects` |
| Visual tuning (colour, duration, order, caps) | `RS/EnchantHitEffectConfig` |
| Normalized timing curves | `RS/EnchantHitEffectMotion` |
| Which effects a hit earned | `SSS/EnchantHitFeedback` |
| Armor break / ignore | `SSS/ArmorEnchantService` + `RS/ArmorEnchantConfig` |
| Target statuses (bleed/blind/slow) | `SSS/CombatEnchantStatus` + `RS/CombatEnchantConfig` |
| Damage-number colour by source | `RS/DamageNumberStyles` |
| Life Steal HUD | `client/LifeStealBarFeedback`, mounted by `HealthClient` |
| Delivery | 5th `DamageNumberEvent` argument; rendered from `DamageNumberClient` |

## The effects

### Armor and impact

- **Execute** — dark red jaws close, then shed embers. Fires only when Execute actually **added damage**, so it is not an instant-kill indicator. Damage behavior pre-existed.
- **Shatter** — a steel shell cracks and bursts. **Gameplay (new):** reduces armor by 20% for 3 seconds, including the triggering hit. Refreshes duration without stacking, and the break is shared across attackers.
- **Crushing** — fragments compress inward, hold, then release a pressure ring and falling chips. **Gameplay (new):** ignores 50% of the remaining armor, for that hit only.
- **Piercing** — a narrow needle and exit spray along the attack direction. Follows the existing always-on Piercing bonus; this pass did not rebalance it.

Shatter/Crushing item values remain **proc chances**; strength and duration live in `ArmorEnchantConfig`. When both proc, 100 armor becomes 80 from Shatter and then 40 for that Crushing hit; the next ordinary hit sees 80, and expiry restores the current base armor. Base gear and mob stats are never modified, and **zero-armor targets trigger neither**.

`ArmorEnchantService` owns server-only, weak-keyed expiry. Mob damage checks invulnerability before resolving armor, PvP checks block first, and respawns start clean because a new character is a new key.

### Splash, status and drain

- **Cleave** — a broad sweep past the struck target. **Gameplay (new):** 30% splash damage, 5-stud radius, up to 3 extra targets. Works in PvE and PvP; each splashed target gets its own effect.
- **Bleeding** — a wound streak, then sparse drops on each tick. **Gameplay:** the item value is a **proc chance**; on proc the target bleeds for **50% of the hit that applied it**, spread over 3 ticks 1 second apart. **Stacks** — every proc is its own independent bleed with its own timer and its own per-tick damage, capped at 5 concurrent (oldest dropped). Ticks route through the normal damage path, so they award kill credit and fire their own damage numbers, **in red** (`RS/DamageNumberStyles`) so they read apart from weapon damage.
- **Blinding** — a compact starburst and broken halo. **Gameplay (new):** 2 seconds, 50% miss chance. Applies in **both** directions: a blinded mob's hits are nullified in `DamageService`, and a blinded player's swings miss in `MobCombat`.
- **Slowness** — a flash of dragging ankle bands on the proc, then a **persistent ring of white dashes on the ground** under the target for as long as the slow lasts (`EnchantSlowMarkers`). **Gameplay (new):** -20% movement speed for 3 seconds, non-stacking. See below.
- **Life Steal** — no world effect by design. It shows on the **health bar**: the recovered HP is highlighted as its own segment with a pulse, and rapid heals coalesce into one readout. **Gameplay (new):** heals a percent of damage **actually dealt**, capped by real health lost — never overkill, never pre-armor damage — and capped again at missing HP. Returns a receipt so the HUD can tell Life Steal apart from regen or potions.
- **Elemental** — embers climbing from the impact. Fires off the existing `elementalDamage` bonus.
- **Glowing** — a lingering spark at the impact point. **Visual only.** The flag is just "the weapon has the stat"; Glowing still has no mechanic.

### Slowness

**Two sources, one status.** The `slowness` substat (bows only, `rangedOnly`) rolls its own chance, and **any hit that dealt elemental damage** gets a separate flat `ElementalSlowChance` (5%) — ice chills on its own. Either lands the same non-stacking status: a second proc refreshes the 3-second timer, it never deepens the slow or runs two timers.

**-20% movement speed** (`SlowMultiplier = 0.80`), applied at every movement site rather than at one:

- **Mobs** go through `MobClass:GetEffectiveMoveSpeed()`, which multiplies `Stats.MoveSpeed` by the status multiplier. `StepToward`, the informational `humanoid.WalkSpeed` write, and `HoppingMobClass`'s hop distance and hop speed all read it. Hoppers matter here: leaving them on raw `MoveSpeed` would have made a slowed slime hop exactly as far, exactly as often, since its translation speed is derived from that one number.
- **Players** (PvP) go through `EnergyServer.applyWalkSpeed`, where the slow is the **last** factor — it scales whatever sprint/crouch/pant state and speed buffs already decided, rather than fighting them for ownership of `WalkSpeed`. That function is event-driven, so `connectCharacter` also re-runs it on `EnchantSlowed` changing; otherwise a slow landing mid-run wouldn't show until the next sprint or buff change, and wouldn't lift on expiry.

**The marker** is driven by a `CollectionService` tag (`EnchantSlowed`) written next to the attribute in `CombatEnchantStatus`, so it can never outlive the status and needs no remote of its own — tags replicate, so every client sees every slowed target. `EnchantSlowMarkers` draws five white dashes in a slowly rotating ring at foot height, sized to the target's footprint, culled at 120 studs. Deliberately not a trail: a trail reads as "moving fast", the opposite of the thing being communicated.

## Damage-number colour

The `DamageNumberEvent` payload carries an explicit **source key** as its 6th argument (`RS/DamageNumberStyles.Sources`). Bleed ticks pass `Bleed` and render red; everything else passes nothing and renders the default white. Crit colours still win.

**The client cannot infer this.** `enchantFeedback.effects.Bleeding` is true on a bleed *tick* and equally true on the weapon hit that *applied* the bleed — `CombatEnchantStatus.Apply` returns the proc in `extras` and `EnchantHitFeedback.Select` merges it into the main hit's effects. The two are indistinguishable client-side, so the source has to travel on the wire as its own field. Cleave splash stays white deliberately: it is still a hit from your weapon.

Adding a colour for another source is a key in `DamageNumberStyles.Sources`, a colour in `.Styles`, and passing the key at the relevant `damageNumberEvent:FireClient` site in `MobCombat`. Note this is separate from `EnchantHitEffectConfig`'s palette, which colours the world-space burst — a burst colour and a small-text colour want different tuning, so the number reads brighter. Retune them together.

## Proc chances vs. strengths

Item substat values are **proc chances** (percent) for Shatter, Crushing, Cleave, Blinding, Slowness and Bleeding. Slowness rolls **6-12% at T1** on bows; Bleeding **3-5% at T1**. One exception:

- **Life Steal** — the value is the percent of damage dealt that is returned.

Bleeding used to be flat damage per tick and always applied (changed 2026-09-18). Scaling the bleed off the triggering hit means it is worth whatever the weapon is worth, with no per-tier damage table to keep in step with weapon scaling — `BleedDamageFraction` is the one dial.

Strengths, durations and radii are first-pass tuning values in `ArmorEnchantConfig` and `CombatEnchantConfig`, deliberately separate from the item data.

## Delivery

An optional fifth `DamageNumberEvent` argument carries effect flags, impact position, direction and scale. The position is captured **before** damage and projected onto the target's bounds toward the attacker, so the client can finish a killing-blow effect after the target is gone. Original damage numbers, the critical effect and existing sounds are untouched; this pass added no dedicated audio.

Geometry is local, anchored, non-colliding, non-touching and non-queryable. One renderer runs only while effects exist. Lifetimes are 0.25-0.85 seconds, with 120-stud distance culling, a 12-effect cap, and same-target/effect throttling at 0.10 seconds. No new uploaded images, meshes, remotes or asset IDs.

## Studio checkpoint (user playtest)

Accept Rojo and start a fresh session. Use the F8 GEAR tab's force-substat controls (the **+** stacks several at chosen values) to build a test weapon, against an armored mob.

1. Check each silhouette individually, including close-range first person.
2. Test rapid hits and simultaneous Critical/Execute/Shatter/Crushing procs.
3. Verify a killing blow still shows the effect after the enemy disappears.
4. Check Shatter refresh, expiry after 3 seconds, and a second attacker benefiting from the same break; verify Crushing does not persist onto the next hit.
5. Verify an invulnerable mob or blocked PvP hit receives no effect and no debuff, and that a respawn starts without Shatter.
6. Cleave: confirm the splash count caps at 3 and each splashed target shows its own effect.
7. Bleeding: confirm 3 RED ticks with their own damage numbers, that a kill by a bleed tick still credits loot and XP, and that several procs stack into overlapping bleeds rather than one refreshing timer (a big hit's bleed should stay big when a small one lands on top).
8. Life Steal: watch the health-bar segment, and confirm a hit that overkills only heals for health actually removed.
9. Slowness: hit a mob with a slow-rolled bow and confirm it visibly moves slower, that the foot ring appears and disappears with it, and that a hopper's hops shorten rather than staying identical. Re-proc mid-slow and confirm the speed does not drop further. Elemental-only weapons should slow occasionally (5%/hit) with no `slowness` substat at all.

For deterministic visual inspection only, a **client** command during your own playtest can call the module directly without touching damage or item data:

```lua
local player = game:GetService("Players").LocalPlayer
local fx = require(player.PlayerScripts:WaitForChild("EnchantHitEffects"))
local cam = workspace.CurrentCamera
fx.Play("Shatter", cam.CFrame.Position + cam.CFrame.LookVector * 6, cam.CFrame.LookVector, 1)
-- Names: Execute, Shatter, Crushing, Piercing, Cleave, Bleeding, Blinding,
-- Slowness, Elemental, Glowing.
```

## Offline checks

```
python tests/run_enchant_hits.py --luau <path-to-luau>
```

They exercise combat, proc delivery, timing and lifecycle doubles against the real source files; they do not establish Roblox visual quality or multiplayer correctness.

**They need a `luau` CLI binary, which is not part of the project toolchain** (`rokit.toml` installs rojo and wally only). Without one the runner exits with `FileNotFoundError` before running anything, so a passing claim means whoever ran it had `luau` installed separately.
