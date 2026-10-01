--!strict
--  CharacterViewport -- renders the local player's own custom character (gear included)
--  into PlayerPreview's backdrop area, via a ViewportFrame + WorldModel holding a cleaned
--  clone of Players.LocalPlayer.Character, looping the Unarmed idle clip and framed from
--  a three-quarter angle (PREVIEW_YAW_DEG) rather than dead-on.
--
--  Deliberately implementation-agnostic to HOW gear is visually attached to the
--  character. It never reads ArmorVisualsService internals, part names, or assumes
--  Motor6D welds -- it just clones whatever the live Character looks like, wholesale.
--  That means this component needs no changes if/when gear moves from today's rigid
--  welds to real Accessories/Layered Clothing: both are just more descendants of the
--  same Character Model at clone time.
--
--  Why the idle clip: a :Clone() never carries the live Bone.Transform pose (it isn't
--  serialized), so an un-animated clone of the skinned Hero_Character rig shows its bind
--  pose -- the stiff A-pose. Animators inside a WorldModel do play, so the clone gets
--  the same Unarmed Idle track Animate2 uses (CharacterAnimProfiles). Unarmed, not the
--  weapon profile, because cleanClone strips any held Tool.
--
--  The clone/camera/track are (re)built once per mount and once per distinct `equipped`
--  signature (see equipSignature below), never on a RenderStepped/Heartbeat loop. The
--  only per-frame cost is the engine advancing one looped track on one skinned mesh.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local e = React.createElement

local CharacterAnimProfiles = require(ReplicatedStorage:WaitForChild("CharacterAnimProfiles"))
-- Face + hair: drawn by FacePlates outside the character model, so a clone has none of them
-- until it's attached (inside this viewport's WorldModel).
local FacePlates = require(script.Parent.Parent.Parent:WaitForChild("FacePlates"))

local FOV = 30
local FRAME_PADDING = 1.15 -- 15% headroom above/below the bounding box
-- How far the camera orbits off dead-front, around the character's vertical axis.
-- 0 = straight-on; flip the sign to angle from the other side.
local PREVIEW_YAW_DEG = 25
-- Hide the viewport until the idle track has actually started, so opening the menu
-- never flashes the bind pose for a frame. Reveal anyway after this long, so a failed
-- clip load degrades to the old static A-pose instead of an empty panel.
local IDLE_REVEAL_TIMEOUT = 2

