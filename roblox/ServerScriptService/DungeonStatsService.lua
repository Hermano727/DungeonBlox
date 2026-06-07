--[[
  Computes derived stats from base profile.stats + equipped item subStats.
  SubStat ids (additive):
    MaxHp, ArmorRating, HPRegen, EnergyRegen, MiningLevel, FishingLevel
]]

local DungeonStatsService = {}

local function sumEquipped(profile, key)
	local total = 0
	for _, uuid in pairs(profile.equipped) do
		if type(uuid) == "string" then
			local item = profile.inventory[uuid]
			if item and item.subStats then
				local v = item.subStats[key]
				if type(v) == "number" then
					total = total + v
				end
			end
		end
	end
	return total
end

function DungeonStatsService.RecomputeRuntimeHp(profile)
	local snap = DungeonStatsService.BuildSnapshot(profile)
	local maxHp = snap.combat.maxHp
	if profile.runtime.currentHp > maxHp then
		profile.runtime.currentHp = maxHp
	end
	if profile.runtime.currentHp < 0 then
		profile.runtime.currentHp = 0
	end
end

function DungeonStatsService.BuildSnapshot(profile)
	local c = profile.stats.combat
	local m = profile.stats.mining
	local f = profile.stats.fishing

	local addHp      = sumEquipped(profile, "hp")
	local addArmor   = sumEquipped(profile, "armor")
	local addHps     = sumEquipped(profile, "hps")
	local addEnergy  = sumEquipped(profile, "energy")
	local addMining  = sumEquipped(profile, "MiningLevel")
	local addFishing = sumEquipped(profile, "FishingLevel")

	local maxHp       = math.max(1, c.maxHp + addHp)
	local armor       = math.max(0, addArmor)
	local hpRegen     = math.max(0, c.hpRegen + addHps)
	local energyRegen = math.max(0, c.energyRegen + addEnergy)
	local miningLevel = math.max(1, math.floor(m.miningLevel + addMining))
	local fishingLevel = math.max(1, math.floor(f.fishingLevel + addFishing))

	local hp = profile.runtime.currentHp
	if hp > maxHp then
		hp = maxHp
	end

	return {
		combat = {
			hp = hp,
			maxHp = maxHp,
			armor = armor,
			hpRegen = hpRegen,
			energyRegen = energyRegen,
		},
		mining = { miningLevel = miningLevel },
		fishing = { fishingLevel = fishingLevel },
	}
end

return DungeonStatsService
