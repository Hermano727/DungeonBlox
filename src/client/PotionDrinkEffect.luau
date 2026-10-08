-- Server-confirmed cosmetic burst. The real tool/welds are never moved or destroyed.
-- All tuning is in RS/PotionDrinkConfig; per-potion colour is in RS/PotionConfig.
--
-- Uncorking releases a stream of light orbs in the potion's colour. Each rises out of the
-- vial, spirals around the body (alternate orbs turn opposite ways) and sinks into the chest,
-- where a glow builds with every orb absorbed and then fades. Paths are computed in the
-- drinker's root space, so the burst follows a moving character.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("PotionDrinkConfig"))
local Potions = require(RS:WaitForChild("PotionConfig"))
local HudArt = require(RS:WaitForChild("Assets"):WaitForChild("Images"):WaitForChild("HudArt"))
local SfxService = require(RS:WaitForChild("SfxService"))
local Presentation = require(script.Parent:WaitForChild("PotionPresentation"))

local Effect = {}
local rng = Random.new()
local bursts = {}
local hiddenCorks = {}
local renderConnection

local function findPart(parent, name)
	local part = parent and parent:FindFirstChild(name)
	return part and part:IsA("BasePart") and part or nil
end

local function visualPart(name)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	return part
end

local function sprite(parent, color, z)
	local image = Instance.new("ImageLabel")
	image.AnchorPoint = Vector2.new(0.5, 0.5)
	image.Position = UDim2.fromScale(0.5, 0.5)
	image.BackgroundTransparency = 1
	image.Image = HudArt.GLOW_SOFT
	image.ImageColor3 = color
	image.ZIndex = z
	image.Parent = parent
	return image
end

local function makeOrb(folder, color, index)
	local anchor = visualPart("PotionOrb")
	anchor.Parent = folder
	local gui = Instance.new("BillboardGui")
	gui.Name = "Light"
	gui.Adornee = anchor
	gui.Size = UDim2.fromScale(Config.BILLBOARD_SIZE, Config.BILLBOARD_SIZE)
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.MaxDistance = Config.AUDIENCE_RADIUS
	gui.Enabled = false
	gui.Parent = anchor
	local halo = sprite(gui, color, 1)
	local core = sprite(gui, Config.CORE_COLOR, 2)
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = core
	local outline = Instance.new("UIStroke")
	outline.Color = Config.OUTLINE_COLOR
	outline.Transparency = Config.OUTLINE_TRANSPARENCY
	outline.Thickness = Config.OUTLINE_THICKNESS
	outline.Parent = core
	return {
		anchor = anchor, gui = gui, core = core, halo = halo, outline = outline,
		size = rng:NextNumber(Config.ORB_SIZE_MIN, Config.ORB_SIZE_MAX),
		delay = Config.ORB_RELEASE_DELAY + (index - 1) * Config.ORB_STAGGER,
		travel = rng:NextNumber(Config.ORB_TRAVEL_MIN, Config.ORB_TRAVEL_MAX),
		lift = rng:NextNumber(Config.ORB_LIFT_MIN, Config.ORB_LIFT_MAX),
		turn = (index % 2 == 0 and 1 or -1) * rng:NextNumber(Config.ORB_TURN_MIN, Config.ORB_TURN_MAX),
		bulge = rng:NextNumber(Config.ORB_BULGE_MIN, Config.ORB_BULGE_MAX),
	}
end

local function hideCork(cork, tool, character)
	if not cork then return function() end end
	local state = hiddenCorks[cork]
	if not state then
		state = { count = 0, original = cork.LocalTransparencyModifier }
		hiddenCorks[cork] = state
	end
	state.count += 1
	cork.LocalTransparencyModifier = 1
	local released = false
	local connection
	local function release()
		if released then return end
		released = true
		if connection then connection:Disconnect() end
		state.count -= 1
		if state.count == 0 then
			if cork.Parent then cork.LocalTransparencyModifier = state.original end
			hiddenCorks[cork] = nil
		end
	end
	-- Restore on leaving the hand, even if it is re-equipped before the burst ends.
	if tool then
		connection = tool.AncestryChanged:Connect(function()
			if tool.Parent ~= character then release() end
		end)
	end
	return release
end

