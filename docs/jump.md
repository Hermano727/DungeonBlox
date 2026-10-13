# Jump

The player's jump: a small state machine over Roblox's Humanoid, with five authored states, a shorter and weightier arc than the default, and a landing that scales with how hard you hit. Replaces Roblox's default jump (instant, very high, no weight, no animation: Animate2 had no jump clips).

- **Code:** `src/characterscripts/JumpMotion.client.luau` (the state machine and physics), `RS/JumpConfig` (every number), `RS/Assets/Animations/JumpAnimations` (the clip ids).
- **Clips:** `assets/models/main character/jump/`: `author_jump.py` (Blender, background; poses by two-bone IK on the Hero_Rig, bind-corrected from `rig_snapshot.json`), `publish_jump.py` (Open Cloud), `jump_ids.json`, `sheet_side.png` / `sheet_front.png` (review sheets of every key pose).

## States

```
Grounded -> Windup -> Takeoff -> Rise | LongAir -> Fall -> Land -> Grounded
            (walking off a ledge: Grounded -> Fall after WALKOFF_AIR_TIME)
```

| State | What happens |
|---|---|
| Windup | Jump pressed: the squat (Takeoff clip) plays; the Humanoid leaves the ground `WINDUP` (0.12 s) later, at the squat's bottom |
| Takeoff | The push-off and stretch finish in the air (the clip is 0.40 s) |
| Rise | The air pose of a standing or short jump: knees tucked, hands low with bent elbows, the arms looping a small left / right balance wobble |
| LongAir | The stretched, forward-leaning leap, chosen only when horizontal speed at takeoff is `LONG_SPEED` (22, above any sprint) or more, so an ordinary jump is never a long one |
| Fall | Once the rise is over (upward speed under `APEX_SPEED`), or off a ledge: legs reach down, arms a little wider, still wobbling |
| Land | The compress and recover. Played at a weight from the impact speed (`LAND_WEIGHT_MIN` at `LAND_IMPACT_SOFT`, full at `LAND_IMPACT_HARD`); a tiny hop lands without a clip; from `HARD_LANDING_IMPACT` it also slows you (client-side) for `HARD_LANDING_SECONDS`. No fall damage |

Each state is two clips: **Body** (pelvis, spine, neck, head, legs) always, and **Arms** only when nothing is held (`ActiveEquipment.GetTool`), so a held weapon keeps its hold while the legs jump. Exception: with a **sword** out the arms still flail in a **Fall** (the unarmed Fall arms; the sword just rides Hand_R). The jump arms also step aside whenever another Action-priority animation is playing (a swing, a bow draw, a drink, the dash) and come back after it. All are Action priority; Rise, LongAir and Fall BODY clips move into their pose and hold it for 6 s (a second keyframe with the same pose); their ARMS clips are looped (`JumpAnimations.LoopedArms`, last pose == first) so the arms keep wobbling for as long as the jump lasts.

## Physics

- **Workspace gravity is untouched** (mobs and dropped loot use it). The Humanoid's own jump is off (the `Jumping` state is kept DISABLED) and `JumpMotion` releases a jump itself after the squat: it enables the state, sets `JumpHeight` for the launch speed `v0 = sqrt(2 * GRAVITY_RISE * HEIGHT)`, calls `ChangeState(Jumping)` and disables it again 0.12 s later.
- While airborne a `VectorForce` on the root cancels most of the world's gravity for this character only: it rises at `GRAVITY_RISE` (55) and falls at `GRAVITY_FALL` (80) studs/s^2 (the world is 196.2). Defaults: about 4 studs high, 0.38 s up and 0.32 s down, ~0.7 s in the air, a quicker fall than rise. Tune `HEIGHT`, `GRAVITY_RISE`, `GRAVITY_FALL` in `RS/JumpConfig`.

## Other systems

- **Blocks, owned here:** Crouching, PotionActionLock, EnergyServer and MountRiderCleanupClient all flip the `Jumping` state to block or allow jumping. `JumpMotion` owns that flag (it takes it back every frame) and reads their REASONS directly: `IsCrouching`, `PotionAction.IsLocked`, `WalkSpeed > 0` (dialogue / cutscene freezes), and not mounted, seated, swimming or climbing. A new reason to block jumping = one check in `canStartJump` (and the Windup recheck), not a `SetStateEnabled` call.
- **Potion drink:** its "stop the Action layer" check leaves the jump BODY clips alone (`JumpAnimations.IsBodyClip`) and stops the Arms clip like any other arm animation.
- **Air dash:** zeroes the fall each frame while it lasts; the gravity assist does not fight it.
- **Footsteps / jump sound:** still driven by the Humanoid's `Jumping` / `Landed` states, which the release produces.

## Rebuilding the clips

```
"C:/Program Files/Blender Foundation/Blender 5.1/blender.exe" -b --python "assets/models/main character/jump/author_jump.py"
python "assets/models/main character/jump/publish_jump.py"   # then paste jump_ids.json into JumpAnimations
```

Poses are the keyframe tables at the top of `author_jump.py` (pelvis drop and lean, spine pitch, where each ankle goes, which way each arm points; readable numbers, solved onto the rig, no bone axes guessed). The review renders land in `review/` (`sheet_*.png` are composed from them).

## Not done

First pass, not play-tested (the no-Play rule): the feel numbers, the fade times and the pose timings are expected to need a tuning pass in a real session. Ideas deliberately left out: fall damage, a camera dip on a hard landing, a wall-slide or double jump.

## Timings vs clips (2026-10-12)

`Takeoff` and `Land` play their motion (0.40 s / 0.52 s) and then **hold the last pose**; the state machine ends them on `JumpConfig.TAKEOFF_LENGTH` (from the press until the air pose takes over) and `LAND_LENGTH` (then the landing fades out). Before this the clips ended on their own: with `TAKEOFF_LENGTH` raised to 0.60 the Takeoff clip ran out at 0.40, the arms dropped to the run / idle pose for 0.2 s, and the Rise clip lifted them again (the "hands up, flicker down, back up" bug). Never derive a state's length from a held clip's `Length`: it includes the hold.

The same symptom had a second cause in the Takeoff clip itself: its arms swung far back in the squat and then forward through neutral in 0.07 s, which from the third-person camera behind the player read as "up, snap down, up". The arms now only load back slightly in the squat and rise once, smoothly, to the air pose.

`characterscripts/LandAnim` (an old script that played a pre-Hero-rig landing clip for 1 s on every `Landed`) was removed: the Land state replaces it, and its Action-priority track made the jump arms step aside after every landing.

**The random version of the flicker (found from a frame-by-frame recording):** `Humanoid.FloorMaterial` lags the physics by a frame or more, so just after the release it could still report the ground. The old landing test ("on the ground, 0.1 s after release") then landed the jump at once (a tiny hop: no landing clip, idle pose), and on the next frames the walk-off check saw air and threw the Fall pose back on. Whether it happened depended on frame timing, so it came and went. Now a jump only lands after it has been SEEN in the air (`leftGround`) and has settled (not rising, or the Humanoid is back in Running / Landed); a jump that never leaves the ground in 0.4 s is simply cancelled. The release also sets the launch velocity directly instead of waiting for the Humanoid's own jump.
