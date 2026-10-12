# Dungeon Clear Sequence: asset requests

Everything the clear sequence ([Dungeon Clear Sequence](./dungeon-clear-sequence.md)) wants from you. It works today without any of it: each item below has a stand-in. Delivering one only means dropping it in its registry key.

Where things go:

- **Images:** save to `assets/vfx/DungeonClear/incoming/` under the file name given. Claude processes them (`tools/vfx_assets/process.py`, mode in brackets) and uploads them.
- **Tripo models:** export to `assets/vfx/DungeonClear/tripo/`. Claude cleans them in Blender, uploads them and registers them.
- **Sounds:** an mp3/ogg file, or a Creator Store id you approve.

## Images (ChatGPT)

**Status 2026-10-10: all six delivered and live** (ids in `RS/Assets/Images/ClearSequenceArt`, sources in `assets/vfx/DungeonClear/incoming/` under their own names). The prompts below stay as the record of what produced them, and as the template for future VFX textures.

These match the style of the Kane textures in `assets/vfx/FireTornado/side effect images/`: white with flat grey bands, swirly calligraphic wisps, small loose flecks, no soft glow.

**How to send each one:**
1. Attach the reference named in its entry and paste the shared preamble.
2. Then paste the piece's own prompt.
3. Choose the canvas listed. ChatGPT only makes square, landscape (3:2) or portrait (2:3), so never ask for pixel sizes; `process.py` crops and resizes.

