# Item Identity & Substat Ranges

Two systems that share one field. Read both halves before touching either.

- **Identity** (`RS/ItemIdentity`) — a durable serial + birth record on every non-stackable item, for provenance, dupe detection and date-window rollback.
- **Ranges** (`RS/ItemStatRanges`) — makes already-owned substat values follow a rebalance instead of drifting permanently out of range.

The link between them is `item.origin.d`, the authored-def key. Without it the range clamp cannot tell Kane's 9% critical god-roll from corrupt data.

---

## Rebalancing a substat: the whole procedure

1. Edit the numbers in `RS/ItemConfig` (`WEAPON_EFFECTS[...].ranges`, `ARMOR_BONUS_EFFECTS[...].ranges`, `ARMOR_SUBSTAT_RANGE`, or `RARITY_SUBSTAT_MULT`).
2. **Bump `ItemConfig.SUBSTAT_RANGES_VERSION`.**
3. Done.

On each player's next load, `ProfileTypes.Reconcile` sweeps their inventory and chest, clamps every substat back inside its new window, and stamps `profile.statsVersion` so the pass never runs again at that version.

Forgetting step 2 is not destructive — existing items just keep their old out-of-range values until some later bump sweeps them up.

### Clamp policy

**Upper bound only.**

| Case | Result |
|---|---|
| Value inside the window | untouched |
| Value above the window | lowered to the maximum |
| Value below the window | **untouched** |

Raising a low value would be a silent buff, and legitimately-low authored values exist — Kane's armour rolls `block` 2-4 where the generic T1 block floor is 3.

### What is never clamped

`ItemStatRanges` is a **whitelist**: only ids that `ItemConfig.FindSubstatEffect` resolves are ever touched. That automatically excludes

- base stats — `dmgMin`, `dmgMax`, `hp`, `hps`, `armor`, `energy`, `dmgRed`
- the private re-scale keys — `_rawDmgMin`, `_rawDmgMax`, `_rawHp`
- profession stats — `MiningLevel`, `FishingLevel`

Base stats **must** stay excluded: enchant scrolls multiply `hp`/`dmgMin`/`dmgMax` compoundingly and legitimately grow far past any generation range.

Because it is a whitelist, adding a new substat to `ItemConfig` makes it clampable automatically. No edit in `ItemStatRanges`.

### Authored loot is exempt

Named-elite and Mythic gear is hand-authored **outside** the generic windows, in both directions. Kane's Axe rolls 6-9% critical where `WEAPON_EFFECTS.critical.ranges[1]` is `{2,3}`. A generic clamp would quietly gut every named-elite drop in the game.

`WindowFor` therefore resolves the window from the item's own source:

- `item.origin.d` names the authored pool entry (`"KaneAxe"`) or Mythic key
- a spec with explicit `min`/`max` **is** the window
- a spec with `highRollStandard` / `useStandardRoll` defers to the generic window, which is correct — that is exactly where its value came from

### The `elemDmg` trap

`elemDmg` is the only substat that takes a **second** multiplier after it is rolled: `ItemClass:getFinalStats` applies the weapon-type multiplier to it (Bow 1.20, Mace 1.15, Axe 1.10, Scythe 1.05, Sword 1.00). Its stored value legitimately sits above whatever window it was rolled from.

`WindowFor` accounts for this on both the generic and authored paths. Without it, the first rebalance sweep would shave ~17% off every bow's elemental damage.

**If another substat ever picks up a post-roll multiplier in `getFinalStats`, mirror it in `WindowFor`.** Nothing enforces this pairing.

### Out-of-band entry points

The sweep is gated at the **profile** level, not per item, so no `statsVersion` field is needed on every item. That is sound because `Reconcile` runs before any grant in a session, so anything granted afterwards was rolled from current ranges.

The one gap is an item that sat in a DataStore **outside** a profile across a rebalance and then lands in an already-swept profile. Two such paths exist, and both clamp explicitly on the way in:

