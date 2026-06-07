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
	if type(rng) ~= "table" or type(rng.NextNumber) ~= "function" then
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
return EnchantScrollApply
