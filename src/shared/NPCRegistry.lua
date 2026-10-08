--[[
    NPCRegistry
    Shared data-only module. Defines every NPC type, their shop catalogs,
    trade rates, and interaction lists.

    Talking to an NPC (2026-10-01): service NPCs open a dialog tree
    (RS/DialogSystem/Trees/<NpcType>) whose options open their menu. Set
    SkipDialog = true to skip the conversation and open the menu straight from
    the prompt (MerchantShopClient's router decides). The tutorial / quest NPCs
    (Miner, Fisherman, QuestGiver) are still on the old DialogModule (NPCClient).
    No side-effects on require().

    Nametag (2026-10-05): a type with a Nametag entry gets the crest-on-plaque tag drawn by
    src/client/NpcNametags (art in RS/Assets/Images/NpcNametagArt) instead of the old text
    Head.gui, which NPCBootstrapKit/SpawnerService then stop building. Types without one keep
    the old Head.gui, the DialogModule contract.
        Icon          key into NpcNametagArt.ICONS; nil = plaque only, no crest
        HeightOffset  studs added above the model's top (default 0), for a model whose
                      bounding box doesn't end at its head
        Accent        Color3 for a soft glow behind the crest; nil = no glow
]]

local ShopCatalogConfig = require(script.Parent:WaitForChild("ShopCatalogConfig"))

local NPCRegistry = {}

NPCRegistry.Types = {

    ["Merchant"] = {
        DisplayName    = "Merchant",
        Nametag        = { Icon = "Merchant" },
        -- assets/models/npcs/merchant/rig (Merchant_Idle, custom skinned rig)
        IdleAnimationId = "rbxassetid://119614028237873",
        SkipDialog     = true,
        Interactions   = { "BuyItem", "SellItem", "TradeOre", "SalvageGear" },
        OpenShopPrompt = "Browse Wares",
        ShopCatalog    = ShopCatalogConfig.Merchant.ShopCatalog,
        TradeRates     = ShopCatalogConfig.Merchant.TradeRates,
    },

    ["SkillTrainer"] = {
        DisplayName    = "Skill Trainer",
        Nametag        = {}, -- no icon yet: plaque only
        Interactions   = { "BuyItem" },
        OpenShopPrompt = "Show me your wares.",
        ShopCatalog    = ShopCatalogConfig.SkillTrainer.ShopCatalog,
    },

    ["AnimalTrainer"] = {
        DisplayName    = "Animal Trainer",
        Nametag        = { Icon = "AnimalTrainer" },
        -- assets/models/npcs/capybara animal tamer/rig (AnimalTrainer_Idle, custom skinned rig)
        IdleAnimationId = "rbxassetid://92755483647266",
        SkipDialog     = true,
        Interactions   = { "BuyItem" },
        OpenShopPrompt = "Browse saddles",
        ShopCatalog    = ShopCatalogConfig.AnimalTrainer.ShopCatalog,
    },

    ["Innkeeper"] = {
        DisplayName    = "Innkeeper",
        Nametag        = {}, -- no icon yet: plaque only
        Interactions   = { "BuyItem" },
        OpenShopPrompt = "Browse wares",
        ShopCatalog    = ShopCatalogConfig.Innkeeper.ShopCatalog,
        -- Hearthstone locations managed via HearthstoneRegistry + HearthstoneClient ProximityPrompt.
    },

    ["Dungeoneer"] = {
        DisplayName    = "Dungeoneer",
        Nametag        = { Icon = "Dungeoneer" },
        Interactions   = { "BuyItem" },
        OpenShopPrompt = "Trade key fragments",
        ShopCatalog    = ShopCatalogConfig.Dungeoneer.ShopCatalog,
    },

    ["Blacksmith"] = {
        DisplayName      = "Blacksmith",
        Nametag          = { Icon = "Blacksmith" },
        -- assets/models/npcs/oakhaven blacksmith/rig (Blacksmith_Idle, custom skinned rig)
        IdleAnimationId  = "rbxassetid://92053429330371",
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
        DisplayName     = "Auctioneer",
        Nametag         = { Icon = "Auctioneer" },
        IdleAnimationId = "rbxassetid://113709712798356",
        Interactions    = { "BrowseAuction" },
        OpenShopPrompt  = "Browse Auction House",
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

--- Returns the type's Nametag entry (see the header), or nil when it keeps the old Head.gui.
function NPCRegistry.GetNametag(npcType)
    local entry = npcType and NPCRegistry.Types[npcType]
    return entry and entry.Nametag
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
