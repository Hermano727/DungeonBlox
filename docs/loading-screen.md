# Loading screen

The painted screen a player sees while the game loads: the sunset tree as the backdrop, a "Loading..." word whose letters hop one at a time, a gold bar that fills as assets arrive, and a rotating tip. It fades through black into the game.

- **Code:** `src/replicatedfirst/LoadingScreen/init.client.luau` (a LocalScript in ReplicatedFirst).
- **Art ids:** `src/replicatedfirst/LoadingScreen/LoadingArt.luau`, its own small registry (see "Why it lives in ReplicatedFirst").
- **Rojo:** `default.project.json` maps only `ReplicatedFirst/LoadingScreen`. The `ReplicatedFirst` node has no `$path`, so Rojo leaves the Studio-owned `ReplicatedFirst.CharacterParts` folder alone. Never give `ReplicatedFirst` itself a `$path`: Rojo would delete `CharacterParts`.

## How it works

This is the standard Roblox pattern:

1. A LocalScript in ReplicatedFirst builds its own ScreenGui (`DisplayOrder` 10000, `IgnoreGuiInset`) with every piece already in place under a closed black curtain, and preloads that ScreenGui (`PreloadAsync({ gui })`) on its own, before anything else is requested. Roblox's default screen stays up meanwhile. Once its art is in (or after `OWN_ART_TIMEOUT`, 6 s), it waits two frames so the art is drawn, not just downloaded, calls `RemoveDefaultLoadingScreen()` and opens the curtain (`REVEAL`, 0.5 s): the painting, bar and leaves appear together instead of one by one.
   - Why the order matters: `PreloadAsync` has no priority setting, and "loaded" only means downloaded. Requesting the screen's art alone, first, keeps the hundreds of bulk assets from competing with it; drawing it behind the curtain means it's on the GPU when shown.
2. It waits on real work, not a fixed timer, and moves the bar as each step finishes:

| Step | Bar | Timeout |
|---|---|---|
| `game.Loaded` (everything has replicated) | 0 to 10% | `MAX_WAIT / 3` |
| `ContentProvider:PreloadAsync` on the important assets, counted one by one | 10 to 85% | `PRELOAD_TIMEOUT` (25 s) |
| The character has spawned with a `HumanoidRootPart` | 85 to 100% | `CHARACTER_TIMEOUT` (20 s) |

3. Once loaded (and at least `MIN_SHOW`, 2.5 s, after the reveal) the bouncing word gives way to a pulsing "Click anywhere to start" ("Tap anywhere to start" on touch-only devices). Loading itself never takes longer than `MAX_WAIT` (60 s); the click wait has no limit (the failsafe only covers the loading part).
   - A full-screen invisible button takes the click, so the same click doesn't swing a sword or fire a bow in the game underneath. Enter, Space and a gamepad's A also start.
4. On the click: fade to black (`FADE_OUT`), destroy the screen, set the player attribute `LoadingScreenDone = true`, then fade the game in (`FADE_IN`).

**What gets preloaded:**
- every id in `RS/Assets/Icons/*` and `RS/Assets/Images/*` (UI art and item icons)
- the sound effects in `RS/Assets/Sounds/SoundEffects`, as Sound instances
- the clips in `RS/Assets/Animations/*`, as Animation instances
- the face decals in `RS/Assets/Appearance` (eyes, nose, mouth)
- `ReplicatedFirst.CharacterParts` (hair and beard meshes with their textures)
- the images already sitting in the player's GUIs

Music and meshes are left out on purpose: tracks are large and only heard later, and the world uses streaming (`Workspace.StreamingEnabled`), so meshes arrive with the world around the spawn point.

**Waiting on the screen:** anything that should start after it clears (a welcome banner, a cutscene) waits on the `LoadingScreenDone` player attribute.

```lua
if not player:GetAttribute("LoadingScreenDone") then
	player:GetAttributeChangedSignal("LoadingScreenDone"):Wait()
end
```

## Why it lives in ReplicatedFirst

