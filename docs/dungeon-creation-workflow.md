---
title: Dungeon Creation Workflow
tags: [dungeons, blender, environments, roblox, pipeline]
aliases: [Dungeon Pipeline, Environment Pipeline]
---

# Dungeon Creation Workflow

This is the source-of-truth workflow for building DungeonBlox dungeon rooms and
encounters. It keeps gameplay geometry testable before detail work, preserves a
clean Blender-to-Roblox pipeline, and prevents encounter scripts from depending
on fragile mesh names or world-space coordinates.

## Checkpoint sequence

Build and review one checkpoint at a time. Do not texture a room whose gameplay
layout has not passed a Studio graybox test.

1. **Encounter brief:** define player count, intended duration, phase flow,
   combat footprint, interaction zones, traversal, sightlines, and required
   state changes.
2. **Blender graybox:** build the floor, boundaries, elevation, entrances,
   channels, platforms, and major landmarks at Roblox scale.
3. **Encounter structure:** add gates, mechanisms, hazards, spawn locations,
   protected interaction areas, and stateful geometry as separate objects.
4. **Dressing and collision:** add modular detail without obstructing combat,
   then create dedicated low-complexity collision proxies.
5. **Graybox export:** import the untextured modular room into Studio and test
   scale, navigation, collision, camera clearance, and enemy movement.
6. **Gameplay implementation:** build the encounter against tagged anchors and
   configuration, then playtest its complete loop.
7. **Animation and VFX:** author only the clips and effects required by proven
   mechanics. Align damage timing with authored animation events.
8. **Materials and lighting:** apply PBR materials after the gameplay geometry
   is accepted. Build water, poison, particles, fog, and lighting in Studio.
9. **Optimization and acceptance:** validate party-size extremes, streaming,
   cleanup, collision, visual clarity, and frame cost.

At every checkpoint, record the artifact version, what changed, and the exact
Studio or Blender checks the user must perform.

## 1. Encounter brief

Before modeling, write down:

- Intended party-size range and which size is the balance baseline.
- First-clear duration target.
- Combat phases and transition triggers.
- Where players fight, solve tasks, cleanse, enter, and exit.
- Boss dimensions, movement limits, reach, and camera requirements.
- Persistent and temporary hazards.
- Interactive objects and every visual state they require.
- Failure, reset, victory, death, and disconnect behavior.
- Which mechanics need server authority and which are presentation only.

Convert these requirements into physical zones. A boss room should have a clear
combat center, readable perimeter landmarks, unobstructed routes between tasks,
and enough space for the maximum supported party to spread without leaving the
camera-readable arena.

## 2. Scale and Blender grayboxing

### Scale rules

- Work against an imported player-scale reference and the actual boss-scale
  reference whenever possible.
- Treat Blender dimensions as planned Roblox studs and verify the conversion on
  the first graybox export. Do not compensate for a wrong import scale by
  resizing each mesh independently in Studio.
- Use measured widths for doors, bridges, stairs, channels, interaction pads,
  and boss routes.
- Apply transforms before the final export and keep object origins intentional.

### Layout rules

- Build traversable surfaces and encounter boundaries before decorative shells.
- Preserve clean sightlines from the combat center to every important task.
- Keep narrow routes wide enough for the boss and multiple players unless the
  encounter deliberately uses a choke point.
- Avoid small height changes that create accidental steps, snagging, or camera
  clipping.
- Test the room from first-person eye height, not only from Blender's overview.

### Blender collections

Use separate collections for:

- `ArenaShell`: permanent visible architecture.
- `GameplayModules`: gates, mechanisms, altars, bridges, and moving pieces.
- `StateVariants`: clean, corrupted, opened, broken, or flooded replacements.
- `Collision`: simple collision meshes that are never used as final visuals.
- `Anchors`: empties or marker meshes for spawns, effects, triggers, and zones.
- `Dressing`: debris, bones, chains, grates, and repeated decoration.
- `References`: player and enemy scale references excluded from export.

Do not merge a stateful object into the arena shell. A gate, clog, channel flow,
breakable object, or animated mechanism must remain independently addressable.

## 3. Encounter structure and anchors

Model the physical explanation for every mechanic. A puzzle should look like a
machine in the room, a hazard should have a source, and a safe area should be
recognizable before its first use.

