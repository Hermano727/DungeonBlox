--!strict
--  UIDevTool
--  Press KeybindConfig.UIDevTool (F6) to open a tiny overlay for live-nudging
--  runtime values. Slash switches which of two independent things it's
--  tuning:
--
--    UI mode    -- ANY UI's decorative art that has called
--                  UIDevTuning.Register() -- not just XpHud's branch wrap.
--                  New panels don't need their own copy of this script:
--                  they register with UIDevTuning and immediately show up
--                  here to cycle through.
--    Model mode -- the worn-armor Motor6D weld(s) ArmorVisualsService
--                  creates on YOUR OWN character (ArmorVisual_<Slot> /
--                  ArmorVisualMotor_<Slot>, welded to whichever BasePart
--                  ArmorEquipVisuals' AttachPart says -- UpperTorso by
--                  default, Head for Helm), so a prefab's C0/Size can be
--                  dialed in by eye instead of guessed at from a script.
--                  See ArmorVisualsService's header comment for why that
--                  needs hand-tuning at all: prefab pivots aren't
--                  calibrated against a live rig at import time.
--
--  Kept the name "UIDevTool" (and the F6 bind) even though Model mode isn't
--  UI -- one dev-facing tuning overlay with a mode switch beats two
--  similar-but-separate scripts drifting apart. (An earlier pass shipped
--  Model tuning as its own ArmorVisualDevTool.client.lua on F11 -- wrong on
--  two counts: F11 is the OS/browser fullscreen bind, and it duplicated
--  this entire input/readout scaffold for no reason. Folded in here
--  instead.)
--
--  UI-mode writes go through the registered handle's Set()/Reset(), which
--  the owning panel subscribes to and re-renders from -- this script never
--  touches another panel's GUI instances directly (see the "a panel's
--  ScreenGui belongs to that panel alone" rule in the XpHud LocalScript).
--  Model-mode writes touch the live Motor6D.C0 / MeshPart.Size directly --
--  there's no owning panel to go through, and per ArmorVisualsService those
--  values aren't authoritative anywhere: ApplyVisual always rebuilds at
--  identity C0 on the next equip/respawn. Print a snapshot (Enter) and
--  hand-copy the numbers into ArmorVisualsService once a slot looks right.
--
--  Controls (shown in the overlay too):
--    ;  (Semicolon)  switch between UI mode and Model mode
--    ,              UI: switch to the previous registered UI
--                   Model: switch to the previous equipped slot
--    .  (Period)    UI: switch to the next registered UI (works fine here).
--                   Model: UNUSED. It also opens chat before this script's
--                   InputBegan ever sees it -- same failure Slash hit for
--                   the mode switch -- so Model mode's "next" moved to
--                   Quote instead (see below) rather than fighting it.
--    '  (Quote)     UI: switch which of that UI's named targets is selected
--                   (NOT Tab -- Tab is already KeybindConfig.SkillsTab and
--                   popping that menu open every cycle got in the way. NOT
--                   Semicolon either -- that's the mode switch now. Slash was
--                   tried first for the mode switch and didn't work: Roblox's
--                   default chat bar grabs "/" as its open-chat shortcut
--                   before this script ever sees it.)
--                   Model: switch to the NEXT equipped slot (pairs with
--                   Comma above for previous) -- reused from being unused in
--                   Model mode once Period turned out to open chat too.
--    Y / H / G / J  Up / Down / Left / Right -- UI: nudge OffsetX / OffsetY by
--                   1px (Shift = 10px). Model: nudge local X/Y by 0.02 studs
--                   (Shift = 0.2). Arranged like WASD one row down (H is the
--                   "S": Y above it is up, G/J either side are left/right) --
--                   deliberately NOT the arrow keys, which this game's camera
--                   also pans on, fighting with the panel every press.
--    N / M          Model only: nudge local Z (depth) by 0.02 studs
--                   (Shift = 0.2). Was Page Up/Page Down -- also intercepted
--                   by something else in this game before reaching this
--                   script (same "gameProcessed" symptom as Period/Slash) --
--                   moved to the letter row next to G/Y/H/J's cluster instead.
--    U / I          Model only: pitch -5 / +5 degrees (Shift = 45)
--    K / L          Model only: roll -5 / +5 degrees (Shift = 45)
--                   (Not O/P -- P is KeybindConfig's Party menu key and ate
--                   the input the same way Period/Page Up/Down did.)
--    - / =          UI: shrink/grow Scale by 0.01 (Shift = 0.05)
--                   Model: shrink/grow uniform mesh scale by 2% (Shift = 10%)
--    [ / ]          UI: rotate by -5 / +5 degrees (Shift = 45)
--                   Model: yaw -5 / +5 degrees (Shift = 45)
--    Backspace      Reset the selected target/slot to its defaults
--    Enter          Print a paste-ready snapshot of the selection to Output
--    F6 again       Close the overlay (tuning stays live either way)
--
--  Dev-gated the same way DevClient (F8) is: DevRoster.IsDev(player) is
--  checked once, up front, and the whole script bails before building any
--  GUI or hooking any input if the local player isn't on the roster (or in
--  Studio). This is a UX gate, not a security boundary -- see DevRoster's
--  own header comment and the explanation in UIDevTuning for why that's
--  fine here: neither mode talks to the server (no RemoteEvents/
--  RemoteFunctions anywhere in this script), so there is no privileged
--  action for a bypassed check to reach. The absolute worst case of someone
--  forcing this script to run anyway is that ONE exploited client
--  redecorates the HUD or its own worn armor, locally, with no server
--  round-trip -- nothing else on the roster's other gated tools (spawner/
--  zone placement, item grants, day/night control) is true of that.

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
local mode: "UI" | "Model" = "UI"

