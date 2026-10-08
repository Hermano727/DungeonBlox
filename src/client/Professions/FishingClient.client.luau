--[[
	FishingClient
	Spear-fishing (FishingConfig has the loop; SpearFishHandler judges it).

	  1. Approach unseen: fish circle in every pool (parts tagged FishingPool), drawn with the real
	     fish models (falling back to flat shadows if a model is missing). Sprinting or
	     jumping near one sends them deep for a few seconds (the server stamps SpookedUntil).
	  2. Spear out, left click the water: the camera swings over the pool. Hold to draw, release to
	     throw at the cursor. The spear lands FLIGHT seconds later, so lead the fish. One hit spears
	     it; spears are unlimited.
	  3. The haul: the spear holds the fish on its line. Hold the mouse to lift the catch zone,
	     let go to drop it, and keep the fish inside until the line is in.
	  Then the next fish swim in (a new ROUND) without leaving the pool view. Esc leaves.

	Ambient and session fish are drawn from the same deterministic paths the server judges with
	(FishingConfig.FishPosition, on the server clock), so what you see is what it checks.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")

local FishingConfig = require(ReplicatedStorage:WaitForChild("FishingConfig"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local HudIcons = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Icons"):WaitForChild("Hud"):WaitForChild("HudIcons"))
local ActiveEquipment = require(ReplicatedStorage:WaitForChild("ActiveEquipment"))
local InteractionLock = require(ReplicatedStorage:WaitForChild("InteractionLock"))
local CameraOverrideState = require(ReplicatedStorage:WaitForChild("CameraOverrideState"))
local CursorUtils = require(ReplicatedStorage:WaitForChild("CursorUtils"))
local Keys = require(ReplicatedStorage:WaitForChild("KeybindConfig"))
local SfxService = require(ReplicatedStorage:WaitForChild("SfxService"))
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local MovementLock = require(script.Parent:WaitForChild("ProfessionMovementLock"))
local HaulBar = require(script.Parent:WaitForChild("HaulBar"))
local CenterFlashUI = require(script.Parent.Parent:WaitForChild("CenterFlashUI"))

local player = Players.LocalPlayer
local gameEvents = ReplicatedStorage:WaitForChild("GameEvents")
local SessionStart = gameEvents:WaitForChild("FishingSessionStart")
local ThrowRemote = gameEvents:WaitForChild("FishingThrow")
local SessionAction = gameEvents:WaitForChild("FishingSessionAction")
local FishingResult = gameEvents:WaitForChild("FishingResult")

local THROW = FishingConfig.THROW
local HAUL = FishingConfig.HAUL
local LOCK_OWNER = "FishingSession"
-- Studs under the surface. Negative: a hair above it, because terrain water here is murky
-- (WaterTransparency 0.3) and hides anything really underneath. Tune with the water.
local SHADOW_DEPTH = -0.12
local SHADOW_ALPHA = 0.3 -- shadow transparency when visible
local MODEL_SINK = 0.15 -- a fish model's centre sits this share of its height under the surface
local MODEL_SOLID_AT = 0.3 -- an alpha at or under this shows a fish model fully solid
local DRAW_DISTANCE = 220 -- pools further than this from the camera aren't animated
local AMBIENT_SPEED = 0.4 -- ambient fish idle slower than hunted ones
local THROW_VOLUME = 0.75 -- the spear-throw whoosh at 1.5x the default 0.5
local THROW_SPACING = 0.36 -- seconds between clicks that throw (the server allows one per 0.35 s)
local STRIP_H, STRIP_ICON, STRIP_TEXT = 68, 44, 36 -- the helper strip's plates, at full size
local STRIP_TOP = 28 -- px from the top of the screen
local STRIP_MARGIN = 16 -- it shrinks to keep this much room each side on narrow screens
local RESULT_TIME = 3.0 -- seconds the catch banner shows before the next fish swim in (covers the showcase)
local ROUND_FADE_IN = 0.8

local INK = {
	Gold = Color3.fromRGB(232, 196, 120),
	Bone = Color3.fromRGB(236, 226, 208),
	Muted = Color3.fromRGB(160, 148, 128),
	Zone = Color3.fromRGB(120, 210, 110),
	Bad = Color3.fromRGB(230, 110, 90),
	Water = Color3.fromRGB(190, 230, 255),
}

local function serverNow()
	return workspace:GetServerTimeNow()
end

local function make(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do inst[k] = v end
	inst.Parent = parent
	return inst
end

local function sound(key, position)
	SfxService.PlayEffect(key, position and { Position = position } or nil)
end

local function isSpear(tool)
	if not tool then return false end
	if tool:GetAttribute("DungeonEquipSlot") == "FishingSpear" then return true end
	return string.find(tool.Name, "Spear", 1, true) ~= nil
end

local function poolRadius(pool)
	return tonumber(pool:GetAttribute("Radius")) or 8
end

local function fishName(id)
	local def = ItemDefinitions.Get and ItemDefinitions.Get(id)
	return def and def.DisplayName or id
end

---------------------------------------------------------------------------
-- Fish shadows
---------------------------------------------------------------------------

-- A swimming fish: its real model (FishingConfig.CATCH_SHOW[id].model, copied to
-- ReplicatedStorage.FishVisuals by SpearFishHandler), or the old flat body + tail shadow while
-- that model isn't there. `alpha` below is how see-through it is (1 = hidden).
local function fishTemplate(fishId)
	local spec = FishingConfig.CATCH_SHOW[fishId]
	local visuals = ReplicatedStorage:FindFirstChild(FishingConfig.VISUALS_FOLDER)
	return spec and visuals and visuals:FindFirstChild(spec.model)
end

local function newShadow(parent, behaviour, fishId)
	local size = behaviour.size
	local template = fishTemplate(fishId)
	if template then
		local body = template:Clone()
		body.Anchored = true
		body.CanCollide, body.CanTouch, body.CanQuery = false, false, false
		body.CastShadow = false
		body.Transparency = 1
		body.Parent = parent
		return { body = body, model = true, height = body.Size.Y, size = size, alpha = 1, last = nil, heading = Vector3.new(0, 0, -1) }
	end
	local body = make("Part", {
		Name = "FishShadow", Size = Vector3.new(0.85, 0.1, 2.1) * size, Color = behaviour.tint,
		Material = Enum.Material.SmoothPlastic, Transparency = 1, Anchored = true, CanCollide = false,
		CanQuery = false, CanTouch = false, CastShadow = false,
	}, parent)
	make("SpecialMesh", { MeshType = Enum.MeshType.Sphere }, body)
	local tail = make("Part", {
		Name = "Tail", Size = Vector3.new(0.75, 0.08, 0.55) * size, Color = behaviour.tint,
		Material = Enum.Material.SmoothPlastic, Transparency = 1, Anchored = true, CanCollide = false,
		CanQuery = false, CanTouch = false, CastShadow = false,
	}, parent)
	make("SpecialMesh", { MeshType = Enum.MeshType.Sphere }, tail)
	return { body = body, tail = tail, size = size, alpha = 1, last = nil, heading = Vector3.new(0, 0, -1) }
end

-- The parts that fade and flash: the model, or the shadow's body and tail.
local function shadowParts(shadow)
	return shadow.tail and { shadow.body, shadow.tail } or { shadow.body }
end

-- Put a fish at a pool-local (x, z), facing the way it's swimming.
local function placeShadow(shadow, center, local2, alpha, t)
	local pos = Vector3.new(center.X + local2.X, center.Y - SHADOW_DEPTH, center.Z + local2.Y)
	if shadow.last then
		local delta = (pos - shadow.last) * Vector3.new(1, 0, 1)
		if delta.Magnitude > 0.002 then
			shadow.heading = shadow.heading:Lerp(delta.Unit, 0.25)
		end
	end
	shadow.last = pos
	local heading = shadow.heading.Magnitude > 0.01 and shadow.heading.Unit or Vector3.new(0, 0, -1)
	local wag = math.sin(t * 9 + shadow.size * 3)
	if shadow.model then
		-- Mostly under the surface with its back breaking it; the whole body sways as it swims.
		local sunk = pos - Vector3.new(0, SHADOW_DEPTH + shadow.height * MODEL_SINK, 0)
		shadow.body.CFrame = CFrame.lookAt(sunk, sunk + heading) * CFrame.Angles(0, wag * 0.14, wag * 0.05)
	else
		local cf = CFrame.lookAt(pos, pos + heading)
		shadow.body.CFrame = cf
		shadow.tail.CFrame = cf * CFrame.new(0, 0, 1.15 * shadow.size) * CFrame.Angles(0, wag * 0.45, 0)
	end
	if alpha ~= shadow.alpha then
		shadow.alpha = alpha
		-- Models are solid when fully shown (the flat shadows were always a little see-through).
		local transparency = shadow.model and math.clamp((alpha - MODEL_SOLID_AT) / (1 - MODEL_SOLID_AT), 0, 1) or alpha
		for _, part in ipairs(shadowParts(shadow)) do part.Transparency = transparency end
	end
end

local function destroyShadow(shadow)
	for _, part in ipairs(shadowParts(shadow)) do part:Destroy() end
end

-- Every pool's ambient fish: the same for every client (seeded by the pool's FishSeed).
local pools = {} -- [pool] = { folder, fish = { {shadow, params} }, fade }
local ambientBehaviour = FishingConfig.BehaviourFor("Fish")

local function addPool(pool)
	if pools[pool] or not pool:IsA("BasePart") then return end
	local folder = make("Folder", { Name = "FishShadows" }, workspace)
	pools[pool] = { folder = folder, fish = {}, fade = 1 }
end

local function removePool(pool)
	local entry = pools[pool]
	if not entry then return end
	pools[pool] = nil
	entry.folder:Destroy()
end

for _, pool in ipairs(CollectionService:GetTagged(FishingConfig.POOL_TAG)) do addPool(pool) end
CollectionService:GetInstanceAddedSignal(FishingConfig.POOL_TAG):Connect(addPool)
CollectionService:GetInstanceRemovedSignal(FishingConfig.POOL_TAG):Connect(removePool)

local session = nil -- the live session, or nil

RunService.RenderStepped:Connect(function(dt)
	local camera = workspace.CurrentCamera
	local now = serverNow()
	for pool, entry in pairs(pools) do
		local seed = pool:GetAttribute("FishSeed")
		local near = (pool.Position - camera.CFrame.Position).Magnitude < DRAW_DISTANCE
		-- Wait for the fish models to replicate before building, or these would stay flat shadows.
		local ready = ReplicatedStorage:FindFirstChild(FishingConfig.VISUALS_FOLDER) ~= nil
		if seed and near and ready and pool.Parent then
			if #entry.fish == 0 then
				for i = 1, FishingConfig.AMBIENT_FISH do
					entry.fish[i] = { shadow = newShadow(entry.folder, ambientBehaviour, "Fish"), params = FishingConfig.FishParams(seed, i) }
				end
			end
			-- Spooked, or this is our own session's pool: the ambient fish fade out.
			local hidden = (pool:GetAttribute("SpookedUntil") or 0) > now or (session ~= nil and session.pool == pool)
			local goal = hidden and 1 or 0
			entry.fade += math.clamp(goal - entry.fade, -dt * 1.5, dt * 1.5)
			local alpha = SHADOW_ALPHA + (1 - SHADOW_ALPHA) * entry.fade
			local radius = poolRadius(pool)
			local tau = (now % 3600) * AMBIENT_SPEED
			for _, f in ipairs(entry.fish) do
				local p = FishingConfig.FishPosition(f.params, ambientBehaviour, tau, radius)
				-- Going deep: they also drift toward the middle as they fade.
				placeShadow(f.shadow, pool.Position, p * (1 - 0.4 * entry.fade), alpha, now)
			end
		elseif #entry.fish > 0 then
			for _, f in ipairs(entry.fish) do destroyShadow(f.shadow) end
			table.clear(entry.fish)
		end
	end
end)

---------------------------------------------------------------------------
-- Session visuals
---------------------------------------------------------------------------

local function label(parent, text, size, color)
	return make("TextLabel", {
		BackgroundTransparency = 1, Text = text, FontFace = UIFonts.HUDLabel, TextSize = size,
		TextColor3 = color or INK.Bone, TextStrokeTransparency = 0.4, AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(700, size + 6),
	}, parent)
end

local function worldAt(s, local2, depth)
	return Vector3.new(s.center.X + local2.X, s.center.Y - (depth or 0), s.center.Z + local2.Y)
end

-- Where the cursor meets the water, pool-local.
local function aimOnWater(s)
	local mouse = UserInputService:GetMouseLocation()
	local ray = workspace.CurrentCamera:ViewportPointToRay(mouse.X, mouse.Y)
	if math.abs(ray.Direction.Y) < 1e-4 then return nil end
	local t = (s.center.Y - ray.Origin.Y) / ray.Direction.Y
	if t <= 0 then return nil end
	local hit = ray.Origin + ray.Direction * t
	local local2 = Vector2.new(hit.X - s.center.X, hit.Z - s.center.Z)
	-- Keep the aim on the pool (a little past its edge is fine).
	local limit = s.radius * 1.1
	if local2.Magnitude > limit then local2 = local2.Unit * limit end
	return local2
end

local function newSpear(parent)
	local shaft = make("Part", {
		Name = "Spear", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4.2, 0.14, 0.14),
		Material = Enum.Material.Wood, Color = Color3.fromRGB(110, 78, 48),
		Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
	}, parent)
	local tip = make("Part", {
		Name = "Tip", Size = Vector3.new(0.55, 0.16, 0.16), Material = Enum.Material.Metal,
		Color = Color3.fromRGB(150, 150, 146), Anchored = true, CanCollide = false, CanQuery = false,
		CanTouch = false, CastShadow = false,
	}, parent)
	return { shaft = shaft, tip = tip }
end

-- Aim a spear so its tip sits at `tipAt`, pointing along `dir`.
local function placeSpear(spear, tipAt, dir)
	if dir.Magnitude < 1e-4 then dir = Vector3.new(0, -1, 0) end
	local look = CFrame.lookAt(tipAt, tipAt + dir.Unit) * CFrame.Angles(0, math.rad(90), 0) -- +X along dir
	spear.tip.CFrame = look
	spear.shaft.CFrame = look * CFrame.new(-2.35, 0, 0)
end

local function fadeSpear(spear, seconds)
	for _, part in ipairs({ spear.shaft, spear.tip }) do
		TweenService:Create(part, TweenInfo.new(seconds), { Transparency = 1 }):Play()
	end
	task.delay(seconds, function()
		spear.shaft:Destroy()
		spear.tip:Destroy()
	end)
end

-- A ring of spray on the surface.
local function splash(s, at, color, big)
	local ring = make("Part", {
		Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.05, 0.6, 0.6), Material = Enum.Material.Neon,
		Color = color or INK.Water, Transparency = 0.3, Anchored = true, CanCollide = false, CanQuery = false,
		CanTouch = false, CastShadow = false, CFrame = CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90)),
	}, s.folder)
	local grow = big and 5 or 3
	TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {
		Size = Vector3.new(0.05, grow, grow), Transparency = 1,
	}):Play()
	game:GetService("Debris"):AddItem(ring, 0.6)
	for _ = 1, big and 10 or 6 do
		local drop = make("Part", {
			Shape = Enum.PartType.Ball, Size = Vector3.new(0.18, 0.18, 0.18), Material = Enum.Material.Glass,
			Color = INK.Water, Transparency = 0.2, Anchored = false, CanCollide = false, CanQuery = false,
			CanTouch = false, CastShadow = false, Position = at + Vector3.new(0, 0.2, 0),
		}, s.folder)
		drop.AssemblyLinearVelocity = Vector3.new((math.random() - 0.5) * 8, 7 + math.random() * 6, (math.random() - 0.5) * 8)
		game:GetService("Debris"):AddItem(drop, 0.9)
	end
