--[[
    LootService
    Handles item drops when mobs die.
    Called by MobManager.ProcessMobDeath after kill credit is awarded.

    Drop flow:
      1. Roll against TIER_DROP_CHANCE (+ elite bonus if applicable)
      2. Roll rarity from TIER_RARITY_WEIGHTS for the mob's tier
      3. Generate item via ItemGenerator at mob level + tier
      4. Grant to the killing player via DungeonProfileService.GrantItem
      5. Fire ItemDropNotify to client so the HUD can show a pickup banner

    Private loot model: only the killing blow player receives the drop for now.
    Contribution-based multi-drop can be added later by iterating DamageTracker.
]]

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config         = require(ReplicatedStorage:WaitForChild("ItemConfig"))
local ItemGenerator  = require(ServerScriptService:WaitForChild("ItemGenerator"))
local DungeonProfile = require(ServerScriptService:WaitForChild("DungeonProfileService"))
local BuffService    = require(ServerScriptService:WaitForChild("BuffService"))

local LootService = {}

-- Sum coinFind % across all equipped armor slots for a player.
local ARMOR_SLOTS_CHECK = { "Helm", "Chest", "Legs", "Boots", "Shield" }
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
-- LootService.onMobDied(mob, killingBlowPlayer)
-- Called from MobManager.ProcessMobDeath.
-- mob fields used: mob.Tier, mob.Stats.Level, mob.MobID
------------------------------------------------------------------------
function LootService.onMobDied(mob, killingBlowPlayer)
    if not killingBlowPlayer or not killingBlowPlayer.Parent then return end

    local tier  = mob.Tier or 1
    local level = (mob.Stats and mob.Stats.Level) or 1
    local elite = isEliteMob(mob)

    ----------------------------------------------------------------
    -- Coin drop (wallet): 30% base for all non-elite mobs; elites always.
    -- Independent of the gear drop roll below.
    ----------------------------------------------------------------
    local coinFindPct    = getTotalCoinFind(killingBlowPlayer)
    local effectiveCoinChance = Config.MOB_COIN_DROP_CHANCE * (1 + coinFindPct / 100)
    local coinRoll        = math.random()
    local coinFindProc    = false
    if not elite and coinRoll > Config.MOB_COIN_DROP_CHANCE and coinRoll <= effectiveCoinChance then
        coinFindProc = true  -- coin find pushed this over the base threshold
    end
    if elite or coinRoll <= effectiveCoinChance then
        local t = math.clamp(math.floor(tonumber(tier) or 1), 1, 5)
        local range = Config.MOB_COIN_RANGE_BY_TIER[t]
        if range then
            local lo, hi = range[1], range[2]
            if type(lo) == "number" and type(hi) == "number" and hi >= lo then
                local coins = math.random(lo, hi)
                if coins > 0 then
                    local profile = DungeonProfile.Load(killingBlowPlayer)
                    profile.currencies.Coins = math.floor((profile.currencies.Coins or 0) + coins)
                    DungeonProfile.PushProfile(killingBlowPlayer)
                    ItemDropNotify:FireClient(killingBlowPlayer, {
                        kind      = "Coins",
                        amount    = coins,
                        coinFind  = coinFindProc,
                    })
                end
            end
        end
    end

    ----------------------------------------------------------------
    -- Key fragment drop: independent roll, scales by mob tier.
    ----------------------------------------------------------------
    local fragTier = math.clamp(math.floor(tonumber(tier) or 1), 1, 5)
    if math.random() <= KEY_FRAG_CHANCES[fragTier] then
        local fragId = KEY_FRAG_IDS[fragTier]
        local okFrag = DungeonProfile.GrantItemId(killingBlowPlayer, fragId, 1)
        if okFrag then
            ItemDropNotify:FireClient(killingBlowPlayer, {
                kind = "KeyFragment",
                name = fragId,
                tier = fragTier,
            })
        end
    end

    -- Roll for drop. Luck buff (BuffService "LuckPct") multiplies the final chance.
    local baseDrop  = Config.TIER_DROP_CHANCE[tier] or 0.18
    local dropBonus = elite and Config.ELITE_DROP_CHANCE_BONUS or 0
    local luckMult  = 1 + (BuffService.GetLuckBonusPct(killingBlowPlayer) / 100)
    local effectiveDrop = math.min(1, (baseDrop + dropBonus) * luckMult)
    if math.random() > effectiveDrop then
        return  -- no drop this kill
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

    -- Build the grant template and validate it before granting
    local template = item:toGrantTemplate()

    local granted, err = DungeonProfile.GrantItem(killingBlowPlayer, template, 1)
    if not granted then
        warn("[LootService] GrantItem failed for " .. killingBlowPlayer.Name
            .. ": " .. tostring(err))
        return
    end

    -- Notify the client so they can display a pickup banner
    ItemDropNotify:FireClient(killingBlowPlayer, {
        name   = template.name,
        rarity = template.rarity,
        tier   = template.tier,
        type   = template.type,
    })

    print(string.format("[LootService] %s dropped: %s",
        killingBlowPlayer.Name, template.name))
end

return LootService
