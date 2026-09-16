--[[
    HearthstoneClient
    Manages all client-side hearthstone UI:
      - Tele / Swap buttons + cooldown countdown (injected into DungeonMenuUI's PlayerModelArea)
      - LocationPicker overlay (swap between owned locations)
      - HearthstoneShopUI (buy locations; opened from MerchantShopClient on Innkeeper prompt, same pattern as BlacksmithClient)
    Called once via HearthstoneClient.init(refs) from SkillsTabClient.
]]

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local DungeonMenuNet    = require(script.Parent:WaitForChild("DungeonMenuNet"))
local HearthstoneConfig = require(ReplicatedStorage:WaitForChild("HearthstoneConfig"))
local MenuMouse         = require(ReplicatedStorage:WaitForChild("CursorUtils"))

-- RemoteFunctions created by ProfileBootstrap at server start.
local rfTele     = ReplicatedStorage:WaitForChild("HearthstoneTeleport",  30)
local rfSwap     = ReplicatedStorage:WaitForChild("HearthstoneSwap",      30)
local rfSync     = ReplicatedStorage:WaitForChild("HearthstoneSync",      30)
local rfPurchase = ReplicatedStorage:WaitForChild("HearthstonePurchase",  30)

-- ─────────────────────────────────────────────────────────────────────────────
-- Location catalog  (populated once via HearthstoneSync RF)
-- ─────────────────────────────────────────────────────────────────────────────
local locationCatalog = {}  -- { [id] = { id, name, cost, px, py, pz } }

local function fetchCatalog()
    local ok, result = pcall(function()
        return rfSync:InvokeServer()
    end)
    if not ok then
        warn("[Hearthstone] fetchCatalog InvokeServer failed:", result)
        return
    end
    if type(result) ~= "table" then
        warn("[Hearthstone] fetchCatalog bad result type:", typeof(result), result)
        return
    end
    for _, loc in ipairs(result) do
        if type(loc) == "table" and type(loc.id) == "string" then
            locationCatalog[loc.id] = loc
        else
            warn("[Hearthstone] fetchCatalog skip bad row:", loc)
        end
    end
end

local function getLocationName(id)
    if locationCatalog[id] then return locationCatalog[id].name end
    for _, seed in ipairs(HearthstoneConfig.SEED_LOCATIONS) do
        if seed.id == id then return seed.name end
    end
    return id
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Cooldown state  (os.time()-based, synced from profile snapshots)
-- ─────────────────────────────────────────────────────────────────────────────
local cooldownUntil  = 0
local activeLocation = "oakhaven"

local function formatCountdown(secs)
    secs = math.max(0, math.floor(secs))
    return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- LocationPicker overlay (swap between owned locations)
-- ─────────────────────────────────────────────────────────────────────────────
local pickerGui = Instance.new("ScreenGui")
pickerGui.Name           = "HearthstonePickerUI"
pickerGui.ResetOnSpawn   = false
pickerGui.IgnoreGuiInset = true
pickerGui.DisplayOrder   = 130
pickerGui.Enabled        = false
pickerGui.Parent         = playerGui

local pickerDim = Instance.new("TextButton")
pickerDim.Size                  = UDim2.fromScale(1, 1)
pickerDim.BackgroundColor3      = Color3.new(0, 0, 0)
pickerDim.BackgroundTransparency = 0.6
pickerDim.BorderSizePixel       = 0
pickerDim.Text                  = ""
pickerDim.AutoButtonColor       = false
pickerDim.ZIndex                = 1
pickerDim.Parent                = pickerGui

local pickerPanel = Instance.new("Frame")
pickerPanel.Name            = "PickerPanel"
pickerPanel.AnchorPoint     = Vector2.new(0.5, 0.5)
pickerPanel.Position        = UDim2.new(0.5, 0, 0.5, 0)
pickerPanel.Size            = UDim2.fromOffset(320, 300)
pickerPanel.BackgroundColor3 = Color3.fromRGB(28, 20, 20)
pickerPanel.BorderSizePixel = 0
pickerPanel.ZIndex          = 2
pickerPanel.Parent          = pickerGui
Instance.new("UICorner", pickerPanel).CornerRadius = UDim.new(0, 10)
local pickerStroke = Instance.new("UIStroke", pickerPanel)
pickerStroke.Color     = Color3.fromRGB(90, 65, 65)
pickerStroke.Thickness = 1

local pickerTitle = Instance.new("TextLabel", pickerPanel)
pickerTitle.BackgroundTransparency = 1
pickerTitle.Size                   = UDim2.new(1, -80, 0, 32)
pickerTitle.Position               = UDim2.new(0, 12, 0, 6)
pickerTitle.FontFace                   = UIFonts.BodyBold
pickerTitle.TextSize               = 15
pickerTitle.TextColor3             = Color3.new(1, 1, 1)
pickerTitle.TextXAlignment         = Enum.TextXAlignment.Left
pickerTitle.Text                   = "Select Location"
pickerTitle.ZIndex                 = 3

local pickerCancelBtn = Instance.new("TextButton", pickerPanel)
pickerCancelBtn.Size             = UDim2.fromOffset(70, 24)
pickerCancelBtn.AnchorPoint      = Vector2.new(1, 0)
pickerCancelBtn.Position         = UDim2.new(1, -10, 0, 8)
pickerCancelBtn.BackgroundColor3 = Color3.fromRGB(60, 40, 40)
pickerCancelBtn.BorderSizePixel  = 0
pickerCancelBtn.FontFace             = UIFonts.BodyMedium
pickerCancelBtn.TextSize         = 11
pickerCancelBtn.TextColor3       = Color3.fromRGB(200, 180, 180)
pickerCancelBtn.Text             = "Cancel"
pickerCancelBtn.ZIndex           = 3
Instance.new("UICorner", pickerCancelBtn).CornerRadius = UDim.new(0, 5)

local pickerGrid = Instance.new("ScrollingFrame", pickerPanel)
pickerGrid.Name                = "LocationGrid"
pickerGrid.BackgroundTransparency = 1
pickerGrid.BorderSizePixel     = 0
pickerGrid.ScrollBarThickness  = 4
pickerGrid.AutomaticCanvasSize = Enum.AutomaticSize.Y
pickerGrid.CanvasSize          = UDim2.new()
pickerGrid.Position            = UDim2.new(0, 8, 0, 48)
pickerGrid.Size                = UDim2.new(1, -16, 1, -56)
pickerGrid.ZIndex              = 3
local pickerGridLayout = Instance.new("UIGridLayout", pickerGrid)
pickerGridLayout.CellSize    = UDim2.fromOffset(88, 72)
pickerGridLayout.CellPadding = UDim2.fromOffset(8, 8)
pickerGridLayout.SortOrder   = Enum.SortOrder.LayoutOrder

local function closePicker()
    pickerGui.Enabled = false
end

pickerDim.Activated:Connect(closePicker)
pickerCancelBtn.Activated:Connect(closePicker)

local function mergeWithSeeds(unlockedIds)
    local merged = {}
    local seen   = {}
    for _, seed in ipairs(HearthstoneConfig.SEED_LOCATIONS) do
        if not seen[seed.id] then
            seen[seed.id] = true
            table.insert(merged, seed.id)
        end
    end
    for _, id in ipairs(unlockedIds or {}) do
        if not seen[id] then
            seen[id] = true
            table.insert(merged, id)
        end
    end
    return merged
end

local function rebuildPickerGrid(unlockedIds)
    for _, child in ipairs(pickerGrid:GetChildren()) do
        if child:IsA("TextButton") or child:IsA("Frame") then child:Destroy() end
    end
    for order, locId in ipairs(unlockedIds) do
        local name     = getLocationName(locId)
        local isActive = locId == activeLocation

        local card = Instance.new("TextButton", pickerGrid)
        card.Name            = "Loc_" .. locId
        card.BackgroundColor3 = isActive
            and Color3.fromRGB(60, 44, 18)
            or  Color3.fromRGB(36, 26, 26)
        card.BorderSizePixel = 0
        card.Text            = ""
        card.LayoutOrder     = order
        card.ZIndex          = 4
        Instance.new("UICorner", card).CornerRadius = UDim.new(0, 6)
        if isActive then
            local sk = Instance.new("UIStroke", card)
            sk.Color     = Color3.fromRGB(200, 158, 58)
            sk.Thickness = 1.5
        end

        local iconId = locationCatalog[locId] and locationCatalog[locId].icon or ""
        if iconId ~= "" then
            local iconImg = Instance.new("ImageLabel", card)
            iconImg.BackgroundTransparency = 1
            iconImg.Size      = UDim2.new(1, 0, 1, 0)
            iconImg.Position  = UDim2.new(0, 0, 0, 0)
            iconImg.Image     = iconId
            iconImg.ScaleType = Enum.ScaleType.Crop
            iconImg.ZIndex    = 4
            Instance.new("UICorner", iconImg).CornerRadius = UDim.new(0, 6)
        end

        local lbl = Instance.new("TextLabel", card)
        lbl.BackgroundTransparency = 1
        lbl.Size           = UDim2.new(1, -6, 0.65, 0)
        lbl.Position       = UDim2.new(0, 3, 0.12, 0)
        lbl.FontFace           = UIFonts.BodyMedium
        lbl.TextSize       = 11
        lbl.TextWrapped    = true
        lbl.TextColor3     = isActive
            and Color3.fromRGB(255, 218, 130)
            or  Color3.fromRGB(218, 208, 192)
        lbl.Text           = name
        lbl.ZIndex         = 5

        if isActive then
            local al = Instance.new("TextLabel", card)
            al.BackgroundTransparency = 1
            al.Size          = UDim2.new(1, 0, 0, 13)
            al.AnchorPoint   = Vector2.new(0.5, 1)
            al.Position      = UDim2.new(0.5, 0, 1, -4)
            al.FontFace          = UIFonts.BodyBold
            al.TextSize      = 8
            al.TextColor3    = Color3.fromRGB(200, 158, 58)
            al.Text          = "ACTIVE"
            al.ZIndex        = 5
        end

        local capturedId = locId
        card.Activated:Connect(function()
            if capturedId == activeLocation then closePicker() return end
            local ok, _err = pcall(function()
                return rfSwap:InvokeServer(capturedId)
            end)
            if ok then closePicker() end
        end)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Innkeeper Shop UI (buy new hearthstone locations)
-- ─────────────────────────────────────────────────────────────────────────────
local shopGui = Instance.new("ScreenGui")
shopGui.Name           = "HearthstoneShopUI"
shopGui.ResetOnSpawn   = false
shopGui.IgnoreGuiInset = true
shopGui.DisplayOrder   = 125
shopGui.Enabled        = false
shopGui.Parent         = playerGui

local shopDim = Instance.new("TextButton")
shopDim.Size                  = UDim2.fromScale(1, 1)
shopDim.BackgroundColor3      = Color3.new(0, 0, 0)
shopDim.BackgroundTransparency = 0.5
shopDim.BorderSizePixel       = 0
shopDim.Text                  = ""
shopDim.AutoButtonColor       = false
shopDim.ZIndex                = 1
shopDim.Parent                = shopGui

local shopPanel = Instance.new("Frame")
shopPanel.Name            = "ShopPanel"
shopPanel.AnchorPoint     = Vector2.new(0.5, 0.5)
shopPanel.Position        = UDim2.new(0.5, 0, 0.5, 0)
shopPanel.Size            = UDim2.fromOffset(340, 360)
shopPanel.BackgroundColor3 = Color3.fromRGB(28, 20, 20)
shopPanel.BorderSizePixel = 0
shopPanel.ZIndex          = 2
shopPanel.Parent          = shopGui
Instance.new("UICorner", shopPanel).CornerRadius = UDim.new(0, 10)
local shopStroke = Instance.new("UIStroke", shopPanel)
shopStroke.Color     = Color3.fromRGB(90, 65, 65)
shopStroke.Thickness = 1

local shopTitle = Instance.new("TextLabel", shopPanel)
shopTitle.BackgroundTransparency = 1
shopTitle.Size           = UDim2.new(1, -90, 0, 32)
shopTitle.Position       = UDim2.new(0, 12, 0, 6)
shopTitle.FontFace           = UIFonts.BodyBold
shopTitle.TextSize       = 15
shopTitle.TextColor3     = Color3.new(1, 1, 1)
shopTitle.TextXAlignment = Enum.TextXAlignment.Left
shopTitle.Text           = "Hearthstone Locations"
shopTitle.ZIndex         = 3

local shopCoinLabel = Instance.new("TextLabel", shopPanel)
shopCoinLabel.Name               = "CoinBalance"
shopCoinLabel.BackgroundTransparency = 1
shopCoinLabel.Size               = UDim2.new(1, -24, 0, 16)
shopCoinLabel.Position           = UDim2.new(0, 12, 0, 38)
shopCoinLabel.FontFace               = UIFonts.Body
shopCoinLabel.TextSize           = 11
shopCoinLabel.TextColor3         = Color3.fromRGB(200, 178, 98)
shopCoinLabel.TextXAlignment     = Enum.TextXAlignment.Left
shopCoinLabel.Text               = "Coins: 0"
shopCoinLabel.ZIndex             = 3

local shopCloseBtn = Instance.new("TextButton", shopPanel)
shopCloseBtn.Size             = UDim2.fromOffset(70, 24)
shopCloseBtn.AnchorPoint      = Vector2.new(1, 0)
shopCloseBtn.Position         = UDim2.new(1, -10, 0, 8)
shopCloseBtn.BackgroundColor3 = Color3.fromRGB(60, 40, 40)
shopCloseBtn.BorderSizePixel  = 0
shopCloseBtn.FontFace             = UIFonts.BodyMedium
shopCloseBtn.TextSize         = 11
shopCloseBtn.TextColor3       = Color3.fromRGB(200, 180, 180)
shopCloseBtn.Text             = "Close"
shopCloseBtn.ZIndex           = 3
Instance.new("UICorner", shopCloseBtn).CornerRadius = UDim.new(0, 5)

local shopStatusLabel = Instance.new("TextLabel", shopPanel)
shopStatusLabel.Name               = "Status"
shopStatusLabel.BackgroundTransparency = 1
shopStatusLabel.Size               = UDim2.new(1, -24, 0, 14)
shopStatusLabel.Position           = UDim2.new(0, 12, 0, 56)
shopStatusLabel.FontFace               = UIFonts.Body
shopStatusLabel.TextSize           = 10
shopStatusLabel.TextColor3         = Color3.fromRGB(140, 218, 140)
shopStatusLabel.TextXAlignment     = Enum.TextXAlignment.Left
shopStatusLabel.Text               = ""
shopStatusLabel.ZIndex             = 3

local shopScroll = Instance.new("ScrollingFrame", shopPanel)
shopScroll.BackgroundTransparency = 1
shopScroll.BorderSizePixel        = 0
shopScroll.ScrollBarThickness     = 4
shopScroll.AutomaticCanvasSize    = Enum.AutomaticSize.Y
shopScroll.CanvasSize             = UDim2.new()
shopScroll.Position               = UDim2.new(0, 8, 0, 74)
shopScroll.Size                   = UDim2.new(1, -16, 1, -82)
shopScroll.ZIndex                 = 3
local shopListLayout = Instance.new("UIListLayout", shopScroll)
shopListLayout.FillDirection = Enum.FillDirection.Vertical
shopListLayout.Padding       = UDim.new(0, 6)
shopListLayout.SortOrder     = Enum.SortOrder.LayoutOrder

local function setShopStatus(msg, isError)
    shopStatusLabel.Text      = msg
    shopStatusLabel.TextColor3 = isError
        and Color3.fromRGB(255, 98, 98)
        or  Color3.fromRGB(140, 218, 140)
    if msg ~= "" then
        task.delay(3, function()
            if shopStatusLabel.Text == msg then
                shopStatusLabel.Text = ""
            end
        end)
    end
end

local function closeShop()
    shopGui.Enabled = false
    MenuMouse.release()
end

shopDim.Activated:Connect(closeShop)
shopCloseBtn.Activated:Connect(closeShop)

local function rebuildShop(unlockedIds, coinBalance)
    shopCoinLabel.Text = "Coins: " .. tostring(coinBalance or 0)
    for _, child in ipairs(shopScroll:GetChildren()) do
        if not child:IsA("UIListLayout") then child:Destroy() end
    end

    local unlockedSet = {}
    for _, id in ipairs(unlockedIds) do unlockedSet[id] = true end

    local order    = 0
    local hasItems = false
    for _, loc in pairs(locationCatalog) do
        if not unlockedSet[loc.id] then
            hasItems = true
            order    = order + 1
            local row = Instance.new("Frame", shopScroll)
            row.Name             = "LocRow_" .. loc.id
            row.BackgroundColor3 = Color3.fromRGB(36, 26, 26)
            row.BorderSizePixel  = 0
            row.Size             = UDim2.new(1, 0, 0, 48)
            row.LayoutOrder      = order
            row.ZIndex           = 4
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

            local nameLbl = Instance.new("TextLabel", row)
            nameLbl.BackgroundTransparency = 1
            nameLbl.Size           = UDim2.new(1, -110, 1, 0)
            nameLbl.Position       = UDim2.new(0, 10, 0, 0)
            nameLbl.FontFace           = UIFonts.BodyMedium
            nameLbl.TextSize       = 13
            nameLbl.TextColor3     = Color3.fromRGB(220, 208, 192)
            nameLbl.TextXAlignment = Enum.TextXAlignment.Left
            nameLbl.Text           = loc.name
            nameLbl.ZIndex         = 5

            local costLbl = Instance.new("TextLabel", row)
            costLbl.BackgroundTransparency = 1
            costLbl.Size         = UDim2.fromOffset(52, 48)
            costLbl.AnchorPoint  = Vector2.new(1, 0.5)
            costLbl.Position     = UDim2.new(1, -72, 0.5, 0)
            costLbl.FontFace         = UIFonts.BodyMedium
            costLbl.TextSize     = 12
            costLbl.TextColor3   = Color3.fromRGB(218, 188, 98)
            costLbl.Text         = loc.cost == 0 and "Free" or (tostring(loc.cost) .. "c")
            costLbl.ZIndex       = 5

            local buyBtn = Instance.new("TextButton", row)
            buyBtn.Size             = UDim2.fromOffset(60, 28)
            buyBtn.AnchorPoint      = Vector2.new(1, 0.5)
            buyBtn.Position         = UDim2.new(1, -6, 0.5, 0)
            buyBtn.BackgroundColor3 = Color3.fromRGB(48, 98, 58)
            buyBtn.BorderSizePixel  = 0
            buyBtn.FontFace             = UIFonts.BodyBold
            buyBtn.TextSize         = 11
            buyBtn.TextColor3       = Color3.new(1, 1, 1)
            buyBtn.Text             = "Buy"
            buyBtn.ZIndex           = 5
            Instance.new("UICorner", buyBtn).CornerRadius = UDim.new(0, 5)

            local capturedId = loc.id
            local capturedName = loc.name
            buyBtn.Activated:Connect(function()
                buyBtn.Active          = false
                buyBtn.BackgroundColor3 = Color3.fromRGB(38, 58, 42)
                local ok, newCoins, _err = pcall(function()
                    return rfPurchase:InvokeServer(capturedId)
                end)
                if ok and newCoins == true then
                    -- newCoins is actually the second return from PurchaseLocation
                    setShopStatus("Unlocked: " .. capturedName, false)
                    row:Destroy()
                elseif ok and type(newCoins) == "boolean" and not newCoins then
                    -- newCoins is false (failed), _err is the error string
                    setShopStatus(tostring(_err) or "Purchase failed.", true)
                    buyBtn.Active          = true
                    buyBtn.BackgroundColor3 = Color3.fromRGB(48, 98, 58)
                else
                    setShopStatus("Purchase failed.", true)
                    buyBtn.Active          = true
                    buyBtn.BackgroundColor3 = Color3.fromRGB(48, 98, 58)
                end
            end)
        end
    end

    if not hasItems then
        local emptyLbl = Instance.new("TextLabel", shopScroll)
        emptyLbl.BackgroundTransparency = 1
        emptyLbl.Size          = UDim2.new(1, 0, 0, 40)
        emptyLbl.FontFace          = UIFonts.Body
        emptyLbl.TextSize      = 12
        emptyLbl.TextColor3    = Color3.fromRGB(110, 92, 92)
        emptyLbl.Text          = "All locations unlocked."
    end
end

local function openShop()
    task.spawn(function()
        fetchCatalog()
        local snap    = DungeonMenuNet.getLastSnapshot()
        local profile = snap and snap.profile
        local hs      = profile and profile.hearthstone
        rebuildShop(
            hs and hs.unlocked or { "oakhaven" },
            profile and profile.currencies and profile.currencies.Coins or 0
        )
        shopGui.Enabled = true
        MenuMouse.acquire()
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- HearthstoneClient public API
-- ─────────────────────────────────────────────────────────────────────────────
local HearthstoneClient = {}
local heartbeatConn     = nil
local menuRefs          = nil

local function updateTeleButton()
    if not menuRefs then return end
    local btn       = menuRefs.teleButton
    local remaining = cooldownUntil - os.time()
    if remaining > 0 then
        btn.Text             = formatCountdown(remaining)
        btn.BackgroundColor3 = Color3.fromRGB(60, 40, 22)
        btn.Active           = false
        btn.AutoButtonColor  = false
    else
        btn.Text             = "Tele"
        btn.BackgroundColor3 = Color3.fromRGB(160, 118, 38)
        btn.Active           = true
        btn.AutoButtonColor  = true
    end
end

function HearthstoneClient.init(refs)
    menuRefs = refs
    if not refs then
        warn("[HearthstoneClient] No refs provided")
        return
    end

    -- Sync initial state from cached snapshot.
    local snap    = DungeonMenuNet.getLastSnapshot()
    local profile = snap and snap.profile
    local hs      = profile and profile.hearthstone
    if hs then
        cooldownUntil  = hs.cooldownUntil or 0
        activeLocation = hs.active or "oakhaven"
    end
    if refs.locationLabel then
        refs.locationLabel.Text = getLocationName(activeLocation)
    end

    -- Heartbeat ticker for cooldown countdown display.
    if heartbeatConn then heartbeatConn:Disconnect() end
    heartbeatConn = RunService.Heartbeat:Connect(updateTeleButton)
    updateTeleButton()

    -- Tele button handler.
    refs.teleButton.Activated:Connect(function()
        if os.time() < cooldownUntil then return end
        refs.teleButton.Active = false
        local ok, success, cdVal = pcall(function()
            return rfTele:InvokeServer()
        end)
        if ok and success then
            cooldownUntil = type(cdVal) == "number"
                and cdVal
                or (os.time() + HearthstoneConfig.COOLDOWN)
        else
            warn("[Hearthstone] Teleport failed:", success)
        end
        refs.teleButton.Active = true
        updateTeleButton()
    end)

    -- Swap button handler.
    refs.swapButton.Activated:Connect(function()
        local s       = DungeonMenuNet.getLastSnapshot()
        local prof    = s and s.profile
        local hsData  = prof and prof.hearthstone
        rebuildPickerGrid(mergeWithSeeds(hsData and hsData.unlocked or {}))
        pickerGui.Enabled = true
    end)

    -- Snapshot listener: update cooldown + location label on every server push.
    DungeonMenuNet.addSnapshotListener(function(snap2)
        local prof2 = snap2 and snap2.profile
        local hs2   = prof2 and prof2.hearthstone
        if not hs2 then return end
        cooldownUntil  = hs2.cooldownUntil or 0
        activeLocation = hs2.active or "oakhaven"
        if refs.locationLabel then
            refs.locationLabel.Text = getLocationName(activeLocation)
        end
        updateTeleButton()
    end)

    -- Fetch catalog in background so location names resolve correctly.
    task.spawn(function()
        fetchCatalog()
        if refs.locationLabel then
            refs.locationLabel.Text = getLocationName(activeLocation)
        end
    end)
end

function HearthstoneClient.openInnkeeperShop()
    openShop()
end

return HearthstoneClient
