# World Map and Minimap

The top-down map of the overworld: a corner minimap, an expanded map on **M**, fog of war that fills in as you walk, and region discovery.

## What the player sees

- **Corner minimap:** top right, always on in the overworld, hidden inside dungeons.
  - Centred on the player, north up.
  - A white arrow turns with the way the character faces.
  - An ornate bronze ring with gold corner studs and an "N" notch frames it, and a small "M" keycap sits on its bottom-right corner (the key comes from `KeybindConfig.ToggleMap`).
- **Expanded map (M):** opens centred on the player.
  - Zoom with the scroll wheel or `+` / `-`; the controls are listed in the bottom-right corner.
  - Drag to look around. M or Esc closes it, and reopening re-centres on the player.
- **Fog of war:** everything is black except:
  - ground the player has walked near (within `REVEAL_RADIUS` studs), saved to the profile;
  - zones in `DefaultRevealed` (Oakhaven), shown in full from the start;
  - **safe zones:** a discovered zone whose alignment is in `AutoRevealAlignments` (Lawful) shows in full the moment it's discovered. Towns are never gated behind exploring them. This is derived on the client from the discovered set; the server saves no cells for it.
- **NPCs:** every NPC whose type has an `NPCRegistry` `Nametag` entry shows as its nametag crest and role icon, on uncovered ground only (an unexplored town keeps its NPCs hidden).
  - Each crest has a dark ring and a soft drop shadow (`MapView` `NPC_RING` / `NPC_SHADOW`) so it reads over bright ground.
  - Corner minimap: small fixed-size crests, never named.
  - Expanded map: the crests grow with zoom, and the role name (`DisplayName`, e.g. "Auctioneer", never a personal name) appears under each from `NpcNameScale`.
- **Discovered zones:** zones entered at least once, plus Oakhaven by default, show their outline in the alignment colour and their name at the zone's visual centre. The name shows even while the inside is still dark, and it scales with zoom.
- **First entry into a zone:**
  - The zone banner becomes a three-line REGION DISCOVERED banner: the header, the zone name, and its alignment.
  - The alignment uses `ZoneConfig.DisplayAlignment`, so a Neutral zone reads "WILDERNESS", the same as the normal entry banner.
  - The zone's outline pulses bright twice on both maps.
  - **In-world sneak peek** (`client/Minimap/DiscoveryPeek`, tuned in `MinimapConfig.Peek`):
    - A curtain of yellow light rays runs along the zone's whole real outline, one ray per 24-stud piece of edge, so it follows the ground.
    - Each ray is an additive Beam facing the camera: solid at the base, fading toward the top.
    - The rays shoot up to about 140 studs in 0.6 s, hold for 1.3 s, then lift off and fade over 1.8 s.
    - A bright neon band on the ground traces the outline too. It shares one `Highlight` (AlwaysOnTop), so it shows through terrain and walls.

## Player markers (2026-10-10)

Your own pins: **General**, **Mining**, **Fishing**, **Combat** (`MinimapConfig.PlayerMarkerTypes`). Client: `client/Minimap/PlayerMarkers`; server: `MinimapMarkerAction` in `SSS/MinimapService`.

| On the M map | Does |
|---|---|
| Right click empty ground | The picker (four types, "Place marker 12 / 40") at the cursor |
| Click or right click a pin | Its card: distance, Track / Stop tracking, Change type, Remove |
| Hover a pin | It grows; a tooltip names it with its distance |
| `Keys.MapDeleteMarker` (Delete) over a pin | Removes it at once |
| Legend (top left) | Count per type; click a row to hide / show that type (NPCs too); Centre on me; Clear all (click twice within 3 s) |
| Scroll | Zooms toward the cursor (the ground under it stays put) |
| `Keys.MapRecentre` (C) | Back to following you |
| Esc | Closes the picker / card first, then the map |

