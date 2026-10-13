--[[
	CharacterAnimProfiles
	Registry of locomotion animation clips per "what's equipped" profile, for
	the custom skinned player rig (Hero_Character, 52-bone skeleton -- see
	Animate2/init.client.lua and WeaponAttachClient.client.lua). Mirrors
	MobAnimConfig.luau's plain-table registry pattern (same project
	convention, different domain).

	Missing clips (2026-09-14, not yet authored for this skeleton): Jump,
	Fall, Landing, RunStop. Left absent here rather than guessed or
	borrowed from the old R15 rig's incompatible assets -- Animate2 holds
	the current pose/state when a requested clip is missing instead of
	substituting a wrong-rig animation. The melee swing is configured in
	CombatAnimConfig and played by CombatClient at Action priority over
	these locomotion tracks.

	Walk / RunStart / RunLoop (2026-10-12) are authored by script, not exported
	FBX: assets/models/main character/locomotion/author_locomotion.py (4-step
	asymmetric loops: uneven step timing, the left arm leads, overlap on elbow /
	wrist / head, loops start on the passing pose; Run_Start ends on it). Walk is
	authored for speed 8.7 and RunLoop for the sprint speed (Animate2 scales both
	by the real speed). CrouchIdle / CrouchWalk (2026-10-12) come from the same script: an athletic
	crouch (hips low between the feet, torso forward through the spine, knees over the toes), not the
	old lean-back "invisible chair"), all sharing one base pose: CrouchEnter (standing -> crouch, ends on
	CrouchIdle's first pose), CrouchIdle (4 s, breathing), CrouchWalk (4 studs/s = the crouch speed, ~0.9 s
	per left/right cycle) and CrouchExit (crouch -> standing). Enter / Exit hold their last pose; Animate2
	hands off on its own clock (CROUCH_ENTER_LENGTH / CROUCH_EXIT_LENGTH). Old FBX ids in the comments,
	kept for a quick revert.
]]

local BowConfig = require(script.Parent:WaitForChild("BowConfig"))

local CharacterAnimProfiles = {}

CharacterAnimProfiles.Profiles = {
	Unarmed = {
		CrouchIdle = "rbxassetid://79347873142496", -- old FBX 88535647574045
		CrouchWalk = "rbxassetid://124190788617594", -- old FBX 75552957909461
		CrouchEnter = "rbxassetid://114249007153841", -- standing -> crouch, 0.32 s, then holds
		CrouchExit = "rbxassetid://93551354269514",  -- crouch -> standing, 0.30 s, then holds
		Idle = "rbxassetid://72094441737047",
		Walk = "rbxassetid://105971759730904",      -- old FBX 95948405960169
		RunStart = "rbxassetid://106277664313122", -- old FBX 140166382441030
		RunLoop = "rbxassetid://126353627348863",   -- old FBX 115075307442771
	},
	Sword = {
		CrouchIdle = "rbxassetid://102877477973093", -- old FBX 125056721204059
		CrouchWalk = "rbxassetid://78931282062519", -- old FBX 95552267471977
		CrouchEnter = "rbxassetid://136724588218577", -- standing -> crouch, 0.32 s, then holds
		CrouchExit = "rbxassetid://94017312820670",  -- crouch -> standing, 0.30 s, then holds
		Idle = "rbxassetid://134742105465889",
		Walk = "rbxassetid://82335503911683",      -- old FBX 120007605000208
		RunStart = "rbxassetid://106932126155402",  -- old FBX 118461840134893
		RunLoop = "rbxassetid://110924516145160",  -- old FBX 83948294410663
	},
}

function CharacterAnimProfiles.CrouchReady()
    for _, name in ipairs({"Unarmed", "Sword"}) do
        local profile = CharacterAnimProfiles.Profiles[name]
        if not profile.CrouchIdle or profile.CrouchIdle == "" or not profile.CrouchWalk or profile.CrouchWalk == "" then return false end
    end
    return true
end

-- Only known swords use sword poses. Unauthored tools retain unarmed
-- locomotion until they get their own profile.
function CharacterAnimProfiles.GetProfileForTool(tool)
	if not tool then
		return "Unarmed"
	end
	local weaponId = tool:GetAttribute("WeaponId")
	if weaponId and CharacterAnimProfiles.Profiles[weaponId] then
		return weaponId
	end
	if tool:GetAttribute("WeaponType") == "Sword" or weaponId == "TrainingSword" then
		return "Sword"
	end
	return "Unarmed"
end

