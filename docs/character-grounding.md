# Skinned player grounding

`CharacterGrounding.server.lua` calibrates each custom `Hero_Character` rig on
spawn. It measures the resting body mesh in root-local space, then calculates:

```text
BoundsHipHeight = root-center-to-sole distance - root half-height
HipHeight = max(1, BoundsHipHeight)
VisualOffsetY = BoundsHipHeight - HipHeight
```

The current 5-stud model measures 1 stud from root center to soles and has a
2-stud-tall root. Keep its original HipHeight of 1 and lower the body mesh and
helper Head by 1 stud relative to the root, once per spawn. The corrected soles
are 2 studs below the root center; eye-to-body alignment stays unchanged.
Setting HipHeight to 0 caused a regression: the live client remained in Freefall
with FloorMaterial=Air while its root collider rested on Terrain. Offline height
math alone did not catch this native-physics failure.

The server uses BasePart.Position to update the existing weld offsets, without
moving the connected root. It does not set welded-part CFrames, move bones,
resize, anchor, or change collision properties. Automatic avatar scaling is
disabled for this fixed custom rig. Equipment and animated poses are excluded.
`GroundingRootToSole` records the corrected distance; `GroundingHipHeight`,
`GroundingVisualOffsetY`, and `GroundingCalibrated` expose the applied setup.
See [Roblox's Position API](https://create.roblox.com/docs/reference/engine/classes/BasePart/Position)
for the distinction between repositioning one welded part and its assembly.

## Local observation API

`CharacterGroundStateBootstrap` starts one observer for the local character.
It waits for server calibration and samples at 20 Hz. It never drives physics,
animation, camera transforms, or sound. Terrain and collidable parts use the same
probe; Terrain retains its material/normal and has zero surface velocity.

Client scripts under PlayerScripts can consume the shared owner:

```lua
local GroundState = require(script.Parent:WaitForChild("CharacterGroundState"))
local sample = GroundState.GetState() -- nil until ready or after detachment
GroundState.GroundedChanged:Connect(function(grounded, sample)
    -- sample is nil when a grounded character is detached.
end)
GroundState.Landed:Connect(function(approachSpeed, sample)
    -- One event after observed ground -> air -> ground, never initial spawn.
end)
```

Snapshots are frozen tables. Fields: `Character`, `Grounded`, `Position`,
`Normal`, `Material`, `Instance`, `Distance`, `SurfaceVelocity`, `Velocity`,
`RelativeVelocity`, `HumanoidState`, and `LandingSuppressed`. Contact fields can
be nil on a miss. A nearby ray hit alone does not establish `Grounded`; Humanoid
support state and FloorMaterial must agree. Consumers must check `Grounded`
before interpreting a detected surface as a planted contact.

Landing speed is the last sampled airborne velocity relative to the supporting
surface, projected into its normal, clamped nonnegative, in studs/second.
Swimming, seating, death, and other unsupported physics states reset landing
history. This is presentation data, not authoritative fall-damage input.

`GroundedChanged` reports transitions after the initial sample. Read `GetState()`
for current state. Subscriptions survive respawns; the owner replaces the
per-character sampler and tracker. Individual consumers disconnect their own
subscriptions when destroyed. No ground observations are sent over remotes.

## Boundaries and validation

Native Humanoid physics still owns terrain, stairs, gravity, jumping, and moving
platform support. The visual offset happens only at initialization. There is no
continuous root snapping or foot IK. Existing camera, leaning, footsteps, combat, and animation consumers are
unchanged. Later effects can subscribe to this API without adding competing
movement/camera writers. Per-foot contact requires a separate future layer.

Run offline regression checks with a Luau CLI executable:

```text
python tests/run_grounding.py --luau <path-to-luau>
```

The tests use engine doubles and exercise production measurement, sampling,
landing transitions, spawn calibration, and observer lifecycle. They do not
validate engine physics or weld replication. In a fresh Studio playtest, first
stand still on the previously failing slope and confirm there is no downhill
slide, then walk toward and away from the building. Confirm Running and a
non-Air FloorMaterial on the client while standing. Also verify flat Terrain and a
flat Part, gentle slopes, stairs, moving platforms, jump/ledge transitions,
equipment changes, respawn, and a second client's view. Exact conformity of both
feet on uneven terrain is outside this pass.
