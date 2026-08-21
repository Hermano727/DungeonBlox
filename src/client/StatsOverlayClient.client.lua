--[[
	StatsOverlayClient
	Replaces the DerivedStats text wall in the inventory StatsPanel with a
	compact "View Stats" button. Clicking opens a tall character-sheet overlay
	that shows all combat, attribute, skill and wealth stats with live data.
	Self-contained - no changes to DungeonMenuUI or SkillsTabClient.
]]

local Players      = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player         = Players.LocalPlayer
local playerGui      = player:WaitForChild("PlayerGui")
local DungeonMenuNet = require(script.Parent:WaitForChild("DungeonMenuNet"))
-- Row-value math (sum equipped attributes, format HP/regen/level strings) is
-- shared with the InventoryHud StatsPanel -- see DerivedStatsView for why
-- this used to be two independent copies of the same computation.
local DerivedStatsView = require(ReplicatedStorage:WaitForChild("DerivedStatsView"))

-- Wait for PlayerStatsBox (created by DungeonMenuUI inside SkillsTabClient)
local statsBox
do
	local deadline = os.clock() + 15
	repeat
		statsBox = playerGui:FindFirstChild("PlayerStatsBox", true)
		if not statsBox then task.wait(0.08) end
	until statsBox or os.clock() > deadline
end
if not statsBox then
	warn("[StatsOverlayClient] PlayerStatsBox not found")
	return
end

-- Suppress the existing multiline text wall (DungeonMenuUI still writes to it,
-- we just hide it to free the space for the button)
local derivedStats = statsBox:FindFirstChild("DerivedStats")
if derivedStats then
	derivedStats.Visible = false
end

----------------------------------------------------------------
-- "View Stats" button (left half of the stats box)
----------------------------------------------------------------

local viewBtn            = Instance.new("TextButton")
viewBtn.Name             = "ViewStatsBtn"
viewBtn.Size             = UDim2.new(0.5, -4, 0, 34)
viewBtn.Position         = UDim2.new(0, 0, 0, 26)
viewBtn.BackgroundColor3 = Color3.fromRGB(38, 26, 14)
viewBtn.BorderSizePixel  = 0
viewBtn.Font             = Enum.Font.GothamBold
viewBtn.TextSize         = 12
viewBtn.TextColor3       = Color3.fromRGB(245, 205, 110)
viewBtn.Text             = "View Stats  \xE2\x80\xBA"
viewBtn.AutoButtonColor  = false
viewBtn.ZIndex           = 6
viewBtn.Parent           = statsBox
Instance.new("UICorner", viewBtn).CornerRadius = UDim.new(0, 6)
local vStroke            = Instance.new("UIStroke", viewBtn)
vStroke.Thickness        = 1
vStroke.Color            = Color3.fromRGB(125, 92, 38)

viewBtn.MouseEnter:Connect(function()
	TweenService:Create(viewBtn, TweenInfo.new(0.1),
		{BackgroundColor3 = Color3.fromRGB(54, 38, 18)}):Play()
end)
viewBtn.MouseLeave:Connect(function()
	TweenService:Create(viewBtn, TweenInfo.new(0.1),
		{BackgroundColor3 = Color3.fromRGB(38, 26, 14)}):Play()
end)

----------------------------------------------------------------
-- Overlay ScreenGui
----------------------------------------------------------------

local overlayGui           = Instance.new("ScreenGui")
overlayGui.Name            = "StatsOverlayUI"
overlayGui.ResetOnSpawn    = false
overlayGui.IgnoreGuiInset  = true
overlayGui.DisplayOrder    = 150
overlayGui.Enabled         = false
overlayGui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
overlayGui.Parent          = playerGui

local backdrop                     = Instance.new("TextButton")
backdrop.Size                      = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3          = Color3.new(0, 0, 0)
backdrop.BackgroundTransparency    = 0.52
backdrop.BorderSizePixel           = 0
backdrop.Text                      = ""
backdrop.AutoButtonColor           = false
backdrop.ZIndex                    = 1
backdrop.Parent                    = overlayGui

----------------------------------------------------------------
-- Main character-sheet panel (362 x 554)
----------------------------------------------------------------

local SHEET_W, SHEET_H = 362, 554

local sheet              = Instance.new("Frame")
sheet.Name               = "Sheet"
sheet.AnchorPoint        = Vector2.new(0.5, 0.5)
sheet.Position           = UDim2.new(0.5, 0, 0.5, 0)
sheet.Size               = UDim2.fromOffset(SHEET_W, SHEET_H)
sheet.BackgroundColor3   = Color3.fromRGB(22, 16, 14)
sheet.BorderSizePixel    = 0
sheet.ZIndex             = 2
sheet.Parent             = overlayGui
Instance.new("UICorner", sheet).CornerRadius = UDim.new(0, 14)

local sheetStroke        = Instance.new("UIStroke", sheet)
sheetStroke.Thickness    = 1
sheetStroke.Color        = Color3.fromRGB(92, 68, 40)

