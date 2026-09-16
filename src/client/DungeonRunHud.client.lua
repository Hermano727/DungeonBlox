--[[
    DungeonRunHud  (client)

    Two pieces:
      1. End-of-run summary panel -- drops, coins, XP. On a failed run it
         shows what was FORFEIT instead, so the penalty is legible rather
         than silently missing. (Key fragments never appear: they don't drop
         inside dungeons at all.)
      2. Post-clear exit countdown -- a persistent banner with a Leave button.
         Killing the boss does not eject anyone; players get 5 minutes to loot
         and regroup, then get pulled to hearthstone.

    Deliberately plain Instance UI, not React: this is the interim version.
    The eventual one wants an animated reveal per drop.

    Dev bindings: F6 start a run, F7 end it.
]]
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local ge = ReplicatedStorage:WaitForChild("GameEvents", 30)

-- These remotes are created by DungeonRunService, which is required LAZILY
-- (first dungeon launch) -- so at client startup they may not exist yet.
-- A blocking WaitForChild that times out returns nil, and the first
-- :Connect() on nil kills this whole script, silently taking the summary
-- panel with it. That is exactly what happened: the exit remote was missing,
-- so the summary handler below it never got connected.
--
-- So: never block, never assume. Bind whenever the remote shows up.
local function bindWhenReady(name, connect)
    local existing = ge:FindFirstChild(name)
    if existing then
        connect(existing)
        return
    end
    task.spawn(function()
        local remote = ge:WaitForChild(name, 600)
        if remote then
            connect(remote)
        else
            warn("[DungeonRunHud] remote never appeared: " .. name)
        end
    end)
end

-- Fire-and-forget senders tolerate a missing remote too.
local function fireServer(name, ...)
    local remote = ge:FindFirstChild(name)
    if remote then
        remote:FireServer(...)
    else
        warn("[DungeonRunHud] cannot fire, remote missing: " .. name)
    end
end

local RARITY_COLORS = {
    Common    = Color3.fromRGB(205, 210, 220),
    Uncommon  = Color3.fromRGB(70, 205, 105),
    Rare      = Color3.fromRGB(80, 170, 255),
    Epic      = Color3.fromRGB(200, 120, 255),
    Legendary = Color3.fromRGB(255, 175, 85),
    Mythic    = Color3.fromRGB(255, 85, 0),
}

local gui = Instance.new("ScreenGui")
gui.Name = "DungeonRunHud"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder = 50  -- above the inventory/hotbar HUDs
gui.Parent = playerGui

local function corner(inst, r)
    local c = Instance.new("UICorner", inst)
    c.CornerRadius = UDim.new(0, r or 6)
    return c
end

----------------------------------------------------------------
-- Summary panel
----------------------------------------------------------------
local panel = Instance.new("Frame", gui)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(400, 460)
panel.BackgroundColor3 = Color3.fromRGB(22, 24, 30)
panel.BorderSizePixel = 0
panel.Visible = false
panel.ZIndex = 10
corner(panel, 8)

local title = Instance.new("TextLabel", panel)
title.BackgroundTransparency = 1
title.Position = UDim2.fromOffset(0, 14)
title.Size = UDim2.new(1, 0, 0, 28)
title.Font = Enum.Font.GothamBold
title.TextSize = 20
title.TextColor3 = Color3.fromRGB(240, 240, 245)
title.Text = "Run Complete"
title.ZIndex = 11

local sub = Instance.new("TextLabel", panel)
sub.BackgroundTransparency = 1
sub.Position = UDim2.fromOffset(0, 44)
sub.Size = UDim2.new(1, 0, 0, 18)
sub.Font = Enum.Font.Gotham
sub.TextSize = 12
sub.TextColor3 = Color3.fromRGB(150, 155, 165)
sub.Text = ""
sub.ZIndex = 11

-- Reward strip: coins / xp
local strip = Instance.new("Frame", panel)
strip.Position = UDim2.fromOffset(14, 68)
strip.Size = UDim2.new(1, -28, 0, 34)
strip.BackgroundColor3 = Color3.fromRGB(16, 17, 22)
strip.BorderSizePixel = 0
strip.ZIndex = 11
corner(strip, 6)

