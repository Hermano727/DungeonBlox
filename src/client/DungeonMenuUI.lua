--[[
  Builds + redraws the Character menu inventory/equipped UI region.
  SkillsTabClient owns Tab/dim/backdrop; this module owns the dungeon panels only.

  STATUS (checked 2026-08-21): this Gui-based screen is currently UNREACHABLE in normal play.
  SkillsTabClient's Tab handler was rewired to do nothing (Tab now opens the React InventoryHud
  panel instead -- see the comment on its InputBegan connection), and nothing else in the
  codebase ever calls SkillsTabClient's local setOpen(true) / setOpenFn(true). DungeonMenuUI.
  redraw() is only reached from inside `if open then ... end` guards, so it never actually runs
  right now either -- createLayout() below still builds this screen's Instance tree once at
  startup (it's just parented under an Enabled=false ScreenGui named "SkillsPopupUI"), but the
  redraw path that would populate it with live data is dead code at runtime.

  This is NOT safe to delete, though -- other client scripts still depend on side effects of
  createLayout() running:
    - HearthstoneClient.init(refs) (called from SkillsTabClient) parents its real Tele/Swap
      buttons into hearthstoneRefs from this module. The InventoryHud React HearthstonePanel is
      explicitly a "no teleport wiring yet, just the grid layout for review" mockup per its own
      header comment -- so the ACTUAL working hearthstone teleport buttons currently live inside
      this same unreachable screen. Functionally, players likely cannot hearthstone-teleport
      right now via any UI path.
    - StatsOverlayClient.client.lua finds this module's "PlayerStatsBox" instance by name and
      parents its own "View Stats" button into it -- meaning that button is ALSO inside the
      unreachable screen and can't currently be seen or clicked.
    - DungeonHotbarHud, InventoryDragController, and QuestTrackerClient all still look up the
      "SkillsPopupUI" ScreenGui by name to check whether the character menu is open (it never
      is, so those checks are permanently false -- harmless, but worth knowing if you're
      debugging why a "menu open" branch never fires).
    - DungeonMenuNet (this same folder) is NOT legacy -- it's the shared data layer the new
      InventoryHud React panels read from too. Don't assume "used by DungeonMenuUI" means "safe
      to remove"; check every requirer first (see file header there).
  Flagging this loudly rather than silently reconnecting Tab or moving Hearthstone/View-Stats
  into the new HUD myself: that's a real product decision (is the legacy screen meant to come
  back, or should Hearthstone/View-Stats be rebuilt as InventoryHud panels?) that needs the
  project owner's call, not a guess made overnight with no one able to playtest it.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types           = require(ReplicatedStorage:WaitForChild("DungeonProfileTypes"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local DayNightConfig  = require(ReplicatedStorage:WaitForChild("DayNightConfig"))
local ItemTooltip = require(script.Parent:WaitForChild("ItemTooltip"))
local InventoryDragController = require(script.Parent:WaitForChild("InventoryDragController"))

local HOTBAR_SLOTS = 9

local EQUIP_SLOTS = { "Helm", "Chest", "Legs", "Boots", "Shield", "Necklace", "Ring" }
local ARMOR_STAT_SLOTS = { "Helm", "Chest", "Legs", "Boots" }
local SLOT_ACCENT = {
    Helm     = Color3.fromRGB(180,160,255),
    Chest    = Color3.fromRGB(255,190,110),
    Legs     = Color3.fromRGB(110,210,180),
    Boots    = Color3.fromRGB(200,160,130),
    Weapon   = Color3.fromRGB(255,120,120),
    Shield   = Color3.fromRGB(120,180,255),
    Necklace = Color3.fromRGB(255,220,80),
    Ring     = Color3.fromRGB(180,255,180),
}

local DungeonMenuUI = {}

local function hotbarSlotUuid(hb, i)
	if type(hb) ~= "table" then return nil end
	i = math.floor(tonumber(i) or -1)
	if i < 1 or i > 9 then return nil end
	local v = hb[i]
	if type(v) == "string" and v ~= "" then return v end
	v = hb[tostring(i)]
	if type(v) == "string" and v ~= "" then return v end
	return nil
end

local function bagSlotUuid(bs, i)
	if type(bs) ~= "table" then return nil end
	i = math.floor(tonumber(i) or -1)
	if i < 1 or i > Types.BAG_SLOT_COUNT then return nil end
	local v = bs[i]
	if type(v) == "string" and v ~= "" then return v end
	v = bs[tostring(i)]
	if type(v) == "string" and v ~= "" then return v end
	return nil
end



local QS = "rbxasset://fonts/families/Quicksand.json"
local function qsFont(lbl, w)
	pcall(function() lbl.FontFace = Font.new(QS, w or Enum.FontWeight.Medium) end)
end

local ALIGNMENTS = { "Lawful", "Neutral", "Chaotic" }
local ALIGNMENT_COLORS = {
	Lawful  = Color3.fromRGB(80, 170, 255),
	Neutral = Color3.fromRGB(255, 200, 80),
	Chaotic = Color3.fromRGB(255, 90, 90),
}

local function applyAlignmentBars(bars, currentAlignment, cooldownUntil)
	if type(bars) ~= "table" then return end
	local now = os.time()
	local locked = now < (tonumber(cooldownUntil) or 0)
	for name, ref in pairs(bars) do
		if ref and ref.button then
			local isActive = (name == currentAlignment)
			if isActive then
				ref.button.BackgroundColor3 = Color3.fromRGB(50, 40, 32)
				ref.nameLabel.TextColor3 = Color3.new(1, 1, 1)
				ref.statusLabel.Text = "Active"
				ref.statusLabel.TextColor3 = Color3.fromRGB(150, 220, 130)
				ref.button.Active = true
				ref.button.AutoButtonColor = true
				ref.stripe.BackgroundTransparency = 0
			elseif locked then
				ref.button.BackgroundColor3 = Color3.fromRGB(22, 18, 18)
				ref.nameLabel.TextColor3 = Color3.fromRGB(110, 100, 100)
				local remaining = math.max(0, (tonumber(cooldownUntil) or 0) - now)
				ref.statusLabel.Text = string.format("Locked: %d:%02d", math.floor(remaining/60), remaining%60)
				ref.statusLabel.TextColor3 = Color3.fromRGB(180, 100, 100)
				ref.button.Active = false
				ref.button.AutoButtonColor = false
				ref.stripe.BackgroundTransparency = 0.6
			else
				ref.button.BackgroundColor3 = Color3.fromRGB(32, 24, 24)
				ref.nameLabel.TextColor3 = Color3.new(1, 1, 1)
				ref.statusLabel.Text = ""
				ref.button.Active = true
				ref.button.AutoButtonColor = true
				ref.stripe.BackgroundTransparency = 0
			end
		end
	end
end

local function clearInventory(scroll)
	for _, child in ipairs(scroll:GetChildren()) do
		if not child:IsA("UIGridLayout") and not child:IsA("UIPadding") and not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
end

function DungeonMenuUI.createLayout(panel, skillRows)
	local PAD_X=14; local HDR_H=48; local SLOT_SZ=76; local SLOT_GAP=6
	local GRID_W=SLOT_SZ*2+SLOT_GAP; local EQUIP_H=SLOT_SZ*2+SLOT_GAP
	local CELL=70; local C_PAD=6; local HB_W=94; local HB_H=60; local HB_PAD=6

	local body=Instance.new("Frame")
	body.Name="DungeonBody"; body.BackgroundTransparency=1
	body.Position=UDim2.new(0,PAD_X,0,HDR_H+2)
	body.Size=UDim2.new(1,-PAD_X*2,1,-(HDR_H+10))
	body.ZIndex=3; body.Parent=panel

	local equipButtons={}; local equipSlotState={}

	local function makeSlotBtn(slot,parent,x,y)
		local btn=Instance.new("TextButton")
		btn.Name="Equip_"..slot; btn.Position=UDim2.fromOffset(x,y)
		btn.Size=UDim2.fromOffset(SLOT_SZ,SLOT_SZ)
		btn.BackgroundColor3=Color3.fromRGB(26,18,18); btn.BorderSizePixel=0
		btn.Text=""; btn.AutoButtonColor=false; btn.ZIndex=5
		Instance.new("UICorner",btn).CornerRadius=UDim.new(0,8)
		local sk=Instance.new("UIStroke",btn); sk.Thickness=1.5
		sk.Color=SLOT_ACCENT[slot] or Color3.fromRGB(55,42,42); sk.Transparency=0.35
		-- Placeholder: slot type, centered, shown when empty
		local ph=Instance.new("TextLabel",btn); ph.Name="Placeholder"
		ph.BackgroundTransparency=1; ph.Size=UDim2.new(1,0,1,0)
		ph.Font=Enum.Font.GothamBold; ph.TextSize=16
		ph.TextColor3=Color3.fromRGB(72,52,52)
		ph.TextXAlignment=Enum.TextXAlignment.Center
		ph.TextYAlignment=Enum.TextYAlignment.Center
		ph.Text=slot:upper(); ph.ZIndex=6
		qsFont(ph, Enum.FontWeight.Bold)
		-- Item name strip at TOP (hidden when empty)
		local nl=Instance.new("TextLabel",btn); nl.Name="ItemName"
		nl.BackgroundTransparency=1; nl.Size=UDim2.new(1,-4,0,15)
		nl.Position=UDim2.new(0,2,0,3)
		nl.Font=Enum.Font.GothamMedium; nl.TextSize=10
		nl.TextColor3=Color3.fromRGB(220,212,195)
		nl.TextXAlignment=Enum.TextXAlignment.Center
		nl.TextTruncate=Enum.TextTruncate.AtEnd
		nl.Text=""; nl.Visible=false; nl.ZIndex=7
		qsFont(nl, Enum.FontWeight.Medium)
		-- Icon fills middle below name
		local il=Instance.new("ImageLabel",btn); il.Name="SlotIcon"
		il.Size=UDim2.new(1,-12,1,-26); il.Position=UDim2.new(0,6,0,18)
		il.BackgroundTransparency=1; il.Image=""; il.ImageTransparency=1
		il.ScaleType=Enum.ScaleType.Fit; il.ZIndex=6
		btn.Parent=parent; return btn
	end

	local rowA=Instance.new("Frame",body); rowA.Name="EquipRow"
	rowA.BackgroundTransparency=1; rowA.Size=UDim2.new(1,0,0,EQUIP_H); rowA.ZIndex=3

	local armorGroup=Instance.new("Frame",rowA); armorGroup.Name="ArmorGroup"
	armorGroup.BackgroundTransparency=1; armorGroup.Size=UDim2.fromOffset(GRID_W,EQUIP_H); armorGroup.ZIndex=3
	local ap={{0,0},{SLOT_SZ+SLOT_GAP,0},{0,SLOT_SZ+SLOT_GAP},{SLOT_SZ+SLOT_GAP,SLOT_SZ+SLOT_GAP}}
	for i,slot in ipairs({"Helm","Chest","Legs","Boots"}) do
		equipButtons[slot]=makeSlotBtn(slot,armorGroup,ap[i][1],ap[i][2])
		equipSlotState[slot]={item=nil,uuid=nil}
	end

	local accGroup=Instance.new("Frame",rowA); accGroup.Name="AccessoryGroup"
	accGroup.BackgroundTransparency=1; accGroup.AnchorPoint=Vector2.new(1,0)
	accGroup.Position=UDim2.new(1,0,0,0); accGroup.Size=UDim2.fromOffset(GRID_W,EQUIP_H); accGroup.ZIndex=3
	for i,slot in ipairs({"Shield","Necklace","Ring"}) do
		equipButtons[slot]=makeSlotBtn(slot,accGroup,ap[i][1],ap[i][2])
		equipSlotState[slot]={item=nil,uuid=nil}
	end

	local ig=12
	local ic=Instance.new("Frame",rowA); ic.Name="InfoCenter"
	ic.BackgroundTransparency=1; ic.Position=UDim2.fromOffset(GRID_W+ig,0)
	ic.Size=UDim2.new(1,-(GRID_W*2+ig*2),0,EQUIP_H); ic.ZIndex=3

	-- PlayerStatsBox: StatsOverlayClient searches for this by name to inject the View Stats button
	local psb=Instance.new("Frame",ic); psb.Name="PlayerStatsBox"
	psb.BackgroundColor3=Color3.fromRGB(22,16,16); psb.BorderSizePixel=0
	psb.Position=UDim2.new(0,0,0,0); psb.Size=UDim2.new(0.52,-4,0,62); psb.ZIndex=4
	Instance.new("UICorner",psb).CornerRadius=UDim.new(0,8)
	local psbPad=Instance.new("UIPadding",psb)
	psbPad.PaddingLeft=UDim.new(0,8); psbPad.PaddingTop=UDim.new(0,6)

	local currency=Instance.new("TextLabel",psb); currency.Name="Currency"
	currency.BackgroundTransparency=1; currency.Font=Enum.Font.GothamMedium; currency.TextSize=14
	currency.TextColor3=Color3.fromRGB(230,220,200); currency.TextXAlignment=Enum.TextXAlignment.Left
	currency.Text="Coins: 0"; currency.Size=UDim2.new(1,-4,0,22); currency.ZIndex=5
	qsFont(currency, Enum.FontWeight.Medium)

	local stats=Instance.new("TextLabel",psb); stats.Name="DerivedStats"
	stats.BackgroundTransparency=1; stats.Font=Enum.Font.Gotham; stats.TextSize=11
	stats.TextWrapped=true; stats.AutomaticSize=Enum.AutomaticSize.Y
	stats.Text="Syncing..."; stats.Size=UDim2.new(1,-4,0,0)
	stats.Position=UDim2.new(0,0,0,24); stats.Visible=false; stats.ZIndex=5

	local hsBox=Instance.new("Frame",ic); hsBox.Name="HearthstoneOverlay"
	hsBox.BackgroundColor3=Color3.fromRGB(20,14,14); hsBox.BorderSizePixel=0
	hsBox.Position=UDim2.new(0,0,0,68); hsBox.Size=UDim2.new(0.52,-4,1,-68); hsBox.ZIndex=4
	Instance.new("UICorner",hsBox).CornerRadius=UDim.new(0,8)
	local hsPad=Instance.new("UIPadding",hsBox)
	hsPad.PaddingLeft=UDim.new(0,10); hsPad.PaddingRight=UDim.new(0,10); hsPad.PaddingTop=UDim.new(0,8)

	local hsTitle=Instance.new("TextLabel",hsBox); hsTitle.Name="HSTitle"
	hsTitle.BackgroundTransparency=1; hsTitle.Font=Enum.Font.GothamBold; hsTitle.TextSize=10
	hsTitle.TextColor3=Color3.fromRGB(120,95,80); hsTitle.TextXAlignment=Enum.TextXAlignment.Left
	hsTitle.Text="HEARTHSTONE"; hsTitle.Size=UDim2.new(1,0,0,14); hsTitle.ZIndex=5
	qsFont(hsTitle, Enum.FontWeight.Bold)

	local hsLoc=Instance.new("TextLabel",hsBox); hsLoc.Name="HSLocation"
	hsLoc.BackgroundTransparency=1; hsLoc.Font=Enum.Font.GothamMedium; hsLoc.TextSize=17
	hsLoc.TextColor3=Color3.fromRGB(230,218,195); hsLoc.TextXAlignment=Enum.TextXAlignment.Left
	hsLoc.Text="Cyren"; hsLoc.Size=UDim2.new(1,0,0,22); hsLoc.Position=UDim2.new(0,0,0,20); hsLoc.ZIndex=5
	qsFont(hsLoc, Enum.FontWeight.SemiBold)

	local hsBR=Instance.new("Frame",hsBox); hsBR.Name="HSBtnRow"
	hsBR.BackgroundTransparency=1; hsBR.Position=UDim2.new(0,0,0,44)
	hsBR.Size=UDim2.new(1,0,0,30); hsBR.ZIndex=5
	local hsBL=Instance.new("UIListLayout",hsBR)
	hsBL.FillDirection=Enum.FillDirection.Horizontal
	hsBL.VerticalAlignment=Enum.VerticalAlignment.Center; hsBL.Padding=UDim.new(0,6)

	local teleBtn=Instance.new("TextButton",hsBR); teleBtn.Name="TeleButton"
	teleBtn.Size=UDim2.fromOffset(54,26); teleBtn.BackgroundColor3=Color3.fromRGB(160,118,38)
	teleBtn.BorderSizePixel=0; teleBtn.Font=Enum.Font.GothamBold; teleBtn.TextSize=11
	teleBtn.TextColor3=Color3.new(1,1,1); teleBtn.Text="Tele"; teleBtn.ZIndex=6
	Instance.new("UICorner",teleBtn).CornerRadius=UDim.new(0,5)

	local swapBtn=Instance.new("TextButton",hsBR); swapBtn.Name="SwapButton"
	swapBtn.Size=UDim2.fromOffset(54,26); swapBtn.BackgroundColor3=Color3.fromRGB(36,26,26)
	swapBtn.BorderSizePixel=0; swapBtn.Font=Enum.Font.GothamBold; swapBtn.TextSize=11
	swapBtn.TextColor3=Color3.fromRGB(200,182,160); swapBtn.Text="Swap"; swapBtn.ZIndex=6
	Instance.new("UICorner",swapBtn).CornerRadius=UDim.new(0,5)
	local ss2=Instance.new("UIStroke",swapBtn); ss2.Color=Color3.fromRGB(75,55,55); ss2.Thickness=1

	local ab=Instance.new("Frame",ic); ab.Name="AlignmentPanel"
	ab.BackgroundTransparency=1; ab.Position=UDim2.new(0.52,4,0,0)
	ab.Size=UDim2.new(0.48,-4,1,0); ab.ZIndex=4

	local ah=Instance.new("TextLabel",ab); ah.Name="AlignmentHeader"
	ah.BackgroundTransparency=1; ah.Font=Enum.Font.GothamBold; ah.TextSize=11
	ah.TextColor3=Color3.fromRGB(190,170,140); ah.TextXAlignment=Enum.TextXAlignment.Left
	ah.Text="ALIGNMENT"; ah.Size=UDim2.new(1,0,0,16); ah.ZIndex=5
	qsFont(ah, Enum.FontWeight.Bold)

	local alignBars={}
	local BH=34; local BG=4
	local alignEv=ReplicatedStorage:FindFirstChild("DungeonAlignmentRequest")
	if not alignEv then
		task.spawn(function() alignEv=ReplicatedStorage:WaitForChild("DungeonAlignmentRequest",10) end)
	end
	for i,name in ipairs(ALIGNMENTS) do
		local bar=Instance.new("TextButton",ab); bar.Name=name.."Bar"
		bar.AutoButtonColor=false; bar.Text=""
		bar.BackgroundColor3=Color3.fromRGB(32,24,24); bar.BorderSizePixel=0
		bar.Size=UDim2.new(1,0,0,BH); bar.Position=UDim2.fromOffset(0,18+(i-1)*(BH+BG)); bar.ZIndex=5
		Instance.new("UICorner",bar).CornerRadius=UDim.new(0,6)
		local stripe=Instance.new("Frame",bar); stripe.Name="Stripe"
		stripe.BackgroundColor3=ALIGNMENT_COLORS[name]; stripe.BorderSizePixel=0
		stripe.Size=UDim2.new(0,3,1,-6); stripe.Position=UDim2.new(0,4,0,3); stripe.ZIndex=6
		Instance.new("UICorner",stripe).CornerRadius=UDim.new(0,2)
		local nL=Instance.new("TextLabel",bar); nL.Name="NameLabel"
		nL.BackgroundTransparency=1; nL.Font=Enum.Font.GothamBold; nL.TextSize=13
		nL.TextColor3=Color3.new(1,1,1); nL.TextXAlignment=Enum.TextXAlignment.Left
		nL.Text=name; nL.Size=UDim2.new(0.5,-14,1,0); nL.Position=UDim2.fromOffset(14,0); nL.ZIndex=6
		qsFont(nL, Enum.FontWeight.SemiBold)
		local sL=Instance.new("TextLabel",bar); sL.Name="StatusLabel"
		sL.BackgroundTransparency=1; sL.Font=Enum.Font.Gotham; sL.TextSize=11
		sL.TextColor3=Color3.fromRGB(180,180,180); sL.TextXAlignment=Enum.TextXAlignment.Right
		sL.Text=""; sL.Size=UDim2.new(0.5,-8,1,0); sL.Position=UDim2.new(0.5,0,0,0); sL.ZIndex=6
		alignBars[name]={button=bar,nameLabel=nL,statusLabel=sL,stripe=stripe}
		local cn=name
		bar.MouseButton1Click:Connect(function()
			if not bar.Active then return end
			local ev=alignEv or ReplicatedStorage:FindFirstChild("DungeonAlignmentRequest")
			if ev then ev:FireServer(cn) end
		end)
	end
	local alignmentState={current="Lawful",cooldownUntil=0}
	task.spawn(function()
		while true do
			task.wait(1)
			if alignmentState.cooldownUntil>os.time() then
				applyAlignmentBars(alignBars,alignmentState.current,alignmentState.cooldownUntil)
			elseif alignmentState._wasLockedLastTick then
				alignmentState._wasLockedLastTick=false
				applyAlignmentBars(alignBars,alignmentState.current,0)
			end
		end
	end)

	local ROW_CLOCK_Y=EQUIP_H+10
	local CLOCK_H=36
	local clockRow=Instance.new("Frame",body); clockRow.Name="DayNightRow"
	clockRow.BackgroundTransparency=1
	clockRow.Position=UDim2.new(0,0,0,ROW_CLOCK_Y)
	clockRow.Size=UDim2.new(1,0,0,CLOCK_H); clockRow.ZIndex=3

	local clockPanel=Instance.new("Frame",clockRow); clockPanel.Name="DayNightClock"
	clockPanel.BackgroundColor3=Color3.fromRGB(20,14,14); clockPanel.BorderSizePixel=0
	clockPanel.AnchorPoint=Vector2.new(1,0)
	clockPanel.Position=UDim2.new(1,0,0,0)
	clockPanel.Size=UDim2.new(0.48,-4,1,0); clockPanel.ZIndex=4
	Instance.new("UICorner",clockPanel).CornerRadius=UDim.new(0,8)
	local cp=Instance.new("UIPadding",clockPanel)
	cp.PaddingLeft=UDim.new(0,10); cp.PaddingRight=UDim.new(0,10)
	cp.PaddingTop=UDim.new(0,4); cp.PaddingBottom=UDim.new(0,4)

	local clockPhase=Instance.new("TextLabel",clockPanel); clockPhase.Name="PhaseLabel"
	clockPhase.BackgroundTransparency=1; clockPhase.Font=Enum.Font.GothamBold; clockPhase.TextSize=11
	clockPhase.TextColor3=Color3.fromRGB(255,210,90); clockPhase.TextXAlignment=Enum.TextXAlignment.Left
	clockPhase.Text="DAY"; clockPhase.Size=UDim2.new(0.42,0,0,14); clockPhase.ZIndex=5
	qsFont(clockPhase, Enum.FontWeight.Bold)

	local clockTime=Instance.new("TextLabel",clockPanel); clockTime.Name="TimeLabel"
	clockTime.BackgroundTransparency=1; clockTime.Font=Enum.Font.GothamMedium; clockTime.TextSize=16
	clockTime.TextColor3=Color3.fromRGB(230,218,195); clockTime.TextXAlignment=Enum.TextXAlignment.Left
	clockTime.Text="12:00 PM"; clockTime.Position=UDim2.new(0,0,0,14)
	clockTime.Size=UDim2.new(0.58,0,0,18); clockTime.ZIndex=5
	qsFont(clockTime, Enum.FontWeight.SemiBold)

	local clockRemain=Instance.new("TextLabel",clockPanel); clockRemain.Name="RemainingLabel"
	clockRemain.BackgroundTransparency=1; clockRemain.Font=Enum.Font.Gotham; clockRemain.TextSize=10
	clockRemain.TextColor3=Color3.fromRGB(150,135,115); clockRemain.TextXAlignment=Enum.TextXAlignment.Right
	clockRemain.Text="Night in 20:00"
	clockRemain.AnchorPoint=Vector2.new(1,0)
	clockRemain.Position=UDim2.new(1,0,0,0)
	clockRemain.Size=UDim2.new(0.55,0,1,0); clockRemain.ZIndex=5

	local ROW_B_Y=ROW_CLOCK_Y+CLOCK_H+8
	local sb=Instance.new("Frame",body); sb.Name="SkillsBox"
	sb.BackgroundColor3=Color3.fromRGB(20,14,14); sb.BorderSizePixel=0
	sb.Position=UDim2.new(0,0,0,ROW_B_Y); sb.Size=UDim2.new(1,0,0,54); sb.ZIndex=3
	Instance.new("UICorner",sb).CornerRadius=UDim.new(0,8)
	local sp2=Instance.new("UIPadding",sb)
	sp2.PaddingLeft=UDim.new(0,6); sp2.PaddingRight=UDim.new(0,6); sp2.PaddingTop=UDim.new(0,4)
	local sl2=Instance.new("UIListLayout",sb)
	sl2.FillDirection=Enum.FillDirection.Horizontal
	sl2.VerticalAlignment=Enum.VerticalAlignment.Center
	sl2.SortOrder=Enum.SortOrder.LayoutOrder; sl2.Padding=UDim.new(0,8)
	for i,row in ipairs(skillRows) do
		row.Parent=sb; row.LayoutOrder=i; row.Size=UDim2.new(0.333,-8,0,46)
	end

	local BAG_Y=ROW_B_Y+54+12
	local bLine=Instance.new("Frame",body)
	bLine.BackgroundColor3=Color3.fromRGB(52,38,26); bLine.BorderSizePixel=0
	bLine.Position=UDim2.new(0,0,0,BAG_Y+7); bLine.Size=UDim2.new(1,0,0,1); bLine.ZIndex=3
	local bLbl=Instance.new("TextLabel",body)
	bLbl.BackgroundTransparency=1; bLbl.Font=Enum.Font.GothamBold; bLbl.TextSize=11
	bLbl.TextColor3=Color3.fromRGB(130,105,80); bLbl.TextXAlignment=Enum.TextXAlignment.Left
	bLbl.Text="BAG"; bLbl.Position=UDim2.new(0,0,0,BAG_Y); bLbl.Size=UDim2.new(0,44,0,16); bLbl.ZIndex=3
	qsFont(bLbl, Enum.FontWeight.Bold)

	local invSec=Instance.new("Frame",body); invSec.Name="InventorySection"
	invSec.BackgroundColor3=Color3.fromRGB(18,13,13); invSec.BorderSizePixel=0
	invSec.Position=UDim2.new(0,0,0,BAG_Y+14)
	invSec.Size=UDim2.new(1,0,0,CELL*3+C_PAD*2+16); invSec.ZIndex=3
	Instance.new("UICorner",invSec).CornerRadius=UDim.new(0,8)

	local scroll=Instance.new("ScrollingFrame",invSec); scroll.Name="InventoryScroll"
	scroll.BackgroundTransparency=1; scroll.BorderSizePixel=0; scroll.ScrollBarThickness=5
	scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y; scroll.CanvasSize=UDim2.new()
	scroll.Size=UDim2.new(1,0,1,0); scroll.ZIndex=4

	local grid=Instance.new("UIGridLayout",scroll)
	grid.CellSize=UDim2.fromOffset(CELL,CELL); grid.CellPadding=UDim2.fromOffset(C_PAD,C_PAD)
	grid.SortOrder=Enum.SortOrder.LayoutOrder; grid.FillDirectionMaxCells=9

	local invPad=Instance.new("UIPadding",scroll)
	invPad.PaddingTop=UDim.new(0,8); invPad.PaddingLeft=UDim.new(0,8)
	invPad.PaddingRight=UDim.new(0,8); invPad.PaddingBottom=UDim.new(0,8)

	local abl=Instance.new("Frame",body); abl.Name="ActiveBuffsList"
	abl.BackgroundTransparency=1; abl.Size=UDim2.new(0,0,0,0); abl.Visible=false
	Instance.new("UIListLayout",abl)

	local HB_Y=BAG_Y+14+CELL*3+C_PAD*2+16+12
	local hbLine=Instance.new("Frame",body)
	hbLine.BackgroundColor3=Color3.fromRGB(52,38,26); hbLine.BorderSizePixel=0
	hbLine.Position=UDim2.new(0,0,0,HB_Y+7); hbLine.Size=UDim2.new(1,0,0,1); hbLine.ZIndex=3
	local hbLbl=Instance.new("TextLabel",body)
	hbLbl.BackgroundTransparency=1; hbLbl.Font=Enum.Font.GothamBold; hbLbl.TextSize=11
	hbLbl.TextColor3=Color3.fromRGB(130,105,80); hbLbl.TextXAlignment=Enum.TextXAlignment.Left
	hbLbl.Text="HOTBAR"; hbLbl.Position=UDim2.new(0,0,0,HB_Y); hbLbl.Size=UDim2.new(0,68,0,16); hbLbl.ZIndex=3
	qsFont(hbLbl, Enum.FontWeight.Bold)

	local hbTotalW = HOTBAR_SLOTS * HB_W + (HOTBAR_SLOTS - 1) * HB_PAD
	local hbWrap = Instance.new("Frame", body)
	hbWrap.Name = "HotbarScroll"
	hbWrap.BackgroundTransparency = 1
	hbWrap.BorderSizePixel = 0
	hbWrap.Position = UDim2.new(0, 0, 0, HB_Y + 16)
	hbWrap.Size = UDim2.new(1, 0, 0, HB_H)
	hbWrap.ZIndex = 4

	local hbRow = Instance.new("Frame", hbWrap)
	hbRow.Name = "HotbarButtons"
	hbRow.BackgroundTransparency = 1
	hbRow.Size = UDim2.fromOffset(hbTotalW, HB_H)
	hbRow.ZIndex = 4

	local hotbarButtons = {}; local hotbarSlotItem = {}; local ctxHolder = { current = nil }
	for i = 1, HOTBAR_SLOTS do
		local b = Instance.new("TextButton")
		b.Name = "HB" .. i; b.AutoButtonColor = false; b.TextWrapped = true
		b.Font = Enum.Font.GothamMedium; b.TextSize = 13; b.TextColor3 = Color3.new(1, 1, 1)
		qsFont(b, Enum.FontWeight.Medium)
		b.BackgroundColor3 = Color3.fromRGB(36, 28, 28); b.Size = UDim2.fromOffset(HB_W, HB_H)
		b.Position = UDim2.fromOffset((i - 1) * (HB_W + HB_PAD), 0)
		b.ZIndex = 5; b.TextXAlignment = Enum.TextXAlignment.Center
		b.TextYAlignment = Enum.TextYAlignment.Center
		b.Text = tostring(i) .. "\n(empty)"
		Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
		b:SetAttribute("HotbarSlot", i)
		b.Parent = hbRow
		InventoryDragController.hookSource("hotbar", b, {})
		local si=i
		b.MouseEnter:Connect(function()
			local slot = tonumber(b:GetAttribute("HotbarSlot")) or si; local it=hotbarSlotItem[slot]; if it then ItemTooltip.show(it,b) end
			InventoryDragController.setHoveredHotbar(tonumber(b:GetAttribute("HotbarSlot")) or si)
		end)
		b.MouseLeave:Connect(function()
			ItemTooltip.hide()
			InventoryDragController.clearHoveredHotbar(tonumber(b:GetAttribute("HotbarSlot")) or si)
		end)
		-- Hotbar clicks while the menu is open are owned entirely by InventoryDragController's
		-- click-to-pick-up/click-to-place (hookSource below) -- there is no separate
		-- equip-by-click-while-menu-open feature (onHotbarSelect was never wired in menuCtx).
		b.MouseButton2Click:Connect(function()
			local h=ctxHolder.current; if h and h.onHotbarClear then do local slot=b:GetAttribute("HotbarSlot"); if type(slot)~="number" then slot=tonumber(string.match(b.Name,"^HB(%d+)$")) end; if type(slot)=="number" then h.onHotbarClear(math.floor(slot)) end end end
		end)
		hotbarButtons[i]=b
	end

	for _,slot in ipairs(EQUIP_SLOTS) do
		local btn=equipButtons[slot]
		if btn then
			equipSlotState[slot]=equipSlotState[slot] or {item=nil,uuid=nil}
			local sl=slot
			btn.MouseEnter:Connect(function()
				local s=equipSlotState[sl]; if s and s.item then ItemTooltip.show(s.item,btn) end
				InventoryDragController.setHoveredEquip(sl)
			end)
			btn.MouseLeave:Connect(function()
				ItemTooltip.hide()
				InventoryDragController.clearHoveredEquip(sl)
			end)
			btn.MouseButton2Click:Connect(function()
				ItemTooltip.hide()
				local h=ctxHolder.current
				if h and h.onEquippedSecondary then h.onEquippedSecondary(sl) end
			end)
		end
	end

	return {
		statsCurrency=currency, statsDerived=stats, inventoryScroll=scroll,
		activeBuffsList=abl, hotbarButtons=hotbarButtons, hotbarRow=hbRow, hotbarSlotItem=hotbarSlotItem,
		ctxHolder=ctxHolder, equipButtons=equipButtons, equipSlotState=equipSlotState,
		hearthstoneRefs={locationLabel=hsLoc,teleButton=teleBtn,swapButton=swapBtn},
		alignmentRefs={bars=alignBars,state=alignmentState},
		dayNightRefs={phaseLabel=clockPhase,timeLabel=clockTime,remainingLabel=clockRemain},
	}
end

local function bagItemHotbarOk(item)
	if type(item)~="table" then return false end
	if type(item.itemId)=="string" and item.itemId~="" then
		return ItemDefinitions.IsHotbarEquippable(item.itemId)
	end
	if item.type=="Weapon" then return true end
	if item.type=="Consumable" then return true end
	if item.type=="Armor" then return false end
	if item.type=="Material" then
		if item.equipSlot=="Pickaxe" or item.equipSlot=="FishingSpear" then return true end
		if type(item.toolPrefabName)=="string" and item.toolPrefabName~="" then return true end
		return false
	end
	return false
end

local function itemDisplayName(item)
	if type(item)~="table" then return "Item" end
	local base
	if item.name and item.name~="" then base=item.name
	elseif item.itemId and item.itemId~="" then base=item.itemId
	else base="Item" end
	local ench=math.floor(tonumber(item.enchantLevel) or 0)
	if ench>0 then return base.." +"..tostring(ench) end
	return base
end

local function itemCount(item)
	if type(item)=="table" and type(item.count)=="number" and item.count>1 then return item.count end
	return nil
end

-- Pure durability -> {text, color} mapping. Used by syncDurabilityLabel (equip slots + bag
-- slots) AND by the hotbar redraw loop further down, which used to hand-roll an identical copy
-- of this exact ratio/threshold logic inline -- the red/yellow/grey cutoffs (0.3, 0.5) now only
-- ever live in one place, so retuning them can't accidentally miss one of the two call sites.
local function durabilityTextAndColor(it)
	local dur=it.durability or 0
	local ratio=it.maxDurability>0 and dur/it.maxDurability or 0
	local text=it.broken and "BROKEN" or (dur.."/"..it.maxDurability)
	local color=it.broken and Color3.fromRGB(255,60,60)
		or (ratio<0.3 and Color3.fromRGB(255,80,80) or (ratio<0.5 and Color3.fromRGB(255,200,50) or Color3.fromRGB(120,120,120)))
	return text, color, ratio
end

local function syncDurabilityLabel(parent,it)
	local old=parent:FindFirstChild("DurLabel")
	if not it or not it.maxDurability then if old then old:Destroy() end; return end
	local dl=old
	if not dl then
		dl=Instance.new("TextLabel",parent); dl.Name="DurLabel"
		dl.Size=UDim2.new(1,-4,0,10); dl.Position=UDim2.new(0,2,1,-11)
		dl.BackgroundTransparency=1; dl.Font=Enum.Font.GothamBold
		dl.TextSize=7; dl.TextXAlignment=Enum.TextXAlignment.Center; dl.ZIndex=8
	end
	dl.Text, dl.TextColor3 = durabilityTextAndColor(it)
end

function DungeonMenuUI.redraw(refs,snapshot,ctx)
	local profile=snapshot.profile; local derived=snapshot.derived
	if type(profile)~="table" or type(derived)~="table" then return end
	local inv=profile.inventory or {}
	if refs.ctxHolder then refs.ctxHolder.current=ctx end
	local coins=math.floor(tonumber(profile.currencies and profile.currencies.Coins) or 0)
	local inRaid=profile.flags and profile.flags.inRaid
	refs.statsCurrency.Text=string.format("Coins: %d   Raid: %s",coins,inRaid and "Yes" or "No")
	local dc=derived.combat
	local armorTotals={vit=0,str=0,int=0,dex=0}
	local eqRef=profile.equipped or {}
	for _,slot in ipairs(ARMOR_STAT_SLOTS) do
		local uuid=eqRef[slot]
		if type(uuid)=="string" and uuid~="" then
			local it=inv[uuid]
			if type(it)=="table" and type(it.subStats)=="table" then
				for id in pairs(armorTotals) do
					armorTotals[id]=armorTotals[id]+(tonumber(it.subStats[id]) or 0)
				end
			end
		end
	end
	refs.statsDerived.Text=string.format(
		"HP: %d/%d  Armor: %d  HPRegen: %.1f/s  EnergyRegen: %.1f/s\nSTR:%d INT:%d DEX:%d VIT:%d  Mining:%d Fishing:%d",
		math.floor(dc.hp),math.floor(dc.maxHp),math.floor(dc.armor),dc.hpRegen,dc.energyRegen,
		armorTotals.str,armorTotals.int,armorTotals.dex,armorTotals.vit,
		derived.mining.miningLevel,derived.fishing.fishingLevel
	)
	if refs.alignmentRefs then
		local alignment=profile.alignment
		local current=(type(alignment)=="table" and type(alignment.current)=="string") and alignment.current or "Lawful"
		local cdUntil=(type(alignment)=="table" and tonumber(alignment.cooldownUntil)) or 0
		refs.alignmentRefs.state.current=current
		refs.alignmentRefs.state.cooldownUntil=cdUntil
		refs.alignmentRefs.state._wasLockedLastTick=(cdUntil>os.time())
		applyAlignmentBars(refs.alignmentRefs.bars,current,cdUntil)
	end
	local equipped=profile.equipped or {}
	if refs.equipButtons and refs.equipSlotState then
		for _,slot in ipairs(EQUIP_SLOTS) do
			local btn=refs.equipButtons[slot]
			if not btn then continue end
			local st=refs.equipSlotState[slot]
			local uuid=equipped[slot]
			local it=(type(uuid)=="string" and uuid~="") and inv[uuid] or nil
			local iL=btn:FindFirstChild("ItemName")
			local sI=btn:FindFirstChild("SlotIcon")
			local ph=btn:FindFirstChild("Placeholder")
			if st then st.item=it; st.uuid=it and uuid or nil end
			if it then
				if ph then ph.Visible=false end
				-- Name at top strip
				if iL then
					iL.Visible=true
					iL.Text=itemDisplayName(it)
					iL.TextColor3=Types.GetRarityColor(it.rarity)
				end
				local iconId=ItemDefinitions.GetIcon(it.itemId or "")
				if sI then sI.Image=iconId; sI.ImageTransparency=iconId~="" and 0 or 1 end
				syncDurabilityLabel(btn,it)
			else
				if ph then ph.Visible=true end
				if iL then iL.Visible=false; iL.Text="" end
				if sI then sI.Image=""; sI.ImageTransparency=1 end
				syncDurabilityLabel(btn,nil)
			end
		end
	end
	clearInventory(refs.inventoryScroll)
	if type(inv)~="table" then inv={} end
	local hotbar=profile.hotbar
	if type(hotbar)~="table" then hotbar={} end
	local bagSlots=profile.bagSlots
	if type(bagSlots)~="table" then bagSlots={} end
	local BAG_SLOTS=Types.BAG_SLOT_COUNT
	do
		for slotIdx=1,BAG_SLOTS do
			local uuid=bagSlotUuid(bagSlots, slotIdx)
			local item=(type(uuid)=="string" and uuid~="") and inv[uuid] or nil
			local hbOk=item and bagItemHotbarOk(item); local isArmor=item and item.type=="Armor"
			local showFull=hbOk or isArmor
			local rCol=item and Types.GetRarityColor(item.rarity) or Color3.fromRGB(35,28,28)
			local dimBg=item and rCol:Lerp(Color3.fromRGB(18,14,14),0.78) or Color3.fromRGB(22,17,17)
			local nm=item and itemDisplayName(item) or ""; local cnt=item and itemCount(item)
			local btn=Instance.new("TextButton")
			btn.Name=uuid and ("Item_"..uuid) or ("Slot_"..slotIdx)
			btn.AutoButtonColor=false; btn.Text=""
			btn.BackgroundColor3=Color3.fromRGB(24,18,18); btn.BorderSizePixel=0
			btn.Size=UDim2.fromOffset(60,60); btn.LayoutOrder=slotIdx; btn.ZIndex=5
			Instance.new("UICorner",btn).CornerRadius=UDim.new(0,5)
			local sk=Instance.new("UIStroke",btn); sk.Thickness=1.5
			sk.Color=item and (showFull and rCol or Color3.fromRGB(50,40,40)) or Color3.fromRGB(38,30,30)
			sk.Transparency=item and (showFull and 0.4 or 0.7) or 0.35
			btn:SetAttribute("BagSlot",slotIdx)
			if uuid then btn:SetAttribute("BagUUID",uuid) end
			local iconImg=item and item.itemId and ItemDefinitions.GetIcon(item.itemId) or ""
			local hasIcon=iconImg~=""
			local icon=Instance.new("ImageLabel",btn); icon.Name="Icon"
			icon.Size=UDim2.new(1,-8,1,-20); icon.Position=UDim2.new(0,4,0,4)
			icon.BackgroundColor3=hasIcon and Color3.fromRGB(0,0,0) or dimBg
			icon.BackgroundTransparency=hasIcon and 1 or (item and (showFull and 0 or 0.5) or 0.75)
			icon.BorderSizePixel=0; icon.Image=iconImg
			icon.ImageTransparency=(item and hasIcon) and 0 or 1
			icon.ScaleType=Enum.ScaleType.Fit; icon.ZIndex=6
			Instance.new("UICorner",icon).CornerRadius=UDim.new(0,4)
			if cnt then
				local badge=Instance.new("TextLabel",btn)
				badge.Size=UDim2.fromOffset(22,13); badge.Position=UDim2.new(1,-24,0,2)
				badge.BackgroundTransparency=1; badge.Text="x"..tostring(cnt)
				badge.Font=Enum.Font.GothamBold; badge.TextSize=9
				badge.TextColor3=Color3.fromRGB(230,220,200); badge.ZIndex=7
			end
			local lbl=Instance.new("TextLabel",btn); lbl.Name="NameLabel"
			local hasDur=item and item.maxDurability
			lbl.Size=UDim2.new(1,-4,0,hasDur and 11 or 14)
			lbl.Position=UDim2.new(0,2,1,hasDur and -25 or -15)
			lbl.BackgroundTransparency=1; lbl.Font=Enum.Font.Gotham; lbl.TextSize=8
			lbl.TextColor3=item and (showFull and Color3.fromRGB(220,212,195) or Color3.fromRGB(110,100,90)) or Color3.fromRGB(45,36,36)
			lbl.TextXAlignment=Enum.TextXAlignment.Center
			lbl.TextTruncate=Enum.TextTruncate.AtEnd; lbl.Text=nm; lbl.ZIndex=7
			if item and item.maxDurability then
				syncDurabilityLabel(btn,item)
				local dl=btn:FindFirstChild("DurLabel")
				if dl then dl.Position=UDim2.new(0,2,1,-12) end
			else syncDurabilityLabel(btn,nil) end
			if item and uuid then
				btn.MouseButton2Click:Connect(function()
					if ctx and ctx.onBagSecondary then ctx.onBagSecondary(uuid) end
				end)
			end
			-- Hover and click sources are hooked unconditionally (not just when occupied): an
			-- empty bag slot must still be a valid hover target / click-to-place destination.
			local ci,cb,thisSlot=item,btn,slotIdx
			btn.MouseEnter:Connect(function()
				if ci then ItemTooltip.show(ci,cb) end
				InventoryDragController.setHoveredBag(uuid,thisSlot)
			end)
			btn.MouseLeave:Connect(function()
				ItemTooltip.hide()
				InventoryDragController.clearHoveredBag(thisSlot)
			end)
			InventoryDragController.hookSource("bag",btn,{uuid=uuid,bagSlot=slotIdx})
			btn.Parent=refs.inventoryScroll
		end
	end
	local hb=refs.hotbarButtons; local hsi=refs.hotbarSlotItem
	local hbRow=refs.hotbarRow
	if hbRow then
		if type(hb)~="table" then hb={}; refs.hotbarButtons=hb end
		for _,child in ipairs(hbRow:GetChildren()) do
			if child:IsA("GuiButton") then
				local slot=tonumber(child.Name:match("^HB(%d+)$"))
				if slot and slot>=1 and slot<=HOTBAR_SLOTS then hb[slot]=child end
			end
		end
	end
	if type(hsi)=="table" then for _i=1,HOTBAR_SLOTS do hsi[_i]=nil end end
	if type(hb)=="table" then
		for i=1,HOTBAR_SLOTS do
			local b=hb[i]
			if b then
				local slotNum = tonumber(b.Name:match("^HB(%d+)$")) or i
				b:SetAttribute("HotbarSlot", slotNum)
				b.TextXAlignment=Enum.TextXAlignment.Center; b.TextYAlignment=Enum.TextYAlignment.Top
				local uuid=hotbarSlotUuid(hotbar, i)
				local it=(type(uuid)=="string" and uuid~="") and inv[uuid] or nil
				if hsi then hsi[i]=it end
				if it then
					local nm=itemDisplayName(it); local cnt=itemCount(it)
					b.Text=cnt and string.format("%d\n%s (x%d)",i,nm,cnt) or string.format("%d\n%s",i,nm)
					b.TextColor3=Types.GetRarityColor(it.rarity)
					if it.maxDurability then
						local dl=b:FindFirstChild("DurLabel")
						if not dl then
							dl=Instance.new("TextLabel",b); dl.Name="DurLabel"
							dl.Size=UDim2.new(1,0,0,11); dl.Position=UDim2.new(0,0,1,-12)
							dl.BackgroundTransparency=1; dl.Font=Enum.Font.GothamBold
							dl.TextSize=7; dl.TextXAlignment=Enum.TextXAlignment.Center; dl.ZIndex=6
						end
						local text,color,ratio=durabilityTextAndColor(it)
						dl.Text=text; dl.TextColor3=color
						b.BackgroundColor3=(it.broken or ratio<0.3) and Color3.fromRGB(40,18,18)
							or (ratio<0.5 and Color3.fromRGB(38,30,14) or Color3.fromRGB(36,28,28))
					end
				else
					b.Text=string.format("%d\n(empty)",i)
					b.TextColor3=Color3.new(1,1,1); b.BackgroundColor3=Color3.fromRGB(36,28,28)
					local dlOld=b:FindFirstChild("DurLabel"); if dlOld then dlOld:Destroy() end
				end
			end
		end
	end
end

local BUFF_PANEL_LABELS={WalkSpeedPct="Move speed",LuckPct="Luck (drops)"}
local function formatBuffRemaining(sec)
	sec=tonumber(sec) or 0
	if sec<=0 then return "0s" end
	if sec>=3600 then return string.format("%.1fh",sec/3600)
	elseif sec>=60 then return string.format("%dm %ds",math.floor(sec/60),math.floor(sec%60)) end
	return string.format("%.0fs",sec)
end

function DungeonMenuUI.setActiveBuffs(refs,rows)
	local listFrame=refs and refs.activeBuffsList
	if not listFrame then return end
	for _,ch in ipairs(listFrame:GetChildren()) do
		if not ch:IsA("UIListLayout") and not ch:IsA("UIPadding") then ch:Destroy() end
	end
	if type(rows)~="table" or #rows==0 then return end
	local sorted={}; for i,v in ipairs(rows) do sorted[i]=v end
	table.sort(sorted,function(a,b) return (tonumber(a.remaining) or 0)>(tonumber(b.remaining) or 0) end)
	local order=1
	for _,row in ipairs(sorted) do
		if type(row)=="table" and type(row.type)=="string" then
			local label=BUFF_PANEL_LABELS[row.type] or row.type
			local amt=math.floor(tonumber(row.amount) or 0)
			local rem=formatBuffRemaining(row.remaining)
			local line=(row.type=="WalkSpeedPct" or row.type=="LuckPct")
				and string.format("%s  +%d%%  \xe2\x80\xa2  %s left",label,amt,rem)
				or string.format("%s  %+d  \xe2\x80\xa2  %s left",label,amt,rem)
			local tl=Instance.new("TextLabel")
			tl.BackgroundTransparency=1; tl.Size=UDim2.new(1,-4,0,18)
			tl.Font=Enum.Font.GothamMedium; tl.TextSize=12
			tl.TextColor3=Color3.fromRGB(255,215,100)
			tl.TextXAlignment=Enum.TextXAlignment.Left; tl.TextWrapped=true
			tl.Text=line; tl.ZIndex=6; tl.LayoutOrder=order; order+=1
			tl.Parent=listFrame
		end
	end
end

function DungeonMenuUI.updateDayNight(refs, state)
	if type(state) ~= "table" or type(refs) ~= "table" then return end
	local dn = refs.dayNightRefs
	if not dn then return end
	local phase = state.phase == "Night" and "Night" or "Day"
	local clockTime = tonumber(state.clockTime) or 12
	local remaining = tonumber(state.phaseRemaining) or 0
	local nextPhase = phase == "Day" and "Night" or "Day"
	if dn.phaseLabel then
		dn.phaseLabel.Text = string.upper(phase)
		dn.phaseLabel.TextColor3 = phase == "Day"
			and Color3.fromRGB(255, 210, 90)
			or Color3.fromRGB(140, 170, 255)
	end
	if dn.timeLabel then
		dn.timeLabel.Text = DayNightConfig.formatClockTime(clockTime)
	end
	if dn.remainingLabel then
		if state.devOverride then
			dn.remainingLabel.Text = "Dev override (paused)"
		else
			dn.remainingLabel.Text = string.format("%s in %s", nextPhase, DayNightConfig.formatRemaining(remaining))
		end
	end
end

return DungeonMenuUI