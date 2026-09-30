---
title: Inventory & Equipment
tags: [inventory, ui, items]
aliases: [Hotbar, Bag, Equipment]
---

# Inventory & Equipment

## Two profile systems — don't mix up

| | Legacy (dead) | Modern (active) |
|---|---|---|
| Service | `SSS/PlayerDataManager` | `SSS/ProfileService` |
| Schema | `SSS/PlayerBootstrap` DEFAULT_KIT | `RS/ProfileTypes` DefaultProfile() |
| Storage | slot-indexed `profile.Inventory[i]` | uuid-keyed `profile.inventory[uuid]` |
| Used by | `InventoryService`, `PlayerBootstrap` | everything new |

Legacy capitalized `profile.Equipped`/`profile.Inventory` (InventoryService, PlayerBootstrap) is a different system — don't touch when working on modern inventory.

## Hotbar/Inventory model (current, Minecraft-style)

**Updated 2026-09-13 — this section previously said "no reserved weapon slot" and gave the bag as 27 slots; both are stale, see below.** Three separate slot systems, all pointing into the one `profile.inventory[uuid]` ownership dict:

- **Equip panel** — `profile.equipped[slot]`, 9 dedicated gear boxes: `Helm/Chest/Legs/Boots/Shield` (armor) + `Weapon/Bow/Pickaxe/FishingSpear` (tools). This is where your actual weapon/tool lives, not the hotbar. `Types.GetAllowedEquipSlot(item)` derives an item's slot; `PlayerPreview.lua`'s `SLOTS` list is the UI-facing source of truth for which equip slots are real.
- **Hotbar** — `profile.hotbar[1..9]`, a manual quickbar the player drags items into themselves. New acquisitions never auto-land here.
- **Bag** — `profile.bagSlots[1..30]` (5x6, `Types.BAG_SLOT_COUNT` — was 27/3x9, which didn't divide evenly into `InvSlots.lua`'s COLS=5 grid and left 3 dead cells in the last row that looked empty but silently rejected every drop; bumped to 30), same uuid-pointer pattern as `hotbar`.

**Fill-first-empty-slot on every acquisition, bag first.** `SSS/ProfileService.placeItemInFirstEmptySlot(profile, uuid, player)`: tries `bagSlots[1..30]` first; only if the bag is completely full does it fall back to an **empty** equip-box slot the item can wear into (`STORAGE_EQUIP_SLOTS`, the same 9 gear slots above) — an unused gear slot is real capacity, not just something reached by dragging. That fallback needs `player` (drives `ArmorVisualsService.ApplyVisual` + `Hotbar.syncFromProfile`, same as `EquipItem`) — omit it and the fallback is skipped. `ProfileService.HasRoomForItem`/`HasRoomForStackable`/`HasRoomForItemId`/`HasRoomForItems` mirror this same bag-then-equip-box rule for pre-checking room before a grant. Wired into `GrantItem`, `GrantItemId`, `mergeStackableIntoInventory`'s create-fallback, `ChestWithdrawSlot`. Public wrapper `ProfileService.PlaceItemInFirstEmptySlot(profile, uuid, player)` for outside callers that mint uuids directly: `AuctionHouseService.grantItemDirect`, `WorldLootService.GrantLootToPlayer`. **Any new direct `profile.inventory[uuid]=item` write must call this too**, or item is owned but invisible.

**WorldLootService denies pickup outright when there's no room** — `tryPickupFor` checks `HasRoomFor*` before granting and, if it fails, leaves the loot on the ground and fires `GameEvents/CenterFlashNotify` ("Inventory is full!", 10s per-player cooldown) instead of silently eating the item into an unplaced/invisible slot.

