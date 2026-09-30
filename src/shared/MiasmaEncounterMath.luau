local Math = {}

function Math.ClampPartySize(size, maximum)
	return math.clamp(math.floor(tonumber(size) or 1), 1, maximum or 8)
end

function Math.ActiveGateCount(size)
	return math.min(Math.ClampPartySize(size), 4)
end

function Math.SlimeWaveSize(size)
	return math.ceil(Math.ClampPartySize(size) / 2)
end

function Math.SlimeLivingCap(size)
	return math.min(3 * Math.ClampPartySize(size), 16)
end

function Math.SlimeWaveInterval(elapsed, duration, startInterval, endInterval)
	local alpha = math.clamp((tonumber(elapsed) or 0) / math.max(0.001, tonumber(duration) or 60), 0, 1)
	return (tonumber(startInterval) or 12) + ((tonumber(endInterval) or 6) - (tonumber(startInterval) or 12)) * alpha
end

function Math.AltarCooldown(size, baseCooldown)
	return (tonumber(baseCooldown) or 120) / Math.ClampPartySize(size)
end

function Math.PuddleCount(size)
	return math.min(4 + Math.ClampPartySize(size), 12)
end

function Math.SackCount(size)
	return math.min(math.ceil(Math.ClampPartySize(size) / 2) + 1, 5)
end

function Math.PoisonTick(maxHealth, stacks, fraction, cap)
	local damage = math.max(0, tonumber(maxHealth) or 0)
		* math.max(0, math.floor(tonumber(stacks) or 0))
		* (tonumber(fraction) or 0.01)
	return math.min(damage, tonumber(cap) or 50)
end

function Math.PointInCircle(point, center, radius)
	local dx = point.X - center.X
	local dy = point.Y - center.Y
	return dx * dx + dy * dy <= radius * radius
end

local function orientation(a, b, c)
	return (b.X - a.X) * (c.Y - a.Y) - (b.Y - a.Y) * (c.X - a.X)
end

function Math.SegmentsIntersect(a, b, c, d)
	local abC, abD = orientation(a, b, c), orientation(a, b, d)
	local cdA, cdB = orientation(c, d, a), orientation(c, d, b)
	return ((abC > 0 and abD < 0) or (abC < 0 and abD > 0))
		and ((cdA > 0 and cdB < 0) or (cdA < 0 and cdB > 0))
end

function Math.SegmentCrossesWalls(fromPoint, toPoint, walls)
	for _, wall in ipairs(walls or {}) do
		if Math.SegmentsIntersect(fromPoint, toPoint, wall[1], wall[2]) then
			return true
		end
	end
	return false
end

function Math.TransformPoint(point, rotation, mirrored)
	local x = mirrored and (1 - point.X) or point.X
	local y = point.Y
	for _ = 1, (rotation or 0) % 4 do
		x, y = 1 - y, x
	end
	return Vector2.new(x, y)
end

function Math.EncodeGateSet(indices)
	local copy = table.clone(indices or {})
	table.sort(copy)
	for i, value in ipairs(copy) do copy[i] = tostring(value) end
	return table.concat(copy, ",")
end

return table.freeze(Math)