end

local function flashShadow(f, color)
	if f.shadow.model then
		-- A textured model ignores Color: flash it with a brief highlight instead.
		local flash = make("Highlight", {
			FillColor = color, FillTransparency = 0.35, OutlineTransparency = 1,
			DepthMode = Enum.HighlightDepthMode.Occluded,
		}, f.shadow.body)
		game:GetService("Debris"):AddItem(flash, 0.18)
		return
	end
	f.shadow.body.Color = color
	f.shadow.tail.Color = color
	task.delay(0.18, function()
		if f.shadow.body.Parent then
			f.shadow.body.Color = f.behaviour.tint
			f.shadow.tail.Color = f.behaviour.tint
		end
	end)
end

local function refreshStatus(s)
	s.strip.caught.Text = tostring(s.caught)
end

-- The helper strip at the top of the screen: dark plates (readable over bright water and dark
-- caves alike), each an icon and a word or number. The input icons are white art tinted bone.
local function buildStrip(gui)
	local row = make("Frame", {
		Name = "HelperStrip", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, STRIP_TOP),
		Size = UDim2.fromOffset(0, STRIP_H), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1,
	}, gui)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 20),
		VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)
	local scale = make("UIScale", { Scale = 1 }, row)
	local function item(order, icon, iconTint, text)
		local plate = make("Frame", {
			LayoutOrder = order, Size = UDim2.fromOffset(0, STRIP_H), AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = Color3.fromRGB(18, 14, 10), BackgroundTransparency = 0.3, BorderSizePixel = 0,
		}, row)
		make("UICorner", { CornerRadius = UDim.new(0, 16) }, plate)
		make("UIStroke", { Color = Color3.fromRGB(150, 118, 70), Transparency = 0.35, Thickness = 3 }, plate)
		make("UIPadding", { PaddingLeft = UDim.new(0, 20), PaddingRight = UDim.new(0, 24) }, plate)
		make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 16),
			VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
		}, plate)
		make("ImageLabel", {
			LayoutOrder = 1, Size = UDim2.fromOffset(STRIP_ICON, STRIP_ICON), BackgroundTransparency = 1,
			Image = icon or "", ImageColor3 = iconTint or Color3.new(1, 1, 1), ScaleType = Enum.ScaleType.Fit,
		}, plate)
		return make("TextLabel", {
			LayoutOrder = 2, Size = UDim2.fromOffset(0, STRIP_H), AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1, Text = text, FontFace = UIFonts.HUDLabel, TextSize = STRIP_TEXT,
			TextColor3 = INK.Bone, TextStrokeTransparency = 0.5,
		}, plate)
	end
	local strip = {
		root = row,
		action = item(1, HudIcons.MOUSE_LEFT, INK.Bone, "Throw"),
		caught = item(2, ItemDefinitions.GetIcon("Fish"), nil, "0"),
		timer = item(3, HudIcons.HOURGLASS, nil, "0:00"),
		exit = item(4, HudIcons.KEY_ESC, INK.Bone, "Exit"),
	}
	-- Centred by its anchor at any resolution; on a screen too narrow for it, it scales down to fit
	-- (AbsoluteSize already includes the UIScale, so divide it back out for the natural width).
	function strip.fit()
		local viewport = workspace.CurrentCamera.ViewportSize
		local natural = row.AbsoluteSize.X / math.max(scale.Scale, 0.01)
		if natural <= 0 then return end
		local fit = math.min(1, (viewport.X - STRIP_MARGIN * 2) / natural)
		if math.abs(fit - scale.Scale) > 0.001 then scale.Scale = fit end
	end
	return strip
