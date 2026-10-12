---
title: Model, Rig & Studio Setup (custom skinned NPCs)
tags: [npc, rigging, blender, animation, studio]
aliases: [NPC model pipeline, Skinned NPC setup]
---

# Model, Rig & Studio Setup

How a Tripo character becomes a live, animated NPC in the game: fix the mesh, build a custom skinned rig, publish the model and its idle without the Studio importer, and swap it into the world. Custom rig means our own bones on one skinned MeshPart, **not R15** (R15 is the player pipeline, see `tripo-to-roblox-r15`).

**Shared kit:** `assets/models/npcs/_rigkit/npc_rig.py` holds everything generic (load and scale the Tripo source, the heat proxy, weight helpers, foot IK, idle baking, FBX export, upload, the clip exporter, review renders, clearance). A new NPC is three small scripts: `build_<npc>_rig.py` (bones, accessory rules, pose), `review_<npc>.py`, `export_<npc>_idle.py`. Copy `npcs/capybara animal tamer/rig/`.

Worked examples:
- **The capybara Animal Trainer** (`assets/models/npcs/capybara animal tamer/rig/`): the first NPC on the kit, about 7 minutes end to end.
- **The Oakhaven Blacksmith** (`assets/models/npcs/oakhaven blacksmith/rig/`): on the kit, with an eye repaint first, about 10 minutes.
- **The Merchant** (`assets/models/npcs/merchant/rig/`): the full chain below, fully scripted, idle published through Open Cloud. Copy this folder's scripts for the next NPC.
- **The Auctioneer** (`assets/models/npcs/auctioneer/Auctioneer Model/`): same rig idea (plus face and finger bones, hand IK), but its idle went in through the Animation Editor.

**Simple creatures skip Tripo altogether:** the Miasma underling (a slime) is generated end to end by one Blender script: revolved profile mesh, texture painted from the surface's 3D coordinates, a translation-bone cage for squash and stretch (Roblox bones can't scale), and its clips. Same upload, bind-measure and clip-export steps as below. See `assets/models/mobs/dungeon bosses/miasma/underling/README.md`.

## 0. Generate by parts, then fix the source mesh