Create anchors for:

- Encounter entrance threshold and seal.
- Player relocation and recovery positions.
- Boss spawn, intro, landing, center, and movement bounds.
- Add spawns and landing positions.
- Projectile, drip, pool, sack, and area-hazard emitters.
- Interactive controls, prompts, and protected radii.
- Water or poison flow endpoints.
- Cinematic camera subjects and effect origins.

Blender anchor names are authoring aids. Export their realm-local coordinates to
JSON alongside the FBXs. For a Rojo-owned encounter, commit the required subset
as a shared anchor-data module and transform it through each cloned realm's
origin. A deliberately Studio-owned room may instead use tagged instances or a
documented encounter model schema. Do not create untracked anchor Instances
inside a Rojo-managed tree: the next sync will remove them. Gameplay must never
use a global `Workspace` path or world-space coordinates copied from one room.

## 4. Dressing and collision

### Dressing priorities

Use detail to improve navigation and story:

- Give each task station a distinct silhouette or landmark.
- Use floor borders, channels, arches, light, color, and debris direction to
  point toward important routes.
- Concentrate high-frequency detail near walls and landmarks. Keep active
  combat surfaces visually quieter.
- Match the setting. DungeonBlox sewer construction uses medieval masonry,
  brick, iron grates, chains, braces, hand-operated valves, organic growth, and
  accumulated bones rather than modern industrial fixtures.

### Collision rules

- Prefer simple invisible collision proxies over detailed render-mesh collision.
- Keep floors continuous and remove tiny ledges that catch the Humanoid.
- Use broad blockers for walls and large props.
- Do not give chains, small debris, bones, cosmetic growth, or VFX geometry
  player collision.
- Keep interaction volumes clear even when their visible surroundings are
  damaged or overgrown.
- Validate gentle slopes, stairs, platform seams, moving parts, and arena edges
  with the production character controller.

## 5. Materials and UV strategy

### Tiled materials

Use reusable tiled PBR sets for broad surfaces:

- Wet stone and brick.
- Corroded iron.
- Bone.
- Slime growth.
- Poison-stained masonry.

Use consistent texel density across modules. Repeated floor and wall modules
should share material scale so seams do not reveal where pieces meet.

### Unique textures

Reserve unique UV space, atlases, decals, or trim details for:

- Hero mechanisms and puzzle markings.
- Specific cracks or structural damage.
- Poison leaks and discoloration with gameplay meaning.
- Banners, inscriptions, and unique landmarks.

Roblox `SurfaceAppearance` consumes Color, Normal, Roughness, and Metalness maps.
Do not rely on Blender displacement or height rendering to survive import. Use
geometry for silhouette-changing damage and normal maps for shallow relief.

Water, poison, animated flow, fog, dripping, lighting, and particles should be
authored as Studio materials and runtime effects unless a static mesh is needed
to define their boundary.

## 6. Export and Studio assembly

### FBX preparation

- Apply location, rotation, and scale where the asset pipeline permits it.
- Give modular pieces useful pivots, especially gates, wheels, doors, and props.
- Remove unused material slots and hidden construction geometry.
- Exclude reference objects and Blender-only guides.
- Export visual meshes, collision proxies, and stateful modules separately.
- Keep filenames stable across revisions so reimporting is predictable.

### Studio ownership

Studio owns:

- Final room assembly and terrain.
- Collision assignments and collision groups.
- Tags, attributes, prompts, and instance-only configuration outside a
  Rojo-managed tree.
- Lighting, fog, water, poison, particles, sounds, and post-processing.
- Published mesh, texture, and animation asset IDs.

Local source owns all scripts, modules, runtime-created prompts, and exported
realm-local anchor data. Rojo synchronizes `src/` into Studio.
Do not edit a Rojo-managed script in Studio unless it will immediately be synced
back to disk according to [Rojo Sync & Version Control](./rojo-sync.md).

### Verifying a dungeon launch

Keep the editable realm model directly under `Workspace`, but never run a party
inside that master copy. A portal configuration names the realm template and
encounter. The dungeon instance service clones the template under
`Workspace.DungeonInstances`, moves that clone to an isolated same-server slot,
and teleports accepted players to the clone's root `SpawnPoint`.

