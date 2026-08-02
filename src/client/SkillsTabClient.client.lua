local Keys = require(game:GetService("ReplicatedStorage"):WaitForChild("KeybindConfig"))
-- SkillsTabClient
-- Tab toggles the Character menu: server-derived stats + bag inventory + 9-slot hotbar,
-- plus the existing Combat/Mining/Fishing XP rows (client-side SkillXPShared).
-- Click the dimmed backdrop or press Escape to close.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local MenuMouse = require(ReplicatedStorage:WaitForChild("CursorUtils"))
local playerScripts = script.Parent
local DungeonMenuNet = require(playerScripts:WaitForChild("DungeonMenuNet"))
local DungeonMenuUI = require(playerScripts:WaitForChild("DungeonMenuUI"))
local InventoryDragController = require(playerScripts:WaitForChild("InventoryDragController"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local Types = require(ReplicatedStorage:WaitForChild("DungeonProfileTypes"))
local ItemTooltip = require(playerScripts:WaitForChild("ItemTooltip"))
local DayNightConfig = require(ReplicatedStorage:WaitForChild("DayNightConfig"))

-- Roblox CoreGui binds Tab to the player list; disable it so Tab reaches this script.
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
end)
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

local player = Players.LocalPlayer

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


local playerGui = player:WaitForChild("PlayerGui")

local function getGuiFolder()
	local f = playerGui:FindFirstChild("GUI")
	if f and f:IsA("Folder") then
		return f
	end
	return playerGui
end

local combatTemplateGui = playerGui:WaitForChild("CombatXPUI")
local miningTemplateGui = playerGui:WaitForChild("MiningXPUI")
local fishingTemplateGui = playerGui:WaitForChild("FishingXPUI")

local function getXPForLevel(level)
	local lv = math.max(1, math.floor(tonumber(level) or 1))
	return 5 * (2 ^ (lv - 1))
end

local function updateBar(mainFrame, level, xp)
	local xpNeeded = getXPForLevel(level)
	local progress = math.clamp((xp or 0) / xpNeeded, 0, 1)
	local xpBackground = mainFrame:FindFirstChild("XPBackground")
	local xpFill = xpBackground and xpBackground:FindFirstChild("XPFill")
	local levelLabel = mainFrame:FindFirstChild("LevelLabel")
	local xpLabel = mainFrame:FindFirstChild("XPLabel")
	if xpFill then
		xpFill.Size = UDim2.new(progress, 0, 1, -4)
	end
	if levelLabel then
		levelLabel.Text = "Level " .. tostring(level or 1)
	end
	if xpLabel then
		xpLabel.Text = tostring(xp or 0) .. " / " .. tostring(xpNeeded) .. " XP"
	end
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SkillsPopupUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 120
screenGui.Enabled = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local open = false
local setOpenFn = nil
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.KeyCode == Keys.SkillsTab then
		if setOpenFn then
			setOpenFn(not open)
		else
			open = not open
			screenGui.Enabled = open
			if open then MenuMouse.acquire() else MenuMouse.release() end
		end
		return
	end
	if gameProcessed then return end
	if input.KeyCode == Keys.CloseMenu and open then
		if setOpenFn then setOpenFn(false) else screenGui.Enabled = false; open = false; MenuMouse.release() end
	end
end)

local dim = Instance.new("TextButton")
dim.Name = "Dim"
dim.Size = UDim2.fromScale(1, 1)
dim.Position = UDim2.new()
dim.BackgroundColor3 = Color3.new(0, 0, 0)
dim.BackgroundTransparency = 0.45
dim.BorderSizePixel = 0
dim.Text = ""
dim.AutoButtonColor = false

dim.ZIndex = 1
dim.Parent = screenGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.45, 0)
panel.Size = UDim2.fromOffset(960, 680)
panel.BackgroundColor3 = Color3.fromRGB(30, 22, 22)
panel.BorderSizePixel = 0
panel.ZIndex = 2
panel.Parent = screenGui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 12)
panelCorner.Parent = panel

local stroke = Instance.new("UIStroke")
stroke.Thickness = 1
stroke.Color = Color3.fromRGB(90, 70, 70)
stroke.Parent = panel

local title = Instance.new("TextLabel")
title.Name = "Title"
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, -24, 0, 36)
title.Position = UDim2.new(0, 12, 0, 8)
title.Font = Enum.Font.GothamBold
title.TextSize = 22
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.new(1, 1, 1)
title.Text = "Character"
title.ZIndex = 3
title.Parent = panel

local combatRow = combatTemplateGui:WaitForChild("MainFrame"):Clone()
combatRow.Name = "CombatRow"
combatRow.Visible = true

local miningRow = miningTemplateGui:WaitForChild("MainFrame"):Clone()
miningRow.Name = "MiningRow"
miningRow.Visible = true

local fishingRow = fishingTemplateGui:WaitForChild("MainFrame"):Clone()
fishingRow.Name = "FishingRow"
fishingRow.Visible = true

local uiRefs = DungeonMenuUI.createLayout(panel, { combatRow, miningRow, fishingRow })

