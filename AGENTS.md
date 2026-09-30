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
| [Enchant Scrolls](./docs/enchanting.md) | the enchant-scroll apply flow specifically (RNG, validation, sync) |
| [Inventory & Equipment](./docs/inventory-and-equipment.md) | hotbar/bag slots, equip/unequip, drag-and-drop, the legacy-vs-modern profile split |
| [Mob & NPC System](./docs/mob-and-npc-system.md) | spawners, mob AI/heartbeat, NPC bootstrap, shops, dialog |
| [Character & Rigging Pipeline](./docs/character-pipeline.md) | Blender/Tripo asset creation, weapon Grip tuning, R15 rigging, retopo |
| [UI & Networking](./docs/ui-and-networking.md) | menu UI, fonts, remotes, zone theming (design goal) |
| [Studio & Tooling Gotchas](./docs/studio-tooling.md) | command bar, MCP `multi_edit`/`execute_luau` quirks, Luau syntax traps |
| [Asset & Naming Conventions](./docs/asset-conventions.md) | itemId/prefab naming, icon/mesh asset registries |
| [Rojo Sync & Version Control](./docs/rojo-sync.md) | Rojo project structure, syncback, sandboxing/capability bugs, React migration |
| [Dungeon Creation Workflow](./docs/dungeon-creation-workflow.md) | Blender grayboxing, encounter-ready geometry, collision, PBR materials, export, Studio assembly |
| [Miasma Boss Arena & Encounter](./docs/miasma-boss-encounter.md) | Miasma arena construction, encounter phases, poison, gates, valve maze, attacks, and validation |