local function stripLabel(x, w, color)
    local l = Instance.new("TextLabel", strip)
    l.BackgroundTransparency = 1
    l.Position = UDim2.fromScale(x, 0)
    l.Size = UDim2.new(w, 0, 1, 0)
    l.Font = Enum.Font.GothamMedium
    l.TextSize = 12
    l.TextColor3 = color
    l.Text = ""
    l.ZIndex = 12
    return l
end
local coinLbl = stripLabel(0, 0.5, Color3.fromRGB(255, 210, 90))
local xpLbl   = stripLabel(0.5, 0.5, Color3.fromRGB(120, 200, 255))

local dropsHdr = Instance.new("TextLabel", panel)
dropsHdr.BackgroundTransparency = 1
dropsHdr.Position = UDim2.fromOffset(16, 108)
dropsHdr.Size = UDim2.new(1, -32, 0, 16)
dropsHdr.Font = Enum.Font.GothamBold
dropsHdr.TextSize = 11
dropsHdr.TextXAlignment = Enum.TextXAlignment.Left
dropsHdr.TextColor3 = Color3.fromRGB(140, 145, 160)
dropsHdr.Text = "DROPS"
dropsHdr.ZIndex = 11

local list = Instance.new("ScrollingFrame", panel)
list.Position = UDim2.fromOffset(14, 128)
list.Size = UDim2.new(1, -28, 1, -186)
list.BackgroundColor3 = Color3.fromRGB(16, 17, 22)
list.BorderSizePixel = 0
list.ScrollBarThickness = 4
list.CanvasSize = UDim2.new()
list.ZIndex = 11
corner(list, 6)
local layout = Instance.new("UIListLayout", list)
layout.Padding = UDim.new(0, 3)
layout.SortOrder = Enum.SortOrder.LayoutOrder

local closeBtn = Instance.new("TextButton", panel)
closeBtn.AnchorPoint = Vector2.new(0.5, 1)
closeBtn.Position = UDim2.new(0.5, 0, 1, -14)
closeBtn.Size = UDim2.fromOffset(140, 32)
closeBtn.BackgroundColor3 = Color3.fromRGB(60, 110, 190)
closeBtn.BorderSizePixel = 0
closeBtn.Font = Enum.Font.GothamMedium
closeBtn.TextSize = 13
closeBtn.TextColor3 = Color3.new(1, 1, 1)
closeBtn.Text = "Close"
closeBtn.ZIndex = 11
corner(closeBtn, 5)
closeBtn.Activated:Connect(function() panel.Visible = false end)

----------------------------------------------------------------
-- Exit countdown banner
----------------------------------------------------------------
local banner = Instance.new("Frame", gui)
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0, 12)
banner.Size = UDim2.fromOffset(300, 40)
banner.BackgroundColor3 = Color3.fromRGB(22, 24, 30)
banner.BackgroundTransparency = 0.1
banner.BorderSizePixel = 0
banner.Visible = false
banner.ZIndex = 8
corner(banner, 6)

local bannerLbl = Instance.new("TextLabel", banner)
bannerLbl.BackgroundTransparency = 1
bannerLbl.Position = UDim2.fromOffset(12, 0)
bannerLbl.Size = UDim2.new(1, -110, 1, 0)
bannerLbl.Font = Enum.Font.GothamMedium
bannerLbl.TextSize = 13
bannerLbl.TextXAlignment = Enum.TextXAlignment.Left
bannerLbl.TextColor3 = Color3.fromRGB(220, 225, 235)
bannerLbl.Text = "Exit in 5:00"
bannerLbl.ZIndex = 9

local leaveBtn = Instance.new("TextButton", banner)
leaveBtn.AnchorPoint = Vector2.new(1, 0.5)
leaveBtn.Position = UDim2.new(1, -8, 0.5, 0)
leaveBtn.Size = UDim2.fromOffset(88, 26)
leaveBtn.BackgroundColor3 = Color3.fromRGB(170, 60, 60)
leaveBtn.BorderSizePixel = 0
leaveBtn.Font = Enum.Font.GothamMedium
leaveBtn.TextSize = 12
leaveBtn.TextColor3 = Color3.new(1, 1, 1)
leaveBtn.Text = "Leave Now"
leaveBtn.ZIndex = 9
corner(leaveBtn, 5)

