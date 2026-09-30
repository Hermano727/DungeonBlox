# Skinned-character movement presentation

## Ownership

- `MovementPresentation` is required by the active first-person camera. One
  controller per client layers skeletal offsets on local and nearby player rigs
  (120 studs), using the six named bones in the current Hero skeleton.
- Before animation, restore the saved unmodified animation pose; after animation,
  compute one combined offset per bone in character-space axes. Restore again
  before repeated simulation steps so skipped Animator evaluations cannot cause
  drift. Streamed-out/removed/dead/distant characters return to their base pose.
- The camera consumes motion values and local `CharacterGroundState.Landed`;
  neither helper writes camera CFrames. WeaponAttachClient still runs at the last
  render priority and follows the resulting hand transform.
- Existing footstep code and grounding calibration are unchanged. Ground probes
  observe support; procedural pose changes never reposition the physical root.

## State and controls

EnergyServer owns both sprint and crouch requests and the one speed calculation.
Accepted sprint publishes `Character.IsSprinting`; accepted crouch publishes
`HumanoidRootPart.IsCrouching` (the existing consumer name). States reset on spawn.
C toggles crouch, entering crouch ends sprint, and Shift stands before requesting
sprint even if hunger/energy denies it. Jumping is disabled on server and client
while crouched. Sustained freefall (0.35 seconds), death, swimming, seating,
climbing, and Physics exit crouch. Speed buffs apply through the same calculation.
There is no HipHeight reduction or collider resize.

Animate2 owns idle/walk/run/crouch locomotion. Crouch input no longer loads tracks,
changes FOV, emits dust, or writes Humanoid.CameraOffset. Old R15 Lean/Turning stay
disabled; the obsolete R15 landing animation is explicitly disabled. Sprint FOV
and existing video settings remain in place.

## Asset publication checkpoint

Five assets are exported in `assets/models/main character/male base model`:
unarmed and sword crouch idle/walk, plus a crouched sword slash. See
`Crouch_Import_Instructions.md` there. IDs in CharacterAnimProfiles and
CombatAnimConfig are deliberately empty until publication. Both input and server
requests gate crouching until all five IDs are present. No placeholder IDs or
legacy R15 clips are used. Combat damage/energy/cadence are unchanged; the stance
selects the next visual slash, without interrupting an in-progress strike.

## Tuning and checks

MovementPresentationConfig holds angular limits, decay, range, and camera
amplitudes. There is no continuous head bob or new settings UI. Roll/sprint/landing
effects are suppressed in debug third-person and when mouse control is released.
The crouch camera follows the authored 0.8-stud drop; it does not follow all head
bone animation. Existing forward offsets and wall protection remain.

`tests/run_movement.py --luau <executable>` exercises production motion math,
controller accumulation/teardown, and server state arbitration with engine
doubles. `tests/run_grounding.py` covers the unchanged observation/calibration.
These do not simulate engine physics, real skeletal axes, or replication. User
playtests must verify body direction/sign, camera comfort/clearance, weapon
attachment, low energy, crouch transitions, the earlier slope/corner regression,
and two-client visibility after a fresh Stop/Start.
