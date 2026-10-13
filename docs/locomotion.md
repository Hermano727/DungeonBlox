# Locomotion: walk, run, dash

The player's walk, run and dash clips on the custom 52-bone Hero_Rig, all authored by script in background Blender (no Animation Editor, no FBX round trip) and published as native KeyframeSequences through Open Cloud. The jump is its own doc: [Jump](./jump.md).

- **Authoring:** `assets/models/main character/locomotion/`
  - `author_locomotion.py`: Walk / Run_Start / Run_Loop, armed and unarmed. Writes the `.rbxmx` clips, review renders (`review/`, side / front / back / rear three-quarter) and `Locomotion_Preview.blend` (every clip as an action on the rig; the old FBX clips are kept there as `OLD_*` for comparison).
  - `author_dash.py`: the dash poses (imports `author_locomotion` for the rig, solver and run model, so the pose matches the run).
  - `publish_locomotion.py [prefix]`: publishes and merges ids into `locomotion_ids.json`.
  - `preview_start.py`: `blender Locomotion_Preview.blend --python preview_start.py` opens the preview in the side view, playing.
- **In game:** ids in `RS/CharacterAnimProfiles` (Walk / RunStart / RunLoop, played by `Animate2` at Core) and `RS/Assets/Animations/DashAnimations` (played by `DashClient` at Action2).

## The run and walk (2026-10-12)

The old FBX loops were 16-frame mirror-symmetric cycles: arms barely swinging, every cycle identical. The new ones are built from a gait model with readable numbers (`RUN` / `WALK` at the top of `author_locomotion.py`):

- **4-step loops** (two left-right pairs). Every step has its own length (`dur`), landing weight, stride and arm swing (per-step tables), so it never repeats inside the loop. Slow harmonics of the loop wander the head and chest a little.
- **Leading edge:** the left arm swings bigger and whips forward faster; the right lags.
- **Mechanics:** knees drive straight ahead (IK pole along the hips' facing), feet land under the hips, the heel kicks up behind toward the glutes in recovery and the shin unfolds forward to land. Elbows stay at 80 to 100 degrees and close to the ribs, forearms angled in; the hand comes to the lower chest going forward and to the hip going back. Opposite arm and leg. A subtle lean, hips and chest counter-rotate, the head stays steady.
- **Weight:** contact, compression (the hip drops onto the stance knee), push-off, flight, recovery.
- **Loops start on the passing pose** (right foot planted mid-stance), so they blend from idle; Run_Start ends exactly on it and hands off to the loop.
- **Armed:** the sword arm swings smaller at the side; the forearm is twisted so the blade rides the arm's swing plane (upright when running, ahead when walking). The blade axis is measured from `Hero_Sword` in Hand_R's rest frame.
- **Speed:** Walk is authored for speed 8.7 (Animate2 plays it at `speed / 8.7`); RunLoop for the sprint speed (`EnergyConfig.SPRINT_SPEED`, Animate2 plays it at `speed / sprint`, clamped 0.8 to 1.5). The old flat 1.5x is gone.

**Run pass 3 (2026-10-13):** arms driven from the shoulders (swing -50..+48 deg, elbow 76..104, `alpha_clamp` / `clav_amp`), forward hand up to the lower ribs, rear elbow behind the torso, forearms angled in a third less (`forearm_in` 0.12); longer push-off (`B` 1.38) and a real foot arc (`swing_y` / `swing_zu`: the foot stays behind, heel up, through the passing moment while the knee drives forward, then the shin reaches out); lean from the ankles (`pelvis_dy` -0.12, pelvis 7 deg, spine only 5 more); bounce lowest at weight acceptance and highest in flight. **Walk (2026-10-13):** arms hang with a soft elbow (`elbow_clamp` 6..85, `elbow_mid` 14) and swing a little forward: before, WALK had no `elbow_clamp` and inherited the run's 78 deg minimum, which held the forearms up. These knobs default to the old behaviour, so a mode that doesn't set them is unchanged.

Tuning: change the numbers in `RUN` / `WALK` (stride `F` / `B`, `bounce`, `swing_z`, `arm_*`, `lean_base`, `yaw_*`, `dur`), rerun, check `review/`, publish, paste the ids into `CharacterAnimProfiles`.

## The crouch (2026-10-12)

Four clips per profile (unarmed and sword), all from `author_locomotion.py` and all built on ONE base pose, `crouch_idle_pose(0)`, so pelvis height, lean, head, knee bend and arm rest match across them. The old FBX crouch leaned back with the hips far behind the feet (the "invisible chair"). The base: hips dropped between the feet (only 0.08 back), torso ~27 degrees forward spread through pelvis and both spine bones, the neck countering so the head looks ahead, knee pole following the toe-out (knees over toes), feet flat where the standing feet are, soft elbows with the hands forward beside the thighs (sword: held low and ready, blade forward). Head drop ~0.8 studs, matching the first-person camera's `CrouchCameraY` (-0.8).

| Clip | What it is |
|---|---|
| `CrouchEnter` | Standing to the base in 0.32 s: knees and hips bend together (IK keeps the feet planted while the pelvis drops and eases back), the lean comes in alongside, the head stays forward, elbows soften; a hair of overshoot, ends exactly on the idle's first pose. Holds its last pose. |
| `CrouchIdle` | 4 s loop: two slow breaths (chest and shoulders, almost no depth change), one small weight shift with the arms following, a little head drift. |
| `CrouchWalk` | The `CROUCH` gait: bent knees throughout, short steps along the line of travel, feet low, long stance, subtle hip rotation and weight transfer. Authored for **4 studs/s**, the crouch speed (`EnergyConfig.CROUCH_SPEED`, lowered from 8 on 2026-10-12 for exactly this); ~0.9 s per left/right cycle, the planted foot sweeping the ground it covers. Carries Footstep markers. |
| `CrouchExit` | The base to standing in 0.30 s: the legs push the pelvis up first, the torso follows a beat later. Holds its last pose. |

**State machine (Animate2, the existing one; no parallel system):** crouching while still plays CrouchEnter, which hands off to CrouchIdle (or to CrouchWalk the moment you move) on its own clock (`CROUCH_ENTER_LENGTH`). Standing up while still plays CrouchExit, which hands off to Idle (`CROUCH_EXIT_LENGTH`). On the move there is no clip to wait for: CrouchWalk and Walk / RunStart blend over 0.25 s (`CROUCH_ENTER_FADE` / `CROUCH_EXIT_FADE`). A toggle in the middle of an enter or exit blends straight back instead of starting the opposite clip. Idle and walk switch with a 0.18 s fade and reuse their tracks (nothing restarts). All crouch clips are Core priority, so swings, drinks and the bow still play over them. The enter / exit hand-offs are timed, never on a clip ending, for the reason in [Jump](./jump.md) (a clip that ends by itself drops to the pose underneath for a frame).

**Not redone:** the crouched sword swing (`CombatAnimConfig.CROUCH_SWING_ANIM_ID`) is still the old FBX clip, so its legs show the old crouch for the length of a swing.

## Footsteps in sync (2026-10-12)

The walk / run / run-start clips carry a **`Footstep` KeyframeMarker** (value `L` / `R`) on the frame each foot lands: `author_locomotion.py` knows the landings exactly (the step boundaries of its gait model, `footstep_markers`) and writes them into the KeyframeSequence (`write_clip(..., markers)`); `locomotion_manifest.json` lists them per clip. `client/Footsteps` hooks `GetMarkerReachedSignal("Footstep")` on any playing track whose id is one of `CharacterAnimProfiles`' Walk / RunStart / RunLoop / CrouchWalk, for every character in range, and plays the step on the marker, so the sound lands with the foot at any playback speed (and keeps the clip's uneven step timing). Only a track at weight 0.5+ steps (no double steps in a crossfade). The old distance timer still runs whenever no marked clip carries the gait: riding (the hoofbeats), NPCs. A new locomotion clip needs its markers written by its authoring script, or it falls back to the timer.

