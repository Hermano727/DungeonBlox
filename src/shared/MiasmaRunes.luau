--[[
	MiasmaRunes -- rune IDENTITY for the Miasma valve puzzle.

	The eight ids here are what the server rolls as a gate's target pattern, what the maze
	places on its symbol slots, and what the tablet and the maze UI both render. They are
	the only thing gameplay code compares.

	What a rune LOOKS like lives in MiasmaRuneArt, keyed by these same ids, so the MVP
	stroke art can be swapped for uploaded images without touching any rule. Display names
	are for debugging and docs only: the puzzle never shows a rune's name to players (the
	whole point is reading shapes from memory).
]]

local Runes = {}

-- Fixed order. Server rolls and client renders are keyed by id, never by index, so this
-- order only matters for dev tooling and tests.
Runes.Order = table.freeze({ "Eye", "Fang", "Crown", "Tide", "Moon", "Coil", "Ward", "Anchor" })

Runes.Names = table.freeze({
	Eye = "Eye",
	Fang = "Fang",
	Crown = "Crown",
	Tide = "Tide",
	Moon = "Moon",
	Coil = "Coil",
	Ward = "Ward",
	Anchor = "Anchor",
})

local valid = {}
for _, id in ipairs(Runes.Order) do valid[id] = true end

function Runes.IsValid(id)
	return type(id) == "string" and valid[id] == true
end

-- Returns `count` distinct rune ids in random order.
function Runes.Pick(count, rng)
	local pool = table.clone(Runes.Order)
	for i = #pool, 2, -1 do
		local j = rng and rng:NextInteger(1, i) or math.random(i)
		pool[i], pool[j] = pool[j], pool[i]
	end
	local picked = {}
	for i = 1, math.clamp(count, 0, #pool) do picked[i] = pool[i] end
	return picked
end

function Runes.Shuffled(rng)
	return Runes.Pick(#Runes.Order, rng)
end

return table.freeze(Runes)
