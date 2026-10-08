--[[
	MiningClient
	The local player's mining session (MiningConfig has the loop; MiningRewardHandler judges it).

	Pickaxe out, left click one of the coal crystals on a rock within reach (the rock's "Ore"
	part; the stone itself doesn't start it):
	  1. The camera closes in on the crystals. A ring closes on the seam: click as it meets it.
	  2. Fault points glow on the stone around the coal. Press and hold one to charge (the gauge
	     beside it shows the band that breaks it cleanly), release to strike. Too soft: nothing.
	     A clean break runs a crack across the stone. Too hard: it breaks, but the coal cracks
	     too. Right click pries the ore out with what's freed so far. Esc stops (nothing gained).
	  3. The server's result: the rock crumbles apart, the coal drops at your feet as pickups,
	     the grade and XP show.

	Feedback is predicted locally with the same MiningConfig functions the server uses, so it's
	instant; the final grade and coal always come from the server (GameEvents/MiningResult).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

local MiningConfig = require(ReplicatedStorage:WaitForChild("MiningConfig"))
local MiningExcavationConfig = require(ReplicatedStorage:WaitForChild("MiningExcavationConfig"))
local ActiveEquipment = require(ReplicatedStorage:WaitForChild("ActiveEquipment"))
local InteractionLock = require(ReplicatedStorage:WaitForChild("InteractionLock"))
local CameraOverrideState = require(ReplicatedStorage:WaitForChild("CameraOverrideState"))
local CursorUtils = require(ReplicatedStorage:WaitForChild("CursorUtils"))
local Keys = require(ReplicatedStorage:WaitForChild("KeybindConfig"))
local SfxService = require(ReplicatedStorage:WaitForChild("SfxService"))
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local HudBarStyle = require(ReplicatedStorage:WaitForChild("HudBarStyle"))
local MovementLock = require(script.Parent:WaitForChild("ProfessionMovementLock"))
local CenterFlashUI = require(script.Parent.Parent:WaitForChild("CenterFlashUI"))

local player = Players.LocalPlayer
local gameEvents = ReplicatedStorage:WaitForChild("GameEvents")
local SessionStart = gameEvents:WaitForChild("MiningSessionStart")
local SessionAction = gameEvents:WaitForChild("MiningSessionAction")
local MiningResult = gameEvents:WaitForChild("MiningResult")

local LOCK_OWNER = "MiningSession"
local ORE_PART = "Ore" -- the coal crystals on a rock (assets/models/environment/ores); hit these to start
local RING_PX = 320 -- the seam ring's starting diameter
local FAULT_PX = 46
local GAUGE_W, GAUGE_H = 14, 120
local FAULT_SPREAD = 1.35 -- studs from the coal to the farthest fault point
local CRACK_WIDTH = 0.07

local INK = {
	Gold = Color3.fromRGB(232, 196, 120),
	Bone = Color3.fromRGB(236, 226, 208),
	Muted = Color3.fromRGB(160, 148, 128),
	Band = Color3.fromRGB(120, 210, 110),
	Crack = Color3.fromRGB(255, 120, 60),
	StoneCrack = Color3.fromRGB(26, 22, 19),    -- cracks running through the stone
	CoalCrack = Color3.fromRGB(205, 210, 222),  -- fracture lines on a cracked crystal
	Stone = Color3.fromRGB(116, 112, 108),
	StoneDark = Color3.fromRGB(84, 82, 82),
	Coal = Color3.fromRGB(22, 22, 27),
}

---------------------------------------------------------------------------
-- Finding a rock
---------------------------------------------------------------------------

local function isPickaxe(tool)
	if not tool then return false end
	if tool:GetAttribute("DungeonEquipSlot") == "Pickaxe" then return true end
	return string.find(tool.Name, "Pickaxe", 1, true) ~= nil
end

local function oreModelFor(instance)
	local tier, tierCfg = MiningExcavationConfig.getTierForOreModel(instance)
	if not tier then return nil end
	local cur = instance
	while cur and cur ~= workspace do
		if tierCfg.matchName and string.find(cur.Name, tierCfg.matchName, 1, true) and cur:IsA("Model") then
			return cur, tierCfg
		end
		cur = cur.Parent
	end
	return nil
end

local function aimRay()
	local camera = workspace.CurrentCamera
	local mouse = UserInputService:GetMouseLocation()
	return camera:ViewportPointToRay(mouse.X, mouse.Y)
end

-- The crystal under the cursor: (part, model, raycast result). A click on a rock's plain stone
-- returns (nil, model) so the caller can hint. Rocks without crystals (old models) start
-- from anywhere on them.
local function rockUnderAim()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	local ray = aimRay()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local result = workspace:Raycast(ray.Origin, ray.Direction * 60, params)
	if not result or (result.Position - root.Position).Magnitude > MiningConfig.START_RANGE then
		return nil
	end
	local model = oreModelFor(result.Instance)
	if not model then return nil end
	if model:FindFirstChild(ORE_PART, true) and result.Instance.Name ~= ORE_PART then
		return nil, model
	end
	return result.Instance, model, result
end

---------------------------------------------------------------------------
-- Session visuals
---------------------------------------------------------------------------

local session = nil -- the live session, or nil

local function make(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do inst[k] = v end
	inst.Parent = parent
	return inst
end

local function circle(parent, color, thickness, z)
	local frame = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = z or 1,
	}, parent)
	make("UICorner", { CornerRadius = UDim.new(1, 0) }, frame)
	make("UIStroke", { Color = color, Thickness = thickness, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, frame)
	return frame
end

local function label(parent, text, size, color)
	return make("TextLabel", {
		BackgroundTransparency = 1, Text = text, FontFace = UIFonts.HUDLabel, TextSize = size,
		TextColor3 = color or INK.Bone, TextStrokeTransparency = 0.4, AnchorPoint = Vector2.new(0.5, 0),
		Size = UDim2.fromOffset(700, size + 6),
	}, parent)
end

local function sound(key, position)
	SfxService.PlayEffect(key, position and { Position = position } or nil)
end

-- A burst of chips off the face (local only).
local function chips(at, normal, count, color, speed)
	for _ = 1, count do
		local piece = make("Part", {
			Size = Vector3.new(0.18, 0.14, 0.2) * (0.7 + math.random() * 0.8),
			Material = Enum.Material.Slate, Color = color or INK.Stone,
			Anchored = false, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
			CFrame = CFrame.new(at) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6),
		}, session and session.folder or workspace)
		local spread = Vector3.new(math.random() - 0.5, math.random() * 0.8, math.random() - 0.5)
		piece.AssemblyLinearVelocity = (normal * (speed or 9) + spread * 10)
		piece.AssemblyAngularVelocity = Vector3.new(math.random() * 20, math.random() * 20, math.random() * 20)
		Debris:AddItem(piece, 1.4)
	end
end

-- Onto the stone you can see: along the camera's line of sight through `p`, hitting only the
-- rock's stone (never the crystals in front of it). Returns the point (a hair off the surface)
-- and the surface normal there.
local function project(s, p)
	local origin = s.cameraCf.Position
	local dir = p - origin
	local hit = workspace:Raycast(origin, dir.Unit * (dir.Magnitude + 4), s.rockParams)
	if hit then
		return hit.Position + hit.Normal * 0.02, hit.Normal
	end
	return p, s.faceDir
end

-- A crack from `from` to `to` that hugs the stone: short segments (one every CRACK_STEP studs),
-- each projected onto the surface and lying flat on it, wandering smoothly with a little jitter.
local CRACK_STEP = 0.14
local function crackLine(s, from, to, color, width, _)
	local length = (to - from).Magnitude
	if length < 0.05 then return end
	local across = (to - from):Cross(s.faceDir)
	across = across.Magnitude > 1e-3 and across.Unit or s.right
	local steps = math.max(4, math.ceil(length / CRACK_STEP))
	local phase, bend = math.random() * math.pi * 2, length * (0.1 + math.random() * 0.08)
	local points, normals = {}, {}
	for k = 0, steps do
		local u = k / steps
		local wander = math.sin(u * math.pi * 1.6 + phase) * bend * math.sin(u * math.pi)
		local jitter = (k > 0 and k < steps) and (math.random() - 0.5) * 0.05 or 0
		local p, n = project(s, from:Lerp(to, u) + across * (wander + jitter))
		points[k + 1], normals[k + 1] = p, n
	end
	for k = 1, #points - 1 do
		local a, b = points[k], points[k + 1]
		local seg = (b - a).Magnitude
		-- A jump means the line of sight fell off an edge between two samples: leave a gap
		-- rather than a segment through the air.
		if seg > 0.005 and seg < CRACK_STEP * 3 then
			local w = width * (1 - (k - 1) / #points * 0.6) -- tapers toward the end
			local up = (normals[k] + normals[k + 1]).Unit
			local part = make("Part", {
				Name = "Crack", Size = Vector3.new(w, w * 0.35, seg + w * 0.5), Color = color,
				Material = Enum.Material.SmoothPlastic, Transparency = 1,
				Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
				CFrame = CFrame.lookAt((a + b) / 2, b, up),
			}, s.folder)
			-- The crack runs out from its start, segment by segment.
			task.delay((k - 1) * 0.012, function()
				if part.Parent then part.Transparency = 0 end
			end)
		end
	end
	return points
end

-- A clean break: a crack from the broken fault across the stone toward the coal, with a branch.
local function crackStone(s, index)
	local from = s.faultWorld[index]
	local toward = s.face + (from - s.face) * 0.22
	local points = crackLine(s, from, toward, INK.StoneCrack, CRACK_WIDTH * (1 + s.broken * 0.12), 5)
	if points and #points > 3 then
		local mid = points[math.random(2, #points - 1)]
		local away = (mid - s.face).Unit
		local side = away:Cross(s.faceDir).Unit * (math.random() < 0.5 and -1 or 1)
		crackLine(s, mid, mid + (side + away * 0.4).Unit * FAULT_SPREAD * 0.45, INK.StoneCrack, CRACK_WIDTH * 0.7, 3)
	end
end

-- The coal itself cracks: pale fracture lines across the crystals and a spit of sparks. Drawn
-- against the crystals (coalParams), not the stone behind them.
local function crackCoal(s)
	local stone = s.rockParams
	s.rockParams = s.coalParams
	for _ = 1, 2 do
		local a = math.random() * math.pi * 2
		local dir = s.right * math.cos(a) + s.up * math.sin(a)
		crackLine(s, s.face - dir * 0.3, s.face + dir * 0.35, INK.CoalCrack, CRACK_WIDTH * 0.6)
	end
	s.rockParams = stone
	chips(s.face, s.faceDir, 6, INK.Coal, 6)
end

local function shake(s, amount)
	s.shakeUntil = os.clock() + 0.18
	s.shakeAmount = amount
end

-- The rock breaks apart: chunks of stone tumble off (and coal shards if it shattered).
local function crumble(s, shattered)
	local cf, size = s.oreModel:GetBoundingBox()
	local scale = math.clamp(size.Magnitude / 8, 0.5, 2)
	local centre = cf.Position
	local pieces = {}
	local function piece(color, material, sizeRange)
		local part = make(math.random() < 0.5 and "WedgePart" or "Part", {
			Size = Vector3.new(
				math.random() * (sizeRange[2] - sizeRange[1]) + sizeRange[1],
				math.random() * (sizeRange[2] - sizeRange[1]) + sizeRange[1],
				math.random() * (sizeRange[2] - sizeRange[1]) + sizeRange[1]) * scale,
			Color = color, Material = material, Anchored = false, CanCollide = true, CanQuery = false,
			CanTouch = false, CastShadow = true,
			CFrame = cf * CFrame.new((math.random() - 0.5) * size.X * 0.7, (math.random() - 0.3) * size.Y * 0.6,
				(math.random() - 0.5) * size.Z * 0.7) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6),
		}, workspace)
		local out = (part.Position - centre) * Vector3.new(1, 0, 1)
		out = out.Magnitude > 0.05 and out.Unit or Vector3.new(1, 0, 0)
		part.AssemblyLinearVelocity = out * (5 + math.random() * 6) + Vector3.new(0, 6 + math.random() * 7, 0)
		part.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 18
		table.insert(pieces, part)
	end
	for _ = 1, shattered and 24 or 16 do
		piece(math.random() < 0.5 and INK.Stone or INK.StoneDark, Enum.Material.Slate, { 0.35, 1.0 })
	end
	for _ = 1, shattered and 10 or 3 do
		piece(INK.Coal, Enum.Material.Glass, { 0.18, 0.4 })
	end
	-- Settle, then fade out.
	task.delay(1.5, function()
		for _, part in ipairs(pieces) do
			if part.Parent then
				TweenService:Create(part, TweenInfo.new(0.6), { Transparency = 1 }):Play()
				Debris:AddItem(part, 0.65)
			end
		end
	end)
end

local function cleanup()
	local s = session
	if not s then return end
	session = nil
	for _, c in ipairs(s.connections) do c:Disconnect() end
	s.gui:Destroy()
	s.folder:Destroy()
	if s.lookBack then CameraOverrideState.RequestLook(s.lookBack) end
	CameraOverrideState.SetActive(false)
	CursorUtils.release()
	InteractionLock.Release(LOCK_OWNER)
	MovementLock.Set(false)
end

local function setHint(s, text)
	s.hint.Text = text
end

local function refreshStatus(s)
	local dots = {}
	for i = 1, MiningConfig.MAX_CRACKS do
		table.insert(dots, i <= s.crackCount and "X" or "o")
	end
	local outcome = MiningConfig.Outcome({ broken = s.broken, total = #s.layout.faults, cracks = s.crackCount, seam = s.seam or "miss" })
	s.status.Text = ("Coal cracks  %s     Chunk  %d coal"):format(table.concat(dots, " "), outcome.coal)
end

local function showResult(s, result)
	s.phase = "done"
	s.ring.Visible, s.target.Visible = false, false
	for _, f in ipairs(s.faultUi) do f.button.Visible = false end
	s.gauge.Visible = false
	s.timer.Visible = false
	s.keys.Visible = false
	local color = MiningConfig.GRADE_COLORS[result.grade] or INK.Bone
	s.banner.Text = (result.grade or "Done"):upper()
	s.banner.TextColor3 = color
	s.banner.Visible = true
	s.bannerSub.Text = ("+%d Coal     +%d Mining XP"):format(result.coal or 0, result.xp or 0)
	s.bannerSub.Visible = true
	local shattered = result.grade == "Shattered"
	-- The rock comes apart (the server has already hidden it for its respawn).
	for _, d in ipairs(s.folder:GetChildren()) do d:Destroy() end
	crumble(s, shattered)
	shake(s, shattered and 0.3 or 0.18)
	sound(shattered and "MineShatter" or "MinePry", s.face)
	task.delay(1.7, function()
		if session == s then cleanup() end
	end)
end

---------------------------------------------------------------------------
-- Session flow
---------------------------------------------------------------------------

local function project2d(world)
	local point = workspace.CurrentCamera:WorldToViewportPoint(world)
	return Vector2.new(point.X, point.Y)
end

local function strike(s, index, hold)
	local fault = s.layout.faults[index]
	if not fault or s.brokenSet[index] or s.phase ~= "extract" then return end
	if hold < MiningConfig.MIN_HOLD then return end
	SessionAction:FireServer({ kind = "strike", point = index, hold = hold })
	local result = MiningConfig.JudgeStrike(fault, MiningConfig.PowerFromHold(hold))
	local ui = s.faultUi[index]
	local at = s.faultWorld[index]
	if result == "weak" then
		chips(at, s.faceDir, 3)
		sound("MineWeak", at)
		ui.stroke.Color = INK.Muted
		task.delay(0.25, function() if ui.button.Parent then ui.stroke.Color = INK.Gold end end)
		return
	end
	s.brokenSet[index] = true
	s.broken += 1
	ui.button.BackgroundTransparency = 0.2
	ui.button.BackgroundColor3 = Color3.fromRGB(40, 34, 28)
	ui.stroke.Color = Color3.fromRGB(90, 80, 66)
	ui.button.Active = false
	chips(at, s.faceDir, 10)
	crackStone(s, index)
	shake(s, 0.06)
	if result == "crack" then
		s.crackCount += 1
		crackCoal(s)
		shake(s, 0.12)
		sound("MineCrack", at)
	else
		sound("MineBreak", at)
	end
	refreshStatus(s)
	if s.crackCount >= MiningConfig.MAX_CRACKS or s.broken >= #s.layout.faults then
		s.phase = "waiting"
		setHint(s, s.crackCount >= MiningConfig.MAX_CRACKS and "The coal shatters..." or "The rock gives way...")
	end
end

local function begin(orePart, oreModel, data, hit)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local camera = workspace.CurrentCamera

	-- The crystals you struck, and the side of the rock facing you.
	local boxCf = oreModel:GetBoundingBox()
	local flat = (root.Position - boxCf.Position) * Vector3.new(1, 0, 1)
	local faceDir = flat.Magnitude > 0.1 and flat.Unit or -camera.CFrame.LookVector
	local up = Vector3.yAxis
	local right = (-faceDir):Cross(up).Unit
	local face = hit.Position
	-- Cracks draw on the stone (everything but the crystals); coal cracks on the crystals.
	local stoneParts, crystalParts = {}, {}
	for _, d in ipairs(oreModel:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(d.Name == ORE_PART and crystalParts or stoneParts, d)
		end
	end
	local rockParams = RaycastParams.new()
	rockParams.FilterType = Enum.RaycastFilterType.Include
	rockParams.FilterDescendantsInstances = stoneParts
	local coalParams = RaycastParams.new()
	coalParams.FilterType = Enum.RaycastFilterType.Include
	coalParams.FilterDescendantsInstances = #crystalParts > 0 and crystalParts or stoneParts

	local folder = make("Folder", { Name = "MiningSession" }, workspace)
	local gui = make("ScreenGui", {
		Name = "MiningSession", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 60,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, player:WaitForChild("PlayerGui"))
	local hint = label(gui, "Strike the seam as the ring meets it", 26, INK.Gold)
	hint.Position = UDim2.new(0.5, 0, 0, 70)
	local status = label(gui, "", 18, INK.Bone)
	status.Position = UDim2.new(0.5, 0, 0, 104)
	local timer = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 132), Size = UDim2.fromOffset(320, 6),
		BackgroundColor3 = HudBarStyle.TROUGH, BackgroundTransparency = HudBarStyle.TROUGH_TRANSPARENCY,
		BorderSizePixel = 0, Visible = false,
	}, gui)
	local timerFill = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = INK.Gold, BorderSizePixel = 0 }, timer)
	local keys = label(gui, "Hold a fault to charge, release to strike     Right click: pry it out     Esc: stop", 15, INK.Muted)
	keys.AnchorPoint = Vector2.new(0.5, 1)
	keys.Position = UDim2.new(0.5, 0, 1, -40)
	keys.Visible = false

	local target = circle(gui, INK.Gold, 3, 2)
	target.Size = UDim2.fromOffset(RING_PX * MiningConfig.SEAM.SEAM_SCALE, RING_PX * MiningConfig.SEAM.SEAM_SCALE)
	local ring = circle(gui, INK.Bone, 2, 3)

	local banner = label(gui, "", 48, INK.Bone)
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.32)
	banner.Visible = false
	local bannerSub = label(gui, "", 22, INK.Bone)
	bannerSub.AnchorPoint = Vector2.new(0.5, 0.5)
	bannerSub.Position = UDim2.new(0.5, 0, 0.32, 44)
	bannerSub.Visible = false

	-- The charge gauge: a track, the band that breaks the fault cleanly, the rising fill.
	local gauge = make("Frame", {
		AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(GAUGE_W, GAUGE_H),
		BackgroundColor3 = HudBarStyle.TROUGH, BackgroundTransparency = 0.1, BorderSizePixel = 0, Visible = false, ZIndex = 5,
	}, gui)
	make("UIStroke", { Color = HudBarStyle.BRONZE, Thickness = 1.5 }, gauge)
	local band = make("Frame", { BackgroundColor3 = INK.Band, BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 6 }, gauge)
	local fill = make("Frame", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), BackgroundColor3 = INK.Bone,
		BackgroundTransparency = 0.15, BorderSizePixel = 0, ZIndex = 7,
	}, gauge)

	local layout = MiningConfig.Layout(data.seed)
	local s = {
		orePart = orePart, oreModel = oreModel, layout = layout, folder = folder, gui = gui,
		faceDir = faceDir, right = right, up = up, face = face, rockParams = rockParams, coalParams = coalParams,
		hint = hint, status = status, timer = timer, timerFill = timerFill, keys = keys,
		ring = ring, target = target, banner = banner, bannerSub = bannerSub,
		gauge = gauge, band = band, fill = fill,
		phase = "seam", startedAt = os.clock(), broken = 0, brokenSet = {}, crackCount = 0,
		faultUi = {}, faultWorld = {}, connections = {}, lookBack = camera.CFrame.LookVector,
		cameraCf = CFrame.lookAt(face + faceDir * 5.2 + right * 1.3 + up * 1.4, face + up * 0.1),
	}
	session = s

	for i, fault in ipairs(layout.faults) do
		-- Fault points sit on the stone around the coal.
		local offset = (right * math.cos(fault.angle) + up * math.sin(fault.angle)) * (FAULT_SPREAD * (0.55 + 0.45 * fault.radius))
		s.faultWorld[i] = (project(s, face + offset))
		local button = make("TextButton", {
			AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(FAULT_PX, FAULT_PX), Text = "",
			BackgroundColor3 = Color3.fromRGB(255, 200, 110), BackgroundTransparency = 0.75, AutoButtonColor = false,
			Visible = false, ZIndex = 4,
		}, gui)
		make("UICorner", { CornerRadius = UDim.new(1, 0) }, button)
		local stroke = make("UIStroke", { Color = INK.Gold, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, button)
		s.faultUi[i] = { button = button, stroke = stroke }
		table.insert(s.connections, button.MouseButton1Down:Connect(function()
			if s.phase ~= "extract" or s.brokenSet[i] then return end
			s.charging = i
			s.chargeStart = os.clock()
			local f = layout.faults[i]
			band.Position = UDim2.fromScale(0, 1 - f.hi)
			band.Size = UDim2.fromScale(1, f.hi - f.lo)
			sound("MineCharge", s.faultWorld[i])
		end))
	end

	InteractionLock.Acquire(LOCK_OWNER, { keepVitals = true }) -- open world: health still matters
	CursorUtils.acquire()
	CameraOverrideState.SetActive(true)
	MovementLock.Set(true)
	refreshStatus(s)

	table.insert(s.connections, RunService.RenderStepped:Connect(function()
		if session ~= s then return end
		local cam = workspace.CurrentCamera
		cam.CameraType = Enum.CameraType.Scriptable
		local cf = s.cameraCf
		if s.shakeUntil and os.clock() < s.shakeUntil then
			local a = s.shakeAmount
			cf *= CFrame.new((math.random() - 0.5) * a, (math.random() - 0.5) * a, 0)
		end
		cam.CFrame = cf
		local now = os.clock()
		local facePx = project2d(s.face)
		if s.phase == "seam" then
			local scale = 1 - (now - s.startedAt) / MiningConfig.SEAM.RING_TIME
			if scale <= 0 then
				-- Too late: a miss.
				s.phase = "extract-pending"
				SessionAction:FireServer({ kind = "seam", accuracy = 1 })
				s.seam = "miss"
			else
				s.ring.Size = UDim2.fromOffset(RING_PX * scale, RING_PX * scale)
			end
			s.ring.Position = UDim2.fromOffset(facePx.X, facePx.Y)
			s.target.Position = UDim2.fromOffset(facePx.X, facePx.Y)
		end
		if s.phase == "extract-pending" then
			-- Enter the main phase (after a click or a late miss).
			s.phase = "extract"
			s.extractAt = now
			s.ring.Visible, s.target.Visible = false, false
			s.timer.Visible = true
			s.keys.Visible = true
			if s.seam == "miss" then
				s.crackCount += 1
				crackCoal(s)
				sound("MineCrack", s.face)
				setHint(s, "Missed the seam: the coal is cracked")
			elseif s.seam == "perfect" then
				setHint(s, "Perfect strike: +1 coal")
			else
				setHint(s, "Clean strike")
			end
			refreshStatus(s)
			for _, ui in ipairs(s.faultUi) do ui.button.Visible = true end
			task.delay(1.2, function()
				if session == s and s.phase == "extract" then setHint(s, "Break the faults: crack the rock open") end
			end)
		end
		if s.phase == "extract" or s.phase == "waiting" then
			for i, ui in ipairs(s.faultUi) do
				local px = project2d(s.faultWorld[i])
				ui.button.Position = UDim2.fromOffset(px.X, px.Y)
			end
			if s.phase == "extract" then
				local left = 1 - (now - s.extractAt) / MiningConfig.TIME_LIMIT
				s.timerFill.Size = UDim2.fromScale(math.clamp(left, 0, 1), 1)
				if left <= 0 then
					s.phase = "waiting"
					setHint(s, "The rock settles: prying it out...")
				end
			end
		end
		if s.charging then
			local px = project2d(s.faultWorld[s.charging])
			s.gauge.Visible = true
			s.gauge.Position = UDim2.fromOffset(px.X + FAULT_PX / 2 + 10, px.Y)
			local power = MiningConfig.PowerFromHold(now - s.chargeStart)
			s.fill.Size = UDim2.fromScale(1, power)
			local f = s.layout.faults[s.charging]
			s.fill.BackgroundColor3 = power > f.hi and INK.Crack or power >= f.lo and INK.Band or INK.Bone
		else
			s.gauge.Visible = false
		end
	end))

	table.insert(s.connections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if session ~= s then return end
		if input.KeyCode == Keys.CloseMenu then
			SessionAction:FireServer({ kind = "cancel" })
			cleanup()
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 and s.phase == "seam" and not gameProcessed then
			local scale = 1 - (os.clock() - s.startedAt) / MiningConfig.SEAM.RING_TIME
			local accuracy = math.abs(scale - MiningConfig.SEAM.SEAM_SCALE)
			s.seam = MiningConfig.JudgeSeam(accuracy)
			SessionAction:FireServer({ kind = "seam", accuracy = accuracy })
			sound(s.seam == "miss" and "MineWeak" or "MineSeam", s.face)
			chips(s.face, s.faceDir, s.seam == "perfect" and 14 or 8, INK.Coal)
			s.phase = "extract-pending"
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 and s.phase == "extract" then
			s.phase = "waiting"
			s.charging = nil
			setHint(s, "Prying it out...")
			SessionAction:FireServer({ kind = "pry" })
		end
	end))
	table.insert(s.connections, UserInputService.InputEnded:Connect(function(input)
		if session ~= s or input.UserInputType ~= Enum.UserInputType.MouseButton1 or not s.charging then return end
		local index = s.charging
		s.charging = nil
		strike(s, index, os.clock() - s.chargeStart)
	end))
