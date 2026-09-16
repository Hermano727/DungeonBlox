--[[
    NPCRegistry
    Shared data-only module. Defines every NPC type, their shop catalogs,
    trade rates, and interaction lists.
    No side-effects on require().
]]

local ShopCatalogConfig = require(script.Parent:WaitForChild("ShopCatalogConfig"))

local NPCRegistry = {}

NPCRegistry.Types = {

    ["Merchant"] = {
        DisplayName    = "Merchant",
        Interactions   = { "BuyItem", "SellItem", "TradeOre", "SalvageGear" },
        OpenShopPrompt = "Browse Wares",
        ShopCatalog    = ShopCatalogConfig.Merchant.ShopCatalog,
        TradeRates     = ShopCatalogConfig.Merchant.TradeRates,
    },

    ["SkillTrainer"] = {
        DisplayName    = "Skill Trainer",
        Interactions   = { "BuyItem" },
        OpenShopPrompt = "Show me your wares.",
        ShopCatalog    = ShopCatalogConfig.SkillTrainer.ShopCatalog,
    },

    ["AnimalTrainer"] = {
        DisplayName    = "Animal Trainer",
        Interactions   = { "BuyItem" },
        OpenShopPrompt = "Browse saddles",
        ShopCatalog    = ShopCatalogConfig.AnimalTrainer.ShopCatalog,
    },

    ["Innkeeper"] = {
        DisplayName    = "Innkeeper",
        Interactions   = { "BuyItem" },
        OpenShopPrompt = "Browse wares",
        ShopCatalog    = ShopCatalogConfig.Innkeeper.ShopCatalog,
        -- Hearthstone locations managed via HearthstoneRegistry + HearthstoneClient ProximityPrompt.
    },

    ["Dungeoneer"] = {
        DisplayName    = "Dungeoneer",
        Interactions   = { "BuyItem" },
        OpenShopPrompt = "Trade key fragments",
        ShopCatalog    = ShopCatalogConfig.Dungeoneer.ShopCatalog,
    },

    ["Blacksmith"] = {
        DisplayName      = "Blacksmith",
        Interactions     = { "RepairItem", "RepairAll", "AcceptQuest", "TurnInQuest" },
        OpenRepairPrompt = "Repair Equipment",
        -- Cost formula in DurabilityService.getRepairCost: ceil(lost/50) Coins, min 1, x3 if broken
        -- AcceptQuest/TurnInQuest: generic quest actions (see QuestRegistry.BlacksmithScrapRun),
        -- routed here the same way as any other NPC transaction.
    },

    ["Miner"] = {
        DisplayName  = "Miner",
        Interactions = { "TalkMinerGreet", "TalkMinerCoalQuest" },
    },

    ["Fisherman"] = {
        DisplayName  = "Fisherman",
        Interactions = { "TalkFishermanGreet", "TalkFishermanFishQuest" },
    },

    ["QuestGiver"] = {
        DisplayName  = "Quest Giver",
        Interactions = { "TalkCusoQuest" },
    },

    ["Auctioneer"] = {
        DisplayName    = "Auctioneer",
        Interactions   = { "BrowseAuction" },
        OpenShopPrompt = "Browse Auction House",
    },

    -- TODO: AnimalVendor (BuyMounts)
    -- TODO: LeaderboardNPC
    -- TODO: GuildRegistrar
    -- TODO: ItemVendor (Realm Chest / misc)
    -- TODO: ScrollMerchant (Clue scroll discovery/exchange)
}

--- Returns the registry entry for the given NPC type, or nil.
function NPCRegistry.Get(npcType)
    return NPCRegistry.Types[npcType]
end

--- Returns true if the given action is allowed for the given NPC type.
function NPCRegistry.AllowsAction(npcType, action)
    local entry = NPCRegistry.Types[npcType]
    if not entry then return false end
    for _, v in ipairs(entry.Interactions) do
        if v == action then return true end
    end
    return false
end

--- Returns the ShopCatalog entry for itemId in the given NPC type, or nil.
function NPCRegistry.FindCatalogEntry(npcType, itemId)
    local entry = NPCRegistry.Types[npcType]
    if not entry or not entry.ShopCatalog then return nil end
    for _, row in ipairs(entry.ShopCatalog) do
        if row.ItemId == itemId then return row end
    end
    return nil
end

return NPCRegistry
