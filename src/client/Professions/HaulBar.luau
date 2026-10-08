--[[
	HaulBar -- the spear-fishing haul bar (FishingClient's phase 3), painted (2026-10-03).

	A slice of seabed seen side-on inside a driftwood frame: water (code gradient) with drifting
	light shafts, sand and swaying kelp at the bottom, rising bubbles that pop, the rope-net catch
	zone, and the caught fish itself (its item icon) darting up and down. The line's progress is a
	rope trough on the right with the reel on top (its crank winds with the line). Art: RS/Assets/Images/FishingHaulArt.

		local bar = HaulBar.new(screenGui)
		bar:Show(fishId)                         -- at the start of the haul
		bar:Update(dt, haul, inZone)             -- every frame; haul = { zone, fish, fishGoal, progress }
		bar:Finish(caught)                       -- catch burst or snapped line
		bar:Hide()

	All positions are bar fractions (0 = bottom) like FishingClient's haul state; this module only
	draws. Everything animates from one Update call, no tweens left running.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FishingConfig = require(ReplicatedStorage:WaitForChild("FishingConfig"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local Images = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images")
local Art = require(Images:WaitForChild("FishingHaulArt"))
local HudArt = require(Images:WaitForChild("HudArt"))

local HaulBar = {}
HaulBar.__index = HaulBar

-- Design size (px), scaled to the screen by a UIScale.
local W, H = 150, 460
local WALL_X, WALL_Y = 20, 20 -- the water starts a little under the frame's walls (drawn ~25 px thick), so no gap shows
local WATER_W, WATER_H = W - WALL_X * 2, H - WALL_Y * 2
local TROUGH_W, TROUGH_H = 30, H * 0.8
local FISH_W, FISH_H = 66, 46
local MAX_BUBBLES = 28
local WATER_TOP = Color3.fromRGB(95, 168, 184)
local WATER_BOTTOM = Color3.fromRGB(22, 56, 74)
local IN_ZONE = Color3.fromRGB(120, 210, 110)
local OUT_ZONE = Color3.fromRGB(230, 90, 70)
local GOLD = Color3.fromRGB(232, 196, 120)
local CRANK_TURN = 1800 -- degrees the crank turns per full bar of line (5 turns); it unwinds when the line pays out
local REEL_NUDGE = 8 -- px right of the trough's centre, so the spool sits over the rope

local function make(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do inst[k] = v end
	inst.Parent = parent
	return inst
end

local function image(piece, props, parent)
	props.BackgroundTransparency = 1
	props.Image = piece.Image
	if piece.SliceCenter then
		props.ScaleType = Enum.ScaleType.Slice
		props.SliceCenter = piece.SliceCenter
	else
		props.ScaleType = props.ScaleType or Enum.ScaleType.Fit
	end
	return make("ImageLabel", props, parent)
end

function HaulBar.new(parent)
	local self = setmetatable({}, HaulBar)
	local root = make("Frame", {
		Name = "HaulBar", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 260, 0.5, 0),
		Size = UDim2.fromOffset(W + 14 + TROUGH_W, H), BackgroundTransparency = 1, Visible = false,
	}, parent)
	self.scale = make("UIScale", { Scale = 1 }, root)
	self.root = root

	-- The water: gradient, clipped so nothing escapes the frame.
	local water = make("Frame", {
		Name = "Water", Position = UDim2.fromOffset(WALL_X, WALL_Y), Size = UDim2.fromOffset(WATER_W, WATER_H),
		BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 1,
	}, root)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(WATER_TOP, WATER_BOTTOM) }, water)
	self.water = water

	self.rays = image(Art.Rays, {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), ZIndex = 2,
		Size = UDim2.fromOffset(WATER_W * 1.7, WATER_W * 1.7 / Art.Rays.Aspect), ImageTransparency = 0.5,
	}, water)

	-- The seabed and the kelp rooted in it (behind the fish and the net).
	local sandH = WATER_W * 1.3 / Art.Sand.Aspect
	image(Art.Sand, {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), ZIndex = 4,
		Size = UDim2.fromOffset(WATER_W * 1.3, sandH), ScaleType = Enum.ScaleType.Stretch,
	}, water)
	self.kelp = {}
	local kelps = {
		{ Art.KelpTall, 0.16, 150, 0, 1.2 },
		{ Art.KelpTall, 0.62, 105, 0.35, 1.6 }, -- a shorter, darker one further back
		{ Art.KelpBush, 0.86, 88, 0, 1.0 },
	}
	for i, k in ipairs(kelps) do
		local piece, x, height, dark, speed = k[1], k[2], k[3], k[4], k[5]
		local strand = image(piece, {
			AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(x, 0, 1, -sandH * 0.45),
			Size = UDim2.fromOffset(height * piece.Aspect, height), ZIndex = 3,
			ImageColor3 = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(40, 70, 70), dark),
		}, water)
		self.kelp[i] = { inst = strand, phase = i * 1.7, speed = speed }
	end

	-- Bubbles (pooled).
	self.bubbles, self.pool = {}, {}
	for i = 1, MAX_BUBBLES do
		self.pool[i] = image(Art.Bubble, { AnchorPoint = Vector2.new(0.5, 0.5), Visible = false, ZIndex = 5 }, water)
	end

	-- The catch zone: a soft wash behind the rope net (a square 3x4 net, drawn whole).
	local zone = make("Frame", {
		Name = "Zone", Size = UDim2.new(1, 0, FishingConfig.HAUL.ZONE, 0), BackgroundTransparency = 1, ZIndex = 6,
	}, water)
	self.zoneWash = make("Frame", {
		Size = UDim2.new(1, -8, 1, -8), Position = UDim2.fromOffset(4, 4), BackgroundColor3 = IN_ZONE,
		BackgroundTransparency = 0.78, BorderSizePixel = 0, ZIndex = 6,
	}, zone)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, self.zoneWash)
	image(Art.Zone, { Size = UDim2.fromScale(1, 1), ScaleType = Enum.ScaleType.Stretch, ZIndex = 7 }, zone)
	self.zone = zone

	-- The fish, and a glow behind rarer ones.
	self.glow = make("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(FISH_W * 1.6, FISH_W * 1.6),
		BackgroundTransparency = 1, Image = HudArt.GLOW_SOFT, ImageTransparency = 1, ZIndex = 8,
	}, water)
	self.fish = make("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(FISH_W, FISH_H),
		BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, ZIndex = 9,
	}, water)

	-- The driftwood frame over the water's edges.
	image(Art.Frame, { Size = UDim2.fromOffset(W, H), SliceScale = 0.42, ZIndex = 10 }, root)

	-- The line's progress: a rope trough with a gold fill, the reel on top.
	local trough = image(Art.Progress, {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromOffset(W + 14, H - 6),
		Size = UDim2.fromOffset(TROUGH_W, TROUGH_H), SliceScale = 0.35, ZIndex = 10,
	}, root)
	local fillHost = make("Frame", {
		Position = UDim2.fromOffset(8, 12), Size = UDim2.new(1, -16, 1, -24), BackgroundTransparency = 1,
		ClipsDescendants = true, ZIndex = 11,
	}, trough)
	self.fill = make("Frame", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = GOLD, BorderSizePixel = 0, ZIndex = 11,
	}, fillHost)
	make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 236, 170), Color3.fromRGB(196, 140, 60)) }, self.fill)
	local reelW = 64
	local reel = image(Art.Reel, {
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(W + 14 + TROUGH_W / 2 + REEL_NUDGE, H - 6 - TROUGH_H + 10),
		Size = UDim2.fromOffset(reelW, reelW / Art.Reel.Aspect), ZIndex = 12,
	}, root)
	-- The crank is its own piece, centred on its nut, so turning it spins it about the nut.
	local crank = Art.ReelCrank
	self.crank = image(crank, {
		AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 13,
		Position = UDim2.fromScale(crank.Pivot.X, crank.Pivot.Y),
		Size = UDim2.fromScale(crank.Size.X, crank.Size.Y), ScaleType = Enum.ScaleType.Stretch,
	}, reel)
	self.crankAngle = 0
	self.flash = make("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1,
		BorderSizePixel = 0, ZIndex = 9,
	}, water)
	return self
