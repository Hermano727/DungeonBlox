-- Attacker-local world effects, driven by confirmed damage only.
-- Detached from the victim so killing blows survive model teardown.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Config = require(ReplicatedStorage:WaitForChild("EnchantHitEffectConfig"))
local Motion = require(ReplicatedStorage:WaitForChild("EnchantHitEffectMotion"))

local Effects = {}
local active = {}
local recent = setmetatable({}, { __mode = "k" })
local connection
local folder

local function part(group, color, wedge)
	local p = Instance.new(wedge and "WedgePart" or "Part")
	p.Name = "EnchantFragment"
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 1
	p.Parent = group
	return p
end

local function pose(p, frame, size, transparency)
	p.Size = size
	p.CFrame = frame
	p.Transparency = math.clamp(transparency, 0, 1)
end

local function line(p, base, a, b, width, alpha)
	local delta = b - a
	if delta.Magnitude < 0.001 then p.Transparency = 1; return end
	pose(p, base * CFrame.lookAt((a + b) * 0.5, b), Vector3.new(width, width, delta.Magnitude), alpha)
end

local function radial(angle, radius)
	return Vector3.new(math.cos(angle) * radius, math.sin(angle) * radius, 0)
end

local builders = {}

function builders.Execute(group, cfg, scale)
	local jaws, embers = {}, {}
	for _, side in ipairs({ -1, 1 }) do
		for i = 1, 9 do
			table.insert(jaws, { part = part(group, cfg.Color), side = side, index = i })
		end
		for i = 1, 5 do
			table.insert(jaws, { part = part(group, cfg.Accent, true), side = side, index = i, tooth = true })
		end
	end
	for i = 1, 7 do embers[i] = part(group, cfg.Accent) end
	return function(t, base)
		local s = Motion.State("Execute", t)
		for _, jaw in ipairs(jaws) do
			local side = jaw.side
			local gap = (1 - s.close) * 0.85 * scale
			if jaw.tooth then
				local x = (jaw.index - 3) * 0.30 * scale
				local y = side * (gap + 0.15 + math.abs(x) * 0.17)
				pose(jaw.part, base * CFrame.new(x, y, 0) * CFrame.Angles(0, math.pi / 2, side == 1 and math.pi or 0),
					Vector3.new(0.07, 0.32, 0.24) * scale, s.fade)
			else
				local a = math.pi * (jaw.index - 1) / 9
				local b = math.pi * jaw.index / 9
				local function edge(angle)
					return Vector3.new(math.cos(angle) * 0.95, side * (math.sin(angle) * 0.52 + gap / scale), 0) * scale
				end
				line(jaw.part, base, edge(a), edge(b), 0.11 * scale, s.fade)
			end
		end
		for i, p in ipairs(embers) do
			local a = i * 2.399
			local pos = radial(a, s.burst * 1.35 * scale) + Vector3.new(0, s.burst * 0.35 * scale, 0.04)
			pose(p, base * CFrame.new(pos) * CFrame.Angles(0, 0, a), Vector3.new(0.055, 0.16, 0.055) * scale,
				t < 0.28 and 1 or s.fade)
		end
	end
end

function builders.Shatter(group, cfg, scale)
	local plates, cracks = {}, {}
	for i = 1, 8 do
		plates[i] = part(group, cfg.Color, true)
		plates[i].Material = Enum.Material.SmoothPlastic
		cracks[i] = part(group, cfg.Accent)
	end
	return function(t, base)
		local s = Motion.State("Shatter", t)
		for i = 1, 8 do
			local angle = i * math.pi / 4
			local pos = radial(angle, (0.42 + s.burst * 1.2) * scale)
			pos += Vector3.new(0, -s.burst ^ 2 * 0.42 * scale, s.burst * (i % 3) * 0.12)
			pose(plates[i], base * CFrame.new(pos) * CFrame.Angles(0, 0, angle - math.pi / 2)
				* CFrame.Angles(s.burst * 1.8, math.pi / 2, s.burst * (i % 2 == 0 and 1 or -1)),
				Vector3.new(0.09, 0.66, 0.46) * scale, 0.16 + s.fade * 0.84)
			line(cracks[i], base, radial(angle + 0.12, 0.10 * scale),
				radial(angle, (0.10 + s.crack * 0.78) * scale) + Vector3.new(0, 0, 0.08),
				0.035 * scale, t > 0.30 and math.clamp((t - 0.30) / 0.18, 0, 1) or 0)
		end
	end