- **It has to run first.** ReplicatedFirst is the only container whose contents reach the client before the rest of the game, so it's the only place a loading screen can run from.
- **It can't use the normal registries.** Until `game.Loaded`, nothing in ReplicatedStorage can be relied on, so the screen can't require `RS/Assets/...` or `UIFonts`.
  - Its art ids live in its own child module, `LoadingArt` (shared ids such as the glow and grain are copied from `HudArt` and marked).
  - Its font is Merriweather, which is bundled with Roblox and needs no download.
- **It must not listen to `DungeonProfilePush` or any other game RemoteEvent.** A RemoteEvent fired before anyone listens is queued and delivered to the FIRST listener only. If the loading screen connected first, it would swallow the profile snapshot that `DungeonMenuNet` needs. That's why step 3 waits on the character, not the profile.

## The screen

- **Backdrop:** `loading_bg.png` (1747x900), split into `loading_bg_l` / `_r` so each half stays under the 1024 px UI cap at full resolution. It's drawn cover-fit and centred on any screen shape, fades in once downloaded over a night-dark base (no white flash), and slowly zooms in by 4% over 40 s.
- **Shade:** a black gradient rises from the bottom so the bar and text read over the bright grass.
- **The word:** "Loading..." in Merriweather Bold. Each letter is its own label: one letter hops at a time, left to right, brightening to gold at the top of its hop, then a short pause and it starts again.
  - Tuning: `HOP_STEP`, `HOP_TIME`, `HOP_HEIGHT`, `HOP_REST`.