## The dash (2026-10-12)

**Pose:** the run caught mid-flight and held for the burst: hard lean, front knee driven up, back leg stretched behind. Three arm placements, a different one from the last each dash: **Pump** (one fist forward, one flung back), **Trail** (both arms swept back), **Guard** (forearm across the chest). Armed variants keep the sword grip. `DashClient` plays it at Action2 with a 0.05 s fade in and stops it 0.04 s after the burst with a 0.18 s fade.

**Effect:** `RS/DashFx.Play(character, direction, { duration, inAir })`, client-local parts under `Workspace.DashFx`:
- an air burst where the dash starts (pale puffs flung back, a shock ring standing across the line of travel)
- dust behind the feet (ground dashes) and a smaller scuff where it stops
- speed lines while it lasts (streak particles thrown backward plus four Trails at the shoulders and hips)
- `DashWhoosh` (the Tab-switch whoosh for now, Movement bucket)

**Who sees it:** the dasher draws it at once; `EnergyServer`'s `RequestDash` (after allowing the dash) fires `GameEvents/DashFx` to everyone else within 250 studs, drawn by `client/DashFxClient`. The direction / air / length the client sends are used only for that drawing.

**Later:** a class dash (flash step / teleport) is another function next to `DashFx.Play` plus its own pose, picked by the same callers.

## Not done

Not play-tested (the no-Play rule): the dash pose fade timings, the VFX sizes against the real camera, and the run/walk pace scaling want a pass in a real session. First person sees little of the dash (the effect is behind the camera); a first-person cue (FOV kick, edge streaks) is a separate decision.
