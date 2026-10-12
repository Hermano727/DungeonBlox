-- MobAnimConfig
-- Per-mob animation table. MobAnimController reads this on spawn.
--
-- Walk:           string  = single animation ID
--                 table   = list of IDs; one is picked randomly each time walking starts
-- Attack:         string  = the mob's ordinary swing, plays on PerformAttack
-- AttackSpeed:    number  = optional playback rate for Attack (2 = twice as
--                 fast, default 1). AttackHitFrame and the attack-state lock
--                 are rescaled with it automatically. ScriptedBody mobs ignore
--                 it -- their pulse is generated, not played from a clip.
-- Moveset:        table   = { <Id> = animation ID } -- one entry per authored
--                 special (combo, slam, ...). The Id matches a MobData
--                 Moveset entry's `Id`; MobMovesetBehaviour plays it and
--                 lands its impacts from that entry's HitTimes.
-- Idle:           string  = loops when the mob is standing still
-- AttackHitFrame: number  = optional. 0-indexed frame, matching however the
--                 clip was authored, at which PerformAttack's damage should
--                 actually land instead of instantly on swing start.
--                 MobAnimController resolves this to a real seconds-offset
--                 by reading the animation's own KeyframeSequence at attach
--                 time (not a guessed fixed frame rate), and caches it on
--                 the mob as _attackHitDelay. Omit for the old instant-hit
--                 behavior. DOES NOT WORK for FBX-imported clips -- they
--                 upload as curve animations and report zero keyframes -- use
--                 AttackHitDelay for those.
-- AttackHitDelay: number  = optional. Same thing as seconds into the clip's
--                 AUTHORED timing, instead of a frame index. Used when
--                 AttackHitFrame can't resolve (FBX imports) and by
--                 ScriptedBody mobs, which have no clip to read frames from.
--                 AttackSpeed rescales it, same as AttackHitFrame.
--
-- Omit any key the mob doesn't need — it falls back gracefully.

local RS = game:GetService("ReplicatedStorage")
local WalkRegistry = require(RS:WaitForChild("MobAnimWalkRegistry"))

