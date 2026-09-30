# Project: DungeonBlox

Roblox first-person Looter-ARPG (DungeonRealms-like). 5-tier progression (lvl 1/21/41/61/81), energy-based combat, alignment system (Lawful/Neutral/Chaotic).

## Rojo limitations (learned the hard way, 2026-08)
- **Deleting a meta.json does not reset the properties it declared back to Roblox's engine defaults on an instance that already exists in Studio.** Rojo only pushes properties it currently has an opinion about; removing the declaration makes Rojo stop *managing* that property, it does not unset it. Confirmed directly: `KeybindConfig.meta.json` set `Sandboxed: true`; deleting the meta.json and re-syncing left the live `ReplicatedStorage.KeybindConfig.Sandboxed` still `true` (verified via `inspect_instance`). Had to reset it manually (`instance.Sandboxed = false` via `execute_luau`) on the already-existing Studio instance. **Potentially** version/config-dependent — not confirmed whether a from-scratch place (or a Rojo setting) would behave differently — but treat "delete the meta.json" as necessary, not sufficient, for reverting a property. Always verify with `inspect_instance` after removing a meta.json instead of assuming the deletion took effect.
- **If you see `The current thread cannot start '<Module>' (lacking capability RunClientScript/...)`**, check that module's meta.json (and any sibling/ancestor's) for `Sandboxed: true` + a `Capabilities.SecurityCapabilities` bitmask. This is real Roblox script-capability sandboxing (meant for untrusted/third-party content) and silently kills every script that requires that module at the top level — it can take down most of the game's client scripts at once if the sandboxed module is a widely-required shared config. Known offenders found 2026-08: `KeybindConfig` (fixed) and `DialogModule` + `DialogModule/sounds` (fixed) — both are core hand-authored game code, not toolbox imports, so the sandboxing there was accidental, likely a leftover from a prior syncback that stamped it broadly. `client/Enviroment/InteractiveGrass` (both copies, under `src/client/` and `src/shared/Modules/`) and `shared/Modules/init` still carry the same flag as of this writing — **potentially** intentional (toolbox-sourced grass asset) or **potentially** the same accidental stamp; not yet verified either way, left alone pending confirmation.
- **Separately spotted, not yet fixed:** `src/shared/DialogModule/` has both `init.lua` and `init.luau` (identical content, saved 12 minutes apart on 2026-08-02) — the same duplicate-instance risk the Rojo gotchas section below warns about, just within one folder instead of a `X.lua` + `X/` collision. Appears harmless today since the two files are identical, but is a landmine for the next edit that touches only one. Needs a deliberate cleanup (delete one), not yet done.

## Gameplay loop
- **Combat/Energy:** energy bar 8/s regen. 0 energy = "Low Energy Mode" (3s lockout). Walk regens; sprint/swing drains.
- **Spawners/Sharding:** radius spawners w/ cooldowns. Shard Hop cooldown by alignment: Lawful 10s, Neutral 30s, Chaotic 1m.
- **Loot:** private, visual "flying keys" mob→world chests (Food/Green, Normal/White, Elite/Purple).
- **Score:** 1 Score = 1 Loot Roll. Damage-weighted kill credit; base score 1 (world) / 4 (dungeon) to all party.
- **Dungeons:** instanced 8-player, tier keys + difficulty mods. Auto-Scrap low-tier loot.

## Key systems
- **Alignment/death-drop:** Neutral/Chaotic = PvP. Death rule (`SSS/DeathProtection`) applies to *every* death regardless of alignment today — no Lawful/Neutral leniency yet. See Death-drop section below.
- **Enchanting:** safe to +3. +4 fail (20%) breaks item (3x repair), resets to +0. Max +9. Protection scrolls block breaking, not failure. Each success multiplies the CURRENT value x1.05 (compounding): weapons dmgMin/dmgMax; armor hp + energy (Energy/s); shields hp + hps (HP/s). One formula, `RS/EnchantScrollApply.computeBonusSubStats` (also drives the station preview); never add a stat the piece didn't roll.
- **Level scaling:** dmg penalty if mob 5+ lvl above; XP penalty if mob 5+ lvl below.
- **Professions:** Mining + Spear-Fishing, tools roll substats, 2:1 Ore→Scrap.

## Dev principles
First-person only. Grim-stylized tone. No emoji/em-dash in UI. Prefer readable code over clever; combat/loot/shard logic must stay lag-free at high CPS.

---

## Two profile systems — don't mix up
| | Legacy (dead) | Modern (active) |
|---|---|---|
| Service | `SSS/PlayerDataManager` | `SSS/ProfileService` |
| Schema | `SSS/PlayerBootstrap` DEFAULT_KIT | `RS/ProfileTypes` DefaultProfile() |
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

