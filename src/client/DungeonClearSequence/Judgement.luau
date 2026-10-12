--[[
	Judgement -- stage 3 of the clear sequence: the Mythic rolls, one judgement per boss, minibosses
	first in kill order, the main boss last.

	Each miniboss judgement: a dark echo of the boss rises where it fell and shatters (Echo), and one
	Mythic relic forms from the shards. The MAIN boss's echo plays at the start of the show instead,
	right after its death animation (BossEcho); its judgement is the relic sinking from above.
	The relic itself then plays roulette: it HOPS round the braziers (every
	one, eligible or not, so a solo test still bounces a lot), each hop slower than the last, ticking
	as it lands, then lands once on each eligible member. Landing on a winner it flares Mythic
	orange: a pillar of fire from their brazier, the item spinning above it, their name and the item
	in orange. Landing on a loser it gutters grey. If nobody wins, the relic crumbles to ash with a
	bell toll where it last landed.

	The LAST landing may be a fake-out (visit.fake, revealAt = at + FakeOut): a winner relic dies
	(goes dark, sags) before it roars back; a loser relic flares as if it had won, then gutters.
	It always settles on the real result, which was decided long before (see the honesty rule in
	docs/dungeon-clear-sequence.md).

	The main boss's relic sinks slowly from above, trailing fire.

	The server-wide announcement of each win (MythicBroadcast) fires on the server at the same
	moment the relic lands on the winner's brazier here.

	Timeline (payload.judgements[]): t0, final, bossName, position, formed, visits[] {member, at,
	revealAt, fake, won, itemName, prefab}, hops[] {member, at}, verdictAt, finish; a miniboss adds riseEnd.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("DungeonClearConfig"))
local Fx = require(script.Parent:WaitForChild("Fx"))
local Echo = require(script.Parent:WaitForChild("Echo"))

local J = Config.Judgement
local MYTHIC = Fx.rarityColor("Mythic")
local GREY = Color3.fromRGB(120, 118, 116)
local FINAL_RELIC_HEIGHT = 22 -- above the floor, arena centre
local RELIC_RISE = 12         -- above the boss's fall, for a miniboss
local HIDDEN = Fx.HIDDEN
local PERCH = 3.4          -- the relic rests this far above a brazier's bowl
local HOP_RISE = 0.3       -- hop arc height, as a fraction of the hop's length
local HOP_MIN = 3          -- ... but never flatter than this (studs)
local DWELL = 0.3          -- share of each hop's time spent sitting on the brazier before leaving
local LAND_BOUNCE = 0.6    -- seconds of settling bounces after a landing (three, dying away)
local GRAVITY = 40         -- in-place hops: height = GRAVITY * T^2 / 8, so slower hops hang higher
local DARK = Color3.fromRGB(70, 62, 60) -- the relic core in a false death
local BALL = 2.8           -- the fallback ball's diameter, studs (used only without the sack model)
local SHROUD_SCALE = 1.25  -- the sack model is 3 studs; the judgement shows it a little larger

local Judgement = {}
Judgement.__index = Judgement

local function buildOne(show, folder, s, index)
	local j = { s = s, index = index, winners = {} }
	local f = Instance.new("Folder")
	f.Name = "Judgement" .. index
	f.Parent = folder
	j.folder = f

	-- Where the echo rises and where the relic ends up.
	local fallPos = typeof(s.position) == "Vector3" and s.position or show:centre(0)
	if s.final then
		j.relicPos = show:centre(FINAL_RELIC_HEIGHT)
	else
		j.echoBase = fallPos
		j.relicPos = fallPos + Vector3.new(0, RELIC_RISE, 0)
	end

	-- A miniboss's echo rises where it fell, then shatters as the relic forms. (The main boss's
	-- already played at the start of the show.)
	if not s.final then
		j.echo = Echo.new(show, f, {
			final = false, base = j.echoBase, key = "j" .. index, seed = index,
			riseFrom = s.t0, breakAt = s.riseEnd, breakEnd = s.formed,
		})
	end

	-- The Mythic relic: the very same chain-bound sack that floats in the Reliquary Ring
	-- (RS.VfxModels.CLEAR_RELIC), with a Mythic deep-orange Highlight outline and fill and an orange
	-- glow shell. j.relic is the invisible host that carries the position, light, trail and
	-- particles; the sack is placed on it every frame. With no model loaded it falls back to a
	-- plain orange loot ball.
	j.relic = Fx.part(f, {
		Name = "MythicRelic", Shape = Enum.PartType.Ball, Material = Enum.Material.Neon,
		Color = MYTHIC, Size = Vector3.one * BALL, Transparency = 1, CFrame = HIDDEN,
	})
	j.relicOutline = Fx.make("Highlight", {
		Adornee = j.relic, FillColor = MYTHIC, FillTransparency = 0.55, OutlineColor = MYTHIC,
		OutlineTransparency = 0, DepthMode = Enum.HighlightDepthMode.Occluded,
	}, j.relic)
	j.relicAura = Fx.emitter(j.relic, {
		Texture = "rbxasset://textures/particles/sparkles_main.dds", Rate = 16, LightEmission = 0.85,
		Lifetime = NumberRange.new(0.35, 0.8), Speed = NumberRange.new(0.2, 1.2), SpreadAngle = Vector2.new(180, 180),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-90, 90),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.15) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
		Color = ColorSequence.new(MYTHIC),
	})
	j.relicCore = Fx.part(f, {
		Name = "MythicCore", Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = MYTHIC,
		Size = Vector3.one * BALL * 1.3, Transparency = 1, CFrame = HIDDEN,
	})
	local shroud = Fx.vfxModel("CLEAR_RELIC")
	if shroud then
		shroud.Parent = f
		local glow = shroud:FindFirstChild("EmberGlow", true)
		if glow then
			glow.Material, glow.Color, glow.Transparency = Enum.Material.Neon, MYTHIC, 0.85
		end
		Fx.place(shroud, HIDDEN)
		j.shroud, j.shroudGlow = shroud, glow
		j.relicOutline.Adornee = shroud
	end
	j.relicLight = Fx.light(j.relic, MYTHIC, 20, 0)
	j.relicFire = Fx.emitter(j.relic, {
		Texture = Fx.TEX.Fire, Color = ColorSequence.new(Color3.fromRGB(255, 150, 60), Color3.fromRGB(180, 30, 10)),
		Size = Fx.seq(1.6, 0.2), Lifetime = NumberRange.new(0.4, 0.8), Speed = NumberRange.new(2, 5),
		SpreadAngle = Vector2.new(30, 30), Transparency = Fx.seq(0.2, 1), EmissionDirection = Enum.NormalId.Top,
	})
	j.relicBurst = Fx.emitter(j.relic, {
		Color = ColorSequence.new(MYTHIC, Color3.fromRGB(255, 220, 160)), Size = Fx.seq(1.4, 0),
		Lifetime = NumberRange.new(0.7, 1.3), Speed = NumberRange.new(10, 20), SpreadAngle = Vector2.new(180, 180),
		Transparency = Fx.seq(0, 1), Drag = 3,
	})
	j.ash = Fx.smoke(j.relic, {
		Color = ColorSequence.new(Fx.ASH), Size = Fx.seq(1.5, 4), Lifetime = NumberRange.new(1.5, 2.5),
		Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(180, 180), Acceleration = Vector3.new(0, -4, 0),
		Transparency = Fx.seq(0.2, 1),
	})
	local trailA = Fx.attachment(j.relic, Vector3.new(0, 1.2, 0))
	local trailB = Fx.attachment(j.relic, Vector3.new(0, -1.2, 0))
	j.relicTrail = Fx.make("Trail", {
		Attachment0 = trailA, Attachment1 = trailB, Lifetime = 0.9, LightEmission = 1, LightInfluence = 0,
		FaceCamera = true, Enabled = false, Transparency = Fx.seq(0.1, 1),
		Color = ColorSequence.new(Color3.fromRGB(255, 190, 90), MYTHIC),
	}, j.relic)

	-- Per winner: a pillar of fire, the spinning item, a plaque.
	for _, visit in ipairs(s.visits or {}) do
		if visit.won then
			local brazier = show.braziers[visit.member]
			local bowl = brazier and brazier.bowl or show:centre(4)
			local pillar = Fx.part(f, {
				Name = "Pillar", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = MYTHIC,
				Size = Vector3.new(40, 3, 3), Transparency = 1,
				CFrame = CFrame.new(bowl + Vector3.new(0, 20, 0)) * CFrame.Angles(0, 0, math.pi / 2),
			})
			local pillarFire = Fx.emitter(pillar, {
				Texture = Fx.TEX.Fire, Color = ColorSequence.new(Color3.fromRGB(255, 170, 70), MYTHIC),
				Size = Fx.seq(3, 0.5), Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(10, 18),
				SpreadAngle = Vector2.new(8, 8), Transparency = Fx.seq(0.1, 1),
				Shape = Enum.ParticleEmitterShape.Cylinder, EmissionDirection = Enum.NormalId.Right,
			})
			local item = Fx.lootPrefab(visit.prefab)
			if item then item.Parent = f else
				item = Fx.part(f, { Name = "Gem", Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = MYTHIC, Size = Vector3.one * 1.8 })
			end
			Fx.place(item, HIDDEN)
			local trailHost = Fx.part(f, { Name = "TrailHost", Transparency = 1, Size = Vector3.one * 0.2, CFrame = HIDDEN })
			local trail = Fx.make("Trail", {
				Attachment0 = Fx.attachment(trailHost, Vector3.new(0, 0.4, 0)),
				Attachment1 = Fx.attachment(trailHost, Vector3.new(0, -0.4, 0)),
				Lifetime = 0.4, LightEmission = 1, LightInfluence = 0, FaceCamera = true, Enabled = false,
				Color = ColorSequence.new(MYTHIC), Transparency = Fx.seq(0.1, 1),
			}, trailHost)
			local plaqueAnchor = Fx.part(f, { Name = "PlaqueAnchor", Transparency = 1, Size = Vector3.one * 0.2, CFrame = HIDDEN })
			local gui = show:plaque(plaqueAnchor, {
				size = UDim2.fromOffset(320, 70), maxDistance = 450,
				lines = {
					{ text = (show.members[visit.member] or {}).name or "", color = MYTHIC, height = 0.55, y = 0, stroke = 3 },
					{ text = visit.itemName or "", color = Color3.fromRGB(255, 205, 160), height = 0.45, y = 0.55 },
				},
			})
			Fx.fadePlaque(gui, 1)
			table.insert(j.winners, {
				visit = visit, bowl = bowl, pillar = pillar, pillarFire = pillarFire,
				item = item, trailHost = trailHost, trail = trail, plaqueAnchor = plaqueAnchor, gui = gui,
			})
		end
	end
	-- Every stop the relic makes, in order: the neutral hops, then the verdict landings.
	j.stops = {}
	for _, hop in ipairs(s.hops or {}) do table.insert(j.stops, { member = hop.member, at = hop.at, neutral = true }) end
	for _, visit in ipairs(s.visits or {}) do table.insert(j.stops, visit) end
	return j