end

local function cleanup()
	local s = session
	if not s then return end
	session = nil
	for _, c in ipairs(s.connections) do c:Disconnect() end
	s.gui:Destroy()
	s.folder:Destroy()
	if s.lineAttachment then s.lineAttachment:Destroy() end
	if s.lookBack then CameraOverrideState.RequestLook(s.lookBack) end
	CameraOverrideState.SetActive(false)
	CursorUtils.release()
	InteractionLock.Release(LOCK_OWNER)
	MovementLock.Set(false)
end

-- Where the session's fish are right now (pool-local), given each fish's hit times.
local function fishLocal(s, f, t)
	return FishingConfig.FishPosition(f.params, f.behaviour, FishingConfig.PathTime(t, f.hits), s.radius)
end

---------------------------------------------------------------------------
-- The haul
---------------------------------------------------------------------------

local function startHaul(s)
	s.phase = "haul"
	local f = s.fish[s.target]
	s.haul = {
		rng = Random.new(s.seed),
		-- Zone and fish both start centred, with a moment's grace before either moves.
		zone = 0.5 - HAUL.ZONE / 2, vel = 0, progress = HAUL.START, fish = 0.5, fishGoal = 0.5,
		nextJump = os.clock() + HAUL.GRACE, graceUntil = os.clock() + HAUL.GRACE,
		startedAt = os.clock(), from = s.stunLocal or fishLocal(s, f, serverNow() - s.startedAt),
	}
	s.strip.action.Text = "Reel" -- hold to lift the net
	s.haulBar:Show(f.id)
	sound("FishStunned", worldAt(s, s.haul.from))
	sound("FishReelIn")
	-- The line from the hand to the fish.
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		s.lineAttachment = make("Attachment", { Name = "FishingLine", Position = Vector3.new(0.6, 0.8, -0.6) }, root)
		local fishAttach = make("Attachment", {}, f.shadow.body)
		make("Beam", {
			Attachment0 = s.lineAttachment, Attachment1 = fishAttach, Width0 = 0.05, Width1 = 0.05,
			Color = ColorSequence.new(INK.Bone), Transparency = NumberSequence.new(0.15), FaceCamera = true,
			Segments = 12, CurveSize0 = 0, CurveSize1 = 0, LightInfluence = 0,
		}, s.lineAttachment)
	end
