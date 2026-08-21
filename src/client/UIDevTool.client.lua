--!strict
--  UIDevTool
--  Press KeybindConfig.UIDevTool (F6) to open a tiny overlay for
--  live-nudging ANY UI's decorative art that has called
--  UIDevTuning.Register() -- not just XpHud's branch wrap. New panels don't
--  need their own copy of this script: they register with UIDevTuning and
--  immediately show up here to cycle through.
--
--  Writes go through the registered handle's Set()/Reset(), which the
--  owning panel subscribes to and re-renders from -- this script never
--  touches another panel's GUI instances directly (see the "a panel's
--  ScreenGui belongs to that panel alone" rule in the XpHud LocalScript).
--
--  Controls (shown in the overlay too):
--    , / .          switch which registered UI is being tuned
--    ;              switch which of that UI's named targets is selected
--                    (NOT Tab -- Tab is already KeybindConfig.SkillsTab and
--                    popping that menu open every cycle got in the way)
--    Arrow keys     nudge OffsetX / OffsetY by 1px (Shift = 10px)
--    - / =          shrink / grow Scale by 0.01 (Shift = 0.05)
--    [ / ]          rotate by -5 / +5 degrees (Shift = 45)
--    Backspace      reset the selected target to its defaults
--    Enter          print a paste-ready snapshot of the selected UI to Output
--    F6 again       close the overlay (tuning stays live either way)
--
--  Dev-gated the same way DevClient (F8) is: DevRoster.IsDev(player) is
--  checked once, up front, and the whole script bails before building any
--  GUI or hooking any input if the local player isn't on the roster (or in
--  Studio). This is a UX gate, not a security boundary -- see DevRoster's
--  own header comment and the explanation in UIDevTuning for why that's
--  fine here: this tool never talks to the server (no RemoteEvents/
--  RemoteFunctions anywhere in it), so there is no privileged action for a
--  bypassed check to reach. The absolute worst case of someone forcing this
--  script to run anyway is that ONE exploited client redecorates the HUD
--  it renders for itself, locally, with no server round-trip -- nothing
--  else on the roster's other gated tools (spawner/zone placement, item
--  grants, day/night control) is true of that.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local Keybinds     = require(ReplicatedStorage:WaitForChild("KeybindConfig"))
local UIDevTuning  = require(ReplicatedStorage:WaitForChild("UIDevTuning"))
local DevRoster    = require(ReplicatedStorage:WaitForChild("DevRoster"))

local player = Players.LocalPlayer

-- Same early-return shape as DevClient (F8): build nothing, hook nothing,
-- for anyone not on the roster. A normal player's client never even
-- creates the overlay ScreenGui or connects the InputBegan listener.
if not DevRoster.IsDev(player) then
    return
end

local playerGui = player:WaitForChild("PlayerGui")

local active = false
local selectedUIIndex = 1
local selectedTargetIndex = 1
local currentUnsubscribe: (() -> ())? = nil

--------------------------------------------------------------------------------
--  Selection helpers -- work off whatever's currently registered, so this
--  script never hardcodes a panel name or target list.

local function currentId(): string?
    return UIDevTuning.List()[selectedUIIndex]
end

local function currentHandle(): UIDevTuning.Handle?
    local id = currentId()
    if id == nil then
        return nil
    end
    return UIDevTuning.GetHandle(id)
end

local function currentTargetName(): string?
    local handle = currentHandle()
    if handle == nil then
        return nil
    end
    return handle:TargetNames()[selectedTargetIndex]
end

--------------------------------------------------------------------------------
--  Overlay GUI -- its own ScreenGui, separate from any panel's own React-
--  owned one.

local gui = Instance.new("ScreenGui")
gui.Name = "UIDevToolGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Enabled = false
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(320, 210)
panel.Position = UDim2.new(1, -20, 0, 20)
panel.AnchorPoint = Vector2.new(1, 0)
panel.BackgroundColor3 = Color3.fromRGB(15, 15, 18)
panel.BackgroundTransparency = 0.1
panel.BorderSizePixel = 0
panel.Parent = gui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 8)
panelCorner.Parent = panel

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 10)
padding.PaddingBottom = UDim.new(0, 10)
padding.PaddingLeft = UDim.new(0, 12)
padding.PaddingRight = UDim.new(0, 12)
padding.Parent = panel

local readout = Instance.new("TextLabel")
readout.Name = "Readout"
readout.Size = UDim2.fromScale(1, 1)
readout.BackgroundTransparency = 1
readout.TextColor3 = Color3.fromRGB(230, 230, 230)
readout.TextXAlignment = Enum.TextXAlignment.Left
readout.TextYAlignment = Enum.TextYAlignment.Top
readout.TextSize = 15
readout.Font = Enum.Font.Code
readout.RichText = true
readout.TextWrapped = true
readout.Parent = panel