-- UI-mode selection state.
local selectedUIIndex = 1
local selectedTargetIndex = 1
local currentUnsubscribe: (() -> ())? = nil

-- Model-mode selection + per-slot tuning state, keyed by slot name
-- ("Chest", ...). Recomputed into the live Motor6D.C0 on every change
-- rather than nudging C0 in place, so rotation never skews which local
-- axis the arrow keys move along.
local selectedSlotIndex = 1
type SlotState = { Pos: Vector3, YawDeg: number, PitchDeg: number, RollDeg: number, Scale: number, BaseSize: Vector3 }
local stateBySlot: { [string]: SlotState } = {}

--------------------------------------------------------------------------------
--  UI-mode helpers -- work off whatever's currently registered, so this
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
--  Model-mode helpers.

local function getCharacter(): Model?
    return player.Character
end

-- Every slot with BOTH a live ArmorVisual_<Slot> part and its Motor6D right now --
-- sorted for a stable, deterministic cycling order. Searches the WHOLE character
-- (recursive), not just UpperTorso -- ArmorEquipVisuals' AttachPart can weld a slot
-- to Head or any other BasePart, so Motor6Ds no longer all live under one parent.
local function scanSlots(): { string }
    local char = getCharacter()
    if not char then
        return {}
    end
    local slots = {}
    for _, inst in ipairs(char:GetDescendants()) do
        if inst:IsA("Motor6D") then
            local slot = inst.Name:match("^ArmorVisualMotor_(.+)$")
            if slot and char:FindFirstChild("ArmorVisual_" .. slot, true) then
                table.insert(slots, slot)
            end
        end
    end
    table.sort(slots)
    return slots
end

