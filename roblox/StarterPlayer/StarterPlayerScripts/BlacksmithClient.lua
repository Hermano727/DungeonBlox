--[[
	BlacksmithClient
	Repair list UI for the Blacksmith NPC.
	Call BlacksmithClient.open(npcId) when player triggers the Blacksmith prompt.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gameEvents = ReplicatedStorage:WaitForChild("GameEvents", 10)
local npcRequest = gameEvents and gameEvents:WaitForChild("NPCRequest", 10)
local profilePush = ReplicatedStorage:WaitForChild("DungeonProfilePush", 10)

local currentNpcId = nil
local lastSnapshot  = nil

-- Subscribe to profile pushes so the UI stays current
if profilePush then
	profilePush.OnClientEvent:Connect(function(snap)
		lastSnapshot = snap
	end)
end

-- Request a fresh profile snapshot
local rfSync = ReplicatedStorage:FindFirstChild("DungeonProfileRequestSync")
local function syncSnapshot()
	if rfSync and rfSync:IsA("RemoteFunction") then
		local ok, snap = pcall(function() return rfSync:InvokeServer() end)
		if ok and snap then lastSnapshot = snap end
	end
end

---------------------------------------------------------------------------
-- Build the ScreenGui (once)
---------------------------------------------------------------------------
local screen = Instance.new("ScreenGui")
screen.Name           = "BlacksmithUI"
screen.ResetOnSpawn   = false
screen.IgnoreGuiInset = true
screen.DisplayOrder   = 160
screen.Enabled        = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent         = playerGui

local dim = Instance.new("TextButton", screen)
dim.Size = UDim2.fromScale(1,1)
dim.BackgroundColor3 = Color3.new(0,0,0)
dim.BackgroundTransparency = 0.5
dim.BorderSizePixel = 0
dim.Text = ""
dim.AutoButtonColor = false
dim.ZIndex = 1

local panel = Instance.new("Frame", screen)
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.45, 0)
panel.Size = UDim2.fromOffset(480, 480)
panel.BackgroundColor3 = Color3.fromRGB(28, 20, 20)
panel.BorderSizePixel = 0
panel.ZIndex = 2
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)
local pStroke = Instance.new("UIStroke", panel)
pStroke.Thickness = 1
pStroke.Color = Color3.fromRGB(90, 65, 50)

local titleLbl = Instance.new("TextLabel", panel)
titleLbl.Size = UDim2.new(1, -24, 0, 36)
titleLbl.Position = UDim2.new(0, 12, 0, 8)
titleLbl.BackgroundTransparency = 1
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 20
titleLbl.TextColor3 = Color3.new(1,1,1)
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Text = "Blacksmith — Repair Equipment"
titleLbl.ZIndex = 3

local coinsLbl = Instance.new("TextLabel", panel)
coinsLbl.Size = UDim2.new(1, -24, 0, 18)
coinsLbl.Position = UDim2.new(0, 12, 0, 46)
coinsLbl.BackgroundTransparency = 1
coinsLbl.Font = Enum.Font.GothamMedium
coinsLbl.TextSize = 13
coinsLbl.TextColor3 = Color3.fromRGB(255, 210, 80)
coinsLbl.TextXAlignment = Enum.TextXAlignment.Left
coinsLbl.Text = "Coins: --"
coinsLbl.ZIndex = 3

local scroll = Instance.new("ScrollingFrame", panel)
scroll.Name = "ItemList"
scroll.Position = UDim2.new(0, 8, 0, 72)
scroll.Size = UDim2.new(1, -16, 1, -130)
scroll.BackgroundColor3 = Color3.fromRGB(20, 14, 14)
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 5
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new()
scroll.ZIndex = 3
Instance.new("UICorner", scroll).CornerRadius = UDim.new(0, 8)
local listLayout = Instance.new("UIListLayout", scroll)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 4)
local listPad = Instance.new("UIPadding", scroll)
listPad.PaddingTop = UDim.new(0, 6)
listPad.PaddingLeft = UDim.new(0, 6)
listPad.PaddingRight = UDim.new(0, 6)

local repairAllBtn = Instance.new("TextButton", panel)
repairAllBtn.Name = "RepairAllBtn"
repairAllBtn.AnchorPoint = Vector2.new(0.5, 1)
repairAllBtn.Position = UDim2.new(0.5, 0, 1, -10)
repairAllBtn.Size = UDim2.fromOffset(300, 38)
repairAllBtn.BackgroundColor3 = Color3.fromRGB(70, 50, 20)
repairAllBtn.BorderSizePixel = 0
repairAllBtn.Font = Enum.Font.GothamBold
repairAllBtn.TextSize = 14
repairAllBtn.TextColor3 = Color3.fromRGB(255, 220, 100)
repairAllBtn.Text = "Repair All"
repairAllBtn.ZIndex = 4
Instance.new("UICorner", repairAllBtn).CornerRadius = UDim.new(0, 8)

