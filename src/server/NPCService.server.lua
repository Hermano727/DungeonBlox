--[[
    NPCService
    Server-authoritative handler for all NPC transactions.
    Creates the NPCRequest RemoteFunction and validates every purchase,
    trade, and interaction before mutating player state.

    Profile split:
      DungeonProfileService  → currencies (Coins), flags (teleports)
      InventoryService       → item inventory (slot-indexed consumables/gear)
]]

local CollectionService   = game:GetService("CollectionService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players             = game:GetService("Players")

local NPCRegistry      = require(ReplicatedStorage:WaitForChild("NPCRegistry"))
local DungeonProfile   = require(ServerScriptService:WaitForChild("DungeonProfileService"))
local InventoryService = require(ServerScriptService:WaitForChild("InventoryService"))
local PlayerData       = require(ServerScriptService:WaitForChild("PlayerDataManager"))
local ItemDefinitions  = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

---------------------------------------------------------------------------
-- RemoteFunction setup
---------------------------------------------------------------------------

local GameEvents = ReplicatedStorage:WaitForChild("GameEvents", 10)
if not GameEvents then
    error("[NPCService] ReplicatedStorage.GameEvents not found")
end

local NPCRequest = Instance.new("RemoteFunction")
NPCRequest.Name   = "NPCRequest"
NPCRequest.Parent = GameEvents

---------------------------------------------------------------------------
-- NPC model index  [npcId] = model
---------------------------------------------------------------------------

local npcIndex = {}

local function indexNPC(model)
    local npcId = model:GetAttribute("NpcId")
    if type(npcId) == "string" and npcId ~= "" then
        npcIndex[npcId] = model
    end
end

for _, model in ipairs(CollectionService:GetTagged("NPC")) do
    indexNPC(model)
end
CollectionService:GetInstanceAddedSignal("NPC"):Connect(indexNPC)
CollectionService:GetInstanceRemovedSignal("NPC"):Connect(function(model)
    local npcId = model:GetAttribute("NpcId")
    if npcId then npcIndex[npcId] = nil end
end)

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local RATE_LIMIT  = 0.5          -- seconds between requests per player
local lastRequest = {}           -- [userId] = tick()

local function getDungeonProfile(player)
    local profile = DungeonProfile.Get(player)
    if not profile then profile = DungeonProfile.Load(player) end
    if type(profile.flags) ~= "table" then
        profile.flags = {}
    end
    -- Ensure teleports sub-table exists for older saves
    if type(profile.flags.teleports) ~= "table" then
        profile.flags.teleports = {}
    end
    return profile
end

local function validateProximity(player, npcModel)
    local char = player.Character
    if not char then
        return false
    end
    local hrp = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
    if not hrp then
        return false
    end
    local pp = npcModel.PrimaryPart or npcModel:FindFirstChildWhichIsA("BasePart")
    if not pp then
        return false
    end
    local maxDist = (npcModel:GetAttribute("MaxActivationDistance") or 10) + 2
    return (hrp.Position - pp.Position).Magnitude <= maxDist
end

-- Count legacy slot-indexed InventoryService slots only
local function countLegacySlots(player, itemId)
    local profile = PlayerData.Get(player)
    if not profile then return 0 end
    local total = 0
    for _, slot in pairs(profile.Inventory) do
        if slot and slot.ItemId == itemId then
            total = total + (slot.Count or 1)
        end
    end
    return total
end

local function countDungeonStacks(player, itemId)
    local profile = DungeonProfile.Get(player) or DungeonProfile.Load(player)
    if not profile or type(profile.inventory) ~= "table" then
        return 0
    end
    local total = 0
    for _, it in pairs(profile.inventory) do
        if type(it) == "table" and it.itemId == itemId then
            if ItemDefinitions.IsStackable(itemId) then
                total = total + math.max(1, math.floor(tonumber(it.count) or 1))
            else
                total = total + 1
            end
        end
    end
    return total
end

local function countItem(player, itemId)
    return countLegacySlots(player, itemId) + countDungeonStacks(player, itemId)
end

local function removeItemAcrossStores(player, itemId, qty)
    local legacyHave = countLegacySlots(player, itemId)
    local dungeonHave = countDungeonStacks(player, itemId)
    if legacyHave + dungeonHave < qty then
        return false
    end
    local takeLegacy = math.min(legacyHave, qty)
    if takeLegacy > 0 then
        if not InventoryService.RemoveItem(player, itemId, takeLegacy) then
            return false
        end
    end
    local takeDungeon = qty - takeLegacy
    if takeDungeon > 0 then
        local okConsume = DungeonProfile.ConsumeItemId(player, itemId, takeDungeon)
        if not okConsume then
            if takeLegacy > 0 then
                InventoryService.AddItem(player, itemId, takeLegacy)
            end
            return false
        end
    end
    return true
end
---------------------------------------------------------------------------
-- Action handlers  (each returns a result table {ok, err?, ...})
---------------------------------------------------------------------------

-- BuyItem: deduct currency, add item to slot inventory
local function handleBuyItem(player, _npcId, npcType, params)
    local itemId = params.itemId
    local qty    = math.max(1, math.min(99, math.floor(tonumber(params.qty) or 1)))

    if type(itemId) ~= "string" then return {ok=false, err="bad_item"} end

    local entry = NPCRegistry.FindCatalogEntry(npcType, itemId)
    if not entry then return {ok=false, err="not_in_catalog"} end

    if not ItemDefinitions.Get(itemId) then return {ok=false, err="unknown_item"} end

    local cost     = entry.Price * qty
    local currency = entry.Currency or "Coins"

    local dProfile = getDungeonProfile(player)
    if not dProfile then return {ok=false, err="no_profile"} end

    -- Grant item into authoritative dungeon inventory first; payment is deducted after grant.
    local grantQty = (entry.Qty or 1) * qty
    local okGrant, errGrant = DungeonProfile.GrantItemId(player, itemId, grantQty)
    if not okGrant then
        return { ok = false, err = errGrant or "grant_failed", wallet = dProfile.currencies.Coins or 0 }
    end

    -- Currency can be either a wallet key (Coins) OR an itemId (e.g. Coal barter).
    if dProfile.currencies[currency] ~= nil then
        local balance = dProfile.currencies[currency] or 0
        if balance < cost then
            DungeonProfile.ConsumeItemId(player, itemId, grantQty)
            return {ok=false, err="insufficient_funds"}
        end
        dProfile.currencies[currency] = balance - cost
        DungeonProfile.PushProfile(player)
    else
        if countItem(player, currency) < cost then
            DungeonProfile.ConsumeItemId(player, itemId, grantQty)
            return {ok=false, err="insufficient_funds"}
        end
        if not removeItemAcrossStores(player, currency, cost) then
            DungeonProfile.ConsumeItemId(player, itemId, grantQty)
            return {ok=false, err="remove_failed"}
        end
    end

    return {
        ok     = true,
        wallet = dProfile.currencies.Coins or 0,
    }
end

-- TradeOre: remove materials from slot inventory, receive currency or items
local function handleTradeOre(player, _npcId, npcType, params)
    local tradeIndex = math.max(1, math.floor(tonumber(params.tradeIndex) or 1))
    local qty        = math.max(1, math.min(99, math.floor(tonumber(params.qty) or 1)))

    local npcData = NPCRegistry.Get(npcType)
    if not npcData or not npcData.TradeRates then return {ok=false, err="no_trades"} end
    local trade = npcData.TradeRates[tradeIndex]
    if not trade then return {ok=false, err="bad_trade_index"} end

    local giveItemId = trade.Give.ItemId
    local giveQty    = trade.Give.Qty * qty

    if countItem(player, giveItemId) < giveQty then
        return {ok=false, err="insufficient_items"}
    end

    -- Remove materials from legacy + dungeon inventories
    if not removeItemAcrossStores(player, giveItemId, giveQty) then
        return { ok = false, err = "remove_failed" }
    end

    -- Deliver received goods
    local dProfile = getDungeonProfile(player)
    local receive  = trade.Receive
    if receive.Currency then
        dProfile.currencies[receive.Currency] =
            (dProfile.currencies[receive.Currency] or 0) + receive.Qty * qty
        DungeonProfile.PushProfile(player)
    elseif receive.ItemId then
        local okRecv, errRecv = DungeonProfile.GrantItemId(player, receive.ItemId, receive.Qty * qty)
        if not okRecv then
            return { ok = false, err = errRecv or "receive_failed" }
        end
    end
    return {
        ok     = true,
        wallet = dProfile.currencies.Coins or 0,
    }
end

-- UnlockTeleport: deduct currency, set profile flag
local function handleUnlockTeleport(player, _npcId, npcType, params)
    local nodeId = params.nodeId
    if type(nodeId) ~= "string" or nodeId == "" then return {ok=false, err="bad_node"} end

    local npcData = NPCRegistry.Get(npcType)
    if not npcData or not npcData.TeleportNodes then return {ok=false, err="no_nodes"} end

    local node = nil
    for _, n in ipairs(npcData.TeleportNodes) do
        if n.NodeId == nodeId then node = n break end
    end
    if not node then return {ok=false, err="unknown_node"} end

    local dProfile = getDungeonProfile(player)
    if not dProfile then return {ok=false, err="no_profile"} end

    if dProfile.flags.teleports[nodeId] then
        return {ok=false, err="already_unlocked"}
    end

    local cost     = node.Price or 0
    local currency = node.Currency or "Coins"
    if cost > 0 then
        local balance = dProfile.currencies[currency] or 0
        if balance < cost then return {ok=false, err="insufficient_funds"} end
        dProfile.currencies[currency] = balance - cost
    end

    dProfile.flags.teleports[nodeId] = true
    DungeonProfile.PushProfile(player)

    return {
        ok     = true,
        nodeId = nodeId,
        wallet = dProfile.currencies.Coins or 0,
    }
end

---------------------------------------------------------------------------
-- RepairItem: deduct Coins, restore item durability to max
---------------------------------------------------------------------------

local function handleRepairItem(player, _npcId, npcType, params)
    local itemUuid = params.itemUuid
    if type(itemUuid) ~= "string" or itemUuid == "" then
        return { ok = false, err = "bad_item_uuid" }
    end

    local dProfile = getDungeonProfile(player)
    if not dProfile then return { ok = false, err = "no_profile" } end

    local inv = dProfile.inventory
    if type(inv) ~= "table" then
        return { ok = false, err = "no_inventory" }
    end

    local item = inv[itemUuid]
    if type(item) ~= "table" then
        return { ok = false, err = "item_not_found" }
    end

    -- Only repairable types
    local kind = item.type
    if kind ~= "Weapon" and kind ~= "Armor" and not (kind == "Material" and item.equipSlot) then
        return { ok = false, err = "not_repairable" }
    end

    -- Read durability (default 100/100 if not yet set)
    local dur     = type(item.durability) == "number" and item.durability or 100
    local maxDur  = type(item.maxDurability) == "number" and item.maxDurability or 100

    if dur >= maxDur then
        return { ok = false, err = "no_repair_needed" }
    end

    -- Calculate cost using DurabilityService formula (Coins, not Scrap)
    local DurSvc = require(ServerScriptService:WaitForChild("DurabilityService"))
    local cost = DurSvc.getRepairCost(item)
    if cost <= 0 then
        return { ok = false, err = "no_repair_needed" }
    end

    local coinBalance = dProfile.currencies.Coins or 0
    if coinBalance < cost then
        return { ok = false, err = "insufficient_funds" }
    end

    -- Deduct Coins and restore durability
    dProfile.currencies.Coins = coinBalance - cost
    DurSvc.repairItem(item)
    DungeonProfile.PushProfile(player)

    return {
        ok     = true,
        wallet = dProfile.currencies.Coins or 0,
    }
end

---------------------------------------------------------------------------
-- RepairAll: repair every damaged/broken item in one atomic request
local function handleRepairAll(player, _npcId, _npcType, _params)
    local dProfile = getDungeonProfile(player)
    if not dProfile then return { ok = false, err = "no_profile" } end

    local inv = dProfile.inventory
    if type(inv) ~= "table" then return { ok = false, err = "no_inventory" } end

    local DurSvc = require(ServerScriptService:WaitForChild("DurabilityService"))

    -- Collect repairable items and total cost
    local toRepair = {}
    local totalCost = 0
    for uuid, item in pairs(inv) do
        if type(item) == "table" then
            local kind = item.type
            local isRepairableType = kind == "Weapon" or kind == "Armor" or
                (kind == "Material" and item.equipSlot)
            if isRepairableType then
                local cost = DurSvc.getRepairCost(item)
                if cost > 0 then
                    table.insert(toRepair, { item = item, cost = cost })
                    totalCost = totalCost + cost
                end
            end
        end
    end

    if #toRepair == 0 then
        return { ok = false, err = "no_repair_needed" }
    end

    local coinBalance = dProfile.currencies.Coins or 0
    if coinBalance < totalCost then
        return { ok = false, err = "insufficient_funds" }
    end

    dProfile.currencies.Coins = coinBalance - totalCost
    for _, entry in ipairs(toRepair) do
        DurSvc.repairItem(entry.item)
    end
    DungeonProfile.PushProfile(player)

    return {
        ok     = true,
        wallet = dProfile.currencies.Coins,
    }
end

local function handleTalkCusoQuest(player, npcId, npcType, _params)
    if npcType ~= "QuestGiver" or npcId ~= "cuso_01" then
        return { ok = false, err = "bad_npc" }
    end

    local dProfile = getDungeonProfile(player)
    if not dProfile then
        return { ok = false, err = "no_profile" }
    end

    if type(dProfile.flags) ~= "table" then
        dProfile.flags = {}
    end
    local q = dProfile.flags.cusoBanditQuest
    if type(q) ~= "table" then
        q = { active = false, completed = false, target = 5, progress = 0, rewardCoins = 10, rewardPaid = false }
        dProfile.flags.cusoBanditQuest = q
    end
    if q.rewardCoins == nil then
        q.rewardCoins = 10
    end
    if q.rewardPaid == nil then
        q.rewardPaid = false
    end

    local target = math.max(1, math.floor(tonumber(q.target) or 5))
    q.target = target

    if q.completed then
        return { ok = true, msg = "You already dealt with those bandits — thanks again." }
    end

    if q.active then
        local p = math.min(target, math.floor(tonumber(q.progress) or 0))
        local rc = math.max(0, math.floor(tonumber(q.rewardCoins) or 10))
        return {
            ok = true,
            msg = string.format("You're on it: %d / %d bandits down. Finish the job for %d coins.", p, target, rc),
        }
    end

    q.active = true
    q.progress = 0
    q.completed = false
    q.rewardCoins = math.max(0, math.floor(tonumber(q.rewardCoins) or 10))
    q.rewardPaid = false
    DungeonProfile.PushProfile(player)

    return {
        ok = true,
        msg = string.format(
            "Good. Put down some bandits on the road and help me clear my home. I'll pay you %d coins when it's done.",
            q.rewardCoins
        ),
    }
end

local StarterPack = game:GetService("StarterPack")

local function grantStarterPackWoodenPickaxe(player)
    if playerHasPhysicalPickaxe(player) then
        return true
    end
    local bp = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 15)
    if not bp then
        return false
    end
    local tmpl = StarterPack:FindFirstChild("WoodenPickaxe")
    if not tmpl or not tmpl:IsA("Tool") then
        return false
    end
    local tool = tmpl:Clone()
    tool.Parent = bp
    return true
