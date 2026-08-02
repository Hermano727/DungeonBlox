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

local function applyCompoundStatBonus(scrollDef, target)
	local subs = target.subStats
	if type(subs) ~= "table" then
		subs = {}
		target.subStats = subs
	end
	local mult = 1 + statMultForScrollTier(scrollDef.Tier)
	if target.type == "Armor" then
		local hp = tonumber(subs.hp)
		if not hp or hp < 1 then
			return false, "armor_missing_hp"
		end
		local newHp = math.max(1, math.floor(hp * mult + 1e-9))
		if newHp <= hp then
			newHp = hp + 1
		end
		subs.hp = newHp
		subs.hps = math.floor(subs.hp * 0.5)
	elseif target.type == "Weapon" then
		local lo = tonumber(subs.dmgMin)
		local hi = tonumber(subs.dmgMax)
		if not lo or not hi or lo < 1 or hi < 1 then
			return false, "weapon_missing_damage"
		end
		local newLo = math.max(1, math.floor(lo * mult + 1e-9))
		local newHi = math.max(newLo, math.floor(hi * mult + 1e-9))
		if newLo <= lo and newHi <= hi then
			newLo = lo + 1
			newHi = math.max(newLo, hi + (hi > lo and 1 or 0))
		end
		subs.dmgMin = newLo
		subs.dmgMax = newHi
	else
		return false, "bad_target_type"
	end
	return true, nil
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