local statusLbl = Instance.new("TextLabel", panel)
statusLbl.AnchorPoint = Vector2.new(0, 1)
statusLbl.Position = UDim2.new(0, 12, 1, -54)
statusLbl.Size = UDim2.new(1, -24, 0, 18)
statusLbl.BackgroundTransparency = 1
statusLbl.Font = Enum.Font.Gotham
statusLbl.TextSize = 12
statusLbl.TextColor3 = Color3.fromRGB(200, 180, 160)
statusLbl.TextXAlignment = Enum.TextXAlignment.Center
statusLbl.Text = ""
statusLbl.ZIndex = 3

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local RARITY_COLORS = {
	Common = Color3.fromRGB(205,210,220), Uncommon = Color3.fromRGB(70,205,105),
	Rare = Color3.fromRGB(80,170,255), Epic = Color3.fromRGB(200,120,255),
	Legendary = Color3.fromRGB(255,175,85),
}
local function rarityColor(r) return RARITY_COLORS[r] or Color3.fromRGB(200,200,200) end

local function repairCost(item)
	local dur = type(item.durability) == "number" and item.durability or (item.maxDurability or 0)
	local maxDur = type(item.maxDurability) == "number" and item.maxDurability or 0
	local lost = maxDur - dur
	if lost <= 0 then return 0 end
	local base = math.max(1, math.ceil(lost / 50))
	if item.broken then base = base * 3 end
	return base
end

local function isRepairable(item)
	if type(item) ~= "table" then return false end
	if item.type ~= "Weapon" and item.type ~= "Armor" and not (item.type == "Material" and item.equipSlot) then
		return false
	end
	return type(item.maxDurability) == "number" and item.maxDurability > 0
end

local function setStatus(msg, color)
	statusLbl.Text = msg
	statusLbl.TextColor3 = color or Color3.fromRGB(200,180,160)
end