`RS/ProfileTypes`: `DefaultProfile()`, `ValidateItemTemplate`, `VALID_SLOTS`, `GetAllowedEquipSlot(item)`.

`SSS/StatsService.RecomputeRuntimeHp(profile)` — call after every GrantItem.

## Mob system
- `SSS/MobClass` — `mob.Tier/MobID/Stats.Level/DamageTracker`
- `SSS/MobManager` — heartbeat; `ProcessMobDeath` → `LootService.onMobDied`
- `SSS/MobData` (RS) — `FindMobById(id)` → baseStats, tier
- `SSS/SpawnerService` — reads `Workspace/Spawners/MobSpawners` Part attrs (MobId/Count/Radius/RespawnDelay/Active)

**Mob combat is two tiers (2026-09-17):** tier 1 is `MobClass`'s ordinary attack state machine (in range + facing -> play `Attack` -> damage at `AttackHitFrame`), used by every mob; tier 2 is `SSS/MobMovesetBehaviour`, authored specials (combos/slams) layered ON TOP via a `Moveset` array in `MobData` + clips in `MobAnimConfig[MobID].Moveset`. Between specials the mob still swings normally. It is a **mixin**, applied after the base class is resolved, so it does not consume the single base-class slot below -- a boss can be a `DungeonBoss` and have a moveset. Kane's old proximity/"thorns" contact damage is gone; don't reintroduce per-mob touch damage. **Named elites also own the music while alive:** ids in `RS/Assets/Sounds/NamedEliteSoundtracks` (by MobID), pushed via `ZoneService.SetMusicOverride` which outranks zone music (scripted boss encounters use a separate, higher layer, `ZoneService.SetEncounterMusic` + `RS/Assets/Sounds/EncounterSoundtracks` -- never share `SetMusicOverride`, MobManager clears it to "" every tick for anyone without a live elite), and **a named elite despawns after 5 minutes out of combat** (no loot/credit; any hit taken or dealt resets `mob._lastCombatAt`, `NAMED_ELITE_IDLE_DESPAWN` in MobManager). Dying to it does NOT despawn it any more. **Its boss bar shows for every player outside a dungeon** (only one named elite can be alive server-wide); its music only reaches its spawner and players within `NAMED_ELITE_MUSIC_RADIUS` (250). **Named-elite GEAR is its own system** (`RS/NamedEliteLootDefs` + `SSS/NamedEliteLootService`, hooked in `LootService.onMobDied`), NOT the dungeon Mythic path: flat per-item chance to the killing player, dropped as world loot, at real rarities generated "high roll equivalent" (top of the rarity's base-stat range, `ItemGenerator` `options.highRoll`). `block` is now a live stat (rolled per incoming hit in `DamageService`, capped 30%). Full detail: [Named Elite Loot](./docs/named-elite-loot.md) and [Mob & NPC System](./docs/mob-and-npc-system.md).

**Crowding + threat (2026-09-29):**
- **Crowding:** no seat rings. Mobs walk straight at their target and soft-push each other apart (`CROWD_*`, spatial grid rebuilt per tick by `MobManager` via `MobClass.BuildCrowdGrid`). They never push the player.
- **Threat:** targets come from a per-player threat list (damage in, halving every 6 s; 4 s for elites and bosses). Another player takes over by beating the current target by 20% (10% for priority mobs), with no hold time, falling back down the list when the target is invalid. The leash clears it.
- Detail: [Mob & NPC System](./docs/mob-and-npc-system.md) (Crowding, Threat).

**Per-mob subclass overrides (`SSS/MobClassRegistry`):** one small class per override, inheriting everything else from its parent -- `SkeletonMobClass`/`SlimeMobClass` only override `GetHitSoundId()` (cycled 4-clip vs. random-of-3), `HoppingMobClass` only overrides `Move()`. `MobClassRegistry.Resolve(mobId)` picks ONE class per mob, in order: explicit `MobData[...].MovementClass` -> explicit `MobData[...].SoundClass` -> `JumpHeight > 0` heuristic (-> Hopping) -> Default. **Combining an existing movement override with a new sound override means subclassing the movement class, not composing two registry entries** (Resolve can only return one) -- `SlimeMobClass` extends `HoppingMobClass` (not `MobClass` directly) for exactly this reason: several unrelated mobs (Forest Goblin, Cave Bat, Shadow Wolf, ...) already reach Hopping via the JumpHeight heuristic, so a sound override can't just live on `HoppingMobClass` itself without leaking onto all of them. Set the composed class via `MovementClass` (not `SoundClass`) on that mob's `MobData` entry so it's picked before the heuristic ever runs. Hit-sound ids are hardcoded `rbxassetid://...` strings directly in these class files (not the `RS/Assets/...` icon/mesh registries -- those are for visuals, not this).