- `AuctionHouseService.grantItemDirect` — the AH's `active` / `pendingReturn` keys are never swept
- `WorldLootService.GrantLootToPlayer` — death bundles

Add a third out-of-band store and it needs the same call.

---

## Identity

### The serial

```
"<10-digit zero-padded unix seconds>-<8-char server tag>-<6-hex counter>"
"1774039112-a1b2c3d4-00003f"
```

Sortable on purpose, not a GUID. Lexicographic order equals chronological order, because decimal seconds stay exactly 10 digits until 2286. **Creation time lives inside the item**, so "remove everything minted between t0 and t1" is a predicate you run per profile — with a GUID that same operation would require a cross-player ledger.

Do not switch it to base36: base36 seconds roll from 6 to 7 characters in 2038 and silently break the ordering.

Server tag is the first 8 hex chars of `game.JobId`, or the literal `"studio00"` in Studio. All current save data is dev data; being able to filter it by substring is worth the eight characters.

### `serial` vs `uuid` — not the same thing

| | `uuid` | `serial` |
|---|---|---|
| Means | which slot in **one** profile's `inventory` dict | which **object** this is |
| On transfer | **re-minted every time** | never changes |
| Answers | "where is it right now" | "where did it come from", "are these the same item" |

Never repurpose `uuid`. Too many call sites depend on its current meaning.

### `origin`

```lua
item.origin = {
    t  = 1774039112,   -- unix seconds. 0 = predates this system
    by = 12345678,     -- UserId minted for. 0 = system
    k  = "named_elite",-- ItemIdentity.SOURCE.*, always present
    s  = "Kane",       -- source id: MobID / npcId / questId. optional, 32 chars max
    d  = "KaneAxe",    -- authored def key. REQUIRED for named-elite/Mythic gear
    p  = 98765432,     -- PlaceId
}
```

`origin.t` is taken from the serial that was just minted, not from a second `os.time()` call — otherwise the pair disagrees whenever it straddles a second boundary and trips the audit's own consistency check.

**Stackables get neither a serial nor an origin.** A per-unit identity is meaningless for something that merges into an existing pile by count, and skipping them is what keeps the audit honest — otherwise every stack merge would look like a dropped serial.

### The mint chokepoint

`ItemIdentity.Stamp(record, ctx)` is the only thing that may write `serial`. Four mint sites call it:

| Site | Source kind |
|---|---|
| `Items/Item.lua` `CreateOwnedRecord` | from `opts.origin` |
| `ProfileService.GrantItem` | from `originCtx` |
| `ProfileService.GrantItemId` | threads to `ItemFactory` |
| `ProfileService.mergeStackableIntoInventory` | threads (no-op today) |

`originCtx` is a **trailing optional argument** everywhere, so a caller that omits it still compiles — and mints with `kind = "unknown"` plus a one-time warn. That warning is the instrumentation: it tells you a grant path still needs threading.

#### The `i == 1` guard in `GrantItem`

```lua
if not (i == 1 and ItemIdentity.CarryForward(item, template)) then
    ItemIdentity.Stamp(item, originCtx)
end
```

A template carrying a serial is **one** item being transferred, so only the first unit may inherit it. `DevService` grants up to 20 units from a single template and those must be 20 distinct items. Removing this guard creates 20 items sharing one serial, which the audit will then report as a dupe.

#### `GrantItem` copies a fixed field literal

`serial`/`origin` do **not** come across from the template on their own. Do not "fix" that by adding two more lines to the literal — the next field will drift the same way. `CarryForward` is the one sanctioned path.

### Transfers preserve identity

Most transfer sites do `for k,v in pairs(item) do copy[k]=v end` or a deep `cloneTable`, so they carry the new fields forward for free. Three notes:

- **`WorldLootService.SpawnPlayerDrop`** sets `template.uuid = nil`. Correct — but do **not** add `template.serial = nil` "for symmetry". Dropping an item must not change its identity.
- **`AuctionHouseService.grantItemDirect`** and **`WorldLootService.GrantLootToPlayer`** backfill a missing serial, for items that were already in those out-of-band stores when this shipped.
- **`AltarUpgrade.ApplyUpgrade`** mutates the item in place and keeps its identity, deliberately. An upgrade transforms an existing object; it does not create a new one.

