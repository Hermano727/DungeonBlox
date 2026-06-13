--[[
    ItemGrantDevMenu  (admin-only LocalScript)
    Opens with F9. Grants items or currency to the local player via DevGrantItem RF.
    Studio users always get access; live server requires HearthstoneConfig.ADMIN_IDS match.
]]

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local HearthstoneConfig = require(ReplicatedStorage:WaitForChild("HearthstoneConfig"))

local isAdmin = RunService:IsStudio()
if not isAdmin then
    for _, id in ipairs(HearthstoneConfig.ADMIN_IDS) do
        if id == player.UserId then isAdmin = true break end
    end
end
if not isAdmin then return end

-- Don't hard-exit if RF isn't ready yet; buttons will warn gracefully.
local rfGrant = ReplicatedStorage:WaitForChild("DevGrantItem", 60)
if not rfGrant then
    warn("[ItemGrantDevMenu] DevGrantItem RF not found after 60s")
end

-- ─────────────────────────────────────────────────────────────────────────────
-- GUI
-- ─────────────────────────────────────────────────────────────────────────────
local screenGui = Instance.new("ScreenGui")
screenGui.Name           = "ItemGrantDevMenu"
screenGui.ResetOnSpawn   = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder   = 201
screenGui.Enabled        = false
screenGui.Parent         = playerGui

local dim = Instance.new("TextButton")
dim.Size                  = UDim2.fromScale(1, 1)
dim.BackgroundColor3      = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 0.55
dim.BorderSizePixel       = 0
dim.Text                  = ""
dim.AutoButtonColor       = false
dim.ZIndex                = 1
dim.Parent                = screenGui

local panel = Instance.new("Frame")
panel.Name            = "Panel"
panel.AnchorPoint     = Vector2.new(0.5, 0.5)
panel.Position        = UDim2.new(0.5, 0, 0.5, 0)
panel.Size            = UDim2.fromOffset(420, 440)
panel.BackgroundColor3 = Color3.fromRGB(22, 15, 15)
panel.BorderSizePixel = 0
panel.ZIndex          = 2
panel.Parent          = screenGui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)
local panelStroke = Instance.new("UIStroke", panel)
panelStroke.Color     = Color3.fromRGB(120, 80, 80)
panelStroke.Thickness = 1.5

local titleBar = Instance.new("TextLabel", panel)
titleBar.BackgroundColor3 = Color3.fromRGB(35, 22, 22)
titleBar.BorderSizePixel  = 0
titleBar.Size             = UDim2.new(1, 0, 0, 38)
titleBar.Font             = Enum.Font.GothamBold
titleBar.TextSize         = 13
titleBar.TextColor3       = Color3.fromRGB(130, 220, 130)
titleBar.Text             = "Item Grant  [DEV]  —  F10"
titleBar.ZIndex           = 3
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 10)

local closeBtn = Instance.new("TextButton", panel)
closeBtn.Size             = UDim2.fromOffset(26, 26)
closeBtn.AnchorPoint      = Vector2.new(1, 0)
closeBtn.Position         = UDim2.new(1, -8, 0, 6)
closeBtn.BackgroundColor3 = Color3.fromRGB(90, 40, 40)
closeBtn.BorderSizePixel  = 0
closeBtn.Font             = Enum.Font.GothamBold
closeBtn.TextSize         = 13
closeBtn.TextColor3       = Color3.new(1, 1, 1)
closeBtn.Text             = "X"
closeBtn.ZIndex           = 4
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 5)

local content = Instance.new("Frame", panel)
content.BackgroundTransparency = 1
content.Position = UDim2.new(0, 14, 0, 46)
content.Size     = UDim2.new(1, -28, 1, -54)
content.ZIndex   = 3

-- ─── Manual input row ───
local function makeLabel(parent, y, text)
    local lbl = Instance.new("TextLabel", parent)
    lbl.BackgroundTransparency = 1
    lbl.Position       = UDim2.new(0, 0, 0, y)
    lbl.Size           = UDim2.new(1, 0, 0, 14)
    lbl.Font           = Enum.Font.Gotham
    lbl.TextSize       = 11
    lbl.TextColor3     = Color3.fromRGB(158, 138, 128)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Text           = text
    lbl.ZIndex         = 4
    return lbl
end

local function makeBox(parent, y, w, placeholder)
    local box = Instance.new("TextBox", parent)
    box.BackgroundColor3  = Color3.fromRGB(38, 26, 26)
    box.BorderSizePixel   = 0
    box.Position          = UDim2.new(0, 0, 0, y)
    box.Size              = UDim2.new(w, 0, 0, 28)
    box.Font              = Enum.Font.GothamMedium
    box.TextSize          = 12
    box.TextColor3        = Color3.fromRGB(228, 212, 198)
    box.PlaceholderColor3 = Color3.fromRGB(88, 68, 68)
    box.PlaceholderText   = placeholder
    box.Text              = ""
    box.ClearTextOnFocus  = false
    box.ZIndex            = 4
    local pad = Instance.new("UIPadding", box)
    pad.PaddingLeft = UDim.new(0, 6)
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 5)
    Instance.new("UIStroke", box).Color = Color3.fromRGB(68, 48, 48)
    return box
