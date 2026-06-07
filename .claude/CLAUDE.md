# Project: DungeonBlox

## Core Concept
DungeonBlox is a first-person, high-uptime Roblox Looter-ARPG inspired by DungeonRealms. It features a 5-tier progression system (Levels 1, 21, 41, 61, 81) with energy-based combat and a high-risk player alignment system (Lawful, Neutral, Chaotic).

## Core Gameplay Loop
1. **Combat & Energy:** High-CPS farming loop regulated by an energy bar (8/sec regen). Zero energy triggers "Low Energy Mode" (3s lockout). Walking allows regen; sprinting/swinging consumes energy.
2. **Spawners & Sharding:** Mobs spawn from radius-based spawners with cooldowns. Players "Shard Hop" to find open spots. Hopping has a cooldown based on alignment (Lawful: 10s, Neutral: 30s, Chaotic: 1m).
3. **Loot System:** Private loot via visual-only "flying keys" that travel from mobs to world chests (Food/Green, Normal/White, Elite/Purple).
4. **Score Mechanic:** 1 Score = 1 Loot Roll. Kill credit is damage-weighted, but all party members get a base score (default 1 in world, 4 in dungeons).
5. **Dungeons:** Instanced 8-player raids using Tier-specific keys with difficulty modifiers. Automatic "Scrap" conversion for low-tier loot to prevent inventory clutter.

## Key Systems Logic
- **Alignment Risks:** Neutral/Chaotic allows PvP. Chaotic players drop worn gear/weapons on death; others only drop inventory items. Profession tools are NEVER dropped.
- **Enchanting:** Safe to +3. Failure at +4 (20% chance) breaks the item (3x repair cost) and resets to +0. Max enchant +9. Protection scrolls (crafted from shards) prevent breaking but not failure.
- **Level Scaling:** Scaling damage penalty for mobs 5+ levels above player; XP penalty for mobs 5+ levels below.
- **Professions:** Active Mining and Spear-Fishing. Tools roll sub-stats (Double Ore, Mining Success, etc.). 2:1 Ore-to-Scrap conversion.

## Development Principles
- **Perspective:** Strictly First-Person.
- **Tone:** Grim-Stylized aesthetic with high atmospheric tension.
- **UI/UX:** Minimalist, no emojis, no em-dashes. Use clear progress bars/pies for energy.
- **Code Logic:** Prioritize human-readable, efficient scripts that handle high-speed loot rolls and multi-instance shard logic without lag.

---

## Codebase Systems Map

### Two Profile Systems (do not mix them up)
There are two parallel profile systems. The **modern Dungeon system** is the active one:

| | Old (legacy) | Modern (active) |
|---|---|---|
| Service | `SSS/PlayerDataManager` | `SSS/DungeonProfileService` |
| Types/schema | `SSS/PlayerBootstrap` DEFAULT_KIT | `RS/DungeonProfileTypes` DefaultProfile() |
| Storage key | slot-indexed `profile.Inventory[slotIdx]` | UUID-keyed `profile.inventory[uuid]` |
| Used by | `InventoryService`, `PlayerBootstrap` | Everything new (drops, equip, UI) |

### Default Starter Inventory
`SSS/DungeonBootstrap` → `seedStarterIfEmpty(player)` (lines ~213–265)
- Runs on join if `profile.inventory` is empty
- Grants: Worn Blade (Weapon T1), Tattered Mail (Armor T1 Uncommon), Stone Pickaxe, Twig Rod (FishingSpear), Cracked Flask ×3
- All granted via `DungeonProfileService.GrantItem(player, template, count)`
- Old legacy kit (TrainingSword, LeatherHelm etc.) is in `SSS/PlayerBootstrap` → `DEFAULT_KIT` — this is the **old system** and largely superseded

