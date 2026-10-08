# Professions: Mining and Spear-Fishing

The professions loop (2026-10-03). Each profession runs as one short session played in the world, in three phases: a first-contact check, a main skill phase, and collection. MVP covers the loop only: no tool upgrades, research trees or new tiers yet.

## Shared rules

- **Server judges, client predicts.**
  - The server opens a session with a seed. Everything the client draws (fault layout, fish paths) comes from that seed through functions in a shared config, so the server re-simulates and judges each input.
  - The client only ever sends inputs: hold times, throw point and time. Never results.
- **One session per node.** One miner per rock (`oreInUse`) and one fisher per pool (`poolInUse`, mirrored to the pool's `FishingUserId` attribute).
- **Ending a session:**
  - Esc, swapping the tool away, dying or walking out of range cancels it.
  - Taking a hit (`CombatStateService.OnHit`) ends it, keeping whatever was already earned. For mining, a hit pries out the ore as it stands; for fishing, the fish escapes but the hits still give XP.
- **Failure never gives nothing:** a shattered ore still drops 1 coal, and a fish that snaps the line still gives XP.
- **While a session runs:**
  - The camera is overridden (`CameraOverrideState`) and the mouse is freed (`CursorUtils`).
  - It holds `InteractionLock` with `keepVitals`.
  - `Professions/ProfessionMovementLock` sinks the movement keys.
- **Sounds:** `SoundEffects` keys `Mine*`, `Spear*` and `Fish*`. First picks from the Pro Sound Effects library were chosen by description and **not yet listened to**.

## Mining

**Files:** `RS/MiningConfig` (loop + judging), `SSS/MiningRewardHandler` (sessions + the unchanged coal pickup flow), `src/client/Professions/MiningClient`.

1. **Strike the seam.** With the pickaxe out, left click one of the **coal crystals** on a rock within `START_RANGE`. Each rock model holds a `Rock` part and an `Ore` part (the crystals); clicking plain stone only hints "Strike the coal". The camera closes in on the crystals and a ring closes on the seam; click as they meet.
   - **Perfect:** +1 coal.
   - **Good:** a clean start.
   - **Miss** (or too late): the coal starts cracked.
2. **Fracture strikes.** 4 to 6 fault points sit on the stone around the coal. Press and hold one to charge; the gauge shows that fault's clean band. Release to strike.
   - **Under the band:** nothing (a "weak" strike).
   - **In the band:** the fault breaks, and a jagged dark crack (with a branch) runs across the stone toward the coal, so the rock visibly breaks up.
   - **Over the band:** it breaks, but the coal cracks too (pale fracture lines across the crystals, sparks).
   - **Cracks:** 3 cracks in the coal shatter it.
   - **Prying:** right click pries the ore out with what's freed so far. The 15 s limit pries automatically.
3. **Collection.** The rock crumbles apart: stone chunks tumble off, plus coal shards and more pieces on a shatter. The server computes `MiningConfig.Outcome`:
   - Grades: Pristine / Clean / Rough / Shattered.
   - Coal is scaled by the share of faults broken, -1 for 2+ cracks, +1 for a perfect seam.
   - The coal drops as the existing nonce pickups (`MiningCoalDrop` / `MiningCoalCollect`), and the rock enters its respawn cycle (the server hides it for `respawnSeconds`).

The rocks are procedural (`assets/models/environment/ores/build_ores.py`, skill `procedural-environment`).

The old 6x8 grid game (`MiningScript_GridExcavation`) is parked, disabled, in `ServerStorage.ProfessionLegacy` for the future Treasure Find proc. Its server half was removed from `MiningRewardHandler` and is in git history.

## Spear-Fishing

**Files:** `RS/FishingConfig` (catch table + loop + deterministic fish movement), `SSS/SpearFishHandler` (pools, sessions, spooking), `src/client/Professions/FishingClient`.

**Pools** are invisible parts tagged `FishingPool` with a `Radius` attribute, sitting on the water surface: `Workspace.FishingPools` holds two in the Oakhaven pond, radius 6, placed in the open water either side of the wooden bridge (moved 2026-10-03: at first both sat half under it, hiding fish from the top-down camera). Check a new pool has open sky above it.
- The server gives each pool a `FishSeed`, so every client draws the same ambient fish shadows.
- To add a pool, drop a tagged part on the water.

1. **Approach unseen.** Sprinting (while moving) or jumping within `SPOOK.RADIUS` of a pool's edge stamps `SpookedUntil` on the pool. The shadows fade and a start is refused until it passes.
2. **Spear.** With the spear out, left click the water. The camera swings to an angled top-down view and 3 or 4 fish swim (types rolled from `FishDropTable`; rarer ones are faster and tinted).
   - **Throwing:** a click throws at the cursor (no draw; one throw per 0.36 s, the server allows one per 0.35 s). The spear lands `THROW.FLIGHT` (0.5 s) later, so lead the fish. The game doesn't say so: the tutorial will.
   - **Helper UI:** one strip of dark plates at the top of the screen, nothing else: left mouse + Throw (Reel during the haul), the fish icon + caught this session, the hourglass + session time, Esc + Exit. The mouse and Esc icons (`HudIcons.MOUSE_LEFT` / `KEY_ESC`) are white art tinted bone, so they read over any water.
   - **One hit** spears a fish (`HITS_TO_STUN` 1). Spears are unlimited.
   - **Judging:** the server judges every throw at release + FLIGHT against `FishPosition(params, behaviour, PathTime(t, hits), radius)`.
3. **Haul.** A Fisch-style bar: the spear holds the fish on a line. Hold the mouse to lift your catch zone and let go to drop it.
   - **Fish inside the zone:** progress fills.
   - **Fish outside it:** progress drains.
   - **Full:** caught, granted via `GrantItemId` with XP by tier + grade.
   - **Empty:** the line snaps, with a little XP.
   - **The look (2026-10-03, `Professions/HaulBar`, art in `RS/Assets/Images/FishingHaulArt`):** a slice of seabed in a driftwood frame:
     - water as a code gradient, with drifting light shafts
     - sand and swaying kelp at the bottom
     - pooled bubbles that rise, wobble and pop: more while the fish is outside the net, and a burst on each lunge
     - the rope-net catch zone (a square 3x4 net, `haul_zone_grid`) over a green / red wash
     - the caught fish's own icon, tilting with its motion and glowing in its colour if rare
     - a rope trough with a gold fill and the reel on top; its crank is a separate piece that winds as the line comes in and unwinds as it pays out (`CRANK_TURN`). The net and crank pieces are rebuilt from the painted originals by `tools/ui_assets/haul_pieces.py`
     - catch = bubble burst and flash; snap = the fish sinks and the bar shakes. FishingClient only feeds it the haul state.
   - **Start:** zone and fish both start centred, and for `HAUL.GRACE` (0.6 s) the zone doesn't sink and the fish doesn't lunge, so nobody fails before they can react.
   - **Checking:** the bar can't be proven, only made plausible. A catch faster than `HAUL.MIN_TIME` (under a flawless haul's (1 - START) / FILL) is treated as a snap.

