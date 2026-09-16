--[[
    LootService
    Handles item drops when mobs die.
    Called by MobManager.ProcessMobDeath after kill credit is awarded.

    Drop flow:
      1. Roll against TIER_DROP_CHANCE (+ elite bonus if applicable)
      2. Roll rarity from TIER_RARITY_WEIGHTS for the mob's tier
      3. Generate item via ItemGenerator at mob level + tier
      4. Spawn a visible world pickup orb (press E to collect)
      5. On pickup, grant to the killing player and show the HUD banner

    Private loot model: only the killing blow player can pick up their drops.
]]

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config         = require(ReplicatedStorage:WaitForChild("ItemConfig"))
local Types          = require(ReplicatedStorage:WaitForChild("ProfileTypes"))
local ItemGenerator  = require(ServerScriptService:WaitForChild("ItemGenerator"))
local DungeonProfile = require(ServerScriptService:WaitForChild("ProfileService"))
local BuffService    = require(ServerScriptService:WaitForChild("BuffService"))
local PartyService   = require(ServerScriptService:WaitForChild("PartyService"))
local WorldLoot      = require(ServerScriptService:WaitForChild("WorldLootService"))

local Players = game:GetService("Players")

local LootService = {}

-- Sum coinFind % across all equipped armor slots for a player.
-- Pulled from the shared ItemConfig.ARMOR_SLOTS list (also used by DurabilityService
-- and ItemConfig itself) instead of a locally hardcoded copy, so adding/removing an
-- armor slot in the future only means editing ItemConfig.
local ARMOR_SLOTS_CHECK = Config.ARMOR_SLOTS
local function getTotalCoinFind(player)
	local profile = DungeonProfile.Load(player)
	if not profile or type(profile.equipped) ~= "table" or type(profile.inventory) ~= "table" then
		return 0
	end
	local total = 0
	for _, slot in ipairs(ARMOR_SLOTS_CHECK) do
		local uuid = profile.equipped[slot]
		if type(uuid) == "string" and uuid ~= "" then
			local item = profile.inventory[uuid]
			if type(item) == "table" and type(item.subStats) == "table" then
				total = total + (tonumber(item.subStats.coinFind) or 0)
			end
		end
	end
	return total
end

-- Create the client notification event (ensure GameEvents folder exists for load order)
local function ensureGameEventsFolder()
	local f = ReplicatedStorage:FindFirstChild("GameEvents")
	if f and f:IsA("Folder") then
		return f
	end
	if f then
		f:Destroy()
	end
	f = Instance.new("Folder")
	f.Name = "GameEvents"
	f.Parent = ReplicatedStorage
	return f
end

local gameEventsFolder = ensureGameEventsFolder()
local ItemDropNotify = gameEventsFolder:FindFirstChild("ItemDropNotify")
if ItemDropNotify and not ItemDropNotify:IsA("RemoteEvent") then
	ItemDropNotify:Destroy()
	ItemDropNotify = nil
end
if not ItemDropNotify then
	ItemDropNotify = Instance.new("RemoteEvent")
	ItemDropNotify.Name = "ItemDropNotify"
	ItemDropNotify.Parent = gameEventsFolder
end

print("[LootService] ready")

------------------------------------------------------------------------
-- Internal: pick a rarity using the tier-specific weight table.
-- isElite shifts the effective rarity tier up by ELITE_RARITY_TIER_BOOST.
------------------------------------------------------------------------
local RARITY_ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }

-- Key fragment drop chances per mob tier (independent of gear drop roll)
local KEY_FRAG_CHANCES = { 1/10, 1/15, 1/20, 1/25, 1/30 }
local KEY_FRAG_IDS     = {
    "T1KeyFragment", "T2KeyFragment", "T3KeyFragment",
    "T4KeyFragment", "T5KeyFragment",
}

local function rollRarity(tier, isElite)
    local effectiveTier = tier
    if isElite then
        effectiveTier = math.min(tier + Config.ELITE_RARITY_TIER_BOOST, 5)
    end

    local weights = Config.TIER_RARITY_WEIGHTS[effectiveTier]
    local total   = 0
    for _, w in pairs(weights) do total = total + w end

    local roll = math.random() * total
    local cum  = 0
    for _, rarity in ipairs(RARITY_ORDER) do
        cum = cum + weights[rarity]
        if roll <= cum then return rarity end
    end
    return "Common"