--------------------------------------------------------------------------
-- Seeded one-handed grip frame (Hand_R bone-local CFrame), now used by the pickaxe and
-- spear only (the sword has its own measured grip since 2026-10-13, SWORD_GRIP_OFFSET
-- below) -- see WeaponAttachClient.client.lua for how this is applied
-- (Hand_R.TransformedWorldCFrame * SWORD_GRIP_OFFSET).
--
-- Seeded from the Blender authoring master (MaleBase_Skinned_5Studs.blend)'s
-- reference sword ("Hero_Sword"), which is rigidly skin-bound to Hand_R (an
-- Armature modifier, 100% vertex weight -- NOT bone-parented, so the
-- object's own transform is identity and meaningless; the real placement
-- is baked into its vertex positions). Computed in Hand_R's REST-POSE
-- LOCAL space (Hand_R_rest_world_matrix:Inverse() * vertex_world_position
-- for every vertex):
--   - Principal (blade) axis via PCA over all vertices: (0.795, 0.001, 0.607)
--   - Mesh vertex closest to Hand_R's own bone-local origin: (0.078, 0.231,
--     -0.059), distance 0.251 -- a proxy for "where the palm/grip center
--     sits relative to the wrist-ish bone origin."
-- Hero_Sword is a different, differently-scaled reference asset from the
-- actual TrainingSword.Handle being attached, so this data is used for
-- ORIENTATION + approximate relative POSITION, not a literal unit
-- transfer -- and roll around the blade axis isn't recoverable from this
-- data at all (the seed "right" vector below is arbitrary).
--
-- THIS IS A STARTING VALUE, NOT A FINAL ONE. Per the project's own
-- documented convention for TrainingSword's original Tool.Grip ("rotation
-- still needs per-weapon tuning... tune live in Play"), validate and
-- adjust live in Studio (F6 UIDevTool, Model mode) and hand-update this
-- constant once it looks right -- same workflow ArmorEquipVisuals.lua's
-- WornC0 values already use.
local BLADE_AXIS_HAND_R_LOCAL = Vector3.new(0.795, 0.001, 0.607)

-- The measured seed position (see the PCA note above). Do not hand-edit this to
-- reposition the weapon -- use the two tuning scalars below instead.
local GRIP_SEED_HAND_R_LOCAL = Vector3.new(0.078, 0.231, -0.059)

-- Which way the CHARACTER's left points, expressed in Hand_R's bone-local axes.
-- Sampled live off Hand_R.WorldCFrame against the character's facing (2026-09-18).
--
-- DO NOT tune the weapon by nudging Hand_R's raw X/Y/Z. Those axes are not
-- aligned with anything you can see, and worse, they are not independent of each
-- other for this purpose: "left" here overlaps the blade axis at -0.68, so a
-- pure -X nudge is only ~60% lateral and spends the other ~40% sliding the sword
-- DOWN its own blade. That is what a "move it left" pass did on 2026-09-18 -- it
-- read as moving only halfway, and it silently pushed the hand a third of a stud
-- up toward the tip, off the handle.
local CHARACTER_LEFT_HAND_R_LOCAL = Vector3.new(-0.979, -0.130, 0.155)

-- The two tuning knobs, in studs. These ARE independent -- the lateral axis is
-- built perpendicular to the blade below, so each one moves the weapon in
-- exactly one direction and neither disturbs the other.
--   GRIP_LATERAL_OFFSET     + = toward the character's LEFT (into the palm),
--                           - = out to their right.
--   GRIP_ALONG_BLADE_OFFSET + = toward the blade TIP, which slides the hand DOWN
--                           the weapon toward the pommel; - grips higher up.
local GRIP_LATERAL_OFFSET = 0.24
local GRIP_ALONG_BLADE_OFFSET = 0

local GRIP_POSITION_HAND_R_LOCAL do
	local bladeUnit = BLADE_AXIS_HAND_R_LOCAL.Unit
	-- Strip the along-blade part out of "left" so the lateral knob is purely lateral.
	local left = CHARACTER_LEFT_HAND_R_LOCAL
	local lateralUnit = (left - bladeUnit * left:Dot(bladeUnit)).Unit
	GRIP_POSITION_HAND_R_LOCAL = GRIP_SEED_HAND_R_LOCAL
		+ lateralUnit * GRIP_LATERAL_OFFSET
		+ bladeUnit * GRIP_ALONG_BLADE_OFFSET
end

