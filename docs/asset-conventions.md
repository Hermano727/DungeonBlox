---
title: Asset & Naming Conventions
tags: [assets, naming, conventions]
aliases: [Naming, Asset Registries]
---

# Asset & Naming Conventions

## Tiering is the naming system

The game is 5-tier (lvl 1/21/41/61/81); tier 1 is leather/wooden gear. Names must encode tier, never vague adjectives.

- New itemIds / prefabs / configs: `T1_Sword`, `T2_Helm`, `T1_Bow`. PascalCase after the tier prefix.
- Never "Low tier", "Basic", "Starter" as a *code-facing* identifier. Those are display words, not ids.
- `DisplayName` is the only place human phrasing belongs ("T1 Sword", "Training Sword").
- No snake_case or spaces in instance/prefab names. `Low_tier_sword`, `Wood Sword`, `Gravity Coil` are legacy — leave them, don't imitate them.

**Legacy ids are frozen.** `ItemDefinitions` keys ARE itemIds and are persisted in `PlayerProfile_v1`. Renaming a key orphans every saved item using it. Convention applies to *new* entries only; renaming an existing id requires an alias map that rewrites legacy ids on profile load. As of 2026-07 save data is dev-only, so a full rename + migration is still cheap if wanted.

## Asset ID registries (`RS/Assets/...`)

Asset IDs live in registry ModuleScripts, never as inline `rbxassetid://` literals.

```
RS/Assets/Icons/<Category>/<Category>Icons     -- Weapons, Armor, Materials, Keys, Consumables, Hearthstones
RS/Assets/Meshes/<Category>/<Category>Meshes   -- Weapons (added 2026-07)
```

Keys are SCREAMING_SNAKE and match the `ItemDefinitions` itemId: `TRAINING_SWORD`. Mesh entries carry `MeshId`, `TextureId`, and `GripDrop` (see [Character & Rigging Pipeline](./character-pipeline.md#weapon-authoring-convention) for how `GripDrop` is derived).

`MeshPart.MeshId` cannot be assigned from a script (`lacking capability NotAccessible`) — meshes must be set by importing, not generated at runtime. The registry is the source of truth for *documentation and validation*; the instance property is set at import time.

## Uploading assets without the Studio importer (Open Cloud)

Meshes and models can be uploaded straight from disk through the Open Cloud Assets API, with no File > Import 3D. First used 2026-09-29 for the wardrobe hair.

- **Key:** `ASSET_API_KEY` in the repo-root `.env`, which is gitignored and must never be printed or committed. It needs the asset read and write scopes.
- **Creator:** the place is user-owned (`game.CreatorId` 706604079), so `creationContext.creator.userId` is that id.
- **Upload:** `POST https://apis.roblox.com/assets/v1/assets` with header `x-api-key`, as multipart form data:
  - `request`: JSON `{ assetType = "Model", displayName, description, creationContext }`
  - `fileContent`: the `.fbx`, content type `model/fbx`
- **Wait for the asset id:** the upload returns an operation. Poll `GET https://apis.roblox.com/assets/v1/operations/<operationId>` until `done`; `response.assetId` is the new Model asset.
- **Bring it into the place:** in Edit mode, `InsertService:LoadAsset(assetId)` returns a Model holding the imported MeshPart(s). Move the MeshPart where it belongs and destroy the container. Check its `Size` against the build: FBX exported in studs arrives 1:1.
- **Every upload creates a new asset.** Record the ids next to the source files, like `assets/models/main character/hair/README.md`.
- **PBR comes through the FBX (confirmed 2026-10-10, `assets/builds/SafeZones/T1_FencePack`):** a Principled material with
  Base Color, Roughness and Normal Map (via a Normal Map node) image textures, exported with `embed_textures=True`, imports as
  a SurfaceAppearance (ColorMap, NormalMap, RoughnessMap) on every MeshPart, no separate image uploads. Put a whole kit in ONE
  FBX with one shared material: every piece then points at the same three images.

## Weapon and gear models: ChatGPT concept, then Tripo

How a hand-authored item (a Mythic, a named-elite piece, a tier set) gets its 3D model. The user generates the images and the Tripo model; Claude writes the prompts and does everything after Tripo.

1. **Concept image (ChatGPT).** Claude writes a few prompts, each a distinct design *direction* (not five wordings of one idea), each starting from the 3D-model preamble in [Art Direction](./art-direction.md). The user generates them, picks one, or asks for a mix ("A's blade, C's hilt").
2. **Tripo (image to 3D).** The user feeds the chosen image to Tripo: generate at ~20k, Retopo to the prop budget (500 to 3k triangles; a Mythic hero weapon may go to ~5k), keep the full-resolution texture. Skip Segment and Animate (see the Tripo settings in `.claude/CLAUDE.md`). The export goes to `assets/models/armor weapons equipment/<item folder>/`.
3. **Claude in Blender** (worked example `assets/models/dungeons/build_clear_props.py`):
   - rename every object, mesh, material and image: Tripo calls them `tripo_node_<uuid>`, which must not reach Roblox (the export asserts no "tripo" in the FBX bytes);
   - origin at the grip, blade along +Z (the weapon authoring convention), scaled in studs (a one-handed sword is ~3.5);
   - one MeshPart, one texture.
4. **Claude uploads** it (`tools/roblox_upload.py`) and wires it up:
   - the mesh registry entry, and the world-drop display prefab (`LootDropVisuals`; a Mythic would use a `ByMythicKey` lookup, which doesn't exist yet);
   - the held Tool's `Grip`. Its rotation is tuned live by the user.

**The concept prompt:** the preamble, the rules and the good/bad examples are in [Art Direction & Image Generation](./art-direction.md#1-3d-models-chatgpt-concept-image-then-tripo), section 1. That is the one place they live, so every model matches the rest of the game. A weapon uses the flat-of-the-blade view; anything with real depth (props, buildings, armour) uses the three-quarter view from slightly above, so Tripo sees the top and the sides.

Request lists with the actual prompts live with the feature that needs the model (e.g. [Dungeon Clear Sequence: asset requests](./dungeon-clear-asset-requests.md) for Miasma's Mythics).

## Finding sound effects

Pick effect sounds from the two libraries Roblox licenses for every experience: Pro Sound Effects
(creator `ProSoundEffects`, 7462895450) and APM (`APMOfficial`, 7462718749). Random Creator Store
uploads are often ripped from other games. `python tools/sfx_search.py "keyword" [max_seconds] [count]`
lists matches with their library descriptions. Pick by description, put the ids in
`RS/Assets/Sounds/SoundEffects` (a list = random variations), and mark them "not listened to"
until someone has auditioned them (Sounds under `ServerStorage.SfxAudition` preview in Studio).