---

## Hotbar/Inventory model (current, Minecraft-style)

**This section previously said "no reserved weapon slot / `profile.equipped.Weapon` doesn't exist / `EquipItem` rejects `slot=="Weapon"`" — that was true of an older iteration and is wrong today (caught 2026-09-13 while wiring inventory-capacity/drop/trash).** Current reality, three separate slot systems, all pointing into the one `profile.inventory[uuid]` ownership dict:

- **Equip panel** — `profile.equipped[slot]`, 9 dedicated gear boxes: `Helm/Chest/Legs/Boots/Shield` (armor) + `Weapon/Bow/Pickaxe/FishingSpear` (tools). This is where your actual weapon/tool lives now, not the hotbar. `Types.GetAllowedEquipSlot(item)` derives an item's slot from `item.equipSlot`/`.type`/`.tags`; `isValidEquipSlot` in ProfileService also allows `Armor/Necklace/Ring/Potion` but nothing currently equips into those (no UI box exists for them — see `PlayerPreview.lua`'s `SLOTS` list, the actual UI-facing source of truth for which equip slots are real).
- **Hotbar** — `profile.hotbar[1..9]`, a manual quickbar (potions, etc.) the player drags items into themselves. New acquisitions never auto-land here anymore.
- **Bag** — `profile.bagSlots[1..30]` (5x6, `Types.BAG_SLOT_COUNT` -- was 27/3x9 until 2026-09-13, which didn't divide evenly into `InvSlots.lua`'s COLS=5 grid and left 3 dead cells in the last row that looked like empty slots but silently rejected every drop; bumped to 30 to make them real instead of hiding them), same uuid-pointer pattern as `hotbar`.

**Fill-first-empty-slot on every acquisition, bag first.** `SSS/ProfileService.placeItemInFirstEmptySlot(profile, uuid, player)`: tries `bagSlots[1..30]` first; only if the bag is completely full does it fall back to an **empty** equip-box slot the item can wear into (`STORAGE_EQUIP_SLOTS` — the same 9 gear slots above) — an unused gear slot is real capacity, not just something the player opts into by dragging. That fallback needs `player` (it drives `ArmorVisualsService.ApplyVisual` + `Hotbar.syncFromProfile` the same way `EquipItem` does) — omit it and the fallback is skipped, matching the old bag-only behavior. `ProfileService.HasRoomForItem`/`HasRoomForStackable`/`HasRoomForItemId`/`HasRoomForItems` mirror this exact bag-then-equip-box rule for **pre-checking** room before a grant (see WorldLootService pickup-denial below) — keep both in sync if the rule ever changes. Wired into `GrantItem`, `GrantItemId`, `mergeStackableIntoInventory`'s create-fallback, `ChestWithdrawSlot`. Public wrapper `ProfileService.PlaceItemInFirstEmptySlot(profile, uuid, player)` for outside callers that mint uuids directly: `AuctionHouseService.grantItemDirect`, `WorldLootService.GrantLootToPlayer`. **Any new direct `profile.inventory[uuid]=item` write must call this too**, or item is owned but invisible. Safety net since 2026-09-27: `rehomeOrphanedItems` (cold Load + every `BuildSnapshotPayload`) bag-places any owned uuid no slot points at, and `mergeStackableIntoInventory` only tops up VISIBLE stacks -- it used to merge into orphan stacks too, which is how F8 `T1ArmorScroll` grants "vanished" into a hidden x24 stack.

**WorldLootService denies pickup outright when there's no room** (2026-09-13) — `tryPickupFor` checks `HasRoomFor*` before granting and, if it fails, leaves the loot on the ground and fires `GameEvents/CenterFlashNotify` ("Inventory is full!", 10s per-player cooldown so standing near it doesn't spam every Heartbeat) instead of silently eating the item into an unplaced/invisible inventory slot (the old behavior).

**Never raw-assign `profile.equipped[slot]=uuid` or `profile.hotbar[i]=uuid`.** Always go through `EquipItem`/`SetHotbarSlot`/`SetBagSlot`/etc — they clear the uuid's old slot reference first. A raw assignment (e.g. an old `seedStarterIfEmpty` bug) leaves the same uuid referenced in two places at once → item renders twice, and unequip/requip can make it vanish. Every "leaves a slot" path must call `clearUuidFromBagSlots`/`clearItemUuidFromAllHotbar`/`clearItemUuidFromAllEquipped` — already wired into `EquipItem`, `SetHotbarSlot`, `ChestDepositToSlot`, `ConsumeItemId`, `SalvageGearByUuid`, `DropItem`/`TrashItem`, scroll-apply safety nets, and `DeathLootService.stripReferencesToMissing` (hotbar+bagSlots+equipped).

