--[[
	MiasmaPureWaterCutscene -- the final valve's payoff, for every member of the party (client).

		Cutscene.Play(payload, parent)   -- the "PureWaterCutscene" presentation
		Cutscene.Stop()                  -- immediate (fight failed / encounter gone)

	payload (server, MiasmaEncounterController:BeginPureWaterStun): startsAt, duration, impactAt,
	gate (index), gatePosition, centre, boss, flowing (gate indices), channels (their channel
	models, lined up with `flowing`), stunSeconds (how long the stun lasts after impact).

	Shots, timed off the server clock so everyone sees the same moment:
	  0 .. WAVE_START     on the final gate as it opens: white water bursts out of it
	  .. impactAt         following the flood's glowing wave front down its channel
	  impactAt .. end     on Miasma (the server snapped it to the arena centre) as the water hits:
	                      flash, shockwave ring, a pillar of light (its aura is quenched by
	                      MiasmaEncounterVFX via MiasmaAuraFX.Quench)
	then a quick fade and the camera hands back facing Miasma.

	The flood is dressed as HOLY water on every flowing channel for the whole stun: rising white-
	gold motes, foam flecks and a warm glow on the channel's water parts (the server's own
	sludge->water swap is MiasmaArenaChannels; this only adds light and particles on top).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CameraOverrideState = require(ReplicatedStorage:WaitForChild("CameraOverrideState"))
local HudHider = require(script.Parent:WaitForChild("HudHider"))
local ArenaShake = require(script.Parent:WaitForChild("ArenaShake"))

local Cutscene = {}

local RENDER_NAME = "MiasmaPureWaterCutscene"
local FOV = 60
local LETTERBOX = .1
local WAVE_START = 1.3          -- the wave leaves the gate (shot 1 -> 2)
local FADE_OUT = .35
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local HOLY_WHITE = Color3.fromRGB(245, 250, 255)
local HOLY_GOLD = Color3.fromRGB(255, 232, 170)
local WATER_BLUE = Color3.fromRGB(150, 215, 255)

local active       -- the running cutscene
local holy         -- channel dressing (outlives the cutscene: the whole stun)

local function serverNow() return Workspace:GetServerTimeNow() end
local function smooth(u) u = math.clamp(u, 0, 1); return u * u * (3 - 2 * u) end
local function flat(v) return Vector3.new(v.X, 0, v.Z) end

local function tween(inst, seconds, props, style, dir)
	local t = TweenService:Create(inst, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.CastShadow = false
	for k, v in pairs(props) do p[k] = v end
	p.Parent = parent
	return p
end

local function emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	for k, v in pairs(props) do e[k] = v end
	e.Parent = parent
	return e
end

local function waterParts(channel)
	local list = {}
	if typeof(channel) ~= "Instance" then return list end
	for _, d in ipairs(channel:GetDescendants()) do
		if d:IsA("BasePart") and (d.Name:sub(1, 10) == "OuterWater" or d.Name:sub(1, 10) == "InnerWater") then
			table.insert(list, d)
		end
	end
	return list
end

-- The final channel's run from the gate to the centre, as a polyline with arc lengths.
local function buildPath(gateWater, gatePosition, centre)
	table.sort(gateWater, function(a, b)
		return flat(a.Position - centre).Magnitude > flat(b.Position - centre).Magnitude
	end)
	local points = {}
	local out = flat(gatePosition - centre)
	out = out.Magnitude > .01 and out.Unit or Vector3.new(1, 0, 0)
	local first = gateWater[1]
	local start = first and (first.Position + out * math.min(first.Size.Magnitude * .4, 10)) or gatePosition
	table.insert(points, start)
	for _, p in ipairs(gateWater) do table.insert(points, p.Position) end
	table.insert(points, centre + Vector3.new(0, points[#points].Y - centre.Y, 0))
	local lengths, total = { 0 }, 0
	for i = 2, #points do
		total += (points[i] - points[i - 1]).Magnitude
		lengths[i] = total
	end
	return { points = points, lengths = lengths, total = math.max(total, .01) }
end

local function pathAt(path, u)
	local target = math.clamp(u, 0, 1) * path.total
	for i = 2, #path.points do
		if target <= path.lengths[i] then
			local a, b = path.lengths[i - 1], path.lengths[i]
			return path.points[i - 1]:Lerp(path.points[i], (target - a) / math.max(b - a, 1e-4))
		end
	end
	return path.points[#path.points]
end

-- How far along the path (0..1) a point lies, for "light this part up when the wave passes".
local function pathFraction(path, position)
	local best, bestD = 0, math.huge
	for i, p in ipairs(path.points) do
		local d = (p - position).Magnitude
		if d < bestD then best, bestD = path.lengths[i] / path.total, d end
	end
	return best
end

----------------------------------------------------------------------
-- Holy water dressing (the whole stun)
----------------------------------------------------------------------

local function stopHoly()
	local h = holy
	holy = nil
	if not h then return end
	for _, e in ipairs(h.emitters) do e.Enabled = false end
	for _, l in ipairs(h.lights) do tween(l, 1, { Brightness = 0 }) end
	task.delay(2.5, function() h.folder:Destroy() end)
end

local function dressWater(parts, folder, lightsOn)
	local entries = {}
	for _, water in ipairs(parts) do
		local area = water.Size.X * water.Size.Z
		local host = part({ Name = "HolyWater", Transparency = 1, Size = Vector3.new(math.max(water.Size.X, 1), .3, math.max(water.Size.Z, 1)),
			CFrame = water.CFrame * CFrame.new(0, water.Size.Y * .5 + .2, 0) }, folder)
		local motes = emitter(host, {
			Texture = SPARKLE, Color = ColorSequence.new(HOLY_WHITE, HOLY_GOLD), LightEmission = 1, LightInfluence = 0,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, .5), NumberSequenceKeypoint.new(.5, .9), NumberSequenceKeypoint.new(1, 0) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(.2, 0), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(1.6, 2.8), Speed = NumberRange.new(1.5, 3.5), SpreadAngle = Vector2.new(25, 25),
			EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, 1.5, 0),
			Rate = math.clamp(area * .05, 4, 26), Enabled = false,
		})
		local foam = emitter(host, {
			Texture = SMOKE, Color = ColorSequence.new(HOLY_WHITE), LightEmission = .4,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, .8), NumberSequenceKeypoint.new(1, 2.4) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .35), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(.6, 1.1), Speed = NumberRange.new(.5, 2), SpreadAngle = Vector2.new(70, 70),
			EmissionDirection = Enum.NormalId.Top, Rate = math.clamp(area * .04, 3, 20), Enabled = false,
		})
		local light = Instance.new("PointLight")
		light.Color = HOLY_GOLD
		light.Range = math.clamp(math.max(water.Size.X, water.Size.Z) * .6, 10, 22)
		light.Brightness = 0
		light.Shadows = false
		light.Parent = host
		table.insert(entries, { host = host, emitters = { motes, foam }, light = light })
		if lightsOn then
			motes.Enabled, foam.Enabled = true, true
			tween(light, 1.2, { Brightness = 1.6 })
		end
	end
	return entries
end

local function startHoly(p, path, parent)
	stopHoly()
	local folder = Instance.new("Folder")
	folder.Name = "HolyFlood"
	folder.Parent = parent or Workspace
	local h = { folder = folder, emitters = {}, lights = {}, pending = {} }
	for i, index in ipairs(p.flowing or {}) do
		local isFinal = index == p.gate
		-- The final channel lights up as the wave front passes; the others once it's under way.
		local entries = dressWater(waterParts((p.channels or {})[i]), folder, false)
		for _, entry in ipairs(entries) do
			for _, e in ipairs(entry.emitters) do table.insert(h.emitters, e) end
			table.insert(h.lights, entry.light)
			local at = isFinal and path and pathFraction(path, entry.host.Position) or .35
			table.insert(h.pending, { entry = entry, at = at })
		end
	end
	holy = h
	-- Tear down when the stun ends, however the fight goes.
	local lasts = (tonumber(p.impactAt) or 0) + (tonumber(p.stunSeconds) or 12)
	task.delay(math.max(1, lasts - (serverNow() - (tonumber(p.startsAt) or serverNow()))), function()
		if holy == h then stopHoly() end
	end)
	return h
end

local function lightPending(h, waveU)
	if not h then return end
	for i = #h.pending, 1, -1 do
		local item = h.pending[i]
		if waveU >= item.at then
			table.remove(h.pending, i)
			for _, e in ipairs(item.entry.emitters) do e.Enabled = true end
			tween(item.entry.light, .8, { Brightness = 1.6 })
		end
	end
end

----------------------------------------------------------------------
-- Overlay
----------------------------------------------------------------------

local function buildOverlay()
	local gui = Instance.new("ScreenGui")
	gui.Name = "MiasmaPureWaterCutscene"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 950
	local function bar(anchorY)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0, anchorY)
		f.Position = UDim2.fromScale(0, anchorY)
		f.Size = UDim2.fromScale(1, 0)
		f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.BorderSizePixel = 0
		f.ZIndex = 5
		f.Parent = gui
		return f
	end
	local top, bottom = bar(0), bar(1)
	local fade = Instance.new("Frame")
	fade.Size = UDim2.fromScale(1, 1)
	fade.BackgroundColor3 = Color3.new(0, 0, 0)
	fade.BackgroundTransparency = 1
	fade.BorderSizePixel = 0
	fade.ZIndex = 10
	fade.Parent = gui
	local flash = fade:Clone()
	flash.BackgroundColor3 = HOLY_WHITE
	flash.ZIndex = 9
	flash.Parent = gui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return { gui = gui, top = top, bottom = bottom, fade = fade, flash = flash }
end

----------------------------------------------------------------------
-- Impact
----------------------------------------------------------------------

local function impact(state)
	local centre = state.centre
	local folder = state.folder
	tween(state.overlay.flash, .05, { BackgroundTransparency = .25 })
	task.delay(.06, function() tween(state.overlay.flash, .6, { BackgroundTransparency = 1 }) end)
	ArenaShake.Shake({ amplitude = .9, rotation = 1, duration = .15, rampIn = 0, decay = .7, frequency = 16 })
	-- Shockwave ring racing out across the floor.
	local ring = part({ Name = "HolyRing", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = HOLY_WHITE,
		Transparency = .15, Size = Vector3.new(.4, 6, 6), CFrame = CFrame.new(state.floor) * CFrame.Angles(0, 0, math.pi / 2) }, folder)
	tween(ring, .9, { Size = Vector3.new(.4, 90, 90), Transparency = 1 })
	-- A pillar of light on Miasma.
	local pillar = part({ Name = "HolyPillar", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = HOLY_GOLD,
		Transparency = .2, Size = Vector3.new(80, 4, 4), CFrame = CFrame.new(state.floor + Vector3.new(0, 40, 0)) * CFrame.Angles(0, 0, math.pi / 2) }, folder)
	tween(pillar, .35, { Size = Vector3.new(80, 18, 18) })
	task.delay(.35, function() tween(pillar, 1.4, { Size = Vector3.new(80, 2, 2), Transparency = 1 }) end)
	local glow = Instance.new("PointLight")
	glow.Color, glow.Range, glow.Brightness, glow.Shadows = HOLY_WHITE, 60, 8, false
	glow.Parent = pillar
	tween(glow, 1.8, { Brightness = 0 })
	-- Splash of holy water off Miasma.
	local splashHost = part({ Name = "HolySplash", Transparency = 1, Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(centre + Vector3.new(0, 4, 0)) }, folder)
	local splash = emitter(splashHost, {
		Texture = SMOKE, Color = ColorSequence.new(HOLY_WHITE, WATER_BLUE), LightEmission = .6,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 9) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .15), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(.8, 1.4), Speed = NumberRange.new(20, 38), SpreadAngle = Vector2.new(70, 70),
		EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, -30, 0), Rate = 0,
	})
	local sparks = emitter(splashHost, {
		Texture = SPARKLE, Color = ColorSequence.new(HOLY_WHITE, HOLY_GOLD), LightEmission = 1, LightInfluence = 0,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(1, 2), Speed = NumberRange.new(10, 26), SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -4, 0), Rate = 0,
	})
	splash:Emit(70)
	sparks:Emit(90)