end

local function toolLooksLikePickaxe(t)
    if not t or not t:IsA("Tool") then
        return false
    end
    local n = t.Name
    if n == "WoodenPickaxe" or n == "Pickaxe" or n == "Wooden Pickaxe" then
        return true
    end
    if t:GetAttribute("DungeonEquipSlot") == "Pickaxe" then
        return true
    end
    if t:FindFirstChild("MiningScript") then
        return true
    end
    return false
end

local function playerHasPhysicalPickaxe(player)
    local char = player.Character
    if char then
        for _, c in ipairs(char:GetChildren()) do
            if toolLooksLikePickaxe(c) then
                return true
            end
        end
    end
    local bp = player:FindFirstChildOfClass("Backpack")
    if bp then
        for _, c in ipairs(bp:GetChildren()) do
            if toolLooksLikePickaxe(c) then
                return true
            end
        end
    end
    return false
end

local function profileHasPickaxeInventory(profile)
    for _, it in pairs(profile.inventory or {}) do
        if type(it) == "table" then
            if it.equipSlot == "Pickaxe" then
                return true
            end
            if it.itemId == "WoodenPickaxe" then
                return true
            end
        end
    end
    return false
end

-- Miner coal quest: always grant another WoodenPickaxe via GrantItemId (same as TradeOre receive), even if the player already owns one.
local function ensureMinerPickaxeForQuest(player, dProfile)
    local raidWas = dProfile.flags.inRaid == true
    if raidWas then
        dProfile.flags.inRaid = false
    end
    local okRecv, errRecv = DungeonProfile.GrantItemId(player, "WoodenPickaxe", 1)
    if raidWas then
        dProfile.flags.inRaid = true
    end
    if not okRecv then
        warn("[NPCService] Miner quest GrantItemId(WoodenPickaxe) failed:", errRecv)
        grantStarterPackWoodenPickaxe(player)
    end
