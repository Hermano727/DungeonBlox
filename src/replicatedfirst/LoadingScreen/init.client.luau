--[[
	LoadingScreen -- ReplicatedFirst (LocalScript)

	Replaces Roblox's default loading screen with the painted one and holds it until the game is
	ready to look at:
		0. this screen's own art downloads and draws behind a black curtain (Roblox's screen
		   stays up meanwhile), then the whole screen fades in at once
		1. the game has loaded (game.Loaded)                       0% .. 10%
		2. the UI art, icons, sound effects and animations are
		   preloaded (ContentProvider:PreloadAsync)                 10% .. 85%
		3. the character has spawned                                85% .. 100%
	then shows "Click anywhere to start" and waits for the player before fading through black into
	the game. Each loading step has a timeout, so a slow asset can never
	keep a player on this screen: the worst case is MAX_WAIT seconds.

	ReplicatedFirst runs before anything else replicates, so this script can only lean on its own
	child registry (LoadingArt) until step 1 is done. Fonts: Merriweather is bundled with Roblox,
	so the text shows instantly.

	Sets the player attribute "LoadingScreenDone" = true when it hands over, for anything that
	should wait for the screen to clear (a welcome banner, a cutscene).
	Detail: docs/loading-screen.md.
]]

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Art = require(script:WaitForChild("LoadingArt"))

-- Roblox's own loading screen stays up until this screen's art is downloaded and drawn
-- (see "This screen's own art first" below), so the first thing a player sees of it is the
-- whole painting at once, not the pieces arriving one by one.

---------------------------------------------------------------------------
-- Tuning
---------------------------------------------------------------------------

local MIN_SHOW = 2.5 -- seconds on screen at least (from the reveal), so it never just flickers
local OWN_ART_TIMEOUT = 6 -- longest wait for this screen's own art before showing it anyway
local REVEAL = 0.5 -- fade in from black once the art is ready
local PRELOAD_TIMEOUT = 25 -- give up on stragglers after this long
local CHARACTER_TIMEOUT = 20
local MAX_WAIT = 60 -- hard cap on the whole screen
local FADE_OUT, FADE_IN = 0.6, 0.8 -- through black into the game

local WORD = "Loading..."
local WORD_SIZE = 40
local HOP_STEP = 0.11 -- seconds between one letter's hop and the next
local HOP_TIME = HOP_STEP * 1.6 -- one hop (a little overlap reads as a wave, still one letter at a time)
local HOP_HEIGHT = 14
local HOP_REST = 0.7 -- pause after the last dot before the first letter goes again

local BAR_H = 34 -- matches LoadingArt.BarFrame's SliceScale
local BAR_MAX_W = 640
local MOTES = 16 -- drifting specks of light
local LEAVES = 9 -- only when leaf art exists

local FONT = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold)
local FONT_TIP = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Regular, Enum.FontStyle.Italic)
local BONE = Color3.fromRGB(236, 226, 208)
local GOLD = Color3.fromRGB(255, 214, 140)
local INK = Color3.fromRGB(26, 18, 12)
local NIGHT = Color3.fromRGB(14, 11, 18)

-- Shown one at a time under the bar. Plain sentences, no dashes, about the game's real rules.
local TIPS = {
	"Lawful lands keep other players' blades sheathed. Step past them at your own risk.",
	"Enchanting is safe to +3. Past that, the gear can break.",
	"Protection scrolls stop an item breaking, not the enchant failing.",
	"A chaotic soul waits a full minute to change shards. A lawful one, ten seconds.",
	"Named elites lose interest after five quiet minutes and leave.",
	"Raw fish are for the fire. Cook them before you eat.",
	"Any hit breaks a hearthstone channel. Find somewhere quiet first.",
	"Sprint or jump near a pool and the fish dive deep.",
	"Damage dealt decides who earns the loot score for a kill.",
}

---------------------------------------------------------------------------
-- Building the screen
---------------------------------------------------------------------------