end

function builders.Crushing(group, cfg, scale)
	local inward, ring, chips = {}, {}, {}
	for i = 1, 8 do inward[i] = part(group, cfg.Color, true) end
	for i = 1, 16 do ring[i] = part(group, cfg.Accent) end
	for i = 1, 5 do chips[i] = part(group, cfg.Color, true); chips[i].Material = Enum.Material.Slate end
	return function(t, base)
		local s = Motion.State("Crushing", t)
		for i, p in ipairs(inward) do
			local angle = i * math.pi / 4
			pose(p, base * CFrame.new(radial(angle, (1.05 - s.compress * 0.92) * scale))
				* CFrame.Angles(0, 0, angle) * CFrame.Angles(0, math.pi / 2, 0),
				Vector3.new(0.12, 0.34, 0.42) * scale, Motion.Progress(t, 0.34, 0.55))
		end
		local radius = (0.20 + s.burst * 1.25) * scale
		for i, p in ipairs(ring) do
			local a = radial((i - 1) * math.pi / 8, radius)
			local b = radial(i * math.pi / 8, radius)
			line(p, base, a, b, (0.14 - s.burst * 0.10) * scale, t < 0.34 and 1 or s.fade)
		end
		for i, p in ipairs(chips) do
			local pos = Vector3.new((i - 3) * s.burst * 0.35, -s.burst ^ 2 * 1.4, 0.1) * scale
			pose(p, base * CFrame.new(pos) * CFrame.Angles(s.burst * i, 0, i),
				Vector3.new(0.10, 0.17, 0.22) * scale, t < 0.34 and 1 or s.fade)
		end
	end
end

function builders.Piercing(group, cfg, scale)
	local needle = part(group, cfg.Accent)
	local sparks = {}
	for i = 1, 5 do sparks[i] = part(group, cfg.Color) end
	return function(t, base, axis)
		local s = Motion.State("Piercing", t)
		local z = (-0.65 + s.thrust * 1.9) * scale
		pose(needle, axis * CFrame.new(0, 0, -z), Vector3.new(0.045, 0.045, 1.25) * scale, s.fade)
		for i, p in ipairs(sparks) do
			local angle = i * 2.399
			local pos = radial(angle, s.burst * 0.28 * scale) + Vector3.new(0, 0, -(0.15 + s.burst * 1.5) * scale)
			pose(p, axis * CFrame.new(pos) * CFrame.Angles(math.sin(angle) * 0.2, math.cos(angle) * 0.2, 0),
				Vector3.new(0.025, 0.025, 0.26) * scale, t < 0.20 and 1 or s.fade)
		end
	end
end

function builders.Cleave(group, cfg, scale)
	local arc = {}
	for i = 1, 14 do arc[i] = part(group, i % 2 == 0 and cfg.Color or cfg.Accent) end
	return function(t, base)
		local sweep = Motion.Out(Motion.Progress(t, 0, 0.55))
		for i, p in ipairs(arc) do
			local a = -1.15 + (i - 1) * 0.15
			local b = a + 0.15
			local radius = (0.9 + sweep * 0.8) * scale
			local origin = Vector3.new((sweep - 0.5) * 1.2 * scale, 0, 0)
			line(p, base * CFrame.Angles(0, 0, -0.35), origin + radial(a, radius), origin + radial(b, radius),
				(0.035 + math.sin(i / 15 * math.pi) * 0.10) * scale,
				i / 14 > sweep and 1 or Motion.Progress(t, 0.30 + i * 0.02, 1))
		end
	end
end

