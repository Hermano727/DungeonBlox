local Keys = require(game:GetService("ReplicatedStorage"):WaitForChild("KeybindConfig"))
--[[
    NPCClient
    Factory that discovers all CollectionService-tagged "NPC" models,
    initialises a DialogModule instance per NPC, and owns the shared
    NPCShopUI panel used for all merchant interactions.

    Model contract (attributes on the model root):
      NpcId   (string)  – unique identifier, e.g. "hollow_merchant_01"
      NpcType (string)  – key into NPCRegistry, e.g. "Merchant", "Miner", "Fisherman"
      NpcName (string)  – display name shown in dialogue
      MaxActivationDistance (number) – default 10
    Plus CollectionService tag "NPC" and a ProximityPrompt tagged "NPCprompt"
    on HumanoidRootPart.

    Note: CampMerchantDialogue is a hand-authored story NPC that is NOT tagged
    "NPC", so this factory skips it entirely. FishermanNpcBootstrap tags
    Workspace.Fisherman like MinerNpcBootstrap does for the Miner.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local UserInputService  = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local DialogModule  = require(ReplicatedStorage:WaitForChild("DialogModule"))
local NPCRegistry   = require(ReplicatedStorage:WaitForChild("NPCRegistry"))

local MenuMouse     = require(ReplicatedStorage:WaitForChild("CursorUtils"))
local Types         = require(ReplicatedStorage:WaitForChild("ProfileTypes"))
local DungeonMenuNet = require(script.Parent:WaitForChild("DungeonMenuNet"))

-- NPCRequest is created by NPCService at server start; wait with timeout
local GameEvents = ReplicatedStorage:WaitForChild("GameEvents", 10)
local NPCRequest = GameEvents and GameEvents:WaitForChild("NPCRequest", 10)
if not NPCRequest then
    warn("[NPCClient] NPCRequest RemoteFunction not found — shop purchases disabled")
end

-- DungeonProfilePush keeps coin wallet fresh
local ProfilePush = ReplicatedStorage:WaitForChild("DungeonProfilePush", 10)

---------------------------------------------------------------------------
-- Wallet state (refreshed by DungeonProfilePush)
---------------------------------------------------------------------------

local cachedWallet = 0

if ProfilePush then
    ProfilePush.OnClientEvent:Connect(function(payload)
        if payload and payload.profile and payload.profile.currencies then
            cachedWallet = payload.profile.currencies.Coins or 0
        end
    end)
end

---------------------------------------------------------------------------
-- NPCShopUI  – single ScreenGui, repopulated each time it opens
---------------------------------------------------------------------------

local shopOpen    = false
local currentNpcId = nil

local shopGui = Instance.new("ScreenGui")
shopGui.Name           = "NPCShopUI"
shopGui.ResetOnSpawn   = false
shopGui.IgnoreGuiInset = true
shopGui.DisplayOrder   = 140
shopGui.Enabled        = false
shopGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
shopGui.Parent         = playerGui

-- Dim backdrop (click to close)
local dim = Instance.new("TextButton")
dim.Name                   = "Dim"
dim.Size                   = UDim2.fromScale(1, 1)
dim.BackgroundColor3       = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 0.45
dim.BorderSizePixel        = 0
dim.Text                   = ""
dim.AutoButtonColor        = false
dim.ZIndex                 = 1
dim.Parent                 = shopGui

-- Main panel
local panel = Instance.new("Frame")
panel.Name             = "Panel"
panel.AnchorPoint      = Vector2.new(0.5, 0.5)
panel.Position         = UDim2.new(0.5, 0, 0.45, 0)
panel.Size             = UDim2.fromOffset(480, 440)
panel.BackgroundColor3 = Color3.fromRGB(30, 22, 22)
panel.BorderSizePixel  = 0
panel.ZIndex           = 2
panel.Parent           = shopGui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)
local panelStroke = Instance.new("UIStroke", panel)
panelStroke.Thickness = 1
panelStroke.Color     = Color3.fromRGB(90, 70, 70)

-- Title
local titleLabel = Instance.new("TextLabel")
titleLabel.Name                   = "Title"
titleLabel.BackgroundTransparency = 1
titleLabel.Size                   = UDim2.new(1, -52, 0, 36)
titleLabel.Position               = UDim2.new(0, 12, 0, 8)
titleLabel.Font                   = Enum.Font.GothamBold
titleLabel.TextSize               = 22
titleLabel.TextXAlignment         = Enum.TextXAlignment.Left
titleLabel.TextColor3             = Color3.new(1, 1, 1)
titleLabel.Text                   = "Shop"
titleLabel.ZIndex                 = 3
titleLabel.Parent                 = panel

-- Close button
local closeBtn = Instance.new("TextButton")
closeBtn.Name             = "CloseBtn"
closeBtn.Size             = UDim2.fromOffset(32, 32)
closeBtn.Position         = UDim2.new(1, -40, 0, 8)
closeBtn.BackgroundColor3 = Color3.fromRGB(60, 40, 40)
closeBtn.Font             = Enum.Font.GothamBold
closeBtn.TextSize         = 18
closeBtn.TextColor3       = Color3.fromRGB(220, 180, 180)
closeBtn.Text             = "X"
closeBtn.ZIndex           = 4
closeBtn.Parent           = panel
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)

-- Balance bar
local balanceLabel = Instance.new("TextLabel")
balanceLabel.Name                   = "BalanceLabel"
balanceLabel.BackgroundTransparency = 1
balanceLabel.Size                   = UDim2.new(1, -24, 0, 24)
balanceLabel.Position               = UDim2.new(0, 12, 0, 50)
balanceLabel.Font                   = Enum.Font.GothamMedium
balanceLabel.TextSize               = 15
balanceLabel.TextXAlignment         = Enum.TextXAlignment.Left
balanceLabel.TextColor3             = Color3.fromRGB(255, 215, 100)
balanceLabel.Text                   = "Wallet: 0 Coins"
balanceLabel.ZIndex                 = 3
balanceLabel.Parent                 = panel

-- Status label (purchase feedback)
local statusLabel = Instance.new("TextLabel")
statusLabel.Name                   = "StatusLabel"
statusLabel.BackgroundTransparency = 1
statusLabel.Size                   = UDim2.new(1, -24, 0, 22)
statusLabel.Position               = UDim2.new(0, 12, 0, 76)
statusLabel.Font                   = Enum.Font.GothamMedium
statusLabel.TextSize               = 13
statusLabel.TextXAlignment         = Enum.TextXAlignment.Center
statusLabel.TextColor3             = Color3.fromRGB(200, 200, 200)
statusLabel.Text                   = ""
statusLabel.ZIndex                 = 3
statusLabel.Parent                 = panel