local function make(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do inst[k] = v end
	inst.Parent = parent
	return inst
end

local gui = make("ScreenGui", {
	Name = "LoadingScreen", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 10000,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, player:WaitForChild("PlayerGui"))
-- Failsafe: whatever goes wrong while loading, the screen never outlives MAX_WAIT by much. Once
-- it's waiting for the player's click it's done its job, so it stays until they click.
local awaitingClick = false
task.delay(MAX_WAIT + 10, function()
	if gui.Parent and not awaitingClick then
		player:SetAttribute("LoadingScreenDone", true)
		gui:Destroy()
	end
end)

-- Night-dark base, so nothing white flashes while the painting downloads.
local base = make("Frame", {
	Name = "Base", Size = UDim2.fromScale(1, 1), BackgroundColor3 = NIGHT, BorderSizePixel = 0,
}, gui)

-- The painting, cover-fit and centred, in two halves. It breathes in slowly while loading.
local painting = make("Frame", {
	Name = "Painting", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	BackgroundTransparency = 1, ZIndex = 1,
}, base)
local paintingScale = make("UIScale", { Scale = 1 }, painting)
local bg = Art.Background
local halves = {
	make("ImageLabel", {
		Size = UDim2.new(bg.Split, 1, 1, 0), BackgroundTransparency = 1, Image = bg.Left,
		ScaleType = Enum.ScaleType.Stretch, ZIndex = 1,
	}, painting),
	make("ImageLabel", {
		Position = UDim2.fromScale(bg.Split, 0), Size = UDim2.fromScale(1 - bg.Split, 1), BackgroundTransparency = 1,
		Image = bg.Right, ScaleType = Enum.ScaleType.Stretch, ZIndex = 1,
	}, painting),
}

-- Drifting light and leaves sit between the painting and the shade.
local fx = make("Frame", { Name = "Fx", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2 }, base)

-- A shade rising from the bottom so the bar and text read over the bright grass.
local shade = make("Frame", {
	Name = "Shade", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0.42),
	BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 3,
}, base)
make("UIGradient", {
	Rotation = 90,
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.55, 0.55), NumberSequenceKeypoint.new(1, 0.25),
	}),
}, shade)

-- The panel: the bouncing word, the bar, the tip.
local panel = make("Frame", {
	Name = "Panel", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -48),
	Size = UDim2.fromOffset(BAR_MAX_W, 150), BackgroundTransparency = 1, ZIndex = 4,
}, base)

local wordRow = make("Frame", {
	Name = "Word", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0),
	Size = UDim2.fromOffset(0, 56), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, ZIndex = 4,
}, panel)
make("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Bottom,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, wordRow)
local letters = {}
for i = 1, #WORD do
	-- Each letter sits in its own holder so the list lays the word out and the letter can hop
	-- inside its slot without nudging its neighbours.
	local holder = make("Frame", {
		LayoutOrder = i, Size = UDim2.fromOffset(0, 56), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1, ZIndex = 4,
	}, wordRow)
	local letter = make("TextLabel", {
		Size = UDim2.fromOffset(0, 56), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1,
		Text = WORD:sub(i, i), FontFace = FONT, TextSize = WORD_SIZE, TextColor3 = BONE,
		TextYAlignment = Enum.TextYAlignment.Bottom, ZIndex = 4,
	}, holder)
	make("UIStroke", { Color = INK, Thickness = 2, Transparency = 0.2 }, letter)
	letters[i] = letter
end

-- The bar: a frame (its own art, or the Journal trough until then) round a gold fill.
local frameArt = (Art.BarFrame.Image ~= "") and Art.BarFrame or Art.BarFrameFallback
local bar = make("Frame", {
	Name = "Bar", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 64),
	Size = UDim2.new(1, 0, 0, BAR_H), BackgroundTransparency = 1, ZIndex = 4,
}, panel)
local inset = frameArt.FillInset
local fillHost = make("Frame", {
	Position = UDim2.fromOffset(inset.X, inset.Y), Size = UDim2.new(1, -inset.X * 2, 1, -inset.Y * 2),
	BackgroundColor3 = Color3.fromRGB(20, 14, 10), BackgroundTransparency = 0.2, BorderSizePixel = 0,
	ClipsDescendants = true, ZIndex = 4,
}, bar)
local fill = make("Frame", {
	Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 5,
	ClipsDescendants = true, -- the grain runs wider than the fill
}, fillHost)
make("UIGradient", {
	Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 232, 160), Color3.fromRGB(200, 138, 58)),
}, fill)
local grain = make("ImageLabel", {
	Size = UDim2.new(1, 256, 1, 0), BackgroundTransparency = 1, Image = Art.Grain, ImageTransparency = 0.55,
	ScaleType = Enum.ScaleType.Tile, TileSize = UDim2.fromOffset(256, 32), ZIndex = 6,
}, fill)
make("ImageLabel", {
	Name = "Frame", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = frameArt.Image,
	ScaleType = Enum.ScaleType.Slice, SliceCenter = frameArt.SliceCenter, SliceScale = frameArt.SliceScale, ZIndex = 7,
}, bar)
-- The glow (and the leaf, once drawn) at the fill's leading edge.
local headGlow = make("ImageLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(BAR_H * 2.6, BAR_H * 2.6),
	BackgroundTransparency = 1, Image = Art.Glow, ImageColor3 = GOLD, ImageTransparency = 0.35, ZIndex = 8,
}, bar)
local headLeaf = Art.BarHead.Image ~= "" and make("ImageLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(BAR_H * 1.3 * Art.BarHead.Aspect, BAR_H * 1.3),
	BackgroundTransparency = 1, Image = Art.BarHead.Image, ScaleType = Enum.ScaleType.Fit, ZIndex = 9,
}, bar) or nil

