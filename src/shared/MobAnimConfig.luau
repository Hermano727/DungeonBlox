-- MobAnimConfig
-- Per-mob animation table. MobAnimController reads this on spawn.
--
-- Walk:           string  = single animation ID
--                 table   = list of IDs; one is picked randomly each time walking starts
-- Attack:         string  = plays on PerformAttack
-- Idle:           string  = loops when the mob is standing still
-- AttackHitFrame: number  = optional. 0-indexed frame, matching however the
--                 clip was authored, at which PerformAttack's damage should
--                 actually land instead of instantly on swing start.
--                 MobAnimController resolves this to a real seconds-offset
--                 by reading the animation's own KeyframeSequence at attach
--                 time (not a guessed fixed frame rate), and caches it on
--                 the mob as _attackHitDelay. Omit for the old instant-hit
--                 behavior.
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
	-- like any other mob's Walk track. No Attack yet, per direct request.
	Kane = {
		Walk = "rbxassetid://105344590641520",
	},

	-- Miasma (T1 dungeon boss). No walk animation authored yet, so it slides
	-- while chasing -- acceptable for now. AggroStart doubles as the attack
	-- animation since there is no dedicated active-aggro loop yet.
	MiasmaBoss = {
		Idle       = "rbxassetid://74796988436650",
		Attack     = "rbxassetid://119310311898063",  -- Aggro Start, reused
		AggroStart = "rbxassetid://119310311898063",
		CeilingLatch = "rbxassetid://83086053617866",
	},

	-- Template for adding future mobs:
	-- MyNewMob = {
	-- 	Walk   = WalkRegistry.Walk1,
	-- 	Attack = "rbxassetid://...",
	-- 	Idle   = "rbxassetid://...",
	-- },
}