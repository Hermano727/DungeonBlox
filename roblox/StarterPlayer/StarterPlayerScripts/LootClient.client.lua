--[[
    LootClient
    Listens for ItemDropNotify and shows a brief pickup banner in the top-right.
    Banners stack up to 5 and auto-dismiss after 4 seconds.
    Rarity color matches the existing DungeonProfileTypes.GetRarityColor() palette.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

------------------------------------------------------------------------
-- Rarity colors (mirrors DungeonProfileTypes.RARITY_COLORS)
------------------------------------------------------------------------
local RARITY_COLORS = {
    Common    = Color3.fromRGB(205, 210, 220),
    Uncommon  = Color3.fromRGB(70,  205, 105),
    Rare      = Color3.fromRGB(80,  170, 255),
    Epic      = Color3.fromRGB(200, 120, 255),
    Legendary = Color3.fromRGB(255, 175, 85),
}

------------------------------------------------------------------------
-- Banner container (top-right, stacks downward)
------------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name           = "LootBannerGui"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.DisplayOrder   = 260
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled        = true
gui.Parent         = playerGui

local stack = Instance.new("Frame", gui)
stack.Name              = "Stack"
stack.AnchorPoint       = Vector2.new(1, 0)
stack.Position          = UDim2.new(1, -12, 0, 48)
stack.Size              = UDim2.fromOffset(280, 10)
stack.BackgroundTransparency = 1
stack.AutomaticSize     = Enum.AutomaticSize.Y

local layout = Instance.new("UIListLayout", stack)
layout.Padding         = UDim.new(0, 6)
layout.SortOrder       = Enum.SortOrder.LayoutOrder
layout.HorizontalAlignment = Enum.HorizontalAlignment.Right

local MAX_BANNERS   = 5
local BANNER_LIFE   = 4    -- seconds before auto-dismiss
local SLIDE_TIME    = 0.18
local bannerCount   = 0
local nextOrder     = 0

local function spawnBanner(data)
    if type(data) ~= "table" then
        return
    end
    if bannerCount >= MAX_BANNERS then return end
    bannerCount = bannerCount + 1
    nextOrder   = nextOrder + 1

    local rarityColor
    local displayText
    if data.kind == "Coins" then
        local amount = math.max(0, math.floor(tonumber(data.amount) or 0))
        rarityColor = Color3.fromRGB(255, 215, 100)
        if data.coinFind then
            displayText = string.format("+%d Coins  ✨ Coin Find!", amount)
        else
            displayText = string.format("+%d Coins", amount)
        end
    else
        rarityColor = RARITY_COLORS[data.rarity] or Color3.new(1, 1, 1)
        local typeIcon = data.type == "Weapon" and "[W]" or "[A]"
        displayText = typeIcon .. " " .. tostring(data.name or "Item")
    end

    local banner = Instance.new("Frame", stack)
    banner.Name             = "Banner"
    banner.LayoutOrder      = nextOrder
    banner.Size             = UDim2.fromOffset(280, 40)
    banner.BackgroundColor3 = Color3.fromRGB(18, 14, 14)
    banner.BackgroundTransparency = 0.2
    banner.BorderSizePixel  = 0
    banner.ClipsDescendants = true
    Instance.new("UICorner", banner).CornerRadius = UDim.new(0, 8)

    local accent = Instance.new("Frame", banner)
    accent.Size             = UDim2.new(0, 4, 1, 0)
    accent.BackgroundColor3 = rarityColor
    accent.BorderSizePixel  = 0

    local lbl = Instance.new("TextLabel", banner)
    lbl.BackgroundTransparency = 1
    lbl.Size           = UDim2.new(1, -12, 1, 0)
    lbl.Position       = UDim2.fromOffset(10, 0)
    lbl.Font           = Enum.Font.GothamMedium
    lbl.TextSize       = 13
    lbl.TextColor3     = rarityColor
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextWrapped    = true
    lbl.Text           = displayText
    lbl.ZIndex         = 2

    -- Slide in from right
    banner.Position = UDim2.new(1, 0, 0, 0)
    TweenService:Create(banner, TweenInfo.new(SLIDE_TIME,
        Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Position = UDim2.new(0, 0, 0, 0) }):Play()

    -- Auto-dismiss
    task.delay(BANNER_LIFE, function()
        if not banner.Parent then return end
        local tween = TweenService:Create(banner,
            TweenInfo.new(SLIDE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { Position = UDim2.new(1, 0, 0, 0) })
        tween:Play()
        tween.Completed:Connect(function()
            banner:Destroy()
            bannerCount = math.max(0, bannerCount - 1)
        end)
    end)
end

local function bindItemDropNotify()
    local ge = ReplicatedStorage:WaitForChild("GameEvents", 120)
    if not ge or not ge:IsA("Folder") then
        warn("[LootClient] ReplicatedStorage.GameEvents folder missing after wait — loot banners disabled.")
        return
    end
    local ev = ge:WaitForChild("ItemDropNotify", 120)
    if not ev or not ev:IsA("RemoteEvent") then
        warn("[LootClient] GameEvents.ItemDropNotify missing after wait — loot banners disabled.")
        return
    end
    ev.OnClientEvent:Connect(spawnBanner)
    print("[LootClient] ready (banners bound)")
end

task.defer(bindItemDropNotify)
