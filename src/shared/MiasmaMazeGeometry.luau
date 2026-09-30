--[[
	MiasmaMazeGeometry -- maze rules shared by the server validator and the client renderer.

	Turns an ASCII layout (MiasmaMazeLayouts) into normalized geometry (0..1 on both axes,
	y pointing down), applies a rotation/reflection, and answers the collision questions
	both sides ask about a cursor moving from one sample point to the next:
		- does this segment touch a wall?
		- does this segment touch a symbol slot?

	The client and server run the SAME functions on the SAME points. The server uses a
	slightly smaller wall margin (SERVER_WALL_LENIENCY), so it never resets a line the
	client drew as clean; anything the client resets locally it reports by bumping its
	attempt epoch, which the server accepts.

	All sizes below are fractions of ONE CELL, so they scale with the grid.
]]

local Geometry = {}

Geometry.Tuning = table.freeze({
	CursorRadius = .13,       -- the traced token
	WallHalfThickness = .075, -- drawn wall half-width; collision margin = this + CursorRadius
	SymbolRadius = .3,        -- touching within this distance of a slot centre counts
	GrabRadius = .6,          -- client only: pointer this close to the token takes hold of it
	ServerWallLeniency = .8,  -- server wall margin = client margin * this
	-- The collision margin (WallHalfThickness + CursorRadius) is scaled by this; the DRAWN wall
	-- and token keep their size, so the token can brush a wall before it counts as a hit.
	-- .67 = 33% less sensitive (2026-09-29: touching an edge failed too easily).
	WallMarginScale = .67,
	-- The poison blob Miasma's lob drops into a valve operator's maze (MiasmaMazeService.SpawnBlob).
	BlobRadius = .36,     -- drawn radius; the token stops at BlobRadius + CursorRadius (blocks a corridor)
	BlobHits = 5,         -- rams to pop it (pull back, ram again)
})

-- Where the token must stop for a blob of `radius` (normalized units).
function Geometry.BlobBlockRadius(metrics, radius)
	return radius + metrics.cursorRadius
end

local function v(x, y) return Vector2.new(x, y) end

