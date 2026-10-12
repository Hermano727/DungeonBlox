# Dungeon Clear Sequence

What happens in the boss room when a dungeon is cleared (Miasma today): a shared, in-world, server-timed show for the whole party. It runs from the "dungeon complete" moment, through the loot reveal, to the Mythic rolls, and the summary panel opens after it. Players keep full control the whole time: there is no camera takeover and no frozen movement.

Art and sound still owed: [Dungeon Clear Sequence: asset requests](./dungeon-clear-asset-requests.md).

## The rolls are already decided (the show is theatre)

- **Score:** during a run, kills only bank score (`DungeonScoreService.AddKill`).
- **Loot rolls:** at the clear, `DungeonRunService.EndRunFor` calls `DungeonScoreService.EndRun`. That runs `LootPityService.ResolveScore` once, the same per-point roll the overworld uses, and the drops are **granted immediately**.
- **Mythics:** each boss's Mythic is rolled and granted at its kill (`LootService.tryDropMythic`).
- **Result:** the client receives every result up front and acts out "rolling" them, so a disconnect mid-show loses nothing.
- **Honesty rule:** the Reliquary Ring's glow now cycles through random rarities while a relic breathes (a pure teaser, user's call 2026-10-10), but always settles on the real rarity for the reveal. The Mythic fake-out follows the same rule: it may show the wrong result for `FakeOut` seconds, then always settles on the real one (which was granted before the show started).

## Timeline

