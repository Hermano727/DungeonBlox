--[[
	Pyres -- stage 1 of the clear sequence: one iron brazier per party member.

	Braziers grind up out of the floor on a circle round the arena centre (fixed slots: players
	move freely, so nothing follows them). Each member's score pours in as embers from the dark,
	a counter climbing over the fire; the fire roars, and the low rolls that were auto-scrapped
	burn off in an ash puff with a "+N Scrap" tally. A brazier whose owner kept nothing gutters to
	coals, visible to the whole party. A member who fell in the fight gets a cold, grey brazier.

	The relics that lift out of the fire belong to ReliquaryRing; this stage only exposes each
	brazier (show.braziers[i]) for the later stages: its bowl position, and its fire's dim/flare.

	Timeline keys (DungeonClearConfig.Pyres): t0, riseEnd, pourEnd, burnEnd, finish.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("DungeonClearConfig"))
local Fx = require(script.Parent:WaitForChild("Fx"))

local P = Config.Pyres
local SINK = 6           -- studs below the floor a brazier starts (and ends, in the outro)
local EMBER_FLIGHT = 0.6 -- seconds per ember, sky to bowl
local EMBER_POOL = 24    -- ember parts per brazier, reused
local GREY = Color3.fromRGB(150, 150, 150)

local Pyres = {}
Pyres.__index = Pyres

-- The procedural stand-in brazier: base, stem, bowl, rim, coal bed. Pivot = base on the floor.
-- An uploaded model (RS.VfxModels.CLEAR_BRAZIER) replaces it; its bowl height is its extents.
local function buildBrazier(parent)
	local uploaded = Fx.vfxModel("CLEAR_BRAZIER")
	if uploaded then
		-- Textured parts (the Tripo brazier) keep their own look; only an untextured part (an
		-- older placeholder) is painted iron.
		local coals = uploaded:FindFirstChild("Coals", true)
		for _, part in ipairs(uploaded:GetDescendants()) do
			if part:IsA("MeshPart") and part ~= coals and part.TextureID == "" then
				part.Material = Enum.Material.Metal
				part.Color = Fx.IRON
			end
		end
		local pivotY = uploaded:GetPivot().Position.Y
		local _, size = uploaded:GetBoundingBox()
		local height = size.Y
		if coals then
			coals.Material = Enum.Material.Neon
			coals.Color = Color3.fromRGB(90, 30, 12)
			-- The fire sits on the coal bed, not on the rim.
			height = coals.Position.Y + coals.Size.Y * 0.5 - pivotY
		end
		uploaded.Parent = parent
		return uploaded, height, coals
	end
	local model = Instance.new("Model")
	model.Name = "Brazier"
	local function cyl(name, height, diameter, y, color, material)
		return Fx.part(model, {
			Name = name, Shape = Enum.PartType.Cylinder, Size = Vector3.new(height, diameter, diameter),
			CFrame = CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.pi / 2),
			Color = color or Fx.IRON, Material = material or Enum.Material.Metal,
		})
	end
	local base = cyl("Base", 0.7, 3.4, 0.35)
	cyl("Foot", 0.35, 2.4, 0.85)
	cyl("Stem", 2.4, 0.9, 2.2)
	cyl("Collar", 0.4, 1.6, 3.4)
	cyl("Bowl", 1.1, 4.4, 4.05)
	cyl("Rim", 0.3, 4.9, 4.6)
	local coals = cyl("Coals", 0.12, 3.8, 4.66, Color3.fromRGB(90, 30, 12), Enum.Material.Neon)
	model.PrimaryPart = base
	model:PivotTo(CFrame.new())
	model.Parent = parent
	return model, 4.75, coals
end

