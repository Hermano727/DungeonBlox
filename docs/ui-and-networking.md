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