local tip = make("TextLabel", {
	Name = "Tip", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 64 + BAR_H + 18),
	Size = UDim2.new(1, 120, 0, 44), BackgroundTransparency = 1, Text = "", FontFace = FONT_TIP, TextSize = 20,
	TextColor3 = BONE, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 4,
}, panel)
make("UIStroke", { Color = INK, Thickness = 1.5, Transparency = 0.35 }, tip)

-- Replaces the bouncing word once everything is in. Pulses gently until the player clicks.
local startPrompt = make("TextLabel", {
	Name = "StartPrompt", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0),
	Size = UDim2.new(1, 120, 0, 56), BackgroundTransparency = 1, FontFace = FONT, TextSize = WORD_SIZE,
	TextColor3 = BONE, TextYAlignment = Enum.TextYAlignment.Bottom, TextTransparency = 1, Visible = false, ZIndex = 4,
	Text = (UserInputService.TouchEnabled and not UserInputService.MouseEnabled) and "Tap anywhere to start"
		or "Click anywhere to start",
}, panel)
local startStroke = make("UIStroke", { Color = INK, Thickness = 2, Transparency = 1 }, startPrompt)

-- Black over everything: it starts closed (the art loads and draws behind it), opens at the
-- reveal, and closes again for the fade into the game.
local curtain = make("Frame", {
	Name = "Curtain", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 20,
}, gui)

-- Cover-fit the painting and size the panel to the window.
local function fit()
	local camera = workspace.CurrentCamera
	local vp = camera and camera.ViewportSize or Vector2.new(1280, 720)
	if vp.X < 2 or vp.Y < 2 then return end
	local w, h = vp.X, vp.X / bg.Aspect
	if h < vp.Y then w, h = vp.Y * bg.Aspect, vp.Y end
	painting.Size = UDim2.fromOffset(math.ceil(w) + 2, math.ceil(h) + 2)
	panel.Size = UDim2.fromOffset(math.min(BAR_MAX_W, vp.X - 64), 150)
end
fit()
local fitConn
local function watchCamera()
	if fitConn then fitConn:Disconnect() end
	local camera = workspace.CurrentCamera
	if camera then fitConn = camera:GetPropertyChangedSignal("ViewportSize"):Connect(fit) end
	fit()
end
watchCamera()
local cameraConn = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera)

---------------------------------------------------------------------------
-- Ambient life: specks of light drifting up, leaves drifting down
---------------------------------------------------------------------------

local rng = Random.new()
local particles = {}

local function resetMote(p, anywhere)
	p.x = rng:NextNumber(0, 1)
	p.y = anywhere and rng:NextNumber(0.35, 1.05) or rng:NextNumber(1.0, 1.08)
	p.speed = rng:NextNumber(0.012, 0.03) -- screen heights per second
	p.sway, p.phase = rng:NextNumber(0.004, 0.012), rng:NextNumber(0, 6.28)
	local size = rng:NextNumber(6, 16)
	p.inst.Size = UDim2.fromOffset(size, size)
	p.alpha = rng:NextNumber(0.35, 0.7)
end

for _ = 1, MOTES do
	local p = { kind = "mote" }
	p.inst = make("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Image = Art.Glow, ImageColor3 = GOLD, ZIndex = 2,
	}, fx)
	resetMote(p, true)
	table.insert(particles, p)