end

local function handleTalkMinerGreet(player, npcId, npcType, _params)
    if npcType ~= "Miner" or npcId ~= "miner_01" then
        return { ok = false, err = "bad_npc" }
    end

    local dProfile = getDungeonProfile(player)
    if not dProfile then
        return { ok = false, err = "no_profile" }
    end

    if type(dProfile.flags) ~= "table" then
        dProfile.flags = {}
    end
    if dProfile.flags.minerPickaxeGreetingDone == nil then
        dProfile.flags.minerPickaxeGreetingDone = false
    end

    if dProfile.flags.minerPickaxeGreetingDone then
        return { ok = true, gavePickaxe = false }
    end

    local needGrant = not profileHasPickaxeInventory(dProfile) and not playerHasPhysicalPickaxe(player)

    if not needGrant then
        dProfile.flags.minerPickaxeGreetingDone = true
        DungeonProfile.PushProfile(player)
        return { ok = true, gavePickaxe = false }
    end

    local granted = grantStarterPackWoodenPickaxe(player)
    if not granted then
        return { ok = false, err = "pickaxe_unavailable" }
    end

    dProfile.flags.minerPickaxeGreetingDone = true
    DungeonProfile.PushProfile(player)

    return { ok = true, gavePickaxe = true }
end

local function handleTalkMinerCoalQuest(player, npcId, npcType, _params)
    if npcType ~= "Miner" or npcId ~= "miner_01" then
        return { ok = false, err = "bad_npc" }
    end

    local dProfile = getDungeonProfile(player)
    if not dProfile then
        return { ok = false, err = "no_profile" }
    end

    if type(dProfile.flags) ~= "table" then
        dProfile.flags = {}
    end
    local q = dProfile.flags.minerCoalQuest
    if type(q) ~= "table" then
        q = { active = false, completed = false, started = false, target = 5, progress = 0, rewardCoins = 10, rewardPaid = false }
        dProfile.flags.minerCoalQuest = q
    end
    if q.started == nil then
        q.started = (q.completed == true) or (q.active == true)
    end
    if q.rewardCoins == nil then
        q.rewardCoins = 10
    end
    if q.rewardPaid == nil then
        q.rewardPaid = false
    end

    local target = math.max(1, math.floor(tonumber(q.target) or 5))
    q.target = target

    if q.completed then
        return { ok = true, msg = "You already brought me that coal — much obliged." }
    end

    if q.started == true and q.active ~= true then
        return {
            ok = true,
            msg = "You already took that coal contract once. The guild doesn't hand out duplicates.",
        }
    end

    if q.active then
        local p = math.min(target, math.floor(tonumber(q.progress) or 0))
        local rc = math.max(0, math.floor(tonumber(q.rewardCoins) or 10))
        return {
            ok = true,
            msg = string.format("You're on it: %d / %d coal collected. I'll pay %d coins when it's done.", p, target, rc),
        }
    end

    local firstStart = q.started ~= true
    if firstStart then
        ensureMinerPickaxeForQuest(player, dProfile)
    end

    q.started = true
    q.active = true
    q.progress = 0
    q.completed = false
    q.rewardCoins = math.max(0, math.floor(tonumber(q.rewardCoins) or 10))
    q.rewardPaid = false
    DungeonProfile.PushProfile(player)

    return {
        ok = true,
        msg = string.format(
            "I need five lumps of coal from the veins out there. Bring them in through proper mining — I'll pay you %d coins when you've got all five.",
            q.rewardCoins
        ),
    }
