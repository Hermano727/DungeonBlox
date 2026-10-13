--[[
	FirstPersonSwingOverlay -- what YOUR sword swing looks like through your own eyes (first person only).

		FirstPersonSwingOverlay.Begin(character, track)   CombatClient, right after a standing swing starts

	The third-person swing twists and leans the spine, which (the camera sits on the Head PART, welded to the
	root, not on the animated head) swung the skinned head up to 0.8 studs off the camera: you saw the back of
	your own head, and the wind-up happened out of view, so the blade crossed the screen in one frame.

	While the swing track plays, this replaces the upper-body bone Transforms on THIS client only with an
	authored first-person slash (RS/Assets/Animations/FirstPersonSwing, posed in FP_Swing_Edit.blend and
	written by export_fp_swing.py),
	sampled at the track's own progress, so it keeps pace with any swing speed. Bone Transforms set on the
	client never replicate: everyone else still sees the third-person swing.
	  * the torso, neck and head hold the swing's first frame: the camera stays inside the skull and the view
	    never moves (fast clicking must not shake it)
	  * the right arm raises the blade into the top-right of the view and cuts down across to the bottom-left
	  * the pelvis keeps only its translation (no swing lunge or twist), plus the first-person camera's own
	    forward offset (FirstPersonViewModel publishes it as the camera's FirstPersonForward attribute): while
	    walking or sprinting the camera sits 1 - 1.5 studs ahead of the body, so the body is drawn that much
	    ahead too for the swing, keeping the arm at the same distance from the eyes. The camera never moves.
	Standing swings only (a crouched swing keeps its own clip). Restores every Transform before the Animator's
	next step, the same pattern as client/MovementPresentation.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Animations = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Animations")
local Data = require(Animations:WaitForChild("FirstPersonSwing"))
local Grip = require(Animations:WaitForChild("SwordGrip"))

local Overlay = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local ROTATION_ONLY = { Pelvis = true }
-- The overlay owns Hand_R while it plays (client/SwordGripPose stands down). Its Hand_R frames must hold
-- the grip's wrist tilt (FP_Swing_Edit.blend's Hand_R carries it), and it blends from the clip's wrist WITH
-- that tilt, so the tilt never pops in or out as the swing fades.
local HAND_TILT = CFrame.new(table.unpack(Grip.HandTilt))
local FADE_IN = 0.06  -- of the swing's progress
local FADE_OUT = 0.10

-- The sampled frames as CFrames, built once.
local frames = {}
for i, frame in ipairs(Data.Frames) do
	local list = {}
	for b, c in ipairs(frame) do
		list[b] = CFrame.new(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10], c[11], c[12])
	end
	frames[i] = list
end

local active = nil -- { track, bones = { [index] = Bone }, pelvis = Bone }
local saved = {}   -- [Bone] = the Transform before the overlay touched it this frame

local function findBones(character)
	local mesh = character:FindFirstChild("Hero_Character")
	if not mesh then return nil end
	local bones = {}
	for index, name in ipairs(Data.Bones) do
		local bone = mesh:FindFirstChild(name, true)
		if not (bone and bone:IsA("Bone")) then return nil end
		bones[index] = bone
	end
	return bones
end

local function phaseWeight(u)
	if u < FADE_IN then return u / FADE_IN end
	if u > 1 - FADE_OUT then return math.max(0, (1 - u) / FADE_OUT) end
	return 1
end

local function stop()
	active = nil
end

function Overlay.IsActive(character)
	return active ~= nil and active.character == character
end

function Overlay.Begin(character, track)
	if character ~= player.Character or player:GetAttribute("FirstPersonView") ~= true then return end
	local bones = active and active.character == character and active.bones or findBones(character)
	if not bones then return end
	active = { character = character, track = track, bones = bones }
end

-- Put back what the Animator wrote before it writes again (it only rewrites bones its tracks touch).
RunService.PreAnimation:Connect(function()
	for bone, transform in pairs(saved) do bone.Transform = transform end
	table.clear(saved)
end)

RunService.PreSimulation:Connect(function()
	if not active then return end
	local track, character = active.track, active.character
	if not track.IsPlaying or track.Length <= 0 or character ~= player.Character or not character.Parent
		or player:GetAttribute("FirstPersonView") ~= true then
		stop()
		return
	end
	local u = math.clamp(track.TimePosition / track.Length, 0, 1)
	local w = phaseWeight(u) * math.clamp(track.WeightCurrent, 0, 1)
	if w <= 0 then return end
	local x = u * Data.Samples
	local i = math.min(math.floor(x), Data.Samples - 1)
	local f = x - i
	local a, b = frames[i + 1], frames[i + 2]
	local forward = camera:GetAttribute("FirstPersonForward") or 0
	for index, bone in ipairs(active.bones) do
		local base = bone.Transform
		saved[bone] = base
		if bone.Name == "Hand_R" then base *= HAND_TILT end
		local pose = a[index]:Lerp(b[index], f)
		if ROTATION_ONLY[bone.Name] then
			-- Keep the base translation (locomotion bob), drop the swing's lunge and twist, and carry the body
			-- forward with the first-person camera's own offset, expressed in this bone's parent space.
			local offset = Vector3.zero
			if forward ~= 0 and bone.Parent and bone.Parent:IsA("Bone") then
				local frame = (bone.Parent.TransformedWorldCFrame * bone.CFrame).Rotation
				local root = character:FindFirstChild("HumanoidRootPart")
				if root then offset = frame:VectorToObjectSpace(root.CFrame.LookVector * forward) end
			end
			pose = CFrame.new(base.Position + offset) * pose.Rotation
		end
		bone.Transform = base:Lerp(pose, w)
	end
end)

return Overlay
