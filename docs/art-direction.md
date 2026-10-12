---
title: Art Direction & Image Generation
tags: [art, style, prompts, chatgpt, tripo, icons, ui, vfx]
aliases: [Art Style Guide, Prompt Preambles, Image Generation]
---

# Art Direction & Image Generation

THE place for how DungeonBlox looks, and the copy-paste preambles for every kind of generated image. Every category of art draws from the same style, so the game reads as one world. When an image is generated for the game (a model concept, an icon, a UI piece, a VFX texture, a painting), its prompt starts with that category's preamble from this doc.

**Who does what:** the user generates every image (ChatGPT; Tripo for 3D) and saves it under its own name. Claude writes the prompts (preamble + the piece), reviews the result against this doc, then processes, uploads and wires it (category notes below).

**Keep this doc alive:** when a result is approved or rejected, add it to that category's "good" or "bad" examples, saying WHY in a few words. The examples teach future prompts better than adjectives do.

## The look, in one paragraph

Stylized fantasy in the vein of **Genshin Impact and League of Legends**: anime-influenced, hand-painted, chunky readable silhouettes with slightly exaggerated proportions, big simple forms with clean bevelled edges. Colour sits in **clean flat shapes**. **3D models carry no painted light at all:** the game lights them, so their textures are flat base colour (no shading, highlights or shadows baked in). Only 2D art the engine doesn't light (icons, UI, paintings) paints its light in, from the top left. The world is warm and lived-in (T1 is sunlit forest, leather, timber and bronze), with a grim edge in its dungeons and bosses, not a bright cartoon. **Shape and colour carry everything; surface texture carries almost nothing.**

**Rejected, every time:**
- **Photoreal / PBR:** hammered or pitted micro-detail, realistic fabric weave, glossy specular, dramatic studio lighting. *Example: the first brazier and relic concepts (2026-10-10), real iron and real burlap, too many torn cloth edges.*
- **AI mush / airbrush:** soft mottled gradients inside shapes, blurry edges, noise that reads as photo grain. *Examples: `fx_armor`, `fx_elemental`.*
- **Random faceting:** asking for "faceted" or "low poly" gives random triangle facets (`fx_armor`). Ask for "a few large clean planes" instead.
- **Raw low-poly** (flat-shaded convex hulls) for environment props.
- **Bright saturated cartoon**, unless it is an icon's own palette.

## Shared palette

Give colours as hex in every prompt; without them, colours drift muddy.

| Use | Hex |
|---|---|
| Dark outline (icons, UI) | `#1A120C` |
| Bronze (UI rims, trims) | `#AC966C`, shadow `#6B5536`, highlight `#E3CFA0` |
| T1 leather (gear) | `#342319` |
| Leaf gold | `#F2C45A`, shadow `#C98A2E`, highlight `#FFE7A3` |
| Leaf green (T1) | `#5E7F3E`, shadow `#3A5530` |
| Sunset accent | `#F6A04D` |
| Blackened iron (props) | `#3A3532`, shadow `#24201E`, edge highlight `#7C746C`, rust `#6B3A26` |

**Rarity colours are global** (`ProfileTypes.GetRarityColor`): Common `#CDD2DC`, Uncommon `#46CD69`, Rare `#50AAFF`, Epic `#C878FF`, Legendary `#FFAF55`, Mythic `#FF5500`. An item's art may lean toward its rarity, but never uses another rarity's colour as its main tone.

**Per-tier / per-zone palettes:** T1 is nature (browns + greens, warm, muted). T2 to T5 are TBD; see [UI & Networking](./ui-and-networking.md) zone theming.

**Per-boss palettes:** a boss's drops and effects use the boss's own colours.
- **Miasma:** violet-black `#100B14`, bruised purple `#783C96`, pale lilac `#E2D6EC`, moss green `#CDD7BE` / `#28371A`, corroded iron `#4A4A4E`.

## Rules for every image

