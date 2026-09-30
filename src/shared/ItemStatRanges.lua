--[[
	ItemStatRanges -- ReplicatedStorage

	The one authority for "what window is this substat allowed to be in, on THIS
	item", and the clamp that brings an existing item back inside it.

	Why this exists: a rolled substat is stored as a bare number
	(`item.subStats.bleeding = 6`) with no record of the window it came from. So
	when a range is rebalanced -- say bleeding narrows from 3-6% to 2-5% -- every
	item already holding a 6% is permanently out of range and nothing in the game
	notices. This module plus the gated pass in ProfileTypes.Reconcile is what
	makes those values follow a rebalance.

	POLICY: clamp the UPPER bound only.
	  * A value already inside the window is untouched.
	  * A value above the window is lowered to the maximum.
	  * A value BELOW the window is left alone. Raising it would be a silent buff,
	    and legitimately-low authored values exist (Kane's armour rolls block 2-4
	    where the generic T1 block floor is 3).

	AUTHORED LOOT IS NOT GENERIC. Named-elite and Mythic gear is hand-authored
	outside the generic per-tier windows in BOTH directions -- Kane's Axe rolls
	6-9% critical where WEAPON_EFFECTS.critical.ranges[1] is {2,3}. A generic
	clamp would quietly gut every named-elite drop in the game to 3. That is why
	`item.origin.d` (the authored def key, stamped by ItemIdentity at drop time)
	is load-bearing here: without it this module cannot tell a god-roll from
	corrupt data.

	WHITELIST, NOT BLACKLIST. Only ids that ItemConfig.FindSubstatEffect resolves
	are ever touched. That automatically skips base stats (dmgMin/dmgMax/hp/hps/
	armor/energy/dmgRed), the private _raw* keys, and MiningLevel/FishingLevel --
	none of which live in the effect tables. Base stats MUST be skipped anyway:
	enchant scrolls multiply hp/dmgMin/dmgMax compoundingly and legitimately grow
	far past any generation range. Adding a new substat to ItemConfig makes it
	clampable automatically, with no edit here.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemConfig = require(ReplicatedStorage:WaitForChild("ItemConfig"))
local NamedEliteLootDefs = require(ReplicatedStorage:WaitForChild("NamedEliteLootDefs"))
local MythicItemDefs = require(ReplicatedStorage:WaitForChild("MythicItemDefs"))

local ItemStatRanges = {}

----------------------------------------------------------------------
-- Authored-def lookup
----------------------------------------------------------------------

-- defKey -> the authored SubStats spec list, across both authored-loot systems.
-- Built lazily and cached: the def tables are static data loaded once.
local authoredSpecsByKey

local function buildAuthoredIndex()
	local index = {}
	for _, drops in pairs(NamedEliteLootDefs.Drops or {}) do
		for _, entry in ipairs(drops.Pool or {}) do
			if type(entry.Key) == "string" then
				index[entry.Key] = entry.SubStats
			end
		end
	end
	for key, def in pairs(MythicItemDefs.Items or {}) do
		if type(key) == "string" then
			index[key] = def.SubStats
		end
	end
	return index
end

-- Returns the authored {min, max} for this def key's substat, or nil when the
-- item isn't authored, the key is unknown, or the spec defers to the standard
-- roll (`highRollStandard` / `useStandardRoll`), in which case the generic
-- window is the correct answer.
local function authoredWindow(defKey, substatId)
	if type(defKey) ~= "string" or defKey == "" then
		return nil
	end
	authoredSpecsByKey = authoredSpecsByKey or buildAuthoredIndex()
	local specs = authoredSpecsByKey[defKey]
	if type(specs) ~= "table" then
		return nil
	end
	for _, spec in ipairs(specs) do
		if spec.id == substatId then
			if type(spec.min) == "number" and type(spec.max) == "number" then
				return spec.min, spec.max
			end
			return nil -- defers to the generic roll
		end
	end
	return nil
end

----------------------------------------------------------------------
-- Window resolution
----------------------------------------------------------------------

-- The weapon-type multiplier for an item, or 1.0 for armour / an unknown type.
-- Weapon kind survives onto the owned record only inside `tags` -- ItemClass's
-- toGrantTemplate pushes self.weaponType there and keeps no dedicated field.
local function weaponMultiplierFor(item)
	if type(item.tags) ~= "table" then
		return 1.0
	end
	for _, tag in ipairs(item.tags) do
		local mult = ItemConfig.WEAPON_MULTIPLIERS[tag]
		if mult then
			return mult
		end
	end
	return 1.0
end

--[[
	WindowFor(item, substatId) -> lo, hi | nil

	nil means "no opinion" -- an unknown substat id, or a base stat. Callers must
	leave those values completely alone rather than guessing.

	Generic windows mirror ItemGenerator's roll math exactly (the per-tier range
	multiplied by the rarity multiplier, floored). If that math ever changes,
	change it in both places or the clamp will start shaving legitimately-rolled
	values on the next rebalance.
]]
function ItemStatRanges.WindowFor(item, substatId)
	if type(item) ~= "table" or type(substatId) ~= "string" then
		return nil
	end

	local effect = ItemConfig.FindSubstatEffect(substatId)
	if not effect then
		return nil -- base stat, profession stat, or something we don't own
	end

	-- elemDmg is the one substat that takes a SECOND multiplier after it is
	-- rolled: ItemClass:getFinalStats applies the weapon-type multiplier to it
	-- (Bow 1.20, Mace 1.15, ...). Its stored value therefore legitimately sits
	-- above whatever window it was rolled from -- generic OR authored -- and
	-- forgetting this would shave ~17% off every bow's elemental damage on the
	-- first rebalance sweep. If another substat ever picks up a post-roll
	-- multiplier in getFinalStats, mirror it here.
	local postRoll = (substatId == "elemDmg") and weaponMultiplierFor(item) or 1.0

	local origin = type(item.origin) == "table" and item.origin or nil
	local lo, hi = authoredWindow(origin and origin.d, substatId)
	if lo and hi then
		return math.floor(lo * postRoll), math.floor(hi * postRoll)
	end

	local tier = math.clamp(math.floor(tonumber(item.tier) or 1), 1, 5)
	local range = effect.ranges and effect.ranges[tier]
	if not range then
		-- vit/str/int/dex have no per-effect ranges; they share one table.
		range = ItemConfig.ARMOR_SUBSTAT_RANGE and ItemConfig.ARMOR_SUBSTAT_RANGE[tier]
	end
	if not range then
		return nil
	end

	local mult = (ItemConfig.RARITY_SUBSTAT_MULT[item.rarity] or 1.0) * postRoll
	return math.floor(range[1] * mult), math.floor(range[2] * mult)
end

----------------------------------------------------------------------
-- Clamping
----------------------------------------------------------------------

local function clampDict(item, subs)
	if type(subs) ~= "table" then
		return false
	end
	local changed = false
	for id, value in pairs(subs) do
		if type(value) == "number" then
			local _, hi = ItemStatRanges.WindowFor(item, id)
			if hi and value > hi then
				subs[id] = hi
				changed = true
			end
		end
	end
	return changed
end

--[[
	ClampItem(item) -> changed: boolean

	Clamps `item.subStats` and `item.baseSubStats` together.

	`baseSubStats` is not optional. EnchantScrollApply snapshots it before an
	enchant attempt and restores it verbatim when the attempt fails -- clamping
	only `subStats` would let a player un-clamp an out-of-range value by
	deliberately failing an enchant.
]]
function ItemStatRanges.ClampItem(item)
	if type(item) ~= "table" then
		return false
	end
	local a = clampDict(item, item.subStats)
	local b = clampDict(item, item.baseSubStats)
	return a or b
end

-- Clamps every item in an inventory dict. Returns how many were changed.
function ItemStatRanges.ClampInventory(inv)
	if type(inv) ~= "table" then
		return 0
	end
	local count = 0
	for _, item in pairs(inv) do
		if type(item) == "table" and ItemStatRanges.ClampItem(item) then
			count += 1
		end
	end
	return count
end

return ItemStatRanges
