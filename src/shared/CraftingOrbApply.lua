--[[
	CraftingOrbApply
	Authoritative rules for ApplyCraftingOrb.

	Wisdom Orb: increments item.level by 1 (cap = tier*20) and rescales
	  dmgMin/dmgMax (weapons) or hp/hps (armor).

	Alteration Orb (Weapon):
	  50/50 win/lose -> count from WIN_SUBSTAT_DIST (win) or LOSE_SUBSTAT_RANGE (lose).
	  75% chance elemental is guaranteed as first slot.
	  Remaining slots weighted by baseWeight x type-override.

	Alteration Orb (Armor):
	  50/50 win/lose -> count: win = WIN_SUBSTAT_DIST, lose = 1 (all tiers).
	  Max 2 VIT/STR/DEX/INT total per item.
	  Slots 1-2: each is 50/50 stat-pool vs bonus-pool.
	  Slots 3+: completely random from all remaining substats (respecting cap).
	  Base stats (dmgMin/dmgMax/hp/etc.) are never touched.

	Chaos / Nullification / Transmutation / Reforging / Divinity: defined as items but have
	NO effect yet. ApplyFromAct refuses them ("orb_not_implemented") BEFORE consuming, so an
	orb is never eaten for nothing. Add a kind to IMPLEMENTED once its rules exist.

	Public (pure, usable client-side for previews):
	  CraftingOrbApply.IsImplemented(orbKind)          -> bool
	  CraftingOrbApply.PreviewWisdom(item)             -> newLevel, previewSubStats | nil, reason
	  CraftingOrbApply.WISDOM_LEVEL_CAP_PER_TIER       (cap = tier * this)
]]

local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ItemConfig         = require(ReplicatedStorage:WaitForChild("ItemConfig"))
local ItemDefinitions    = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local EnchantScrollApply = require(ReplicatedStorage:WaitForChild("EnchantScrollApply"))

local TIER_MEDIANS       = { 10, 30, 50, 70, 90 }
local WEAPON_MULTIPLIERS = ItemConfig.WEAPON_MULTIPLIERS

-- Win 50/50: count distribution per tier { {count, weight}, ... }
-- Shared between weapons and armor.
local WIN_SUBSTAT_DIST = {
	[1] = {{1,40},{2,40},{3,20}},
	[2] = {{2,50},{3,50}},
	[3] = {{2,30},{3,44},{4,26}},
	[4] = {{3,40},{4,44},{5,16}},
	[5] = {{4,64},{5,30},{6,6}},
}
-- Weapon lose range
local LOSE_SUBSTAT_RANGE  = { {1,1},{1,1},{1,2},{1,3},{2,3} }
local ELEMENTAL_CHANCE    = 0.75
local WEAPON_BASE_KEYS    = {dmgMin=true,dmgMax=true,_rawDmgMin=true,_rawDmgMax=true}
local ARMOR_BASE_KEYS     = {hp=true,hps=true,armor=true,energy=true,_rawHp=true,dmgRed=true}
local ARMOR_MAX_STAT_SUBS = 2   -- max VIT/STR/DEX/INT per item via orb
local WISDOM_LEVEL_CAP_PER_TIER = 20

-- Orb kinds that actually do something. Every other OrbKind is refused before consuming.
local IMPLEMENTED = { Wisdom = true, Alteration = true }

local rescaleForLevel -- defined below the Alteration helpers

-- Quick lookup: is an armor substat id one of the weapon-damage stats?
local ARMOR_STAT_IDS = {}
for _, eff in ipairs(ItemConfig.ARMOR_EFFECTS) do
	ARMOR_STAT_IDS[eff.id] = true
end

------------------------------------------------------------------------
-- Shared helpers
------------------------------------------------------------------------

local function bumpSnapSeq(profile)
	local n = math.floor(tonumber(profile.__snapSeq) or 0) + 1
	profile.__snapSeq = n
	return n
end

local function resolveInBag(profile, uuid)
	if type(profile) ~= "table" or type(uuid) ~= "string" or uuid == "" then return nil end
	local inv = profile.inventory
	if type(inv) ~= "table" then return nil end
	local it = inv[uuid]
	return type(it) == "table" and it or nil
end

