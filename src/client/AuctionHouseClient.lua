--[[
	AuctionHouseClient
	All Auction House UI: Browse, My Auctions, My Listing, Create Listing.
	Opened from MerchantShopClient when player interacts with Auctioneer NPC.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local MenuMouse       = require(ReplicatedStorage:WaitForChild("CursorUtils"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local Config          = require(ReplicatedStorage:WaitForChild("AuctionConfig"))

local rfGetListings   = ReplicatedStorage:WaitForChild("AuctionGetListings",   30)
local rfGetMyListings = ReplicatedStorage:WaitForChild("AuctionGetMyListings",  30)
local rfCreateListing = ReplicatedStorage:WaitForChild("AuctionCreateListing", 30)
local rfCancelListing = ReplicatedStorage:WaitForChild("AuctionCancelListing", 30)
local rfBuyListing    = ReplicatedStorage:WaitForChild("AuctionBuyListing",    30)

local profilePush = ReplicatedStorage:WaitForChild("DungeonProfilePush",         10)
local rfSync      = ReplicatedStorage:WaitForChild("DungeonProfileRequestSync",  10)

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------
local C = {
	BG       = Color3.fromRGB(16, 11, 11),
	PANEL    = Color3.fromRGB(30, 22, 22),
	PANEL2   = Color3.fromRGB(22, 16, 16),
	STROKE   = Color3.fromRGB(90, 70, 50),
	TEXT     = Color3.new(1, 1, 1),
	DIM      = Color3.fromRGB(200, 182, 160),
	GOLD     = Color3.fromRGB(255, 215, 100),
	BTN      = Color3.fromRGB(52, 38, 30),
	BTN_ACT  = Color3.fromRGB(75, 58, 42),
	BTN_GOLD = Color3.fromRGB(80, 62, 22),
	GREEN    = Color3.fromRGB(70, 205, 105),
	RED      = Color3.fromRGB(255, 90, 90),
	SLOT_BG  = Color3.fromRGB(24, 18, 18),
	SECTION  = Color3.fromRGB(130, 105, 80),
}

local RARITY_COLORS = {
	Common    = Color3.fromRGB(205, 210, 220),
	Uncommon  = Color3.fromRGB(70,  205, 105),
	Rare      = Color3.fromRGB(80,  170, 255),
	Epic      = Color3.fromRGB(200, 120, 255),
	Legendary = Color3.fromRGB(255, 175,  85),
}

local QS_FONT = "rbxasset://fonts/families/Quicksand.json"
local function qsFont(lbl, w)
	pcall(function()
		lbl.FontFace = Font.new(QS_FONT, w or Enum.FontWeight.Medium)
	end)
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
local latestSnapshot    = nil
local cursorHeld        = false
local activeScreen      = nil
local countdownThread   = nil

-- Browse state
local browsePage        = 1
local browseTotalPages  = 1
local browseFilter      = nil
local browseSearchItem  = nil
local browseSearchPlayer= nil
local browsePriceSort   = nil
local advFilterOpen     = false

-- My Auctions state
local myAuctionsData    = nil
local historyPage       = 1
local historyTotalPages = 1

-- Create Listing state
local selectedItemUuid  = nil
local selectedItem      = nil

-- ---------------------------------------------------------------------------
-- Utilities
-- ---------------------------------------------------------------------------
local function rarityColor(rarity)
	return RARITY_COLORS[rarity] or C.DIM
end

-- Per-slot T1 armor icons (same assets as training gear)
local SLOT_ICONS = {
	Helm  = "rbxassetid://71167376295923",
	Chest = "rbxassetid://91334970387049",
	Legs  = "rbxassetid://83129624279163",
	Boots = "rbxassetid://109900187251534",
}

local function getItemIcon(item)
	if not item then return "" end
	if type(item.icon) == "string" and item.icon ~= "" then return item.icon end
	if type(item.itemId) == "string" and item.itemId ~= "" then
		local ok, def = pcall(function() return ItemDefinitions.Get(item.itemId) end)
		if ok and type(def) == "table" then
			if type(def.Icon) == "string" and def.Icon ~= "" then return def.Icon end
		end
	end
	-- Slot-specific fallback (uses T1 training gear icons for all tiers)
	local slot = item.equipSlot or ""
	if SLOT_ICONS[slot] then return SLOT_ICONS[slot] end
	if item.type == "Armor" then return Config.ARMOR_ICON_ID end
	return ""
end

local function formatCoins(n)
	n = math.floor(tonumber(n) or 0)
	if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
	if n >= 1000    then return string.format("%.1fK", n / 1000) end
	return tostring(n)
end

local function formatDate(ts)
	if type(ts) ~= "number" then return "?" end
	-- Roblox doesn't have os.date with format strings; build from DateTime
	local ok, dt = pcall(function()
		return DateTime.fromUnixTimestamp(ts):FormatLocalTime("M/D/YY [at] h:mmA", "en-us")
	end)
	if ok and dt then return dt end
	return tostring(ts)
end

local function formatTimeRemaining(expiresAt)
	local secs = math.max(0, (expiresAt or 0) - os.time())
	if secs <= 0 then return "EXPIRED" end
	local d = math.floor(secs / 86400)
	local h = math.floor((secs % 86400) / 3600)
	local m = math.floor((secs % 3600)  / 60)
	local s = secs % 60
	if d > 0 then return string.format("%dD %02dH %02dM", d, h, m) end
	return string.format("%02dH %02dM %02dS", h, m, s)
end

local function getProfileCoins()
	if latestSnapshot and latestSnapshot.profile and latestSnapshot.profile.currencies then
		return math.floor(tonumber(latestSnapshot.profile.currencies.Coins) or 0)
	end
	return 0
end

local function getInventoryItems()
	if not (latestSnapshot and latestSnapshot.profile) then return {}, {} end
	local profile  = latestSnapshot.profile
	local equipped = type(profile.equipped) == "table" and profile.equipped or {}
	local equippedSet = {}
	for _, uuid in pairs(equipped) do
		if type(uuid) == "string" then equippedSet[uuid] = true end
	end
	local bagItems  = {}
	local hotbarSet = {}
	if type(profile.hotbar) == "table" then
		for _, uuid in ipairs(profile.hotbar) do
			if type(uuid) == "string" then hotbarSet[uuid] = true end
		end
	end
	for uuid, item in pairs(profile.inventory or {}) do
		if not equippedSet[uuid] then
			table.insert(bagItems, item)
		end
	end
	table.sort(bagItems, function(a, b)
		local ta = (a.type or "") .. (a.name or "")
		local tb = (b.type or "") .. (b.name or "")
		return ta < tb
	end)
	return bagItems, hotbarSet
end

-- ---------------------------------------------------------------------------
-- UI builders
-- ---------------------------------------------------------------------------
local function uiCorner(parent, r)
	Instance.new("UICorner", parent).CornerRadius = UDim.new(0, r or 8)
end

local function uiStroke(parent, thickness, color, trans)
	local s         = Instance.new("UIStroke", parent)
	s.Thickness     = thickness or 1.5
	s.Color         = color or C.STROKE
	s.Transparency  = trans or 0
	return s
end

local function makeLabel(parent, props)
	local lbl                  = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.TextColor3             = props.color or C.TEXT
	lbl.Font                   = Enum.Font.GothamMedium
	lbl.TextSize               = props.size or 14
	lbl.TextXAlignment         = props.xAlign or Enum.TextXAlignment.Left
	lbl.TextYAlignment         = props.yAlign or Enum.TextYAlignment.Center
	lbl.TextWrapped            = props.wrap or false
	lbl.Text                   = props.text or ""
	lbl.Size                   = props.sz or UDim2.new(1, 0, 0, 24)
	lbl.Position               = props.pos or UDim2.new(0, 0, 0, 0)
	lbl.ZIndex                 = props.z or 3
	lbl.Parent                 = parent
	qsFont(lbl, props.weight)
	return lbl
end

local function makeBtn(parent, props)
	local btn                  = Instance.new("TextButton")
	btn.BackgroundColor3       = props.bg or C.BTN
	btn.Size                   = props.sz or UDim2.fromOffset(120, 32)
	btn.Position               = props.pos or UDim2.new(0, 0, 0, 0)
	btn.AnchorPoint            = props.anchor or Vector2.new(0, 0)
	btn.Font                   = Enum.Font.GothamBold
	btn.TextSize               = props.textSize or 13
	btn.TextColor3             = props.fg or C.TEXT
	btn.Text                   = props.text or ""
	btn.ZIndex                 = props.z or 4
	btn.AutoButtonColor        = false
	btn.BorderSizePixel        = 0
	btn.Parent                 = parent
	uiCorner(btn, props.r or 8)
	if props.stroke then uiStroke(btn, 1.5, props.stroke, 0.35) end
	return btn
end

-- ---------------------------------------------------------------------------
-- ScreenGui
-- ---------------------------------------------------------------------------
local gui         = Instance.new("ScreenGui")
gui.Name          = "AuctionHouseUI"
gui.ResetOnSpawn  = false
gui.IgnoreGuiInset= true
gui.DisplayOrder  = 120
gui.Enabled       = false
gui.ZIndexBehavior= Enum.ZIndexBehavior.Sibling
gui.Parent        = playerGui

local dim         = Instance.new("TextButton")
dim.Name          = "Dim"
dim.Size          = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 0.5
dim.BorderSizePixel = 0
dim.Text          = ""
dim.AutoButtonColor = false
dim.ZIndex        = 1
dim.Parent        = gui

-- ---------------------------------------------------------------------------
-- Screen containers (only one visible at a time)
-- ---------------------------------------------------------------------------
local screens = {}

local function showScreen(name)
	for n, f in pairs(screens) do f.Visible = (n == name) end
	activeScreen = name
end

local function closeAll()
	gui.Enabled = false
	if cursorHeld then MenuMouse.release() ; cursorHeld = false end
	if countdownThread then task.cancel(countdownThread) ; countdownThread = nil end
	for _, f in pairs(screens) do f.Visible = false end
end

dim.Activated:Connect(closeAll)
UserInputService.InputBegan:Connect(function(input, proc)
	if proc then return end
	if input.KeyCode == Enum.KeyCode.Escape and gui.Enabled then closeAll() end
end)

-- ---------------------------------------------------------------------------
-- SCREEN 1: Browse
-- ---------------------------------------------------------------------------
do
	local root        = Instance.new("Frame")
	root.Name         = "Browse"
	root.Size         = UDim2.fromOffset(980, 640)
	root.AnchorPoint  = Vector2.new(0.5, 0.5)
	root.Position     = UDim2.fromScale(0.5, 0.5)
	root.BackgroundColor3 = C.PANEL
	root.BorderSizePixel  = 0
	root.ZIndex       = 2
	root.Visible      = false
	root.Parent       = gui
	uiCorner(root, 12)
	uiStroke(root, 1.5, C.STROKE, 0)
	screens["Browse"] = root

	-- Title bar
	local titleBar = Instance.new("Frame")
	titleBar.Name  = "TitleBar"
	titleBar.Size  = UDim2.new(1, 0, 0, 46)
	titleBar.BackgroundColor3 = Color3.fromRGB(20, 14, 14)
	titleBar.BorderSizePixel  = 0
	titleBar.ZIndex = 3
	titleBar.Parent = root
	uiCorner(titleBar, 12)

	local titleLbl = makeLabel(titleBar, {
		text   = "Auction House",
		color  = C.GOLD,
		size   = 18,
		weight = Enum.FontWeight.Bold,
		sz     = UDim2.new(0, 260, 1, 0),
		pos    = UDim2.new(0, 16, 0, 0),
		z      = 4,
	})

	local resultsLbl = makeLabel(titleBar, {
		text  = "Results:",
		color = C.DIM,
		size  = 13,
		sz    = UDim2.new(0, 200, 1, 0),
		pos   = UDim2.new(0, 200, 0, 0),
		z     = 4,
		xAlign = Enum.TextXAlignment.Left,
	})

	local createBtn = makeBtn(titleBar, {
		text   = "Create Listing",
		bg     = C.BTN_GOLD,
		sz     = UDim2.fromOffset(130, 30),
		anchor = Vector2.new(1, 0.5),
		pos    = UDim2.new(1, -152, 0.5, 0),
		z      = 4,
	})

	local myAuctBtn = makeBtn(titleBar, {
		text   = "My Auctions",
		bg     = C.BTN,
		sz     = UDim2.fromOffset(110, 30),
		anchor = Vector2.new(1, 0.5),
		pos    = UDim2.new(1, -14, 0.5, 0),
		z      = 4,
	})

	-- Body
	local body = Instance.new("Frame")
	body.Name  = "Body"
	body.Size  = UDim2.new(1, 0, 1, -96)
	body.Position = UDim2.new(0, 0, 0, 46)
	body.BackgroundTransparency = 1
	body.BorderSizePixel = 0
	body.ZIndex = 3
	body.Parent = root

	-- Sidebar
	local sidebar = Instance.new("Frame")
	sidebar.Name  = "Sidebar"
	sidebar.Size  = UDim2.fromOffset(148, 498)
	sidebar.Position = UDim2.fromOffset(8, 4)
	sidebar.BackgroundColor3 = Color3.fromRGB(20, 14, 14)
	sidebar.BorderSizePixel  = 0
	sidebar.ZIndex = 4
	sidebar.Parent = body
	uiCorner(sidebar, 8)
	uiStroke(sidebar, 1, C.STROKE, 0.4)

	local sideLayout = Instance.new("UIListLayout")
	sideLayout.Padding    = UDim.new(0, 6)
	sideLayout.SortOrder  = Enum.SortOrder.LayoutOrder
	sideLayout.Parent     = sidebar
	local sidePad = Instance.new("UIPadding", sidebar)
	sidePad.PaddingTop    = UDim.new(0, 8)
	sidePad.PaddingLeft   = UDim.new(0, 8)
	sidePad.PaddingRight  = UDim.new(0, 8)

	local FILTER_DEFS = {
		{ name = "Weapons",     label = "Weapons",     icon = "rbxassetid://6034267774" },
		{ name = "Armor",       label = "Armor",        icon = Config.ARMOR_ICON_ID },
		{ name = "Consumables", label = "Consumables",  icon = "" },
		{ name = "Professions", label = "Professions",  icon = "" },
		{ name = "Other",       label = "Other",         icon = "" },
	}

	local filterBtns = {}
	for i, fd in ipairs(FILTER_DEFS) do
		local btn = makeBtn(sidebar, {
			text      = fd.label,
			bg        = C.BTN,
			sz        = UDim2.new(1, 0, 0, 58),
			pos       = UDim2.new(0, 0, 0, 0),
			anchor    = Vector2.new(0, 0),
			textSize  = 13,
			z         = 5,
		})
		btn.LayoutOrder = i
		btn.Parent = sidebar
		if fd.icon ~= "" then
			local img = Instance.new("ImageLabel")
			img.Size  = UDim2.fromOffset(28, 28)
			img.AnchorPoint = Vector2.new(1, 0.5)
			img.Position    = UDim2.new(1, -8, 0.5, 0)
			img.BackgroundTransparency = 1
			img.Image = fd.icon
			img.ZIndex = 6
			img.Parent = btn
		end
		filterBtns[fd.name] = btn
	end

	local function applyFilterStyle(activeFilter)
		for fname, fb in pairs(filterBtns) do
			local active = (activeFilter == fname)
			local stroke = fb:FindFirstChildOfClass("UIStroke")
			if active and not stroke then
				uiStroke(fb, 2, C.GOLD, 0)
			elseif not active and stroke then
				stroke:Destroy()
			end
			fb.BackgroundColor3 = active and C.BTN_ACT or C.BTN
		end
	end

	-- Remove Filter button (visible only when a filter is active)
	local removeFilterBtn = makeBtn(sidebar, {
		text     = "Remove Filter",
		bg       = Color3.fromRGB(90, 30, 30),
		sz       = UDim2.new(1, 0, 0, 34),
		anchor   = Vector2.new(0, 0),
		textSize = 12,
		z        = 5,
	})
	removeFilterBtn.LayoutOrder = 10
	removeFilterBtn.Visible     = false
	removeFilterBtn.Parent      = sidebar
	-- Grid area
	local gridContainer = Instance.new("Frame")
	gridContainer.Name  = "GridContainer"
	gridContainer.Size  = UDim2.new(1, -164, 1, -4)
	gridContainer.Position = UDim2.fromOffset(160, 4)
	gridContainer.BackgroundTransparency = 1
	gridContainer.ZIndex = 3
	gridContainer.Parent = body

	local gridScroll = Instance.new("ScrollingFrame")
	gridScroll.Name   = "Grid"
	gridScroll.Size   = UDim2.new(1, 0, 1, 0)
	gridScroll.BackgroundColor3 = Color3.fromRGB(18, 13, 13)
	gridScroll.BorderSizePixel  = 0
	gridScroll.ScrollBarThickness = 6
	gridScroll.ScrollBarImageColor3 = C.STROKE
	gridScroll.CanvasSize  = UDim2.new()
	gridScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	gridScroll.ScrollingDirection  = Enum.ScrollingDirection.Y
	gridScroll.ZIndex = 3
	gridScroll.Parent = gridContainer
	uiCorner(gridScroll, 8)

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize     = UDim2.fromOffset(128, 128)
	gridLayout.CellPadding  = UDim2.fromOffset(6, 6)
	gridLayout.SortOrder    = Enum.SortOrder.LayoutOrder
	gridLayout.Parent       = gridScroll
	local gridPad = Instance.new("UIPadding", gridScroll)
	gridPad.PaddingTop    = UDim.new(0, 8)
	gridPad.PaddingBottom = UDim.new(0, 8)
	gridPad.PaddingLeft   = UDim.new(0, 8)
	gridPad.PaddingRight  = UDim.new(0, 8)

	local noResultsLbl = makeLabel(gridScroll, {
		text   = "NO RESULTS",
		color  = C.DIM,
		size   = 22,
		xAlign = Enum.TextXAlignment.Center,
		sz     = UDim2.new(1, 0, 0, 50),
		pos    = UDim2.new(0, 0, 0, 60),
		z      = 5,
	})
	noResultsLbl.Visible = false

	-- Bottom bar
	local bottomBar = Instance.new("Frame")
	bottomBar.Name  = "BottomBar"
	bottomBar.Size  = UDim2.new(1, -16, 0, 46)
	bottomBar.AnchorPoint = Vector2.new(0, 1)
	bottomBar.Position    = UDim2.new(0, 8, 1, -4)
	bottomBar.BackgroundColor3 = Color3.fromRGB(20, 14, 14)
	bottomBar.BorderSizePixel  = 0
	bottomBar.ZIndex = 3
	bottomBar.Parent = root
	uiCorner(bottomBar, 8)

	local advBtn = makeBtn(bottomBar, {
		text     = "  FILTER",
		bg       = C.BTN,
		sz       = UDim2.fromOffset(100, 32),
		anchor   = Vector2.new(0, 0.5),
		pos      = UDim2.new(0, 8, 0.5, 0),
		textSize = 12,
		z        = 4,
	})
	-- Hamburger icon lines
	for i = 0, 2 do
		local ln = Instance.new("Frame")
		ln.Size  = UDim2.fromOffset(14, 2)
		ln.Position = UDim2.fromOffset(8, 10 + i * 5)
		ln.BackgroundColor3 = C.TEXT
		ln.BorderSizePixel  = 0
		ln.ZIndex = 5
		ln.Parent = advBtn
	end

	local searchPlayerBtn = makeBtn(bottomBar, {
		text     = "Player Search",
		bg       = C.BTN,
		sz       = UDim2.fromOffset(130, 32),
		anchor   = Vector2.new(0, 0.5),
		pos      = UDim2.new(0, 118, 0.5, 0),
		textSize = 12,
		z        = 4,
	})

	local searchItemBtn = makeBtn(bottomBar, {
		text     = "Item Search",
		bg       = C.BTN,
		sz       = UDim2.fromOffset(110, 32),
		anchor   = Vector2.new(0, 0.5),
		pos      = UDim2.new(0, 258, 0.5, 0),
		textSize = 12,
		z        = 4,
	})

	local prevPageBtn = makeBtn(bottomBar, {
		text     = "< Back",
		bg       = C.BTN,
		sz       = UDim2.fromOffset(80, 32),
		anchor   = Vector2.new(1, 0.5),
		pos      = UDim2.new(1, -96, 0.5, 0),
		textSize = 12,
		z        = 4,
	})

	local nextPageBtn = makeBtn(bottomBar, {
		text     = "Next >",
		bg       = C.BTN,
		sz       = UDim2.fromOffset(80, 32),
		anchor   = Vector2.new(1, 0.5),
		pos      = UDim2.new(1, -8, 0.5, 0),
		textSize = 12,
		z        = 4,
	})

	-- Advanced filter dropdown
	local advDropdown = Instance.new("Frame")
	advDropdown.Name  = "AdvDropdown"
	advDropdown.Size  = UDim2.fromOffset(240, 200)
	advDropdown.AnchorPoint = Vector2.new(0, 1)
	advDropdown.Position    = UDim2.new(0, 8, 1, -50)
	advDropdown.BackgroundColor3 = Color3.fromRGB(22, 16, 16)
	advDropdown.BorderSizePixel  = 0
	advDropdown.ZIndex = 8
	advDropdown.Visible = false
	advDropdown.Parent  = root
	uiCorner(advDropdown, 8)
	uiStroke(advDropdown, 1, C.STROKE, 0.2)

	local advLayout = Instance.new("UIListLayout")
	advLayout.Padding   = UDim.new(0, 4)
	advLayout.SortOrder = Enum.SortOrder.LayoutOrder
	advLayout.Parent    = advDropdown
	local advPad = Instance.new("UIPadding", advDropdown)
	advPad.PaddingTop    = UDim.new(0, 8)
	advPad.PaddingBottom = UDim.new(0, 8)
	advPad.PaddingLeft   = UDim.new(0, 8)
	advPad.PaddingRight  = UDim.new(0, 8)

	local ADV_OPTIONS = { "Weapons", "Armor", "Consumables", "Professions", "Other" }
	local advCheckboxes = {}
	local advChecked = {}

	for i, opt in ipairs(ADV_OPTIONS) do
		local row = Instance.new("Frame")
		row.Name  = "Row_" .. opt
		row.BackgroundTransparency = 1
		row.Size  = UDim2.new(1, 0, 0, 26)
		row.LayoutOrder = i
		row.ZIndex = 9
		row.Parent = advDropdown

		local box = Instance.new("TextButton")
		box.Size  = UDim2.fromOffset(18, 18)
		box.Position = UDim2.fromOffset(0, 4)
		box.BackgroundColor3 = C.SLOT_BG
		box.Text  = ""
		box.Font  = Enum.Font.GothamBold
		box.TextSize = 12
		box.ZIndex = 10
		box.Parent = row
		uiCorner(box, 4)
		uiStroke(box, 1.5, C.STROKE, 0)

		local chk = Instance.new("TextLabel")
		chk.Size = UDim2.fromScale(1, 1)
		chk.BackgroundTransparency = 1
		chk.Text = ""
		chk.Font = Enum.Font.GothamBold
		chk.TextSize = 13
		chk.TextColor3 = C.GOLD
		chk.ZIndex = 11
		chk.Parent = box

		makeLabel(row, {
			text  = opt,
			color = C.TEXT,
			size  = 13,
			sz    = UDim2.new(1, -28, 1, 0),
			pos   = UDim2.fromOffset(26, 0),
			z     = 10,
		})

		advCheckboxes[opt] = { box = box, chk = chk }
	end

	-- Price sort row
	local sortRow = Instance.new("Frame")
	sortRow.BackgroundTransparency = 1
	sortRow.Size  = UDim2.new(1, 0, 0, 26)
	sortRow.LayoutOrder = 10
	sortRow.ZIndex = 9
	sortRow.Parent = advDropdown

	local priceAscBtn = makeBtn(sortRow, {
		text = "Price Asc",
		bg   = C.BTN,
		sz   = UDim2.fromOffset(90, 22),
		pos  = UDim2.fromOffset(0, 2),
		z    = 10,
		textSize = 12,
	})
	local priceDescBtn = makeBtn(sortRow, {
		text = "Price Desc",
		bg   = C.BTN,
		sz   = UDim2.fromOffset(90, 22),
		pos  = UDim2.fromOffset(96, 2),
		z    = 10,
		textSize = 12,
	})

	-- Search popup (shared)
	local searchPopup = Instance.new("Frame")
	searchPopup.Name  = "SearchPopup"
	searchPopup.Size  = UDim2.fromOffset(360, 150)
	searchPopup.AnchorPoint = Vector2.new(0.5, 0.5)
	searchPopup.Position    = UDim2.fromScale(0.5, 0.5)
	searchPopup.BackgroundColor3 = C.PANEL
	searchPopup.BorderSizePixel  = 0
	searchPopup.ZIndex = 20
	searchPopup.Visible = false
	searchPopup.Parent  = root
	uiCorner(searchPopup, 10)
	uiStroke(searchPopup, 1.5, C.STROKE, 0)

	local searchTitle = makeLabel(searchPopup, {
		text   = "Search",
		color  = C.GOLD,
		size   = 16,
		xAlign = Enum.TextXAlignment.Center,
		sz     = UDim2.new(1, -16, 0, 32),
		pos    = UDim2.fromOffset(8, 8),
		z      = 21,
		weight = Enum.FontWeight.Bold,
	})

	local searchBox = Instance.new("TextBox")
	searchBox.Size  = UDim2.new(1, -24, 0, 34)
	searchBox.Position = UDim2.fromOffset(12, 46)
	searchBox.BackgroundColor3 = Color3.fromRGB(18, 13, 13)
	searchBox.TextColor3 = C.TEXT
	searchBox.PlaceholderText = "Type here..."
	searchBox.PlaceholderColor3 = C.DIM
	searchBox.Font   = Enum.Font.GothamMedium
	searchBox.TextSize = 14
	searchBox.ClearTextOnFocus = true
	searchBox.BorderSizePixel = 0
	searchBox.ZIndex = 21
	searchBox.Parent = searchPopup
	uiCorner(searchBox, 6)
	uiStroke(searchBox, 1, C.STROKE, 0.3)

	local searchCancelBtn = makeBtn(searchPopup, {
		text   = "Cancel",
		bg     = C.BTN,
		sz     = UDim2.fromOffset(100, 32),
		anchor = Vector2.new(0, 1),
		pos    = UDim2.new(0, 12, 1, -10),
		z      = 21,
	})
	local searchConfirmBtn = makeBtn(searchPopup, {
		text   = "Search",
		bg     = C.BTN_GOLD,
		sz     = UDim2.fromOffset(100, 32),
		anchor = Vector2.new(1, 1),
		pos    = UDim2.new(1, -12, 1, -10),
		z      = 21,
	})

	local searchMode = "item" -- "item" or "player"

	local function hideSearchPopup()
		searchPopup.Visible = false
		advDropdown.Visible = false
	end

	local function showSearchPopup(mode)
		searchMode = mode
		searchTitle.Text = (mode == "player") and "Search by Player Name" or "Search by Item Name"
		searchBox.Text   = ""
		searchPopup.Visible = true
		advDropdown.Visible = false
		task.spawn(function() searchBox:CaptureFocus() end)
	end

	-- Forward-declare refreshBrowse so buttons can call it
	local refreshBrowse

	searchCancelBtn.Activated:Connect(hideSearchPopup)
	searchConfirmBtn.Activated:Connect(function()
		local text = searchBox.Text
		hideSearchPopup()
		if searchMode == "player" then
			browseSearchPlayer = (text ~= "") and text or nil
			browseSearchItem   = nil
		else
			browseSearchItem   = (text ~= "") and text or nil
			browseSearchPlayer = nil
		end
		browsePage = 1
		applyFilterStyle(browseFilter)
		refreshBrowse()
	end)
	searchBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then searchConfirmBtn.Activated:Fire() end
	end)

	-- Filter sidebar buttons
	for fname, fb in pairs(filterBtns) do
		local n = fname
		fb.Activated:Connect(function()
			if browseFilter == n then
				browseFilter = nil
			else
				browseFilter = n
			end
			browsePage = 1
			applyFilterStyle(browseFilter)
			advDropdown.Visible = false
			refreshBrowse()
		end)
	end

	-- Remove Filter button wiring
	removeFilterBtn.Activated:Connect(function()
		browseFilter = nil
		for opt, cb in pairs(advCheckboxes) do
			advChecked[opt] = false
			cb.chk.Text     = ""
		end
		applyFilterStyle(nil)
		browsePage = 1
		refreshBrowse()
	end)
	local _baseApply = applyFilterStyle
	applyFilterStyle = function(f)
		_baseApply(f)
		removeFilterBtn.Visible = (f ~= nil)
	end

	-- Advanced filter checkboxes
	for opt, cb in pairs(advCheckboxes) do
		local o = opt
		cb.box.Activated:Connect(function()
			advChecked[o] = not advChecked[o]
			cb.chk.Text = advChecked[o] and "x" or ""
			-- Use first checked as active filter
			local newFilter = nil
			for _, od in ipairs(ADV_OPTIONS) do
				if advChecked[od] then newFilter = od ; break end
			end
			browseFilter = newFilter
			applyFilterStyle(browseFilter)
			browsePage = 1
			refreshBrowse()
		end)
	end

	priceAscBtn.Activated:Connect(function()
		browsePriceSort = "asc"
		priceAscBtn.BackgroundColor3  = C.BTN_ACT
		priceDescBtn.BackgroundColor3 = C.BTN
		browsePage = 1 ; refreshBrowse()
	end)
	priceDescBtn.Activated:Connect(function()
		browsePriceSort = "desc"
		priceDescBtn.BackgroundColor3 = C.BTN_ACT
		priceAscBtn.BackgroundColor3  = C.BTN
		browsePage = 1 ; refreshBrowse()
	end)

	advBtn.Activated:Connect(function()
		advDropdown.Visible = not advDropdown.Visible
		searchPopup.Visible = false
	end)
	searchPlayerBtn.Activated:Connect(function() showSearchPopup("player") end)
	searchItemBtn.Activated:Connect(function()   showSearchPopup("item")   end)

	prevPageBtn.Activated:Connect(function()
		if browsePage > 1 then browsePage -= 1 ; refreshBrowse() end
	end)
	nextPageBtn.Activated:Connect(function()
		if browsePage < browseTotalPages then browsePage += 1 ; refreshBrowse() end
	end)

	-- Listing slot builder
	local function clearGrid()
		for _, ch in ipairs(gridScroll:GetChildren()) do
			if ch:IsA("Frame") then ch:Destroy() end
		end
	end

	local function buildListingSlot(listing, order)
		local item     = listing.item or {}
		local rCol     = rarityColor(item.rarity)
		local slot     = Instance.new("Frame")
		slot.Name      = "Slot_" .. tostring(listing.id)
		slot.BackgroundColor3 = C.SLOT_BG
		slot.BorderSizePixel  = 0
		slot.LayoutOrder      = order
		slot.ZIndex           = 4
		slot.Parent           = gridScroll
		uiCorner(slot, 6)
		uiStroke(slot, 1.5, rCol, 0.35)

		-- Name label (top)
		local nameLbl = makeLabel(slot, {
			text   = item.name or "?",
			color  = rCol,
			size   = 9,
			xAlign = Enum.TextXAlignment.Center,
			wrap   = true,
			sz     = UDim2.new(1, -4, 0, 22),
			pos    = UDim2.fromOffset(2, 2),
			z      = 5,
		})

		-- Icon (fills rest of slot)
		local iconImg = Instance.new("ImageLabel")
		iconImg.Size  = UDim2.new(1, -8, 1, -36)
		iconImg.Position = UDim2.fromOffset(4, 24)
		iconImg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		iconImg.BackgroundTransparency = 0.6
		iconImg.Image = getItemIcon(item)
		iconImg.ScaleType = Enum.ScaleType.Fit
		iconImg.ZIndex = 5
		iconImg.Parent = slot
		uiCorner(iconImg, 4)

		-- Price label (bottom)
		local priceLbl = makeLabel(slot, {
			text   = formatCoins(listing.price) .. " coins",
			color  = C.GOLD,
			size   = 9,
			xAlign = Enum.TextXAlignment.Center,
			sz     = UDim2.new(1, -4, 0, 14),
			anchor = Vector2.new(0, 1),
			pos    = UDim2.new(0, 2, 1, -2),
			z      = 5,
		})

		-- Click to buy
		local overlay = Instance.new("TextButton")
		overlay.Size = UDim2.fromScale(1, 1)
		overlay.BackgroundTransparency = 1
		overlay.Text = ""
		overlay.ZIndex = 6
		overlay.Parent = slot
		overlay.Activated:Connect(function()
			-- Confirm buy dialog inline on slot
			local ok, res = pcall(function()
				return rfBuyListing:InvokeServer(listing.id)
			end)
			if ok and res and res.ok then
				refreshBrowse()
			else
				local errMsg = (ok and res and res.err) or "Error"
									local errKey = (ok and res and res.err) or "save_failed"
					local MSGS = {own_listing="That is your own listing.",insufficient_funds="Not enough coins.",not_found="Listing no longer available.",already_sold="Someone else just bought it.",save_failed="Server error.",untradeable="Cannot list: starter gear is untradeable."}
					resultsLbl.Text = MSGS[errKey] or ("Error: "..tostring(errKey))
			end
		end)

		return slot
	end

	-- Debounce prevents two concurrent refreshBrowse calls building duplicate slots
	local _browseBusy = false

	-- Main refresh function
	refreshBrowse = function()
		if _browseBusy then return end
		_browseBusy = true
		clearGrid()
		noResultsLbl.Visible = false
		resultsLbl.Text = "Results: loading..."

		local ok, data = pcall(function()
			return rfGetListings:InvokeServer({
				page         = browsePage,
				filter       = browseFilter,
				searchItem   = browseSearchItem,
				searchPlayer = browseSearchPlayer,
				priceSort    = browsePriceSort,
			})
		end)

		if not ok or not data then
			resultsLbl.Text = "Results: error"
			return
		end

		local listings   = data.listings or {}
		browseTotalPages = data.totalPages or 1
		browsePage       = data.currentPage or browsePage
		resultsLbl.Text  = string.format("Results: %d  (pg %d/%d)",
			data.totalCount or 0, browsePage, browseTotalPages)

		if #listings == 0 then
			noResultsLbl.Visible = true
			return
		end

		for i, listing in ipairs(listings) do
			buildListingSlot(listing, i)
		end
		_browseBusy = false
	end

	-- Buttons
	createBtn.Activated:Connect(function()
		advDropdown.Visible = false
		searchPopup.Visible = false
		showScreen("CreateListing")
	end)

	myAuctBtn.Activated:Connect(function()
		advDropdown.Visible = false
		searchPopup.Visible = false
		showScreen("MyAuctions")
	end)

	-- Expose for open()
	_doRefreshBrowse = refreshBrowse

	-- Auto-refresh when screen becomes visible
	root:GetPropertyChangedSignal("Visible"):Connect(function()
		if root.Visible then refreshBrowse() end
	end)
end

-- ---------------------------------------------------------------------------
-- SCREEN 2: My Auctions
-- ---------------------------------------------------------------------------
do
	local root       = Instance.new("Frame")
	root.Name        = "MyAuctions"
	root.Size        = UDim2.fromOffset(900, 560)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position    = UDim2.fromScale(0.5, 0.5)
	root.BackgroundColor3 = C.PANEL
	root.BorderSizePixel  = 0
	root.ZIndex      = 2
	root.Visible     = false
	root.Parent      = gui
	uiCorner(root, 12)
	uiStroke(root, 1.5, C.STROKE, 0)
	screens["MyAuctions"] = root

	local titleBar = Instance.new("Frame")
	titleBar.Size  = UDim2.new(1, 0, 0, 46)
	titleBar.BackgroundColor3 = Color3.fromRGB(20, 14, 14)
	titleBar.BorderSizePixel  = 0
	titleBar.ZIndex = 3
	titleBar.Parent = root
	uiCorner(titleBar, 12)
	makeLabel(titleBar, {
		text   = "My Auctions",
		color  = C.GOLD,
		size   = 18,
		weight = Enum.FontWeight.Bold,
		sz     = UDim2.new(0, 300, 1, 0),
		pos    = UDim2.fromOffset(16, 0),
		z      = 4,
	})

	local backBtn = makeBtn(titleBar, {
		text   = "Back",
		bg     = C.BTN,
		sz     = UDim2.fromOffset(80, 30),
		anchor = Vector2.new(1, 0.5),
		pos    = UDim2.new(1, -10, 0.5, 0),
		z      = 4,
	})
	backBtn.Activated:Connect(function() showScreen("Browse") end)

	local body = Instance.new("Frame")
	body.Size  = UDim2.new(1, -16, 1, -56)
	body.Position = UDim2.fromOffset(8, 50)
	body.BackgroundTransparency = 1
	body.ZIndex = 3
	body.Parent = root

	local bodyLayout = Instance.new("UIListLayout", body)
	bodyLayout.Padding   = UDim.new(0, 10)
	bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder

	-- Currently listed section
	local activeHeader = makeLabel(body, {
		text      = "--- Currently Listed Items ---",
		color     = C.SECTION,
		size      = 13,
		xAlign    = Enum.TextXAlignment.Center,
		sz        = UDim2.new(1, 0, 0, 20),
		z         = 4,
		weight    = Enum.FontWeight.SemiBold,
	})
	activeHeader.LayoutOrder = 1

	local activeScroll = Instance.new("ScrollingFrame")
	activeScroll.Size  = UDim2.new(1, 0, 0, 100)
	activeScroll.BackgroundColor3 = Color3.fromRGB(18, 13, 13)
	activeScroll.BorderSizePixel  = 0
	activeScroll.ScrollBarThickness = 4
	activeScroll.CanvasSize    = UDim2.new()
	activeScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
	activeScroll.ScrollingDirection  = Enum.ScrollingDirection.X
	activeScroll.LayoutOrder   = 2
	activeScroll.ZIndex        = 4
	activeScroll.Parent        = body
	uiCorner(activeScroll, 6)

	local activeLayout = Instance.new("UIGridLayout", activeScroll)
	activeLayout.CellSize    = UDim2.fromOffset(88, 88)
	activeLayout.CellPadding = UDim2.fromOffset(4, 4)
	activeLayout.SortOrder   = Enum.SortOrder.LayoutOrder
	local activePad = Instance.new("UIPadding", activeScroll)
	activePad.PaddingTop    = UDim.new(0, 6)
	activePad.PaddingBottom = UDim.new(0, 6)
	activePad.PaddingLeft   = UDim.new(0, 6)
	activePad.PaddingRight  = UDim.new(0, 6)

	local activeEmptyLbl = makeLabel(activeScroll, {
		text   = "No items listed here",
		color  = C.DIM,
		size   = 13,
		xAlign = Enum.TextXAlignment.Center,
		sz     = UDim2.new(1, 0, 1, 0),
		z      = 5,
	})
	activeEmptyLbl.Visible = false

	-- History section
	local histHeader = makeLabel(body, {
		text   = "--- Auctions History ---",
		color  = C.SECTION,
		size   = 13,
		xAlign = Enum.TextXAlignment.Center,
		sz     = UDim2.new(1, 0, 0, 20),
		z      = 4,
		weight = Enum.FontWeight.SemiBold,
	})
	histHeader.LayoutOrder = 3

	local histScroll = Instance.new("ScrollingFrame")
	histScroll.Size  = UDim2.new(1, 0, 0, 200)
	histScroll.BackgroundColor3 = Color3.fromRGB(18, 13, 13)
	histScroll.BorderSizePixel  = 0
	histScroll.ScrollBarThickness = 6
	histScroll.CanvasSize    = UDim2.new()
	histScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	histScroll.ScrollingDirection  = Enum.ScrollingDirection.Y
	histScroll.LayoutOrder   = 4
	histScroll.ZIndex        = 4
	histScroll.Parent        = body
	uiCorner(histScroll, 6)

	local histGrid = Instance.new("UIGridLayout", histScroll)
	histGrid.CellSize    = UDim2.fromOffset(88, 88)
	histGrid.CellPadding = UDim2.fromOffset(4, 4)
	histGrid.SortOrder   = Enum.SortOrder.LayoutOrder
	local histPad = Instance.new("UIPadding", histScroll)
	histPad.PaddingTop    = UDim.new(0, 6)
	histPad.PaddingBottom = UDim.new(0, 6)
	histPad.PaddingLeft   = UDim.new(0, 6)
	histPad.PaddingRight  = UDim.new(0, 6)

	local histEmptyLbl = makeLabel(histScroll, {
		text   = "No items sold yet",
		color  = C.DIM,
		size   = 13,
		xAlign = Enum.TextXAlignment.Center,
		sz     = UDim2.new(1, 0, 0, 50),
		z      = 5,
	})
	histEmptyLbl.Visible = false

	-- Bottom bar
	local bottomBar = Instance.new("Frame")
	bottomBar.Size  = UDim2.new(1, -16, 0, 36)
	bottomBar.AnchorPoint = Vector2.new(0, 1)
	bottomBar.Position    = UDim2.new(0, 8, 1, -4)
	bottomBar.BackgroundTransparency = 1
	bottomBar.ZIndex = 3
	bottomBar.Parent = root

	local histPrevBtn = makeBtn(bottomBar, {
		text   = "< Prev",
		bg     = C.BTN,
		sz     = UDim2.fromOffset(80, 30),
		anchor = Vector2.new(1, 0.5),
		pos    = UDim2.new(1, -96, 0.5, 0),
		z      = 4,
	})
	local histNextBtn = makeBtn(bottomBar, {
		text   = "Next >",
		bg     = C.BTN,
		sz     = UDim2.fromOffset(80, 30),
		anchor = Vector2.new(1, 0.5),
		pos    = UDim2.new(1, -8, 0.5, 0),
		z      = 4,
	})

	local function buildMiniSlot(item, isActive, listingData, parentFrame)
		local rCol = rarityColor(item and item.rarity)
		local slot = Instance.new("Frame")
		slot.BackgroundColor3 = C.SLOT_BG
		slot.BorderSizePixel  = 0
		slot.ZIndex = 5
		slot.Parent = parentFrame
		uiCorner(slot, 5)
		uiStroke(slot, 1.5, rCol, 0.35)

		local nameLbl = makeLabel(slot, {
			text   = item and item.name or "?",
			color  = rCol,
			size   = 8,
			xAlign = Enum.TextXAlignment.Center,
			wrap   = true,
			sz     = UDim2.new(1, -4, 0, 20),
			pos    = UDim2.fromOffset(2, 2),
			z      = 6,
		})

		local iconImg = Instance.new("ImageLabel")
		iconImg.Size  = UDim2.new(1, -8, 1, -28)
		iconImg.Position = UDim2.fromOffset(4, 22)
		iconImg.BackgroundTransparency = 0.7
		iconImg.BackgroundColor3 = Color3.new(0, 0, 0)
		iconImg.Image  = getItemIcon(item)
		iconImg.ScaleType = Enum.ScaleType.Fit
		iconImg.ZIndex = 6
		iconImg.Parent = slot
		uiCorner(iconImg, 3)

		if isActive and listingData then
			local overlay = Instance.new("TextButton")
			overlay.Size  = UDim2.fromScale(1, 1)
			overlay.BackgroundTransparency = 1
			overlay.Text  = ""
			overlay.ZIndex = 7
			overlay.Parent = slot
			overlay.Activated:Connect(function()
				-- show My Listing detail
				_G.AH_showMyListing(listingData, false)
			end)
		end

		return slot
	end

	local function refreshMyAuctions()
		local ok, data = pcall(function()
			return rfGetMyListings:InvokeServer()
		end)
		if not ok or not data then return end
		myAuctionsData = data

		-- Clear active grid
		for _, ch in ipairs(activeScroll:GetChildren()) do
			if ch:IsA("Frame") then ch:Destroy() end
		end

		local active = data.active or {}
		activeEmptyLbl.Visible = (#active == 0)
		for i, listing in ipairs(active) do
			local slot = buildMiniSlot(listing.item, true, listing, activeScroll)
			slot.LayoutOrder = i
		end

		-- History grid
		for _, ch in ipairs(histScroll:GetChildren()) do
			if ch:IsA("Frame") then ch:Destroy() end
		end

		local history = data.history or {}
		histEmptyLbl.Visible = (#history == 0)
		histEmptyLbl = histEmptyLbl

		local hs = Config.HISTORY_PAGE_SIZE
		histEmptyLbl.Visible = (#history == 0)
		histEmptyLbl.Visible = (#history == 0)
		historyTotalPages = math.max(1, math.ceil(#history / hs))
		histEmptyLbl.Visible = (#history == 0)
		local s   = (historyPage - 1) * hs + 1
		local e   = math.min(s + hs - 1, #history)
		for i = s, e do
			local entry = history[i]
			local slot = buildMiniSlot(entry.item, false, nil, histScroll)
			slot.LayoutOrder = i
			-- Status badge
			local badge = makeLabel(slot, {
				text   = (entry.status == "sold") and "SOLD" or (entry.status == "expired" and "EXP" or "CNCL"),
				color  = (entry.status == "sold") and C.GREEN or C.RED,
				size   = 8,
				xAlign = Enum.TextXAlignment.Right,
				sz     = UDim2.new(1, -4, 0, 14),
				anchor = Vector2.new(0, 1),
				pos    = UDim2.new(0, 2, 1, -2),
				z      = 7,
			})
			-- Click to show detail
			local overlay = Instance.new("TextButton")
			overlay.Size  = UDim2.fromScale(1, 1)
			overlay.BackgroundTransparency = 1
			overlay.Text  = ""
			overlay.ZIndex = 8
			overlay.Parent = slot
			local captured = entry
			overlay.Activated:Connect(function()
				_G.AH_showMyListing(captured, true)
			end)
		end
	end

	histEmptyLbl = histEmptyLbl -- patch reference used above before it was declared

	histEmptyLbl = nil -- clear the global-ish reference (local capture was enough)

	histPrevBtn.Activated:Connect(function()
		if historyPage > 1 then historyPage -= 1 ; refreshMyAuctions() end
	end)
	histNextBtn.Activated:Connect(function()
		if historyPage < historyTotalPages then historyPage += 1 ; refreshMyAuctions() end
	end)

	-- Hook screen show
	local origVisible = Instance.new("BindableEvent")
	root:GetPropertyChangedSignal("Visible"):Connect(function()
		if root.Visible then refreshMyAuctions() end
	end)
end

-- ---------------------------------------------------------------------------
-- SCREEN 3: My Listing Detail
-- ---------------------------------------------------------------------------
do
	local root       = Instance.new("Frame")
	root.Name        = "MyListing"
	root.Size        = UDim2.fromOffset(620, 420)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position    = UDim2.fromScale(0.5, 0.5)
	root.BackgroundColor3 = C.PANEL
	root.BorderSizePixel  = 0
	root.ZIndex      = 2
	root.Visible     = false
	root.Parent      = gui
	uiCorner(root, 12)
	uiStroke(root, 1.5, C.STROKE, 0)
	screens["MyListing"] = root

	-- Title strip
	local titleFrame = Instance.new("Frame")
	titleFrame.Size  = UDim2.new(1, -32, 0, 36)
	titleFrame.AnchorPoint = Vector2.new(0.5, 0)
	titleFrame.Position    = UDim2.new(0.5, 0, 0, 10)
	titleFrame.BackgroundTransparency = 1
	titleFrame.ZIndex = 3
	titleFrame.Parent = root

	local titleDivL = Instance.new("Frame")
	titleDivL.Size  = UDim2.new(0.3, -60, 0, 1)
	titleDivL.Position = UDim2.fromOffset(0, 17)
	titleDivL.BackgroundColor3 = C.STROKE
	titleDivL.BorderSizePixel  = 0
	titleDivL.ZIndex = 4
	titleDivL.Parent = titleFrame

	local titleLbl = makeLabel(titleFrame, {
		text   = "Item Title",
		color  = C.TEXT,
		size   = 16,
		weight = Enum.FontWeight.Bold,
		xAlign = Enum.TextXAlignment.Center,
		sz     = UDim2.new(0.4, 0, 1, 0),
		pos    = UDim2.new(0.3, 0, 0, 0),
		z      = 4,
	})

	local titleDivR = Instance.new("Frame")
	titleDivR.Size  = UDim2.new(0.3, -60, 0, 1)
	titleDivR.Position = UDim2.new(0.7, 60, 0, 17)
	titleDivR.BackgroundColor3 = C.STROKE
	titleDivR.BorderSizePixel  = 0
	titleDivR.ZIndex = 4
	titleDivR.Parent = titleFrame

	-- Content
	local contentFrame = Instance.new("Frame")
	contentFrame.Size  = UDim2.new(1, -24, 1, -100)
	contentFrame.Position = UDim2.fromOffset(12, 52)
	contentFrame.BackgroundTransparency = 1
	contentFrame.ZIndex = 3
	contentFrame.Parent = root

	local itemIcon = Instance.new("ImageLabel")
	itemlcon = itemIcon
	itemIcon.Size  = UDim2.fromOffset(180, 180)
	itemIcon.BackgroundColor3 = C.SLOT_BG
	itemIcon.BackgroundTransparency = 0.3
	itemIcon.BorderSizePixel  = 0
	itemIcon.ZIndex = 4
	itemIcon.Parent = contentFrame
	uiCorner(itemIcon, 10)
	uiStroke(itemIcon, 1.5, C.STROKE, 0.3)

	local infoFrame = Instance.new("Frame")
	infoFrame.Size  = UDim2.new(1, -200, 1, 0)
	infoFrame.Position = UDim2.fromOffset(196, 0)
	infoFrame.BackgroundTransparency = 1
	infoFrame.ZIndex = 3
	infoFrame.Parent = contentFrame

	local infoLayout = Instance.new("UIListLayout", infoFrame)
	infoLayout.Padding   = UDim.new(0, 6)
	infoLayout.SortOrder = Enum.SortOrder.LayoutOrder

	local function makeInfoRow(text, z_)
		local lbl = makeLabel(infoFrame, {
			text  = text,
			color = C.DIM,
			size  = 13,
			wrap  = true,
			sz    = UDim2.new(1, 0, 0, 22),
			z     = z_ or 4,
		})
		lbl.LayoutOrder = #infoFrame:GetChildren()
		return lbl
	end

	local infoStatus       = makeInfoRow("")
	local infoListedAt     = makeInfoRow("")
	local infoListedFor    = makeInfoRow("")
	local infoTimeRemain   = makeInfoRow("")
	local infoSoldAt       = makeInfoRow("")
	local infoBoughtBy     = makeInfoRow("")
	local infoBoughtFor    = makeInfoRow("")
	local infoDuration     = makeInfoRow("")

	-- Bottom buttons
	local backBtn = makeBtn(root, {
		text   = "Back",
		bg     = C.BTN,
		sz     = UDim2.fromOffset(100, 34),
		anchor = Vector2.new(0, 1),
		pos    = UDim2.new(0, 12, 1, -12),
		z      = 4,
	})
	backBtn.Activated:Connect(function() showScreen("MyAuctions") end)

	local cancelBtn = makeBtn(root, {
		text   = "Cancel Listing",
		bg     = C.RED,
		sz     = UDim2.fromOffset(150, 34),
		anchor = Vector2.new(1, 1),
		pos    = UDim2.new(1, -12, 1, -12),
		z      = 4,
	})

	local currentListingId = nil

	-- Cancel handler
	cancelBtn.Activated:Connect(function()
		if not currentListingId then return end
		local ok, res = pcall(function()
			return rfCancelListing:InvokeServer(currentListingId)
		end)
		if ok and res and res.ok then
			showScreen("MyAuctions")
		else
			infoStatus.Text = "Error: " .. tostring((ok and res and res.err) or "failed")
		end
	end)

	-- Public function to show a listing
	_G.AH_showMyListing = function(listingData, isPast)
		showScreen("MyListing")
		currentListingId = listingData.id

		local item = listingData.item or {}
		titleLbl.Text = item.name or "Unknown Item"
		itemIcon.Image = getItemIcon(item)

		local rCol = rarityColor(item.rarity)
		local existingStroke = itemIcon:FindFirstChildOfClass("UIStroke")
		if existingStroke then existingStroke.Color = rCol
		else uiStroke(itemIcon, 1.5, rCol, 0.3) end

		infoListedAt.Text  = "Listed at: " .. formatDate(listingData.listedAt)
		infoListedFor.Text = "Listed for: " .. formatCoins(listingData.price) .. " coins"

		-- Stop old countdown
		if countdownThread then task.cancel(countdownThread) ; countdownThread = nil end

		if isPast then
			local statusStr = listingData.status or "?"
			infoStatus.Text = (statusStr == "sold") and "SOLD" or
				(statusStr == "expired") and "EXPIRED" or "CANCELLED"
			infoStatus.TextColor3 = (statusStr == "sold") and C.GREEN or C.RED
			infoTimeRemain.Text = ""
			infoSoldAt.Text   = "Sold at: "  .. (listingData.soldAt and formatDate(listingData.soldAt) or "N/A")
			infoBoughtBy.Text = "Bought by: " .. (listingData.buyerName or "N/A")
			infoBoughtFor.Text = "Bought for: " .. formatCoins(listingData.price) .. " coins"
			local dur = (listingData.soldAt or 0) - (listingData.listedAt or 0)
			local dh  = math.floor(dur / 3600)
			local dm  = math.floor((dur % 3600) / 60)
			infoDuration.Text = string.format("Listed for: %dh %dm", dh, dm)
			cancelBtn.Visible  = false
		else
			infoStatus.Text      = "ACTIVE"
			infoStatus.TextColor3 = C.GREEN
			infoSoldAt.Text   = ""
			infoBoughtBy.Text = ""
			infoBoughtFor.Text = ""
			infoDuration.Text = ""
			cancelBtn.Visible  = true
			-- Live countdown
			countdownThread = task.spawn(function()
				while root.Visible and activeScreen == "MyListing" do
					infoTimeRemain.Text = "Expires in: " .. formatTimeRemaining(listingData.expiresAt)
					task.wait(1)
				end
			end)
		end
	end
end

-- ---------------------------------------------------------------------------
-- SCREEN 4: Create Listing
-- ---------------------------------------------------------------------------
do
	local root       = Instance.new("Frame")
	root.Name        = "CreateListing"
	root.Size        = UDim2.fromOffset(1200, 700)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position    = UDim2.fromScale(0.5, 0.5)
	root.BackgroundColor3 = C.PANEL
	root.BorderSizePixel  = 0
	root.ZIndex      = 2
	root.Visible     = false
	root.Parent      = gui
	uiCorner(root, 12)
	uiStroke(root, 1.5, C.STROKE, 0)
	screens["CreateListing"] = root

	-- Title
	local titleBar = Instance.new("Frame")
	titleBar.Size  = UDim2.new(1, 0, 0, 46)
	titleBar.BackgroundColor3 = Color3.fromRGB(20, 14, 14)
	titleBar.BorderSizePixel  = 0
	titleBar.ZIndex = 3
	titleBar.Parent = root
	uiCorner(titleBar, 12)
	makeLabel(titleBar, {
		text   = "Create Listing",
		color  = C.GOLD,
		size   = 18,
		weight = Enum.FontWeight.Bold,
		sz     = UDim2.new(0, 300, 1, 0),
		pos    = UDim2.fromOffset(16, 0),
		z      = 4,
	})

	-- Body: left = inventory, right = form
	local body = Instance.new("Frame")
	body.Size  = UDim2.new(1, -16, 1, -56)
	body.Position = UDim2.fromOffset(8, 50)
	body.BackgroundTransparency = 1
	body.ZIndex = 3
	body.Parent = root

	-- Left: Mini Inventory
	local invPanel = Instance.new("Frame")
	invPanel.Name  = "InvPanel"
	invPanel.Size  = UDim2.fromOffset(520, 620)
	invPanel.BackgroundColor3 = Color3.fromRGB(18, 13, 13)
	invPanel.BorderSizePixel  = 0
	invPanel.ZIndex = 4
	invPanel.Parent = body
	uiCorner(invPanel, 8)
	uiStroke(invPanel, 1, C.STROKE, 0.4)

	local invLabel = makeLabel(invPanel, {
		text  = "Your Inventory (select item to list)",
		color = C.SECTION,
		size  = 12,
		sz    = UDim2.new(1, -8, 0, 20),
		pos   = UDim2.fromOffset(8, 4),
		z     = 5,
	})

	local invScroll = Instance.new("ScrollingFrame")
	invScroll.Size  = UDim2.new(1, -8, 1, -28)
	invScroll.Position = UDim2.fromOffset(4, 24)
	invScroll.BackgroundTransparency = 1
	invScroll.BorderSizePixel  = 0
	invScroll.ScrollBarThickness = 6
	invScroll.CanvasSize  = UDim2.new()
	invScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	invScroll.ScrollingDirection  = Enum.ScrollingDirection.Y
	invScroll.ZIndex = 5
	invScroll.Parent = invPanel

	local invGrid = Instance.new("UIGridLayout", invScroll)
	invGrid.CellSize    = UDim2.fromOffset(100, 100)
	invGrid.CellPadding = UDim2.fromOffset(6, 6)
	invGrid.SortOrder   = Enum.SortOrder.LayoutOrder
	local invPad = Instance.new("UIPadding", invScroll)
	invPad.PaddingTop    = UDim.new(0, 4)
	invPad.PaddingBottom = UDim.new(0, 4)
	invPad.PaddingLeft   = UDim.new(0, 4)
	invPad.PaddingRight  = UDim.new(0, 4)

	-- Right: Listing form
	local formPanel = Instance.new("Frame")
	formPanel.Name  = "FormPanel"
	formPanel.Size  = UDim2.new(1, -546, 1, 0)
	formPanel.Position = UDim2.fromOffset(538, 0)
	formPanel.BackgroundColor3 = Color3.fromRGB(18, 13, 13)
	formPanel.BorderSizePixel  = 0
	formPanel.ZIndex = 4
	formPanel.Parent = body
	uiCorner(formPanel, 8)
	uiStroke(formPanel, 1, C.STROKE, 0.4)

	local noSelectLbl = makeLabel(formPanel, {
		text   = "Please select an item\nfrom your inventory",
		color  = C.DIM,
		size   = 14,
		xAlign = Enum.TextXAlignment.Center,
		wrap   = true,
		sz     = UDim2.new(1, -16, 0, 60),
		anchor = Vector2.new(0, 0.5),
		pos    = UDim2.new(0, 8, 0.5, -30),
		z      = 5,
	})

	local formContent = Instance.new("Frame")
	formContent.Name  = "FormContent"
	formContent.Size  = UDim2.new(1, -16, 1, -50)
	formContent.Position = UDim2.fromOffset(8, 8)
	formContent.BackgroundTransparency = 1
	formContent.ZIndex = 5
	formContent.Parent = formPanel
	formContent.Visible = false

	local formLayout = Instance.new("UIListLayout", formContent)
	formLayout.Padding   = UDim.new(0, 10)
	formLayout.SortOrder = Enum.SortOrder.LayoutOrder
	formLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	local formItemName = makeLabel(formContent, {
		text   = "Item Name",
		color  = C.TEXT,
		size   = 15,
		weight = Enum.FontWeight.Bold,
		xAlign = Enum.TextXAlignment.Center,
		sz     = UDim2.new(1, 0, 0, 24),
		z      = 6,
	})
	formItemName.LayoutOrder = 1

	local formIconImg = Instance.new("ImageLabel")
	formIconImg.Size  = UDim2.fromOffset(110, 110)
	formIconImg.BackgroundColor3 = C.SLOT_BG
	formIconImg.BackgroundTransparency = 0.3
	formIconImg.BorderSizePixel = 0
	formIconImg.ZIndex = 6
	formIconImg.ScaleType = Enum.ScaleType.Fit
	formIconImg.LayoutOrder = 2
	formIconImg.Parent = formContent
	uiCorner(formIconImg, 8)
	uiStroke(formIconImg, 1.5, C.STROKE, 0.3)

	local function makeFormInput(labelText, placeholder, defaultVal, lo)
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 36)
		row.ZIndex = 6
		row.LayoutOrder = lo
		row.Parent = formContent
		makeLabel(row, {
			text  = labelText,
			color = C.DIM,
			size  = 12,
			sz    = UDim2.new(0, 110, 1, 0),
			z     = 7,
		})
		local box = Instance.new("TextBox")
		box.Size  = UDim2.new(1, -118, 1, -4)
		box.Position = UDim2.fromOffset(114, 2)
		box.BackgroundColor3 = Color3.fromRGB(24, 18, 18)
		box.TextColor3 = C.TEXT
		box.PlaceholderText  = placeholder
		box.PlaceholderColor3 = C.DIM
		box.Font  = Enum.Font.GothamMedium
		box.TextSize = 14
		box.Text  = defaultVal or ""
		box.ZIndex = 7
		box.BorderSizePixel = 0
		box.Parent = row
		uiCorner(box, 5)
		uiStroke(box, 1, C.STROKE, 0.4)
		return box
	end

	local priceBox    = makeFormInput("Sell price:",   "Enter price here", "", 3)
	local durationBox = makeFormInput("List for (days):", "1 - 7",   "1", 4)

	local statusLbl = makeLabel(formContent, {
		text   = "",
		color  = C.RED,
		size   = 12,
		xAlign = Enum.TextXAlignment.Center,
		sz     = UDim2.new(1, 0, 0, 20),
		z      = 6,
	})
	statusLbl.LayoutOrder = 5

	-- Bottom buttons (on root, not formContent)
	local goBackBtn2 = makeBtn(root, {
		text   = "Go Back",
		bg     = C.BTN,
		sz     = UDim2.fromOffset(100, 34),
		anchor = Vector2.new(0, 1),
		pos    = UDim2.new(0, 12, 1, -12),
		z      = 5,
	})
	goBackBtn2.Activated:Connect(function() showScreen("Browse") end)

	local confirmBtn = makeBtn(root, {
		text   = "Confirm",
		bg     = C.BTN_GOLD,
		sz     = UDim2.fromOffset(120, 34),
		anchor = Vector2.new(1, 1),
		pos    = UDim2.new(1, -12, 1, -12),
		z      = 5,
	})

	-- Inventory refresh
	local function clearInvGrid()
		for _, ch in ipairs(invScroll:GetChildren()) do
			if ch:IsA("Frame") then ch:Destroy() end
		end
	end

	local function selectItem(uuid, item)
		selectedItemUuid = uuid
		selectedItem     = item
		if item then
			noSelectLbl.Visible  = false
			formContent.Visible  = true
			formItemName.Text    = item.name or "?"
			formIconImg.Image    = getItemIcon(item)
			local rCol = rarityColor(item.rarity)
			formItemName.TextColor3 = rCol
			local existStroke = formIconImg:FindFirstChildOfClass("UIStroke")
			if existStroke then existStroke.Color = rCol
			else uiStroke(formIconImg, 1.5, rCol, 0.3) end
		else
			noSelectLbl.Visible  = true
			formContent.Visible  = false
		end
	end

	local function refreshInv()
		clearInvGrid()
		selectedItemUuid = nil
		selectedItem     = nil
		noSelectLbl.Visible  = true
		formContent.Visible  = false

		local items, hotbarSet = getInventoryItems()
		for i, item in ipairs(items) do
			local uuid  = item.uuid
			local rCol  = rarityColor(item.rarity)
			local isHot = hotbarSet[uuid]

			local slot = Instance.new("Frame")
			slot.BackgroundColor3 = C.SLOT_BG
			slot.BorderSizePixel  = 0
			slot.LayoutOrder = i
			slot.ZIndex = 6
			slot.Parent = invScroll
			uiCorner(slot, 4)
			uiStroke(slot, 1.5, rCol, 0.4)

			local nameLbl = makeLabel(slot, {
				text   = item.name or "?",
				color  = rCol,
				size   = 9,
				xAlign = Enum.TextXAlignment.Center,
				wrap   = true,
				sz     = UDim2.new(1, -2, 0, 22),
				pos    = UDim2.fromOffset(1, 1),
				z      = 7,
			})

			local icon = Instance.new("ImageLabel")
			icon.Size  = UDim2.new(1, -8, 1, -28)
			icon.Position = UDim2.fromOffset(4, 23)
			icon.BackgroundTransparency = 0.7
			icon.BackgroundColor3 = Color3.new(0, 0, 0)
			icon.Image = getItemIcon(item)
			icon.ScaleType = Enum.ScaleType.Fit
			icon.ZIndex = 7
			icon.Parent = slot
			uiCorner(icon, 3)

			local overlay = Instance.new("TextButton")
			overlay.Size = UDim2.fromScale(1, 1)
			overlay.BackgroundTransparency = 1
			overlay.Text  = ""
			overlay.ZIndex = 8
			overlay.Parent = slot
			local cu, ci = uuid, item
			overlay.Activated:Connect(function()
				selectItem(cu, ci)
				-- Highlight selected
				for _, ch in ipairs(invScroll:GetChildren()) do
					if ch:IsA("Frame") then
						local s = ch:FindFirstChildOfClass("UIStroke")
						if s then s.Transparency = 0.4 end
					end
				end
				local myStroke = slot:FindFirstChildOfClass("UIStroke")
				if myStroke then myStroke.Transparency = 0 ; myStroke.Color = C.GOLD end
			end)
		end
	end

	-- Hook: refresh inventory when screen shows
	root:GetPropertyChangedSignal("Visible"):Connect(function()
		if root.Visible then
			-- Sync profile first
			if rfSync then
				task.spawn(function()
					local ok, snap = pcall(function()
						return rfSync:InvokeServer()
					end)
					if ok and snap then latestSnapshot = snap end
					refreshInv()
				end)
			else
				refreshInv()
			end
		end
	end)

	-- Confirm
	confirmBtn.Activated:Connect(function()
		if not selectedItemUuid or not selectedItem then
			statusLbl.Text = "Select an item first."
			return
		end
		local price = math.floor(tonumber(priceBox.Text) or 0)
		if price < 1 or price > 999999 then
			statusLbl.Text = "Price must be 1-999,999."
			return
		end
		local days = math.floor(tonumber(durationBox.Text) or 0)
		if days < 1 or days > 7 then
			statusLbl.Text = "Duration must be 1-7 days."
			return
		end
		statusLbl.Text = "Submitting..."
		statusLbl.TextColor3 = C.DIM
		confirmBtn.Active = false
		local ok, res = pcall(function()
			return rfCreateListing:InvokeServer(selectedItemUuid, price, days)
		end)
		confirmBtn.Active = true
		if ok and res and res.ok then
			statusLbl.Text = ""
			showScreen("Browse")
			-- Trigger a browse refresh
			task.spawn(function()
				task.wait(0.2)
				-- browse screen's refreshBrowse not in scope here;
				-- handled by screen visibility change
			end)
		else
			statusLbl.TextColor3 = C.RED
			statusLbl.Text = "Error: " .. tostring((ok and res and res.err) or "failed")
		end
	end)
end

-- ---------------------------------------------------------------------------
-- Profile push listener
-- ---------------------------------------------------------------------------
if profilePush then
	profilePush.OnClientEvent:Connect(function(payload)
		if payload then latestSnapshot = payload end
	end)
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------
local AuctionHouseClient = {}

function AuctionHouseClient.open()
	if not cursorHeld then
		MenuMouse.acquire()
		cursorHeld = true
	end
	gui.Enabled = true
	browsePage  = 1
	showScreen("Browse")
	-- Profile sync in background; Browse Visible listener handles the grid refresh
	task.spawn(function()
		if rfSync then
			local ok, snap = pcall(function() return rfSync:InvokeServer() end)
			if ok and snap then latestSnapshot = snap end
		end
	end)
end

function AuctionHouseClient.close()
	closeAll()
end

return AuctionHouseClient