function builders.Bleeding(group, cfg, scale)
	local wound = part(group, cfg.Color)
	local drops = {}
	for i = 1, 3 do drops[i] = part(group, cfg.Accent, true) end
	return function(t, base)
		line(wound, base, Vector3.new(-0.22, 0.22, 0) * scale, Vector3.new(0.16, -0.18, 0) * scale,
			0.075 * scale, Motion.Progress(t, 0.12, 0.65))
		for i, p in ipairs(drops) do
			local fall = Motion.Progress(t, i * 0.08, 1)
			pose(p, base * CFrame.new((i - 2) * 0.13 * scale, -fall ^ 2 * 1.1 * scale, 0.06),
				Vector3.new(0.045, 0.12 + fall * 0.10, 0.055) * scale, t < i * 0.08 and 1 or Motion.Progress(t, 0.55, 1))
		end
	end
end

function builders.Blinding(group, cfg, scale)
	local rays, halo = {}, {}
	for i = 1, 6 do rays[i] = part(group, cfg.Accent) end
	for i = 1, 10 do halo[i] = part(group, cfg.Color) end
	return function(t, base)
		local pop = Motion.Out(Motion.Progress(t, 0, 0.18))
		for i, p in ipairs(rays) do
			local angle = i * math.pi / 3
			line(p, base, radial(angle, 0.10 * scale), radial(angle, pop * (i % 2 == 0 and 0.72 or 0.44) * scale),
				0.045 * scale, Motion.Progress(t, 0.14, 0.48))
		end
		for i, p in ipairs(halo) do
			local a = (i - 1) * math.pi / 5 + t * 0.25
			line(p, base, radial(a, (0.48 + t * 0.15) * scale), radial(a + 0.30, (0.48 + t * 0.15) * scale),
				0.03 * scale, t < 0.12 and 1 or Motion.Progress(t, 0.25, 1))
		end
	end
end

function builders.Slowness(group, cfg, scale)
	local bands = {}
	for i = 1, 12 do bands[i] = part(group, i % 3 == 0 and cfg.Accent or cfg.Color) end
	return function(t, base)
		local settle = Motion.Out(Motion.Progress(t, 0, 0.35))
		for i, p in ipairs(bands) do
			local side = i <= 6 and -1 or 1
			local a = (i % 6) * math.pi / 3 + t * 0.3
			local radius = (0.48 - settle * 0.18) * scale
			local function point(angle)
				return Vector3.new(side * 0.28 * scale + math.cos(angle) * radius, (1 - settle) * 0.35 * scale, math.sin(angle) * radius)
			end
			line(p, base, point(a), point(a + 0.82), 0.05 * scale, Motion.Progress(t, 0.45, 1))
		end
	end
end

function builders.Elemental(group, cfg, scale)
	-- Current data has a single elemental bonus (named-elite data calls it fire).
	local embers = {}
	for i = 1, 7 do embers[i] = part(group, i % 2 == 0 and cfg.Color or cfg.Accent, true) end
	return function(t, base)
		for i, p in ipairs(embers) do
			local rise = Motion.Progress(t, (i % 3) * 0.04, 1)
			local pos = Vector3.new(math.sin(i * 2.4) * (0.16 + rise * 0.38), rise * (0.55 + i * 0.07), 0.03) * scale
			pose(p, base * CFrame.new(pos) * CFrame.Angles(0, 0, math.sin(i) * rise),
				Vector3.new(0.055, 0.14 * (1 - rise) + 0.03, 0.05) * scale, Motion.Progress(t, 0.30, 1))
		end
	end
end

function builders.Glowing(group, cfg, scale)
	local core = part(group, cfg.Accent)
	local motes = {}
	for i = 1, 4 do motes[i] = part(group, cfg.Color) end
	return function(t, base)
		local fade = Motion.Progress(t, 0.10, 1)
		local pulse = (0.12 + math.sin(t * math.pi) * 0.10) * scale
		pose(core, base * CFrame.Angles(0, 0, math.pi / 4), Vector3.new(pulse, pulse, 0.035), fade)
		for i, p in ipairs(motes) do
			local pos = radial(i * math.pi / 2 + t, (0.17 + t * 0.12) * scale)
			pose(p, base * CFrame.new(pos), Vector3.new(0.035, 0.06, 0.035) * scale, fade)
		end
	end