-- Separator
local sep = Instance.new("Frame")
sep.Size             = UDim2.new(1, -24, 0, 1)
sep.Position         = UDim2.new(0, 12, 0, 104)
sep.BackgroundColor3 = Color3.fromRGB(90, 70, 70)
sep.BorderSizePixel  = 0
sep.ZIndex           = 3
sep.Parent           = panel

-- Merchant offer showcase card (hidden for non-merchant NPCs)
local offerFrame = Instance.new("Frame")
offerFrame.Name = "OfferCard"
offerFrame.Size = UDim2.new(1, -24, 0, 56)
offerFrame.Position = UDim2.new(0, 12, 0, 112)
offerFrame.BackgroundColor3 = Color3.fromRGB(48, 36, 30)
offerFrame.BorderSizePixel = 0
offerFrame.ZIndex = 3
offerFrame.Visible = false
offerFrame.Parent = panel
Instance.new("UICorner", offerFrame).CornerRadius = UDim.new(0, 8)
local offerStroke = Instance.new("UIStroke", offerFrame)
offerStroke.Thickness = 1
offerStroke.Color = Color3.fromRGB(150, 120, 80)

local offerTitle = Instance.new("TextLabel")
offerTitle.Name = "Title"
offerTitle.BackgroundTransparency = 1
offerTitle.Size = UDim2.new(1, -16, 0, 20)
offerTitle.Position = UDim2.new(0, 8, 0, 4)
offerTitle.Font = Enum.Font.GothamBold
offerTitle.TextSize = 13
offerTitle.TextXAlignment = Enum.TextXAlignment.Left
offerTitle.TextColor3 = Color3.fromRGB(255, 220, 140)
offerTitle.Text = "Merchant Offer"
offerTitle.ZIndex = 4
offerTitle.Parent = offerFrame

local offerText = Instance.new("TextLabel")
offerText.Name = "OfferText"
offerText.BackgroundTransparency = 1
offerText.Size = UDim2.new(1, -16, 0, 28)
offerText.Position = UDim2.new(0, 8, 0, 24)
offerText.Font = Enum.Font.GothamMedium
offerText.TextSize = 14
offerText.TextXAlignment = Enum.TextXAlignment.Left
offerText.TextColor3 = Color3.fromRGB(235, 235, 235)
offerText.Text = "Trade 1 Coal for 1 T1 Scrap"
offerText.ZIndex = 4
offerText.Parent = offerFrame

-- Scrolling item list
local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Name                   = "ItemList"
scrollFrame.Size                   = UDim2.new(1, -24, 1, -116)
scrollFrame.Position               = UDim2.new(0, 12, 0, 108)
scrollFrame.BackgroundTransparency = 1
scrollFrame.BorderSizePixel        = 0
scrollFrame.ScrollBarThickness     = 6
scrollFrame.ScrollBarImageColor3   = Color3.fromRGB(90, 70, 70)
scrollFrame.AutomaticCanvasSize    = Enum.AutomaticSize.Y
scrollFrame.CanvasSize             = UDim2.new(0, 0, 0, 0)
scrollFrame.ZIndex                 = 3
scrollFrame.Parent                 = panel
local listLayout = Instance.new("UIListLayout", scrollFrame)
listLayout.Padding   = UDim.new(0, 6)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
local listPad = Instance.new("UIPadding", scrollFrame)
listPad.PaddingTop    = UDim.new(0, 4)
listPad.PaddingBottom = UDim.new(0, 6)

---------------------------------------------------------------------------
-- UI helpers
---------------------------------------------------------------------------

local function updateBalance()
    balanceLabel.Text = string.format("Wallet: %d Coins", cachedWallet)
end

local function showStatus(text, isErr)
    statusLabel.Text       = text
    statusLabel.TextColor3 = isErr
        and Color3.fromRGB(255, 120, 120)
        or  Color3.fromRGB(120, 255, 120)
    task.delay(3, function()
        if statusLabel.Text == text then statusLabel.Text = "" end
    end)
end

local function setShopOpen(v)
    if v == shopOpen then return end
    shopOpen    = v
    shopGui.Enabled = v
    if v then
        MenuMouse.acquire()
        updateBalance()
        statusLabel.Text = ""
    else
        MenuMouse.release()
        currentNpcId = nil
    end
end

