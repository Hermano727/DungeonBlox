--!strict
--[[
	WeaponItem : Item -- catalog weapons (Kind = "Weapon").

	The equip-slot bug this whole hierarchy exists to fix, in one sentence: every weapon
	used to resolve to the single slot "Weapon" no matter what kind it was, so a Bow and a
	Sword fought over the same equip-panel box even though PlayerPreview.lua, the hotbar
	HUD, and KeybindConfig.Keybinds.ToolSlot already all treat Bow as its own slot.

	Catalog weapon entries (TrainingSword, TrainingBow, ...) don't carry an explicit
	"weapon kind" field of their own -- only `WeaponId`, which keys into WeaponData for
	combat stats. ItemConfig.WEAPON_ID_KIND maps that WeaponId to a kind string (Sword /
	Scythe / Axe / Mace / Bow); anything not listed there defaults to "Sword", which is
	correct for every catalog weapon that exists today (only WoodenBow needs an entry).
	Add a new bow-family (or any non-default-slot) weapon there, nowhere else, and both the
	catalog-grant path (this class) and the procedural-drop path
	(src/server/ItemClass.lua, which already carries an explicit weaponType from
	ItemGenerator) agree on its slot via the same ItemConfig.WEAPON_TYPE_EQUIP_SLOT table.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("ItemConfig"))
local Item = require(script.Parent:WaitForChild("Item"))

local WeaponItem = setmetatable({}, { __index = Item })
WeaponItem.__index = WeaponItem

function WeaponItem.new(itemId: string, def)
	local self = Item.new(itemId, def)
	self.weaponId = def.WeaponId
	self.weaponKind = (self.weaponId and Config.WEAPON_ID_KIND[self.weaponId]) or "Sword"
	return setmetatable(self, WeaponItem)
end

function WeaponItem:GetEquipSlot(): string?
	return Config.WEAPON_TYPE_EQUIP_SLOT[self.weaponKind] or "Weapon"
end

-- Deliberately NOT stamping `tags` here (see Item:GetTags doc) -- EquippedHotbar
-- reads a weapon's tags to apply EnergyConfig.WEAPON_SWING_MULT, so doing this
-- automatically would silently change training gear's swing-energy cost. Uncomment (and
-- have someone sanity-check the resulting swing costs in a real playtest) if that's ever
-- intentionally wanted:
-- function WeaponItem:GetTags(): { string }?
-- 	return { self.weaponKind }
-- end

-- Rolls flat dmgMin/dmgMax onto subStats from WeaponData, same formula GrantItemId used
-- to do inline. Only fires for non-stackable single-instance grants (weapons never stack).
function WeaponItem:GetExtraSubStats(_opts)
	local WeaponData = require(ReplicatedStorage:WaitForChild("WeaponData"))
	local wid = (type(self.weaponId) == "string" and self.weaponId ~= "") and self.weaponId or self.itemId
	local stats = WeaponData.GetStats(wid)
	local d = math.max(1, math.floor(tonumber(stats.Damage) or 1))
	return { dmgMin = d, dmgMax = d }
end

return WeaponItem