end

function HaulBar:Show(fishId)
	local viewport = workspace.CurrentCamera.ViewportSize
	self.scale.Scale = math.clamp(viewport.Y / 900, 0.75, 1.4)
	self.fish.Image = ItemDefinitions.GetIcon(fishId)
	self.fish.ImageTransparency, self.fish.ImageColor3, self.fish.Rotation = 0, Color3.new(1, 1, 1), 0
	local show = FishingConfig.CATCH_SHOW[fishId]
	-- Plain fish swim without a glow; the rarer ones carry their colour.
	self.glowColor = (show and fishId ~= "Fish") and show.color or nil
	self.glow.ImageColor3 = self.glowColor or Color3.new(1, 1, 1)
	self.glow.ImageTransparency = 1
	for _, b in ipairs(self.bubbles) do b.inst.Visible = false; table.insert(self.pool, b.inst) end
	table.clear(self.bubbles)
	self.t, self.spawnClock, self.lastFish, self.lastGoal, self.finish = 0, 0, nil, nil, nil
	self.lastProgress = nil
	self.root.Position = UDim2.new(0.5, 260, 0.5, 0)
	self.flash.BackgroundTransparency = 1
	self.root.Visible = true
end

function HaulBar:Hide()
	self.root.Visible = false
end

-- A bubble from (x, y) in water pixels (y down), sized `size`.
function HaulBar:spawnBubble(x, y, size)
	local inst = table.remove(self.pool)
	if not inst then return end
	inst.Visible = true
	inst.ImageTransparency = 0.15
	table.insert(self.bubbles, {
		inst = inst, x = x, y = y, size = size, age = 0, phase = math.random() * 6.28,
		speed = 38 + math.random() * 40, popAt = math.random() * WATER_H * 0.45, popping = nil,
	})