**Never raw-assign `profile.equipped[slot]=uuid` or `profile.hotbar[i]=uuid`.** Always go through `EquipItem`/`SetHotbarSlot`/`SetBagSlot`/etc — they clear the uuid's old slot reference first. A raw assignment (e.g. an old `seedStarterIfEmpty` bug) leaves the same uuid referenced in two places at once → item renders twice, and unequip/requip can make it vanish. Every "leaves a slot" path must call `clearUuidFromBagSlots`/`clearItemUuidFromAllHotbar`/`clearItemUuidFromAllEquipped` — already wired into `EquipItem`, `SetHotbarSlot`, `ChestDepositToSlot`, `ConsumeItemId`, `SalvageGearByUuid`, `DropItem`/`TrashItem`, scroll-apply safety nets, and `DeathLootService.stripReferencesToMissing` (hotbar+bagSlots+equipped — see [Combat, Energy & Death](./combat.md#death-drop-protection-sssdeathprotection)).

**Starter seed order (`ProfileBootstrap.seedStarterIfEmpty`):** explicit reorder step after granting — Sword→hotbar[1], Bow→[2], Pickaxe→[3], Spear→[4], independent of grant order. Armor still explicitly equipped via `EquipItem` (not hotbar-eligible, would otherwise sit in bag). Gated by `flags.trainingGearSeeded`, runs once ever; later sessions preserve player's own arrangement.

**Server actions:** `SetHotbarSlot`/`ClearHotbarSlot`/`SwapHotbarSlots`, `SetBagSlot`/`SwapBagSlot` (mirror pair), `EquipItem`, `UnequipItem`, `DropItem`/`TrashItem` (drop/trash an owned item — see Networking table below). Dispatched via `DungeonInventoryAct` RF kinds of the same name in `ProfileBootstrap`.

**Client (`InventoryDragController`) — two gestures, one dispatch path (`performDrop`):**

1. Click-to-pick-up/place: click occupied slot → picks up (cursor-follow ghost), click destination → places (swaps if occupied). Same slot or right-click = cancel, free (nothing mutated until the placing click).
2. Hold-and-drag: press+hold on occupied slot, move past 5px threshold, release on destination. Release under threshold falls through to gesture 1. Drag-release uses position hit-testing (`dropTargetAt`/`pointInGui`) since it isn't tied to one button's own click event.

Both gestures end at the same `performDrop`/`performHotbarToHotbarSwap`/`performAssignToHotbar` calls — never add a third path to the server.

**Hover+number-key (1-9):** while menu open, hover bag/hotbar slot + press 1-9 = same assign/swap actions. Hover state fed by `DungeonMenuUI`'s existing tooltip MouseEnter/Leave (no 2nd hover system).

**Hotbar clicks while menu open = pick/place only**, no equip-by-click (that callback was always dead code). `HotbarHud`'s "press 1-9 while menu *closed*" to equip is separate/untouched.

`DungeonMenuUI` bag render reads `profile.bagSlots[i]` directly (no client-side sorting). Every bag button gets `BagSlot` attr (even empty ones — valid drop targets).

## Inventory item borders: ItemSlot vs PlayerPreview (recurring drift)

`RarityBorder` (`src/client/InventoryHud/Inventory/RarityBorder.lua`) is the one shared stroke component, but it's called from **two separate, independently-maintained sites** that must be tuned to match by hand — nothing enforces parity:

- `ItemSlot.lua` — bag/inventory grid slots (used by `InvSlots`).
- `PlayerPreview.lua`'s `EquipmentSlot` — the 8 equipped-gear boxes. Despite `ItemSlot.lua`'s own header comment claiming it's "used by both InvSlots (bag) and PlayerPreview (equip boxes)", `PlayerPreview` actually reimplements the same icon/border/legendary-glow logic itself rather than rendering `ItemSlot` — that comment is aspirational, not current fact.

This has drifted at least twice: equipped items rendered with a bold border while the same item sitting in the bag looked borderless/thin. Both times the fix was bumping `ItemSlot`'s `RarityBorder` `thickness` props to match `PlayerPreview`'s (currently **8**, with the `selected`/currently-held state a level above that at **10**). If you touch either file's border thickness, update the other one too, and check both still visually match in Studio.
