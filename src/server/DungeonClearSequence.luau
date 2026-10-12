--[[
	DungeonClearSequence -- ServerScriptService (docs/dungeon-clear-sequence.md)

	The in-world show that plays in the boss room when a dungeon is cleared, for the whole party
	at once:

		0  Benediction      a shaft of gold light, a winged core; it fades out on its own
		1  Pyres            a brazier per member; their score pours in as embers, the scrapped
		                    low rolls burn off, the kept drops lift out as shrouded relics
		2  Reliquary Ring   the relics circle overhead and unveil one by one, best last
		3  Mythic Judgement per boss (minibosses in kill order, then the main boss): a beam
		                    visits each eligible member; winners flare Mythic orange

	Everything is ALREADY decided and granted when this starts: the run's score was rolled by
	DungeonScoreService.EndRun (via DungeonRunService.EndRunFor, called from Play), each boss's
	Mythic at its kill (RecordJudgement). The server lays the whole show out as ONE timeline of
	absolute offsets from `startsAt` (server clock) and fires it once; every client evaluates it
	against Workspace:GetServerTimeNow(), so the party sees the same frame at the same moment.

	Server-side effects tied to the timeline: the Mythic broadcast (MythicBroadcast, delayed to
	each winner's flare) and the summary panel (DungeonRunService.SendSummary, after the end).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("DungeonClearConfig"))
local RemoteUtils = require(ReplicatedStorage:WaitForChild("RemoteUtils"))
local LootDropVisuals = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Meshes"):WaitForChild("Loot"):WaitForChild("LootDropVisuals"))
local EncounterSoundtracks = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Sounds"):WaitForChild("EncounterSoundtracks"))
local MythicBroadcast = require(script.Parent:WaitForChild("MythicBroadcast"))
local DevFakeParty = require(script.Parent:WaitForChild("DevFakeParty"))
local MythicItemBuilder = require(script.Parent:WaitForChild("MythicItemBuilder"))

local DungeonClearSequence = {}

local remote = RemoteUtils.EnsureRemoteEvent(RemoteUtils.EnsureFolder(ReplicatedStorage, "GameEvents"), "DungeonClearSequence")

----------------------------------------------------------------------
-- Mythic Judgement log (one entry per boss kill that has a Mythic drop table)
----------------------------------------------------------------------

-- Called by LootService.tryDropMythic at the kill, after the rolls were granted.
-- `candidates`: the members who rolled (alive, not spectating). `results`: the winners.
function DungeonClearSequence.RecordJudgement(instance, mob, deathPos, candidates, results)
	if not instance then return end
	instance.mythicLog = instance.mythicLog or {}
	local stats = mob and mob.Stats or {}
	local entry = {
		mobId = mob and mob.MobID or "Unknown",
		bossName = stats.Name or (mob and mob.MobID) or "Unknown",
		position = deathPos,
		-- The main boss gets the extravagant judgement; a miniboss is any boss flagged as one.
		final = stats.IsBoss == true and stats.IsMiniBoss ~= true,
		killedAt = Workspace:GetServerTimeNow(),
		eligible = {},
		winners = {},
	}
	for _, plr in ipairs(candidates or {}) do
		table.insert(entry.eligible, plr.UserId)
	end
	for _, r in ipairs(results or {}) do
		entry.winners[r.player.UserId] = r.template
	end
	table.insert(instance.mythicLog, entry)
end

----------------------------------------------------------------------
-- Timeline
----------------------------------------------------------------------

local function prefabFor(template)
	local entry = LootDropVisuals.ResolveForTemplate(template)
	return entry and entry.PrefabName or nil
end

-- Arena-local frame the show is staged in: (origin, floorY). Origin = the centre of the boss
-- room; floorY = the walking surface's height above it, in that frame.
local function arenaOrigin(instance)
	local realm = instance.realmModel
	if instance.encounterId == "Miasma" and realm then
		local ok, Resolver = pcall(require, script.Parent:WaitForChild("MiasmaArenaResolver"))
		if ok and Resolver then
			local okNew, resolver = pcall(Resolver.new, realm)
			if okNew and resolver then
				local Layout = require(ReplicatedStorage:WaitForChild("MiasmaArenaLayout"))
				return resolver.Origin, Layout.FloorY
			end
		end
	end
	local spawn = realm and realm:FindFirstChild("SpawnPoint")
	if spawn and spawn:IsA("BasePart") then return CFrame.new(spawn.Position - Vector3.new(0, spawn.Size.Y * .5, 0)), 0 end
	return realm and realm:GetPivot() or CFrame.new(), 0
end

local function displayName(player)
	return (player.DisplayName ~= "" and player.DisplayName) or player.Name
end

-- Stage -1: the main boss's echo, right after its death animation. Fixed length.
local function layoutEcho(t)
	local E = Config.Echo
	local s = { t0 = t }
	s.blackoutEnd = t + E.Blackout
	s.echoEnd = s.blackoutEnd + E.Rise
	s.tearEnd = s.echoEnd + E.Tear
	return s, s.tearEnd
end

-- Stage 0. Fixed length.
local function layoutBenediction(t)
	local B = Config.Benediction
	local s = { t0 = t }
	s.descend = t + B.Silence
	s.unfurl = s.descend + B.Descend
	s.hold = s.unfurl + B.Unfurl
	s.fade = s.hold + B.Hold
	s.finish = s.fade + B.Fade
	return s, s.finish + B.Beat
end

-- Stage 1. Fixed length; a member with nothing kept gutters instead of lifting relics.
local function layoutPyres(t)
	local P = Config.Pyres
	local s = { t0 = t }
	s.riseEnd = t + P.Rise
	s.pourEnd = s.riseEnd + P.EmberPour
	s.burnEnd = s.pourEnd + P.Burn
	s.finish = s.burnEnd + P.RelicLift
	return s, s.finish
end

-- Stage 2. Relics sit in the ring interleaved by member (round-robin), so nobody's drops
-- clump; they are REVEALED in a random order (any rarity can come first). Every relic takes the same fixed time, so the stage grows with the drop count.
local function layoutRing(t, members)
	local R = Config.Ring
	local relics = {}
	local queues, longest = {}, 0
	for index, m in ipairs(members) do
		queues[index] = m._kept
		longest = math.max(longest, #m._kept)
	end
	for round = 1, longest do
		for index = 1, #members do
			local drop = queues[index][round]
			if drop then
				table.insert(relics, {
					member = index,
					name = drop.name,
					rarity = drop.rarity,
					prefab = prefabFor(drop),
					slot = #relics + 1,
				})
			end
		end
	end
	if #relics == 0 then return nil, t end

	local s = { t0 = t, relics = relics }
	s.gatherEnd = t + R.Gather
	s.spinEnd = s.gatherEnd + R.SpinUp

	-- The reveal order is random (a shuffle), so a Legendary can come first and the Rares last: nobody
	-- can tell from the order what is coming.
	local order = table.clone(relics)
	for i = #order, 2, -1 do
		local j = math.random(i)
		order[i], order[j] = order[j], order[i]
	end

	local clock = s.spinEnd
	for revealIndex, relic in ipairs(order) do
		relic.revealIndex = revealIndex
		relic.breathAt = clock
		relic.burnAt = clock + R.Breath
		relic.flareAt = relic.burnAt + R.Burn
		clock = relic.flareAt + R.Settle
	end
	s.disperseAt = clock
	s.finish = clock + R.Disperse
	return s, s.finish
end

-- Stage 3. One judgement per logged boss, in kill order. The beam visits eligible members in
-- brazier order, slowing each visit; a winner flares at the moment of the visit.
local function layoutJudgements(t, members, mythicLog, memberIndexByUserId)
	local J = Config.Judgement
	local judgements = {}
	local entries = table.clone(mythicLog or {})
	table.sort(entries, function(a, b)
		if a.final ~= b.final then return not a.final end -- the main boss always last
		return (a.killedAt or 0) < (b.killedAt or 0)
	end)
	for _, entry in ipairs(entries) do
		local visits = {}
		for _, uid in ipairs(entry.eligible) do
			local index = memberIndexByUserId[uid]
			if index then
				local template = entry.winners[uid]
				table.insert(visits, {
					member = index,
					userId = uid,
					won = template ~= nil,
					itemName = template and template.name or nil,
					prefab = template and prefabFor(template) or nil,
					_template = template,
				})
			end
		end
		table.sort(visits, function(a, b) return a.member < b.member end)
		if #visits > 0 then
			local s = { t0 = t, final = entry.final, bossName = entry.bossName, position = entry.position }
			local clock = t
			if entry.final then
				s.formed = clock + J.Final.Descend -- its echo already played, at the start of the show
			else
				s.riseEnd = clock + J.Rise
				s.formed = s.riseEnd + J.Shatter
			end
			clock = s.formed
			-- The roulette: neutral hops round every brazier (eligible or not, so a solo run still
			-- bounces a lot), then a landing per eligible member. Each hop is slower than the last.
			local hopCount = entry.final and J.Final.Hops or J.Hops
			local dur = J.HopStart
			local function nextHop()
				clock += dur
				dur *= J.HopGrowth
				return clock
			end
			local hops = {}
			local offset = math.random(0, math.max(0, #members - 1))
			for i = 1, hopCount do
				table.insert(hops, { member = (offset + i - 1) % math.max(1, #members) + 1, at = nextHop() })
			end
			for _, visit in ipairs(visits) do
				visit.at = nextHop()
				visit.revealAt = visit.at
			end
			-- The fake-out belongs to the last landing only.
			local chance = entry.final and J.Final.FakeOutChance or J.FakeOutChance
			local last = visits[#visits]
			if last and math.random() < chance then
				last.fake = true
				last.revealAt = last.at + J.FakeOut
				clock = last.revealAt
			end
			s.hops = hops
			s.visits = visits
			s.verdictAt = clock -- the last verdict is shown (after its fake-out, if it has one)
			s.finish = clock + J.Verdict
			table.insert(judgements, s)
			t = s.finish + J.Gap
		end
	end
	return judgements, t
end

----------------------------------------------------------------------
-- Play
----------------------------------------------------------------------

-- Cashes the party out (EndRunFor, summary held back), lays out and fires the show, schedules
-- the broadcasts and the summary. Yields briefly (the Mythic roll for the killing blow may
-- still be landing). Returns the server time the show ends at.
function DungeonClearSequence.Play(instance)
	local killedAt = Workspace:GetServerTimeNow()
	task.wait(0.75) -- let LootService.onMobDied (task.spawned at the kill) log the boss's Mythic

	local runSvc = require(ServerScriptService:WaitForChild("DungeonRunService"))
	local Instances = require(ServerScriptService:WaitForChild("DungeonInstanceService"))

	-- Members still in the instance, in party order. A member who fell in the boss fight is
	-- still here (spectating), already cashed out as "died": a cold brazier.
	local members, players, summaries, memberIndexByUserId = {}, {}, {}, {}
	for _, uid in ipairs(instance.memberUserIds or {}) do
		local plr = Players:GetPlayerByUserId(uid)
		if plr and instance.members[uid] then
			local fallen = Instances.IsSpectating(plr)
			local granted, payload
			if not fallen then
				granted, payload = runSvc.EndRunFor(plr, "cleared", { deferSummary = true })
			end
			table.insert(members, {
				userId = uid,
				name = displayName(plr),
				state = fallen and "fallen" or "live",
				score = payload and payload.score or 0,
				scrap = payload and payload.scrap and payload.scrap.qty or 0,
				kept = granted and #granted or 0,
				_kept = granted or {},
			})
			players[#members] = plr
			summaries[#members] = payload
			memberIndexByUserId[uid] = #members
		end
	end

	-- Dev stand-ins (F8 Dungeon tab, DevFakeParty): extra braziers after every real member, so the
	-- `players` / `summaries` lists stay gap-free. No Player, nothing granted: pure theatre.
	local fakes = DevFakeParty.Collect(instance)
	local fakeCount = 0
	for _, fake in ipairs(fakes) do
		if #members >= 8 then break end
		fakeCount += 1
		table.insert(members, {
			userId = fake.userId, name = fake.name, state = "live",
			score = fake.score, scrap = fake.scrap, kept = #fake.kept, _kept = fake.kept,
		})
		memberIndexByUserId[fake.userId] = #members
		fake.index = #members
	end

	-- Brazier slots: evenly around the circle, the first one facing the entrance side.
	for index, m in ipairs(members) do
		m.angle = (index - 1) / math.max(1, #members) * 360 + 180
	end

	local startsAt = killedAt + Config.DEATH_LEAD
	local echo, t = layoutEcho(0)
	local benediction
	benediction, t = layoutBenediction(t)
	local pyres
	pyres, t = layoutPyres(t)
	local ring
	ring, t = layoutRing(t, members)
	local judgements
	-- A fake joins every logged boss's judgement, rolling the same Mythic table (forced win / loss
	-- if the dev chose). Built on a copy: the real log is untouched.
	local mythicLog = instance.mythicLog
	if fakeCount > 0 and mythicLog then
		mythicLog = {}
		for _, entry in ipairs(instance.mythicLog) do
			local copy = table.clone(entry)
			copy.eligible, copy.winners = table.clone(entry.eligible), table.clone(entry.winners)
			for _, fake in ipairs(fakes) do
				if fake.index then
					table.insert(copy.eligible, fake.userId)
					local okRoll, item = pcall(MythicItemBuilder.TryRollForMob, entry.mobId, fake.mythic)
					if okRoll and item then copy.winners[fake.userId] = item:toGrantTemplate() end
				end
			end
			table.insert(mythicLog, copy)
		end
	end
	judgements, t = layoutJudgements(t, members, mythicLog, memberIndexByUserId)
	local finish = t + 0.5

	-- A winner who is no longer in the instance (left after the kill) gets no beam in the show,
	-- but still gets the server-wide announcement, straight away.
	for _, entry in ipairs(instance.mythicLog or {}) do
		for uid, template in pairs(entry.winners) do
			local plr = Players:GetPlayerByUserId(uid)
			if plr and not memberIndexByUserId[uid] then MythicBroadcast.Announce(plr, template, entry.bossName) end
		end
	end

	local judgementWire = {}
	for _, s in ipairs(judgements) do
		local visits = {}
		for _, v in ipairs(s.visits) do
			table.insert(visits, { member = v.member, at = v.at, revealAt = v.revealAt, fake = v.fake, won = v.won, itemName = v.itemName, prefab = v.prefab })
			if v.won then
				local plr = players[v.member]
				if plr then MythicBroadcast.Announce(plr, v._template, s.bossName, (startsAt + v.revealAt) - Workspace:GetServerTimeNow()) end
			end
		end
		local wire = table.clone(s)
		wire.visits = visits
		table.insert(judgementWire, wire)
	end
	local memberWire = {}
	for _, m in ipairs(members) do
		table.insert(memberWire, {
			userId = m.userId, name = m.name, state = m.state, angle = m.angle,
			score = m.score, scrap = m.scrap, kept = m.kept,
		})
	end

	local origin, floorY = arenaOrigin(instance)
	local payload = {
		instanceId = instance.instanceId,
		startsAt = startsAt,
		duration = finish,
		origin = origin,
		floorY = floorY,
		members = memberWire,
		echo = echo,
		benediction = benediction,
		pyres = pyres,
		ring = ring,
		judgements = judgementWire,
	}
	for uid in pairs(instance.members) do
		local plr = Players:GetPlayerByUserId(uid)
		if plr then remote:FireClient(plr, payload) end
	end

	-- The victory layer, if one is registered (EncounterSoundtracks.DungeonClear). Cleared again
	-- by DungeonInstanceService.releaseMember on the way out, like every other dungeon layer.
	local victory = EncounterSoundtracks.DungeonClear
	if type(victory) == "string" and victory ~= "" then
		local ZoneService = require(ServerScriptService:WaitForChild("ZoneService"))
		task.delay(math.max(0, startsAt + benediction.descend - Workspace:GetServerTimeNow()), function()
			for _, plr in ipairs(players) do
				if plr.Parent then pcall(ZoneService.SetEncounterMusic, plr, victory) end
			end
		end)
	end

	local endsAt = startsAt + finish
	for index, plr in ipairs(players) do
		if summaries[index] then runSvc.SendSummary(plr, summaries[index], endsAt + Config.SUMMARY_AFTER) end
	end
	print(("[DungeonClearSequence] %s: %d member(s) (%d dev stand-in), %d relic(s), %d judgement(s), %.1fs")
		:format(tostring(instance.instanceId), #members, fakeCount, ring and #ring.relics or 0, #judgementWire, finish))
	return endsAt
end

return DungeonClearSequence