**Continuous.** A catch or a snapped line ends a ROUND, not the session. The server sends the next round's fish with the result (`result.next`) and they swim in after the banner, without leaving the pool view. The session ends on Esc, walking off, a hit (a fish on the line gets away) or 120 s without a throw.

**The catch show (2026-10-03).** A landed fish with a `FishingConfig.CATCH_SHOW` entry leaps out of the water in an arc to just above the angler's head, hangs there turning in its effects, then shrinks into them (into the bag).
- **Who sees it:** SpearFishHandler fires `GameEvents/FishCatchShow` to everyone within `SHOW_RADIUS` (150), and `Professions/FishCatchVisuals` plays it.
- **The angler's showcase:** your own catch doesn't hang over your head. It leaps into the middle of your screen: the real 3D fish just in front of the camera (so its particles render, which a ViewportFrame can't), lit, spinning in its effects for a second longer, then it drops off the bottom of the screen. The result banner holds for 3 s (`RESULT_TIME`) to cover it.
- **Effects:** the golden fish is the loud one (dense gold sparkle trail, a 60-glint burst at the top, a soft halo, a gold light). The swift fish reads as speed: a quicker leap, a wind ribbon (a `Trail`; a swirl while it whirls at the top), streaks off its tail and a burst of speed lines. The lucky fish gets a few green motes.
- **Swimming fish:** the fish in the pools (ambient and in a session) are the same models, back just breaking the surface (`MODEL_SINK`), falling back to flat shadows only if a model is missing.
- **Models:** `ServerStorage.FishModels` (Studio-owned), copied to `ReplicatedStorage.FishVisuals` at server start. Sources and ids are in `assets/models/professions/fishing/README.md`. All four fish have one; the regular fish's is the quietest (a few water droplets).

**Grades:**

| Grade | Spears it took |
|---|---|
| Pristine | 1 |
| Clean | 2 |
| Rough | 3 or more |

**Tuning (measured in Edit mode, radius 10):** `SWIM_SPEED` 1.34 and `TURN_SCALE` 0.67 (bursts and side-to-side wiggle), both cut by a third on 2026-10-03, with `HIT_RADIUS` 1.25:

| Throw | Common fish | Swift fish |
|---|---|---|
| Aimed where the fish is (no lead) | about 43% | about 18% |
| Lead off by 0.12 s | about 100% | about 95% |

The old tug box (`FishClient_TugBox`) and the two `FishSilhouette` meshes are parked in `ServerStorage.ProfessionLegacy`. The old `SpearFishHook/Tug/Cancel` remotes are unused.

## Cooking and eating fish (2026-10-03)

**Files:** `RS/CookingConfig` (recipes, fire sources, carried counts), `SSS/CookingService` (prompts on every fire, the cook), `src/client/CookingClient` (the COOK emblem, the result), `SSS/FoodService` (every way of eating).

- **Fires:** any model named in `CookingConfig.SOURCE_NAMES` (only `Torch_Stand` today, the four in the T1 boss room and every dungeon copy) or tagged `CookingFire`. To make more fires cook, tag them; don't add names.
- **The prompt:** CookingService puts a `CookPrompt` on each fire (on its `TorchFlame` attachment when there is one). CookingClient styles it as a `PromptEmblem` (COOK, embers) and switches it off locally while you carry no raw fish.
- **Cooking:** holding E (1.5 s) cooks every raw fish you carry, bag and hotbar but not the bank, one for one (`RECIPES`). Stack by stack: the raw stack comes out first, so a full bag still works; if a grant fails anyway, the raw fish go back.
- **The fish:**

| Raw | Cooked | Hunger | Buff |
|---|---|---|---|
| Fish | T1_CookedFish | 3 | none (the default quick-eat fish) |
| SwiftFish | T2_CookedSwiftFish | 3 | +25% speed, 60 s |
| LuckyFish | T2_CookedLuckyFish | 3 | +15% luck, 60 s |
| GoldenFish | T3_CookedGoldenFish | 4 | +20% speed and +15% luck, 60 s |

  Raw fish can't be eaten at all: they are Kind "Material" (SubKind "RawFish"), an ingredient, so no eating path accepts them and they can't go on the hotbar. They still sell to the Merchant.
- **Buffs stack in time, not strength (2026-10-03):** BuffService keeps one entry per type. Eating another adds its duration and keeps the stronger amount, so two Swift fish give +25% for twice as long, never +50%.
- **Eating:** one `eat()` in FoodService, three ways in. All of them consume that exact stack (never a banked one), and food without buffs is refused on a full stomach.
  - **Held tool:** `EatFoodRequest`, the right-click hold; the item must be on the hotbar.
  - **Bag:** `EatFromBag` (RF), the bag's right-click "Eat". This is how the buff fish are eaten.
  - **Quick eat:** `QuickEatFish` (RF), `Keys.QuickEat` (V), which eats one `QUICK_EAT_ITEM`.
- **HUD:** `FishQuickEatClient` builds the key chip, icon and count into HealthClient's `FishIconsMount`, left of the hunger pips. Tap V eats the selected cooked kind; hold V for 0.8 s (the key chip fills) to switch to the next kind you carry, once per hold. `BuffHudClient` lists active buffs on the left middle of the screen (`RS/BuffDisplay` names, icons and colours; the last ten seconds blink), from BuffService's `ActiveBuffsSync`.
- **Art:** raw fish icons, the COOK emblem and both buff icons are uploaded (2026-10-03). The cooked fish have their own grilled icons. Both buff icons (Swiftness feather, Fortune clover) are in. Sounds: `SpearThrow` picks one of three throws, `FishReelIn` plays as the haul starts; `CookSizzle` and `FishEat` are still silent.

## Holding the tools

This rig has no RightHand part, so `Humanoid:EquipTool` can't weld a tool. Pickaxes and spears are now bone-held like the sword: `CharacterAnimProfiles.GetAttachForTool` returns `Hand_R` with `PICKAXE_GRIP_OFFSET` / `SPEAR_GRIP_OFFSET`. Both are built by `handGripOffset(gripPoint, shaftDir, strikeDir)` from the sword's measured grip frame, so the shaft sits where the blade does and the striking side where its edge does. They are starting values: tune live.

## Not built yet (MVP gaps)

- **Mining:** catching the falling chunk for +1; the Treasure Find proc.
- **Fishing:** a missed throw spooking the target into a dart (needs the dart shared with the server, like hits are).
- **Animations:** no strike, throw or haul animations; the held tool just follows the hand.
- **Sounds:** `MineCharge`, `FishStunned` and `FishLineSnap` are silent.
