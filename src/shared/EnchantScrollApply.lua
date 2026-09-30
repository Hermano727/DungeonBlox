--[[
	EnchantScrollApply
	Authoritative scroll rules for ApplyEnchantScroll.

	Server: in your DungeonInventoryAct OnServerInvoke, when act.kind == "ApplyEnchantScroll":
	  local EnchantScrollApply = require(ReplicatedStorage.EnchantScrollApply)
	  local ok, err, snap = EnchantScrollApply.ApplyFromAct(profile, act, Random.new())
	  if not ok then return false, err end
	  -- persist profile, then return true, snap (same shape as other inventory acts)

	Returns: ok:boolean, err:string?, snapshot:{ profile, _seq }?
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local EnchantScrollApply = {}

EnchantScrollApply.SUCCESS_CHANCE_AT_TARGET_LEVEL = {
	[4] = 0.80,
	[5] = 0.60,
	[6] = 0.40,
	[7] = 0.25,
	[8] = 0.15,
	[9] = 0.10,
}

local function statMultForScrollTier(_tier)
	return 0.05
end

local function bumpSnapSeq(profile)
	local n = math.floor(tonumber(profile.__snapSeq) or 0) + 1
	profile.__snapSeq = n
	return n
end

local function resolveInBag(profile, uuid)
	if type(profile) ~= "table" or type(uuid) ~= "string" or uuid == "" then
		return nil
	end
	local inv = profile.inventory
	if type(inv) ~= "table" then
		return nil
	end
	local it = inv[uuid]
	if type(it) == "table" then
		return it
	end
	return nil
end

function EnchantScrollApply.RollEnchantSuccess(targetEnchantLevel, rng)
	-- Random.new() returns userdata in Luau, not a table; only duck-type NextNumber.
	if rng == nil or type(rng.NextNumber) ~= "function" then
		return false
	end
	if targetEnchantLevel <= 3 then
		return true
	end
	local p = EnchantScrollApply.SUCCESS_CHANCE_AT_TARGET_LEVEL[targetEnchantLevel]
	if type(p) ~= "number" then
		return false
	end
	return rng:NextNumber() < p
end

--[[
	Targets for enchant can be:
	- Catalog-backed items with itemId (training gear, etc.)
	- Rolled loot from ItemGenerator: type/tier/name/subStats, often NO itemId
]]
function EnchantScrollApply.ValidateEnchantTargetItem(target)
	if type(target) ~= "table" then
		return false, "bad_target"
	end
	if target.type ~= "Weapon" and target.type ~= "Armor" then
		return false, "bad_target_type"
	end
	local tier = math.floor(tonumber(target.tier) or 0)
	if tier < 1 or tier > 5 then
		return false, "bad_tier"
	end
	return true, nil
end

local function scrollFitsTarget(scrollItemId, target)
	if not ItemDefinitions.IsEnchantScroll(scrollItemId) then
		return false
	end
	local st = ItemDefinitions.GetScrollTarget(scrollItemId)
	if st == "Weapon" then
		return target.type == "Weapon"
	end
	if st == "Armor" then
		return target.type == "Armor"
	end
	return target.type == "Weapon" or target.type == "Armor"
end

local function consumeOneFromBag(profile, uuid)
	local inv = profile.inventory
	if type(inv) ~= "table" then
		return false
	end
	local it = inv[uuid]
	if type(it) ~= "table" then
		return false
	end
	local c = math.floor(tonumber(it.count) or 1)
	if c > 1 then
		it.count = c - 1
	else
		inv[uuid] = nil
	end
	return true
end

local function refundScrollToBag(profile, uuid, scrollItem)
	local inv = profile.inventory
	if type(inv) ~= "table" then
		return
	end
	local back = inv[uuid]
	if type(back) == "table" then
		back.count = math.floor(tonumber(back.count) or 0) + 1
	else
		inv[uuid] = scrollItem
		scrollItem.count = 1
	end
end

-- Shields are told apart by slot, falling back to their stat shape (only shields roll HP/s,
-- only the other armor slots roll Energy/s -- see ItemGenerator).
local function isShield(item, subs)
	if type(item) == "table" and item.equipSlot == "Shield" then return true end
	if type(item) == "table" and type(item.tags) == "table" and table.find(item.tags, "Shield") then return true end
	return subs.hps ~= nil and subs.energy == nil
end

-- current * mult, floored, but always at least +1 (small values would otherwise never grow).
local function growInt(v, mult)
	local n = math.max(1, math.floor(v * mult + 1e-9))
	if n <= v then n = v + 1 end
	return n
end

-- current * mult at the stat's own 2-decimal precision, always at least +0.01.
local function growEnergy(v, mult)
	local n = math.floor(v * mult * 100 + 0.5) / 100
	if n <= v then n = math.floor((v + 0.01) * 100 + 0.5) / 100 end
	return n
end

--[[
	Pure: given an item + its current subStats, returns the subStats ONE successful enchant
	produces. Never mutates `subs`. Every bonus multiplies the CURRENT value (x1.05 per enchant,
	compounding), never the base:
	  Weapon                dmgMin, dmgMax
	  Armor (not a shield)  hp, energy (Energy/s)
	  Shield                hp, hps (HP/s out of combat)
	Nothing else changes, and no stat is added that the piece didn't roll. (Before 2026-09-27,
	armor set hps = floor(hp * 0.5) on EVERY piece -- giving helms/chests/legs/boots an HP/s
	they never rolled -- and never touched energy; RecomputeEnchantedArmor corrects those.)
	Shared by applyCompoundStatBonus (the real apply) and PreviewNextSubStats (the Enchanting
	Station's before/after preview), so the two can never drift apart. This is the only place
	the formula lives.
]]
local function computeBonusSubStats(item, subs, scrollTier)
	local mult = 1 + statMultForScrollTier(scrollTier)
	local itemType = type(item) == "table" and item.type or nil
	if itemType == "Armor" then
		local hp = tonumber(subs.hp)
		if not hp or hp < 1 then
			return false, "armor_missing_hp", nil
		end
		local out = {}
		for k, v in pairs(subs) do out[k] = v end
		out.hp = growInt(hp, mult)
		if isShield(item, subs) then
			local hps = tonumber(subs.hps)
			if hps and hps > 0 then out.hps = growInt(hps, mult) end
		else
			local energy = tonumber(subs.energy)
			if energy and energy > 0 then out.energy = growEnergy(energy, mult) end
		end
		return true, nil, out
	elseif itemType == "Weapon" then
		local lo = tonumber(subs.dmgMin)
		local hi = tonumber(subs.dmgMax)
		if not lo or not hi or lo < 1 or hi < 1 then
			return false, "weapon_missing_damage", nil
		end
		local newLo = math.max(1, math.floor(lo * mult + 1e-9))
		local newHi = math.max(newLo, math.floor(hi * mult + 1e-9))
		if newLo <= lo and newHi <= hi then
			newLo = lo + 1
			newHi = math.max(newLo, hi + (hi > lo and 1 or 0))
		end
		local out = {}
		for k, v in pairs(subs) do out[k] = v end
		out.dmgMin = newLo
		out.dmgMax = newHi
		return true, nil, out
	end
	return false, "bad_target_type", nil
end

--[[
	One-time correction (ProfileTypes.MIGRATIONS.enchantStats) for armor enchanted under the
	old formula. Re-derives the enchant-owned stats (hp + energy, or hp + hps for shields) by
	replaying enchantLevel successful enchants from the pre-enchant snapshot (baseSubStats),
	then writes just those keys back -- every other substat is left exactly as it is. A
	non-shield piece loses the HP/s the old formula wrongly gave it. Items without a snapshot
	(or not enchanted) are untouched. Returns true if it changed the item.
]]
function EnchantScrollApply.RecomputeEnchantedArmor(item)
	if type(item) ~= "table" or item.type ~= "Armor" then return false end
	local level = math.floor(tonumber(item.enchantLevel) or 0)
	local base = item.baseSubStats
	if level < 1 or type(base) ~= "table" or type(item.subStats) ~= "table" then return false end
	local subs = {}
	for k, v in pairs(base) do subs[k] = v end
	for _ = 1, level do
		local ok, _err, nextSubs = computeBonusSubStats(item, subs, nil)
		if not ok then return false end
		subs = nextSubs
	end
	local cur = item.subStats
	cur.hp = subs.hp
	if isShield(item, base) then
		cur.hps = subs.hps
	else
		cur.energy = subs.energy
		cur.hps = base.hps -- nil unless the piece really rolled HP/s
	end
	return true
end

local function applyCompoundStatBonus(scrollDef, target)
	local subs = target.subStats
	if type(subs) ~= "table" then
		subs = {}
		target.subStats = subs
	end
	local ok, err, newSubs = computeBonusSubStats(target, subs, scrollDef.Tier)
	if not ok then
		return false, err
	end
	for k, v in pairs(newSubs) do
		subs[k] = v
	end
	return true, nil
end

-- Read-only preview: what would `target.subStats` look like after ONE successful enchant,
-- with no side effects. Returns nil if the item can't be previewed (missing/invalid stats,
-- unknown type) -- callers should fall back to showing no preview rather than erroring.
function EnchantScrollApply.PreviewNextSubStats(target)
	if type(target) ~= "table" or type(target.subStats) ~= "table" then
		return nil
	end
	local ok, _err, newSubs = computeBonusSubStats(target, target.subStats, nil)
	if not ok then
		return nil
	end
	return newSubs
end

-- Read-only odds: success chance (0..1) for going from `currentEnchantLevel` to +1, with no
-- side effects -- the same rule RollEnchantSuccess rolls against, exposed for UI odds
-- display (e.g. the Enchanting Station's "X% success" text) without needing an RNG. Returns
-- nil when already at the +9 cap (nothing to roll).
function EnchantScrollApply.GetSuccessChanceForNextLevel(currentEnchantLevel)
	local cur = math.floor(tonumber(currentEnchantLevel) or 0)
	if cur >= 9 then
		return nil
	end
	local nextLevel = cur + 1
	if nextLevel <= 3 then
		return 1
	end
	return EnchantScrollApply.SUCCESS_CHANCE_AT_TARGET_LEVEL[nextLevel]
end

function EnchantScrollApply.ApplyFromAct(profile, act, rng)
	if type(profile) ~= "table" then
		return false, "bad_profile", nil
	end
	if type(act) ~= "table" or act.kind ~= "ApplyEnchantScroll" then
		return false, "bad_act", nil
	end
	local scrollUuid = act.scrollUuid
	local targetUuid = act.targetUuid
	if type(scrollUuid) ~= "string" or scrollUuid == "" or type(targetUuid) ~= "string" or targetUuid == "" then
		return false, "bad_uuids", nil
	end

	local scrollItem = resolveInBag(profile, scrollUuid)
	local targetItem = resolveInBag(profile, targetUuid)
	if not scrollItem or not targetItem then
		return false, "item_not_found", nil
	end
	local scrollDef = ItemDefinitions.Get(scrollItem.itemId)
	if not scrollDef or not ItemDefinitions.IsEnchantScroll(scrollItem.itemId) then
		return false, "not_scroll", nil
	end
	if not scrollFitsTarget(scrollItem.itemId, targetItem) then
		return false, "scroll_target_mismatch", nil
	end
	local sTier = math.floor(tonumber(scrollDef.Tier) or 1)
	local tTier = math.floor(tonumber(targetItem.tier) or 1)
	if sTier ~= tTier then
		return false, "tier_mismatch", nil
	end

	local curEnch = math.floor(tonumber(targetItem.enchantLevel) or 0)
	if curEnch >= 9 then
		return false, "max_enchant", nil
	end
	local nextEnch = curEnch + 1

	-- Snapshot base stats before the first enchant so we can restore on failure.
	if curEnch == 0 then
		local subs = targetItem.subStats
		if type(subs) == "table" then
			local snap = {}
			for k, v in pairs(subs) do snap[k] = v end
			targetItem.baseSubStats = snap
		end
	end

	-- T1 enchant scroll on Protected gear: failed roll keeps enchant (no wipe) and strips protection;
	-- successful roll applies enchant and strips protection.
	local tier1Protected = (math.floor(tonumber(scrollDef.Tier) or 1) == 1) and targetItem.scrollProtected

	if not consumeOneFromBag(profile, scrollUuid) then
		return false, "scroll_not_in_bag", nil
	end

	local success = EnchantScrollApply.RollEnchantSuccess(nextEnch, rng)
	if not success then
		if tier1Protected then
			targetItem.scrollProtected = nil
		else
			targetItem.enchantLevel = 0
			local base = targetItem.baseSubStats
			if type(base) == "table" then
				local subs = targetItem.subStats
				if type(subs) ~= "table" then
					subs = {}
					targetItem.subStats = subs
				end
				for k in pairs(subs) do subs[k] = nil end
				for k, v in pairs(base) do subs[k] = v end
				targetItem.baseSubStats = nil
			end
		end
		bumpSnapSeq(profile)
		return true, nil, { profile = profile, _seq = profile.__snapSeq }
	end

	targetItem.enchantLevel = nextEnch
	local okStat, errStat = applyCompoundStatBonus(scrollDef, targetItem)
	if not okStat then
		targetItem.enchantLevel = curEnch
		refundScrollToBag(profile, scrollUuid, scrollItem)
		return false, errStat or "stat_apply_failed", nil
	end

	if tier1Protected then
		targetItem.scrollProtected = nil
	end

	bumpSnapSeq(profile)
	return true, nil, { profile = profile, _seq = profile.__snapSeq }
end

return EnchantScrollApply

