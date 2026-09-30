# World Map and Minimap

The top-down map of the overworld: a corner minimap, an expanded map on **M**, fog of war that fills in as you walk, and region discovery.

## What the player sees

- **Corner minimap:** top right, always on in the overworld, hidden inside dungeons.
  - Centred on the player, north up.
  - A white arrow turns with the way the character faces.
  - An `[M] Map` hint sits under it.
- **Expanded map (M):** opens centred on the player.
  - Zoom with the scroll wheel or `+` / `-`; the controls are listed in the bottom-right corner.
  - Drag to look around. M or Esc closes it, and reopening re-centres on the player.
- **Fog of war:** everything is black except:
  - ground the player has walked near (within `REVEAL_RADIUS` studs), saved to the profile;
  - zones in `DefaultRevealed` (Oakhaven), shown in full from the start;
  - **safe zones:** a discovered zone whose alignment is in `AutoRevealAlignments` (Lawful) shows in full the moment it's discovered. Towns are never gated behind exploring them. This is derived on the client from the discovered set; the server saves no cells for it.
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

## Files

| File | Role |
|---|---|
| `RS/MinimapConfig` | Grid, tuning, default zones, and the maths both sides share (cells, chunks, bitsets, point-in-polygon, base64) |
| `SSS/MinimapService` (Script) | Saves exploration and discovery, and raycasts chunk colours |
| `client/Minimap/init.client` | Controller: UI frames, input, local reveal, chunk images, remotes |
| `client/Minimap/MapView` | One rendering of the map in a frame; the corner and expanded maps are two MapViews over the same chunk images |
| `client/Minimap/DiscoveryPeek` | The in-world see-through outline that rises and fades on a first discovery |
| `client/DevMapTab` | F8 dev panel MAP tab: reset your own map |
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

## Remotes (ReplicatedStorage.GameEvents)

| Name | Type | Direction | Payload |
|---|---|---|---|
| `MinimapStateRequest` | RF | C -> S | returns `{ discovered = { [zoneId] = true }, revealed = { [key] = buffer } }`; waits up to 20 s for the profile |
| `MinimapChunkRequest` | RF | C -> S | `(keys)` returns `{ [key] = buffer }` of 64*64*3 RGB bytes; at most 16 keys per call, in-bounds chunks only |
| `ZoneEntryNotify` | RE | S -> C | existing zone-entry event, now with `discovered` |
| `MinimapDevAction` | RF | C -> S | `("reset")` returns `ok, err`; dev-only (`DevRoster`), wipes the caller's own `profile.map` |
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
| `MiniSize` / `MiniScale` | 190 px / 2 | Corner minimap size, and pixels per cell (about 380 studs across) |
| `BigMinScale` / `BigMaxScale` / `ZoomStep` | 0.5 / 8 / 1.25 | Expanded-map zoom |

The corner minimap's screen position is `mini.Position` in `client/Minimap/init.client`, top right just below the top bar. The party panel sits at 20% down the right side, so move one of them if they crowd each other.

## Testing: F8 MAP tab

**Reset My Map** (click twice to confirm) wipes your discoveries and explored ground. Oakhaven comes back as the default. The map reloads at once, and the region you're standing in is re-discovered within half a second, with the banner, map pulse and in-world peek. That makes it the quick way to replay a discovery.

## Known limits (MVP)

- **Map colours are computed on the server:** raycasts only see what the server has loaded. That is everything, since the server doesn't stream.
- **Colours are cached per server:** a building moved in a live server shows its old colour until the server restarts.
- **Textured buildings:** these come out as their Material colour or grey-brown. Tag them with `MapColor` where it matters.
- **Map orientation:** always north up. There's no rotating minimap mode.
- **Missing features:** no markers yet (NPCs, dungeons, party members), and no touch pinch-zoom.