**Starter seed order (`ProfileBootstrap.seedStarterIfEmpty`):** explicit reorder step after granting — Sword→hotbar[1], Bow→[2], Pickaxe→[3], Spear→[4], independent of grant order. Armor still explicitly equipped via `EquipItem` (not hotbar-eligible, would otherwise sit in bag). Gated by `flags.trainingGearSeeded`, runs once ever; later sessions preserve player's own arrangement.

**Server actions:** `SetHotbarSlot`/`ClearHotbarSlot`/`SwapHotbarSlots`, `SetBagSlot`/`SwapBagSlot` (mirror pair), `EquipItem`, `UnequipItem`, `DropItem`/`TrashItem` (see below). Dispatched via `DungeonInventoryAct` RF kinds of the same name in `ProfileBootstrap`.

**Drop/Trash (2026-09-13), both gated server-side in `ProfileService.DropItem`/`TrashItem`, never trust the client:**
- `DropItem(player, itemUuid)` — denied with `"in_combat"` while `CombatStateService.IsInCombat(player)`. On success, removes the item from the profile and hands it back (3rd return value) to `ProfileBootstrap`'s `DungeonInventoryAct` handler, which calls `WorldLootService.SpawnPlayerDrop(player, item)` — spawns it on the ground with the exact same orb/fall/settle visuals as a mob drop, unowned (any nearby player can pick it up, not just the thrower), with a `PLAYER_DROP_PICKUP_DELAY` (1.5s) so the thrower's own walk-over auto-pickup doesn't instantly re-grab it.
- `TrashItem(player, itemUuid)` — denied with `"in_combat"` (same check) **and** `"not_safe_zone"` unless `ZoneService.IsPlayerInSafeZone(player)` (a Lawful zone). No world pickup — the item is just gone.
- Both are exposed client-side as `DungeonMenuNet.requestDropItem`/`requestTrashItem`, wired into the bag/equip-panel right-click `ContextMenu` in `InventoryHud/Inventory/init.lua` alongside Equip/Swap/Unequip. A denial shows via `CenterFlashUI.Show(...)` using the RF's returned error code — no round trip through a server-fired event needed for this synchronous case (contrast the passive inventory-full warning above, which has no natural request/response to hang off).

**Client (`InventoryDragController`) — two gestures, one dispatch path (`performDrop`):**
1. Click-to-pick-up/place: click occupied slot → picks up (cursor-follow ghost), click destination → places (swaps if occupied). Same slot or right-click = cancel, free (nothing mutated until the placing click).
2. Hold-and-drag: press+hold on occupied slot, move past 5px threshold, release on destination. Release under threshold falls through to gesture 1. Drag-release uses position hit-testing (`dropTargetAt`/`pointInGui`) since it isn't tied to one button's own click event.
Both gestures end at the same `performDrop`/`performHotbarToHotbarSwap`/`performAssignToHotbar` calls — never add a third path to the server.

**Hover+number-key (1-9):** while menu open, hover bag/hotbar slot + press 1-9 = same assign/swap actions. Hover state fed by `DungeonMenuUI`'s existing tooltip MouseEnter/Leave (no 2nd hover system).

**Hotbar clicks while menu open = pick/place only**, no equip-by-click (that callback was always dead code). `HotbarHud`'s "press 1-9 while menu *closed*" to equip is separate/untouched.

`DungeonMenuUI` bag render reads `profile.bagSlots[i]` directly (no client-side sorting). Every bag button gets `BagSlot` attr (even empty ones — valid drop targets).

## Debuff cleanse (`SSS/StatusCleanse`, 2026-09-30)

- **One call wipes everything:** `StatusCleanse.All(player, reason)` runs every registered handler (protected), then fires `GameEvents/StatusCleansed` to that client.
  - Built-in handlers: Miasma poison, encounter flags (`MiasmaInvulnerable`, stagger meter) and enchant statuses.
- **Called on:**
  - death (`DeathLootService.cleanse`, reason "Death")
  - every dungeon exit (`DungeonInstanceService.releaseMember`: Leave, disconnect, absence watchdog, the stuck-in-realm escape, "DungeonLeft")
  - instance end, cleared or failed ("DungeonEnded")
  - the F8 Cleanse button ("Dev")
- **New debuff:** `StatusCleanse.Register(name, fn)` for its server state.
  - Drive its client visual from a replicated attribute.
  - Anything purely client-side registers with `src/client/StatusCleanseClient`.
  - The purple Miasma tint once hung on after a dungeon because it was driven only by a one-shot event.
