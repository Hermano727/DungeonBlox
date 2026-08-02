--[[
	AltarUpgrade
	Authoritative altar rarity fusion: 5 same-tier + same-rarity gear -> center +1 rarity.
	Each gear piece can only be ascended once (altarRarityUpgraded flag).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage:WaitForChild("ItemConfig"))
local ItemGenerator = require(ServerScriptService:WaitForChild("ItemGenerator"))

local AltarUpgrade = {}

local RARITY_ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }

function AltarUpgrade.GetNextRarity(rarity)
	if type(rarity) ~= "string" then
		return nil
	end
	for i, r in ipairs(RARITY_ORDER) do
		if r == rarity and i < #RARITY_ORDER then
			return RARITY_ORDER[i + 1]
		end
	end
	return nil
end

local function inferWeaponType(item)
	if type(item.tags) == "table" then
		for _, tag in ipairs(item.tags) do
			for _, wt in ipairs(Config.WEAPON_TYPES) do
				if tag == wt then
					return wt
				end
			end
		end
	end
	if type(item.name) == "string" then
		for _, wt in ipairs(Config.WEAPON_TYPES) do
			if string.find(item.name, wt, 1, true) then
				return wt
			end
		end
	end
	return Config.WEAPON_TYPES[1]
end

local function inferArmorSlot(item)
	if type(item.equipSlot) == "string" then
		for _, slot in ipairs(Config.ARMOR_SLOTS) do
			if item.equipSlot == slot then
				return slot
			end
		end
	end
	if type(item.tags) == "table" then
		for _, tag in ipairs(item.tags) do
			for _, slot in ipairs(Config.ARMOR_SLOTS) do
				if tag == slot then
					return slot
				end
			end
		end
	end
	return Config.ARMOR_SLOTS[1]
end

function AltarUpgrade.IsValidGearItem(item)
	return type(item) == "table" and (item.type == "Weapon" or item.type == "Armor")
end

function AltarUpgrade.ItemMatchesAltar(item, altarTier)
	if not AltarUpgrade.IsValidGearItem(item) then
		return false, "not_gear"
	end
	local tier = math.floor(tonumber(item.tier) or 0)
	altarTier = math.floor(tonumber(altarTier) or 0)
	if tier ~= altarTier or altarTier < 1 then
		return false, "tier_mismatch"
	end
	return true, nil
end

function AltarUpgrade.CanBeCenter(item, altarTier)
	local ok, err = AltarUpgrade.ItemMatchesAltar(item, altarTier)
	if not ok then
		return false, err
	end
	if item.altarRarityUpgraded == true then
		return false, "already_upgraded"
	end
	local rarity = item.rarity
	if type(rarity) ~= "string" or rarity == "" then
		return false, "bad_rarity"
	end
	if not AltarUpgrade.GetNextRarity(rarity) then
		return false, "max_rarity"
	end
	return true, nil
end

function AltarUpgrade.CanBeSacrifice(item, altarTier, centerItem)
	local ok, err = AltarUpgrade.ItemMatchesAltar(item, altarTier)
	if not ok then
		return false, err
	end
	if type(centerItem) ~= "table" then
		return false, "bad_center"
	end
	if item.rarity ~= centerItem.rarity then
		return false, "rarity_mismatch"
	end
	return true, nil
end

local function rollUpgradedTemplate(centerItem, nextRarity)
	local tier = math.floor(tonumber(centerItem.tier) or 1)
	local level = math.max(1, math.floor(tonumber(centerItem.level) or Config.TIER_MEDIANS[tier] or 10))
	local opts = {
		tier = tier,
		rarity = nextRarity,
		level = level,
	}
	if centerItem.type == "Weapon" then
		opts.weaponType = inferWeaponType(centerItem)
	else
		opts.armorSlot = inferArmorSlot(centerItem)
	end
	local rolled = ItemGenerator.generate(opts)
	return rolled:toGrantTemplate()
end

function AltarUpgrade.ApplyUpgrade(profile, altarTier, centerUuid, sacrificeUuids)
	if type(profile) ~= "table" then
		return false, "bad_profile"
	end
	altarTier = math.floor(tonumber(altarTier) or 0)
	if altarTier < 1 or altarTier > 5 then
		return false, "bad_altar_tier"
	end
	if type(centerUuid) ~= "string" or centerUuid == "" then
		return false, "bad_center"
	end
	if type(sacrificeUuids) ~= "table" or #sacrificeUuids ~= 4 then
		return false, "bad_sacrifices"
	end

	local inv = profile.inventory
	if type(inv) ~= "table" then
		return false, "bad_inventory"
	end

	local center = inv[centerUuid]
	if type(center) ~= "table" then
		return false, "center_not_owned"
	end

	local okCenter, errCenter = AltarUpgrade.CanBeCenter(center, altarTier)
	if not okCenter then
		return false, errCenter
	end

	local seen = { [centerUuid] = true }
	for _, su in ipairs(sacrificeUuids) do
		if type(su) ~= "string" or su == "" then
			return false, "bad_sacrifice_uuid"
		end
		if seen[su] then
			return false, "duplicate_uuid"
		end
		seen[su] = true
		local sac = inv[su]
		if type(sac) ~= "table" then
			return false, "sacrifice_not_owned"
		end
		local okSac, errSac = AltarUpgrade.CanBeSacrifice(sac, altarTier, center)
		if not okSac then
			return false, errSac
		end
	end

	local nextRarity = AltarUpgrade.GetNextRarity(center.rarity)
	if not nextRarity then
		return false, "max_rarity"
	end

	local template = rollUpgradedTemplate(center, nextRarity)

	center.rarity = nextRarity
	center.name = template.name
	center.level = template.level or center.level
	center.subStats = template.subStats
	center.equipSlot = template.equipSlot or center.equipSlot
	center.enchantLevel = 0
	center.baseSubStats = nil
	center.scrollProtected = nil
	center.altarRarityUpgraded = true
	if template.toolPrefabName then
		center.toolPrefabName = template.toolPrefabName
	end
	if template.tags then
		center.tags = template.tags
	end

	for _, su in ipairs(sacrificeUuids) do
		inv[su] = nil
	end

	return true, nil, {
		centerUuid = centerUuid,
		nextRarity = nextRarity,
	}
end

return AltarUpgrade