export type CharacterViewportProps = {
	-- Only used to build a rebuild-trigger signature -- never interpreted, so this
	-- component doesn't need to know or care how gear ends up on the character.
	equipped: { [string]: string }?,
	size: UDim2,
	position: UDim2,
	zIndex: number?,
	-- Drag (left mouse) across the portrait to turn the character (the Journal's Stats page).
	rotatable: boolean?,
}

local DRAG_DEG_PER_PX = 0.6

-- Sorted "slot=uuid,slot=uuid" string. A plain-string useEffect dependency, same pattern
-- as SlidingBody's { props.activeKey } in init.lua -- fires on mount and again only when
-- the set of equipped items actually changes, never on unrelated re-renders.
local function equipSignature(equipped: { [string]: string }?): string
	if not equipped then
		return ""
	end
	local parts = {}
	for slot, uuid in pairs(equipped) do
		table.insert(parts, slot .. "=" .. uuid)
	end
	table.sort(parts)
	return table.concat(parts, ",")
end

-- Strips everything that would make a straight :Clone() of the live character look
-- wrong or misbehave inside a static ViewportFrame preview:
--  * Scripts/LocalScripts -- never need to run in the preview.
--  * LocalTransparencyModifier stuck at 1 -- FirstPersonViewModel.client.lua permanently
--    hides Accessory-parented parts this way (ACCESSORY_TRANSPARENCY) and toggles the
--    Head Decal (face texture) the same way on the R perspective toggle. Reset BOTH
--    unconditionally regardless of the player's current perspective. This also covers
--    any FUTURE Accessory-based gear, which would hit that exact same line.
--  * Physics -- Anchored so the pose can never sag/jitter; WorldModel (unlike the old
--    flat-parent-into-ViewportFrame trick) actually simulates unanchored parts.
--  * Billboard/SurfaceGui overlays (nameplate/health-bar style UI).
--  * Humanoid health/name display.
--  * Any held Tool -- the preview is scoped to the 9 armor/gear slots this panel shows,
--    not whatever's in the separate combat hotbar.
local function cleanClone(clone: Model)
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.LocalTransparencyModifier = 0
			d.Anchored = true
		elseif d:IsA("Decal") then
			d.LocalTransparencyModifier = 0
		elseif d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
			d:Destroy()
		end
	end

	for _, child in ipairs(clone:GetChildren()) do
		if child:IsA("Tool") then
			child:Destroy()
		end
	end

	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
end

-- Where buildCamera put the camera, so a drag can orbit it: centre, distance, and the
-- front-facing direction the yaw is measured from.
type Orbit = { center: Vector3, distance: number, front: Vector3 }

local function placeCamera(camera: Camera, orbit: Orbit, yawDeg: number)
	local look = CFrame.Angles(0, math.rad(yawDeg), 0):VectorToWorldSpace(orbit.front)
	camera.CFrame = CFrame.lookAt(orbit.center + look * orbit.distance, orbit.center)
end

local function buildCamera(viewport: ViewportFrame, clone: Model): (Camera, Orbit)
	local cframe, size = clone:GetBoundingBox()
	local distance = (size.Y / 2) / math.tan(math.rad(FOV / 2)) * FRAME_PADDING

	-- GetBoundingBox's own CFrame is axis-aligned (no rotation), so it can't tell us
	-- which way the character is actually facing. Read that off the root part instead,
	-- so the preview always frames the front regardless of which way the character
	-- happened to be facing in the world when it was cloned.
	local rootPart = clone:FindFirstChild("HumanoidRootPart") :: BasePart?
	local lookVector = rootPart and rootPart.CFrame.LookVector or Vector3.new(0, 0, -1)
	-- Flatten to the horizontal plane first, so a lean/tilt on the live root at clone
	-- time can't tip the camera above or below the character.
	local flat = Vector3.new(lookVector.X, 0, lookVector.Z)
	lookVector = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	local orbit: Orbit = { center = cframe.Position, distance = distance, front = lookVector }

	local camera = Instance.new("Camera")
	camera.FieldOfView = FOV
	-- The camera must sit in FRONT of the character (same side their face points
	-- toward, i.e. + lookVector) and look back at them, or it frames their back.
	placeCamera(camera, orbit, PREVIEW_YAW_DEG)
	camera.Parent = viewport

	viewport.Ambient = Color3.fromRGB(140, 140, 140)
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.LightDirection = Vector3.new(-0.5, -1, -0.3)
	viewport.CurrentCamera = camera

	return camera, orbit
end

-- Loops the Unarmed idle on the clone's own Animator (cloned along with its Humanoid).
-- Returns the track, or nil if the rig has no Animator or the clip id is missing.
local function playIdle(clone: Model): AnimationTrack?
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local idleId = CharacterAnimProfiles.Profiles.Unarmed.Idle
	if not animator or not idleId or idleId == "" then
		return nil
	end

	local anim = Instance.new("Animation")
	anim.AnimationId = idleId
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if not ok or not track then
		warn("[CharacterViewport] failed to load idle animation", idleId, track)
		return nil
	end

	track.Priority = Enum.AnimationPriority.Core
	track.Looped = true
	track:Play(0)
	return track
end

local function CharacterViewport(props: CharacterViewportProps)
	local viewportRef = React.useRef(nil :: ViewportFrame?)
	local worldModelRef = React.useRef(nil :: WorldModel?)
	local cloneRef = React.useRef(nil :: Model?)
	local cameraRef = React.useRef(nil :: Camera?)
	local orbitRef = React.useRef(nil :: Orbit?)
	local yawRef = React.useRef(PREVIEW_YAW_DEG)

	local signature = equipSignature(props.equipped)

	React.useEffect(function()
		local viewport = viewportRef.current
		local worldModel = worldModelRef.current
		if not viewport or not worldModel then
			return
		end

		local characterAddedConn: RBXScriptConnection? = nil
		local detachFace: (() -> ())? = nil

		local function teardown()
			if characterAddedConn then
				characterAddedConn:Disconnect()
				characterAddedConn = nil
			end
			if detachFace then
				detachFace()
				detachFace = nil
			end
			if cloneRef.current then
				cloneRef.current:Destroy()
				cloneRef.current = nil
			end
			if cameraRef.current then
				cameraRef.current:Destroy()
				cameraRef.current = nil
			end
		end

		local function build()
			teardown()

			local character = Players.LocalPlayer.Character
			local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")

			if not character or not humanoidRootPart or not humanoid then
				-- Not loaded yet (fresh join / mid-respawn) -- retry once it exists,
				-- leave the viewport showing whatever it last showed (or empty).
				characterAddedConn = Players.LocalPlayer.CharacterAdded:Once(function()
					build()
				end)
				return
			end

			-- The live character (and a few of its descendant Sounds) have Archivable
			-- set to false, which makes :Clone() silently return nil -- flip it on just
			-- long enough to clone, then restore it so nothing else about the live
			-- character changes. Non-archivable descendants are simply omitted from the
			-- clone by the engine, not an error, so only the root needs this.
			local wasArchivable = character.Archivable
			character.Archivable = true
			local clone = character:Clone()
			character.Archivable = wasArchivable

			if not clone then
				return
			end

			cleanClone(clone)
			clone.Parent = worldModel
			cloneRef.current = clone
			-- The wardrobe choices: skin rides along (body colour), face + hair need attaching.
			-- The Appearance_* attributes came across with the clone.
			detachFace = FacePlates.Attach(clone, worldModel)

			local camera, orbit = buildCamera(viewport, clone)
			cameraRef.current, orbitRef.current = camera, orbit
			placeCamera(camera, orbit, yawRef.current) -- keep the angle the player turned it to

			-- Parent before loading: the Animator needs to be in the WorldModel to drive
			-- the bones. Stays hidden until the clip reports a Length (i.e. has loaded
			-- and is actually posing the rig), see IDLE_REVEAL_TIMEOUT.
			viewport.ImageTransparency = 1
			local track = playIdle(clone)
			local thisBuild = clone
			task.spawn(function()
				local deadline = os.clock() + IDLE_REVEAL_TIMEOUT
				while track and track.Length <= 0 and os.clock() < deadline do
					task.wait()
				end
				-- A newer build (or unmount) owns the viewport now -- leave it alone.
				if cloneRef.current == thisBuild then
					viewport.ImageTransparency = 0
				end
			end)
		end

		build()

		return teardown
	end, { signature :: any })

	-- Drag to turn: press on the portrait, then follow the mouse anywhere until release.
	React.useEffect(function()
		local viewport = viewportRef.current
		if not props.rotatable or not viewport then
			return
		end
		local dragging = false
		local lastX = 0
		local began = viewport.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging, lastX = true, input.Position.X
			end
		end)
		local moved = UserInputService.InputChanged:Connect(function(input)
			if not dragging then return end
			if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
			local dx = input.Position.X - lastX
			lastX = input.Position.X
			yawRef.current -= dx * DRAG_DEG_PER_PX
			if cameraRef.current and orbitRef.current then
				placeCamera(cameraRef.current, orbitRef.current, yawRef.current)
			end
		end)
		local ended = UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = false
			end
		end)
		return function()
			began:Disconnect(); moved:Disconnect(); ended:Disconnect()
		end
	end, { props.rotatable == true })

	return e("ViewportFrame", {
		ref = viewportRef,
		Size = props.size,
		Position = props.position,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = props.zIndex or 1,
		Active = props.rotatable == true, -- receive the press that starts a drag
	}, {
		World = e("WorldModel", { ref = worldModelRef }),
	})
end

return CharacterViewport
