--[[
	MiasmaEntranceCutscene -- the boss room's opening, for every member of the party (client).

		Cutscene.Play(payload, parent)   -- the "EntranceCutscene" presentation
		Cutscene.Stop()                  -- immediate (fight failed / encounter gone)

	It teaches the room before the fight: where the poisonous slimes come from, the pressure plate,
	the valve, the altars that cleanse poison, then the gate shuts behind the party and phase 1 starts
	at once. Holding Space votes to skip it (the server skips when every living member is holding).

	payload (server, MiasmaEncounterController:BeginEntranceCutscene): startsAt, duration, times
	(MiasmaEncounterConfig.EntranceCutscene), plate, wheel (world positions of the nearest valve
	station's plate and wheel), tablet / plateGlow / station (the station's instances, may be nil),
	altar (a cleansing altar), drains (the four outfall pipes: { mouth, pool, dir }), drainShow (which one the
	camera visits), seal (the gate), centre (the arena centre).

	Shots, every one timed off the server clock so the whole party sees the same moment:
	  0  a poison outfall pipe: slimes swell in its mouth, strain, and drop out down the poison stream
	     to the pool (staged blobs, two a pipe; the real ones are spawned by the server when
	     phase 1 starts, 4 per member, and fall from the same pipes: Cutscene.DropSlimes)
	  1  the camera sweeps to the pressure plate
	  2  a boulder lets go of the ceiling and shatters on the plate: dust, shake, the plate lights
	  3  the camera pushes in on the rune tablet beside it: its runes light up (a SAMPLE pattern:
	     the real one is rolled later and is never sent to anyone)
	  4  the camera swings to the valve wheel, which glows
	  4b a cleansing altar lights up: poison is cleansed there
	  5  the camera swings back to the entrance as the gate slides shut behind the party (the server
	     moves the gate and closes its collision; this adds the dust, shake and sound)
	Then a quick fade, and control returns facing the arena.

	Everything local is put back as it was (plate colour, tablet light) when it ends.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CameraOverrideState = require(ReplicatedStorage:WaitForChild("CameraOverrideState"))
local SfxService = require(ReplicatedStorage:WaitForChild("SfxService"))
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local RuneArt = require(ReplicatedStorage:WaitForChild("MiasmaRuneArt"))
local HudHider = require(script.Parent:WaitForChild("HudHider"))
local ArenaShake = require(script.Parent:WaitForChild("ArenaShake"))
local CeilingDebris = require(script.Parent:WaitForChild("CeilingDebrisFX"))

local Cutscene = {}

local RENDER_NAME = "MiasmaEntranceCutscene"
local FOV = 58
local LETTERBOX = .1
local FADE_OUT = .4
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local DUST = Color3.fromRGB(150, 140, 126)
local ROCK = Color3.fromRGB(104, 98, 90)
local PLATE_LIT = Color3.fromRGB(110, 235, 160)
local RUNE_LIT = Color3.fromRGB(214, 244, 214)
local RUNE_GLOW = Color3.fromRGB(96, 230, 150)
local SAMPLE_RUNES = { "Eye", "Crown", "Moon" }
local ROCK_HEIGHT = 58   -- studs above the plate the boulder lets go from
local FRAGMENTS = 9
local SLIME = Color3.fromRGB(112, 70, 150)
local SLIME_LIGHT = Color3.fromRGB(170, 120, 205)
local GOO = Color3.fromRGB(96, 214, 84)
local ALTAR_GLOW = Color3.fromRGB(150, 255, 200)
local SLIMES_PER_DRAIN = 2
local CAPTION_COLOR = Color3.fromRGB(235, 228, 205)

local skipSender -- fn(held), set by MiasmaEncounterClient: sends the Space-hold vote to the server

local active

local function serverNow() return Workspace:GetServerTimeNow() end
local function smooth(u) u = math.clamp(u, 0, 1); return u * u * (3 - 2 * u) end
local function flat(v) return Vector3.new(v.X, 0, v.Z) end
local function unitOr(v, fallback)
	return v.Magnitude > .01 and v.Unit or fallback
end

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

local function sound(key, position, volume)
	SfxService.PlayEffect(key, {
		Position = position, Volume = volume or .9, RollOffMinDistance = 50, RollOffMaxDistance = 400,
	})
end

-- A puff of dust at `position`, `count` particles, spread over `spread` studs.
local function dust(folder, position, count, spread, size)
	local host = part({ Name = "Dust", Transparency = 1, Size = Vector3.new(spread or 1, 1, spread or 1), CFrame = CFrame.new(position) }, folder)
	local e = emitter(host, {
		Texture = SMOKE, Color = ColorSequence.new(DUST), LightEmission = 0, LightInfluence = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, (size or 3) * .6), NumberSequenceKeypoint.new(1, (size or 3) * 2.2) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .25), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(.9, 1.7), Speed = NumberRange.new(6, 16), SpreadAngle = Vector2.new(75, 75),
		EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, -4, 0), Rate = 0,
		Shape = Enum.ParticleEmitterShape.Box,
	})
	e:Emit(count)
	task.delay(2.5, function() host:Destroy() end)