end

------------------------------------------------------------------------
-- Internal: determine whether this mob is an elite variant.
-- Elite mobs have "Elite" in their MobID string by convention.
------------------------------------------------------------------------
local function isEliteMob(mob)
    return mob.MobID and mob.MobID:find("Elite") ~= nil
end

------------------------------------------------------------------------
-- Each mob death rolls three INDEPENDENT drop types: coins, a key fragment,
-- and gear. They used to all live inline in one long onMobDied function;
-- splitting them into their own try* functions keeps each roll's logic
-- self-contained (easier to reason about / unit-poke individually) and
-- makes adding a future 4th independent drop type (e.g. crafting shards)
-- a matter of writing one more tryDropX function instead of threading more
-- state through a single growing function.
--
-- Each tryDrop* takes the current scatterIndex (which world-pickup "slot"
-- around the death position is next free) and returns the index the next
-- roll should use -- it only advances when this roll actually spawned a
-- pickup, so drops still scatter tightly instead of leaving gaps.
------------------------------------------------------------------------

-- Coin drop (wallet): base chance for all non-elite mobs; elites always.
-- Independent of the gear drop roll.
local function tryDropCoins(tier, elite, killingBlowPlayer, deathPos, ownerUserId, scatterIndex)
    local coinFindPct = getTotalCoinFind(killingBlowPlayer)
    local effectiveCoinChance = Config.MOB_COIN_DROP_CHANCE * (1 + coinFindPct / 100)
    local coinRoll = math.random()
    local coinFindProc = false
    if not elite and coinRoll > Config.MOB_COIN_DROP_CHANCE and coinRoll <= effectiveCoinChance then
        coinFindProc = true  -- coin find pushed this over the base threshold
    end
    if not (elite or coinRoll <= effectiveCoinChance) then
        return scatterIndex  -- no coin drop this kill
    end

    local t = math.clamp(math.floor(tonumber(tier) or 1), 1, 5)
    local range = Config.MOB_COIN_RANGE_BY_TIER[t]
    if not range then
        return scatterIndex
    end
    local lo, hi = range[1], range[2]
    if not (type(lo) == "number" and type(hi) == "number" and hi >= lo) then
        return scatterIndex
    end

    local coins = math.random(lo, hi)
    local partyMult = PartyService.GetRewardMultiplier(killingBlowPlayer)
    if partyMult > 1 then
        coins = math.max(1, math.floor(coins * partyMult))
    end
    if coins <= 0 then
        return scatterIndex
    end

    -- Inside a dungeon, coins BANK instead of dropping -- you don't see what
    -- you earned until the run resolves. Forfeit entirely if you fail.
    do
        local DungeonScore = require(ServerScriptService:WaitForChild("DungeonScoreService"))
        if DungeonScore.IsInRun(killingBlowPlayer) then
            DungeonScore.AddCoins(killingBlowPlayer, coins)
            return scatterIndex
        end
    end

    WorldLoot.SpawnMobDrop(deathPos, ownerUserId, {
        kind = "coins",
        amount = coins,
        coinFind = coinFindProc,
    }, scatterIndex)
    return scatterIndex + 1
end

-- Key fragment drop: independent roll, scales by mob tier.
local function tryDropKeyFragment(tier, deathPos, ownerUserId, scatterIndex, killingBlowPlayer)
    -- Key fragments do not exist inside dungeons. They neither drop nor bank:
    -- fragments are the way you EARN entry to a dungeon, so farming them from
    -- inside one would let a run pay for its own successor.
    if killingBlowPlayer then
        local DungeonScore = require(ServerScriptService:WaitForChild("DungeonScoreService"))
        if DungeonScore.IsInRun(killingBlowPlayer) then
            return scatterIndex
        end
    end

    local fragTier = math.clamp(math.floor(tonumber(tier) or 1), 1, 5)
    if math.random() > KEY_FRAG_CHANCES[fragTier] then
        return scatterIndex  -- no key fragment this kill
    end

    local fragId = KEY_FRAG_IDS[fragTier]

    WorldLoot.SpawnMobDrop(deathPos, ownerUserId, {
        kind = "item_id",
        itemId = fragId,
        count = 1,
        notifyPayload = {
            kind = "KeyFragment",
            name = fragId,
            tier = fragTier,
        },
    }, scatterIndex)
    return scatterIndex + 1