end

local function resetLeaf(p, anywhere)
	local leaf = Art.Leaves[rng:NextInteger(1, #Art.Leaves)]
	p.inst.Image, p.inst.ImageRectOffset, p.inst.ImageRectSize = leaf.Image, leaf.Offset, leaf.Size
	p.x = anywhere and rng:NextNumber(0, 1) or rng:NextNumber(-0.1, 0.9)
	p.y = anywhere and rng:NextNumber(-0.1, 0.8) or rng:NextNumber(-0.15, -0.05)
	p.speed = rng:NextNumber(0.05, 0.09)
	p.drift = rng:NextNumber(0.02, 0.05) -- the breeze carries them right, like the painting's light
	p.sway, p.phase = rng:NextNumber(0.01, 0.025), rng:NextNumber(0, 6.28)
	p.spin = rng:NextNumber(-90, 90)
	local size = rng:NextNumber(18, 34)
	p.inst.Size = UDim2.fromOffset(size, size)
end

if #Art.Leaves > 0 then
	for _ = 1, LEAVES do
		local p = { kind = "leaf" }
		p.inst = make("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, ZIndex = 2,
		}, fx)
		resetLeaf(p, true)
		table.insert(particles, p)
	end
end

---------------------------------------------------------------------------
-- Animation
---------------------------------------------------------------------------

local shownProgress, targetProgress = 0, 0
local t = 0
local tipIndex = rng:NextInteger(1, #TIPS)
local tipClock = 0
local TIP_EVERY = 6
tip.Text = TIPS[tipIndex]

local renderConn = RunService.RenderStepped:Connect(function(dt)
	t += dt

	-- The word: one letter hops at a time, left to right, then a pause.
	local cycle = (#WORD - 1) * HOP_STEP + HOP_TIME + HOP_REST
	local c = t % cycle
	for i, letter in ipairs(letters) do
		local u = (c - (i - 1) * HOP_STEP) / HOP_TIME
		local lift = (u >= 0 and u <= 1) and math.sin(u * math.pi) or 0
		letter.Position = UDim2.fromOffset(0, -lift * HOP_HEIGHT)
		letter.TextColor3 = BONE:Lerp(GOLD, lift)
	end

	if startPrompt.Visible and startPrompt:GetAttribute("Shown") then
		local pulse = 0.5 + math.sin(t * 2.6) * 0.5
		startPrompt.TextTransparency = pulse * 0.45
		startPrompt.TextColor3 = BONE:Lerp(GOLD, 1 - pulse)
	end

	-- The bar eases toward the real progress and never runs backwards.
	shownProgress += (targetProgress - shownProgress) * math.min(1, dt * 5)
	fill.Size = UDim2.fromScale(shownProgress, 1)
	grain.Position = UDim2.fromOffset(-((t * 30) % 256), 0)
	local headX = inset.X + fillHost.AbsoluteSize.X * shownProgress
	headGlow.Position = UDim2.new(0, headX, 0.5, 0)
	headGlow.ImageTransparency = 0.45 + math.sin(t * 3) * 0.12
	if headLeaf then
		headLeaf.Position = UDim2.new(0, headX, 0.5, 0)
		headLeaf.Rotation = math.sin(t * 2.2) * 12
	end

	-- The painting breathes in, very slowly.
	paintingScale.Scale = 1 + math.min(t, 40) / 40 * 0.04

	for _, p in ipairs(particles) do
		if p.kind == "mote" then
			p.y -= p.speed * dt
			if p.y < 0.3 then resetMote(p, false) end
			-- fade in from the bottom, out toward the top
			local edge = math.clamp((p.y - 0.3) / 0.2, 0, 1) * math.clamp((1.08 - p.y) / 0.1, 0, 1)
			p.inst.ImageTransparency = 1 - p.alpha * edge * (0.75 + math.sin(t * 2 + p.phase) * 0.25)
			p.inst.Position = UDim2.fromScale(p.x + math.sin(t * 0.8 + p.phase) * p.sway, p.y)
		else
			p.y += p.speed * dt
			p.x += p.drift * dt
			if p.y > 1.1 or p.x > 1.1 then resetLeaf(p, false) end
			p.inst.Position = UDim2.fromScale(p.x + math.sin(t * 1.3 + p.phase) * p.sway, p.y)
			p.inst.Rotation = (p.inst.Rotation + p.spin * dt) % 360
		end
	end

	-- A new tip every few seconds, crossfaded.
	tipClock += dt
	if tipClock > TIP_EVERY then
		tipClock = 0
		tipIndex = tipIndex % #TIPS + 1
		local nextTip = TIPS[tipIndex]
		local out = TweenService:Create(tip, TweenInfo.new(0.35), { TextTransparency = 1 })
		out.Completed:Once(function()
			tip.Text = nextTip
			TweenService:Create(tip, TweenInfo.new(0.35), { TextTransparency = 0 }):Play()
		end)
		out:Play()
	end
end)

---------------------------------------------------------------------------
-- Loading
---------------------------------------------------------------------------

local function raise(p)
	targetProgress = math.max(targetProgress, math.clamp(p, 0, 1))
end

-- Waits until `done()` or `timeout` seconds pass.
local function waitUntil(done, timeout)
	local deadline = os.clock() + timeout
	while not done() and os.clock() < deadline do
		task.wait(0.05)
	end
end

-- This screen's own art first, on its own: the painting, the bar frame, the leaves, the glow.
-- Preloading the ScreenGui fetches every image in it. Nothing else is requested until this is
-- done, so the bulk preload below can't compete with it for bandwidth. "Loaded" only means
-- downloaded, not drawn: the pieces are already on screen under the closed curtain (and under
-- Roblox's own screen), so they're uploaded and drawn too by the time the curtain opens.
do
	local ready = false
	task.spawn(function()
		pcall(ContentProvider.PreloadAsync, ContentProvider, { gui })
		ready = true
	end)
	waitUntil(function() return ready end, OWN_ART_TIMEOUT)
	RunService.RenderStepped:Wait() -- a frame or two drawn behind the curtain
	RunService.RenderStepped:Wait()
end
ReplicatedFirst:RemoveDefaultLoadingScreen()
TweenService:Create(curtain, TweenInfo.new(REVEAL, Enum.EasingStyle.Sine), { BackgroundTransparency = 1 }):Play()
local startedAt = os.clock()

-- Everything worth having ready before the first look round: the icon and UI art registries,
-- the sound effects and animations, and the images already in the player's GUIs. Music and
-- meshes are left to stream in as usual (large, and only heard or seen later).
local function gatherContent()
	local list, seen = {}, {}
	local function addString(id)
		if type(id) == "string" and id:match("^rbxassetid://%d+$") and not seen[id] then
			seen[id] = true
			table.insert(list, id)
		end
	end
	local function addInstance(class, prop, id)
		if type(id) == "string" and id:match("^rbxassetid://%d+$") and not seen[id] then
			seen[id] = true
			local inst = Instance.new(class)
			inst[prop] = id
			table.insert(list, inst)
		end
	end
	local function walk(value, add, visited)
		if type(value) == "string" then
			add(value)
		elseif type(value) == "table" and not visited[value] then
			visited[value] = true
			for _, v in pairs(value) do walk(v, add, visited) end
		end
	end
	local function requireAll(folder, add)
		if not folder then return end
		for _, m in ipairs(folder:GetDescendants()) do
			if m:IsA("ModuleScript") then
				local ok, data = pcall(require, m)
				if ok then walk(data, add, {}) end
			end
		end
	end

	local assets = game:GetService("ReplicatedStorage"):WaitForChild("Assets", 10)
	if assets then
		requireAll(assets:FindFirstChild("Icons"), addString)
		requireAll(assets:FindFirstChild("Images"), addString)
		requireAll(assets:FindFirstChild("Appearance"), addString) -- face decals (eyes, nose, mouth)
		requireAll(assets:FindFirstChild("Animations"), function(id) addInstance("Animation", "AnimationId", id) end)
		local sounds = assets:FindFirstChild("Sounds")
		local effects = sounds and sounds:FindFirstChild("SoundEffects")
		if effects then
			local ok, data = pcall(require, effects)
			if ok then walk(data, function(id) addInstance("Sound", "SoundId", id) end, {}) end
		end
	end
	for _, d in ipairs(player:WaitForChild("PlayerGui"):GetDescendants()) do
		if (d:IsA("ImageLabel") or d:IsA("ImageButton")) and not d:IsDescendantOf(gui) then
			addString(d.Image)
		end
	end
	-- The hair / beard pieces the wardrobe and AppearanceApply clone onto characters (meshes and
	-- their textures): preloading the folder fetches everything inside it.
	local characterParts = ReplicatedFirst:FindFirstChild("CharacterParts")
	if characterParts then table.insert(list, characterParts) end
	return list
end

local function load()
	-- 1. The game itself.
	if not game:IsLoaded() then
		local loaded = false
		task.spawn(function() game.Loaded:Wait(); loaded = true end)
		waitUntil(function() return loaded or game:IsLoaded() end, MAX_WAIT / 3)
	end
	raise(0.1)

	-- 2. Assets, counted one by one as they come in.
	local list = gatherContent()
	if #list > 0 then
		local finished, count = false, 0
		task.spawn(function()
			pcall(ContentProvider.PreloadAsync, ContentProvider, list, function()
				count += 1
				raise(0.1 + 0.75 * count / #list)
			end)
			finished = true
		end)
		waitUntil(function() return finished end, PRELOAD_TIMEOUT)
	end
	raise(0.85)

	-- 3. The character, standing in the world -- and, for a new player, moved into their own
	-- copy of the tutorial area (the server clears SpawnPending once it has), so the jump
	-- happens behind this screen.
	waitUntil(function()
		local character = player.Character
		return character ~= nil and character:FindFirstChild("HumanoidRootPart") ~= nil
			and player:GetAttribute("SpawnPending") ~= true
	end, CHARACTER_TIMEOUT)
	raise(1)
end

local loadDone = false
task.spawn(function()
	load()
	loadDone = true
end)
waitUntil(function() return loadDone end, MAX_WAIT)
raise(1)

-- Let the bar visibly reach the end, and keep the screen up for its minimum.
waitUntil(function() return shownProgress > 0.985 end, 1.5)
local shownFor = os.clock() - startedAt
if shownFor < MIN_SHOW then task.wait(MIN_SHOW - shownFor) end

---------------------------------------------------------------------------
-- Ready: the word gives way to "Click anywhere to start", and the screen waits for the player
---------------------------------------------------------------------------

awaitingClick = true
for _, letter in ipairs(letters) do
	TweenService:Create(letter, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
	TweenService:Create(letter:FindFirstChildOfClass("UIStroke"), TweenInfo.new(0.3), { Transparency = 1 }):Play()
end
task.wait(0.3)
wordRow.Visible = false
startPrompt.Visible = true
TweenService:Create(startStroke, TweenInfo.new(0.4), { Transparency = 0.2 }):Play()
local appear = TweenService:Create(startPrompt, TweenInfo.new(0.4), { TextTransparency = 0 })
appear:Play()
appear.Completed:Wait()
startPrompt:SetAttribute("Shown", true) -- hand the text over to the pulse

-- A full-screen button takes the click (or tap), so the same click doesn't also swing a sword
-- or fire a bow in the game underneath. Enter, Space and a gamepad's A start it too.
local clicked = false
local catcher = make("TextButton", {
	Name = "ClickCatcher", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "",
	AutoButtonColor = false, ZIndex = 19,
}, gui)
catcher.Activated:Connect(function() clicked = true end)
local keyConn = UserInputService.InputBegan:Connect(function(input)
	local key = input.KeyCode
	if key == Enum.KeyCode.Return or key == Enum.KeyCode.Space or key == Enum.KeyCode.ButtonA then
		clicked = true
	end
end)
while not clicked do
	task.wait()
end
keyConn:Disconnect()

---------------------------------------------------------------------------
-- Hand over: fade to black, drop the screen, fade the game in
---------------------------------------------------------------------------

local fadeOut = TweenService:Create(curtain, TweenInfo.new(FADE_OUT, Enum.EasingStyle.Sine), { BackgroundTransparency = 0 })
fadeOut:Play()
fadeOut.Completed:Wait()
renderConn:Disconnect()
cameraConn:Disconnect()
if fitConn then fitConn:Disconnect() end
base:Destroy()
player:SetAttribute("LoadingScreenDone", true)
local fadeIn = TweenService:Create(curtain, TweenInfo.new(FADE_IN, Enum.EasingStyle.Sine), { BackgroundTransparency = 1 })
fadeIn:Play()
fadeIn.Completed:Wait()
gui:Destroy()
