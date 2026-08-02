--  WeaponData
--  Combat stats keyed by WeaponId (referenced from ItemDefinitions.WeaponId).
--  NAMING CONVENTION (see .claude/CLAUDE.md "Asset & naming conventions")
--  The game is 5-tier. Names must encode tier, never vague adjectives.
--    New ids:  T1_Sword, T2_Helm, T1_Bow   (PascalCase after the tier prefix)
--    Never as a code-facing id: "Low tier", "Basic", "Starter" -- those are
--    display words. DisplayName is the only place human phrasing belongs.
--    No snake_case or spaces. Low_tier_sword / "Wood Sword" / "Gravity Coil"
--    are legacy: leave them, do not imitate them.
--
--  Legacy ids are FROZEN. Keys here are itemIds persisted in PlayerProfile_v1;
--  renaming one orphans every saved item using it. Convention applies to new
--  entries only. Renaming an existing id needs an alias map applied on profile
--  load.
--
--  SINGLE AUTHORITY: WeaponData.Weapons
--  Every consumer reads this flat table via WeaponData.GetStats(weaponId)
--  (CombatClient, MobCombat, BowServer, DungeonProfileService,
--  StarterCharacterScripts/LocalScript). Add weapons HERE and nowhere else.
--
--  Per-weapon child ModuleScripts (WeaponData.<Name>) were an abandoned
--  refactor: nothing ever required them, their SwingEnergy/SwingCooldown/Range
--  fields had zero readers, and they disagreed with this table. Deleted
--  2026-07. Do not reintroduce that shape without also writing a loader and
--  migrating every call site.
--
--  Fields: Damage, MaxRange (studs), AttackType ("Melee" | "Projectile"),
--          ProjectileSpeed (projectile only).

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
	AdminSword = {
		Damage     = 999,
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