end

----------------------------------------------------------------------
-- Overlay (letterbox + fade), the same as the other Miasma cutscenes
----------------------------------------------------------------------

local function buildOverlay()
	local gui = Instance.new("ScreenGui")
	gui.Name = "MiasmaEntranceCutscene"
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
	-- The caption sits just above the bottom bar.
	local caption = Instance.new("TextLabel")
	caption.AnchorPoint = Vector2.new(.5, 1)
	caption.Position = UDim2.fromScale(.5, .86)
	caption.Size = UDim2.fromScale(.7, .06)
	caption.BackgroundTransparency = 1
	caption.FontFace = UIFonts.SerifBold
	caption.TextScaled = true
	caption.TextColor3 = CAPTION_COLOR
	caption.Text = ""
	caption.TextTransparency = 1
	caption.ZIndex = 6
	local captionStroke = Instance.new("UIStroke")
	captionStroke.Color = Color3.fromRGB(10, 8, 6)
	captionStroke.Thickness = 2.5
	captionStroke.Transparency = 1
	captionStroke.Parent = caption
	caption.Parent = gui
	-- The skip prompt (bottom right): "Hold SPACE to skip", a fill bar, and how many are holding.
	local skip = Instance.new("Frame")
	skip.AnchorPoint = Vector2.new(1, 1)
	skip.Position = UDim2.new(.985, 0, .975, 0)
	skip.Size = UDim2.fromOffset(250, 46)
	skip.BackgroundColor3 = Color3.fromRGB(20, 17, 14)
	skip.BackgroundTransparency = .35
	skip.BorderSizePixel = 0
	skip.ZIndex = 7
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = skip
	local skipText = Instance.new("TextLabel")
	skipText.BackgroundTransparency = 1
	skipText.Position = UDim2.fromOffset(10, 4)
	skipText.Size = UDim2.new(1, -20, 0, 22)
	skipText.FontFace = UIFonts.SerifBold
	skipText.TextSize = 17
	skipText.TextColor3 = CAPTION_COLOR
	skipText.TextXAlignment = Enum.TextXAlignment.Left
	skipText.Text = "Hold SPACE to skip"
	skipText.ZIndex = 8
	skipText.Parent = skip
	local barBack = Instance.new("Frame")
	barBack.Position = UDim2.fromOffset(10, 31)
	barBack.Size = UDim2.new(1, -20, 0, 6)
	barBack.BackgroundColor3 = Color3.fromRGB(60, 54, 46)
	barBack.BorderSizePixel = 0
	barBack.ZIndex = 8
	barBack.Parent = skip
	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.fromScale(0, 1)
	barFill.BackgroundColor3 = Color3.fromRGB(110, 235, 160)
	barFill.BorderSizePixel = 0
	barFill.ZIndex = 9
	barFill.Parent = barBack
	skip.Parent = gui
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return { gui = gui, top = top, bottom = bottom, fade = fade, caption = caption, captionStroke = captionStroke, skipText = skipText, skipFill = barFill }
end

----------------------------------------------------------------------
-- Moments
----------------------------------------------------------------------

-- The boulder: lets go of the ceiling above the plate, falls, shatters on it.
local function buildRock(state)
	local rock = part({
		Name = "EntranceBoulder", Material = Enum.Material.Slate, Color = ROCK, Size = Vector3.new(4.6, 3.6, 5),
		CFrame = CFrame.new(state.plate + Vector3.new(0, ROCK_HEIGHT, 0)), Transparency = 1,
	}, state.folder)
	state.rock = rock
	state.rockTrail = emitter(rock, {
		Texture = SMOKE, Color = ColorSequence.new(DUST), LightEmission = 0, LightInfluence = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.2), NumberSequenceKeypoint.new(1, 5) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .35), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(.5, .9), Speed = NumberRange.new(1, 4), SpreadAngle = Vector2.new(180, 180), Rate = 0,
	})
	state.fragments = {}
	for i = 1, FRAGMENTS do
		state.fragments[i] = part({
			Name = "Fragment", Material = Enum.Material.Slate, Color = ROCK, Transparency = 1,
			Size = Vector3.new(.8 + math.random() * 1.2, .6 + math.random() * .9, .8 + math.random() * 1.1),
		}, state.folder)
	end
