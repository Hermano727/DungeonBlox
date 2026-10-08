---
title: Tutorial
tags: [tutorial, onboarding, server]
---

# Tutorial

New players play a short, guided tutorial in their **own private copy** of a tutorial area, then hearth to Oakhaven. The current steps are a **placeholder flow** that exercises every part of the machinery; the real flow gets drafted next.

## Who gets it

- `profile.flags.tutorial = { done, step }`, server-owned. New profiles start `done = false`; saves from before it existed were marked done on load (`ProfileTypes.Reconcile`). Same for `flags.hearthstoneUnlocked` (new players get it at a totem).
- Only `SSS/TutorialService` advances it. The step id is saved as it goes, so a rejoin resumes at that step (in a fresh copy, from the step's checkpoint).

## Pieces

| Piece | What it does |
|---|---|
| `SSS/TutorialService` (started by `TutorialBootstrap`) | Joins a new player into their copy, runs the steps, finishes (flag done, rigs cleared, copy destroyed). Dev: `Reset`, `Skip`, `JumpTo` |
| `SSS/TutorialSteps` | The steps, in order (data + small functions). The flow lives here |
| `SSS/TutorialInstanceService` | Clones `Workspace.TutorialRealmTemplate` per player, parks it at `+Z 100000` (one slot each), registers its zones, finds markers, spawns one-shot mobs, cleans up |
| `ZoneService.AddTransientZone` | Runtime-only zones for a copy (safe zone, Region Discovered, elite arena): never saved, never broadcast, never on the minimap |
| `SSS/ScriptedRigs` | Every rigged outcome (crit, drop, orb result, fish, chest, price, elite drop), tutorial-only, server-only. See CLAUDE.md "Tutorial flag + scripted outcomes" |
| `src/client/TutorialClient` | Draws what it's told: objective line, key hints, world arrow (+ edge pointer), a gold glow on the model to use, spotlight-pause, the "wake" moment |
| `RespawnCheckpoint` | Dying mid-tutorial respawns at the current step's checkpoint (`RespawnAt`) |
| Loading screen | Waits while `SpawnPending` is set, so the move into the copy happens behind it |

## The template (build in Studio)

`Workspace.TutorialRealmTemplate`, a Model parked at `(0, 50, -100000)` (a placeholder was generated 2026-10-04: ground, a stone ring camp, a totem pillar):
- **PrimaryPart**, and a part named **`SpawnPoint`** (where a new player wakes up).
- **`Markers`** folder: invisible named parts the steps use (`FirstMob`, `Camp`, `Totem` today). Add any; refer to them by name.
- **`Zones`** folder (optional): parts with `ZoneName`, `Alignment`, `Radius`, `IsEliteZone`, `EliteMobId`, `MusicId` attributes, each a transient zone in every copy.
- Anything with the attribute **`HearthTotem = true`** is an attunement totem.
- Key-chests: a `Dropper` model (with `ChestRarity`) inside the template works in every copy.

## Writing a step

```lua
{
	id = "first_fight",                      -- saved as progress
	objective = "Defeat the slime",          -- one short line, no em-dashes
	arrow = "FirstMob",                      -- marker (or function(ctx) -> part / Vector3)
	highlight = "The Merchant",              -- model in the copy to glow gold (or function(ctx) -> Instance)
	hints = { { key = "MouseLeft", text = "Attack" } },
	checkpoint = "FirstMob",                 -- respawn / resume spot during this step
	cutscene = "wake",                       -- a named client moment on entry
	spotlight = { target = "EnergyBarGui/BarBackground", caption = "..." }, -- with waitForAck
	waitForAck = true,                       -- done() may use ctx.acked()
	enter = function(ctx)                    -- set up; rigs only via ctx.rigs
		ctx.rigs.Queue(ctx.player, "crit", true)
		ctx.state.mob = ctx.spawnMob("FirstMob", "PlainsSlime", 1)
	end,
	done = function(ctx)                     -- checked 4x a second
		return not ctx.state.mob:IsAlive()
	end,
}
```

`ctx`: `player`, `profile()`, `marker(name)`, `spawnMob(marker, mobId, level)`, `rigs`, `instances`, `elapsed()`, `acked()`, `state`.

## Security

- The client only draws and says two things back (`TutorialAck`): "sync" (resend the state) and "ack" with the step's one-time token, honoured only by a step that waits on it. It can't complete a step or reach any reward.
- Rigs, companions, tutorial pity, respawn overrides: all server-only and gated on the server's own profile flag.

## Dev (F8 Profile tab, TUTORIAL)

- **Wipe + restart** (click twice): wipes the WHOLE profile (`ProfileService.WipeProfile`: items, coins, skills, map, flags) and starts the tutorial as a brand-new player in a fresh copy. Spawn gear back in with the F8 tools.
- **Skip tutorial:** marks it done and sends you to your hearthstone town.
- **Jump:** enter a step id (from `TutorialSteps`) to start there.

## The flow (first pass, 2026-10-04)

Left to right through `TutorialRealmTemplate`: wake camp, the road, the main camp (`T1_TutorialCamp`), the dash gap, the forest path, the repair camp (`T1_TutorialRepairCamp`), the arena, the totem.

1. **wake**: eyes open beside a fire, at half HP. **drink**: drink a potion (Z; the potion slot is lit).
2. **spam_attack**: a slime that can't die yet (HP floor) and barely hurts; click until you pant. **panting**: spotlight on the energy bar (game paused). **finish_slime**: it drops a 5% crit Training Sword on the ground (rigged, 2.5 s before it can be picked up). **pickup_sword** (the path leads to the drop). **equip_sword** (the sword's bag slot is lit, or the Inventory button while the menu's closed).
3. **crit_fight**: the first hit crits (rigged). **crit_spotlight**. **crit_finish**.
4. **to_camp** (Region Discovered). **salvage** the old sword at the merchant (4 scrap). **buy_scroll** (a one-time 4-scrap price; the shop shows it through the `RigPrice_<itemId>` player attribute that `ScriptedRigs` mirrors, display only). **enchant** at the altar. **enchant_spotlight**.
5. **mine** the coal ore. **buy_orb** (1 coal). **orb_fail**: the first Alteration loses the crit (rigged). **orb_retry**: a free second orb gives crit 5% + piercing 1 (rigged). **orb_spotlight** (merchants are in every town).
6. **hunger** (set to 4/5, spotlight). **fish_one** (the pond holds exactly one plain fish), **fish_swift** (then one swift fish). **cook** at the campfire. **eat** (V). **eat_swift** (hold V to switch, tap to eat). **buff_spotlight** (the buff list).
7. **dash_gap**: jump, dash mid-air across a 9-stud gap.
8. **forest**: five slimes; keys from kills near the chest fly to it; the chest gives a potion, 25 coins and a broken "Rusted Training Sword" (rigged). **chest**. **journal**: open the Journal and click Loot Score (focus walks you there). **journal_spotlight** (dry streaks).
9. **ambush**: your sword is worn to 20%, a brute kills you, you wake in the repair camp (bag kept: tutorial deaths keep inventory). **broken_spotlight** (30% durability per death, 3 enchant levels on a break). **repair** (coins for exactly the repair). **reequip**.
10. **arena**: pity set to 99/100, kill the slime in the pit, the Slime King (`TutorialSlimeKing`, a private named elite) appears. **elite**. **fragment** (its scripted key fragment). **fragment_spotlight**.
11. **totem**: attune (unlocks the Hearthstone). **hearth**: the Journal's Hearthstone Return button is lit; leaving finishes the tutorial.

The party companion is left out of this pass (`SSS/TutorialCompanion` + `PartyService.AddCompanion` exist if it comes back).

## Guidance

- **The path:** glowing blue chevrons on the ground along a walkable route (`PathfindingService`, recomputed every 0.8 s), pulsing toward the target, a diamond over it, a pointer on the screen's edge when it's behind you.
- **Objective plate:** "OBJECTIVE" + one line, pops in with a chime; key hints in pulsing plates beneath.
- **Focus:** while a step wants a UI click, the screen greys slightly EXCEPT that element (clicks still go through). Targets are found by the `TutorialTarget` attribute (`nav_<tab>`, `shortcut_<tab>`, `journal_<page>`, `hearth_return`, `hud_energy/hp/hunger/potion/fish/dash/buffs`) or `item:<uuid>` (bag slots carry `ItemUuid`). A list means the first one on screen.
- **Spotlight:** focus + a caption + "Click to continue"; the player's controls and the copy's mobs pause (`MobClass` `TutorialPaused`).

## Props in the template (`TutorialProps`)

The Blacksmith and the Merchant are both copies of Oakhaven's R15 `T1_Blacksmith_R15` (2026-10-04), the merchant one renamed `The Merchant` and standing behind the crate counter. The names are what `MerchantBootstrap` / `BlacksmithBootstrap` wire. The totem is the waystone (`HearthTotem`, the arch from `assets/builds/SafeZones/waystone model`, its spinning vortex drawn by `WaystoneVortexClient` on the `WaystoneVortex`-tagged part). The altar is Oakhaven's, copied. Also: a coal ore, the pond (`FishingPool` part), the dash ledges, a `Dropper` chest, the arena stones. The camp campfire carries the `CookingFire` tag. Zones: the camp and repair camp (Lawful), the arena (`The Slime Pit`, named-elite zone for `TutorialSlimeKing`).