---------------------------------------------------------------------------
-- Rebuild the item list
---------------------------------------------------------------------------
local function buildList()
	-- Clear existing rows
	for _, c in ipairs(scroll:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end

	if not lastSnapshot or not lastSnapshot.profile then
		return 0, 0
	end

	local profile  = lastSnapshot.profile
	local coins    = (profile.currencies and profile.currencies.Coins) or 0
	coinsLbl.Text  = "Coins: " .. tostring(math.floor(coins))

	local totalCost = 0
	local rowCount  = 0

	local items = {}
	for uuid, item in pairs(profile.inventory or {}) do
		if isRepairable(item) then
			local cost = repairCost(item)
			if cost > 0 then
				table.insert(items, { uuid = uuid, item = item, cost = cost })
			end
		end
	end
	table.sort(items, function(a,b) return (a.item.name or "") < (b.item.name or "") end)

	for idx, entry in ipairs(items) do
		local uuid, item, cost = entry.uuid, entry.item, entry.cost
		totalCost = totalCost + cost
		rowCount  = rowCount + 1

		local row = Instance.new("Frame", scroll)
		row.Name = "Row_" .. idx
		row.Size = UDim2.new(1, 0, 0, 46)
		row.BackgroundColor3 = Color3.fromRGB(30, 22, 22)
		row.BorderSizePixel = 0
		row.LayoutOrder = idx
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

		-- Item name
		local nameLbl = Instance.new("TextLabel", row)
		nameLbl.Position = UDim2.new(0, 8, 0, 4)
		nameLbl.Size = UDim2.new(0.5, 0, 0, 18)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Font = Enum.Font.GothamMedium
		nameLbl.TextSize = 13
		nameLbl.TextColor3 = rarityColor(item.rarity)
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.Text = (item.broken and "[BROKEN] " or "") .. (item.name or "Item")
		nameLbl.TextTruncate = Enum.TextTruncate.AtEnd

		-- Durability text
		local dur = item.durability or 0
		local maxDur = item.maxDurability
		local ratio = maxDur > 0 and dur / maxDur or 0
		local durColor = ratio < 0.3 and Color3.fromRGB(255,80,80) or
			(ratio < 0.5 and Color3.fromRGB(255,200,50) or Color3.fromRGB(160,160,160))
		if item.broken then durColor = Color3.fromRGB(255,60,60) end

		local durLbl = Instance.new("TextLabel", row)
		durLbl.Position = UDim2.new(0, 8, 0, 24)
		durLbl.Size = UDim2.new(0.5, 0, 0, 16)
		durLbl.BackgroundTransparency = 1
		durLbl.Font = Enum.Font.Gotham
		durLbl.TextSize = 11
		durLbl.TextColor3 = durColor
		durLbl.TextXAlignment = Enum.TextXAlignment.Left
		durLbl.Text = dur .. " / " .. maxDur .. " durability"

		-- Cost label
		local costLbl = Instance.new("TextLabel", row)
		costLbl.Position = UDim2.new(0.5, 4, 0, 4)
		costLbl.Size = UDim2.new(0, 100, 0, 18)
		costLbl.BackgroundTransparency = 1
		costLbl.Font = Enum.Font.GothamMedium
		costLbl.TextSize = 13
		costLbl.TextColor3 = Color3.fromRGB(255, 210, 80)
		costLbl.TextXAlignment = Enum.TextXAlignment.Left
		costLbl.Text = tostring(cost) .. " Coins"
		if item.broken then costLbl.Text = costLbl.Text .. " (BROKEN 3×)" end

		-- Repair button
		local repairBtn = Instance.new("TextButton", row)
		repairBtn.Position = UDim2.new(1, -80, 0.5, -16)
		repairBtn.Size = UDim2.fromOffset(72, 32)
		repairBtn.BackgroundColor3 = cost <= coins and Color3.fromRGB(40,65,30) or Color3.fromRGB(50,30,30)
		repairBtn.BorderSizePixel = 0
		repairBtn.Font = Enum.Font.GothamBold
		repairBtn.TextSize = 12
		repairBtn.TextColor3 = cost <= coins and Color3.fromRGB(140,220,100) or Color3.fromRGB(180,100,100)
		repairBtn.Text = "Repair"
		repairBtn.ZIndex = 5
		Instance.new("UICorner", repairBtn).CornerRadius = UDim.new(0, 6)

		local capturedUuid = uuid
		repairBtn.MouseButton1Click:Connect(function()
			if not npcRequest then return end
			setStatus("Repairing...", Color3.fromRGB(200,200,200))
			local ok, res = pcall(function()
				return npcRequest:InvokeServer({
					npcId    = currentNpcId,
					action   = "RepairItem",
					itemUuid = capturedUuid,
				})
			end)
			if ok and res and res.ok then
				setStatus("Repaired!", Color3.fromRGB(120,220,100))
			else
				local err = (ok and res and res.err) or "unknown error"
				setStatus("Failed: " .. tostring(err), Color3.fromRGB(220,100,100))
			end
			task.wait(0.3)
			syncSnapshot()
			buildList()
		end)
	end

	-- Repair All button text
	if rowCount > 0 then
		repairAllBtn.Text = "Repair All — " .. totalCost .. " Coins"
		repairAllBtn.Visible = true
		local canAfford = totalCost <= coins
		repairAllBtn.BackgroundColor3 = canAfford and Color3.fromRGB(70,50,20) or Color3.fromRGB(50,30,30)
		repairAllBtn.TextColor3 = canAfford and Color3.fromRGB(255,220,100) or Color3.fromRGB(180,100,100)
	else
		repairAllBtn.Text = "Nothing to repair"
		repairAllBtn.Visible = true
		repairAllBtn.BackgroundColor3 = Color3.fromRGB(35,28,28)
		repairAllBtn.TextColor3 = Color3.fromRGB(120,110,100)
	end

	return rowCount, totalCost
end

---------------------------------------------------------------------------
-- Repair All handler
---------------------------------------------------------------------------
repairAllBtn.MouseButton1Click:Connect(function()
	if not npcRequest or not currentNpcId then return end
	if not lastSnapshot then return end
	local profile = lastSnapshot.profile
	local coins = profile and profile.currencies and profile.currencies.Coins or 0
	local _, totalCost = buildList()
	if totalCost <= 0 then return end
	if totalCost > coins then
		setStatus("Not enough Coins.", Color3.fromRGB(220,100,100))
		return
	end
	setStatus("Repairing all...", Color3.fromRGB(200,200,200))
	local ok, res = pcall(function()
		return npcRequest:InvokeServer({
			npcId  = currentNpcId,
			action = "RepairAll",
		})
	end)
	if ok and res and res.ok then
		setStatus("All items repaired!", Color3.fromRGB(120,220,100))
	else
		local err = (ok and res and res.err) or "unknown error"
		setStatus("Failed: " .. tostring(err), Color3.fromRGB(220,100,100))
	end
	task.wait(0.3)
	syncSnapshot()
	buildList()
end)

---------------------------------------------------------------------------
-- Open / Close
---------------------------------------------------------------------------
local BlacksmithClient = {}

function BlacksmithClient.open(npcId)
	currentNpcId = npcId
	setStatus("")
	syncSnapshot()
	buildList()
	screen.Enabled = true
end

function BlacksmithClient.close()
	screen.Enabled = false
	statusLbl.Text = ""
end

dim.Activated:Connect(BlacksmithClient.close)

return BlacksmithClient