local function clearItemList()
    for _, child in ipairs(scrollFrame:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end
end

-- Error messages shown to the player
local ERR_MESSAGES = {
    insufficient_funds = "Not enough currency.",
    inventory_full     = "Your inventory is full.",
    throttled          = "Too fast — wait a moment.",
    too_far            = "Move closer to the NPC.",
    npc_not_found      = "NPC not found.",
    not_in_catalog     = "Item not available here.",
    server_error       = "Server error. Try again.",
}

local function buildItemRow(entry, npcId, layoutOrder)
    local row = Instance.new("Frame")
    row.Name             = "Row_" .. entry.ItemId
    row.Size             = UDim2.new(1, 0, 0, 52)
    row.BackgroundColor3 = Color3.fromRGB(40, 30, 30)
    row.BorderSizePixel  = 0
    row.LayoutOrder      = layoutOrder
    row.ZIndex           = 4
    row.Parent           = scrollFrame
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

    -- Item name
    local nameLabel = Instance.new("TextLabel")
    nameLabel.BackgroundTransparency = 1
    nameLabel.Size           = UDim2.new(1, -140, 1, 0)
    nameLabel.Position       = UDim2.new(0, 12, 0, 0)
    nameLabel.Font           = Enum.Font.GothamMedium
    nameLabel.TextSize       = 15
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.TextColor3     = Color3.new(1, 1, 1)
    nameLabel.Text           = entry.Label
    nameLabel.ZIndex         = 5
    nameLabel.Parent         = row

    -- Price
    local priceLabel = Instance.new("TextLabel")
    priceLabel.BackgroundTransparency = 1
    priceLabel.Size           = UDim2.new(0, 80, 1, 0)
    priceLabel.Position       = UDim2.new(1, -148, 0, 0)
    priceLabel.Font           = Enum.Font.Gotham
    priceLabel.TextSize       = 13
    priceLabel.TextXAlignment = Enum.TextXAlignment.Right
    priceLabel.TextColor3     = Color3.fromRGB(255, 215, 100)
    priceLabel.Text           = tostring(entry.Price) .. " " .. (entry.Currency or "Coins")
    priceLabel.ZIndex         = 5
    priceLabel.Parent         = row

    -- Buy button
    local buyBtn = Instance.new("TextButton")
    buyBtn.Size             = UDim2.fromOffset(68, 34)
    buyBtn.AnchorPoint      = Vector2.new(1, 0.5)
    buyBtn.Position         = UDim2.new(1, -8, 0.5, 0)
    buyBtn.BackgroundColor3 = Color3.fromRGB(40, 80, 40)
    buyBtn.Font             = Enum.Font.GothamBold
    buyBtn.TextSize         = 14
    buyBtn.TextColor3       = Color3.new(1, 1, 1)
    buyBtn.Text             = "Buy"
    buyBtn.ZIndex           = 5
    buyBtn.Parent           = row
    Instance.new("UICorner", buyBtn).CornerRadius = UDim.new(0, 6)

    buyBtn.Activated:Connect(function()
        if not NPCRequest then
            showStatus("Shop service unavailable.", true)
            return
        end
        buyBtn.Text   = "..."
        buyBtn.Active = false

        local ok, result = pcall(function()
            return NPCRequest:InvokeServer({
                npcId  = npcId,
                action = "BuyItem",
                itemId = entry.ItemId,
                qty    = 1,
            })
        end)

        buyBtn.Text   = "Buy"
        buyBtn.Active = true

        if not ok then
            showStatus("Server error.", true)
            return
        end

        if result.ok then
            cachedWallet = result.wallet or cachedWallet
            updateBalance()
            showStatus("Purchased: " .. entry.Label, false)
        else
            local msg = ERR_MESSAGES[result.err]
                or ("Error: " .. tostring(result.err))
            showStatus(msg, true)
        end
    end)

    return row
end

---------------------------------------------------------------------------
-- Open / close shop
---------------------------------------------------------------------------

local function openShop(npcId, npcType, npcDisplayName)
    if wiredNpcIds[npcId] then
        return
    end

    local reg = NPCRegistry.Get(npcType)
    if not reg or not reg.ShopCatalog or #reg.ShopCatalog == 0 then
        warn("[NPCClient] No ShopCatalog for NpcType: " .. tostring(npcType))
        return
    end

    currentNpcId    = npcId
    titleLabel.Text = npcDisplayName .. "  —  Shop"

    local showcaseOffer = nil
    for _, row in ipairs(reg.ShopCatalog) do
        if row.Currency and row.Currency ~= "Coins" then
            showcaseOffer = row
            break
        end
    end

    if npcType == "Merchant" and showcaseOffer then
        offerText.Text = string.format("Trade %d %s for %d %s", showcaseOffer.Price or 1, showcaseOffer.Currency or "Item", showcaseOffer.Qty or 1, showcaseOffer.Label or showcaseOffer.ItemId or "Item")
        offerFrame.Visible = true
        scrollFrame.Position = UDim2.new(0, 12, 0, 174)
        scrollFrame.Size = UDim2.new(1, -24, 1, -182)
    else
        offerFrame.Visible = false
        scrollFrame.Position = UDim2.new(0, 12, 0, 108)
        scrollFrame.Size = UDim2.new(1, -24, 1, -116)
    end

    clearItemList()
    for i, entry in ipairs(reg.ShopCatalog) do
        buildItemRow(entry, npcId, i)
    end

    setShopOpen(true)
end

-- Close handlers
dim.Activated:Connect(function() setShopOpen(false) end)
closeBtn.Activated:Connect(function() setShopOpen(false) end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if UserInputService:GetFocusedTextBox() then return end
    if input.KeyCode == Keys.CloseMenu and shopOpen then
        setShopOpen(false)
    end
end)

-- Keep balance label fresh while the panel is open
if ProfilePush then
    ProfilePush.OnClientEvent:Connect(function(payload)
        if not shopOpen then return end
        if payload and payload.profile and payload.profile.currencies then
            cachedWallet = payload.profile.currencies.Coins or cachedWallet
            updateBalance()
        end
    end)
end

---------------------------------------------------------------------------
-- Dialogue tree builder
---------------------------------------------------------------------------

-- Default greetings per NPC type (flavour text can be overridden per-NPC later)
local GREETINGS = {
    Merchant     = "The markets thin out here, but my wares are sound. What do you need?",
    SkillTrainer = "Looking to get equipped? I keep only quality tools.",
    Innkeeper    = "Rest easy, traveler. I manage the roads between here and beyond.",
    Dungeoneer   = "You want dungeon work? I have what you need — for a price.",
    Blacksmith   = "I can restore what the dungeon breaks. Bring your gear.",
    Miner        = "These veins don't mine themselves. You pickin' up what I'm puttin' down?",
    Fisherman    = "The river's generous if you know how to ask. Need a line in the water?",
}

local function buildDialogue(dialogue, npcId, npcType, npcName, reg)
    local greeting       = GREETINGS[npcType] or "What brings you to me, stranger?"
    local shopPrompt     = reg.OpenShopPrompt or "Browse Wares"
    local repairPrompt   = reg.OpenRepairPrompt or "Repair Equipment"
    local hasShop        = reg.ShopCatalog and #reg.ShopCatalog > 0
    local hasRepair      = NPCRegistry.AllowsAction(npcType, "RepairItem")

    -- Build response options dynamically
    local responses = {}
    if hasShop then
        table.insert(responses, shopPrompt)
    end
    if hasRepair then
        table.insert(responses, repairPrompt)
    end
    table.insert(responses, "Goodbye.")

    dialogue:addDialog(greeting, responses)

    -- Calculate option indices
    local idx = 0
    local shopIdx, repairIdx, goodbyeIdx
    if hasShop   then idx += 1; shopIdx   = idx end
    if hasRepair  then idx += 1; repairIdx = idx end
    goodbyeIdx = idx + 1  -- always last

    dialogue.responded:Connect(function(responseNum, dialogNum)
        if dialogNum == 1 then
            if shopIdx and responseNum == shopIdx then
                dialogue:hideGui(nil, true)
                task.delay(0.15, function()
                    openShop(npcId, npcType, npcName)
                end)
            elseif repairIdx and responseNum == repairIdx then
                dialogue:hideGui(nil, true)
                task.delay(0.15, function()
                    openAnvil(npcId, npcType, npcName)
                end)
            elseif responseNum == goodbyeIdx then
                dialogue:hideGui("Until next time.")
            end
        end
    end)
end

local function buildQuestDialogue(dialogue, npcId, npcType, npcName, _reg)
    local questText = string.format(
        "Hail, traveler. I am %s. I need your help! These bandits have taken over my home. I need you to kill some of them. Will you help me?",
        npcName
    )
    dialogue:addDialog(questText, { "Yes, I accept the quest.", "Not right now." })
    dialogue.responded:Connect(function(responseNum, dialogNum)
        if dialogNum ~= 1 then
            return
        end
        if responseNum == 1 then
            if not NPCRequest then
                dialogue:hideGui("Server link missing — try again later.")
                return
            end
            local ok, res = pcall(function()
                return NPCRequest:InvokeServer({ npcId = npcId, action = "TalkCusoQuest" })
            end)
            local msg = "Could not update quest."
            if ok and type(res) == "table" then
                if res.ok and type(res.msg) == "string" then
                    msg = res.msg
                elseif type(res.err) == "string" then
                    msg = res.err
                end
            elseif not ok then
                msg = "Request failed."
            end
            dialogue:hideGui(msg)
        elseif responseNum == 2 then
            dialogue:hideGui("Come back if you change your mind.")
        end
    end)
end

local function buildMinerQuestDialogue(dialogue, npcId, npcType, npcName, _reg)
    local questText = string.format(
        "Hey there, kiddo. I need some help mining some coal. Here, I've got a spare wooden pickaxe for you. Right click it in your inventory to equip it. Mine five lumps from the coal veins and I'll make it worth your coin. You in?"
      
    )
    dialogue:addDialog(questText, { "Yes, I'll gather the coal.", "Not right now." })
    dialogue.responded:Connect(function(responseNum, dialogNum)
        if dialogNum ~= 1 then
            return
        end
        if responseNum == 1 then
            if not NPCRequest then
                dialogue:hideGui("Server link missing — try again later.")
                return
            end
            local ok, res = pcall(function()
                return NPCRequest:InvokeServer({ npcId = npcId, action = "TalkMinerCoalQuest" })
            end)
            local msg = "Could not update quest."
            if ok and type(res) == "table" then
                if res.ok and type(res.msg) == "string" then
                    msg = res.msg
                elseif type(res.err) == "string" then
                    msg = res.err
                end
            elseif not ok then
                msg = "Request failed."
            end
            dialogue:hideGui(msg)
        elseif responseNum == 2 then
            dialogue:hideGui("Suit yourself — the veins will wait.")
        end
    end)
end

local function buildMinerActiveDialogue(dialogue, npcId, npcType, npcName, _reg)
    local t = string.format(
        "You've still got an open coal contract with the forge. Want a progress check?"
       
    )
    dialogue:addDialog(t, { "How's my haul?", "I'll get back to it." })
    dialogue.responded:Connect(function(responseNum, dialogNum)
        if dialogNum ~= 1 then
            return
        end
        if responseNum == 1 then
            if not NPCRequest then
                dialogue:hideGui("Server link missing — try again later.")
                return
            end
            local ok, res = pcall(function()
                return NPCRequest:InvokeServer({ npcId = npcId, action = "TalkMinerCoalQuest" })
            end)
            local msg = "Could not check progress."
            if ok and type(res) == "table" then
                if res.ok and type(res.msg) == "string" then
                    msg = res.msg
                elseif type(res.err) == "string" then
                    msg = res.err
                end
            elseif not ok then
                msg = "Request failed."
            end
            dialogue:hideGui(msg)
        elseif responseNum == 2 then
            dialogue:hideGui("Coal won't haul itself — good luck out there.")
        end
    end)
end

local function buildFishermanQuestDialogue(dialogue, npcId, npcType, npcName, _reg)
    local questText = string.format(
        "Ahoy. wanna help me get some fish. I have a spare Wooden Spear. The camp needs fresh fish and I'm stuck untangling the nets. Spear five honest catches from this river and I'll make it worth your while. You in?"
       
    )
    dialogue:addDialog(questText, { "Yes, I'll fish.", "Not right now." })
    dialogue.responded:Connect(function(responseNum, dialogNum)
        if dialogNum ~= 1 then
            return
        end
        if responseNum == 1 then
            if not NPCRequest then
                dialogue:hideGui("Server link missing — try again later.")
                return
            end
            local ok, res = pcall(function()
                return NPCRequest:InvokeServer({ npcId = npcId, action = "TalkFishermanFishQuest" })
            end)
            local msg = "Could not update quest."
            if ok and type(res) == "table" then
                if res.ok and type(res.msg) == "string" then
                    msg = res.msg
                elseif type(res.err) == "string" then
                    msg = res.err
                end
            elseif not ok then
                msg = "Request failed."
            end
            dialogue:hideGui(msg)
        elseif responseNum == 2 then
            dialogue:hideGui("The river keeps its own schedule — come back when you're ready.")
        end
    end)
end

local function buildFishermanActiveDialogue(dialogue, npcId, npcType, npcName, _reg)
    local t = string.format(
        "You getting lazy or what? Want a progress check?"
       
    )
    dialogue:addDialog(t, { "How's my catch?", "I'll get back to it." })
    dialogue.responded:Connect(function(responseNum, dialogNum)
        if dialogNum ~= 1 then
            return
        end
        if responseNum == 1 then
            if not NPCRequest then
                dialogue:hideGui("Server link missing — try again later.")
                return
            end
            local ok, res = pcall(function()
                return NPCRequest:InvokeServer({ npcId = npcId, action = "TalkFishermanFishQuest" })
            end)
            local msg = "Could not check progress."
            if ok and type(res) == "table" then
                if res.ok and type(res.msg) == "string" then
                    msg = res.msg
                elseif type(res.err) == "string" then
                    msg = res.err
                end
            elseif not ok then
                msg = "Request failed."
            end
            dialogue:hideGui(msg)
        elseif responseNum == 2 then
            dialogue:hideGui("Tight lines — don't keep the kitchen waiting.")
        end
    end)
end

---------------------------------------------------------------------------
-- Anvil / Repair UI
---------------------------------------------------------------------------

local anvilOpen     = false
local anvilNpcId    = nil
local selectedItem  = nil  -- uuid of item placed on anvil

local anvilGui = Instance.new("ScreenGui")
anvilGui.Name           = "AnvilUI"
anvilGui.ResetOnSpawn   = false
anvilGui.IgnoreGuiInset = true
anvilGui.DisplayOrder   = 135
anvilGui.Enabled        = false
anvilGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
anvilGui.Parent         = playerGui

-- Dim backdrop
local anvilDim = Instance.new("TextButton")
anvilDim.Name                   = "Dim"
anvilDim.Size                   = UDim2.fromScale(1, 1)
anvilDim.BackgroundColor3       = Color3.new(0, 0, 0)
anvilDim.BackgroundTransparency = 0.5
anvilDim.BorderSizePixel        = 0
anvilDim.Text                   = ""
anvilDim.AutoButtonColor        = false
anvilDim.ZIndex                 = 1
anvilDim.Parent                 = anvilGui

-- Main panel (wide: inventory left + anvil right)
local anvilPanel = Instance.new("Frame")
anvilPanel.Name             = "Panel"
anvilPanel.AnchorPoint      = Vector2.new(0.5, 0.5)
anvilPanel.Position         = UDim2.new(0.5, 0, 0.48, 0)
anvilPanel.Size             = UDim2.fromOffset(720, 480)
anvilPanel.BackgroundColor3 = Color3.fromRGB(28, 22, 18)
anvilPanel.BorderSizePixel  = 0
anvilPanel.ZIndex           = 2
anvilPanel.Parent           = anvilGui
Instance.new("UICorner", anvilPanel).CornerRadius = UDim.new(0, 12)
local anvilStroke = Instance.new("UIStroke", anvilPanel)
anvilStroke.Thickness = 1
anvilStroke.Color     = Color3.fromRGB(120, 90, 50)

-- Title
local anvilTitle = Instance.new("TextLabel")
anvilTitle.Name                   = "Title"
anvilTitle.BackgroundTransparency = 1
anvilTitle.Size                   = UDim2.new(1, -52, 0, 36)
anvilTitle.Position               = UDim2.new(0, 12, 0, 8)
anvilTitle.Font                   = Enum.Font.GothamBold
anvilTitle.TextSize               = 22
anvilTitle.TextXAlignment         = Enum.TextXAlignment.Left
anvilTitle.TextColor3             = Color3.fromRGB(255, 210, 120)
anvilTitle.Text                   = "Anvil — Repair Equipment"
anvilTitle.ZIndex                 = 3
anvilTitle.Parent                 = anvilPanel

-- Close button
local anvilClose = Instance.new("TextButton")
anvilClose.Name             = "CloseBtn"
anvilClose.Size             = UDim2.fromOffset(32, 32)
anvilClose.Position         = UDim2.new(1, -40, 0, 8)
anvilClose.BackgroundColor3 = Color3.fromRGB(80, 50, 30)
anvilClose.Font             = Enum.Font.GothamBold
anvilClose.TextSize         = 18
anvilClose.TextColor3       = Color3.fromRGB(220, 180, 140)
anvilClose.Text             = "X"
anvilClose.ZIndex           = 4
anvilClose.Parent           = anvilPanel
Instance.new("UICorner", anvilClose).CornerRadius = UDim.new(0, 8)

-- Separator
local anvilSep = Instance.new("Frame")
anvilSep.Size             = UDim2.new(1, -24, 0, 1)
anvilSep.Position         = UDim2.new(0, 12, 0, 48)
anvilSep.BackgroundColor3 = Color3.fromRGB(100, 75, 40)
anvilSep.BorderSizePixel  = 0
anvilSep.ZIndex           = 3
anvilSep.Parent           = anvilPanel

---------------------------------------------------------------------------
-- Left column: player inventory (weapons & armor)
---------------------------------------------------------------------------

local invLabel = Instance.new("TextLabel")
invLabel.Name                   = "InvLabel"
invLabel.BackgroundTransparency = 1
invLabel.Size                   = UDim2.new(0.5, -16, 0, 22)
invLabel.Position               = UDim2.new(0, 12, 0, 56)
invLabel.Font                   = Enum.Font.GothamBold
invLabel.TextSize               = 14
invLabel.TextXAlignment         = Enum.TextXAlignment.Left
invLabel.TextColor3             = Color3.fromRGB(200, 190, 170)
invLabel.Text                   = "Your Equipment"
invLabel.ZIndex                 = 3
invLabel.Parent                 = anvilPanel

local invScroll = Instance.new("ScrollingFrame")
invScroll.Name                   = "InvScroll"
invScroll.Size                   = UDim2.new(0.5, -16, 1, -90)
invScroll.Position               = UDim2.new(0, 12, 0, 82)
invScroll.BackgroundColor3       = Color3.fromRGB(18, 14, 10)
invScroll.BorderSizePixel        = 0
invScroll.ScrollBarThickness     = 6
invScroll.ScrollBarImageColor3   = Color3.fromRGB(100, 75, 40)
invScroll.AutomaticCanvasSize    = Enum.AutomaticSize.Y
invScroll.CanvasSize             = UDim2.new()
invScroll.ZIndex                 = 3
invScroll.Parent                 = anvilPanel
Instance.new("UICorner", invScroll).CornerRadius = UDim.new(0, 8)

local invGrid = Instance.new("UIGridLayout")
invGrid.CellSize        = UDim2.fromOffset(200, 72)
invGrid.CellPadding     = UDim2.fromOffset(6, 6)
invGrid.SortOrder       = Enum.SortOrder.LayoutOrder
invGrid.FillDirectionMaxCells = 2
invGrid.Parent          = invScroll

local invPad = Instance.new("UIPadding")
invPad.PaddingTop    = UDim.new(0, 6)
invPad.PaddingLeft   = UDim.new(0, 6)
invPad.PaddingRight  = UDim.new(0, 6)
invPad.PaddingBottom = UDim.new(0, 6)
invPad.Parent        = invScroll

---------------------------------------------------------------------------
-- Right column: anvil / repair slot
---------------------------------------------------------------------------

local anvilLabel = Instance.new("TextLabel")
anvilLabel.Name                   = "AnvilLabel"
anvilLabel.BackgroundTransparency = 1
anvilLabel.Size                   = UDim2.new(0.5, -16, 0, 22)
anvilLabel.Position               = UDim2.new(0.5, 4, 0, 56)
anvilLabel.Font                   = Enum.Font.GothamBold
anvilLabel.TextSize               = 14
anvilLabel.TextXAlignment         = Enum.TextXAlignment.Left
anvilLabel.TextColor3             = Color3.fromRGB(255, 210, 120)
anvilLabel.Text                   = "Anvil"
anvilLabel.ZIndex                 = 3
anvilLabel.Parent                 = anvilPanel

-- Drop zone / selected item display
local dropZone = Instance.new("TextButton")
dropZone.Name             = "DropZone"
dropZone.Size             = UDim2.new(0.5, -16, 0, 100)
dropZone.Position         = UDim2.new(0.5, 4, 0, 82)
dropZone.BackgroundColor3 = Color3.fromRGB(40, 30, 20)
dropZone.BorderSizePixel  = 0
dropZone.Font             = Enum.Font.GothamMedium
dropZone.TextSize         = 16
dropZone.TextColor3       = Color3.fromRGB(180, 160, 130)
dropZone.TextWrapped      = true
dropZone.Text             = "Click an item from your inventory\nor drag it here"
dropZone.ZIndex           = 3
dropZone.AutoButtonColor  = true
dropZone.Parent           = anvilPanel
Instance.new("UICorner", dropZone).CornerRadius = UDim.new(0, 10)
local dropStroke = Instance.new("UIStroke", dropZone)
dropStroke.Thickness = 2
dropStroke.Color     = Color3.fromRGB(100, 75, 40)
dropStroke.Transparency = 0.5

-- Durability bar area
local durFrame = Instance.new("Frame")
durFrame.Name             = "DurabilityFrame"
durFrame.Size             = UDim2.new(0.5, -16, 0, 50)
durFrame.Position         = UDim2.new(0.5, 4, 0, 192)
durFrame.BackgroundTransparency = 1
durFrame.ZIndex           = 3
durFrame.Parent           = anvilPanel

local durLabel = Instance.new("TextLabel")
durLabel.Name                   = "DurLabel"
durLabel.BackgroundTransparency = 1
durLabel.Size                   = UDim2.new(1, 0, 0, 18)
durLabel.Font                   = Enum.Font.GothamMedium
durLabel.TextSize               = 13
durLabel.TextXAlignment         = Enum.TextXAlignment.Left
durLabel.TextColor3             = Color3.fromRGB(200, 190, 170)
durLabel.Text                   = "Durability"
durLabel.ZIndex                 = 4
durLabel.Parent                 = durFrame

local durBarBg = Instance.new("Frame")
durBarBg.Name             = "BarBg"
durBarBg.Size             = UDim2.new(1, 0, 0, 14)
durBarBg.Position         = UDim2.new(0, 0, 0, 20)
durBarBg.BackgroundColor3 = Color3.fromRGB(30, 22, 16)
durBarBg.BorderSizePixel  = 0
durBarBg.ZIndex           = 4
durBarBg.Parent           = durFrame
Instance.new("UICorner", durBarBg).CornerRadius = UDim.new(0, 6)

local durBarFill = Instance.new("Frame")
durBarFill.Name             = "BarFill"
durBarFill.Size             = UDim2.fromScale(1, 1)
durBarFill.BackgroundColor3 = Color3.fromRGB(80, 200, 100)
durBarFill.BorderSizePixel  = 0
durBarFill.ZIndex           = 5
durBarFill.Parent           = durBarBg
Instance.new("UICorner", durBarFill).CornerRadius = UDim.new(0, 6)

local durText = Instance.new("TextLabel")
durText.Name                   = "DurText"
durText.BackgroundTransparency = 1
durText.Size                   = UDim2.new(1, 0, 1, 0)
durText.Font                   = Enum.Font.GothamBold
durText.TextSize               = 11
durText.TextColor3             = Color3.new(1, 1, 1)
durText.Text                   = "100%"
durText.ZIndex                 = 6
durText.Parent                 = durBarBg

-- Repair cost label
local costLabel = Instance.new("TextLabel")
costLabel.Name                   = "CostLabel"
costLabel.BackgroundTransparency = 1
costLabel.Size                   = UDim2.new(0.5, -16, 0, 20)
costLabel.Position               = UDim2.new(0.5, 4, 0, 248)
costLabel.Font                   = Enum.Font.GothamMedium
costLabel.TextSize               = 13
costLabel.TextXAlignment         = Enum.TextXAlignment.Left
costLabel.TextColor3             = Color3.fromRGB(255, 215, 100)
costLabel.Text                   = ""
costLabel.ZIndex                 = 3
costLabel.Parent                 = anvilPanel

-- Repair button
local repairBtn = Instance.new("TextButton")
repairBtn.Name             = "RepairBtn"
repairBtn.Size             = UDim2.new(0.5, -16, 0, 40)
repairBtn.Position         = UDim2.new(0.5, 4, 0, 274)
repairBtn.BackgroundColor3 = Color3.fromRGB(60, 120, 60)
repairBtn.Font             = Enum.Font.GothamBold
repairBtn.TextSize         = 16
repairBtn.TextColor3       = Color3.new(1, 1, 1)
repairBtn.Text             = "Repair"
repairBtn.ZIndex           = 3
repairBtn.AutoButtonColor  = true
repairBtn.Parent           = anvilPanel
Instance.new("UICorner", repairBtn).CornerRadius = UDim.new(0, 8)

-- Status label
local anvilStatus = Instance.new("TextLabel")
anvilStatus.Name                   = "Status"
anvilStatus.BackgroundTransparency = 1
anvilStatus.Size                   = UDim2.new(0.5, -16, 0, 22)
anvilStatus.Position               = UDim2.new(0.5, 4, 0, 322)
anvilStatus.Font                   = Enum.Font.GothamMedium
anvilStatus.TextSize               = 13
anvilStatus.TextXAlignment         = Enum.TextXAlignment.Center
anvilStatus.TextColor3             = Color3.fromRGB(200, 200, 200)
anvilStatus.Text                   = ""
anvilStatus.ZIndex                 = 3
anvilStatus.Parent                 = anvilPanel

---------------------------------------------------------------------------
-- Anvil helpers
---------------------------------------------------------------------------

local function clearInvScroll()
    for _, child in ipairs(invScroll:GetChildren()) do
        if not child:IsA("UIGridLayout") and not child:IsA("UIPadding") then
            child:Destroy()
        end
    end
end

local function getLatestProfile()
    local snap = DungeonMenuNet.getLastSnapshot()
    if snap and snap.profile then
        return snap.profile
    end
    return nil
end

local function isRepairable(item)
    if type(item) ~= "table" then return false end
    local kind = item.type
    return kind == "Weapon" or kind == "Armor" or (kind == "Material" and item.equipSlot)
end

local function getDurability(item)
    -- Placeholder: returns 100 until durability system is implemented
    -- When durability is added, read from item.durability / item.maxDurability
    if type(item) ~= "table" then return 100, 100 end
    if type(item.durability) == "number" and type(item.maxDurability) == "number" then
        return item.durability, item.maxDurability
    end
    return 100, 100
end

local function setAnvilState(open)
    if open == anvilOpen then return end
    anvilOpen     = open
    anvilGui.Enabled = open
    if open then
        MenuMouse.acquire()
        selectedItem = nil
        refreshAnvilInventory()
        updateAnvilSlot()
    else
        MenuMouse.release()
        selectedItem = nil
        anvilStatus.Text = ""
    end
end

local function showAnvilStatus(text, isErr)
    anvilStatus.Text       = text
    anvilStatus.TextColor3 = isErr
        and Color3.fromRGB(255, 120, 120)
        or  Color3.fromRGB(120, 255, 120)
    task.delay(3, function()
        if anvilStatus.Text == text then anvilStatus.Text = "" end
    end)
end

function updateAnvilSlot()
    local profile = getLatestProfile()
    local inv = profile and profile.inventory or {}

    if selectedItem and inv[selectedItem] then
        local item = inv[selectedItem]
        local name = item.name or item.itemId or "Item"
        local dur, maxDur = getDurability(item)
        local pct = maxDur > 0 and (dur / maxDur) or 1

        dropZone.Text = name
        dropZone.TextColor3 = Types.GetRarityColor(item.rarity)
        dropZone.BackgroundColor3 = Color3.fromRGB(50, 38, 26)

        durLabel.Text = string.format("Durability  %d / %d", dur, maxDur)
        durBarFill.Size = UDim2.fromScale(pct, 1)
        durBarFill.BackgroundColor3 = pct >= 0.75
            and Color3.fromRGB(80, 200, 100)
            or pct >= 0.4
                and Color3.fromRGB(220, 180, 50)
                or Color3.fromRGB(220, 60, 60)
        durText.Text = string.format("%d%%", math.floor(pct * 100))

        durFrame.Visible = true

        if pct >= 1 then
            costLabel.Text = "No repair needed."
            repairBtn.Text = "Repair"
            repairBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
            repairBtn.TextColor3 = Color3.fromRGB(120, 120, 120)
            repairBtn.Active = false
        else
            local reg = NPCRegistry.Get(item.npcType or "Blacksmith")
            local costPer = reg and reg.RepairCostPerPt or 2
            local ptsLost = maxDur - dur
            local cost = ptsLost * costPer
            costLabel.Text = string.format("Cost: %d Coins", cost)
            repairBtn.Text = string.format("Repair (%d Coins)", cost)
            repairBtn.BackgroundColor3 = Color3.fromRGB(60, 120, 60)
            repairBtn.TextColor3 = Color3.new(1, 1, 1)
            repairBtn.Active = true
        end
    else
        selectedItem = nil
        dropZone.Text = "Click an item from your inventory\nor drag it here"
        dropZone.TextColor3 = Color3.fromRGB(180, 160, 130)
        dropZone.BackgroundColor3 = Color3.fromRGB(40, 30, 20)
        durFrame.Visible = false
        costLabel.Text = ""
        repairBtn.Text = "Repair"
        repairBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
        repairBtn.TextColor3 = Color3.fromRGB(120, 120, 120)
        repairBtn.Active = false
    end
end

function refreshAnvilInventory()
    clearInvScroll()
    local profile = getLatestProfile()
    if not profile then return end
    local inv = profile.inventory or {}
    local order = 1

    for uuid, item in pairs(inv) do
        if type(item) == "table" and isRepairable(item) then
            local btn = Instance.new("TextButton")
            btn.Name = "Item_" .. uuid
            btn.AutoButtonColor = true
            btn.Font = Enum.Font.GothamMedium
            btn.TextSize = 12
            btn.TextWrapped = true
            btn.TextXAlignment = Enum.TextXAlignment.Left
            btn.TextColor3 = Types.GetRarityColor(item.rarity)
            btn.BackgroundColor3 = Color3.fromRGB(28, 22, 18)
            btn.Size = UDim2.fromOffset(200, 72)
            btn.LayoutOrder = order
            order = order + 1

            local name = item.name or item.itemId or "Item"
            local dur, maxDur = getDurability(item)
            local pct = maxDur > 0 and math.floor((dur / maxDur) * 100) or 100
            btn.Text = string.format("%s\nDur: %d%%", name, pct)

            -- Highlight if currently selected
            if uuid == selectedItem then
                btn.BackgroundColor3 = Color3.fromRGB(60, 45, 30)
            end

            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, 8)
            corner.Parent = btn

            -- Click to place on anvil
            btn.MouseButton1Click:Connect(function()
                selectedItem = uuid
                updateAnvilSlot()
                refreshAnvilInventory()  -- re-render to highlight selection
            end)

            btn.Parent = invScroll
        end
    end