local function sound(key, position, volume)
	SfxService.PlayEffect(key, {
		Position = position, Volume = volume,
		RollOffMinDistance = Config.SOUND_MIN_DISTANCE,
		RollOffMaxDistance = Config.SOUND_MAX_DISTANCE,
	})
end

local function firstPerson(burst)
	return burst.isLocal and Players.LocalPlayer:GetAttribute("FirstPersonView") == true
end

local function targetPosition(burst, camera)
	if camera and firstPerson(burst) then
		return camera.CFrame:PointToWorldSpace(Config.FIRST_PERSON_CHEST)
	end
	if burst.chestBone and burst.chestBone.Parent then
		return burst.chestBone.TransformedWorldCFrame.Position + burst.root.CFrame.LookVector * 0.35
	end
	return burst.torso.CFrame:PointToWorldSpace(Config.CHEST_OFFSET)
end

local function cameraOpacity(burst, camera, position)
	if not camera or not firstPerson(burst) then return 1 end
	local depth = -camera.CFrame:PointToObjectSpace(position).Z
	return math.clamp((depth - Config.CAMERA_FADE_DEPTH) / Config.CAMERA_FADE_RANGE, 0, 1)
end

local function drawOrb(orb, position, size, stretch, rotation, opacity)
	orb.anchor.Position = position
	orb.gui.Enabled = opacity > 0
	local scale = size / Config.BILLBOARD_SIZE
	orb.core.Size = UDim2.fromScale(scale * stretch, scale)
	orb.halo.Size = UDim2.fromScale(scale * Config.HALO_SCALE * (1 + (stretch - 1) * 0.5), scale * Config.HALO_SCALE)
	orb.core.Rotation = rotation
	orb.halo.Rotation = rotation
	orb.core.ImageTransparency = 1 - opacity
	orb.halo.ImageTransparency = 1 - opacity * (1 - Config.HALO_TRANSPARENCY)
	orb.outline.Transparency = 1 - opacity * (1 - Config.OUTLINE_TRANSPARENCY)
end

-- Where an orb is at progress u (0..1): a spiral around the vertical line through the chest
-- target, starting exactly at the vial mouth. All in root space.
local function spiralPoint(orb, targetLocal, u)
	local e = u ^ Config.ORB_EASE
	local radius = orb.radius0 * (1 - e) + orb.bulge * math.sin(math.pi * u)
	local angle = orb.angle0 + orb.turn * e
	local height = orb.height0 * (1 - e) + orb.lift * math.sin(math.pi * u)
	return targetLocal + Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
end

local function destroyBurst(burst)
	burst.releaseCork()
	burst.folder:Destroy()
end