- **New dungeon type:** remove members through `removePlayerFromInstance`/`finishInstance` and the cleanse comes free. `InDungeon` (player attribute) is set at launch and cleared by `releaseMember`.

## Saving + wipe detection (2026-09-28)

- **Slot lists are saved gap-free.** In memory `bagSlots`/`hotbar`/`chestSlots` are numeric lists with nil gaps; `ProfileService.toSaveForm` writes them as `{"3" = uuid}` maps because a JSON list with gaps can lose entries (owned items then come back in no slot: an invisible "wipe" with equipped gear intact). Every DataStore write of the profile goes through `toSaveForm`; `Types.Reconcile` reads the string keys back. Never return the raw profile from an `UpdateAsync` again.
- **`SSS/InventoryAudit`** watches every live profile (3s + before each save) for bulk losses (`items_removed`, `slots_lost`) and records `orphans_on_load`: full record (incl. the missing item tables, for manual restore) in DataStore `InventoryAudit_v1`, a `[WIPE-ALERT]` log line, and a centre flash to online devs in all servers. A legitimate bulk removal must call `InventoryAudit.Sanction(player, reason)` first (DeathLootService does); use `InventoryAudit.Note` for breadcrumbs that ride along on reports.

## Death-drop protection (`SSS/DeathProtection`)
Decision logic is standalone, not inlined in `DeathLootService` (which only owns the drop loop/coin loss/world-loot spawn). Keep precedence:
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

**Third track: `CombatAnimConfig.FIRST_PERSON_SWING_ANIM_ID`** (2026-09-16) -- the third-person swing's big shoulder wind-up reads as "goofy" from inside the character's own head, so `CombatClient.client.lua` loads a separate, much simpler arm-only swing (see `assets/models/main character/male base model/FirstPersonSwing_Import_Instructions.md`) and picks it in `startSwing()` whenever `Player:GetAttribute("FirstPersonView")` is true -- published live by `FirstPersonViewModel.client.lua` on every perspective toggle (Keys.TogglePerspective), not read from anywhere else. Falls back to `SWING_ANIM_ID` while the field is empty, while crouched (checked first -- no first-person crouch variant exists), or in over-shoulder view. Same three-track pattern as the standing/crouch split above: one `xAttackTrack` local, loaded/destroyed alongside the others in `bindAttackCharacter`/`clearAttackCharacter`.

Gotchas: never restore `SwingAnimId` tool attribute (reverts on play-stop, becomes stale). `CombatClient.InitAnimator` must try `FindFirstChildOfClass("Animator")` then `WaitForChild` fallback — never `FindFirstChildOfClass` alone (races Roblox's async `Animate` script, creates a phantom 2nd Animator that doesn't drive the character). Player chars are R15 (Game Settings->Avatar, not the toolbar Avatar tab). **NPC rigs are R15 as of 2026-08** — the Avatar Type setting governs players only; NPCs are ordinary Models and may use any rig. Legacy toolbox NPCs are still R6; existing R6 animations auto-convert onto R15 (approximate, not broken). Bulk-spawned mobs are an open question — R15 is 15 parts/14 Motor6Ds vs 6/5, so measure before converting `SpawnerService` mobs.

## Networking (ReplicatedStorage)
| Name | Type | Dir | Purpose |
|---|---|---|---|
| `DungeonProfilePush` | RemoteEvent | S->C | full snapshot push |
| `DungeonProfileRequestSync`/`requestSync` | RF | C->S | fresh snapshot pull |
| `EquipItem`/`UnequipItem` | Event/RF | C->S | equip by uuid / unequip by slot |
| `DungeonInventoryAct` | RF | C->S | hotbar/bag/chest/enchant/drop/trash actions |
| `ItemDropNotify` | RemoteEvent | S->C | drop banner |
| `CombatRemote`/`CombatXPEvent` | Event | C->S / S->C | hit reg / XP popup |
| `CombatStateEvent` | RemoteEvent | S->C | "combat"/"safe" + seconds, drives `CombatTimerClient` |
| `GameEvents/CenterFlashNotify` | RemoteEvent | S->C | center-screen flash text (e.g. "Inventory is full!"), rendered by `CenterFlashUI.lua` |
| `GameEvents/PlayEffectSfx` | RemoteEvent | S->C | server-decided one-shot sound, by `SoundEffects` registry KEY (never an asset id); played by `SfxNetClient` via `SfxService` |

**Any new purchase/shop client must call `DungeonMenuNet.requestSync()` after a successful action.** The implicit `DungeonProfilePush` broadcast can race or get dropped as stale — `BankClient`/`SkillsTabClient`/`AuctionHouseClient`/`BlacksmithClient` all do this defensively; `MerchantClient`/`ShopClientBase` originally didn't (fixed).