end

local function stepHaul(s, dt)
	local h = s.haul
	local f = s.fish[s.target]
	local now = os.clock()
	local jump = f.behaviour.haulJump
	-- The fish: lunges to a new spot every so often (further for stronger fish).
	if now >= h.nextJump then
		h.fishGoal = math.clamp(h.fish + (h.rng:NextNumber() * 2 - 1) * (0.25 + jump), 0.04, 0.96)
		h.nextJump = now + h.rng:NextNumber(0.5, 1.3)
	end
	h.fish += (h.fishGoal - h.fish) * math.min(1, dt * (2.5 + jump * 4))
	-- Your zone: lifts while held, sinks when not.
	local held = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
	local sinking = now >= h.graceUntil -- during the grace the zone only moves if you lift it
	h.vel = math.clamp(h.vel + (held and HAUL.RISE or (sinking and -HAUL.FALL or 0)) * dt, -1.6, 1.6)
	h.zone += h.vel * dt
	if h.zone <= 0 then
		h.zone, h.vel = 0, math.max(h.vel, 0)
	elseif h.zone >= 1 - HAUL.ZONE then
		h.zone, h.vel = 1 - HAUL.ZONE, math.min(h.vel, 0)
	end
	local inZone = h.fish >= h.zone and h.fish <= h.zone + HAUL.ZONE
	h.progress = math.clamp(h.progress + (inZone and HAUL.FILL or -HAUL.DRAIN) * dt, 0, 1)

	-- The bar (0 = bottom).
	s.haulBar:Update(dt, h, inZone)

	-- In the water: it thrashes, and comes in toward the bank as the line comes in.
	local bank = s.bankLocal
	local base = h.from:Lerp(bank, h.progress * 0.85)
	local thrash = Vector2.new(math.sin(now * 13), math.cos(now * 11)) * (inZone and 0.12 or 0.35)
	placeShadow(f.shadow, s.center, base + thrash, 0.15, now)
	for _, spear in ipairs(s.stuck) do
		if spear.index == s.target then
			placeSpear(spear.spear, worldAt(s, base + thrash, SHADOW_DEPTH), spear.dir)
		end
	end

	if h.progress >= 1 then
		s.phase = "waiting"
		s.haulBar:Finish(true)
		SessionAction:FireServer({ kind = "caught" })
	elseif h.progress <= 0 then
		s.phase = "waiting"
		s.haulBar:Finish(false)
		SessionAction:FireServer({ kind = "snap" })
	end