function Pyres.new(show)
	local s = show.payload.pyres
	local self = setmetatable({ show = show, s = s, items = {} }, Pyres)
	local folder = Instance.new("Folder")
	folder.Name = "Pyres"
	folder.Parent = show.folder
	self.folder = folder

	for index, member in ipairs(show.members) do
		local fallen = member.state == "fallen"
		local base = show:polar(member.angle, P.Radius, 0)
		local facing = CFrame.lookAt(base, Vector3.new(show:centre(0).X, base.Y, show:centre(0).Z))
		local model, height, coals = buildBrazier(folder)

		-- Fire, light, sparks and smoke all hang off one anchor at the bowl.
		local anchor = Fx.part(folder, { Name = "BowlAnchor", Transparency = 1, Size = Vector3.one * 0.2 })
		local fire = Fx.emitter(anchor, {
			Texture = Fx.TEX.Fire, Color = ColorSequence.new(Color3.fromRGB(255, 190, 90), Color3.fromRGB(200, 50, 20)),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(0.4, 2.4), NumberSequenceKeypoint.new(1, 0.3) }),
			Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(4, 7), SpreadAngle = Vector2.new(12, 12),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(0.6, 0.4), NumberSequenceKeypoint.new(1, 1) }),
			-- The flame art points up: only a slight lean, never spun.
			Rotation = NumberRange.new(-10, 10),
			EmissionDirection = Enum.NormalId.Top,
		})
		local sparks = Fx.emitter(anchor, {
			Texture = Fx.TEX.Ember, Color = ColorSequence.new(Color3.fromRGB(255, 200, 120)),
			Size = Fx.seq(0.45, 0), Lifetime = NumberRange.new(0.8, 1.6), Speed = NumberRange.new(5, 10),
			SpreadAngle = Vector2.new(20, 20), Acceleration = Vector3.new(0, -2, 0),
			Orientation = Enum.ParticleOrientation.VelocityParallel, EmissionDirection = Enum.NormalId.Top,
		})
		local ash = Fx.smoke(anchor, {
			Color = ColorSequence.new(Fx.ASH), Size = Fx.seq(2, 6), Lifetime = NumberRange.new(1.4, 2.2),
			Speed = NumberRange.new(3, 6), SpreadAngle = Vector2.new(25, 25), Transparency = Fx.seq(0.3, 1),
			EmissionDirection = Enum.NormalId.Top,
		})
		local dust = Fx.smoke(anchor, {
			Color = ColorSequence.new(Color3.fromRGB(90, 84, 78)), Size = Fx.seq(2.5, 5), Lifetime = NumberRange.new(0.8, 1.3),
			Speed = NumberRange.new(4, 8), SpreadAngle = Vector2.new(80, 10), Transparency = Fx.seq(0.4, 1),
			EmissionDirection = Enum.NormalId.Bottom,
		})
		local light = Fx.light(anchor, Fx.FIRE, 22, 0)

		-- Owner plaque over the fire: name, then the score counter.
		local plaqueAnchor = Fx.part(folder, { Name = "PlaqueAnchor", Transparency = 1, Size = Vector3.one * 0.2 })
		local _, lines = show:plaque(plaqueAnchor, {
			size = UDim2.fromOffset(240, 58), maxDistance = 300,
			lines = {
				{ text = member.name, color = fallen and GREY or Fx.PALE, height = 0.55, y = 0 },
				{ text = fallen and "Fallen" or "", color = fallen and GREY or Color3.fromRGB(255, 200, 120), height = 0.45, y = 0.55 },
			},
		})

		-- Embers (pooled parts with a short trail each).
		local embers = {}
		for i = 1, EMBER_POOL do
			local ember = Fx.part(folder, {
				Name = "Ember", Shape = Enum.PartType.Ball, Material = Enum.Material.Neon,
				Color = Color3.fromRGB(255, 170, 70), Size = Vector3.one * 0.35, Transparency = 1,
			})
			local a0 = Fx.attachment(ember, Vector3.new(0, 0.12, 0))
			local a1 = Fx.attachment(ember, Vector3.new(0, -0.12, 0))
			local trail = Fx.make("Trail", {
				Attachment0 = a0, Attachment1 = a1, Lifetime = 0.22, LightEmission = 1, LightInfluence = 0,
				Color = ColorSequence.new(Color3.fromRGB(255, 200, 120), Color3.fromRGB(255, 90, 30)),
				Transparency = Fx.seq(0.2, 1), FaceCamera = true, Enabled = false,
			}, ember)
			embers[i] = { part = ember, trail = trail }
		end

		local item = {
			index = index, member = member, fallen = fallen,
			model = model, height = height, coals = coals, base = base, facing = facing,
			anchor = anchor, fire = fire, sparks = sparks, ash = ash, dust = dust, light = light,
			plaqueAnchor = plaqueAnchor, nameLabel = lines[1], counter = lines[2],
			embers = embers, emberCount = fallen and 0 or math.min(member.score or 0, P.MaxVisibleEmbers),
			dim = 1, flareAt = -math.huge, flareColor = Fx.FIRE, flareStrength = 0,
		}
		self.items[index] = item

		-- What later stages may touch.
		show.braziers[index] = {
			bowl = base + Vector3.new(0, height + 0.3, 0),
			plaqueAnchor = plaqueAnchor,
			-- Multiplies the fire (the main boss's blackout dims every brazier).
			setDim = function(f) item.dim = f end,
			-- A burst of light/fire in `color` at the moment `at` (show time), fading over ~1 s.
			flare = function(at, color, strength)
				item.flareAt, item.flareColor, item.flareStrength = at, color, strength or 1
				fire:Emit(math.floor(20 * (strength or 1)))
			end,
		}
	end
	return self
end

-- Ember i's flight: from a deterministic point in the dark above, down a curve into the bowl.
local function emberPosition(show, item, i, x)
	local seed = item.index * 101 + i
	local angle = Fx.hash(seed) * math.pi * 2
	local radius = 10 + Fx.hash(seed + 0.5) * 8
	local start = item.base + Vector3.new(math.cos(angle) * radius, 18 + Fx.hash(seed + 0.25) * 10, math.sin(angle) * radius)
	local finish = show.braziers[item.index].bowl
	local control = (start + finish) / 2 + Vector3.new(0, 6, 0)
	local e = Fx.inCubic(x) * 0.6 + x * 0.4
	local a = start:Lerp(control, e)
	local b = control:Lerp(finish, e)
	return a:Lerp(b, e)
end

function Pyres:Update(t)
	local s, show = self.s, self.show
	local outroAt = show.duration
	for _, item in ipairs(self.items) do
		-- Rise (a grinding shake on the way up), then the outro sink.
		local rise = Fx.outBack(Fx.alpha(t, s.t0 + (item.index - 1) * 0.12, s.riseEnd))
		local sink = Fx.inCubic(Fx.alpha(t, outroAt, outroAt + show.outro * 0.9))
		local lift = (rise - 1 - sink) * SINK
		local shake = (rise < 1) and (Fx.hash(math.floor(t * 30) + item.index) - 0.5) * 0.25 or 0
		local pivot = item.facing + Vector3.new(shake, lift, 0)
		item.model:PivotTo(pivot)
		local bowl = show.braziers[item.index].bowl + Vector3.new(0, lift, 0)
		item.anchor.CFrame = CFrame.new(bowl)
		item.plaqueAnchor.CFrame = CFrame.new(bowl + Vector3.new(0, 4.2, 0))
		show.once:at("rise" .. item.index, s.t0, t, function()
			item.dust:Emit(14)
			Fx.sound("BrazierRise", item.base, 0.7)
		end)

		local visible = rise > 0.05 and sink < 0.95
		item.nameLabel.Visible = visible
		item.counter.Visible = visible

		if item.fallen then
			item.fire.Rate, item.sparks.Rate, item.light.Brightness = 0, 0, 0
			if item.coals then item.coals.Color = Color3.fromRGB(60, 58, 56) end
		else
			-- Fire: a low flame once up, swelling as the embers land, a roar at the burn, then
			-- either a steady fire (relics) or a gutter to coals (nothing kept).
			local pour = Fx.alpha(t, s.riseEnd, s.pourEnd)
			local roar = 1 - Fx.alpha(t, s.pourEnd, s.burnEnd)
			local intensity = (rise >= 1) and (0.35 + 0.55 * pour) or 0
			if t >= s.pourEnd then intensity = 0.9 + 0.6 * roar end
			if item.member.kept == 0 and t >= s.burnEnd then
				intensity = Fx.lerp(0.9, 0.12, Fx.alpha(t, s.burnEnd, s.burnEnd + P.Gutter))
			end
			intensity *= item.dim * (1 - sink)
			local flare = item.flareStrength * (1 - Fx.alpha(t, item.flareAt, item.flareAt + 1))
			item.fire.Rate = 30 * intensity
			item.sparks.Rate = 6 * intensity
			item.light.Brightness = 2.2 * intensity + 4 * flare
			item.light.Color = flare > 0.05 and item.flareColor or Fx.FIRE
			if item.coals then
				item.coals.Color = Color3.fromRGB(90, 30, 12):Lerp(Color3.fromRGB(255, 120, 40), math.min(1, intensity))
			end

			-- Embers and the counter.
			local n = item.emberCount
			for i = 1, n do
				local spawnAt = s.riseEnd + (n > 1 and (i - 1) / (n - 1) or 0) * (P.EmberPour - EMBER_FLIGHT)
				local x = (t - spawnAt) / EMBER_FLIGHT
				local slot = item.embers[(i - 1) % EMBER_POOL + 1]
				if x >= 0 and x <= 1 then
					slot.part.Position = emberPosition(show, item, i, x)
					slot.part.Transparency = 0
					slot.trail.Enabled = true
					slot.owner = i
				elseif slot.owner == i then
					slot.part.Transparency = 1
					slot.trail.Enabled = false
					slot.owner = nil
				end
			end
			local score = item.member.score or 0
			local shown = math.floor(score * Fx.alpha(t, s.riseEnd, s.pourEnd - EMBER_FLIGHT * 0.5) + 0.5)
			item.counter.Text = (t >= s.riseEnd and score > 0) and tostring(shown) or ""
			show.once:at("pour" .. item.index, s.riseEnd, t, function()
				if n > 0 then Fx.sound("EmberPour", item.base, 0.6) end
			end)

			-- The burn: flare, ash and the scrap tally rising off the fire.
			show.once:at("burn" .. item.index, s.pourEnd, t, function()
				item.fire:Emit(30)
				item.sparks:Emit(25)
				if (item.member.scrap or 0) > 0 then
					item.ash:Emit(18)
					Fx.sound("ScrapBurn", item.base, 0.8)
					self:scrapTally(item, t)
				end
			end)
		end
		if self.tally and self.tally[item.index] then
			local tally = self.tally[item.index]
			local x = Fx.alpha(t, tally.at, tally.at + 1.8)
			tally.anchor.CFrame = CFrame.new(bowl + Vector3.new(0, 2.5 + 4 * Fx.outCubic(x), 0))
			Fx.fadePlaque(tally.gui, Fx.alpha(t, tally.at + 1.1, tally.at + 1.8))
		end
	end
end

-- "+N Scrap" floating up off the fire.
function Pyres:scrapTally(item, t)
	self.tally = self.tally or {}
	local anchor = Fx.part(self.folder, { Name = "TallyAnchor", Transparency = 1, Size = Vector3.one * 0.2 })
	local gui = self.show:plaque(anchor, {
		size = UDim2.fromOffset(180, 30), maxDistance = 250,
		lines = { { text = string.format("+%d Scrap", item.member.scrap), color = Color3.fromRGB(205, 195, 180), height = 1, y = 0 } },
	})
	self.tally[item.index] = { anchor = anchor, gui = gui, at = t }
end

function Pyres:Destroy()
	self.folder:Destroy()
end

return Pyres