local lastStep = os.clock()
local function step()
	local now = os.clock()
	local dt = math.min(now - lastStep, 0.1)
	lastStep = now
	local camera = workspace.CurrentCamera
	for index = #bursts, 1, -1 do
		local burst = bursts[index]
		local age = (now - burst.born) / burst.timeScale
		if not burst.character.Parent or not burst.root.Parent or not burst.torso.Parent
			or burst.humanoid.Health <= 0 or age >= burst.duration then
			destroyBurst(burst)
			table.remove(bursts, index)
			continue
		end
		local rootFrame = burst.root.CFrame
		local target = targetPosition(burst, camera)
		if burst.cork then
			if age >= Config.CORK_TIME then
				burst.cork:Destroy()
				burst.cork = nil
			else
				local launch = rootFrame * burst.corkOffset
				local displacement = burst.corkVelocity * age - Vector3.yAxis * (Config.CORK_GRAVITY * age * age * 0.5)
				local position = launch.Position + rootFrame:VectorToWorldSpace(displacement)
				local spin = Config.CORK_SPIN * age
				burst.cork.CFrame = CFrame.new(position) * launch.Rotation * CFrame.Angles(spin.X, spin.Y, spin.Z)
				local fade = math.clamp((age - Config.CORK_FADE_START) / (Config.CORK_TIME - Config.CORK_FADE_START), 0, 1)
				burst.cork.Transparency = 1 - (1 - burst.corkTransparency) * (1 - fade) * cameraOpacity(burst, camera, position)
			end
		end
		for _, orb in ipairs(burst.orbs) do
			local elapsed = age - orb.delay
			if elapsed < 0 or orb.done then continue end
			if elapsed >= orb.travel then
				local pulse = (elapsed - orb.travel) / Config.PULSE_TIME
				if pulse >= 1 then
					orb.done = true
					orb.anchor:Destroy()
				else
					if not burst.absorbPlayed then
						burst.absorbPlayed = true -- one quiet sound per drink, not one per orb
						sound("PotionOrbAbsorb", target, Config.ABSORB_VOLUME)
					end
					if not orb.absorbed then
						orb.absorbed = true
						burst.glowLevel = math.min(1, burst.glowLevel + Config.ABSORB_GLOW_GAIN)
					end
					drawOrb(orb, target, orb.size * (1 + pulse * Config.PULSE_SCALE), 1, 0,
						(1 - pulse) * cameraOpacity(burst, camera, target))
				end
				continue
			end
			if not orb.start then
				local mouth = rootFrame * burst.mouthOffset
				local presentation = Presentation.Get(burst.character, burst.itemUuid)
				local handle = presentation and presentation.visible and presentation.model:FindFirstChild("Handle")
					or (burst.tool and burst.tool.Parent == burst.character and burst.tool:FindFirstChild("Handle"))
				if handle then
					mouth = handle.CFrame * CFrame.new(0, handle.Size.Y * 0.5, 0)
				end
				-- Spiral coordinates of the mouth around the chest target, so u = 0 is exactly the mouth.
				local offset = rootFrame:PointToObjectSpace(mouth.Position) - rootFrame:PointToObjectSpace(target)
				orb.radius0 = Vector2.new(offset.X, offset.Z).Magnitude
				orb.angle0 = math.atan2(offset.Z, offset.X)
				orb.height0 = offset.Y
				orb.start = true
			end
			local targetLocal = rootFrame:PointToObjectSpace(target)
			local u = elapsed / orb.travel
			local k = u ^ Config.ORB_EASE
			local position = rootFrame:PointToWorldSpace(spiralPoint(orb, targetLocal, u))
			local tangent = rootFrame:PointToWorldSpace(spiralPoint(orb, targetLocal, math.min(1, u + 0.02))) - position
			local rotation = 0
			if camera then
				local a = camera:WorldToViewportPoint(position)
				local b = camera:WorldToViewportPoint(position + tangent)
				rotation = math.deg(math.atan2(b.Y - a.Y, b.X - a.X))
			end
			local pop = math.clamp(elapsed / Config.ORB_POP_TIME, 0, 1)
			drawOrb(orb, position, orb.size * pop * (1 - Config.ORB_SHRINK * k),
				1 + Config.ORB_STRETCH * k, rotation, cameraOpacity(burst, camera, position))
		end
		-- The chest fills with light as the orbs land, then fades.
		burst.glowLevel *= math.exp(-Config.ABSORB_GLOW_DECAY * dt)
		local glow = burst.glow
		glow.anchor.Position = target
		local level = burst.glowLevel * cameraOpacity(burst, camera, target)
		glow.gui.Enabled = level > 0.01
		-- In first person the "chest" sits just under the camera: a smaller glow, or it floods the view.
		local grow = (0.6 + 0.4 * burst.glowLevel) * (firstPerson(burst) and 0.5 or 1)
		glow.sprite.Size = UDim2.fromScale(grow, grow)
		glow.sprite.ImageTransparency = 1 - level * 0.75
	end
	if #bursts == 0 and renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
end

