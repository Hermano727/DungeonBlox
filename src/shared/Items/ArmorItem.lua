--!strict
--[[
	ArmorItem : Item -- catalog armor (Kind = "Armor"). Its equip slot is already
	1:1 with the catalog's own `Slot` field (Helm/Chest/Legs/Boots/Shield) -- this class
	just makes sure that field actually gets copied onto the owned record, which
	GrantItemId never used to do. Without it, EVERY armor piece collapsed onto one shared
	generic "Armor" slot that isn't even one of PlayerPreview's real equip-panel boxes, so
	e.g. equipping a Shield and then Boots would silently bounce each other back to the bag
	-- both were fighting over that one fake slot.
]]

local Item = require(script.Parent:WaitForChild("Item"))
local ItemConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("ItemConfig"))

local ArmorItem = setmetatable({}, { __index = Item })
ArmorItem.__index = ArmorItem

function ArmorItem.new(itemId: string, def)
	local self = Item.new(itemId, def)
	self.armorSlot = def.Slot -- "Helm" | "Chest" | "Legs" | "Boots" | "Shield"
	return setmetatable(self, ArmorItem)
end

function ArmorItem:GetEquipSlot(): string?
	return self.armorSlot
end

-- Roll the SAME defensive base stats ItemGenerator gives procedurally-generated
-- armor, from the SAME ItemConfig tables -- ARMOR_HP_RANGES / ARMOR_ARMOR_RANGES /
-- ARMOR_ENERGY_RANGES / ARMOR_DMGRED_RANGES -- rather than duplicating numbers here.
--
-- Catalog armor (every Training* and Leather* piece) previously granted with an
-- EMPTY subStats table, because ItemFactory had no armor equivalent of
-- WeaponItem:GetExtraSubStats. So starter gear contributed no HP, no armor, no
-- energy regen and no HP/s, while a first mob-dropped Common did all four --
-- which is why the training set looked broken next to it.
--
-- Slot rules:
--   HP       -- every armor slot
--   HP/s     -- SHIELD ONLY (derived: exactly half the HP roll; CombatStateService
--               adds it to out-of-combat regen)
--   Energy/s -- every slot EXCEPT shields
--   DMG Red  -- SHIELD ONLY
--   Armor    -- every armor slot
function ArmorItem:GetExtraSubStats(_opts)
	local def = self.def
	if type(def) ~= "table" then
		return nil
	end

	local tier = math.clamp(tonumber(def.Tier) or 1, 1, 5)
	local rarity = def.Rarity or "Common"

	local function pickInt(tbl)
		local byTier = tbl and tbl[tier]
		local r = byTier and byTier[rarity]
		if not r then return nil end
		return math.random(r[1], r[2])
	end

	local out: { [string]: any } = {}

	local isShield = (def.Slot == "Shield")

	-- HP: every armor slot.
	local hp = pickInt(ItemConfig.ARMOR_HP_RANGES)
	if hp then
		out.hp = hp
		-- HP/s is SHIELD-EXCLUSIVE. Helm/Chest/Legs/Boots never roll it.
		if isShield then
			out.hps = math.floor(hp * 0.5)
		end
	end

	local armor = pickInt(ItemConfig.ARMOR_ARMOR_RANGES)
	if armor then
		out.armor = armor
	end

	-- Energy/s is the inverse of HP/s: regular armor rolls it, shields never do.
	local enByTier = (not isShield) and ItemConfig.ARMOR_ENERGY_RANGES
		and ItemConfig.ARMOR_ENERGY_RANGES[tier] or nil
	local enR = enByTier and enByTier[rarity]
	if enR then
		local roll = enR[1] + math.random() * (enR[2] - enR[1])
		out.energy = math.floor(roll * 100 + 0.5) / 100
	end

	if isShield then
		local dr = pickInt(ItemConfig.ARMOR_DMGRED_RANGES)
		if dr then
			out.dmgRed = dr
		end
	end

	if next(out) == nil then
		return nil
	end
	return out
end

return ArmorItem