## UI entry points (StarterPlayerScripts)
`DungeonMenuUI` (panel layout+redraw, fonts via `qsFont`/`QS` at top of file), `DungeonMenuNet` (snapshot cache, `_seq`-aware merge), `LootClient`, `ItemTooltip`, `SkillsTabClient` (uses `local refresh` forward-declare pattern — see gotcha below), `MerchantShopClient` (routes ProximityPrompt by NpcType), `HearthstoneClient`.

## ProfileMenus (React) UI system

The newer React-lua UI — separate from the legacy `DungeonMenuUI` system above — is where Inventory/Skills/Stats/Hearthstone/Party tabs and the bottom quick-nav carousel actually live now. Key files, all under `src/client/InventoryHud/Inventory/` unless noted:

- `QuickNav.lua` — the quick-nav icon carousel (tab switcher) and its hover tooltip. `SIZE_MULTIPLIER` (currently 1.4) scales the whole carousel's icons/backing in one place.
- `Inventory/init.lua` — the tab content area (`ContentArea`); `QUICKNAV_H`/`QUICKNAV_UP_SHIFT`/`CONTENT_UP_SHIFT` control how much vertical room the carousel takes and how far up the whole stack sits.
- `PanelShell.lua` — shared wrapper every tab panel (`PartyPanel`, `StatsPanel`, `HearthstonePanel`, the inventory tab) renders through; each panel just fills whatever `ContentArea` gives it, so a "gap" or "too small" symptom across multiple tabs is almost always one root-cause fix in `Inventory/init.lua`'s `ContentArea` sizing, not four separate panel bugs.
- `RS/ProfileMenusState.lua` — shared open/closed state, plus (2026-09-13) the carousel's live screen-position broadcast, see pattern below.
- `src/client/XpHud/XpHud.luau` — separate system (XP bars + kill orb-burst effect), see its own entry below.

**Carousel-anchor broadcast pattern (added 2026-09-13):** rather than hand-duplicating the carousel's screen position as constants in every HUD element that needs to hang below it (`HealthClient.client.lua`, `characterscripts/EnergyClient.client.lua`), `QuickNav.lua` publishes its own real rendered position via `ProfileMenusState.SetCarouselAnchor(Vector2)` — a `GetPropertyChangedSignal("AbsolutePosition"/"AbsoluteSize")` listener on its container — and dependents read `ProfileMenusState.GetCarouselAnchor()` and position themselves with `AnchorPoint = (0.5, 0)` off that point. **Use this pattern for any future "hang UI relative to another dynamically-positioned UI element" need** — publish real geometry once from the component that owns it, don't re-derive position math per dependent.

**One UI at a time (`RS/InteractionLock`, the UI stack, 2026-09-29):**
- **Blocking overlays:** the world map, the Enchanting Station and the cleanse channel `Acquire` the lock. While one is up, menu hotkeys stand down; gameplay binds like dash keep working.
- **Switchable menus:** inventory, party panel and settings call `OpenMenu(name, close)` / `MenuClosed(name)`, so opening one closes the other. They refuse to open while a blocking overlay holds the lock, and close themselves when one takes it.
- **New screens:** any new menu or overlay must join one of these two groups.
- **Vitals hide by default (2026-09-30):** every `OpenMenu`/`Acquire` hides the HP/energy/hunger cluster (`RS/HudVitals`) while up. A screen where health matters passes `{ keepVitals = true }`: the inventory menu and the cleanse channel do. The Tab menu hides them on every tab except Inventory (owner "ProfileMenuTab"). The valve maze registers nothing, so it keeps them.
- **Settings screen:** centred, Minecraft-style page stack in `SettingsClient` (`makePage`/`navButton`/`makeSlider`/`makeBar`). Every page ends in Done (back one level; Done on the root closes Settings, Esc = Done). New setting: add a bar to a page; new category: `makePage` + a `navButton` on the root.

**Cursor (2026-09-30):**
- **Locked means hidden.** `client/CursorIcon` hides the Roblox arrow whenever the mouse is locked (LockCenter). It runs every frame after every other cursor writer (render priority Last + 20).
- **Engine bug workaround.** It also flips `MouseIconEnabled` true for one frame, then false, at startup and on window refocus. Without that, Roblox can draw the arrow even while the property is false.
- **New free-cursor UIs** keep using `RS/CursorUtils` (acquire/release), or `RS/CursorManager` for hold-to-free; never leave the mouse locked with the icon on.
- **Crosshair:** `client/Crosshair` draws it, shown only while the mouse is locked and no camera override is active. Its on/off button sits in `RS/HudQuickNav` (`ORDER.Crosshair`), saved as `hud.crosshair` through `UpdatePlayerSettings`/`SettingsRanges`.

