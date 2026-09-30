--[[
	DungeonCompleteBanner -- the full-screen end-of-run moment (client, any dungeon):
	"Dungeon Complete" on a clear, "Dungeon Failed" on a death / wipe.

		Banner.Play(key)     play the banner registered under `key` in RS/Assets/Images/Banners
		                     (default "DungeonComplete"). No-op while one is already playing.
		Banner.IsPlaying()
		Banner.OnDone(fn)    run fn once the banner has finished (right away if none is playing)

	Triggered by DungeonRunHud when a run summary carries a Banner key (the server picks it,
	DungeonRunService.EndRunFor); the summary panel waits for OnDone.

	While it plays, ALL other UI is hidden (HudHider: every ScreenGui plus the Roblox core UI),
	and put back as it was afterwards.

	The art (and glow) are preloaded when this module loads and again before each play, so the
	sequence never starts on an image that hasn't arrived yet (it used to fade in "nothing",
	then the ornament popped in late).

	Each banner names a STYLE (Banners[key].Style), tuned in STYLES below:
	  Complete  the screen dims, the banner fades in and settles from slightly small, its gold
	            outline glow blooms and breathes while it holds, then it all fades out.
	  Failed    the world drains of colour (a grey-red grade), the torn banner drops in from
	            above and sways to rest like hanging cloth, its dull red glow beats twice per
	            cycle like a failing heartbeat (weaker each beat), then it sinks and fades.
]]

local ContentProvider = game:GetService("ContentProvider")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Banners = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images"):WaitForChild("Banners"))
local HudHider = require(script.Parent:WaitForChild("HudHider"))

local Banner = {}

-- Timings in seconds; sizes as fractions of the screen (width capped by maxHeight).
local STYLES = {
	Complete = {
		fadeIn = .9,            -- banner fades in over this (not a sudden pop)
		glowDelay = .55,        -- glow blooms once the ornament is mostly faded in
		glowIn = .7,
		hold = 2.2,             -- fully shown
		fadeOut = .7,
		dimColor = Color3.new(0, 0, 0),
		dim = .45,              -- backdrop transparency at full strength
		width = .62, maxHeight = .5, y = .46,
		startScale = .9,        -- settles from this to 1 while fading in
		pulse = "breathe", pulseAmount = .18,
	},
	Failed = {
		fadeIn = 1.1,
		glowDelay = .55,
		glowIn = .9,
		hold = 2.6,
		fadeOut = .9,
		dimColor = Color3.fromRGB(18, 2, 2),
		dim = .35,
		width = .8, maxHeight = .62, y = .42, -- the art is a thin band on a tall canvas
		dropFrom = .14,         -- starts this far above its resting y, drops in
		sway = 4,               -- degrees; swings to rest after the drop
		sinkBy = .05,           -- sinks this far while fading out
		pulse = "heartbeat", pulseAmount = .6,
		grade = { Saturation = -.85, Brightness = -.06, Contrast = .1, TintColor = Color3.fromRGB(255, 212, 206) },
	},
}

local playing = false
local waiters = {}

local PRELOAD_TIMEOUT = 3 -- never hold the moment back longer than this for a slow download

local function bannerImages(def)
	local list = {}
	if type(def) == "table" then
		if type(def.Image) == "string" and def.Image ~= "" then table.insert(list, def.Image) end
		if type(def.Glow) == "string" and def.Glow ~= "" then table.insert(list, def.Glow) end
	end
	return list
end

-- Waits (up to `timeout`) until every image in `list` is downloaded.
local function preload(list, timeout)
	if #list == 0 then return end
	local done = false
	task.spawn(function()
		pcall(ContentProvider.PreloadAsync, ContentProvider, list)
		done = true
	end)
	local started = os.clock()
	while not done and os.clock() - started < timeout do task.wait() end
end

-- Warm the cache as soon as the client starts, so the first banner is already local.
task.spawn(function()
	local all = {}
	for _, def in pairs(Banners) do
		for _, id in ipairs(bannerImages(def)) do table.insert(all, id) end
	end
	preload(all, 30)
end)

----------------------------------------------------------------------
-- The banner
----------------------------------------------------------------------

