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