### Item Generation Pipeline
```
ItemConfig (RS)         ← all raw stat tables, no logic
    ↓ required by
ItemGenerator (SSS)     ← rolls rarity, base stats, substats → returns ItemClass
    ↓ returns
ItemClass (SSS)         ← OOP wrapper; getFinalStats() applies multipliers; toGrantTemplate() formats for GrantItem
    ↓ used by
LootService (SSS)       ← called by MobManager.ProcessMobDeath; rolls drop chance → grants item → fires ItemDropNotify
    ↓ notifies
LootClient (StarterPlayerScripts) ← slides in top-right banner on drop
```

### Item Config File: `ReplicatedStorage/ItemConfig`
All static numbers — no logic. Key tables:
- `TIER_MEDIANS` = {10, 30, 50, 70, 90} — used in level-scaling formula
- `ARMOR_HP_RANGES[tier][rarity]` = {lo, hi} — e.g. T1 Common = {45,51}
- `ARMOR_ARMOR_RANGES`, `ARMOR_DMGRED_RANGES`, `ARMOR_ENERGY_RANGES` — per tier/rarity
- `WEAPON_DMG_RANGES[tier][rarity]` = `{min={lo,hi}, max={lo,hi}}` — produces a "7-9" style range
- `ARMOR_SUBSTAT_RANGE[tier]` = {lo, hi} — single range, all 4 armor substats share it
- `ARMOR_EFFECTS` — VIT/STR/INT/DEX, weight=30 each
- `WEAPON_EFFECTS` — 15 effects with `meleeOnly`/`rangedOnly` flags and per-tier ranges
- `WEAPON_TYPE_WEIGHTS[weaponType]` — per-effect multipliers (e.g. Mace: critical×3, crushing×3)
- `WEAPON_MULTIPLIERS` — Sword=1.00 … Bow=1.20; applied to dmgMin/dmgMax and elemDmg substat
- `TIER_DROP_CHANCE[tier]` — default {T1=0.18 … T5=0.72}; **change server-side only** (switch command bar to Server before running)
- `TIER_RARITY_WEIGHTS[tier]` — rarity distribution per tier

### Item Stat Scaling Formula (`SSS/ItemGenerator` → `scaleStat`)
```
result = baseStat * (1 + (level - tierMedian) * 0.01)
if level > 100: result = max(result, baseStat * (1 + (level-100) * 0.05))
result = floor(result)
```
Armor HP/s is always `floor(hp * 0.5)`. Energy rolls as a float, rounded to 2 decimal places.

### Armor Base Stats (all four slots: Helm/Chest/Legs/Boots share same tables)
`hp`, `hps` (=floor(hp*0.5)), `armor` (flat rating), `dmgRed` (% integer), `energy` (float Energy/s regen)

### Weapon Base Stats
`dmgMin`, `dmgMax` — after WEAPON_MULTIPLIERS applied via `ItemClass:getFinalStats()`

### Item Template Format (what GrantItem accepts)
```lua
{
  name        = string,
  type        = "Weapon" | "Armor" | "Material" | "Consumable",
  rarity      = "Common"|"Uncommon"|"Rare"|"Epic"|"Legendary",
  tier        = 1-5,
  enchantLevel = 0,
  subStats    = { [statId] = number, ... },  -- base stats + substats all in one flat dict
  equipSlot   = "Weapon"|"Helm"|"Chest"|"Legs"|"Boots"|"Armor"|"Pickaxe"|"FishingSpear"|"Potion",
  tags        = { string, ... },  -- e.g. {"Mace"} or {"Helm"}
}
```

### Profile Schema: `ReplicatedStorage/DungeonProfileTypes`
- `DefaultProfile()` — the canonical empty profile structure
- `ValidateItemTemplate(t)` — validates before GrantItem
- `VALID_SLOTS` — all allowed equipSlot values
- `GetAllowedEquipSlot(item)` — derives correct slot from item.equipSlot or item.tags

### Player Stats / HP Recompute
`SSS/DungeonStatsService` → `RecomputeRuntimeHp(profile)` — called after every GrantItem

