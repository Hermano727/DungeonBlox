--[[
	ReliquaryRing -- stage 2 of the clear sequence (and the relics' lift out of the pyres).

	Every kept drop is a shrouded relic: a chain-bound cloth bundle with an ember inside, all of
	them identical. They lift out of their owner's fire at the end of the Pyres stage, spiral up
	into one shared ring over the arena centre, and the ring spins up. Then the reveal pass, in
	a random order (any rarity can come first): the relic trembles for a flat 1.5 s while its glow cycles through random
	rarity colours (the last moments settle on the real one), the shroud burns away, then a short
	wave of shock rings in the real rarity's colour pulses out of it (Wave, 0.25 s) and the next relic starts. The
	real item spins in place and a plaque names the owner and the item in the rarity colour. From
	Epic the ring slows, from Legendary it stops dead and every other relic dims. Last, every item streaks down into its owner's chest
	(their brazier if they are gone).

	Timeline (payload.ring): t0, gatherEnd, spinEnd, disperseAt, finish, relics[] with
	{ member, slot, name, rarity, prefab, revealIndex, breathAt, burnAt, flareAt }.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("DungeonClearConfig"))
local Fx = require(script.Parent:WaitForChild("Fx"))
local Wave = require(script.Parent:WaitForChild("Wave"))

local R = Config.Ring
local HOVER = 5.5         -- studs above the bowl a lifted relic waits
local LIFT_TIME = 0.9
local POP_TIME = 0.4      -- the revealed item scaling in
local STREAK_TIME = 0.75
local SHROUD_CLOTH = Color3.fromRGB(52, 44, 40)
local SHROUD_CHAIN = Color3.fromRGB(70, 66, 62)
local LADDER = Config.RARITY_ORDER
local STEP = 1 / 30       -- spin integration step (deterministic on every client)
local HIDDEN = Fx.HIDDEN

local Ring = {}
Ring.__index = Ring

-- The procedural stand-in shroud (RS.VfxModels.CLEAR_RELIC replaces it): cloth bundle, a
-- gathered knot on top, two chain bands, and an ember core showing through the weave.
local function buildShroud(parent)
	local uploaded = Fx.vfxModel("CLEAR_RELIC")
	if uploaded then
		local cloth = uploaded:FindFirstChild("Cloth", true)
		local chains = uploaded:FindFirstChild("Chains", true)
		local glow = uploaded:FindFirstChild("EmberGlow", true)
		if cloth then cloth.Material, cloth.Color = Enum.Material.Fabric, SHROUD_CLOTH end
		if chains then chains.Material, chains.Color = Enum.Material.Metal, SHROUD_CHAIN end
		if glow then glow.Material, glow.Color, glow.Transparency = Enum.Material.Neon, Fx.FIRE, 0.85 end
		uploaded.Parent = parent
		return uploaded, glow
	end
	local model = Instance.new("Model")
	model.Name = "Shroud"
	local cloth = Fx.part(model, {
		Name = "Cloth", Shape = Enum.PartType.Ball, Material = Enum.Material.Fabric,
		Color = SHROUD_CLOTH, Size = Vector3.new(2.3, 2.6, 2.3),
	})
	Fx.part(model, {
		Name = "Knot", Shape = Enum.PartType.Ball, Material = Enum.Material.Fabric, Color = SHROUD_CLOTH,
		Size = Vector3.one * 0.95, CFrame = CFrame.new(0, 1.35, 0),
	})
	Fx.part(model, {
		Name = "BandA", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Metal, Color = SHROUD_CHAIN,
		Size = Vector3.new(0.22, 2.5, 2.5), CFrame = CFrame.Angles(0, 0, math.pi / 2),
	})
	Fx.part(model, {
		Name = "BandB", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Metal, Color = SHROUD_CHAIN,
		Size = Vector3.new(0.22, 2.6, 2.6), CFrame = CFrame.Angles(0, math.pi / 2, 0),
	})
	local core = Fx.part(model, {
		Name = "EmberCore", Shape = Enum.PartType.Ball, Material = Enum.Material.Neon,
		Color = Fx.FIRE, Size = Vector3.one * 2.36, Transparency = 0.85,
	})
	model.PrimaryPart = cloth
	model.Parent = parent
	return model, core
end

-- The revealed item: its loot display prefab, or a glowing gem in the rarity colour.
local function buildItem(parent, prefab, color)
	local model = Fx.lootPrefab(prefab)
	if model then
		model.Parent = parent
		return model
	end
	local gem = Fx.part(parent, {
		Name = "Gem", Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = color,
		Size = Vector3.one * 1.6,
	})
	return gem
end

local function scaleOf(inst, factor)
	if inst:IsA("Model") then
		inst:ScaleTo(math.max(0.01, factor))
	else
		local base = inst:GetAttribute("BaseSize") or inst.Size
		inst:SetAttribute("BaseSize", base)
		inst.Size = base * math.max(0.01, factor)
	end
end

function Ring.new(show)
	local ring = show.payload.ring
	if not ring then return setmetatable({ empty = true }, Ring) end
	local self = setmetatable({ show = show, ring = ring, relics = {} }, Ring)
	local folder = Instance.new("Folder")
	folder.Name = "ReliquaryRing"
	folder.Parent = show.folder
	self.folder = folder

	local perMember = {}
	for _, data in ipairs(ring.relics) do
		perMember[data.member] = (perMember[data.member] or 0) + 1
		local color = Fx.rarityColor(data.rarity)
		local holder = Fx.part(folder, { Name = "Relic", Transparency = 1, Size = Vector3.one * 0.2 })
		local shroud, emberCore = buildShroud(folder)
		local light = Fx.light(holder, Fx.FIRE, 14, 0)
		local glow = Fx.emitter(holder, {
			Color = ColorSequence.new(Fx.FIRE), Size = Fx.seq(0.5, 0), Lifetime = NumberRange.new(0.6, 1.1),
			Speed = NumberRange.new(0.5, 1.5), SpreadAngle = Vector2.new(180, 180), Transparency = Fx.seq(0, 1),
		})
		-- The reveal pulse: shock rings sweeping out in the rarity's colour (Wave).
		local wave = Wave.new(holder, color, Config.RarityRank(data.rarity))
		local cinders = Fx.emitter(holder, {
			Texture = Fx.TEX.Fire, Color = ColorSequence.new(Color3.fromRGB(255, 170, 80), Color3.fromRGB(120, 40, 20)),
			Size = Fx.seq(0.9, 0.1), Lifetime = NumberRange.new(0.4, 0.8), Speed = NumberRange.new(2, 5),
			SpreadAngle = Vector2.new(60, 60), Transparency = Fx.seq(0.2, 1), EmissionDirection = Enum.NormalId.Top,
		})
		-- Scraps of burning cloth flying off while the shroud burns (only with the art).
		local rags = Fx.TEX.ShroudBurn ~= "" and Fx.emitter(holder, {
			Texture = Fx.TEX.ShroudBurn, LightEmission = 0.4,
			Color = ColorSequence.new(Color3.fromRGB(255, 190, 120), Color3.fromRGB(120, 60, 40)),
			Size = Fx.seq(1.1, 0.4), Lifetime = NumberRange.new(0.6, 1.1), Speed = NumberRange.new(3, 6),
			SpreadAngle = Vector2.new(70, 70), Acceleration = Vector3.new(0, 4, 0), Drag = 1.5,
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-90, 90),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0.2), NumberSequenceKeypoint.new(1, 1) }),
			EmissionDirection = Enum.NormalId.Top,
		}) or nil
		-- The item and its trail (for the streak home).
		local item = buildItem(folder, data.prefab, color)
		Fx.fade(item, 1)
		local trailHost = Fx.part(folder, { Name = "TrailHost", Transparency = 1, Size = Vector3.one * 0.2 })
		local trail = Fx.make("Trail", {
			Attachment0 = Fx.attachment(trailHost, Vector3.new(0, 0.4, 0)),
			Attachment1 = Fx.attachment(trailHost, Vector3.new(0, -0.4, 0)),
			Lifetime = 0.35, LightEmission = 1, LightInfluence = 0, FaceCamera = true, Enabled = false,
			Color = ColorSequence.new(color), Transparency = Fx.seq(0.1, 1),
		}, trailHost)
		local gui = show:plaque(holder, {
			size = UDim2.fromOffset(280, 60), maxDistance = 400, offset = Vector3.new(0, 3.4, 0),
			lines = {
				{ text = (show.members[data.member] or {}).name or "", color = color, height = 0.55, y = 0 },
				{ text = data.name or "", color = Fx.PALE, height = 0.45, y = 0.55 },
			},
		})
		Fx.fadePlaque(gui, 1)

		table.insert(self.relics, {
			data = data, color = color, rank = Config.RarityRank(data.rarity),
			holder = holder, shroud = shroud, emberCore = emberCore, light = light, glow = glow,
			wave = wave, cinders = cinders, rags = rags, item = item,
			trailHost = trailHost, trail = trail, gui = gui,
			liftAt = show.payload.pyres.burnEnd + (perMember[data.member] - 1) * 0.15,
			hoverIndex = perMember[data.member],
		})
	end
	self.count = #self.relics
	self.spin = { t = ring.gatherEnd, phase = 0, speed = 0 }
	return self
