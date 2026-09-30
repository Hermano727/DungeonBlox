--[[
	MiasmaArenaChannels -- drives the four gate channels and the centre basin that
	MiasmaArenaLayoutBuilder authored into the arena (MiasmaChannel_0N, MiasmaCenterBasin).

		Reset()          every channel and the basin back to poisoned sludge (cycle start,
		                 re-corruption, purge); all flood effects stop
		Prime(index)     that gate's leaf rises: water surges out of the gate and fills its
		                 OUTER run (apron, funnel, channel to the platform edge)
		Flow(indices)    success: the listed gates' inner runs and the basin fill with clean
		                 water, so the flood visibly reaches the centre

	Liquids are every BasePart whose name starts with OuterSludge / OuterWater / InnerSludge /
	InnerWater (one or more per run). Effects are the ParticleEmitters named OuterSurge,
	OuterFoam and InnerFoam under the channel model. Purely presentational; missing parts are
	skipped so a realm without the layout still runs.
]]

local TweenService = game:GetService("TweenService")

local Channels = {}
Channels.__index = Channels

local WATER_VISIBLE = .25
local SLUDGE_VISIBLE = 0
local SURGE_SECONDS = 4      -- the gate burst after a prime
local FOAM_SECONDS = 9       -- foam keeps racing down a run this long after it fills

local function tween(part, seconds, goal)
	if part and part:IsA("BasePart") then
		TweenService:Create(part, TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), goal):Play()
	end
end

local function collect(model, prefix, className)
	local found = {}
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA(className) and string.sub(item.Name, 1, #prefix) == prefix then
			table.insert(found, item)
		end
	end
	return found
end

local function setClean(sludge, water, clean, seconds)
	for _, part in ipairs(sludge) do tween(part, seconds, { Transparency = clean and 1 or SLUDGE_VISIBLE }) end
	for _, part in ipairs(water) do
		tween(part, seconds, { Transparency = clean and WATER_VISIBLE or 1 })
		local light = part:FindFirstChildOfClass("PointLight")
		if light then light.Enabled = clean end
	end
end

function Channels.new(resolver)
	local self = setmetatable({ Gates = {}, Basin = nil, Serial = 0 }, Channels)
	for index = 1, 4 do
		local model = resolver:ChannelModel(index)
		if model then
			self.Gates[index] = {
				OuterSludge = collect(model, "OuterSludge", "BasePart"),
				OuterWater = collect(model, "OuterWater", "BasePart"),
				InnerSludge = collect(model, "InnerSludge", "BasePart"),
				InnerWater = collect(model, "InnerWater", "BasePart"),
				Surge = collect(model, "OuterSurge", "ParticleEmitter"),
				OuterFoam = collect(model, "OuterFoam", "ParticleEmitter"),
				InnerFoam = collect(model, "InnerFoam", "ParticleEmitter"),
			}
		end
	end
	local basin = resolver:CenterBasin()
	if basin then
		self.Basin = { Sludge = { basin:FindFirstChild("Sludge") }, Water = { basin:FindFirstChild("Water") } }
	end
	return self
end

-- Turns emitters on for `seconds` (cancelled by Reset through the serial).
function Channels:_burst(emitters, seconds)
	if #emitters == 0 then return end
	for _, e in ipairs(emitters) do e.Enabled = true end
	local serial = self.Serial
	task.delay(seconds, function()
		if self.Serial ~= serial then return end
		for _, e in ipairs(emitters) do e.Enabled = false end
	end)
end

function Channels:_stopEffects()
	self.Serial += 1
	for _, gate in pairs(self.Gates) do
		for _, list in ipairs({ gate.Surge, gate.OuterFoam, gate.InnerFoam }) do
			for _, e in ipairs(list) do e.Enabled = false end
		end
	end
end

function Channels:Reset()
	self:_stopEffects()
	for _, gate in pairs(self.Gates) do
		setClean(gate.OuterSludge, gate.OuterWater, false, .8)
		setClean(gate.InnerSludge, gate.InnerWater, false, .8)
	end
	if self.Basin then setClean(self.Basin.Sludge, self.Basin.Water, false, .8) end
end

function Channels:Prime(index)
	local gate = self.Gates[index]
	if not gate then return end
	setClean(gate.OuterSludge, gate.OuterWater, true, 1.6)
	self:_burst(gate.Surge, SURGE_SECONDS)
	self:_burst(gate.OuterFoam, FOAM_SECONDS)
end

function Channels:Flow(indices)
	for _, index in ipairs(indices) do
		local gate = self.Gates[index]
		if gate then
			setClean(gate.OuterSludge, gate.OuterWater, true, .6)
			setClean(gate.InnerSludge, gate.InnerWater, true, 1.8)
			self:_burst(gate.Surge, SURGE_SECONDS)
			self:_burst(gate.OuterFoam, FOAM_SECONDS)
			self:_burst(gate.InnerFoam, FOAM_SECONDS)
		end
	end
	if self.Basin then
		task.delay(1.2, function() setClean(self.Basin.Sludge, self.Basin.Water, true, 1.5) end)
	end
end

return Channels