### Mob System
- `SSS/MobClass` — OOP mob, fields: `mob.Tier`, `mob.MobID`, `mob.Stats.Level`, `mob.DamageTracker`
- `SSS/MobManager` — heartbeat loop; owns `ProcessMobDeath` which calls `LootService.onMobDied`
- `SSS/MobData` (RS) — static mob definitions; `MobData.FindMobById(id)` returns `baseStats, tier`
- `SSS/SpawnerService` — reads `Workspace/Spawners/MobSpawners` Parts with attributes (MobId, Count, Radius, RespawnDelay, Active)

### Combat & Animation System

#### Files — what to touch and what to avoid

| File | Purpose | Touch for |
|---|---|---|
| `ReplicatedStorage/CombatAnimConfig` | All animation + hitbox constants | Swap anim ID, tune speed/priority/hitbox |
| `StarterPlayerScripts/CombatClient` | Input → animation → hit detection → remotes | Combat logic changes only; never hardcode values here |
| `StarterPack/R6Sword/AnimationScript` | Gutted — replaced by CombatClient | Do not restore; CombatClient owns all swing anims |

#### How to swap the swing animation
Edit only `CombatAnimConfig.SWING_ANIM_ID`. Nothing else needs to change.
- Animation must be published to the same Roblox account/group as this game.
- Use R15-native or R6 animations (R6 auto-converts on R15 characters). R15 animations that fail asset delivery produce **no console error and no visual output** — silent failure.
- To diagnose: set `CombatAnimConfig.DEBUG = true` → logs rig type, anim ID, track length, and `IsPlaying` on every load and swing.

#### Key constants (all live in `CombatAnimConfig`)
- `SWING_ANIM_ID` — animation asset ID
- `ANIM_SPEED_MULT` — playback speed (4.0 = 4× for high-CPS feel)
- `ANIM_PRIORITY` — `Enum.AnimationPriority.Action` by default
- `CANCEL_FADE` — fade-out seconds when cancelling an in-progress swing
- `HITBOX_SIZE` — overlap box for the secondary melee sweep

#### What to avoid
- **Never hardcode animation IDs or Vector3 hitbox sizes in CombatClient.** All tunable values belong in `CombatAnimConfig`.
- **Never restore the `SwingAnimId` tool attribute pattern.** It was removed because `execute_luau` attribute changes revert when play stops, making the attribute silently override `CombatAnimConfig` with stale data.
- **Never add `SwingAnimId` attributes to tools in StarterPack.** `CombatClient` no longer reads them; they would be dead data.
- **Never re-enable `R6Sword.AnimationScript`.** It played `SlashAnim2` independently on the Humanoid Animator and raced with CombatClient.

### NPC System
- `SSS/NPCService` — server-side NPC logic
- CollectionService tag `"NPC"` — drives NPCClient factory on the client
- NPC spawner markers in `Workspace/Spawners/NPCSpawners` (NpcId, NpcType, NpcName attributes)

### Innkeeper and Hearthstone (how the client UI is wired)
**What was wrong**
- `StarterPlayerScripts/MerchantShopClient` hooks `ProximityPromptService.PromptTriggered` for every prompt. It used to treat **Innkeeper** like a wallet or scrap merchant (`SHOP_NPC_TYPES.Innkeeper`). That opened **MerchantShopFallbackUI** and filled offers from `NPCRegistry` **TeleportNodes**, which are empty for Innkeeper (hearthstone routes live in DataStore and **HearthstoneSync**, not in the registry).
- A separate **client-only** `ProximityPrompt` named `HearthstonePrompt` on the Innkeeper rig conflicted with the real NPC prompt. Disabling sibling prompts or wrong key bindings could remove the normal **E** affordance entirely.

