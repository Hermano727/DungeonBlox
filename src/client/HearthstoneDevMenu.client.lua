local Keys = require(game:GetService("ReplicatedStorage"):WaitForChild("KeybindConfig"))
--[[
    HearthstoneDevMenu  (admin-only LocalScript)
    Opened with F8. Provides an "Add Hearthstone Location" form that writes to
    the HearthstoneRegistry DataStore via the HearthstoneAdminAdd RemoteFunction.
    Exits early (does nothing) if player.UserId is not in HearthstoneConfig.ADMIN_IDS.
]]

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local HearthstoneConfig = require(ReplicatedStorage:WaitForChild("HearthstoneConfig"))

-- Studio users always get access; live server requires UserId match.
local isAdmin = RunService:IsStudio()
if not isAdmin then
    for _, id in ipairs(HearthstoneConfig.ADMIN_IDS) do
        if id == player.UserId then isAdmin = true break end
    end
end
if not isAdmin then return end

local rfAdmin    = ReplicatedStorage:WaitForChild("HearthstoneAdminAdd",    30)
local rfAdminDel = ReplicatedStorage:WaitForChild("HearthstoneAdminDelete", 30)
local rfSync     = ReplicatedStorage:WaitForChild("HearthstoneSync",        30)
if not rfAdmin then
    warn("[HearthstoneDevMenu] HearthstoneAdminAdd RF not found")
    return
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Build GUI
-- ─────────────────────────────────────────────────────────────────────────────
local screenGui = Instance.new("ScreenGui")
screenGui.Name           = "HearthstoneDevMenu"
screenGui.ResetOnSpawn   = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder   = 200
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
panel.Name            = "DevPanel"
panel.AnchorPoint     = Vector2.new(0.5, 0.5)
panel.Position        = UDim2.new(0.5, 0, 0.5, 0)
panel.Size            = UDim2.fromOffset(360, 490)
panel.BackgroundColor3 = Color3.fromRGB(22, 15, 15)
panel.BorderSizePixel = 0
panel.ZIndex          = 2
panel.Parent          = screenGui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)
local panelStroke = Instance.new("UIStroke", panel)
panelStroke.Color     = Color3.fromRGB(130, 88, 88)
panelStroke.Thickness = 1.5

-- Title bar
local titleBar = Instance.new("TextLabel", panel)
titleBar.BackgroundColor3 = Color3.fromRGB(35, 22, 22)
titleBar.BorderSizePixel  = 0
titleBar.Size             = UDim2.new(1, 0, 0, 38)
titleBar.Font             = Enum.Font.GothamBold
titleBar.TextSize         = 13
titleBar.TextColor3       = Color3.fromRGB(255, 198, 98)
titleBar.Text             = "Hearthstone Dev Panel  [DEV]"
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

local function makeTextBox(parent, y, placeholder)
    local box = Instance.new("TextBox", parent)
    box.BackgroundColor3  = Color3.fromRGB(38, 26, 26)
    box.BorderSizePixel   = 0
    box.Position          = UDim2.new(0, 0, 0, y)
    box.Size              = UDim2.new(1, 0, 0, 28)
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
    local sk = Instance.new("UIStroke", box)
    sk.Color     = Color3.fromRGB(68, 48, 48)
    sk.Thickness = 1
    return box
end

makeLabel(content, 0, "Location Name")
local nameBox = makeTextBox(content, 16, "e.g. Iron Peaks")

makeLabel(content, 56, "Cost (Coins)")
local costBox = makeTextBox(content, 72, "0 = free")

makeLabel(content, 112, "Position")
local posDisplay = Instance.new("TextLabel", content)
posDisplay.Name               = "PosDisplay"
posDisplay.BackgroundColor3   = Color3.fromRGB(30, 22, 22)
posDisplay.BorderSizePixel    = 0
posDisplay.Position           = UDim2.new(0, 0, 0, 128)
posDisplay.Size               = UDim2.new(0.6, -4, 0, 28)
posDisplay.Font               = Enum.Font.Gotham
posDisplay.TextSize           = 10
posDisplay.TextColor3         = Color3.fromRGB(148, 138, 118)
posDisplay.Text               = "not captured"
posDisplay.ZIndex             = 4
Instance.new("UICorner", posDisplay).CornerRadius = UDim.new(0, 5)

