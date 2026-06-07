local WeaponData = {}

WeaponData.Weapons = {
	TrainingSword = {
		Damage     = 6,
		MaxRange   = 12,
		AttackType = "Melee",
	},
	WoodenSword = {
		Damage     = 5,
		MaxRange   = 12,
		AttackType = "Melee",
	},
	["Wood Sword"] = {
		Damage     = 5,
		MaxRange   = 12,
		AttackType = "Melee",
	},
	Low_tier_sword = {
		Damage     = 7,
		MaxRange   = 12,
		AttackType = "Melee",
	},
	R6Sword = {
		Damage     = 6,
		MaxRange   = 12,
		AttackType = "Melee",
	},
	["Axe Tool"] = {
		Damage     = 5,
		MaxRange   = 12,
		AttackType = "Melee",
	},
	scythe = {
		Damage     = 5,
		MaxRange   = 12,
		AttackType = "Melee",
	},
	Mace = {
		Damage     = 5,
		MaxRange   = 12,
		AttackType = "Melee",
	},
	WoodenBow = {
		Damage          = 12,
		MaxRange        = 100,
		ProjectileSpeed = 150,
		AttackType      = "Projectile",
	},
}

local TOOL_NAME_ALIASES = {}

function WeaponData.GetWeaponIdFromTool(tool)
	if not tool then return nil end
	local attr = tool:GetAttribute("WeaponId")
	if attr and WeaponData.Weapons[attr] then return attr end
	if WeaponData.Weapons[tool.Name] then return tool.Name end
	if TOOL_NAME_ALIASES[tool.Name] then return TOOL_NAME_ALIASES[tool.Name] end
	return nil
end

function WeaponData.GetStats(weaponId)
	return WeaponData.Weapons[weaponId] or {Damage=0, MaxRange=0, AttackType="None"}
end

function WeaponData.ShouldUseClientHitDetection(weaponId)
	if not weaponId or not WeaponData.Weapons[weaponId] then return false end
	return WeaponData.Weapons[weaponId].AttackType == "Melee"
end

function WeaponData.IsCombatWeapon(weaponId)
	return weaponId ~= nil and WeaponData.Weapons[weaponId] ~= nil
end

return WeaponData