**Taking over the camera (cutscenes, menu pans):** `FirstPersonViewModel` re-asserts the camera every frame, so an override owner must `RS/CameraOverrideState.SetActive(true)` first and `SetActive(false)` to hand back; `RequestLook(direction)` before handing back makes the first-person camera return facing that way instead of snapping to the old view. Reference implementation: `MiasmaDropCutscene.luau` (server-clock-timed shots, letterbox, fade-hidden handback); boss title-card art is registered in `RS/Assets/Images/TitleCards`.

**Bottom-left HUD stack (added 2026-09-26):** small always-on status readouts (combat timer, dungeon run timer) live in one vertical stack, `RS/HudBottomLeftStack` -- `Slot(name, ORDER.x)` returns an auto-sized Frame (higher order = lower on screen; `Combat` = 100 always owns the very bottom, `Dungeon` = 90 above it), `Pill(...)` builds the shared dark icon+text plate. Hidden slots collapse and the rest slide down. XpHud's Mining/Fishing bars (same corner, outside the stack) offset themselves by `GetHeight()`/`HeightChanged`. Add new bottom-left readouts as slots here, don't hand-position them. Icons in `RS/Assets/Icons/Hud/HudIcons` (`HOURGLASS` empty = icon hidden, text only).

**UIScale double-scaling gotcha:** a Roblox `UIScale` scales the offset-based `Size`/`Position` of every descendant, not just its own direct children. A Frame that computes its own `Position` from already-resolved real screen pixels (e.g. `AbsolutePosition`/hover math, like `QuickNav.lua`'s `HoverTooltip`) gets shrunk a second time if it lives anywhere under an ancestor `UIScale`. Symptom: the element renders collapsed toward the container's corner instead of at the intended pixel offset (can land fully off-screen). Fix: divide the real-pixel offset by the same scale factor before assigning to `Position` — mirrors the existing `CounterScale = UIScale(1/designScale)` trick already used to un-shrink a tooltip's own child content (that one only fixes size; apply the same idea to `Position` too).

## Character customization (wardrobe, 2026-09-27)

- **Data:** `RS/Assets/Appearance/AppearanceOptions` (categories, options, the skin ramp, `Sanitize`), saved in `profile.appearance`. Add a hair style etc. as one registry entry; the menu draws from it.
- **Apply:** `RS/AppearanceApply.Apply(character, appearance)` is the ONLY place appearance touches a model, used by the server (`SSS/AppearanceService`, every spawn + after save) and the client preview. Skin tone = `Hero_Character.Color`: the body texture (88378186645210, source `assets/models/main character/male base model/male model texture img/male model texture skinmask.png`) has see-through skin, applied as a `SurfaceAppearance` with `AlphaMode = Overlay` so the MeshPart colour shows through. NOT via `MeshPart.TextureID`: its alpha is ignored for this (2026-09-28, skin rendered as raw black/white shading). Never re-tint by swapping textures.
- **Wardrobes:** any Workspace model named `...Wardrobe` (or tagged `Wardrobe`) gets its prompt renamed `WardrobePrompt`; `src/client/Wardrobe` opens on it: a client-only grass stage far above the map (`WardrobeStage`), a clone of the character in idle, camera via `CameraOverrideState`, menu `WardrobeMenu`. Deliberately NOT the brown/gold UI style.
- **Full-screen moments hide the HUD through `src/client/HudHider`** (ref-counted; see its header for the deferred-signal trap).

## World map / minimap (2026-09-29)

- **Files:** `RS/MinimapConfig` (grid, tuning, the maths both sides share), `SSS/MinimapService` (saves exploration + discovery, bakes colours), `src/client/Minimap/` (corner minimap + M expanded map, two `MapView`s over the same chunk images).
- **Grid:** 4-stud cells in 64x64 chunks. Each chunk is one `EditableImage` on the client and one base64 bitset in `profile.map.revealed[chunkKey]`. The map only exists over the zones' bounding box + 200 studs, so dungeon realms never create chunks.
- **Colours:** raycast top-down by the server on first request (`MinimapChunkRequest`) and cached, so there's no bake step and the map follows the build.
  - Textured meshes fall back by Material, or to foliage green by name.
  - Set a Color3 attribute `MapColor` on a part or model to force its colour.
- **Discovery:** `ZoneService.SetDiscoveryHandler` puts `discovered = true` on `ZoneEntryNotify`; ZoneClient then shows REGION DISCOVERED and the map pulses the outline.
- **Oakhaven:** discovered and fully revealed by default (`MinimapConfig.DefaultDiscovered/DefaultRevealed`, by zone NAME).
- **Profile push:** `profile.map` is stripped from the profile push; it rides on `MinimapStateRequest` instead.

## XpHud (`src/client/XpHud/XpHud.luau`)

**Skill XP is server-authoritative (2026-09-27):** the saved values are `profile.stats.combat/mining/fishing` (`ProfileService.AddSkillXP`, which returns the post-gain `{level, xp, levelsGained}`). The client's `SkillXPShared` is only a display cache: `SkillXPSync.client` seeds it from every profile snapshot, and the XP events carry the server totals (`ApplyServerGain` SETS, never adds). Any new XP source must go through `AddSkillXP` and forward its totals, or the display drifts from the save again (the old bug: every rejoin showed level 1).

React-lua Combat/Mining/Fishing XP bars, replacing three old polling scripts. Reads `SkillXPShared` only — XP accumulation/level-ups still live in the original scripts that write into it, deliberately, to keep the migration reversible. Combat-only `XpGainBurst` component: a scatter of light-blue orbs pops around the bar on a kill and funnels inward, plus (2026-09-13) a brief white flash on the bar itself once the orbs have mostly converged. All burst tuning — orb count/spread/duration/flash timing — is a handful of constants at the top of the file (`BURST_ORB_COUNT`, `BURST_SPREAD_X/Y`, `BURST_CONVERGE_TIME`, `FLASH_*`); tune there, not by touching the render/effect logic.

## Enchant scrolls (`RS/EnchantScrollApply`, entry via `ProfileService.ApplyEnchantScroll`)
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

## Inventory item borders: ItemSlot vs PlayerPreview (recurring drift)

`RarityBorder` (`src/client/InventoryHud/Inventory/RarityBorder.lua`) is the one shared
stroke component, but it's called from **two separate, independently-maintained sites**
that must be tuned to match by hand -- nothing enforces parity:

- `ItemSlot.lua` -- bag/inventory grid slots (used by `InvSlots`).
- `PlayerPreview.lua`'s `EquipmentSlot` -- the 8 equipped-gear boxes. Despite `ItemSlot.lua`'s
  own header comment claiming it's "used by both InvSlots (bag) and PlayerPreview (equip
  boxes)", `PlayerPreview` actually reimplements the same icon/border/legendary-glow logic
  itself rather than rendering `ItemSlot` -- that comment is aspirational, not current fact.

