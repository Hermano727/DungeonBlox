---
title: UI & Networking
tags: [ui, networking, client]
aliases: [Fonts, Remotes, Zone Theming]
---

# UI & Networking

## UI entry points (StarterPlayerScripts)

`DungeonMenuUI` (panel layout+redraw, fonts via `qsFont`/`QS` at top of file), `DungeonMenuNet` (snapshot cache, `_seq`-aware merge), `LootClient`, `ItemTooltip`, `SkillsTabClient` (uses `local refresh` forward-declare pattern — see [Studio & Tooling Gotchas](./studio-tooling.md)), `MerchantShopClient` (routes ProximityPrompt by NpcType), `HearthstoneClient`.

Font handling note: fonts are set via `qsFont`/`QS` constants at the top of `DungeonMenuUI`, not scattered inline. Quicksand's "Temp read failed" console message in Studio is expected/harmless (works in real game) — the fix was keeping `FontFace` assignment wrapped in `pcall` (see [Studio & Tooling Gotchas](./studio-tooling.md)).

## ProfileMenus (React) UI system

The newer React-lua UI — Inventory/Skills/Stats/Hearthstone/Party tabs and the bottom quick-nav carousel — lives separately from the legacy `DungeonMenuUI` system above, under `src/client/InventoryHud/Inventory/`:

- `QuickNav.lua` — quick-nav icon carousel (tab switcher) + hover tooltip. `SIZE_MULTIPLIER` scales the whole carousel's icons/backing in one place.
- `Inventory/init.lua` — tab content area (`ContentArea`); `QUICKNAV_H`/`QUICKNAV_UP_SHIFT`/`CONTENT_UP_SHIFT` control vertical layout of the carousel + content stack.
- `PanelShell.lua` — shared wrapper every tab panel (`PartyPanel`, `StatsPanel`, `HearthstonePanel`, the inventory tab) renders through and fills; a layout symptom (gap, wrong size) shared across multiple tabs is almost always one fix in `Inventory/init.lua`'s `ContentArea` sizing, not a per-panel bug.
- `RS/ProfileMenusState.lua` — open/closed state + the carousel's live screen-position broadcast (see below).
- `src/client/XpHud/XpHud.luau` — separate: Combat/Mining/Fishing XP bars + the kill orb-burst effect, tuned via constants at the top of the file (`BURST_ORB_COUNT`, `BURST_SPREAD_X/Y`, `BURST_CONVERGE_TIME`, `FLASH_*`).

**Carousel-anchor broadcast pattern:** `QuickNav.lua` publishes its own live screen position via `ProfileMenusState.SetCarouselAnchor`/`GetCarouselAnchor` (a `GetPropertyChangedSignal("AbsolutePosition"/"AbsoluteSize")` listener on its container), and `HealthClient`/`EnergyClient` read it to hang the HP/energy/hunger cluster beneath the carousel wherever it currently sits. Use this pattern — publish real geometry once from the component that owns it — for any future UI that needs to hang off another dynamically-positioned element, rather than duplicating position constants across files.

**UIScale double-scaling gotcha:** a `UIScale` re-scales the offset-based `Position`/`Size` of every descendant, not just its own direct children. A child that computes its own `Position` from already-resolved real screen pixels (e.g. hover-tooltip placement off `AbsolutePosition`) gets shrunk a second time if it lives under an ancestor `UIScale`, and collapses toward the container's corner. Fix: divide the real-pixel offset by the same scale factor before assigning to `Position`.

## Journal (Tab menu -> Journal)

- **Layout:** `Journal/Sidebar` (top-level pages) beside `Journal/Book` (leather cover, two pages, spine, bookmark tabs on the top edge). A page is a component that renders a `Book`; register it in `JournalPanel.lua`'s `PAGES`.
- **Parts:** `Journal/Parts` has `ArtFrame`, `ChromeButton`, `Heading`, `Divider`, `HelpIcon`, `Gem`, `BarTrough` and `SplitBar`, plus `Journal/ScoreChart`. Each draws its art from `RS/Assets/Images/JournalUI` when uploaded, else a flat stand-in of the same size.
- **Colours:** only `Journal/Style` picks them. Once `page_paper` art exists, the pages switch to dark ink text.
- **Loot Score** (`LootScorePage.lua`):
  - The landing spread is all-time: score, overworld / dungeon split, runs, dry streaks.
  - "Activity >" goes one level deeper: windows 1H / 24H / 7D / 30D, drops by rarity, score chart, comparison with your average window, and luck (drops found vs expected).