end

----------------------------------------------------------------------
-- Play / Stop
----------------------------------------------------------------------

local function finish(state, instant)
	if state.finished then return end
	state.finished = true
	pcall(function() RunService:UnbindFromRenderStep(RENDER_NAME) end)
	local camera = Workspace.CurrentCamera
	if camera then camera.FieldOfView = state.prevFov end
	local character = Players.LocalPlayer.Character
	local head = character and character:FindFirstChild("Head")
	if head then CameraOverrideState.RequestLook(state.centre + Vector3.new(0, 6, 0) - head.Position) end
	CameraOverrideState.SetActive(false)
	if state.releaseHud then state.releaseHud() end
	if active == state then active = nil end
	if state.wave then state.wave:Destroy() end
	local overlay = state.overlay
	if instant then
		overlay.gui:Destroy()
		return
	end
	tween(overlay.top, FADE_OUT, { Size = UDim2.fromScale(1, 0) })
	tween(overlay.bottom, FADE_OUT, { Size = UDim2.fromScale(1, 0) })
	tween(overlay.fade, FADE_OUT, { BackgroundTransparency = 1 })
	task.delay(FADE_OUT + .05, function() overlay.gui:Destroy() end)
end

function Cutscene.Stop()
	if active then finish(active, true) end
	stopHoly()