local function consumeOneFromBag(profile, uuid)
	local inv = profile.inventory
	if type(inv) ~= "table" then return false end
	local it = inv[uuid]
	if type(it) ~= "table" then return false end
	local c = math.floor(tonumber(it.count) or 1)
	if c > 1 then it.count = c - 1 else inv[uuid] = nil end
	return true
end

------------------------------------------------------------------------
-- Alteration helpers
------------------------------------------------------------------------

local function rollWeighted(dist)
	local total = 0
	for _, e in ipairs(dist) do total = total + e[2] end
	local r = math.random() * total
	local cum = 0
	for _, e in ipairs(dist) do
		cum = cum + e[2]
		if r <= cum then return e[1] end
	end
	return dist[#dist][1]
end

local function pickWeightedEffect(available, typeOverrides)
	local total = 0
	for _, eff in ipairs(available) do
		total = total + eff.baseWeight * (typeOverrides[eff.id] or 1)
	end
	local r = math.random() * total
	local cum = 0
	for _, eff in ipairs(available) do
		cum = cum + eff.baseWeight * (typeOverrides[eff.id] or 1)
		if r <= cum then return eff end
	end
	return available[#available]
end

-- Weapon alteration: unchanged from before.
local function rollWeaponAlterationSubstats(targetItem, tier, count)
	local rarityMult = ItemConfig.RARITY_SUBSTAT_MULT[targetItem.rarity] or 1.0
	local weaponType, weaponMult, isMelee = nil, 1.0, true
	if type(targetItem.tags) == "table" then
		for _, tag in ipairs(targetItem.tags) do
			if WEAPON_MULTIPLIERS[tag] then
				weaponType = tag
				weaponMult = WEAPON_MULTIPLIERS[tag]
				isMelee    = tag ~= "Bow"
				break
			end
		end
	end
	local pool         = ItemConfig.WEAPON_EFFECTS
	local typeOverrides = (weaponType and ItemConfig.WEAPON_TYPE_WEIGHTS[weaponType]) or {}
	local usedIds, results, remaining = {}, {}, count

	-- 75% guaranteed elemental slot
	if math.random() < ELEMENTAL_CHANCE then
		for _, eff in ipairs(pool) do
			if eff.id == "elemDmg" then
				usedIds.elemDmg = true
				local range = eff.ranges[tier]
				local val = math.floor(math.random(range[1], range[2]) * rarityMult * weaponMult)
				table.insert(results, {id="elemDmg", value=val})
				remaining = remaining - 1
				break
			end
		end
	end

	for _ = 1, remaining do
		local available = {}
		for _, eff in ipairs(pool) do
			if not usedIds[eff.id]
				and not (eff.meleeOnly  and not isMelee)
				and not (eff.rangedOnly and isMelee) then
				table.insert(available, eff)
			end
		end
		if #available == 0 then break end
		local picked = pickWeightedEffect(available, typeOverrides)
		usedIds[picked.id] = true
		local range = picked.ranges[tier]
		local val = math.floor(math.random(range[1], range[2]) * rarityMult)
		table.insert(results, {id=picked.id, value=val})
	end

	return results
end

-- Armor alteration: new per-slot 50/50 logic.
local function rollArmorAlterationSubstats(targetItem, tier, count)
	local rarityMult = ItemConfig.RARITY_SUBSTAT_MULT[targetItem.rarity] or 1.0
	local statRange  = ItemConfig.ARMOR_SUBSTAT_RANGE[tier] or {175, 200}

	-- id -> effect lookup so we can use per-effect ranges for bonus substats
	local idToEff = {}
	for _, eff in ipairs(ItemConfig.ARMOR_EFFECTS)             do idToEff[eff.id] = eff end
	for _, eff in ipairs(ItemConfig.ARMOR_BONUS_EFFECTS or {}) do idToEff[eff.id] = eff end

	-- Build the two pools from ItemConfig
	local statPool  = {}   -- VIT/STR/DEX/INT
	local otherPool = {}   -- block, reflect, dodge, coinFind, elemRes, future extras
	for _, eff in ipairs(ItemConfig.ARMOR_EFFECTS) do
		table.insert(statPool, eff.id)
	end
	for _, eff in ipairs(ItemConfig.ARMOR_BONUS_EFFECTS or {}) do
		table.insert(otherPool, eff.id)
	end

	local usedIds  = {}
	local statUsed = 0
	local results  = {}

	for slot = 1, count do
		local availStat  = {}
		for _, id in ipairs(statPool)  do if not usedIds[id] then table.insert(availStat,  id) end end
		local availOther = {}
		for _, id in ipairs(otherPool) do if not usedIds[id] then table.insert(availOther, id) end end

		local pickedId

		if slot <= 2 then
			-- 50/50: try stat pool vs other pool
			local wantStat = math.random() < 0.5
			if wantStat and statUsed < ARMOR_MAX_STAT_SUBS and #availStat > 0 then
				pickedId = availStat[math.random(1, #availStat)]
				statUsed = statUsed + 1
			elseif #availOther > 0 then
				pickedId = availOther[math.random(1, #availOther)]
			elseif statUsed < ARMOR_MAX_STAT_SUBS and #availStat > 0 then
				-- fallback: other pool exhausted, use stat pool
				pickedId = availStat[math.random(1, #availStat)]
				statUsed = statUsed + 1
			else
				break
			end
		else
			-- Slots 3+: random from all remaining (respecting stat cap)
			local available = {}
			if statUsed < ARMOR_MAX_STAT_SUBS then
				for _, id in ipairs(availStat)  do table.insert(available, id) end
			end
			for _, id in ipairs(availOther) do table.insert(available, id) end
			if #available == 0 then break end
			pickedId = available[math.random(1, #available)]
			if ARMOR_STAT_IDS[pickedId] then statUsed = statUsed + 1 end
		end

		if not pickedId then break end
		usedIds[pickedId] = true
		local eff = idToEff[pickedId]
		local val
		if eff and eff.ranges then
			-- bonus effect: use its own tier range directly (no rarityMult — these are final values)
			local r = eff.ranges[tier] or eff.ranges[1]
			val = math.random(r[1], r[2])
		else
			-- stat substat (VIT/STR/DEX/INT): scale by rarity as normal
			val = math.floor(math.random(statRange[1], statRange[2]) * rarityMult)
		end
		table.insert(results, {id=pickedId, value=val})
	end

	return results
end

local function rollAlterationSubstats(targetItem, tier)
	local isWin = math.random() < 0.5
	local count

	if targetItem.type == "Armor" then
		-- Armor: fail = always 1 substat; win = WIN_SUBSTAT_DIST
		count = isWin and rollWeighted(WIN_SUBSTAT_DIST[tier] or WIN_SUBSTAT_DIST[1]) or 1
		return rollArmorAlterationSubstats(targetItem, tier, count)
	else
		-- Weapon: existing logic
		if isWin then
			count = rollWeighted(WIN_SUBSTAT_DIST[tier] or WIN_SUBSTAT_DIST[1])
		else
			local range = LOSE_SUBSTAT_RANGE[tier] or {1,1}
			count = math.random(range[1], range[2])
		end
		return rollWeaponAlterationSubstats(targetItem, tier, count)
	end
end

------------------------------------------------------------------------
-- Wisdom: rescale base stats from oldLevel to newLevel (writes into `subs`)
------------------------------------------------------------------------

rescaleForLevel = function(targetItem, subs, oldLevel, newLevel)
	local tTier = math.floor(tonumber(targetItem.tier) or 1)
	local median = TIER_MEDIANS[tTier] or 10
	local newFactor = 1 + (newLevel - median) * 0.01
	local oldFactor = 1 + (oldLevel - median) * 0.01
	if targetItem.type == "Weapon" then
		local mult = 1.0
		if type(targetItem.tags) == "table" then
			for _, tag in ipairs(targetItem.tags) do
				if WEAPON_MULTIPLIERS[tag] then mult = WEAPON_MULTIPLIERS[tag]; break end
			end
		end
		local rawMin = tonumber(subs._rawDmgMin)
		local rawMax = tonumber(subs._rawDmgMax)
		local oldMin = math.floor(tonumber(subs.dmgMin) or 0)
		local oldMax = math.floor(tonumber(subs.dmgMax) or 0)
		if rawMin and rawMax then
			subs.dmgMin = math.floor(rawMin * mult * newFactor)
			subs.dmgMax = math.floor(rawMax * mult * newFactor)
		else
			local ratio = newFactor / oldFactor
			if oldMin > 0 then subs.dmgMin = math.floor(oldMin * ratio) end
			if oldMax > 0 then subs.dmgMax = math.floor(oldMax * ratio) end
		end
	elseif targetItem.type == "Armor" then
		local rawHp = tonumber(subs._rawHp)
		local oldHp = math.floor(tonumber(subs.hp) or 0)
		local newHp = rawHp and math.floor(rawHp * newFactor) or math.floor(oldHp * (newFactor / oldFactor))
		if newHp and newHp > 0 then
			subs.hp  = newHp
			subs.hps = math.floor(newHp * 0.5)
		end
	end
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------

local CraftingOrbApply = {}

CraftingOrbApply.WISDOM_LEVEL_CAP_PER_TIER = WISDOM_LEVEL_CAP_PER_TIER

function CraftingOrbApply.IsImplemented(orbKind)
	return IMPLEMENTED[orbKind] == true
end

-- What a Wisdom Orb would do to `item` (pure; nothing is changed). Returns the new level and
-- a copy of subStats at that level, or nil + a reason ("level_capped").
function CraftingOrbApply.PreviewWisdom(item)
	if type(item) ~= "table" then return nil, "bad_target_item" end
	local tier = math.floor(tonumber(item.tier) or 1)
	local level = math.floor(tonumber(item.level) or 1)
	if level >= tier * WISDOM_LEVEL_CAP_PER_TIER then return nil, "level_capped" end
	local subs = {}
	for k, v in pairs(type(item.subStats) == "table" and item.subStats or {}) do subs[k] = v end
	rescaleForLevel(item, subs, level, level + 1)
	return level + 1, subs
end

function CraftingOrbApply.ApplyFromAct(profile, act, _rng)
	if type(profile) ~= "table" then return false, "bad_profile", nil end
	if type(act) ~= "table" or act.kind ~= "ApplyCraftingOrb" then return false, "bad_act", nil end
	local scrollUuid = act.scrollUuid
	local targetUuid = act.targetUuid
	if type(scrollUuid) ~= "string" or scrollUuid == ""
		or type(targetUuid) ~= "string" or targetUuid == "" then
		return false, "bad_uuids", nil
	end
	if scrollUuid == targetUuid then return false, "bad_uuids", nil end

	local orbItem    = resolveInBag(profile, scrollUuid)
	local targetItem = resolveInBag(profile, targetUuid)
	if not orbItem or not targetItem then return false, "item_not_found", nil end

	local orbDef = ItemDefinitions.Get(orbItem.itemId)
	if not orbDef or not ItemDefinitions.IsCraftingOrb(orbItem.itemId) then
		return false, "not_orb", nil
	end
	local okTarget, targetErr = EnchantScrollApply.ValidateEnchantTargetItem(targetItem)
	if not okTarget then return false, targetErr or "bad_target_item", nil end

	local sTier = math.floor(tonumber(orbDef.Tier) or 1)
	local tTier = math.floor(tonumber(targetItem.tier) or 1)
	if sTier ~= tTier then return false, "tier_mismatch", nil end

	local orbKind = orbDef.OrbKind
	if not IMPLEMENTED[orbKind] then return false, "orb_not_implemented", nil end

	local wisdomOldLevel, wisdomNewLevel
	if orbKind == "Wisdom" then
		wisdomOldLevel = math.floor(tonumber(targetItem.level) or 1)
		if wisdomOldLevel >= tTier * WISDOM_LEVEL_CAP_PER_TIER then return false, "level_capped", nil end
		wisdomNewLevel = wisdomOldLevel + 1
	end

	if not consumeOneFromBag(profile, scrollUuid) then
		return false, "orb_not_in_bag", nil
	end

	-- Wisdom Orb
	if orbKind == "Wisdom" then
		targetItem.level = wisdomNewLevel
		if type(targetItem.subStats) == "table" then
			rescaleForLevel(targetItem, targetItem.subStats, wisdomOldLevel, wisdomNewLevel)
		end
	end

	-- Alteration Orb
	if orbKind == "Alteration" then
		local newSubs = rollAlterationSubstats(targetItem, tTier)
		local subs    = targetItem.subStats
		if type(subs) == "table" then
			local baseKeys = (targetItem.type == "Weapon") and WEAPON_BASE_KEYS or ARMOR_BASE_KEYS
			for k in pairs(subs) do
				if not baseKeys[k] then subs[k] = nil end
			end
			for _, sub in ipairs(newSubs) do
				subs[sub.id] = sub.value
			end
		end
	end

	bumpSnapSeq(profile)
	return true, nil, { profile = profile, _seq = profile.__snapSeq }
end

return CraftingOrbApply
