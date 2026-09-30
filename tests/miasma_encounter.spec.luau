--[[
	Pure-logic regressions for the Miasma encounter and the valve maze.

	Called with a context table so the same spec runs under the Luau CLI
	(tests/run_miasma_encounter.py, with shims) or in Studio Edit mode:
		ctx.Math, ctx.Config, ctx.Layouts, ctx.Geometry, ctx.Runes
		ctx.Layout            -> RS/MiasmaArenaLayout (skipped where CFrame is unavailable)
		ctx.newMazeService()  -> fresh MiasmaMazeService instance
		ctx.setClock(seconds) -> controls os.clock() as seen by MiasmaMazeService
]]
return function(ctx)
	local Math, Config, Layouts, Geometry, Runes = ctx.Math, ctx.Config, ctx.Layouts, ctx.Geometry, ctx.Runes
	local count = 0
	local function check(value, message)
		assert(value, message)
		count += 1
	end

	-- Encounter formulas ----------------------------------------------------------------
	for partySize = 1, 8 do
		check(Math.ActiveGateCount(partySize) == math.min(partySize, 4), "active gate formula " .. partySize)
		check(Math.SlimeWaveSize(partySize) == math.ceil(partySize / 2), "wave formula " .. partySize)
		check(Math.SlimeLivingCap(partySize) == math.min(3 * partySize, 16), "slime cap " .. partySize)
		check(Math.SackCount(partySize) == math.min(math.ceil(partySize / 2) + 1, 5), "sack formula " .. partySize)
		check(math.abs(Math.AltarCooldown(partySize, 120) - 120 / partySize) < 1e-9, "altar cooldown " .. partySize)
		check(Config.Gates.Workload[partySize] ~= nil, "gate workload exists " .. partySize)
	end
	local expected = { {2,3},{2,3},{2,3},{2,3},{3,4},{3,5},{4,5},{4,6} }
	for partySize, pair in ipairs(expected) do
		local workload = Config.Gates.Workload[partySize]
		check(workload.clogs == pair[1] and workload.symbols == pair[2], "workload table " .. partySize)
	end
	check(Math.SlimeWaveInterval(0, 60, 12, 6) == 12, "wave starts at twelve seconds")
	check(Math.SlimeWaveInterval(60, 60, 12, 6) == 6, "wave ends at six seconds")
	check(Math.SlimeWaveInterval(30, 60, 12, 6) == 9, "wave interpolation")
	check(Math.PoisonTick(345, 5, .01, 50) == 17.25, "poison is max health percent per stack")
	check(Math.PoisonTick(2000, 5, .01, 50) == 50, "poison aggregate cap")
	check(Math.EncodeGateSet({4,1,3}) == "1,3,4", "gate set identity is order independent")

	-- Arena layout invariants (the one placement source) --------------------------------
	local Layout = ctx.Layout
	if Layout and CFrame then
		check(#Layout.Stations == 4, "four valve stations")
		check(Layout.PlatformRadius >= Config.BossDropRadius + 10, "landing danger leaves a >= 10 stud escape ring on the platform")
		check(Layout.Apothem - Layout.PlatformRadius >= 30, "perimeter ring wide enough for the boss core plus clearance")
		check(Layout.Entrance.Width >= 10, "entrance route >= 10 wide")
		check(Layout.Recess.Width >= 8, "station/altar approaches >= 8 wide")
		check(Layout.ShaftHalfWidth > 99.8 * .67 / 2, "latch disc fits the ceiling shaft")
		check(Layout.CeilingY - Layout.FloorY >= 46 + 10, "ceiling clears the standing boss")
		local anchors = Layout.Anchors()
		check(anchors.ANCHOR_Miasma_CeilingLatch == Vector3.new(0, 53, 0), "latch anchor unchanged (animation-aligned)")
		check(anchors.ANCHOR_CisternLiquidPivot == Vector3.new(0, 56.4, 0), "cistern pivot unchanged")
		local frames = {}
		for index = 1, 4 do
			local frame = Layout.StationFrame(index)
			local flat = Vector3.new(frame.Position.X, 0, frame.Position.Z)
			local angle = Layout.Stations[index].Angle
			check(frame.LookVector:Dot(Layout.Outward(angle)) > .999, "station " .. index .. " faces its wall")
			local back = frame:PointToWorldSpace(Vector3.new(0, 0, -5.3))
			check(math.abs(Vector3.new(back.X, 0, back.Z):Dot(Layout.Outward(angle)) - Layout.Apothem) < .5, "station " .. index .. " back flush with the room wall")
			local face = Layout.FaceFrame(angle)
			local G = Layout.Gate
			for _, corner in ipairs({ Vector3.new(-10.4, 0, -0.6), Vector3.new(7.5, 0, 8) }) do
				local p = face:PointToObjectSpace(frame:PointToWorldSpace(corner))
				check(p.X >= G.Platform.X[1] - .1 and p.X <= G.Platform.X[2] + .1 and p.Z >= G.Platform.Z[1] - .1 and p.Z <= G.Platform.Z[2] + .1,
					"station " .. index .. " footprint on its valve platform")
			end
			check(math.abs(face:PointToObjectSpace(frame.Position).Y - G.Platform.Top) < 1e-3, "station " .. index .. " stands on the platform top")
			for _, z in ipairs(G.GrateZ[index]) do
				check(z - G.GrateHalfLength > G.Bridge.Z[2] and z + G.GrateHalfLength < Layout.Apothem - Layout.BasinRadius - 1.3,
					"gate " .. index .. " grate on the open channel run")
			end
			check(G.ChannelHalfWidth * 2 >= G.OpeningHalfWidth, "gate " .. index .. " channel at least half the gate width")
			for _, other in ipairs(frames) do check((other - flat).Magnitude > 50, "stations are distinct") end
			table.insert(frames, flat)
			local mouth, split, finish = Layout.ChannelPath(index)
			check(math.abs(Vector3.new(finish.X, 0, finish.Z).Magnitude - Layout.BasinRadius) < 1e-3, "channel " .. index .. " reaches the basin")
			check(math.abs(Vector3.new(split.X, 0, split.Z).Magnitude - Layout.PlatformRadius) < 1.5, "channel " .. index .. " splits at the platform edge")
			local protection = Layout.StationProtectionCentre(index)
			for _, localPoint in ipairs({ Vector3.new(0, 0, 1.2), Vector3.new(-6, 0, 2.6), Vector3.new(-1, 0, 12) }) do
				local p = frame:PointToWorldSpace(localPoint)
				check(Vector3.new(p.X - protection.X, 0, p.Z - protection.Z).Magnitude <= Config.Arena.ProtectedRadius, "station " .. index .. " controls protected")
			end
		end
		for index = 1, #Layout.SafeAreas do
			local p = anchors[("ANCHOR_PurgeSafe_%02d"):format(index)]
			check(Vector3.new(p.X, 0, p.Z).Magnitude + Layout.SafeAreaRadius <= Layout.Circumradius - 4, "safe pad " .. index .. " fits its corner")
		end
		check(Config.Arena.HazardRadius + Config.Abilities.PoisonScatter.Radius <= Layout.Apothem, "puddles stay inside the walls")
	end

	-- Runes -----------------------------------------------------------------------------
	check(#Runes.Order == 8, "eight runes")
	local picked = Runes.Pick(6)
	local seen = {}
	for _, id in ipairs(picked) do
		check(Runes.IsValid(id) and not seen[id], "picked runes are valid and distinct")
		seen[id] = true
	end

	-- Layouts: authoring rules ----------------------------------------------------------
	check(#Layouts == 6, "six authored maze layouts")
	for index, layout in ipairs(Layouts) do
		local ok, message = Geometry.Validate(layout)
		check(ok, "layout " .. index .. " valid: " .. tostring(message))
		local parsed = Geometry.Parse(layout)
		check(#parsed.slots == 8, "layout " .. index .. " parses eight slots")
		check(parsed.start ~= nil, "layout " .. index .. " has a start")
	end

	-- Geometry: every rotation/reflection stays solvable under the REAL collision -------
	local function cellGraph(geometry, margin, radius)
		local size = geometry.size
		local function centre(c, r) return Vector2.new((c + .5) / size, (r + .5) / size) end
		local slotAt = {}
		for index, slot in ipairs(geometry.slots) do
			slotAt[math.floor(slot.X * size) .. "," .. math.floor(slot.Y * size)] = index
		end
		local function key(c, r) return c .. "," .. r end
		local function open(c1, r1, c2, r2)
			return not Geometry.SegmentHitsWall(centre(c1, r1), centre(c2, r2), geometry.walls, margin)
		end
		return size, centre, slotAt, key, open
	end

	for index, layout in ipairs(Layouts) do
		local parsed = Geometry.Parse(layout)
		for rotation = 0, 3 do
			for _, mirrored in ipairs({ false, true }) do
				local g = Geometry.Transform(parsed, rotation, mirrored)
				local metrics = Geometry.Metrics(g, false)
				local label = ("layout %d rot %d mirror %s"):format(index, rotation, tostring(mirrored))
				for _, wall in ipairs(g.walls) do
					for _, p in ipairs(wall) do check(p.X >= -1e-9 and p.X <= 1 + 1e-9 and p.Y >= -1e-9 and p.Y <= 1 + 1e-9, label .. " wall in bounds") end
				end
				local size, centre, slotAt, key, open = cellGraph(g, metrics.wallMargin, metrics.symbolRadius)
				local sc, sr = math.floor(g.start.X * size), math.floor(g.start.Y * size)
				local reached = { [key(sc, sr)] = true }
				local queue = { { sc, sr } }
				local head = 1
				local reachedCount = 1
				while head <= #queue do
					local c, r = queue[head][1], queue[head][2]; head += 1
					for _, d in ipairs({ {1,0},{-1,0},{0,1},{0,-1} }) do
						local nc, nr = c + d[1], r + d[2]
						if nc >= 0 and nc < size and nr >= 0 and nr < size and not reached[key(nc, nr)] and not slotAt[key(nc, nr)] and open(c, r, nc, nr) then
							-- Walking between two corridor cells must never brush a rune.
							check(Geometry.FirstSlotContact(centre(c, r), centre(nc, nr), g.slots, metrics.symbolRadius) == nil, label .. " corridor clear of runes")
							reached[key(nc, nr)] = true
							reachedCount += 1
							table.insert(queue, { nc, nr })
						end
					end
				end
				check(reachedCount == size * size - 8, label .. " every corridor cell reachable")
				for slotIndex, slot in ipairs(g.slots) do
					local c, r = math.floor(slot.X * size), math.floor(slot.Y * size)
					local reachable = false
					for _, d in ipairs({ {1,0},{-1,0},{0,1},{0,-1} }) do
						local nc, nr = c + d[1], r + d[2]
						if reached[key(nc, nr)] and open(nc, nr, c, r) then reachable = true end
					end
					check(reachable, label .. " slot " .. slotIndex .. " reachable")
				end
			end
		end
	end

	local wall = { { Vector2.new(.5, 0), Vector2.new(.5, 1) } }
	check(Geometry.SegmentHitsWall(Vector2.new(.1, .5), Vector2.new(.9, .5), wall, .01), "crossing a wall is caught")
	check(Geometry.SegmentHitsWall(Vector2.new(.1, .5), Vector2.new(.495, .5), wall, .01), "brushing a wall is caught")
	check(not Geometry.SegmentHitsWall(Vector2.new(.1, .2), Vector2.new(.4, .2), wall, .01), "clear segment passes")
	check(Geometry.SegmentHitsWall(Vector2.new(.9, .5), Vector2.new(1.05, .5), {}, .01), "leaving the board is a wall")

	-- Server maze rules -----------------------------------------------------------------
	if ctx.newMazeService then
		local clock = 100
		ctx.setClock(clock)
		local function advance(seconds) clock += seconds; ctx.setClock(clock) end
		local playerA, playerB = { Name = "A" }, { Name = "B" }

		-- Builds a cursor path through cell centres from `from` (a point) into slot `target`.
		local function pathTo(g, fromPoint, targetSlot)
			local metrics = Geometry.Metrics(g, false)
			local size, centre, slotAt, key, open = cellGraph(g, metrics.wallMargin, metrics.symbolRadius)
			local fc, fr = math.floor(fromPoint.X * size), math.floor(fromPoint.Y * size)
			local tc, tr = math.floor(targetSlot.X * size), math.floor(targetSlot.Y * size)
			local prev = { [key(fc, fr)] = false }
			local queue = { { fc, fr } }
			local head = 1
			while head <= #queue do
				local c, r = queue[head][1], queue[head][2]; head += 1
				if c == tc and r == tr then break end
				for _, d in ipairs({ {1,0},{-1,0},{0,1},{0,-1} }) do
					local nc, nr = c + d[1], r + d[2]
					local k = key(nc, nr)
					local isTarget = nc == tc and nr == tr
					if nc >= 0 and nc < size and nr >= 0 and nr < size and prev[k] == nil and (isTarget or not slotAt[k]) and open(c, r, nc, nr) then
						prev[k] = { c, r }
						table.insert(queue, { nc, nr })
					end
				end
			end
			local cells = {}
			local cursor = { tc, tr }
			while cursor do
				table.insert(cells, 1, cursor)
				cursor = prev[key(cursor[1], cursor[2])]
			end
			local points = {}
			for i = 2, #cells do
				local a, b = centre(cells[i - 1][1], cells[i - 1][2]), centre(cells[i][1], cells[i][2])
				for s = 1, 4 do
					local p = a + (b - a) * (s / 4)
					table.insert(points, p.X); table.insert(points, p.Y)
				end
			end
			return points
		end

		-- Delivers `points` in 8-point batches, advancing the clock like a steady human hand
		-- (3 board-widths per second, under the server's speed budget).
		local function submitPath(service, player, session, epoch, points)
			local last
			local previous = service:GetAttempt(player) and service:GetAttempt(player).last
			for i = 1, #points, 16 do
				local batch = {}
				local length = 0
				for j = i, math.min(i + 15, #points), 2 do
					local p = Vector2.new(points[j], points[j + 1])
					if previous then length += (p - previous).Magnitude end
					previous = p
					table.insert(batch, points[j]); table.insert(batch, points[j + 1])
				end
				advance(math.max(1 / 15, length / 3))
				last = service:Submit(player, { session = session, epoch = epoch, points = batch })
				if last and last.kind ~= "Progress" then return last end
			end
			return last
		end

		local function geometryFor(service, player)
			return service:GetAttempt(player).geometry
		end

		-- (1) Reservation is exclusive.
		local service = ctx.newMazeService()
		local open = service:Open(playerA, 1, { "Eye", "Fang", "Crown" })
		check(open ~= nil and open.requiredCount == 3 and #open.symbols == 8, "open returns a client payload")
		for _, symbol in ipairs(open.symbols) do check(symbol.required == nil, "payload never marks target runes") end
		check(open.required == nil and open.requiredSymbols == nil, "payload carries no target set")
		local denied, reason = service:Open(playerB, 1, { "Eye" })
		check(denied == nil and reason == "Reserved", "second operator is refused")

		-- (2) Real paths through every target rune complete, in any order, across random
		-- layouts, transforms, placements and target sizes 3..6.
		for trial = 1, 60 do
			local trialService = ctx.newMazeService()
			local ids = Runes.Pick(({ 3, 4, 5, 6 })[(trial % 4) + 1])
			local trialOpen = trialService:Open(playerA, 1, ids)
			local trialAttempt = trialService:GetAttempt(playerA)
			local tg = trialAttempt.geometry
			local from = tg.start
			local result
			local targets = {}
			for index, placement in ipairs(trialAttempt.placements) do
				if trialAttempt.required[placement.id] then table.insert(targets, 1, index) end -- reverse order on purpose
			end
			advance(3)
			for _, slotIndex in ipairs(targets) do
				result = submitPath(trialService, playerA, trialOpen.session, 0, pathTo(tg, from, tg.slots[slotIndex]))
				check(not (result and result.kind == "Reset"), "trial " .. trial .. " never resets on a clean path")
				from = tg.slots[slotIndex]
			end
			check(result and result.kind == "Complete", "trial " .. trial .. " completes")
			check(trialService:GetOperator(1) == nil, "completion releases the reservation")
			check(trialService:Submit(playerA, { session = trialOpen.session, epoch = 0, points = { .5, .5 } }) == nil, "duplicate completion is ignored")
		end
		service:Release(playerA)
		local result, g, attempt

		-- (3) Crossing a wall resets: jump from the drain into a neighbouring cell behind a wall.
		for _ = 1, 20 do
			open = service:Open(playerA, 1, { "Eye" })
			g = geometryFor(service, playerA)
			local metrics = Geometry.Metrics(g, false)
			local size, centre, _, _, openFn = cellGraph(g, metrics.wallMargin, metrics.symbolRadius)
			local sc, sr = math.floor(g.start.X * size), math.floor(g.start.Y * size)
			for _, d in ipairs({ {1,0},{-1,0},{0,1},{0,-1} }) do
				local nc, nr = sc + d[1], sr + d[2]
				if nc >= 0 and nc < size and nr >= 0 and nr < size and not openFn(sc, sr, nc, nr) then
					advance(2)
					local blocked = centre(nc, nr)
					result = service:Submit(playerA, { session = open.session, epoch = 0, points = { blocked.X, blocked.Y } })
					check(result and result.kind == "Reset" and result.reason == "Wall", "wall crossing resets")
					break
				end
			end
		end

		-- (4) Touching a non-target rune resets.
		open = service:Open(playerA, 1, { "Eye", "Fang", "Crown" })
		attempt = service:GetAttempt(playerA)
		g = attempt.geometry
		local wrongIndex
		for index, placement in ipairs(attempt.placements) do
			if not attempt.required[placement.id] then wrongIndex = index break end
		end
		advance(3)
		result = submitPath(service, playerA, open.session, 0, pathTo(g, g.start, g.slots[wrongIndex]))
		check(result and result.kind == "Reset" and result.reason == "WrongSymbol", "wrong rune resets")
		check(result.epoch == 1, "server reset bumps the epoch")
		check(service:Submit(playerA, { session = open.session, epoch = 0, points = { g.start.X, g.start.Y } }) == nil, "old epoch batch ignored")

		-- (5) Newer client epoch = client restarted; server follows.
		attempt = service:GetAttempt(playerA)
		attempt.collected.Eye = true
		attempt.collectedCount = 1
		advance(.1)
		service:Submit(playerA, { session = open.session, epoch = 3, points = {} })
		check(attempt.epoch == 3 and attempt.collectedCount == 0, "client epoch bump resets server progress")

		-- (6) Stale session ignored.
		check(service:Submit(playerA, { session = open.session - 1, epoch = 3, points = { .5, .5 } }) == nil, "stale session ignored")

		-- (7) Completion faster than plausible is refused. Target = the rune nearest the drain,
		-- traced at full legal speed straight after opening.
		open = service:Open(playerA, 1, { "Eye" })
		attempt = service:GetAttempt(playerA)
		g = attempt.geometry
		local nearestIndex, nearestPoints
		for index, slot in ipairs(g.slots) do
			local pts = pathTo(g, g.start, slot)
			if not nearestPoints or #pts < #nearestPoints then nearestIndex, nearestPoints = index, pts end
		end
		attempt.required = { [attempt.placements[nearestIndex].id] = true }
		attempt.requiredCount = 1
		result = submitPath(service, playerA, open.session, 0, nearestPoints)
		check(result and result.kind == "Reset" and result.reason == "TooFast", "impossibly quick completion resets")

		-- (8) Speed budget: rapid scribbling with no time passing slips.
		open = service:Open(playerA, 1, { "Eye" })
		attempt = service:GetAttempt(playerA)
		g = attempt.geometry
		local wiggle = {}
		for i = 1, 30 do
			local q = g.start + Vector2.new(0, (i % 2 == 0) and .02 or -.02)
			table.insert(wiggle, q.X); table.insert(wiggle, q.Y)
		end
		local slipped = false
		for _ = 1, 20 do
			result = service:Submit(playerA, { session = open.session, epoch = attempt.epoch, points = wiggle })
			if result and result.kind == "Reset" and result.reason == "Slipped" then slipped = true break end
			if result and result.kind == "Reset" then break end
		end
		check(slipped, "cursor faster than the speed budget slips")

		-- (9) Release frees the gate.
		service:Release(playerA)
		check(service:GetOperator(1) == nil and service:GetAttempt(playerA) == nil, "release clears reservation and attempt")
		check(service:Open(playerB, 1, { "Eye" }) ~= nil, "a released gate can be reserved again")
	end

	return count
end