`ItemIdentity.Remint` exists for a path that builds a genuinely new object out of an existing one. There is no such path today; it exists so that when one is written, the correct call is obvious.

### Audit

`ProfileTypes.AuditItemIdentity(profile)` runs from `ProfileService.Load`'s **cold path** and from `SaveProfile`. **Never from `Reconcile`** — `Reconcile` re-runs on every cached `Load()`, and `Load()` is on the per-mob-kill path (`LootService.getTotalCoinFind`).

It reports only, never deletes. Every check is a heuristic and destroying a player's item on a false positive is worse than the exploit it guards.

Catches, from per-profile state alone:

- the same serial twice in one profile — the double-grant class of bug
- a non-stackable with no serial — the **chokepoint drift detector**, arguably worth more than the dupe check, because it means a mint path exists that bypasses `ItemIdentity`
- a creation time in the future, or an `origin.t` that contradicts its own serial

Cannot catch, because it needs cross-player state:

- the same serial in two different players' profiles (the auction-house dupe: delivered to the buyer *and* returned to the seller)
- a salvaged/trashed serial reappearing later
- mint-rate anomalies

Those need a real ledger. Deliberately not built — see below.

### Backfill

Gated on `profile.migrations.itemIdentity` against `ProfileTypes.MIGRATIONS.itemIdentity`.

Deliberately **not** `profile.version`, which is dead (defined, never read). A single profile-wide integer means every future unrelated schema bump silently re-triggers every past migration. A named dict costs ~30 bytes and tolerates migrations landing out of order or being reverted.

Backfilled items get `t = 0` and a legacy serial whose time prefix is all zeroes — **not** `os.time()`. Stamping "now" would make every pre-existing item claim it was created at migration time and poison every date-window query and rollback from then on.

### Provenance never reaches the client

`BuildSnapshotPayload` strips `origin` via `ItemIdentity.StripForWire`, saving ~9 KB per push and keeping who-created-what server-side.

**This must copy, never strip in place.** `table.clone(profile)` is **shallow**, so `profileWire.inventory` *is* `profile.inventory` and every item table inside it is shared with the live profile. Nilling `origin` in place there would silently and permanently destroy provenance on the server's own data.

`ItemIdentity` lives in ReplicatedStorage, so the client holds its own copy with its own counter. Harmless, but **never accept a client-supplied `serial` or `origin` on any remote.**

---

## Deliberately not built

Ordered cheapest-first, if this ever needs to go further:

1. **Per-profile rolling log** — a capped ring buffer inside the profile. Costs zero extra DataStore calls since it rides the existing profile write. Gives "where did my item go" and makes an in-profile resurrection catchable. Must be excluded from the wire.
2. **MemoryStore SortedMap keyed by serial**, 7-day TTL — near-real-time cross-player dupe detection while both players are online.
3. **DataStore ledger** — never `UpdateAsync` per mint (6-second per-key write cooldown, guaranteed throttle). The only workable shape is accumulating mints in memory per server and flushing every 60s to a key that includes the server tag, so no two servers contend on one key and hour buckets stay directly queryable.
4. **`AnalyticsService:LogEconomyEvent`** — free and non-blocking, gives Roblox-side dashboards, but cannot be queried programmatically and cannot support a rollback. Monitoring, not a ledger.

---

## Known adjacent bug, not fixed here

`ProfileService.GrantItem` aliases `template.subStats` and `template.tags` **by reference** across all N granted units when `count > 1`. `EnchantScrollApply` mutates `subStats` in place, so enchanting one of 20 dev-granted items buffs all 20 for the rest of the session.

`ItemIdentity.CarryForward` shallow-**copies** `origin` specifically so it does not become a third aliased field on that pile.