**Shared preamble:** the VFX-texture preamble in [Art Direction & Image Generation](./art-direction.md#4-vfx-textures-particles-beams-flipbooks), section 4 (paste it first, every time).

Beam textures (feather, light shaft) run **horizontally**: Roblox stretches a Beam texture's left-to-right axis along the beam's length.

### 1. `T_ClearFeather.png` [tile] → `ClearSequenceArt.FEATHER`
- **Reference:** `T_FlameStreak.png`. **Canvas:** landscape.
- **Used for:** the Benediction's wing feathers. Each one is a Beam stretched from the glowing core (left) to the feather's tip (right), about 20 at once forming two wings.
- **Stand-in today:** a solid tapered band of light.
- **Prompt:**
  > One long stylized angel-wing feather lying horizontally across the whole width of the image, quill end touching the left edge, tip touching the right edge, vertically centred with black above and below. A thin bright quill along its length, a vane that widens from the quill end and tapers to a pointed tip, 5 or 6 gentle notches along the vane's edges breaking into a few small wispy flecks. The grey shadow shape runs along the lower half of the vane.

### 2. `T_ClearLightShaft.png` [lum] → `ClearSequenceArt.LIGHT_SHAFT`
- **Reference:** `T_FlameStreak.png`. **Canvas:** landscape.
- **Used for:** the Benediction's shaft of light pouring from the ceiling to the floor. It is a camera-facing Beam, so the image's LEFT edge is the ceiling and its RIGHT edge is the floor.
- **Stand-in today:** a flat band with a transparency ramp.
- **Prompt:**
  > A shaft of holy light lying horizontally across the whole width of the image: a band of long parallel light rays running left to right, brightest and solid along the horizontal centre line, broken into separate grey ray-streaks toward the top and bottom edges, which fade to pure black. Strongest at the left end, gradually thinning and breaking up toward the right end. Rays only: no dust specks, no sun disc, no objects.

### 3. `T_ClearEmber.png` [lum] → `ClearSequenceArt.EMBER`
- **Reference:** `T_Spark.png`. **Canvas:** square.
- **Used for:** the embers your score pours into each brazier, and the sparks off the relics. Each particle is drawn tiny and stretched along its direction of travel.
- **Stand-in today:** Roblox's built-in sparkle.
- **Prompt:**
  > One single ember in the centre of the image, small (about a fifth of the image width): a bright white teardrop core with a short tapering flame-wisp tail trailing straight down, and two tiny detached flecks beside the tail. Lots of empty black space around it.

### 4. `T_ClearFire_4x4.png` [grid4] → `ClearSequenceArt.FIRE`
- **Reference:** `T_SmokePuff_4x4.png` (for the grid layout and style). **Canvas:** square.
- **Used for:** the brazier flames, the Mythic relic's fire, the winners' pillars of fire. It is a particle flipbook: each particle shows one random cell, so every cell must be a complete flame on its own.
- **Stand-in today:** Roblox's built-in fire.
- **Prompt:**
  > A 4 by 4 grid of 16 separate stylized flame licks, laid out like the attached sheet: each flame centred in its own equal square cell, with clear black space between cells (nothing crosses a cell border). Every flame points upward with a wide rounded base and curling, tapered tips, all a similar size, but each a different silhouette: some single tongues, some forked, some with one or two detached flecks flicking off the top. No smoke, no sparks between cells.

### 5. `T_ClearSparkle.png` [lum] → `ClearSequenceArt.SPARKLE`
- **Reference:** `T_Spark.png`. **Canvas:** square.
- **Used for:** dust motes in the light shaft, glints shed from the wings, the reveal bursts. Drawn tiny, so the silhouette must read at a few pixels.
- **Prompt:**
  > One four-point star glint in the centre of the image, small (about a quarter of the image width): a round white core with four thin sharp tapering rays (up, down, left, right), the vertical rays a little longer. Lots of empty black space around it.

### 6. (optional) `T_ClearShroudBurn_4x4.png` [grid4]
- **Reference:** `T_SmokePuff_4x4.png`. **Canvas:** square.
- **Used for:** scraps of burning cloth flying off a relic while its shroud burns away. A MeshPart texture can't dissolve, since its alpha is ignored (docs/vfx-pipeline.md), so the burn is sold with particles.
- **Stand-in today:** fire particles while the shroud shrinks and fades.
- **Prompt:**
  > A 4 by 4 grid of 16 small torn scraps of burning cloth, laid out like the attached sheet: each scrap centred in its own equal square cell with clear black space between cells. Each scrap a ragged rag shape whose torn edge is curling into small flame wisps, the cloth itself in the grey shadow tone and the burning edge in bright white. Every scrap a different shape and tilt.

**Already have it (no request):** the smoke for ash and the boss echo uses your `T_SmokePuff_4x4` (WorldVfx). `T_ShockRing` and `T_FlameStreak` could also replace two stand-ins without any new art: the Neon-disc shockwaves on Legendary reveals and the final tear, and the fire pillars. Say the word and I'll swap them in.

## Models (Tripo)

The game colours these itself: one material each, base colour only, no text.

Paste the 3D-model preamble from [Art Direction & Image Generation](./art-direction.md#1-3d-models-chatgpt-concept-image-then-tripo) (section 1) first, then the piece.

### 7. Brazier → `VfxMeshes.CLEAR_BRAZIER`
- **DONE (2026-10-10), live as `VfxMeshes.CLEAR_BRAZIER`.**
  - Concept: `assets/models/dungeons/Brazier (dungeon completion).png`.
  - Tripo export: `assets/models/dungeons/Dungeon Brazier/`.
  - Cleaned by `assets/models/dungeons/build_clear_props.py`: renamed (no Tripo ids), 4.8 studs, coal bed added at 60% of the bowl's depth. The output is `DungeonBrazier_ImportReady.fbx`.
- **Target:** about 4.8 studs tall, origin at the floor centre, 500 to 3k triangles (prop class).
- **The glowing coal bed is NOT in the concept.** Claude models it in Blender as its own object, `Coals`, next to `Brazier` (the client finds both by name and lights the coals itself).
- **Prompt** (the one that produced the approved concept):
  > A medieval iron fire brazier: a wide, shallow round bowl with a thick rolled rim and a simple band of six big round rivets around it, on one thick stem with a bulging knuckle in the middle, braced by three chunky scroll-curled legs down to a heavy round base plate. The bowl is empty: no fire, no coals. Dark blackened iron painted in flat tones (base #3A3532, shadows #24201E) with broad worn steel-grey highlights on the rim, rivets and leg curls (#7C746C), and a touch of warm rust colour in the corners (#6B3A26). Simple, chunky, symmetrical, about as tall as a person's chest.

### 8. Shrouded relic → `VfxMeshes.CLEAR_RELIC`
- **DONE (2026-10-10), live as `VfxMeshes.CLEAR_RELIC`.**
  - Concept: `assets/models/dungeons/Shrouded relic (dungeon completion).png`.
  - Tripo export: `assets/models/dungeons/Dungeon Shrouded Relic/`.
  - Same script as the brazier: 3 studs, one textured `Relic` mesh, plus an `EmberGlow` shell.
- **Target:** about 3 studs, origin at the centre, 500 to 3k triangles.
- **Objects:** `Relic` (cloth and chains in one textured mesh) and `EmberGlow`, a copy scaled 1.04 that the game turns into a faint Neon glow showing the rarity climb.
- **Prompt** (the one that produced the approved concept):
  > A round bundle wrapped in heavy dark cloth, about the size of a large melon, sitting upright. Smooth and full, with a few large soft folds (not many small wrinkles), gathered at the top into one neat twisted knot with a short tuft of cloth sticking up. Only one or two small torn corners in total; the cloth is mostly whole and tidy. Bound by two thick iron chains with big simple links, lying tight against the cloth: one around the middle, one over the top and down both sides. Cloth painted in flat dark umber (#3E302A) with soft lighter fold highlights (#6A5448). Chains in dark iron (#3E3A38) with broad grey edge highlights (#8A847E). Grim and sealed, but clean and readable.
- **First attempt (rejected):** photoreal burlap with torn edges everywhere. Why it failed: [Art Direction](./art-direction.md), "Rejected".

### 9. Mythic item models → `LootDropVisuals` (a new `ByMythicKey` lookup) + the held weapon
- **Today:** the revealed Mythics show the generic T1 Training Sword / Chestplate meshes.
- **Want:** the real items, so the reveal shows what was won (and so they can be equipped as themselves):
  - `MiasmaBlade`: "Miasma, the Devouring Tide", a one-handed sword.
  - `MiasmaCarapace`: "Miasma Carapace", a chestplate.
- **Workflow:** a ChatGPT concept image, then Tripo; the rules are in [Asset & Naming Conventions](./asset-conventions.md#weapon-and-gear-models-chatgpt-concept-then-tripo).
  - Attach a screenshot of the T1 sword for scale and style.
  - Pick a direction, or mix two.
  - Tripo export goes to `assets/models/armor weapons equipment/mythic miasma blade/`.

#### `MiasmaBlade` concept directions
- **What it is:** Miasma is the T1 dungeon boss: a many-eyed poison slime that hangs from the ceiling of the Blighted Aqueducts (grey masonry, monumental flood gates, valves, sludge channels).
- **Palette:** deep violet-black `#100B14`, bruised purple `#783C96`, pale lilac `#E2D6EC`, sickly moss green `#CDD7BE` / `#28371A`, corroded iron grey `#4A4A4E`.
- **The item's stats:** crit, life steal and poison (elemental) damage. It is a Mythic, so it should look like the best thing in T1, not a common sword with a tint.
- **Prompting:** paste the 3D-model preamble ([Art Direction](./art-direction.md) section 1), then *"A one-handed sword standing vertically, tip pointing straight up, the broad flat of the blade facing the camera; the blade about three times the length of the grip."*, then ONE direction below. These directions were written before the preamble was settled: if a result comes out too detailed or photoreal, cut the direction's wording down to its big shapes.

**A. The Devouring Tide** (the name, literally)
> A one-handed sword whose blade is a cresting wave of solidified violet sludge frozen mid-break: the edge curls forward into two hooked wave crests near the tip, and the flat of the blade shows layered ripple bands from bruised purple at the spine to pale lilac at the edge. A dark corroded-iron spine runs up the back of the blade. The crossguard is two short curled wave crests, the grip wrapped in dark leather, the pommel a round drop of hardened sludge. Colours: violet-black #100B14, bruised purple #783C96, pale lilac #E2D6EC, corroded iron #4A4A4E.

**B. The Many-Eyed**
> A straight one-handed broadsword of dark corroded iron with a wide fuller. Set into the fuller, a vertical row of five half-lidded eyes of different sizes, glossy and sickly yellow-green with slit pupils, the iron around them swollen like flesh. The crossguard is a thick bar ending in two clenched eyelids, the grip wrapped in dark purple-stained leather, the pommel a single large closed eye. Colours: iron #4A4A4E, violet-black #100B14, bruised purple #783C96, eyes moss green #CDD7BE with dark #28371A pupils.

**C. The Sluice Key** (the arena: flood gates and valves)
> A one-handed sword built like a piece of an ancient aqueduct: a heavy straight blade of weathered grey stone-coloured steel, with a deep channel down its centre filled with hardened violet sludge. The crossguard is a small iron valve wheel set sideways (spokes visible, thick and solid), the grip wrapped in dark rope, the pommel a squared masonry block with a carved drip-channel. Rust and moss-green staining at the joins. Colours: weathered grey #6E6A66, iron #4A4A4E, sludge #783C96, moss #CDD7BE.

**D. The Rot-Eaten Executioner**
> A heavy one-handed blade with a squared, slightly widening tip, the steel eaten through by rot: large irregular corroded holes and pitted edges, every hole rimmed in thick violet-black crust with pale lilac at its lips, as if something dissolved its way through. The crossguard is a simple heavy bar, half dissolved on one side, the grip wrapped in grey bandage cloth, the pommel a cracked iron cap. Colours: iron #4A4A4E, crust #100B14, bruised purple #783C96, lilac #E2D6EC.

**E. The Leech Fang** (life steal)
> A one-handed sword with a long, gently curved blade shaped like a parasite's fang: a serrated inner edge of small backward-hooked teeth, a smooth outer edge, a pointed tip. The blade is translucent-looking bruised purple shading to violet-black at the spine, with thin darker veins running from the hilt toward the tip. The crossguard is a ring of short ridged segments like a leech's mouth, the grip ribbed in segments, the pommel a closed sucker disc. Colours: violet-black #100B14, bruised purple #783C96, lilac #E2D6EC, vein #28371A.

**F. The Plague Vessel**
> A straight one-handed sword of dark iron with two shallow fullers running the blade's length, both filled with hardened moss-green venom. At the centre of the crossguard, a thick glass vial set in an iron cage of solid bars, full of swirling violet sludge (painted inside the glass, nothing floating outside). The crossguard arms end in downturned drip shapes, the grip wrapped in dark purple leather, the pommel a stoppered flask cap. Colours: iron #4A4A4E, venom #CDD7BE / #28371A, sludge #783C96, glass lilac #E2D6EC.

**Tips:**
- **Mixing two directions:** "Edit the attached image: keep its blade exactly, replace the crossguard and hilt with <the other direction's hilt text>".
- **Tripo glass:** a glass vial (F) comes out solid in Tripo. That's fine, since the painted swirl carries it. Ask ChatGPT for an opaque-looking vial if it reads badly.

#### `MiasmaCarapace` (later)
Same workflow and palette, the 3D-model preamble, the armour view (front, as worn, on no body). Ask Claude for its directions when you get to it.

## Sounds

These are first picks from the licensed Pro Sound Effects / APM libraries. They were **chosen by catalogue description only, not listened to**: approve or swap. Empty ones play nothing.

| Key (`SoundEffects`) | Moment | Today |
|---|---|---|
| `ClearChoir` | the Benediction's light descends | APM "Drama Sting 7" (choir, two chords, 7 s) |
| `BrazierRise` | braziers grind up out of the floor | Pro "Rock Scrape Huge Boulder" |
| `EmberPour` | score pours in as embers | *empty*: want a soft rising crackle, 2 s |
| `ScrapBurn` | the low rolls burn off | *empty*: want a short fire puff |
| `RelicTick` | each rung of a relic's rarity climb (pitched up per step) | Pro "Tuning Fork 4" |
| `RelicBurn` | a shroud catches fire | *empty* |
| `RevealCommon` / `RevealUncommon` | reveals (only seen at T3+ / T5) | *empty* |
| `RevealRare` | Rare reveal | Pro "Fork Tine Pluck" |
| `RevealEpic` | Epic reveal | APM "Showdown At The Docks 18" (single low hit) |
| `RevealLegendary` | Legendary reveal | APM "Cryptic Veil - Sting 1" |
| `BossEchoRoar` | the main boss's echo rises | Miasma's own roar |
| `MiniEchoRise` / `EchoShatter` | a miniboss echo rises / shatters | *empty* |
| `EchoTear` | the final echo is torn apart | Pro "Whoosh Combo Of Impacts" |
| `MythicDescend` | the Mythic sinks out of the dark | *empty*: want a low rising drone, 2.5 s |
| `JudgementTick` | the beam lands on a loser | Pro "Fork Tine Pluck 9" |
| `MythicWin` | the beam flares on a winner | APM single low hit |
| `MythicToll` | nobody won, the relic crumbles | Pro "Church Bell Tolling 1" (18 s, cut at 10) |
| `MythicBroadcast` | the server-wide announcement | APM "Cryptic Veil - Sting 2" |

**Music:** `EncounterSoundtracks.DungeonClear` is empty. It wants a short, solemn victory track, from the light until the party leaves (about 60 s, loops). While it is empty, the zone track keeps playing through the show, so the 1 s of silence before the Benediction isn't truly silent yet.
