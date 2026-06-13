--[[
	ProtectionScrollApply
	Authoritative rules for ApplyProtectionScroll (consumes scroll, sets scrollProtected on T1 gear).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local EnchantScrollApply = require(ReplicatedStorage:WaitForChild("EnchantScrollApply"))

local ProtectionScrollApply = {}

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

local function scrollFitsTarget(scrollItemId, target)
	if not ItemDefinitions.IsProtectionScroll(scrollItemId) then
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

function ProtectionScrollApply.ApplyFromAct(profile, act)
	if type(profile) ~= "table" then
		return false, "bad_profile", nil
	end
	if type(act) ~= "table" or act.kind ~= "ApplyProtectionScroll" then
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
	if not scrollDef or not ItemDefinitions.IsProtectionScroll(scrollItem.itemId) then
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

	if targetItem.scrollProtected == true then
		return false, "already_protected", nil
	end

	local okTarget, targetErr = EnchantScrollApply.ValidateEnchantTargetItem(targetItem)
	if not okTarget then
		return false, targetErr or "bad_target_item", nil
	end

	if not consumeOneFromBag(profile, scrollUuid) then
		return false, "scroll_not_in_bag", nil
	end

	targetItem.scrollProtected = true
	bumpSnapSeq(profile)
	return true, nil, { profile = profile, _seq = profile.__snapSeq }
end

return ProtectionScrollApply
