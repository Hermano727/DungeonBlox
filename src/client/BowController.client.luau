--[[
	BowController
	The local player's bow (BowConfig has every number), plus everyone's arrows in flight.

	Hold the left mouse button with a bow out to draw, release to shoot. The draw clip plays at
	1 / CHARGE_TIME so the string reaches the chin exactly at full charge, then the aim clip
	holds it there. The camera narrows slightly as the draw fills (Minecraft's bow zoom).
	Releasing below MIN_CHARGE lowers the bow without shooting.

	The server times the draw itself (BowService); this side only asks. The clips play on the
	local Animator, which replicates them, and WeaponAttachClient reads them back on every
	client to pull the string and show the nocked arrow, so other players see the same draw.

	Arrows: on release this client flies its own copy at once from the nocked arrow toward the
	crosshair. Other clients get GameEvents/BowShot and fly theirs from the server's origin.
	Same ballistics as the server; an arrow that hits the world sticks for a moment.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ActiveEquipment = require(ReplicatedStorage:WaitForChild("ActiveEquipment"))
local PotionAction = require(ReplicatedStorage:WaitForChild("PotionAction"))
local AimRay = require(ReplicatedStorage:WaitForChild("AimRay"))
local BowConfig = require(ReplicatedStorage:WaitForChild("BowConfig"))
local InteractionLock = require(ReplicatedStorage:WaitForChild("InteractionLock"))
local WeaponData = require(ReplicatedStorage:WaitForChild("WeaponData"))
local BowAnimations = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Animations"):WaitForChild("BowAnimations"))

local player = Players.LocalPlayer
local gameEvents = ReplicatedStorage:WaitForChild("GameEvents")
local BowDraw = gameEvents:WaitForChild("BowDraw")
local BowRelease = gameEvents:WaitForChild("BowRelease")
local BowShot = gameEvents:WaitForChild("BowShot")

local STICK_TIME = 4 -- seconds an arrow stays in the wall it hit
local FADE_TIME = 0.4
local FLIGHT_LENGTH = BowConfig.ARROW_LENGTH * BowConfig.FLIGHT_ARROW_SCALE

local arrowFolder = Instance.new("Folder")
arrowFolder.Name = "BowArrows"
arrowFolder.Parent = workspace

---------------------------------------------------------------------------
-- Arrows in flight (everyone's)
---------------------------------------------------------------------------

local flights = {}
local flightConnection

local function arrowTemplate()
	local folder = ReplicatedStorage:FindFirstChild(BowConfig.VISUALS_FOLDER)
	return folder and folder:FindFirstChild(BowConfig.ARROW_TEMPLATE)
end

-- The flying arrow: FLIGHT_ARROW_SCALE times the nocked one, with a pale gold glow
-- (Highlight) and a short streak (Trail) behind it.
local function dressArrow(arrow)
	local scale = BowConfig.FLIGHT_ARROW_SCALE
	arrow.Size *= scale -- a MeshPart's mesh follows its Size
	local mesh = arrow:FindFirstChildOfClass("SpecialMesh")
	if mesh then mesh.Scale *= scale end

	local glow = Instance.new("Highlight")
	glow.FillColor = BowConfig.ARROW_GLOW_COLOR
	glow.FillTransparency = BowConfig.ARROW_GLOW_FILL_TRANSPARENCY
	glow.OutlineColor = BowConfig.ARROW_GLOW_OUTLINE
	glow.OutlineTransparency = 0
	glow.DepthMode = Enum.HighlightDepthMode.Occluded
	glow.Parent = arrow

	-- Both ends at the tail (the arrow flies along -Z), apart across it for the streak's width.
	local halfWidth = BowConfig.ARROW_TRAIL_WIDTH / 2
	local top = Instance.new("Attachment")
	top.Position = Vector3.new(0, halfWidth, FLIGHT_LENGTH / 2)
	top.Parent = arrow
	local bottom = Instance.new("Attachment")
	bottom.Position = Vector3.new(0, -halfWidth, FLIGHT_LENGTH / 2)
	bottom.Parent = arrow
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = top, bottom
	trail.FaceCamera = true
	trail.Lifetime = BowConfig.ARROW_TRAIL_LIFETIME
	trail.Color = ColorSequence.new(BowConfig.ARROW_GLOW_OUTLINE, BowConfig.ARROW_GLOW_COLOR)
	trail.Transparency = NumberSequence.new(0.25, 1)
	trail.WidthScale = NumberSequence.new(1, 0)
	trail.LightEmission = 1
	trail.Parent = arrow
end

local function stickThenFade(arrow)
	task.delay(STICK_TIME, function()
		if not arrow.Parent then return end
		local info = TweenInfo.new(FADE_TIME)
		local glow = arrow:FindFirstChildOfClass("Highlight")
		if glow then
			TweenService:Create(glow, info, { FillTransparency = 1, OutlineTransparency = 1 }):Play()
		end
		local fade = TweenService:Create(arrow, info, { Transparency = 1 })
		fade.Completed:Connect(function() arrow:Destroy() end)
		fade:Play()
	end)
end

local function stepFlights(dt)
	local gravity = Vector3.new(0, -BowConfig.GRAVITY, 0)
	for i = #flights, 1, -1 do
		local f = flights[i]
		local step = f.velocity * dt + gravity * (0.5 * dt * dt)
		local remaining = f.maxDistance - f.traveled
		local done = false
		if step.Magnitude > remaining then
			step = step.Unit * remaining
			done = true
		end
		local result = BowConfig.CastArrow(f.position, step, f.params)
		if result then
			f.position = result.Position
			local model = result.Instance:FindFirstAncestorOfClass("Model")
			local hitCharacter = model and model:FindFirstChildOfClass("Humanoid")
			if result.Instance.Anchored and not hitCharacter then
				-- Sink the head a little into what it hit, then leave it there.
				f.arrow.CFrame = CFrame.lookAt(f.position - f.velocity.Unit * (FLIGHT_LENGTH / 2 - 0.5), f.position)
				stickThenFade(f.arrow)
			else
				f.arrow:Destroy()
			end
			table.remove(flights, i)
			continue
		end
		f.position += step
		f.velocity += gravity * dt
		f.traveled += step.Magnitude
		if f.velocity.Magnitude > 0.1 then
			f.arrow.CFrame = CFrame.lookAt(f.position - f.velocity.Unit * (FLIGHT_LENGTH / 2), f.position)
		end
		if done then
			f.arrow:Destroy()
			table.remove(flights, i)
		end
	end
	if #flights == 0 and flightConnection then
		flightConnection:Disconnect()
		flightConnection = nil
	end
end

-- origin: where the arrow's tip starts. ignore: the shooter's character.
local function launch(origin, velocity, maxDistance, ignore)
	local template = arrowTemplate()
	if not template or velocity.Magnitude < 0.1 then return end
	local arrow = template:Clone()
	dressArrow(arrow)
	arrow.CFrame = CFrame.lookAt(origin - velocity.Unit * (FLIGHT_LENGTH / 2), origin)
	arrow.Parent = arrowFolder
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignoreList = { arrowFolder }
	if ignore then table.insert(ignoreList, ignore) end
	local weaponVisuals = workspace:FindFirstChild("HarukaWeaponVisuals")
	if weaponVisuals then table.insert(ignoreList, weaponVisuals) end
	params.FilterDescendantsInstances = ignoreList
	table.insert(flights, { arrow = arrow, position = origin, velocity = velocity, traveled = 0,
		maxDistance = maxDistance, params = params })
	if not flightConnection then flightConnection = RunService.RenderStepped:Connect(stepFlights) end
end

BowShot.OnClientEvent:Connect(function(shot)
	if type(shot) ~= "table" or shot.shooter == player then return end
	-- Catch up on the time the packet spent in transit.
	local age = math.clamp(workspace:GetServerTimeNow() - (shot.sentAt or 0), 0, 0.3)
	local gravity = Vector3.new(0, -BowConfig.GRAVITY, 0)
	local origin = shot.origin + shot.velocity * age + gravity * (0.5 * age * age)
	local character = shot.shooter and shot.shooter.Character
	launch(origin, shot.velocity + gravity * age, shot.maxDistance - shot.velocity.Magnitude * age, character)
end)

---------------------------------------------------------------------------
-- The local player's draw
---------------------------------------------------------------------------

local bow -- the held bow Tool, or nil
local tracks = {} -- hold, draw, aim, release
local animations = {}
local drawing = false
local drawStart = 0
local nextDrawAt = 0
local baseFov
local stopObserving

local function loadTracks(character)
	-- Destroy alone doesn't stop a playing track; a leftover hold kept playing beside the new one.
	for _, track in pairs(tracks) do track:Stop(0); track:Destroy() end
	table.clear(tracks)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	-- Never make an Animator here: a client-made one would not replicate the clips.
	local animator = humanoid and (humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", 10))
	if not animator then return end
	local specs = {
		hold = { BowAnimations.T1_BOW_HOLD, Enum.AnimationPriority.Idle, true },
		draw = { BowAnimations.T1_BOW_DRAW, Enum.AnimationPriority.Action, false },
		aim = { BowAnimations.T1_BOW_AIM, Enum.AnimationPriority.Action, true },
		release = { BowAnimations.T1_BOW_RELEASE, Enum.AnimationPriority.Action, false },
	}
	for key, spec in pairs(specs) do
		if spec[1] ~= "" then
			local animation = animations[key] or Instance.new("Animation")
			animation.AnimationId = spec[1]
			animations[key] = animation
			local ok, track = pcall(animator.LoadAnimation, animator, animation)
			if ok then
				track.Priority = spec[2]
				track.Looped = spec[3]
				tracks[key] = track
			end
		end
	end
end

local function stopTrack(key, fade)
	local track = tracks[key]
	if track and track.IsPlaying then track:Stop(fade or BowConfig.ANIMATION_FADE) end
end

local function setZoom(charge)
	local camera = workspace.CurrentCamera
	if not camera then return end
	if charge <= 0 then
		if baseFov then
			TweenService:Create(camera, TweenInfo.new(BowConfig.FOV_RETURN_TIME), { FieldOfView = baseFov }):Play()
			baseFov = nil
		end
		return
	end
	baseFov = baseFov or camera.FieldOfView
	local eased = 1 - (1 - charge) * (1 - charge)
	camera.FieldOfView = baseFov + BowConfig.FULL_DRAW_FOV_DELTA * eased
end

local function endDraw()
	drawing = false
	stopTrack("draw")
	stopTrack("aim")
	setZoom(0)
end

local function charge()
	return math.clamp((os.clock() - drawStart) / BowConfig.CHARGE_TIME, 0, 1)
end

-- Where the crosshair points, and where the nocked arrow sits right now.
local function aimPoint()
	local camera = workspace.CurrentCamera
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local origin, direction = ray.Origin, ray.Direction
	local frontOrigin, frontDirection = AimRay.FrontView()
	if frontOrigin then origin, direction = frontOrigin, frontDirection end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { arrowFolder }
	if player.Character then table.insert(ignore, player.Character) end
	local weaponVisuals = workspace:FindFirstChild("HarukaWeaponVisuals")
	if weaponVisuals then table.insert(ignore, weaponVisuals) end
	params.FilterDescendantsInstances = ignore
	local result = workspace:Raycast(origin, direction * 1000, params)
	return result and result.Position or origin + direction * 1000
end

local function nockedArrowTip()
	local visuals = workspace:FindFirstChild("HarukaWeaponVisuals")
	local model = visuals and visuals:FindFirstChild("Weapon_" .. player.Character.Name)
	local arrow = model and model:FindFirstChild(BowConfig.ARROW_TEMPLATE)
	if arrow and arrow.LocalTransparencyModifier < 1 then
		return arrow.CFrame * Vector3.new(0, 0, -BowConfig.ARROW_LENGTH / 2)
	end
	local head = player.Character:FindFirstChild("Head")
	return head and head.Position
end

local function startDraw()
	if PotionAction.IsLocked(player.Character) then return end
	if drawing or not bow or os.clock() < nextDrawAt then return end
	if player:GetAttribute("EnergyPanting") == true then return end
	drawing = true
	drawStart = os.clock()
	BowDraw:FireServer()
	stopTrack("release", 0.05)
	local draw = tracks.draw
	if draw then
		draw:Play(BowConfig.ANIMATION_FADE, 1, math.max(draw.Length, 0.01) / BowConfig.CHARGE_TIME)
	end
end

local function release()
	if PotionAction.IsLocked(player.Character) then endDraw(); return end
	if not drawing then return end
	local amount = charge()
	endDraw()
	if amount < BowConfig.MIN_CHARGE or not bow then return end
	local target = aimPoint()
	local tip = nockedArrowTip()
	BowRelease:FireServer(target)
	nextDrawAt = os.clock() + BowConfig.REFIRE_DELAY
	if tracks.release then tracks.release:Play(0.04) end
	if tip then
		local direction = (target - tip)
		if direction.Magnitude > 0.5 then
			local range = WeaponData.GetStats(bow:GetAttribute("WeaponId")).MaxRange or 100
			launch(tip, direction.Unit * BowConfig.Speed(amount), range, player.Character)
		end
	end
end

RunService.RenderStepped:Connect(function()
	if not drawing then return end
	if not bow or player:GetAttribute("EnergyPanting") == true or PotionAction.IsLocked(player.Character) then
		endDraw()
		return
	end
	local amount = charge()
	setZoom(amount)
	-- Full draw: hand the pose from the draw clip to the looping aim clip.
	if amount >= 1 and tracks.aim and not tracks.aim.IsPlaying then
		tracks.aim:Play(0.05)
		stopTrack("draw", 0.08)
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	if InteractionLock.IsLocked() or not bow then return end
	startDraw()
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then release() end
end)

local function onTool(tool)
	local isBow = BowConfig.IsBow(tool)
	if isBow and tool == bow then return end
	if drawing then endDraw() end
	bow = isBow and tool or nil
	if bow then
		if tracks.hold and not tracks.hold.IsPlaying then tracks.hold:Play(0.2) end
	else
		stopTrack("hold", 0.2)
		stopTrack("release", 0.1)
	end
end

local currentCharacter
local function onCharacter(character)
	-- CharacterAdded and the startup check can both deliver the same character.
	if character == currentCharacter then return end
	currentCharacter = character
	if stopObserving then stopObserving() end
	bow, drawing = nil, false
	setZoom(0)
	character:WaitForChild("Humanoid", 10)
	loadTracks(character)
	stopObserving = ActiveEquipment.Observe(character, onTool)
end

player.CharacterAdded:Connect(onCharacter)
if player.Character then task.spawn(onCharacter, player.Character) end

print("[BowController] ready")