end

local function impactRock(state)
	local p = state.plate + Vector3.new(0, 1.5, 0)
	dust(state.folder, p, 45, 5, 3.4)
	CeilingDebris.Burst(state.plate, 6, 5, state.folder, .5)
	ArenaShake.Shake({ amplitude = .7, rotation = .7, duration = .25, rampIn = 0, decay = .6, frequency = 18, focus = state.plate })
	sound("EntranceRockImpact", state.plate, 1)
	-- The plate wakes: it is what reveals the tablet in the real fight.
	if state.plateGlow then
		state.plateOld = state.plateOld or { Color = state.plateGlow.Color, Transparency = state.plateGlow.Transparency }
		tween(state.plateGlow, .25, { Color = PLATE_LIT, Transparency = .1 })
	end
	state.shatterAt = serverNow()
	for i, frag in ipairs(state.fragments) do
		local angle = (i / FRAGMENTS) * math.pi * 2 + math.random() * .5
		frag.Transparency = 0
		frag:SetAttribute("Vx", math.cos(angle) * (6 + math.random() * 7))
		frag:SetAttribute("Vz", math.sin(angle) * (6 + math.random() * 7))
		frag:SetAttribute("Vy", 9 + math.random() * 9)
		frag.CFrame = CFrame.new(state.plate + Vector3.new(0, 2, 0))
	end
end

local function lightTablet(state)
	local tablet = state.tablet
	if typeof(tablet) ~= "Instance" or not tablet.Parent then return end
	sound("EntranceRune", tablet.Position, .9)
	local gui = tablet:FindFirstChild("RuneTabletGui")
	local light = tablet:FindFirstChild("RuneLight")
	if light then light.Enabled = true end
	if gui then
		gui.LightInfluence = 0
		local holder = Instance.new("Frame")
		holder.Name = "CutsceneRunes"
		holder.BackgroundTransparency = 1
		holder.AnchorPoint = Vector2.new(.5, .5)
		holder.Position = UDim2.fromScale(.5, .52)
		holder.Size = UDim2.fromScale(.9, .8)
		local layout = Instance.new("UIGridLayout")
		layout.CellSize = UDim2.fromScale(.3, .8)
		layout.CellPadding = UDim2.fromScale(.05, .05)
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = holder
		for index, id in ipairs(SAMPLE_RUNES) do
			local slot = Instance.new("Frame")
			slot.LayoutOrder = index
			slot.BackgroundColor3 = Color3.fromRGB(26, 28, 25)
			slot.BackgroundTransparency = .15
			slot.BorderSizePixel = 0
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(.12, 0)
			corner.Parent = slot
			local square = Instance.new("UIAspectRatioConstraint")
			square.AspectRatio = 1
			square.Parent = slot
			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.fromRGB(90, 150, 110)
			stroke.Thickness = 3
			stroke.Parent = slot
			local inner = Instance.new("Frame")
			inner.BackgroundTransparency = 1
			inner.AnchorPoint = Vector2.new(.5, .5)
			inner.Position = UDim2.fromScale(.5, .5)
			inner.Size = UDim2.fromScale(.78, .78)
			inner.Parent = slot
			RuneArt.Render(inner, id, { Color = RUNE_LIT, GlowColor = RUNE_GLOW, GlowTransparency = .72, Thickness = .09 })
			slot.Parent = holder
		end
		holder.Parent = gui
		state.runes = holder
	end
	state.tabletLit = true
end

local function glowValve(state)
	sound("EntranceValve", state.wheel, .9)
	local host = part({ Name = "ValveGlow", Transparency = 1, Size = Vector3.one, CFrame = CFrame.new(state.wheel) }, state.folder)
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness, light.Shadows = RUNE_GLOW, 22, 0, false
	light.Parent = host
	tween(light, .35, { Brightness = 4 })
	task.delay(.5, function() tween(light, 1.6, { Brightness = .6 }) end)
	local sparks = emitter(host, {
		Texture = SPARKLE, Color = ColorSequence.new(RUNE_LIT, RUNE_GLOW), LightEmission = 1, LightInfluence = 0,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(.8, 1.6), Speed = NumberRange.new(3, 9), SpreadAngle = Vector2.new(180, 180), Rate = 0,
	})
	sparks:Emit(40)
end

local function slamGate(state)
	sound("EntranceGateSlam", state.seal, 1)
	ArenaShake.Shake({ amplitude = 1.1, rotation = 1, duration = .35, rampIn = 0, decay = .7, frequency = 14, focus = state.seal })
	local floor = Vector3.new(state.seal.X, state.floorY, state.seal.Z)
	local across = unitOr(flat(state.centre - state.seal):Cross(Vector3.yAxis), Vector3.xAxis)
	for _, offset in ipairs({ -9, 0, 9 }) do
		dust(state.folder, floor + across * offset + Vector3.new(0, 1, 0), 30, 6, 4)
	end