end

-- Gear drop: rarity roll + ItemGenerator + world pickup spawn.
-- Luck buff (BuffService "LuckPct") multiplies the final chance.
local function tryDropGear(tier, level, elite, killingBlowPlayer, deathPos, ownerUserId, scatterIndex)
    local baseDrop  = Config.TIER_DROP_CHANCE[tier] or 0.18
    local dropBonus = elite and Config.ELITE_DROP_CHANCE_BONUS or 0
    local luckMult  = 1 + (BuffService.GetLuckBonusPct(killingBlowPlayer) / 100)
    local effectiveDrop = math.min(1, (baseDrop + dropBonus) * luckMult)
    if math.random() > effectiveDrop then
        return  -- no gear drop this kill
    end

    -- Roll rarity, biased to mob tier
    local rarity = rollRarity(tier, elite)

    -- Generate item at mob level and tier
    local ok, item = pcall(ItemGenerator.generate, {
        tier   = tier,
        rarity = rarity,
        level  = level,
    })
    if not ok or not item then
        warn("[LootService] ItemGenerator.generate failed: " .. tostring(item))
        return
    end

    local template = item:toGrantTemplate()
    local okTpl, errTpl = Types.ValidateItemTemplate(template)
    if not okTpl then
        warn("[LootService] Invalid generated template for " .. killingBlowPlayer.Name .. ": " .. tostring(errTpl))
        return
    end

    local okSpawn, lootIdOrErr = pcall(function()
        return WorldLoot.SpawnMobDrop(deathPos, ownerUserId, {
            kind = "item_template",
            template = template,
        }, scatterIndex)
    end)
    if not okSpawn then
        warn("[LootService] SpawnMobDrop failed for " .. killingBlowPlayer.Name .. ": " .. tostring(lootIdOrErr))
        return
    end
    if not lootIdOrErr then
        warn("[LootService] SpawnMobDrop returned nil for " .. killingBlowPlayer.Name .. ": " .. template.name)
        return
    end

    print(string.format("[LootService] %s dropped world loot: %s",
        killingBlowPlayer.Name, template.name))
end

------------------------------------------------------------------------
-- LootService.onMobDied(mob, killingBlowPlayer)
-- Called from MobManager.ProcessMobDeath.
-- mob fields used: mob.Tier, mob.Stats.Level, mob.MobID
------------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- Score-driven gear drops (replaces the flat per-kill TIER_DROP_CHANCE
-- roll for GEAR only -- coins and key fragments are untouched).
--
--   * Inside a dungeon: the kill BANKS score. Nothing drops now; the whole
--     total is cashed out through the same pity pools on run end.
--   * Overworld: the kill converts to score immediately and rolls every
--     rarity independently against its own dry streak.
--
-- Both paths share ONE dry-streak pool per player (LootPityService), so
-- dungeon progress and overworld progress are the same pity.
-- ---------------------------------------------------------------------
local function spawnGeneratedItem(item, killingBlowPlayer, deathPos, ownerUserId, scatterIndex)
    local okTpl, template = pcall(function() return item:toGrantTemplate() end)
    if not okTpl or not template then return scatterIndex end
    local valid, errTpl = Types.ValidateItemTemplate(template)
    if not valid then
        warn("[LootService] invalid template: " .. tostring(errTpl))
        return scatterIndex
    end
    local okSpawn, lootId = pcall(function()
        return WorldLoot.SpawnMobDrop(deathPos, ownerUserId, {
            kind = "item_template", template = template,
        }, scatterIndex)
    end)
    if okSpawn and lootId then
        print(string.format("[LootService] %s dropped %s (%s)",
            killingBlowPlayer.Name, template.name, tostring(template.rarity)))
        return scatterIndex + 1
    end
    return scatterIndex
