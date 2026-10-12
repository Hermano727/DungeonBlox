--[[
	Benediction -- stage 0 of the clear sequence: the "dungeon complete" moment, in the world.

	After a beat of silence a shaft of pale gold light punches down through the ceiling opening
	onto the arena centre; a faceless hooded angel (RS.VfxModels.CLEAR_ANGEL) sinks into it and two
	real wings unfurl from its shoulder blades (RS.VfxModels.CLEAR_WINGS: a feathered 3D wing,
	mirrored for the pair, folded against the back then swung open). It sinks facing the local
	player (each client draws the show, so everyone sees it face them), turns two full circles over
	the hold, ends facing them again, then rises back up the shaft (fading only near the top) as the wings fold and the
	light thins. No text: the light is the message. A near-silent beat follows before the loot
	begins. Entirely separate from the loot stages.

	Timeline keys (DungeonClearConfig.Benediction): t0, descend, unfurl, hold, fade, finish.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("DungeonClearConfig"))
local Fx = require(script.Parent:WaitForChild("Fx"))

local B = Config.Benediction
local HIDDEN = Fx.HIDDEN

-- The wing model (assets/models/dungeons/build_angel_wings.py prints these). Roblox places a MeshPart
-- by its bounding-box centre, so each wing is positioned from its SHOULDER joint using the offset
-- from that centre to the shoulder, in the part's own axes. Left = extends toward -X.
local V = Vector3.new
local WINGS = {
	WingL = { side = -1, size = V(11.134, 7.604, 1.155), shoulder = V(5.433, 1.031, -0.013), tip = V(-5.567, 3.802, -0.076) },
	WingR = { side = 1, size = V(11.134, 7.604, 1.155), shoulder = V(-5.433, 1.031, -0.013), tip = V(5.567, 3.802, -0.076) },
}
local WING_MATERIAL = Enum.Material.SmoothPlastic -- Neon makes the painted texture glow flat instead
-- The angel (assets/models/dungeons/build_angel_figure.py). Origin = its bounding-box centre; CHEST is
-- the point on the back of the torso, at shoulder-blade height, that sits on the Benediction's anchor.
local ANGEL = { size = V(4.526, 9, 2.836), chest = V(0, 1.8, 0.608) }
local ANGEL_MATERIAL = Enum.Material.SmoothPlastic
local WING_SCALE = 0.8             -- the wing model is 11 studs a side; against a 9-stud figure, 0.8
local SHOULDER = V(0.8, 0.3, 0.2)  -- each wing's pivot, from the chest anchor (x mirrored per side; z is behind)
local FOLDED_ROLL = -85            -- degrees: hanging down the back
local OPEN_ROLL = 22               -- degrees: the arm angled up and out
local SWEEP = 14                   -- degrees the open wings sweep back
local FOLDED_SCALE = 0.3           -- the wings unfurl as they open: a folded wing is small
local TURNS = 2        -- full circles the angel turns during the hold, so every side sees it
local SHAFT_WIDTH = 16

local Benediction = {}
Benediction.__index = Benediction

function Benediction.new(show)
	local s = show.payload.benediction
	local self = setmetatable({ show = show, s = s, wings = {} }, Benediction)
	local folder = Instance.new("Folder")
	folder.Name = "Benediction"
	folder.Parent = show.folder
	self.folder = folder

	local top = show:world(0, B.ShaftTop - show.floorY, 0)
	local floor = show:centre(0.05)
	self.top, self.floor = top, floor

	-- The shaft: two FaceCamera beams (soft wide outer, brighter inner) top -> floor.
	local shaftHost = Fx.part(folder, { Name = "Shaft", Transparency = 1, Size = Vector3.one, CFrame = CFrame.new(floor) })
	local aTop = Fx.attachment(shaftHost)
	local aFloor = Fx.attachment(shaftHost)
	aTop.WorldPosition = top
	aFloor.WorldPosition = floor
	self.shaftHost, self.aTop, self.aFloor = shaftHost, aTop, aFloor
	self.outer = Fx.beam(folder, aTop, aFloor, {
		Color = ColorSequence.new(Fx.PALE, Fx.GOLD),
		Width0 = SHAFT_WIDTH * 0.7, Width1 = SHAFT_WIDTH,
		Texture = Fx.TEX.LightShaft, TextureMode = Enum.TextureMode.Stretch,
		Transparency = Fx.seq(1, 1),
	})
	self.inner = Fx.beam(folder, aTop, aFloor, {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Fx.PALE),
		Width0 = 3.5, Width1 = 5,
		Transparency = Fx.seq(1, 1),
	})

	-- Dust motes drifting in the shaft.
	local motesHost = Fx.part(folder, {
		Name = "Motes", Transparency = 1, Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(B.CoreHeight + 10, SHAFT_WIDTH * 0.6, SHAFT_WIDTH * 0.6),
		CFrame = CFrame.new(show:centre((B.CoreHeight + 10) / 2)) * CFrame.Angles(0, 0, math.pi / 2),
	})
	self.motes = Fx.emitter(motesHost, {
		Shape = Enum.ParticleEmitterShape.Cylinder, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
		Color = ColorSequence.new(Fx.PALE), Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.35), NumberSequenceKeypoint.new(1, 0),
		}),
		Lifetime = NumberRange.new(2.5, 4), Speed = NumberRange.new(0.2, 0.8), SpreadAngle = Vector2.new(180, 180),
		Transparency = Fx.seq(0.2, 0.6), LightEmission = 1,
	})

	-- Floor glow where the shaft lands.
	self.pool = Fx.part(folder, {
		Name = "Pool", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = Fx.GOLD,
		Size = Vector3.new(0.1, 14, 14), Transparency = 1,
		CFrame = CFrame.new(floor) * CFrame.Angles(0, 0, math.pi / 2),
	})
	self.poolLight = Fx.light(self.pool, Fx.GOLD, 30, 0)

	-- The light host: an invisible part in front of the angel's chest that lights it and the wings
	-- and sheds sparks. (It used to be a glowing orb; the figure replaces it.)
	self.core = Fx.part(folder, {
		Name = "Core", Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = Fx.PALE,
		Size = Vector3.one * 2.2, Transparency = 1, CFrame = CFrame.new(top),
	})
	self.coreLight = Fx.light(self.core, Fx.PALE, 45, 0)
	self.coreSparks = Fx.emitter(self.core, {
		Color = ColorSequence.new(Fx.PALE, Fx.GOLD), Size = Fx.seq(1, 0),
		Lifetime = NumberRange.new(0.8, 1.4), Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(180, 180),
		Transparency = Fx.seq(0, 1),
	})

	-- The angel: one MeshPart. Missing (not uploaded / not loaded yet): the show goes on without it.
	local angelModel = Fx.vfxModel("CLEAR_ANGEL")
	local angel = angelModel and angelModel:FindFirstChild("Angel", true)
	if angel and angel:IsA("BasePart") then
		if (angel.Size - ANGEL.size).Magnitude > 0.5 then
			warn(("[Benediction] Angel imported at %s, expected %s (axes changed? rerun build_angel_figure.py)")
				:format(tostring(angel.Size), tostring(ANGEL.size)))
		end
		angelModel.Parent = folder
		angel.Anchored, angel.CanCollide, angel.CanQuery, angel.CanTouch, angel.CastShadow = true, false, false, false, false
		angel.Material = ANGEL_MATERIAL
		angel.CFrame = Fx.HIDDEN
		self.angel = angel
		self.chest = ANGEL.chest * Vector3.new(angel.Size.X / ANGEL.size.X, angel.Size.Y / ANGEL.size.Y, angel.Size.Z / ANGEL.size.Z)
	else
		warn("[Benediction] RS.VfxModels.CLEAR_ANGEL is not loaded: no angel this time")
	end

	-- Wings: the uploaded model's two MeshParts. Missing (not uploaded / not loaded yet): the show
	-- simply has no wings rather than failing.
	local model = Fx.vfxModel("CLEAR_WINGS")
	if model then
		model.Parent = folder
		for name, spec in pairs(WINGS) do
			local part = model:FindFirstChild(name, true)
			if part and part:IsA("BasePart") then
				if (part.Size - spec.size).Magnitude > 0.5 then
					warn(("[Benediction] %s imported at %s, expected %s (axes changed? rerun build_angel_wings.py)")
						:format(name, tostring(part.Size), tostring(spec.size)))
				end
				part.Anchored, part.CanCollide, part.CanQuery, part.CanTouch, part.CastShadow = true, false, false, false, false
				part.Material = WING_MATERIAL
				-- Scale the authored numbers by how the part actually came in.
				local ratio = Vector3.new(part.Size.X / spec.size.X, part.Size.Y / spec.size.Y, part.Size.Z / spec.size.Z)
				local tip = Fx.attachment(part, spec.tip * ratio)
				table.insert(self.wings, {
					part = part, side = spec.side, base = part.Size, ratio = ratio,
					shoulder = spec.shoulder * ratio, tipOffset = spec.tip * ratio, tip = tip,
					glint = Fx.emitter(tip, {
						Color = ColorSequence.new(Fx.PALE), Size = Fx.seq(0.5, 0), Lifetime = NumberRange.new(1, 1.8),
						Speed = NumberRange.new(0.5, 1.5), Acceleration = Vector3.new(0, -1.5, 0), Transparency = Fx.seq(0, 1),
					}),
				})
				part.CFrame = Fx.HIDDEN
			end
		end
	else
		warn("[Benediction] RS.VfxModels.CLEAR_WINGS is not loaded: no wings this time")
	end
	return self