- **Tracking** (one pin at a time, saved as `profile.map.tracked`): the pin wears a breathing ring on both maps; when it's out of view it sits on the view's edge with a pointer toward it (corner map and M map); in the world a beacon (its badge + distance, always on top) stands over it, hidden within 10 studs. Distances read in studs as "m".
- **Saving:** `profile.map.markers` as `{ id, type, x, z }` in map cells, ids from `markerSeq`. The server validates every action (known type, in-map position, cap `PlayerMarkerMax` = 40, a 0.15 s rate limit). The client updates at once and rolls back if the server refuses. The F8 map reset keeps pins; a profile wipe clears them. Legend filters are per session.
- **Input is hit-tested** from `UserInputService` (rows, pins, panels), not GuiButton events, and the M map is its own ScreenGui at `UILayers.WORLD_MAP` (300). It used to share the minimap's layer (30), under most of the HUD, and the quest tracker / banners swallowed the picker's clicks: only the first row worked.
- **Look:** a dark round plate, a ring in the type's colour, the icon. Reused art for now (`MapView.PLAYER_MARKER_ICONS`): Combat = `HudIcons.COMBAT` (sword and shield), Fishing = `ConsumableIcons.FISH`, Mining = `ItemConfig.TOOL_ICONS.Pickaxe`, General = a drawn bronze diamond. Dedicated pin art replaces them with one registry entry each.
- **Not yet:** touch (no right click; a long press is the natural gesture), names / notes on pins, sharing pins with the party, saving the legend filters.

## Files

| File | Role |
|---|---|
| `RS/MinimapConfig` | Grid, tuning, default zones, and the maths both sides share (cells, chunks, bitsets, point-in-polygon, base64) |
| `SSS/MinimapService` (Script) | Saves exploration and discovery, and raycasts chunk colours |
| `client/Minimap/init.client` | Controller: UI frames, input, local reveal, chunk images, remotes |
| `client/Minimap/MapStyle` | Turns the raw cell colours into the stylized look (blur, colour bands, parchment grade, ink shores and cliffs, soft fog edge). Pure client-side post-processing |
| `client/Minimap/MapView` | One rendering of the map in a frame; the corner and expanded maps are two MapViews over the same chunk images |
| `SSS/NpcLocations` | Publishes every registered NPC (one Folder per NpcId with `NpcType` / `Position` attributes) under `RS.NpcLocations.Markers`, tutorial copies left out; the client never needs the model streamed in |
| `RS/NpcMapMarkers` | The middle man: maps those folders onto map markers from `NPCRegistry` (name, `Nametag`) and `NpcNametagArt` (icon); `List()` + `Changed` |
| `client/Minimap/DiscoveryPeek` | The in-world see-through outline that rises and fades on a first discovery |
| `client/DevMenu/Tabs/Map` | F8 dev menu MAP tab: reset your own map |
| `SSS/ZoneService` | `SetDiscoveryHandler` hook; puts `discovered = true` on `ZoneEntryNotify` |
| `client/ZoneClient` | Entry banner, including the REGION DISCOVERED variant |
| `RS/KeybindConfig` | `ToggleMap` (M), `MapZoomIn` (`=`, keypad `+`), `MapZoomOut` (`-`, keypad `-`) |

## How it works

### The grid

- The world is a fixed grid of **4-stud cells**, one map pixel each (`CELL`), anchored at world 0,0.
- Cells are grouped into **64x64-cell chunks** (`CHUNK`, 256 studs square). Chunk keys are `"kx,kz"`.
- **The map only exists over the zones' bounding box plus `BOUNDS_MARGIN` (200) studs.** Dungeon realms sit about 100,000 studs away and never create chunks. Adding a zone grows the map automatically.

### Exploration (fog of war)