end

-- The relic being revealed at time t (breath through settle), or nil.
function Ring:focusAt(t)
	for _, r in ipairs(self.relics) do
		local d = r.data
		if t >= d.breathAt and t < d.flareAt + 0.3 then return r end
	end
	return nil
end

-- Ring spin speed target at time t: spin-up, then slowed / stopped by what is being revealed.
function Ring:spinTarget(t)
	local ring = self.ring
	if t < ring.gatherEnd then return 0 end
	local up = Fx.alpha(t, ring.gatherEnd, ring.spinEnd)
	local factor = 1
	local focus = self:focusAt(t)
	if focus then
		if focus.rank >= Config.RarityRank(R.StopFrom) then factor = 0
		elseif focus.rank >= Config.RarityRank(R.SlowFrom) then factor = 0.35 end
	end
	if t >= ring.disperseAt then factor = 0.4 end
	return R.BaseSpin * up * factor
end

-- Ring phase (radians) at t: integrated in fixed steps from the gather, the same on every client.
function Ring:phaseAt(t)
	local st = self.spin
	if t < st.t then
		st.t, st.phase, st.speed = self.ring.gatherEnd, 0, 0
	end
	while st.t + STEP <= t do
		local target = self:spinTarget(st.t)
		st.speed += (target - st.speed) * math.min(1, STEP * 3)
		st.phase += st.speed * STEP
		st.t += STEP
	end
	return st.phase + st.speed * (t - st.t)
