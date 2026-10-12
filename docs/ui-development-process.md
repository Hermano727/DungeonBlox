# UI development process

How DungeonBlox's UI gets designed, drawn and built: who does what, the tools involved, and how prompts and generated images are iterated. For the code side (components, registries, the Journal parts kit) see [UI & Networking](./ui-and-networking.md).

## Roles

| | You (the developer) | Claude |
|---|---|---|
| Direction | Decide what a screen is for and how it should feel; approve or reject mockups | Propose layouts and alternatives, critique them against the real game (slots, data, screen space) |
| Art | Generate every image in ChatGPT from Claude's prompts; save them to `assets/ui/incoming/` | Write the prompts, review results, ask for targeted re-rolls, process and upload the keepers |
| Build | Nothing required | Write the React-lua UI, register asset ids, compile-check in Studio, preview in Edit mode, commit |
| Test | Play-test in Studio and report what's off (screenshots help most) | Never runs Play mode (see the project rule); fixes from your reports |

The one hard boundary: Claude does not start Play mode or drive the game. Edit-mode previews (a component mounted with sample data, screenshotted) are how it checks layouts before handing over.

## The loop

1. **Brief.** You describe the screen in a sentence or two: purpose, what must be on it, what you dislike about the current one.
2. **Draft.** Claude proposes 2 to 4 layouts (quick wireframes when helpful) and recommends one. You pick or mix.
3. **Mockup.** Claude writes ONE prompt for a full-screen mockup image of the chosen layout. You generate it; that image becomes the target. Claude reviews it against reality (real slot list, real data, HUD that overlaps, screen sizes) and says what changes in the real build.
4. **Pieces.** Claude breaks the mockup into the smallest set of new art pieces, reusing existing art wherever it fits (book cover, page paper, medallions, plaques, chips, troughs). Each piece gets its own prompt and a file name.
5. **Generate.** You generate each piece and save it as `assets/ui/incoming/<name>.png`, then tell Claude.
6. **Process + upload.** Claude runs `tools/ui_assets/process.py`, checks each piece, uploads it, and registers the id.
7. **Build + preview.** Claude builds the screen, compile-checks it and renders an Edit-mode preview.
8. **Play-test.** You test in Play and send screenshots of anything off. Claude fixes, previews again, commits.

Rebuilt screens that reuse existing art are marked **FIRST PASS** at the top of their file: they work, and are due a second pass with their own art.

## Writing image prompts

Start every prompt from the UI preamble (or the icon preamble for icons) in [Art Direction & Image Generation](./art-direction.md), the one style guide for every generated image in the game. The rules below are where those preambles came from.

Every piece prompt follows the same rules (each one learned from a failed image):

- **Attach a style reference** (the approved mockup, or an existing in-game screenshot). Say "match the attached style exactly".
- **One piece per image.** Never ask for a sheet unless it's meant to be split (`process.py --split`).
- **Transparent background, no drop shadow, generous margin.** Generators sometimes paint a fake grey checkerboard; the processor rejects that, so re-roll.
- **No text, ever.** All text is drawn by the game in Roblox fonts so it stays sharp and translatable.
- **Flat, front-on, no perspective.**
- **For frames and panels:** "Flat 2D game interface element, not a real object". Without it, asking for "a satchel" produced a photo-real purse.
- **Edges stay plain where the frame will stretch.** 9-sliced art needs ornaments in the corners only; anything in the middle of an edge (a buckle, a vine, a notch) stretches badly. Say "the edges are straight and even along their whole length".
- **Variants of an image:** "Edit the attached image. Keep the exact same composition, camera, framing, objects and art style: change ONLY ...". That's how the dawn, afternoon and dusk courtyards line up.
- **To avoid the "AI-generated" look** (learned on the XP wreath, 2026-10-01): ask for two-tone cel shading (one base colour and ONE shadow shape per object that follows its form), light from one direction, and a fixed palette given as hex codes. Without the hex palette, colours drift muddy; asking for "faceted" shading gives random triangle facets.
- **Name the file** in the prompt instructions so it lands in `incoming/` under the right registry key.

## Iterating on a result

When an image comes back, Claude checks it before processing:

- **Style:** does it match the reference (palette, line weight, bronze and leather material)?
- **Usability:** real transparency, no baked text, nothing important at the edges, a shape that fits where it goes.
- **What to change:** a targeted revision, not a fresh prompt. Name the one thing wrong ("less AI-looking: fewer tiny highlights, flatter shading", "the inside must be empty") and keep everything else.

Two rounds is normal; a third usually means the request itself should change (often: reuse existing art instead, as the satchel became the Journal's page paper).

## Tools Claude uses

| Tool | What for |
|---|---|
| `tools/ui_assets/process.py` | Checks real transparency, trims, bleeds edge colour (no dark halos), caps at 1024 px, splits sheets, reports a starting 9-slice rect |
| Roblox Studio MCP | `upload_image` (images: returns ids directly), `execute_luau` in Edit mode (compile checks, previews with sample data), `screen_capture`, read-only inspection |
| Open Cloud Assets API | Audio and model uploads with `ASSET_API_KEY` from `.env` (never printed); see [Asset & Naming Conventions](./asset-conventions.md) |
| Python + PIL | Small generated sprites that don't need painting (the character's ground shadow), image crops and splits (the 16:9 courtyard halves) |
| Inline wireframes | Quick side-by-side layout drafts before any image is generated |
| Design skills in Claude Code | `critique`, `arrange`, `polish`, `typeset`, `colorize`, `distill`, `animate` and similar: structured passes over a design when a screen needs one |

## Where things land

- **Art in progress:** `assets/ui/incoming/` (git-ignored). Processed copies: `assets/ui/journal/`.
- **Asset ids:** `RS/Assets/Images/JournalUI` (UI art), `RS/Assets/Icons/...` (item and HUD icons), `RS/Assets/Sounds/SoundEffects` (sounds). Never inline `rbxassetid://` in UI code.
- **Look and parts:** colours and fonts only from `Journal/Style`; pieces from `Journal/Parts` (`ArtFrame`, `ChromeButton`, `Medallion`, `BarTrough`, `Text`, `List`...); pages draw a `Journal/Book`.
- **Rules that apply to every screen:** no emoji or em-dashes in UI text, grim-stylized tone, sentence case, and every full-screen menu joins the UI stack (`InteractionLock`) and hides the HUD through `HudHider`.
