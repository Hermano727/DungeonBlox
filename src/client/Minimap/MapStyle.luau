--[[
	MapStyle -- turns the server's raw per-cell map colours into a stylized, hand-painted look
	(flat colour bands, warm parchment grade, ink-lined shores and cliffs, soft fog edges)
	instead of a hard pixel grid. Pure client-side post-processing: the server raycasts and the
	saved exploration data are untouched.

		MapStyle.Stylize(colours, n)         -> styled     once per chunk, when its colours arrive
		MapStyle.Compose(styled, shown, out, n)            every re-render: applies fog + reveal

	colours / styled : buffer, 3 bytes (r, g, b) per cell, n x n cells, row-major
	shown            : buffer, 1 byte per cell (1 = explored / revealed, 0 = fog)
	out              : buffer, 4 bytes (r, g, b, a) per cell, ready for WritePixelsBuffer

	The tiles are drawn with bilinear sampling (MapView), which is what turns these cells into
	soft painted shapes instead of squares. Tuning: the constants below.
]]

local MapStyle = {}

MapStyle.FOG = Color3.fromRGB(22, 18, 14) -- what unexplored ground looks like; also the clip colour

local BANDS = 7            -- brightness levels the ground is flattened into
local BAND_STRENGTH = 0.6  -- 0 = keep the raw shading, 1 = fully flat bands
local SATURATION = 0.92
local WARM = { 1.04, 1.0, 0.93 } -- r, g, b multipliers: the parchment grade
local LIFT = 12            -- added to every channel, so shadows are brown rather than black
local SHORE_INK = 0.5      -- land next to water darkens to this fraction (the coast line)
local CLIFF_INK = 0.68     -- the brink of a steep drop
local GRAIN = 2            -- +/- brightness of the painted-paper grain

local FOG_R, FOG_G, FOG_B = 22, 18, 14
local NEIGHBOURS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

local function clamp255(v)
	if v < 0 then return 0 elseif v > 255 then return 255 end
	return v
end

-- Blueish ground reads as water (terrain water, the Water material, lakes), which is what the
-- shoreline ink keys off.
local function isWater(r, g, b)
	return b > r + 14 and b >= g - 6
end

