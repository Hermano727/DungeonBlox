local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("ArmorEnchantConfig"))
local ArmorEnchants = {}

-- Separate instances permit deterministic offline checks without global state.
function ArmorEnchants.new(clock, randomRoll)
	local now = clock or os.clock
	local rng = Random.new()
	local roll = randomRoll or function() return rng:NextNumber() end
	local shatteredUntil = setmetatable({}, { __mode = "k" })
	local service = {}

	-- Invoke only after invulnerability/block/positive-damage gates. The same
	-- target key shares Shatter across attackers; character keys reset on respawn.
	function service.Resolve(target, armorRating, subStats)
		local armor = math.max(0, tonumber(armorRating) or 0)
		local subs = subStats or {}
		local time = now()
		local expiry = target and shatteredUntil[target]
		if expiry and expiry <= time then shatteredUntil[target] = nil; expiry = nil end
		local function procs(key)
			local chance = math.clamp(tonumber(subs[key]) or 0, 0, 100) / 100
			return chance > 0 and roll() < chance
		end
		local shatter = target ~= nil and armor > 0 and procs("shatter")
		local crushing = armor > 0 and procs("crushing")
		if shatter then
			expiry = time + Config.ShatterDuration
			shatteredUntil[target] = expiry
		end
		-- Always derive from base armor: repeated Shatter refreshes time only.
		if expiry then armor *= 1 - Config.ShatterArmorReduction end
		if crushing then armor *= 1 - Config.CrushingArmorIgnore end
		return armor, { isShatter = shatter, isCrushing = crushing }
	end

	return service
end

return ArmorEnchants.new()