end

---------------------------------------------------------------------------
-- Throwing
---------------------------------------------------------------------------

local function throw(s, aim)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local releaseT = serverNow()
	s.throwsUsed += 1
	s.inFlight += 1
	refreshStatus(s)
	SfxService.PlayEffect("SpearThrow", { Position = root.Position, Volume = THROW_VOLUME })

	local round = s.round
	local spear = newSpear(s.roundFolder)
	local start = root.Position + Vector3.new(0, 1.4, 0) + root.CFrame.RightVector * 0.6
	local finish = worldAt(s, aim, 0.6)
	local arc = 2 + (finish - start).Magnitude * 0.08
	local result = nil
	task.spawn(function()
		local ok, r = pcall(ThrowRemote.InvokeServer, ThrowRemote, aim.X, aim.Y, releaseT)
		result = ok and type(r) == "table" and r or { ok = false }
		if s.round ~= round then return end
		-- A hit slows the fish from the moment of impact on; record it as soon as we know.
		if result.hit and s.fish[result.hit] and result.impact then
			table.insert(s.fish[result.hit].hits, result.impact)
			s.target = result.hit
		end
	end)

	local flightStart = os.clock()
	local function pointAt(u)
		return start:Lerp(finish, u) + Vector3.new(0, arc * 4 * u * (1 - u), 0)
	end
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if session ~= s then conn:Disconnect() return end
		if s.round ~= round then
			-- The round ended while it flew (its folder, and this spear, are already gone).
			conn:Disconnect()
			s.inFlight -= 1
			return
		end
		local u = math.min(1, (os.clock() - flightStart) / THROW.FLIGHT)
		local p = pointAt(u)
		placeSpear(spear, p, pointAt(math.min(1, u + 0.02)) - pointAt(math.max(0, u - 0.02)))
		if u >= 1 and result then
			conn:Disconnect()
			s.inFlight -= 1
			local landAt = worldAt(s, aim)
			if result.hit and s.fish[result.hit] then
				local f = s.fish[result.hit]
				sound("SpearHit", landAt)
				splash(s, landAt, INK.Bone, false)
				flashShadow(f, INK.Bone)
				local dir = (finish - start)
				table.insert(s.stuck, { spear = spear, index = result.hit, dir = Vector3.new(dir.X, -math.abs(dir.Magnitude) * 0.6, dir.Z) })
				refreshStatus(s)
				if result.stunned then
					s.stunLocal = fishLocal(s, f, serverNow() - s.startedAt)
					startHaul(s)
				end
			else
				sound("SpearSplash", landAt)
				splash(s, landAt, nil, false)
				fadeSpear(spear, 0.6)
			end
		end
	end)
	table.insert(s.connections, conn)