end

local function tryDropGearByScore(mob, tier, level, killingBlowPlayer, deathPos, ownerUserId, scatterIndex)
    local Pity = require(ServerScriptService:WaitForChild("LootPityService"))
    local DungeonScore = require(ServerScriptService:WaitForChild("DungeonScoreService"))

    local contribution = 1
    if mob.DamageTracker then
        local total, mine = 0, 0
        for uid, dmg in pairs(mob.DamageTracker) do
            total = total + dmg
            if uid == ownerUserId then mine = dmg end
        end
        if total > 0 then contribution = mine / total end
    end

    -- In a dungeon the score is banked, not spent.
    if DungeonScore.IsInRun(killingBlowPlayer) then
        DungeonScore.AddKill(killingBlowPlayer, mob, contribution)
        return scatterIndex
    end

    local items = Pity.OnKill(killingBlowPlayer, mob, contribution)
    for _, item in ipairs(items) do
        scatterIndex = spawnGeneratedItem(item, killingBlowPlayer, deathPos, ownerUserId, scatterIndex)
    end
    return scatterIndex
end

-- Boss / named-elite Mythic: FLAT chance, no pity, no score. Only players
-- alive at the moment of death are eligible.
local function tryDropMythic(mob, killingBlowPlayer, deathPos, scatterIndex)
    local mobId = mob.MobID
    if not mobId then return scatterIndex end
    local MythicDefs = require(ReplicatedStorage:WaitForChild("MythicItemDefs"))
    if not MythicDefs.GetDropSpec(mobId) then return scatterIndex end

    local BossLoot = require(ServerScriptService:WaitForChild("DungeonBossLootService"))
    local results = BossLoot.OnBossKilledForAll(mob, deathPos)
    if #results > 0 then
        for _, r in ipairs(results) do
            print(string.format("[LootService] MYTHIC to %s: %s", r.player.Name, tostring(r.item.name)))
        end
    end
    return scatterIndex + #results
end

function LootService.onMobDied(mob, killingBlowPlayer)
    if not killingBlowPlayer or not killingBlowPlayer.Parent then return end

    local tier  = mob.Tier or 1
    local level = (mob.Stats and mob.Stats.Level) or 1
    local elite = isEliteMob(mob)
    local deathPos = mob.GetPosition and mob:GetPosition()
    if typeof(deathPos) ~= "Vector3" then
        return
    end
    local ownerUserId = killingBlowPlayer.UserId
    local scatterIndex = 0

    -- Each roll is independent; scatterIndex only advances when a roll
    -- actually spawns a pickup, so drops stay tightly clustered.
    scatterIndex = tryDropCoins(tier, elite, killingBlowPlayer, deathPos, ownerUserId, scatterIndex)
    scatterIndex = tryDropKeyFragment(tier, deathPos, ownerUserId, scatterIndex, killingBlowPlayer)
    scatterIndex = tryDropGearByScore(mob, tier, level, killingBlowPlayer, deathPos, ownerUserId, scatterIndex)
    scatterIndex = tryDropMythic(mob, killingBlowPlayer, deathPos, scatterIndex)

    -- Boss death ends the run: cash everyone out, then open the exit window.
    -- Players are NOT ejected -- they get a grace period to loot and regroup
    -- before being pulled to hearthstone.
    if mob.Stats and mob.Stats.IsBoss then
        task.defer(function()
            local okRun, runSvc = pcall(function()
                return require(ServerScriptService:WaitForChild("DungeonRunService", 5))
            end)
            if not okRun or not runSvc then return end

            local DungeonScore = require(ServerScriptService:WaitForChild("DungeonScoreService"))
            local cleared = {}
            for _, plr in ipairs(Players:GetPlayers()) do
                if DungeonScore.IsInRun(plr) then
                    table.insert(cleared, plr)
                end
            end
            if #cleared == 0 then return end

            for _, plr in ipairs(cleared) do
                pcall(runSvc.EndRunFor, plr, "cleared")
            end
            pcall(runSvc.BeginExitWindow, cleared)
        end)
    end
end

return LootService