**What we did (Blacksmith pattern)**
- **Innkeeper is not a merchant shop type:** `Innkeeper` was removed from `SHOP_NPC_TYPES` in `MerchantShopClient`, so the wallet or scrap UI never opens for Innkeepers.
- **Same entry path as Blacksmith:** After resolving a **Blacksmith** prompt with `getNpcFromPrompt`, `MerchantShopClient` calls `getInnkeeperFromPrompt(prompt)` (matches `NpcType == "Innkeeper"` or model **Name** `"Innkeeper"`; default `NpcId` **`innkeeper_01`** if missing) and then **`HearthstoneClient.openInnkeeperShop()`**.
- **`HearthstoneClient`** keeps the **HearthstoneShopUI** (catalog from **`HearthstoneSync`**, buy via **`HearthstonePurchase`**) and tele or swap UI from **`SkillsTabClient.init`**. It **no longer** creates a second prompt, scans the world for Innkeepers, or disables other **ProximityPrompt** instances on the HRP.
- **`NPCClient`** still short-circuits **Innkeeper** on `prompt.Triggered` so the dialog UI does not fight the shop; the shop is opened only through **`ProximityPromptService`** in `MerchantShopClient`, like the blacksmith repair UI.

**Data and remotes (ReplicatedStorage)**
- **`HearthstoneConfig`** (ModuleScript): seeds, admin ids, DataStore key name, cooldown constant.
- **`HearthstoneSync`** (RemoteFunction): client gets the location list (dev tool additions and server merge).
- **`HearthstonePurchase`**, **`HearthstoneTeleport`**, **`HearthstoneSwap`**, plus admin **`HearthstoneAdminAdd`** / **`HearthstoneAdminDelete`** for the dev panel.

### Networking (RemoteEvents/Functions in ReplicatedStorage)
| Name | Type | Direction | Purpose |
|---|---|---|---|
| `DungeonProfilePush` | RemoteEvent | S→C | Push full profile snapshot to client |
| `DungeonProfileRequestSync` | RemoteFunction | C→S | Client requests fresh snapshot |
| `DungeonEquipItem` | RemoteEvent | C→S | Equip item by UUID |
| `DungeonUnequipItem` | RemoteEvent | C→S | Unequip by slot name |
| `DungeonInventoryAct` | RemoteFunction | C→S | Hotbar/chest/enchant actions |
| `ItemDropNotify` | RemoteEvent | S→C | Notify client of item drop (shows banner) |
| `CombatRemote` | RemoteEvent | C→S | Weapon hit registration |
| `CombatXPEvent` | RemoteEvent | S→C | Combat XP popup |

### UI Entry Points (StarterPlayerScripts)
- `DungeonMenuUI` — Tab menu: inventory grid + equipment slots panel (Helm/Chest/Legs/Boots/Weapon)
- `DungeonMenuNet` — client cache for profile snapshots; inventory RF (`DungeonInventoryAct`), equip/unequip, **`requestSync`**. After **`ApplyEnchantScroll`** success, merges state via sync so `_seq` races with **`DungeonProfilePush`** do not drop the update (see Important Caveats).
- `LootClient` — ItemDropNotify listener; shows slide-in banner top-right
- `ItemTooltip` — hover tooltip showing dmgMin-dmgMax / hp / substats
- `SkillsTabClient` — skills/stats tab; wires equip/unequip callbacks into DungeonMenuNet; character bag scroll UI. If callbacks call `refresh` before it is defined, use **`local refresh` forward declare** then **`refresh = function() ... end`** (see Important Caveats). Calls **`HearthstoneClient.init`** for tele or swap and hearthstone menu refs
- `MerchantShopClient` — global **ProximityPromptService** routing: **Blacksmith** to `BlacksmithClient`, **Innkeeper** to **`HearthstoneClient.openInnkeeperShop`**, other shop NPC types to merchant UI
- `HearthstoneClient` — hearthstone shop UI, picker, and profile-driven tele or swap (opened from `MerchantShopClient` on Innkeeper prompt)

### Important Caveats
- **Command bar Server vs Client:** The Studio command bar runs as **Client** by default during play. Use the dropdown to switch to **Server** before running any server-side require() or config mutations. Client-side changes to `ItemConfig` do NOT affect the server drop rolls.
- **Script persistence:** Scripts created via MCP `multi_edit` persist to the place file. Scripts created via `execute_luau` do NOT persist after session ends.
- **`goto continue` is invalid in Luau** inside nested if blocks — use inline `and not (condition)` guards instead.

