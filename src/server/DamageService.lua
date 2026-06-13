-- DamageService
-- The single chokepoint for the armor damage curve and player-side damage
-- application. The existing CombatService Script is an energy/swing gate;
-- this module is where the math lives.
--
-- Curve: final = raw * 100 / (100 + armor)
--   armor=0    -> 100% damage taken
--   armor=100  -> 50%
--   armor=200  -> 33%
--   armor=500  -> ~16.6%
-- Asymptotic, never reaches 0, so armor never grants full invuln.
--
-- "Armor" everywhere in this codebase is an additive RATING, not a percent.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DamageService = {}

local _css
local function getCombatState()
	if not _css then
		local m = ServerScriptService:FindFirstChild("CombatStateService")
		if m then _css = require(m) end
	end
	return _css
end

function DamageService.ComputeFinal(rawDamage, armorRating)
	local armor = math.max(0, armorRating or 0)
	if rawDamage == nil or rawDamage <= 0 then return 0 end
	return rawDamage * (100 / (100 + armor))
end

-- Weapon substat formula (player → mob damage).
-- roll        = base damage after enchant + armor-substat multiplier
-- subStats    = item.subStats dict (pierce, critical, execute, vsMon, vsPly, elemDmg)
-- hpFrac      = mob.CurrentHealth / mob.MaxHealth  (0-1)
-- targetType  = "Mob" | "Player"
-- Returns: finalDamage (integer), flags { isCrit, isExe }
function DamageService.ComputeWeaponFinal(roll, subStats, hpFrac, targetType)
	local subs = subStats or {}

	local piercePct = (tonumber(subs.pierce)   or 0) / 100
	local base      = roll * (1 + piercePct)

	local isCrit  = math.random() < ((tonumber(subs.critical) or 0) / 100)
	local critMod = isCrit and (base * 0.5) or 0

	local isExe       = math.random() < ((tonumber(subs.execute) or 0) / 100)
	local missingFrac = math.clamp(1 - math.clamp(hpFrac or 1, 0, 1), 0, 1)
	local exeMod      = isExe and (base * (missingFrac * 0.25)) or 0

	local phys = base + critMod + exeMod
	if targetType == "Mob" then
		phys = phys * (1 + (tonumber(subs.vsMon) or 0) / 100)
	elseif targetType == "Player" then
		phys = phys * (1 + (tonumber(subs.vsPly) or 0) / 100)
	end

	local elem = tonumber(subs.elemDmg) or 0
	return math.floor(phys + elem), { isCrit = isCrit, isExe = isExe }
end

-- Resolve the lazy require for PlayerDataManager so this module can be required
-- before the manager exists during boot.
local _pdm
local function getPDM()
	if not _pdm then
		local mod = ServerScriptService:FindFirstChild("PlayerDataManager")
		if mod then _pdm = require(mod) end
	end
	return _pdm
end

-- Apply damage to a Player. Reads armor rating from the player's session
-- profile. Mirrors HP to the Humanoid so existing death systems keep working.
function DamageService.ApplyToPlayer(player, rawDamage, source)
	local pdm = getPDM()
	local profile = pdm and pdm.Get(player)
	local armor = profile and profile.Combat and profile.Combat.Armor or 0
	local final = DamageService.ComputeFinal(rawDamage, armor)
	if final <= 0 then return 0 end

	if profile then
		profile.Combat.HP = math.max(0, profile.Combat.HP - final)
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Health = profile.Combat.HP
		end
	else
		-- No profile loaded yet (very early in join). Fall back to Humanoid.
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum:TakeDamage(final)
		end
	end
	-- Notify combat timer on every hit
	local cs = getCombatState()
	if cs then cs.OnPlayerDamaged(player) end

	-- Degrade equipped armor on every mob hit
	pcall(function()
		local DurSvc = require(ServerScriptService:WaitForChild("DurabilityService"))
		DurSvc.armorHit(player)
	end)

	return final
end

-- Tier-aware kill award. MobClass.Die already returns DamageTracker; the
-- spawner / manager can call this for the killing-blow player. Tier comes
-- straight off the mob (set during MobClass.new from MobData).
function DamageService.AwardKill(player, mob)
	local pdm = getPDM()
	local profile = pdm and pdm.Get(player)
	if not profile then return end
	local tier = math.clamp(mob.Tier or 1, 1, 5)
	local killsKey = "Tier" .. tier .. "Kills"
	local scoreKey = "Tier" .. tier .. "Score"
	local score = (mob.Stats and mob.Stats.BaseScore) or 0
	profile.Progression[killsKey] = (profile.Progression[killsKey] or 0) + 1
	profile.Progression[scoreKey] = (profile.Progression[scoreKey] or 0) + score

	local xpEvent = ReplicatedStorage:FindFirstChild("CombatXPEvent")
	if xpEvent then
		xpEvent:FireClient(player, mob.MobID or "Unknown", score, tier)
	end

	pcall(function()
		local qp = ServerScriptService:FindFirstChild("QuestProgressService")
		if qp and qp:IsA("ModuleScript") then
			require(qp).OnMobKilledByPlayer(player, mob.MobID)
		end
	end)
end

return DamageService
