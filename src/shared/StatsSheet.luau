--[[
	StatsSheet -- everything the Journal's Stats page shows, computed from a profile snapshot.

	DISPLAY ONLY. Weapons are shown as if wielded from their equip slot (Weapon / Bow): the
	game applies a weapon's stats only while that weapon is actually held (MobCombat reads
	the held Tool), and this never changes that -- nothing here feeds back into combat, so
	there is nothing to hot-swap or stack.

	Mirrors the combat maths so the numbers match what happens in a fight:
	  armor        DamageService.ComputeFinal: damage * 100 / (100 + armor)
	  block        summed over all equipped gear, capped at ItemConfig.BLOCK_CHANCE_CAP_PCT
	  attributes   STR / INT / DEX / VIT summed over ItemConfig.ARMOR_SLOTS; the one matching the
	               weapon type (ARMOR_SUBSTAT_WEAPON_MAP) adds ARMOR_SUBSTAT_DMG_PER_200 per 200
	               points, smoothly (MobCombat.armorSubstatMultiplier)
	  weapon dmg   item.subStats.dmgMin/dmgMax (catalog weapons: WeaponData Damage), times the
	               attribute multiplier, floored, plus the flat Piercing and Elemental damage
	               every hit carries (DamageService.ComputeWeaponFinal), before armor and procs
	  effects      the weapon's own substats, explained from ItemConfig / ArmorEnchantConfig /
	               CombatEnchantConfig (live effects only: Dodge, Reflect, Elemental
	               Resistance and Accuracy do nothing in combat yet and are left out)
	  coin find    summed over ItemConfig.ARMOR_SLOTS (LootService.getTotalCoinFind)
	  mount        the fastest saddle owned (ItemDefinitions MountSpeed), vs sprint speed

	Compute(snap) -> sheet (see the return at the bottom), or nil while the snapshot isn't ready.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemConfig = require(ReplicatedStorage:WaitForChild("ItemConfig"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local WeaponData = require(ReplicatedStorage:WaitForChild("WeaponData"))
local EnergyConfig = require(ReplicatedStorage:WaitForChild("EnergyConfig"))
local ArmorEnchantConfig = require(ReplicatedStorage:WaitForChild("ArmorEnchantConfig"))
local CombatEnchantConfig = require(ReplicatedStorage:WaitForChild("CombatEnchantConfig"))

local StatsSheet = {}

StatsSheet.ATTRIBUTES = { "str", "int", "dex", "vit" }
StatsSheet.ATTRIBUTE_LABEL = { str = "STR", int = "INT", dex = "DEX", vit = "VIT" }

local function round(n)
	return math.floor(n + 0.5)
end

local function pct(n)
	n = tonumber(n) or 0
	if n == math.floor(n) then return tostring(math.floor(n)) .. "%" end
	return string.format("%.1f%%", n)
end

-- One plain line per live effect: what this value actually does.
local EXPLAIN = {
	critical = function(v)
		local every = v > 0 and math.max(1, math.floor(100 / v + 0.5)) or 0
		return ("About 1 hit in %d deals +50%% damage"):format(every)
	end,
	execute = function() return "Bonus damage on wounded foes, up to +25% the lower their health" end,
	pierce = function(v) return ("+%d damage on every hit (included in the damage range)"):format(math.floor(v)) end,
	crushing = function()
		return ("Chance to ignore %d%% of the target's armor on that hit"):format(round(ArmorEnchantConfig.CrushingArmorIgnore * 100))
	end,
	shatter = function()
		return ("Chance to break %d%% of the target's armor for %ds"):format(
			round(ArmorEnchantConfig.ShatterArmorReduction * 100), ArmorEnchantConfig.ShatterDuration)
	end,
	cleave = function()
		return ("Chance to hit up to %d nearby foes for %d%% damage"):format(
			CombatEnchantConfig.CleaveMaxTargets, round(CombatEnchantConfig.CleaveDamageFraction * 100))
	end,
	lifesteal = function(v) return ("Heals %s of the damage you deal"):format(pct(v)) end,
	vsMon = function(v) return ("%s more damage to monsters"):format(pct(v)) end,
	vsPly = function(v) return ("%s more damage to players"):format(pct(v)) end,
	elemDmg = function(v) return ("+%d elemental damage on every hit (included in the damage range)"):format(math.floor(v)) end,
	bleeding = function()
		return ("Chance to make the target bleed for %d%% of the hit over %ds"):format(
			round(CombatEnchantConfig.BleedDamageFraction * 100), CombatEnchantConfig.BleedTicks * CombatEnchantConfig.BleedInterval)
	end,
	blinding = function()
		return ("Chance to blind for %ds: half their attacks miss"):format(CombatEnchantConfig.BlindDuration)
	end,
	slowness = function()
		return ("Chance to slow the target by %d%% for %ds"):format(
			round((1 - CombatEnchantConfig.SlowMultiplier) * 100), CombatEnchantConfig.SlowDuration)
	end,
}
StatsSheet.EXPLAIN = EXPLAIN

-- Effect id -> registry icon key (RS/Assets/Images/JournalUI).
StatsSheet.EFFECT_ICON = {
	critical = "fx_critical", execute = "fx_execute", pierce = "fx_pierce", crushing = "fx_crushing",
	shatter = "fx_shatter", cleave = "fx_cleave", lifesteal = "fx_lifesteal", vsMon = "fx_vsmon",
	vsPly = "fx_vsply", elemDmg = "fx_elemental", bleeding = "fx_bleeding", blinding = "fx_blinding",
	slowness = "fx_slowness",
}

local function itemAt(profile, slot)
	local uuid = profile.equipped and profile.equipped[slot]
	local item = type(uuid) == "string" and profile.inventory and profile.inventory[uuid]
	return type(item) == "table" and item or nil
end

local function weaponTypeOf(item)
	if type(item.tags) == "table" then
		for _, tag in ipairs(item.tags) do
			if ItemConfig.WEAPON_MULTIPLIERS[tag] then return tag end
		end
	end
	return nil
end

local function displayName(item)
	if type(item.name) == "string" and item.name ~= "" then return item.name end
	local def = type(item.itemId) == "string" and ItemDefinitions.Get(item.itemId) or nil
	return def and def.DisplayName or "Unknown"
end

local function baseDamage(item)
	local subs = type(item.subStats) == "table" and item.subStats or {}
	local lo, hi = math.floor(tonumber(subs.dmgMin) or 0), math.floor(tonumber(subs.dmgMax) or 0)
	if lo < 1 or hi < 1 then
		local def = type(item.itemId) == "string" and ItemDefinitions.Get(item.itemId) or nil
		local wid = def and ((type(def.WeaponId) == "string" and def.WeaponId ~= "") and def.WeaponId or item.itemId) or nil
		if wid and WeaponData.Weapons and WeaponData.Weapons[wid] then
			local d = math.max(1, math.floor(tonumber(WeaponData.GetStats(wid).Damage) or 1))
			lo, hi = d, d
		end
	end
	return lo, math.max(lo, hi)
end

local function weaponSheet(item, attributes)
	if not item then return nil end
	local weaponType = weaponTypeOf(item) or (item.equipSlot == "Bow" and "Bow") or nil
	local lo, hi = baseDamage(item)

	-- The attribute that boosts this weapon type, and what it's worth right now.
	local attrKey
	for key, wt in pairs(ItemConfig.ARMOR_SUBSTAT_WEAPON_MAP) do
		if wt == weaponType then attrKey = key end
	end
	local mult = 1 + (attrKey and attributes[attrKey] / 200 or 0) * ItemConfig.ARMOR_SUBSTAT_DMG_PER_200

	local effects = {}
	local subs = type(item.subStats) == "table" and item.subStats or {}
	local pierce = math.max(0, tonumber(subs.pierce) or 0)
	local elem = math.max(0, tonumber(subs.elemDmg) or 0)
	local rollLo, rollHi = math.floor(lo * mult), math.floor(hi * mult)
	for _, effect in ipairs(ItemConfig.WEAPON_EFFECTS or {}) do
		local v = tonumber(subs[effect.id])
		if v and v > 0 and EXPLAIN[effect.id] then
			table.insert(effects, {
				id = effect.id,
				label = effect.label,
				value = v,
				valueText = effect.valueType == "flat" and ("+" .. math.floor(v)) or pct(v),
				explain = EXPLAIN[effect.id](v),
				icon = StatsSheet.EFFECT_ICON[effect.id],
			})
		end
	end

	return {
		item = item,
		name = displayName(item),
		icon = ItemDefinitions.GetIconForItem(item),
		rarity = item.rarity,
		enchant = tonumber(item.enchantLevel) or 0,
		weaponType = weaponType,
		baseLo = lo, baseHi = hi,        -- the weapon's own roll
		rollLo = rollLo, rollHi = rollHi, -- after the attribute bonus
		pierce = pierce, elem = elem,     -- flat, added to every hit
		lo = math.floor(rollLo + pierce + elem), hi = math.floor(rollHi + pierce + elem),
		attrKey = attrKey,
		attrTotal = attrKey and attributes[attrKey] or 0,
		attrBonusPct = (mult - 1) * 100,
		effects = effects,
	}
end

local function bestSaddle(profile)
	local best
	for _, item in pairs(profile.inventory or {}) do
		local def = type(item) == "table" and type(item.itemId) == "string" and ItemDefinitions.Get(item.itemId) or nil
		local speed = def and tonumber(def.MountSpeed)
		if speed and speed > 0 and (not best or speed > best.speed) then
			best = { name = def.DisplayName or item.itemId, tier = def.Tier, speed = speed, item = item }
		end
	end
	return best
end

function StatsSheet.Compute(snap)
	local profile = snap and snap.profile
	local derived = snap and snap.derived
	if type(profile) ~= "table" or type(derived) ~= "table" then return nil end
	local dc = derived.combat or {}

	-- Attributes + coin find over the armor slots; block over everything equipped.
	local attributes = { str = 0, int = 0, dex = 0, vit = 0 }
	local attributeSources = { str = {}, int = {}, dex = {}, vit = {} }
	local coinFind, coinSources = 0, {}
	local slots = {}
	for _, slot in ipairs(ItemConfig.ARMOR_SLOTS) do
		local item = itemAt(profile, slot)
		local subs = item and type(item.subStats) == "table" and item.subStats or {}
		for _, key in ipairs(StatsSheet.ATTRIBUTES) do
			local v = tonumber(subs[key]) or 0
			if v > 0 then
				attributes[key] += v
				table.insert(attributeSources[key], { slot = slot, value = v })
			end
		end
		local cf = tonumber(subs.coinFind) or 0
		if cf > 0 then
			coinFind += cf
			table.insert(coinSources, { slot = slot, value = cf })
		end
		table.insert(slots, {
			slot = slot,
			item = item,
			name = item and displayName(item) or nil,
			icon = item and ItemDefinitions.GetIconForItem(item) or nil,
			rarity = item and item.rarity or nil,
			hp = tonumber(subs.hp) or 0,
			armor = tonumber(subs.armor) or 0,
			hps = tonumber(subs.hps) or 0,
			energy = tonumber(subs.energy) or 0,
			block = tonumber(subs.block) or 0,
		})
	end
	local block, blockSources = 0, {}
	for slot, uuid in pairs(profile.equipped or {}) do
		local item = type(uuid) == "string" and profile.inventory and profile.inventory[uuid]
		local v = type(item) == "table" and type(item.subStats) == "table" and tonumber(item.subStats.block) or 0
		if v and v > 0 then
			block += v
			table.insert(blockSources, { slot = slot, value = v })
		end
	end

	local armor = math.floor(tonumber(dc.armor) or 0)
	-- Character base (before gear), from the same profile.stats.combat StatsService adds to.
	local sc = type(profile.stats) == "table" and type(profile.stats.combat) == "table" and profile.stats.combat or {}
	local melee = weaponSheet(itemAt(profile, "Weapon"), attributes)
	local ranged = weaponSheet(itemAt(profile, "Bow"), attributes)
	local saddle = bestSaddle(profile)

	return {
		hp = math.floor(tonumber(dc.hp) or 0),
		maxHp = math.floor(tonumber(dc.maxHp) or 0),
		hpRegen = tonumber(dc.hpRegen) or 0,
		energyRegen = tonumber(dc.energyRegen) or 0,
		base = {
			maxHp = math.floor(tonumber(sc.maxHp) or 0),
			hpRegen = tonumber(sc.hpRegen) or 0,
			energyRegen = tonumber(sc.energyRegen) or 0,
		},
		armor = armor,
		reduction = 1 - 100 / (100 + armor), -- share of incoming damage armor removes
		block = math.min(block, ItemConfig.BLOCK_CHANCE_CAP_PCT),
		blockRaw = block,
		blockCap = ItemConfig.BLOCK_CHANCE_CAP_PCT,
		blockSources = blockSources,
		slots = slots,
		attributes = attributes,
		attributeSources = attributeSources,
		attributeWeapon = ItemConfig.ARMOR_SUBSTAT_WEAPON_MAP, -- str -> "Axe", ...
		per200 = ItemConfig.ARMOR_SUBSTAT_DMG_PER_200 * 100,  -- damage % per 200 points (smooth)
		coinFind = coinFind,
		coinSources = coinSources,
		melee = melee,
		ranged = ranged,
		mount = saddle,
		sprintSpeed = EnergyConfig.SPRINT_SPEED,
		walkSpeed = EnergyConfig.NORMAL_SPEED,
	}
end

return StatsSheet
