--[[
	Wave -- the reveal pulse: a few shock rings sweeping out of a relic in its rarity's colour.

	Roblox has no shaders, so the wave is layered particles (docs/vfx-pipeline.md):
	  * flat rings    the swirled ShockRing sprite laid horizontal (a particle emitted straight up with
	                  VelocityPerpendicular faces along its travel, i.e. lies flat), spinning as it
	                  grows. Two or three of them a beat apart: that is the "pulse". Each starts
	                  white-hot and ends in the rarity colour.
	  * a face ring   the same sprite facing the camera, so the wave still reads from straight below
	                  (the ring hangs 20 studs up and players watch it from the floor)
	  * streaks       thin radial lines flung outward, fast and short
	  * motes         a shimmer of slow sparkles left drifting after the wave has passed
	The bigger the rarity, the bigger and the more numerous the rings. The relic's own light carries
	the flash. Built once per relic (the host part is the relic's moving holder) and fired once.

		local wave = Wave.new(hostPart, color, rank)    rank: 1 (Common) .. 6 (Mythic)
		wave:Fire()
]]

local Fx = require(script.Parent:WaitForChild("Fx"))

local keys = NumberSequenceKeypoint.new
local ckeys = ColorSequenceKeypoint.new
local WHITE = Color3.new(1, 1, 1)

local Wave = {}
Wave.__index = Wave

-- Fast at first, easing out: a wave, not a balloon.
local function growth(diameter)
	return NumberSequence.new({ keys(0, diameter * .1), keys(.18, diameter * .6), keys(.6, diameter * .9), keys(1, diameter) })
end

local function fade(first)
	return NumberSequence.new({ keys(0, first), keys(.45, first + (1 - first) * .3), keys(1, 1) })
end

-- White-hot at the front of its life, the rarity colour by the end.
local function tint(color)
	return ColorSequence.new({ ckeys(0, WHITE), ckeys(.3, WHITE:Lerp(color, .45)), ckeys(1, color) })
end

local function ring(host, color, diameter, first, facing)
	return Fx.emitter(host, {
		Texture = Fx.TEX.ShockRing, Color = tint(color), Size = growth(diameter), Transparency = fade(first),
		Lifetime = NumberRange.new(.5, .5), Speed = NumberRange.new(.6, .6), SpreadAngle = Vector2.zero,
		EmissionDirection = Enum.NormalId.Top,
		Orientation = facing and Enum.ParticleOrientation.FacingCamera or Enum.ParticleOrientation.VelocityPerpendicular,
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-150, 150), LightEmission = 1, LightInfluence = 0,
	})
end

function Wave.new(host, color, rank)
	local self = setmetatable({ flats = {} }, Wave)
	local diameter = 14 + 3.5 * rank
	-- One ring for the lowest rarities, two for Rare and Epic, three from Legendary: each a beat later,
	-- wider and fainter than the one before.
	local pulses = rank >= 5 and 3 or (rank >= 3 and 2 or 1)
	for pulse = 1, pulses do
		table.insert(self.flats, {
			emitter = ring(host, color, diameter * (1 + .3 * (pulse - 1)), .05 + .12 * (pulse - 1), false),
			delay = .085 * (pulse - 1),
		})
	end
	self.face = ring(host, color, diameter * .8, .12, true)
	self.streaks = Fx.emitter(host, {
		Texture = Fx.TEX.Ember, Color = ColorSequence.new(WHITE, color), Size = NumberSequence.new({ keys(0, 1.5), keys(1, .15) }),
		Squash = NumberSequence.new(-1.2), Transparency = NumberSequence.new({ keys(0, 0), keys(.7, .2), keys(1, 1) }),
		Lifetime = NumberRange.new(.16, .3), Speed = NumberRange.new(34, 58), Drag = 3,
		Shape = Enum.ParticleEmitterShape.Sphere, ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
	})
	self.motes = Fx.emitter(host, {
		Texture = Fx.TEX.Sparkle, Color = ColorSequence.new(WHITE, color), Size = NumberSequence.new({ keys(0, .7), keys(1, 0) }),
		Transparency = NumberSequence.new({ keys(0, .1), keys(1, 1) }), Lifetime = NumberRange.new(.8, 1.4),
		Speed = NumberRange.new(3, 11), SpreadAngle = Vector2.new(180, 180), Drag = 1.5,
	})
	self.rank = rank
	return self
end

function Wave:Fire()
	for _, flat in ipairs(self.flats) do
		if flat.delay <= 0 then
			flat.emitter:Emit(1)
		else
			task.delay(flat.delay, function()
				if flat.emitter.Parent then flat.emitter:Emit(1) end
			end)
		end
	end
	self.face:Emit(1)
	self.streaks:Emit(20 + 7 * self.rank)
	self.motes:Emit(14 + 5 * self.rank)
end

return Wave