For a fresh-session verification:

1. Sync Rojo and start Play in Studio.
2. Obtain the configured dungeon key. In development, use the existing F10
   `ItemGrantDevMenu`; production acquisition can use the key shop or rewards.
3. Enter the tagged portal as a solo player or party leader.
4. Confirm missing-key and ready states before accepting.
5. Confirm the key is consumed only after everyone accepts.
6. Inspect `Workspace.DungeonInstances` during the run and verify the party is
   inside a new clone at its `SpawnPoint`, not inside the source template.
7. Exercise entry, death, disconnect, leave, wipe, victory, and cleanup. The
   GUID-named clone and all encounter-owned runtime objects must disappear when
   the run ends.

## 7. Gameplay architecture

- Give each encounter one server-owned lifecycle controller.
- Put tuning and party-scaling formulas in shared configuration.
- Keep damage, status effects, enemy spawns, puzzle completion, rewards, and
  state transitions server-authoritative.
- Let clients render telegraphs, interfaces, camera presentation, audio, and
  local cursor feedback from server-approved state.
- Prefer tags and attributes for replicated presentation state.
- Use remotes for actions that require validation rather than broadcasting every
  visual frame.
- Own all connections, tasks, temporary instances, reservations, and hazards in
  an encounter cleanup container so victory, failure, and realm destruction can
  tear them down deterministically.

## 8. Validation checklist

### Blender review

- Player and boss scale references are present.
- Important tasks are visible from expected approach directions.
- Combat and interaction zones have sufficient clearance.
- Stateful pieces and collisions remain separate.
- Pivots and origins support planned movement.

### Studio graybox review

- Import scale matches the design measurements.
- Players do not snag on seams, slopes, stairs, or dressing.
- The boss can navigate intended routes without covering prompts.
- First-person camera does not enter ceilings, walls, or oversized props.
- Every tagged anchor belongs to the correct realm instance.

### Encounter review

- Test solo, balance-baseline, and maximum party sizes.
- Test death, disconnect, wipe, victory, reset, and realm destruction.
- Test interaction contention and latency.
- Confirm hazards cannot persist into a later run.
- Confirm visual warnings remain readable at maximum effect density.
- Confirm performance under maximum configured add and hazard counts.

### Final art review

- PBR scale and orientation are consistent across modules.
- Lighting preserves telegraph colors and puzzle readability.
- Decoration does not change accepted collision or navigation.
- Streaming does not hide essential encounter objects at gameplay distance.

## Mob levels in a run

**Every mob in a run takes the run's level**, decided once when the run launches — the boss, trash and encounter adds alike. No spawn definition carries a hand-typed level any more.

The rule lives in `RS/DungeonLevels`: **base level = the tier's level cap − 6**, so a T1 run (cap 21) is level 15. `TIER_LEVEL_CAP` is `21 / 41 / 61 / 81 / 100`; the T5 value is an assumption, since there is no T6 to cap against.

```
DungeonInstanceService.launchDungeon
    instance.runLevel = DungeonLevels.Resolve(numericTier, instance.modifiers)
        -> DungeonMobSpawnService.RegisterForRealm(..., runLevel)   boss + trash
        -> MiasmaEncounterService.Start{ runLevel = ... }           encounter adds
```

A spawn definition may set `LevelOffset` to sit above or below the run level (e.g. `LevelOffset = 2` for a boss meant to out-level its trash). The F8 dev-tool boss spawn uses the same resolver, so a playtest fights the boss at its real dungeon level.

### Modifiers (the extension point)

`instance.modifiers` is an array of modifier tables, empty today. Each may shift the level:

```lua
{ Id = "Hardened", LevelDelta = 4 }       -- +4 on top of whatever came before
{ Id = "Ascended", LevelOverride = 30 }   -- replace the level outright
```

Overrides apply first (last one wins), then every delta is added. The result is floored at 1 but deliberately **not** capped at the tier's level cap, since a hard-mode modifier pushing past it is the point. Adding a real modifier is: define its table, put it in `instance.modifiers` at launch. Nothing that spawns mobs changes. `Resolve` also returns a step-by-step breakdown for a future "Lv 19 (15 base, +4 Hardened)" readout.
