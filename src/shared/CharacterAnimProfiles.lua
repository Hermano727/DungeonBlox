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

	RunStart ids (2026-09-14) are re-authored 1.5x faster than the original
	export -- the original pace looked clunky against this game's actual
	sprint-start acceleration, which ramps up faster than the first cut of
	the clip assumed.
]]

local CharacterAnimProfiles = {}

CharacterAnimProfiles.Profiles = {
	Unarmed = {
		CrouchIdle = "rbxassetid://88535647574045",
		CrouchWalk = "rbxassetid://75552957909461",
		Idle = "rbxassetid://72094441737047",
		Walk = "rbxassetid://95948405960169",
		RunStart = "rbxassetid://140166382441030",
		RunLoop = "rbxassetid://115075307442771",
	},
	Sword = {
		CrouchIdle = "rbxassetid://125056721204059",
		CrouchWalk = "rbxassetid://95552267471977",
		Idle = "rbxassetid://134742105465889",
		Walk = "rbxassetid://120007605000208",
		RunStart = "rbxassetid://118461840134893",
		RunLoop = "rbxassetid://83948294410663",
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
-- Sword grip offset (Hand_R bone-local CFrame) -- see
-- WeaponAttachClient.client.lua for how this is applied
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

-- TrainingSword.Handle's own PivotOffset: the grip point sits 0.951825 studs
-- below the mesh's geometric center along local +Y (blade extends +Y) --
-- see WeaponMeshes.luau's GripDrop and the CLAUDE.md weapon-authoring
-- convention. We're setting Handle.CFrame directly (its geometric center),
-- so back-solve from the desired PIVOT (grip) transform to the center
-- transform that puts the pivot there.
-- Sword resized to 70%, then narrowed 15% and lengthened 5% (2026-09-15).
-- Long-axis factor is 0.735; preserve the grip point rather than mesh center.
local HANDLE_PIVOT_OFFSET = CFrame.new(0, -0.951825, 0)

local function buildGripOffset()
	local up = BLADE_AXIS_HAND_R_LOCAL.Unit
	local seedRight = Vector3.new(1, 0, 0)
	if math.abs(up:Dot(seedRight)) > 0.9 then
		seedRight = Vector3.new(0, 0, 1)
	end
	-- Supply an orthonormal basis explicitly; seedRight is not perpendicular
	-- to the measured blade axis and must not be passed through unchanged.
	local right = (seedRight - up * seedRight:Dot(up)).Unit
	local gripLocalCFrame = CFrame.fromMatrix(GRIP_POSITION_HAND_R_LOCAL, right, up, right:Cross(up))
	return gripLocalCFrame * HANDLE_PIVOT_OFFSET:Inverse()
end

CharacterAnimProfiles.SWORD_GRIP_OFFSET = buildGripOffset()

return CharacterAnimProfiles
