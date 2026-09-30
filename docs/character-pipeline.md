---
title: Character & Rigging Pipeline
tags: [3d-assets, blender, rigging, pipeline]
aliases: [Blender Pipeline, Tripo, R15 Pipeline]
---

# Character & Rigging Pipeline

Hard-won rules for the Tripo AI → Blender → Roblox workflow. Each rule exists because of a specific silent failure. Full step-by-step workflow lives in the `tripo-to-roblox-r15` skill — this doc is the reference for *why* each rule exists.

## Blender -> Roblox export pipeline

**Texture filename collisions produce a black or error-flagged import.** Blender names embedded FBX textures from the image's *filepath*. An image with an empty filepath, or one pointing at a path that doesn't exist on this machine (common with packed/downloaded assets), falls back to a generic name — several textures then export as `base_color_texture` and overwrite each other. Symptom: import preview lists multiple `base_color_texture` entries with red icons, or the model imports black with only one part textured correctly. Fix: give every image a real unique file on disk (`img.filepath_raw = <unique path>; img.file_format='PNG'; img.save()`) before exporting.

**One texture per MeshPart.** A multi-material mesh imports as one MeshPart per material. That's fine and often desirable for props. It is NOT fine for a single-part asset — merge into one atlas and remap UVs by material slot.

**Delete material slots with zero faces before export.** They confuse the importer and add phantom entries.

**Limits:** 10,000 triangles per MeshPart; textures capped at 1024 for meshes (2048 only for Marketplace avatar bodies).

**Strip Normal/Metallic/Roughness links before exporting props.** Roblox uses base colour only unless you build a `SurfaceAppearance`. Leaving them linked bloats the FBX several times over.

**Check whether alpha is actually used before stripping it.** Measure the alpha channel; if min == 1.0 the link is redundant and should go. If a meaningful share of pixels are below ~0.9 it's real cutout transparency and must stay.

### Weapon authoring convention

Author in Blender with **origin at the grip point** and **blade along +Z** (becomes +Y in Roblox after FBX axis conversion, matching the classic sword Handle convention). Scale in studs (a one-handed sword is ~3.5; the player character is 5.82).

Roblox welds Tools by `Handle.CFrame` — the bounding-box centre — and **ignores `PivotOffset`**. So `Tool.Grip` must compensate: `CFrame.new(0, GripDrop, 0)` where `GripDrop` is the negative Y distance from bbox centre to grip. Store it in the mesh registry (see [Asset & Naming Conventions](./asset-conventions.md)). Origin-at-grip authoring makes the *translation* repeatable (`GripDrop` from the mesh registry), but **rotation still needs per-weapon tuning** — the hand attachment carries its own orientation. `TrainingSword` landed at:

```lua
tool.Grip = CFrame.new(0, -1.295, 0)
    * CFrame.Angles(math.rad(20), 0, math.rad(25))
    * CFrame.Angles(0, math.rad(-15), 0)
```

Grip rotation axes, blade along the Handle's +Y:

| Axis | Effect |
|---|---|
| X | pitch — swings the tip fore/aft |
| Y | roll — spins the handle about the blade; tip does not move |
| Z | yaw — sweeps the tip around the wrist axis |

Multiply roll (Y) on the **right** so it turns about the blade's own local axis, or it drifts whenever X or Z change. Do **not** tune Grip against `StarterCharacter`'s rest pose — the arm hangs down there but is raised in most animations, so world-space angles mislead. Tune live in Play. Contrast `Low_tier_sword`, whose Grip is unrepeatable magic numbers from dragging in Studio.

### R15 character pipeline

Full workflow lives in the `tripo-to-roblox-r15` skill. The two that bite hardest:

- The armature object's **90 deg X rotation must stay UNAPPLIED**. Freezing it silently prevents Roblox from ever offering R15 as a Rig Type.
- The **rest pose must match Roblox's** (arms angled down, not T-pose). Stock animations store rotations relative to rest, so a T-posed rig plays every animation ~50 deg off.

## NPC rigs: R15, not R6

**The Avatar Type game setting governs player characters only** — NPCs are ordinary Models and can use any rig. (An older note in this project's history claimed NPC/mob rigs were R6 as a rule; that recorded inherited toolbox models, not an actual rule.)

As of 2026-08 new NPCs are built **R15**, same pipeline as the player character. A Tripo mesh gets segmented into 15 parts regardless, so forcing it back down to 6 throws away joints for nothing. Existing R6 NPC animations still play — Roblox auto-converts R6 onto R15 rigs (approximate, but not broken).

Open question: **bulk-spawned mobs**. R15 is 15 parts and 14 Motor6Ds vs 6 and 5. Irrelevant for a dozen town NPCs, potentially significant for `SpawnerService` radius spawners at high counts (see [Mob & NPC System](./mob-and-npc-system.md)). Measure before committing mobs to R15; named/interactive NPCs are R15 unconditionally.

## Tripo generation settings (established 2026-08)

- **Generate at ~20k**, then **Retopo to your final target** — do NOT generate high and decimate. Retopo rebuilds clean surface flow; Decimate collapses edges and leaves whatever falls out. Doing both destroys what retopo produced.
- Target triangles by class: named NPC **8k–15k**, common mob **3k–6k**, boss **15k–25k**, prop/weapon **500–3k**.
- Watch units: if the retopo field is in **faces/quads**, halve the triangle number.
- **Texture 2K** in Tripo (exports at 1024, which is Roblox's mesh cap anyway).
- **Skip Tripo's Segment** — it is the same failure mode as "generate in parts": independently generated topology per piece, boundaries that do not share vertices, unfixable seams.
- **Skip Tripo's Animate** — produces a non-R15 rig you would only have to undo.
- Generate the character with **empty open hands** and tools as separate props. AI generators sculpt a closed fist around a held object and you inherit a grip you cannot open.
- Prompt for **A-pose, arms ~45 deg down**, not T-pose — closer to Roblox's R15 rest, so less pose-baking later.

## Topology: quads are convenient, not required

FBX export triangulates regardless of what retopo produced, and **Roblox triangulates everything on import** — the shipped result is identical either way. Do not run tris-to-quads to "fix" it.

Quads only ever helped `Alt+Click` edge-loop select. The anti-seam property does **not** come from cutting along a neat loop — it comes from both halves being cut from *one mesh*, so boundary vertices are literally the same vertices. Any selection-based split preserves that.

On triangulated meshes, cut with **planar bisect** at joint heights:

```python
bpy.ops.mesh.bisect(plane_co=(0, 0, JOINT_Z), plane_no=(0, 0, 1))
# select one side, then mesh.separate(type='SELECTED')
```

Deterministic, scriptable across all 14 cuts, and a better match for R15 — Roblox joints pivot at fixed planes.
