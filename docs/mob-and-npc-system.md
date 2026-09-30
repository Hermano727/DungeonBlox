---
title: Mob & NPC System
tags: [mobs, npc, gameplay]
aliases: [Spawners, Sharding]
---

# Mob & NPC System

## Spawners & sharding

- Radius spawners with cooldowns.
- Shard Hop cooldown by alignment: Lawful 10s, Neutral 30s, Chaotic 1m (see [Combat, Energy & Death](./combat.md#alignment--pvp) for the alignment system itself).

## Mob system

- `SSS/MobClass` — `mob.Tier/MobID/Stats.Level/DamageTracker`
- `SSS/MobManager` — heartbeat; `ProcessMobDeath` → `LootService.onMobDied`
- `SSS/MobData` (RS) — `FindMobById(id)` → baseStats, tier
- `SSS/SpawnerService` — reads `Workspace/Spawners/MobSpawners` Part attrs (MobId/Count/Radius/RespawnDelay/Active)

## Mob combat: two tiers

Every mob's combat is one of exactly two shapes. Decide which one a new mob needs before writing anything.

**Tier 1 — the regular attack state machine (`SSS/MobClass`).** Chase, and once the target is inside `AttackRange` and the mob is facing it, play the `Attack` clip and land `BaseDamage` at that clip's `AttackHitFrame`. Minecraft rules: in range and in front of it means it swings at you. This is every ordinary mob, and it needs no code — a `MobData` entry plus a `MobAnimConfig` entry. `MobAnimConfig.AttackSpeed` scales playback if an authored swing is too slow (Kane uses `2`); the hit frame and the attack-state lock rescale with it automatically.

**Tier 2 — authored specials on top (`SSS/MobMovesetBehaviour`).** For bosses and named elites with animations you made yourself: combos, slams, anything with its own clip and multiple impact frames. Tier 2 does not replace tier 1, it sits on it. When a special is off cooldown and the target is in its reach and frontal cone, the mob plays that; otherwise it falls through to the ordinary swing, so a boss is never harmless while its special recharges.

Opting in is data only — no class file per mob:

```lua
MobData[1]["Kane"] = {
    CombatClass = "Moveset",     -- optional; a Moveset table alone is enough
    AttackRange = 5,             -- tier 1 reach; BaseDamage is the ordinary swing
    Moveset = {
        {
            Id = "AxeCombo3Hit",                -- key in MobAnimConfig[MobID].Moveset
            Damage = 100,                       -- per connecting impact
            SourceDuration = 4,                 -- authored clip length, seconds
            HitTimes = { 17/24, 39/24, 66/24 }, -- impacts, in authored time
            Cooldown = 5,                       -- gap after the clip, before this special returns
            RangeMultiplier = 1.25,             -- of AttackRange
            HalfAngleDegrees = 70,              -- frontal sweep, half-angle
            Speed = 2,                          -- optional playback rate
        },
    },
}
```

Several entries give a boss several specials; the first eligible one wins, so order the array most situational first. **`Cooldown` must exceed `AttackCooldown`**, or the special re-arms every time the mob may attack and the ordinary swing never happens.

Two timebases live in a special, and mixing them up is the easy bug here. `HitTimes` and `SourceDuration` are in the clip's **authored** time and are compared against `TimePosition`, which always runs `0 -> Length` no matter the playback rate — so they ignore `Speed`. The clip deadline and the attack-state lock are **real** seconds and do divide by it.

**It is a mixin, not a subclass.** `MobClassRegistry.Resolve` picks one base class as before (`CombatClass` → `MovementClass` → `SoundClass` → the `JumpHeight > 0` heuristic → `Default`) and then wraps it. So the moveset layer does not consume the single base-class slot: a future boss can be a `DungeonBoss` *and* have a moveset. Specials still open from the base Attacking state, so `RangeMultiplier` widens where a running special can keep connecting, not where it can start.

**No mob deals contact/proximity damage.** Kane used to: standing near him hurt on a timer, with no animation and no facing check, which read as a huge invisible thorns bubble. That was removed 2026-09-17 in favor of the ordinary swing above. Don't reintroduce per-mob touch damage — give the mob a swing.

**Knockback dealt to players** is `MobData.PlayerKnockbackMultiplier` (default 1), scaling `MobClass`'s baseline hitstun impulse. It covers the ordinary swing and every impact of every special, since both land through `ApplyPlayerHitstun` — a special only differs if its entry sets its own `PlayerKnockbackMultiplier`. Don't confuse it with `KnockbackMultiplier`, which is the reverse: how hard the mob is shoved when the player hits it.

## Non-R15 (skinned mesh) mob models

The project is moving mobs off the R15 rig. A skinned-mesh model (one MeshPart + Bones, e.g. `MiasmaBoss`, built 2026-09-23 from `Workspace.DungeonRealmTemplate["T1 BOSS ROOM"].miasma.Miasma_Skinned_Base_v01`) has no `Humanoid`; it carries an `AnimationController` > `Animator` instead. Both `MobAnimController.attach` and `DungeonBossMobClass` get their Animator through `MobAnimController.GetAnimator(model)`, which accepts either driver, so a new mob only needs the model and a `MobAnimConfig` entry.

Requirements for a template in `ServerStorage/MobModels`:

- **An upright `HumanoidRootPart` as `PrimaryPart`.** `MobClass` moves and turns the model with `PivotTo(CFrame.lookAt(...))` / `CFrame.Angles(0, yaw, 0)` off the PrimaryPart, and an FBX-imported skin carries a baked +90 degree X rotation, so using the skin itself as PrimaryPart lays the mob on its side. The root is an invisible part at the mesh centre, welded to the skin; its LookVector must be the mob's front.
- **Skin `CanCollide = false`.** A MeshPart's default box collision is an invisible wall the size of its bounding box; collision comes from the root.
- Mobs animate their own `MobAnimConfig` clips; `DungeonBossMobClass` plays `AggroStart` once on acquiring a target, then `AggroLoop` (Movement priority, under attack/encounter clips) until the target is lost.

The old R15 boss rig is kept in `MobModels` as `MiasmaBoss_R15_Legacy` for rollback.

## Attack telegraphs

Optional per attack. A mob draws the ground shape it is about to hit during its windup, so the swing can be read and dodged. Opt in with a `Telegraph` style key; a mob without one never draws anything, which is why the ordinary mobs are unaffected.

```lua
MobData[1]["Kane"] = {
    Telegraph = "KaneSlash",   -- the ORDINARY swing
    Moveset = {
        { Id = "AxeCombo3Hit", Telegraph = "KaneCombo", ... },
    },
}
```

Three files: `RS/MobTelegraphConfig` (style + the shared tag/attribute names), `SSS/MobTelegraph` (publishes the tag), `StarterPlayerScripts/MobTelegraphs` (draws it).

**The windup IS the telegraph — there is deliberately no lead-time constant.** The server hands the client the same hit offsets the damage itself uses (`MobClass._attackHitDelay` for tier 1, the `HitTimes`/`timeScale`/`Speed` product for tier 2), so the sweep reaches full radius at the instant damage lands. Retune `AttackSpeed` or `Speed` and the telegraph re-times itself. A hand-authored lead would silently become a lie the first time the clip's pace changed.

The consequence is that **a telegraph can never be longer than the windup**. Kane's ordinary swing commits ~0.40s after it starts, so that is all the warning there is; lengthen a tell by slowing the clip, not by editing the telegraph.

**The shape is the real hitbox, not a decorative ring.** The radius comes straight from `AttackRange + GetHitRadius()` (times the entry's `RangeMultiplier`) and the half-angle straight from `HalfAngleDegrees`, so what is drawn is what the server will actually test. The client then traces that region's **boundary**:

| Attack | Hit test | Outline drawn |
|---|---|---|
| ordinary swing | plain distance check | full circle (the hit area really is a disc) |
| a moveset entry | disc ∩ frontal cone | pie **sector** — apex at the mob, two straight edges out to the arc |

The straight edges are the point. Drawing only the far arc read as a band floating in front of the mob, saying nothing about where the danger begins; the edges are what communicate "step outside these and it misses" — which is the lesson that you can walk behind Kane mid-combo but not mid-swing. Segments are distributed along the boundary by **arc length**, so a sector's edges and its arc each get density proportional to their real length.

**Transport is a CollectionService tag plus attributes, not a remote** — same pattern as `CombatEnchantStatus`'s slow tag. Tags and attributes replicate on their own, so there is no per-player fan-out and the mark cannot outlive the state. `TelegraphStart` is a `Workspace:GetServerTimeNow()` timestamp rather than a duration, so a client that joins mid-windup renders the correct *remaining* time instead of restarting the sweep, with no further traffic.

Two gotchas worth keeping in mind if you extend this:

- `CollectionService:AddTag` on an already-tagged instance does **not** re-fire `GetInstanceAddedSignal`. A second attack starting while the previous mark still lingers would render with stale timing, so the client watches the `TelegraphStart` attribute — the tag alone is not enough. The server writes `Start` last on every `Begin` for exactly this reason.
- It draws procedural neon segments, not a projected decal. A flat projection was the obvious choice and was rejected: this game is played on rolling terrain, where a large projection visibly clips through hillsides.
- **The shape is a low raised band, not a floor marking, and that is a terrain fix.** The segments sit on one flat plane at the mob's feet and do not follow ground contour, so `Height`/`Lift` give them ~1 stud of vertical presence to stand proud of rising ground. The first version was 0.08 studs tall sitting exactly on the foot plane and was effectively invisible on T1's hills -- drawing correctly, just underneath them. If steeper terrain ever buries it again, raycast each segment down individually rather than growing the band further.
- `MobTelegraphConfig.DEBUG` turns every telegraph into an opaque 6-stud wall at chest height and makes both the server and the client print when they fire. That pair of prints is the bisect for "I see nothing": server only means replication or the renderer, neither means the attack never reached `MobTelegraph.Begin`, both means it is drawing somewhere you are not looking.

## Ground probes: "ground" is never a creature

`MobGroundUtils` raycasts **downward from above** a mob to find its footing, so anything standing or flying over it sits in the ray's path. It excludes the mob itself **and every player character** for that reason.

Without the character exclusion, a player hovering above a mob was read as ground: the mob snapped up to the player's feet and could be shoved under the map, where `FindGroundY`'s "no hit, keep the current height" fallback means it never climbs back — it falls until Roblox's `FallenPartsDestroyHeight` destroys the model, which reads in game as the mob despawning for no reason (2026-09-18, flying above Kane).

`MobClass:RescueIfFallen` is the backstop: a mob more than `FALL_RESCUE_DEPTH` (80 studs) below its spawn is teleported back to a grounded spawn position with its velocity cleared, and warns. That covers the other ways into the void — thin geometry, a bad spawn point, knockback off a ledge.

**Still open:** mobs don't exclude *each other* from these probes, so one standing on another's head can read its friend as ground. Less visible than the player case, and not yet reported.

## Named elites: soundtrack and idle despawn

A named elite (`MobData` `IsNamedElite = true`) plays its own looped track while it is alive. Ids live in `RS/Assets/Sounds/NamedEliteSoundtracks`, keyed by MobID, one row per elite — a row may list several ids and one is rolled per spawn and held for that whole fight.

**It outranks zone music.** `MobManager` picks the id when the elite spawns and pushes it through `ZoneService.SetMusicOverride(player, musicId)`, a per-player override that sits above the zone's own `musicId`. Clearing the override drops the player straight back to whatever their zone plays; nothing else needs to know a boss track was ever on.

**Who hears it:** whoever the elite's boss bar is bound to (`PlayerActiveEliteMob`), which today is the player whose kill spawned it. Another player joining the fight gets neither the bar nor the track — that's pre-existing boss-bar behavior, not a music decision.

**Dy**A named elite despawns after 5 minutes out of combat** (`NAMED_ELITE_IDLE_DESPAWN` in `MobManager`, checked every heartbeat, removed via `MobManager.DespawnNamedElite`). Any hit it takes (`MobClass.TakeDamage`) or lands (`DamageService.ApplyToPlayer`) resets `mob._lastCombatAt`; the clock starts at spawn. No loot, no XP, no kill credit, no death effect: it is removed, not killed, the bar and music end with it, and the one-elite slot frees up. Dying to it no longer despawns it (changed 2026-09-30): the bar is shared by every player now, so one death must not end the fight for the rest. NPC system

Two parallel, non-unified paths — don't conflate:

1. **Bootstrap scripts** (primary): one `SSS/<Type>Bootstrap` per type. Scans `Workspace:GetDescendants()` for **every** matching Model (not just first — old `FindFirstChild(name,true)` bug silently broke all-but-one duplicate town copy), wires `NpcId`/ProximityPrompt/CollectionService tag `"NPC"`/Head.gui dialog.
2. **SpawnerService + ServerStorage/NPCModels clone (dev-tool, F8 placer):** independent of path 1, known 2nd source of duplicate NPCs (not yet unified). This is the closest thing in the project to a "dev menu" item/NPC spawner — an F8-triggered placer tool, not a full dev menu.

NpcId convention: tutorial copy = `<type>_tutorial`, else first match = canonical (`blacksmith_01`), dupes get numeric suffix.

**Quest state is per-player (`profile.flags.<questName>`), not per-NPC-instance** — handlers check `npcType` only, not exact `npcId`, so any duplicate NPC of that type serves the same quest.

- `SSS/NPCService` — `NPCRequest` RF, `npcIndex` (by NpcId), `HANDLERS` dispatch, validates via `NPCRegistry.AllowsAction`.
- `RS/NPCRegistry` — pure data: `NpcType -> {Interactions, ShopCatalog, TradeRates, ...}`. Catalog data itself lives in `RS/ShopCatalogConfig` (one file, all NPC prices) — NPCRegistry just assigns `ShopCatalog = ShopCatalogConfig.<Type>.ShopCatalog`.
- `RS/DialogModule` — indexes `UIStroke` directly (not FindFirstChild) on name/arrow/dialog labels; calls `ensureNpcBillboardStrokes` first to backfill on old pre-UIStroke `Head.gui`s. Don't remove.
- Innkeeper is NOT a merchant-shop type (`SHOP_NPC_TYPES`) — routes through `HearthstoneClient.openInnkeeperShop()` like Blacksmith routes to `BlacksmithClient`, both via `MerchantShopClient`'s ProximityPromptService hook. Hearthstone remotes: `HearthstoneSync/Purchase/Teleport/Swap` + admin Add/Delete.

For rig type (R15 vs R6) and the Blender/Tripo generation pipeline that produces these models, see [Character & Rigging Pipeline](./character-pipeline.md).

## Crowding (2026-09-29: seat rings removed)

Mobs walk straight at their target and stop at melee reach. There are no more "seats" in rings around the player. A pack clumps around you like Minecraft mobs instead of standing in a ring with gaps.

**Soft spacing between mobs only.** They never push the player (not yet: first see how it feels).
- **Footprint:** `MobClass:CrowdRadius()` takes a share (`CROWD_BODY_FRACTION` 0.85) of the model's narrower half-extent, so antlers, tails and weapons don't hold neighbours away. The floor is `CROWD_MIN_RADIUS` 1.2.
  - The old rule was a flat 3-stud minimum radius, which held two 2.5-stud slimes 6 studs apart.
  - `SeparationRadius` still exists, but only for boss movement bounds.
- **Overlap:** two mobs may overlap `CROWD_OVERLAP` (20%) of their combined radii. Only `CROWD_STIFFNESS` (35%) of any further overlap is resolved per tick, so they jostle rather than snap.
- **Mass:** `CrowdMass` is the footprint area, times `CROWD_PRIORITY_MASS` (4) for bosses and named elites, so trash yields to them.

**Performance:** `MobManager` rebuilds a spatial grid once per tick (`MobClass.BuildCrowdGrid`, `CROWD_CELL` 8 studs). Each mob checks only the 3x3 cells around it plus a short list of oversized mobs, instead of every mob on the server.

All tuning is the `CROWD_*` constants at the top of `SSS/MobClass`.

## Threat: who a mob fights (2026-09-29)

Every mob (`SSS/MobClass`) keeps a threat score per player, and its target is the top of that list. It is no longer simply "whoever hit it last".

- **Damage adds threat.** `TakeDamage` adds the post-armor damage via `AddThreat`, so a big hit counts more than a poke.
- **Threat fades,** halving every `THREAT_HALF_LIFE` (6 s; `THREAT_HALF_LIFE_PRIORITY` 4 s for elites and bosses). Recent damage dominates, and entries below `THREAT_FORGET` are dropped.
- **Switching:** another player takes the mob over once their threat beats the current target's by `THREAT_SWITCH_MARGIN` (1.2x; 1.1x for elites and bosses). There's **no minimum hold time**, by design.
- **Fallback:** `RefreshThreatTarget` runs every tick. If the target dies, leaves, spectates or gets out of reach (`IsValidThreatTarget`), the mob moves to the next highest valid threat. Only when nobody valid has threat does it go idle, where plain proximity aggro (`TryAcquireTarget`) takes over again.
- **Leash:** giving up a chase past `ReturnDistance` clears the threat list (`ClearThreat`). Otherwise the next tick would pick the same player straight back up.
- **Dead players:** their entries are dropped when seen dead, so a respawned player starts clean.
- **Priority:** `IsPriorityMob` (bosses, named elites, `IsElite`) gives the faster fade and lower switch margin, so elites and bosses react to whoever is hurting them. The same flag gives them right of way in crowding (`CROWD_PRIORITY_MASS`).

Bosses use the same list for their encounter moves: Miasma's `_pickTarget` asks `boss:TopThreat(allowed)`.