end

MiningResult.OnClientEvent:Connect(function(result)
	local s = session
	if not s or type(result) ~= "table" then return end
	if result.ended == "cancel" then
		cleanup()
		return
	end
	showResult(s, result)
end)

---------------------------------------------------------------------------
-- Starting
---------------------------------------------------------------------------

local starting = false
local lastHint = 0
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or session or starting or input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	if InteractionLock.IsLocked() then return end
	local character = player.Character
	if not isPickaxe(ActiveEquipment.GetTool(character)) then return end
	local orePart, oreModel, hit = rockUnderAim()
	if not orePart then
		-- Struck the plain stone of a coal rock: point at the coal.
		if oreModel and os.clock() - lastHint > 2 then
			lastHint = os.clock()
			CenterFlashUI.Show("Strike the coal")
		end
		return
	end
	starting = true
	local ok, data = pcall(SessionStart.InvokeServer, SessionStart, orePart)
	starting = false
	if ok and type(data) == "table" and data.ok then
		begin(orePart, oreModel, data, hit)
	end
end)

-- Dropping the pickaxe or dying mid-session ends it here too (the server ends its side).
player.CharacterRemoving:Connect(cleanup)
RunService.Heartbeat:Connect(function()
	local s = session
	if s and s.phase ~= "done" and not isPickaxe(ActiveEquipment.GetTool(player.Character)) then
		SessionAction:FireServer({ kind = "cancel" })
		cleanup()
	end
end)
