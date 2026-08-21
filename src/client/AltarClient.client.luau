local Keys = require(game:GetService("ReplicatedStorage"):WaitForChild("KeybindConfig"))
--[[
	AltarClient
	T1+ altar UI: pick center gear, sacrifice 4 matching pieces, ascend rarity once.
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Types = require(ReplicatedStorage:WaitForChild("DungeonProfileTypes"))
local MenuMouse = require(ReplicatedStorage:WaitForChild("CursorUtils"))
local DungeonMenuNet = require(script.Parent:WaitForChild("DungeonMenuNet"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local rfAltarRequest = ReplicatedStorage:WaitForChild("AltarRequest", 30)

local currentAltarTier = 1
local centerUuid = nil
local sacrificeUuids = { nil, nil, nil, nil }
local open = false

local RARITY_COLORS = {
	Common = Color3.fromRGB(205, 210, 220),
	Uncommon = Color3.fromRGB(70, 205, 105),
	Rare = Color3.fromRGB(80, 170, 255),
	Epic = Color3.fromRGB(200, 120, 255),
	Legendary = Color3.fromRGB(255, 175, 85),
}

local ERR = {
	bad_request = "Invalid altar request.",
	bad_altar_tier = "This altar cannot process that tier.",
	too_far = "Move closer to the altar.",
	in_raid = "Cannot use the altar during a dungeon run.",
	not_gear = "Only weapons and armor can be offered.",
	already_upgraded = "That item was already ascended once.",
	max_rarity = "That item is already Legendary.",
	rarity_mismatch = "Sacrifices must match the center item's rarity.",
	equipped = "Unequip items before offering them.",
	in_chest = "Withdraw items from your chest first.",
	not_owned = "Item no longer in your bags.",
	duplicate_uuid = "Each sacrifice must be a different item.",
	bad_sacrifices = "Select exactly 4 sacrifices.",
}

local function rarityColor(r)
	return RARITY_COLORS[r] or Color3.fromRGB(200, 200, 200)
end

local function itemLabel(item)
	if type(item) ~= "table" then return "Item" end
	local name = (type(item.name) == "string" and item.name ~= "") and item.name or "Gear"
	local ench = math.floor(tonumber(item.enchantLevel) or 0)
	if ench > 0 then
		return name .. " +" .. tostring(ench)
	end
	return name
end

local function getSnapshot()
	return DungeonMenuNet.getLastSnapshot()
end

local function uuidEquippedInSnap(snap, uuid)
	local p = snap and snap.profile
	if type(p) ~= "table" or type(p.equipped) ~= "table" then
		return false
	end
	for _, u in pairs(p.equipped) do
		if u == uuid then return true end
	end
	return false
end

local function uuidInChestSnap(snap, uuid)
	local p = snap and snap.profile
	if type(p) ~= "table" or type(p.chestSlots) ~= "table" then
		return false
	end
	for i = 1, Types.CHEST_SLOT_COUNT do
		if p.chestSlots[i] == uuid then return true end
	end
	return false
end

local function isEligibleGear(item, snap, uuid, asCenter)
	if type(item) ~= "table" then return false end
	if item.type ~= "Weapon" and item.type ~= "Armor" then return false end
	if math.floor(tonumber(item.tier) or 0) ~= currentAltarTier then return false end
	if uuidEquippedInSnap(snap, uuid) then return false end
	if uuidInChestSnap(snap, uuid) then return false end
	if asCenter then
		if item.altarRarityUpgraded == true then return false end
		if not Types.GetNextRarity(item.rarity) then return false end
	else
		local center = centerUuid and snap.profile.inventory[centerUuid]
		if type(center) ~= "table" then return false end
		if item.rarity ~= center.rarity then return false end
	end
	if not asCenter and uuid == centerUuid then return false end
	for _, su in ipairs(sacrificeUuids) do
		if su == uuid then return false end
	end
	return true
end

local function isPlacedSacrifice(uuid)
	for _, su in ipairs(sacrificeUuids) do
		if su == uuid then return true end
	end
	return false
end

local function collectBagCandidates(profile)
	if type(profile) ~= "table" then return {} end
	local inv = profile.inventory or {}
	local equipped = profile.equipped or {}
	-- Hotbar items stay eligible; only worn armor (profile.equipped) is hidden.
	local worn = {}
	for _, u in pairs(equipped) do
		if type(u) == "string" and u ~= "" then worn[u] = true end
	end
	local list = {}
	for uuid, it in pairs(inv) do
		if type(uuid) == "string" and type(it) == "table" and not worn[uuid] then
			list[#list + 1] = { uuid = uuid, item = it }
		end
	end
	return list
end

-- GUI
local screen = Instance.new("ScreenGui")
screen.Name = "AltarUI"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 165
screen.Enabled = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

local dim = Instance.new("TextButton", screen)
dim.Size = UDim2.fromScale(1, 1)
dim.BackgroundColor3 = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 0.55
dim.BorderSizePixel = 0
dim.Text = ""
dim.AutoButtonColor = false
dim.ZIndex = 1

local panel = Instance.new("Frame", screen)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.48, 0)
panel.Size = UDim2.fromOffset(560, 620)
panel.BackgroundColor3 = Color3.fromRGB(24, 18, 28)
panel.BorderSizePixel = 0
panel.ZIndex = 2
panel.Active = true
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)
local stroke = Instance.new("UIStroke", panel)
stroke.Color = Color3.fromRGB(120, 80, 160)
stroke.Thickness = 1.5

local titleLbl = Instance.new("TextLabel", panel)
titleLbl.Size = UDim2.new(1, -24, 0, 32)
titleLbl.Position = UDim2.new(0, 12, 0, 10)
titleLbl.BackgroundTransparency = 1
titleLbl.Font = Enum.Font.GothamBold
titleLbl.TextSize = 20
titleLbl.TextColor3 = Color3.fromRGB(230, 200, 255)
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Text = "T1 Altar"
titleLbl.ZIndex = 3

local hintLbl = Instance.new("TextLabel", panel)
hintLbl.Size = UDim2.new(1, -24, 0, 36)
hintLbl.Position = UDim2.new(0, 12, 0, 42)
hintLbl.BackgroundTransparency = 1
hintLbl.Font = Enum.Font.Gotham
hintLbl.TextWrapped = true
hintLbl.TextWrapped = true
hintLbl.TextSize = 12
hintLbl.TextColor3 = Color3.fromRGB(180, 165, 195)
hintLbl.TextXAlignment = Enum.TextXAlignment.Left
hintLbl.TextYAlignment = Enum.TextYAlignment.Top
hintLbl.Text = "Choose the piece to ascend in the center, then offer 4 more T1 weapons or armor of the same rarity. Each item can only ascend once."
hintLbl.ZIndex = 3

local slotsFrame = Instance.new("Frame", panel)
slotsFrame.BackgroundTransparency = 1
slotsFrame.Position = UDim2.new(0, 12, 0, 84)
slotsFrame.Size = UDim2.new(1, -24, 0, 170)
slotsFrame.ZIndex = 3

local function makeSlot(name, pos, size, labelText)
	local f = Instance.new("TextButton")
	f.Name = name
	f.Position = pos
	f.Size = size
	f.BackgroundColor3 = Color3.fromRGB(36, 28, 42)
	f.BorderSizePixel = 0
	f.AutoButtonColor = false
	f.Text = ""
	f.ZIndex = 4
	f.Parent = slotsFrame
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, 8)
	local s2 = Instance.new("UIStroke", f)
	s2.Color = Color3.fromRGB(90, 60, 110)
	local cap = Instance.new("TextLabel", f)
	cap.BackgroundTransparency = 1
	cap.Size = UDim2.new(1, -8, 0, 14)
	cap.Position = UDim2.new(0, 4, 0, 4)
	cap.Font = Enum.Font.GothamMedium
	cap.TextSize = 10
	cap.TextColor3 = Color3.fromRGB(150, 130, 170)
	cap.TextXAlignment = Enum.TextXAlignment.Left
	cap.Text = labelText
	cap.ZIndex = 5
	local body = Instance.new("TextLabel", f)
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Size = UDim2.new(1, -8, 1, -22)
	body.Position = UDim2.new(0, 4, 0, 18)
	body.Font = Enum.Font.GothamMedium
	body.TextSize = 11
	body.TextWrapped = true
	body.TextColor3 = Color3.new(1, 1, 1)
	body.Text = "(empty)"
	body.ZIndex = 5
	return f
end

local centerSlot = makeSlot("Center", UDim2.new(0.5, -50, 0, 8), UDim2.fromOffset(100, 72), "CENTER")
local sacSlots = {}
for i = 1, 4 do
	sacSlots[i] = makeSlot("Sac" .. i, UDim2.new(0.08 + (i - 1) * 0.23, 0, 0, 92), UDim2.fromOffset(110, 64), "SAC " .. i)
end

local scroll = Instance.new("ScrollingFrame", panel)
scroll.Position = UDim2.new(0, 8, 0, 268)
scroll.Size = UDim2.new(1, -16, 1, -340)
scroll.BackgroundColor3 = Color3.fromRGB(18, 14, 22)
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 5
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new()
scroll.ZIndex = 3
Instance.new("UICorner", scroll).CornerRadius = UDim.new(0, 8)
local list = Instance.new("UIListLayout", scroll)
list.Padding = UDim.new(0, 4)
list.SortOrder = Enum.SortOrder.LayoutOrder
local pad = Instance.new("UIPadding", scroll)
pad.PaddingTop = UDim.new(0, 6)
pad.PaddingLeft = UDim.new(0, 6)
pad.PaddingRight = UDim.new(0, 6)

local statusLbl = Instance.new("TextLabel", panel)
statusLbl.AnchorPoint = Vector2.new(0, 1)
statusLbl.Position = UDim2.new(0, 12, 1, -54)
statusLbl.Size = UDim2.new(1, -24, 0, 20)
statusLbl.BackgroundTransparency = 1
statusLbl.Font = Enum.Font.Gotham
statusLbl.TextSize = 12
statusLbl.TextColor3 = Color3.fromRGB(200, 180, 210)
statusLbl.TextXAlignment = Enum.TextXAlignment.Center
statusLbl.ZIndex = 3

local upgradeBtn = Instance.new("TextButton", panel)
upgradeBtn.AnchorPoint = Vector2.new(0.5, 1)
upgradeBtn.Position = UDim2.new(0.5, 0, 1, -12)
upgradeBtn.Size = UDim2.fromOffset(280, 38)
upgradeBtn.BackgroundColor3 = Color3.fromRGB(70, 40, 100)
upgradeBtn.BorderSizePixel = 0
upgradeBtn.Font = Enum.Font.GothamBold
upgradeBtn.TextSize = 14
upgradeBtn.TextColor3 = Color3.fromRGB(240, 220, 255)
upgradeBtn.Text = "Ascend Rarity"
upgradeBtn.ZIndex = 4
Instance.new("UICorner", upgradeBtn).CornerRadius = UDim.new(0, 8)

local closeBtn = Instance.new("TextButton", panel)
closeBtn.Size = UDim2.fromOffset(28, 28)
closeBtn.Position = UDim2.new(1, -36, 0, 8)
closeBtn.BackgroundColor3 = Color3.fromRGB(60, 40, 70)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 16
closeBtn.TextColor3 = Color3.new(1, 1, 1)
closeBtn.Text = "X"
closeBtn.ZIndex = 5
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

local rebuild
local setStatus

local function clearSelection()
	centerUuid = nil
	sacrificeUuids = { nil, nil, nil, nil }
end

local function clearScrollRows()
	for _, ch in ipairs(scroll:GetChildren()) do
		if ch:IsA("GuiButton") then ch:Destroy() end
	end
end

local function sanitizeSelection(snap)
	local inv = snap and snap.profile and snap.profile.inventory
	if type(inv) ~= "table" then
		clearSelection()
		return
	end
	if centerUuid and (not inv[centerUuid] or not isEligibleGear(inv[centerUuid], snap, centerUuid, true)) then
		clearSelection()
		return
	end
	for i = 1, 4 do
		local u = sacrificeUuids[i]
		if u then
			local it = inv[u]
			local center = centerUuid and inv[centerUuid]
			if type(it) ~= "table" or u == centerUuid or type(center) ~= "table" or it.rarity ~= center.rarity then
				sacrificeUuids[i] = nil
			end
		end
	end
end

local function setSlotVisual(slotBtn, item)
	local body = slotBtn:FindFirstChild("Body")
	if not body then return end
	if type(item) == "table" then
		body.Text = itemLabel(item)
		body.TextColor3 = rarityColor(item.rarity)
	else
		body.Text = "(empty)"
		body.TextColor3 = Color3.fromRGB(140, 130, 150)
	end
end

local function refreshSlots(snap)
	local inv = snap and snap.profile and snap.profile.inventory or {}
	setSlotVisual(centerSlot, centerUuid and inv[centerUuid] or nil)
	for i = 1, 4 do
		local u = sacrificeUuids[i]
		setSlotVisual(sacSlots[i], u and inv[u] or nil)
	end
	local center = centerUuid and inv[centerUuid]
	local ready = type(center) == "table"
	for i = 1, 4 do
		if not sacrificeUuids[i] then ready = false break end
	end
	if ready and type(center.rarity) == "string" then
		local nxt = Types.GetNextRarity(center.rarity)
		upgradeBtn.Text = string.format("Ascend: 5x %s -> 1x %s", center.rarity, nxt or "?")
		upgradeBtn.BackgroundColor3 = Color3.fromRGB(90, 50, 130)
	else
		upgradeBtn.Text = "Ascend Rarity"
		upgradeBtn.BackgroundColor3 = Color3.fromRGB(50, 35, 65)
	end
end

rebuild = function()
	clearScrollRows()
	local snap = getSnapshot()
	if not snap or type(snap.profile) ~= "table" then
		refreshSlots(snap)
		return
	end
	sanitizeSelection(snap)
	local rows = {}
	local pickingCenter = centerUuid == nil
	for _, row in ipairs(collectBagCandidates(snap.profile)) do
		local uuid, item = row.uuid, row.item
		if pickingCenter then
			if isEligibleGear(item, snap, uuid, true) then
				table.insert(rows, row)
			end
		elseif isEligibleGear(item, snap, uuid, false) and not isPlacedSacrifice(uuid) then
			table.insert(rows, row)
		end
	end
	table.sort(rows, function(a, b)
		return (a.item.name or "") < (b.item.name or "")
	end)
	for idx, row in ipairs(rows) do
		local rowF = Instance.new("TextButton", scroll)
		rowF.Name = "Row_" .. row.uuid
		rowF.Size = UDim2.new(1, 0, 0, 40)
		rowF.BackgroundColor3 = Color3.fromRGB(32, 24, 38)
		rowF.BorderSizePixel = 0
		rowF.AutoButtonColor = false
		rowF.Text = ""
		rowF.LayoutOrder = idx
		rowF.ZIndex = 4
		Instance.new("UICorner", rowF).CornerRadius = UDim.new(0, 6)
		local lbl = Instance.new("TextLabel", rowF)
		lbl.BackgroundTransparency = 1
		lbl.Size = UDim2.new(1, -12, 1, 0)
		lbl.Position = UDim2.new(0, 8, 0, 0)
		lbl.Font = Enum.Font.GothamMedium
		lbl.TextSize = 12
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Text = string.format("%s  |  %s T%d", itemLabel(row.item), row.item.rarity or "?", math.floor(tonumber(row.item.tier) or 0))
		lbl.TextColor3 = rarityColor(row.item.rarity)
		lbl.ZIndex = 5
		lbl.Active = false
		lbl.Selectable = false
		local capUuid = row.uuid
		rowF.MouseButton1Click:Connect(function()
			local snap2 = getSnapshot()
			local inv2 = snap2 and snap2.profile and snap2.profile.inventory
			local it = inv2 and inv2[capUuid]
			if not it then return end
			if centerUuid == nil then
				if not isEligibleGear(it, snap2, capUuid, true) then
					setStatus("Cannot use that as the center piece.", Color3.fromRGB(255, 120, 120))
					return
				end
				centerUuid = capUuid
				setStatus("Now choose 4 sacrifices of the same rarity.", Color3.fromRGB(200, 200, 220))
			else
				if not isEligibleGear(it, snap2, capUuid, false) then
					setStatus("Sacrifice must match center tier and rarity.", Color3.fromRGB(255, 120, 120))
					return
				end
				local placed = false
				for i = 1, 4 do
					if not sacrificeUuids[i] then
						sacrificeUuids[i] = capUuid
						placed = true
						break
					end
				end
				if not placed then
					setStatus("All sacrifice slots are full.", Color3.fromRGB(255, 120, 120))
					return
				end
				setStatus("", Color3.fromRGB(200, 180, 210))
			end
			refreshSlots(snap2)
			rebuild()
		end)
	end
	refreshSlots(snap)
end

setStatus = function(msg, color)
	statusLbl.Text = msg or ""
	statusLbl.TextColor3 = color or Color3.fromRGB(200, 180, 210)
end

local function setOpen(on, altarTier)
	if on == open and screen.Enabled == on then
		return
	end
	open = on
	if on then
		currentAltarTier = math.floor(tonumber(altarTier) or 1)
		titleLbl.Text = string.format("T%d Altar", currentAltarTier)
		hintLbl.Text = string.format("Choose the piece to ascend in the center, then offer 4 more T%d weapons or armor of the same rarity. Each item can only ascend once.", currentAltarTier)
		clearSelection()
		setStatus("")
		DungeonMenuNet.requestSync()
		rebuild()
		screen.Enabled = true
		MenuMouse.acquire()
	else
		screen.Enabled = false
		MenuMouse.release()
		clearScrollRows()
		clearSelection()
	end
end

centerSlot.MouseButton1Click:Connect(function()
	centerUuid = nil
	sacrificeUuids = { nil, nil, nil, nil }
	refreshSlots(getSnapshot())
	rebuild()
end)

for i = 1, 4 do
	sacSlots[i].MouseButton1Click:Connect(function()
		sacrificeUuids[i] = nil
		refreshSlots(getSnapshot())
		rebuild()
	end)
end

upgradeBtn.MouseButton1Click:Connect(function()
	if not centerUuid then return end
	local sacs = {}
	for i = 1, 4 do
		if not sacrificeUuids[i] then
			setStatus("Select 4 sacrifices first.", Color3.fromRGB(255, 120, 120))
			return
		end
		table.insert(sacs, sacrificeUuids[i])
	end
	setStatus("Ascending...", Color3.fromRGB(200, 200, 220))
	local ok, res = pcall(function()
		return rfAltarRequest:InvokeServer({
			action = "Upgrade",
			altarTier = currentAltarTier,
			centerUuid = centerUuid,
			sacrificeUuids = sacs,
		})
	end)
	if not ok or type(res) ~= "table" then
		setStatus("Server error.", Color3.fromRGB(255, 120, 120))
		return
	end
	if res.ok then
		setStatus("Ascension complete!", Color3.fromRGB(140, 255, 160))
		clearSelection()
		DungeonMenuNet.requestSync()
		rebuild()
	else
		-- tier_mismatch isn't in the ERR table because its text depends on
		-- currentAltarTier, which changes per altar the player opens (a
		-- static string here would always say "T1" even at a T3+ altar).
		local msg
		if res.err == "tier_mismatch" then
			msg = string.format("This altar only accepts T%d gear.", currentAltarTier)
		else
			msg = ERR[res.err] or ("Failed: " .. tostring(res.err))
		end
		setStatus(msg, Color3.fromRGB(255, 120, 120))
	end
end)

closeBtn.MouseButton1Click:Connect(function() setOpen(false) end)
dim.MouseButton1Click:Connect(function() setOpen(false) end)

UserInputService.InputBegan:Connect(function(input, gp)
	if not open or not screen.Enabled then return end
	if input.KeyCode == Keys.CloseMenu and not gp then
		setOpen(false)
	end
end)

local function resolveAltarPrompt(prompt)
	if not prompt or prompt.Name ~= "AltarPrompt" then return nil end
	local model = prompt:FindFirstAncestorOfClass("Model")
	if not model then return nil end
	local tier = math.floor(tonumber(model:GetAttribute("AltarTier")) or 1)
	return tier
end

ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
	if who ~= player then return end
	if prompt.Name ~= "AltarPrompt" then return end
	local tier = resolveAltarPrompt(prompt)
	if not tier then return end
	if open and screen.Enabled then
		setOpen(false)
		return
	end
	setOpen(true, tier)
end)

DungeonMenuNet.addSnapshotListener(function()
	if open then
		rebuild()
	end
end)

print("[AltarClient] ready")
