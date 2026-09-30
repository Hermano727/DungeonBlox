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

local HungerConfig = require(ReplicatedStorage:WaitForChild("HungerConfig"))
local ItemConfig   = require(ReplicatedStorage:WaitForChild("ItemConfig"))
local ArmorEnchantService = require(ServerScriptService:WaitForChild("ArmorEnchantService"))
local CombatEnchantStatus = require(ServerScriptService:WaitForChild("CombatEnchantStatus"))

local DamageService = {}

local _hgr
local function hgr()
	if not _hgr then
		_hgr = require(ServerScriptService:WaitForChild("HungerData"))
	end
	return _hgr
end

-- Server -> client "play this effect sound" hop. Same shape as
-- WorldLootService's pickup sfx: the server fires a KEY from the shared
-- SoundEffects registry and the client resolves it through SfxService, so no
-- asset id is ever hardcoded here and the sound still routes through the
-- player's own Effects volume group. Generic on purpose -- any future
-- server-decided one-shot can reuse this one remote (see SfxNetClient).
local function ensurePlayEffectSfxEvent()
	local ge = ReplicatedStorage:FindFirstChild("GameEvents")
	if not ge then
		ge = Instance.new("Folder")
		ge.Name = "GameEvents"
		ge.Parent = ReplicatedStorage
	end
	local ev = ge:FindFirstChild("PlayEffectSfx")
	if ev and not ev:IsA("RemoteEvent") then
		ev:Destroy()
		ev = nil
	end
	if not ev then
		ev = Instance.new("RemoteEvent")
		ev.Name = "PlayEffectSfx"
		ev.Parent = ge
	end
	return ev
end
local playEffectSfxEvent = ensurePlayEffectSfxEvent()

function DamageService.PlayEffectFor(player, key)
	if not player or not player.Parent or not playEffectSfxEvent then
		return
	end
	playEffectSfxEvent:FireClient(player, key)
end

local _dungeonProfile
local function getDungeonProfile()
	if not _dungeonProfile then
		local mod = ServerScriptService:FindFirstChild("ProfileService")
		if mod then _dungeonProfile = require(mod) end
	end
	return _dungeonProfile
end

local _stats
local function getStats()
	if not _stats then
		_stats = require(ServerScriptService:WaitForChild("StatsService"))
	end
	return _stats
end

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

function DamageService.ComputeHitFinal(rawDamage, armorRating, target, subStats)
	if not rawDamage or rawDamage <= 0 then return 0, {} end
	local effectiveArmor, flags = ArmorEnchantService.Resolve(target, armorRating, subStats)
	return DamageService.ComputeFinal(rawDamage, effectiveArmor), flags
end

-- Weapon substat formula (player → mob damage).
-- roll        = base damage after enchant + armor-substat multiplier
-- subStats    = item.subStats dict (pierce, critical, execute, vsMon, vsPly, elemDmg)
-- hpFrac      = mob.CurrentHealth / mob.MaxHealth  (0-1)
-- targetType  = "Mob" | "Player"
-- Returns damage and resolved bonus metadata for confirmed-hit presentation.
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
	return math.floor(phys + elem), {
		isCrit = isCrit, isExe = isExe, executeBonus = exeMod,
		isPiercing = piercePct > 0 and roll > 0,
		elementalDamage = elem,
	}
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
function DamageService.ApplyToPlayer(player, rawDamage, source, weaponSubStats, isPeriodic)
	if player and player:GetAttribute("MiasmaInvulnerable") == true then return 0 end
	local sourceModel = type(source) == "table" and source.Model
		or (typeof(source) == "Instance" and source:IsA("Player") and source.Character)
	if not isPeriodic and not CombatEnchantStatus.CanHit(sourceModel) then return 0 end
	local pdm = getPDM()
	local profile = pdm and pdm.Get(player)

	-- Block: all-or-nothing, rolled on EVERY incoming hit. The player's total
	-- block % is summed across equipped gear and capped at
	-- ItemConfig.BLOCK_CHANCE_CAP_PCT -- stacking past the cap does nothing,
	-- because an uncapped stack of an all-or-nothing negate trends to immunity.
	-- Rolled before armor: a blocked hit takes zero damage, so nothing below
	-- (hunger, combat timer, armor durability) should run for it either.
	--
	-- `profile` above is the LEGACY PlayerDataManager profile (capitalised
	-- Combat.HP). Equipped gear lives in the MODERN ProfileService profile, so
	-- the block sum has to be read from that one instead -- see the "two profile
	-- systems" table in CLAUDE.md. Passing the legacy profile to
	-- SumEquippedSubStat would silently sum nothing and never block.
	do
		local svc = getDungeonProfile()
		local geared = svc and svc.Get and svc.Get(player)
		if geared then
			local okBlock, sum = pcall(getStats().SumEquippedSubStat, geared, "block")
			local blockPct = (okBlock and type(sum) == "number") and math.clamp(sum, 0, ItemConfig.BLOCK_CHANCE_CAP_PCT) or 0
			if blockPct > 0 and math.random() * 100 < blockPct then
				-- Feedback matters here: a blocked hit is otherwise indistinguishable
				-- from the mob having missed. One of the BlockHit variations plays.
				DamageService.PlayEffectFor(player, "BlockHit")
				return 0
			end
		end
	end

	local armor = profile and profile.Combat and profile.Combat.Armor or 0
	local final, armorHit = DamageService.ComputeHitFinal(rawDamage, armor, player.Character, weaponSubStats)
	if final <= 0 then return 0 end
	pcall(hgr().addExhaustion, player, HungerConfig.EXHAUSTION.DAMAGE_TAKEN)

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

	-- A mob landing a hit is in combat: refreshes a named elite's idle-despawn timer
	-- (MobManager despawns one after NAMED_ELITE_IDLE_DESPAWN seconds out of combat).
	-- Dying to it no longer despawns it: the fight belongs to everyone now.
	if type(source) == "table" and source.Stats then
		source._lastCombatAt = os.clock()
	end

	return final, armorHit
