--[[
	SwordGripPose -- the right hand closed round the sword, on every character holding one (2026-10-13).

	Every armed clip keys the same loose fist, which never closed on the handle. The real grip is posed by
	hand in assets/models/main character/locomotion/FP_Swing_Edit.blend: handle diagonal across the palm,
	thumb over the fingers, the wrist tilted toward the little finger so the blade runs near the forearm.
	CharacterAnimProfiles.SWORD_GRIP_OFFSET places the sword in that hand; this makes the hand match, on top
	of whatever clip plays (RS/Assets/Animations/SwordGrip):
	  * the right fingers take the grip's Transforms outright (SwordGrip.Fingers)
	  * Hand_R gets the grip's fixed tilt multiplied onto the clip's own wrist (SwordGrip.HandTilt), except
	    while your first-person swing overlay plays: it owns Hand_R and carries the tilt itself
	Runs for every character on every client, so everyone sees the same grip (bone Transforms set on a
	client never replicate). Not while the sword is hidden (drinking, riding), the same rule as
	WeaponAttachClient. Restores every Transform before the Animator's next step, like FirstPersonSwingOverlay.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ActiveEquipment = require(ReplicatedStorage:WaitForChild("ActiveEquipment"))
local Profiles = require(ReplicatedStorage:WaitForChild("CharacterAnimProfiles"))
local Grip = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Animations"):WaitForChild("SwordGrip"))
local PotionPresentation = require(script.Parent:WaitForChild("PotionPresentation"))
local Overlay = require(script.Parent:WaitForChild("FirstPersonSwingOverlay"))

local MAX_DISTANCE = 200 -- studs from the camera: past this a fist is a few pixels

local HAND_TILT = CFrame.new(table.unpack(Grip.HandTilt))
local FINGERS = {}
for name, c in pairs(Grip.Fingers) do
	FINGERS[name] = CFrame.new(table.unpack(c))
end

local camera = workspace.CurrentCamera
local boneCache = setmetatable({}, { __mode = "k" }) -- [character] = { mesh, hand, fingers = { [Bone] = CFrame } }
local saved = {} -- [Bone] = its Transform before this script touched it this frame

local function bonesFor(character)
	local mesh = character:FindFirstChild("Hero_Character")
	if not mesh then return nil end
	local cached = boneCache[character]
	if cached and cached.mesh == mesh then return cached end
	local hand = mesh:FindFirstChild("Hand_R", true)
	if not (hand and hand:IsA("Bone")) then return nil end
	local fingers = {}
	for name, pose in pairs(FINGERS) do
		local bone = mesh:FindFirstChild(name, true)
		if not (bone and bone:IsA("Bone")) then return nil end
		fingers[bone] = pose
	end
	cached = { mesh = mesh, hand = hand, fingers = fingers }
	boneCache[character] = cached
	return cached
end

local function holdsVisibleSword(player, character)
	local tool = ActiveEquipment.GetTool(character)
	local attach = tool and Profiles.GetAttachForTool(tool)
	if not (attach and attach.kind == "Sword") then return false end
	return not PotionPresentation.IsDrinking(character) and player:GetAttribute("Mounted") ~= true
end

-- Put back what the Animator wrote before it writes again (it only rewrites bones its tracks touch).
RunService.PreAnimation:Connect(function()
	for bone, transform in pairs(saved) do bone.Transform = transform end
	table.clear(saved)
end)

-- PostSimulation: after the first-person overlay (PreSimulation) has settled whether it plays this frame.
RunService.PostSimulation:Connect(function()
	local eye = camera.CFrame.Position
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root or (root.Position - eye).Magnitude > MAX_DISTANCE then continue end
		if not holdsVisibleSword(player, character) then continue end
		local bones = bonesFor(character)
		if not bones then continue end
		for bone, pose in pairs(bones.fingers) do
			saved[bone] = bone.Transform
			bone.Transform = pose
		end
		if not Overlay.IsActive(character) then
			saved[bones.hand] = bones.hand.Transform
			bones.hand.Transform *= HAND_TILT
		end
	end
end)