end

-- The yaw that turns the angel's front (-Z) toward THIS player's character. The show is drawn on
-- each client, so everyone sees the angel face them; if their character is not around (dead,
-- streamed out), it faces the entrance side.
function Benediction:chooseFacing()
	local centre = self.show:centre(0)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return 0 end
	local direction = Vector3.new(root.Position.X - centre.X, 0, root.Position.Z - centre.Z)
	if direction.Magnitude < 3 then return 0 end
	return math.atan2(-direction.X, -direction.Z)
end

function Benediction:Update(t)
	local s, show = self.s, self.show
	if self.done then return end
	if t > s.finish + 0.5 then
		self.folder:Destroy()
		self.done = true
		return
	end

	show.once:at("choir", s.descend, t, function() Fx.sound("ClearChoir", self.top, 1) end, 2)

	-- Shaft: punches down in the first third of the descent, thins out over the fade.
	local strike = Fx.outCubic(Fx.alpha(t, s.descend, s.descend + (s.unfurl - s.descend) * 0.35))
	local fade = Fx.alpha(t, s.fade, s.finish)
	local visible = strike * (1 - fade)
	self.aFloor.WorldPosition = self.top:Lerp(self.floor, strike)
	local breathe = 0.04 * math.sin(t * 2.2)
	self.outer.Transparency = NumberSequence.new(1 - visible * (0.45 + breathe), 1 - visible * 0.12)
	self.inner.Transparency = NumberSequence.new(1 - visible * 0.75, 1 - visible * 0.3)
	self.outer.Width1 = SHAFT_WIDTH * (1 - fade * 0.8)
	self.inner.Width1 = 5 * (1 - fade)
	self.motes.Rate = visible > 0.2 and 35 * visible or 0
	self.pool.Transparency = 1 - visible * 0.6
	self.poolLight.Brightness = 3 * visible

	-- The angel: sinks from the opening facing the local player, hovers while it turns
	-- two full circles (ending facing them again), then rises back up the shaft and only fades near
	-- the top.
	local sink = Fx.outCubic(Fx.alpha(t, s.descend, s.unfurl))
	local rise = Fx.inOutSine(fade)
	local coreY = Fx.lerp(Fx.lerp(B.ShaftTop - show.floorY, B.CoreHeight, sink), B.ShaftTop - show.floorY, rise)
	local coreAt = show:centre(coreY + 0.4 * math.sin(t * 1.4))
	local ghost = Fx.alpha(t, s.fade + 0.6 * (s.finish - s.fade), s.finish)
	local coreVis = Fx.alpha(t, s.descend, s.descend + 0.4) * (1 - ghost)
	if not self.faceYaw and t >= s.descend - 0.5 then self.faceYaw = self:chooseFacing() end
	local spin = TURNS * 2 * math.pi * Fx.inOutSine(Fx.alpha(t, s.hold, s.fade))
	local frame = CFrame.new(coreAt) * CFrame.Angles(0, (self.faceYaw or 0) + spin, 0)
	if self.angel then
		if coreVis > 0.01 then
			self.angel.CFrame = frame * CFrame.new(-self.chest)
			self.angel.Transparency = 1 - coreVis
		else
			self.angel.CFrame = HIDDEN
		end
	end
	self.core.CFrame = frame * CFrame.new(0, 0, -3)
	self.coreLight.Brightness = 4 * coreVis
	self.coreSparks.Rate = 25 * coreVis

	-- Wings: folded down the back, they swing open from the shoulder (a little overshoot), unfurling
	-- as they go, hold with a slow breath, then fold back as the angel rises.
	local open = Fx.outBack(Fx.alpha(t, s.unfurl, s.hold)) * (1 - Fx.inOutSine(fade))
	local wingVis = Fx.clamp01(open) * (1 - ghost)
	local k = Fx.lerp(FOLDED_SCALE, 1, Fx.clamp01(open)) * WING_SCALE
	local beat = math.sin(t * 1.6)
	for _, w in ipairs(self.wings) do
		if wingVis <= 0.01 then
			w.part.CFrame = HIDDEN
			w.glint.Rate = 0
		else
			local roll = math.rad(Fx.lerp(FOLDED_ROLL, OPEN_ROLL, open) + 3 * beat * Fx.clamp01(open)) * w.side
			local sweep = -w.side * math.rad(SWEEP * Fx.clamp01(open))
			local pivot = frame * CFrame.new(w.side * SHOULDER.X, SHOULDER.Y, SHOULDER.Z)
			w.part.Size = w.base * k
			w.part.CFrame = pivot * CFrame.Angles(0, sweep, 0) * CFrame.Angles(0, 0, roll) * CFrame.new(-w.shoulder * k)
			w.part.Transparency = 1 - wingVis
			w.tip.Position = w.tipOffset * k
			w.glint.Rate = wingVis > 0.6 and 8 or 0
		end
	end
end

function Benediction:Destroy()
	if not self.done then self.folder:Destroy() end
end

return Benediction