end

function Judgement.new(show)
	local self = setmetatable({ show = show, list = {} }, Judgement)
	local folder = Instance.new("Folder")
	folder.Name = "Judgements"
	folder.Parent = show.folder
	self.folder = folder
	-- Built lazily, when each judgement is close: the braziers must exist first (Pyres builds
	-- them in the same frame, but order is not guaranteed if a stage failed).
	return self
end

-- Where the hopping relic is at time t (after it has formed): resting over a brazier, or in the air
-- between two. Stop i is reached at stop.at, after a short dwell on the brazier it is leaving. A hop
-- between braziers arcs by its length; a hop that lands where it started (a solo run, or the lap
-- coming round) is a plain bounce whose height follows its hang time. Returns position, whether it
-- is in the air, the last VERDICT visit it landed on (or nil), and the time of its last landing.
local function relicSweepAt(show, j, t, rest)
	local s = j.s
	local fromPos, fromAt = rest, s.formed
	local landed, landedAt
	for i, stop in ipairs(j.stops) do
		local brazier = show.braziers[stop.member]
		local pos = (brazier and brazier.bowl or show:centre(2)) + Vector3.new(0, PERCH, 0)
		if t < stop.at then
			local dwell = (i > 1) and (stop.at - fromAt) * DWELL or 0
			local x = Fx.alpha(t, fromAt + dwell, stop.at)
			if x <= 0 then return fromPos, false, landed, landedAt end
			local dist = (pos - fromPos).Magnitude
			local height
			if dist < 2 then
				local hang = stop.at - (fromAt + dwell)
				height = math.clamp(GRAVITY * hang * hang / 8, 1.2, 8)
			else
				height = math.max(HOP_MIN, dist * HOP_RISE)
			end
			return fromPos:Lerp(pos, x) + Vector3.new(0, height * 4 * x * (1 - x), 0), true, landed, landedAt
		end
		fromPos, fromAt, landedAt = pos, stop.at, stop.at
		if not stop.neutral then landed = stop end
	end
	return fromPos, false, landed, landedAt
