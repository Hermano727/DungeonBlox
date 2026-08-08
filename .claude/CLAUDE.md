# Project: DungeonBlox

Roblox first-person Looter-ARPG (DungeonRealms-like). 5-tier progression (lvl 1/21/41/61/81), energy-based combat, alignment system (Lawful/Neutral/Chaotic).

## Gameplay loop
- **Combat/Energy:** energy bar 8/s regen. 0 energy = "Low Energy Mode" (3s lockout). Walk regens; sprint/swing drains.
- **Spawners/Sharding:** radius spawners w/ cooldowns. Shard Hop cooldown by alignment: Lawful 10s, Neutral 30s, Chaotic 1m.
- **Loot:** private, visual "flying keys" mob→world chests (Food/Green, Normal/White, Elite/Purple).
- **Score:** 1 Score = 1 Loot Roll. Damage-weighted kill credit; base score 1 (world) / 4 (dungeon) to all party.
- **Dungeons:** instanced 8-player, tier keys + difficulty mods. Auto-Scrap low-tier loot.

## Key systems
- **Alignment/death-drop:** Neutral/Chaotic = PvP. Death rule (`SSS/DungeonDeathProtection`) applies to *every* death regardless of alignment today — no Lawful/Neutral leniency yet. See Death-drop section below.
- **Enchanting:** safe to +3. +4 fail (20%) breaks item (3x repair), resets to +0. Max +9. Protection scrolls block breaking, not failure.
- **Level scaling:** dmg penalty if mob 5+ lvl above; XP penalty if mob 5+ lvl below.
- **Professions:** Mining + Spear-Fishing, tools roll substats, 2:1 Ore→Scrap.

## Dev principles
First-person only. Grim-stylized tone. No emoji/em-dash in UI. Prefer readable code over clever; combat/loot/shard logic must stay lag-free at high CPS.

---

## Two profile systems — don't mix up
| | Legacy (dead) | Modern (active) |
|---|---|---|
| Service | `SSS/PlayerDataManager` | `SSS/DungeonProfileService` |
| Schema | `SSS/PlayerBootstrap` DEFAULT_KIT | `RS/DungeonProfileTypes` DefaultProfile() |
| Storage | slot-indexed `profile.Inventory[i]` | uuid-keyed `profile.inventory[uuid]` |
| Used by | `InventoryService`, `PlayerBootstrap` | everything new |

Legacy capitalized `profile.Equipped`/`profile.Inventory` (InventoryService, PlayerBootstrap) is a different system — don't touch when working on modern inventory.

## Item pipeline
```
ItemConfig (RS) -- raw stat tables
  -> ItemGenerator (SSS) -- rolls rarity/stats -> ItemClass
  -> ItemClass (SSS) -- getFinalStats(), toGrantTemplate()
  -> LootService (SSS) -- MobManager.ProcessMobDeath -> grant -> ItemDropNotify
  -> LootClient -- top-right banner
```
`ItemConfig`: TIER_MEDIANS, ARMOR_*_RANGES[tier][rarity], WEAPON_DMG_RANGES, WEAPON_MULTIPLIERS (Sword 1.00..Bow 1.20), TIER_DROP_CHANCE (server-side only!), TIER_RARITY_WEIGHTS.

Scale formula (`SSS/ItemGenerator.scaleStat`): `base*(1+(lvl-tierMedian)*0.01)`, floor; if lvl>100 also floor at `base*(1+(lvl-100)*0.05)`. Armor hps=floor(hp*0.5). Energy is float, 2dp.

GrantItem template: `{name, type, rarity, tier, enchantLevel, subStats={}, equipSlot, tags={}}`.

`RS/DungeonProfileTypes`: `DefaultProfile()`, `ValidateItemTemplate`, `VALID_SLOTS`, `GetAllowedEquipSlot(item)`.

`SSS/DungeonStatsService.RecomputeRuntimeHp(profile)` — call after every GrantItem.

