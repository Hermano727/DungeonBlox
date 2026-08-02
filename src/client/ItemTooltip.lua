--[[
    ItemTooltip
    Shared tooltip panel for inventory and hotbar item hover.
    Creates a single ScreenGui on require; show/hide via the exported API.

    Layout:
      Name              (rarity color, GothamBold 14px)
      Type | Tier | Lv  (grey, Gotham 11px)
      separator
      DMG N  or  HP N / HP/s N   (white, GothamBold 15px)
      separator (if catalog effects / substats exist)
      Food: hunger, eat time, timed buffs
      Consumable: HP heal, energy restore
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

-- Label map for every substat id produced by ItemGenerator / ItemClass
local LABELS = {
    dmgMin    = "DMG",
    dmgMax    = "DMG",
    hp        = "HP",
    hps       = "HP/s",
    armor     = "Armor",
    dmgRed    = "DMG Red.",
    energy    = "Energy/s",
    vit       = "VIT (Mace DMG)",
    str       = "STR (Axe DMG)",
    ["int"]  = "INT (Scythe DMG)",
    dex       = "DEX (Sword DMG)",
    vsMon     = "vs. Monsters",
    vsPly     = "vs. Players",
    accuracy  = "Accuracy",
    lifesteal = "Life Steal",
    elemDmg   = "Elemental DMG",
    crushing  = "Crushing",
    critical  = "Critical Strike",
    execute   = "Execute",
    bleed     = "Bleed",
    bleeding  = "Bleeding",
    pierce    = "Armor Pierce",
    cleave    = "Cleave",
    shatter   = "Shatter",
    glowing   = "Glowing",
    blinding  = "Blinding",
    slowness  = "Slowness",
    block     = "Block",
    reflect   = "Reflect",
    dodge     = "Dodge",
    coinFind  = "Coin Find",
    elemRes   = "Elemental Resistance",
}

local PRIMARY_STATS = { dmgMin=true, dmgMax=true, hp=true, hps=true, armor=true, dmgRed=true, energy=true }
local PRIMARY_ORDER = { "dmgMin", "dmgMax", "hp", "hps", "armor", "dmgRed", "energy" }
local PCT_STATS     = {
    vsMon=true, vsPly=true, accuracy=true, lifesteal=true,
    crushing=true, critical=true, execute=true, pierce=true,
    coinFind=true, block=true, reflect=true, dodge=true, elemRes=true,
}

local RARITY_COLORS = {
    Common    = Color3.fromRGB(205, 210, 220),
    Uncommon  = Color3.fromRGB(70,  205, 105),
    Rare      = Color3.fromRGB(80,  170, 255),
    Epic      = Color3.fromRGB(200, 120, 255),
    Legendary = Color3.fromRGB(255, 175,  85),
}

local COLOR_PRIMARY   = Color3.new(1, 1, 1)
local COLOR_SUBSTAT   = Color3.fromRGB(255, 215, 100)
local COLOR_META      = Color3.fromRGB(160, 155, 145)
local COLOR_SEPARATOR = Color3.fromRGB(70,  55,  45)
local COLOR_PROTECTED = Color3.fromRGB(180, 100, 255)
local TOOLTIP_W       = 230

------------------------------------------------------------------------
-- ScreenGui
------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name           = "ItemTooltipGui"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.DisplayOrder   = 999
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled        = false
gui.Parent         = playerGui

local frame = Instance.new("Frame", gui)
frame.Name             = "Tooltip"
frame.Size             = UDim2.fromOffset(TOOLTIP_W, 10)
frame.AutomaticSize    = Enum.AutomaticSize.Y
frame.BackgroundColor3 = Color3.fromRGB(16, 12, 10)
frame.BorderSizePixel  = 0
frame.ZIndex           = 2
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
local sk = Instance.new("UIStroke", frame)
sk.Thickness = 1
sk.Color     = Color3.fromRGB(90, 70, 50)

Instance.new("UIListLayout", frame).SortOrder = Enum.SortOrder.LayoutOrder

local outerPad = Instance.new("UIPadding", frame)
outerPad.PaddingTop    = UDim.new(0, 8)
outerPad.PaddingBottom = UDim.new(0, 8)
outerPad.PaddingLeft   = UDim.new(0, 10)
outerPad.PaddingRight  = UDim.new(0, 10)

------------------------------------------------------------------------
-- Row builders
------------------------------------------------------------------------

local function clearRows()
    for _, c in ipairs(frame:GetChildren()) do
        if c:IsA("TextLabel") or (c:IsA("Frame") and c.Name == "Sep") then
            c:Destroy()
        end
    end
end

local function addRow(text, color, size, bold, order)
    local l = Instance.new("TextLabel", frame)
    l.BackgroundTransparency = 1
    l.Size             = UDim2.new(1, 0, 0, size + 5)
    l.Font             = bold and Enum.Font.GothamBold or Enum.Font.GothamMedium
    l.TextSize         = size
    l.TextColor3       = color
    l.TextXAlignment   = Enum.TextXAlignment.Left
    l.TextWrapped      = true
    l.Text             = text
    l.ZIndex           = 3
    l.LayoutOrder      = order
end

local function addSep(order)
    local s = Instance.new("Frame", frame)
    s.Name             = "Sep"
    s.Size             = UDim2.new(1, 0, 0, 5)
    s.BackgroundTransparency = 1
    s.BorderSizePixel  = 0
    s.ZIndex           = 3
    s.LayoutOrder      = order
    -- thin colored line inside
    local line = Instance.new("Frame", s)
    line.Size             = UDim2.new(1, 0, 0, 1)
    line.Position         = UDim2.new(0, 0, 0.5, 0)
    line.BackgroundColor3 = COLOR_SEPARATOR
    line.BorderSizePixel  = 0
end

------------------------------------------------------------------------
-- Positioning
------------------------------------------------------------------------

local function positionNear(btn)
    task.defer(function()
        if not gui.Enabled then return end
        local abs  = btn.AbsolutePosition
        local absS = btn.AbsoluteSize
        local vp   = workspace.CurrentCamera.ViewportSize
        local H    = frame.AbsoluteSize.Y
        local W    = TOOLTIP_W

        -- Prefer left of button; fall back to right if off-screen
        local x = abs.X - W - 10
        if x < 8 then x = abs.X + absS.X + 10 end
        if x + W > vp.X - 8 then x = vp.X - W - 8 end

        local y = abs.Y
        if y + H > vp.Y - 8 then y = vp.Y - H - 8 end

        frame.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
    end)
end

local function positionAtWorldPart(part)
    task.defer(function()
        if not gui.Enabled then return end
        local cam = workspace.CurrentCamera
        if not cam or typeof(part) ~= "Instance" or not part.Parent then return end
        local worldPos = part.Position + Vector3.new(0, 2, 0)
        local screenPos, onScreen = cam:WorldToScreenPoint(worldPos)
        if not onScreen then
            gui.Enabled = false
            return
        end
        local vp = cam.ViewportSize
        local H = frame.AbsoluteSize.Y
        local W = TOOLTIP_W
        local x = screenPos.X + 18
        local y = screenPos.Y - (H * 0.5)
        if x + W > vp.X - 8 then x = screenPos.X - W - 18 end
        if x < 8 then x = 8 end
        if y < 8 then y = 8 end
        if y + H > vp.Y - 8 then y = vp.Y - H - 8 end
        frame.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
    end)
end

------------------------------------------------------------------------
-- Static catalog effects (Food / Consumable) from ItemDefinitions
------------------------------------------------------------------------

local BUFF_TYPE_LABELS = {
	WalkSpeedPct = "Move speed",
	LuckPct = "Luck (drops)",
}

local function catalogBuffLine(b)
	local label = BUFF_TYPE_LABELS[b.type] or b.type
	local amt = math.floor(tonumber(b.amount) or 0)
	local dur = math.floor((tonumber(b.duration) or 0) + 0.5)
	if b.type == "WalkSpeedPct" or b.type == "LuckPct" then
		return string.format("%s  +%d%%  (%ds)", label, amt, dur)
	end
	return string.format("%s  %+d  (%ds)", label, amt, dur)
end

local function appendCatalogEffectRows(itemId, n)
	if type(itemId) ~= "string" or itemId == "" then
		return n
	end
	local def = ItemDefinitions.Get(itemId)
	if type(def) ~= "table" then
		return n
	end
	local rows = {}
	if def.Kind == "Food" then
		local fc = ItemDefinitions.GetFoodConfig(itemId)
		if fc then
			if fc.hungerAmount > 0 then
				table.insert(rows, { str = string.format("Restores hunger  +%d", fc.hungerAmount), color = COLOR_PRIMARY, size = 15, bold = true })
			end
			if fc.timeToEat > 0 then
				table.insert(rows, { str = string.format("Eat time  %.1fs", fc.timeToEat), color = COLOR_META, size = 11, bold = false })
			else
				table.insert(rows, { str = "Eat time  Instant", color = COLOR_META, size = 11, bold = false })
			end
			for _, b in ipairs(fc.buffs) do
				if type(b) == "table" and (tonumber(b.duration) or 0) > 0 then
					table.insert(rows, { str = catalogBuffLine(b), color = COLOR_SUBSTAT, size = 12, bold = false })
				end
			end
		end
	elseif def.Kind == "Consumable" then
		local heal = tonumber(def.HealAmount)
		if heal and heal > 0 then
			table.insert(rows, { str = string.format("Restores HP  +%d", heal), color = COLOR_PRIMARY, size = 15, bold = true })
		end
		local en = tonumber(def.EnergyAmount)
		if en and en > 0 then
			table.insert(rows, { str = string.format("Restores Energy  +%d", en), color = COLOR_PRIMARY, size = 15, bold = true })
		end
	end
	if #rows == 0 then
		return n
	end
	addSep(n); n += 1
	for _, r in ipairs(rows) do
		addRow(r.str, r.color, r.size, r.bold, n)
		n += 1
	end
	return n
end

------------------------------------------------------------------------
-- Public
------------------------------------------------------------------------

local ItemTooltip = {}

local function renderItem(item)
    if type(item) ~= "table" then return false end
    clearRows()

    local n      = 1
    local rCol   = RARITY_COLORS[item.rarity] or COLOR_PRIMARY
    local subs   = type(item.subStats) == "table" and item.subStats or {}

    -- Name
    addRow(item.name or item.itemId or "Unknown", rCol, 14, true, n); n+=1

    -- Meta: type | tier | level
    local meta = item.type or "Item"
    if item.tier  then meta = meta .. "  |  T" .. item.tier  end
    if item.level then meta = meta .. "  Lv" .. item.level   end
    local ench = math.floor(tonumber(item.enchantLevel) or 0)
    if ench > 0 then
        meta = meta .. "  |  +" .. tostring(ench)
    end
    addRow(meta, COLOR_META, 11, false, n); n+=1

    local itemId = type(item.itemId) == "string" and item.itemId or ""
    if itemId ~= "" then
        local desc = ItemDefinitions.GetDescription(itemId)
        if desc ~= "" then
            addRow(desc, COLOR_META, 11, false, n); n+=1
        end
    end

    n = appendCatalogEffectRows(itemId, n)

    -- Primary stats (DMG / HP / HP/s / Armor)
    local hasPrimary = false
    for _, id in ipairs(PRIMARY_ORDER) do
        if subs[id] then hasPrimary = true; break end
    end

    if hasPrimary then
        addSep(n); n+=1
        -- Weapon DMG shown as a combined "7-9" range
        if subs.dmgMin and subs.dmgMax then
            addRow(string.format("DMG   %d - %d", subs.dmgMin, subs.dmgMax), COLOR_PRIMARY, 15, true, n)
            n+=1
        end
        local skipIds = { dmgMin=true, dmgMax=true }
        for _, id in ipairs(PRIMARY_ORDER) do
            if not skipIds[id] then
                local val = subs[id]
                if val and val ~= 0 then
                    local lbl = LABELS[id] or id
                    local fmt
                    if id == "hps"    then fmt = string.format("%-8s %d/s", lbl, val)
                    elseif id == "dmgRed"  then fmt = string.format("%-8s %d%%", lbl, val)
                    elseif id == "energy" then fmt = string.format("%-8s %.2f/s", lbl, val)
                    else                       fmt = string.format("%-8s %d",   lbl, val)
                    end
                    addRow(fmt, COLOR_PRIMARY, 15, true, n)
                    n+=1
                end
            end
        end
    end

    if (item.type == "Weapon" or item.type == "Armor") and item.scrollProtected == true then
        addSep(n); n+=1
        addRow("Protected", COLOR_PROTECTED, 14, true, n)
        n+=1
    end

    -- Secondary substats
    local subLines = {}
    for id, val in pairs(subs) do
        if not PRIMARY_STATS[id] and val and val ~= 0 and string.sub(id, 1, 1) ~= "_" then
            table.insert(subLines, { id=id, val=val })
        end
    end
    table.sort(subLines, function(a, b) return a.id < b.id end)

    if #subLines > 0 then
        addSep(n); n+=1
        for _, e in ipairs(subLines) do
            local lbl = LABELS[e.id] or e.id
            local fmtV = PCT_STATS[e.id]
                and ("+" .. e.val .. "%")
                or  ("+" .. e.val)
            addRow(
                string.format("%-18s %s", lbl, fmtV),
                COLOR_SUBSTAT, 12, false, n
            )
            n+=1
        end
    end

    return true
end

function ItemTooltip.show(item, anchorBtn)
    if not renderItem(item) then return end
    gui.Enabled = true
    positionNear(anchorBtn)
end

function ItemTooltip.showAtWorldPart(item, part)
    if not renderItem(item) then return end
    gui.Enabled = true
    positionAtWorldPart(part)
end

function ItemTooltip.repositionAtWorldPart(part)
    if not gui.Enabled then return end
    positionAtWorldPart(part)
end

function ItemTooltip.hide()
    gui.Enabled = false
end

return ItemTooltip