DungeonMenuUI.setActiveBuffs(uiRefs, {})

do
	local ge = ReplicatedStorage:FindFirstChild("GameEvents")
	local abs = ge and ge:FindFirstChild("ActiveBuffsSync")
	if abs and abs:IsA("RemoteEvent") then
		abs.OnClientEvent:Connect(function(rows)
			if type(rows) == "table" then
				DungeonMenuUI.setActiveBuffs(uiRefs, rows)
			end
		end)
	else
		warn("[SkillsTabClient] ActiveBuffsSync missing — buff panel may stay empty until remote exists.")
	end
end

local HearthstoneClient = require(playerScripts:WaitForChild("HearthstoneClient"))
HearthstoneClient.init(uiRefs.hearthstoneRefs)

InventoryDragController.install(uiRefs, function()
	return DungeonMenuNet.getLastSnapshot()
end)
InventoryDragController.bindStaticSources(uiRefs)

local pendingScrollUuid = nil

local function getProfileFromSnapshot()
	local s = DungeonMenuNet.getLastSnapshot()
	return s and s.profile
end

local function snapshotItem(profile, uuid)
	if not profile or type(uuid) ~= "string" or uuid == "" then
		return nil
	end
	return profile.inventory and profile.inventory[uuid]
end

local function updateTitleHint()
	if pendingScrollUuid then
		title.Text = "Character — right-click a weapon or armor to apply scroll or orb"
	else
		title.Text = "Character"
	end
end

local function validatePendingScroll()
	if not pendingScrollUuid then
		return
	end
	local p = getProfileFromSnapshot()
	local it = snapshotItem(p, pendingScrollUuid)
	if not it or not ItemDefinitions.IsScrollApplyItem(it.itemId) then
		pendingScrollUuid = nil
	end
end

local refresh

local function scrollInventoryAct(scrollUuid, targetUuid)
	local p = getProfileFromSnapshot()
	local scroll = snapshotItem(p, scrollUuid)
	if scroll and ItemDefinitions.IsCraftingOrb(scroll.itemId) then
		return {
			kind = "ApplyCraftingOrb",
			scrollUuid = scrollUuid,
			targetUuid = targetUuid,
		}
	end
	if scroll and ItemDefinitions.IsProtectionScroll(scroll.itemId) then
		return {
			kind = "ApplyProtectionScroll",
			scrollUuid = scrollUuid,
			targetUuid = targetUuid,
		}
	end
	return {
		kind = "ApplyEnchantScroll",
		scrollUuid = scrollUuid,
		targetUuid = targetUuid,
	}
end

local menuCtx = {
	-- Right-click bag item: enchant scroll (select) or apply pending scroll to gear, else hotbar assign
	onBagSecondary = function(uuid)
		local profile = getProfileFromSnapshot()
		local item = snapshotItem(profile, uuid)
		if not item then
			return
		end

		if ItemDefinitions.IsScrollApplyItem(item.itemId) then
			if pendingScrollUuid == uuid then
				pendingScrollUuid = nil
			else
				pendingScrollUuid = uuid
			end
			updateTitleHint()
			return
		end

		if pendingScrollUuid then
			if item.type == "Weapon" or item.type == "Armor" then
				local act = scrollInventoryAct(pendingScrollUuid, uuid)
				local ok, err = DungeonMenuNet.requestInventoryAct(act)
				if ok then
					pendingScrollUuid = nil
					task.defer(refresh)
				elseif err then
					warn("[Character] ApplyEnchantScroll failed:", err)
				end
			end
			updateTitleHint()
			return
		end
	end,
	-- Right-click hotbar slot: apply scroll to gear in that slot, or clear slot
	onHotbarClear = function(i)
		i = math.floor(tonumber(i) or -1)
		if i < 1 or i > 9 then return end
		local profile = getProfileFromSnapshot()
		if not profile then
			return
		end
		local hotbar = profile.hotbar or {}
		local slotUuid = hotbarSlotUuid(hotbar, i)
		if pendingScrollUuid and type(slotUuid) == "string" and slotUuid ~= "" then
			local hotItem = snapshotItem(profile, slotUuid)
			if hotItem and (hotItem.type == "Weapon" or hotItem.type == "Armor") then
				local act = scrollInventoryAct(pendingScrollUuid, slotUuid)
				local ok, err = DungeonMenuNet.requestInventoryAct(act)
				if ok then
					pendingScrollUuid = nil
					task.defer(refresh)
				elseif err then
					warn("[Character] ApplyEnchantScroll failed:", err)
				end
				updateTitleHint()
				return
			end
		end
	end,
	onEquippedSecondary = function(slot)
		if pendingScrollUuid then
			local profile = getProfileFromSnapshot()
			if not profile then
				return
			end
			local eq = profile.equipped or {}
			local uuid = eq[slot]
			if type(uuid) ~= "string" or uuid == "" then
				return
			end
			local it = snapshotItem(profile, uuid)
			if not it or (it.type ~= "Weapon" and it.type ~= "Armor") then
				return
			end
			local ok, err = DungeonMenuNet.requestInventoryAct(scrollInventoryAct(pendingScrollUuid, uuid))
			if ok then
				pendingScrollUuid = nil
				task.defer(refresh)
			elseif err then
				warn("[Character] ApplyEnchantScroll failed:", err)
			end
			updateTitleHint()
			return
		end
		DungeonMenuNet.requestUnequip(slot)
	end,
}