local captureBtn = Instance.new("TextButton", content)
captureBtn.Size             = UDim2.new(0.4, 0, 0, 28)
captureBtn.AnchorPoint      = Vector2.new(1, 0)
captureBtn.Position         = UDim2.new(1, 0, 0, 128)
captureBtn.BackgroundColor3 = Color3.fromRGB(38, 58, 80)
captureBtn.BorderSizePixel  = 0
captureBtn.Font             = Enum.Font.GothamMedium
captureBtn.TextSize         = 11
captureBtn.TextColor3       = Color3.fromRGB(178, 208, 228)
captureBtn.Text             = "Capture Pos"
captureBtn.ZIndex           = 4
Instance.new("UICorner", captureBtn).CornerRadius = UDim.new(0, 5)

local statusLbl = Instance.new("TextLabel", content)
statusLbl.BackgroundTransparency = 1
statusLbl.Position       = UDim2.new(0, 0, 0, 172)
statusLbl.Size           = UDim2.new(1, 0, 0, 18)
statusLbl.Font           = Enum.Font.Gotham
statusLbl.TextSize       = 11
statusLbl.TextColor3     = Color3.fromRGB(138, 218, 138)
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.Text           = ""
statusLbl.ZIndex         = 4

local addBtn = Instance.new("TextButton", content)
addBtn.Size             = UDim2.new(1, 0, 0, 32)
addBtn.Position         = UDim2.new(0, 0, 0, 198)
addBtn.BackgroundColor3 = Color3.fromRGB(48, 78, 48)
addBtn.BorderSizePixel  = 0
addBtn.Font             = Enum.Font.GothamBold
addBtn.TextSize         = 13
addBtn.TextColor3       = Color3.new(1, 1, 1)
addBtn.Text             = "Add Location"
addBtn.ZIndex           = 4
Instance.new("UICorner", addBtn).CornerRadius = UDim.new(0, 6)

-- ─────────────────────────────────────────────────────────────────────────────
-- Current Locations list
-- ─────────────────────────────────────────────────────────────────────────────
local listDivider = Instance.new("Frame", content)
listDivider.BackgroundColor3 = Color3.fromRGB(60, 42, 42)
listDivider.BorderSizePixel  = 0
listDivider.Position         = UDim2.new(0, 0, 0, 240)
listDivider.Size             = UDim2.new(1, 0, 0, 1)
listDivider.ZIndex           = 4

local listHeader = Instance.new("TextLabel", content)
listHeader.BackgroundTransparency = 1
listHeader.Position       = UDim2.new(0, 0, 0, 248)
listHeader.Size           = UDim2.new(0.65, 0, 0, 13)
listHeader.Font           = Enum.Font.GothamBold
listHeader.TextSize       = 9
listHeader.TextColor3     = Color3.fromRGB(158, 138, 128)
listHeader.TextXAlignment = Enum.TextXAlignment.Left
listHeader.Text           = "CURRENT LOCATIONS"
listHeader.ZIndex         = 4

local refreshListBtn = Instance.new("TextButton", content)
refreshListBtn.Size             = UDim2.new(0.35, 0, 0, 18)
refreshListBtn.AnchorPoint      = Vector2.new(1, 0)
refreshListBtn.Position         = UDim2.new(1, 0, 0, 245)
refreshListBtn.BackgroundColor3 = Color3.fromRGB(38, 28, 28)
refreshListBtn.BorderSizePixel  = 0
refreshListBtn.Font             = Enum.Font.Gotham
refreshListBtn.TextSize         = 9
refreshListBtn.TextColor3       = Color3.fromRGB(160, 148, 130)
refreshListBtn.Text             = "↺ Refresh"
refreshListBtn.ZIndex           = 4
Instance.new("UICorner", refreshListBtn).CornerRadius = UDim.new(0, 4)