end

function Cutscene.Play(p, parent)
	if active then finish(active, true) end
	if type(p) ~= "table" or typeof(p.centre) ~= "Vector3" or typeof(p.gatePosition) ~= "Vector3" then return end
	local startsAt, duration = tonumber(p.startsAt), tonumber(p.duration)
	local impactAt = tonumber(p.impactAt) or 3.3
	if not startsAt or not duration then return end
	local camera = Workspace.CurrentCamera
	if not camera then return end

	-- The final gate's channel, for the wave's route.
	local finalWater = {}
	for i, index in ipairs(p.flowing or {}) do
		if index == p.gate then finalWater = waterParts((p.channels or {})[i]) end
	end
	local path = buildPath(finalWater, p.gatePosition, p.centre)
	startHoly(p, path, parent)
	if serverNow() - startsAt >= duration then return end -- joined too late for the cutscene itself

	local folder = Instance.new("Folder")
	folder.Name = "PureWaterCutscene"
	folder.Parent = parent or Workspace
	local centre = p.centre
	local floorY = path.points[#path.points].Y
	local state = {
		finished = false, prevFov = camera.FieldOfView, overlay = buildOverlay(), folder = folder,
		centre = centre, floor = Vector3.new(centre.X, floorY, centre.Z), impacted = false,
	}
	active = state
	state.releaseHud = HudHider.Acquire(state.overlay.gui)
	task.delay(duration + 3, function() folder:Destroy() end)

	-- The flood's wave front: a bright glowing crest trailing foam and light.
	local wave = part({ Name = "FloodWave", Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = WATER_BLUE,
		Transparency = .3, Size = Vector3.new(7, 7, 7), CFrame = CFrame.new(path.points[1]) }, folder)
	state.wave = wave
	local crestLight = Instance.new("PointLight")
	crestLight.Color, crestLight.Range, crestLight.Brightness, crestLight.Shadows = HOLY_WHITE, 26, 3.5, false
	crestLight.Parent = wave
	emitter(wave, {
		Texture = SMOKE, Color = ColorSequence.new(HOLY_WHITE, WATER_BLUE), LightEmission = .5,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 7) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .2), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(.5, .9), Speed = NumberRange.new(6, 14), SpreadAngle = Vector2.new(60, 60),
		EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, -12, 0), Rate = 60,
	})
	emitter(wave, {
		Texture = SPARKLE, Color = ColorSequence.new(HOLY_WHITE, HOLY_GOLD), LightEmission = 1, LightInfluence = 0,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(.8, 1.6), Speed = NumberRange.new(2, 6), SpreadAngle = Vector2.new(180, 180), Rate = 40,
	})
	-- White water bursting out of the gate.
	local burstHost = part({ Name = "GateBurst", Transparency = 1, Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(path.points[1] + Vector3.new(0, 3, 0)) }, folder)
	local burst = emitter(burstHost, {
		Texture = SMOKE, Color = ColorSequence.new(HOLY_WHITE, WATER_BLUE), LightEmission = .4,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 10) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .1), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(.9, 1.5), Speed = NumberRange.new(14, 26), SpreadAngle = Vector2.new(35, 35),
		EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, -26, 0), Rate = 90,
	})
	task.delay(math.max(0, WAVE_START + .8 - (serverNow() - startsAt)), function() burst.Enabled = false end)

	-- Camera frame.
	local gatePoint = path.points[1]
	local dir = flat(centre - gatePoint)
	dir = dir.Magnitude > .01 and dir.Unit or Vector3.new(0, 0, -1)
	local side = dir:Cross(Vector3.yAxis)
	local up = Vector3.yAxis
	local function shotGate()
		return gatePoint + dir * 15 + side * 7 + up * 7, gatePoint + up * 4
	end
	local function shotWave(u)
		local w = pathAt(path, u)
		return w - dir * 13 + side * 4 + up * 9, w + dir * 12 + up * 1
	end
	local function shotImpact(k)
		local back = 30 - 5 * smooth(k)
		return state.floor - dir * back + side * 9 + up * 12, state.floor + up * 7
	end

	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = FOV
	CameraOverrideState.SetActive(true)
	tween(state.overlay.top, .4, { Size = UDim2.fromScale(1, LETTERBOX) })
	tween(state.overlay.bottom, .4, { Size = UDim2.fromScale(1, LETTERBOX) })

	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, function()
		if state.finished then return end
		local t = serverNow() - startsAt
		if t >= duration then finish(state, false) return end
		-- The wave leaves the gate a little before shot 2 and reaches Miasma exactly at impact.
		local waveU = math.clamp((t - (WAVE_START - .4)) / (impactAt - (WAVE_START - .4)), 0, 1)
		local w = pathAt(path, waveU)
		wave.CFrame = CFrame.new(w + Vector3.new(0, 1.5, 0))
		wave.Transparency = (waveU >= 1) and 1 or .3
		lightPending(holy, waveU)
		if t >= impactAt and not state.impacted then
			state.impacted = true
			impact(state)
		end

		local eye, look
		local e1, l1 = shotGate()
		local e2, l2 = shotWave(waveU)
		local e3, l3 = shotImpact((t - impactAt) / math.max(duration - impactAt, .1))
		local toWave = smooth((t - (WAVE_START - .3)) / .6)
		eye, look = e1:Lerp(e2, toWave), l1:Lerp(l2, toWave)
		local toImpact = smooth((t - (impactAt - .45)) / .6)
		eye, look = eye:Lerp(e3, toImpact), look:Lerp(l3, toImpact)
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = CFrame.lookAt(eye, look)
		if not state.fading and t >= duration - FADE_OUT then
			state.fading = true
			tween(state.overlay.fade, FADE_OUT, { BackgroundTransparency = 0 })
		end
	end)
end

return Cutscene