### Enchant scrolls and profile snapshots (do not regress)
Authoritative scroll logic lives in **`ReplicatedStorage/EnchantScrollApply`**. Server entry: **`ServerScriptService/DungeonProfileService`** `ApplyEnchantScroll` → `EnchantScrollApply.ApplyFromAct(profile, act, Random.new())` after validation. Client entry: **`DungeonInventoryAct`** → same server function; client merge in **`StarterPlayerScripts/DungeonMenuNet`**.

- **Luau `Random` is userdata, not a table.** `Random.new()` must never be validated with `type(rng) == "table"`. If `RollEnchantSuccess` (or any RNG helper) rejects the instance, every scroll will look like a failure: scroll consumed, `enchantLevel` forced to `0`, substats unchanged. Duck-type only: `rng` non-nil and `type(rng.NextNumber) == "function"`. Do not use `game:GetService("Random")` (nil).

- **Scroll targets vs catalog `itemId`.** `DungeonProfileTypes.ValidateOwnedItem` requires a non-empty catalog `itemId`. Rolled weapons/armor from **`ItemGenerator`** often have **no** `itemId`. For scroll application, validate the **scroll** with `ValidateOwnedItem`; validate the **target** with **`EnchantScrollApply.ValidateEnchantTargetItem`** (type + tier). Using `ValidateOwnedItem` on the target yields `bad_itemId` for legitimate drops.

- **Client snapshot merge after `ApplyEnchantScroll`.** Snapshots carry monotonic `_seq` from **`DungeonProfileService.BuildSnapshotPayload`** (`snapshotGenByUserId`). While the client is yielding on **`DungeonInventoryAct:InvokeServer`**, **`DungeonProfilePush`** can still run and advance `lastSnapshot._seq`. The RF return payload can then look **stale** to `applySnapshotPayload` / `snapshotIsStale` and be dropped, so the UI shows no `+N` even though the server applied the scroll. After a successful scroll act, **`DungeonMenuNet.requestInventoryAct`** should rely on an authoritative **`requestSync()`** for `ApplyEnchantScroll` (not only the RF second return value).

- **`SkillsTabClient` and `task.defer(refresh)`.** `menuCtx` callbacks are created **before** the `refresh` function is defined. Without a forward declaration (`local refresh` then `refresh = function() ... end` later), `refresh` inside those closures resolves to **global** (nil) and `task.defer(refresh)` errors. Any callback defined above `refresh` that calls `refresh` must use that pattern or an inline closure.

- **Repo vs Studio.** On-disk `roblox/` may only mirror **`ReplicatedStorage/EnchantScrollApply`**, **`ItemDefinitions`**, **`ItemTooltip`**. **`DungeonProfileService`**, **`DungeonMenuNet`**, **`SkillsTabClient`**, **`DungeonBootstrap`**, **`MobCombat`**, etc. often exist **only in the place file**. After MCP or manual edits in Studio, **save the place** and consider copying critical modules into `roblox/` if you use Rojo.

- **Optional debug:** Server `ApplyEnchantScroll` and client `DungeonMenuNet` may log **`[EnchantTrace]`** (target uuid, `enchantLevel`, `push_seq` / merged `_seq`) when tracing server vs UI drift. Remove or gate once stable.

---

## Inventory GUI Revamp (May 2026)

### Files Changed