local locListScroll = Instance.new("ScrollingFrame", content)
locListScroll.BackgroundTransparency = 1
locListScroll.BorderSizePixel        = 0
locListScroll.ScrollBarThickness     = 4
locListScroll.AutomaticCanvasSize    = Enum.AutomaticSize.Y
locListScroll.CanvasSize             = UDim2.new()
locListScroll.Position               = UDim2.new(0, 0, 0, 266)
locListScroll.Size                   = UDim2.new(1, 0, 1, -266)
locListScroll.ZIndex                 = 4
local locListLayout = Instance.new("UIListLayout", locListScroll)
locListLayout.FillDirection = Enum.FillDirection.Vertical
locListLayout.Padding       = UDim.new(0, 4)
locListLayout.SortOrder     = Enum.SortOrder.LayoutOrder

local seedIdSet = {}
for _, seed in ipairs(HearthstoneConfig.SEED_LOCATIONS) do
    seedIdSet[seed.id] = true
end

local refreshList  -- forward declaration

-- ─────────────────────────────────────────────────────────────────────────────
-- Interaction logic
-- ─────────────────────────────────────────────────────────────────────────────
local capturedPos = nil

local function setStatus(msg, isError)
    statusLbl.Text      = msg
    statusLbl.TextColor3 = isError
        and Color3.fromRGB(255, 98, 98)
        or  Color3.fromRGB(138, 218, 138)
    if msg ~= "" then
        task.delay(4, function()
            if statusLbl.Text == msg then statusLbl.Text = "" end
        end)
    end
end

captureBtn.Activated:Connect(function()
    local char = player.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        setStatus("No character found.", true)
        return
    end
    capturedPos = hrp.Position
    posDisplay.Text      = string.format("%.1f, %.1f, %.1f",
        capturedPos.X, capturedPos.Y, capturedPos.Z)
    posDisplay.TextColor3 = Color3.fromRGB(138, 218, 138)
end)

addBtn.Activated:Connect(function()
    local name = nameBox.Text:match("^%s*(.-)%s*$")
    local cost = tonumber(costBox.Text) or 0
    if name == "" then
        setStatus("Name is required.", true)
        return
    end
    if not capturedPos then
        setStatus("Capture a position first.", true)
        return
    end
    addBtn.Active = false
    setStatus("Adding...", false)
    local ok, result = pcall(function()
        return rfAdmin:InvokeServer(
            name, cost,
            capturedPos.X, capturedPos.Y, capturedPos.Z
        )
    end)
    addBtn.Active = true
    if ok and result == true then
        setStatus("Added: " .. name, false)
        nameBox.Text     = ""
        costBox.Text     = ""
        posDisplay.Text  = "not captured"
        posDisplay.TextColor3 = Color3.fromRGB(148, 138, 118)
        capturedPos      = nil
        task.spawn(refreshList)
    else
        local errMsg = (type(result) == "string") and result or "Server rejected the request."
        setStatus(errMsg, true)
    end
end)

