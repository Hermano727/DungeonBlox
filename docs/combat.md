---
title: Combat, Energy & Death
tags: [combat, gameplay, animation]
aliases: [Damage, Death-drop]
---

# Combat, Energy & Death

## Energy / combat loop

- Energy bar regens 8/s. 0 energy = "Low Energy Mode" (3s lockout).
- Walk regens energy; sprint/swing drains it.

## Alignment & PvP

- Neutral/Chaotic alignment = PvP enabled.
- **Death rule (`SSS/DeathProtection`) applies to every OVERWORLD death regardless of alignment today** — no Lawful/Neutral leniency yet. **Dungeon deaths are the exception: they drop nothing** — see [Dungeon deaths](#dungeon-deaths-keep-the-inventory) below.
- Shard Hop cooldown by alignment: Lawful 10s, Neutral 30s, Chaotic 1m. (See [Mob & NPC System](./mob-and-npc-system.md) for spawner/sharding mechanics generally.)

## Combat & animation

| File | Purpose |
|---|---|
| `RS/CombatAnimConfig` | all anim/hitbox constants — edit here only |
| `StarterPlayerScripts/CombatClient` | input->anim->hit->remote; never hardcode values |
| `StarterPack/R6Sword/AnimationScript` | gutted, do not restore (raced with CombatClient) |

Swap swing anim: edit `CombatAnimConfig.SWING_ANIM_ID` only. Must be R15-native or R6 (auto-converts); failed R15 delivery = silent no-op (no console error). `DEBUG=true` logs rig/anim/track per swing.

**Gotchas:**
- Never restore `SwingAnimId` tool attribute (reverts on play-stop, becomes stale).
- `CombatClient.InitAnimator` must try `FindFirstChildOfClass("Animator")` then `WaitForChild` fallback — never `FindFirstChildOfClass` alone (races Roblox's async `Animate` script, creates a phantom 2nd Animator that doesn't drive the character).
- Player chars are R15 (Game Settings->Avatar, not the toolbar Avatar tab). **NPC rigs are R15 as of 2026-08** — the Avatar Type setting governs players only; NPCs are ordinary Models and may use any rig (see [Character & Rigging Pipeline](./character-pipeline.md)). Legacy toolbox NPCs are still R6; existing R6 animations auto-convert onto R15 (approximate, not broken). Bulk-spawned mobs are an open question — R15 is 15 parts/14 Motor6Ds vs 6/5, so measure before converting `SpawnerService` mobs.

## Dungeon deaths keep the inventory

Dying inside a dungeon run drops **no items**. The run is cashed out instead (`DungeonRunService.EndRunFor(player, "died")`) and the player receives whatever loot the run earned. Durability loss, the wallet coin loss and hunger still apply; only the item drop is skipped.

**`DeathLootService` is the only `Humanoid.Died` hook for player deaths.** `DungeonRunService` used to have its own, and the two raced on every death: the run ends — so "in a run?" flips to false — the moment it is cashed out, and whichever hook ran second decided whether the inventory dropped. Nothing guaranteed the order. `DeathLootService` now decides "in a run?" **once**, first, then skips the drop and cashes out. Don't add a second death hook for dungeon logic; route it through here.

### Run payouts never vanish to a full bag

Every run ending — died, cleared, left, failed — pays out through `EndRunFor`, and each drop goes to the first place with room:

| Destination | When | Summary tag |
|---|---|---|
| bag (or an empty equip box) | `ProfileService.HasRoomForItem` says so — same rule as every other grant | none |
| **bank** (Treasure Chest) | bag full; first empty **unlocked** chest slot, via `ProfileService.GrantItemToChest` | `SENT TO BANK` |
| ground at the player's feet | bag **and** bank full; waits for the respawn if they died | `BANK FULL - DROPPED AT YOUR FEET` |

Locked chest rows are never used — an item parked behind a coin unlock would read as held hostage. Run coins split the same way: as many as fit go to the bag as the `Coins` item (`ProfileService.StackableCapacity` works out how many), the rest go straight to the bank balance (`currencies.Coins`, which is what the Bank UI shows), and the summary's coin line says how many were banked.

`GrantItemToChest` mints through the same `buildOwnedItemFromTemplate` as `GrantItem`, so a banked item is identical to one that landed in the bag — same shape, same serial.

## Death-drop protection (`SSS/DeathProtection`)

Decision logic is standalone, not inlined in `DeathLootService` (which only owns the drop loop/coin loss/world-loot spawn). Keep precedence:

1. Profession items (Pickaxe/FishingSpear/`IsProtectedOnDeath`) — always
2. Equipped armor — always
3. "Main weapon" = first weapon found scanning `hotbar[1..9]` (closest-to-1, not strictly slot1) — `GetProtectedWeaponUuid`
4. Single highest-damage Bow anywhere in hotbar — `GetProtectedBowUuid` (can overlap rule 3)
5. Everything else, incl. all bag items, drops

**`ReorderHotbarAfterDeath(profile)`** runs after the drop loop: front-loads survivors into slots 1-4 in priority — melee weapon, bow, pickaxe, fishing spear, then anything else — closing gaps left by dropped items. Pickaxe/spear detection checks `equipSlot` then falls back to `toolPrefabName`/`itemId` substring match (catalog items don't carry an explicit equipSlot field).

This routine reaches into hotbar/bag/equipped clearing helpers shared with the inventory system — see [Inventory & Equipment](./inventory-and-equipment.md) for those (`clearUuidFromBagSlots`, `clearItemUuidFromAllHotbar`, `clearItemUuidFromAllEquipped`, `DeathLootService.stripReferencesToMissing`).

## Dying in the boss fight: spectating (2026-09-29)

There are no revives in the boss room. A party member who dies while the instance's encounter is live stays in the run as a spectator instead of being sent home.

**Where it's wired:**
- `DeathLootService`, the one Humanoid.Died hook, calls `DungeonInstanceService.OnPlayerDied`.
- That wipes the player's Miasma poison stacks and releases any valve they held (`MiasmaEncounterController:OnMemberDied`).
- It then sets the `DungeonSpectating` player attribute (the instanceId) and fires `GameEvents/DungeonSpectate` to the client.

**The parked body:**
- When the dead body despawns, `onCharacterRemoving` keeps a spectator in the instance.
- The next body is parked 600 studs above the realm: anchored, invisible, no collision.
- The encounter's `_livingPlayers` skips anyone with the attribute, so spectators are never hit, poisoned or counted. A party wipe still triggers once everyone else is down.

**The client (`SpectatorClient`):**
- Hides the HUD and follows a living teammate. Right-drag orbits, the wheel zooms, `Keys.SpectatePrev/Next` (arrow keys) switch teammate.
- A top bar has **Leave Dungeon**, which sends `DungeonLeaveRequest`.

**How it ends:** leaving, or the realm being torn down (clear or wipe), clears the attribute and respawns the player at their hearthstone (`endSpectating`).

**Dying cleanses every debuff.** `DeathLootService.cleanse`, the first thing the Died hook runs, clears Miasma poison stacks and releases any valve the player held. Character-bound statuses (enchant bleed, blind, slow) already die with the character model. The cleanse and the spectate hand-off both run before the loot drop and cash-out, each in its own `pcall`, so a failure there can't skip them.

**Respawns start at full health.** `PlayerBootstrap` used to restore the legacy `profile.Combat.HP`, which is mirrored to 0 on death, and that caused the respawn-and-die loop. `ProfileService`'s push keeps a full bar full when MaxHealth rises.

**Unchanged:** the death still ends that player's own run (`EndRunFor("died")`), so they see the DUNGEON FAILED banner before the spectator view appears.
