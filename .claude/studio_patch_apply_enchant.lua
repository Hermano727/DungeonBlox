local m = game.ServerScriptService:WaitForChild("ProfileService")
local src = m.Source

if not string.find(src, "local EnchantScrollApply = require", 1, true) then
	local needle = 'local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))'
	local ins = needle
		.. "\nlocal EnchantScrollApply = require(ReplicatedStorage:WaitForChild(\"EnchantScrollApply\"))"
	src = string.gsub(src, needle, ins, 1)
end

local startPat = "local MAX_PLUS_SCROLL = 99"
local endPat = "\nfunction ProfileService.ConsumeItemId"
local i = string.find(src, startPat, 1, true)
local j = string.find(src, endPat, 1, true)
if not i or not j then
	return "markers_not_found", i, j
end

local newBlock = [==[function ProfileService.ApplyEnchantScroll(player, scrollUuid, targetUuid)
	local profile = ProfileService.Load(player)
	if type(scrollUuid) ~= "string" or scrollUuid == "" or type(targetUuid) ~= "string" or targetUuid == "" then
		return false, "bad_arg"
	end
	if scrollUuid == targetUuid then
		return false, "bad_arg"
	end
	ensureHotbar(profile)

	local scroll = profile.inventory[scrollUuid]
	local target = profile.inventory[targetUuid]
	if type(scroll) ~= "table" or type(target) ~= "table" then
		return false, "not_owned"
	end
	if type(scroll.itemId) ~= "string" or not ItemDefinitions.IsEnchantScroll(scroll.itemId) then
		return false, "not_scroll"
	end
	if uuidEquipped(profile, scrollUuid) then
		return false, "scroll_equipped"
	end
	if target.type ~= "Weapon" and target.type ~= "Armor" then
		return false, "bad_target"
	end

	local okScroll, scrollErr = Types.ValidateOwnedItem(scroll)
	if not okScroll then
		return false, scrollErr or "bad_scroll"
	end
	-- Rolled mob loot is a valid Weapon/Armor but usually has no catalog itemId;
	-- ValidateOwnedItem would return bad_itemId. Scroll rules only need type/tier/subStats.
	local okTarget, targetErr = EnchantScrollApply.ValidateEnchantTargetItem(target)
	if not okTarget then
		return false, targetErr or "bad_target_item"
	end

	local okApply, errApply = EnchantScrollApply.ApplyFromAct(profile, {
		kind = "ApplyEnchantScroll",
		scrollUuid = scrollUuid,
		targetUuid = targetUuid,
	}, Random.new())
	if not okApply then
		return false, errApply
	end

	StatsService.RecomputeRuntimeHp(profile)
	ProfileService.PushProfile(player)
	Hotbar.syncFromProfile(player, profile)
	return true, ProfileService.GetLastSnapshotPayload(player)
end

]==]

src = string.sub(src, 1, i - 1) .. newBlock .. string.sub(src, j)
m.Source = src
return "ok", #m.Source