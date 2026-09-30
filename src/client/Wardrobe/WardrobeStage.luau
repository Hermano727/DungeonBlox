--[[
	WardrobeStage -- the detached grass field the wardrobe shows your character on (client only).

		local stage = WardrobeStage.Open(character)   -- nil if the character isn't ready
		stage:ApplyAppearance(appearance)             -- live preview (RS/AppearanceApply)
		stage:Rotate(degrees)                         -- spin the model (drag in the menu)
		stage:Close()

	Nothing here exists for anyone else. The field is built far above the map (STAGE_ORIGIN) out
	of one huge flat grass plate, a copy of your character stands
	on it looping the unarmed idle, and the camera is taken over (CameraOverrideState) to frame
	it on the RIGHT side of the screen, leaving the left for the menu. Your real character stays
	frozen at the wardrobe the whole time (the menu sinks movement input).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local AppearanceApply = require(ReplicatedStorage:WaitForChild("AppearanceApply"))
local CameraOverrideState = require(ReplicatedStorage:WaitForChild("CameraOverrideState"))
local CharacterAnimProfiles = require(ReplicatedStorage:WaitForChild("CharacterAnimProfiles"))
local FacePlates = require(script.Parent.Parent:WaitForChild("FacePlates"))

local WardrobeStage = {}
WardrobeStage.__index = WardrobeStage

local STAGE_ORIGIN = Vector3.new(0, 3000, 0) -- ground level of the field; far above everything
local PLATE_SIZE = 2048                        -- flat grass plate to the horizon
local GRASS_COLOR = Color3.fromRGB(78, 104, 52)
local ROCK_COLOR = Color3.fromRGB(96, 96, 92)

-- Framing: the model faces the camera; the camera looks LEFT of it so it sits right of centre.
local FOV = 36
local CAMERA_BACK = 13.5        -- studs in front of the model
local CAMERA_UP = 4.2           -- camera height above the ground (clear of the grass blades)
local LOOK_LEFT = 3.1           -- how far left of the model the camera aims
local LOOK_UP = 2.7
local SWAY = 0.06               -- tiny idle drift so the shot isn't dead still

-- Camera shots per wardrobe category (AppearanceOptions Category.Focus). "Body" is measured
-- from the ground, the others from the centre of the head; `back` = studs in front, `up` =
-- camera height over the anchor, `aim` = how far above the anchor it looks. Every shot aims
-- LEFT of the model by the same fraction of its distance, so the model stays right of centre.
local LEFT_RATIO = LOOK_LEFT / CAMERA_BACK
local SHOTS = {
	Body = { back = CAMERA_BACK, up = CAMERA_UP, aim = LOOK_UP, fromHead = false },
	Face = { back = 3.2, up = 0.08, aim = 0.02, fromHead = true },
	Hair = { back = 3.7, up = 1.05, aim = 0.12, fromHead = true },
}
local SHOT_BLEND = .6           -- seconds to glide between shots
local HEAD_CENTRE_ABOVE_BONE = 0.3 -- the Head bone sits at the base of the skull

local function cleanClone(clone)
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Sound") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.LocalTransparencyModifier = 0
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		elseif d:IsA("Decal") then
			d.LocalTransparencyModifier = 0
		elseif d:IsA("BillboardGui") or d:IsA("SurfaceGui") or d:IsA("ProximityPrompt") then
			d:Destroy()
		end
	end
	for _, child in ipairs(clone:GetChildren()) do
		if child:IsA("Tool") then child:Destroy() end
	end
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
end

-- The field's surface under the model (measured, so the plate's placement can change freely).
local function groundAt(folder)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { folder:FindFirstChild("Plate") }
	local hit = Workspace:Raycast(STAGE_ORIGIN + Vector3.new(0, 40, 0), Vector3.new(0, -80, 0), params)
	return hit and hit.Position.Y or STAGE_ORIGIN.Y
end

-- Lowest point of the character's body (the skinned body mesh's bottom; the whole model's
-- box as a fallback), so its feet can be put exactly on the ground.
local function feetY(clone)
	local body = clone:FindFirstChild("Hero_Character")
	if body and body:IsA("BasePart") then return body.Position.Y - body.Size.Y * .5 end
	local cf, size = clone:GetBoundingBox()
	return cf.Position.Y - size.Y * .5
end

local function playIdle(clone)
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local idle = CharacterAnimProfiles.Profiles.Unarmed and CharacterAnimProfiles.Profiles.Unarmed.Idle
	if not animator or type(idle) ~= "string" or idle == "" then return nil end
	local anim = Instance.new("Animation")
	anim.AnimationId = idle
	local ok, track = pcall(animator.LoadAnimation, animator, anim)
	if not ok or not track then return nil end
	track.Priority = Enum.AnimationPriority.Core
	track.Looped = true
	track:Play(0)
	return track
end

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do p[k] = v end
	return p
end

local function buildField(folder)
	-- A flat grass plate to the horizon, its top exactly at STAGE_ORIGIN. No terrain: the
	-- place's terrain grass blades are taller than the character here and buried it (and a
	-- script can neither read nor change their length).
	part({
		Name = "Plate", Size = Vector3.new(PLATE_SIZE, 2, PLATE_SIZE),
		CFrame = CFrame.new(STAGE_ORIGIN - Vector3.new(0, 1, 0)),
		Material = Enum.Material.Grass, Color = GRASS_COLOR, CastShadow = false, Parent = folder,
	})
	-- A few rocks far out, so the field has some depth.
	local rng = Random.new(7)
	for i = 1, 9 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local dist = rng:NextNumber(38, 120)
		local s = rng:NextNumber(2, 7)
		part({
			Name = "Rock" .. i, Size = Vector3.new(s * rng:NextNumber(1, 1.8), s * rng:NextNumber(.5, .9), s),
			CFrame = CFrame.new(STAGE_ORIGIN + Vector3.new(math.cos(angle) * dist, s * .2, math.sin(angle) * dist))
				* CFrame.Angles(rng:NextNumber(-.3, .3), rng:NextNumber(0, 6.28), rng:NextNumber(-.3, .3)),
			Material = Enum.Material.Slate, Color = ROCK_COLOR, Parent = folder,
		})
	end
