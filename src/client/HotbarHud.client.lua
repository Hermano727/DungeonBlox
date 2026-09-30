local Keys = require(game:GetService("ReplicatedStorage"):WaitForChild("KeybindConfig"))
--[[
	HotbarHud — drives the diamond-tile hotbar shown bottom-center.

	2026-09-10 rework: the 4 diamond slots (background art + item icon +
	slot number) are now built ENTIRELY from this script, not hand-placed as
	individual Frames in the StarterGui.GUI.Hotbar prefab. Reasons:
	  1) A prefab-based layout needs hand-tuned pixel positions per slot,
	     which broke twice already (a decorative NumberBackdrop frame got
	     mistaken for a real slot by position-sorting, and slot 4's number
	     label silently failed to render for reasons that were never fully
	     root-caused). Generating slots from one list removes an entire class
	     of "which Studio child is actually a slot" bugs.
	  2) Direct request: slots should auto-center as a group (a UIListLayout
	     inside an AutomaticSize container -- Roblox's answer to a CSS
	     "justify-content: center" row), and adding a 5th tool slot later
	     should mean adding one entry to SLOT_NAMES, never hand-placing pixels
	     in Studio again.
	StarterGui.GUI.Hotbar itself still exists (Studio-only, never disk-synced
	-- see default.project.json syncbackRules.ignoreTrees) but is now just a
	bare anchor Frame with its background/border switched off; all visible
	content is parented under the SlotsContainer this script creates.

	Behaviour:
	  • Press 1–9 or click a slot → equip that hotbar entry + highlight selection
	  • White UIStroke on the active slot (Minecraft-style selection)
	  • Item icon rendered inside the slot's diamond tile, resolved from the
	    equipped item via ItemDefinitions.GetIconForItem (also resolves
	    procedurally generated/rolled gear that has no itemId)
	  • Hidden while SkillsPopupUI (character menu) is open
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local playerScripts = script.Parent
local DungeonMenuNet = require(playerScripts:WaitForChild("DungeonMenuNet"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ActiveEquipment = require(ReplicatedStorage:WaitForChild("ActiveEquipment"))
-- GetIconForItem (not the itemId-only GetIcon) so procedurally generated mob-drop/rolled
-- gear with no itemId (only {type, tier, tags, equipSlot}) still resolves an icon -- same
-- function/convention InventoryHud/Inventory/ItemSlot.lua already uses.
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
-- HUDLabel: the same font every other always-visible HUD readout uses (HP/Energy bar
-- text) -- see UIFonts.luau. Slot numbers use this instead of a raw Enum.Font so they
-- fall into the shared font registry like everything else.
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
-- ProfileMenus (the persistent-header Inventory/Skills/Stats/Hearthstone/Party panel)
-- also hides this hotbar while open (2026-09-13, per direct request), same as the legacy
-- SkillsPopupUI check below -- both feed into one combined visibility calc, see
-- refreshVisibility.
local ProfileMenusState = require(ReplicatedStorage:WaitForChild("ProfileMenusState"))

-- 4 fixed tool-equip slots. Add a 5th by adding one entry to each of these two
-- tables -- the slot row below rebuilds itself from #SLOT_NAMES, no pixel math.
local TOOL_SLOTS = 4
local SLOT_NAMES = { "Weapon", "Bow", "Pickaxe", "FishingSpear" }
local SLOT_INDEX_BY_NAME = { Weapon = 1, Bow = 2, Pickaxe = 3, FishingSpear = 4 }

local KEY_TO_SLOT_NAME = Keys.ToolSlot

---------------------------------------------------------------------------
-- Visual tuning constants -- everything you'd want to tweak lives here.
---------------------------------------------------------------------------

local SLOT_BG_IMAGE = "rbxassetid://105136741869654" -- ornate diamond tile art
local SLOT_WIDTH, SLOT_HEIGHT = 87, 79.5 -- diamond tile footprint -- resizing this
	-- scales the diamond art AND the item icon together, since both are sized as a
	-- fraction of this same frame (see SlotBackground/ItemIcon below). Halved from
	-- 174,159 (2026-09-10, "decrease the altogether size by maybe 2x").
local SLOT_BLEED = 12 -- diamond art overhangs its own tile by this many px (per axis,
	-- split evenly by centering) so its ornate edges don't look clipped at the frame edge --
	-- halved alongside SLOT_WIDTH/HEIGHT above so the overhang stays the same proportion
	-- of the tile instead of ballooning relative to a now-smaller diamond
local ICON_SIZE_SCALE = 0.745 -- item icon size, as a fraction of SLOT_WIDTH/HEIGHT --
	-- independent of SLOT_BLEED, so you can grow/shrink the diamond via SLOT_BLEED
	-- alone without touching the icon's size. Was 0.56, bumped 33% (2026-09-10,
	-- "increase the image size of the items inside the hotbar by 33%").
local SLOT_GAP = 30 -- horizontal gap between diamond tiles (the UIListLayout Padding --
	-- this is your one-number "distance between diamonds" control)

-- Slot number: sits ON the diamond itself, tucked into its bottom-right corner (no
-- separate badge circle behind it -- legibility instead comes from a dark text-shadow
-- clone, same trick HealthClient's HP number uses). Sized small and proportionate to
-- the now-halved SLOT_WIDTH/HEIGHT above (2026-09-10, "the numbers need to be smaller").
local NUMBER_SIZE = 14 -- px box the numeral renders in (also its max font size, TextScaled)
local NUMBER_INSET = 4 -- px from the diamond's bottom-right corner
local NUMBER_SHADOW_OFFSET = Vector2.new(1, 1) -- shadow clone's offset from the real numeral

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

local selectSlot

-- ── Locate the (now mostly empty) Hotbar anchor frame ────────────────────────

local guiFolder = playerGui:WaitForChild("GUI", 30)
if not guiFolder then
	warn("[HotbarHud] PlayerGui.GUI not found — aborting")
	return
end

local hotbarFrameOrigin = guiFolder:WaitForChild("Hotbar", 30)
if not hotbarFrameOrigin then
	warn("[HotbarHud] PlayerGui.GUI.Hotbar not found — aborting")
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
local HOTBAR_SCALE = 0.25  -- raise to make slots bigger, lower to shrink -- left alone;
	-- the "decrease by 2x" request is handled by halving SLOT_WIDTH/HEIGHT above instead.
	-- Don't also drop this, or the row shrinks 4x.
local uiScale = hotbarFrame:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
uiScale.Scale = HOTBAR_SCALE
uiScale.Parent = hotbarFrame
hotbarFrame.AnchorPoint = Vector2.new(0.5, 1)
hotbarFrame.Position = UDim2.new(0.5, 0, 1, -25) -- was -10; nudged up 15px more (2026-09-10, "move it up very slightly")

-- The Figma-exported prefab bakes ClipsDescendants=true. Harmless up top (huge empty
-- margin above the diamonds in this oversized 2070x279 frame), but SlotsContainer sits
-- flush with Hotbar's own bottom edge (see below), so anything overhanging past the
-- diamonds' bottom -- the SelectionStroke's outward thickness, the diamond art's
-- SLOT_BLEED overhang -- was getting clipped off there. Root cause, not a reposition
-- (2026-09-10, direct request: "fix the clipping ... i would prefer doing a proper fix").
hotbarFrame.ClipsDescendants = false

-- Wipe any leftover hand-placed children from the old prefab-based layout --
-- this script is now the single source of truth for what's inside Hotbar.
for _, child in ipairs(hotbarFrame:GetChildren()) do
	child:Destroy()
end

-- ── Build the slot row: an AutomaticSize container + UIListLayout ───────────
-- This is the "div-middle" equivalent: SlotsContainer hugs the width of its
-- children (AutomaticSize.X) and is itself anchored to Hotbar's center, so the
-- whole row centers as a group no matter how many slots exist. Add a slot by
-- adding a name to SLOT_NAMES/SLOT_INDEX_BY_NAME above -- nothing here is
-- keyed to a fixed slot count or a hand-placed pixel position.

-- Bottom-anchored (not centered) within hotbarFrame: hotbarFrame is still the
-- original oversized Figma export (2070x279), and centering vertically inside
-- that left a large, mostly-empty top margin above the diamonds -- reading as
-- "too far up" (2026-09-10, direct feedback). Anchoring to hotbarFrame's own
-- bottom edge instead means the diamonds always sit right against it,
-- regardless of hotbarFrame's leftover Figma-export height.
local slotsContainer = Instance.new("Frame")
slotsContainer.Name = "SlotsContainer"
slotsContainer.AnchorPoint = Vector2.new(0.5, 1)
slotsContainer.Position = UDim2.new(0.5, 0, 1, 0)
slotsContainer.Size = UDim2.new(0, 0, 0, SLOT_HEIGHT)
slotsContainer.AutomaticSize = Enum.AutomaticSize.X
slotsContainer.BackgroundTransparency = 1
slotsContainer.Parent = hotbarFrame

local slotsLayout = Instance.new("UIListLayout")
slotsLayout.FillDirection = Enum.FillDirection.Horizontal
slotsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
slotsLayout.VerticalAlignment = Enum.VerticalAlignment.Top
slotsLayout.SortOrder = Enum.SortOrder.LayoutOrder
slotsLayout.Padding = UDim.new(0, SLOT_GAP)
slotsLayout.Parent = slotsContainer

-- ── Per-slot construction ─────────────────────────────────────────────────────

local itemIcons        = {}
local selectionStrokes  = {}
local enchantBadges     = {} -- "+N" chip per slot, same look as the inventory's EnchantBadge

for i = 1, TOOL_SLOTS do
	-- Diamond tile: background art + item icon + slot number, all sized/anchored
	-- relative to this one frame. This is the object UIListLayout spaces/centers --
	-- SLOT_WIDTH/HEIGHT is the one lever that scales the diamond art and icon
	-- together (see the constants block up top).
	local diamond = Instance.new("Frame")
	diamond.Name = "HotbarSlot" .. i
	diamond.LayoutOrder = i
	diamond.Size = UDim2.fromOffset(SLOT_WIDTH, SLOT_HEIGHT)
	diamond.BackgroundTransparency = 1
	diamond.Parent = slotsContainer

	local slotBg = Instance.new("ImageLabel")
	slotBg.Name = "SlotBackground"
	slotBg.AnchorPoint = Vector2.new(0.5, 0.5)
	slotBg.Position = UDim2.new(0.5, 0, 0.5, 0)
	slotBg.Size = UDim2.new(1, SLOT_BLEED, 1, SLOT_BLEED)
	slotBg.BackgroundTransparency = 1
	slotBg.Image = SLOT_BG_IMAGE
	slotBg.ScaleType = Enum.ScaleType.Fit
	slotBg.ZIndex = 1
	slotBg.Parent = diamond

	local icon = Instance.new("ImageLabel")
	icon.Name = "ItemIcon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.new(0.5, 0, 0.46, 0)
	icon.Size = UDim2.new(ICON_SIZE_SCALE, 0, ICON_SIZE_SCALE, 0)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = ""
	icon.ZIndex = 2
	icon.Parent = diamond
	itemIcons[i] = icon

	local badge = Instance.new("TextLabel")
	badge.Name = "EnchantBadge"
	badge.Position = UDim2.fromScale(0.06, 0.08)
	badge.Size = UDim2.fromScale(0.36, 0.22)
	badge.BackgroundColor3 = Color3.fromRGB(20, 15, 12)
	badge.BackgroundTransparency = 0.15
	badge.BorderSizePixel = 0
	badge.FontFace = UIFonts.HUDLabel
	badge.TextScaled = true
	badge.TextColor3 = Color3.fromRGB(255, 220, 130)
	badge.Text = ""
	badge.Visible = false
	badge.ZIndex = 4
	Instance.new("UICorner", badge).CornerRadius = UDim.new(0.2, 0)
	local badgePad = Instance.new("UIPadding")
	badgePad.PaddingTop, badgePad.PaddingBottom = UDim.new(0.12, 0), UDim.new(0.12, 0)
	badgePad.PaddingLeft, badgePad.PaddingRight = UDim.new(0.08, 0), UDim.new(0.08, 0)
	badgePad.Parent = badge
	badge.Parent = diamond
	enchantBadges[i] = badge

	local selectionStroke = Instance.new("UIStroke")
	selectionStroke.Name = "SelectionStroke"
	selectionStroke.Thickness = 3
	selectionStroke.Color = Color3.fromRGB(255, 255, 255)
	selectionStroke.Enabled = false
	selectionStroke.Parent = diamond
	selectionStrokes[i] = selectionStroke

	-- Slot number: no badge circle -- sits directly on the diamond's bottom-right
	-- corner, legible via a dark offset text-shadow clone instead (same approach
	-- HealthClient's HP number uses) rather than a stroke or backing chip.
	-- TextScaled=true (a fixed box, not a fixed TextSize) so the glyph always
	-- fits and always renders regardless of exact box size.
	local numberShadow = Instance.new("TextLabel")
	numberShadow.Name = "NumberShadow"
	numberShadow.AnchorPoint = Vector2.new(1, 1)
	numberShadow.Position = UDim2.new(1, -NUMBER_INSET + NUMBER_SHADOW_OFFSET.X, 1, -NUMBER_INSET + NUMBER_SHADOW_OFFSET.Y)
	numberShadow.Size = UDim2.fromOffset(NUMBER_SIZE, NUMBER_SIZE)
	numberShadow.BackgroundTransparency = 1
	numberShadow.FontFace = UIFonts.HUDLabel
	numberShadow.TextScaled = true
	numberShadow.TextColor3 = Color3.new(0, 0, 0)
	numberShadow.TextTransparency = 0.35
	numberShadow.Text = tostring(i)
	numberShadow.ZIndex = 2
	numberShadow.Parent = diamond

	local numberLabel = Instance.new("TextLabel")
	numberLabel.Name = "Number"
	numberLabel.AnchorPoint = Vector2.new(1, 1)
	numberLabel.Position = UDim2.new(1, -NUMBER_INSET, 1, -NUMBER_INSET)
	numberLabel.Size = UDim2.fromOffset(NUMBER_SIZE, NUMBER_SIZE)
	numberLabel.BackgroundTransparency = 1
	numberLabel.FontFace = UIFonts.HUDLabel
	numberLabel.TextScaled = true
	numberLabel.TextColor3 = Color3.new(1, 1, 1)
	numberLabel.Text = tostring(i)
	numberLabel.ZIndex = 3
	numberLabel.Parent = diamond

	local idx = i
	diamond.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			selectSlot(idx)
		end
	end)
end

-- ── Selection state ───────────────────────────────────────────────────────────

local selectedSlot = 0
local desiredSlot = 0
local requestVersion = 0
local requestRunning = false
local selectionPending = false

local function updateSelection()
	local tool = ActiveEquipment.GetTool(player.Character)
	selectedSlot = tool and SLOT_INDEX_BY_NAME[tool:GetAttribute("DungeonEquipSlot")] or 0
	for i = 1, TOOL_SLOTS do
		selectionStrokes[i].Enabled = (i == selectedSlot)
	end
end

local function sendSelection()
	if requestRunning or not selectionPending then return end
	local snapshot = DungeonMenuNet.getLastSnapshot()
	local character = player.Character
	if not snapshot or not snapshot.profile or not character
		or not character:FindFirstChildOfClass("Humanoid")
		or not character:FindFirstChild("HumanoidRootPart")
		or not player:FindFirstChildOfClass("Backpack") then return end
	requestRunning = true
	task.spawn(function()
		repeat
			local version, character = requestVersion, player.Character
			local slotName = SLOT_NAMES[desiredSlot] or ""
			local ok, err
			for attempt = 1, 4 do
				ok, err = DungeonMenuNet.requestInventoryAct({
					kind = "SelectActiveTool", slot = slotName, character = character,
				})
				if ok or err ~= "throttled" or version ~= requestVersion then break end
				-- Back off only for the server's explicit 150ms rate limit.
				task.wait(0.16)
			end
			if version == requestVersion then
				if not ok then warn("[HotbarHud] Selection rejected:", err) end
				selectionPending = false
				break
			end
		until not player.Parent
		requestRunning = false
		updateSelection()
	end)
end

selectSlot = function(i)
	if isCharacterMenuOpen() or ProfileMenusState.IsOpen()
		or UserInputService:GetFocusedTextBox() then return end
	if i < 1 or i > TOOL_SLOTS then return end
	updateSelection()
	local current = (requestRunning or selectionPending) and desiredSlot or selectedSlot
	desiredSlot = i == current and 0 or i
	requestVersion += 1
	selectionPending = true
	sendSelection()
end

-- ── Refresh item icons from snapshot ─────────────────────────────────────────

local function refreshHud(_snap)
	updateSelection()
	sendSelection()
	local snap = DungeonMenuNet.getLastSnapshot()
	local profile = snap and snap.profile
	local inv = profile and profile.inventory or {}
	local equipped = profile and profile.equipped or {}
	for i = 1, TOOL_SLOTS do
		local icon = itemIcons[i]
		if not icon then continue end
		local uuid = equipped[SLOT_NAMES[i]]
		local it = (type(uuid) == "string" and uuid ~= "") and inv[uuid] or nil
		if it then
			icon.Image = ItemDefinitions.GetIconForItem(it)
		else
			icon.Image = ""
		end
		local ench = it and math.floor(tonumber(it.enchantLevel) or 0) or 0
		local badge = enchantBadges[i]
		if badge then
			badge.Visible = ench > 0
			badge.Text = ench > 0 and ("+" .. tostring(ench)) or ""
		end
	end
end

DungeonMenuNet.addSnapshotListener(refreshHud)

-- ── Visibility: hide while the legacy character menu OR ProfileMenus is open ─────

local popupOpen = false
local profileMenusOpen = false
local respawnProtectedUntil = 0

-- Combines both hide sources into the one Enabled flag. The respawn grace window
-- (see CharacterAdded below) always wins -- same behavior the old popup-only version
-- had, just no longer special-cased to only the popup's own Enabled signal.
local function refreshVisibility()
	if os.clock() < respawnProtectedUntil then
		hotbarScreen.Enabled = true
		return
	end
	hotbarScreen.Enabled = not (popupOpen or profileMenusOpen)
end

task.spawn(function()
	local popup
	repeat
		popup = playerGui:FindFirstChild("SkillsPopupUI", true)
		if not popup then task.wait(0.5) end
	until popup
	popupOpen = popup.Enabled
	refreshVisibility()
	popup:GetPropertyChangedSignal("Enabled"):Connect(function()
		popupOpen = popup.Enabled
		refreshVisibility()
	end)
end)

profileMenusOpen = ProfileMenusState.IsOpen()
ProfileMenusState.Subscribe(function()
	profileMenusOpen = ProfileMenusState.IsOpen()
	refreshVisibility()
end)

-- ── Character lifecycle ───────────────────────────────────────────────────────

local stopObservingCharacter
local function watchCharacter(character)
	if stopObservingCharacter then stopObservingCharacter() end
	stopObservingCharacter = ActiveEquipment.Observe(character, function()
		updateSelection()
		sendSelection()
	end)
	desiredSlot = 0
	selectionPending = false
	requestVersion += 1
	updateSelection()
end

player.CharacterRemoving:Connect(function()
	if stopObservingCharacter then stopObservingCharacter(); stopObservingCharacter = nil end
	desiredSlot = 0
	selectionPending = false
	requestVersion += 1
end)

player.CharacterAdded:Connect(function(character)
	watchCharacter(character)
	-- Roblox re-copies StarterGui.GUI on respawn; hide the fresh Hotbar copy it adds.
	local folder = playerGui:FindFirstChild("GUI")
	local newOrigin = folder and folder:FindFirstChild("Hotbar")
	if newOrigin then newOrigin.Visible = false end

	respawnProtectedUntil = os.clock() + 1
	refreshVisibility()
	task.defer(refreshHud, nil)
	-- Spawn unarmed; initialization must never invoke the same-slot toggle.
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
	-- Was isCharacterMenuOpen() only -- missed profileMenusOpen entirely, so pressing 1-9
	-- while ProfileMenus was open still silently swapped your equipped tool even though the
	-- hotbar itself was hidden (found 2026-09-13, same day as the hide-while-open feature).
	if isCharacterMenuOpen() or profileMenusOpen then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	local slotName = KEY_TO_SLOT_NAME[input.KeyCode]
	local slot = slotName and SLOT_INDEX_BY_NAME[slotName]
	if slot then
		selectSlot(slot)
	end
end)

-- ── Scroll wheel cycles slots ───────────────────────────────────────────────

UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if isCharacterMenuOpen() or profileMenusOpen then return end
	if input.UserInputType ~= Enum.UserInputType.MouseWheel then return end
	local dir = input.Position.Z > 0 and -1 or 1  -- scroll up = previous slot
	local next = selectedSlot + dir
	if next < 1 then next = TOOL_SLOTS end
	if next > TOOL_SLOTS then next = 1 end
	selectSlot(next)
end)

-- ── Boot ─────────────────────────────────────────────────────────────────────

if player.Character then watchCharacter(player.Character) end
DungeonMenuNet.start()
task.defer(refreshHud, nil)

print("[HotbarHud] ready")
