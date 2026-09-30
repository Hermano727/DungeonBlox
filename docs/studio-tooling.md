---
title: Studio & Tooling Gotchas
tags: [tooling, studio, workflow]
aliases: [MCP Tooling, Play Mode]
---

# Studio & Tooling Gotchas

- **Command bar defaults to Client during play** — switch to Server before server-side require()/mutations.
- **`execute_luau` caches `require()` across calls within one Edit-mode session.** Editing a ModuleScript does NOT invalidate an already-required copy — you'll silently get pre-edit behavior (missing new functions) until a Play-mode Start/Stop cycle resets the Lua VM. If a just-added function "doesn't exist," verify with a fresh Play cycle before assuming the edit failed. (This is the reason Play mode doesn't "hot reload" — see the project index.)
- **MCP `multi_edit` is atomic** — one failing `old_string` match rolls back every edit in that call. Verify after with a read/grep.
- Scripts via `multi_edit` persist to the place; scripts via `execute_luau` do not survive session end.
- `goto continue` invalid in Luau nested-if — use inline `and not (cond)` guards.
- `DungeonMenuUI` corruption recovery: rename old (`.Name = "..._OLD"`), create fresh via `multi_edit` empty-old_string, destroy old. Don't patch corrupted layout code in place.
- Quicksand font "Temp read failed" in Studio is expected/harmless (works in real game) — keep `FontFace` set in `pcall`.
- **Play-mode profile/join races:** `seedStarterIfEmpty`/character-spawn flow is async; ad-hoc `execute_luau` profile pokes right after spawn often race it (profile looks unseeded for several real seconds). Don't conclude a feature is broken from one early poke — wait or test via real UI.
For Rojo-specific sync/syncback gotchas, see [Rojo Sync & Version Control](./rojo-sync.md). `SkillsTabClient`'s `local refresh` forward-declare pattern is flagged from [UI & Networking](./ui-and-networking.md) — the original notes don't elaborate on it further than that; check the file directly before assuming a scoping bug.