end

function openAnvil(npcId, npcType, npcName)
    anvilNpcId = npcId
    anvilTitle.Text = npcName .. "  —  Anvil"
    setAnvilState(true)
end

-- Close handlers
anvilDim.Activated:Connect(function() setAnvilState(false) end)
anvilClose.Activated:Connect(function() setAnvilState(false) end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if UserInputService:GetFocusedTextBox() then return end
    if input.KeyCode == Keys.CloseMenu and anvilOpen then
        setAnvilState(false)
    end
end)

-- Clicking the drop zone deselects
dropZone.Activated:Connect(function()
    if selectedItem then
        selectedItem = nil
        updateAnvilSlot()
        refreshAnvilInventory()
    end
end)

-- Repair button — wired up but not yet implemented server-side
repairBtn.Text             = "Repair  (Coming Soon)"
repairBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
repairBtn.TextColor3       = Color3.fromRGB(130, 130, 130)
repairBtn.Active           = false
repairBtn.Activated:Connect(function()
    -- TODO: implement RepairItem action in NPCService
    showAnvilStatus("Repair system coming soon.", false)
end)

-- Refresh inventory when profile updates
if ProfilePush then
    ProfilePush.OnClientEvent:Connect(function(payload)
        if not anvilOpen then return end
        if payload and payload.profile then
            refreshAnvilInventory()
            updateAnvilSlot()
        end
    end)
