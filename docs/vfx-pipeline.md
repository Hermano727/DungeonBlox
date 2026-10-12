---
title: Custom VFX Pipeline
tags: [vfx, blender, pipeline, glossary]
aliases: [VFX Workflow, Fire Tornado, Flipbook, Mesh VFX]
---

# Custom VFX pipeline

How a fully custom effect (own meshes, own textures, own motion) gets made for this game, what every
term means, which decisions are yours at each stage, and how to ask an agent for one stage at a time.
The first effect built this way is the **Fire Tornado** (bottom of this page).

Most existing VFX (Miasma, enchant hits, level-up) are the simpler kind: built entirely in Luau from
ParticleEmitters, Beams, Trails and Lights, with no custom meshes. That is still the right choice for
small effects. Reach for this pipeline when an effect needs a **shape** particles can't make.

## The one rule that shapes everything: Roblox has no custom shaders

Game engines (Unity, Unreal) let you write a **shader**, a small program that runs on the GPU for every
pixel and vertex, every frame. That's how the reference videos scroll and distort fire live. Roblox
doesn't allow it. So every "live" GPU trick becomes one of these:

| Engine technique | What it does | Roblox replacement |
|---|---|---|
| UV distortion / panning shader | moves or warps the texture over time | **Bake** it: run the shader offline in Blender, save N frames, swap `MeshPart.TextureID` through them (a **flipbook**) |
| Vertex shader / vertex animation (VAT) | moves the mesh's vertices | **Bones** in the mesh, posed from Luau through `Bone.Transform` (or an authored animation clip) |
| Dissolve / erosion threshold | holes eat through the surface | **Not on a `TextureID`**: a MeshPart ignores the texture's alpha and renders it solid. Only a `SurfaceAppearance` (`AlphaMode` Transparency) cuts holes, and scripts can't change its texture, so a swapping flipbook can't have holes |
| A body made of streaks (vortex, swirl) | many glowing strokes | **Trails** on invisible points moved along a path every frame: each point drags a stroke (the fire tornado's body) |
| Additive blending, emissive glow | bright, light-adding look | only particles, beams and trails have it (`LightEmission`). Meshes get glow from the support layer around them |
| VFX Graph / Niagara | a node graph that drives everything on a timeline | a **Luau timeline module**: one function of `(now - startTime)` sets every parameter |

Treat these as fixed constraints. They're the main thing to keep in mind before designing.

**Rule of thumb from the first effect:** if the reference looks like it's made of streaks, light or
particles, build it from trails, beams and particles (they glow, and have real transparency). Use a
mesh only for things that really are solid surfaces (a rock wall, a shield dome, a blade). The first
fire tornado was a textured mesh and read as a solid red cylinder in game for exactly this reason.

## Glossary

**Shape and mesh**
- **Mesh**: the 3D surface (vertices, edges, faces). In Roblox, a `MeshPart`.
- **Edge loop**: a ring of edges around a tube. More loops mean smoother bending.
- **Tris (triangle count)**: cost of a mesh. Roblox caps a MeshPart at 10,000. VFX meshes stay well under (the tornado is 2,560 per shell).
- **Shell**: one layer of a layered effect (the tornado has an outer Shell and an inner Core).
- **Double-sided**: render the back of faces too. Needed for see-through tubes (`MeshPart.DoubleSided`, set in Studio).

**Surface and texture**
- **UVs / UV unwrap**: where each vertex sits on the 2D texture. "Square UVs" means the tube is unrolled to fill the 0..1 square: U around, V up.
- **Seam**: where the UV unroll is cut. The texture must match across it, or a vertical line shows.
- **Tileable / seamless**: the texture's edges match when repeated.
- **Noise**: procedural random pattern (Perlin, fBm). **fBm** = several noise layers at doubling detail.
- **Domain warp / UV distortion**: offsetting where a texture is read, using another noise. It turns blobs into flowing, smeared fire.
- **Erosion / dissolve**: cutting holes wherever a value falls below a threshold.
- **Colour ramp / gradient map**: turns a greyscale value into colours (dark red to yellow).
- **Alpha**: per-pixel opacity. **Alpha cutout** = hard holes; **alpha blend** = soft fade.
- **Bake**: compute something expensive once, offline, and save the result as an image.
- **Flipbook / sprite sheet**: a sequence of frames. Separate images (the tornado body) or a grid in one image (particles: `FlipbookLayout` 2x2, 4x4, 8x8).
- **Loop**: the last frame flows into the first. Needs periodic noise or a crossfade.

**Motion**
- **Bone / armature / rig**: a skeleton inside the mesh. **Skinning / weights** = how much each vertex follows each bone.
- **Procedural animation**: motion computed in code (sine waves, noise) rather than keyframed.
- **Keyframe animation**: authored poses on a timeline (Blender clip, published as an Animation asset).

**Support layer (the "punch")**
- **ParticleEmitter**: many small sprites. Key knobs: `Rate` or `Emit(n)` bursts, `Lifetime`, `Speed`, `Size`/`Transparency` curves, `LightEmission`, `Orientation` (`VelocityParallel` = streaks), `Drag`, `Acceleration`, `FlipbookMode` (`Random` picks a random cell per particle).
- **Beam**: a textured ribbon between two Attachments, optionally curved (`CurveSize0/1`), with a scrolling texture (`TextureSpeed`). Good for spiralling streaks and energy lines.
- **Trail**: a ribbon left behind a moving Attachment.
- **Shockwave**: an expanding ring at an impact.
- **Anticipation / wind-up**: the build-up before a hit. **Telegraph**: what tells the player where it will hit.
- **Impact frame**: the instant of the hit, sold with a flash, a shockwave, camera shake and sound.
- **Secondary motion**: things that react after the main event (embers drifting, smoke lingering).

**Timing and integration**
- **Timeline**: phases with start and end times (wind-up, release, travel, dissipate).
- **Easing / curve**: how a value moves between keys (`NumberSequence`, `TweenService`, or a hand-written curve).
- **Deterministic path**: a function of `(origin, startTime, t)` that the server and every client evaluate identically, so nothing streams per frame.
- **Pooling**: reusing effect instances instead of creating and destroying them.
- **LOD / culling**: less or no detail far away.

## The workflow, stage by stage

Each stage is a separate piece of work with its own deliverable and its own review. Approve one before
starting the next: changing the shape after the textures are baked means re-baking.

| # | Stage | Where it lives | Deliverable | Your decisions |
|---|---|---|---|---|
| 1 | **Gameplay spec** | `MobData` moveset entry, a config module | timeline (seconds), hitbox size and path, damage, counterplay | how long the wind-up is, can it be interrupted, how you dodge it, damage per hit or per tick |
| 2 | **Reference and look** | this doc / chat | 2 to 5 reference images, palette, style words | stylized vs realistic, colour family, how busy |
| 3 | **Shape (mesh)** | `assets/vfx/<Effect>/build_*.py` in Blender | FBX + review render | silhouette, height, number of shells, how off-centre |
| 4 | **Surface (baked "shader")** | same script, `frames/` | flipbook PNGs + contact sheet | frame count (memory vs smoothness), hole amount, colours, scroll speed |
| 5 | **Motion (bones)** | Blender rig + a Luau driver | bone chain + driver constants | twist speed, sway, how it grows in and collapses out |
| 6 | **Support layer** | Luau client module, particle textures | particles, beams, lights, sound keys | which beats get extra punch: wind-up, release, travel, impact |
| 7 | **Timeline** | Luau client module | one `update(t)` per instance | the exact beat timing, aligned to the server |
| 8 | **Server integration** | `SSS/...` | hitbox on Heartbeat, a start event with origin and time | damage, cooldown, which mob uses it |
| 9 | **Readability and cost** | review | telegraph pass, caps, culling | max simultaneous instances, distance cull, does it hide other telegraphs |
| 10 | **Review in game** | you, in Studio | notes back to the agent | |

Server/client split (always): **the server decides where and when, and whether you got hit. Clients only
draw**, from the same shared path function, starting from the time the server sent. Never let a client
report a VFX hit.

## Asset handoffs

- **Meshes and rigs**: FBX through `tools/roblox_upload.py`. The id goes in
  `RS/Assets/Meshes/Vfx/VfxMeshes`; `SSS/VfxModelLoader` loads each one at server start into
  `ReplicatedStorage.VfxModels.<KEY>` (anchored, non-colliding, no shadows) for clients to clone.
  There is no Studio-owned copy, so nothing has to be imported by hand.
- **Rigged FBX export scale is 0.01.** Roblox reads a rigged FBX in centimetres: at scale 1 the
  tornado came in 100x too big, even with Blender's unit system set to NONE. Static props still
  export at 1. Check the size with an Edit-mode `LoadAsset` after every upload.
- **Double-sided = real geometry.** `MeshPart.DoubleSided` is a Studio-import setting and can't be
  turned on for a model loaded at runtime, so see-through VFX meshes carry a second, reversed copy of
  every face (own vertices, so normals stay clean).
- **Images**: `python tools/vfx_assets/process.py <scratch dir> <file> <mode> ...` (modes `lum`, `tile`,
  `grid4`, `alpha`, `bleed`; see its header). It writes into a scratch folder, never a renamed copy
  in the repo. Upload with the Studio MCP `upload_image` (serve the folder with
  `python -m http.server`). Ids go in `RS/Assets/Images/WorldVfx` with the source file named next to
  each. Uploads are capped at 1024 px.
- **Particle textures from an image generator**: ask for **white/grey on a pure black background**.
  `lum` mode turns brightness into alpha, which is more reliable than asking a generator for real
  transparency. Particle grids must be square (2x2, 4x4, 8x8). Prompting: paste the VFX preamble
  from [Art Direction & Image Generation](./art-direction.md#4-vfx-textures-particles-beams-flipbooks)
  (black = transparent, no dark detail inside shapes, the darkest grey #808080), attach one of the
  `assets/vfx/FireTornado/side effect images/` as the style reference, and ask for a canvas SHAPE
  (square / landscape / portrait), never pixel sizes: ChatGPT returns ~1254 px regardless.
- **`lum` keeps the full canvas; trim what needs it** (learned 2026-10-10): a Beam texture (stretched
  along the beam, LEFT = Attachment0) and a single-sprite particle should be cropped to their
  content (`process.trim`), or the beam's width and the particle's size are mostly empty black. A
  particle draws into a SQUARE quad, so pad a trimmed sprite back to square around its centre or it
  stretches. 4x4 sheets stay `grid4` (exact 1024, 256 px cells). The clear sequence's six textures
  were processed this way.
- **Sounds**: keys in `RS/Assets/Sounds/SoundEffects`, played by key, never by asset id. A looping
  sound on a moving effect is its own `Sound` parented to the effect (with `SfxService.GetEffectsGroup()`
  as its SoundGroup); `SfxService.PlayEffect` is one-shot only.
- **Animations for a custom rig** (a mob's move that the VFX syncs to): don't hand-import the FBX in
  the Animation Editor. Export the Blender action as a KeyframeSequence with the rig's measured bind
  frames and publish it with Open Cloud: for Kane,
  `blender --background <file.blend> --python "assets/models/mobs/named elites/kane animation/export_kane_clip.py" -- <Action> --publish`.
  It prints the .blend's timeline markers in seconds, which is where effect timings come from (the
  slam's impact). Method and the bind-frame measurement: [Model, Rig & Studio Setup](./model-rig-and-studio-setup.md) sections 4-5.

## How to prompt an agent, one stage at a time

Name the stage, the effect, and what to deliver. Examples:

- *"Stage 3 for the Ice Spike effect: build the mesh in Blender like assets/vfx/FireTornado. One shard
  shell, 6 studs tall, cracked silhouette, square UVs, bones up the spine. Give me a review render, don't
  bake textures yet."*
- *"Stage 4 for FireTornado: fewer holes, more orange at the top, 12 frames instead of 16. Re-bake and
  show the contact sheet."*
- *"Stage 6 for FireTornado: add the wind-up layer. Embers stream inward along the ground toward the
  caster for 2.5 s, the ground ring heats from dark red to bright orange, then one shockwave on release.
  Use the textures in assets/vfx/FireTornado/particles."*
- *"Stage 8: wire FireTornado as Kane's special. Server hitbox follows the shared path, 30 damage per 0.5 s
  tick inside 3 studs. Clients draw from the start event only."*

Useful words when giving feedback:
- **Silhouette** (overall shape)
- **Density** (how many holes or particles)
- **Value contrast** (dark vs bright)
- **Saturation**
- **Timing** (too fast or too slow)
- **Anticipation** (more or less wind-up)
- **Overshoot** (too punchy past its target)
- **Secondary motion**
- **Readability** (can you tell where it hits?)
- **Noise** (too busy)

## Fire Tornado (first effect, Kane's special)

**The move (the Groundbreaker Slam):**
1. **Wind-up, 1 s:** Kane stops, plays the slam wind-up (the axe goes up over his head), and a red "!!" appears above him. The ground sigil heats up, sparks rush in, and the four paths light up.
2. **Impact, at 1 s:** the axe hits the ground just in front of his feet.
   - Anyone within 8 studs takes 90 once and is knocked back.
   - The ground breaks: ground-coloured slabs burst up in a ring and rocks fly.
   - A column of fire and eight fire jets go up, a shock ring bursts out, and the slam sound plays.
3. **Tornadoes:** four fire tornadoes leave him 90 degrees apart and spiral out to 30 studs over 4.5 s, each howling with the wind loop.
   - **Damage:** anyone inside one takes 40 every 0.5 s, with a burn sound on each tick that lands.
   - **The drag:** within 10 studs a tornado pulls you toward it and carries you along with it, gently enough to walk out of. It runs on each player's own client, which owns that character's physics (`PULL_*`, `CARRY`).
   - **End:** each one collapses into a small burst.
4. **Recovery:** Kane is held until the slam clip finishes (about 0.65 s after the impact).

**Kane's axe burns all the time:** flames, embers, smoke and a glow on the axe head, plus a fire trail
along the blade's edge, so every swing leaves a fire arc (`client/KaneAxeFire`).

| Piece | Where |
|---|---|
| Timeline, path, hitbox size, visual tuning | `RS/FireTornadoConfig` (`PathPoint` is shared by server and client) |
| Damage, tick, cooldown, first delay | `MobData` Kane `Moveset` entry with `Cast = "FireTornado"` |
| Cast hook (channel, stand still, cancel on death) | `SSS/MobMovesetBehaviour` `CASTS` |
| Slam clip, impact damage, hitbox + damage ticks | `SSS/FireTornadoCast` (own Heartbeat while tornadoes are out) |
| Slam timing (clip speed so the impact lands on the wind-up) | `FireTornadoConfig` `SLAM_*`, `RECOVERY`, `IMPACT_FORWARD`, `SLAM_RADIUS` |
| The slam animation | `MobAnimConfig.Kane.Moveset.GroundbreakerSlam`, exported by `assets/models/mobs/named elites/kane animation/export_kane_clip.py` |
| Ground crumbling | `client/MiasmaLandingSlamFX` `Crumble` (shared with Miasma's landing) |
| Axe fire | `client/KaneAxeFire` |
| Sounds | `SoundEffects`: `KaneGroundSlam` (impact), `FireTornadoWind` (looped per tornado), `FireTornadoBurn` (each tick that lands); Kane's axe swing/hit through `SSS/MobCombatSfx` |
| All visuals | `client/FireTornadoVFX` |
| Network | `GameEvents/FireTornadoCast`: `"begin"` once per cast (origin, facing, start time), `"cancel"` |
| Textures | `WorldVfx`: `FLAME_STREAK` (strands, beams), `SMOKE_PUFF_4X4`, `SPARK`, `SHOCK_RING` (bursts, base swirl), `CHANNEL_SIGIL`, `ALERT_DOUBLE` |

**The tornado body is strands, not a mesh.** About 42 invisible points per tornado orbit the axis while
climbing it, each dragging a glowing Trail, so the column is drawn by spiral strokes. Five groups, inside
out:
- a hot thin core,
- **the silhouette:** 18 strands climbing slowly, so each draws a near-horizontal ring on the funnel surface. Stacked rings are what make the outline read.
- dark-red outer sheets,
- **wind:** thin pale plain lines whipping around outside the fire, faster than it,
- smoke wisps.
- **Shape:** each point follows `FireTornadoConfig.FunnelRadius(h)`: a ground skirt, a narrow neck and a wide flared lip (the profile designed in Blender).
- **Spin:** points orbit faster where the funnel is narrow.
- **Off-centre:** the axis swings to one side (`AxisOffset`) and that bend rotates over time.
- **Seamless loop:** when a point reaches the lip it wraps back to the ground. Its trail is cleared and its width tapers to zero at both ends, so the jump never shows.
- **Around the strands:** a shock-ring swirl spins on the ground, smoke rolls at the base, embers rise, sparks fly off the lip, and a light flickers inside.
- **Lesson: no tall ribbons.** The first strand version had three wide flame beams curling from base to lip. In game they read as three little tornadoes inside the big one and hid the outline, and steep strands did the same. The outline comes from many thin, slow-climbing (near-horizontal) strokes.
- **Tuning:** everything lives in `FireTornadoConfig.VISUAL` (`STRANDS` table: count, radius, pad, width, orbit, rise, trail length, colours, textured).

**Retired first attempt (kept as a lesson):** `assets/vfx/FireTornado/build_fire_tornado.py`.
- It built a two-shell skinned mesh with bones and a baked 16-frame fire flipbook (a noise "shader" run offline).
- It uploaded and animated fine, but rendered as a solid cylinder. The flipbook's holes were alpha, and `MeshPart.TextureID` ignores alpha.
- The script is still the reference for baking textures in Blender and for the rigged-FBX export settings.

**Art:** `assets/vfx/FireTornado/side effect images/`: the generated particle art and the "!!" icon,
under the names in `WorldVfx`.

**First-run things to judge in game:**
- Strand density and brightness: `STRANDS` counts, `emission`, `transparency`.
- Whether the off-centre lean (`WOBBLE`) reads.
- Damage 40 per tick against T2 armor.
- Whether 150 degrees of sweep is dodgeable with the 1 s channel.
- The "!!" size: 2.4 x 3.6 studs, 2.6 above his head.

**Status:**
- [x] Particle textures and icon, processed and uploaded.
- [x] Server cast, hitbox and ticks; client channel, release, tornadoes, collapse.
- [x] Body rebuilt from trails (2026-10-08) after the mesh read as solid; channel shortened to 1 s.
- [x] Silhouette pass: beams removed, slow-climbing outline rings and wind strands added.
- [x] Groundbreaker Slam (2026-10-08): the slam clip exported and published by script, impact damage, ground crumbling, slam fire, sounds, burning axe.
- [ ] In-game review (the user).