## Mob system
- `SSS/MobClass` — `mob.Tier/MobID/Stats.Level/DamageTracker`
- `SSS/MobManager` — heartbeat; `ProcessMobDeath` → `LootService.onMobDied`
- `SSS/MobData` (RS) — `FindMobById(id)` → baseStats, tier
- `SSS/SpawnerService` — reads `Workspace/Spawners/MobSpawners` Part attrs (MobId/Count/Radius/RespawnDelay/Active)

---

## Hotbar/Inventory model (current, Minecraft-style)

All 9 hotbar slots identical, no reserved weapon slot. `profile.equipped.Weapon` doesn't exist — your weapon is just whatever's in the hotbar. Bag is positional too: `profile.bagSlots[1..27]` (3x9, `Types.BAG_SLOT_COUNT`), same uuid-pointer pattern as `hotbar[1..9]`. `profile.inventory[uuid]` is the only ownership dict; `hotbar`/`bagSlots` are indices into it.

**Fill-first-empty-slot on every acquisition.** `SSS/DungeonProfileService.placeItemInFirstEmptySlot(profile, uuid)`: hotbar 1-9 first (if `itemAllowsHotbar`), else bagSlots 1-27. Wired into `GrantItem`, `GrantItemId`, `mergeStackableIntoInventory`'s create-fallback, `ChestWithdrawSlot`. Public wrapper `DungeonProfileService.PlaceItemInFirstEmptySlot` for the 2 outside callers that mint uuids directly: `AuctionHouseService.grantItemDirect`, `DungeonWorldLootService.GrantLootToPlayer`. **Any new direct `profile.inventory[uuid]=item` write must call this too**, or item is owned but invisible.

**Never raw-assign `profile.equipped[slot]=uuid` or `profile.hotbar[i]=uuid`.** Always go through `EquipItem`/`SetHotbarSlot`/`SetBagSlot`/etc — they clear the uuid's old slot reference first. A raw assignment (e.g. an old `seedStarterIfEmpty` bug) leaves the same uuid referenced in two places at once → item renders twice, and unequip/requip can make it vanish. Every "leaves a slot" path must call `clearUuidFromBagSlots`/`clearItemUuidFromAllHotbar`/`clearItemUuidFromAllEquipped` — already wired into `EquipItem`, `SetHotbarSlot`, `ChestDepositToSlot`, `ConsumeItemId`, `SalvageGearByUuid`, scroll-apply safety nets, and `DungeonDeathLoot.stripReferencesToMissing` (hotbar+bagSlots+equipped).

**Starter seed order (`DungeonBootstrap.seedStarterIfEmpty`):** explicit reorder step after granting — Sword→hotbar[1], Bow→[2], Pickaxe→[3], Spear→[4], independent of grant order. Armor still explicitly equipped via `EquipItem` (not hotbar-eligible, would otherwise sit in bag). Gated by `flags.trainingGearSeeded`, runs once ever; later sessions preserve player's own arrangement.

**Server actions:** `SetHotbarSlot`/`ClearHotbarSlot`/`SwapHotbarSlots`, `SetBagSlot`/`SwapBagSlot` (mirror pair), `EquipItem` (rejects `slot=="Weapon"` outright), `UnequipItem`. Dispatched via `DungeonInventoryAct` RF kinds of the same name in `DungeonBootstrap`.

**Client (`InventoryDragController`) — two gestures, one dispatch path (`performDrop`):**
1. Click-to-pick-up/place: click occupied slot → picks up (cursor-follow ghost), click destination → places (swaps if occupied). Same slot or right-click = cancel, free (nothing mutated until the placing click).
2. Hold-and-drag: press+hold on occupied slot, move past 5px threshold, release on destination. Release under threshold falls through to gesture 1. Drag-release uses position hit-testing (`dropTargetAt`/`pointInGui`) since it isn't tied to one button's own click event.
Both gestures end at the same `performDrop`/`performHotbarToHotbarSwap`/`performAssignToHotbar` calls — never add a third path to the server.

**Hover+number-key (1-9):** while menu open, hover bag/hotbar slot + press 1-9 = same assign/swap actions. Hover state fed by `DungeonMenuUI`'s existing tooltip MouseEnter/Leave (no 2nd hover system).

