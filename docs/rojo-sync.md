---
title: Rojo Sync & Version Control
tags: [rojo, tooling, sync]
aliases: [Rojo, Syncback]
---

# Rojo Sync & Version Control

## Repo layout

**Repo:** `~/Desktop/DungeonBlox`. Rojo project already set up — this is not a fresh bootstrap.

**`src/` is the only source layout.** `default.project.json` maps:

```
src/shared           -> ReplicatedStorage
src/server           -> ServerScriptService
src/client           -> StarterPlayer.StarterPlayerScripts
src/characterscripts -> StarterPlayer.StarterCharacterScripts
src/starterpack      -> StarterPack
```

A duplicate `roblox/` tree (older dump of the same scripts) was deleted 2026-08. If it reappears, it is stale — do not read from it.

**Toolchain is Rokit, not Aftman.** `rokit.toml` is the source of truth; Aftman is unmaintained (its author left the Roblox ecosystem). Rojo must be **>= 7.7.0 final** — syncback shipped there, and 7.7.0-rc.1 predates several syncback fixes.

## Direction of truth

- Disk owns **scripts and data** (`src/`).
- Studio owns **geometry, terrain, instance trees** — Workspace, Lighting, StarterGui, ServerStorage, StarterPack tools. These are in `syncbackRules.ignoreTrees`.

**`StarterPlayer` is a mixed tree** — `StarterCharacterScripts` and `StarterPlayerScripts` are Rojo-owned (`src/characterscripts` / `src/client`), but `StarterPlayer.StarterCharacter` itself has no `$path` entry anywhere in `default.project.json`. If it exists, Roblox's built-in behavior clones it for every spawning player instead of their real avatar — no script drives that swap, it's just engine default behavior triggered by the model's presence. There is nothing on disk to open for it; it lives only in the `.rbxl`, edited directly in Studio (same pattern as `ServerStorage.ArmorModels`/`ServerStorage.LootDropVisuals`). `StarterPlayer`'s own `$properties` block sets `LoadCharacterAppearance: false` — without that, Roblox still layers the player's real avatar clothing/body on top of the custom `StarterCharacter` rig on spawn. The current `StarterCharacter` is the custom-scaled R15 base rig (Head/UpperTorso/limbs/Humanoid/HumanoidRootPart), the same one measured for armor-offset tuning.

## Serve vs syncback

**Syncback before serve when disk is stale.** `rojo serve` pushes disk -> Studio and will happily overwrite newer Studio work. To pull Studio -> disk: `rojo syncback . --input place.rbxl`. Syncback only writes instances referenced in the project tree, so if something is missing from disk, the fix is usually the project file, not the command.

## Never re-add these to the project tree

Template leftovers; Rojo *creates* them in the live game on connect:

- a `Baseplate` Part under Workspace
- `Lighting` `$properties` (the template sets `Technology: "Voxel"`, which downgrades lighting)
- empty `$className: "Tool"` declarations in StarterPack (`Mace`, `Low_tier_sword`, `Wood Sword`, `Building Tools`)

**UI framework target:** React-lua (`jsdotlua/react` + `react-roblox` @17.0.1) via Wally. Roact is deprecated. Migration is strangler-fig — one panel per commit, React and imperative UI coexist. Never let both React and imperative code own the same instance.

## Rojo gotchas

**Never have `X.lua` and a folder `X/` in the same directory.** Both map to the same instance and syncback hard-errors:

```
Instances that are direct children of an Instance that is made by a
project file must have a unique name.
The child 'WeaponData' of 'ReplicatedStorage' is duplicated on the file system.
```

A ModuleScript **with children** is a folder containing `init.lua`; a ModuleScript **without children** is a bare `.lua` file. Never both. Hit 2026-08 with `src/shared/WeaponData.lua` + `src/shared/WeaponData/` — the folder was a leftover from before `WeaponData.Weapons` became the single authority.

**Deleting the files is not enough** — git doesn't track empty directories, but Rojo reads the filesystem, so an emptied folder still collides. Remove the directory itself.

## Rojo limitations learned the hard way (2026-08)

- **Deleting a `meta.json` does not reset the properties it declared back to Roblox's engine defaults on an instance that already exists in Studio.** Rojo only pushes properties it currently has an opinion about; removing the declaration makes Rojo stop *managing* that property, it does not unset it. Confirmed directly: `KeybindConfig.meta.json` set `Sandboxed: true`; deleting the meta.json and re-syncing left the live `ReplicatedStorage.KeybindConfig.Sandboxed` still `true` (verified via `inspect_instance`). Had to reset it manually (`instance.Sandboxed = false` via `execute_luau`) on the already-existing Studio instance. **Potentially** version/config-dependent — not confirmed whether a from-scratch place (or a Rojo setting) would behave differently — but treat "delete the meta.json" as necessary, not sufficient, for reverting a property. Always verify with `inspect_instance` after removing a meta.json instead of assuming the deletion took effect.
- **If you see `The current thread cannot start '<Module>' (lacking capability RunClientScript/...)`**, check that module's meta.json (and any sibling/ancestor's) for `Sandboxed: true` + a `Capabilities.SecurityCapabilities` bitmask. This is real Roblox script-capability sandboxing (meant for untrusted/third-party content) and silently kills every script that requires that module at the top level — it can take down most of the game's client scripts at once if the sandboxed module is a widely-required shared config. Known offenders found 2026-08: `KeybindConfig` (fixed) and `DialogModule` + `DialogModule/sounds` (fixed) — both are core hand-authored game code, not toolbox imports, so the sandboxing there was accidental, likely a leftover from a prior syncback that stamped it broadly. `client/Enviroment/InteractiveGrass` (both copies, under `src/client/` and `src/shared/Modules/`) and `shared/Modules/init` still carry the same flag as of this writing — **potentially** intentional (toolbox-sourced grass asset) or **potentially** the same accidental stamp; not yet verified either way, left alone pending confirmation.
- **Separately spotted, not yet fixed:** `src/shared/DialogModule/` has both `init.lua` and `init.luau` (identical content, saved 12 minutes apart on 2026-08-02) — the same duplicate-instance risk the Rojo gotchas section above warns about, just within one folder instead of a `X.lua` + `X/` collision. Appears harmless today since the two files are identical, but is a landmine for the next edit that touches only one. Needs a deliberate cleanup (delete one), not yet done.

See also: [Studio & Tooling Gotchas](./studio-tooling.md) for the Play-mode `require()` caching gotcha and other command-bar/edit-mode traps.
