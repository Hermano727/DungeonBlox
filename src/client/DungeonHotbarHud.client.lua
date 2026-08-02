local Keys = require(game:GetService("ReplicatedStorage"):WaitForChild("KeybindConfig"))
--[[
	DungeonHotbarHud — drives the pre-built StarterGui/GUI/Hotbar Frame.

	Slot discovery: each slot is a direct child of Hotbar that contains a
	TextLabel/TextButton whose .Text is "1"–"9".

	Behaviour:
	  • Press 1–9 or click a slot → equip that hotbar entry + highlight selection
	  • White UIStroke on the active slot (Minecraft-style selection)
	  • Small item-name label added below slot number if not already present
	  • Hidden while SkillsPopupUI (character menu) is open
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local playerScripts = script.Parent
local DungeonMenuNet = require(playerScripts:WaitForChild("DungeonMenuNet"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage:WaitForChild("DungeonProfileTypes"))

local HOTBAR_SLOTS = 9

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



local KEY_TO_SLOT = Keys.HotbarSlot

local function isCharacterMenuOpen()
	local g = playerGui:FindFirstChild("SkillsPopupUI", true)
	return g and g:IsA("ScreenGui") and g.Enabled
end

local function itemDisplayName(item)
	if type(item) ~= "table" then return "" end
	local base
	if type(item.name) == "string" and item.name ~= "" then
		base = item.name
	elseif type(item.itemId) == "string" and item.itemId ~= "" then
		base = item.itemId
	else
		base = "Item"
	end
	local ench = math.floor(tonumber(item.enchantLevel) or 0)
	if ench > 0 then
		return base .. " +" .. tostring(ench)
	end
	return base
end

local function findToolByUuid(uuid)
	if type(uuid) ~= "string" or uuid == "" then return nil end
	local function scan(container)
		if not container then return nil end
		for _, c in ipairs(container:GetChildren()) do
			if c:IsA("Tool") and c:GetAttribute("DungeonItemUuid") == uuid then
				return c
			end
		end
		return nil
	end
	return scan(player:FindFirstChildOfClass("Backpack")) or scan(player.Character)
end

local function equipToolForUuid(uuid)
	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local tool = findToolByUuid(uuid)
	if tool then hum:EquipTool(tool) end
end

local function equipHotbarSlot(slotIndex)
	if slotIndex < 1 or slotIndex > HOTBAR_SLOTS then return end
	local snap = DungeonMenuNet.getLastSnapshot()
	local profile = snap and snap.profile
	if not profile then return end
	local uuid = Types.HotbarSlotUuid(profile.hotbar or {}, slotIndex)
	if type(uuid) == "string" and uuid ~= "" then
		equipToolForUuid(uuid)
	else
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then hum:UnequipTools() end
	end
end

-- ── Locate the pre-built Hotbar frame ────────────────────────────────────────

local guiFolder = playerGui:WaitForChild("GUI", 30)
if not guiFolder then
	warn("[DungeonHotbarHud] PlayerGui.GUI not found — aborting")
	return
end

local hotbarFrameOrigin = guiFolder:WaitForChild("Hotbar", 30)
if not hotbarFrameOrigin then
	warn("[DungeonHotbarHud] PlayerGui.GUI.Hotbar not found — aborting")
	return
end
-- Clone BEFORE hiding so the clone inherits Visible=true.
local hotbarFrame = hotbarFrameOrigin:Clone()
hotbarFrame.Visible = true
hotbarFrameOrigin.Visible = false  -- hide the StarterGui-tracked original

-- Wrap in a ResetOnSpawn=false ScreenGui parented directly to playerGui.
local hotbarScreen = Instance.new("ScreenGui")
hotbarScreen.Name = "DungeonHotbarScreen"
hotbarScreen.ResetOnSpawn = false
hotbarScreen.IgnoreGuiInset = true
hotbarScreen.DisplayOrder = 35
hotbarScreen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
hotbarScreen.Parent = playerGui
hotbarFrame.Parent = hotbarScreen

-- Figma export uses artboard-absolute pixel coords — reanchor to bottom-center
-- and scale down to a normal hotbar strip height.
local HOTBAR_SCALE = 0.25  -- raise to make slots bigger, lower to shrink
local uiScale = hotbarFrame:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
uiScale.Scale = HOTBAR_SCALE
uiScale.Parent = hotbarFrame
hotbarFrame.AnchorPoint = Vector2.new(0.5, 1)
hotbarFrame.Position = UDim2.new(0.5, 0, 1, -10)

-- ── Discover slot frames: child Frames sorted left→right by X position ────────
-- The number labels ("1"–"9") are siblings of the slot Frames, not children.

local slotFrames = {}

local rawSlots = {}
for _, child in ipairs(hotbarFrame:GetChildren()) do
	if child:IsA("Frame") then
		table.insert(rawSlots, child)
	end
end
table.sort(rawSlots, function(a, b)
	local aScale = a.Position.X.Scale
	local bScale = b.Position.X.Scale
	if aScale ~= bScale then return aScale < bScale end
	return a.Position.X.Offset < b.Position.X.Offset
end)
for i = 1, math.min(HOTBAR_SLOTS, #rawSlots) do
	slotFrames[i] = rawSlots[i]
end

-- ── Per-slot: ensure ItemLabel + SelectionStroke ─────────────────────────────

local itemLabels       = {}
local selectionStrokes = {}

for i = 1, HOTBAR_SLOTS do
	local f = slotFrames[i]
	if not f then
		warn(("[DungeonHotbarHud] slot %d frame not found"):format(i))
		continue
	end

	local il = f:FindFirstChild("ItemLabel")
	if not il then
		il = Instance.new("TextLabel")
		il.Name = "ItemLabel"
		il.AnchorPoint = Vector2.new(0, 1)
		il.Size = UDim2.new(1, 0, 0.38, 0)
		il.Position = UDim2.new(0, 0, 1, 0)
		il.BackgroundTransparency = 1
		il.TextColor3 = Color3.new(1, 1, 1)
		il.TextScaled = true
		il.Font = Enum.Font.GothamMedium
		il.Text = ""
		il.ZIndex = (f.ZIndex or 1) + 1
		il.Parent = f
	end
	itemLabels[i] = il

	local sk = f:FindFirstChild("SelectionStroke")
	if not sk then
		sk = Instance.new("UIStroke")
		sk.Name = "SelectionStroke"
		sk.Thickness = 3
		sk.Color = Color3.fromRGB(255, 255, 255)
		sk.Parent = f
	end
	sk.Enabled = false
	selectionStrokes[i] = sk

	local idx = i
	if f:IsA("GuiButton") then
		f.MouseButton1Click:Connect(function()
			selectSlot(idx)
		end)
	else
		f.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				selectSlot(idx)
			end
		end)
	end
end

-- ── Selection state ───────────────────────────────────────────────────────────

local selectedSlot = 0

local function updateSelection()
	for i = 1, HOTBAR_SLOTS do
		if selectionStrokes[i] then
			selectionStrokes[i].Enabled = (i == selectedSlot)
		end
	end
end

function selectSlot(i)
	selectedSlot = i
	updateSelection()
	equipHotbarSlot(i)
end

-- ── Refresh item labels from snapshot ────────────────────────────────────────

local function refreshHud(_snap)
	local snap = DungeonMenuNet.getLastSnapshot()
	local profile = snap and snap.profile
	local inv = profile and profile.inventory or {}
	local hb  = profile and profile.hotbar or {}
	for i = 1, HOTBAR_SLOTS do
		local il = itemLabels[i]
		if not il then continue end
		local uuid = Types.HotbarSlotUuid(hb, i)
		local it = (type(uuid) == "string" and uuid ~= "") and inv[uuid] or nil
		if it then
			local nm = itemDisplayName(it)
			if #nm > 12 then nm = string.sub(nm, 1, 11) .. "…" end
			il.Text = nm
		else
			il.Text = ""
		end
	end
end

DungeonMenuNet.addSnapshotListener(refreshHud)

-- ── Visibility: hide while character menu is open ────────────────────────────

local function setHotbarVisible(v)
	hotbarScreen.Enabled = v
end

local respawnProtectedUntil = 0

task.spawn(function()
	local popup
	repeat
		popup = playerGui:FindFirstChild("SkillsPopupUI", true)
		if not popup then task.wait(0.5) end
	until popup
	setHotbarVisible(not popup.Enabled)
	popup:GetPropertyChangedSignal("Enabled"):Connect(function()
		if popup.Enabled and os.clock() < respawnProtectedUntil then return end
		setHotbarVisible(not popup.Enabled)
	end)
end)

-- ── Character lifecycle ───────────────────────────────────────────────────────

-- Number labels sit on top of slot frames and may intercept clicks — hook them too.
for _, child in ipairs(hotbarFrame:GetChildren()) do
	if child:IsA("TextLabel") or child:IsA("TextButton") then
		local n = tonumber(child.Text)
		if n and n >= 1 and n <= 9 then
			child.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch then
					selectSlot(n)
				end
			end)
		end
	end
end

player.CharacterAdded:Connect(function()
	-- Roblox re-copies StarterGui.GUI on respawn; hide the fresh Hotbar copy it adds.
	local folder = playerGui:FindFirstChild("GUI")
	local newOrigin = folder and folder:FindFirstChild("Hotbar")
	if newOrigin then newOrigin.Visible = false end

	respawnProtectedUntil = os.clock() + 1
	setHotbarVisible(true)
	task.defer(refreshHud, nil)
	task.delay(0.35, function()
		selectSlot(1)
	end)
end)

-- ── Backpack refresh ──────────────────────────────────────────────────────────

local bpAddedConn, bpRemovedConn

local function hookBackpack()
	if bpAddedConn then bpAddedConn:Disconnect(); bpAddedConn = nil end
	if bpRemovedConn then bpRemovedConn:Disconnect(); bpRemovedConn = nil end
	local bp = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 30)
	if not bp then return end
	bpAddedConn   = bp.ChildAdded:Connect(function() task.defer(refreshHud, nil) end)
	bpRemovedConn = bp.ChildRemoved:Connect(function() task.defer(refreshHud, nil) end)
end

hookBackpack()
player.ChildAdded:Connect(function(ch)
	if ch:IsA("Backpack") then
		hookBackpack()
		task.defer(refreshHud, nil)
	end
end)

-- ── Key bindings 1–9 ─────────────────────────────────────────────────────────

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if UserInputService:GetFocusedTextBox() ~= nil then return end
	if isCharacterMenuOpen() then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	local slot = KEY_TO_SLOT[input.KeyCode]
	if slot then
		selectSlot(slot)
	end
end)

-- ── Scroll wheel cycles slots ───────────────────────────────────────────────

UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if isCharacterMenuOpen() then return end
	if input.UserInputType ~= Enum.UserInputType.MouseWheel then return end
	local dir = input.Position.Z > 0 and -1 or 1  -- scroll up = previous slot
	local next = selectedSlot + dir
	if next < 1 then next = HOTBAR_SLOTS end
	if next > HOTBAR_SLOTS then next = 1 end
	selectSlot(next)
end)

-- ── Boot ─────────────────────────────────────────────────────────────────────

DungeonMenuNet.start()
task.defer(refreshHud, nil)

print("[DungeonHotbarHud] ready")