This has drifted at least twice: equipped items rendered with a bold border while the same
item sitting in the bag looked borderless/thin. Both times the fix was bumping `ItemSlot`'s
`RarityBorder` `thickness` props to match `PlayerPreview`'s (currently **8**, with the
`selected`/currently-held state a level above that at **10**). If you touch either file's
border thickness, update the other one too, and check both still visually match in Studio.

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

**Correction (2026-09-28): `src/starterpack` is NOT actually mapped** -- `default.project.json` has no StarterPack entry, so the tool scripts (`BowClient`, `MiningScript`, `FishClient`...) live only in the place file, and several `src/starterpack` copies are stale, much older versions (MiningScript: 7 KB on disk vs 23 KB live). Edit tool scripts in Studio (ScriptEditorService) and save the place; don't trust or edit the disk copies.

A duplicate `roblox/` tree (older dump of the same scripts) was deleted 2026-08. If it reappears, it is stale — do not read from it.

**Toolchain is Rokit, not Aftman.** `rokit.toml` is the source of truth; Aftman is unmaintained (its author left the Roblox ecosystem). Rojo must be **>= 7.7.0 final** — syncback shipped there, and 7.7.0-rc.1 predates several syncback fixes.

**Direction of truth:**

- Disk owns **scripts and data** (`src/`).
- Studio owns **geometry, terrain, instance trees** — Workspace, Lighting, StarterGui, ServerStorage, StarterPack tools. These are in `syncbackRules.ignoreTrees`.

**`StarterPlayer` is a mixed tree** — `StarterCharacterScripts` and `StarterPlayerScripts` are Rojo-owned (`src/characterscripts` / `src/client`), but `StarterPlayer.StarterCharacter` itself has no `$path` entry anywhere in `default.project.json`. If it exists, Roblox's built-in behavior clones it for every spawning player instead of their real avatar — no script drives that swap, it's just engine default behavior triggered by the model's presence. There is nothing on disk to open for it; it lives only in the `.rbxl`, edited directly in Studio (same pattern as `ServerStorage.ArmorModels`/`ServerStorage.LootDropVisuals`). `StarterPlayer`'s own `$properties` block sets `LoadCharacterAppearance: false` — without that, Roblox still layers the player's real avatar clothing/body on top of the custom `StarterCharacter` rig on spawn. The current `StarterCharacter` is the custom-scaled R15 base rig (Head/UpperTorso/limbs/Humanoid/HumanoidRootPart), the same one measured for armor-offset tuning.

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