- **Data:**
  - Per-tier totals are in `profile.stats.tracking` (`scoreByTier`, `dungeonScoreByTier`, `runsClearedByTier`).
  - Activity history lives in `profile.activity` (`RS/JournalActivity`: 5-minute buckets for 2 h, hourly for 7 d, daily for 90 d). It's stripped from the profile push and served per window by `GameEvents/JournalRequest` (`SSS/JournalService`).
  - "Expected" drops are exact: `LootPityService.ResolveScore` sums each roll's real chance.
  - F8 Profile tab has "Seed activity" / "Clear activity" for testing.

## UI art pipeline

1. **Generate:** the user makes each piece in ChatGPT (one piece per image, transparent background, no text, the blueprint attached as the style reference) and saves it as `assets/ui/incoming/<key>.png`. `<key>` is the registry key.
2. **Process:** `python tools/ui_assets/process.py [key...]` (`--tile` for seamless textures).
   - Rejects images without real transparency (including painted checkerboards).
   - Trims, bleeds edge colour into transparent pixels (no dark halos), caps at 1024 px.
   - Writes `assets/ui/journal/<key>.png` and prints size, aspect and a starting 9-slice rect.
3. **Upload:** serve `assets/ui/journal/` with a local http server (`python -m http.server <port>`) and pass the URLs to the Studio MCP `upload_image`. It returns `rbxassetid://` image ids directly (an Open Cloud Decal id would not render in an ImageLabel).
4. **Register:** fill `RS/Assets/Images/JournalUI` (`Image`, `SliceCenter`, `Aspect`, `TileSize`). Tune `SliceCenter` by eye so the corners never stretch.

`assets/` is git-ignored: the art stays local, and the ids live in the tracked registry.

## Networking (ReplicatedStorage)

| Name | Type | Dir | Purpose |
|---|---|---|---|
| `DungeonProfilePush` | RemoteEvent | S->C | full snapshot push |
| `DungeonProfileRequestSync`/`requestSync` | RF | C->S | fresh snapshot pull |
| `EquipItem`/`UnequipItem` | Event/RF | C->S | equip by uuid / unequip by slot |
| `DungeonInventoryAct` | RF | C->S | hotbar/bag/chest/enchant actions |
| `ItemDropNotify` | RemoteEvent | S->C | drop banner |
| `CombatRemote`/`CombatXPEvent` | Event | C->S / S->C | hit reg / XP popup |

**Any new purchase/shop client must call `DungeonMenuNet.requestSync()` after a successful action.** The implicit `DungeonProfilePush` broadcast can race or get dropped as stale — `BankClient`/`SkillsTabClient`/`AuctionHouseClient`/`BlacksmithClient` all do this defensively; `MerchantClient`/`ShopClientBase` originally didn't (fixed). Enchant scrolls have the same race — see [Enchant Scrolls](./enchanting.md).

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

- One registry module, `RS/Assets/Themes/ZoneThemes`, same pattern as the icon/mesh registries (see [Asset & Naming Conventions](./asset-conventions.md)). Keys `T1`..`T5`. Never inline `Color3.fromRGB(...)` in UI code.
- Theme is selected by **zone**, and zone already has a home — `SSS/ZoneService` + `StarterPlayerScripts/ZoneClient`. Theme lookup keys off the zone the player is in, so no new state system is needed.
- A theme is a flat table of *semantic* names (`PanelBg`, `SlotBg`, `SlotBorder`, `TextPrimary`, `TextMuted`, `AccentPositive`, `RarityCommon`...). Never geometry or layout — theming must not be able to move things.
- Rarity colours stay **global**, not per-theme. A purple Elite drop must read as Elite in every zone.
- Transitions between zones should tween the palette, not hard-cut, or the swap will read as a bug.

**Do this after the React migration, not before.** In the current imperative UI every colour is set at `Instance.new` time across 44 client scripts, so re-theming means hunting every mutation site. In React the theme is a context provider and a zone change re-renders the tree — it is the single strongest practical argument for finishing the React port first (see [Rojo Sync & Version Control](./rojo-sync.md) for the React migration strategy).
