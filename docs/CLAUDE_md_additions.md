# Additions for `.claude/CLAUDE.md`

Paste both sections at the end of `.claude/CLAUDE.md` (after the R15 character
pipeline bullets), then delete this file.

---

## Zone-based UI theming (design goal, not yet built)

**The UI should re-theme itself by zone.** Same layout, same components, different palette — the inventory in a T1 area should not look like the inventory in a T5 area. Tier identity is carried by colour and material feel, not by different screens.

Palette direction per tier follows the gear fiction:

| Tier | Level | Gear fiction | Palette direction |
|---|---|---|---|
| T1 | 1 | leather / wooden | **nature: browns + greens**, warm, muted, organic |
| T2 | 21 | — | TBD |
| T3 | 41 | — | TBD |
| T4 | 61 | — | TBD |
| T5 | 81 | — | TBD |

T1 is the reference implementation: earthy brown base, green accents, leather-and-timber feel. Grim-stylized, consistent with the existing tone — muted and slightly desaturated, not a bright fantasy palette.

**Architecture when this gets built:**

- One registry module, `RS/Assets/Themes/ZoneThemes`, same pattern as the icon/mesh registries. Keys `T1`..`T5`. Never inline `Color3.fromRGB(...)` in UI code.
- Theme is selected by **zone**, and zone already has a home — `SSS/ZoneService` + `StarterPlayerScripts/ZoneClient`. Theme lookup keys off the zone the player is in, so no new state system is needed.
- A theme is a flat table of *semantic* names (`PanelBg`, `SlotBg`, `SlotBorder`, `TextPrimary`, `TextMuted`, `AccentPositive`, `RarityCommon`...). Never geometry or layout — theming must not be able to move things.
- Rarity colours stay **global**, not per-theme. A purple Elite drop must read as Elite in every zone.
- Transitions between zones should tween the palette, not hard-cut, or the swap will read as a bug.

**Do this after the React migration, not before.** In the current imperative UI every colour is set at `Instance.new` time across 44 client scripts, so re-theming means hunting every mutation site. In React the theme is a context provider and a zone change re-renders the tree — it is the single strongest practical argument for finishing the React port first.

---

## Version control / Rojo pipeline

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

**Direction of truth:**

- Disk owns **scripts and data** (`src/`).
- Studio owns **geometry, terrain, instance trees** — Workspace, Lighting, StarterGui, ServerStorage, StarterPack tools. These are in `syncbackRules.ignoreTrees`.

**Syncback before serve when disk is stale.** `rojo serve` pushes disk -> Studio and will happily overwrite newer Studio work. To pull Studio -> disk: `rojo syncback . --input place.rbxl`. Syncback only writes instances referenced in the project tree, so if something is missing from disk, the fix is usually the project file, not the command.

**Never re-add these to the project tree** (template leftovers; Rojo *creates* them in the live game on connect):

- a `Baseplate` Part under Workspace
- `Lighting` `$properties` (the template sets `Technology: "Voxel"`, which downgrades lighting)
- empty `$className: "Tool"` declarations in StarterPack (`Mace`, `Low_tier_sword`, `Wood Sword`, `Building Tools`)

**UI framework target:** React-lua (`jsdotlua/react` + `react-roblox` @17.0.1) via Wally. Roact is deprecated. Migration is strangler-fig — one panel per commit, React and imperative UI coexist. Never let both React and imperative code own the same instance.

### Rojo gotchas

**Never have `X.lua` and a folder `X/` in the same directory.** Both map to the same instance and syncback hard-errors:

```
Instances that are direct children of an Instance that is made by a
project file must have a unique name.
The child 'WeaponData' of 'ReplicatedStorage' is duplicated on the file system.
```

A ModuleScript **with children** is a folder containing `init.lua`; a ModuleScript **without children** is a bare `.lua` file. Never both. Hit 2026-08 with `src/shared/WeaponData.lua` + `src/shared/WeaponData/` — the folder was a leftover from before `WeaponData.Weapons` became the single authority.

**Deleting the files is not enough** — git doesn't track empty directories, but Rojo reads the filesystem, so an emptied folder still collides. Remove the directory itself.

---

## Correction to an existing line

Under **Weapon authoring convention**, this claim is now wrong:

> Weapons authored this way need no hand-tuned Grip rotation

`TrainingSword` did need one. Replace with:

> Origin-at-grip authoring makes the *translation* repeatable (`GripDrop` from the
> mesh registry), but rotation still needs tuning per weapon — the hand attachment
> has its own orientation. `TrainingSword` landed at:
>
> ```lua
> tool.Grip = CFrame.new(0, -1.295, 0)
>     * CFrame.Angles(math.rad(20), 0, math.rad(25))
>     * CFrame.Angles(0, math.rad(-15), 0)
> ```
>
> Grip rotation axes, with the blade along the Handle's +Y:
>
> | Axis | Effect |
> |---|---|
> | X | pitch — swings the tip fore/aft |
> | Y | roll — spins the handle around the blade, tip stays put |
> | Z | yaw — sweeps the tip around the wrist axis |
>
> Multiply roll (Y) on the **right** so it turns about the blade's own local axis;
> otherwise it drifts whenever X or Z change. Do not tune Grip by measuring against
> `StarterCharacter`'s rest pose — the arm hangs down there but is raised in most
> animations, so world-space angles mislead. Tune live in Play instead.