end

function Ring:slotPosition(r, t, phase)
	local show = self.show
	local angle = (r.data.slot - 1) / self.count * math.pi * 2 + phase
	local bob = 0.35 * math.sin(t * 1.3 + r.data.slot)
	return show:world(math.sin(angle) * R.Radius, R.Height - show.floorY + bob, -math.cos(angle) * R.Radius)
end

function Ring:hoverPosition(r)
	local brazier = self.show.braziers[r.data.member]
	local base = brazier and brazier.bowl or self.show:centre(4)
	local a = r.hoverIndex * 2.4
	local radius = r.hoverIndex > 1 and 1.8 or 0
	return base + Vector3.new(math.cos(a) * radius, HOVER + (r.hoverIndex - 1) * 0.6, math.sin(a) * radius)
end

-- The glow colour shown while a relic breathes: a random rarity every R.CycleStep (never the same
-- twice in a row, the same sequence on every client), then, for the last R.CycleSettle, the real
-- one. Same flat timing for every relic, whatever the drop count.
local function ladderRank(r, t)
	local d = r.data
	if t < d.breathAt then return 0 end
	if t >= d.burnAt - R.CycleSettle then return r.rank end
	local n = #LADDER
	local seed = d.slot * 17
	local pick = 1 + math.floor(Fx.hash(seed) * n) % n
	for step = 1, math.floor((t - d.breathAt) / R.CycleStep) do
		pick = (pick + math.floor(Fx.hash(seed + step * 3.7) * (n - 1))) % n + 1
	end
	return pick