end

function HaulBar:burst(x, y, count)
	for _ = 1, count do
		self:spawnBubble(x + (math.random() - 0.5) * 20, y + (math.random() - 0.5) * 12, 6 + math.random() * 8)
	end
end

local function fishY(v)
	return (1 - v) * WATER_H
end

function HaulBar:Update(dt, haul, inZone)
	self.t += dt
	self.lastHaul = haul
	local t = self.t

	-- Water life: shafts drift and breathe, kelp sways.
	self.rays.Position = UDim2.new(0.5, math.sin(t * 0.35) * 10, 0, 0)
	self.rays.ImageTransparency = 0.55 + math.sin(t * 0.9) * 0.12
	for _, k in ipairs(self.kelp) do
		k.inst.Rotation = math.sin(t * k.speed + k.phase) * 7
	end

	-- The net, and its wash: green in, red (and jittering) out.
	local zoneTop = 1 - haul.zone - FishingConfig.HAUL.ZONE
	local jitter = inZone and 0 or (math.random() - 0.5) * 3
	self.zone.Position = UDim2.new(0, jitter, zoneTop, 0)
	self.zoneWash.BackgroundColor3 = inZone and IN_ZONE or OUT_ZONE
	self.zoneWash.BackgroundTransparency = inZone and (0.72 + math.sin(t * 6) * 0.06) or 0.68

	-- The fish: tilts with its motion (icons face left, so rising = nose up = clockwise),
	-- wiggles harder the faster it goes.
	local fishPx = fishY(haul.fish)
	local vel = self.lastFish and (haul.fish - self.lastFish) / math.max(dt, 1e-3) or 0
	self.lastFish = haul.fish
	local finishing = self.finish
	if not finishing then
		local tilt = math.clamp(vel * 60, -28, 28)
		self.fish.Rotation = tilt + math.sin(t * (12 + math.abs(vel) * 30)) * (3 + math.min(math.abs(vel) * 20, 6))
		self.fish.Position = UDim2.fromOffset(WATER_W / 2, fishPx)
		self.glow.Position = self.fish.Position
		if self.glowColor then
			self.glow.ImageTransparency = 0.5 + math.sin(t * 4) * 0.12
		end
	end
	-- A lunge (the fish picked a new spot) throws off a little burst.
	if self.lastGoal and math.abs(haul.fishGoal - self.lastGoal) > 0.05 then
		self:burst(WATER_W / 2 + 18, fishPx, 4)
	end
	self.lastGoal = haul.fishGoal

	-- Ambient bubbles from the seabed; more while the fish thrashes outside the net.
	self.spawnClock += dt * (inZone and 2.5 or 7)
	while self.spawnClock >= 1 do
		self.spawnClock -= 1
		self:spawnBubble(8 + math.random() * (WATER_W - 16), WATER_H - 10, 5 + math.random() * 7)
	end
	for i = #self.bubbles, 1, -1 do
		local b = self.bubbles[i]
		b.age += dt
		if b.popping then
			-- Pop: a quick swell as it vanishes.
			local u = (t - b.popping) / 0.12
			b.inst.Size = UDim2.fromOffset(b.size * (1 + u * 0.8), b.size * (1 + u * 0.8))
			b.inst.ImageTransparency = 0.15 + u * 0.85
			if u >= 1 then
				b.inst.Visible = false
				table.insert(self.pool, b.inst)
				table.remove(self.bubbles, i)
			end
		else
			b.y -= b.speed * dt
			local grow = 1 + math.min(b.age * 0.25, 0.35)
			b.inst.Size = UDim2.fromOffset(b.size * grow, b.size * grow)
			b.inst.Position = UDim2.fromOffset(b.x + math.sin(b.age * 3 + b.phase) * 5, b.y)
			if b.y <= b.popAt then b.popping = t end
		end
	end

	-- The line coming in: fill, and the crank winding with it (backwards while the fish takes line).
	if self.lastProgress then
		self.crankAngle = (self.crankAngle + (haul.progress - self.lastProgress) * CRANK_TURN) % 360
		self.crank.Rotation = self.crankAngle
	end
	self.lastProgress = haul.progress
	self.fill.Size = UDim2.fromScale(1, math.clamp(haul.progress, 0, 1))

	-- The finish: a short show, then FishingClient hides the bar.
	if finishing then
		local u = math.clamp((t - finishing.at) / 0.6, 0, 1)
		if finishing.caught then
			self.fish.Size = UDim2.fromOffset(FISH_W * (1 + u * 0.4), FISH_H * (1 + u * 0.4))
			self.fish.Position = UDim2.fromOffset(WATER_W / 2, fishPx - u * 40)
			self.flash.BackgroundTransparency = 0.4 + u * 0.6
		else
			self.fish.Position = UDim2.fromOffset(WATER_W / 2, fishPx + u * 80)
			self.fish.ImageTransparency = u
			self.root.Position = UDim2.new(0.5, 260 + (1 - u) * (math.random() - 0.5) * 8, 0.5, 0)
		end
	end
end

function HaulBar:Finish(caught)
	if self.finish then return end
	self.finish = { at = self.t, caught = caught }
	local x, y = WATER_W / 2, fishY(self.lastFish or 0.5)
	if caught then
		self:burst(x, y, 16)
		self.fish.ImageColor3 = Color3.fromRGB(255, 255, 240)
		self.flash.BackgroundTransparency = 0.4
	else
		self.zoneWash.BackgroundColor3 = OUT_ZONE
		self:burst(x, y, 6)
		self.glow.ImageTransparency = 1
	end
	-- Keep animating the finish for a moment even though the haul has stopped feeding us.
	local start = os.clock()
	task.spawn(function()
		local last = os.clock()
		while self.root.Visible and os.clock() - start < 0.8 do
			local now = os.clock()
			self:Update(now - last, self.lastHaul or { zone = 0, fish = self.lastFish or 0.5, fishGoal = self.lastGoal or 0.5, progress = self.lastProgress or 0 }, caught)
			last = now
			task.wait()
		end
	end)
end

return HaulBar