function MapStyle.Stylize(colours, n)
	local count = n * n
	local r, g, b, water = table.create(count), table.create(count), table.create(count), table.create(count)
	for i = 0, count - 1 do
		local at = i * 3
		local cr, cg, cb = buffer.readu8(colours, at), buffer.readu8(colours, at + 1), buffer.readu8(colours, at + 2)
		r[i + 1], g[i + 1], b[i + 1] = cr, cg, cb
		water[i + 1] = isWater(cr, cg, cb)
	end

	-- 1) Soften: a 3x3 weighted blur that never mixes water with land, so coasts stay crisp.
	local band = table.create(count)
	local gr, gg, gb = table.create(count), table.create(count), table.create(count)
	for y = 0, n - 1 do
		for x = 0, n - 1 do
			local i = y * n + x + 1
			local mine = water[i]
			local sr, sg, sb, sw = 0, 0, 0, 0
			for dy = -1, 1 do
				local yy = y + dy
				if yy >= 0 and yy < n then
					for dx = -1, 1 do
						local xx = x + dx
						if xx >= 0 and xx < n then
							local j = yy * n + xx + 1
							if water[j] == mine then
								local w = (dx == 0 and dy == 0) and 4 or ((dx == 0 or dy == 0) and 2 or 1)
								sr += r[j] * w; sg += g[j] * w; sb += b[j] * w; sw += w
							end
						end
					end
				end
			end
			local cr, cg, cb = sr / sw, sg / sw, sb / sw

			-- 2) Grade: flatten brightness into bands (keeping hue), desaturate a touch, warm it.
			local l = (0.299 * cr + 0.587 * cg + 0.114 * cb) / 255
			local q = math.floor(l * BANDS + 0.5) / BANDS
			local k = l > 0.001 and (l + (q - l) * BAND_STRENGTH) / l or 1
			cr, cg, cb = cr * k, cg * k, cb * k
			local gray = 0.299 * cr + 0.587 * cg + 0.114 * cb
			cr = gray + (cr - gray) * SATURATION
			cg = gray + (cg - gray) * SATURATION
			cb = gray + (cb - gray) * SATURATION
			local grain = (bit32.bxor(x * 73856093, y * 19349663) % (GRAIN * 2 + 1)) - GRAIN
			gr[i] = clamp255(cr * WARM[1] + LIFT + grain)
			gg[i] = clamp255(cg * WARM[2] + LIFT + grain)
			gb[i] = clamp255(cb * WARM[3] + LIFT + grain)
			band[i] = math.floor(l * BANDS + 0.5)
		end
	end

	-- 3) Ink: land that touches water gets a dark coast line; the high side of a steep step
	-- gets a lighter cliff line.
	local styled = buffer.create(count * 3)
	for y = 0, n - 1 do
		for x = 0, n - 1 do
			local i = y * n + x + 1
			local ink = 1
			local mineWater = water[i]
			for _, d in ipairs(NEIGHBOURS) do
				local xx, yy = x + d[1], y + d[2]
				if xx >= 0 and xx < n and yy >= 0 and yy < n then
					local j = yy * n + xx + 1
					if water[j] ~= mineWater then
						if not mineWater then ink = math.min(ink, SHORE_INK) end
					elseif not mineWater and band[i] - band[j] >= 2 then
						ink = math.min(ink, CLIFF_INK)
					end
				end
			end
			local at = (i - 1) * 3
			buffer.writeu8(styled, at, math.floor(gr[i] * ink + 0.5))
			buffer.writeu8(styled, at + 1, math.floor(gg[i] * ink + 0.5))
			buffer.writeu8(styled, at + 2, math.floor(gb[i] * ink + 0.5))
		end
	end
	return styled
end

-- Applies the reveal mask. Explored cells next to unexplored ones fade into the fog, so the edge
-- of what you have seen is a soft cloud instead of a hard staircase. Neighbours outside the chunk
-- count as explored, so chunk borders never grow a fog line.
function MapStyle.Compose(styled, shown, out, n)
	for y = 0, n - 1 do
		for x = 0, n - 1 do
			local i = y * n + x
			local dst = i * 4
			if buffer.readu8(shown, i) == 1 then
				local around = 0
				for dy = -1, 1 do
					local yy = y + dy
					for dx = -1, 1 do
						if dx ~= 0 or dy ~= 0 then
							local xx = x + dx
							if xx < 0 or xx >= n or yy < 0 or yy >= n or buffer.readu8(shown, yy * n + xx) == 1 then
								around += 1
							end
						end
					end
				end
				local at = i * 3
				local r, g, b = buffer.readu8(styled, at), buffer.readu8(styled, at + 1), buffer.readu8(styled, at + 2)
				if around < 8 then
					local f = around / 8
					local k = 0.6 + 0.4 * f
					r, g, b = math.floor(r * k), math.floor(g * k), math.floor(b * k)
					buffer.writeu8(out, dst + 3, math.floor(120 + 135 * f))
				else
					buffer.writeu8(out, dst + 3, 255)
				end
				buffer.writeu8(out, dst, r)
				buffer.writeu8(out, dst + 1, g)
				buffer.writeu8(out, dst + 2, b)
			else
				-- Fog colour at zero alpha, so bilinear sampling fades into fog, not into black.
				buffer.writeu8(out, dst, FOG_R)
				buffer.writeu8(out, dst + 1, FOG_G)
				buffer.writeu8(out, dst + 2, FOG_B)
				buffer.writeu8(out, dst + 3, 0)
			end
		end
	end
end

return MapStyle