end

---------------------------------------------------------------------------
-- NPC factory
---------------------------------------------------------------------------

local wiredNpcIds = {}

local function setupNPC(model)
    local npcId   = model:GetAttribute("NpcId")
    local npcType = model:GetAttribute("NpcType")
    local npcName = model:GetAttribute("NpcName")

    if type(npcId) ~= "string" or type(npcType) ~= "string" or type(npcName) ~= "string" then
        return  -- missing required attributes, skip silently
    end
    if wiredNpcIds[npcId] then
        return
    end

    local reg = NPCRegistry.Get(npcType)
    if not reg then
        warn("[NPCClient] Unknown NpcType '" .. npcType .. "' on NPC: " .. npcId)
        return
    end

    local head = model:FindFirstChild("Head") or model:WaitForChild("Head", 8)
    if not head then
        warn("[NPCClient] NPC missing Head: " .. tostring(npcId))
        return
    end
    if not head:FindFirstChild("gui") then
        head:WaitForChild("gui", 20)
    end
    if not head:FindFirstChild("gui") then
        warn("[NPCClient] NPC missing Head.gui (dialog UI): " .. tostring(npcId))
        return
    end

    -- Support both R15 (HumanoidRootPart) and R6/custom (Torso) rigs
    local hrp = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso")
    if not hrp then
        warn("[NPCClient] NPC missing HRP/Torso: " .. tostring(npcId))
        return
    end

    local prompt = hrp:FindFirstChildOfClass("ProximityPrompt")
    if not prompt then
        local t0 = tick()
        while not prompt and tick() - t0 < 20 do
            prompt = hrp:FindFirstChildOfClass("ProximityPrompt")
            task.wait(0.05)
        end
    end
    if not prompt then
        warn("[NPCClient] NPC missing ProximityPrompt on root: " .. tostring(npcId))
        return
    end

    local ok, dialogue = pcall(function() return DialogModule.new(npcName, model, prompt, nil) end)
    if not ok or not dialogue then
        warn("[NPCClient] DialogModule.new failed for '" .. npcId .. "': " .. tostring(dialogue))
        return
    end

    if npcType == "QuestGiver" then
        buildQuestDialogue(dialogue, npcId, npcType, npcName, reg)
    elseif npcType == "Miner" then
        local snap = DungeonMenuNet.getLastSnapshot()
        local profile = snap and snap.profile
        local mq = profile and profile.flags and profile.flags.minerCoalQuest
        if type(mq) == "table" and mq.completed == true then
            buildDialogue(dialogue, npcId, npcType, npcName, reg)
        elseif type(mq) == "table" and mq.active == true then
            buildMinerActiveDialogue(dialogue, npcId, npcType, npcName, reg)
        else
            buildMinerQuestDialogue(dialogue, npcId, npcType, npcName, reg)
            -- After the first dialog line finishes typing, server handles Miner greet / pickaxe.
            dialogue._onDialogLinePrinted = function(_dlg, pl, dNum)
                if dNum ~= 1 then
                    return
                end
                if pl ~= player then
                    return
                end
                if not NPCRequest then
                    return
                end
                pcall(function()
                    NPCRequest:InvokeServer({ npcId = npcId, action = "TalkMinerGreet" })
                end)
            end
        end
    elseif npcType == "Fisherman" then
        local snap = DungeonMenuNet.getLastSnapshot()
        local profile = snap and snap.profile
        local fq = profile and profile.flags and profile.flags.fisherFishQuest
        if type(fq) == "table" and fq.completed == true then
            buildDialogue(dialogue, npcId, npcType, npcName, reg)
        elseif type(fq) == "table" and fq.active == true then
            buildFishermanActiveDialogue(dialogue, npcId, npcType, npcName, reg)
        else
            buildFishermanQuestDialogue(dialogue, npcId, npcType, npcName, reg)
            dialogue._onDialogLinePrinted = function(_dlg, pl, dNum)
                if dNum ~= 1 then
                    return
                end
                if pl ~= player then
                    return
                end
                if not NPCRequest then
                    return
                end
                pcall(function()
                    NPCRequest:InvokeServer({ npcId = npcId, action = "TalkFishermanGreet" })
                end)
            end
        end
    else
        buildDialogue(dialogue, npcId, npcType, npcName, reg)
    end

    prompt.Triggered:Connect(function()
        -- Merchant-style shop UI (ProximityPromptService).
        if npcType == "Merchant" or npcType == "AnimalTrainer" or npcType == "Dungeoneer" or npcType == "Innkeeper" or npcType == "Blacksmith" then
            return
        end
        local char = player.Character
        if char and not char.PrimaryPart then
            local cr = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso")
            if cr then
                char.PrimaryPart = cr
            end
        end
        dialogue:triggerDialog(player, 1)
    end)

    wiredNpcIds[npcId] = true
