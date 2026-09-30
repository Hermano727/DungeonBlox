# Dev Tools

In-game developer tools: what each one does, how it's gated, where its code lives, and the traps in each.

## Who can use them

**Add or remove devs in `RS/DevRoster.IDS` only.** Everything else reads from it: `DevClient`, `DevService`, `DayNightService`, `UIDevTool`, and `HearthstoneConfig.ADMIN_IDS`, which is just `DevRoster.IDS`. Hand-copying the list is how it drifted before (DevClient's copy was empty, so F8 silently did nothing on live servers).

`DevRoster.IsDev(player)` is true for anyone on the list **and for everyone in a Studio session**. So local testing never needs a roster edit, and everyone in Team Create counts as a dev.

The client-side check only decides whether the UI gets built. It is **not** the security boundary. Every privileged remote re-checks on the server, so a player who fires the remotes directly gets rejected the same way. The one exception is under Known issues.

## Keybinds

All binds live in `RS/KeybindConfig`, except the dungeon-run keys.

| Key | Tool | Script | Gate |
|---|---|---|---|
| **F8** | DevPlacer (main dev panel) | `client/DevClient.client.lua` | DevRoster |
| **F7** | Hearthstone Dev Panel | `client/HearthstoneDevMenu.client.lua` | ADMIN_IDS (= DevRoster) |
| **F10** | Item Grant menu | `client/ItemGrantDevMenu.client.lua` | ADMIN_IDS (= DevRoster) |
| **F6** | UIDevTool (UI art / armor weld nudging) | `client/UIDevTool.client.lua` | DevRoster |
| **F6 / F7** | Start / end a T1 dungeon run | `client/DungeonRunHud.client.lua` | **None** (see Known issues) |
| Esc | Closes whichever panel is open | `Keys.CloseMenu` | |

**Don't bind new tools to F9, F10, or F11.** Studio's voice/mic panel takes F9, F10 is already the Item Grant menu, and F11 is the OS/browser fullscreen bind.

---

## F8: DevPlacer

The main dev panel. It's a left-docked panel with a row of mode tabs, a section for the active tab, one shared confirm button, and a **Managed Spawners** list.

- **Client:** `client/DevClient.client.lua` (the whole UI, input handling, and zone drawing)
- **Server:** `server/DevService.server.lua` (creates the `GameEvents/Dev*` remotes and validates every request)
- **Persistence:** `MobDevSpawnStore`, `NpcDevSpawnStore`, `ZoneDevStore`, all built on `DevStoreListBase` (one DataStore key per place: `place_<PlaceId>`)

### Tabs

The tab row is data-driven. Add a `{ key, label, color, colorOff }` entry to `MODES` and the buttons lay out and wrap on their own. `immediate = true` means the tab's button fires right away instead of entering click-to-place.

| Tab | Kind | What it does |
|---|---|---|
| **MOB** | click-to-place | Places a mob spawner camp: mob type, Count (1-20), Respawn delay (1-300s), Activation radius (10-500), Zone name. Ordinary mobs only -- named elites live in their own tab. |
| **ELITE** | immediate | Spawns a named elite in front of you with the rise-from-ground intro and boss bar, through the same path a real elite roll uses (`MobManager.ForceSpawnNamedElite`). Lists every `MobData` entry with `IsNamedElite` (Kane today), so a new one appears with no dev-tool edit. Only one named elite may be alive server-wide, so the spawn is refused while one is up. **Dungeon bosses** (`MobData` `IsBoss`, e.g. `MiasmaBoss`) share this tab for playtesting and spawn through `MobManager.ForceSpawnBoss` instead: 45 studs ahead, real stats and class (`DungeonBoss` AggroStart + attack), no dungeon run, no ceiling intro, no boss bar. A new request replaces the previous dev boss and unregisters its throwaway spawner. Killing one outside a run ends nothing -- LootService's boss cash-out returns early with nobody in a run. |
| **NPC** | click-to-place | Places an NPC marker: NPC type, display name, unique ID. |
| **ZONE** | draw polygon | Draws a zone polygon with a name, alignment (Lawful/Wilderness/Chaotic), banned player alignments (entry flash), optional elite-mob zone and elite mob, and optional music ID. |
| **TIME** | immediate | Sets the day/night clock by hour/minute or a preset (Dawn/Noon/Dusk/Midnight). Setting a time pauses the auto cycle; **Resume Auto Cycle** restarts it. |
| **GEAR** | immediate | Rolls procedural gear through `ItemGenerator` (the same engine mob drops use): kind (Random/Weapon/Armor), subtype, level, rarity, substat count, count (1-20), and **Force Substat** -- pin a substat to an exact value (`critical @ 100` for a guaranteed-crit test weapon), or **+** it onto a list to pin several at once (crit AND lifesteal AND block). |
| **ITEMS** | immediate | An icon grid of every entry in `ItemDefinitions.Items`. Set a quantity and click an icon to grant it. |
| **MYTHIC** | immediate | Grants the real hand-authored mythic from `MythicItemDefs` with its fixed substats, not a random roll labeled Mythic. |
| **PROFILE** | immediate | Sets your Combat / Mining / Fishing level exactly and refills HP / energy / hunger (`client/DevProfileTab`). |
| **MAP** | immediate | **Reset My Map** (click twice): forgets your discovered regions and explored ground, then re-discovers the region you're in, which replays the discovery banner and peek (`client/DevMapTab`, `MinimapDevAction`). See [World Map & Minimap](./minimap.md). |

**MOB only lists fully modeled mobs.** `MOB_ID_WHITELIST` in `DevClient` (currently `PlainsSlime`, `SmallSkeleton`) filters the placement list. `MobData` isn't changed, and existing spawners still use every MobID. Add a mob to the whitelist once it has a real model.

**MOB and ELITE are deliberately separate.** A named elite is a single server-wide world event with a boss bar and its own soundtrack, not a camp you place a radius spawner for. They used to share the MOB tab, where "Force Spawn Elite" fired whichever ordinary mob happened to be selected. `DevService` now refuses a `NamedElite` spawn for any mob without `IsNamedElite`, so the split is enforced server-side, not just hidden in the UI.

**The force-substat picker reflects `ItemConfig`.** It reads `ItemConfig.GetSubstatEffects(kind, weaponType)` -- the shared "what can sit on this kind of item" pool, which spans `WEAPON_EFFECTS`, `ARMOR_EFFECTS` and `ARMOR_BONUS_EFFECTS` (block, reflect, dodge...) and applies the melee/ranged filter. Add or remove a substat in `ItemConfig` and the dev tool follows on its own; it should never need a matching edit. `ItemGenerator` validates forced ids against that same pool, so anything the picker offers can actually be forced -- including the bonus-only stats that never roll randomly.

**GEAR/MYTHIC are T1 only.** The server rejects any level above 21 with `"T2 and above not implemented"` (`ITEM_SPAWN_TIER1_MAX_LEVEL` in `DevService`).

**ITEMS and MYTHIC need no code changes for new content.** ITEMS reflects `ItemDefinitions.Items` and MYTHIC reflects `MythicItemDefs.Items`, so new entries there appear automatically.

**GEAR and ITEMS used to be one tab.** Its shared confirm button stayed wired to the gear spawn, so pressing it after picking a catalog item spawned random gear. That's why ITEMS hides the shared button and has each icon grant itself. Keep new catalog-style tabs off the shared button.

### Placing mobs and NPCs

1. Pick the tab and fill in its fields.
2. Click **Click to Place**. A ghost follows your aim: red cylinder sized to the activation radius for mobs, blue for NPCs.
3. Left-click in the world to place it. Placement mode then ends and the list refreshes.

### Drawing zones

1. ZONE tab, then **Draw Zone**.
2. Add corners with **E** or left-click (minimum `ZoneConfig.MIN_POLYGON_POINTS`, currently 3; maximum `MAX_POLYGON_POINTS`). **Backspace** undoes the last corner. After the first corner, all corners snap to its height. A live edge follows your aim from the last corner.
3. To finish, do one of these:
   - **Place a corner on top of an existing corner.** Once there are 3+ corners, aiming within `ZONE_SNAP_RADIUS` of a corner turns the ghost and live edge green, and placing there closes the shape and saves it. Snapping onto corner *k* (not the first) saves only corners *k* through the last, so earlier corners are dropped.
   - **Enter** or the **Finish Zone** button.
   - **Clear** removes all corners; **Esc** cancels the draw.

While drawing (or flying), a HUD strip at the top of the screen shows the corner count, the controls, and the last status message, so feedback stays visible with the panel hidden. After a successful save the panel reopens so the saved yellow outline and its Managed Spawners row are visible, and the HUD shows "Zone saved" for a few seconds.

**Dev keys ignore `gameProcessed`** (they only back off while a TextBox has focus), and zone clicks hit-test the panel instead of trusting `gameProcessed`. Other systems (ProximityPrompts on E, first-person GUI) were marking these inputs processed, which silently ate corner and finish presses.

### Fly

Fly is its own toggle, independent of drawing: the **Fly** button in the ZONE tab or **F** (`Keys.DevToggleFly`) while the panel is open, drawing, or already flying. **WASD** to move, **Space** up, **Ctrl/C** down (`FLY_SPEED` = 90). It drives a `LinearVelocity` constraint on the HumanoidRootPart plus `PlatformStand`. It used to set `AssemblyLinearVelocity` once per rendered frame, which let gravity win between 240Hz physics steps and caused a slow constant sink.

**Hide Panel** (available while drawing or flying) hides the panel and locks the mouse so you can look around; F8 brings it back without losing corners. Closing the panel with F8/X mid-draw keeps the drawing in progress (Enter still finishes). Closing it outside a draw exits the tool, which also turns fly off. Respawning turns fly off.

### Mouse handling while the panel is open

The panel frees the cursor. **Hold right mouse** to temporarily lock it back to center and look around.

### Managed Spawners list

Lists what the **active tab** manages, sorted by distance from you, with coordinates: ZONE lists zones, MOB lists mob camps, NPC lists NPC markers. Tabs that place nothing (TIME/GEAR/ITEMS/MYTHIC) hide the list. **x** deletes an entry.

**Your own position** sits right-aligned on that list's header (`YOU  x, y, z`), so the distance-sorted rows below have something to be relative to. It ticks at 4Hz from a plain `task.spawn` loop at the bottom of `DevClient`, deliberately NOT from `refreshList` -- that function round-trips to the server for the entire list, which is far too heavy to run just to move a coordinate readout. It hides itself whenever the list does.

Zone rows have a second line of in-place editors, all going through the one `DevUpdateZone` remote (no redraw needed):

| Control | Does |
|---|---|
| name box + **Rename** | renames the zone (trimmed, 1-40 chars) |
| alignment button | cycles Lawful -> Wilderness -> Chaotic and saves immediately |
| music ID box + **Save** | sets or clears the looped soundtrack |

### World visuals

The markers are red neon cylinders (mobs) and blue neon cylinders (NPCs) with billboard labels, under `Workspace.Spawners/DevMobMarkers` and `Workspace.Spawners/NPCSpawners`. Yellow zone outlines come from `client/ZoneDevVisuals.client.lua`, which only shows them while the `DevPlacerOpen` player attribute is true.

### Remotes (`ReplicatedStorage.GameEvents`, created by DevService)

| Remote | Type | Purpose |
|---|---|---|
| `DevPlaceSpawner` | Event | `SpawnerType` = `Mob` / `NPC` / `Zone` / `NamedElite` |
| `DevDeleteSpawner` | Event | Delete by `{SpawnId}`, `{Type="Zone", ZoneId}`, or a marker Part |
| `DevListSpawners` | Function | Rows for the Managed Spawners list |
| `DevPlaceZone` | Function | Saves a drawn polygon and returns `{ok, zone}` or `{ok=false, error}` |
| `DevUpdateZone` | Function | Edits an existing zone: any of `Name` / `Alignment` / `MusicId` |
| `DevSpawnItem` | Function | GEAR and MYTHIC spawns |
| `DevDayNightControl` | Function | `action` = `Get` / `SetTime` / `Resume` (server: `DayNightService`) |
| `ReplicatedStorage.DevGrantItem` | Function | ITEMS tab and the F10 menu (server: `ProfileBootstrap`) |

### Persistence

Placed camps, NPC markers, and zones survive Studio Stop and server restarts through DataStores:

| Store | DataStore name |
|---|---|
| `MobDevSpawnStore` | `MobDevSpawns_v1` |
| `NpcDevSpawnStore` | `DevNpcSpawns_v1` |
| `ZoneDevStore` | `DevZones_v1` |

- **Studio persistence requires** Game Settings -> Security -> **Enable Studio Access to API Services**. Without it, placements are session-only: they work until you press Stop.
- On boot, `MobManager` re-registers saved mob camps and `DevService` rebuilds the markers.
- Editing a ModuleScript's source during Play doesn't survive Stop. That's why these use DataStores instead of writing into scripts.

**The persistence headers disagree with the code.** The headers say live-server persistence only turns on with a `ServerStorage` BoolValue (`MobDevSpawnsPersistInLive` / `ZoneDevPersistInLive`). `DevStoreListBase.persistenceEnabled()` is hardcoded `true` and never reads that value, so **live servers persist too**. This predates the `DevStoreListBase` refactor and was kept as-is on purpose. Pick one behavior before relying on either.

---

## F7: Hearthstone Dev Panel

Adds and deletes hearthstone teleport locations in the `HearthstoneRegistry` DataStore. Fill in a name and cost, use **Capture Pos** to grab where you're standing, then **Add Location**. **Current Locations** lists existing entries with delete buttons; seeded defaults are tagged `SEED`.

- Remotes: `HearthstoneAdminAdd`, `HearthstoneAdminDelete`, `HearthstoneSync`
- **Stale header:** the script's top comment still says it opens with F8. It moved to **F7** when it collided with DevPlacer. `KeybindConfig` is correct.

## F10: Item Grant menu

Grants any item by itemId, or Coins, to yourself through `DevGrantItem`. It has a free-text itemId box with a quantity (1-9999), plus **Quick Grant** rows for Key Fragments, Dungeon Keys, Currency, Consumables, and Mythics. The special id `"Coins"` adds directly to `profile.currencies.Coins`.

- **Stale header:** the script's top comment says F9. The real bind is **F10**.
- F8's ITEMS tab uses the same `DevGrantItem` remote, so the two overlap. The F10 menu is the older one.

## F6: UIDevTool

A small overlay for nudging values live. It never talks to the server. **`;`** switches between two modes:

- **UI mode** tunes decorative art registered through `RS/UIDevTuning.Register()`. Any new panel that registers shows up here automatically.
- **Model mode** tunes the worn-armor Motor6D welds on your own character (C0 offset, rotation, mesh scale).

Tuned values reset on the next equip or restart. **Press Enter** to print a snapshot, then hand-copy the numbers into the owning panel's `Register()` call or into `ArmorVisualsService`.

| Keys | UI mode | Model mode |
|---|---|---|
| `;` | Switch mode | Switch mode |
| `,` | Previous registered UI | Previous equipped slot |
| `.` | Next registered UI | Unused (opens chat) |
| `'` | Next target within that UI | Next equipped slot |
| Y / H / G / J | Offset up/down/left/right, 1px (Shift = 10) | Local X/Y, 0.02 studs (Shift = 0.2) |
| N / M | | Local Z, 0.02 studs (Shift = 0.2) |
| U / I | | Pitch -/+5 degrees (Shift = 45) |
| K / L | | Roll -/+5 degrees (Shift = 45) |
| `-` / `=` | Scale -/+0.01 (Shift = 0.05) | Mesh scale -/+2% (Shift = 10%) |
| `[` / `]` | Rotate -/+5 degrees (Shift = 45) | Yaw -/+5 degrees (Shift = 45) |
| Backspace | Reset selection | Reset selection |
| Enter | Print snapshot | Print snapshot |
| F6 | Close (tuning stays live) | Close |

Why the keys are odd: `/`, `.`, Page Up/Down, arrow keys, `P`, and Tab were all tried first. Each one was taken by chat, the camera, or another menu before the tool received the input.

---

## Zone alignment: "Wilderness", not "Neutral"

A zone's middle alignment is **stored** as `"Neutral"` and **shown** as `"Wilderness"`, via `ZoneConfig.ALIGNMENT_DISPLAY_NAMES` / `ZoneConfig.DisplayAlignment(a)`. "Neutral" is being reserved for the player-facing PvP toggle that is coming later, so the two cannot share a label.

Only the zone's own alignment is relabelled. **Player** alignment keeps the name Neutral everywhere (party tags, the ZONE tab's banned-alignment set, `ShardConfig`). Nothing persisted or sent on the wire changed, so existing saved zones are unaffected. Display sites wired up: the ZONE tab buttons, the Managed Spawners row label, the dev zone outline billboard (`ZoneDevVisuals`), and the zone entry banner (`ZoneClient`).

## Known issues

- **The dungeon-run dev keys have no gate at all.** `DungeonRunHud.client.lua` fires `DungeonRunStart` on F6 and `DungeonRunEnd` on F7 for every player, and `DungeonRunService`'s handlers don't check `DevRoster`. `DungeonRunEnd` pays out as `"cleared"`, so any player can start and immediately cash out a run for free loot rolls. They're also hardcoded `Enum.KeyCode` literals rather than `KeybindConfig` entries.
- **F6 and F7 are double-bound for devs.** F6 opens UIDevTool *and* starts a dungeon run. F7 opens the Hearthstone panel *and* ends the run.
- **Persistence headers vs. code:** see the Persistence section above.
- **Two separate NPC paths:** F8 NPC markers are a second, independent source of NPCs alongside the `<Type>Bootstrap` scripts, and a known source of duplicate NPCs. See [Mob & NPC System](./mob-and-npc-system.md).