function Geometry.Parse(layout)
	local rows = layout.rows
	local size = (#rows - 1) // 2
	local start
	local cells = {}
	local slots = {}
	local walls = {}

	local function char(row, col)
		return string.sub(rows[row + 1], col + 1, col + 1)
	end

	for row = 0, size - 1 do
		for col = 0, size - 1 do
			local c = char(2 * row + 1, 2 * col + 1)
			local centre = v((col + .5) / size, (row + .5) / size)
			if c == "S" then start = centre; cells.start = { col, row } end
			if c == "o" then table.insert(slots, centre) end
		end
	end

	-- Horizontal wall runs: '-' on even rows, merged along the row.
	for row = 0, 2 * size, 2 do
		local runStart = nil
		for col = 0, size do
			local isWall = col < size and char(row, 2 * col + 1) == "-"
			if isWall and not runStart then runStart = col end
			if not isWall and runStart then
				table.insert(walls, { v(runStart / size, (row / 2) / size), v(col / size, (row / 2) / size) })
				runStart = nil
			end
		end
	end
	-- Vertical wall runs: '|' on even columns, merged down the column.
	for col = 0, 2 * size, 2 do
		local runStart = nil
		for row = 0, size do
			local isWall = row < size and char(2 * row + 1, col) == "|"
			if isWall and not runStart then runStart = row end
			if not isWall and runStart then
				table.insert(walls, { v((col / 2) / size, runStart / size), v((col / 2) / size, row / size) })
				runStart = nil
			end
		end
	end

	return {
		name = layout.name,
		size = size,
		cell = 1 / size,
		start = start,
		slots = slots,
		walls = walls,
	}
end

-- Rotation in quarter turns (clockwise on screen), reflection across the vertical axis first.
function Geometry.TransformPoint(point, rotation, mirrored)
	local x = mirrored and (1 - point.X) or point.X
	local y = point.Y
	for _ = 1, (rotation or 0) % 4 do
		x, y = 1 - y, x
	end
	return v(x, y)
end

function Geometry.Transform(parsed, rotation, mirrored)
	local walls, slots = {}, {}
	for _, wall in ipairs(parsed.walls) do
		table.insert(walls, { Geometry.TransformPoint(wall[1], rotation, mirrored), Geometry.TransformPoint(wall[2], rotation, mirrored) })
	end
	for _, slot in ipairs(parsed.slots) do
		table.insert(slots, Geometry.TransformPoint(slot, rotation, mirrored))
	end
	return {
		name = parsed.name,
		size = parsed.size,
		cell = parsed.cell,
		start = Geometry.TransformPoint(parsed.start, rotation, mirrored),
		slots = slots,
		walls = walls,
		rotation = rotation or 0,
		mirrored = mirrored == true,
	}
end

-- Tuning values converted to normalized units for one geometry.
function Geometry.Metrics(geometry, isServer)
	local cell = geometry.cell
	local tuning = Geometry.Tuning
	local wallMargin = (tuning.WallHalfThickness + tuning.CursorRadius) * tuning.WallMarginScale * cell
	if isServer then wallMargin *= tuning.ServerWallLeniency end
	return {
		wallMargin = wallMargin,
		symbolRadius = tuning.SymbolRadius * cell,
		grabRadius = tuning.GrabRadius * cell,
		cursorRadius = tuning.CursorRadius * cell,
		wallHalfThickness = tuning.WallHalfThickness * cell,
	}
end

local function dot(a, b) return a.X * b.X + a.Y * b.Y end

-- Distance from point p to segment ab, plus the 0..1 parameter of the closest point.
function Geometry.PointSegment(p, a, b)
	local ab = b - a
	local lengthSq = dot(ab, ab)
	if lengthSq < 1e-12 then return (p - a).Magnitude, 0 end
	local t = math.clamp(dot(p - a, ab) / lengthSq, 0, 1)
	return (p - (a + ab * t)).Magnitude, t
end

local function cross(a, b) return a.X * b.Y - a.Y * b.X end

local function segmentsCross(a, b, c, d)
	local r, s = b - a, d - c
	local denom = cross(r, s)
	if math.abs(denom) < 1e-12 then return false end
	local t = cross(c - a, s) / denom
	local u = cross(c - a, r) / denom
	return t >= 0 and t <= 1 and u >= 0 and u <= 1
end

function Geometry.SegmentDistance(a, b, c, d)
	if segmentsCross(a, b, c, d) then return 0 end
	return math.min(
		(Geometry.PointSegment(a, c, d)),
		(Geometry.PointSegment(b, c, d)),
		(Geometry.PointSegment(c, a, b)),
		(Geometry.PointSegment(d, a, b))
	)
end

-- True when a cursor moving from `from` to `to` comes within `margin` of any wall, or
-- leaves the board.
function Geometry.SegmentHitsWall(from, to, walls, margin)
	if to.X < 0 or to.X > 1 or to.Y < 0 or to.Y > 1 then return true end
	for _, wall in ipairs(walls) do
		if Geometry.SegmentDistance(from, to, wall[1], wall[2]) < margin then return true end
	end
	return false
end

-- Index of the first slot (along the direction of travel) touched by the segment, skipping
-- slots for which skip(index) returns true. Returns nil when none is touched.
function Geometry.FirstSlotContact(from, to, slots, radius, skip)
	local bestIndex, bestT = nil, math.huge
	for index, slot in ipairs(slots) do
		if not (skip and skip(index)) then
			local distance, t = Geometry.PointSegment(slot, from, to)
			if distance <= radius and t < bestT then
				bestIndex, bestT = index, t
			end
		end
	end
	return bestIndex
end

--[[
	Validate(parsed) -> ok, message
	Structural check of an authored layout, independent of rendering: one start, eight
	slots, and every slot reachable without passing through any other slot.
]]
function Geometry.Validate(layout)
	local rows = layout.rows
	if type(rows) ~= "table" or #rows < 3 then return false, "missing rows" end
	local width = #rows[1]
	for i, row in ipairs(rows) do
		if #row ~= width then return false, ("row %d has width %d, expected %d"):format(i, #row, width) end
	end
	if #rows ~= width then return false, "layout is not square" end
	local size = (#rows - 1) // 2
	local function char(row, col) return string.sub(rows[row + 1], col + 1, col + 1) end

	local starts, symbolCells = {}, {}
	for row = 0, size - 1 do
		for col = 0, size - 1 do
			local c = char(2 * row + 1, 2 * col + 1)
			if c == "S" then table.insert(starts, { col, row }) end
			if c == "o" then symbolCells[col .. "," .. row] = true end
		end
	end
	local symbolCount = 0
	for _ in pairs(symbolCells) do symbolCount += 1 end
	if #starts ~= 1 then return false, "expected exactly one start" end
	if symbolCount ~= 8 then return false, "expected eight symbol slots, found " .. symbolCount end
	for i = 0, 2 * size do
		if char(0, i) == " " or char(2 * size, i) == " " or char(i, 0) == " " or char(i, 2 * size) == " " then
			if i % 2 == 1 then return false, "outer border has a gap" end
		end
	end

	local function neighbours(col, row)
		local list = {}
		if col > 0 and char(2 * row + 1, 2 * col) == " " then table.insert(list, { col - 1, row }) end
		if col < size - 1 and char(2 * row + 1, 2 * col + 2) == " " then table.insert(list, { col + 1, row }) end
		if row > 0 and char(2 * row, 2 * col + 1) == " " then table.insert(list, { col, row - 1 }) end
		if row < size - 1 and char(2 * row + 2, 2 * col + 1) == " " then table.insert(list, { col, row + 1 }) end
		return list
	end

	local start = starts[1]
	local reached = { [start[1] .. "," .. start[2]] = true }
	local queue = { start }
	local head = 1
	while head <= #queue do
		local cell = queue[head]; head += 1
		for _, n in ipairs(neighbours(cell[1], cell[2])) do
			local key = n[1] .. "," .. n[2]
			if not reached[key] and not symbolCells[key] then
				reached[key] = true
				table.insert(queue, n)
			end
		end
	end
	for row = 0, size - 1 do
		for col = 0, size - 1 do
			local key = col .. "," .. row
			if symbolCells[key] then
				local open = false
				for _, n in ipairs(neighbours(col, row)) do
					if reached[n[1] .. "," .. n[2]] then open = true end
				end
				if not open then return false, "symbol at " .. key .. " is not reachable without crossing another symbol" end
			elseif not reached[key] then
				return false, "cell " .. key .. " is cut off from the start"
			end
		end
	end
	return true, "ok"
end

return table.freeze(Geometry)
