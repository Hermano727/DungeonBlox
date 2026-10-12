--[[
	DevMenu -- the F8 developer menu (dev-only; DevRoster). The controller: it owns the window,
	whether it's open, placement, fly and input, and hands everything else to one module per tab.

	Layout of this folder:
	  init (this)      open/close, cursor, hide-panel (explore), fly, placement, input routing
	  Shell            the window: header, collapsible grouped tab list, body, footer, floating HUD
	  Ui               look + widget helpers (Journal art, fonts, lbl/mkB/mkI/section)
	  Placement        the placement ghost, the aim point, fly physics
	  SpawnerList      the "Managed ..." column for tabs with a listType
	  Lists            mob / elite / NPC catalogues reflected off the game data
	  TabList          which tabs exist, in order
	  Tabs/<Name>      one module per tab

	A tab module returns a table:
	  key, label, group                 identity; group places it in the tab list (World, Items, ...)
	  Build(ctx) -> Frame               its section (Ui.section), built once, hidden until selected
	  listType, listTitle               optional: show the Managed column for "Mob" / "NPC" / "Zone"
	  ActionLabel(ctx) -> text, color   optional: the footer's shared button (nil = hidden)
	  OnAction(ctx)                     what that button does (a placing tab toggles placing instead)
	  places = true                     click-to-place: the button toggles placing; then
	    SetupGhost(ctx) / OnAim(ctx, pos) / OnWorldClick(ctx) / OnKey(ctx, keyCode) -> handled
	    OnPlacingChanged(ctx, placing)
	    KeepPlacingWhenClosed           placing survives closing/hiding the window (zone drawing)
	    HudLines(ctx) -> title, h1, h2  the floating help strip while placing
	  OnShow(ctx) / OnHide(ctx)         selected / deselected
	  InterceptToggle() -> handled      F8 pressed: e.g. capture mode ends itself instead

	ctx (shared by every tab; per-tab copies carry their own parent/w/h):
	  player, mouse, GE, Ui, lbl/mkB/mkI, acc, gold (legacy names the older tabs use)
	  status(msg, isErr), refreshAction(), refreshList(), refreshHud(), hudToast(seconds)
	  placing(), setPlacing(v), activeKey(), Placement (ghost, Aim, StyleDisc, PlaceDisc, Hide, Fly)
	  fly.enabled(), fly.set(v), fly.onChanged(fn)
	  panel.isOpen(), panel.setOpen(v), panel.isExplore(), panel.setExplore(v)
	  onStart()                          close the window (capture mode starting)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local DevRoster = require(ReplicatedStorage:WaitForChild("DevRoster"))
if not DevRoster.IsDev(player) then return end

local Keys = require(ReplicatedStorage:WaitForChild("KeybindConfig"))
local MenuMouse = require(ReplicatedStorage:WaitForChild("CursorUtils"))

local Ui = require(script:WaitForChild("Ui"))
local Shell = require(script:WaitForChild("Shell"))
local Placement = require(script:WaitForChild("Placement"))
local SpawnerList = require(script:WaitForChild("SpawnerList"))
local TabList = require(script:WaitForChild("TabList"))

local RMB_LOOK_BIND = "DevMenu_RMBLook"

local state = {
	open = false,
	explore = false,     -- window hidden while drawing/flying, still logically open
	placing = false,
	mouseFree = false,
	rmbLook = false,     -- right mouse held on the world: look around
	hudToastUntil = 0,
	active = nil,        -- the active tab
}
local flyListeners = {}

local shell = Shell.new(TabList)
local ctx = {
	player = player,
	mouse = player:GetMouse(),
	GE = ReplicatedStorage:WaitForChild("GameEvents", 15),
	Ui = Ui,
	lbl = Ui.lbl, mkB = Ui.mkB, mkI = Ui.mkI,
	acc = Ui.Color.Label, gold = Ui.Color.Gold,
	Placement = Placement,
}
local list = SpawnerList.new(shell.listColumn, ctx)

---------------------------------------------------------------- shared helpers

local function keepsPlacing()
	return state.placing and state.active and state.active.KeepPlacingWhenClosed == true
end

local function visualsActive()
	return state.open or state.explore or keepsPlacing() or Placement.Fly.IsEnabled()
end

local function publishOpen()
	-- ZoneDevVisuals shows the saved zone outlines while this is set.
	player:SetAttribute("DevPlacerOpen", visualsActive())
end

local function refreshHud()
	local tab = state.active
	local flyText = "F = fly (" .. (Placement.Fly.IsEnabled() and "ON" or "OFF") .. ")"
	local title, h1, h2
	if state.placing and tab and tab.HudLines then
		title, h1, h2 = tab.HudLines(ctx)
		h2 = (h2 or "") .. "    " .. flyText .. "    F8 = panel"
	elseif Placement.Fly.IsEnabled() then
		title, h1, h2 = "FLY MODE", "WASD = move    Space = up    Ctrl / C = down", flyText .. "    F8 = panel"
	end
	local visible = title ~= nil or os.clock() < state.hudToastUntil
	shell.hud:Set(visible, title or "DEV TOOLS", h1, h2, shell.status.Text, shell.status.TextColor3)
end

ctx.status = function(msg, isErr)
	shell:SetStatus(msg, isErr)
	refreshHud()
end
ctx.refreshHud = refreshHud
ctx.hudToast = function(seconds)
	state.hudToastUntil = os.clock() + seconds
	task.delay(seconds + 0.1, refreshHud)
	refreshHud()
end
ctx.activeKey = function() return state.active and state.active.key end
ctx.placing = function() return state.placing end
ctx.refreshList = function()
	local tab = state.active
	list:Refresh(tab and tab.listType, tab and tab.listTitle)
end
ctx.refreshAction = function()
	local tab = state.active
	if tab and tab.ActionLabel then
		shell:SetAction(tab.ActionLabel(ctx))
	else
		shell:SetAction(nil)
	end
end

local function refreshMouse()
	local wantLook = state.open and not state.explore and state.rmbLook
	local wantFree = state.open and not state.explore and not wantLook
	if wantLook then
		if state.mouseFree then
			MenuMouse.release()
			state.mouseFree = false
		end
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	elseif wantFree then
		if not state.mouseFree then
			MenuMouse.acquire()
			state.mouseFree = true
		end
	else
		if state.mouseFree then
			MenuMouse.release()
			state.mouseFree = false
		end
		state.rmbLook = false
	end
end
RunService:BindToRenderStep(RMB_LOOK_BIND, Enum.RenderPriority.Last.Value + 1, function()
	if state.open and not state.explore and state.rmbLook then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	end
end)

---------------------------------------------------------------- explore, placing, fly, open

local function setExplore(v)
	if not (keepsPlacing() or Placement.Fly.IsEnabled()) then
		v = false
	end
	local changed = state.explore ~= v
	state.explore = v
	shell:SetVisible(state.open and not state.explore)
	publishOpen()
	refreshMouse()
	if changed then
		ctx.status(v and "Panel hidden. F8 brings it back" or "Panel open")
	end
end

local function setPlacing(v)
	local tab = state.active
	if not (tab and tab.places) then
		v = false
	end
	if state.placing == v then
		ctx.refreshAction()
		return
	end
	state.placing = v
	if tab and tab.OnPlacingChanged then tab.OnPlacingChanged(ctx, v) end
	if v and tab.SetupGhost then
		tab.SetupGhost(ctx)
	elseif not v then
		Placement.Hide()
		setExplore(false)
	end
	ctx.refreshAction()
	publishOpen()
	refreshMouse()
	refreshHud()
end
ctx.setPlacing = setPlacing

local function setFly(v)
	Placement.Fly.SetEnabled(v)
	if not v and state.explore and not keepsPlacing() then
		setExplore(false)
	end
	publishOpen()
	for _, fn in ipairs(flyListeners) do fn(Placement.Fly.IsEnabled()) end
	ctx.status(v and "Fly ON: WASD, Space up, Ctrl/C down" or "Fly OFF")
end
ctx.fly = {
	enabled = function() return Placement.Fly.IsEnabled() end,
	set = setFly,
	onChanged = function(fn) table.insert(flyListeners, fn) end,
}
player.CharacterAdded:Connect(function()
	-- A respawn starts grounded.
	if Placement.Fly.IsEnabled() then setFly(false) end
end)

local function setOpen(v)
	state.open = v
	shell:SetVisible(v and not state.explore)
	publishOpen()
	if v then
		refreshMouse()
		return
	end
	state.rmbLook = false
	state.explore = false
	if keepsPlacing() then
		ctx.status("Panel hidden. F8 to reopen, Enter to finish")
	else
		-- Closing outside a draw exits the tool, fly included.
		setPlacing(false)
		if Placement.Fly.IsEnabled() then setFly(false) end
		ctx.status("")
	end
	refreshMouse()
end

ctx.panel = {
	isOpen = function() return state.open end,
	setOpen = setOpen,
	isExplore = function() return state.explore end,
	setExplore = setExplore,
}
ctx.onStart = function() setOpen(false) end

---------------------------------------------------------------- tabs

local tabsByKey = {}
for _, tab in ipairs(TabList) do
	local tabCtx = setmetatable({
		parent = shell.host,
		y = 0,
		w = shell:TabWidth(tab),
		h = shell.bodyH - 20,
	}, { __index = ctx })
	tab.ctx = tabCtx
	tab.section = tab.Build(tabCtx)
	tabsByKey[tab.key] = tab
end

local function selectTab(key)
	local tab = tabsByKey[key]
	if not tab or tab == state.active then return end
	setPlacing(false)
	local previous = state.active
	if previous then
		if previous.section then previous.section.Visible = false end
		if previous.OnHide then previous.OnHide(previous.ctx) end
	end
	state.active = tab
	if tab.section then tab.section.Visible = true end
	shell:SetActive(tab)
	if tab.OnShow then tab.OnShow(tab.ctx) end
	ctx.refreshAction()
	ctx.refreshList()
	publishOpen()
	refreshMouse()
end
shell.onTabClicked = selectTab

shell.actionButton.Activated:Connect(function()
	local tab = state.active
	if not tab then return end
	if tab.places then
		setPlacing(not state.placing)
	elseif tab.OnAction then
		tab.OnAction(tab.ctx)
	end
end)
shell.closeButton.Activated:Connect(function() setOpen(false) end)

---------------------------------------------------------------- per frame + input

RunService.RenderStepped:Connect(function()
	local tab = state.active
	if not (state.placing and tab) then return end
	local pos = Placement.Aim()
	if tab.OnAim then
		tab.OnAim(tab.ctx, pos)
	else
		Placement.PlaceDisc(pos)
	end
end)

local function reopen()
	ctx.refreshList()
	ctx.refreshAction()
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	-- Right-drag to look around, but only when the right-click lands on the world: a right-click
	-- on UI (a context menu) would otherwise snap the cursor to the centre.
	if input.UserInputType == Enum.UserInputType.MouseButton2 and state.open and not state.explore and not gameProcessed then
		state.rmbLook = true
		refreshMouse()
	end

	if input.KeyCode == Keys.CloseMenu then
		if state.explore then setExplore(false) return end
		if state.placing then setPlacing(false) return end
		if state.open then setOpen(false) return end
	end

	if input.KeyCode == Keys.DevPlacer and not gameProcessed then
		for _, tab in ipairs(TabList) do
			if tab.InterceptToggle and tab.InterceptToggle() then return end
		end
		if state.explore then
			setExplore(false)
			reopen()
			return
		end
		if keepsPlacing() and not state.open then
			setOpen(true)
			reopen()
			return
		end
		setOpen(not state.open)
		if state.open then reopen() end
		return
	end

	-- Dev keys ignore gameProcessed and only back off while a TextBox has focus: ProximityPrompts
	-- (E) and first-person GUI mark these keys processed, which used to swallow zone presses.
	local typing = UserInputService:GetFocusedTextBox() ~= nil
	if input.KeyCode == Keys.DevToggleFly and not typing and (state.open or Placement.Fly.IsEnabled() or keepsPlacing()) then
		setFly(not Placement.Fly.IsEnabled())
		return
	end

	local tab = state.active
	if not (state.placing and tab) then return end
	if not typing and tab.OnKey and tab.OnKey(tab.ctx, input.KeyCode) then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
	if tab.KeepPlacingWhenClosed then
		-- Hit-test the window instead of trusting gameProcessed (same reason as the keys).
		if shell:Contains(UserInputService:GetMouseLocation()) then return end
		tab.OnWorldClick(tab.ctx)
		return
	end
	if gameProcessed then return end
	tab.OnWorldClick(tab.ctx)
	setPlacing(false)
	task.delay(0.5, ctx.refreshList)
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 and state.rmbLook then
		state.rmbLook = false
		refreshMouse()
	end
end)

selectTab(TabList[1].key)
print("[DevMenu] ready -- F8 | zone draw: E = corner, corner-on-corner or Enter = finish, F = fly")
