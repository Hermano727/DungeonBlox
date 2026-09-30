--[[
	DungeonLevels -- ReplicatedStorage

	The ONE place a dungeon run's mob level is decided. Everything spawned
	inside a run -- the boss, trash, encounter adds -- takes its level from
	Resolve(), so nothing inside a run carries a hand-typed level of its own.

	The rule: a run's BASE level is its tier's level cap minus BASE_BELOW_CAP.
	T1 caps at 21, so a T1 run is level 15.

	MODIFIERS are the extension point, and nothing uses them yet. A run holds a
	list of modifier tables, built when the run launches (see
	DungeonInstanceService.launchDungeon). Each can shift the level:

		{ Id = "Hardened", LevelDelta = 4 }        -- +4 on top of whatever came before
		{ Id = "Ascended", LevelOverride = 30 }    -- replace the level outright

	Overrides apply first (the last one wins), then every delta is added. So
	"Ascended + Hardened" is 30 + 4 = 34. The level is floored at 1 but NOT capped
	at the tier's level cap: a hard-mode modifier pushing a T1 run past 21 is the
	point of having one.

	Adding a real modifier later means: define its table, and put it in the run's
	modifier list at launch. Nothing that spawns mobs needs to change, because all
	of it already reads the resolved level.
]]

local DungeonLevels = {}

-- Level cap per tier, indexed by numeric tier. Tiers START at 1/21/41/61/81,
-- and a tier's cap is the level the next tier starts at.
-- T5 has no next tier; 100 is an assumption, revisit when T5 ships.
DungeonLevels.TIER_LEVEL_CAP = { 21, 41, 61, 81, 100 }

-- How far below the tier cap a run's base level sits.
DungeonLevels.BASE_BELOW_CAP = 6

local MIN_LEVEL = 1

function DungeonLevels.Cap(numericTier)
	local tier = math.clamp(math.floor(tonumber(numericTier) or 1), 1, #DungeonLevels.TIER_LEVEL_CAP)
	return DungeonLevels.TIER_LEVEL_CAP[tier]
end

-- Base level before modifiers. T1 -> 15.
function DungeonLevels.BaseLevel(numericTier)
	return math.max(MIN_LEVEL, DungeonLevels.Cap(numericTier) - DungeonLevels.BASE_BELOW_CAP)
end

--[[
	Resolve(numericTier, modifiers) -> level, breakdown

	`modifiers` is optional; an absent or empty list gives the base level.
	`breakdown` lists every step, for a future UI line like "Lv 19 (15 base,
	+4 Hardened)" or for debugging a modifier stack.
]]
function DungeonLevels.Resolve(numericTier, modifiers)
	local level = DungeonLevels.BaseLevel(numericTier)
	local breakdown = { { source = "base", level = level } }

	if type(modifiers) == "table" then
		for _, mod in ipairs(modifiers) do
			local override = type(mod) == "table" and tonumber(mod.LevelOverride)
			if override then
				level = override
				table.insert(breakdown, { source = mod.Id or "override", set = override })
			end
		end
		for _, mod in ipairs(modifiers) do
			local delta = type(mod) == "table" and tonumber(mod.LevelDelta)
			if delta then
				level += delta
				table.insert(breakdown, { source = mod.Id or "delta", delta = delta })
			end
		end
	end

	level = math.max(MIN_LEVEL, math.floor(level))
	return level, breakdown
end

-- The { minLevel, maxLevel } range MobSpawner takes, pinned to one level.
function DungeonLevels.SpawnRange(level)
	return { minLevel = level, maxLevel = level }
end

return DungeonLevels
