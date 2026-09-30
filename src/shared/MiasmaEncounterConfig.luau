-- The Enrage clip is authored at 3.6s (rear-up 0.4-1.8s, jaw thrust / spew 1.9-2.95s); it plays
-- at ENRAGE_ANIM_SPEED, and every enrage timing below is derived from these so the cutscene,
-- spew, rumble and shroud wave all stretch with it.
local ENRAGE_ANIM_SPEED = 0.5
local ENRAGE_CLIP = { Length = 3.6, SpewStart = 1.9, SpewEnd = 2.95 }

local Config = {
	MaxPartySize = 8,
	EntranceGrace = 10,
	Act1Duration = 10, -- TEMP (testing the boss flow): normal value is 60. Revert before shipping.
	Act1InitialWaveDelay = 12,
	Act1FinalWaveDelay = 6,
	SlimeLandingWarning = 1.25,
	PoisonDropWarning = 1.1,
	BossDropWarning = 2,
	-- Damage + warning-circle radius of the landing slam, matched to how far the
	-- slam VFX reaches (~1.6x the boss's half-width) so anything the dust and
	-- debris visibly hit takes the damage.
	-- 49 at ModelScale 0.67; scaled with the boss to 33 at 0.45.
	BossDropRadius = 33,

	-- Phase 1 -> phase 2 presentation, ONE timeline (BeginBossDrop). Every number here was
	-- measured 2026-09-25 by reading the published clips' keyframes (AnimationClipProvider) and
	-- posing the rigs' bones -- re-measure if either clip or a rig is re-authored:
	--   1. BRIDGE (0.6s): LatchDetach plays on the ceiling-latch model while CeilingToBody plays on
	--      the upright boss, at the same time. The two forms cross-fade between SwapStart and
	--      SwapEnd of the bridge. CeilingToBody's last pose is identical to LandingSlam's first.
	--   2. SLAM (4.0s): LandingSlam plays straight on, no blend. It already contains the fall
	--      (BodyMotion 106.9 -> 0, landing ~0.78s), the squash, the expansion and the roar, so
	--      nothing else is scripted for any of them -- the growth VFX and phase 2 key off its motion.
	-- The slam starts SlamImpactTime before the warning circle ends, so the landing lands on it,
	-- and the bridge starts BridgeSeconds - SlamLeadSeconds before the slam.
	BossDropSequence = {
		BridgeSeconds = 0.6,        -- LatchDetach and CeilingToBody are both 0.6s
		SwapStart = 0.167,          -- into the bridge: latch begins fading out / boss fading in
		SwapEnd = 0.333,            -- ...fully swapped (window centre 0.25)
		-- The slam clip starts this much BEFORE the bridge clip ends. A non-looped clip that ends
		-- drops to the rest pose for a frame; starting the slam ~2 frames early (the poses are
		-- near-identical there) means the rest pose is never shown.
		SlamLeadSeconds = 0.033,
		SlamLength = 4.0,           -- LandingSlam, published asset 93045226675327 (120 frames at 30fps)
		SlamImpactTime = 0.8,       -- body reaches the floor (BodyMotion hits 0 at ~0.78s)
		SlamGrowthTime = 1.3,       -- squash (1.0s) has rebounded: expansion + roar begin
		SlamGrowthSeconds = 1.7,    -- ...and the roar holds until ~3.0s
		SlamSettleTime = 3.6,       -- body motion has settled; phase 2 starts here (clip ends 4.0)
		-- The roar: the mouth is open from frame 65 to frame 100 of the 30fps clip. The server
		-- fires "BossRoar" for that window (breath out of the mouth, arena shake, ceiling dust).
		SlamRoarStart = 65 / 30,    -- 2.167s
		SlamRoarEnd = 100 / 30,     -- 3.333s
		SlamRoarSoundLead = 0.5,    -- the roar SOUND starts this much before frame 65 (it has a wind-up)
		-- The clip plays at 1 / SlamRoarStretch speed through frames 65-100 only, so the roar lasts
		-- SlamRoarStretch x as long (the fall, squash and settle keep their speed). Every time in
		-- this table is CLIP time; the server maps it to real time (slamRealTime in the controller),
		-- so anything after frame 65 lands later by the extra roar time. The roar sound repeats
		-- to cover the longer window (MiasmaRoarFX.PlaySound).
		SlamRoarStretch = 2,
		-- Geometry (studs, at model scale 1), measured by posing both rigs at the bridge's first
		-- frame: CeilingToBody t=0 folds the body into a flat disc whose centre sits
		-- BodyMotionAltitude + DiscCentreFromRig = 136.15 above the upright boss's root part; the
		-- flipped latch's bone plane sits LatchBonePlaneAbovePivotFlipped above its own pivot.
		-- Making those planes coincide is what makes the latch -> boss swap seamless.
		BodyMotionAltitude = 106.9,    -- the clips' BodyMotion offset (held through the bridge)
		DiscCentreFromRig = 29.25,     -- the rest of the 136.15: the folded body's own height
		LatchBonePlaneAbovePivotFlipped = 4.1,
		-- Does the animation's own translation (BodyMotion) scale with the model, or stay in
		-- absolute studs? Assumed to scale (ModelScale 0.45 -> the 106.9 fall becomes ~48.1).
		-- If the boss looks like it falls from the wrong height in a playtest, flip this.
		AnimTranslationScalesWithModel = true,

		-- Drop cutscene (MiasmaDropCutscene, client): every member's camera is taken over for the
		-- whole drop -- a close-up on the ceiling blob, a sweeping pull-out that follows it down to
		-- a front-on view, the landing, then a push-in on the roar. Players are frozen and immune
		-- to the encounter for the whole cutscene (they can't see the warning circle, so the slam
		-- can't be dodged fairly). LeadIn = extra seconds on the ceiling close-up before the drop
		-- itself starts. TitleCardSeconds = how long the boss's title card holds after the roar,
		-- only when TitleCards has art for this boss (the fight waits for it).
		Cutscene = {
			Enabled = true,
			LeadIn = 1.6,
			TitleCardSeconds = 3.75, -- 0.18 slam-in + ~3.3s fully on screen + 0.3 fade to black
		},

		-- The clips were authored for a ceiling ~176 studs up; the arena's real ceiling (the latch's
		-- anchor, ANCHOR_Miasma_CeilingLatch) is ~53 above the floor. With this ON the latch hangs
		-- at the real anchor (visible in phase 1, as before) and the boss root is held LOWER by
		-- exactly the difference during the bridge, then lifted back to the floor in step with
		-- the slam's fall (root offset = fraction-of-fall-remaining x the difference), so the boss
		-- falls from the real ceiling to the floor. OFF = play the clips at their authored altitude
		-- (the latch then hangs far above the arena roof and is never seen).
		CompensateToCeilingAnchor = true,
		-- LandingSlam's fall (studs, scale 1) over its first 0.8s, {time, height}; linearly
		-- interpolated. The fall-remaining fraction is height / the first sample's height; after
		-- 0.8s the body is on the floor. Re-measured 2026-09-27 for 93045226675327: unlike the old
		-- clip (103860484509234), this one keeps BodyMotion at 0 and carries the fall on the body
		-- bones themselves, so these are the average height of its *_Core bones per keyframe.
		-- It starts at 102.7, ~4 studs (scale 1; ~2 at 0.45) under CeilingToBody's end pose.
		SlamBodyMotion = {
			{ 0, 102.7 }, { 0.1, 102.9 }, { 0.2, 101.4 }, { 0.3, 95.4 }, { 0.4, 85.2 },
			{ 0.5, 73.1 }, { 0.6, 60.7 }, { 0.7, 40.9 }, { 0.8, 0 },
		},
	},
	-- How far the landing slam VFX reaches, as a multiple of the boss's standing
	-- half-width: the body squishes wider on impact, and the dust and debris
	-- carry on past it. Visual only; the damage radius is separate.
	BossLandingVisualScale = 1.6,

	Poison = {
		MaxStacks = 5,
		TickInterval = 2,
		MaxHealthFractionPerStack = 0.01,
		TickDamageCap = 50,
		ExposureStackInterval = 3,
	},

	Altars = {
		ChannelDuration = 2,
		BaseCooldown = 0,         -- none: cleanse as often as needed. > 0 = BaseCooldown / party size seconds per altar
		InteractionRange = 12,    -- server: channel must start and stay within this flat distance
		PromptDistance = 9,       -- how close the cleanse signifier appears
		PromptHoldDuration = .35, -- brief hold to begin, so walking past never triggers it
		PostCleanseImmunity = 3,  -- seconds after a successful cleanse in which no new poison stacks land
	},

	Gates = {
		CycleDuration = 130, -- 90 -> 100 -> 130 (2026-09-29): more time for the valves before they swap
		FinalWarningDuration = 15,
		PurgeWarningDuration = 3,
		RecoveryDuration = 2,
		StunDuration = 18,
		StunShrinkFactor = 0.5,   -- the pure-water stun shrinks Miasma to half size (the solo stagger doesn't)
		StunShrinkSeconds = 0.6,  -- shrink / regrow tween
		-- The final valve's prime plays a cutscene for the whole party (MiasmaPureWaterCutscene):
		-- that gate opening, the holy flood racing down its channel, and the water hitting
		-- Miasma (snapped to the arena centre for it). The stun proper (shrink, stunned clip,
		-- vulnerable outline) starts at ImpactAt, and StunDuration counts from the cutscene's end,
		-- so the party never loses damage time to watching it. Players are frozen + immune for it.
		StunCutscene = { Enabled = true, Seconds = 5.6, ImpactAt = 3.3 },
		NextCycleWarning = 5,
		ValveRange = 14, -- altar prompt distance (historical name); valve stations use Valve.* below
		MazeSampleRate = 15, -- client batches per second while tracing
		MinimumMazeSeconds = 1.25,
		-- Physical valve station + maze authority. Station GEOMETRY lives in
		-- SSS/MiasmaValveStationBuilder, placement in SSS/MiasmaValveStationPlacement.
		Valve = {
			PromptDistance = 6,          -- ProximityPrompt reach from the wheel
			PromptHoldDuration = .3,
			MaxOperatorDistance = 8,     -- server: root must be this close to the wheel to reserve / keep operating
			MoveCancelDistance = 3,      -- UNUSED since 2026-09-29 (hits/knockback no longer interrupt; only MaxOperatorDistance does)
			PlateRevealLinger = 2.5,     -- tablet stays lit this long after the last reader steps off the plate
			PlateHeightTolerance = 5,
			MaxPointsPerBatch = 32,      -- server rejects bigger batches outright
			MaxBatchesPerSecond = 45,
			MaxCursorSpeed = 4,          -- board-widths per second the traced line may travel
			CursorSpeedBurst = 1.5,      -- token bucket capacity (board-widths), absorbs network bunching
			MinimumSecondsPerSymbol = .5, -- plus MinimumMazeSeconds, from open to completion
			LatchTimeout = 2,            -- client: give up waiting for a rune verdict after this long
			CompleteHold = 1.1,          -- client: success screen before the maze closes
			CompletedDisplay = 6,        -- dev harness: seconds a finished station shows before re-corrupting
		},
		Workload = {
			[1] = { clogs = 2, symbols = 3 },
			[2] = { clogs = 2, symbols = 3 },
			[3] = { clogs = 2, symbols = 3 },
			[4] = { clogs = 2, symbols = 3 },
			[5] = { clogs = 3, symbols = 4 },
			[6] = { clogs = 3, symbols = 5 },
			[7] = { clogs = 4, symbols = 5 },
			[8] = { clogs = 4, symbols = 6 },
		},
	},

	-- Solo loop: fight -> stagger -> puzzle -> pure water. A lone player has nobody to hold
	-- Miasma off while they work a valve, so in solo Act 2 landing hits fills a STAGGER meter
	-- (under the boss bar). Full meter: Miasma reels for StaggerDuration, doing nothing and
	-- taking NO bonus damage -- that window is for clearing the clogs, reading the plate and
	-- solving the maze. Priming the gate in time gives the normal pure-water stun (full
	-- damage). Too slow: Miasma recovers, the maze closes, and the meter must be rebuilt.
	-- The meter counts HITS, not HP, so it takes about the same time with any gear.
	Solo = {
		MaxPartySize = 1,          -- starting party sizes that use the stagger loop
		StaggerPoints = 12,        -- meter size (~10 s of steady T1 swinging at ~1.2 hits/s)
		ReferenceHitDamage = 8,    -- a raw hit this big (T1 common sword) = 1 point; smaller = less, never more than 1
		MinHitInterval = .2,       -- per player: hits closer together than this count once (multi-proc safety)
		StaggerDecayDelay = 3,     -- seconds without a hit before the meter drains
		StaggerDecayPerSecond = 1.5, -- points drained per second after that
		StaggerDuration = 20,      -- seconds Miasma reels (the puzzle window)
		RecoveryLockout = 4,       -- seconds after recovering before hits count again
		MaxStaggersPerCycle = 2,   -- per gate cycle (Gates.CycleDuration)
	},

	Boss = {
		OutsideStunDamageMultiplier = 0.4,
		StunnedDamageMultiplier = 1,
		EnragedDamageMultiplier = 1,
		NeutralDuration = 2.5,
		-- Enraged ability gaps + telegraphs x this. 0.6 was 67% faster casting; 2026-09-29 eased
		-- to 1/1.4 = 40% faster (asked: 100% -> 50%, 50% -> 35%; it was in between).
		EnrageSpeedMultiplier = 1 / 1.4,
		MinimumTelegraph = 0.45,
		SackThresholds = { 0.70, 0.50, 0.30 },
	},

	-- Enrage (at 30% HP): a cutscene of the Enrage clip (camera pan, shake, rock rain), Miasma
	-- spews poison instead of the landing roar's wind, gains a red outline, and its breath rolls
	-- out to the arena edge as the SHROUD: a ring of poison mist that stacks poison on anyone
	-- outside it and slowly closes in. It tells the party the valves are done (no more gate
	-- cycles after enrage), shrinks the arena, and says: just fight it now.
	Enrage = {
		AnimSpeed = ENRAGE_ANIM_SPEED,                                -- 0.5 = twice as slow (2026-09-27: felt too fast)
		CutsceneSeconds = ENRAGE_CLIP.Length / ENRAGE_ANIM_SPEED,     -- players are frozen + immune for it
		SpewStart = ENRAGE_CLIP.SpewStart / ENRAGE_ANIM_SPEED,        -- jaw thrust opens: spew, shroud wave leaves
		SpewEnd = ENRAGE_CLIP.SpewEnd / ENRAGE_ANIM_SPEED,
		OutlineColor = Color3.fromRGB(255, 45, 45),
		Shroud = {
			WaveSeconds = 1.3,     -- the breath rolls from Miasma out to StartRadius
			StartRadius = 90,      -- studs from the arena centre (wall faces sit at 104)
			EndRadius = 46,        -- where it stops closing in
			ShrinkSeconds = 100,   -- StartRadius -> EndRadius, after the wave lands
			StackInterval = 1.5,   -- seconds outside the ring per poison stack
		},
	},

	-- Miasma up close (2026-09-28). Its ordinary swing (MobData MiasmaBoss: BaseDamage,
	-- AttackRange, Telegraph; MobAnimConfig AttackHitDelay) now lands after a telegraphed
	-- windup, knocks you well back and poisons you. Its reach stays a little SHORT of a
	-- player's 12-stud melee (AttackRange 6 past the body), so you can fight it at the edge
	-- of your reach but hugging it is punished.
	Melee = {
		PoisonStacks = 1,          -- per landed swing, on top of its damage
		-- The BODY is solid: an invisible anchored cylinder players physically cannot enter
		-- (plus a shove for anyone who ends up inside anyway). Its radius follows the ANIMATED
		-- body: the four edge bones of the skin's base ring (front/back/left/right), times
		-- BodyEdgeFromBones -- the skin edge at player height sits at 0.93 of those bones'
		-- distance (measured on the bind pose, 2026-09-29). BodyEdgePadding adds studs on top
		-- (+ = wall further out). BodyRadiusFraction x the model's half-extent is only the
		-- fallback for a model without those bones (it was the whole rule before, and at 0.6
		-- players reached a stud or two into the body).
		BodyEdgeFromBones = 0.93,
		BodyEdgePadding = 0,
		BodyRadiusFraction = 0.6,
		ContactShoveSpeed = 42,    -- studs/s outward, held for ContactShoveSeconds
		ContactShoveSeconds = 0.14,
		ContactCooldown = 0.25,    -- per player, so shoves don't stack every frame
		-- Contact itself is damage-free by default (project rule since Kane's "thorns" were
		-- removed: no per-mob touch damage). Set above 0 to poison anyone who walks into it.
		ContactPoisonStacks = 0,
	},

	Abilities = {
		-- The poison LOB (key kept as FastProjectile for the director): a red reticle marks a
		-- player and tracks them for TrackTime, then locks where they stand; a glob arcs out of
		-- Miasma's mouth and lands there FlightTime later. Dodge = get off the locked spot.
		-- 2026-09-29: cast at EVERY living player at once (one reticle each). A player working a
		-- valve gets a poison blob in their maze instead (MiasmaMazeService.SpawnBlob): it blocks
		-- the path until rammed MiasmaMazeGeometry.Tuning.BlobHits times.
		-- (Was a straight fast shot along a ground lane, at body height, until 2026-09-27.)
		FastProjectile = {
			Weight = 5,
			TrackTime = 1.4,   -- reticle follows the target (the "you are marked" window)
			CastLead = 0.75,   -- the ProjectileCast clip starts this long before the launch
			FlightTime = 0.75, -- lock -> impact: the dodge window
			Radius = 6,        -- splash radius at the landing spot
			RawDamage = 38,
			PoisonStacks = 1,
		},
		PoisonScatter = {
			Weight = 3,
			CastTime = 1,
			Lifetime = 12,
			Radius = 8,
			MinimumSpacing = 12,
			RawDamage = 12,
		},
		Submerge = {
			Weight = 2,
			TrackTime = 2,
			-- Authored clip lengths (real seconds, NOT scaled by enrage speed): the body is
			-- hidden once the submerge clip finishes sinking it, and the boss is held through
			-- the whole emerge clip before it can act again.
			SubmergeClipSeconds = 1.2,
			EmergeClipSeconds = 1.2,
			EruptionWarning = 1,
			Radius = 10,
			RawDamage = 80,
			PoisonStacks = 2,
		},
	},

	Sacks = {
		FuseDuration = 10,
		CloudDuration = 12,
		CloudRadius = 14,
		RawDamage = 12,
		BaseHealth = 180,
	},

	-- Phase 1 slimes' ranged attack: a glob LOBBED onto where the target stood when it was
	-- spat (a green ring marks the spot for the whole flight), so stepping off dodges it.
	-- 2026-09-29: was a straight 75 studs/s dart doing 30 (too fast, too strong, too direct).
	SlimeLob = {
		FlightTime = 1.3,   -- seconds from spit to landing: the dodge window
		ArcHeight = 14,     -- studs above the straight line at the peak
		Radius = 5,         -- splash radius at the landing spot
		Damage = 18,
		PoisonStacks = 1,
		Cooldown = 4.5,     -- per slime
		MinRange = 15,      -- only lobs at players this far away (closer = it just fights)
		MaxRange = 80,
	},

	Damage = {
		PoisonDrop = 40,
		SlimeLanding = 30,
		BossDrop = 90,
		Purge = 90,
	},

	Arena = {
		-- Player-scale layout (RS/MiasmaArenaLayout): wall inner face at 104 from the centre.
		CombatRadius = 104,
		-- Only members within this flat distance of the arena centre are in the fight: a player
		-- who hearthstoned / teleported out is never targeted, hit or counted (and the instance's
		-- absence watchdog removes them from the run).
		MemberRadius = 500,
		HazardRadius = 94,        -- random persistent hazards stay inside the ring, clear of the recesses
		ProtectedRadius = 16,     -- around each station/altar protection centre: controls, plate, approach
		BossProtectedRadius = 24, -- boss movement goals keep its root this far from those centres
		                          -- (was 34 at ModelScale 0.67; the body's half-width is ~20 at 0.45)
		SafeAreaRadius = 12,
	},

	-- Defeat presentation timeline (real seconds): the upright boss plays Defeat for
	-- UprightSeconds, then swaps to the flat puddle model, which plays DefeatFlat while the whole
	-- model is scaled down in ShrinkPulses contractions over FlatSeconds, then is removed.
	Defeat = {
		UprightSeconds = 1.2,
		FlatSeconds = 2.4,
		ShrinkPulses = 4,
		PulseDepth = 0.15, -- how far each contraction rebounds, as a fraction of current size
		MinScale = 0.03,
	},

	Animations = {
		-- Boss BODY clips (Idle, AggroStart/Loop, CeilingLatch, LatchDetach, CeilingToBody) live in
		-- MobAnimConfig.MiasmaBoss, which overrides this table; only encounter-specific clips are here.
		LandingSlam = "rbxassetid://93045226675327", -- fall + squash + roar in one clip (was 103860484509234)
		GrowthRoar = nil,
		ProjectileCast = "rbxassetid://133884327006903", -- "poison shot"
		PoisonScatter = "rbxassetid://73241502086963",
		Submerge = "rbxassetid://137691191955697",
		Emerge = "rbxassetid://117168436352107",
		Stunned = "rbxassetid://80490610288868", -- "dizzy"; played LOOPED for the stun duration
		Enrage = "rbxassetid://125089795052900", -- 3.6s: rears up 0.4-1.8, jaw thrust / spew 1.9-2.95 (was 114580354255115)
		-- Player clip for the cleanse channel (hands lowered into the basin). Played on the
		-- local character by MiasmaCleanseUI when set; nil = camera presentation only.
		CleanseHands = nil,
		Defeat = nil,
	},
}

return table.freeze(Config)
