local Keys = require(game:GetService("ReplicatedStorage"):WaitForChild("KeybindConfig"))
--[[
	MerchantClient
	SELF-CONTAINED merchant shop UI. No routing, no NPC detection, no Auctioneer logic.
	API:  MerchantClient.open(npcId)  /  MerchantClient.close()

	ARCHITECTURE NOTE:
	  To change merchant behaviour -> edit THIS file only.
	  To add a new NPC type       -> edit MerchantShopClient (the router) only.
	  These two files must never share UI state.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local UserInputService  = game:GetService("UserInputService")

local MenuMouse       = require(ReplicatedStorage:WaitForChild("CursorUtils"))
local NPCRegistry     = require(ReplicatedStorage:WaitForChild("NPCRegistry"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local DungeonMenuNet  = require(script.Parent:WaitForChild("DungeonMenuNet"))
local ShopClientBase  = require(script.Parent:WaitForChild("ShopClientBase"))

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gameEvents  = ReplicatedStorage:WaitForChild("GameEvents", 10)
local npcRequest  = gameEvents and gameEvents:WaitForChild("NPCRequest", 10)
local profilePush = ReplicatedStorage:WaitForChild("DungeonProfilePush", 10)

-- State
local currentNpcId = ""
local cachedCoins  = 0
local lastSnapshot = nil
local cursorHeld   = false
local activeTab    = "Ores"
local activeTier   = 1
local tierDDOpen   = false
local rebuild      -- forward declaration

-- Palette: shares the same dark-wood theme as every other NPC shop window, defined
-- once in ShopClientBase so the two never drift apart. Merchant has two extra colors
-- (tier dropdown button, salvage button) other shops don't need.
local T = {}
for k, v in pairs(ShopClientBase._T) do T[k] = v end
T.TierBtn = Color3.fromRGB(68, 120, 68)
T.Salvage = Color3.fromRGB(108, 54, 26)

local RARITY_W  = { Common=1, Uncommon=2, Rare=3, Epic=4, Legendary=5 }
local SCRAP_AMT = { Common=4, Uncommon=8, Rare=12, Epic=16, Legendary=20 }

local ERR = {
	insufficient_funds = "Not enough coins or materials.",
	not_in_catalog     = "That item isn't available here.",
	no_profile         = "Profile not ready, try again.",
	throttled          = "Too fast, wait a moment.",
	remove_failed      = "Could not remove payment from your bags.",
	grant_failed       = "Could not add the item to your bags.",
	not_salvageable    = "Only unequipped weapons or armor can be salvaged.",
	equipped           = "Unequip that piece first.",
	in_raid            = "Cannot salvage during a dungeon run.",
	not_owned          = "Item not in your bags anymore.",
	bad_item_uuid      = "Could not identify that item. Try reopening the shop.",
	bad_uuid           = "Could not identify that item. Try reopening the shop.",
	salvage_failed     = "Salvage failed. Try again.",
	unknown_item       = "That item cannot be salvaged.",
	bad_scrap_item     = "Salvage reward unavailable.",
	action_not_allowed = "This shop cannot do that.",
	npc_not_found      = "Merchant unavailable. Step closer and reopen the shop.",
	too_far            = "You are too far from the merchant.",
	not_stackable      = "Could not add scrap to your bags.",
	merge_failed       = "Could not add scrap to your bags.",
	server_error       = "Salvage failed on the server. Try again.",
	bad_request        = "Invalid salvage request.",
	bad_npc            = "This merchant cannot salvage gear.",
}

-- Tiny helpers: identical to every other shop window, so reuse ShopClientBase's
-- copies instead of maintaining a third (MerchantShopClient/DungeoneerClient already
-- share these via ShopClientBase.create()'s `helpers` argument; MerchantClient
-- predates that factory and builds its own window, so it pulls the pure helpers
-- straight off ShopClientBase.Helpers instead).
local H = ShopClientBase.Helpers
local cr, sk, lbl = H.cr, H.sk, H.lbl
local getIcon, getDesc, fmtPrice = H.getIcon, H.getDesc, H.fmtPrice

-- ScreenGui
local gui=Instance.new("ScreenGui")
gui.Name="MerchantShopUI"; gui.ResetOnSpawn=false; gui.IgnoreGuiInset=true
gui.DisplayOrder=160; gui.Enabled=false; gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
gui.Parent=playerGui

local dimBtn=Instance.new("TextButton")
dimBtn.Size=UDim2.fromScale(1,1); dimBtn.BackgroundColor3=Color3.new(0,0,0)
dimBtn.BackgroundTransparency=0.5; dimBtn.BorderSizePixel=0
dimBtn.Text=""; dimBtn.AutoButtonColor=false; dimBtn.ZIndex=1; dimBtn.Parent=gui

-- Root
local root=Instance.new("Frame")
root.AnchorPoint=Vector2.new(0.5,0.5); root.Position=UDim2.fromScale(0.5,0.5)
root.Size=UDim2.fromOffset(1000,600); root.BackgroundTransparency=1
root.ZIndex=2; root.Parent=gui

-- Header pill
local hdr=Instance.new("Frame")
hdr.AnchorPoint=Vector2.new(0.5,0); hdr.Position=UDim2.new(0.5,0,0,0)
hdr.Size=UDim2.fromOffset(340,52); hdr.BackgroundColor3=T.Panel
hdr.BorderSizePixel=0; hdr.ZIndex=3; hdr.Parent=root
cr(hdr,10); sk(hdr,2,T.PanelDark)
lbl(hdr,{text="MERCHANT",bold=true,size=22,xa=Enum.TextXAlignment.Center,ya=Enum.TextYAlignment.Center,sz=UDim2.fromScale(1,1),z=4})

-- Main panel
local panel=Instance.new("Frame")
panel.AnchorPoint=Vector2.new(0.5,0); panel.Position=UDim2.new(0.5,0,0,44)
panel.Size=UDim2.fromOffset(1000,556); panel.BackgroundColor3=T.Panel
panel.BorderSizePixel=0; panel.ZIndex=2; panel.Parent=root
cr(panel,12); sk(panel,2,T.PanelDark)

local closeBtn=Instance.new("TextButton")
closeBtn.Size=UDim2.fromOffset(32,32); closeBtn.AnchorPoint=Vector2.new(1,0)
closeBtn.Position=UDim2.new(1,-8,0,8); closeBtn.BackgroundColor3=T.CloseBtn
closeBtn.FontFace=UIFonts.BodyBold; closeBtn.TextSize=16
closeBtn.TextColor3=Color3.new(1,1,1); closeBtn.Text="X"; closeBtn.ZIndex=6; closeBtn.Parent=panel
cr(closeBtn,6)

local walletLbl=lbl(panel,{text="Wallet: 0 Coins",color=T.Gold,bold=true,size=15,sz=UDim2.fromOffset(240,26),pos=UDim2.fromOffset(12,10),z=4})
local statusLbl=lbl(panel,{text="",color=T.StatusOk,size=12,wrap=true,sz=UDim2.new(1,-280,0,22),pos=UDim2.fromOffset(12,38),z=4})
lbl(panel,{text="Click item image to buy",color=T.TextSecond,size=12,
	xa=Enum.TextXAlignment.Center,ya=Enum.TextYAlignment.Top,
	sz=UDim2.new(1,-96,0,18),pos=UDim2.fromOffset(48,10),z=4})

-- Sidebar
local sidebar=Instance.new("Frame")
sidebar.Size=UDim2.fromOffset(160,480); sidebar.Position=UDim2.fromOffset(8,66)
sidebar.BackgroundColor3=T.PanelInner; sidebar.BorderSizePixel=0; sidebar.ZIndex=3; sidebar.Parent=panel
cr(sidebar,10)

local TABS = {"Ores","Scrap","Salvage","Potions"}
local tabBtns={}
for i,tabName in ipairs(TABS) do
	local b=Instance.new("TextButton")
	b.Size=UDim2.new(1,-12,0,52); b.Position=UDim2.fromOffset(6,6+(i-1)*58)
	b.BackgroundColor3=T.SidebarInact; b.BorderSizePixel=0
	b.FontFace=UIFonts.BodyBold; b.TextSize=16; b.TextColor3=T.TextPrimary
	b.Text=tabName; b.ZIndex=4; b.AutoButtonColor=false; b.Parent=sidebar
	cr(b,8); tabBtns[tabName]=b
end

-- Content area
local contentArea=Instance.new("Frame")
contentArea.Size=UDim2.new(1,-180,1,-74); contentArea.Position=UDim2.fromOffset(176,66)
contentArea.BackgroundColor3=T.PanelInner; contentArea.BorderSizePixel=0
contentArea.ZIndex=3; contentArea.Parent=panel; cr(contentArea,10)

-- Tier dropdown button
local tierBtn=Instance.new("TextButton")
tierBtn.Size=UDim2.fromOffset(124,32); tierBtn.Position=UDim2.fromOffset(10,8)
tierBtn.BackgroundColor3=T.TierBtn; tierBtn.BorderSizePixel=0
tierBtn.FontFace=UIFonts.BodyBold; tierBtn.TextSize=14
tierBtn.TextColor3=Color3.new(1,1,1); tierBtn.Text="Tier 1"
tierBtn.ZIndex=6; tierBtn.Visible=false; tierBtn.Parent=contentArea; cr(tierBtn,6)

local tierDD=Instance.new("Frame")
tierDD.Size=UDim2.fromOffset(124,5*36+8); tierDD.Position=UDim2.fromOffset(10,44)
tierDD.BackgroundColor3=T.PanelDark; tierDD.BorderSizePixel=0
tierDD.ZIndex=12; tierDD.Visible=false; tierDD.Parent=contentArea
cr(tierDD,6); sk(tierDD,1,T.CardBorder)
for i=1,5 do
	local tb=Instance.new("TextButton")
	tb.Size=UDim2.new(1,-8,0,32); tb.Position=UDim2.fromOffset(4,4+(i-1)*36)
	tb.BackgroundColor3=Color3.fromRGB(60,38,22); tb.BorderSizePixel=0
	tb.FontFace=UIFonts.BodyMedium; tb.TextSize=14
	tb.TextColor3=T.TextPrimary; tb.Text="Tier "..i; tb.ZIndex=13; tb.Parent=tierDD; cr(tb,5)
	local ti=i
	tb.Activated:Connect(function()
		activeTier=ti; tierBtn.Text="Tier "..ti
		tierDD.Visible=false; tierDDOpen=false
		rebuild()
	end)
end

-- Item scroll grid (Ores / Scrap / Potions)
local itemScroll=Instance.new("ScrollingFrame")
itemScroll.Size=UDim2.new(1,-4,1,-4); itemScroll.Position=UDim2.fromOffset(2,2)
itemScroll.BackgroundTransparency=1; itemScroll.BorderSizePixel=0
itemScroll.ScrollBarThickness=6; itemScroll.ScrollBarImageColor3=T.CardBorder
itemScroll.AutomaticCanvasSize=Enum.AutomaticSize.Y; itemScroll.CanvasSize=UDim2.new()
itemScroll.ScrollingDirection=Enum.ScrollingDirection.Y
itemScroll.ZIndex=4; itemScroll.Parent=contentArea
local itemGrid=Instance.new("UIGridLayout",itemScroll)
itemGrid.CellSize=UDim2.fromOffset(376,142); itemGrid.CellPadding=UDim2.fromOffset(8,8)
itemGrid.SortOrder=Enum.SortOrder.LayoutOrder; itemGrid.HorizontalAlignment=Enum.HorizontalAlignment.Center
local itemPad=Instance.new("UIPadding",itemScroll)
itemPad.PaddingTop=UDim.new(0,8); itemPad.PaddingLeft=UDim.new(0,6)
itemPad.PaddingRight=UDim.new(0,6); itemPad.PaddingBottom=UDim.new(0,8)

local emptyLbl=lbl(itemScroll,{text="Nothing here.",color=T.TextSecond,size=14,
	xa=Enum.TextXAlignment.Center,sz=UDim2.new(1,0,0,50),pos=UDim2.fromOffset(0,10),z=5})
emptyLbl.Visible=false

-- Salvage scroll (list view)
local salvScroll=Instance.new("ScrollingFrame")
salvScroll.Size=UDim2.new(1,-4,1,-4); salvScroll.Position=UDim2.fromOffset(2,2)
salvScroll.BackgroundTransparency=1; salvScroll.BorderSizePixel=0
salvScroll.ScrollBarThickness=6; salvScroll.ScrollBarImageColor3=T.CardBorder
salvScroll.AutomaticCanvasSize=Enum.AutomaticSize.Y; salvScroll.CanvasSize=UDim2.new()
salvScroll.ScrollingDirection=Enum.ScrollingDirection.Y
salvScroll.Visible=false; salvScroll.ZIndex=4; salvScroll.Parent=contentArea
local salvLay=Instance.new("UIListLayout",salvScroll)
salvLay.Padding=UDim.new(0,6); salvLay.SortOrder=Enum.SortOrder.LayoutOrder
local salvPad=Instance.new("UIPadding",salvScroll)
salvPad.PaddingTop=UDim.new(0,6); salvPad.PaddingLeft=UDim.new(0,6)
salvPad.PaddingRight=UDim.new(0,6); salvPad.PaddingBottom=UDim.new(0,6)

-- helpers
local function flashStatus(text,isErr)
	statusLbl.Text=text; statusLbl.TextColor3=isErr and T.StatusErr or T.StatusOk
	task.delay(3,function() if statusLbl.Text==text then statusLbl.Text="" end end)
end
local function updateWallet()
	walletLbl.Text=string.format("Wallet: %d Coins",cachedCoins)
end
local function applyTabStyles()
	for t,b in pairs(tabBtns) do
		b.BackgroundColor3=(t==activeTab) and T.SidebarAct or T.SidebarInact
	end
end
local function clearItems()
	for _,ch in ipairs(itemScroll:GetChildren()) do if ch:IsA("Frame") then ch:Destroy() end end
	emptyLbl.Visible=false
end
local function clearSalvage()
	for _,ch in ipairs(salvScroll:GetChildren()) do
		if ch:IsA("Frame") or ch:IsA("TextLabel") then ch:Destroy() end
	end
end

-- Item card (2-column grid cell)
local function buildItemCard(entry,lo)
	local itemId   = entry.ItemId
	local label    = entry.Label or itemId
	local price    = math.max(0,math.floor(tonumber(entry.Price) or 0))
	local currency = entry.Currency or "Coins"
	local isCoins  = (currency=="Coins")
	local priceStr = fmtPrice(price,currency)
	local desc     = getDesc(itemId)
	local icon     = getIcon(itemId)

	local card=Instance.new("Frame")
	card.BackgroundColor3=T.CardBg; card.BorderSizePixel=0
	card.LayoutOrder=lo; card.ZIndex=5; card.Parent=itemScroll
	cr(card,10); sk(card,1.5,T.CardBorder)

	-- Icon box
	local iconBox=Instance.new("Frame")
	iconBox.Size=UDim2.fromOffset(118,118); iconBox.Position=UDim2.fromOffset(8,12)
	iconBox.BackgroundColor3=T.PanelDark; iconBox.BorderSizePixel=0; iconBox.ZIndex=6; iconBox.Parent=card
	cr(iconBox,8); sk(iconBox,1,T.PanelDark)

	local iconImg=Instance.new("ImageLabel")
	iconImg.Size=UDim2.fromOffset(100,100); iconImg.AnchorPoint=Vector2.new(0.5,0.5)
	iconImg.Position=UDim2.fromScale(0.5,0.5); iconImg.BackgroundTransparency=1
	iconImg.Image=icon; iconImg.ScaleType=Enum.ScaleType.Fit; iconImg.ZIndex=7; iconImg.Parent=iconBox

	-- Price overlay (appears on hover)
	local overlay=Instance.new("Frame")
	overlay.Size=UDim2.fromScale(1,1); overlay.BackgroundColor3=Color3.new(0,0,0)
	overlay.BackgroundTransparency=0.3; overlay.BorderSizePixel=0
	overlay.ZIndex=8; overlay.Visible=false; overlay.Parent=iconBox; cr(overlay,8)
	lbl(overlay,{text=priceStr,color=T.Gold,bold=true,size=13,
		xa=Enum.TextXAlignment.Center,ya=Enum.TextYAlignment.Center,
		sz=UDim2.fromScale(1,1),wrap=true,z=9})

	local hzone=Instance.new("TextButton")
	hzone.Size=UDim2.fromScale(1,1); hzone.BackgroundTransparency=1
	hzone.Text=""; hzone.ZIndex=10; hzone.Parent=iconBox
	hzone.MouseEnter:Connect(function() overlay.Visible=true  end)
	hzone.MouseLeave:Connect(function() overlay.Visible=false end)

	-- Text area
	local tf=Instance.new("Frame")
	tf.Size=UDim2.new(1,-140,1,-12); tf.Position=UDim2.fromOffset(132,8)
	tf.BackgroundTransparency=1; tf.ZIndex=6; tf.Parent=card

	lbl(tf,{text=label,color=T.TextPrimary,bold=true,size=15,wrap=true,
		sz=UDim2.new(1,0,0,26),pos=UDim2.fromOffset(0,0),z=6})
	lbl(tf,{text=desc,color=T.TextSecond,size=11,wrap=true,
		sz=UDim2.new(1,0,1,-32),pos=UDim2.fromOffset(0,28),z=6})

	local buying = false
	local function tryPurchase()
		if buying then return end
		buying = true
		overlay.Visible = true
		if npcRequest then
			local ok,res=pcall(function()
				return npcRequest:InvokeServer({npcId=currentNpcId,action="BuyItem",itemId=itemId,qty=1})
			end)
			if ok and res and res.ok then
				cachedCoins=res.wallet or cachedCoins; updateWallet()
				flashStatus("Purchased: "..label,false)
				-- Server-side grant already happened; force a fresh snapshot so the inventory
				-- UI actually reflects the new item instead of waiting on the next unrelated push.
				DungeonMenuNet.requestSync()
			else
				local ek=res and res.err
				flashStatus((type(ek)=="string" and (ERR[ek] or ("Failed: "..ek))) or "Error.",true)
			end
		end
		buying = false
		overlay.Visible = false
	end

	hzone.Activated:Connect(tryPurchase)
end

-- Salvage card (list view)
local function buildSalvageCard(entry,lo)
	local item = entry.item
	local itemUuid = entry.uuid
	if type(item) ~= "table" or type(itemUuid) ~= "string" or itemUuid == "" then return end
	local tier=tonumber(item.tier) or 1
	local scraps=SCRAP_AMT[item.rarity] or 4
	local icon=getIcon(item.itemId)
	local card=Instance.new("Frame")
	card.BackgroundColor3=T.CardBg; card.BorderSizePixel=0; card.Size=UDim2.new(1,-4,0,90)
	card.LayoutOrder=lo; card.ZIndex=5; card.Parent=salvScroll
	cr(card,10); sk(card,1.5,T.CardBorder)
	local ibox=Instance.new("Frame")
	ibox.Size=UDim2.fromOffset(72,72); ibox.Position=UDim2.fromOffset(8,9)
	ibox.BackgroundColor3=T.PanelDark; ibox.BorderSizePixel=0; ibox.ZIndex=6; ibox.Parent=card; cr(ibox,6)
	local iimg=Instance.new("ImageLabel")
	iimg.Size=UDim2.fromOffset(60,60); iimg.AnchorPoint=Vector2.new(0.5,0.5)
	iimg.Position=UDim2.fromScale(0.5,0.5); iimg.BackgroundTransparency=1
	iimg.Image=icon; iimg.ScaleType=Enum.ScaleType.Fit; iimg.ZIndex=7; iimg.Parent=ibox
	local tf=Instance.new("Frame")
	tf.Size=UDim2.new(1,-200,1,-10); tf.Position=UDim2.fromOffset(88,6)
	tf.BackgroundTransparency=1; tf.ZIndex=6; tf.Parent=card
	lbl(tf,{text=item.name or "Item",color=T.TextPrimary,bold=true,size=14,sz=UDim2.new(1,0,0,22)})
	lbl(tf,{text=string.format("%s T%d  -> %d T%dScrap",item.rarity or "?",tier,scraps,tier),
		color=T.TextSecond,size=12,sz=UDim2.new(1,0,0,20),pos=UDim2.fromOffset(0,24)})
	local btn=Instance.new("TextButton")
	btn.Size=UDim2.fromOffset(96,32); btn.AnchorPoint=Vector2.new(1,0.5)
	btn.Position=UDim2.new(1,-8,0.5,0); btn.BackgroundColor3=T.Salvage
	btn.FontFace=UIFonts.BodyBold; btn.TextSize=13
	btn.TextColor3=Color3.new(1,1,1); btn.Text="Salvage"; btn.ZIndex=6; btn.Parent=card; cr(btn,6)
	local capturedItem=item
	local capturedUuid=itemUuid
	btn.Activated:Connect(function()
		if not btn.Active then return end; btn.Active=false; btn.Text="..."
		if npcRequest then
			local ok,res=pcall(function()
				return npcRequest:InvokeServer({npcId=currentNpcId,action="SalvageGear",itemUuid=capturedUuid})
			end)
			if ok and res and res.ok then
				cachedCoins=res.wallet or cachedCoins; updateWallet()
				flashStatus("Salvaged: "..(capturedItem.name or "item"),false)
				rebuild()
			else
				local ek=res and res.err
				flashStatus((type(ek)=="string" and (ERR[ek] or ("Failed: "..ek))) or "Error.",true)
			end
		end
		btn.Text="Salvage"; btn.Active=true
	end)
end

-- rebuild: re-renders the current tab
rebuild = function()
	tierDD.Visible=false; tierDDOpen=false
	if activeTab=="Salvage" then
		itemScroll.Visible=false; salvScroll.Visible=true; tierBtn.Visible=false
		clearSalvage()
		if not (lastSnapshot and lastSnapshot.profile) then return end
		local prof=lastSnapshot.profile; local eqSet={}
		if type(prof.equipped)=="table" then for _,u in pairs(prof.equipped) do eqSet[u]=true end end
		local rows={}
		for key,item in pairs(prof.inventory or {}) do
			if type(item)=="table" and (item.type=="Weapon" or item.type=="Armor") then
				local uuid = (type(key)=="string" and key~="") and key or item.uuid
				if type(uuid)=="string" and uuid~="" and not eqSet[uuid] then
					table.insert(rows,{ uuid = uuid, item = item })
				end
			end
		end
		table.sort(rows,function(a,b)
			local ia=a.item; local ib=b.item
			local ra=RARITY_W[ia.rarity] or 0; local rb=RARITY_W[ib.rarity] or 0
			if ra~=rb then return ra>rb end; return (ia.name or "")<(ib.name or "")
		end)
		if #rows==0 then
			local e=Instance.new("TextLabel"); e.BackgroundTransparency=1
			e.Size=UDim2.new(1,0,0,50); e.FontFace=UIFonts.BodyMedium; e.TextSize=13
			e.TextColor3=T.TextSecond; e.TextWrapped=true
			e.Text="No unequipped weapons or armor in your bags."; e.Parent=salvScroll
			return
		end
		for i,row in ipairs(rows) do buildSalvageCard(row,i) end
		return
	end
	-- Ores / Scrap / Potions
	itemScroll.Visible=true; salvScroll.Visible=false; tierBtn.Visible=(activeTab=="Scrap")
	if activeTab=="Scrap" then
		itemPad.PaddingTop=UDim.new(0,50)
	else
		itemPad.PaddingTop=UDim.new(0,8)
	end
	clearItems()
	local reg=NPCRegistry.Get("Merchant")
	if not (reg and reg.ShopCatalog) then emptyLbl.Visible=true; return end
	local entries={}
	for _,entry in ipairs(reg.ShopCatalog) do
		if (entry.ShopTab or "Scrap")==activeTab then
			if activeTab=="Scrap" then
				if (entry.Tier or 1)==activeTier then table.insert(entries,entry) end
			else
				table.insert(entries,entry)
			end
		end
	end
	if #entries==0 then emptyLbl.Visible=true; return end
	for i,entry in ipairs(entries) do buildItemCard(entry,i) end
end

-- Tab + tier wiring
for tabName,btn in pairs(tabBtns) do
	local n=tabName
	btn.Activated:Connect(function()
		activeTab=n; applyTabStyles(); itemScroll.CanvasPosition=Vector2.new(0,0); rebuild()
	end)
end
tierBtn.Activated:Connect(function()
	tierDDOpen=not tierDDOpen; tierDD.Visible=tierDDOpen
end)

-- Close
local function closeMerchant()
	gui.Enabled=false
	if cursorHeld then MenuMouse.release(); cursorHeld=false end
	tierDD.Visible=false; tierDDOpen=false
	statusLbl.Text=""; clearItems(); clearSalvage()
end
closeBtn.Activated:Connect(closeMerchant)
dimBtn.Activated:Connect(closeMerchant)
UserInputService.InputBegan:Connect(function(inp,proc)
	if proc then return end
	if inp.KeyCode==Keys.CloseMenu and gui.Enabled then closeMerchant() end
end)
player.CharacterAdded:Connect(function()
	if cursorHeld then MenuMouse.release(); cursorHeld=false end
	gui.Enabled=false
end)

if profilePush then
	profilePush.OnClientEvent:Connect(function(payload)
		lastSnapshot=payload
		if payload and payload.profile and payload.profile.currencies then
			cachedCoins=math.floor(tonumber(payload.profile.currencies.Coins) or 0)
			if gui.Enabled then updateWallet() end
		end
	end)
end

local MerchantClient={}
function MerchantClient.open(npcId)
	currentNpcId=npcId or ""; activeTab="Ores"; activeTier=1
	tierBtn.Text="Tier 1"; applyTabStyles(); updateWallet()
	if not cursorHeld then MenuMouse.acquire(); cursorHeld=true end
	gui.Enabled=true; rebuild()
end
function MerchantClient.close() closeMerchant() end
return MerchantClient