end

-- The staged slimes at the outfall pipes: two a pipe, each swelling in the mouth, straining, then
-- dropping out down the poison stream to the pool, splatting and rolling off to the side. Purely
-- visual; phase 1 spawns the real ones.
local FALL = 1.15 -- seconds from the mouth to the pool

local function slimeBody(folder)
	local body = part({
		Name = "StagedSlime", Shape = Enum.PartType.Ball, Material = Enum.Material.SmoothPlastic, Color = SLIME,
		Size = Vector3.one, Transparency = 1,
	}, folder)
	local blotch = part({
		Name = "Blotch", Shape = Enum.PartType.Ball, Material = Enum.Material.SmoothPlastic, Color = SLIME_LIGHT,
		Size = Vector3.one, Transparency = 1,
	}, folder)
	local goo = emitter(body, {
		Texture = SMOKE, Color = ColorSequence.new(GOO, SLIME), LightEmission = .3, LightInfluence = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, .8), NumberSequenceKeypoint.new(1, 2) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .3), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(.5, .9), Speed = NumberRange.new(2, 6), SpreadAngle = Vector2.new(70, 70),
		EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, -14, 0), Rate = 0,
	})
	return body, blotch, goo
end

local function buildSlimes(state)
	state.slimes = {}
	for _, drain in ipairs(state.drains) do
		local side = drain.dir:Cross(Vector3.yAxis)
		for k = 1, SLIMES_PER_DRAIN do
			local body, blotch, goo = slimeBody(state.folder)
			table.insert(state.slimes, {
				body = body, blotch = blotch, goo = goo, drain = drain, k = k,
				rest = drain.pool + drain.dir * (3 + (k - 1) * 1.8) + side * ((k == 1) and -1.7 or 1.9),
				landed = false,
			})
		end
	end
end

local function updateSlimes(state, t)
	local times = state.times
	local up = Vector3.yAxis
	for _, slime in ipairs(state.slimes) do
		local drain, k = slime.drain, slime.k
		local lag = (k - 1) * .45
		local clogAt, pushAt, dropAt = times.DrainClog + lag * .5, times.DrainPush + lag * .3, times.DrainPlop + lag
		local landAt = dropAt + FALL
		local body, blotch = slime.body, slime.blotch
		local mouth, pool = drain.mouth, drain.pool
		if t < clogAt or t > times.DrainLeave + 5 then
			body.Transparency, blotch.Transparency = 1, 1
		elseif t < dropAt then
			-- Swelling in the pipe mouth, then straining: it hangs lower and stretches with each pulse.
			local swell = smooth((t - clogAt) / math.max(pushAt - clogAt, .1))
			local strain = t >= pushAt and (.5 + .5 * math.sin((t - pushAt) * 9)) or 0
			local s = .4 + .6 * swell
			local width, height = (3.4 + strain * .4) * s, (3 + strain * 1.4) * s
			body.Size = Vector3.new(width, height, width)
			body.CFrame = CFrame.new(mouth - up * (.2 + height * .4 + strain * .5))
			body.Transparency = 0
			blotch.Size = Vector3.new(width * .35, height * .25, width * .35)
			blotch.CFrame = CFrame.new(body.Position + up * (height * .28) + drain.dir * (width * .22))
			blotch.Transparency = 0
			slime.goo.Rate = t >= pushAt and 16 or 0
		elseif t < landAt then
			-- Falling down the stream, stretching as it speeds up.
			local u = (t - dropAt) / FALL
			local drop = mouth:Lerp(pool, u * u) - up * .6
			local stretch = 1 + u * .5
			body.Size = Vector3.new(3 / math.sqrt(stretch), 3 * stretch, 3 / math.sqrt(stretch))
			body.CFrame = CFrame.new(drop + up * 1.2)
			body.Transparency = 0
			blotch.Size = Vector3.new(1, 1, 1)
			blotch.CFrame = CFrame.new(body.Position + up * (body.Size.Y * .3))
			blotch.Transparency = 0
			slime.goo.Rate = 0
		else
			-- The splat, then it rolls off the pool and settles beside it.
			local since = t - landAt
			local roll = smooth(since / .7)
			local squash = 1 - .4 * math.sin(math.clamp(since / .45, 0, 1) * math.pi) * (1 - math.clamp(since / .45, 0, 1) * .3)
			local wobble = 1 + .05 * math.sin(since * 5 + k)
			local pos = pool:Lerp(slime.rest, roll) + up * (1.2 * squash + 1.5 * math.sin(roll * math.pi) * .5)
			body.Size = Vector3.new(3.6 * wobble / squash ^ .5, 2.6 * squash, 3.6 * wobble / squash ^ .5)
			body.CFrame = CFrame.new(pos)
			body.Transparency = 0
			blotch.Size = Vector3.new(1.2, .8, 1.2)
			blotch.CFrame = CFrame.new(body.Position + up * (body.Size.Y * .38))
			blotch.Transparency = 0
			if not slime.landed then
				slime.landed = true
				slime.goo:Emit(24)
				sound("EntrancePlop", pool, .9)
			end
		end
	end