end

---------------------------------------------------------------------------
-- Session flow
---------------------------------------------------------------------------

-- A fresh round of fish (the server's `next`, or the session start). Clears the last round's
-- fish, spears and line; the camera, GUI and lock stay up.
local function startRound(s, data)
	s.round += 1
	if s.roundFolder then s.roundFolder:Destroy() end
	if s.lineAttachment then s.lineAttachment:Destroy() s.lineAttachment = nil end
	s.roundFolder = make("Folder", { Name = "Round" }, s.folder)
	s.seed, s.startedAt = data.seed, data.startedAt
	s.fish, s.stuck = {}, {}
	s.phase, s.throwsUsed, s.target, s.haul, s.stunLocal = "stun", 0, nil, nil, nil
	s.roundAt = os.clock()
	for i, id in ipairs(data.fish or {}) do
		local behaviour = FishingConfig.BehaviourFor(id)
		s.fish[i] = {
			id = id, behaviour = behaviour, params = FishingConfig.FishParams(data.seed, i),
			hits = {}, shadow = newShadow(s.roundFolder, behaviour, id),
		}
	end
	s.haulBar:Hide()
	s.banner.Visible = false
	s.bannerSub.Visible = false
	s.strip.action.Text = "Throw"
	refreshStatus(s)
end

local function showResult(s, result)
	s.phase = "done"
	-- Let the bar's catch / snap finish play out, then put it away.
	local finishedRound = s.round
	task.delay(0.9, function()
		if session == s and s.round == finishedRound then s.haulBar:Hide() end
	end)
	s.reticle.Transparency = 1
	local grade = result.grade or "Escaped"
	s.banner.Text = (result.ended == "caught" and grade or "It got away"):upper()
	s.banner.TextColor3 = FishingConfig.GRADE_COLORS[grade] or INK.Bone
	s.banner.Visible = true
	local xp = ("+%d Fishing XP"):format(result.xp or 0)
	if result.ended == "caught" then
		s.caught += 1
		local name = fishName(result.fishId)
		s.bannerSub.Text = result.granted and ("+1 %s     %s"):format(name, xp) or ("No room for the %s     %s"):format(name, xp)
		sound(result.fishId == "GoldenFish" and "GoldenFishCaught" or "FishCaught")
		local f = s.target and s.fish[s.target]
		if f then
			-- Quick: the catch show's own copy of this fish leaps out from the bank right now.
			for _, part in ipairs(shadowParts(f.shadow)) do
				TweenService:Create(part, TweenInfo.new(0.2), { Transparency = 1 }):Play()
			end
		end
	else
		s.bannerSub.Text = xp
		if result.ended == "snap" then sound("FishLineSnap") end
		if s.lineAttachment then s.lineAttachment:Destroy() s.lineAttachment = nil end
	end
	s.bannerSub.Visible = true
	refreshStatus(s)
	for _, stuck in ipairs(s.stuck) do fadeSpear(stuck.spear, 0.8) end
	table.clear(s.stuck)
	local round = s.round
	task.delay(RESULT_TIME, function()
		if session ~= s or s.round ~= round then return end
		if type(result.next) == "table" then
			startRound(s, result.next)
		else
			-- The session is over (a hit knocked the fish off the line).
			cleanup()
		end
	end)
end

local function begin(pool, data)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local camera = workspace.CurrentCamera
	local center = pool.Position
	local radius = tonumber(data.radius) or poolRadius(pool)

	local toPlayer = (root.Position - center) * Vector3.new(1, 0, 1)
	local side = toPlayer.Magnitude > 0.1 and toPlayer.Unit or -camera.CFrame.LookVector * Vector3.new(1, 0, 1)
	if side.Magnitude < 0.1 then side = Vector3.new(0, 0, 1) end
	side = side.Unit
	-- Angled top-down, from the player's side of the pool.
	local eye = center + side * (radius * 0.55) + Vector3.new(0, radius * 2.1 + 6, 0)

	local folder = make("Folder", { Name = "FishingSession" }, workspace)
	local gui = make("ScreenGui", {
		Name = "FishingSession", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 60,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, player:WaitForChild("PlayerGui"))
	-- The only helper UI: one strip at the top (throw, caught, time, exit).
	local strip = buildStrip(gui)
	local banner = label(gui, "", 48, INK.Bone)
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.32)
	banner.Visible = false
	local bannerSub = label(gui, "", 22, INK.Bone)
	bannerSub.AnchorPoint = Vector2.new(0.5, 0.5)
	bannerSub.Position = UDim2.new(0.5, 0, 0.32, 44)
	bannerSub.Visible = false

	-- The haul bar (Professions/HaulBar: a painted slice of seabed, the net, the fish, the reel).
	local haulBar = HaulBar.new(gui)

	-- The aim ring on the water, as wide as a hit.
	local reticle = make("Part", {
		Name = "Aim", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.04, THROW.HIT_RADIUS * 2, THROW.HIT_RADIUS * 2),
		Material = Enum.Material.Neon, Color = INK.Gold, Transparency = 0.65, Anchored = true, CanCollide = false,
		CanQuery = false, CanTouch = false, CastShadow = false,
	}, folder)

	local s = {
		pool = pool, center = center, radius = radius,
		folder = folder, gui = gui, strip = strip, banner = banner, bannerSub = bannerSub, sessionStart = os.clock(),
		haulBar = haulBar, reticle = reticle,
		connections = {}, inFlight = 0, round = 0, caught = 0,
		bankLocal = Vector2.new(side.X, side.Z) * radius * 0.95,
		cameraCf = CFrame.lookAt(eye, center), lookBack = camera.CFrame.LookVector,
	}
	session = s
	startRound(s, data)

	InteractionLock.Acquire(LOCK_OWNER, { keepVitals = true }) -- open world: health still matters
	CursorUtils.acquire()
	CameraOverrideState.SetActive(true)
	MovementLock.Set(true)

	-- Keep the helper strip on screen: refit when the window or its text width changes.
	table.insert(s.connections, workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(strip.fit))
	table.insert(s.connections, strip.root:GetPropertyChangedSignal("AbsoluteSize"):Connect(strip.fit))
	task.defer(strip.fit)
	table.insert(s.connections, RunService.RenderStepped:Connect(function(dt)
		if session ~= s then return end
		local cam = workspace.CurrentCamera
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = s.cameraCf
		local now = serverNow()
		local t = now - s.startedAt
		local elapsed = math.floor(os.clock() - s.sessionStart)
		if elapsed ~= s.shownElapsed then
			s.shownElapsed = elapsed
			s.strip.timer.Text = ("%d:%02d"):format(elapsed // 60, elapsed % 60)
		end
		if s.phase == "stun" or s.phase == "waiting" and not s.haul then
			local fadeIn = math.clamp((os.clock() - s.roundAt) / ROUND_FADE_IN, 0, 1)
			for i, f in ipairs(s.fish) do
				local alpha = (s.target and s.target ~= i) and 0.55 or 0.15
				placeShadow(f.shadow, s.center, fishLocal(s, f, t), 1 - (1 - alpha) * fadeIn, now)
			end
			for _, stuck in ipairs(s.stuck) do
				local f = s.fish[stuck.index]
				placeSpear(stuck.spear, worldAt(s, fishLocal(s, f, t), SHADOW_DEPTH), stuck.dir)
			end
		elseif s.phase == "haul" then
			stepHaul(s, dt)
			-- The other fish scatter.
			for i, f in ipairs(s.fish) do
				if i ~= s.target then
					placeShadow(f.shadow, s.center, fishLocal(s, f, t) * 1.1, 0.85, now)
				end
			end
		end
		if s.phase == "stun" then
			local aim = aimOnWater(s)
			if aim then
				s.reticle.CFrame = CFrame.new(worldAt(s, aim, -0.05)) * CFrame.Angles(0, 0, math.rad(90))
				s.reticle.Transparency = 0.55
			end
		else
			s.reticle.Transparency = 1
		end
	end))

	table.insert(s.connections, UserInputService.InputBegan:Connect(function(input)
		if session ~= s then return end
		if input.KeyCode == Keys.CloseMenu then
			SessionAction:FireServer({ kind = "cancel" })
			cleanup()
			return
		end
		-- A click throws (no draw). Paced like the server (SpearFishHandler's THROW_GAP).
		if input.UserInputType == Enum.UserInputType.MouseButton1 and s.phase == "stun" then
			local now = os.clock()
			if now - (s.lastThrow or 0) < THROW_SPACING then return end
			local aim = aimOnWater(s)
			if aim then
				s.lastThrow = now
				throw(s, aim)
			end
		end
	end))
end

FishingResult.OnClientEvent:Connect(function(result)
	local s = session
	if not s or type(result) ~= "table" then return end
	-- Esc, walking off, idling, or a hit with no fish on the line: just close.
	if result.ended == "cancel" or (result.ended == "hit" and not result.grade) then
		cleanup()
		return
	end
	-- Let an in-flight spear land before the banner.
	task.spawn(function()
		local waitUntil = os.clock() + THROW.FLIGHT + 0.2
		while session == s and s.inFlight > 0 and os.clock() < waitUntil do
			task.wait()
		end
		if session == s then showResult(s, result) end
	end)
end)

---------------------------------------------------------------------------
-- Starting
---------------------------------------------------------------------------

-- The pool the cursor is on, if the player is close enough to it.
local function poolUnderAim()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	local mouse = UserInputService:GetMouseLocation()
	local ray = workspace.CurrentCamera:ViewportPointToRay(mouse.X, mouse.Y)
	local best, bestDist = nil, math.huge
	for pool in pairs(pools) do
		if pool.Parent then
			local radius = poolRadius(pool)
			local flat = (root.Position - pool.Position) * Vector3.new(1, 0, 1)
			local fromEdge = math.max(0, flat.Magnitude - radius)
			if fromEdge <= FishingConfig.START_RANGE and ray.Direction.Y < -1e-3 then
				local t = (pool.Position.Y - ray.Origin.Y) / ray.Direction.Y
				local hit = ray.Origin + ray.Direction * t
				local fromCenter = ((hit - pool.Position) * Vector3.new(1, 0, 1)).Magnitude
				if t > 0 and t < 80 and fromCenter <= radius * 1.25 + 1 and fromEdge < bestDist then
					best, bestDist = pool, fromEdge
				end
			end
		end
	end
	return best
end

local REFUSALS = {
	spooked = "The fish have gone deep. Wait, and come in slowly",
	taken = "Someone is already fishing here",
	too_far = "Get closer to the water",
}

local starting = false
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or session or starting or input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	if InteractionLock.IsLocked() then return end
	if not isSpear(ActiveEquipment.GetTool(player.Character)) then return end
	local pool = poolUnderAim()
	if not pool then return end
	starting = true
	local ok, data = pcall(SessionStart.InvokeServer, SessionStart, pool)
	starting = false
	if ok and type(data) == "table" and data.ok then
		begin(pool, data)
	elseif ok and type(data) == "table" and REFUSALS[data.reason] then
		CenterFlashUI.Show(REFUSALS[data.reason])
	end
end)

-- Dropping the spear or dying mid-session ends it here too (the server ends its side).
player.CharacterRemoving:Connect(cleanup)
RunService.Heartbeat:Connect(function()
	local s = session
	if s and not isSpear(ActiveEquipment.GetTool(player.Character)) then
		SessionAction:FireServer({ kind = "cancel" })
		cleanup()
	end
end)