function Effect.Play(payload, options)
	options = options or {}
	local cfg = Potions.Tiers[payload.itemId]
	local character = payload.character
	if not cfg or not character or not character.Parent then return end
	if workspace:GetServerTimeNow() - payload.sentAt > Config.MAX_EVENT_AGE then return end
	local root = findPart(character, "HumanoidRootPart")
	local torso = findPart(character, "UpperTorso") or findPart(character, "Torso") or root
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not torso or not humanoid or humanoid.Health <= 0 then return end
	local isLocal = character == Players.LocalPlayer.Character
	local camera = workspace.CurrentCamera
	if not isLocal and camera and (camera.CFrame.Position - root.Position).Magnitude > Config.AUDIENCE_RADIUS then return end
	if #bursts >= Config.MAX_BURSTS then
		-- Preserve the drinker's feedback when a crowded fight hits the cosmetic budget.
		local discard
		for i, burst in ipairs(bursts) do
			if not burst.isLocal then discard = i; break end
		end
		if not discard then return end
		destroyBurst(table.remove(bursts, discard))
	end
	local tool
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute("DungeonItemUuid") == payload.itemUuid then
			tool = child
			break
		end
	end
	local handle = findPart(tool, "Handle")
	local cork = findPart(tool, "Cork")
	local presentation = Presentation.Get(character, payload.itemUuid)
	if presentation and presentation.visible then
		handle = findPart(presentation.model, "Handle")
		cork = findPart(presentation.model, "Cork")
	end
	local templates = RS:FindFirstChild("PotionDrinkVisuals")
	local templateModel = templates and templates:FindFirstChild(cfg.visualModel)
	local template = cork or findPart(templateModel, "Cork")
	local folder = Instance.new("Folder")
	folder.Name = "PotionDrinkBurst"
	folder.Parent = workspace
	local burst = {
		character = character, root = root, torso = torso, humanoid = humanoid,
		tool = tool, handle = handle, isLocal = isLocal, folder = folder,
		born = os.clock() - (options.elapsed or 0), timeScale = options.timeScale or 1,
		orbs = {}, mouthOffset = payload.mouthOffset, itemUuid = payload.itemUuid, drinkId = payload.drinkId,
		chestBone = character:FindFirstChild("Hero_Character") and character.Hero_Character:FindFirstChild("Spine_02", true),
		glowLevel = 0,
		duration = math.max(Config.CORK_TIME, Config.ORB_RELEASE_DELAY
			+ ((isLocal and Config.ORB_COUNT or Config.ORB_COUNT_REMOTE) - 1) * Config.ORB_STAGGER
			+ Config.ORB_TRAVEL_MAX + Config.PULSE_TIME + 0.5),
		releaseCork = hideCork(cork, tool, character),
	}
	if template and payload.corkOffset then
		local copy = template:Clone()
		for _, child in ipairs(copy:GetDescendants()) do
			if child:IsA("JointInstance") or child:IsA("WeldConstraint") or child:IsA("LuaSourceContainer") then child:Destroy() end
		end
		copy.Anchored = true
		copy.CanCollide = false
		copy.CanTouch = false
		copy.CanQuery = false
		copy.CastShadow = false
		copy.LocalTransparencyModifier = 0
		copy.Size = payload.corkSize
		burst.corkOffset = cork and root.CFrame:ToObjectSpace(cork.CFrame) or payload.corkOffset
		copy.CFrame = root.CFrame * burst.corkOffset
		copy.Parent = folder
		burst.cork = copy
		burst.corkTransparency = copy.Transparency
		local mouthFrame = handle and root.CFrame:ToObjectSpace(handle.CFrame) or payload.mouthOffset
		burst.corkVelocity = mouthFrame.UpVector * Config.CORK_UP_SPEED
			+ mouthFrame.RightVector * Config.CORK_SIDE_SPEED
	end
	for i = 1, isLocal and Config.ORB_COUNT or Config.ORB_COUNT_REMOTE do
		table.insert(burst.orbs, makeOrb(folder, cfg.drinkColor, i))
	end
	do
		local anchor = visualPart("PotionAbsorbGlow")
		anchor.Parent = folder
		local gui = Instance.new("BillboardGui")
		gui.Adornee = anchor
		gui.Size = UDim2.fromScale(Config.ABSORB_GLOW_SIZE, Config.ABSORB_GLOW_SIZE)
		gui.LightInfluence = 0
		gui.MaxDistance = Config.AUDIENCE_RADIUS
		gui.Enabled = false
		gui.Parent = anchor
		burst.glow = { anchor = anchor, gui = gui, sprite = sprite(gui, cfg.drinkColor, 1) }
	end
	table.insert(bursts, burst)
	local mouth = handle and handle.CFrame * CFrame.new(0, handle.Size.Y * 0.5, 0) or root.CFrame * payload.mouthOffset
	sound("PotionCorkPop", mouth.Position, Config.POP_VOLUME)
	if not renderConnection then renderConnection = RunService.RenderStepped:Connect(step) end
end

function Effect.Cancel(drinkId)
	for i = #bursts, 1, -1 do
		if bursts[i].drinkId == drinkId then destroyBurst(table.remove(bursts, i)) end
	end
end

function Effect.Clear()
	for _, burst in ipairs(bursts) do destroyBurst(burst) end
	table.clear(bursts)
	if renderConnection then renderConnection:Disconnect(); renderConnection = nil end
end

return Effect