end

function WardrobeStage.Open(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end

	local folder = Instance.new("Folder")
	folder.Name = "WardrobeStage"
	buildField(folder)

	local wasArchivable = character.Archivable
	character.Archivable = true
	local clone = character:Clone()
	character.Archivable = wasArchivable
	if not clone then folder:Destroy(); return nil end
	cleanClone(clone)
	clone.Name = "WardrobePreview"
	clone.Parent = folder
	folder.Parent = Workspace

	local ground = groundAt(folder)
	local self = setmetatable({
		folder = folder, clone = clone, ground = ground,
		standAt = Vector3.new(STAGE_ORIGIN.X, ground + 5, STAGE_ORIGIN.Z),
		yaw = 0, started = os.clock(),
	}, WardrobeStage)
	self:_place()
	-- Stand it on the grass: lift/drop by however far its feet are from the ground.
	self.standAt += Vector3.new(0, ground - feetY(clone), 0)
	self:_place()
	self.idle = playIdle(clone)
	local body = clone:FindFirstChild("Hero_Character")
	self.headBone = body and body:FindFirstChild("Head", true)
	self.shot = "Body"
	self.detachFace = FacePlates.Attach(clone) -- the face, following the clone's head bone

	-- Camera: taken from FirstPersonViewModel for as long as the stage is up.
	local camera = Workspace.CurrentCamera
	self.cameraSaved = { type = camera.CameraType, fov = camera.FieldOfView, cframe = camera.CFrame }
	CameraOverrideState.SetActive(true)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = FOV
	self.cameraConn = RunService:BindToRenderStep("WardrobeStageCamera", Enum.RenderPriority.Camera.Value + 2, function()
		self:_updateCamera()
	end)
	self:_updateCamera()
	return self
end

function WardrobeStage:_place()
	-- Faces +Z, toward the camera, turned by the player's drag.
	local base = CFrame.lookAt(self.standAt, self.standAt + Vector3.new(0, 0, 1))
	self.clone:PivotTo(base * CFrame.Angles(0, math.rad(self.yaw), 0))
end

function WardrobeStage:_updateCamera()
	local camera = Workspace.CurrentCamera
	local t = os.clock() - self.started
	local eye, target = self:_shotPoints(self.shot or "Body")
	-- Glide from wherever the camera was when the shot changed.
	if self.blendFrom then
		local u = math.clamp((os.clock() - self.blendStart) / SHOT_BLEND, 0, 1)
		u = u * u * (3 - 2 * u)
		eye = self.blendFrom.eye:Lerp(eye, u)
		target = self.blendFrom.target:Lerp(target, u)
		if u >= 1 then self.blendFrom = nil end
	end
	local swayScale = (self.shot == "Body" or not self.shot) and 1 or .25
	local sway = Vector3.new(math.sin(t * .35) * SWAY * 4, math.sin(t * .5) * SWAY, 0) * swayScale
	self.lastEye, self.lastTarget = eye, target
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(eye + sway, target)
end

-- Where the camera sits and looks for a shot, right now.
function WardrobeStage:_shotPoints(name)
	local shot = SHOTS[name] or SHOTS.Body
	local anchor
	if shot.fromHead and self.headBone and self.headBone.Parent then
		anchor = self.headBone.WorldPosition + Vector3.new(0, HEAD_CENTRE_ABOVE_BONE, 0)
	else
		anchor = Vector3.new(STAGE_ORIGIN.X, self.ground, STAGE_ORIGIN.Z)
	end
	local eye = anchor + Vector3.new(0, shot.up, shot.back)
	local target = anchor + Vector3.new(-shot.back * LEFT_RATIO, shot.aim, 0)
	return eye, target
end

-- Switch the camera shot ("Body" | "Face" | "Hair"), gliding there.
function WardrobeStage:SetFocus(name)
	name = SHOTS[name] and name or "Body"
	if name == self.shot then return end
	if self.lastEye then self.blendFrom = { eye = self.lastEye, target = self.lastTarget } end
	self.blendStart = os.clock()
	self.shot = name
end

function WardrobeStage:ApplyAppearance(appearance)
	if self.clone and self.clone.Parent then AppearanceApply.Apply(self.clone, appearance) end
end

function WardrobeStage:Rotate(degrees)
	self.yaw = (self.yaw + (tonumber(degrees) or 0)) % 360
	self:_place()
end

function WardrobeStage:Close()
	if self.closed then return end
	self.closed = true
	pcall(function() RunService:UnbindFromRenderStep("WardrobeStageCamera") end)
	if self.idle then pcall(function() self.idle:Stop(0) end) end
	if self.detachFace then self.detachFace() end
	local camera = Workspace.CurrentCamera
	local saved = self.cameraSaved
	if saved then
		camera.FieldOfView = saved.fov
		camera.CFrame = saved.cframe
		camera.CameraType = saved.type
	end
	CameraOverrideState.SetActive(false)
	self.folder:Destroy()
end

return WardrobeStage