end

-- Phase 1 begins: the server drops the real slimes out of the pipes (Presentation "SlimeDrop",
-- `fall` seconds before they appear in the pool). This draws the fall: a few blobs a pipe, down the
-- stream, a splat, gone as the real ones arrive.
function Cutscene.DropSlimes(p, parent)
	if type(p) ~= "table" or type(p.drains) ~= "table" then return end
	local fall = tonumber(p.fall) or 1.1
	local perDrain = math.clamp(math.floor(tonumber(p.perDrain) or 1), 1, 3)
	local folder = Instance.new("Folder")
	folder.Name = "SlimeDrop"
	folder.Parent = parent or Workspace
	local blobs = {}
	for _, drain in ipairs(p.drains) do
		if typeof(drain.mouth) == "Vector3" and typeof(drain.pool) == "Vector3" then
			for k = 1, perDrain do
				local body, blotch, goo = slimeBody(folder)
				table.insert(blobs, { body = body, blotch = blotch, goo = goo, drain = drain, delay = (k - 1) * .12 * fall, landed = false })
			end
		end
	end
	local started = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local now = os.clock() - started
		for _, blob in ipairs(blobs) do
			local u = math.clamp((now - blob.delay) / (fall * .78), 0, 1)
			if u <= 0 or now > fall + .2 then
				blob.body.Transparency, blob.blotch.Transparency = 1, 1
			else
				local up = Vector3.yAxis
				local pos = blob.drain.mouth:Lerp(blob.drain.pool, u * u) + up * 1
				local stretch = 1 + u * .5
				blob.body.Size = Vector3.new(2.8 / math.sqrt(stretch), 2.8 * stretch, 2.8 / math.sqrt(stretch))
				blob.body.CFrame = CFrame.new(pos)
				blob.body.Transparency = u >= 1 and .5 or 0
				blob.blotch.Size = Vector3.one * .9
				blob.blotch.CFrame = CFrame.new(pos + up * (blob.body.Size.Y * .3))
				blob.blotch.Transparency = u >= 1 and .5 or 0
				if u >= 1 and not blob.landed then
					blob.landed = true
					blob.goo:Emit(20)
					sound("EntrancePlop", blob.drain.pool, .8)
				end
			end
		end
	end)
	task.delay(fall + 1.2, function()
		connection:Disconnect()
		folder:Destroy()
	end)
end

-- The altar lights up: a column of pale light and a ring of sparks, held until the camera leaves.
local function glowAltar(state)
	sound("EntranceAltar", state.altar, .9)
	local host = part({ Name = "AltarGlow", Transparency = 1, Size = Vector3.one, CFrame = CFrame.new(state.altar + Vector3.new(0, 3, 0)) }, state.folder)
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness, light.Shadows = ALTAR_GLOW, 26, 0, false
	light.Parent = host
	tween(light, .5, { Brightness = 4 })
	local column = part({
		Name = "AltarColumn", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = ALTAR_GLOW,
		Size = Vector3.new(34, .6, .6), Transparency = .3,
		CFrame = CFrame.new(state.altar + Vector3.new(0, 17, 0)) * CFrame.Angles(0, 0, math.pi / 2),
	}, state.folder)
	tween(column, 1.2, { Size = Vector3.new(34, 3.2, 3.2), Transparency = .72 }, Enum.EasingStyle.Sine)
	state.altarSparks = emitter(host, {
		Texture = SPARKLE, Color = ColorSequence.new(Color3.new(1, 1, 1), ALTAR_GLOW), LightEmission = 1, LightInfluence = 0,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(1.2, 2.2), Speed = NumberRange.new(2, 6), SpreadAngle = Vector2.new(25, 25),
		EmissionDirection = Enum.NormalId.Top, Rate = 30,
		Shape = Enum.ParticleEmitterShape.Cylinder, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
	})
	state.altarSparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
end

----------------------------------------------------------------------
-- Camera
----------------------------------------------------------------------