| File | Role |
|---|---|
| `StarterPlayer.StarterPlayerScripts.DungeonMenuUI` | **Primary inventory file.** Complete layout rewrite: 2×2 equipment grids, bag below hotbar, skill bars horizontal, active buffs panel removed. Also owns `redraw` and `setActiveBuffs`. **Edit this file for all layout, font, and slot styling changes.** |
| `StarterPlayer.StarterPlayerScripts.InventoryDragController` | Added bag-to-bag drag-to-swap: `syncBagOrder`, `swapBagOrder`, `getSortedBagItems`, and `bag_item` drop target detection via `BagUUID` attribute on bag buttons. |
| `StarterPlayer.StarterPlayerScripts.StatsOverlayClient` | New script. Injects a "View Stats ›" button into the frame named `PlayerStatsBox` (searches `playerGui` recursively by name) and creates the character sheet overlay ScreenGui (DisplayOrder 150). |

### Changing Fonts

All fonts are controlled in **`DungeonMenuUI`** at the top of the file:

```lua
local QS = "rbxasset://fonts/families/Quicksand.json"
local function qsFont(lbl, w)
    pcall(function() lbl.FontFace = Font.new(QS, w or Enum.FontWeight.Medium) end)
end
```

- **To change the font family:** update the `QS` URL.
- **To change a specific element's weight:** find its `qsFont(label, Enum.FontWeight.X)` call in `createLayout`.
- **Gotham is the fallback** (set via `label.Font = Enum.Font.GothamMedium` before `qsFont`). Quicksand shows "Temp read failed" in Studio testing but loads correctly in-game — this is expected.
- **TextSize** for each element is set inline in `createLayout`; there is no central size table.

### Critical Gotchas

1. **`PlayerStatsBox` must exist in the layout.** `StatsOverlayClient` searches `playerGui` recursively for a `Frame` named exactly `"PlayerStatsBox"`. If `DungeonMenuUI.createLayout` is redesigned and this frame is removed or renamed, the "View Stats" button disappears silently. Always keep a frame with this name in the `InfoCenter` area containing `Currency` and `DerivedStats` labels.

2. **`multi_edit` is atomic — one failing edit rolls back the entire call.** When making multiple changes to `DungeonMenuUI`, use separate `multi_edit` calls per change. A single `old_string` mismatch silently reverts every other edit in the same batch. Always verify with `execute_luau` checking `.Source` for key strings after editing.

3. **`DungeonMenuUI` corruption recovery.** If partial rewrites leave orphaned code (duplicate `Instance.new()` calls, mismatched scopes), targeted edits become impossible. Recovery: rename via `execute_luau` (`.Name = "DungeonMenuUI_OLD"`), create a fresh script with `multi_edit` using an empty `old_string` to set initial content, then destroy the old one. Do not attempt to fix a badly corrupted file in place.

4. **Duplicate Animator breaks animations — fix is in place, do not regress.** `CombatClient.InitAnimator` uses `humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", 10)`. It tries the fast path first; if the real Animator doesn't exist yet it waits. Never replace this with `FindFirstChildOfClass` alone as the sole call. Roblox's `Animate` script creates the real Animator asynchronously; calling `FindFirstChildOfClass` too early (before Animate runs) creates a second phantom Animator. Animations then fire (`IsPlaying = true`, `Length > 0`) but nothing moves visually because the phantom Animator doesn't drive the character.

5. **Player characters are R15, not R6.** The **Avatar** tab in the Studio toolbar ribbon is for appearance customization only — it does NOT change the character rig type. The actual setting is under **File → Game Settings → Avatar → Avatar Type**, which is set to **R15**. Confirm with `execute_luau` on a live character: `char:FindFirstChildOfClass("Humanoid").RigType`. NPC and mob rigs in Workspace are R6 (separate from player characters — they are authored independently). The working swing animation `98847827358249` plays correctly on R15 via Roblox's R6→R15 auto-conversion layer. New animations must be either R15-native or R6 (auto-converted); pure R15 animations that fail to load silently produce no visual output and no error in the console.

6. **Quicksand font fails in Studio, works in-game.** `Font family rbxasset://fonts/families/Quicksand.json failed to load: Temp read failed` in the Studio output is expected and harmless. Always wrap `FontFace` assignment in `pcall` (already done via the `qsFont()` helper in `DungeonMenuUI`).