local function refreshReadout()
    local ids = UIDevTuning.List()
    if #ids == 0 then
        readout.Text = "No UI registered yet.\n\n(Panels call UIDevTuning.Register()\nat load time -- give it a moment and\nreopen with F6.)"
        return
    end

    local id = currentId() :: string
    local handle = currentHandle() :: UIDevTuning.Handle
    local names = handle:TargetNames()

    local lines = {}
    table.insert(lines, string.format("<b>[%d/%d] %s</b>", selectedUIIndex, #ids, id))
    for i, name in ipairs(names) do
        local t = handle:Get()[name]
        local marker = (i == selectedTargetIndex) and ">> " or "   "
        table.insert(lines, string.format(
            "%s%s  Scale %.2f  Offset %d,%d  Rot %d",
            marker, name, t.Scale, t.OffsetX, t.OffsetY, t.Rotation
        ))
    end
    table.insert(lines, "")
    table.insert(lines, ",/. switch UI | ; select target")
    table.insert(lines, "Arrows move | Shift=x10")
    table.insert(lines, "-/= scale | [/] rotate | Bksp reset")
    table.insert(lines, "Enter print snapshot | F6 close")
    readout.Text = table.concat(lines, "\n")
end

--------------------------------------------------------------------------------
--  Selection changes -- keep the readout subscribed to whichever handle is
--  currently selected (handles can appear after this script starts, since
--  StarterPlayerScripts load order isn't guaranteed).

local function resubscribe()
    if currentUnsubscribe then
        currentUnsubscribe()
        currentUnsubscribe = nil
    end
    local handle = currentHandle()
    if handle then
        currentUnsubscribe = handle:Subscribe(function()
            if active then
                refreshReadout()
            end
        end)
    end
end

local function cycleUI(direction: number)
    local ids = UIDevTuning.List()
    if #ids == 0 then
        return
    end
    selectedUIIndex = ((selectedUIIndex - 1 + direction) % #ids) + 1
    selectedTargetIndex = 1
    resubscribe()
end

local function cycleTarget()
    local handle = currentHandle()
    if handle == nil then
        return
    end
    local names = handle:TargetNames()
    if #names == 0 then
        return
    end
    selectedTargetIndex = (selectedTargetIndex % #names) + 1
end

--------------------------------------------------------------------------------
--  Input

local STEP = { small = 1, big = 10 }
local SCALE_STEP = { small = 0.01, big = 0.05 }
local ROT_STEP = { small = 5, big = 45 }

local function isShiftDown(): boolean
    return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
        or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

local function nudge(dx: number, dy: number)
    local handle, target = currentHandle(), currentTargetName()
    if handle == nil or target == nil then
        return
    end
    local t = handle:Get()[target]
    handle:Set(target, { OffsetX = t.OffsetX + dx, OffsetY = t.OffsetY + dy })
end

local function nudgeScale(delta: number)
    local handle, target = currentHandle(), currentTargetName()
    if handle == nil or target == nil then
        return
    end
    local t = handle:Get()[target]
    handle:Set(target, { Scale = math.clamp(t.Scale + delta, 0.05, 3) })
end

local function nudgeRotation(delta: number)
    local handle, target = currentHandle(), currentTargetName()
    if handle == nil or target == nil then
        return
    end
    local t = handle:Get()[target]
    handle:Set(target, { Rotation = (t.Rotation + delta) % 360 })
end

local function resetSelected()
    local handle, target = currentHandle(), currentTargetName()
    if handle == nil or target == nil then
        return
    end
    handle:Reset(target)
end

local function printSnapshot()
    local id, handle = currentId(), currentHandle()
    if id == nil or handle == nil then
        print("[UIDevTool] Nothing registered to print yet.")
        return
    end
    print("[UIDevTool] Paste-ready values for \"" .. id .. "\":\n" .. handle:Snapshot())
end

local function setActive(value: boolean)
    active = value
    gui.Enabled = active
    if active then
        resubscribe()
        refreshReadout()
        print("[UIDevTool] Opened -- " .. (currentId() or "nothing registered yet"))
    end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if input.UserInputType ~= Enum.UserInputType.Keyboard then
        return
    end

    if Keybinds.Matches(Keybinds.UIDevTool, input.KeyCode) then
        setActive(not active)
        return
    end

    if not active or gameProcessed then
        return
    end

    local step = isShiftDown() and STEP.big or STEP.small
    local scaleStep = isShiftDown() and SCALE_STEP.big or SCALE_STEP.small
    local rotStep = isShiftDown() and ROT_STEP.big or ROT_STEP.small

    local key = input.KeyCode
    if key == Enum.KeyCode.Comma then
        cycleUI(-1)
    elseif key == Enum.KeyCode.Period then
        cycleUI(1)
    elseif key == Enum.KeyCode.Semicolon then
        cycleTarget()
    elseif key == Enum.KeyCode.Left then
        nudge(-step, 0)
    elseif key == Enum.KeyCode.Right then
        nudge(step, 0)
    elseif key == Enum.KeyCode.Up then
        nudge(0, -step)
    elseif key == Enum.KeyCode.Down then
        nudge(0, step)
    elseif key == Enum.KeyCode.Minus then
        nudgeScale(-scaleStep)
    elseif key == Enum.KeyCode.Equals then
        nudgeScale(scaleStep)
    elseif key == Enum.KeyCode.LeftBracket then
        nudgeRotation(-rotStep)
    elseif key == Enum.KeyCode.RightBracket then
        nudgeRotation(rotStep)
    elseif key == Enum.KeyCode.Backspace then
        resetSelected()
    elseif key == Enum.KeyCode.Return then
        printSnapshot()
    else
        return
    end

    refreshReadout()
end)