- Each chunk has a bitset of explored cells: 512 bytes, saved as base64 in `profile.map.revealed[chunkKey]`, because DataStore JSON has to stay valid UTF-8.
- **Both sides reveal the same cells:**
  - The server (`SERVER_TICK`, 0.5 s) does it for what gets saved.
  - The client (`CLIENT_TICK`, 0.15 s) does it so the map fills in instantly.
  - Both use `MinimapConfig.ForEachCellInRadius`, so they agree. The client merges the server's saved bits on load.
- **Cost:** a fully explored chunk is about 684 characters in the profile, and the current world is about 30 chunks.

### Discovery

- `profile.map.discovered[zoneId] = true`.
- `ZoneService` calls the handler registered by `MinimapService` on every zone entry. The first entry returns true, and the entry notification carries `discovered = true`.
- **Fallback:** if the profile wasn't loaded yet at the moment of entry, `MinimapService` notices the player standing in an undiscovered zone on its next tick. It fires the same `ZoneEntryNotify` itself with `discovered = true`.
- Default zones (`DefaultDiscovered`, matched by zone **name**) are marked silently and never show the banner.

### Stylized look

- The server still sends raw per-cell colours. `MapStyle.Stylize` runs once per chunk when they arrive (about 5 ms) and caches the result on the chunk entry; `MapStyle.Compose` runs on every re-render (about 1.5 ms) and applies the reveal mask.
- Stylize blurs 3x3 without mixing water and land, flattens brightness into `BANDS` levels, desaturates and warms it, then inks land next to water and the brink of steep drops.
- Compose fades explored cells that touch fog into the fog, so the edge of what you have seen is a soft cloud. Unexplored ground is the dark parchment `MapStyle.FOG`, not black.
- Tiles use bilinear sampling (`ResamplerMode.Default`). Setting them back to `Pixelated` brings the hard pixel look back.
- Tuning is the constants at the top of `MapStyle.luau`.

### Colours

- **Raycasting:** the server raycasts each cell top-down on the **first request** for a chunk (`MinimapChunkRequest`) and caches it for the server's lifetime. There is no bake step, so the map follows whatever is built. A chunk takes about 4,000 rays at about 0.04 ms each, spread over frames.
- **Skipped:** characters, mobs and NPCs (anything under a Model with a Humanoid or AnimationController), and parts with Transparency of 0.9 or more. The ray continues below them.
- **Colour rules, in order:**
  1. A Color3 attribute **`MapColor`** on the part or any ancestor Model wins. Use it to fix anything that reads wrong.
  2. Terrain uses `Terrain:GetMaterialColor`; water uses `WaterColor`.
  3. Textured meshes (SurfaceAppearance or TextureID) have their real colour in the texture, so they fall back:
     - a foliage-looking name (leaf, tree, bush, flower, hedge, shrub, "árvore") becomes dark green;
     - anything else uses a colour per Material, or a grey-brown.
  4. Everything else uses `part.Color`.
- **Height shading:** like a Minecraft map, a cell higher than the one north of it is lighter and a lower one is darker.

### Rendering

- Each visible chunk is one 64x64 `EditableImage` with pixelated resampling, shared by both views through `Content.fromObject`.
- Unexplored pixels are transparent over the black map background.
- Zone outlines are thin rotated Frames per polygon edge, and names are TextLabels. All positions are in map cells, re-laid out on zoom.
- The player arrow is drawn once into a small EditableImage, so no uploaded asset is needed.
- NPC markers (`MapView:SetNpcMarkers`) live on the canvas like the zone names, so panning costs nothing. The controller filters them to uncovered cells on every reveal tick and only re-sends them when the visible set changes.

## Remotes (ReplicatedStorage.GameEvents)

