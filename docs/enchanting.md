---
title: Enchant Scrolls
tags: [items, enchanting]
aliases: [Enchanting]
---

# Enchant Scrolls (`RS/EnchantScrollApply`)

Entry point: `ProfileService.ApplyEnchantScroll`. For the player-facing rules (safe-to-+3, +4 fail rate, max +9, protection scrolls), see [Items, Loot & Progression](./items-and-progression.md#enchanting).

## Implementation gotchas

- `Random.new()` is userdata, not a table — never `type(rng)=="table"` check; duck-type `type(rng.NextNumber)=="function"`.
- Validate scroll with `Types.ValidateOwnedItem`; validate target with `EnchantScrollApply.ValidateEnchantTargetItem` (rolled gear often has no catalog itemId, `ValidateOwnedItem` would reject it).
- After `ApplyEnchantScroll`, client must call `requestSync()` — RF return payload can look stale vs a racing `DungeonProfilePush` and get dropped silently. Same class of race documented for other client actions in [UI & Networking](./ui-and-networking.md#networking-replicatedstorage).