end

local function setupAnimalTrainerFallback()
    local at = workspace:FindFirstChild("Animal Trainer") or workspace:FindFirstChild("Animal Trainer", true)
    if at and at:IsA("Model") then
        task.spawn(setupNPC, at)
    end
end

local function setupDungeoneerFallback()
    local d = workspace:FindFirstChild("Dungeoneer") or workspace:FindFirstChild("Dungeoneer", true)
    if d and d:IsA("Model") then
        task.spawn(setupNPC, d)
    end
end

local function setupInnkeeperFallback()
    local inn = workspace:FindFirstChild("Innkeeper") or workspace:FindFirstChild("Innkeeper", true)
    if inn and inn:IsA("Model") then
        task.spawn(setupNPC, inn)
    end
end

local function setupMinerFallback()
    local m = workspace:FindFirstChild("Miner") or workspace:FindFirstChild("Miner", true)
    if m and m:IsA("Model") then
        task.spawn(setupNPC, m)
    end
end

local function setupFishermanFallback()
    local f = workspace:FindFirstChild("Fisherman") or workspace:FindFirstChild("Fisherman", true)
    if f and f:IsA("Model") then
        task.spawn(setupNPC, f)
    end
end

-- Defined after its dependencies above: Luau resolves a not-yet-declared `local function`
-- as a global (nil) lookup inside an earlier function body, since locals are scoped from
-- the point of declaration onward, not hoisted. This previously made every call inside
-- here throw "attempt to call a nil value" on setupAnimalTrainerFallback.
local function setupMerchantFallback()
    setupAnimalTrainerFallback()
    setupDungeoneerFallback()
    setupInnkeeperFallback()
    setupMinerFallback()
    setupFishermanFallback()
    local merchant = workspace:FindFirstChild("The Merchant") or workspace:FindFirstChild("Noob")
    if merchant and merchant:IsA("Model") then
        task.spawn(setupNPC, merchant)
    end