-- The grip frame in Hand_R's local space: origin in the palm, +Y along the blade, +X along
-- the sword's edge (TrainingSword's handle is wide in X, thin in Z).
local GRIP_FRAME_HAND_R_LOCAL do
	local up = BLADE_AXIS_HAND_R_LOCAL.Unit
	local seedRight = Vector3.new(1, 0, 0)
	if math.abs(up:Dot(seedRight)) > 0.9 then
		seedRight = Vector3.new(0, 0, 1)
	end
	-- Supply an orthonormal basis explicitly; seedRight is not perpendicular
	-- to the measured blade axis and must not be passed through unchanged.
	local right = (seedRight - up * seedRight:Dot(up)).Unit
	GRIP_FRAME_HAND_R_LOCAL = CFrame.fromMatrix(GRIP_POSITION_HAND_R_LOCAL, right, up, right:Cross(up))
end

-- The sword's own grip (2026-10-13): TrainingSword.Handle's CFrame (its bounding-box centre) in Hand_R's
-- bone space, measured, not seeded. Posed by hand in assets/models/main character/locomotion/
-- FP_Swing_Edit.blend: handle diagonal across the palm, pommel at the heel of the hand, blade near the
-- line of the forearm. Hero_Sword there is TrainingSword's own mesh at its in-game size (vertex fit
-- within 0.02 studs), and the bone conversion is export_fp_swing.py's. The fist that closes on it
-- (fingers, thumb, a fixed wrist tilt) is client/SwordGripPose. Re-pose in that file and re-measure;
-- do not hand-tune these numbers.
CharacterAnimProfiles.SWORD_GRIP_OFFSET = CFrame.fromMatrix(
	Vector3.new(0.517394, 0.920754, 0.464199),
	Vector3.new(-0.59551, 0.722707, -0.350803),
	Vector3.new(0.622693, 0.691154, 0.366823))

-- Any other one-handed tool held like the sword: give the grip point, the shaft direction (toward
-- the business end) and the striking side, all in the tool Handle's own space. The shaft lands
-- where the sword's blade does and the striking side where its edge does.
local function handGripOffset(gripPoint, shaftDir, strikeDir)
	local up = shaftDir.Unit
	local right = (strikeDir - up * strikeDir:Dot(up)).Unit
	local gripInHandle = CFrame.fromMatrix(gripPoint, right, up, right:Cross(up))
	return GRIP_FRAME_HAND_R_LOCAL * gripInHandle:Inverse()
end

-- WoodenPickaxe (2026-10-03, measured from its mesh in Handle space): the shaft runs from its
-- butt at (0, -1.05, 0.77) up and slightly back to the head, which lies across X with the
-- pick spike on +X. Held 0.45 studs up from the butt. Starting values: tune live.
CharacterAnimProfiles.PICKAXE_GRIP_OFFSET = handGripOffset(
	Vector3.new(0.04, -0.62, 0.64), Vector3.new(0.108, 0.952, -0.285), Vector3.new(1, 0, 0))

-- WoodenSpear: a 7.5-stud union along Handle X with its blade at -X (flat in Z). Held a little
-- behind the middle, tip forward like the sword's blade.
CharacterAnimProfiles.SPEAR_GRIP_OFFSET = handGripOffset(
	Vector3.new(1.2, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1))

local function isPickaxeTool(tool)
	return tool:GetAttribute("DungeonEquipSlot") == "Pickaxe" or string.find(tool.Name, "Pickaxe", 1, true) ~= nil
end

local function isSpearTool(tool)
	return tool:GetAttribute("DungeonEquipSlot") == "FishingSpear" or string.find(tool.Name, "Spear", 1, true) ~= nil
end

-- Which hand bone a held weapon's visual follows, and its offset from that bone
-- (WeaponAttachClient; EquippedHotbar secures the physical parts of exactly these tools).
-- nil = not a bone-held weapon. Pickaxes and spears ride Hand_R like the sword. Bows ride the LEFT hand (right-handed archer); their
-- locomotion stays Unarmed, with BowController's arm clips layered on top.
function CharacterAnimProfiles.GetAttachForTool(tool)
	if not tool then
		return nil
	end
	if BowConfig.IsBow(tool) then
		return { kind = "Bow", bone = "Hand_L", offset = BowConfig.BOW_GRIP }
	end
	if CharacterAnimProfiles.GetProfileForTool(tool) == "Sword" then
		return { kind = "Sword", bone = "Hand_R", offset = CharacterAnimProfiles.SWORD_GRIP_OFFSET }
	end
	-- Profession tools: this rig has no RightHand part for Humanoid:EquipTool to weld to.
	if isPickaxeTool(tool) then
		return { kind = "Pickaxe", bone = "Hand_R", offset = CharacterAnimProfiles.PICKAXE_GRIP_OFFSET }
	end
	if isSpearTool(tool) then
		return { kind = "Spear", bone = "Hand_R", offset = CharacterAnimProfiles.SPEAR_GRIP_OFFSET }
	end
	return nil
end

return CharacterAnimProfiles