local dayNightCycleStart = nil
local lastSyncRequestClock = 0
local function maybeRequestSync()
	local now = os.clock()
	if now - lastSyncRequestClock < 0.75 then
		return
	end
	lastSyncRequestClock = now
	DungeonMenuNet.requestSync()
end

local function redrawFromServer()
	local snap = DungeonMenuNet.getLastSnapshot()
	if snap then
		DungeonMenuUI.redraw(uiRefs, snap, menuCtx)
	else
		uiRefs.statsCurrency.Text = "Coins: --"
		uiRefs.statsDerived.Text =
			"No snapshot yet.\n\nThis usually means the client subscribed after the first server push.\n\nRequesting a resync..."
		maybeRequestSync()
	end
end

local function predictDayNightState()
	local cycleStart = dayNightCycleStart or workspace:GetAttribute("DayNightCycleStart")
	if type(cycleStart) ~= "number" then
		return nil
	end
	local elapsed = (workspace:GetServerTimeNow() - cycleStart) % DayNightConfig.cycleDurationSec()
	local isDay = elapsed < DayNightConfig.PHASE_DURATION_SEC
	local phaseElapsed = isDay and elapsed or (elapsed - DayNightConfig.PHASE_DURATION_SEC)
	return {
		phase = isDay and "Day" or "Night",
		clockTime = DayNightConfig.clockTimeForPhase(isDay, phaseElapsed / DayNightConfig.PHASE_DURATION_SEC),
		phaseRemaining = DayNightConfig.PHASE_DURATION_SEC - phaseElapsed,
	}
end

local function updateWorldClock(state)
	if type(state) ~= "table" then
		return
	end
	pcall(DungeonMenuUI.updateDayNight, uiRefs, state)
end

refresh = function()
	local snap = DungeonMenuNet.getLastSnapshot()
	local profile = snap and snap.profile
	local stats = profile and profile.stats
	local combat = stats and stats.combat or {}
	local mining = stats and stats.mining or {}
	local fishing = stats and stats.fishing or {}

	updateBar(combatRow, combat.level or 1, combat.xp or 0)
	updateBar(miningRow, mining.level or mining.miningLevel or 1, mining.xp or 0)
	updateBar(fishingRow, fishing.level or fishing.fishingLevel or 1, fishing.xp or 0)
	redrawFromServer()
	validatePendingScroll()
	updateTitleHint()
	updateWorldClock(predictDayNightState())
end

local function bindDayNightSync()
	local ge = ReplicatedStorage:WaitForChild("GameEvents", 60)
	if not ge then
		return
	end
	local dns = ge:WaitForChild("DayNightSync", 60)
	if not dns or not dns:IsA("RemoteEvent") then
		warn("[SkillsTabClient] DayNightSync missing — world clock may stay blank.")
		return
	end
	dns.OnClientEvent:Connect(function(state)
		if type(state.cycleStart) == "number" then
			dayNightCycleStart = state.cycleStart
		end
		updateWorldClock(state)
	end)
	updateWorldClock(predictDayNightState())
end

task.spawn(bindDayNightSync)

local function setOpen(v)
	if v == open then
		return
	end
	open = v
	screenGui.Enabled = v
	if v then
		MenuMouse.acquire()
		pcall(function()
			game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		if not DungeonMenuNet.getLastSnapshot() then
			maybeRequestSync()
		end
		refresh()
		task.defer(function()
			local ge = ReplicatedStorage:FindFirstChild("GameEvents")
			local rf = ge and ge:FindFirstChild("RequestActiveBuffs")
			if rf and rf:IsA("RemoteFunction") then
				local ok, rows = pcall(function()
					return rf:InvokeServer()
				end)
				if ok and type(rows) == "table" then
					DungeonMenuUI.setActiveBuffs(uiRefs, rows)
				end
			end
		end)
	else
		MenuMouse.release()
		pendingScrollUuid = nil
		title.Text = "Character"
		-- Any hover tooltip still showing (mouse closed menu without leaving the
		-- slot first) must be hidden -- the ScreenGui that owns it is separate.
		ItemTooltip.hide()
	end
end
setOpenFn = setOpen

DungeonMenuNet.setListener(function(_snap)
	if open then
		refresh()
	end
end)
DungeonMenuNet.start()


dim.Activated:Connect(function()
	setOpen(false)
end)

-- Tab/Escape handled by early InputBegan connection above.

task.defer(refresh)

-- Close the menu on respawn so hotbar is visible and cursor is released.
player.CharacterAdded:Connect(function()
	setOpen(false)
end)

print("[SkillsTabClient] ready")