| Name | Type | Direction | Payload |
|---|---|---|---|
| `MinimapStateRequest` | RF | C -> S | returns `{ discovered = { [zoneId] = true }, revealed = { [key] = buffer }, markers = { { id, type, x, z } }, tracked = id }`; waits up to 20 s for the profile |
| `MinimapMarkerAction` | RF | C -> S | `("add", type, x, z)` returns `true, marker` or `false, err` (`bad_type`, `bad_position`, `full`, `too_fast`); `("remove", id)`, `("retype", id, type)`, `("track", id or nil)`, `("clear")` return `true` or `false, err` |
| `MinimapChunkRequest` | RF | C -> S | `(keys)` returns `{ [key] = buffer }` of 64*64*3 RGB bytes; at most 16 keys per call, in-bounds chunks only |
| `ZoneEntryNotify` | RE | S -> C | existing zone-entry event, now with `discovered` |
| `MinimapDevAction` | RF | C -> S | `("reset")` returns `ok, err`; dev-only (`DevRoster`), wipes the caller's own discoveries and explored cells (markers kept) |
| `MinimapReset` | RE | S -> C | the map was reset; the client forgets everything and reloads from the server |

`profile.map` is **stripped from the profile push** (`BuildSnapshotPayload`). The client gets it through `MinimapStateRequest` only.

## Tuning (`RS/MinimapConfig`)

| Setting | Default | What it does |
|---|---|---|
| `REVEAL_RADIUS` | 48 | Studs around the player that get explored |
| `CELL` | 4 | Studs per map pixel. **Changing it invalidates every saved bitset.** |
| `CHUNK` | 64 | Cells per chunk side. **Same warning.** |
| `BOUNDS_MARGIN` | 200 | Map beyond the zones' bounding box |
| `DefaultDiscovered` / `DefaultRevealed` | `{ Oakhaven = true }` | By zone name |
| `MiniSize` / `MiniScale` | 247 px / 2.6 | Corner minimap size, and pixels per cell (about 380 studs across). Grown 30% on 2026-10-06 (was 190 / 2) |
| `BigMinScale` / `BigMaxScale` / `ZoomStep` | 0.5 / 8 / 1.25 | Expanded-map zoom |
| `NpcMarkerMiniPx` | 21 | NPC crest size on the corner map |
| `NpcMarkerPerCell` / `NpcMarkerBigMin` / `NpcMarkerBigMax` | 8 / 18 / 32 | NPC crest size on the expanded map: px per cell, clamped |
| `PlayerMarkerMax` | 40 | Your own pins, per player |
| `PlayerMarkerMiniPx` / `PlayerMarkerPerCell` / `PlayerMarkerBigMin` / `PlayerMarkerBigMax` | 18 / 7 / 18 / 30 | Pin size: corner map fixed; expanded map px per cell, clamped |
| `NpcNameScale` | 5 | Expanded-map zoom (px per cell) from which NPC names show; with `ZoomStep` 1.25 from the default 2 that's the fifth notch (6.1). Lower it and close NPCs' names (the Merchant and Auctioneer) start to touch |

The corner minimap's screen position is `mini.Position` in `client/Minimap/init.client`, top right just below the top bar. The quick-nav buttons under it are drawn 1.3x (`HudQuickNav.SCALE`). The party panel lives top left, under Roblox's own buttons (`PartyClient`), so the right side is the map's alone.

## Testing: F8 MAP tab

**Reset My Map** (click twice to confirm) wipes your discoveries and explored ground. Oakhaven comes back as the default. The map reloads at once, and the region you're standing in is re-discovered within half a second, with the banner, map pulse and in-world peek. That makes it the quick way to replay a discovery.

## Known limits (MVP)

- **Map colours are computed on the server:** raycasts only see what the server has loaded. That is everything, since the server doesn't stream.
- **Colours are cached per server:** a building moved in a live server shows its old colour until the server restarts.
- **Textured buildings:** these come out as their Material colour or grey-brown. Tag them with `MapColor` where it matters.
- **Map orientation:** always north up. There's no rotating minimap mode.
- **Missing features:** no dungeon or party-member markers, no touch pinch-zoom, and player markers can't be placed on touch yet.