end

local function toolLooksLikeSpear(t)
    if not t or not t:IsA("Tool") then
        return false
    end
    local n = t.Name
    if n == "WoodenSpear" or n == "Spear" then
        return true
    end
    if t:GetAttribute("DungeonEquipSlot") == "FishingSpear" then
        return true
    end
    if t:FindFirstChild("FishClient") then
        return true
    end
    return false
end

local function playerHasPhysicalSpear(player)
    local char = player.Character
    if char then
        for _, c in ipairs(char:GetChildren()) do
            if toolLooksLikeSpear(c) then
                return true
            end
        end
    end
    local bp = player:FindFirstChildOfClass("Backpack")
    if bp then
        for _, c in ipairs(bp:GetChildren()) do
            if toolLooksLikeSpear(c) then
                return true
            end
        end
    end
    return false
end

local function profileHasSpearInventory(profile)
    for _, it in pairs(profile.inventory or {}) do
        if type(it) == "table" then
            if it.equipSlot == "FishingSpear" then
                return true
            end
            if it.itemId == "WoodenSpear" then
                return true
            end
        end
    end
    return false
end

local function grantStarterPackWoodenSpear(player)
    if playerHasPhysicalSpear(player) then
        return true
    end
    local bp = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 15)
    if not bp then
        return false
    end
    local tmpl = StarterPack:FindFirstChild("WoodenSpear")
    if not tmpl or not tmpl:IsA("Tool") then
        return false
    end
    local tool = tmpl:Clone()
    tool.Parent = bp
    return true