local sheetGrad          = Instance.new("UIGradient", sheet)
sheetGrad.Color          = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 22, 17)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 12, 12)),
})
sheetGrad.Rotation = 108

-- Header bar
local HDR_H = 46
local hdrBg            = Instance.new("Frame", sheet)
hdrBg.Size             = UDim2.new(1, 0, 0, HDR_H)
hdrBg.BackgroundColor3 = Color3.fromRGB(34, 24, 15)
hdrBg.BorderSizePixel  = 0
hdrBg.ZIndex           = 3
Instance.new("UICorner", hdrBg).CornerRadius = UDim.new(0, 14)
local hdrPatch             = Instance.new("Frame", hdrBg)
hdrPatch.Size              = UDim2.new(1, 0, 0, 14)
hdrPatch.Position          = UDim2.new(0, 0, 1, -14)
hdrPatch.BackgroundColor3  = Color3.fromRGB(34, 24, 15)
hdrPatch.BorderSizePixel   = 0
hdrPatch.ZIndex            = 3

local accentRule           = Instance.new("Frame", sheet)
accentRule.Size            = UDim2.new(1, -28, 0, 1)
accentRule.Position        = UDim2.new(0, 14, 0, HDR_H)
accentRule.BackgroundColor3 = Color3.fromRGB(105, 76, 36)
accentRule.BorderSizePixel = 0
accentRule.ZIndex          = 3

local hdrTitle               = Instance.new("TextLabel", hdrBg)
hdrTitle.Size                = UDim2.new(1, -50, 1, 0)
hdrTitle.Position            = UDim2.new(0, 16, 0, 0)
hdrTitle.BackgroundTransparency = 1
hdrTitle.Font                = Enum.Font.GothamBold
hdrTitle.TextSize            = 12
hdrTitle.TextColor3          = Color3.fromRGB(210, 184, 138)
hdrTitle.TextXAlignment      = Enum.TextXAlignment.Left
hdrTitle.Text                = "CHARACTER SHEET"
hdrTitle.ZIndex              = 4

local closeBtn             = Instance.new("TextButton", hdrBg)
closeBtn.Size              = UDim2.fromOffset(26, 26)
closeBtn.Position          = UDim2.new(1, -36, 0.5, -13)
closeBtn.BackgroundColor3  = Color3.fromRGB(48, 28, 28)
closeBtn.BorderSizePixel   = 0
closeBtn.Font              = Enum.Font.GothamBold
closeBtn.TextSize          = 13
closeBtn.TextColor3        = Color3.fromRGB(195, 128, 128)
closeBtn.Text              = "x"
closeBtn.AutoButtonColor   = false
closeBtn.ZIndex            = 5
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 5)

closeBtn.MouseEnter:Connect(function()
	TweenService:Create(closeBtn, TweenInfo.new(0.1),
		{BackgroundColor3 = Color3.fromRGB(72, 34, 34)}):Play()
end)
closeBtn.MouseLeave:Connect(function()
	TweenService:Create(closeBtn, TweenInfo.new(0.1),
		{BackgroundColor3 = Color3.fromRGB(48, 28, 28)}):Play()
end)

-- Scrollable content
local content                     = Instance.new("ScrollingFrame", sheet)
content.Position                  = UDim2.new(0, 0, 0, HDR_H + 7)
content.Size                      = UDim2.new(1, 0, 1, -(HDR_H + 7))
content.BackgroundTransparency    = 1
content.BorderSizePixel           = 0
content.ScrollBarThickness        = 3
content.ScrollBarImageColor3      = Color3.fromRGB(90, 68, 40)
content.AutomaticCanvasSize       = Enum.AutomaticSize.Y
content.CanvasSize                = UDim2.new()
content.ZIndex                    = 3
local cList                       = Instance.new("UIListLayout", content)
cList.FillDirection               = Enum.FillDirection.Vertical
cList.SortOrder                   = Enum.SortOrder.LayoutOrder
cList.Padding                     = UDim.new(0, 0)
local cPad                        = Instance.new("UIPadding", content)
cPad.PaddingLeft                  = UDim.new(0, 18)
cPad.PaddingRight                 = UDim.new(0, 18)
cPad.PaddingTop                   = UDim.new(0, 10)
cPad.PaddingBottom                = UDim.new(0, 20)

----------------------------------------------------------------
-- Row / section builder
----------------------------------------------------------------

local C_LABEL   = Color3.fromRGB(152, 137, 116)
local C_VALUE   = Color3.fromRGB(238, 230, 206)
local C_SECTION = Color3.fromRGB(182, 146, 72)
local C_SEP     = Color3.fromRGB(40, 30, 22)
local C_GOLD    = Color3.fromRGB(255, 200, 75)

local lo   = 0
local refs = {}
local function nextLo() lo += 1 return lo end

local function spacer(h)
	local f           = Instance.new("Frame", content)
	f.BackgroundTransparency = 1
	f.Size            = UDim2.new(1, 0, 0, h)
	f.LayoutOrder     = nextLo()
