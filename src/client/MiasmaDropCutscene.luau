--[[
	MiasmaDropCutscene -- the camera cutscene for Miasma's phase 1 -> 2 drop (client only).

	The server fires "BossDropCutscene" to every member with the drop's timeline in seconds from
	`startsAt` (server clock, so everyone's camera runs in step and latency is absorbed):
	bridgeStart, impact, roarStart, roarEnd, cardStart, endsAt. Timings and the lead-in live in
	MiasmaEncounterConfig.BossDropSequence (+ .Cutscene); this module only frames the shots.

	Shots (camera orbits a moving anchor; every key blends smoothly into the next):
	  1  roof      tight on the gloopy blob hanging from the ceiling, below it, looking up,
	               slowly pushing in while the lead-in plays.
	  2  fall      as it lets go, the camera sweeps around to face it and pulls all the way out,
	               tracking the falling body, so the whole transformation stays in frame.
	  3  landing   front-on, the full body, easing in through the squash and growth.
	  4  roar      pushes in low on the open mouth (MiasmaRoarFX's shake rides on top).
	Enrage mode (payload.mode = "enrage", from the "EnrageCutscene" presentation): the same
	machinery on the boss where it stands -- wide, push in as it rears up, pull back and orbit
	as it spews poison. No ceiling shots, no title card.

	  5  card      the title card (TitleCards art), staged like a Borderlands intro: the frame
	               FREEZES (camera holds, the world behind goes desaturated + blurred), a white hit
	               flash, a dark diagonal band whips in, the card SLAMS in oversized and tilted,
	               settles with a jolt (shake), then creeps slowly larger while it holds. The
	               sting, the roar and phase 2's music all land with it.
	Then a quick fade to black, control goes back to the player's own camera (turned to face
	Miasma, via CameraOverrideState.RequestLook), and the fade lifts.

	Sizes come from the boss's own mesh (width W, height H), so a resize keeps the framing.
	Cinematic letterbox bars cover the HUD edges while it runs.

	  Cutscene.Play(payload)   Cutscene.Stop()
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CameraOverrideState = require(ReplicatedStorage:WaitForChild("CameraOverrideState"))
local HudHider = require(script.Parent:WaitForChild("HudHider"))
local SfxService = require(ReplicatedStorage:WaitForChild("SfxService"))
local MobData = require(ReplicatedStorage:WaitForChild("MobData"))
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local TitleCards = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images"):WaitForChild("TitleCards"))
local SoundEffects = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Sounds"):WaitForChild("SoundEffects"))
local MobAnimConfig = require(ReplicatedStorage:WaitForChild("MobAnimConfig"))
local EncounterConfig = require(ReplicatedStorage:WaitForChild("MiasmaEncounterConfig"))
local ContentProvider = game:GetService("ContentProvider")

local Cutscene = {}

-- The drop's boss clips, as the server resolves them (DungeonBossMobClass:_getExtraTrack).
local function clipId(mobId, key)
	local cfg = MobAnimConfig[mobId]
	return (cfg and cfg[key]) or EncounterConfig.Animations[key]
end

-- The server reveals the body the moment ITS copy of CeilingToBody passes SwapStart. A client
-- that has never played the clip fetches it only then, and until it arrives the rig stands in
-- its rest pose on the floor: one frame of Miasma "already landed" while it is still on the
-- ceiling. So: fetch the clips at client start, and (holdUntilPosed) keep the body hidden
-- locally until this client's own animator is really playing them.
task.spawn(function()
	local anims = {}
	for _, key in ipairs({ "CeilingToBody", "LandingSlam" }) do
		local id = clipId("MiasmaBoss", key)
		if id then
			local anim = Instance.new("Animation")
			anim.AnimationId = id
			table.insert(anims, anim)
		end
	end
	pcall(function() ContentProvider:PreloadAsync(anims) end)
end)

-- Hides the boss for this client (LocalTransparencyModifier, over whatever the server sets)
-- until its animator is playing CeilingToBody past SwapStart or LandingSlam, or `deadline`
-- (server time) passes. Returns the release function (idempotent).
local function holdUntilPosed(boss, mobId, deadline, serverNow)
	local swapStart = EncounterConfig.BossDropSequence.SwapStart
	local ready = {}
	local bridgeId, slamId = clipId(mobId, "CeilingToBody"), clipId(mobId, "LandingSlam")
	if bridgeId then ready[bridgeId] = swapStart end
	if slamId then ready[slamId] = 0 end
	local parts = {}
	for _, d in ipairs(boss:GetDescendants()) do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 1
			table.insert(parts, d)
		end
	end
	local conn
	local function release()
		if conn then conn:Disconnect(); conn = nil end
		for _, part in ipairs(parts) do part.LocalTransparencyModifier = 0 end
		table.clear(parts)
	end
	conn = RunService.RenderStepped:Connect(function()
		if not boss.Parent or serverNow() >= deadline then release() return end
		local animator = boss:FindFirstChildWhichIsA("Animator", true)
		if not animator then return end
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			local need = track.Animation and ready[track.Animation.AnimationId]
			-- Length > 0: the clip is loaded; TimePosition > need: at least one frame evaluated.
			if need and track.Length > 0 and track.TimePosition > need then release() return end
		end
	end)
	return release
end

local RENDER_NAME = "MiasmaDropCutscene"
local FOV = 58
local LETTERBOX = .11           -- bar height, fraction of the screen
local LOOK_SMOOTHING = 7        -- higher = the look target catches up faster
local FADE_OUT = .3             -- to black before the handback (over the card, when there is one)
local FADE_IN = .5              -- back from black after it
-- Title card choreography (seconds from the card's start). See the header, shot 5.
local CARD = {
	MaxWidth = .94,          -- the card fits INSIDE this share of the screen (never cropped, any aspect)
	MaxHeight = .8,
	Aspect = 2,              -- the art's aspect ratio (1024x512-style)
	Tilt = -3,               -- degrees, resting tilt
	SlamTilt = -11,          -- ...and the tilt it slams in from
	SlamScale = 1.45,        -- starts this much oversized
	SlamDelay = .06,         -- after the flash/band, so the hit reads as flash -> slam
	SlamTime = .22,
	ShakeTime = .38,         -- the settle jolt
	ShakePixels = 14,
	Creep = .045,            -- slow push-in while it holds (scale gained over the hold)
	-- Layered cards (TitleCards Layers): the creature and the title move on their own.
	CreatureWidth = .52,     -- creature layer width, share of the card (square art)
	TitleWidth = .78,        -- title layer width, share of the card (2:1 art)
	CreatureSlideTime = .2,  -- the creature slides in from off the right edge, with the band
	CreatureCreep = .07,     -- creeps faster than the title (Creep) while holding: parallax
	BackdropScale = 1.15,    -- the backdrop layer bleeds this far past the card (torn edges)
	BackdropTransparency = .15, -- a little of the frozen arena shows through it
	FlashTime = .28,
	BandTime = .16,
	BandTilt = -7,
	BandColor = Color3.fromRGB(16, 11, 20),
	BandEdge = Color3.fromRGB(120, 60, 150),
	BorderColor = Color3.new(0, 0, 0),
	BorderThickness = 6,
	-- The frozen world behind the card.
	Grade = { Saturation = -.7, Contrast = .25, Brightness = -.06, TintColor = Color3.fromRGB(226, 214, 236) },
	Blur = 0,                -- 0 = no blur; the grade alone sells the freeze (the blur read as a smeared cutscene)
	GradeTime = .15,
}

local BODY_BONE = "Belly_Center_Core"
local MOUTH_BONES = { "LowerJaw_Center_Front", "Throat_Center_Front" }

local active -- the running cutscene, or nil
local showCard, animateCard -- assigned in the title card section below

local function smooth(u)
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

local function lerp(a, b, u) return a + (b - a) * u end

local function serverNow()
	return Workspace:GetServerTimeNow()
end

local function widestMesh(model)
	local skin
	if model then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("MeshPart") and (not skin or d.Size.X > skin.Size.X) then skin = d end
		end
	end
	return skin
end

local function findBones(model)
	local bones = {}
	if model then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("Bone") then bones[d.Name] = d end
		end
	end
	return bones
end

local function bonePosition(bone)
	if bone and bone.Parent then return bone.TransformedWorldCFrame.Position end
	return nil
end

----------------------------------------------------------------------
-- Overlay: letterbox, fade, title card
----------------------------------------------------------------------

local function buildOverlay(mobId)
	local gui = Instance.new("ScreenGui")
	gui.Name = "MiasmaDropCutscene"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 400
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local function bar(anchorY)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0, anchorY)
		f.Position = UDim2.fromScale(0, anchorY)
		f.Size = UDim2.fromScale(1, 0)
		f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.BorderSizePixel = 0
		f.ZIndex = 2
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

	local overlay = { gui = gui, top = top, bottom = bottom, fade = fade }

	local card = TitleCards.Get(mobId)
	if TitleCards.Has(mobId) then
		local layered = TitleCards.IsLayered(mobId)
		-- White hit flash.
		local flash = Instance.new("Frame")
		flash.Name = "CardFlash"
		flash.Size = UDim2.fromScale(1, 1)
		flash.BackgroundColor3 = Color3.new(1, 1, 1)
		flash.BackgroundTransparency = 1
		flash.BorderSizePixel = 0
		flash.ZIndex = 9
		flash.Parent = gui

		-- The dark diagonal band the card lands on. Wider than the screen at any aspect, so it
		-- also fills whatever space the (never-cropped) card leaves at the sides or top/bottom.
		local band = Instance.new("Frame")
		band.Name = "CardBand"
		band.AnchorPoint = Vector2.new(.5, .5)
		band.Position = UDim2.fromScale(-1, .5)
		band.Size = UDim2.fromScale(1.8, .74)
		band.Rotation = CARD.BandTilt
		band.BackgroundColor3 = CARD.BandColor
		band.BackgroundTransparency = .05
		band.BorderSizePixel = 0
		band.Visible = false
		band.ZIndex = 5
		band.Parent = gui
		local bandEdge = Instance.new("UIStroke")
		bandEdge.Color = CARD.BandEdge
		bandEdge.Thickness = 5
		bandEdge.Parent = band

		-- The card: fitted INSIDE MaxWidth x MaxHeight at its own aspect, so it is never cropped
		-- on a wide or tall screen (it used to fill the screen with ScaleType.Crop, which cut
		-- the top and bottom off on wide viewports, e.g. Studio's).
		local holder = Instance.new("Frame")
		holder.Name = "TitleCard"
		holder.AnchorPoint = Vector2.new(.5, .5)
		holder.Position = UDim2.fromScale(.5, .5)
		holder.Size = UDim2.fromScale(CARD.MaxWidth, CARD.MaxHeight)
		holder.Rotation = CARD.Tilt
		holder.BackgroundColor3 = CARD.BorderColor
		holder.BackgroundTransparency = 1
		holder.BorderSizePixel = 0
		holder.Visible = false
		holder.ZIndex = 6
		holder.Parent = gui
		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.AspectRatio = CARD.Aspect
		aspect.AspectType = Enum.AspectType.FitWithinMaxSize
		aspect.Parent = holder
		local scale = Instance.new("UIScale")
		scale.Parent = holder
		local border = Instance.new("UIStroke")
		border.Color = CARD.BorderColor
		border.Thickness = CARD.BorderThickness
		border.Transparency = 1
		border.Parent = holder

		local function layer(name, image, zIndex)
			local img = Instance.new("ImageLabel")
			img.Name = name
			img.BackgroundTransparency = 1
			img.Image = image
			img.ImageTransparency = 1
			img.ScaleType = Enum.ScaleType.Fit
			img.ZIndex = zIndex
			img.Parent = holder
			return img
		end

		local art, creature, creatureScale, titleImg, titleScale, backdrop
		if layered then
			-- No card rectangle: the layers sit straight on the band (the creature overhangs it).
			border.Enabled = false
			local layers = card.Layers
			if type(layers.Backdrop) == "string" and layers.Backdrop ~= "" then
				-- Replaces the plain in-engine band: it whips in from the left in the band's place.
				backdrop = layer("Backdrop", layers.Backdrop, 5)
				backdrop.AnchorPoint = Vector2.new(.5, .5)
				backdrop.Position = UDim2.fromScale(-1.2, .5)
				backdrop.Size = UDim2.fromScale(CARD.BackdropScale, CARD.BackdropScale)
			end
			creature = layer("Creature", layers.Creature, 6)
			creature.AnchorPoint = Vector2.new(1, 1)
			creature.Size = UDim2.fromScale(CARD.CreatureWidth, CARD.CreatureWidth * CARD.Aspect) -- square
			creature.Position = UDim2.fromScale(1 + CARD.CreatureWidth, 1.02) -- off-screen right
			creatureScale = Instance.new("UIScale")
			creatureScale.Parent = creature
			if type(layers.Title) == "string" and layers.Title ~= "" then
				titleImg = layer("Title", layers.Title, 7)
				titleImg.AnchorPoint = Vector2.new(0, .5)
				titleImg.Position = UDim2.fromScale(0, .5)
				titleImg.Size = UDim2.fromScale(CARD.TitleWidth, CARD.TitleWidth) -- 2:1, same as the card
				titleScale = Instance.new("UIScale")
				titleScale.Parent = titleImg
			end
		else
			art = layer("Art", card.Image, 6)
			art.Size = UDim2.fromScale(1, 1)
		end

		local texts = {}
		if card.DrawText then
			local stats = MobData.FindMobById(mobId) or {}
			local name = Instance.new("TextLabel")
			name.AnchorPoint = Vector2.new(0, .5)
			name.Position = UDim2.fromScale(.05, .42)
			name.Size = UDim2.fromScale(.55, .34)
			name.Rotation = -8
			name.BackgroundTransparency = 1
			name.TextScaled = true
			name.TextTransparency = 1
			name.Text = string.upper(tostring(stats.Name or mobId))
			name.TextColor3 = Color3.fromRGB(205, 215, 190)
			name.ZIndex = 7
			pcall(function() name.FontFace = UIFonts.DisplayBold end)
			local nameStroke = Instance.new("UIStroke")
			nameStroke.Color = Color3.fromRGB(40, 55, 25)
			nameStroke.Thickness = 4
			nameStroke.Parent = name
			name.Parent = holder
			table.insert(texts, name)

			local title = type(stats.Title) == "string" and stats.Title or ""
			if title ~= "" then
				local sub = Instance.new("TextLabel")
				sub.AnchorPoint = Vector2.new(0, .5)
				sub.Position = UDim2.fromScale(.07, .74)
				sub.Size = UDim2.fromScale(.42, .1)
				sub.Rotation = -4
				sub.BackgroundTransparency = 1
				sub.TextScaled = true
				sub.TextTransparency = 1
				sub.TextXAlignment = Enum.TextXAlignment.Left
				sub.Text = string.upper(title:sub(1, 1)) .. title:sub(2) -- "the Scourge" -> "The Scourge"
				sub.TextColor3 = Color3.fromRGB(200, 170, 215)
				sub.ZIndex = 7
				pcall(function() sub.FontFace = UIFonts.DisplaySemibold end)
				local subStroke = Instance.new("UIStroke")
				subStroke.Color = Color3.new(0, 0, 0)
				subStroke.Thickness = 2
				subStroke.Parent = sub
				sub.Parent = holder
				table.insert(texts, sub)
			end
		end
		overlay.card = {
			holder = holder, scale = scale, border = border, art = art, texts = texts, band = band, flash = flash,
			layered = layered, creature = creature, creatureScale = creatureScale,
			titleImg = titleImg, titleScale = titleScale, backdrop = backdrop,
		}
	end

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return overlay
end

-- A one-shot for the card (its sting, the roar), through the Effects bus so the volume
-- sliders apply. Plays to its end, even past the handback.
local function playCardSound(id)
	if type(id) ~= "string" or id == "" then return end
	local sound = Instance.new("Sound")
	sound.Name = "TitleCardSting"
	sound.SoundId = id
	sound.SoundGroup = SfxService.GetEffectsGroup()
	sound.Parent = SoundService
	local done = false
	local function cleanup()
		if done then return end
		done = true
		sound:Destroy()
	end
	sound.Ended:Connect(cleanup)
	sound:Play()
	task.delay(30, cleanup)
end

local function tween(inst, seconds, props, style)
	local t = TweenService:Create(inst, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

----------------------------------------------------------------------
-- Shot keys
----------------------------------------------------------------------

--[[
	Each key: t (seconds from start), yaw (degrees around the facing, 0 = straight in front),
	dist (studs from the anchor, in boss widths W), height (studs above the anchor, in W for
	the roof shots and boss heights H for the floor shots), mix (0 = anchored on the ceiling
	blob, 1 = on the landing spot). Values blend with smoothstep between neighbours.
]]
-- Enrage (p.mode == "enrage"): all shots on the boss where it stands (mix 1), no ceiling part.
local function buildEnrageKeys(p)
	local sp, se = tonumber(p.spewStart) or 1.9, tonumber(p.spewEnd) or 2.95
	return {
		{ t = 0,         yaw = -38, dist = 1.9,  height = .55, heightUnit = "H", mix = 1 },
		{ t = sp - .25,  yaw = -14, dist = 1.35, height = .5,  heightUnit = "H", mix = 1 }, -- push in as it rears up
		{ t = se,        yaw = 8,   dist = 1.6,  height = .42, heightUnit = "H", mix = 1 }, -- pull back as it spews
		{ t = p.endsAt,  yaw = 14,  dist = 1.75, height = .48, heightUnit = "H", mix = 1 },
	}
end

local function buildKeys(p)
	if p.mode == "enrage" then return buildEnrageKeys(p) end
	local b, i = p.bridgeStart, p.impact
	return {
		{ t = 0,              yaw = 58,  dist = .52, height = -.34, heightUnit = "W", mix = 0 },
		{ t = b + .25,        yaw = 40,  dist = .38, height = -.28, heightUnit = "W", mix = 0 },
		{ t = i + .35,        yaw = 0,   dist = 1.55, height = .42, heightUnit = "H", mix = 1 },
		{ t = p.roarStart,    yaw = -7,  dist = 1.6, height = .42, heightUnit = "H", mix = 1 },
		{ t = p.roarEnd,      yaw = -3,  dist = 1.4, height = .34, heightUnit = "H", mix = 1 },
		{ t = p.endsAt,       yaw = -2,  dist = 1.45, height = .36, heightUnit = "H", mix = 1 },
	}
end

local function sampleKeys(keys, t, W, H)
	local function resolved(k)
		return k.yaw, k.dist * W, k.height * (k.heightUnit == "H" and H or W), k.mix
	end
	if t <= keys[1].t then return resolved(keys[1]) end
	for n = 2, #keys do
		local a, c = keys[n - 1], keys[n]
		if t <= c.t then
			local u = smooth((t - a.t) / math.max(c.t - a.t, 1e-3))
			local ya, da, ha, ma = resolved(a)
			local yc, dc, hc, mc = resolved(c)
			return lerp(ya, yc, u), lerp(da, dc, u), lerp(ha, hc, u), lerp(ma, mc, u)
		end
	end
	return resolved(keys[#keys])
end

----------------------------------------------------------------------
-- Title card
----------------------------------------------------------------------

-- The hit: sounds, flash, freeze grade, band whip, then the slam. The card holds until the
-- fade to black covers it (no separate exit).
showCard = function(state, cardDef)
	local c = state.overlay.card
	playCardSound(cardDef.Sound)
	if type(cardDef.SfxKey) == "string" then
		local id = SoundEffects[cardDef.SfxKey]
		if type(id) == "table" then id = id[math.random(1, #id)] end
		playCardSound(id)
	end

	c.flash.BackgroundTransparency = .25
	tween(c.flash, CARD.FlashTime, { BackgroundTransparency = 1 })

	-- Freeze the world behind the card: desaturate + blur (client-local Lighting effects).
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "MiasmaCardGrade"
	grade.Parent = Lighting
	state.grade = grade
	tween(grade, CARD.GradeTime, CARD.Grade)
	if CARD.Blur > 0 then
		local blur = Instance.new("BlurEffect")
		blur.Name = "MiasmaCardBlur"
		blur.Size = 0
		blur.Parent = Lighting
		state.blur = blur
		tween(blur, CARD.GradeTime, { Size = CARD.Blur })
	end

	if not c.backdrop then
		c.band.Visible = true
		tween(c.band, CARD.BandTime, { Position = UDim2.fromScale(.5, .5) }, Enum.EasingStyle.Quart)
	end

	if c.layered then
		-- The creature arrives with the band (slides in from the right); the title slams after.
		c.holder.Visible = true
		if c.backdrop then
			tween(c.backdrop, .1, { ImageTransparency = CARD.BackdropTransparency })
			tween(c.backdrop, CARD.BandTime, { Position = UDim2.fromScale(.5, .5) }, Enum.EasingStyle.Quart)
		end
		tween(c.creature, .08, { ImageTransparency = 0 })
		tween(c.creature, CARD.CreatureSlideTime, { Position = UDim2.fromScale(1, 1.02) }, Enum.EasingStyle.Quart)
		task.delay(CARD.SlamDelay, function()
			if state.finished or not c.titleImg then return end
			c.titleScale.Scale = CARD.SlamScale
			c.titleImg.Rotation = CARD.SlamTilt - CARD.Tilt -- the holder already carries the resting tilt
			tween(c.titleImg, .08, { ImageTransparency = 0 })
			tween(c.titleScale, CARD.SlamTime, { Scale = 1 }, Enum.EasingStyle.Back)
			tween(c.titleImg, CARD.SlamTime, { Rotation = 0 }, Enum.EasingStyle.Back)
		end)
		return
	end

	task.delay(CARD.SlamDelay, function()
		if state.finished then return end
		c.holder.Visible = true
		c.scale.Scale = CARD.SlamScale
		c.holder.Rotation = CARD.SlamTilt
		tween(c.art, .08, { ImageTransparency = 0 })
		tween(c.border, .08, { Transparency = 0 })
		for _, text in ipairs(c.texts) do tween(text, .08, { TextTransparency = 0 }) end
		tween(c.scale, CARD.SlamTime, { Scale = 1 }, Enum.EasingStyle.Back)
		tween(c.holder, CARD.SlamTime, { Rotation = CARD.Tilt }, Enum.EasingStyle.Back)
	end)
end

-- Per frame while the card is up (u = seconds since the card started): the settle jolt, then
-- the slow creep. Position/scale only; the tweens above own the rest.
animateCard = function(state, u)
	local c = state.overlay.card
	if not c then return end
	local landed = CARD.SlamDelay + CARD.SlamTime
	if c.layered then
		-- Title takes the settle jolt; then both creep, the creature faster (parallax).
		local shakeU = (u - landed) / CARD.ShakeTime
		if c.titleImg then
			if shakeU >= 0 and shakeU < 1 then
				local amp = CARD.ShakePixels * (1 - shakeU) ^ 2
				c.titleImg.Position = UDim2.new(0, (math.random() * 2 - 1) * amp, .5, (math.random() * 2 - 1) * amp)
			elseif shakeU >= 1 then
				c.titleImg.Position = UDim2.fromScale(0, .5)
			end
		end
		if u > landed then
			local holdU = math.clamp((u - landed) / math.max(state.cardHold - landed, .1), 0, 1)
			if c.titleScale then c.titleScale.Scale = 1 + CARD.Creep * holdU end
			c.creatureScale.Scale = 1 + CARD.CreatureCreep * holdU
		end
		return
	end
	local shakeU = (u - landed) / CARD.ShakeTime
	if shakeU >= 0 and shakeU < 1 then
		local amp = CARD.ShakePixels * (1 - shakeU) ^ 2
		c.holder.Position = UDim2.new(.5, (math.random() * 2 - 1) * amp, .5, (math.random() * 2 - 1) * amp)
	elseif shakeU >= 1 then
		c.holder.Position = UDim2.fromScale(.5, .5)
	end
	if u > landed then
		local holdU = math.clamp((u - landed) / math.max(state.cardHold - landed, .1), 0, 1)
		c.scale.Scale = 1 + CARD.Creep * holdU
	end
end

local function clearGrade(state)
	if state.grade then state.grade:Destroy(); state.grade = nil end
	if state.blur then state.blur:Destroy(); state.blur = nil end
end

----------------------------------------------------------------------
-- Play / Stop
----------------------------------------------------------------------

-- The boss's overhead bars (BillboardGuis) stay hidden on THIS client for the whole cutscene,
-- even when the server turns its HP bar back on mid-way (it does, the moment the boss lands).
-- Deferred signals: our own write reads back as false, so only a switch ON is remembered.
local function holdBillboards(model)
	local held = {}
	if typeof(model) ~= "Instance" then return held end
	for _, g in ipairs(model:GetDescendants()) do
		if g:IsA("BillboardGui") then
			local entry = { gui = g, wanted = g.Enabled }
			g.Enabled = false
			entry.conn = g:GetPropertyChangedSignal("Enabled"):Connect(function()
				if g.Enabled then entry.wanted = true; g.Enabled = false end
			end)
			table.insert(held, entry)
		end
	end
	return held
end

local function releaseBillboards(held)
	for _, entry in ipairs(held or {}) do
		entry.conn:Disconnect()
		if entry.gui.Parent then entry.gui.Enabled = entry.wanted end
	end
end

-- Any other blur (the inventory's background blur if it was open, a DoF) would smear the whole
-- cutscene: switch them off for its length and put them back exactly as they were.
local function suppressBlurs()
	local saved = {}
	local camera = Workspace.CurrentCamera
	for _, holder in ipairs({ Lighting, camera }) do
		if holder then
			for _, fx in ipairs(holder:GetChildren()) do
				if (fx:IsA("BlurEffect") or fx:IsA("DepthOfFieldEffect")) and fx.Enabled then
					saved[fx] = true
					fx.Enabled = false
				end
			end
		end
	end
	return function()
		for fx in pairs(saved) do
			if fx.Parent then fx.Enabled = true end
		end
	end
end

local function finish(state, instant)
	if state.finished then return end
	state.finished = true
	if state.restoreBlurs then state.restoreBlurs(); state.restoreBlurs = nil end
	if state.releaseBoss then state.releaseBoss(); state.releaseBoss = nil end
	if state.releaseHud then state.releaseHud(); state.releaseHud = nil end
	releaseBillboards(state.billboards); state.billboards = nil
	pcall(function() RunService:UnbindFromRenderStep(RENDER_NAME) end)
	local camera = Workspace.CurrentCamera
	if camera then camera.FieldOfView = state.prevFov end
	-- Hand back facing Miasma (FirstPersonViewModel turns its own yaw/pitch to this).
	local character = Players.LocalPlayer.Character
	local head = character and character:FindFirstChild("Head")
	if head and state.lookTarget then
		CameraOverrideState.RequestLook(state.lookTarget - head.Position)
	end
	CameraOverrideState.SetActive(false)
	if active == state then active = nil end

	clearGrade(state) -- the frozen-world grade goes while the screen is black
	local overlay = state.overlay
	if instant then
		overlay.gui:Destroy()
		return
	end
	if overlay.card then -- gone while the screen is black
		overlay.card.holder.Visible = false
		overlay.card.band.Visible = false
	end
	tween(overlay.top, FADE_IN, { Size = UDim2.fromScale(1, 0) })
	tween(overlay.bottom, FADE_IN, { Size = UDim2.fromScale(1, 0) })
	tween(overlay.fade, FADE_IN, { BackgroundTransparency = 1 })
	task.delay(FADE_IN + .05, function() overlay.gui:Destroy() end)
end

function Cutscene.Stop()
	if active then finish(active, true) end
end

function Cutscene.Play(p)
	Cutscene.Stop()
	if type(p) ~= "table" or typeof(p.landing) ~= "Vector3" or typeof(p.ceiling) ~= "Vector3" then return end
	local startsAt = tonumber(p.startsAt)
	local endsAt = tonumber(p.endsAt)
	if not startsAt or not endsAt or serverNow() - startsAt >= endsAt then return end
	local camera = Workspace.CurrentCamera
	if not camera then return end

	local boss = typeof(p.boss) == "Instance" and p.boss or nil
	local latch = typeof(p.latch) == "Instance" and p.latch or nil
	local skin = widestMesh(boss)
	local W = skin and skin.Size.X or 40
	local H = skin and skin.Size.Y or 31
	local bones = findBones(boss)

	local facing = typeof(p.facing) == "Vector3" and p.facing or Vector3.new(0, 0, -1)
	facing = Vector3.new(facing.X, 0, facing.Z)
	facing = facing.Magnitude > .01 and facing.Unit or Vector3.new(0, 0, -1)
	local right = facing:Cross(Vector3.yAxis)

	local landing = p.landing
	local function blobCentre()
		if latch and latch.Parent then
			local cf = latch:GetBoundingBox()
			return cf.Position
		end
		return p.ceiling
	end
	local ceilingPoint = blobCentre()

	local state = {
		finished = false,
		prevFov = camera.FieldOfView,
		overlay = buildOverlay(p.mobId),
		keys = buildKeys(p),
		lookTarget = ceilingPoint,
		cardShown = false,
		fading = false,
	}
	active = state
	-- Cinema: every other UI off (the boss bar included) and the boss's overhead bars too.
	state.releaseHud = HudHider.Acquire(state.overlay.gui)
	state.restoreBlurs = suppressBlurs()
	if boss and p.mode ~= "enrage" and tonumber(p.impact) then
		state.releaseBoss = holdUntilPosed(boss, p.mobId, startsAt + tonumber(p.impact), serverNow)
	end
	state.billboards = holdBillboards(boss)

	CameraOverrideState.SetActive(true)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = FOV
	tween(state.overlay.top, .45, { Size = UDim2.fromScale(1, LETTERBOX) })
	tween(state.overlay.bottom, .45, { Size = UDim2.fromScale(1, LETTERBOX) })

	local function bossVisible()
		return skin ~= nil and skin.Parent ~= nil and skin.Transparency < .95
	end

	-- Where the camera wants to look at time t (smoothed per frame below).
	local function desiredLook(t)
		if p.mode == "enrage" then
			-- Body while it rears up, then the mouth for the spew.
			if t < (tonumber(p.spewStart) or 1.9) - .3 then return landing + Vector3.new(0, H * .55, 0) end
			local a, c = bonePosition(bones[MOUTH_BONES[1]]), bonePosition(bones[MOUTH_BONES[2]])
			if a and c then return (a + c) * .5 end
			return landing + Vector3.new(0, H * .6, 0)
		end
		if t < p.bridgeStart + .2 or not bossVisible() then
			if t < p.impact then return blobCentre() or ceilingPoint end
		end
		if t < p.impact + .35 then
			return bonePosition(bones[BODY_BONE]) or landing + Vector3.new(0, H * .5, 0)
		end
		if t < p.roarStart - .15 then
			return landing + Vector3.new(0, H * .5, 0)
		end
		local a, c = bonePosition(bones[MOUTH_BONES[1]]), bonePosition(bones[MOUTH_BONES[2]])
		if a and c then
			-- Aim a touch below the mouth so the whole roaring face and the breath fill the frame.
			return (a + c) * .5 - Vector3.new(0, H * .05, 0)
		end
		return landing + Vector3.new(0, H * .62, 0)
	end

	local lastClock = os.clock()
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value, function()
		if state.finished then return end
		local now = os.clock()
		local dt = math.min(now - lastClock, .1)
		lastClock = now
		local t = serverNow() - startsAt
		local cam = Workspace.CurrentCamera
		if not cam then return end

		if t >= endsAt then
			finish(state)
			return
		end

		-- Freeze frame: once the card is up, the camera holds exactly where it is. Re-applied
		-- every frame (not just left alone) because the roar's shake is still decaying then and
		-- works by multiplying the camera's current CFrame, which would otherwise drift.
		if state.cardShown then
			state.frozenCFrame = state.frozenCFrame or cam.CFrame
			cam.CameraType = Enum.CameraType.Scriptable
			cam.CFrame = state.frozenCFrame
			animateCard(state, t - state.cardAt)
			if not state.fading and t >= endsAt - FADE_OUT then
				state.fading = true
				tween(state.overlay.fade, FADE_OUT, { BackgroundTransparency = 0 }, Enum.EasingStyle.Linear)
			end
			return
		end

		-- Camera pose.
		local yaw, dist, height, mix = sampleKeys(state.keys, t, W, H)
		local anchor = Vector3.new(
			lerp(ceilingPoint.X, landing.X, mix),
			lerp(ceilingPoint.Y, landing.Y, mix),
			lerp(ceilingPoint.Z, landing.Z, mix)
		)
		local r = math.rad(yaw)
		local dir = facing * math.cos(r) + right * math.sin(r)
		local position = anchor + dir * dist + Vector3.new(0, height, 0)

		local want = desiredLook(t)
		state.lookTarget = state.lookTarget:Lerp(want, 1 - math.exp(-LOOK_SMOOTHING * dt))
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = CFrame.lookAt(position, state.lookTarget)

		-- Title card.
		local overlay = state.overlay
		if overlay.card and not state.cardShown and t >= (tonumber(p.cardStart) or endsAt) then
			state.cardShown = true
			state.cardAt = t
			state.cardHold = math.max(.1, endsAt - t - FADE_OUT)
			showCard(state, TitleCards.Get(p.mobId))
		end

		-- Fade to black just before the handback, so the camera switch is hidden.
		if not state.fading and t >= endsAt - FADE_OUT then
			state.fading = true
			tween(overlay.fade, FADE_OUT, { BackgroundTransparency = 0 }, Enum.EasingStyle.Linear)
		end
	end)
end

return Cutscene