end

local function remove(index)
	active[index].group:Destroy()
	table.remove(active, index)
end

local function update()
	local now = os.clock()
	for i = #active, 1, -1 do
		local effect = active[i]
		local t = (now - effect.started) / effect.duration
		if t >= 1 or not effect.group.Parent then remove(i)
		else
			if effect.anchor and effect.anchor.Parent then effect.frame = effect.anchor.CFrame * effect.anchorOffset end
			effect.render(t, effect.frame, effect.axis)
		end
	end
	if #active == 0 and connection then connection:Disconnect(); connection = nil end
end

function Effects.Play(kind, position, direction, scale, anchor)
	local cfg, builder = Config[kind], builders[kind]
	local camera = Workspace.CurrentCamera
	if not cfg or not builder or not camera or typeof(position) ~= "Vector3" then return end
	if (camera.CFrame.Position - position).Magnitude > Config.MaxDistance then return end
	scale = math.clamp(tonumber(scale) or 1, 0.65, 1.6)
	if typeof(direction) ~= "Vector3" or direction.Magnitude < 0.01 then direction = camera.CFrame.LookVector end
	direction = direction.Unit
	if not folder or not folder.Parent then
		folder = Instance.new("Folder")
		folder.Name = "LocalEnchantHitEffects"
		folder.Parent = Workspace
	end
	while #active >= Config.MaxActiveEffects do remove(1) end
	local group = Instance.new("Model")
	group.Name = kind
	group.Parent = folder
	-- Camera-facing silhouette fixed at impact; does not orbit when the camera turns.
	local frame = CFrame.new(position) * camera.CFrame.Rotation
	if kind == "Slowness" then frame = CFrame.new(position) end
	local up = math.abs(direction.Y) > 0.98 and Vector3.xAxis or Vector3.yAxis
	local axis = CFrame.lookAt(position, position + direction, up)
	local render = builder(group, cfg, scale)
	local effect = { group = group, frame = frame, axis = axis, render = render, started = os.clock(), duration = cfg.Duration }
	if anchor and anchor:IsA("BasePart") then
		effect.anchor = anchor
		effect.anchorOffset = anchor.CFrame:ToObjectSpace(frame)
	end
	table.insert(active, effect)
	render(0, frame, axis)
	if not connection then connection = RunService.RenderStepped:Connect(update) end
end

function Effects.PlayHit(payload, target)
	if type(payload) ~= "table" or type(payload.effects) ~= "table" then return end
	local now = os.clock()
	local last = target and recent[target] or {}
	if target then recent[target] = last end
	for _, kind in ipairs(Config.Order) do
		if payload.effects[kind] == true and (not last[kind] or now - last[kind] >= Config.SameEffectInterval) then
			last[kind] = now
			local anchor, position
			if target and typeof(target) == "Instance" and target:IsA("Model") then
				if kind == "Blinding" then
					anchor = target:FindFirstChild("Head") or target.PrimaryPart
					position = anchor and anchor.Position
				elseif kind == "Slowness" then
					anchor = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
					local hum = target:FindFirstChildOfClass("Humanoid")
					position = anchor and (anchor.Position - Vector3.new(0, math.max(0, anchor.Size.Y / 2 + (hum and hum.HipHeight or 0) - 0.25), 0))
				end
			end
			Effects.Play(kind, position or payload.position, payload.direction, payload.scale, anchor)
		end
	end
end

function Effects.Clear()
	if connection then connection:Disconnect(); connection = nil end
	for i = #active, 1, -1 do remove(i) end
	if folder then folder:Destroy(); folder = nil end
	table.clear(recent)
end

script.Destroying:Connect(Effects.Clear)
return Effects