end

local function ensureFisherSpearForQuest(player, dProfile)
    local raidWas = dProfile.flags.inRaid == true
    if raidWas then
        dProfile.flags.inRaid = false
    end
    local okRecv, errRecv = DungeonProfile.GrantItemId(player, "WoodenSpear", 1)
    if raidWas then
        dProfile.flags.inRaid = true
    end
    if not okRecv then
        warn("[NPCService] Fisher quest GrantItemId(WoodenSpear) failed:", errRecv)
        grantStarterPackWoodenSpear(player)
    end
end

local function handleTalkFishermanGreet(player, npcId, npcType, _params)
    if npcType ~= "Fisherman" or npcId ~= "fisherman_01" then
        return { ok = false, err = "bad_npc" }
    end

    local dProfile = getDungeonProfile(player)
    if not dProfile then
        return { ok = false, err = "no_profile" }
    end

    if type(dProfile.flags) ~= "table" then
        dProfile.flags = {}
    end
    if dProfile.flags.fisherSpearGreetingDone == nil then
        dProfile.flags.fisherSpearGreetingDone = false
    end

    if dProfile.flags.fisherSpearGreetingDone then
        return { ok = true, gaveSpear = false }
    end

    local needGrant = not profileHasSpearInventory(dProfile) and not playerHasPhysicalSpear(player)

    if not needGrant then
        dProfile.flags.fisherSpearGreetingDone = true
        DungeonProfile.PushProfile(player)
        return { ok = true, gaveSpear = false }
    end

    local granted = grantStarterPackWoodenSpear(player)
    if not granted then
        return { ok = false, err = "spear_unavailable" }
    end

    dProfile.flags.fisherSpearGreetingDone = true
    DungeonProfile.PushProfile(player)

    return { ok = true, gaveSpear = true }
