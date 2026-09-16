local Keys = require(game:GetService("ReplicatedStorage"):WaitForChild("KeybindConfig"))
--[[
  BankClient
  Client-side bank GUI + ProximityPrompt interaction.
  Hold E (~0.75s) on the Treasure Chest to open the bank.
  Deposit All moves every Coins item from bags into the spendable wallet.
  Withdraw opens a center popup and returns wallet coins as inventory items.
  Stash items in chest storage (9×6): unlock extra rows with wallet coins. Inventory strip at the bottom.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MenuMouse = require(ReplicatedStorage:WaitForChild("CursorUtils"))
local UserInputService = game:GetService("UserInputService")
local Types = require(ReplicatedStorage:WaitForChild("ProfileTypes"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))

local CHEST_SLOT_COUNT = Types.CHEST_SLOT_COUNT
local CHEST_COLS = Types.CHEST_GRID_COLUMNS
local CHEST_ROWS = Types.CHEST_GRID_ROWS
local CHEST_ROW_UNLOCK_COST = Types.CHEST_ROW_UNLOCK_COIN_COST
-- Must match `rowGrid.CellSize` Y so the unlock strip matches slot button height.
local CHEST_SLOT_PX = 70

local DungeonMenuNet = require(script.Parent:WaitForChild("DungeonMenuNet"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Remote references
local rfBankRequest = ReplicatedStorage:WaitForChild("BankRequest")
local rfBankSync = ReplicatedStorage:WaitForChild("BankSync")

---------------------------------------------------------------------------
-- GUI Construction
---------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BankUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 130
screenGui.Enabled = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- Declared early so chest unlock handlers (wired during GUI build) share the same state as setOpen().
local open = false
local selectedUuid = nil
-- Minimum unlocked chest rows the client trusts after a successful server unlock (snapshot can lag).
local clientChestUr = 1

local function effectiveChestUnlockedRows()
	local snap = DungeonMenuNet.getLastSnapshot()
	local p = snap and snap.profile
	local snapUr = math.clamp(math.floor(tonumber(p and p.chestUnlockedRows) or 1), 1, CHEST_ROWS)
	return math.max(snapUr, clientChestUr)
end

-- Assigned after `setOpen` is defined; used to hard-refresh bank UI after a chest row unlock.
local closeAndReopenBankAfterUnlock

-- Dim backdrop (outside-click dismiss uses GetGuiObjectsAtPosition; see close handlers)
local dim = Instance.new("Frame")
dim.Name = "Dim"
dim.Size = UDim2.fromScale(1, 1)
dim.Position = UDim2.new()
dim.BackgroundColor3 = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 0.45
dim.BorderSizePixel = 0
dim.Active = true
dim.Selectable = false
dim.ZIndex = 1
dim.Parent = screenGui

-- Main panel
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.45, 0)
panel.Size = UDim2.fromOffset(940, 600)
panel.BackgroundColor3 = Color3.fromRGB(30, 22, 22)
panel.BorderSizePixel = 0
panel.ZIndex = 2
panel.Parent = screenGui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 12)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Thickness = 1
panelStroke.Color = Color3.fromRGB(90, 70, 70)
panelStroke.Parent = panel

-- Absorb background clicks so they do not fall through to `dim` (which closes the UI).
-- Transparent Frames default to Active = false, so clicks were hitting the backdrop.
panel.Active = true

-- Title
local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.AnchorPoint = Vector2.new(0.5, 0)
title.Position = UDim2.new(0.5, 0, 0, 8)
title.Size = UDim2.new(1, -72, 0, 32)
title.Font = Enum.Font.GothamBold
title.TextSize = 22
title.TextXAlignment = Enum.TextXAlignment.Center
title.TextColor3 = Color3.new(1, 1, 1)
title.Text = "Bank & Chest"
title.ZIndex = 3
title.Parent = panel

-- Close button (X)
local closeBtn = Instance.new("TextButton")
closeBtn.Name = "CloseBtn"
closeBtn.Size = UDim2.fromOffset(32, 32)
closeBtn.Position = UDim2.new(1, -40, 0, 8)
closeBtn.BackgroundColor3 = Color3.fromRGB(60, 40, 40)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 18
closeBtn.TextColor3 = Color3.fromRGB(220, 180, 180)
closeBtn.Text = "X"
closeBtn.ZIndex = 4
closeBtn.Parent = panel

local closeBtnCorner = Instance.new("UICorner")
closeBtnCorner.CornerRadius = UDim.new(0, 8)
closeBtnCorner.Parent = closeBtn

-- Main layout: top = coins + scrollable chest (rows unlock with coins); bottom = taller scrollable bags
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.BackgroundTransparency = 1
mainFrame.Active = true
mainFrame.Position = UDim2.new(0, 8, 0, 40)
mainFrame.Size = UDim2.new(1, -16, 1, -48)
mainFrame.ZIndex = 3
mainFrame.Parent = panel

local mainVL = Instance.new("UIListLayout")
mainVL.FillDirection = Enum.FillDirection.Vertical
mainVL.HorizontalAlignment = Enum.HorizontalAlignment.Center
mainVL.Padding = UDim.new(0, 8)
mainVL.SortOrder = Enum.SortOrder.LayoutOrder
mainVL.Parent = mainFrame

local upperFrame = Instance.new("Frame")
upperFrame.Name = "Upper"
upperFrame.BackgroundTransparency = 1
upperFrame.Size = UDim2.new(1, 0, 0, 256)
upperFrame.LayoutOrder = 1
upperFrame.Parent = mainFrame

local coinColumn = Instance.new("Frame")
coinColumn.Name = "CoinColumn"
coinColumn.BackgroundTransparency = 1
coinColumn.Position = UDim2.new(0, 0, 0, 0)
coinColumn.Size = UDim2.new(0, 190, 1, 0)
coinColumn.ZIndex = 3
coinColumn.Parent = upperFrame

local coinLayout = Instance.new("UIListLayout")
coinLayout.FillDirection = Enum.FillDirection.Vertical
coinLayout.SortOrder = Enum.SortOrder.LayoutOrder
coinLayout.Padding = UDim.new(0, 5)
coinLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
coinLayout.Parent = coinColumn

local walletLabel = Instance.new("TextLabel")
walletLabel.Name = "WalletLabel"
walletLabel.BackgroundTransparency = 1
walletLabel.Size = UDim2.new(1, 0, 0, 20)
walletLabel.LayoutOrder = 1
walletLabel.Font = Enum.Font.GothamMedium
walletLabel.TextSize = 12
walletLabel.TextXAlignment = Enum.TextXAlignment.Center
walletLabel.TextColor3 = Color3.fromRGB(255, 215, 100)
walletLabel.Text = "Wallet: 0 Coins"
walletLabel.ZIndex = 3
walletLabel.Parent = coinColumn

local bankLabel = Instance.new("TextLabel")
bankLabel.Name = "BankLabel"
bankLabel.BackgroundTransparency = 1
bankLabel.Size = UDim2.new(1, 0, 0, 20)
bankLabel.LayoutOrder = 2
bankLabel.Font = Enum.Font.GothamMedium
bankLabel.TextSize = 12
bankLabel.TextXAlignment = Enum.TextXAlignment.Center
bankLabel.TextColor3 = Color3.fromRGB(100, 200, 255)
bankLabel.Text = "In bags: 0 Coins"
bankLabel.ZIndex = 3
bankLabel.Parent = coinColumn

local depositBtn = Instance.new("TextButton")
depositBtn.Name = "DepositBtn"
depositBtn.Size = UDim2.new(1, -4, 0, 30)
depositBtn.LayoutOrder = 3
depositBtn.BackgroundColor3 = Color3.fromRGB(40, 80, 40)
depositBtn.Font = Enum.Font.GothamBold
depositBtn.TextSize = 13
depositBtn.TextColor3 = Color3.new(1, 1, 1)
depositBtn.Text = "Deposit All"
depositBtn.ZIndex = 4
depositBtn.Parent = coinColumn

local depositBtnCorner = Instance.new("UICorner")
depositBtnCorner.CornerRadius = UDim.new(0, 6)
depositBtnCorner.Parent = depositBtn

local withdrawBtn = Instance.new("TextButton")
withdrawBtn.Name = "WithdrawBtn"
withdrawBtn.Size = UDim2.new(1, -4, 0, 30)
withdrawBtn.LayoutOrder = 4
withdrawBtn.BackgroundColor3 = Color3.fromRGB(80, 40, 40)
withdrawBtn.Font = Enum.Font.GothamBold
withdrawBtn.TextSize = 13
withdrawBtn.TextColor3 = Color3.new(1, 1, 1)
withdrawBtn.Text = "Withdraw"
withdrawBtn.ZIndex = 4
withdrawBtn.Parent = coinColumn

local withdrawBtnCorner = Instance.new("UICorner")
withdrawBtnCorner.CornerRadius = UDim.new(0, 6)
withdrawBtnCorner.Parent = withdrawBtn

local withdrawOverlay = Instance.new('Frame')
withdrawOverlay.Name = 'WithdrawOverlay'
withdrawOverlay.Size = UDim2.fromScale(1, 1)
withdrawOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
withdrawOverlay.BackgroundTransparency = 0.45
withdrawOverlay.BorderSizePixel = 0
withdrawOverlay.Visible = false
withdrawOverlay.ZIndex = 30
withdrawOverlay.Active = true
withdrawOverlay.Parent = screenGui

local withdrawModal = Instance.new('Frame')
withdrawModal.Name = 'WithdrawModal'
withdrawModal.AnchorPoint = Vector2.new(0.5, 0.5)
withdrawModal.Position = UDim2.fromScale(0.5, 0.5)
withdrawModal.Size = UDim2.fromOffset(340, 250)
withdrawModal.BackgroundColor3 = Color3.fromRGB(34, 26, 26)
withdrawModal.BorderSizePixel = 0
withdrawModal.ZIndex = 31
withdrawModal.Parent = withdrawOverlay

local withdrawModalCorner = Instance.new('UICorner')
withdrawModalCorner.CornerRadius = UDim.new(0, 12)
withdrawModalCorner.Parent = withdrawModal

local withdrawModalStroke = Instance.new('UIStroke')
withdrawModalStroke.Thickness = 1
withdrawModalStroke.Color = Color3.fromRGB(90, 70, 70)
withdrawModalStroke.Parent = withdrawModal

local withdrawTitle = Instance.new('TextLabel')
withdrawTitle.BackgroundTransparency = 1
withdrawTitle.Position = UDim2.new(0, 16, 0, 14)
withdrawTitle.Size = UDim2.new(1, -32, 0, 28)
withdrawTitle.Font = Enum.Font.GothamBold
withdrawTitle.TextSize = 20
withdrawTitle.TextColor3 = Color3.new(1, 1, 1)
withdrawTitle.Text = 'Withdraw Coins'
withdrawTitle.ZIndex = 32
withdrawTitle.Parent = withdrawModal

local withdrawCoinIcon = Instance.new('ImageLabel')
withdrawCoinIcon.BackgroundTransparency = 1
withdrawCoinIcon.Position = UDim2.new(0.5, -28, 0, 52)
withdrawCoinIcon.Size = UDim2.fromOffset(56, 56)
withdrawCoinIcon.Image = ItemDefinitions.GetIcon('Coins')
withdrawCoinIcon.ZIndex = 32
withdrawCoinIcon.Parent = withdrawModal

local withdrawAmountLabel = Instance.new('TextLabel')
withdrawAmountLabel.BackgroundTransparency = 1
withdrawAmountLabel.Position = UDim2.new(0, 16, 0, 108)
withdrawAmountLabel.Size = UDim2.new(1, -32, 0, 22)
withdrawAmountLabel.Font = Enum.Font.GothamMedium
withdrawAmountLabel.TextSize = 14
withdrawAmountLabel.TextWrapped = true
withdrawAmountLabel.TextColor3 = Color3.fromRGB(255, 215, 100)
withdrawAmountLabel.Text = 'Wallet: 0 Coins'
withdrawAmountLabel.ZIndex = 32
withdrawAmountLabel.Parent = withdrawModal

local withdrawInputRow = Instance.new('Frame')
withdrawInputRow.Name = 'WithdrawInputRow'
withdrawInputRow.BackgroundTransparency = 1
withdrawInputRow.Position = UDim2.new(0, 16, 0, 136)
withdrawInputRow.Size = UDim2.new(1, -32, 0, 34)
withdrawInputRow.ZIndex = 32
withdrawInputRow.Parent = withdrawModal

local withdrawInputLayout = Instance.new('UIListLayout')
withdrawInputLayout.FillDirection = Enum.FillDirection.Horizontal
withdrawInputLayout.SortOrder = Enum.SortOrder.LayoutOrder
withdrawInputLayout.Padding = UDim.new(0, 8)
withdrawInputLayout.VerticalAlignment = Enum.VerticalAlignment.Center
withdrawInputLayout.Parent = withdrawInputRow

local withdrawAmountBox = Instance.new('TextBox')
withdrawAmountBox.Name = 'WithdrawAmountBox'
withdrawAmountBox.LayoutOrder = 1
withdrawAmountBox.Size = UDim2.fromOffset(236, 34)
withdrawAmountBox.BackgroundColor3 = Color3.fromRGB(18, 14, 14)
withdrawAmountBox.BorderSizePixel = 0
withdrawAmountBox.Font = Enum.Font.GothamMedium
withdrawAmountBox.TextSize = 14
withdrawAmountBox.TextColor3 = Color3.new(1, 1, 1)
withdrawAmountBox.PlaceholderText = 'Amount'
withdrawAmountBox.PlaceholderColor3 = Color3.fromRGB(120, 100, 100)
withdrawAmountBox.Text = ''
withdrawAmountBox.ClearTextOnFocus = false
withdrawAmountBox.ZIndex = 33
withdrawAmountBox.Parent = withdrawInputRow
Instance.new('UICorner', withdrawAmountBox).CornerRadius = UDim.new(0, 6)
local withdrawAmountBoxStroke = Instance.new('UIStroke')
withdrawAmountBoxStroke.Thickness = 1
withdrawAmountBoxStroke.Color = Color3.fromRGB(90, 70, 70)
withdrawAmountBoxStroke.Parent = withdrawAmountBox

local withdrawFillAllBtn = Instance.new('TextButton')
withdrawFillAllBtn.Name = 'WithdrawFillAllBtn'
withdrawFillAllBtn.LayoutOrder = 2
withdrawFillAllBtn.Size = UDim2.fromOffset(64, 34)
withdrawFillAllBtn.BackgroundColor3 = Color3.fromRGB(55, 70, 95)
withdrawFillAllBtn.Font = Enum.Font.GothamBold
withdrawFillAllBtn.TextSize = 13
withdrawFillAllBtn.TextColor3 = Color3.new(1, 1, 1)
withdrawFillAllBtn.Text = 'All'
withdrawFillAllBtn.ZIndex = 33
withdrawFillAllBtn.Parent = withdrawInputRow
Instance.new('UICorner', withdrawFillAllBtn).CornerRadius = UDim.new(0, 6)

local withdrawConfirmBtn = Instance.new('TextButton')
withdrawConfirmBtn.Name = 'ConfirmWithdraw'
withdrawConfirmBtn.Position = UDim2.new(0, 16, 1, -52)
withdrawConfirmBtn.Size = UDim2.new(0.5, -20, 0, 36)
withdrawConfirmBtn.BackgroundColor3 = Color3.fromRGB(80, 40, 40)
withdrawConfirmBtn.Font = Enum.Font.GothamBold
withdrawConfirmBtn.TextSize = 14
withdrawConfirmBtn.TextColor3 = Color3.new(1, 1, 1)
withdrawConfirmBtn.Text = 'Withdraw'
withdrawConfirmBtn.ZIndex = 32
withdrawConfirmBtn.Parent = withdrawModal

local withdrawConfirmCorner = Instance.new('UICorner')
withdrawConfirmCorner.CornerRadius = UDim.new(0, 8)
withdrawConfirmCorner.Parent = withdrawConfirmBtn

local withdrawCancelBtn = Instance.new('TextButton')
withdrawCancelBtn.Name = 'CancelWithdraw'
withdrawCancelBtn.Position = UDim2.new(0.5, 4, 1, -52)
withdrawCancelBtn.Size = UDim2.new(0.5, -20, 0, 36)
withdrawCancelBtn.BackgroundColor3 = Color3.fromRGB(55, 45, 45)
withdrawCancelBtn.Font = Enum.Font.GothamBold
withdrawCancelBtn.TextSize = 14
withdrawCancelBtn.TextColor3 = Color3.fromRGB(220, 200, 200)
withdrawCancelBtn.Text = 'Cancel'
withdrawCancelBtn.ZIndex = 32
withdrawCancelBtn.Parent = withdrawModal

local withdrawCancelCorner = Instance.new('UICorner')
withdrawCancelCorner.CornerRadius = UDim.new(0, 8)
withdrawCancelCorner.Parent = withdrawCancelBtn

-- END_WITHDRAW_OVERLAY

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "StatusLabel"
statusLabel.BackgroundTransparency = 1
statusLabel.Size = UDim2.new(1, 0, 0, 44)
statusLabel.LayoutOrder = 5
statusLabel.Font = Enum.Font.GothamMedium
statusLabel.TextSize = 11
statusLabel.TextWrapped = true
statusLabel.TextYAlignment = Enum.TextYAlignment.Top
statusLabel.TextXAlignment = Enum.TextXAlignment.Center
statusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
statusLabel.Text = ""
statusLabel.ZIndex = 3
statusLabel.Parent = coinColumn

local chestWrap = Instance.new("Frame")
chestWrap.Name = "ChestWrap"
chestWrap.BackgroundTransparency = 1
chestWrap.Position = UDim2.new(0, 198, 0, 0)
chestWrap.Size = UDim2.new(1, -198, 1, 0)
chestWrap.ZIndex = 3
chestWrap.Parent = upperFrame

local storageTitle = Instance.new("TextLabel")
storageTitle.Name = "StorageTitle"
storageTitle.BackgroundTransparency = 1
storageTitle.Size = UDim2.new(1, 0, 0, 22)
storageTitle.Font = Enum.Font.GothamBold
storageTitle.TextSize = 14
storageTitle.TextXAlignment = Enum.TextXAlignment.Center
storageTitle.TextColor3 = Color3.fromRGB(255, 210, 140)
storageTitle.Text = "Storage"
storageTitle.ZIndex = 4
storageTitle.Parent = chestWrap

local chestScroll = Instance.new("ScrollingFrame")
chestScroll.Name = "ChestScroll"
chestScroll.BackgroundColor3 = Color3.fromRGB(14, 11, 11)
chestScroll.BorderSizePixel = 0
chestScroll.Position = UDim2.new(0, 0, 0, 24)
chestScroll.Size = UDim2.new(1, 0, 1, -28)
chestScroll.ZIndex = 4
chestScroll.ScrollBarThickness = 8
chestScroll.ScrollBarImageColor3 = Color3.fromRGB(110, 85, 85)
chestScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
chestScroll.CanvasSize = UDim2.new()
chestScroll.ScrollingDirection = Enum.ScrollingDirection.Y
chestScroll.Parent = chestWrap

local chestScrollCorner = Instance.new("UICorner")
chestScrollCorner.CornerRadius = UDim.new(0, 8)
chestScrollCorner.Parent = chestScroll

local chestScrollPad = Instance.new("UIPadding")
chestScrollPad.PaddingTop = UDim.new(0, 6)
chestScrollPad.PaddingLeft = UDim.new(0, 6)
chestScrollPad.PaddingRight = UDim.new(0, 6)
chestScrollPad.PaddingBottom = UDim.new(0, 6)
chestScrollPad.Parent = chestScroll

local chestSlotBtns = {}
local chestUnlockStrips = {}

local chestList = Instance.new("Frame")
chestList.Name = "ChestList"
chestList.BackgroundTransparency = 1
chestList.Size = UDim2.new(1, -12, 0, 0)
chestList.AutomaticSize = Enum.AutomaticSize.Y
chestList.ZIndex = 5
chestList.Parent = chestScroll

local chestListLayout = Instance.new("UIListLayout")
chestListLayout.FillDirection = Enum.FillDirection.Vertical
chestListLayout.SortOrder = Enum.SortOrder.LayoutOrder
chestListLayout.Padding = UDim.new(0, 6)
chestListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
chestListLayout.Parent = chestList

local function makeChestSlotButton(slotIndex)
	local b = Instance.new("TextButton")
	b.Name = "ChestSlot_" .. tostring(slotIndex)
	b.Text = ""
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 10
	b.TextWrapped = true
	b.TextXAlignment = Enum.TextXAlignment.Center
	b.TextYAlignment = Enum.TextYAlignment.Center
	b.TextColor3 = Color3.fromRGB(160, 145, 130)
	b.BackgroundColor3 = Color3.fromRGB(24, 18, 18)
	b.BorderSizePixel = 0
	b.ZIndex = 6
	b.LayoutOrder = slotIndex
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
	local sk = Instance.new("UIStroke", b)
	sk.Thickness = 1
	sk.Color = Color3.fromRGB(70, 55, 40)
	chestSlotBtns[slotIndex] = b
	return b
end

for row = 1, CHEST_ROWS do
	local slotRow = Instance.new("Frame")
	slotRow.Name = "ChestRow_" .. tostring(row)
	slotRow.BackgroundTransparency = 1
	slotRow.Size = UDim2.new(1, 0, 0, 0)
	slotRow.AutomaticSize = Enum.AutomaticSize.Y
	slotRow.ZIndex = 6
	slotRow.LayoutOrder = row * 100

	local innerGrid = Instance.new("Frame")
	innerGrid.Name = "ChestRowGrid"
	innerGrid.BackgroundTransparency = 1
	innerGrid.Size = UDim2.new(1, 0, 0, 0)
	innerGrid.AutomaticSize = Enum.AutomaticSize.Y
	innerGrid.ZIndex = 5
	innerGrid.Parent = slotRow

	local rowGrid = Instance.new("UIGridLayout")
	rowGrid.CellSize = UDim2.fromOffset(CHEST_SLOT_PX, CHEST_SLOT_PX)
	rowGrid.CellPadding = UDim2.fromOffset(6, 6)
	rowGrid.FillDirectionMaxCells = CHEST_COLS
	rowGrid.SortOrder = Enum.SortOrder.LayoutOrder
	rowGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowGrid.Parent = innerGrid

	for col = 1, CHEST_COLS do
		local slotIndex = (row - 1) * CHEST_COLS + col
		local btn = makeChestSlotButton(slotIndex)
		btn.Parent = innerGrid
	end

	if row > 1 then
		local strip = Instance.new("Frame")
		strip.Name = "UnlockStrip_R" .. tostring(row)
		strip.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		strip.BackgroundTransparency = 0.12
		strip.BorderSizePixel = 0
		strip.Active = true
		strip.Position = UDim2.new(0, 0, 0, 0)
		strip.AnchorPoint = Vector2.new(0, 0)
		strip.Size = UDim2.new(1, 0, 0, CHEST_SLOT_PX)
		strip.ZIndex = 15
		Instance.new("UICorner", strip).CornerRadius = UDim.new(0, 6)
		local spad = Instance.new("UIPadding", strip)
		spad.PaddingLeft = UDim.new(0, 10)
		spad.PaddingRight = UDim.new(0, 10)

		local hLayout = Instance.new("UIListLayout")
		hLayout.FillDirection = Enum.FillDirection.Horizontal
		hLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		hLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		hLayout.Padding = UDim.new(0, 10)
		hLayout.SortOrder = Enum.SortOrder.LayoutOrder
		hLayout.Parent = strip

		local titleLbl = Instance.new("TextLabel")
		titleLbl.BackgroundTransparency = 1
		titleLbl.Size = UDim2.new(0, 170, 1, 0)
		titleLbl.Font = Enum.Font.GothamBold
		titleLbl.TextSize = 12
		titleLbl.TextColor3 = Color3.fromRGB(230, 205, 120)
		titleLbl.TextXAlignment = Enum.TextXAlignment.Left
		titleLbl.Text = "Row " .. tostring(row) .. " (locked)"
		titleLbl.LayoutOrder = 1
		titleLbl.ZIndex = 16
		titleLbl.Parent = strip

		local costLbl = Instance.new("TextLabel")
		costLbl.BackgroundTransparency = 1
		costLbl.Size = UDim2.new(0, 120, 1, 0)
		costLbl.Font = Enum.Font.GothamMedium
		costLbl.TextSize = 11
		costLbl.TextColor3 = Color3.fromRGB(190, 185, 170)
		costLbl.TextXAlignment = Enum.TextXAlignment.Left
		costLbl.LayoutOrder = 2
		costLbl.ZIndex = 16
		costLbl.Parent = strip

		local unlockBtn = Instance.new("TextButton")
		unlockBtn.Name = "UnlockBtn"
		unlockBtn.Size = UDim2.fromOffset(92, 26)
		unlockBtn.LayoutOrder = 3
		unlockBtn.BackgroundColor3 = Color3.fromRGB(68, 120, 72)
		unlockBtn.Font = Enum.Font.GothamBold
		unlockBtn.TextSize = 12
		unlockBtn.TextColor3 = Color3.new(1, 1, 1)
		unlockBtn.Text = "Unlock"
		unlockBtn.AutoButtonColor = true
		unlockBtn.ZIndex = 17
		unlockBtn.Parent = strip
		Instance.new("UICorner", unlockBtn).CornerRadius = UDim.new(0, 4)

		chestUnlockStrips[row] = {
			frame = strip,
			row = row,
			titleLabel = titleLbl,
			costLabel = costLbl,
			unlockBtn = unlockBtn,
		}

		local unlockRowCaptured = row
		unlockBtn.Activated:Connect(function()
			if not unlockBtn.Active then
				showStatus("Unlock the previous row first", true)
				return
			end
			local resOk, err = DungeonMenuNet.requestInventoryAct({ kind = "ChestUnlockRow", row = unlockRowCaptured })
			if resOk then
				clientChestUr = math.max(clientChestUr, unlockRowCaptured)
				local snap = DungeonMenuNet.getLastSnapshot()
				if snap and type(snap.profile) == "table" then
					local pr = math.clamp(math.floor(tonumber(snap.profile.chestUnlockedRows) or 1), 1, CHEST_ROWS)
					snap.profile.chestUnlockedRows = math.clamp(math.max(pr, unlockRowCaptured), 1, CHEST_ROWS)
				end
				closeAndReopenBankAfterUnlock()
			else
				local msg = err or "Unlock failed"
				if msg == "not_enough" then
					msg = "Not enough coins in wallet"
				elseif msg == "not_next_row" or msg == "bad_arg" then
					msg = "Unlock rows in order"
				elseif msg == "max_unlock" then
					msg = "All rows unlocked"
				elseif msg == "throttled" then
					msg = "Too fast — try again"
				elseif msg == "invoke_failed" then
					msg = "Could not reach server"
				end
				showStatus(msg, true)
			end
		end)

		strip.Parent = slotRow
	end

	slotRow.Parent = chestList
end

local invFrame = Instance.new("Frame")
invFrame.Name = "Inventory"
invFrame.BackgroundTransparency = 1
invFrame.Size = UDim2.new(1, 0, 0, 232)
invFrame.LayoutOrder = 2
invFrame.ZIndex = 3
invFrame.Parent = mainFrame

local bagLabel = Instance.new("TextLabel")
bagLabel.Name = "BagLabel"
bagLabel.BackgroundTransparency = 1
bagLabel.Position = UDim2.new(0, 0, 0, 0)
bagLabel.Size = UDim2.new(1, 0, 0, 32)
bagLabel.Font = Enum.Font.GothamMedium
bagLabel.TextSize = 12
bagLabel.TextWrapped = true
bagLabel.TextYAlignment = Enum.TextYAlignment.Top
bagLabel.TextXAlignment = Enum.TextXAlignment.Center
bagLabel.TextColor3 = Color3.fromRGB(200, 180, 180)
bagLabel.Text = "Your bags (scroll): tap an item, then an unlocked chest slot. Unlock more rows with coins (overlay on each locked row)."
bagLabel.ZIndex = 3
bagLabel.Parent = invFrame

local bagScroll = Instance.new("ScrollingFrame")
bagScroll.Name = "BagScroll"
bagScroll.BackgroundColor3 = Color3.fromRGB(16, 12, 12)
bagScroll.BorderSizePixel = 0
bagScroll.ScrollBarThickness = 8
bagScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
bagScroll.CanvasSize = UDim2.new()
bagScroll.Position = UDim2.new(0, 0, 0, 36)
bagScroll.Size = UDim2.new(1, 0, 1, -40)
bagScroll.ZIndex = 3
bagScroll.ScrollingDirection = Enum.ScrollingDirection.Y
bagScroll.Parent = invFrame

local bagScrollCorner = Instance.new("UICorner")
bagScrollCorner.CornerRadius = UDim.new(0, 8)
bagScrollCorner.Parent = bagScroll

local bagListLayout = Instance.new("UIGridLayout")
bagListLayout.CellSize = UDim2.fromOffset(200, 38)
bagListLayout.CellPadding = UDim2.fromOffset(8, 6)
bagListLayout.FillDirectionMaxCells = 4
bagListLayout.SortOrder = Enum.SortOrder.LayoutOrder
bagListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
bagListLayout.Parent = bagScroll

local bagPad = Instance.new("UIPadding")
bagPad.PaddingTop = UDim.new(0, 6)
bagPad.PaddingLeft = UDim.new(0, 6)
bagPad.PaddingRight = UDim.new(0, 6)
bagPad.PaddingBottom = UDim.new(0, 6)
bagPad.Parent = bagScroll

-- Hint label
local hintLabel = Instance.new("TextLabel")
hintLabel.Name = "HintLabel"
hintLabel.BackgroundTransparency = 1
hintLabel.Size = UDim2.new(1, -24, 0, 20)
hintLabel.AnchorPoint = Vector2.new(0.5, 1)
hintLabel.Position = UDim2.new(0.5, 0, 1, -8)
hintLabel.Font = Enum.Font.Gotham
hintLabel.TextSize = 12
hintLabel.TextXAlignment = Enum.TextXAlignment.Center
hintLabel.TextColor3 = Color3.fromRGB(140, 120, 120)
hintLabel.Text = "Press Escape or click outside to close"
hintLabel.ZIndex = 3
hintLabel.Parent = panel

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local function updateDisplay(wallet, inventoryCoins)
	walletLabel.Text = string.format("Wallet: %d Coins", wallet)
	bankLabel.Text = string.format('In bags: %d Coins', inventoryCoins)
end

local function showStatus(text, isError)
	statusLabel.Text = text
	if isError then
		statusLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
	else
		statusLabel.TextColor3 = Color3.fromRGB(120, 255, 120)
	end
	task.delay(2.5, function()
		if statusLabel.Text == text then
			statusLabel.Text = ""
		end
	end)
end

local function itemDisplayName(item)
	if type(item) ~= 'table' then
		return 'Item'
	end
	local name = 'Item'
	if item.name and item.name ~= '' then
		name = item.name
	elseif type(item.itemId) == 'string' and item.itemId ~= '' then
		local def = ItemDefinitions.Get(item.itemId)
		name = (def and def.DisplayName) or item.itemId
	end
	local count = math.floor(tonumber(item.count) or 1)
	if type(item.itemId) == 'string' and ItemDefinitions.IsStackable(item.itemId) and count > 1 then
		return string.format('%s (x%d)', name, count)
	end
	return name
end

local function countInventoryCoins(profile)
	local total = 0
	if type(profile) ~= 'table' or type(profile.inventory) ~= 'table' then
		return 0
	end
	for _, it in pairs(profile.inventory) do
		if type(it) == 'table' and it.itemId == 'Coins' then
			total = total + math.max(0, math.floor(tonumber(it.count) or 1))
		end
	end
	return total
end

local function collectStashCandidates(profile)
	local inv = profile.inventory or {}
	local hotbar = profile.hotbar or {}
	local equipped = profile.equipped or {}
	local inHotbar = {}
	for hi = 1, 9 do
		local u = hotbar[hi]
		if type(u) == "string" and u ~= "" then
			inHotbar[u] = true
		end
	end
	local worn = {}
	for _, u in pairs(equipped) do
		if type(u) == "string" and u ~= "" then
			worn[u] = true
		end
	end
	local list = {}
	for uuid, it in pairs(inv) do
		if type(uuid) == "string" and type(it) == "table" and not inHotbar[uuid] and not worn[uuid] then
			list[#list + 1] = { uuid = uuid, item = it }
		end
	end
	return list
end

local function syncBalances()
	local ok, result = pcall(function()
		return rfBankSync:InvokeServer()
	end)
	if ok and type(result) == "table" then
		updateDisplay(result.wallet or 0, result.inventoryCoins or 0)
	end
end

local function chestSlotUuid(slots, i)
	if type(slots) ~= "table" then
		return nil
	end
	local v = slots[i]
	if v ~= nil then
		return v
	end
	return slots[tostring(i)]
end

-- Repaint chest strips + slot interactivity from a known unlocked row count.
-- Does not read DungeonMenuNet (refreshChestSlots returns early when snapshot is missing/stale).
local function paintChestStorageForUnlockedRows(rowsUnlocked)
	local ur = math.clamp(math.floor(tonumber(rowsUnlocked) or 1), 1, CHEST_ROWS)
	for row = 2, CHEST_ROWS do
		local strip = chestUnlockStrips[row]
		if strip and strip.frame then
			if ur >= row then
				strip.frame.Visible = false
			else
				strip.frame.Visible = true
				local isNext = (ur + 1 == row)
				strip.titleLabel.Text = isNext and ("Unlock row " .. tostring(row)) or ("Row " .. tostring(row) .. " (locked)")
				local c = CHEST_ROW_UNLOCK_COST
				strip.costLabel.Text = string.format("%d coin%s", c, c == 1 and "" or "s")
				strip.unlockBtn.Active = isNext
				strip.unlockBtn.AutoButtonColor = isNext
				strip.unlockBtn.Text = isNext and "Unlock" or "Locked"
				strip.unlockBtn.BackgroundColor3 = isNext and Color3.fromRGB(68, 120, 72) or Color3.fromRGB(48, 48, 48)
			end
		end
	end
	for i = 1, CHEST_SLOT_COUNT do
		local b = chestSlotBtns[i]
		if b then
			local row = math.ceil(i / CHEST_COLS)
			if row > ur then
				b.Text = "—"
				b.TextColor3 = Color3.fromRGB(70, 62, 58)
				b.BackgroundColor3 = Color3.fromRGB(12, 10, 10)
				b.AutoButtonColor = false
				b.Active = false
			else
				b.AutoButtonColor = true
				b.Active = true
				b.BackgroundColor3 = Color3.fromRGB(24, 18, 18)
				b.Text = ""
				b.TextColor3 = Color3.fromRGB(160, 145, 130)
			end
		end
	end
end

local function refreshChestSlots(unlockedRowsFloor)
	local snap = DungeonMenuNet.getLastSnapshot()
	if not snap or type(snap.profile) ~= "table" then
		return
	end
	local p = snap.profile
	local cInv = p.chestInventory or {}
	local cSlots = p.chestSlots or {}
	-- Match slot click gates: snapshot can lag behind a successful unlock (RF/push ordering).
	local ur = effectiveChestUnlockedRows()
	if type(unlockedRowsFloor) == "number" and unlockedRowsFloor == unlockedRowsFloor then
		ur = math.clamp(math.max(ur, math.floor(unlockedRowsFloor)), 1, CHEST_ROWS)
	end
	for row = 2, CHEST_ROWS do
		local strip = chestUnlockStrips[row]
		if strip and strip.frame then
			if ur >= row then
				strip.frame.Visible = false
			else
				strip.frame.Visible = true
				local isNext = (ur + 1 == row)
				strip.titleLabel.Text = isNext and ("Unlock row " .. tostring(row)) or ("Row " .. tostring(row) .. " (locked)")
				local c = CHEST_ROW_UNLOCK_COST
				strip.costLabel.Text = string.format("%d coin%s", c, c == 1 and "" or "s")
				strip.unlockBtn.Active = isNext
				strip.unlockBtn.AutoButtonColor = isNext
				strip.unlockBtn.Text = isNext and "Unlock" or "Locked"
				strip.unlockBtn.BackgroundColor3 = isNext and Color3.fromRGB(68, 120, 72) or Color3.fromRGB(48, 48, 48)
			end
		end
	end
	for i = 1, CHEST_SLOT_COUNT do
		local b = chestSlotBtns[i]
		if b then
			local row = math.ceil(i / CHEST_COLS)
			if row > ur then
				b.Text = "—"
				b.TextColor3 = Color3.fromRGB(70, 62, 58)
				b.BackgroundColor3 = Color3.fromRGB(12, 10, 10)
				b.AutoButtonColor = false
				b.Active = false
			else
				b.AutoButtonColor = true
				b.Active = true
				b.BackgroundColor3 = Color3.fromRGB(24, 18, 18)
				local uuid = chestSlotUuid(cSlots, i)
				if type(uuid) == "string" and uuid ~= "" then
					local it = cInv[uuid]
					if type(it) == "table" then
						local nm = itemDisplayName(it)
						local c = it.count
						if type(c) == "number" and c > 1 then
							b.Text = nm .. "\n(x" .. tostring(c) .. ")"
						else
							b.Text = nm
						end
						b.TextColor3 = Types.GetRarityColor(it.rarity)
					else
						b.Text = "(?)"
						b.TextColor3 = Color3.fromRGB(200, 200, 200)
					end
				else
					b.Text = ""
					b.TextColor3 = Color3.fromRGB(160, 145, 130)
				end
			end
		end
	end
	clientChestUr = math.max(clientChestUr, ur)
end

local function refreshBagList()
	for _, ch in ipairs(bagScroll:GetChildren()) do
		if ch:IsA('TextButton') then
			ch:Destroy()
		end
	end
	local snap = DungeonMenuNet.getLastSnapshot()
	if not snap or type(snap.profile) ~= 'table' then
		return
	end
	local list = collectStashCandidates(snap.profile)
	local lo = 1
	for _, row in ipairs(list) do
		local uuid = row.uuid
		local item = row.item
		local btn = Instance.new('TextButton')
		btn.Name = 'Bag_' .. uuid
		btn.Size = UDim2.fromOffset(176, 40)
		btn.LayoutOrder = lo
		lo = lo + 1
		btn.BackgroundColor3 = Color3.fromRGB(26, 20, 20)
		btn.Font = Enum.Font.GothamMedium
		btn.TextSize = 12
		btn.TextWrapped = true
		btn.TextXAlignment = Enum.TextXAlignment.Left
		btn.Text = itemDisplayName(item)
		btn.TextColor3 = Types.GetRarityColor(item.rarity)
		btn.ZIndex = 4
		local iconId = (type(item.itemId) == 'string') and ItemDefinitions.GetIcon(item.itemId) or nil
		if type(iconId) == 'string' and iconId ~= '' then
			btn.TextXAlignment = Enum.TextXAlignment.Left
			local pad = Instance.new('UIPadding')
			pad.PaddingLeft = UDim.new(0, 36)
			pad.Parent = btn
			local icon = Instance.new('ImageLabel')
			icon.BackgroundTransparency = 1
			icon.Size = UDim2.fromOffset(28, 28)
			icon.Position = UDim2.new(0, 4, 0.5, -14)
			icon.Image = iconId
			icon.ZIndex = 5
			icon.Parent = btn
		end
		local corner = Instance.new('UICorner')
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = btn
		local stroke = Instance.new('UIStroke')
		stroke.Thickness = (selectedUuid == uuid) and 2 or 1
		stroke.Color = (selectedUuid == uuid) and Color3.fromRGB(80, 200, 120) or Color3.fromRGB(55, 45, 45)
		stroke.Parent = btn
		btn.Activated:Connect(function()
			selectedUuid = uuid
			refreshBagList()
			refreshChestSlots()
		end)
		btn.Parent = bagScroll
	end
end

local function applyWalletLabelFromSnapshot()
	local snap = DungeonMenuNet.getLastSnapshot()
	if snap and snap.profile then
		local c = math.floor(tonumber(snap.profile.currencies and snap.profile.currencies.Coins) or 0)
		local bags = countInventoryCoins(snap.profile)
		updateDisplay(c, bags)
	end
end

local function refreshChestBankUiFromCache()
	applyWalletLabelFromSnapshot()
	refreshChestSlots()
	refreshBagList()
end

local function refreshChestBankUi()
	DungeonMenuNet.requestSync()
	syncBalances()
	applyWalletLabelFromSnapshot()
	refreshChestSlots()
	refreshBagList()
end

for i = 1, CHEST_SLOT_COUNT do
	local slotIdx = i
	chestSlotBtns[i].Activated:Connect(function()
		local snap = DungeonMenuNet.getLastSnapshot()
		local p = snap and snap.profile
		local ur = effectiveChestUnlockedRows()
		if math.ceil(slotIdx / CHEST_COLS) > ur then
			showStatus("Unlock this row with coins (overlay on the row)", true)
			return
		end
		local cu = p and p.chestSlots and chestSlotUuid(p.chestSlots, slotIdx)
		if type(cu) == "string" and cu ~= "" then
			local resOk, err = DungeonMenuNet.requestInventoryAct({ kind = "ChestWithdraw", slot = slotIdx })
			if not resOk then
				local msg = err or "Withdraw failed"
				if msg == "empty" then
					msg = "Slot is empty"
				elseif msg == "locked" then
					msg = "That storage row is locked"
				elseif msg == "invoke_failed" then
					msg = "Could not reach server"
				end
				showStatus(msg, true)
				return
			end
			selectedUuid = nil
			refreshChestBankUi()
			showStatus("Returned to your bags", false)
			return
		end

		if not selectedUuid then
			showStatus("Select an item in your bags below first", true)
			return
		end

		local resOk, err = DungeonMenuNet.requestInventoryAct({ kind = "ChestDeposit", uuid = selectedUuid, slot = slotIdx })
		if resOk then
			selectedUuid = nil
			refreshChestBankUi()
			showStatus("Stored in chest", false)
		else
			local msg = err or "Could not stash"
			if msg == "equipped" then
				msg = "Unequip that item first"
			elseif msg == "not_owned" then
				msg = "Item is not in your bags"
			elseif msg == "chest_full" then
				msg = "Storage is full"
			elseif msg == "locked" then
				msg = "That storage row is locked"
			elseif msg == "throttled" then
				msg = "Too fast — try again"
			elseif msg == "invoke_failed" then
				msg = "Could not reach server"
			end
			showStatus(msg, true)
		end
	end)
end

local function setOpen(v)
	if v == open and screenGui.Enabled == v then
		return
	end
	open = v
	screenGui.Enabled = v

	if v then
		MenuMouse.acquire()
		statusLabel.Text = ""
		selectedUuid = nil
		syncBalances()
		refreshChestBankUi()
	else
		MenuMouse.release()
		selectedUuid = nil
		withdrawOverlay.Visible = false
	end
end

closeAndReopenBankAfterUnlock = function()
	if not screenGui.Enabled then
		return
	end
	-- Force-close without relying on `setOpen`'s same-state guard.
	open = false
	screenGui.Enabled = false
	MenuMouse.release()
	selectedUuid = nil
	-- Brief delay so the ScreenGui actually toggles off before reopen (mirrors manual close/reopen).
	task.delay(0.12, function()
		if not screenGui or screenGui.Parent == nil then
			return
		end
		open = true
		screenGui.Enabled = true
		MenuMouse.acquire()
		statusLabel.Text = ""
		selectedUuid = nil
		syncBalances()
		refreshChestBankUi()
		showStatus("Storage row unlocked", false)
	end)
end

---------------------------------------------------------------------------
-- Button handlers
---------------------------------------------------------------------------

local function doDepositAll()
	local ok, result = pcall(function()
		return rfBankRequest:InvokeServer({ action = 'DepositAll' })
	end)
	if not ok then showStatus('Server error - try again', true) return end
	if type(result) ~= 'table' then showStatus('Unexpected response', true) return end
	if result.ok then
		updateDisplay(result.wallet or 0, result.inventoryCoins or 0)
		DungeonMenuNet.requestSync()
		refreshChestBankUiFromCache()
		showStatus(string.format('Deposited %d Coins to wallet', result.amount or 0), false)
	else
		local err = result.err or 'unknown'
		if err == 'no_coins_in_bags' then showStatus('No coins in your bags', true)
		elseif err == 'throttled' then showStatus('Too fast - wait a moment', true)
		else showStatus('Error: ' .. err, true) end
	end
end

local function getWalletCoinBalance()
	local snap = DungeonMenuNet.getLastSnapshot()
	if snap and snap.profile and snap.profile.currencies then
		return math.floor(tonumber(snap.profile.currencies.Coins) or 0)
	end
	return 0
end

local function hideWithdrawPopup()
	withdrawOverlay.Visible = false
	withdrawAmountBox.Text = ''
end

local function showWithdrawPopup()
	local wallet = getWalletCoinBalance()
	withdrawAmountLabel.Text = string.format('Wallet: %d Coins', wallet)
	withdrawAmountBox.Text = ''
	withdrawConfirmBtn.Active = wallet > 0
	withdrawConfirmBtn.AutoButtonColor = wallet > 0
	withdrawFillAllBtn.Active = wallet > 0
	withdrawFillAllBtn.AutoButtonColor = wallet > 0
	withdrawOverlay.Visible = true
end

local function applyWithdrawResult(result)
	updateDisplay(result.wallet or 0, result.inventoryCoins or 0)
	DungeonMenuNet.requestSync()
	refreshChestBankUiFromCache()
	hideWithdrawPopup()
	showStatus(string.format('Withdrew %d Coins to your bags', result.amount or 0), false)
end

local function doWithdrawAmount(amount)
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 then
		showStatus('Enter a valid whole number', true)
		return
	end
	local ok, result = pcall(function()
		return rfBankRequest:InvokeServer({ action = 'Withdraw', amount = amount })
	end)
	if not ok then showStatus('Server error - try again', true) return end
	if type(result) ~= 'table' then showStatus('Unexpected response', true) return end
	if result.ok then
		applyWithdrawResult(result)
	else
		local err = result.err or 'unknown'
		if err == 'empty_wallet' or err == 'insufficient_wallet' then showStatus('Not enough coins in wallet', true)
		elseif err == 'invalid_amount' then showStatus('Enter a valid whole number', true)
		elseif err == 'throttled' then showStatus('Too fast - wait a moment', true)
		else showStatus('Error: ' .. err, true) end
	end
end

depositBtn.Activated:Connect(function() doDepositAll() end)
withdrawBtn.Activated:Connect(function() showWithdrawPopup() end)
withdrawCancelBtn.Activated:Connect(function() hideWithdrawPopup() end)
withdrawFillAllBtn.Activated:Connect(function()
	local wallet = getWalletCoinBalance()
	if wallet > 0 then
		withdrawAmountBox.Text = tostring(wallet)
	end
end)
withdrawConfirmBtn.Activated:Connect(function()
	doWithdrawAmount(withdrawAmountBox.Text)
end)

local function clickShouldCloseBankUIAt(screenX, screenY)
	if not open or not screenGui.Enabled then
		return false
	end
	local objs = playerGui:GetGuiObjectsAtPosition(screenX, screenY)
	for _, inst in ipairs(objs) do
		if inst:IsA("GuiObject") and inst.Visible then
			if inst == panel or inst:IsDescendantOf(panel) then
				return false
			end
			if inst == dim or inst:IsDescendantOf(dim) then
				return true
			end
			return false
		end
	end
	return false
end

closeBtn.Activated:Connect(function()
	setOpen(false)
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not open or not screenGui.Enabled then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local pos = UserInputService:GetMouseLocation()
		if clickShouldCloseBankUIAt(pos.X, pos.Y) then
			setOpen(false)
		end
		return
	end

	if input.UserInputType == Enum.UserInputType.Touch then
		local p = input.Position
		if clickShouldCloseBankUIAt(p.X, p.Y) then
			setOpen(false)
		end
		return
	end

	if input.KeyCode == Keys.CloseMenu then
		if UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if gameProcessed then
			return
		end
		setOpen(false)
	end
end)

---------------------------------------------------------------------------
-- ProximityPrompt interaction
---------------------------------------------------------------------------

local function findChestPrompt()
	local chest = game.Workspace:FindFirstChild("Treasure Chest")
	if not chest then return nil end
	for _, desc in ipairs(chest:GetDescendants()) do
		if desc:IsA("ProximityPrompt") then
			return desc
		end
	end
	return nil
end

local function connectPrompt(prompt)
	prompt.Triggered:Connect(function(triggeringPlayer)
		if triggeringPlayer == player then
			setOpen(true)
		end
	end)
end

-- Try to connect immediately
local prompt = findChestPrompt()
if prompt then
	connectPrompt(prompt)
end

-- Also watch for the chest/prompt being added later
game.Workspace.DescendantAdded:Connect(function(desc)
	if desc:IsA("ProximityPrompt") and desc.Name == "BankPrompt" then
		connectPrompt(desc)
	end
end)

print("[BankClient] ready")