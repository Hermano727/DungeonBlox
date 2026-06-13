local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local WeaponData = require(ReplicatedStorage:WaitForChild("WeaponData"))
local ItemConfig = require(ReplicatedStorage:WaitForChild("ItemConfig"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local EnergyConfig = require(ReplicatedStorage:WaitForChild("EnergyConfig"))
local DamageService = require(ServerScriptService:WaitForChild("DamageService"))

local ARMOR_SLOTS = ItemConfig.ARMOR_SLOTS
local SUBSTAT_WEAPON_MAP = ItemConfig.ARMOR_SUBSTAT_WEAPON_MAP
local SUBSTAT_DMG_PER_200 = ItemConfig.ARMOR_SUBSTAT_DMG_PER_200

local _ed, _dur, _dp
local function ed()  if not _ed  then _ed  = require(ServerScriptService:WaitForChild("EnergyData"))       end return _ed  end
local function dur() if not _dur then _dur = require(ServerScriptService:WaitForChild("DurabilityService")) end return _dur end
local function dp()  if not _dp  then _dp  = require(ServerScriptService:WaitForChild("DungeonProfileService")) end return _dp  end

local function resolveWeaponIdForCombat(player, weaponId)
	if type(weaponId) == "string" and WeaponData.Weapons[weaponId] then
		return weaponId
	end
	local char = player and player.Character
	local tool = char and char:FindFirstChildOfClass("Tool")
	if tool then
		local w = WeaponData.GetWeaponIdFromTool(tool)
		if type(w) == "string" and WeaponData.Weapons[w] then
			return w
		end
	end
	if type(weaponId) == "string" and weaponId ~= "" then
		return weaponId
	end
	return nil
end

local function getHeldWeaponInventoryUuid(player)
	local char = player.Character
	if not char then
		return nil
	end
	local tool = char:FindFirstChildOfClass("Tool")
	if not tool then
		return nil
	end
	local u = tool:GetAttribute("DungeonItemUuid")
	if type(u) ~= "string" or u == "" then
		return nil
	end
	return u
end

local function weaponTypeFromItem(it)
	if type(it) ~= "table" or type(it.tags) ~= "table" then
		return nil
	end
	for _, tag in ipairs(it.tags) do
		if ItemConfig.WEAPON_MULTIPLIERS[tag] then
			return tag
		end
	end
	return nil
end

local function armorSubstatMultiplier(profile, weaponType)
	if not weaponType then return 1.0 end
	local totals = { vit=0, str=0, int=0, dex=0 }
	local equipped = profile.equipped
	local inv = profile.inventory
	if type(equipped) ~= "table" or type(inv) ~= "table" then return 1.0 end
	for _, slot in ipairs(ARMOR_SLOTS) do
		local uuid = equipped[slot]
		if type(uuid) == "string" and uuid ~= "" then
			local it = inv[uuid]
			if type(it) == "table" and type(it.subStats) == "table" then
				for id in pairs(totals) do
					totals[id] = totals[id] + (tonumber(it.subStats[id]) or 0)
				end
			end
		end
	end
	local relevantId
	for id, wt in pairs(SUBSTAT_WEAPON_MAP) do
		if wt == weaponType then relevantId = id; break end
	end
	if not relevantId then return 1.0 end
	local stacks = math.floor(totals[relevantId] / 200)
	return 1.0 + stacks * SUBSTAT_DMG_PER_200
end

local function damageRollFromEquippedWeapon(player, weaponId)
	local profile = dp().Get(player)
	if type(profile) ~= "table" or type(profile.inventory) ~= "table" then
		return nil
	end

	local uuid = getHeldWeaponInventoryUuid(player)
	local it = nil
	if uuid then
		local cand = profile.inventory[uuid]
		if type(cand) == "table" and cand.type == "Weapon" then
			it = cand
		else
			uuid = nil
		end
	end
	if not it then
		if type(profile.equipped) ~= "table" then
			return nil
		end
		uuid = profile.equipped.Weapon
		if type(uuid) ~= "string" or uuid == "" then
			return nil
		end
		it = profile.inventory[uuid]
	end
	if type(it) ~= "table" or it.type ~= "Weapon" then
		return nil
	end

	local subs = it.subStats
	if type(subs) ~= "table" then
		subs = {}
	end
	local lo = math.floor(tonumber(subs.dmgMin) or 0)
	local hi = math.floor(tonumber(subs.dmgMax) or 0)
	if lo < 1 or hi < 1 then
		local def = type(it.itemId) == "string" and ItemDefinitions.Get(it.itemId) or nil
		if def and def.Kind == "Weapon" then
			local wid = (type(def.WeaponId) == "string" and def.WeaponId ~= "") and def.WeaponId or it.itemId
			local st = WeaponData.GetStats(wid)
			local d = math.max(1, math.floor(tonumber(st.Damage) or 1))
			lo, hi = d, d
		elseif type(weaponId) == "string" and WeaponData.Weapons[weaponId] then
			local st = WeaponData.GetStats(weaponId)
			local d = math.max(1, math.floor(tonumber(st.Damage) or 1))
			lo, hi = d, d
		else
			return nil
		end
	end
	if hi < lo then
		hi = lo
	end
	local roll = (lo == hi) and lo or math.random(lo, hi)
	local weaponType = weaponTypeFromItem(it)
	local mult = armorSubstatMultiplier(profile, weaponType)
	local swingMults = EnergyConfig.WEAPON_SWING_MULT or {}
	local swingMult = (weaponType and swingMults[weaponType]) or 1.0
	return math.floor(roll * mult), subs, swingMult
end

local MobCombat = {}

local activeMobs = {}
local processMobDeath = nil
local levelPenaltyThreshold = 5
local damageReductionPerLevel = 0.1
local damageNumberEvent = nil
local meleeGlassEvent = nil

local function ensureMeleeGlassRemote()
	if meleeGlassEvent and meleeGlassEvent.Parent then
		return meleeGlassEvent
	end
	local ge = ReplicatedStorage:FindFirstChild("GameEvents")
	if not ge then
		ge = Instance.new("Folder")
		ge.Name = "GameEvents"
		ge.Parent = ReplicatedStorage
	end
	local ev = ge:FindFirstChild("MeleeHitGlass")
	if not ev or not ev:IsA("RemoteEvent") then
		if ev then
			ev:Destroy()
		end
		ev = Instance.new("RemoteEvent")
		ev.Name = "MeleeHitGlass"
		ev.Parent = ge
	end
	meleeGlassEvent = ev
	return meleeGlassEvent
end

function MobCombat.Initialize(mobTable, deathHandler, config)
    activeMobs = mobTable
    processMobDeath = deathHandler
    damageNumberEvent = ReplicatedStorage:WaitForChild("DamageNumberEvent", 30)
    if not damageNumberEvent then
        warn("[MobCombat] DamageNumberEvent missing; floating damage disabled.")
    end

    if config then
        levelPenaltyThreshold = config.LevelPenaltyThreshold or levelPenaltyThreshold
        damageReductionPerLevel = config.DamageReductionPerLevel or damageReductionPerLevel
    end

	local ge = ReplicatedStorage:FindFirstChild("GameEvents")
	if not ge then
		ge = Instance.new("Folder")
		ge.Name = "GameEvents"
		ge.Parent = ReplicatedStorage
	end
	if not ge:FindFirstChild("MeleeHitGlass") then
		local ev = Instance.new("RemoteEvent")
		ev.Name = "MeleeHitGlass"
		ev.Parent = ge
	end
	meleeGlassEvent = ge:WaitForChild("MeleeHitGlass")
	ensureMeleeGlassRemote()
end

local function calculateDamage(player, mob, baseDamage)
    local playerLevel = player:GetAttribute("Level") or 1
    local mobLevel = mob.Stats.Level
    local levelDiff = mobLevel - playerLevel

    if levelDiff >= levelPenaltyThreshold then
        local reduction = math.min((levelDiff - levelPenaltyThreshold + 1) * damageReductionPerLevel, 0.8)
        baseDamage = baseDamage * (1 - reduction)
    end

    return math.max(math.floor(baseDamage), 0)
end

local function getPlayerRoot(player)
    local character = player.Character
    if not character then
        return nil
    end

    return character:FindFirstChild("HumanoidRootPart")
end

local function applyDamage(player, mob, baseDamage, weaponId, weapSubs, swingMult)
    local hpFrac = (mob.MaxHealth and mob.MaxHealth > 0)
        and (mob.CurrentHealth / mob.MaxHealth) or 1
    local weaponFinal = DamageService.ComputeWeaponFinal(baseDamage, weapSubs, hpFrac, "Mob")
    local finalDamage = calculateDamage(player, mob, weaponFinal)
    if finalDamage <= 0 then
        return false
    end

    -- Snapshot DamageTracker before hit so we can compute the true post-armor delta.
    local beforeDmg = mob.DamageTracker[player.UserId] or 0
    local died = mob:TakeDamage(player, finalDamage)
    local actualDamage = (mob.DamageTracker[player.UserId] or 0) - beforeDmg

    if actualDamage > 0 and damageNumberEvent and mob.Model then
        damageNumberEvent:FireClient(player, actualDamage, mob.Model)
    end

    if died and processMobDeath then
        processMobDeath(mob, player)
    end

	local wid = resolveWeaponIdForCombat(player, weaponId) or weaponId
	local playMeleeGlass = false
	local hitEnergyCost = EnergyConfig.SWING_COST * 0.5
	if finalDamage > 0 and type(wid) == "string" and WeaponData.Weapons[wid] and WeaponData.GetStats(wid).AttackType == "Melee" then
		local d = ed().get(player)
		if d and not d.isBlocked and not d.isPanting and d.energy + 1e-3 >= hitEnergyCost then
			playMeleeGlass = true
		end
	end

    -- Confirmed hit: charge remaining 50% swing energy + degrade weapon
    pcall(ed().chargeHitEnergy, player, swingMult)
    pcall(dur().weaponHit, player)

	if playMeleeGlass then
		local ev = ensureMeleeGlassRemote()
		if ev then
			ev:FireClient(player)
		end
	end

    return true
end

function MobCombat.ApplyWeaponDamage(player, mobUID, weaponId, hitPosition)
    local mob = activeMobs[mobUID]
    if not mob or not mob:IsAlive() then
        return false
    end

	ensureMeleeGlassRemote()

	local dEnergy = ed().get(player)
	if dEnergy and (dEnergy.isPanting or dEnergy.isBlocked) then
		return false
	end

	weaponId = resolveWeaponIdForCombat(player, weaponId)

    local stats = WeaponData.GetStats(weaponId or "Unarmed")
    local playerRoot = getPlayerRoot(player)
    if not playerRoot then
        return false
    end

    local mobPosition = mob:GetPosition()
    if not mobPosition then
        return false
    end

    local playerDistance = (playerRoot.Position - mobPosition).Magnitude
    if playerDistance > stats.MaxRange then
        return false
    end

    if hitPosition and (hitPosition - mobPosition).Magnitude > stats.MaxRange + 5 then
        return false
    end

    local base, weapSubs, swingMult = damageRollFromEquippedWeapon(player, weaponId)
    if base == nil then
        base = stats.Damage
    end
    local hit = applyDamage(player, mob, base, weaponId, weapSubs or {}, swingMult or 1)
    if hit and mob:IsAlive() then
        mob:ApplyKnockback(playerRoot.Position)
    end
    return hit
end

-- Player-vs-player damage path. Mirrors ApplyWeaponDamage but targets a Player
-- instead of a Mob. The alignment gate is owned by DungeonProfileService.CanPvP
-- so Lawful players can neither hit nor be hit. Reuses the same weapon roll,
-- substat curve, energy gate, and durability hooks as PvE so balance is shared.
local _dpsPvP
local function getDPSForPvP()
	if not _dpsPvP then
		_dpsPvP = require(ServerScriptService:WaitForChild("DungeonProfileService"))
	end
	return _dpsPvP
end

-- Lazy require for ZoneService so MobCombat doesn't form a boot-time cycle
-- through it. ZoneService itself lazily requires DungeonProfileService.
local _zoneSvc
local function getZoneSvc()
	if not _zoneSvc then
		local mod = ServerScriptService:FindFirstChild("ZoneService")
		if mod then _zoneSvc = require(mod) end
	end
	return _zoneSvc
end

function MobCombat.ApplyPvPDamage(attacker, target, weaponId, hitPosition)
	if not attacker or not target or attacker == target then
		return false
	end

	-- Alignment gate: Lawful on either side blocks. Same-player blocked above.
	if not getDPSForPvP().CanPvP(attacker, target) then
		return false
	end

	-- Zone gate (most-restrictive wins): if EITHER player is currently standing
	-- inside any Lawful zone, all PvP is suppressed regardless of player
	-- alignments. This is checked after the alignment gate so the cheap path
	-- (Lawful player) still short-circuits without touching ZoneService.
	local zs = getZoneSvc()
	if zs and (zs.IsAnyZoneLawfulAtPlayer(attacker) or zs.IsAnyZoneLawfulAtPlayer(target)) then
		return false
	end

	local attChar = attacker.Character
	local tgtChar = target.Character
	if not attChar or not tgtChar then return false end

	local attRoot = attChar:FindFirstChild("HumanoidRootPart")
	local tgtRoot = tgtChar:FindFirstChild("HumanoidRootPart")
	if not attRoot or not tgtRoot then return false end

	local tgtHum = tgtChar:FindFirstChildOfClass("Humanoid")
	if not tgtHum or tgtHum.Health <= 0 then return false end

	ensureMeleeGlassRemote()

	-- Reuse the PvE energy gate so panting/blocking also stops PvP swings.
	local dEnergy = ed().get(attacker)
	if dEnergy and (dEnergy.isPanting or dEnergy.isBlocked) then
		return false
	end

	weaponId = resolveWeaponIdForCombat(attacker, weaponId)
	local stats = WeaponData.GetStats(weaponId or "Unarmed")

	-- Distance check (server-authoritative). +4 stud lag tolerance.
	local dist = (attRoot.Position - tgtRoot.Position).Magnitude
	if dist > (stats.MaxRange or 8) + 4 then return false end
	if hitPosition and (hitPosition - tgtRoot.Position).Magnitude > (stats.MaxRange or 8) + 5 then
		return false
	end

	local base, weapSubs = damageRollFromEquippedWeapon(attacker, weaponId)
	if base == nil then base = stats.Damage end

	local maxHP = (tgtHum.MaxHealth and tgtHum.MaxHealth > 0) and tgtHum.MaxHealth or 100
	local hpFrac = math.clamp(tgtHum.Health / maxHP, 0, 1)
	local weaponFinal = DamageService.ComputeWeaponFinal(base, weapSubs or {}, hpFrac, "Player")
	if weaponFinal <= 0 then return false end

	local applied = DamageService.ApplyToPlayer(target, weaponFinal, attacker)
	if applied and applied > 0 then
		if damageNumberEvent then
			damageNumberEvent:FireClient(attacker, applied, tgtChar)
		end

		-- Confirmed-hit energy + weapon durability tick, same as PvE.
		pcall(ed().chargeHitEnergy, attacker)
		pcall(dur().weaponHit, attacker)

		-- Melee glass SFX, mirroring PvE rules.
		if type(weaponId) == "string"
			and WeaponData.Weapons[weaponId]
			and WeaponData.GetStats(weaponId).AttackType == "Melee" then
			local d = ed().get(attacker)
			if d and not d.isBlocked and not d.isPanting then
				local ev = ensureMeleeGlassRemote()
				if ev then ev:FireClient(attacker) end
			end
		end
		return true
	end

	return false
end

function MobCombat.ApplyWeaponDamageInRadius(player, center, weaponId)
	ensureMeleeGlassRemote()
	weaponId = resolveWeaponIdForCombat(player, weaponId)

	local dEnergy = ed().get(player)
	if dEnergy and (dEnergy.isPanting or dEnergy.isBlocked) then
		return false
	end

    local stats = WeaponData.GetStats(weaponId or "Unarmed")
    local blastRadius = stats.BlastRadius or stats.MaxRange
    local playerRoot = getPlayerRoot(player)
    if not playerRoot then
        return false
    end

    if (playerRoot.Position - center).Magnitude > stats.MaxRange then
        return false
    end

    local base, weapSubs, swingMult = damageRollFromEquippedWeapon(player, weaponId)
    if base == nil then
        base = stats.Damage
    end

    local damagedAny = false
    for mobUID, mob in pairs(activeMobs) do
        if mob:IsAlive() then
            local mobPosition = mob:GetPosition()
            if mobPosition and (mobPosition - center).Magnitude <= blastRadius then
                if applyDamage(player, mob, base, weaponId, weapSubs or {}, swingMult or 1) then
                    damagedAny = true
                    if mob:IsAlive() then
                        mob:ApplyKnockback(playerRoot.Position)
                    end
                end
            end
        end
    end

    return damagedAny
end

return MobCombat