-- Define refreshList now that all UI + logic helpers (setStatus) are available.
function refreshList()
    for _, child in ipairs(locListScroll:GetChildren()) do
        if not child:IsA("UIListLayout") then child:Destroy() end
    end
    if not rfSync then return end
    local ok, locs = pcall(function()
        return rfSync:InvokeServer()
    end)
    if not ok or type(locs) ~= "table" then
        local errRow = Instance.new("TextLabel", locListScroll)
        errRow.BackgroundTransparency = 1
        errRow.Size       = UDim2.new(1, 0, 0, 28)
        errRow.Font       = Enum.Font.Gotham
        errRow.TextSize   = 10
        errRow.TextColor3 = Color3.fromRGB(200, 80, 80)
        errRow.Text       = "Could not fetch locations."
        return
    end
    table.sort(locs, function(a, b)
        local aS = seedIdSet[a.id] and 0 or 1
        local bS = seedIdSet[b.id] and 0 or 1
        if aS ~= bS then return aS < bS end
        return (a.name or "") < (b.name or "")
    end)
    for order, loc in ipairs(locs) do
        local isSeed = seedIdSet[loc.id]
        local row = Instance.new("Frame", locListScroll)
        row.BackgroundColor3 = Color3.fromRGB(32, 22, 22)
        row.BorderSizePixel  = 0
        row.Size             = UDim2.new(1, 0, 0, 34)
        row.LayoutOrder      = order
        row.ZIndex           = 5
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)

        local nameLbl = Instance.new("TextLabel", row)
        nameLbl.BackgroundTransparency = 1
        nameLbl.Size           = UDim2.new(1, -110, 1, 0)
        nameLbl.Position       = UDim2.new(0, 8, 0, 0)
        nameLbl.Font           = Enum.Font.GothamMedium
        nameLbl.TextSize       = 11
        nameLbl.TextColor3     = Color3.fromRGB(218, 205, 188)
        nameLbl.TextXAlignment = Enum.TextXAlignment.Left
        nameLbl.Text           = loc.name or loc.id
        nameLbl.ZIndex         = 6

        local costLbl = Instance.new("TextLabel", row)
        costLbl.BackgroundTransparency = 1
        costLbl.Size         = UDim2.fromOffset(46, 34)
        costLbl.AnchorPoint  = Vector2.new(1, 0.5)
        costLbl.Position     = UDim2.new(1, -38, 0.5, 0)
        costLbl.Font         = Enum.Font.Gotham
        costLbl.TextSize     = 10
        costLbl.TextColor3   = Color3.fromRGB(200, 178, 88)
        costLbl.Text         = loc.cost == 0 and "Free" or (tostring(loc.cost) .. "c")
        costLbl.ZIndex       = 6

        if isSeed then
            local badge = Instance.new("TextLabel", row)
            badge.BackgroundColor3 = Color3.fromRGB(45, 35, 18)
            badge.BorderSizePixel  = 0
            badge.Size             = UDim2.fromOffset(30, 18)
            badge.AnchorPoint      = Vector2.new(1, 0.5)
            badge.Position         = UDim2.new(1, -4, 0.5, 0)
            badge.Font             = Enum.Font.GothamBold
            badge.TextSize         = 8
            badge.TextColor3       = Color3.fromRGB(200, 165, 70)
            badge.Text             = "SEED"
            badge.ZIndex           = 6
            Instance.new("UICorner", badge).CornerRadius = UDim.new(0, 4)
        else
            local delBtn = Instance.new("TextButton", row)
            delBtn.Size             = UDim2.fromOffset(26, 22)
            delBtn.AnchorPoint      = Vector2.new(1, 0.5)
            delBtn.Position         = UDim2.new(1, -4, 0.5, 0)
            delBtn.BackgroundColor3 = Color3.fromRGB(90, 35, 35)
            delBtn.BorderSizePixel  = 0
            delBtn.Font             = Enum.Font.GothamBold
            delBtn.TextSize         = 14
            delBtn.TextColor3       = Color3.new(1, 1, 1)
            delBtn.Text             = "×"
            delBtn.ZIndex           = 6
            Instance.new("UICorner", delBtn).CornerRadius = UDim.new(0, 4)

            local capturedId2   = loc.id
            local capturedName2 = loc.name or loc.id
            delBtn.Activated:Connect(function()
                delBtn.Active = false
                local ok2, res2 = pcall(function()
                    return rfAdminDel:InvokeServer(capturedId2)
                end)
                if ok2 and res2 == true then
                    setStatus("Deleted: " .. capturedName2, false)
                    row:Destroy()
                else
                    setStatus(type(res2) == "string" and res2 or "Delete failed.", true)
                    delBtn.Active = true
                end
            end)
        end
    end
end

refreshListBtn.Activated:Connect(refreshList)

local open = false
local function setOpen(v)
    open              = v
    screenGui.Enabled = v
    if v then task.spawn(refreshList) end
end

dim.Activated:Connect(function() setOpen(false) end)
closeBtn.Activated:Connect(function() setOpen(false) end)

UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if UserInputService:GetFocusedTextBox() ~= nil then return end
    if input.KeyCode == Keys.HearthstoneMenu then
        setOpen(not open)
    elseif input.KeyCode == Keys.CloseMenu and open then
        setOpen(false)
    end
end)

print("[HearthstoneDevMenu] ready (admin)")