end

local function handleTalkFishermanFishQuest(player, npcId, npcType, _params)
    if npcType ~= "Fisherman" or npcId ~= "fisherman_01" then
        return { ok = false, err = "bad_npc" }
    end

    local dProfile = getDungeonProfile(player)
    if not dProfile then
        return { ok = false, err = "no_profile" }
    end

    if type(dProfile.flags) ~= "table" then
        dProfile.flags = {}
    end
    local q = dProfile.flags.fisherFishQuest
    if type(q) ~= "table" then
        q = { active = false, completed = false, started = false, target = 5, progress = 0, rewardCoins = 10, rewardPaid = false }
        dProfile.flags.fisherFishQuest = q
    end
    if q.started == nil then
        q.started = (q.completed == true) or (q.active == true)
    end
    if q.rewardCoins == nil then
        q.rewardCoins = 10
    end
    if q.rewardPaid == nil then
        q.rewardPaid = false
    end

    local target = math.max(1, math.floor(tonumber(q.target) or 5))
    q.target = target

    if q.completed then
        return { ok = true, msg = "You already brought me those fish — much obliged." }
    end

    if q.started == true and q.active ~= true then
        return {
            ok = true,
            msg = "You already took that fishing contract once. The guild doesn't hand out duplicates.",
        }
    end

    if q.active then
        local p = math.min(target, math.floor(tonumber(q.progress) or 0))
        local rc = math.max(0, math.floor(tonumber(q.rewardCoins) or 10))
        return {
            ok = true,
            msg = string.format("You're on it: %d / %d fish landed. I'll pay %d coins when it's done.", p, target, rc),
        }
    end

    local firstStart = q.started ~= true
    if firstStart then
        ensureFisherSpearForQuest(player, dProfile)
    end

    q.started = true
    q.active = true
    q.progress = 0
    q.completed = false
    q.rewardCoins = math.max(0, math.floor(tonumber(q.rewardCoins) or 10))
    q.rewardPaid = false
    DungeonProfile.PushProfile(player)

    return {
        ok = true,
        msg = string.format(
            "Head to open water with that spear and land five fish for the camp kitchen. I'll pay you %d coins when you've got all five.",
            q.rewardCoins
        ),
    }
