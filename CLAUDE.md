**ABSOLUTE RULE: never test by running the game in Roblox Studio.** Do not start or stop Play mode, and do not drive the game through Studio MCP (`start_stop_play`, `user_keyboard_input`, `user_mouse_input`, in-game `execute_luau` probes) to verify a change. It is slow and it interrupts the user's own session. Write the change, review it, and hand it over: the user runs and verifies it themselves. Read-only Studio inspection (`script_grep`, `inspect_instance`, `get_console_output` for an error the user reports) is still fine.

# Project: DungeonBlox

Roblox first-person Looter-ARPG (DungeonRealms-like). 5-tier progression (lvl 1/21/41/61/81), energy-based combat, alignment system (Lawful/Neutral/Chaotic).

## Key conventions

- **Layout:** `src/` is the only source of truth for scripts (`src/shared` -> ReplicatedStorage, `src/server` -> ServerScriptService, `src/client` -> StarterPlayerScripts, `src/characterscripts` -> StarterCharacterScripts, `src/starterpack` -> StarterPack). Studio owns geometry/terrain/instance trees, not scripts.
- **Rojo sync:** `rojo serve` pushes disk -> Studio (overwrites Studio changes); `rojo syncback` pulls Studio -> disk. Syncback before serve whenever disk might be stale. Toolchain is Rokit, not Aftman. Full detail: [Rojo Sync & Version Control](./docs/rojo-sync.md).
- **Play-mode doesn't hot-reload:** `execute_luau` caches `require()` results for the whole Edit-mode session — editing a ModuleScript does not invalidate an already-required copy. A Play-mode Start/Stop cycle is what resets the Lua VM. If a just-added function "doesn't exist," do a Play cycle before assuming the edit failed. Detail: [Studio & Tooling Gotchas](./docs/studio-tooling.md).
- **Naming:** new itemIds/prefabs are tier-prefixed PascalCase (`T1_Sword`, `T2_Helm`), never vague adjectives like "Basic" or "Starter". Detail: [Asset & Naming Conventions](./docs/asset-conventions.md).
- **Dev principles:** first-person only, grim-stylized tone, no emoji/em-dash in UI. Prefer readable code over clever. Combat/loot/shard logic must stay lag-free at high CPS.

## Docs

| Doc | Read this when working on... |
|---|---|
| [Combat, Energy & Death](./docs/combat.md) | energy/regen, alignment & PvP, swing animations, death-drop protection |
| [Items, Loot & Progression](./docs/items-and-progression.md) | item generation, drop rates, scaling, enchanting rules, professions |
| [Named Elite Loot](./docs/named-elite-loot.md) | named-elite signature gear: "high roll <rarity> equivalent", the drop-chance table, the block stat |
| [Item Identity & Substat Ranges](./docs/item-identity-and-ranges.md) | rebalancing a substat range (bump `SUBSTAT_RANGES_VERSION`), the durable item serial/origin stamp, dupe auditing |
| [Enchant Scrolls](./docs/enchanting.md) | the enchant-scroll apply flow specifically (RNG, validation, sync) |
| [Enchant Hit Effects](./docs/enchant-hit-effects.md) | per-enchant hit visuals and the gameplay behind them (armor break/ignore, cleave, bleed, blind, life steal) |
| [Inventory & Equipment](./docs/inventory-and-equipment.md) | hotbar/bag slots, equip/unequip, drag-and-drop, the legacy-vs-modern profile split |
| [Dungeon Creation Workflow](./docs/dungeon-creation-workflow.md) | building a dungeon realm, spawn definitions, run mob levels (`RS/DungeonLevels`, tier cap - 6, modifiers) |
| [Mob & NPC System](./docs/mob-and-npc-system.md) | spawners, mob AI/heartbeat, NPC bootstrap, shops, dialog |
| [Character & Rigging Pipeline](./docs/character-pipeline.md) | Blender/Tripo asset creation, weapon Grip tuning, R15 rigging, retopo |
| [UI & Networking](./docs/ui-and-networking.md) | menu UI, fonts, remotes, zone theming (design goal) |
| [World Map & Minimap](./docs/minimap.md) | the minimap / M map, fog of war (explored cells), region discovery, map colours (`MapColor`) |
| [Studio & Tooling Gotchas](./docs/studio-tooling.md) | command bar, MCP `multi_edit`/`execute_luau` quirks, Luau syntax traps |
| [Dev Tools](./docs/dev-tools.md) | F8 DevPlacer (spawners/zones/time/item spawning), F7/F10/F6 dev menus, DevRoster gating, dev DataStores |
| [Asset & Naming Conventions](./docs/asset-conventions.md) | itemId/prefab naming, icon/mesh asset registries |
| [Rojo Sync & Version Control](./docs/rojo-sync.md) | Rojo project structure, syncback, sandboxing/capability bugs, React migration |