-- The camera's key poses, in order: { time, eye, look }. Between two keys it eases; a key
-- repeated with the same pose is a hold.
local function buildKeys(state, p, from)
	local times = p.times
	local up = Vector3.yAxis
	local toRoom = unitOr(flat(state.centre - state.plate), Vector3.new(0, 0, -1))
	local side = toRoom:Cross(up)
	local plateEye, plateLook = state.plate + toRoom * 17 + side * 7 + up * 9, state.plate + up * 9

	local tabletEye, tabletLook
	if typeof(state.tablet) == "Instance" and state.tablet:IsA("BasePart") then
		local normal = state.tablet.CFrame.RightVector -- the tablet's face is its Right surface
		tabletLook = state.tablet.Position
		tabletEye = tabletLook + normal * 9 + up * .5
	else
		tabletEye, tabletLook = state.plate + toRoom * 11 + up * 4, state.plate + up * 4
	end

	local roomOfStation = toRoom
	if typeof(state.station) == "Instance" and state.station:IsA("Model") and state.station.PrimaryPart then
		roomOfStation = unitOr(flat(-state.station.PrimaryPart.CFrame.LookVector), toRoom) -- the station faces the wall
	end
	local valveEye = state.wheel + roomOfStation * 12 + roomOfStation:Cross(up) * 3.5 + up * 2
	local valveLook = state.wheel

	local inward = unitOr(flat(state.centre - state.seal), Vector3.new(0, 0, -1))
	local gateSide = inward:Cross(up)
	local seal = Vector3.new(state.seal.X, state.floorY, state.seal.Z)
	local gateEye, gateLook = seal + inward * 30 + gateSide * 8 + up * 9, seal + up * 10

	-- The drain shot: wide on the pipe and its stream, pushing in on the pipe mouth, then following the
	-- fall down to the pool.
	local drain = state.drains[state.drainShow]
	local drainSide = drain.dir:Cross(up)
	local drainWide, drainWideLook = drain.pool + drain.dir * 24 + drainSide * 5 + up * 17, drain.mouth - up * 6
	local drainTight, drainTightLook = drain.mouth + drain.dir * 11 + drainSide * 3 - up * 3, drain.mouth - up * 1.2
	local drainPool, drainPoolLook = drain.pool + drain.dir * 15 + drainSide * 4 + up * 6.5, drain.pool + up * 3.5

	-- The altar shot, from the room side of it.
	local altarToRoom = unitOr(flat(state.centre - state.altar), toRoom)
	local altarEye, altarLook = state.altar + altarToRoom * 15 + altarToRoom:Cross(up) * 5 + up * 7, state.altar + up * 4

	local startLook = from.Position + from.LookVector * 30
	return {
		{ 0, from.Position, startLook },
		{ times.DrainArrive, drainWide, drainWideLook },
		{ times.DrainPush, drainTight, drainTightLook },
		{ times.DrainPlop, drainTight, drainTightLook },
		{ times.DrainLeave, drainPool, drainPoolLook },
		{ times.PlateArrive, plateEye, plateLook },
		{ times.TabletStart, plateEye, plateLook },
		{ times.TabletArrive, tabletEye, tabletLook },
		{ times.TabletLeave, tabletEye, tabletLook },
		{ times.ValveArrive, valveEye, valveLook },
		{ times.ValveLeave, valveEye, valveLook },
		{ times.AltarArrive, altarEye, altarLook },
		{ times.AltarLeave, altarEye, altarLook },
		{ times.BackArrive, gateEye, gateLook },
		{ p.duration, gateEye, gateLook },
	}
end