end

-- Status ticks that explicitly bypass armor and block still pass through this
-- health/profile chokepoint so death, HUD mirroring, and combat state remain
-- consistent. Miasma poison is the first caller.
function DamageService.ApplyTrueDamageToPlayer(player, rawDamage, source)
	if player and player:GetAttribute("MiasmaInvulnerable") == true then return 0 end
	local amount = math.max(0, tonumber(rawDamage) or 0)
	if amount <= 0 or not player then return 0 end
	local pdm = getPDM()
	local profile = pdm and pdm.Get(player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return 0 end
	amount = math.min(amount, hum.Health)
	if profile and profile.Combat then
		profile.Combat.HP = math.max(0, profile.Combat.HP - amount)
		hum.Health = profile.Combat.HP
	else
		hum:TakeDamage(amount)
	end
	local cs = getCombatState()
	if cs then cs.OnPlayerDamaged(player) end
	return amount
end

-- Healing is capped by real health lost, not overkill damage or damage before
-- armor. A receipt allows the HUD to distinguish Life Steal from regen/potions.
function DamageService.ApplyLifeSteal(player, damageDealt, percent)
	local char = player and player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or hum.MaxHealth <= 0 then return nil end
	local before = hum.Health
	local amount = math.min(math.max(0, damageDealt or 0) * math.clamp(tonumber(percent) or 0, 0, 100) / 100, math.max(0, hum.MaxHealth - before))
	if amount <= 0 then return nil end
	local after = before + amount
	local pdm = getPDM()
	local profile = pdm and pdm.Get(player)
	if profile then profile.Combat.HP = after end
	hum.Health = after
	return { amount = amount, before = before, after = after, maxHealth = hum.MaxHealth, character = char }
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

	-- Inside a dungeon, combat XP BANKS instead of being awarded per kill,
	-- and is only paid out on a completed run (forfeit on death). The
	-- Progression kill/score counters above still tick immediately -- those
	-- are lifetime stats, not a reward.
	local banked = false
	do
		local ok, DungeonScore = pcall(function()
			return require(ServerScriptService:WaitForChild("DungeonScoreService", 5))
		end)
		if ok and DungeonScore and DungeonScore.IsInRun(player) then
			DungeonScore.AddXP(player, score)
			banked = true
		end
	end

	if not banked then
		local xpEvent = ReplicatedStorage:FindFirstChild("CombatXPEvent")
		if xpEvent then
			xpEvent:FireClient(player, mob.MobID or "Unknown", score, tier)
		end
	end

	pcall(function()
		local qp = ServerScriptService:FindFirstChild("QuestProgressService")
		if qp and qp:IsA("ModuleScript") then
			require(qp).OnMobKilledByPlayer(player, mob.MobID)
		end
	end)
end

return DamageService
