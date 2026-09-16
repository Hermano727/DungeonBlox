--!strict
--  CharacterViewport -- renders a static 3D snapshot of the local player's own custom
--  character (gear included) into PlayerPreview's backdrop area, via a ViewportFrame +
--  WorldModel holding a cleaned clone of Players.LocalPlayer.Character.
--
--  Deliberately implementation-agnostic to HOW gear is visually attached to the
--  character. It never reads ArmorVisualsService internals, part names, or assumes
--  Motor6D welds -- it just clones whatever the live Character looks like, wholesale.
--  That means this component needs no changes if/when gear moves from today's rigid
--  welds to real Accessories/Layered Clothing: both are just more descendants of the
--  same Character Model at clone time.
--
--  Not a live view: the clone/camera are (re)built once per mount and once per distinct
--  `equipped` signature (see equipSignature below), never on a RenderStepped/Heartbeat
--  loop -- ViewportFrame content only updates when its children change, so a camera set
--  once and left alone is already static/cheap by construction.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local e = React.createElement

local FOV = 30
local FRAME_PADDING = 1.15 -- 15% headroom above/below the bounding box

export type CharacterViewportProps = {
	-- Only used to build a rebuild-trigger signature -- never interpreted, so this
	-- component doesn't need to know or care how gear ends up on the character.
	equipped: { [string]: string }?,
	size: UDim2,
	position: UDim2,
	zIndex: number?,
}

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

local function buildCamera(viewport: ViewportFrame, clone: Model): Camera
	local cframe, size = clone:GetBoundingBox()
	local distance = (size.Y / 2) / math.tan(math.rad(FOV / 2)) * FRAME_PADDING

	-- GetBoundingBox's own CFrame is axis-aligned (no rotation), so it can't tell us
	-- which way the character is actually facing. Read that off the root part instead,
	-- so the preview always frames the front regardless of which way the character
	-- happened to be facing in the world when it was cloned.
	local rootPart = clone:FindFirstChild("HumanoidRootPart") :: BasePart?
	local lookVector = rootPart and rootPart.CFrame.LookVector or Vector3.new(0, 0, -1)

	local camera = Instance.new("Camera")
	camera.FieldOfView = FOV
	-- The camera must sit in FRONT of the character (same side their face points
	-- toward, i.e. + lookVector) and look back at them, or it frames their back.
	camera.CFrame = CFrame.lookAt(cframe.Position + lookVector * distance, cframe.Position)
	camera.Parent = viewport

	viewport.Ambient = Color3.fromRGB(140, 140, 140)
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.LightDirection = Vector3.new(-0.5, -1, -0.3)
	viewport.CurrentCamera = camera

	return camera
end

local function CharacterViewport(props: CharacterViewportProps)
	local viewportRef = React.useRef(nil :: ViewportFrame?)
	local worldModelRef = React.useRef(nil :: WorldModel?)
	local cloneRef = React.useRef(nil :: Model?)
	local cameraRef = React.useRef(nil :: Camera?)

	local signature = equipSignature(props.equipped)

	React.useEffect(function()
		local viewport = viewportRef.current
		local worldModel = worldModelRef.current
		if not viewport or not worldModel then
			return
		end

		local characterAddedConn: RBXScriptConnection? = nil

		local function teardown()
			if characterAddedConn then
				characterAddedConn:Disconnect()
				characterAddedConn = nil
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

			cameraRef.current = buildCamera(viewport, clone)
		end

		build()

		return teardown
	end, { signature :: any })

	return e("ViewportFrame", {
		ref = viewportRef,
		Size = props.size,
		Position = props.position,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = props.zIndex or 1,
	}, {
		World = e("WorldModel", { ref = worldModelRef }),
	})
end

return CharacterViewport