- **One piece per image**, unless it's a sheet meant to be split (`process.py --split`) or a particle grid.
- **Attach a reference** from this doc's examples, and say "match the attached style exactly". A reference holds the style far better than words.
- **No text**, ever. The game draws all text in its own fonts.
- **Canvas shape, not pixel size.** ChatGPT only makes square, landscape (3:2) or portrait (2:3), and returns about 1254 px regardless; the processing scripts crop and resize.
- **Name the file** you want it saved as, in the prompt, when it maps to a registry key.

---

## 1. 3D models: ChatGPT concept image, then Tripo

Props, buildings, weapons, armour, NPCs and mobs. The image is the *input* for Tripo's image-to-3D, so it is a clean reference of shape and painted colour, not an illustration.

**Preamble:**

> Stylized fantasy game asset, in the style of Genshin Impact and League of Legends props: anime-influenced, hand-painted, chunky and readable. This image is the input for an image-to-3D model generator (Tripo), so it must be a clean reference of the object's SHAPE and painted colours, not a moody illustration:
> - **One object, fully in frame**, centred, with an empty margin all round.
> - **Three-quarter view from slightly above**, so the top and two sides are visible, like an isometric game-asset sheet. No dramatic perspective.
> - **Plain flat mid-grey background (#7A7F86).** No floor, no cast shadow, no reflection.
> - **Unlit, flat base colour only**, like a texture reference: the game engine lights the model, so paint NO lighting into it. No shading, no highlights, no shadows, no light-to-dark gradients. Each material is one clean flat colour, and colour changes only where the material changes (a blaze, darker legs, a metal trim). Clean bevelled edges and big simple forms carry the shape.
> - **No surface noise:** no brush strokes, no mottling, no photoreal texture, no fine grain, no hammered or pitted micro-detail, no realistic fabric weave, no PBR shine.
> - **Flat, shadowless, even light**, like an unlit render: no cast shadows, rim lights or glossy highlights.
> - **Every part solid and attached.** No thin wires, loose chains, fringes or small see-through holes; detail is carved or painted on the surface.
> - **No effects** (fire, glow, smoke, particles) and **no text or symbols**.

**Then the piece:**
- what it is, its parts from top to bottom, and its rough size against a person;
- hex colours;
- what it must NOT have when that's tempting. Examples: "the bowl is empty: no fire, no coals" (the game adds fire); "only one or two small torn corners" (the generator overdoes wear).

**Per kind:**
- **Props and buildings:** the preamble as is.
- **Weapons:** the flat-of-the-blade view is better than three-quarter for a sword. Add *"standing vertically, tip pointing straight up, the broad flat of the blade facing the camera"*, plus the blade-to-grip proportion. Glow and poison are painted colour on the surface, never around it. Detail: [Asset & Naming Conventions](./asset-conventions.md#weapon-and-gear-models-chatgpt-concept-then-tripo).
- **Armour pieces:** front view, as worn (hollow at the neck and arms), on no body.
- **NPCs and mobs:** A-pose, arms about 45 degrees down, **empty open hands** (tools are separate props), front view. Generate the **head as its own image and Tripo generation** for a sharp face ([Model, Rig & Studio Setup](./model-rig-and-studio-setup.md) section 0).

**Good examples** (attach as the style reference):
- `assets/models/dungeons/Brazier (dungeon completion).png`: painted blackened iron, big clean forms, a few rivets, a three-quarter view showing inside the bowl.
- `assets/models/dungeons/Shrouded relic (dungeon completion).png`: large soft folds, one knot, a single torn corner, chunky chains painted flat.
- `assets/models/dungeons/Ornate Golden-Trimmed Ivory Wing.png` (approved 2026-10-10, the Benediction wing): one wing flat on, a bent gold arm bone along the top, three clear overlapping feather rows, gold-trimmed tips. Tripo turned it into a clean 6k-triangle wing with no rework; asking for ONE wing, not a pair, is why.
- `assets/models/dungeons/Faceless Floating Ivory Robed Figure.png` (approved 2026-10-10, the Benediction angel): a front view, a deep hood over a smooth empty hollow, wide sleeves, a pointed gold-trimmed hem. Tripo gave a clean 6.7k-triangle figure.
- The Oakhaven market stall and the stone pedestal concept (shared in chat 2026-10-10; "okay, not perfect"): clean painted timber and stone in three-quarter view. Add them here once they're on disk.

**Bad examples:**
- The first brazier and relic concepts (2026-10-10): photoreal hammered iron, realistic burlap, torn edges everywhere, studio lighting.
- The first horse concept (2026-10-11): a painting, not a game model. Mottled brush blotches all over the coat, muscles painted in as light and shadow patches (baked lighting Tripo would keep), realistic proportions and small eyes, the tail brushing a hind leg.

**Why no painted light on models (2026-10-11, user decision):** Tripo bakes whatever the concept shows into the model's texture. Painted highlights and shadows would then sit on top of the game's real lighting and contradict it the moment the model turns. The 2D categories below are different: icons, UI and paintings are never lit by the engine, so their painted shading is how they read.

**Tripo settings:**
- Generate at about 20k, then Retopo to the class budget: prop or weapon 500 to 3k, common mob 3k to 6k, named NPC 8k to 15k, boss 15k to 25k.
- Keep the full-resolution texture.
- Skip Segment and Animate.
- Full detail in `.claude/CLAUDE.md` ("Tripo generation settings").

**After Tripo:** Claude cleans the model in Blender: origin, scale in studs, one texture per MeshPart, the 10k-triangle cap per MeshPart. It also **renames every object, mesh, material and image**. Tripo exports name them `tripo_node_<uuid>`, which must never reach Roblox, and the export step asserts the FBX bytes contain no "tripo". Claude then uploads (`tools/roblox_upload.py`) and registers the model ([Asset & Naming Conventions](./asset-conventions.md)). Worked example: `assets/models/dungeons/build_clear_props.py`.

---

## 2. Icons: items, status effects, buffs, HUD glyphs

**Preamble:**

> Game icon for a stylized fantasy RPG (Genshin Impact / League of Legends readability), matching the attached icons exactly. Flat cel-shaded 2D, NOT a real object and not a painting:
> - a thick, even, dark brown outline (#1A120C) around the whole silhouette;
> - inside it, a few LARGE clean flat planes, each one solid tone: a base, one darker shadow shape and one light highlight shape, with hard crisp edges between them and light from the top left;
> - no airbrushed gradients, no soft blur, no mottled texture, no tiny random facets, no noise;
> - one bold readable shape that still reads at 48 px, slightly chunky and exaggerated, with a little motion where it suits (a swoosh, a few sparkles), drawn as outlined shapes too;
> - centred, with generous margin, on a transparent background. No drop shadow, no glow halo, no frame or badge behind it, no text.

**Then the piece:** what it shows, its pose or angle (objects at a slight three-quarter tilt, like the coins), and its hex colours (rarity or theme).

**Good examples** (`assets/UI/incoming/journal UI and fishing/`):
- `fx_coinfind.png`: stacked coins, clean planes, thick outline.
- `gem_legendary.png`: a gem cut into a few big facets, each flat.
- `Blue Feather in Motion.png`: a bold shape with outlined wind swooshes.
- `fx_critical.png`: a starburst with outlined shard flecks.
- `Golden Koi with Sparkling Fins.png`: rich but still flat, with outlined sparkles.

**Bad examples** (same folder), all for soft mottled gradients and AI mush inside the outline:
- `fx_armor.png`: random noisy micro-facets.
- `fx_elemental.png`: an airbrushed flame.
- `fx_slowness.png`
- `icon_cat_mount.png` (the horse)

**Item icons for gear** (`assets/UI/t1/`, e.g. `t1 chestplate icon.png`) are an older, more detailed and textured style (stitching, scratches). For new gear icons, follow the cleaner style above. The T1 set doesn't need redoing for now.

**After:** `tools/ui_assets/process.py` (`alpha` mode for real transparency), upload, then register in `RS/Assets/Icons/<Category>/<Category>Icons`.

---

## 3. UI pieces: frames, plaques, bars, tabs, medallions

The full process (mockup, then pieces, build, play-test) is [UI Development Process](./ui-development-process.md); its prompt rules apply.

**Preamble:**

> Flat 2D game interface element, not a real object, for a stylized fantasy RPG; match the attached style exactly. Bronze and leather on parchment, two-tone cel shading (one base, ONE shadow shape that follows the form, a thin highlight), light from the top left, a clean dark outline (#1A120C). Front-on, no perspective. Transparent background, no drop shadow, generous empty margin, no text. Colours: bronze #AC966C / shadow #6B5536 / highlight #E3CFA0; leaf green #5E7F3E / #3A5530; leaf gold #F2C45A / #C98A2E.

**Then the piece**, plus the 9-slice rule where it stretches: *"the edges are straight and even along their whole length; ornaments only in the corners"*.

**Good examples:**
- the Journal kit in `assets/UI/incoming/journal UI and fishing/`: `Journal Leather Panel Frame.png`, `Ornate Bronze Progress Bar and Divider.png`, `nav_medallion.png`, `ribbon.png`;
- the loading-screen pieces in [Loading Screen](./loading-screen.md).

**After:** `tools/ui_assets/process.py`, then MCP `upload_image`; ids go in `RS/Assets/Images/JournalUI` (or the feature's own registry).

---

## 4. VFX textures: particles, beams, flipbooks

Tinted in-engine, so they are white and grey on black; brightness becomes opacity.

**Preamble:**

> This is a texture for a real-time game VFX system, not an illustration. The game tints it with colour in-engine and uses its BRIGHTNESS as opacity: pure black becomes fully transparent, white fully solid. So: white and light-to-mid grey shapes only on a pure flat black background (#000000), with no dark shading, black outlines or black detail inside a shape, because they would turn into holes. The darkest grey inside a shape is no darker than #808080. Flat two-tone cel shading: a white body and one grey shadow shape that follows the form, sharp clean edges, no airbrushed glow, no bloom or halo outside the shapes, no text, no border, no perspective. Match the attached reference's style exactly: its line quality, the swirly calligraphic wisps and the small detached flecks.

**Then the piece**, with how it's used:
- **Beam textures run horizontally:** LEFT is the Beam's Attachment0.
- **Particle sprites are centred with margin.**
- **4x4 sheets:** each flame or puff complete in its own equal cell, nothing crossing cell borders.

**Good examples:**
- Kane's set in `assets/vfx/FireTornado/side effect images/` (`T_SmokePuff_4x4`, `T_FlameStreak`, `T_ShockRing`, `T_Spark`);
- the clear sequence's set in `assets/vfx/DungeonClear/incoming/`.

**After:** `tools/vfx_assets/process.py`. Trim beams and single sprites, and pad sprites back to square ([Custom VFX Pipeline](./vfx-pipeline.md)). Then MCP `upload_image`, and the id goes in the feature's registry.

---

## 5. Paintings: loading screens, backdrops, title cards

The one category where painterly is right: full illustrated scenes behind UI.

**Preamble:**

> A hand-painted anime fantasy landscape illustration in the style of Genshin Impact key art and Studio Ghibli backgrounds: warm, glowing light with long soft shadows, rich but harmonious colour (sunset oranges and violets, deep greens), soft painted foliage with clear leaf shapes, readable depth from foreground to distance. Clean painterly brushwork, not photoreal, no grain. No characters unless asked, no text, no UI, no border.

**Then the scene**, the time of day, and the aspect ratio (landscape for screens). Leave calm space where UI or text will sit.

**Good examples:**
- `assets/UI/loading screen/Loading Screen 1.png`;
- the inventory courtyards (`Sunlit Fantasy Courtyard Vista.png` and siblings in `assets/UI/incoming/journal UI and fishing/`).

**After:** processed and uploaded like UI art. Wide paintings are split into halves to stay sharp under the 1024 px cap ([UI & Networking](./ui-and-networking.md), the courtyard).

---

## Where feature-specific prompts live

A feature's own request list holds its piece prompts and links back here for the preamble. For example: [Dungeon Clear Sequence: asset requests](./dungeon-clear-asset-requests.md) (VFX textures, brazier, relic, Miasma's Mythics).