end

local function section(icon, label)
	if lo > 0 then spacer(14) end
	local f           = Instance.new("Frame", content)
	f.BackgroundTransparency = 1
	f.Size            = UDim2.new(1, 0, 0, 26)
	f.LayoutOrder     = nextLo()
	local t           = Instance.new("TextLabel", f)
	t.BackgroundTransparency = 1
	t.Size            = UDim2.new(1, 0, 1, 0)
	t.Font            = Enum.Font.GothamBold
	t.TextSize        = 10
	t.TextColor3      = C_SECTION
	t.TextXAlignment  = Enum.TextXAlignment.Left
	t.Text            = icon .. "   " .. label
	t.ZIndex          = 4
	local rule        = Instance.new("Frame", f)
	rule.BackgroundColor3  = Color3.fromRGB(52, 38, 24)
	rule.BorderSizePixel   = 0
	rule.AnchorPoint       = Vector2.new(0, 1)
	rule.Position          = UDim2.new(0, 0, 1, 0)
	rule.Size              = UDim2.new(1, 0, 0, 1)
	rule.ZIndex            = 3
end

local function row(key, label, isLast, vc)
	local ROW_H      = 27
	local f          = Instance.new("Frame", content)
	f.BackgroundTransparency = 1
	f.Size           = UDim2.new(1, 0, 0, ROW_H)
	f.LayoutOrder    = nextLo()
	local lt         = Instance.new("TextLabel", f)
	lt.BackgroundTransparency = 1
	lt.Size          = UDim2.new(0.6, 0, 1, 0)
	lt.Font          = Enum.Font.GothamMedium
	lt.TextSize      = 12
	lt.TextColor3    = C_LABEL
	lt.TextXAlignment = Enum.TextXAlignment.Left
	lt.Text          = label
	lt.ZIndex        = 4
	local vt         = Instance.new("TextLabel", f)
	vt.BackgroundTransparency = 1
	vt.Size          = UDim2.new(0.4, 0, 1, 0)
	vt.Position      = UDim2.new(0.6, 0, 0, 0)
	vt.Font          = Enum.Font.GothamBold
	vt.TextSize      = 13
	vt.TextColor3    = vc or C_VALUE
	vt.TextXAlignment = Enum.TextXAlignment.Right
	vt.Text          = "-"
	vt.ZIndex        = 4
	refs[key]        = vt
	if not isLast then
		local sep        = Instance.new("Frame", f)
		sep.BackgroundColor3 = C_SEP
		sep.BorderSizePixel  = 0
		sep.AnchorPoint      = Vector2.new(0, 1)
		sep.Position         = UDim2.new(0, 0, 1, 0)
		sep.Size             = UDim2.new(1, 0, 0, 1)
		sep.ZIndex           = 3
	end
end

-- Build stat sections
section("* ", "COMBAT")
row("hp",    "Health")
row("armor", "Armor")
row("hpReg", "HP Regen")
row("enReg", "Energy Regen", true)

section("+ ", "ATTRIBUTES")
row("str",   "STR  -  Axe")
row("int",   "INT  -  Scythe")
row("dex",   "DEX  -  Sword")
row("vit",   "VIT  -  Mace", true)

section("^ ", "SKILLS")
row("combat",  "Combat")
row("mining",  "Mining")
row("fishing", "Fishing", true)

section("$ ", "WEALTH")
row("coins",  "Coins",   false, C_GOLD)
row("inRaid", "In Raid", true)

----------------------------------------------------------------
-- Open / close animation
----------------------------------------------------------------

local isOpen   = false
local EASE_IN  = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local EASE_OUT = TweenInfo.new(0.14, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

local function openSheet()
	if isOpen then return end
	isOpen             = true
	sheet.Position     = UDim2.new(0.5, 0, 0.5, 16)
	overlayGui.Enabled = true
	TweenService:Create(sheet, EASE_IN,
		{Position = UDim2.new(0.5, 0, 0.5, 0)}):Play()
end

local function closeSheet()
	if not isOpen then return end
	isOpen = false
	local t = TweenService:Create(sheet, EASE_OUT,
		{Position = UDim2.new(0.5, 0, 0.5, 10)})
	t:Play()
	t.Completed:Connect(function()
		if not isOpen then overlayGui.Enabled = false end
	end)
end

viewBtn.MouseButton1Click:Connect(openSheet)
closeBtn.MouseButton1Click:Connect(closeSheet)
backdrop.MouseButton1Click:Connect(closeSheet)

----------------------------------------------------------------
-- Live stat sync
----------------------------------------------------------------

local function set(key, val)
	if refs[key] then refs[key].Text = tostring(val) end
end

local function refresh(snap)
	local values = DerivedStatsView.Compute(snap)
	for key, text in pairs(values) do
		set(key, text)
	end
end

DungeonMenuNet.addSnapshotListener(refresh)
task.defer(function()
	refresh(DungeonMenuNet.getLastSnapshot())
end)

print("[StatsOverlayClient] ready")