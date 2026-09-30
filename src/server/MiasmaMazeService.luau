--[[
	MiasmaMazeService -- server authority for valve maze attempts. Pure rules, no Instances.

	One service is shared by every valve gate of an encounter (or the dev harness). It owns:
		- reservations: at most one operator per gate key, one attempt per player;
		- the attempt: layout, rotation/reflection, rune placement, target set, collected set;
		- validation of the client's cursor path.

	Protocol (see MiasmaEncounterClient / MiasmaValveMazeUI for the other side):
		Open -> payload for the client: session id, epoch, walls, start, slots with rune ids,
		        requiredCount. The TARGET rune ids are never sent.
		Submit(player, { session, epoch, points = {x1, y1, x2, y2, ...} }) where points are
		        the cursor's normalized path since the last batch (~15 batches per second).

	Epochs: every reset starts a new epoch. The client bumps its epoch when it resets locally
	(it hit a wall); a batch with a newer epoch therefore means "I restarted", and the server
	restarts too. Server-detected resets bump the server epoch and are reported back; any
	batch still in flight from the old epoch is ignored. Both sides then trace from the start.

	Each consecutive pair of points is a segment. A segment is rejected (attempt reset) when
	it touches a wall, touches a rune that is not part of the target, or exceeds the speed
	budget. Completion requires every target rune and a plausible minimum duration.

	Blob (SpawnBlob, from Miasma's poison lob): a solid obstacle in a corridor next to the token.
	Touching it does NOT reset; the token just can't pass (a point inside or a segment through
	it is ignored). Each fresh contact -- after pulling back past BLOB_RELEASE -- is one ram;
	Tuning.BlobHits rams pop it. Results carry `blob = { hp }` or `blob = { popped = true }`.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("MiasmaEncounterConfig"))
local Geometry = require(ReplicatedStorage:WaitForChild("MiasmaMazeGeometry"))
local Layouts = require(ReplicatedStorage:WaitForChild("MiasmaMazeLayouts"))
local Runes = require(ReplicatedStorage:WaitForChild("MiasmaRunes"))

local VALVE = Config.Gates.Valve
local BLOB_THROUGH = .8   -- x block radius: deeper than this = trying to pass through (ignored)
local BLOB_CONTACT = 1.1  -- x block radius: within this = touching (a ram, if it wasn't already)
local BLOB_RELEASE = 1.3  -- x block radius: back out past this before the next ram counts

local PARSED = {}
for index, layout in ipairs(Layouts) do
	local ok, message = Geometry.Validate(layout)
	if not ok then warn(("[MiasmaMazeService] layout %d (%s) is invalid: %s"):format(index, tostring(layout.name), message)) end
	PARSED[index] = Geometry.Parse(layout)
end

local MazeService = {}
MazeService.__index = MazeService

local sessionCounter = 0

function MazeService.new()
	return setmetatable({
		Reservations = {}, -- gateKey -> player
		Attempts = {},     -- player -> attempt
		Rng = Random.new(),
		LastLayoutByGate = {},
	}, MazeService)
end

function MazeService:GetOperator(gateKey)
	return self.Reservations[gateKey]
end

function MazeService:GetAttempt(player)
	return self.Attempts[player]
end

function MazeService:_pickLayout(gateKey)
	local index = self.Rng:NextInteger(1, #PARSED)
	if #PARSED > 1 and index == self.LastLayoutByGate[gateKey] then
		index = (index % #PARSED) + 1
	end
	self.LastLayoutByGate[gateKey] = index
	return index
end

--[[
	Open(player, gateKey, requiredSymbols) -> clientPayload | nil, reason
	Reserves the gate for `player` and rolls a fresh attempt. Fails when another player
	holds the gate. A player can only operate one gate: any previous attempt is released.
]]
function MazeService:Open(player, gateKey, requiredSymbols)
	local holder = self.Reservations[gateKey]
	if holder and holder ~= player then return nil, "Reserved" end
	if type(requiredSymbols) ~= "table" or #requiredSymbols == 0 then return nil, "NoPattern" end
	self:Release(player)

	local layoutIndex = self:_pickLayout(gateKey)
	local geometry = Geometry.Transform(PARSED[layoutIndex], self.Rng:NextInteger(0, 3), self.Rng:NextNumber() < .5)
	local order = Runes.Shuffled(self.Rng)
	local placements = {}
	for index, slot in ipairs(geometry.slots) do
		placements[index] = { id = order[index], position = slot }
	end
	local required, requiredCount = {}, 0
	for _, id in ipairs(requiredSymbols) do
		if Runes.IsValid(id) and not required[id] then required[id] = true; requiredCount += 1 end
	end

	sessionCounter += 1
	local now = os.clock()
	local attempt = {
		session = sessionCounter,
		gateKey = gateKey,
		player = player,
		layoutIndex = layoutIndex,
		geometry = geometry,
		metrics = Geometry.Metrics(geometry, true),
		placements = placements,
		required = required,
		requiredCount = requiredCount,
		collected = {},
		collectedCount = 0,
		epoch = 0,
		last = geometry.start,
		openedAt = now,
		lastBatchAt = now,
		batchWindowStart = now,
		batchWindowCount = 0,
		speedBudget = VALVE.CursorSpeedBurst,
	}
	self.Reservations[gateKey] = player
	self.Attempts[player] = attempt

	local symbols = {}
	for index, placement in ipairs(placements) do
		symbols[index] = { id = placement.id, position = placement.position }
	end
	return {
		session = attempt.session,
		epoch = attempt.epoch,
		layoutName = geometry.name,
		cell = geometry.cell,
		start = geometry.start,
		walls = geometry.walls,
		symbols = symbols,
		requiredCount = requiredCount,
	}
end

function MazeService:_reset(attempt)
	attempt.epoch += 1
	attempt.last = attempt.geometry.start
	table.clear(attempt.collected)
	attempt.collectedCount = 0
end

local function collectedList(attempt)
	local list = {}
	for id in pairs(attempt.collected) do table.insert(list, id) end
	return list
end

local function resetResult(attempt, reason)
	return { kind = "Reset", session = attempt.session, epoch = attempt.epoch, reason = reason }
end

--[[
	SpawnBlob(player) -> clientPayload | nil
	Drops a blob into `player`'s open maze, in an open corridor cell next to the token (the
	direction it has been moving scores highest), never on a rune or the drain. One at a time.
]]
function MazeService:SpawnBlob(player)
	local attempt = self.Attempts[player]
	if not attempt or attempt.blob then return nil end
	local geometry, metrics = attempt.geometry, attempt.metrics
	local cell = geometry.cell
	local radius = Geometry.Tuning.BlobRadius * cell
	local block = Geometry.BlobBlockRadius(metrics, radius)
	local token = attempt.last
	local tx, ty = math.floor(token.X / cell), math.floor(token.Y / cell)
	local tokenCentre = Vector2.new((tx + .5) * cell, (ty + .5) * cell)
	local heading = attempt.lastDir
	local best, bestScore
	-- 2-3 cells out, never 1: the client's token runs up to ~2 cells ahead of the server's last
	-- point, so a blob "next to" the server's token could land ON the client's (the client also
	-- cancels any blob that still lands on it, see Submit's blobCancel).
	for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
		for distance = 1, 3 do
			local centre = Vector2.new((tx + d[1] * distance + .5) * cell, (ty + d[2] * distance + .5) * cell)
			if centre.X <= 0 or centre.X >= 1 or centre.Y <= 0 or centre.Y >= 1 then break end
			if Geometry.SegmentHitsWall(tokenCentre, centre, geometry.walls, 0) then break end -- corridor ends
			local clear = distance >= 2 and (centre - token).Magnitude > block + 1.2 * cell and (centre - geometry.start).Magnitude > cell * .5
			for _, slot in ipairs(geometry.slots) do
				if (slot - centre).Magnitude < cell * .6 then clear = false break end
			end
			if clear then
				local score = -distance + (heading and Vector2.new(d[1], d[2]):Dot(heading) * 2 or 0) + self.Rng:NextNumber() * .1
				if not bestScore or score > bestScore then best, bestScore = centre, score end
				break
			end
		end
	end
	if not best then return nil end
	attempt.blob = { position = best, block = block, hp = Geometry.Tuning.BlobHits, inContact = false }
	return { session = attempt.session, position = best, radius = radius, hits = Geometry.Tuning.BlobHits }
end

--[[
	Submit(player, payload) -> result | nil
	result.kind:
		"Progress"  a new target rune was collected (payload: collected ids)
		"Reset"     the server restarted the attempt (payload: reason, new epoch)
		"Complete"  every target rune collected; the reservation is released
	nil means "nothing worth telling the client" (clean movement, stale or ignored batch).
]]
function MazeService:Submit(player, payload)
	local attempt = self.Attempts[player]
	if not attempt or type(payload) ~= "table" then return nil end
	if payload.session ~= attempt.session then return nil end -- stale session
	local epoch = tonumber(payload.epoch)
	if not epoch or epoch ~= epoch or epoch < attempt.epoch then return nil end -- old epoch still in flight
	local points = payload.points
	if type(points) ~= "table" or #points % 2 ~= 0 or #points > VALVE.MaxPointsPerBatch * 2 then return nil end

	local now = os.clock()
	if now - attempt.batchWindowStart >= 1 then
		attempt.batchWindowStart = now
		attempt.batchWindowCount = 0
	end
	attempt.batchWindowCount += 1
	if attempt.batchWindowCount > VALVE.MaxBatchesPerSecond then return nil end

	-- Client restarted locally (wall hit on its side). Follow it.
	if epoch > attempt.epoch then
		self:_reset(attempt)
		attempt.epoch = math.floor(epoch)
	end

	attempt.speedBudget = math.min(VALVE.CursorSpeedBurst, attempt.speedBudget + (now - attempt.lastBatchAt) * VALVE.MaxCursorSpeed)
	attempt.lastBatchAt = now

	local geometry, metrics = attempt.geometry, attempt.metrics
	local newlyCollected = false
	local blobChange -- set when a ram lands this batch; rides on whatever result goes back
	local function withBlob(result)
		if not blobChange then return result end
		result = result or { kind = "Blob", session = attempt.session }
		result.blob = blobChange
		return result
	end
	-- The client dropped a blob that landed on its token: take it away here too. Only honoured
	-- while the server's token is near the blob, so it can't be used to skip one.
	local pending = attempt.blob
	if payload.blobCancel == true and pending
		and (attempt.last - pending.position).Magnitude < pending.block + 2.5 * geometry.cell then
		attempt.blob = nil
		blobChange = { popped = true }
	end
	for i = 1, #points, 2 do
		local x, y = tonumber(points[i]), tonumber(points[i + 1])
		if not x or not y or x ~= x or y ~= y then return withBlob(nil) end
		local point = Vector2.new(x, y)
		local from = attempt.last

		-- The blob is solid: count rams, and never let the path through it.
		local blob = attempt.blob
		local skip = false
		if blob then
			local endDistance = (point - blob.position).Magnitude
			local passDistance = Geometry.PointSegment(blob.position, from, point)
			if endDistance <= blob.block * BLOB_CONTACT or passDistance < blob.block * BLOB_THROUGH then
				if not blob.inContact then
					blob.inContact = true
					blob.hp -= 1
					if blob.hp <= 0 then
						attempt.blob = nil
						blobChange = { popped = true }
					else
						blobChange = { hp = blob.hp }
					end
				end
				skip = passDistance < blob.block * BLOB_THROUGH -- inside / through: not a legal position
			elseif endDistance > blob.block * BLOB_RELEASE then
				blob.inContact = false
			end
		end
		if skip then continue end
		if (point - from).Magnitude > 1e-4 then attempt.lastDir = (point - from).Unit end

		attempt.speedBudget -= (point - from).Magnitude
		if attempt.speedBudget < 0 then
			attempt.speedBudget = VALVE.CursorSpeedBurst
			self:_reset(attempt)
			return withBlob(resetResult(attempt, "Slipped"))
		end
		if Geometry.SegmentHitsWall(from, point, geometry.walls, metrics.wallMargin) then
			self:_reset(attempt)
			return withBlob(resetResult(attempt, "Wall"))
		end
		local contact = Geometry.FirstSlotContact(from, point, geometry.slots, metrics.symbolRadius, function(index)
			return attempt.collected[attempt.placements[index].id] == true
		end)
		if contact then
			local id = attempt.placements[contact].id
			if not attempt.required[id] then
				self:_reset(attempt)
				return withBlob(resetResult(attempt, "WrongSymbol"))
			end
			attempt.collected[id] = true
			attempt.collectedCount += 1
			newlyCollected = true
		end
		attempt.last = point

		if attempt.collectedCount >= attempt.requiredCount then
			local minimum = Config.Gates.MinimumMazeSeconds + VALVE.MinimumSecondsPerSymbol * attempt.requiredCount
			if now - attempt.openedAt < minimum then
				self:_reset(attempt)
				return withBlob(resetResult(attempt, "TooFast"))
			end
			local gateKey = attempt.gateKey
			self:Release(player)
			return { kind = "Complete", session = attempt.session, gateKey = gateKey }
		end
	end

	if newlyCollected then
		return withBlob({ kind = "Progress", session = attempt.session, epoch = attempt.epoch, collected = collectedList(attempt) })
	end
	return withBlob(nil)
end

-- Releases `player`'s attempt and reservation. Returns the gate key it held, if any.
function MazeService:Release(player)
	local attempt = self.Attempts[player]
	if not attempt then return nil end
	self.Attempts[player] = nil
	if self.Reservations[attempt.gateKey] == player then self.Reservations[attempt.gateKey] = nil end
	return attempt.gateKey
end

-- Releases whoever holds `gateKey`. Returns that player, if any.
function MazeService:ReleaseGate(gateKey)
	local player = self.Reservations[gateKey]
	if player then self:Release(player) end
	self.Reservations[gateKey] = nil
	return player
end

function MazeService:Reset()
	table.clear(self.Reservations)
	table.clear(self.Attempts)
end

return MazeService