end

makeLabel(content, 0, "Item ID")
local itemIdBox = makeBox(content, 16, 0.72, "e.g. T1KeyFragment")

makeLabel(content, 56, "Qty")
local qtyBox = makeBox(content, 72, 0.28, "1")
qtyBox.Text = "1"

local grantBtn = Instance.new("TextButton", content)
grantBtn.Size             = UDim2.new(0.28, -4, 0, 28)
grantBtn.AnchorPoint      = Vector2.new(1, 0)
grantBtn.Position         = UDim2.new(1, 0, 0, 72)
grantBtn.BackgroundColor3 = Color3.fromRGB(48, 98, 48)
grantBtn.BorderSizePixel  = 0
grantBtn.Font             = Enum.Font.GothamBold
grantBtn.TextSize         = 12
grantBtn.TextColor3       = Color3.new(1, 1, 1)
grantBtn.Text             = "Grant"
grantBtn.ZIndex           = 4
Instance.new("UICorner", grantBtn).CornerRadius = UDim.new(0, 5)

local statusLbl = Instance.new("TextLabel", content)
statusLbl.BackgroundTransparency = 1
statusLbl.Position       = UDim2.new(0, 0, 0, 110)
statusLbl.Size           = UDim2.new(1, 0, 0, 16)
statusLbl.Font           = Enum.Font.Gotham
statusLbl.TextSize       = 11
statusLbl.TextColor3     = Color3.fromRGB(138, 218, 138)
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.Text           = ""
statusLbl.ZIndex         = 4

-- ─── Quick grant buttons ───
local divider = Instance.new("Frame", content)
divider.BackgroundColor3 = Color3.fromRGB(60, 42, 42)
divider.BorderSizePixel  = 0
divider.Position         = UDim2.new(0, 0, 0, 132)
divider.Size             = UDim2.new(1, 0, 0, 1)
divider.ZIndex           = 4

local quickHeader = Instance.new("TextLabel", content)
quickHeader.BackgroundTransparency = 1
quickHeader.Position       = UDim2.new(0, 0, 0, 140)
quickHeader.Size           = UDim2.new(1, 0, 0, 13)
quickHeader.Font           = Enum.Font.GothamBold
quickHeader.TextSize       = 9
quickHeader.TextColor3     = Color3.fromRGB(158, 138, 128)
quickHeader.TextXAlignment = Enum.TextXAlignment.Left
quickHeader.Text           = "QUICK GRANT"
quickHeader.ZIndex         = 4

-- Quick button factory
local function makeQuickBtn(parent, x, y, w, label, color, itemId, qty)
    local btn = Instance.new("TextButton", parent)
    btn.Position         = UDim2.new(0, x, 0, y)
    btn.Size             = UDim2.fromOffset(w, 26)
    btn.BackgroundColor3 = color
    btn.BorderSizePixel  = 0
    btn.Font             = Enum.Font.GothamMedium
    btn.TextSize         = 10
    btn.TextColor3       = Color3.new(1, 1, 1)
    btn.Text             = label
    btn.ZIndex           = 4
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
    btn.Activated:Connect(function()
        btn.Active = false
        local ok, err = pcall(function()
            return rfGrant:InvokeServer(itemId, qty)
        end)
        local success = ok and err ~= false
        statusLbl.Text      = success
            and ("Granted: " .. label)
            or  ("Failed: " .. tostring(err))
        statusLbl.TextColor3 = success
            and Color3.fromRGB(138, 218, 138)
            or  Color3.fromRGB(255, 98, 98)
        task.delay(2.5, function()
            if statusLbl.Text:find(label, 1, true) then
                statusLbl.Text = ""
            end
        end)
        btn.Active = true
    end)
    return btn
end

local FRAG_COLOR = Color3.fromRGB(60, 50, 100)
local KEY_COLOR  = Color3.fromRGB(80, 55, 30)
local COIN_COLOR = Color3.fromRGB(100, 80, 20)
local ITEM_COLOR = Color3.fromRGB(40, 70, 50)

-- Key Fragments row
local fragLabel = Instance.new("TextLabel", content)
fragLabel.BackgroundTransparency = 1
fragLabel.Position = UDim2.new(0, 0, 0, 160)
fragLabel.Size     = UDim2.fromOffset(70, 13)
fragLabel.Font     = Enum.Font.Gotham
fragLabel.TextSize = 9
fragLabel.TextColor3 = Color3.fromRGB(140, 120, 180)
fragLabel.Text     = "Key Frags"
fragLabel.ZIndex   = 4