**Hotbar clicks while menu open = pick/place only**, no equip-by-click (that callback was always dead code). `DungeonHotbarHud`'s "press 1-9 while menu *closed*" to equip is separate/untouched.

`DungeonMenuUI` bag render reads `profile.bagSlots[i]` directly (no client-side sorting). Every bag button gets `BagSlot` attr (even empty ones — valid drop targets).

## Death-drop protection (`SSS/DungeonDeathProtection`)
Decision logic is standalone, not inlined in `DungeonDeathLoot` (which only owns the drop loop/coin loss/world-loot spawn). Keep precedence:
1. Profession items (Pickaxe/FishingSpear/`IsProtectedOnDeath`) — always
2. Equipped armor — always
3. "Main weapon" = first weapon found scanning `hotbar[1..9]` (closest-to-1, not strictly slot1) — `GetProtectedWeaponUuid`
4. Single highest-damage Bow anywhere in hotbar — `GetProtectedBowUuid` (can overlap rule 3)
5. Everything else, incl. all bag items, drops

**`ReorderHotbarAfterDeath(profile)`** runs after the drop loop: front-loads survivors into slots 1-4 in priority — melee weapon, bow, pickaxe, fishing spear, then anything else — closing gaps left by dropped items. Pickaxe/spear detection checks `equipSlot` then falls back to `toolPrefabName`/`itemId` substring match (catalog items don't carry an explicit equipSlot field).

---

## NPC system
Two parallel, non-unified paths — don't conflate:
1. **Bootstrap scripts** (primary): one `SSS/<Type>Bootstrap` per type. Scans `Workspace:GetDescendants()` for **every** matching Model (not just first — old `FindFirstChild(name,true)` bug silently broke all-but-one duplicate town copy), wires `NpcId`/ProximityPrompt/CollectionService tag `"NPC"`/Head.gui dialog.
2. **SpawnerService + ServerStorage/NPCModels clone** (dev-tool, F8 placer): independent of path 1, known 2nd source of duplicate NPCs (not yet unified).

NpcId convention: tutorial copy = `<type>_tutorial`, else first match = canonical (`blacksmith_01`), dupes get numeric suffix.

**Quest state is per-player (`profile.flags.<questName>`), not per-NPC-instance** — handlers check `npcType` only, not exact `npcId`, so any duplicate NPC of that type serves the same quest.

- `SSS/NPCService` — `NPCRequest` RF, `npcIndex` (by NpcId), `HANDLERS` dispatch, validates via `NPCRegistry.AllowsAction`.
- `RS/NPCRegistry` — pure data: `NpcType -> {Interactions, ShopCatalog, TradeRates, ...}`. Catalog data itself lives in `RS/ShopCatalogConfig` (one file, all NPC prices) — NPCRegistry just assigns `ShopCatalog = ShopCatalogConfig.<Type>.ShopCatalog`.
- `RS/DialogModule` — indexes `UIStroke` directly (not FindFirstChild) on name/arrow/dialog labels; calls `ensureNpcBillboardStrokes` first to backfill on old pre-UIStroke `Head.gui`s. Don't remove.
- Innkeeper is NOT a merchant-shop type (`SHOP_NPC_TYPES`) — routes through `HearthstoneClient.openInnkeeperShop()` like Blacksmith routes to `BlacksmithClient`, both via `MerchantShopClient`'s ProximityPromptService hook. Hearthstone remotes: `HearthstoneSync/Purchase/Teleport/Swap` + admin Add/Delete.

## Combat & animation
| File | Purpose |
|---|---|
| `RS/CombatAnimConfig` | all anim/hitbox constants — edit here only |
| `StarterPlayerScripts/CombatClient` | input->anim->hit->remote; never hardcode values |
| `StarterPack/R6Sword/AnimationScript` | gutted, do not restore (raced with CombatClient) |

Swap swing anim: edit `CombatAnimConfig.SWING_ANIM_ID` only. Must be R15-native or R6 (auto-converts); failed R15 delivery = silent no-op (no console error). `DEBUG=true` logs rig/anim/track per swing.

Gotchas: never restore `SwingAnimId` tool attribute (reverts on play-stop, becomes stale). `CombatClient.InitAnimator` must try `FindFirstChildOfClass("Animator")` then `WaitForChild` fallback — never `FindFirstChildOfClass` alone (races Roblox's async `Animate` script, creates a phantom 2nd Animator that doesn't drive the character). Player chars are R15 (Game Settings->Avatar, not the toolbar Avatar tab). **NPC rigs are R15 as of 2026-08** — the Avatar Type setting governs players only; NPCs are ordinary Models and may use any rig. Legacy toolbox NPCs are still R6; existing R6 animations auto-convert onto R15 (approximate, not broken). Bulk-spawned mobs are an open question — R15 is 15 parts/14 Motor6Ds vs 6/5, so measure before converting `SpawnerService` mobs.

## Networking (ReplicatedStorage)
| Name | Type | Dir | Purpose |
|---|---|---|---|
| `DungeonProfilePush` | RemoteEvent | S->C | full snapshot push |
| `DungeonProfileRequestSync`/`requestSync` | RF | C->S | fresh snapshot pull |
| `DungeonEquipItem`/`DungeonUnequipItem` | Event/RF | C->S | equip by uuid / unequip by slot |
| `DungeonInventoryAct` | RF | C->S | hotbar/bag/chest/enchant actions |
| `ItemDropNotify` | RemoteEvent | S->C | drop banner |
| `CombatRemote`/`CombatXPEvent` | Event | C->S / S->C | hit reg / XP popup |

**Any new purchase/shop client must call `DungeonMenuNet.requestSync()` after a successful action.** The implicit `DungeonProfilePush` broadcast can race or get dropped as stale — `BankClient`/`SkillsTabClient`/`AuctionHouseClient`/`BlacksmithClient` all do this defensively; `MerchantClient`/`ShopClientBase` originally didn't (fixed).

## UI entry points (StarterPlayerScripts)
`DungeonMenuUI` (panel layout+redraw, fonts via `qsFont`/`QS` at top of file), `DungeonMenuNet` (snapshot cache, `_seq`-aware merge), `LootClient`, `ItemTooltip`, `SkillsTabClient` (uses `local refresh` forward-declare pattern — see gotcha below), `MerchantShopClient` (routes ProximityPrompt by NpcType), `HearthstoneClient`.

## Enchant scrolls (`RS/EnchantScrollApply`, entry via `DungeonProfileService.ApplyEnchantScroll`)
- `Random.new()` is userdata, not a table — never `type(rng)=="table"` check; duck-type `type(rng.NextNumber)=="function"`.
- Validate scroll with `Types.ValidateOwnedItem`; validate target with `EnchantScrollApply.ValidateEnchantTargetItem` (rolled gear often has no catalog itemId, `ValidateOwnedItem` would reject it).
- After `ApplyEnchantScroll`, client must call `requestSync()` — RF return payload can look stale vs a racing `DungeonProfilePush` and get dropped silently.

## Studio/tooling gotchas
- **Command bar defaults to Client during play** — switch to Server before server-side require()/mutations.
- **`execute_luau` caches `require()` across calls within one Edit-mode session.** Editing a ModuleScript does NOT invalidate an already-required copy — you'll silently get pre-edit behavior (missing new functions) until a Play-mode Start/Stop cycle resets the Lua VM. If a just-added function "doesn't exist," verify with a fresh Play cycle before assuming the edit failed.
- **MCP `multi_edit` is atomic** — one failing `old_string` match rolls back every edit in that call. Verify after with a read/grep.
- Scripts via `multi_edit` persist to the place; scripts via `execute_luau` do not survive session end.
- `goto continue` invalid in Luau nested-if — use inline `and not (cond)` guards.
- `DungeonMenuUI` corruption recovery: rename old (`.Name = "..._OLD"`), create fresh via `multi_edit` empty-old_string, destroy old. Don't patch corrupted layout code in place.
- Quicksand font "Temp read failed" in Studio is expected/harmless (works in real game) — keep `FontFace` set in `pcall`.
- **Play-mode profile/join races:** `seedStarterIfEmpty`/character-spawn flow is async; ad-hoc `execute_luau` profile pokes right after spawn often race it (profile looks unseeded for several real seconds). Don't conclude a feature is broken from one early poke — wait or test via real UI.

---

## Asset & naming conventions

**Tiering is the naming system.** The game is 5-tier (lvl 1/21/41/61/81); tier 1 is leather/wooden gear. Names must encode tier, never vague adjectives.

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

Keys are SCREAMING_SNAKE and match the `ItemDefinitions` itemId: `TRAINING_SWORD`. Mesh entries carry `MeshId`, `TextureId`, and `GripDrop` (see weapon pipeline below).

`MeshPart.MeshId` cannot be assigned from a script (`lacking capability NotAccessible`) — meshes must be set by importing, not generated at runtime. The registry is the source of truth for *documentation and validation*; the instance property is set at import time.

## Blender -> Roblox export pipeline

Hard-won rules. Each exists because of a specific silent failure.

**Texture filename collisions produce a black or error-flagged import.** Blender names embedded FBX textures from the image's *filepath*. An image with an empty filepath, or one pointing at a path that doesn't exist on this machine (common with packed/downloaded assets), falls back to a generic name — several textures then export as `base_color_texture` and overwrite each other. Symptom: import preview lists multiple `base_color_texture` entries with red icons, or the model imports black with only one part textured correctly. Fix: give every image a real unique file on disk (`img.filepath_raw = <unique path>; img.file_format='PNG'; img.save()`) before exporting.

**One texture per MeshPart.** A multi-material mesh imports as one MeshPart per material. That's fine and often desirable for props. It is NOT fine for a single-part asset — merge into one atlas and remap UVs by material slot.

**Delete material slots with zero faces before export.** They confuse the importer and add phantom entries.

**Limits:** 10,000 triangles per MeshPart; textures capped at 1024 for meshes (2048 only for Marketplace avatar bodies).

**Strip Normal/Metallic/Roughness links before exporting props.** Roblox uses base colour only unless you build a `SurfaceAppearance`. Leaving them linked bloats the FBX several times over.

**Check whether alpha is actually used before stripping it.** Measure the alpha channel; if min == 1.0 the link is redundant and should go. If a meaningful share of pixels are below ~0.9 it's real cutout transparency and must stay.

### Weapon authoring convention
Author in Blender with **origin at the grip point** and **blade along +Z** (becomes +Y in Roblox after FBX axis conversion, matching the classic sword Handle convention). Scale in studs (a one-handed sword is ~3.5; the player character is 5.82).

Roblox welds Tools by `Handle.CFrame` — the bounding-box centre — and **ignores `PivotOffset`**. So `Tool.Grip` must compensate: `CFrame.new(0, GripDrop, 0)` where `GripDrop` is the negative Y distance from bbox centre to grip. Store it in the mesh registry. Origin-at-grip authoring makes the *translation* repeatable (`GripDrop` from the mesh registry), but **rotation still needs per-weapon tuning** — the hand attachment carries its own orientation. `TrainingSword` landed at:

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

## NPC rigs: R15, not R6

Line 117 says *"NPC/mob rigs are R6, separate."* That recorded inherited toolbox models, not a rule. **The Avatar Type game setting governs player characters only** — NPCs are ordinary Models and can use any rig.

As of 2026-08 new NPCs are built **R15**, same pipeline as the player character. A Tripo mesh gets segmented into 15 parts regardless, so forcing it back down to 6 throws away joints for nothing. Existing R6 NPC animations still play — Roblox auto-converts R6 onto R15 rigs (approximate, but not broken).

Open question: **bulk-spawned mobs**. R15 is 15 parts and 14 Motor6Ds vs 6 and 5. Irrelevant for a dozen town NPCs, potentially significant for `SpawnerService` radius spawners at high counts. Measure before committing mobs to R15; named/interactive NPCs are R15 unconditionally.

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