local function currentSlot(): string?
    local slots = scanSlots()
    if #slots == 0 then
        return nil
    end
    selectedSlotIndex = math.clamp(selectedSlotIndex, 1, #slots)
    return slots[selectedSlotIndex]
end

local function currentSlotParts(): (BasePart?, Motor6D?)
    local slot = currentSlot()
    local char = getCharacter()
    if not slot or not char then
        return nil, nil
    end
    local part = char:FindFirstChild("ArmorVisual_" .. slot, true)
    local motor = char:FindFirstChild("ArmorVisualMotor_" .. slot, true)
    return (part :: any), (motor :: any)
end

-- Rough per-slot STARTING Y offset (studs, in the slot's OWN attach part's local
-- space -- the same space Motor6D.C0 operates in), so a freshly-cycled-to slot lands
-- roughly where it belongs instead of at its attach part's own origin every time.
-- Measured directly off StarterPlayer.StarterCharacter's own (custom-scaled) rig via
-- Studio, not guessed -- local offset from UpperTorso's CFrame to each body part's
-- center:
--   Head                       ( 0.00,  0.71, -0.12)
--   Boots (L/R foot, averaged) ( 0.01, -4.09, -0.15)
--   Legs  (L/R upper leg, avg) ( 0.00, -1.93,  0.03)
-- Chest and Helm need no entry -- both are welded directly to their own attach part
-- (UpperTorso / Head respectively, see ArmorEquipVisuals' AttachPart), so identity IS
-- the right starting point for them; Helm's entry lived here only back when
-- everything welded to UpperTorso and Helm needed to walk up to head height on its
-- own. Legs/Boots are currently unregistered in ArmorEquipVisuals (see its header
-- comment -- rigid single-bone welds don't work for either) so these two entries sit
-- dormant until they're wired back up, at which point they're still measured against
-- UpperTorso since that's the AttachPart they'd fall back to. X/Z left at 0 -- the
-- measured values there are just left/right leg asymmetry (cancels out) and small
-- enough either axis not to matter as a starting point; G/J and N/M still fine-tune
-- all three axes same as before.
local DEFAULT_POS_BY_SLOT: { [string]: Vector3 } = {
    Legs = Vector3.new(0, -1.9, 0),
    Boots = Vector3.new(0, -4.0, 0),
}

local function defaultPosForSlot(slot: string): Vector3
    return DEFAULT_POS_BY_SLOT[slot] or Vector3.zero
end

-- Lazily creates default state (per-slot starting Pos above, identity rotation,
-- scale 1, base Size captured from the live part the first time this slot is seen).
local function getSlotState(slot: string, part: BasePart): SlotState
    local s = stateBySlot[slot]
    if not s then
        s = { Pos = defaultPosForSlot(slot), YawDeg = 0, PitchDeg = 0, RollDeg = 0, Scale = 1, BaseSize = part.Size }
        stateBySlot[slot] = s
    end
    return s
end

local function applySlotState(part: BasePart, motor: Motor6D, s: SlotState)
    motor.C0 = CFrame.new(s.Pos) * CFrame.Angles(math.rad(s.PitchDeg), math.rad(s.YawDeg), math.rad(s.RollDeg))
    part.Size = s.BaseSize * s.Scale
end

local function withSelectedSlot(fn: (slot: string, part: BasePart, motor: Motor6D, s: SlotState) -> ())
    local slot = currentSlot()
    local part, motor = currentSlotParts()
    if not slot or not part or not motor then
        return
    end
    local s = getSlotState(slot, part)
    fn(slot, part, motor, s)
    applySlotState(part, motor, s)
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
panel.Size = UDim2.fromOffset(340, 230)
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

local function refreshUIReadout(): string
    local ids = UIDevTuning.List()
    if #ids == 0 then
        return "No UI registered yet.\n\n(Panels call UIDevTuning.Register()\nat load time -- give it a moment and\nreopen with F6.)"
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
    table.insert(lines, ",/. switch UI | ' select target")
    table.insert(lines, "Y/H/G/J move | Shift=x10")
    table.insert(lines, "-/= scale | [/] rotate | Bksp reset")
    return table.concat(lines, "\n")
end

local function refreshModelReadout(): string
    local slots = scanSlots()
    if #slots == 0 then
        return "No worn armor right now.\n\n(Equip something into a slot\nArmorEquipVisuals has a prefab\nfor -- Chest/Legs/Boots/Helm --\nthen keep this panel open.)"
    end

    local slot = currentSlot() :: string
    local part, motor = currentSlotParts()
    if not part or not motor then
        return "Selected slot vanished (unequipped?)."
    end
    local s = getSlotState(slot, part)

    local lines = {}
    table.insert(lines, string.format("<b>[%d/%d] %s</b>", selectedSlotIndex, #slots, slot))
    table.insert(lines, string.format("Pos   %.2f, %.2f, %.2f", s.Pos.X, s.Pos.Y, s.Pos.Z))
    table.insert(lines, string.format("Yaw/Pitch/Roll  %d / %d / %d deg", s.YawDeg, s.PitchDeg, s.RollDeg))
    table.insert(lines, string.format("Scale %.2fx  (Size %.3f, %.3f, %.3f)", s.Scale, part.Size.X, part.Size.Y, part.Size.Z))
    table.insert(lines, "")
    table.insert(lines, ",/' switch slot | Y/H/G/J X/Y | N/M Z")
    table.insert(lines, "-/= scale | [/] yaw | U/I pitch | K/L roll")
    table.insert(lines, "Shift=x10 | Bksp reset")
    return table.concat(lines, "\n")
end

local function refreshReadout()
    local body = (mode == "UI") and refreshUIReadout() or refreshModelReadout()
    readout.Text = string.format("<b>Mode: %s</b>  (; to switch)\n\n%s\n\nEnter print snapshot | F6 close", mode, body)
end

--------------------------------------------------------------------------------
--  UI-mode selection changes -- keep the readout subscribed to whichever
--  handle is currently selected (handles can appear after this script
--  starts, since StarterPlayerScripts load order isn't guaranteed).

local function resubscribe()
    if currentUnsubscribe then
        currentUnsubscribe()
        currentUnsubscribe = nil
    end
    local handle = currentHandle()
    if handle then
        currentUnsubscribe = handle:Subscribe(function()
            if active and mode == "UI" then
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

local function cycleSlot(direction: number)
    local slots = scanSlots()
    if #slots == 0 then
        return
    end
    selectedSlotIndex = ((selectedSlotIndex - 1 + direction) % #slots) + 1
end

--------------------------------------------------------------------------------
--  Input

local STEP = { small = 1, big = 10 }
local SCALE_STEP = { small = 0.01, big = 0.05 }
local ROT_STEP = { small = 5, big = 45 }

local MODEL_STEP = { small = 0.02, big = 0.2 }
local MODEL_SCALE_STEP = { small = 0.02, big = 0.1 }

local function isShiftDown(): boolean
    return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
        or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

-- UI mode -------------------------------------------------------------------

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

local function printUISnapshot()
    local id, handle = currentId(), currentHandle()
    if id == nil or handle == nil then
        print("[UIDevTool] Nothing registered to print yet.")
        return
    end
    print("[UIDevTool] Paste-ready values for \"" .. id .. "\":\n" .. handle:Snapshot())
end

-- Model mode ------------------------------------------------------------------

local function nudgeModelPos(dx: number, dy: number, dz: number)
    withSelectedSlot(function(_, _, _, s)
        s.Pos = s.Pos + Vector3.new(dx, dy, dz)
    end)
end

local function nudgeModelScale(delta: number)
    withSelectedSlot(function(_, _, _, s)
        s.Scale = math.clamp(s.Scale + delta, 0.1, 5)
    end)
end

local function nudgeModelYaw(delta: number)
    withSelectedSlot(function(_, _, _, s)
        s.YawDeg = (s.YawDeg + delta) % 360
    end)
end

local function nudgeModelPitch(delta: number)
    withSelectedSlot(function(_, _, _, s)
        s.PitchDeg = (s.PitchDeg + delta) % 360
    end)
end

local function nudgeModelRoll(delta: number)
    withSelectedSlot(function(_, _, _, s)
        s.RollDeg = (s.RollDeg + delta) % 360
    end)
end

local function resetModelSelected()
    local slot = currentSlot()
    if not slot then
        return
    end
    stateBySlot[slot] = nil
    withSelectedSlot(function() end) -- recreate default state + re-apply identity
end

local function printModelSnapshot()
    local slot = currentSlot()
    local part, motor = currentSlotParts()
    if not slot or not part or not motor then
        print("[UIDevTool] Nothing equipped to print yet.")
        return
    end
    local s = getSlotState(slot, part)
    print(string.format(
        "[UIDevTool] Tuned values for slot \"%s\" -- paste into ArmorEquipVisuals.BySlot.%s:\n"
        .. "\tWornC0 = CFrame.new(%.3f, %.3f, %.3f) * CFrame.Angles(math.rad(%d), math.rad(%d), math.rad(%d)),\n"
        .. "\tWornSize = Vector3.new(%.4f, %.4f, %.4f), -- base was (%.4f, %.4f, %.4f), scale %.2fx",
        slot, slot,
        s.Pos.X, s.Pos.Y, s.Pos.Z, s.PitchDeg, s.YawDeg, s.RollDeg,
        part.Size.X, part.Size.Y, part.Size.Z,
        s.BaseSize.X, s.BaseSize.Y, s.BaseSize.Z, s.Scale
    ))
end

--------------------------------------------------------------------------------

local function setActive(value: boolean)
    active = value
    gui.Enabled = active
    if active then
        resubscribe()
        refreshReadout()
        print("[UIDevTool] Opened -- mode " .. mode)
    end
end

local function setMode(newMode: "UI" | "Model")
    mode = newMode
    if mode == "UI" then
        resubscribe()
    end
    refreshReadout()
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

    local key = input.KeyCode

    if key == Enum.KeyCode.Semicolon then
        setMode(mode == "UI" and "Model" or "UI")
        return
    end

    local step = isShiftDown() and STEP.big or STEP.small
    local scaleStep = isShiftDown() and SCALE_STEP.big or SCALE_STEP.small
    local rotStep = isShiftDown() and ROT_STEP.big or ROT_STEP.small
    local modelStep = isShiftDown() and MODEL_STEP.big or MODEL_STEP.small
    local modelScaleStep = isShiftDown() and MODEL_SCALE_STEP.big or MODEL_SCALE_STEP.small

    if mode == "UI" then
        if key == Enum.KeyCode.Comma then
            cycleUI(-1)
        elseif key == Enum.KeyCode.Period then
            cycleUI(1)
        elseif key == Enum.KeyCode.Quote then
            cycleTarget()
        elseif key == Enum.KeyCode.G then
            nudge(-step, 0)
        elseif key == Enum.KeyCode.J then
            nudge(step, 0)
        elseif key == Enum.KeyCode.Y then
            nudge(0, -step)
        elseif key == Enum.KeyCode.H then
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
            printUISnapshot()
        else
            return
        end
    else -- Model
        if key == Enum.KeyCode.Comma then
            cycleSlot(-1)
        elseif key == Enum.KeyCode.Quote then
            -- Period is Model mode's "next" everywhere else, but it (like Slash) gets
            -- eaten by this game's chat before InputBegan ever sees it here -- Quote
            -- was sitting unused in this mode anyway, so it took over "next" instead.
            cycleSlot(1)
        elseif key == Enum.KeyCode.G then
            nudgeModelPos(-modelStep, 0, 0)
        elseif key == Enum.KeyCode.J then
            nudgeModelPos(modelStep, 0, 0)
        elseif key == Enum.KeyCode.Y then
            nudgeModelPos(0, modelStep, 0)
        elseif key == Enum.KeyCode.H then
            nudgeModelPos(0, -modelStep, 0)
        elseif key == Enum.KeyCode.N then
            -- Was Page Up/Page Down -- also swallowed before this script saw it.
            nudgeModelPos(0, 0, -modelStep)
        elseif key == Enum.KeyCode.M then
            nudgeModelPos(0, 0, modelStep)
        elseif key == Enum.KeyCode.Minus then
            nudgeModelScale(-modelScaleStep)
        elseif key == Enum.KeyCode.Equals then
            nudgeModelScale(modelScaleStep)
        elseif key == Enum.KeyCode.LeftBracket then
            nudgeModelYaw(-rotStep)
        elseif key == Enum.KeyCode.RightBracket then
            nudgeModelYaw(rotStep)
        elseif key == Enum.KeyCode.U then
            nudgeModelPitch(-rotStep)
        elseif key == Enum.KeyCode.I then
            nudgeModelPitch(rotStep)
        elseif key == Enum.KeyCode.K then
            nudgeModelRoll(-rotStep)
        elseif key == Enum.KeyCode.L then
            nudgeModelRoll(rotStep)
        elseif key == Enum.KeyCode.Backspace then
            resetModelSelected()
        elseif key == Enum.KeyCode.Return then
            printModelSnapshot()
        else
            return
        end
    end

    refreshReadout()
end)