local fragX, fragBtnW = 74, 60
for t = 1, 5 do
    makeQuickBtn(content, fragX + (t-1)*(fragBtnW+4), 156,
        fragBtnW, "T"..t, FRAG_COLOR, "T"..t.."KeyFragment", 1)
end

-- Dungeon Keys row
local keyLabel = Instance.new("TextLabel", content)
keyLabel.BackgroundTransparency = 1
keyLabel.Position = UDim2.new(0, 0, 0, 194)
keyLabel.Size     = UDim2.fromOffset(70, 13)
keyLabel.Font     = Enum.Font.Gotham
keyLabel.TextSize = 9
keyLabel.TextColor3 = Color3.fromRGB(180, 140, 80)
keyLabel.Text     = "Dungeon Keys"
keyLabel.ZIndex   = 4

for t = 1, 5 do
    makeQuickBtn(content, fragX + (t-1)*(fragBtnW+4), 190,
        fragBtnW, "T"..t, KEY_COLOR, "T"..t.."DungeonKey", 1)
end

-- Currency row
local curLabel = Instance.new("TextLabel", content)
curLabel.BackgroundTransparency = 1
curLabel.Position = UDim2.new(0, 0, 0, 228)
curLabel.Size     = UDim2.fromOffset(70, 13)
curLabel.Font     = Enum.Font.Gotham
curLabel.TextSize = 9
curLabel.TextColor3 = Color3.fromRGB(200, 175, 80)
curLabel.Text     = "Currency"
curLabel.ZIndex   = 4

local coinAmts = {100, 500, 1000, 5000}
local coinW = 72
for i, amt in ipairs(coinAmts) do
    makeQuickBtn(content, fragX + (i-1)*(coinW+3), 224,
        coinW, "+"..tostring(amt).."c", COIN_COLOR, "Coins", amt)
end

-- Consumables row
local conLabel = Instance.new("TextLabel", content)
conLabel.BackgroundTransparency = 1
conLabel.Position = UDim2.new(0, 0, 0, 262)
conLabel.Size     = UDim2.fromOffset(70, 13)
conLabel.Font     = Enum.Font.Gotham
conLabel.TextSize = 9
conLabel.TextColor3 = Color3.fromRGB(120, 200, 120)
conLabel.Text     = "Consumables"
conLabel.ZIndex   = 4

local consumables = {
    { label = "Heal x10",  id = "HealPotion",  qty = 10 },
    { label = "Major x5",  id = "MajorPotion", qty = 5  },
    { label = "Arrow x50", id = "Arrow",        qty = 50 },
    { label = "T1 Wep Scr x5",  id = "T1WeaponScroll", qty = 5  },
    { label = "T1 Arm Scr x5",  id = "T1ArmorScroll",  qty = 5  },
}
local conW = 74
for i, c in ipairs(consumables) do
    makeQuickBtn(content, fragX + (i-1)*(conW+3), 258,
        conW, c.label, ITEM_COLOR, c.id, c.qty)
end

-- ─── Logic ───
local function setStatus(msg, isError)
    statusLbl.Text       = msg
    statusLbl.TextColor3 = isError
        and Color3.fromRGB(255, 98, 98)
        or  Color3.fromRGB(138, 218, 138)
    if msg ~= "" then
        task.delay(3, function()
            if statusLbl.Text == msg then statusLbl.Text = "" end
        end)
    end
end

grantBtn.Activated:Connect(function()
    local id  = itemIdBox.Text:match("^%s*(.-)%s*$")
    local qty = math.clamp(math.floor(tonumber(qtyBox.Text) or 1), 1, 9999)
    if id == "" then setStatus("Enter an item ID.", true) return end
    grantBtn.Active = false
    local ok, result = pcall(function()
        return rfGrant:InvokeServer(id, qty)
    end)
    grantBtn.Active = true
    if ok and result == true then
        setStatus("Granted " .. qty .. "x " .. id, false)
    else
        setStatus(type(result) == "string" and result or "Failed.", true)
    end
end)

local open = false
local function setOpen(v)
    open              = v
    screenGui.Enabled = v
end

dim.Activated:Connect(function() setOpen(false) end)
closeBtn.Activated:Connect(function() setOpen(false) end)

UserInputService.InputBegan:Connect(function(input, _processed)
    -- Do not check _processed for function keys; Roblox marks them processed internally.
    if UserInputService:GetFocusedTextBox() ~= nil then return end
    if input.KeyCode == Enum.KeyCode.F10 then
        setOpen(not open)
    elseif input.KeyCode == Enum.KeyCode.Escape and open then
        setOpen(false)
    end
end)

print("[ItemGrantDevMenu] ready (admin)")