**Generate the head separately (preferred for NPCs and mobs, 2026-10-07).** A whole-body Tripo generation spends little of its budget on the face: eyes come out smeared, brows and hair bleed skin colour, and repainting only goes so far (the Blacksmith's eyes stayed wrong after a mirror repaint). A separate head generation gives a far sharper face and texture. These are separate GENERATIONS, not Tripo's Segment (still skip that: it splits one mesh into pieces with independent topology).

How the Blacksmith was assembled (`oakhaven blacksmith/`, head in `blacksmith head/`):
1. Delete the old head off the body at the neck, in Edit Mode (keep the neck stub).
2. Import the new head and place it on the stub: right scale, angle and height, its neck opening just above the body's.
3. Join the head into the body (`Ctrl+J`, body active), select BOTH neck openings (boundary edge loops), and **Edge > Bridge Edge Loops** (3 cuts, Surface interpolation, smoothness about 0.6). Bridge handles unequal loops (the Blacksmith's were 10 and 16 edges). "Fill" or merging nearest vertices does not work: the openings never line up.
4. Give the band the head's neck skin (head material, UVs from the nearest head neck vertex), then paint over whatever old texture is left on the body's neck stub.
5. Weights: the head follows Head, fading into Neck over its neck; the band blends from the body's neck ring up to that.

Consequences to handle before rigging:
- **Two materials = two textures.** Roblox imports one MeshPart per material. Either keep two skinned MeshParts on one skeleton (unverified in this project) or bake both into one atlas (proven: one MeshPart). Give the head a bigger share of the atlas.
- **Triangles add up.** The Blacksmith went from 8,772 to 10,667 with the new head. One MeshPart holds at most 10,000, so decimate the body a little or keep the parts as separate MeshParts.
- **Assemble in the working file, then rig.** The build script rigs `<Name>.blend`, so the joined mesh belongs there before `build_<npc>_rig.py` runs. Joining inside an already-built `_Rig.blend` works for a test, but the next rebuild would discard it.

Keep one working file per NPC (`<npc>/<Name>.blend`) for paint and sculpt fixes. The rig is built FROM it by script and never written back into it, so a fix is just "save, re-run".

**Texture paint (Tripo paints skin onto hair, smears faces):**
- **Paint Mask** (face-select icon in the Texture Paint header): select the faces to fix in Edit Mode, Tab back, and strokes can't spill onto anything else.
- **Clone brush** (Ctrl+click sets the source) copies existing painted detail, so the fix matches the AI style. Otherwise sample with S and paint, then shade with Multiply / Screen at low strength.
- Keep **Occlude** and **Backface Culling** on, or you paint through a hair lock onto the forehead behind it.
- **Image > Save (Alt+S)** in the Image Editor. Saving the .blend does not save painted pixels of an external image.
- Blender saves JPEG at quality 90 by default (the Merchant's 3.2 MB texture came out 1.2 MB). Save with `img.save(filepath=..., quality=98)` or as PNG.
- A texture-only fix needs no re-rig, but **don't upload the image on its own**: image uploads (`upload_image`, Decals) are capped at **1024 px**. A texture that arrives inside a model upload keeps 4096. Re-export the rig's FBX (it embeds the jpg from disk), upload it as a Model, LoadAsset it, and copy only its `TextureID` onto the live MeshPart and the template (`merchant/rig/refresh_texture.py`). Check the size with `AssetService:CreateEditableImageAsync(Content.fromUri(id)).Size`.

**One eye or brow smeared, the other clean:** mirror it with `_rigkit/mirror_texture_region.py` (render the face flat and front-on, then copy each target texel from the mirrored spot of the render). Don't sample the mesh directly: Tripo eyes are layered shells with tiny scattered UV charts, so nearest-surface lookups pick hidden faces and per-chart sampling smears. Back up `img.pixels` first.

**Sculpt (rough eyes, spikes):** Tripo meshes are low-poly (the Merchant is 4,480 verts), so carve nothing fine; smooth and let the texture carry the detail.
- Smooth (Shift), Grab (G) at a small radius, Crease (Ctrl to invert) for a soft lid line. X symmetry on.
- For more density, Edge > Subdivide (1 cut) on just the region: UVs interpolate, the texture stays put.
- **Never** Dyntopo, Remesh or an applied Multires on the source: they destroy UVs.
- Stay under **10,000 triangles** for the one MeshPart.

## 1. Build the rig (Blender, background script)

Pattern: `build_<npc>_rig.py`, run with `blender --background --factory-startup --python ...`. It opens the source blend, builds everything in memory, and saves `<Name>_Rig.blend` + `<Name>_Model.fbx` beside itself.

**Space and scale.**
- Apply the FBX's Y-up rotation into the mesh (`transform_apply`), so mesh and armature are plain Z-up objects. The character faces **-Y**.
- Scale to studs: **1 Blender unit = 1 stud** (`FBX_SCALE_UNITS`). Townsfolk are about 5.8 studs (the Auctioneer 5.85, the Merchant 5.82).
- Measure landmarks from vertex slices (shoulder, elbow, wrist, hip, knee, ankle, chin) before placing bones, and keep them as source-space constants in the script.

**Bones.**
- Body: `LowerTorso > UpperTorso > Neck > Head`, `Left/Right Shoulder > UpperArm > LowerArm > Hand`, `Left/Right UpperLeg > LowerLeg > Foot`.
- Accessories (packs, pouches, feathers, keys) get their **own deform bones** with their own weights, parented where they hang from (a backpack from `UpperTorso`, a belt pouch from `LowerTorso`). Keyed secondary motion today; a runtime spring can drive the same bones later.
- Controls (`Root`, `CTRL_Foot_*`, `CTRL_Knee_*`, hand IK targets) are `use_deform = False` and are not exported. They are baked when the clip is sampled.

**Weights.**
- **Bone Heat fails on raw Tripo meshes** (open shells, many islands), and also on a fine voxel remesh (0.03). What works: heat-weight a **0.06 voxel remesh** proxy with its **small fragments deleted** (thin brims, rope coils and ribbons break into floating pieces in the remesh, and one boneless fragment fails Heat for every bone), then carry the weights back by the nearest 4 proxy vertices. `Npc.heat_weights` does both.
- Then override by rule:
  - rigid islands (gloves, bracers) split by projection along the bone (LowerArm to Hand at the wrist);
  - small trims and buckles copy the nearest body vertex;
  - arm weight below the elbows is moved to `LowerTorso`, or the hands drag the coat;
  - accessories get soft position masks (smoothstep), not hard cuts.
- Verify the masks with a vertex-colour render before weighting (one colour per region, front / side / back).
- Finish: normalize, **at most 4 influences**, and assert every exported bone has some weight. A zero-influence bone can be dropped on import and silently re-parent its children.

**FBX export:**

```python
bpy.ops.export_scene.fbx(filepath=..., use_selection=True, object_types={"ARMATURE", "MESH"},
    use_armature_deform_only=True, add_leaf_bones=False, bake_anim=False, mesh_smooth_type="FACE",
    axis_forward="-Z", axis_up="Y", apply_unit_scale=True, apply_scale_options="FBX_SCALE_UNITS",
    path_mode="COPY", embed_textures=True)
```

Set `rig.data.pose_position = "REST"` around the export. Keep the texture at source resolution (no downscale to 1024).

## 2. Review before uploading

All in background Blender, written to `rig/review/`:
- idle frames from front, side and back;
- a **stress pose** (accessories 15-25 degrees, head and arms turned) to see that pieces move as solids and nothing tears;
- a **clearance check** (minimum hand-to-coat distance over the loop), since clipping is easy to miss in stills.

## 3. Publish the model (Open Cloud, no importer)

```
python tools/roblox_upload.py <rig>/<Name>_Model.fbx T1_<Name> "description"
```

Then in Edit mode, `InsertService:LoadAsset(id)` into ServerStorage. Check you got a MeshPart (with `TextureID`), the full `Bone` hierarchy, and an `AnimationController`. Open Cloud keeps skinning and bones; it adds a `Root` bone (the armature node) above your top bone.

**Two textures means two mesh objects.** Open Cloud imports ONE mesh object with two materials as ONE MeshPart with ONE texture, silently dropping the other (2026-10-09: Kane's separately generated head lost its face texture this way).
- **Fix:** split by material into separate skinned objects before export. Each imports as its own MeshPart with its own texture, skinned to the same bones. Script: `assets/models/mobs/named elites/kane axe model/split_kane_head.py`.
- **Keep the importer's layout:** with several mesh objects the bones land in a plain `RootPart`, with Motor6Ds from it to each MeshPart. **Don't move the bones into one of the MeshParts:** the other MeshPart then stops following them. Kane's head stayed at its rest pose while his body animated (2026-10-09, caught by an Edit-mode screenshot, not by checking bones).
- **Animations that address bones by part name:** rename the holder instead. Kane's clips go through `Kane_SkinnedMesh`, so the holder `RootPart` became `Kane_SkinnedMesh` (hidden, no collision) and the body MeshPart `Kane_Body`.
- **Match the original export's unit settings.** Check `UnitScaleFactor` in the FBX header: 100 with `FBX_SCALE_UNITS`, but the default writes 1.0.

**Swapping a skinned mob model in place** (Kane, 2026-10-09; full record in that folder's `Kane_UserHead_Split_README.md`):
1. Move the old model to `ServerStorage.MobModelsBackup`.
2. Line the new parts up on the old `Root` bone's world frame, and copy the old mesh's physical settings.
3. Re-point the HumanoidRootPart weld.
4. Before going live, pose both models mid-clip in Edit mode (`Animator:StepAnimations`) and **screenshot them** (MCP `screen_capture` with a camera position).
   - Checking bones alone isn't enough: identical bones can still drive a mesh part that doesn't follow them.
   - Read a bone's pose from `Bone.Transform`. In Edit mode `TransformedWorldCFrame` and `WorldCFrame` both include the pose, so comparing them shows no movement.

## 4. Measure the bind frames

Roblox's FBX import changes every bone's local axes, so a Blender local rotation can't be pasted onto a Roblox Bone as-is. Measure the live frames once per rig and save them as `rig/rig_snapshot.json`:

```lua
local mesh = game.ServerStorage.<Import>.<Model>.<Name>_Character
local bones = {}
for _, d in ipairs(mesh:GetDescendants()) do
	if d:IsA("Bone") then
		table.insert(bones, { name = d.Name, parent = d.Parent.Name, cf = { d.CFrame:GetComponents() } })
	end
end
return game:GetService("HttpService"):JSONEncode({ mesh = mesh.Name, bones = bones })
```

Re-measure whenever the rig is rebuilt with different bones or proportions (the exporter asserts the bind still matches: about 1e-6 studs when it does).

## 5. Publish the idle

Two routes, same Blender action:

| | KeyframeSequence `.rbxmx` (Merchant) | Animated FBX (Auctioneer) |
|---|---|---|
| Publish | `export_<npc>_idle.py -- --publish`, fully scripted (Open Cloud takes `.rbxmx` as an Animation) | A person in the Animation Editor: Import from FBX, Publish to Roblox (Open Cloud won't take an FBX animation) |
| Bone conversion | Ours, from `rig_snapshot.json` | Roblox's |
| One-time cost | Measuring the bind frames (step 4) | None |
| Per clip / per edit | One command | Manual clicks every time |

Default to the `.rbxmx` route. The exporter samples the **evaluated** pose (`convert_space` POSE to LOCAL, so IK and constraints are included), zeroes translation on connected bones, applies the per-bone correction, and writes the Pose tree as `<MeshPart name> > Root > bones`, the MeshPart and Root at weight 0. Every 2nd frame at 24 fps is plenty. Clip settings ride on the action: `Loop`, `Priority` ("0" Idle).

**Verify without Play mode:** load the published clip and pose a temporary copy in Edit mode, screenshot, then delete the copy. To test the real playback path, play it on a copy's Animator and call `animator:StepAnimations(1.5)` in Edit mode (wait until `track.Length > 0` first: the clip loads asynchronously), then read a Bone's `Transform`. No weld between root and skin is needed for this.

```lua
local seq = game:GetService("KeyframeSequenceProvider"):GetKeyframeSequenceAsync("rbxassetid://<id>")
-- pick a Keyframe, then for each Pose with Weight > 0: probeBones[pose.Name].Transform = pose.CFrame
```

## 6. Studio setup and the swap

**No code replaces an NPC's model.** The body is the Model instance in Workspace. Its `SSS/<Type>Bootstrap` finds it by name or `NpcType` attribute on every server start and wires it. Swapping = replacing the instance, keeping the name and attributes.

The model:

| Child | Setup |
|---|---|
| `<Name>_Character` (MeshPart) | Anchored, `CanCollide = false`, `CanTouch = false`; at feet + half its height |
| `AnimationController > Animator` | From the import, but **always add the `Animator`**: Open Cloud imports come without one (capybara, blacksmith), and `NpcIdleAnimations` then plays nothing (it warns) |
| `HumanoidRootPart` | Invisible 2x2x1, anchored, no collision, PrimaryPart; holds the `ProximityPrompt` (the bootstrap needs it or a `Torso`) |
| `Head` | Invisible, anchored, no collision or query, at the head; holds the name `gui` (created if missing) |
| `Collider` (optional) | Invisible, anchored, `CanCollide = true`, body-sized, so players can't walk through it |

The swap:
1. Raycast down **from the old NPC's own position** for the ground (casting from above hits stall roofs and counters).
2. Copy yaw only from the old facing (`CFrame.lookAt(feet, feet + flatLook)`); a model faces -Z.
3. Copy attributes (skip `RBX_*`: scripts may not set them), CollectionService tags, the prompt and the `gui`.
4. Move the old model to `ServerStorage.NPCModelsBackup` (`<Name>_R6_Legacy`); never delete it.
5. Put a clone in `ServerStorage.NPCModels` as `<Type>Template` for the F8 placer.
6. Destroy the LoadAsset wrapper.

**Idle wiring:** `IdleAnimationId` on the type's `RS/NPCRegistry` entry. `src/client/NpcIdleAnimations` plays it locally on every client (looped, Idle priority) for each `NPC`-tagged model with an `AnimationController`. No other code changes.

**Tutorial copies** (`TutorialPathway`, `TutorialRealmTemplate`) are separate instances; swap them separately if wanted.

## Checklist

- [ ] Source blend fixed, image saved (Alt+S), blend saved
- [ ] Rig built, every exported bone weighted, at most 4 influences, under 10k triangles
- [ ] Review renders, stress pose, hand clearance looked at
- [ ] Model uploaded, bones present after LoadAsset
- [ ] `rig_snapshot.json` measured
- [ ] Idle exported (bind error tiny) and published
- [ ] Edit-mode pose probe matches Blender
- [ ] Model swapped, old one backed up, template updated
- [ ] `IdleAnimationId` set in `NPCRegistry`
- [ ] Asset ids recorded in the NPC's `rig/README.md`
- [ ] User play-tests: idle plays, prompt opens the right menu, name tag height