- **The bar:**
  - Fill: a gold gradient with the HUD's drifting grain (`HudArt.BAR_GRAIN`), in its frame.
  - Leading edge: a soft glow.
  - Frame: the bronze double rail with scrolled end caps; the fill runs between the rails (the Journal's bar trough is the stand-in if the frame id is ever empty). A golden leaf rides the leading edge, rocking gently.
- **Start prompt:** "Click anywhere to start" in the word's place once loaded, pulsing between bone and gold.
  - Progress eases toward the real value and never runs backwards.
- **Ambience:** golden specks of light drift up through the scene. Leaves (gold, green, brown, orange) drift down and to the right with the breeze.
- **Tips:** one at a time under the bar, crossfading every 6 s. Plain sentences about real rules, in the game's grim tone, no dashes. Edit `TIPS` in the script.

## Art

All in place (2026-10-04). Source files live in `assets/UI/loading screen/` under the names they were generated with: the painting (`Loading Screen 1.png`), the bar frame (`Ornate Golden Double-Rail UI Frame.png`), the leaf on the bar (`Golden Autumn Leaf Game Icon.png`) and the drifting leaves: gold and green from `Autumn Maple Leaf Icon Trio.png` (its half-green leaf is unused), brown (`Glossy Autumn Maple Leaf Sticker.png`) and orange (`Autumn Maple Leaf Sticker.png`). They were trimmed / edge-bled / capped in memory with the `tools/ui_assets/process.py` helpers and uploaded straight from a scratch folder; no renamed copies are kept in the repo. The trio is ONE uploaded image, each leaf shown through its own `ImageRectOffset`/`ImageRectSize` (`LoadingArt.Leaves`; a zero size means the whole image).

The prompts below are kept for re-rolls. Shared rules ([UI Development Process](./ui-development-process.md)): attach the painting plus an in-game screenshot of the Journal or HUD bars and say "match the attached style exactly"; transparent background; no text.

Shared palette:

| Use | Hex |
|---|---|
| Bronze rim | `#AC966C`, shadow `#6B5536`, highlight `#E3CFA0` |
| Dark outline | `#1A120C` |
| Leaf gold | `#F2C45A`, shadow `#C98A2E`, highlight `#FFE7A3` |
| Leaf green (T1) | `#5E7F3E`, shadow `#3A5530` |
| Sunset accent | `#F6A04D` |

### 1. `loading_bar_frame.png` (the bar's frame)

> Flat 2D game interface element, not a real object. Match the attached style exactly. A long, thin horizontal loading bar frame for a fantasy game, front-on with no perspective, about 10 times wider than it is tall. A bronze rim with a dark outline (#1A120C) runs round the whole frame; the rim is bronze #AC966C with one shadow tone #6B5536 and a thin highlight #E3CFA0, in two-tone cel shading lit from the top left. Each end has a small ornament: a curled bronze leaf with a tiny sprig of green leaves (#5E7F3E, shadow #3A5530) wrapping the end cap. The long top and bottom edges are straight and even along their whole length, with no decoration in the middle, so the frame can be stretched. The inside of the frame is completely empty and fully transparent: draw only the rim and the end ornaments. Transparent background, no drop shadow, generous empty margin around the frame, no text.

Save as `assets/ui/incoming/loading_bar_frame.png`.

### 2. `loading_bar_leaf.png` (the leaf on the fill's leading edge)

> Flat 2D game interface element, not a real object. Match the attached style exactly. A single small golden leaf, like the sunlit leaves of the tree in the attached painting, seen flat and front-on, pointing up and slightly to the right. Two-tone cel shading: base #F2C45A, one shadow shape #C98A2E that follows the leaf's fold, a thin highlight #FFE7A3 on the lit edge, light from the top left, and a clean dark outline #1A120C. A short stem at the bottom. A soft warm glow is NOT part of the image. Transparent background, no drop shadow, generous margin, no text.

Save as `assets/ui/incoming/loading_bar_leaf.png`.

### 3. `loading_leaves.png` (three drifting leaves, one sheet)

> Flat 2D game interface elements, not real objects. Match the attached style exactly. Three separate single leaves in a row, left to right, with wide clear empty gaps between them so they can be cut apart:
> 1. a golden leaf (base #F2C45A, shadow #C98A2E)
> 2. a green leaf (base #5E7F3E, shadow #3A5530)
> 3. a leaf turning from green to gold
>
> All three are maple-like leaves like the ones on the tree in the attached painting, each turned at a slightly different angle, flat and front-on. Two-tone cel shading with one shadow shape per leaf, light from the top left, thin dark outline #1A120C. Transparent background, no drop shadow, no text.

Save as `assets/ui/incoming/loading_leaves.png`.

### 4. (Optional) `loading_logo.png` (the game's wordmark)

The one exception to "no text": a logo is art, not UI copy. Skip it until the game's name and identity are settled; the screen doesn't need it.

> Match the attached style exactly. A fantasy game logo reading "DungeonBlox", carved into a weathered bronze plaque wrapped with a few green leaves and one golden leaf. Bold, chunky, slightly uneven serif lettering in bronze (#AC966C, shadow #6B5536, highlight #E3CFA0) with a dark outline (#1A120C), two-tone cel shading lit from the top left, flat and front-on. Spell the name exactly: D-u-n-g-e-o-n-B-l-o-x. Transparent background, no drop shadow, generous margin.

Save as `assets/ui/incoming/loading_logo.png`. Needs a spot in the layout (top centre) when it arrives.

### Why no art for the text or the fill

- **"Loading..."** is drawn by the game in Merriweather Bold. Each letter has to move on its own, and baked text would blur and can't be translated.
- **The fill** is a code gradient plus the HUD's grain texture, the same as the HP, energy and XP bars, so all the bars match.

## Swapping a piece

1. Process it in memory (`trim`, `bleed_edges`, `cap_size` from `tools/ui_assets/process.py`), upload with the Studio MCP `upload_image`.
2. Update its entry in `LoadingArt`. For the frame: the slice centre must sit in the empty gap between the rails, `SliceScale` x the image height = `BAR_H`, and `FillInset` puts the fill between the rails. For the leaf sheet: each leaf's rect in the uploaded image's pixels.

## Tuning (top of the script)

| Constant | Default | What it does |
|---|---|---|
| `MIN_SHOW` | 2.5 s | shortest time on screen, from the reveal |
| `OWN_ART_TIMEOUT` / `REVEAL` | 6 / 0.5 s | longest wait for the screen's own art; its fade in |
| `PRELOAD_TIMEOUT` / `CHARACTER_TIMEOUT` / `MAX_WAIT` | 25 / 20 / 60 s | when to stop waiting |
| `FADE_OUT` / `FADE_IN` | 0.6 / 0.8 s | the fade through black |
| `WORD_SIZE`, `HOP_*` | 40, ... | the bouncing word |
| `BAR_H`, `BAR_MAX_W` | 34, 640 px | bar size (narrower on small screens: window width minus 64) |
| `MOTES`, `LEAVES` | 16, 9 | ambient particles |