end

---------------------------------------------------------------------------
-- Dispatch table
---------------------------------------------------------------------------

local function handleSalvageGear(player, _npcId, npcType, params)
	if npcType ~= "Merchant" then
		return { ok = false, err = "bad_npc" }
	end
	local itemUuid = params.itemUuid
	if type(itemUuid) ~= "string" or itemUuid == "" then
		return { ok = false, err = "bad_item_uuid" }
	end
	local okSalv, errOrData = DungeonProfile.SalvageGearByUuid(player, itemUuid)
	if not okSalv then
		return { ok = false, err = errOrData or "salvage_failed" }
	end
	local dProfile = getDungeonProfile(player)
	local coinsTotal = math.floor(tonumber(dProfile.currencies.Coins) or 0)
	local grantedItemId = nil
	local grantedQty = 0
	if type(errOrData) == "table" then
		if errOrData.wallet ~= nil then
			coinsTotal = math.floor(tonumber(errOrData.wallet) or coinsTotal)
		end
		if type(errOrData.grantedItemId) == "string" then
			grantedItemId = errOrData.grantedItemId
		end
		if type(errOrData.grantedQty) == "number" then
			grantedQty = errOrData.grantedQty
		end
	end
	return {
		ok = true,
		wallet = coinsTotal,
		grantedItemId = grantedItemId,
		grantedQty = grantedQty,
	}
end

local HANDLERS = {
    BuyItem              = handleBuyItem,
    TradeOre             = handleTradeOre,
    UnlockTeleport       = handleUnlockTeleport,
    RepairItem           = handleRepairItem,
    RepairAll            = handleRepairAll,
    TalkCusoQuest        = handleTalkCusoQuest,
    TalkMinerGreet       = handleTalkMinerGreet,
    TalkMinerCoalQuest   = handleTalkMinerCoalQuest,
    TalkFishermanGreet   = handleTalkFishermanGreet,
    TalkFishermanFishQuest = handleTalkFishermanFishQuest,
    SalvageGear          = handleSalvageGear,
}

---------------------------------------------------------------------------
-- Main handler
---------------------------------------------------------------------------

NPCRequest.OnServerInvoke = function(player, params)
    if type(params) ~= "table" then return {ok=false, err="bad_request"} end

    local npcId  = params.npcId
    local action = params.action
    if type(npcId) ~= "string" or type(action) ~= "string" then
        return {ok=false, err="bad_request"}
    end

    -- Rate limit (Miner greet runs after first dialog line; keep quest accept snappy.)
    local userId = player.UserId
    local now    = tick()
    if action ~= "TalkMinerGreet" and action ~= "TalkFishermanGreet" then
        if (now - (lastRequest[userId] or 0)) < RATE_LIMIT then
            return {ok=false, err="throttled"}
        end
        lastRequest[userId] = now
    end

    -- Resolve NPC
    local npcModel = npcIndex[npcId]
    if not npcModel or not npcModel.Parent then return {ok=false, err="npc_not_found"} end

    local npcType = npcModel:GetAttribute("NpcType")
    if not npcType then return {ok=false, err="no_npc_type"} end

    -- Whitelist check
    if not NPCRegistry.AllowsAction(npcType, action) then
        return {ok=false, err="action_not_allowed"}
    end

    -- Proximity check
    if not validateProximity(player, npcModel) then
        return {ok=false, err="too_far"}
    end

    -- Dispatch
    local handler = HANDLERS[action]
    if not handler then return {ok=false, err="unimplemented"} end

    local ok, result = pcall(handler, player, npcId, npcType, params)
    if not ok then
        warn("[NPCService] Handler error for '" .. action .. "': " .. tostring(result))
        return {ok=false, err="server_error"}
    end
    return result
end

-- Clean up rate-limit table on leave
Players.PlayerRemoving:Connect(function(player)
    lastRequest[player.UserId] = nil
end)

print("[NPCService] ready")