end

-- Best-effort fallback in case CollectionService tags are missing/tardy.
local function retryUnwiredNpcs()
    for _, model in ipairs(CollectionService:GetTagged("NPC")) do
        local id = model:GetAttribute("NpcId")
        if type(id) == "string" and not wiredNpcIds[id] then
            setupNPC(model)
        end
    end
end

workspace.ChildAdded:Connect(function(child)
    if child:IsA("Model") and (child.Name == "The Merchant" or child.Name == "Noob") then
        task.delay(0.2, function()
            if child.Parent then
                setupNPC(child)
            end
        end)
    elseif child:IsA("Model") and child.Name == "Animal Trainer" then
        task.delay(0.2, function()
            if child.Parent then
                setupNPC(child)
            end
        end)
    elseif child:IsA("Model") and child.Name == "Dungeoneer" then
        task.delay(0.2, function()
            if child.Parent then
                setupNPC(child)
            end
        end)
    elseif child:IsA("Model") and child.Name == "Innkeeper" then
        task.delay(0.2, function()
            if child.Parent then
                setupNPC(child)
            end
        end)
    elseif child:IsA("Model") and child.Name == "Cuso" then
        task.delay(0.6, retryUnwiredNpcs)
    elseif child:IsA("Model") and child.Name == "Miner" then
        task.delay(0.6, retryUnwiredNpcs)
    elseif child:IsA("Model") and child.Name == "Fisherman" then
        task.delay(0.6, retryUnwiredNpcs)
    end
end)

-- Initialise all existing tagged NPCs
for _, model in ipairs(CollectionService:GetTagged("NPC")) do
    task.spawn(setupNPC, model)
end

-- Watch for dynamically added NPCs (e.g. instanced dungeons, safezone shards)
CollectionService:GetInstanceAddedSignal("NPC"):Connect(function(model)
    task.wait(0.5)  -- brief settle to ensure attributes are applied
    setupNPC(model)
end)

setupMerchantFallback()

-- Server-side NPC bootstrap (e.g. Cuso) can add prompts after the first client scan.
task.delay(1.0, retryUnwiredNpcs)
task.delay(3.0, retryUnwiredNpcs)

print("[NPCClient] ready")