local exitDeadline = nil
leaveBtn.Activated:Connect(function()
    exitDeadline = nil
    banner.Visible = false
    fireServer("DungeonRunEnd")
end)

RunService.Heartbeat:Connect(function()
    if not exitDeadline then return end
    local left = exitDeadline - os.clock()
    if left <= 0 then
        exitDeadline = nil
        banner.Visible = false
        return
    end
    local m = math.floor(left / 60)
    local sec = math.floor(left % 60)
    bannerLbl.Text = string.format("Exit in %d:%02d", m, sec)
    -- Redden as it runs out so it reads urgently without a separate warning.
    bannerLbl.TextColor3 = (left <= 30)
        and Color3.fromRGB(255, 140, 140)
        or Color3.fromRGB(220, 225, 235)
end)

bindWhenReady("DungeonExitWindow", function(remote)
    remote.OnClientEvent:Connect(function(data)
        exitDeadline = os.clock() + (data and data.seconds or 300)
        banner.Visible = true
    end)
end)

----------------------------------------------------------------
-- Render summary
----------------------------------------------------------------
local function render(data)
    for _, c in ipairs(list:GetChildren()) do
        if c:IsA("TextLabel") then c:Destroy() end
    end

    local failed = (data.reason ~= "cleared")
    title.Text = failed and "Run Failed" or "Run Complete"
    title.TextColor3 = failed and Color3.fromRGB(230, 140, 140) or Color3.fromRGB(240, 240, 245)
    sub.Text = string.format("%d score  -  %d kills", data.score or 0, data.kills or 0)

    -- Coins / XP are forfeit on failure; show the loss rather than
    -- omitting the row, so the cost of dying is visible.
    if failed then
        coinLbl.Text = string.format("  -%d coins", data.coinsLost or 0)
        xpLbl.Text   = string.format("-%d xp", data.xpLost or 0)
        for _, l in ipairs({coinLbl, xpLbl}) do
            l.TextColor3 = Color3.fromRGB(200, 110, 110)
        end
    else
        coinLbl.Text = string.format("  +%d coins", data.coins or 0)
        xpLbl.Text   = string.format("+%d xp", data.xp or 0)
        coinLbl.TextColor3 = Color3.fromRGB(255, 210, 90)
        xpLbl.TextColor3   = Color3.fromRGB(120, 200, 255)
    end

    local drops = data.drops or {}
    if #drops == 0 then
        local none = Instance.new("TextLabel", list)
        none.BackgroundTransparency = 1
        none.Size = UDim2.new(1, 0, 0, 40)
        none.Font = Enum.Font.Gotham
        none.TextSize = 13
        none.TextColor3 = Color3.fromRGB(140, 145, 155)
        none.Text = "No drops acquired."
        none.ZIndex = 12
    else
        for i, d in ipairs(drops) do
            local row = Instance.new("TextLabel", list)
            row.LayoutOrder = i
            row.BackgroundTransparency = 1
            row.Size = UDim2.new(1, -10, 0, 22)
            row.Font = Enum.Font.GothamMedium
            row.TextSize = 12
            row.TextXAlignment = Enum.TextXAlignment.Left
            row.TextColor3 = RARITY_COLORS[d.rarity] or Color3.fromRGB(205, 210, 220)
            row.Text = string.format("   %s  (Lv %s)", tostring(d.name), tostring(d.level or "?"))
            row.ZIndex = 12
        end
    end

    list.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 8)
    panel.Visible = true
end

bindWhenReady("DungeonRunSummary", function(remote)
    remote.OnClientEvent:Connect(render)
end)

UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.F6 then
        fireServer("DungeonRunStart")
    elseif input.KeyCode == Enum.KeyCode.F7 then
        fireServer("DungeonRunEnd")
    end
end)

print("[DungeonRunHud] ready -- F6 start run, F7 end run")