end

function Ring:Update(t)
	if self.empty or self.done then return end
	local show, ring = self.show, self.ring
	if t > ring.finish + 1 then
		self.folder:Destroy()
		for _, r in ipairs(self.relics) do r.gui:Destroy() end
		self.done = true
		return
	end
	local phase = self:phaseAt(t)
	local focus = self:focusAt(t)
	local dimOthers = focus and focus.rank >= Config.RarityRank(R.StopFrom)

	for index, r in ipairs(self.relics) do
		local d = r.data
		local pos
		local hover = self:hoverPosition(r)
		if t < r.liftAt then
			pos = nil
		elseif t < ring.t0 then
			local x = Fx.outCubic(Fx.alpha(t, r.liftAt, r.liftAt + LIFT_TIME))
			pos = (hover - Vector3.new(0, HOVER, 0)):Lerp(hover, x)
		elseif t < ring.gatherEnd then
			-- Spiral up from the fire into the ring slot (staggered by slot).
			local stagger = (d.slot - 1) / math.max(1, self.count) * 0.5
			local x = Fx.inOutSine(Fx.alpha(t, ring.t0 + stagger, ring.gatherEnd))
			local target = self:slotPosition(r, ring.gatherEnd, 0)
			local centre = show:centre(0)
			local fromVec, toVec = hover - centre, target - centre
			local fromAngle = math.atan2(fromVec.X, -fromVec.Z)
			local toAngle = math.atan2(toVec.X, -toVec.Z)
			local delta = (toAngle - fromAngle + math.pi) % (2 * math.pi) - math.pi + math.pi * 0.6
			local angle = fromAngle + delta * x
			local radius = Fx.lerp(Vector2.new(fromVec.X, fromVec.Z).Magnitude, R.Radius, x)
			local height = Fx.lerp(fromVec.Y, toVec.Y, x) + math.sin(x * math.pi) * 4
			pos = centre + Vector3.new(math.sin(angle) * radius, height, -math.cos(angle) * radius)
		else
			pos = self:slotPosition(r, t, phase)
		end

		-- Breath: trembling while the glow cycles through random rarities (a tick on every change).
		local shownRank = ladderRank(r, t)
		local revealed = t >= d.flareAt
		local burning = t >= d.burnAt and not revealed
		local breathing = t >= d.breathAt and t < d.burnAt
		if pos and breathing then
			local f = Fx.alpha(t, d.breathAt, d.burnAt)
			local amp = 0.05 + 0.3 * f * f
			local k = math.floor(t * 40)
			pos += Vector3.new((Fx.hash(k + index) - 0.5) * amp, (Fx.hash(k + index + 0.3) - 0.5) * amp, (Fx.hash(k + index + 0.6) - 0.5) * amp)
		end
		if shownRank ~= r.lastRank then
			if shownRank > 0 and breathing then
				Fx.sound("RelicTick", pos, 0.6, 0.85 + 0.09 * shownRank)
			end
			r.lastRank = shownRank
		end
		local glowColor = shownRank > 0 and Fx.rarityColor(LADDER[shownRank]) or Fx.FIRE

		-- Dispersal: the item streaks to its owner.
		local streakT = ring.disperseAt + (r.data.revealIndex - 1) * 0.08
		local streaking = t >= streakT
		local gone = t >= streakT + STREAK_TIME
		if pos and streaking then
			local root = show:memberRoot(d.member)
			local brazier = show.braziers[d.member]
			local target = (root and root.Position) or (brazier and brazier.bowl) or show:centre(0)
			local x = Fx.inCubic(Fx.alpha(t, streakT, streakT + STREAK_TIME))
			local control = pos:Lerp(target, 0.5) + Vector3.new(0, 8, 0)
			pos = pos:Lerp(control, x):Lerp(control:Lerp(target, x), x)
			r.trail.Enabled = not gone
		end

		if not pos or gone then
			r.holder.CFrame = HIDDEN
			Fx.place(r.shroud, HIDDEN)
			Fx.place(r.item, HIDDEN)
			r.light.Brightness = 0
			r.glow.Rate = 0
			r.cinders.Rate = 0
			if r.rags then r.rags.Rate = 0 end
			if gone and not r.landed then
				r.landed = true
				r.trail.Enabled = false
				Fx.fadePlaque(r.gui, 1)
			end
		else
			r.holder.CFrame = CFrame.new(pos)
			r.trailHost.CFrame = CFrame.new(pos)
			local spinCF = CFrame.new(pos) * CFrame.Angles(0, t * 0.8 + d.slot, 0)

			-- Shroud: whole until the burn, burns away bottom-up (shrinks + fades), then gone.
			local burn = Fx.alpha(t, d.burnAt, d.flareAt)
			local liftScale = (t < ring.t0) and Fx.outCubic(Fx.alpha(t, r.liftAt, r.liftAt + LIFT_TIME)) or 1
			if revealed then
				Fx.place(r.shroud, HIDDEN)
			else
				Fx.place(r.shroud, spinCF * CFrame.new(0, burn * 0.8, 0))
				scaleOf(r.shroud, liftScale * (1 - 0.7 * burn))
				Fx.fade(r.shroud, (dimOthers and r ~= focus) and 0.6 or burn)
				if r.emberCore then r.emberCore.Color = glowColor end
			end
			r.cinders.Rate = burning and 60 or 0
			if r.rags then r.rags.Rate = burning and 30 or 0 end

			-- The item: pops in at the flare and spins in place.
			if revealed then
				local pop = Fx.outBack(Fx.alpha(t, d.flareAt, d.flareAt + POP_TIME))
				Fx.place(r.item, CFrame.new(pos) * CFrame.Angles(0.25, t * 1.6, 0))
				scaleOf(r.item, math.max(0.05, pop))
				Fx.fade(r.item, 0)
			else
				Fx.place(r.item, HIDDEN)
			end

			-- Light: the ember's faint glow, the ladder colour while breathing, then the rarity.
			local breathF = Fx.alpha(t, d.breathAt, d.burnAt)
			local flash = revealed and (1 - Fx.alpha(t, d.flareAt, d.flareAt + 0.8)) or 0
			local brightness = 0.6 + (breathing and 2.5 * breathF or 0) + (burning and 3 or 0) + (revealed and 1.4 or 0) + 5 * flash
			if dimOthers and r ~= focus then brightness *= 0.2 end
			r.light.Brightness = brightness
			r.light.Range = revealed and (14 + 30 * flash) or 14
			r.light.Color = revealed and r.color or glowColor
			r.glow.Color = ColorSequence.new(revealed and r.color or glowColor)
			r.glow.Rate = (dimOthers and r ~= focus) and 0 or (revealed and 10 or 4 + 20 * breathF)
		end

		-- One-shots at the flare: the wave, the reveal sound, the plaque.
		show.once:at("flare" .. index, d.flareAt, t, function()
			r.wave:Fire()
			local key = ({ "RevealCommon", "RevealUncommon", "RevealRare", "RevealEpic", "RevealLegendary", "RevealLegendary" })[r.rank]
			Fx.sound(key, pos, 0.9)
		end)
		show.once:at("burn" .. index, d.burnAt, t, function()
			if r.rags then r.rags:Emit(8) end
			Fx.sound("RelicBurn", pos, 0.6)
		end)
		if pos and revealed and not gone then
			Fx.fadePlaque(r.gui, math.min(1, Fx.alpha(t, ring.disperseAt + 0.2, ring.disperseAt + 0.6) + (1 - Fx.alpha(t, d.flareAt, d.flareAt + 0.25))))
		end
	end
end

function Ring:Destroy()
	if self.empty or self.done then return end
	self.folder:Destroy()
	for _, r in ipairs(self.relics) do r.gui:Destroy() end
end

return Ring
