--[[
	Echo -- a fallen boss's spectral echo: a dark translucent body in a column of smoke with two
	burning eyes. It rises, then is shattered (a miniboss) or torn apart by a shockwave of light
	(the main boss), and the shards fall.

	One component, two users:
	  * BossEcho (the main boss): plays right after the boss's death animation, opening the show.
	  * Judgement (a miniboss): rises where it fell, just before its Mythic relic forms.

	spec = {
		final    = true for the main boss (bigger, roars, tears, shockwave of light)
		base     = Vector3: where it rises from
		riseFrom, breakAt, breakEnd = show times: starts rising, shatters / is torn, shards done
		key      = unique string for the one-shots
		seed     = number, varies the shard sizes
	}
	Drawn purely from t (show time); the one-shots go through show.once.
]]

local Fx = require(script.Parent:WaitForChild("Fx"))

local ECHO = Color3.fromRGB(34, 18, 40)
local EYE = Color3.fromRGB(255, 60, 40)
local SHARDS = 10
local SHOCK_HEIGHT = 18 -- above the floor, the main boss's tearing light
local HIDDEN = Fx.HIDDEN

local Echo = {}
Echo.__index = Echo

function Echo.new(show, parent, spec)
	local self = setmetatable({ show = show, spec = spec, shards = {}, eyes = {} }, Echo)
	local f = Instance.new("Folder")
	f.Name = "Echo_" .. spec.key
	f.Parent = parent
	self.folder = f
	local final = spec.final

	self.body = Fx.part(f, {
		Name = "Echo", Shape = Enum.PartType.Ball, Color = ECHO, Material = Enum.Material.SmoothPlastic,
		Transparency = 1, Size = Vector3.one, CFrame = HIDDEN,
	})
	self.smoke = Fx.smoke(self.body, {
		Color = ColorSequence.new(Color3.fromRGB(50, 30, 60), Color3.fromRGB(15, 10, 20)),
		Size = Fx.seq(final and 8 or 4, final and 18 or 9), Lifetime = NumberRange.new(1.2, 2),
		Speed = NumberRange.new(2, 5), SpreadAngle = Vector2.new(40, 40), Transparency = Fx.seq(0.35, 1),
		EmissionDirection = Enum.NormalId.Top,
	})
	for _, side in ipairs({ -1, 1 }) do
		local eye = Fx.part(f, {
			Name = "Eye", Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = EYE,
			Size = Vector3.one, Transparency = 1, CFrame = HIDDEN,
		})
		Fx.light(eye, EYE, 10, 1)
		table.insert(self.eyes, { part = eye, side = side })
	end
	for i = 1, SHARDS do
		table.insert(self.shards, Fx.part(f, {
			Name = "Shard", Material = Enum.Material.Slate, Color = ECHO, Transparency = 1, CFrame = HIDDEN,
			Size = Vector3.new(0.6, 1.4 + Fx.hash(i + (spec.seed or 0) * 31) * 1.2, 0.5),
		}))
	end
	if final then
		self.shock = Fx.part(f, {
			Name = "Shock", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = Fx.PALE,
			Size = Vector3.new(0.2, 2, 2), Transparency = 1, CFrame = HIDDEN,
		})
		self.flash = Fx.light(self.shock, Fx.PALE, 120, 0)
	end
	return self
end

function Echo:Update(t)
	local show, spec = self.show, self.spec
	local final, key = spec.final, "echo" .. spec.key
	local once = show.once

	-- Rises (its size and height grow together), until it is broken.
	local grow = Fx.outCubic(Fx.alpha(t, spec.riseFrom, spec.breakAt))
	local broken = t >= spec.breakAt
	local size = (final and 18 or 6) * grow
	local at = spec.base + Vector3.new(0, (final and 20 or 7) * grow, 0)
	if grow > 0 and not broken then
		self.body.CFrame = CFrame.new(at)
		self.body.Size = Vector3.new(size, size * 1.2, size)
		self.body.Transparency = 0.35 + 0.1 * math.sin(t * 6)
		self.smoke.Rate = final and 40 or 25
		local eyeSize = final and 1.6 or 0.6
		for _, eye in ipairs(self.eyes) do
			eye.part.CFrame = CFrame.new(at + Vector3.new(eye.side * size * 0.18, size * 0.15, -size * 0.45))
			eye.part.Size = Vector3.one * eyeSize * grow
			eye.part.Transparency = 0
		end
	else
		self.body.CFrame = HIDDEN
		self.smoke.Rate = 0
		for _, eye in ipairs(self.eyes) do eye.part.CFrame = HIDDEN end
	end
	once:at(key .. "roar", spec.riseFrom + 0.3, t, function()
		Fx.sound(final and "BossEchoRoar" or "MiniEchoRise", at, 1)
	end)

	-- Shards fly out at the break and fall.
	local shardX = Fx.alpha(t, spec.breakAt, spec.breakEnd)
	for i, shard in ipairs(self.shards) do
		if broken and shardX < 1 then
			local a = (i / SHARDS) * math.pi * 2 + Fx.hash(i) * 0.6
			local out = (final and 40 or 14) * Fx.outCubic(shardX)
			local fall = -16 * shardX * shardX
			local p = at + Vector3.new(math.cos(a) * out, (final and 8 or 3) * shardX + fall, math.sin(a) * out)
			shard.CFrame = CFrame.new(p) * CFrame.Angles(t * 5 + i, t * 3, i)
			shard.Transparency = 0.2 + 0.8 * shardX
		else
			shard.CFrame = HIDDEN
		end
	end
	once:at(key .. "break", spec.breakAt, t, function()
		self.smoke:Emit(final and 40 or 16)
		Fx.sound(final and "EchoTear" or "EchoShatter", at, 1)
	end)

	-- The main boss's tearing light: a flash and a shockwave ring across the arena.
	if self.shock then
		local x = Fx.alpha(t, spec.breakAt, spec.breakEnd)
		if x > 0 and x < 1 then
			self.shock.CFrame = CFrame.new(show:centre(SHOCK_HEIGHT)) * CFrame.Angles(0, 0, math.pi / 2)
			self.shock.Size = Vector3.new(0.2, 4 + 200 * Fx.outCubic(x), 4 + 200 * Fx.outCubic(x))
			self.shock.Transparency = 0.1 + 0.9 * x
			self.flash.Brightness = 8 * (1 - x)
		else
			self.shock.CFrame = HIDDEN
			self.flash.Brightness = 0
		end
	end
end

function Echo:Destroy()
	self.folder:Destroy()
end

return Echo