local function poseAt(keys, t)
	if t <= keys[1][1] then return keys[1][2], keys[1][3] end
	for i = 2, #keys do
		local a, b = keys[i - 1], keys[i]
		if t <= b[1] then
			local u = smooth((t - a[1]) / math.max(b[1] - a[1], 1e-3))
			return a[2]:Lerp(b[2], u), a[3]:Lerp(b[3], u)
		end
	end
	local last = keys[#keys]
	return last[2], last[3]
end

----------------------------------------------------------------------
-- Play / Stop
----------------------------------------------------------------------

local function restore(state)
	if state.plateGlow and state.plateGlow.Parent and state.plateOld then
		tween(state.plateGlow, .4, state.plateOld)
	end
	if typeof(state.tablet) == "Instance" and state.tablet.Parent then
		local light = state.tablet:FindFirstChild("RuneLight")
		local gui = state.tablet:FindFirstChild("RuneTabletGui")
		if light then light.Enabled = false end
		if gui then gui.LightInfluence = 1 end
	end
	if state.runes then state.runes:Destroy(); state.runes = nil end
end

local function finish(state, instant)
	if state.finished then return end
	state.finished = true
	if state.holding and skipSender then pcall(skipSender, false) end
	for _, connection in ipairs(state.connections or {}) do connection:Disconnect() end
	pcall(function() RunService:UnbindFromRenderStep(RENDER_NAME) end)
	local camera = Workspace.CurrentCamera
	if camera then camera.FieldOfView = state.prevFov end
	local character = Players.LocalPlayer.Character
	local head = character and character:FindFirstChild("Head")
	if head then CameraOverrideState.RequestLook(state.centre + Vector3.new(0, 6, 0) - head.Position) end
	CameraOverrideState.SetActive(false)
	if state.releaseHud then state.releaseHud() end
	if active == state then active = nil end
	restore(state)
	local overlay = state.overlay
	if instant then
		overlay.gui:Destroy()
		state.folder:Destroy()
		return
	end
	tween(overlay.top, FADE_OUT, { Size = UDim2.fromScale(1, 0) })
	tween(overlay.bottom, FADE_OUT, { Size = UDim2.fromScale(1, 0) })
	tween(overlay.fade, FADE_OUT, { BackgroundTransparency = 1 })
	task.delay(FADE_OUT + .05, function()
		overlay.gui:Destroy()
		state.folder:Destroy()
	end)
end

function Cutscene.Stop()
	if active then finish(active, true) end
end

-- MiasmaEncounterClient hands over how a Space-hold vote reaches the server.
function Cutscene.SetSkipSender(fn)
	skipSender = fn
end

-- "2 / 3 holding", from the server (Presentation EntranceSkipVotes).
function Cutscene.SetVotes(votes, needed)
	local state = active
	if not state then return end
	state.votes, state.needed = tonumber(votes) or 0, tonumber(needed) or 0
end

-- The server skipped the opening (everyone held Space): fade out like a normal ending.
function Cutscene.Skipped()
	if active then finish(active, false) end
end

function Cutscene.Play(p, parent)
	if active then finish(active, true) end
	if type(p) ~= "table" or type(p.times) ~= "table" then return end
	if typeof(p.plate) ~= "Vector3" or typeof(p.wheel) ~= "Vector3" or typeof(p.seal) ~= "Vector3" or typeof(p.centre) ~= "Vector3" then return end
	if typeof(p.altar) ~= "Vector3" or type(p.drains) ~= "table" or type(p.drains[tonumber(p.drainShow) or 1]) ~= "table" then return end
	local startsAt, duration = tonumber(p.startsAt), tonumber(p.duration)
	if not startsAt or not duration then return end
	local camera = Workspace.CurrentCamera
	if not camera then return end
	if serverNow() - startsAt >= duration then return end -- joined too late for it

	local folder = Instance.new("Folder")
	folder.Name = "EntranceCutscene"
	folder.Parent = parent or Workspace
	local times = p.times
	local state = {
		finished = false, prevFov = camera.FieldOfView, overlay = buildOverlay(), folder = folder,
		plate = p.plate, wheel = p.wheel, seal = p.seal, centre = p.centre,
		tablet = p.tablet, plateGlow = typeof(p.plateGlow) == "Instance" and p.plateGlow or nil, station = p.station,
		floorY = p.plate.Y - .3, fired = {}, times = times, altar = p.altar,
		drains = p.drains, drainShow = tonumber(p.drainShow) or 1, connections = {},
		votes = 0, needed = tonumber(p.partySize) or 0,
	}
	active = state
	state.releaseHud = HudHider.Acquire(state.overlay.gui)
	buildRock(state)
	buildSlimes(state)
	local keys = buildKeys(state, p, camera.CFrame)

	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = FOV
	CameraOverrideState.SetActive(true)
	tween(state.overlay.top, .4, { Size = UDim2.fromScale(1, LETTERBOX) })
	tween(state.overlay.bottom, .4, { Size = UDim2.fromScale(1, LETTERBOX) })

	-- Hold Space (or A on a gamepad) for SkipHold seconds to vote to skip; releasing withdraws it.
	local holdStart
	local function isSkipKey(input)
		return input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA
	end
	table.insert(state.connections, UserInputService.InputBegan:Connect(function(input)
		if isSkipKey(input) and not holdStart then holdStart = os.clock() end
	end))
	table.insert(state.connections, UserInputService.InputEnded:Connect(function(input)
		if isSkipKey(input) then
			holdStart = nil
			if state.holding then
				state.holding = false
				if skipSender then pcall(skipSender, false) end
			end
		end
	end))

	-- (start, end, text): the line shown across the bottom of the picture.
	local captions = {
		{ times.DrainArrive, times.DrainLeave, "Poisonous slimes crawl up out of the drains." },
		{ times.RockImpact, times.TabletLeave, "Stand on the pressure plate to read the runes." },
		{ times.ValveArrive, times.ValveLeave, "Turn the valves to stun Miasma." },
		{ times.AltarGlow, times.AltarLeave, "Cleanse poison at the altars." },
	}

	local function once(key, when, t, fn)
		if state.fired[key] or t < when then return end
		state.fired[key] = true
		if t - when < 1.2 then fn() end -- a late joiner skips a moment already long past
	end

	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, function()
		if state.finished then return end
		local t = serverNow() - startsAt
		if t >= duration then finish(state, false) return end

		-- The boulder: falls from release to impact (accelerating), tumbling, then shatters.
		local rock = state.rock
		if t >= times.RockRelease and t < times.RockImpact then
			local u = (t - times.RockRelease) / math.max(times.RockImpact - times.RockRelease, .1)
			local y = ROCK_HEIGHT * (1 - u * u) + 1.8
			rock.Transparency = 0
			rock.CFrame = CFrame.new(state.plate + Vector3.new(0, y, 0)) * CFrame.Angles(u * 2.6, u * 4.1, u * 1.7)
			state.rockTrail.Rate = 55
		else
			state.rockTrail.Rate = 0
			if t >= times.RockImpact then rock.Transparency = 1 end
		end
		once("rock", times.RockRelease, t, function() CeilingDebris.Burst(state.plate, 8, 4, folder, .6) end)
		once("impact", times.RockImpact, t, function() impactRock(state) end)
		once("runes", times.RunesLit, t, function() lightTablet(state) end)
		once("valve", times.ValveGlow, t, function() glowValve(state) end)
		once("altar", times.AltarGlow, t, function() glowAltar(state) end)
		if state.altarSparks and t >= times.AltarLeave then state.altarSparks.Rate = 0 end
		updateSlimes(state, t)

		-- The caption (fades in and out), the skip prompt and its vote count.
		local line, alpha = "", 1
		for _, c in ipairs(captions) do
			if t >= c[1] and t < c[2] then
				line = c[3]
				alpha = 1 - math.clamp(math.min((t - c[1]) / .4, (c[2] - t) / .4), 0, 1)
			end
		end
		if line ~= "" then state.overlay.caption.Text = line end
		-- Text and its outline fade together (the dark outline used to stay behind as a black smear).
		local captionAlpha = line ~= "" and alpha or 1
		state.overlay.caption.TextTransparency = captionAlpha
		state.overlay.captionStroke.Transparency = captionAlpha
		if holdStart and not state.holding then
			local progress = (os.clock() - holdStart) / math.max(times.SkipHold or .8, .1)
			state.overlay.skipFill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
			if progress >= 1 then
				state.holding = true
				if skipSender then pcall(skipSender, true) end
			end
		elseif not holdStart then
			state.overlay.skipFill.Size = UDim2.fromScale(0, 1)
		end
		state.overlay.skipText.Text = (state.holding and state.needed > 0)
			and ("Skipping... " .. state.votes .. " / " .. state.needed .. " holding")
			or (state.needed > 1 and ("Hold SPACE to skip (" .. state.votes .. " / " .. state.needed .. ")") or "Hold SPACE to skip")
		once("gateStart", times.GateStart, t, function() sound("EntranceGateGrind", state.seal, .9) end)
		once("slam", times.GateSlam, t, function() slamGate(state) end)

		-- The shattered fragments fly out and settle, then thin away.
		if state.shatterAt then
			local age = serverNow() - state.shatterAt
			for _, frag in ipairs(state.fragments) do
				local vx, vy, vz = frag:GetAttribute("Vx"), frag:GetAttribute("Vy"), frag:GetAttribute("Vz")
				if vx and age >= 0 and age < 2.2 then
					local y = math.max(vy * age - 22 * age * age * .5, -1.4)
					frag.CFrame = CFrame.new(state.plate + Vector3.new(vx * math.min(age, 1.1), 2 + y, vz * math.min(age, 1.1)))
						* CFrame.Angles(age * 3, age * 5, age * 2)
					frag.Transparency = age > 1.6 and math.clamp((age - 1.6) / .6, 0, 1) or 0
				elseif age >= 2.2 then
					frag.Transparency = 1
				end
			end
		end

		local eye, look = poseAt(keys, t)
		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = CFrame.lookAt(eye, look)
		if not state.fading and t >= duration - FADE_OUT then
			state.fading = true
			tween(state.overlay.fade, FADE_OUT, { BackgroundTransparency = 0 })
		end
	end)
end

return Cutscene
