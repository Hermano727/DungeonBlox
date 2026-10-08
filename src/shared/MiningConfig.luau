--[[
	MiningConfig
	The mining loop (2026-10-03): three phases at a rock, played in the world.

	  1. Strike the seam. A ring closes on a glowing seam; strike as it meets the seam.
	     Perfect: +1 coal. Good: clean start. Miss: the ore starts with a crack.
	  2. Fracture strikes. Fault points glow around the ore. Hold on one to charge,
	     release to strike. Inside its band the fault breaks and frees more ore; under it
	     nothing happens; over it the fault breaks AND the ore cracks. MAX_CRACKS shatters it.
	     Pry it out at any time (right click) for the chunk freed so far.
	  3. Collection. The chunk drops at your feet (MiningRewardHandler's nonce pickups),
	     sized by how much you freed and how cracked it is.

	Everything both sides need to agree on lives here: the server (MiningRewardHandler)
	judges every report with these same functions from the session seed, and the client
	(MiningClient) uses them to show the layout and predict results.

	The old 6x8 dig grid is not part of this loop. It's kept for the future pickaxe
	"Treasure Find" proc (src/client/Professions/TreasurePocket notes).
]]

local MiningConfig = {}

MiningConfig.SESSION_RANGE = 16 -- studs from the rock; walking further ends the session
MiningConfig.START_RANGE = 20 -- studs, to start on a rock (matches the old MINE_RANGE)

-- Phase 1: the seam ring. Its scale shrinks from 1 to 0 over RING_TIME; the seam sits at
-- SEAM_SCALE. Accuracy = |ring scale at the strike - SEAM_SCALE|.
MiningConfig.SEAM = {
	RING_TIME = 1.15,
	SEAM_SCALE = 0.3,
	PERFECT = 0.045,
	GOOD = 0.13,
}

-- Phase 2: fault points around the ore.
MiningConfig.FAULTS = {
	COUNT_MIN = 4,
	COUNT_MAX = 6,
	BAND_CENTER_MIN = 0.38, -- power (0..1) at the middle of a fault's band
	BAND_CENTER_MAX = 0.8,
	BAND_WIDTH_MIN = 0.16,
	BAND_WIDTH_MAX = 0.28,
}
MiningConfig.CHARGE_TIME = 1.0 -- seconds of holding to reach full power
MiningConfig.MIN_HOLD = 0.06 -- a tap shorter than this is ignored
MiningConfig.MAX_CRACKS = 3
MiningConfig.TIME_LIMIT = 15 -- seconds of phase 2 before it pries itself out

-- Yield (coal) from the share of faults broken, minus 1 for a badly cracked ore.
-- Never zero: a shattered ore still leaves shards worth 1.
MiningConfig.SEAM_PERFECT_BONUS = 1
MiningConfig.XP_PER_COAL = 5
MiningConfig.GRADE_XP_BONUS = { Pristine = 12, Clean = 6, Rough = 0, Shattered = 0 }
MiningConfig.GRADE_COLORS = {
	Pristine = Color3.fromRGB(150, 220, 255),
	Clean = Color3.fromRGB(150, 230, 140),
	Rough = Color3.fromRGB(230, 200, 120),
	Shattered = Color3.fromRGB(230, 110, 90),
}

---------------------------------------------------------------------------
-- Deterministic simulation (server and client run exactly this)
---------------------------------------------------------------------------

-- The fault points for a session seed. Angles are around the ore on the rock face
-- (0 = right, pi/2 = up); radius is a share of the ore's display radius (client only).
function MiningConfig.Layout(seed: number)
	local rng = Random.new(seed)
	local f = MiningConfig.FAULTS
	local count = rng:NextInteger(f.COUNT_MIN, f.COUNT_MAX)
	local faults = {}
	local start = rng:NextNumber(0, math.pi * 2)
	for i = 1, count do
		local center = rng:NextNumber(f.BAND_CENTER_MIN, f.BAND_CENTER_MAX)
		local width = rng:NextNumber(f.BAND_WIDTH_MIN, f.BAND_WIDTH_MAX)
		faults[i] = {
			angle = start + (i - 1) * (math.pi * 2 / count) + rng:NextNumber(-0.25, 0.25),
			radius = rng:NextNumber(1.25, 1.6),
			lo = math.max(0.05, center - width / 2),
			hi = math.min(0.98, center + width / 2),
		}
	end
	return { faults = faults }
end

-- "perfect" | "good" | "miss"
function MiningConfig.JudgeSeam(accuracy: number)
	accuracy = math.abs(tonumber(accuracy) or 1)
	if accuracy <= MiningConfig.SEAM.PERFECT then
		return "perfect"
	elseif accuracy <= MiningConfig.SEAM.GOOD then
		return "good"
	end
	return "miss"
end

function MiningConfig.PowerFromHold(hold: number)
	return math.clamp((tonumber(hold) or 0) / MiningConfig.CHARGE_TIME, 0, 1)
end

-- "weak" (nothing) | "break" (fault breaks) | "crack" (fault breaks, ore cracks)
function MiningConfig.JudgeStrike(fault, power: number)
	if power < fault.lo then
		return "weak"
	elseif power <= fault.hi then
		return "break"
	end
	return "crack"
end

-- The extraction's grade, coal and XP from its state.
-- state: { broken = count, total = count, cracks = count, seam = "perfect"|"good"|"miss" }
function MiningConfig.Outcome(state)
	local share = state.total > 0 and state.broken / state.total or 0
	local grade
	if state.cracks >= MiningConfig.MAX_CRACKS then
		grade = "Shattered"
	elseif state.cracks == 0 and share >= 1 then
		grade = "Pristine"
	elseif state.cracks <= 1 and share >= 0.66 then
		grade = "Clean"
	else
		grade = "Rough"
	end
	local coal
	if grade == "Shattered" then
		coal = 1
	else
		local size = share >= 1 and 4 or share >= 0.66 and 3 or share >= 0.33 and 2 or 1
		coal = math.max(1, size - (state.cracks >= 2 and 1 or 0))
		if state.seam == "perfect" then
			coal += MiningConfig.SEAM_PERFECT_BONUS
		end
	end
	local xp = coal * MiningConfig.XP_PER_COAL + (MiningConfig.GRADE_XP_BONUS[grade] or 0)
	return { grade = grade, coal = coal, xp = xp, share = share }
end

return MiningConfig