return {
	SmallSkeleton = {
		Walk = "rbxassetid://102225428779386",
		Attack = "rbxassetid://102078367847818",
		Idle   = "rbxassetid://180435571",
	},

	-- Attack anim + hit-frame added 2026-09-08, per direct request: "apply
	-- this animation to the plains slime mob (its the attack one) and make
	-- the hit damage ... register at frame 13 of the animation." Verified
	-- via the real KeyframeSequence that this clip is a 24-authored-frame
	-- swing (0-23, ~1s total) -- frame 13 lands at ~0.542s in.
	--
	-- Walk (hop) added same day, per direct request: "do the same for the
	-- hop ... all mobs that are hopping type with this moving animation" --
	-- shared across every HoppingMobClass mob below rather than authoring a
	-- unique hop per mob.
	-- Switched to a scripted squash-and-stretch body 2026-09-08 -- the old
	-- 15-part R15 rig had a structural seam-gap bug (rigid AnimationConstraint
	-- joints tear open at the hip/waist on any hop with enough amplitude --
	-- see MobScriptedBodyAnim for the writeup) that no import setting or
	-- Blender-side fix could close. PlainsSlime's model is now a single
	-- welded "Body" MeshPart with no bones -- MobScriptedBodyAnim drives its
	-- hop squash/stretch and attack pulse directly instead of Animator
	-- keyframe tracks, so there is no Walk/Attack animation id here anymore.
	-- The old rig is kept as ServerStorage.MobModels.PlainsSlime_R15Rig_Backup_20260908.
	PlainsSlime = {
		ScriptedBody = true,
		AttackHitDelay = 0.25, -- seconds into the attack pulse that damage lands
	},

	-- Every other HoppingMobClass mob (MobData JumpHeight > 0, see
	-- MobClassRegistry) gets the same shared hop/move animation. No
	-- Attack/Idle authored for these yet -- omitted, falls back gracefully.
	ForestGoblin = {
		Walk = "rbxassetid://127030291716156",
	},
	PlainsSlimeElite = {
		Walk = "rbxassetid://127030291716156",
	},
	CaveBat = {
		Walk = "rbxassetid://127030291716156",
	},
	StoneGolem = {
		Walk = "rbxassetid://127030291716156",
	},
	CaveBatElite = {
		Walk = "rbxassetid://127030291716156",
	},
	ShadowWolf = {
		Walk = "rbxassetid://127030291716156",
	},
	FlameImp = {
		Walk = "rbxassetid://127030291716156",
	},
	FrostGiant = {
		Walk = "rbxassetid://127030291716156",
	},
	VoidSerpent = {
		Walk = "rbxassetid://127030291716156",
	},
	DragonWhelp = {
		Walk = "rbxassetid://127030291716156",
	},
	AncientGuardian = {
		Walk = "rbxassetid://127030291716156",
	},

	-- Kane the Enraged (first named-elite boss, 2026-09-14). Skinned-mesh
	-- import driven by a real Humanoid+Animator (not AnimationController --
	-- see the ServerStorage.MobModels.Kane rebuild), so this loads exactly
	-- like any other mob's tracks.
	--
	-- Attack is his ORDINARY swing (single diagonal slash, 42 authored frames
	-- at 24 FPS -- Kane_Axe_Slash_Diagonal.fbx). It replaced the old
	-- proximity/"thorns" damage, so he now hits like any other mob when you
	-- are in range and in front of him. Impact measured off the axe tip in the
	-- source .blend: the windup apexes at authored frame 17 and tip speed peaks
	-- at frame 20, so AttackHitFrame is 19 (0-indexed).
	--
	-- The three-hit combo moved into Moveset -- see MobData.Kane.Moveset,
	-- driven by MobMovesetBehaviour off the playing track's own time.
	Kane = {
		Walk = "rbxassetid://105344590641520",
		Attack = "rbxassetid://90231379538528",
		-- Seconds, not AttackHitFrame: this clip was imported from FBX, so its
		-- KeyframeSequence reads back empty and a frame index can never resolve
		-- (see MobAnimController.attach). 19/24 is the same measured impact --
		-- authored frame 20 of 42 at 24 FPS -- expressed in the clip's own
		-- timebase, so AttackSpeed below still halves it to ~0.40s real.
		AttackHitDelay = 19 / 24,
		AttackSpeed = 2, -- 42-frame slash plays in ~0.88s instead of ~1.75s
		Moveset = {
			AxeCombo3Hit = "rbxassetid://95812769767613",
			-- The Fire Tornado cast (SSS/FireTornadoCast). A KeyframeSequence exported by
			-- assets/models/mobs/named elites/kane animation/export_kane_clip.py from
			-- Kane_Groundbreaker_Slam.blend (2 s, axe impact at frame 30); played at
			-- FireTornadoConfig.SLAM_SPEED so the impact lands on its WINDUP.
			GroundbreakerSlam = "rbxassetid://107914870307930",
		},
	},

	-- Miasma (T1 dungeon boss). Skinned mesh on the v3 JAW rig (2026-10-11, model
	-- MiasmaBossJawRig: Root > Body > Skirt_F/B/L/R, LowerJaw, Spine1 > Spine2 > Head), every
	-- body clip authored in Blender by assets/models/mobs/dungeon bosses/miasma/v3/build_clips_v3.py
	-- (README there). No walk clip: while chasing it plays AggroLoop instead.
	-- AggroStart plays once on acquiring a target, then AggroLoop holds until the target is lost:
	-- jaw closed, eyes showing, surging forward to gape at you and snapping half shut.
	-- The v2 lattice-rig ids are kept in comments (they only drive MiasmaBossEyeRig).
	MiasmaBoss = {
		Idle       = "rbxassetid://100923448881987", -- 2.5 s loop (was 103328246296289)
		-- The BITE (1.0 s, 2026-10-11 v2): a quick gape (0.13-0.27 s), then it lunges forward and
		-- down, its head arcing over you, and the jaws clamp at frame 13 = 0.4 s, ~30 studs out
		-- (its reach, MobData AttackRange). Damage lands at the snap; MobData MeleeHalfAngle makes
		-- it frontal only. (v1, 1.4 s with the snap at 0.6: 78008389802538.)
		Attack     = "rbxassetid://71951280069309",
		AttackHitDelay = 0.4,
		AggroStart = "rbxassetid://95449104792737",  -- 1.2 s (was 126756643218296)
		AggroLoop  = "rbxassetid://128672953481049", -- 2.0 s loop (was 131702188473926)
		-- Plays on the separate ceiling-latch model (MobData CeilingLatchModelName), not on the
		-- boss mesh -- see DungeonBossMobClass._spawnLatchProxy.
		CeilingLatch = "rbxassetid://83190161792275",
		-- Phase 1 -> 2 bridge (0.6s each, played together; see MiasmaEncounterConfig.BossDropSequence).
		-- LatchDetach plays on the CEILING-LATCH model's Animator, CeilingToBody on the boss's.
		LatchDetach  = "rbxassetid://74367298964889",
		CeilingToBody = "rbxassetid://103523507560130", -- v3 (was 115862676634720)
		-- Defeat presentation (DungeonBossMobClass:PlayDefeatPresentation): Defeat plays on the
		-- upright boss; DefeatFlat plays on the flat puddle model (MobData DefeatFlatModelName)
		-- while the runtime shrinks it. Neither loops.
		Defeat     = "rbxassetid://136318150864363", -- upright -> flat, v3 (was 131193462993192)
		DefeatFlat = "rbxassetid://125610215342818", -- flat -> gone (body pulses; shrink is scripted)
	},
	MiasmaSlime = {
		ScriptedBody = true,
		AttackHitDelay = 0.25,
	},
	-- Miasma's underling (2026-10-10): KeyframeSequences exported by
	-- assets/models/mobs/dungeon bosses/miasma/underling/export_underling_clips.py (24 fps, every
	-- frame). Attack is the THRUST, hit at frame 11 = 10/24 s from the clip start.
	MiasmaUnderling = {
		Walk = "rbxassetid://74797150047181",   -- Crawl, 0.67 s loop
		Idle = "rbxassetid://125547582810550",  -- breathing, 2 s loop
		Attack = "rbxassetid://98222048415471", -- Thrust, 1 s
		AttackHitDelay = 10 / 24,
		Moveset = {
			Slam = "rbxassetid://85006863859765", -- 1.5 s, impact 15/24 s
			Spit = "rbxassetid://93127792551463", -- 1.25 s, release 14/24 s
		},
	},
	MiasmaClog = {}, -- the vine has no clips and no squash: it just sits there
	MiasmaSack = { ScriptedBody = true },

	-- Template for adding future mobs:
	-- MyNewMob = {
	-- 	Walk   = WalkRegistry.Walk1,
	-- 	Attack = "rbxassetid://...",
	-- 	Idle   = "rbxassetid://...",
	-- 	-- Only for mobs with authored specials (see MobMovesetBehaviour):
	-- 	-- Moveset = { MySpecial = "rbxassetid://..." },
	-- },
}
