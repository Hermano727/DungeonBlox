local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local WeaponData = require(ReplicatedStorage:WaitForChild("WeaponData"))
local ItemConfig = require(ReplicatedStorage:WaitForChild("ItemConfig"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local EnergyConfig = require(ReplicatedStorage:WaitForChild("EnergyConfig"))
local CombatAnimConfig = require(ReplicatedStorage:WaitForChild("CombatAnimConfig"))
local DamageService = require(ServerScriptService:WaitForChild("DamageService"))
local EnchantHitFeedback = require(ServerScriptService:WaitForChild("EnchantHitFeedback"))
local EnchantStatus = require(ServerScriptService:WaitForChild("CombatEnchantStatus"))
local EnchantConfig = require(ReplicatedStorage:WaitForChild("CombatEnchantConfig"))
local DamageNumberStyles = require(ReplicatedStorage:WaitForChild("DamageNumberStyles"))

-- Server-side counterpart to CombatClient's rayDistanceIntoModelBounds: is
-- `position` (the client's claimed hitPosition) actually inside `model`'s
-- own real bounding box, expanded by `margin` studs? Same slab test, just
-- a point-in-box check instead of a ray-vs-box check since we only have the
-- claimed impact point here, not the original ray. This is what makes
-- ApplyWeaponDamage/ApplyPvPDamage validate against the target's actual
-- geometry instead of a flat radius-from-center -- a small mob's real bounds
-- reject a claimed hit floating well above its body (e.g. at a healthbar's
-- position) even though it'd pass a generic "within weapon range" check.
local function isPositionWithinModelBounds(model, position, margin)
	if not model or not position then
		return false
	end
	local ok, boxCf, size = pcall(function() return model:GetBoundingBox() end)
	if not ok or not boxCf or not size then
		return false
	end
	local half = (size * 0.5) + Vector3.new(margin, margin, margin)
	local local_ = boxCf:PointToObjectSpace(position)
	return math.abs(local_.X) <= half.X
		and math.abs(local_.Y) <= half.Y
		and math.abs(local_.Z) <= half.Z
end

local ARMOR_SLOTS = ItemConfig.ARMOR_SLOTS
local SUBSTAT_WEAPON_MAP = ItemConfig.ARMOR_SUBSTAT_WEAPON_MAP
local SUBSTAT_DMG_PER_200 = ItemConfig.ARMOR_SUBSTAT_DMG_PER_200

local _ed, _dur, _dp
local function ed()  if not _ed  then _ed  = require(ServerScriptService:WaitForChild("EnergyData"))       end return _ed  end
local function dur() if not _dur then _dur = require(ServerScriptService:WaitForChild("DurabilityService")) end return _dur end
local function dp()  if not _dp  then _dp  = require(ServerScriptService:WaitForChild("ProfileService")) end return _dp  end

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

	-- Weapons have no equip-panel slot (Minecraft-style hotbar model): the held Tool's
	-- DungeonItemUuid attribute is the only source of truth for "currently wielded weapon".
	local uuid = getHeldWeaponInventoryUuid(player)
	local it = nil
	if uuid then
		local cand = profile.inventory[uuid]
		if type(cand) == "table" and cand.type == "Weapon" then
			it = cand
		end
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
local MAX_LEVEL_DAMAGE_REDUCTION = 0.5 -- hard ceiling; 10 or more levels behind still deals half
local damageNumberEvent = nil
local meleeGlassEvent = nil
local mobHitFlashEvent = nil

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

-- Broadcast (not per-attacker) -- unlike damageNumberEvent/meleeGlassEvent,
-- which are feedback for the player who swung, a mob flashing white is part
-- of the mob's own on-screen state: every player currently looking at it
-- should see the same flash at the same moment, not just whoever landed the
-- hit. See MobHitFlashClient for the client-side effect this drives.
local function ensureMobHitFlashRemote()
	if mobHitFlashEvent and mobHitFlashEvent.Parent then
		return mobHitFlashEvent
	end
	local ge = ReplicatedStorage:FindFirstChild("GameEvents")
	if not ge then
		ge = Instance.new("Folder")
		ge.Name = "GameEvents"
		ge.Parent = ReplicatedStorage
	end
	local ev = ge:FindFirstChild("MobHitFlash")
	if not ev or not ev:IsA("RemoteEvent") then
		if ev then
			ev:Destroy()
		end
		ev = Instance.new("RemoteEvent")
		ev.Name = "MobHitFlash"
		ev.Parent = ge
	end
	mobHitFlashEvent = ev
	return mobHitFlashEvent
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
	ensureMobHitFlashRemote()
end

local function calculateDamage(player, mob, baseDamage)
    local playerLevel = player:GetAttribute("Level") or 1
    local mobLevel = mob.Stats.Level
    local levelDiff = mobLevel - playerLevel

    if levelDiff >= levelPenaltyThreshold then
        -- Ramp: 10% at 5 levels behind, +10% per level after, HARD CAP 50%.
        -- Was capped at 80%, which meant a level-1 player hitting a level-21
        -- boss dealt only 20% of weapon damage -- and because the raw formula
        -- wanted 160%, every level from 16 downward felt identical. A 50% cap
        -- keeps the penalty meaningful without making under-levelled content
        -- a wall.
        local reduction = math.min((levelDiff - levelPenaltyThreshold + 1) * damageReductionPerLevel, MAX_LEVEL_DAMAGE_REDUCTION)
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

local function applyDamage(player, mob, baseDamage, weaponId, weapSubs, swingMult, hitPosition)
    if not EnchantStatus.CanHit(player.Character) then return false end
    local hpFrac = (mob.MaxHealth and mob.MaxHealth > 0)
        and (mob.CurrentHealth / mob.MaxHealth) or 1
    local weaponFinal, hitInfo = DamageService.ComputeWeaponFinal(baseDamage, weapSubs, hpFrac, "Mob")
    local isCrit = hitInfo and hitInfo.isCrit or false
    -- A "special" hit -- crit today, an on-hit enchant proc later -- plays its
    -- own dedicated sound client-side, so it should suppress the mob's own
    -- base hit noise (below) rather than layering both. When enchant procs
    -- are implemented, OR their own trigger flag into this same line; don't
    -- touch mob:GetHitSoundId() itself, that's still the per-mob base-sound
    -- lookup, just gated on whether anything "special" happened this hit.
    local specialHitSoundOccurred = isCrit
    local finalDamage = calculateDamage(player, mob, weaponFinal)
    if finalDamage <= 0 then
        return false
    end

    -- Snapshot DamageTracker (and the Model reference) before hit -- a kill
    -- makes mob:TakeDamage() call Die() synchronously, which nils out
    -- mob.Model before this function gets control back. Reading mob.Model
    -- AFTER TakeDamage silently drops the damage number on every one-shot kill.
    local beforeDmg = mob.DamageTracker[player.UserId] or 0
    local mobModel = mob.Model
    local mobMaxHealth = mob.MaxHealth
    local beforeHealth = mob.CurrentHealth
    local feedback = EnchantHitFeedback.Snapshot(mobModel, getPlayerRoot(player), hitPosition)
    local died, armorHit = mob:TakeDamage(player, finalDamage, weapSubs)
    local actualDamage = (mob.DamageTracker[player.UserId] or 0) - beforeDmg

    local extras = {}
    if actualDamage > 0 then
        weapSubs = weapSubs or {}
        if mob:IsAlive() then
            extras = EnchantStatus.Apply(mobModel, weapSubs, function(rawTick)
                if not player.Parent or not mob:IsAlive() or mob.Model ~= mobModel then return false end
                local oldDamage = mob.DamageTracker[player.UserId] or 0
                local tickFeedback = EnchantHitFeedback.Snapshot(mobModel, getPlayerRoot(player))
                local killed = mob:TakeDamage(player, rawTick)
                local dealt = (mob.DamageTracker[player.UserId] or 0) - oldDamage
                if dealt > 0 and damageNumberEvent then
                    if tickFeedback then tickFeedback.effects = { Bleeding = true } end
                    -- Bleed ticks are the only damage the player didn't just
                    -- swing for, so they get their own colour. The main hit that
                    -- APPLIED this bleed also carries effects.Bleeding, which is
                    -- why the source can't be inferred client-side.
                    damageNumberEvent:FireClient(player, dealt, mobModel, mobMaxHealth, false, tickFeedback, DamageNumberStyles.Sources.Bleed)
                end
                if killed and processMobDeath then processMobDeath(mob, player) end
                return not killed
            -- Elemental damage chills: its own flat slow chance, same status.
            end, { elementalHit = (hitInfo.elementalDamage or 0) > 0, hitDamage = actualDamage })
        end
        extras.Glowing = (tonumber(weapSubs.glowing) or 0) > 0
        if feedback then feedback.lifeSteal = DamageService.ApplyLifeSteal(player, math.min(actualDamage, beforeHealth), weapSubs.lifesteal) end
        if EnchantStatus.Roll(weapSubs.cleave) then
            local origin = feedback and feedback.position or mobModel:GetPivot().Position
            local candidates = {}
            for _, other in pairs(activeMobs) do
                local position = other ~= mob and other:IsAlive() and other:GetPosition()
                if position and (position - origin).Magnitude <= EnchantConfig.CleaveRadius then
                    table.insert(candidates, { mob = other, distance = (position - origin).Magnitude })
                end
            end
            table.sort(candidates, function(a, b) return a.distance < b.distance end)
            local count = 0
            for _, entry in ipairs(candidates) do
                if count >= EnchantConfig.CleaveMaxTargets then break end
                local other = entry.mob
                local model = other.Model
                local filter = RaycastParams.new()
                filter.FilterType = Enum.RaycastFilterType.Exclude
                filter.FilterDescendantsInstances = { player.Character, mobModel }
                filter.RespectCanCollide = true
                local obstruction = workspace:Raycast(origin, other:GetPosition() - origin, filter)
                if obstruction and not obstruction.Instance:IsDescendantOf(model) then continue end
                local oldDamage = other.DamageTracker[player.UserId] or 0
                local splash = EnchantHitFeedback.Snapshot(model, getPlayerRoot(player))
                local killed = other:TakeDamage(player, calculateDamage(player, other, weaponFinal * EnchantConfig.CleaveDamageFraction))
                local dealt = (other.DamageTracker[player.UserId] or 0) - oldDamage
                if dealt > 0 then
                    count += 1
                    if splash then splash.effects = { Cleave = true } end
                    if damageNumberEvent then damageNumberEvent:FireClient(player, dealt, model, other.MaxHealth, false, splash) end
                end
                if killed and processMobDeath then processMobDeath(other, player) end
            end
            extras.Cleave = count > 0
        end
    end

    if actualDamage > 0 and damageNumberEvent and mobModel then
        if feedback then feedback.effects = EnchantHitFeedback.Select(hitInfo, armorHit, extras) end
        damageNumberEvent:FireClient(player, actualDamage, mobModel, mobMaxHealth, isCrit, feedback)
    end

    -- Hit-flash: fires the instant a real hit is confirmed (same gate as the
    -- damage number above -- actualDamage > 0, i.e. TakeDamage actually took
    -- effect, not just "a swing was reported"), so it never lags behind the
    -- number or plays for a hit the server rejected. Broadcast to everyone,
    -- not just the attacker -- see ensureMobHitFlashRemote.
    if actualDamage > 0 and mobModel then
        local ev = ensureMobHitFlashRemote()
        if ev then
            ev:FireAllClients(mobModel)
        end
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

	if playMeleeGlass and not specialHitSoundOccurred then
		local ev = ensureMeleeGlassRemote()
		if ev then
			-- Per-mob-type hit sfx: base MobClass:GetHitSoundId() returns the
			-- shared default (the "glass" clip this event was originally
			-- built for); a MobClassRegistry subclass like SkeletonMobClass
			-- overrides it to return something else. The event/instance
			-- names below are historical (kept as MeleeHitGlass rather than
			-- renamed) but the id sent is resolved per-mob now.
			local soundId = mob.GetHitSoundId and mob:GetHitSoundId() or nil
			ev:FireClient(player, soundId)
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

    -- Coarse early-out only: a cheap sanity check so we don't bother with the
    -- real bounding-box test below for a claim that's wildly out of range.
    -- Range is measured surface-to-surface, not centre-to-centre: a big mob
    -- credits its own horizontal half-extent so the player can hit its body
    -- rather than having to reach its HumanoidRootPart. No-op for small mobs
    -- (GetHitRadius returns 0 below ~3 studs of half-extent).
    local mobRadius = (mob.GetHitRadius and mob:GetHitRadius()) or 0
    local forgiveness = CombatAnimConfig.SERVER_HIT_FORGIVENESS_STUDS or 3
    local coarseRange = stats.MaxRange + mobRadius + forgiveness

    local playerDistance = (playerRoot.Position - mobPosition).Magnitude
    if playerDistance > coarseRange then
        return false
    end

    -- The actual gate: does the claimed hitPosition land inside this mob's
    -- OWN real bounding box (plus a small latency-forgiveness margin)? This
    -- is what stops a swing aimed well above a small mob's body (e.g. at its
    -- floating healthbar) from landing just because the player was standing
    -- close enough -- the old check only measured distance to mob center,
    -- never the mob's actual shape.
    if not isPositionWithinModelBounds(mob.Model, hitPosition, forgiveness) then
        return false
    end

    local base, weapSubs, swingMult = damageRollFromEquippedWeapon(player, weaponId)
    if base == nil then
        base = stats.Damage
    end
    local hit = applyDamage(player, mob, base, weaponId, weapSubs or {}, swingMult or 1, hitPosition)
    if hit and mob:IsAlive() then
        mob:ApplyKnockback(playerRoot.Position)
    end
    return hit
end

-- Player-vs-player damage path. Mirrors ApplyWeaponDamage but targets a Player
-- instead of a Mob. The alignment gate is owned by ProfileService.CanPvP
-- so Lawful players can neither hit nor be hit. Reuses the same weapon roll,
-- substat curve, energy gate, and durability hooks as PvE so balance is shared.
local _dpsPvP
local function getDPSForPvP()
	if not _dpsPvP then
		_dpsPvP = require(ServerScriptService:WaitForChild("ProfileService"))
	end
	return _dpsPvP
end

-- Lazy require for ZoneService so MobCombat doesn't form a boot-time cycle
-- through it. ZoneService itself lazily requires ProfileService.
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

	-- Coarse early-out (server-authoritative), same pattern as the PvE path:
	-- cheap distance sanity check first, then the real gate is whether the
	-- claimed hitPosition actually lands inside the target's own bounding
	-- box, not just "somewhere near them."
	local forgiveness = CombatAnimConfig.SERVER_HIT_FORGIVENESS_STUDS or 3
	local dist = (attRoot.Position - tgtRoot.Position).Magnitude
	if dist > (stats.MaxRange or 8) + forgiveness then return false end
	if not isPositionWithinModelBounds(tgtChar, hitPosition, forgiveness) then
		return false
	end

	local base, weapSubs = damageRollFromEquippedWeapon(attacker, weaponId)
	if base == nil then base = stats.Damage end

	local maxHP = (tgtHum.MaxHealth and tgtHum.MaxHealth > 0) and tgtHum.MaxHealth or 100
	local hpFrac = math.clamp(tgtHum.Health / maxHP, 0, 1)
	local weaponFinal, hitInfo = DamageService.ComputeWeaponFinal(base, weapSubs or {}, hpFrac, "Player")
	local isCrit = hitInfo and hitInfo.isCrit or false
	-- Same suppression rule as the PvE path in applyDamage: a crit (or, later,
	-- an on-hit enchant proc) plays its own sound and should mute the base
	-- melee-glass noise instead of layering both.
	local specialHitSoundOccurred = isCrit
	if weaponFinal <= 0 then return false end

	local feedback = EnchantHitFeedback.Snapshot(tgtChar, attRoot, hitPosition)
	local beforeHealth = tgtHum.Health
	local applied, armorHit = DamageService.ApplyToPlayer(target, weaponFinal, attacker, weapSubs)
	if applied and applied > 0 then
		weapSubs = weapSubs or {}
		local extras = {}
		if tgtHum.Health > 0 then
			extras = EnchantStatus.Apply(tgtChar, weapSubs, function(rawTick)
				if not attacker.Parent or not target.Parent or target.Character ~= tgtChar or tgtHum.Health <= 0 then return false end
				if not getDPSForPvP().CanPvP(attacker, target) then return false end
				local zones = getZoneSvc()
				if zones and (zones.IsAnyZoneLawfulAtPlayer(attacker) or zones.IsAnyZoneLawfulAtPlayer(target)) then return false end
				local tickFeedback = EnchantHitFeedback.Snapshot(tgtChar, getPlayerRoot(attacker))
				local dealt = DamageService.ApplyToPlayer(target, rawTick, attacker, nil, true)
				if dealt > 0 and damageNumberEvent then
					if tickFeedback then tickFeedback.effects = { Bleeding = true } end
					-- Same as the PvE tick above: colour comes from the server.
					damageNumberEvent:FireClient(attacker, dealt, tgtChar, maxHP, false, tickFeedback, DamageNumberStyles.Sources.Bleed)
				end
				return tgtHum.Health > 0
			-- Elemental damage chills: its own flat slow chance, same status.
			end, { elementalHit = (hitInfo.elementalDamage or 0) > 0, hitDamage = applied })
		end
		extras.Glowing = (tonumber(weapSubs.glowing) or 0) > 0
		if feedback then feedback.lifeSteal = DamageService.ApplyLifeSteal(attacker, math.min(applied, beforeHealth), weapSubs.lifesteal) end
		if EnchantStatus.Roll(weapSubs.cleave) then
			local candidates = {}
			local origin = feedback and feedback.position or tgtRoot.Position
			for _, other in ipairs(game:GetService("Players"):GetPlayers()) do
				local root = other ~= attacker and other ~= target and getPlayerRoot(other)
				if root and (root.Position - origin).Magnitude <= EnchantConfig.CleaveRadius then
					table.insert(candidates, { player = other, root = root, distance = (root.Position - origin).Magnitude })
				end
			end
			table.sort(candidates, function(a,b) return a.distance < b.distance end)
			local count = 0
			for _, entry in ipairs(candidates) do
				if count >= EnchantConfig.CleaveMaxTargets then break end
				local other, root = entry.player, entry.root
				local char = other.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if not hum or hum.Health <= 0 or not getDPSForPvP().CanPvP(attacker, other) then continue end
				local zones = getZoneSvc()
				if zones and (zones.IsAnyZoneLawfulAtPlayer(attacker) or zones.IsAnyZoneLawfulAtPlayer(other)) then continue end
				local filter = RaycastParams.new()
				filter.FilterType = Enum.RaycastFilterType.Exclude
				filter.FilterDescendantsInstances = { attChar, tgtChar }
				filter.RespectCanCollide = true
				local obstruction = workspace:Raycast(origin, root.Position - origin, filter)
				if obstruction and not obstruction.Instance:IsDescendantOf(char) then continue end
				local splash = EnchantHitFeedback.Snapshot(char, attRoot)
				local dealt = DamageService.ApplyToPlayer(other, weaponFinal * EnchantConfig.CleaveDamageFraction, attacker, nil, true)
				if dealt > 0 then
					count += 1
					if splash then splash.effects = { Cleave = true } end
					if damageNumberEvent then damageNumberEvent:FireClient(attacker, dealt, char, hum.MaxHealth, false, splash) end
				end
			end
			extras.Cleave = count > 0
		end
		if damageNumberEvent then
			if feedback then feedback.effects = EnchantHitFeedback.Select(hitInfo, armorHit, extras) end
			damageNumberEvent:FireClient(attacker, applied, tgtChar, maxHP, isCrit, feedback)
		end

		-- Confirmed-hit energy + weapon durability tick, same as PvE.
		pcall(ed().chargeHitEnergy, attacker)
		pcall(dur().weaponHit, attacker)

		-- Melee glass SFX, mirroring PvE rules (including the crit/special-hit
		-- suppression -- see specialHitSoundOccurred above).
		if not specialHitSoundOccurred
			and type(weaponId) == "string"
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
