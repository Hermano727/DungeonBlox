--[[
	ShopClientBase
	Shared UI factory for NPC shop windows.
	Provides the standard dark-wood window frame, card grid, sidebar tabs, and
	open/close lifecycle. Specific clients (DungeoneerClient, AnimalTrainerClient)
	require this module and configure it — they never share state with each other.

	API:
	  local shop = ShopClientBase.create(config)
	  shop.open(npcId)   -- show the window and populate it
	  shop.close()       -- hide the window, release cursor

	config fields:
	  title      string            Header pill text ("DUNGEONEER")
	  tabs       {string}|nil      Sidebar tab names; nil = no sidebar
	  firstTab   string|nil        Tab to open first (defaults to tabs[1])
	  buildContent  function(scroll, tab, npcId, helpers)
	                               Called each time the view needs to render.
	                               Populate `scroll` with Frames; tab is the
	                               active tab name (or nil when no tabs).
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local MenuMouse       = require(ReplicatedStorage:WaitForChild("CursorUtils"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local profilePush = ReplicatedStorage:WaitForChild("DungeonProfilePush", 10)
local gameEvents  = ReplicatedStorage:WaitForChild("GameEvents", 10)

-- Shared palette (all shop windows use the same dark-wood theme)
local ShopClientBase = {}

-- Shared palette (all shop windows use the same dark-wood theme)
local T = {
	Panel        = Color3.fromRGB(100, 55, 38),
	PanelDark    = Color3.fromRGB(68,  34, 20),
	PanelInner   = Color3.fromRGB(84,  47, 30),
	SidebarAct   = Color3.fromRGB(68, 120, 68),
	SidebarInact = Color3.fromRGB(118, 70, 48),
	CardBg       = Color3.fromRGB(76,  42, 26),
	CardBorder   = Color3.fromRGB(48,  26, 14),
	TextPrimary  = Color3.fromRGB(255, 240, 218),
	TextSecond   = Color3.fromRGB(198, 176, 144),
	Gold         = Color3.fromRGB(255, 215, 100),
	Buy          = Color3.fromRGB(42,  88, 145),
	Trade        = Color3.fromRGB(42, 110, 55),
	CloseBtn     = Color3.fromRGB(185, 62, 52),
	StatusOk     = Color3.fromRGB(140, 255, 140),
	StatusErr    = Color3.fromRGB(255, 120, 120),
}
ShopClientBase._T = T

-- ─── Small UI helpers (available to buildContent via helpers table) ────────────
local function cr(inst, r)
	Instance.new("UICorner", inst).CornerRadius = UDim.new(0, r or 8)
end
local function sk(inst, t, c)
	local s = Instance.new("UIStroke", inst); s.Thickness = t or 1.5; s.Color = c or T.CardBorder
end
local function lbl(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextColor3    = props.color or T.TextPrimary
	l.Font          = props.bold  and Enum.Font.GothamBold or Enum.Font.GothamMedium
	l.TextSize      = props.size  or 13
	l.TextXAlignment= props.xa    or Enum.TextXAlignment.Left
	l.TextYAlignment= props.ya    or Enum.TextYAlignment.Top
	l.TextWrapped   = props.wrap  or false
	l.Text          = props.text  or ""
	l.Size          = props.sz    or UDim2.new(1, 0, 0, 20)
	l.Position      = props.pos   or UDim2.new(0, 0, 0, 0)
	l.ZIndex        = props.z     or 5
	l.Parent        = parent
	return l
end
local function getIcon(itemId)
	local def = itemId and ItemDefinitions.Get(itemId)
	return (def and type(def.Icon) == "string" and def.Icon ~= "") and def.Icon or ""
end
local function getDesc(itemId)
	local def = itemId and ItemDefinitions.Get(itemId)
	return (def and type(def.Description) == "string") and def.Description or ""
end
local function fmtPrice(price, currency)
	if currency == "Coins" then return tostring(price) .. " Coins" end
	local def = ItemDefinitions.Get(currency)
	return tostring(price) .. " " .. (def and def.DisplayName or currency)
end

local HELPERS = {
	cr = cr, sk = sk, lbl = lbl,
	getIcon = getIcon, getDesc = getDesc, fmtPrice = fmtPrice,
	T = T,
}

-- ─── Standard item card (2-column grid cell) ──────────────────────────────────
-- Exposed so clients can call it directly without re-implementing.
function ShopClientBase.buildCard(scroll, entry, lo, npcId, npcRequest, cachedCoinsRef, onSuccess)
	local itemId   = entry.ItemId
	local label    = entry.Label or itemId
	local price    = math.max(0, math.floor(tonumber(entry.Price) or 0))
	local currency = entry.Currency or "Coins"
	local isCoins  = (currency == "Coins")
	local priceStr = fmtPrice(price, currency)
	local desc     = getDesc(itemId)
	local icon     = getIcon(itemId)

	local card = Instance.new("Frame")
	card.BackgroundColor3 = T.CardBg; card.BorderSizePixel = 0
	card.LayoutOrder = lo; card.ZIndex = 5; card.Parent = scroll
	cr(card, 10); sk(card, 1.5, T.CardBorder)

	-- Icon
	local ibox = Instance.new("Frame")
	ibox.Size = UDim2.fromOffset(118, 118); ibox.Position = UDim2.fromOffset(8, 12)
	ibox.BackgroundColor3 = T.PanelDark; ibox.BorderSizePixel = 0; ibox.ZIndex = 6; ibox.Parent = card
	cr(ibox, 8); sk(ibox, 1, T.PanelDark)
	local iimg = Instance.new("ImageLabel")
	iimg.Size = UDim2.fromOffset(100, 100); iimg.AnchorPoint = Vector2.new(0.5, 0.5)
	iimg.Position = UDim2.fromScale(0.5, 0.5); iimg.BackgroundTransparency = 1
	iimg.Image = icon; iimg.ScaleType = Enum.ScaleType.Fit; iimg.ZIndex = 7; iimg.Parent = ibox

	-- Hover price overlay
	local overlay = Instance.new("Frame")
	overlay.Size = UDim2.fromScale(1, 1); overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.3; overlay.BorderSizePixel = 0
	overlay.ZIndex = 8; overlay.Visible = false; overlay.Parent = ibox; cr(overlay, 8)
	lbl(overlay, {text=priceStr, color=T.Gold, bold=true, size=13,
		xa=Enum.TextXAlignment.Center, ya=Enum.TextYAlignment.Center,
		sz=UDim2.fromScale(1,1), wrap=true, z=9})
	local hz = Instance.new("TextButton")
	hz.Size=UDim2.fromScale(1,1); hz.BackgroundTransparency=1; hz.Text=""; hz.ZIndex=10; hz.Parent=ibox
	hz.MouseEnter:Connect(function() overlay.Visible = true  end)
	hz.MouseLeave:Connect(function() overlay.Visible = false end)
	hz.Activated:Connect(function()  overlay.Visible = false end)

	-- Text
	local tf = Instance.new("Frame")
	tf.Size = UDim2.new(1, -140, 1, -12); tf.Position = UDim2.fromOffset(132, 8)
	tf.BackgroundTransparency = 1; tf.ZIndex = 6; tf.Parent = card
	lbl(tf, {text=label, color=T.TextPrimary, bold=true, size=15, wrap=true,
		sz=UDim2.new(1,0,0,26), pos=UDim2.fromOffset(0,0), z=6})
	lbl(tf, {text=desc~="" and desc or ("Cost: "..priceStr), color=T.TextSecond, size=11, wrap=true,
		sz=UDim2.new(1,0,1,-56), pos=UDim2.fromOffset(0,28), z=6})
	lbl(tf, {text="Price: "..priceStr, color=T.Gold, size=12,
		sz=UDim2.new(1,-108,0,20), pos=UDim2.new(0,0,1,-26), z=6})

	local btn = Instance.new("TextButton")
	btn.Size=UDim2.fromOffset(96,28); btn.AnchorPoint=Vector2.new(1,1)
	btn.Position=UDim2.new(1,0,1,-2)
	btn.BackgroundColor3 = isCoins and T.Buy or T.Trade
	btn.Font=Enum.Font.GothamBold; btn.TextSize=13
	btn.TextColor3=Color3.new(1,1,1); btn.Text=isCoins and "Buy" or "Trade"
	btn.ZIndex=7; btn.Parent=tf; cr(btn,6)
	btn.Activated:Connect(function()
		if not btn.Active then return end; btn.Active=false; btn.Text="..."
		if npcRequest then
			local ok,res=pcall(function()
				return npcRequest:InvokeServer({npcId=npcId,action="BuyItem",itemId=itemId,qty=1})
			end)
			if ok and res and res.ok then
				if cachedCoinsRef then cachedCoinsRef.value = res.wallet or cachedCoinsRef.value end
				if onSuccess then onSuccess(label, res) end
			end
		end
		btn.Text = isCoins and "Buy" or "Trade"; btn.Active=true
	end)
	return card
end

-- ─── Main factory ─────────────────────────────────────────────────────────────
function ShopClientBase.create(config)
	local title      = config.title or "SHOP"
	local tabs       = config.tabs   -- array or nil
	local firstTab   = config.firstTab or (tabs and tabs[1])
	local buildContent = config.buildContent

	-- Per-instance state
	local activeTab   = firstTab
	local currentNpcId= ""
	local cachedCoins = 0
	local cursorHeld  = false
	local tabBtns     = {}

	-- ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = config.guiName or (title:gsub(" ","").."UI")
	gui.ResetOnSpawn=false; gui.IgnoreGuiInset=true; gui.DisplayOrder=160
	gui.Enabled=false; gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
	gui.Parent=playerGui

	local dimBtn=Instance.new("TextButton")
	dimBtn.Size=UDim2.fromScale(1,1); dimBtn.BackgroundColor3=Color3.new(0,0,0)
	dimBtn.BackgroundTransparency=0.5; dimBtn.BorderSizePixel=0
	dimBtn.Text=""; dimBtn.AutoButtonColor=false; dimBtn.ZIndex=1; dimBtn.Parent=gui

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
	lbl(hdr,{text=title,bold=true,size=22,xa=Enum.TextXAlignment.Center,
		ya=Enum.TextYAlignment.Center,sz=UDim2.fromScale(1,1),z=4})

	-- Panel
	local panel=Instance.new("Frame")
	panel.AnchorPoint=Vector2.new(0.5,0); panel.Position=UDim2.new(0.5,0,0,44)
	panel.Size=UDim2.fromOffset(1000,556); panel.BackgroundColor3=T.Panel
	panel.BorderSizePixel=0; panel.ZIndex=2; panel.Parent=root
	cr(panel,12); sk(panel,2,T.PanelDark)

	local closeBtn=Instance.new("TextButton")
	closeBtn.Size=UDim2.fromOffset(32,32); closeBtn.AnchorPoint=Vector2.new(1,0)
	closeBtn.Position=UDim2.new(1,-8,0,8); closeBtn.BackgroundColor3=T.CloseBtn
	closeBtn.Font=Enum.Font.GothamBold; closeBtn.TextSize=16
	closeBtn.TextColor3=Color3.new(1,1,1); closeBtn.Text="X"
	closeBtn.ZIndex=6; closeBtn.Parent=panel; cr(closeBtn,6)

	local walletLbl=lbl(panel,{text="Wallet: 0 Coins",color=T.Gold,bold=true,size=15,
		sz=UDim2.fromOffset(240,26),pos=UDim2.fromOffset(12,10),z=4})
	local statusLbl=lbl(panel,{text="",color=T.StatusOk,size=12,wrap=true,
		sz=UDim2.new(1,-280,0,22),pos=UDim2.fromOffset(12,38),z=4})

	local function updateWallet()
		walletLbl.Text = string.format("Wallet: %d Coins", cachedCoins)
	end
	local function flashStatus(text, isErr)
		statusLbl.Text = text
		statusLbl.TextColor3 = isErr and T.StatusErr or T.StatusOk
		task.delay(3, function() if statusLbl.Text==text then statusLbl.Text="" end end)
	end

	-- Optional sidebar (only when tabs are provided)
	local contentLeft = 8
	local contentWidth = 0  -- filled below

	if tabs and #tabs > 0 then
		local sidebar=Instance.new("Frame")
		sidebar.Size=UDim2.fromOffset(160, 10+#tabs*58)
		sidebar.Position=UDim2.fromOffset(8,66)
		sidebar.BackgroundColor3=T.PanelInner; sidebar.BorderSizePixel=0
		sidebar.ZIndex=3; sidebar.Parent=panel; cr(sidebar,10)
		for i,tabName in ipairs(tabs) do
			local b=Instance.new("TextButton")
			b.Size=UDim2.new(1,-12,0,52); b.Position=UDim2.fromOffset(6,6+(i-1)*58)
			b.BackgroundColor3=T.SidebarInact; b.BorderSizePixel=0
			b.Font=Enum.Font.GothamBold; b.TextSize=16; b.TextColor3=T.TextPrimary
			b.Text=tabName; b.ZIndex=4; b.AutoButtonColor=false; b.Parent=sidebar; cr(b,8)
			tabBtns[tabName]=b
		end
		contentLeft = 176
	else
		contentLeft = 8
	end
	contentWidth = 1000 - contentLeft - 8  -- not used directly; contentArea uses fill

	-- Content area
	local contentArea=Instance.new("Frame")
	contentArea.Size=UDim2.new(1,-contentLeft-8,1,-74)
	contentArea.Position=UDim2.fromOffset(contentLeft,66)
	contentArea.BackgroundColor3=T.PanelInner; contentArea.BorderSizePixel=0
	contentArea.ZIndex=3; contentArea.Parent=panel; cr(contentArea,10)

	-- Item scroll inside content area
	local scroll=Instance.new("ScrollingFrame")
	scroll.Size=UDim2.new(1,-4,1,-4); scroll.Position=UDim2.fromOffset(2,2)
	scroll.BackgroundTransparency=1; scroll.BorderSizePixel=0
	scroll.ScrollBarThickness=6; scroll.ScrollBarImageColor3=T.CardBorder
	scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y; scroll.CanvasSize=UDim2.new()
	scroll.ScrollingDirection=Enum.ScrollingDirection.Y
	scroll.ZIndex=4; scroll.Parent=contentArea

	local grid=Instance.new("UIGridLayout",scroll)
	grid.CellSize=UDim2.fromOffset(376,142); grid.CellPadding=UDim2.fromOffset(8,8)
	grid.SortOrder=Enum.SortOrder.LayoutOrder; grid.HorizontalAlignment=Enum.HorizontalAlignment.Center
	local gridPad=Instance.new("UIPadding",scroll)
	gridPad.PaddingTop=UDim.new(0,8); gridPad.PaddingLeft=UDim.new(0,6)
	gridPad.PaddingRight=UDim.new(0,6); gridPad.PaddingBottom=UDim.new(0,8)

	local emptyLbl=lbl(scroll,{text="Nothing here.",color=T.TextSecond,size=14,
		xa=Enum.TextXAlignment.Center,sz=UDim2.new(1,0,0,50),pos=UDim2.fromOffset(0,10),z=5})
	emptyLbl.Visible=false

	-- Helpers bundle passed into buildContent
	local coinsRef = { value = 0 }
	local extHelpers = {}
	for k,v in pairs(HELPERS) do extHelpers[k]=v end
	extHelpers.flashStatus = flashStatus
	extHelpers.updateWallet = updateWallet
	extHelpers.coinsRef     = coinsRef
	extHelpers.emptyLbl     = emptyLbl

	-- Rebuild
	local function applyTabStyles()
		for t,b in pairs(tabBtns) do
			b.BackgroundColor3=(t==activeTab) and T.SidebarAct or T.SidebarInact
		end
	end

	local function rebuild()
		for _,ch in ipairs(scroll:GetChildren()) do
			if ch:IsA("Frame") then ch:Destroy() end
		end
		emptyLbl.Visible=false
		scroll.CanvasPosition=Vector2.new(0,0)
		if buildContent then
			coinsRef.value = cachedCoins
			buildContent(scroll, activeTab, currentNpcId, extHelpers)
		end
	end

	-- Tab wiring
	for tabName,btn in pairs(tabBtns) do
		local n=tabName
		btn.Activated:Connect(function()
			activeTab=n; applyTabStyles(); rebuild()
		end)
	end

	-- Close
	local function closeShop()
		gui.Enabled=false
		if cursorHeld then MenuMouse.release(); cursorHeld=false end
		statusLbl.Text=""
		for _,ch in ipairs(scroll:GetChildren()) do if ch:IsA("Frame") then ch:Destroy() end end
	end
	closeBtn.Activated:Connect(closeShop)
	dimBtn.Activated:Connect(closeShop)
	UserInputService.InputBegan:Connect(function(inp,proc)
		if proc then return end
		if inp.KeyCode==Enum.KeyCode.Escape and gui.Enabled then closeShop() end
	end)
	player.CharacterAdded:Connect(function()
		if cursorHeld then MenuMouse.release(); cursorHeld=false end
		gui.Enabled=false
	end)

	-- Profile push
	if profilePush then
		profilePush.OnClientEvent:Connect(function(payload)
			if payload and payload.profile and payload.profile.currencies then
				cachedCoins=math.floor(tonumber(payload.profile.currencies.Coins) or 0)
				coinsRef.value=cachedCoins
				if gui.Enabled then updateWallet() end
			end
		end)
	end

	-- Public API
	local shop={}
	function shop.open(npcId)
		currentNpcId=npcId or ""
		activeTab=firstTab
		applyTabStyles(); updateWallet()
		if not cursorHeld then MenuMouse.acquire(); cursorHeld=true end
		gui.Enabled=true; rebuild()
	end
	function shop.close() closeShop() end
	return shop
end

return ShopClientBase