end

function Judgement:updateOne(j, t)
	local show, s = self.show, j.s
	local once = show.once
	local key = "j" .. j.index

	-- 1. A miniboss's echo (the main boss's is BossEcho, at the start of the show).
	if j.echo then j.echo:Update(t) end

	-- 2. The relic forms (final: sinks slowly out of the dark, trailing fire), then hops brazier to
	-- brazier. relicPos is where it IS now; the verdict (crumble / burst) happens wherever it sits.
	local relicPos, relicVis, moving, landed, landedAt
	if t >= s.formed and #j.stops > 0 then
		relicPos, moving, landed, landedAt = relicSweepAt(show, j, t, j.relicPos)
		relicVis = true
		-- Settling on a brazier: a few bounces dying away.
		local since = landedAt and t - landedAt or LAND_BOUNCE
		if not moving and since < LAND_BOUNCE then
			local k = since / LAND_BOUNCE
			relicPos += Vector3.new(0, 1.3 * (1 - k) * (1 - k) * math.abs(math.sin(k * math.pi * 3)), 0)
		end
	elseif s.final then
		local x = Fx.inOutSine(Fx.alpha(t, s.t0, s.formed))
		relicPos = j.relicPos + Vector3.new(0, 18 * (1 - x), 0)
		relicVis = t >= s.t0
		moving = relicVis and x < 1
		once:at(key .. "descend", s.t0, t, function() Fx.sound("MythicDescend", relicPos, 1) end)
	else
		relicPos = j.relicPos
		relicVis = t >= s.riseEnd
	end
	local verdict = t >= s.verdictAt
	local anyWin = #j.winners > 0
	local endX = Fx.alpha(t, s.verdictAt, s.verdictAt + J.Verdict * 0.6)
	if relicVis and not (verdict and endX >= 1) then
		local popFrom = s.final and s.t0 or s.riseEnd
		local pop = Fx.outBack(Fx.alpha(t, popFrom, popFrom + 0.5))
		local shrink = verdict and (1 - endX) or 1
		local spin = t * (moving and 3.2 or 0.9)
		j.relic.Size = Vector3.one * BALL * math.max(0.05, pop * shrink)
		j.relicCore.Size = j.relic.Size * 1.3
		j.relic.Transparency = verdict and endX or 0
		j.relicOutline.OutlineTransparency = verdict and endX or 0
		j.relicOutline.FillTransparency = 0.55 + 0.45 * (verdict and endX or 0)
		-- The core colour. A fresh VERDICT landing: Mythic orange for a winner, grey for a loser.
		-- The fake-out (the last landing, until its reveal): a winner relic is dark and dead, a
		-- loser relic blazes as if it had won.
		local core, boost, dark = MYTHIC, 0, false
		if landed then
			local reveal = landed.revealAt or landed.at
			if landed.fake and t < reveal then
				if landed.won then
					dark, core, boost = true, DARK, -2.6
				else
					boost = 4
				end
			elseif t - reveal < 0.8 then
				local fade = 1 - (t - reveal) / 0.8
				core = landed.won and MYTHIC or MYTHIC:Lerp(GREY, fade)
				boost = (landed.won and 4 or 0) * fade
			end
		end
		local sag = dark and 0.5 or 0
		local cf = CFrame.new(relicPos + Vector3.new(0, 0.3 * math.sin(t * 2) - sag, 0)) * CFrame.Angles(0, spin, 0)
		j.relic.CFrame = cf
		j.relicCore.CFrame = cf
		j.relicCore.Color = core
		j.relic.Color = core
		j.relicOutline.OutlineColor = core
		j.relicOutline.FillColor = core
		j.relicAura.Rate = (verdict or dark) and 0 or 16
		j.relicLight.Color = core
		j.relicCore.Transparency = dark and 0.93 or (0.75 + 0.15 * math.sin(t * 8) + (verdict and 0.25 * endX or 0) - (boost > 0 and 0.4 * boost / 4 or 0))
		j.relicLight.Brightness = math.max(0.25, 3 + math.sin(t * 8) + boost)
		j.relicFire.Rate = (verdict or dark) and 0 or (moving and 45 or (boost > 0 and 60 or 25))
		j.relicTrail.Enabled = moving == true and not verdict
		if j.shroud then
			-- The sack is the relic; the host ball and its shell stay invisible.
			j.relic.Transparency, j.relicCore.Transparency = 1, 1
			j.shroud:ScaleTo(math.max(0.05, SHROUD_SCALE * pop * shrink))
			Fx.place(j.shroud, cf)
			Fx.fade(j.shroud, verdict and endX or 0)
			if j.shroudGlow then j.shroudGlow.Color = core end
		end
	else
		j.relic.CFrame = HIDDEN
		j.relicCore.CFrame = HIDDEN
		j.relicLight.Brightness = 0
		j.relicFire.Rate = 0
		j.relicAura.Rate = 0
		if j.shroud then Fx.place(j.shroud, HIDDEN) end
		j.relicTrail.Enabled = false
	end
	once:at(key .. "formed", s.formed, t, function() j.relicBurst:Emit(20) end)

	-- 3. The landings. A neutral hop is a tick and a flicker on the brazier. A verdict landing shows
	-- its result at once, unless it is the fake-out: then the landing plays the false result and
	-- the true one arrives at revealAt.
	for i, hop in ipairs(s.hops or {}) do
		once:at(key .. "hop" .. i, hop.at, t, function()
			local brazier = show.braziers[hop.member]
			local pos = brazier and brazier.bowl or show:centre(2)
			Fx.sound("JudgementTick", pos, 0.5, 0.85 + 0.03 * i)
			if brazier then brazier.flare(hop.at, Fx.PALE, 0.15) end
		end)
	end
	for v, visit in ipairs(s.visits or {}) do
		local reveal = visit.revealAt or visit.at
		local function showResult(won)
			local brazier = show.braziers[visit.member]
			local pos = brazier and brazier.bowl or show:centre(2)
			if won then
				Fx.sound("MythicWin", pos, 1)
				if brazier then brazier.flare(reveal, MYTHIC, 2) end
				j.relicBurst:Emit(25)
			else
				Fx.sound("JudgementTick", pos, 0.7, 0.9 + 0.05 * v)
				if brazier then brazier.flare(reveal, GREY, 0.3) end
				j.ash:Emit(6)
			end
		end
		once:at(key .. "visit" .. v, visit.at, t, function()
			if not visit.fake then showResult(visit.won) return end
			local brazier = show.braziers[visit.member]
			local pos = brazier and brazier.bowl or show:centre(2)
			if visit.won then
				-- False death: the light goes out of the relic.
				Fx.sound("JudgementTick", pos, 0.7, 0.7)
				j.ash:Emit(10)
			else
				-- False win: it blazes.
				Fx.sound("MythicWin", pos, 0.6)
				if brazier then brazier.flare(visit.at, MYTHIC, 1.2) end
				j.relicBurst:Emit(18)
			end
		end)
		if visit.fake then
			once:at(key .. "reveal" .. v, reveal, t, function() showResult(visit.won) end)
		end
	end

	-- 4. Winners: pillar, item spinning over the brazier, plaque; then the item streaks home.
	for _, w in ipairs(j.winners) do
		local at = w.visit.revealAt or w.visit.at
		local pillarX = Fx.alpha(t, at, at + 1.6)
		w.pillar.Transparency = (t >= at and pillarX < 1) and (0.1 + 0.9 * pillarX) or 1
		w.pillarFire.Rate = (t >= at and pillarX < 0.7) and 80 or 0
		local streakAt = s.finish - 0.7
		if t >= at and t < s.finish then
			local pos = w.bowl + Vector3.new(0, 6 + 0.4 * math.sin(t * 2), 0)
			if t >= streakAt then
				local root = show:memberRoot(w.visit.member)
				local target = root and root.Position or w.bowl
				local x = Fx.inCubic(Fx.alpha(t, streakAt, s.finish))
				pos = pos:Lerp(target, x)
				w.trail.Enabled = true
			end
			Fx.place(w.item, CFrame.new(pos) * CFrame.Angles(0.25, t * 1.6, 0))
			w.trailHost.CFrame = CFrame.new(pos)
			w.plaqueAnchor.CFrame = CFrame.new(w.bowl + Vector3.new(0, 10.5, 0))
			Fx.fadePlaque(w.gui, math.min(1, (1 - Fx.alpha(t, at, at + 0.3)) + Fx.alpha(t, s.finish - 0.4, s.finish)))
		else
			Fx.place(w.item, HIDDEN)
			w.trail.Enabled = false
			Fx.fadePlaque(w.gui, 1)
		end
	end

	-- 5. The verdict: winners -> the relic bursts into sparks; nobody -> it crumbles to ash.
	once:at(key .. "verdict", s.verdictAt, t, function()
		if anyWin then
			j.relicBurst:Emit(40)
		else
			j.ash:Emit(30)
			Fx.sound("MythicToll", relicPos, 1)
		end
	end)
end

function Judgement:Update(t)
	local show = self.show
	local list = show.payload.judgements or {}
	for index, s in ipairs(list) do
		local j = self.list[index]
		if not j and t >= s.t0 - 1 and t < s.finish + 1 then
			j = buildOne(show, self.folder, s, index)
			self.list[index] = j
		end
		if j and not j.done then
			if t >= s.finish + 1 then
				j.folder:Destroy()
				for _, w in ipairs(j.winners) do w.gui:Destroy() end
				j.done = true
			else
				self:updateOne(j, t)
			end
		end
	end
end

function Judgement:Destroy()
	self.folder:Destroy()
	for _, j in pairs(self.list) do
		for _, w in ipairs(j.winners) do w.gui:Destroy() end
	end
end

return Judgement