`SSS/DungeonClearSequence.Play(instance)` builds ONE timeline of offsets from `startsAt`, which is the server clock at the kill plus `DEATH_LEAD` (Miasma's 3.6 s defeat animation and a beat). It fires the timeline once on `GameEvents/DungeonClearSequence` to every instance member, spectators included. Each client evaluates `t = GetServerTimeNow() - startsAt` per frame, so everyone sees the same moment, and a late payload jumps straight to the right frame. Every number is in `RS/DungeonClearConfig`.

| Stage | Client module | What happens |
|---|---|---|
| 0 Echo (4 s) | `BossEcho`, `Echo` | Right after the main boss's death animation: every light dies, the boss's spectral echo (a dark body in a column of smoke, two burning red eyes) rises over the arena and roars, then a shockwave of light tears it apart and the lights come back. The Benediction answers that light. (Minibosses use the same `Echo` inside their own judgement.) |
| 1 Benediction (~7.6 s with the beat) | `Benediction` | 1 s of silence with the arena lights dimmed (`Ambience`). A gold light shaft punches down through the ceiling opening and a radiant core sinks into it. A faceless hooded angel (the Tripo figure, `CLEAR_ANGEL`) sinks into it facing YOU (the show is drawn per client, so each player sees it face their own character; the entrance side if they have none); two real wings (the Tripo wing model, mirrored for the pair) swing open from its shoulder blades, unfurling as they go; during the hold it turns two full circles over 3 s (ending facing the party again), then rises back up the shaft as the wings fold, fading only near the top. No text. It holds, folds and fades, then a quiet beat. It is deliberately separate from the loot. |
| 2 Pyres (~6 s) | `Pyres` | An iron brazier per member rises on a circle (r = 30) around the centre, at fixed slots, carrying the owner's name. The score pours in as embers (capped at 60 visible; the counter reaches the real score). The fire roars, and the auto-scrapped low rolls burn off as ash with "+N Scrap". A brazier with nothing kept gutters to coals. A member who died in the fight gets a cold, grey brazier. |
| 3 Reliquary Ring (2.05 s per relic) | `ReliquaryRing` | Kept drops lift out of the fires as identical shrouded relics, spiral into one ring overhead (interleaved by owner) and the ring spins up. Reveals go in a **random order** (a shuffle: any rarity can come first). **Every relic takes the same fixed time, whatever the drop count** (`Ring.Breath` 1.5 s + `Burn` 0.3 + `Settle` 0.25; the stage grows with the number of relics, nothing compresses): the relic trembles while its glow cycles through RANDOM rarity colours (a new one every `CycleStep`, ticking on each change, never the same twice in a row, the last `CycleSettle` on the real colour), the shroud burns, then a 0.25 s wave pulses out of the ball (`Wave`: two or three swirled shock rings laid flat, a camera-facing ring so it reads from below, radial streaks and a shimmer of motes, white-hot fading into the real rarity's colour; bigger and more rings for higher rarities) and the next relic starts. The item pops in and a plaque names owner and item. From Epic the ring slows; from Legendary it stops and the others dim. Then every item streaks into its owner's chest, or their brazier if they're gone. Skipped if nobody kept anything. |
| 4 Mythic Judgement | `Judgement` | One per logged boss: minibosses in kill order, the main boss last. A dark echo rises where the boss fell and shatters, and a Mythic relic forms. The relic itself plays roulette: it hops round every brazier (eligible or not, so a solo test still bounces: `Judgement.Hops` 8, 12 for the main boss), each hop slower than the last (`HopStart`, `HopGrowth`), ticking as it lands, then lands once on each eligible member. It leaves an ember trail and settles with a few bounces. **Fake-out:** the LAST landing may deceive (`FakeOutChance`, always for the main boss): a winner's relic goes dark and sags, then roars back at `revealAt`; a loser's relic blazes as if it had won, then gutters. The Mythic broadcast waits for `revealAt`. A winner gets a Mythic-orange flare as it touches down, a pillar of fire, their item spinning over the brazier and an orange plaque; a loser gets a grey puff and a gutter. Nobody winning crumbles the relic with a bell toll. **Main boss:** its echo already played at the start of the show (stage 0), so its judgement is the relic sinking slowly from above, trailing fire, then the roulette. |
| outro (2.2 s) | all | The braziers sink and the room's light returns. The summary panel opens `SUMMARY_AFTER` after the end (`DungeonRunSummary.showAt`). |

The realm is torn down `LEAVE_WINDOW` (20 s) after the show ends. The exit countdown's **Leave Now** works throughout, since everything is already granted.

## Party restore on the kill

The moment Miasma is registered dead (`DungeonInstanceService`, the Miasma `onFinished("cleared")`, before the clear show), `restorePartyAfterClear` runs a full `StatusCleanse.All(plr, "DungeonCleared")` (the F8 cleanse) and refills HP for every member still INSIDE the run: connected, in `instance.members`, flagged `InDungeon` (cleared by `releaseMember`), mapped to this instance and alive and not spectating. Someone who died in the fight and left, or anyone who has already walked out, gets nothing, so nobody can bank a heal and carry it into PvP.

## Auto-scrap

At grant time, `EndRunFor` turns any drop at or below `DungeonClearConfig.AUTO_SCRAP_MAX_RARITY[tier]` into tier scrap. It is priced by `ProfileService.SalvageYield`, the Merchant's own formula (`4 * rarity index`: Common 4, Uncommon 8, ...), and granted as one stack.

| Tier | Scrapped | Revealed in the ring |
|---|---|---|
| T1, T2 | Common, Uncommon | Rare and up |
| T3, T4 | Common | Uncommon and up |
| T5 | nothing | everything |

The summary panel shows one "+N T1Scrap (k low rolls scrapped)" row.

## Mythics

- **Who rolls:** `LootService.tryDropMythic` → `DungeonBossLootService.OnBossKilled` rolls for the instance's **living, non-spectating members only**. It used to roll for every player on the server.
- **Logging:** the results go to `DungeonClearSequence.RecordJudgement(instance, ...)`, which feeds `instance.mythicLog`. A miniboss is any boss with `MobData.IsMiniBoss = true`; it gets the smaller judgement, before the main boss.
- **Odds:** Miasma is `MythicItemDefs.DropTable.MiasmaBoss.Chance = 0.10`.
- **Dev override:** F8 → Mythic → "Boss Mythic roll" cycles Normal / Force win / Force loss. It is server-held (`DevMythicForce` remote, the `DevMythicForce` player attribute) and honoured for DevRoster players only.
- **Server-wide broadcast (`SSS/MythicBroadcast.Announce`):** every Mythic is announced to the whole server. `client/MythicBroadcastClient` draws a top-centre line (a Mythic-orange rule opening out of a diamond, "X has claimed", the item name, "from <boss>"), plays a sting and posts a coloured chat system line. Announcements queue.
  - **Dungeon Mythics** are delayed to the moment that player's beam flares, so the server hears it in step with the party seeing it.
  - **Named-elite Mythics** are announced when they drop.
  - **Future:** numbered copies ("#2"). This needs a global per-Mythic counter (DataStore `UpdateAsync` at grant time, stored on the item). `Announce` already receives the item.

## Files

| Side | File | Role |
|---|---|---|
| shared | `DungeonClearConfig` | timings, auto-scrap table, `RarityRank`, the dev force attribute |
| server | `DungeonClearSequence` | the Judgement log, the timeline, `Play` (cash-out with summaries held, fire the show, schedule broadcasts and summaries) |
| server | `MythicBroadcast` | the one entry point for Mythic announcements |
| server | `DungeonInstanceService` | Miasma `onFinished("cleared")` → `Play`, the exit timing; `GetInstanceForPlayer`, `GetLiveMembers`; loads the sequence at boot so its remotes exist early |
| server | `DungeonRunService.EndRunFor(player, reason, { deferSummary })` | auto-scrap, a richer `granted` list (`itemId`, `tags`, `equipSlot`, `type`, `tier`), returns `(granted, payload)`; `SendSummary(player, payload, showAt)` |
| server | `WorldLootService` | mirrors `ServerStorage.LootDropVisuals` → `ReplicatedStorage.LootDisplayPrefabs` (clients can't read ServerStorage) |
| shared | `Assets/Meshes/Loot/LootDropVisuals.ResolveForTemplate` | template → display prefab (was private to WorldLootService) |
| shared | `Assets/Meshes/Vfx/VfxMeshes` | `CLEAR_BRAZIER`, `CLEAR_RELIC`: the Tripo models, cleaned by `assets/models/dungeons/build_clear_props.py`. `CLEAR_ANGEL`: the hooded figure, built by `assets/models/dungeons/build_angel_figure.py`. `CLEAR_WINGS`: the wing pair (`WingL` + `WingR`), built by `assets/models/dungeons/build_angel_wings.py`, which prints the pivot numbers `Benediction` hard-codes (a MeshPart is placed by its bounding-box centre, so a wing is positioned from its shoulder through that offset; rerun it and update the numbers if the wing is ever re-exported). Textured parts keep their texture; the client only styles the untextured `Coals` / `EmberGlow` |
| shared | `Assets/Images/ClearSequenceArt` | bespoke textures (feather, light shaft, ember, fire 4x4, sparkle, burning-rag 4x4; live 2026-10-10), each with a fallback in `Fx`. A 4x4 sheet gets its flipbook settings automatically (`Fx` FLIPBOOKS) |
| client | `DungeonClearSequence/` (`init.client`, `Fx`, `Ambience`, `BossEcho`, `Echo`, `Benediction`, `Pyres`, `ReliquaryRing`, `Judgement`) | the show |
| client | `MythicBroadcastClient` | the announcement |
| client | `DungeonRunHud` | holds the cleared summary until `showAt`, shows the scrap row |

## Rules

- **Stages draw purely from `t`.** No tweens; one-shots go through `show.once:at(key, when, t, fn)`, which skips moments a late client is already past.
- **Hidden pieces park at `Fx.HIDDEN`** (far above the map), never below it, because of `FallenPartsDestroyHeight`.
- **A new dungeon** gets the show by calling `DungeonClearSequence.Play(instance)` from its clear and logging its bosses' Mythics. The arena frame comes from `arenaOrigin` (Miasma's resolver, else the realm `SpawnPoint`).
- **Run Summary (For The King style lineup):** not built yet. It will replace `DungeonRunHud`'s panel at `showAt` and needs per-run counters (damage dealt and taken, healing, crits, potions, deaths) that don't exist yet.