local function tween(inst, seconds, props, style, direction)
	local t = TweenService:Create(inst, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

-- Glow transparency while held, at `t` seconds into the hold (0 = brightest).
local function glowAt(style, t)
	if style.pulse == "heartbeat" then
		-- lub-dub every 1.25s, each pair a little weaker than the last
		local p = t % 1.25
		local beat = math.exp(-(p / .09) ^ 2) + .7 * math.exp(-((p - .27) / .09) ^ 2)
		local fading = 1 - .45 * math.clamp(t / style.hold, 0, 1)
		return style.pulseAmount * (1 - math.clamp(beat, 0, 1) * fading)
	end
	return style.pulseAmount * (math.sin(t * 3.2 - math.pi / 2) + 1) * .5
end

local function build(def, style)
	local gui = Instance.new("ScreenGui")
	gui.Name = "DungeonEndBanner"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 1000
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = style.dimColor
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	dim.Parent = gui

	-- Holder at the art's own aspect, fitted to width x maxHeight of the screen.
	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.AnchorPoint = Vector2.new(.5, .5)
	holder.Position = UDim2.fromScale(.5, style.y - (style.dropFrom or 0))
	holder.Size = UDim2.fromScale(style.width, style.maxHeight)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = def.Aspect or 1.8
	aspect.AspectType = Enum.AspectType.FitWithinMaxSize
	aspect.Parent = holder
	local scale = Instance.new("UIScale")
	scale.Scale = style.startScale or 1
	scale.Parent = holder

	local glow
	if type(def.Glow) == "string" and def.Glow ~= "" then
		local gs = def.GlowScale or Vector2.new(1.1, 1.2)
		glow = Instance.new("ImageLabel")
		glow.Name = "Glow"
		glow.AnchorPoint = Vector2.new(.5, .5)
		glow.Position = UDim2.fromScale(.5, .5)
		glow.Size = UDim2.fromScale(gs.X, gs.Y)
		glow.BackgroundTransparency = 1
		glow.Image = def.Glow
		glow.ImageColor3 = def.GlowColor or Color3.fromRGB(255, 212, 110)
		glow.ImageTransparency = 1
		glow.ZIndex = 1
		glow.Parent = holder
	end

	local art = Instance.new("ImageLabel")
	art.Name = "Art"
	art.Size = UDim2.fromScale(1, 1)
	art.BackgroundTransparency = 1
	art.Image = def.Image
	art.ImageTransparency = 1
	art.ZIndex = 2
	art.Parent = holder

	local grade
	if style.grade then
		grade = Instance.new("ColorCorrectionEffect")
		grade.Name = "DungeonEndBannerGrade"
		grade.Parent = Lighting
	end

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return { gui = gui, dim = dim, holder = holder, scale = scale, art = art, glow = glow, grade = grade }
end

local function run(style, b)
	local restY = style.y
	tween(b.dim, style.fadeIn, { BackgroundTransparency = style.dim })
	tween(b.art, style.fadeIn, { ImageTransparency = 0 })
	if b.grade then tween(b.grade, style.fadeIn * 1.4, style.grade, Enum.EasingStyle.Sine) end
	if style.startScale then tween(b.scale, style.fadeIn + .3, { Scale = 1 }, Enum.EasingStyle.Quart) end
	if style.dropFrom then
		tween(b.holder, style.fadeIn, { Position = UDim2.fromScale(.5, restY) }, Enum.EasingStyle.Back)
	end
	if b.glow then
		task.delay(style.glowDelay, function()
			tween(b.glow, style.glowIn, { ImageTransparency = glowAt(style, 0) }, Enum.EasingStyle.Sine)
		end)
	end

	-- Sway (starts as the drop lands, damped) + glow pulse (once the glow is up).
	local started = os.clock()
	local glowFrom = style.glowDelay + style.glowIn
	local swayFrom = style.fadeIn * .7
	local live = RunService.RenderStepped:Connect(function()
		local t = os.clock() - started
		if style.sway and t > swayFrom then
			local s = t - swayFrom
			b.holder.Rotation = style.sway * math.exp(-s * 1.1) * math.sin(s * 4.2)
		end
		if b.glow and t > glowFrom then b.glow.ImageTransparency = glowAt(style, t - glowFrom) end
	end)
	task.wait(math.max(style.fadeIn, glowFrom) + style.hold)
	live:Disconnect()

	local out = style.fadeOut
	tween(b.dim, out, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tween(b.art, out, { ImageTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	if b.glow then tween(b.glow, out * .8, { ImageTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In) end
	if b.grade then
		tween(b.grade, out, { Saturation = 0, Brightness = 0, Contrast = 0, TintColor = Color3.new(1, 1, 1) })
	end
	if style.sinkBy then
		tween(b.holder, out, { Position = UDim2.fromScale(.5, restY + style.sinkBy), Rotation = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	else
		tween(b.scale, out, { Scale = 1.04 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
	task.wait(out)
end

local function finish()
	playing = false
	local list = waiters
	waiters = {}
	for _, fn in ipairs(list) do task.spawn(fn) end
end

function Banner.IsPlaying()
	return playing
end

function Banner.OnDone(fn)
	if not playing then task.spawn(fn) return end
	table.insert(waiters, fn)
end

function Banner.Play(key)
	if playing then return end
	local def = Banners[key or "DungeonComplete"]
	if type(def) ~= "table" or type(def.Image) ~= "string" or def.Image == "" then return end
	local style = STYLES[def.Style or "Complete"] or STYLES.Complete
	playing = true

	task.spawn(function()
		preload(bannerImages(def), PRELOAD_TIMEOUT) -- instant when the startup preload finished
		local b = build(def, style)
		local restoreUi = HudHider.Acquire(b.gui)
		local ok, err = pcall(run, style, b)
		if not ok then warn("[DungeonCompleteBanner] " .. tostring(err)) end
		b.gui:Destroy()
		if b.grade then b.grade:Destroy() end
		restoreUi()
		finish()
	end)
end

return Banner
