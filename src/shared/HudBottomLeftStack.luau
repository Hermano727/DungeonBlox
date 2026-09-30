--[[
    HudBottomLeftStack (client-only; lives in RS so every client script shares one copy)

    The bottom-left corner of the screen is one vertical stack of small status readouts. The
    most important one sits at the very bottom and everything else piles up above it; a readout
    that hides collapses out of the stack, and the rest slide down.

        Slot(name, order) -> Frame     higher order = lower on screen
            ORDER.Combat   = 100       (combat timer: always the bottom, PvP-relevant)
            ORDER.Dungeon  = 90        (dungeon run timer, above it)

    A slot is invisible until its owner sets Visible = true, and it sizes itself to its content
    (AutomaticSize), so owners just parent their pill into it.

    Things that live in the same corner but outside this stack (XpHud's Mining/Fishing bars)
    read GetHeight() / HeightChanged and sit above it.

    Also publishes a small shared pill builder, so every readout here looks like one family.
]]

local Players = game:GetService("Players")

local Stack = {}

Stack.ORDER = {
    Dungeon = 90,
    Combat = 100,
}

Stack.MARGIN = 16   -- from the screen's left and bottom edges
Stack.PADDING = 6   -- between readouts

local gui, container
local heightChanged = Instance.new("BindableEvent")
Stack.HeightChanged = heightChanged.Event

local function ensure()
    if container and container.Parent then return container end
    local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
    gui = Instance.new("ScreenGui")
    gui.Name = "HudBottomLeft"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 111
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = playerGui

    container = Instance.new("Frame")
    container.Name = "Stack"
    container.AnchorPoint = Vector2.new(0, 1)
    container.Position = UDim2.new(0, Stack.MARGIN, 1, -Stack.MARGIN)
    container.Size = UDim2.fromOffset(0, 0)
    container.AutomaticSize = Enum.AutomaticSize.XY
    container.BackgroundTransparency = 1
    container.Parent = gui

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, Stack.PADDING)
    layout.Parent = container

    local last = -1
    container:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        local h = Stack.GetHeight()
        if h ~= last then
            last = h
            heightChanged:Fire(h)
        end
    end)
    return container
end

function Stack.Slot(name, order)
    local parent = ensure()
    local slot = parent:FindFirstChild(name)
    if slot then return slot end
    slot = Instance.new("Frame")
    slot.Name = name
    slot.LayoutOrder = order or 0
    slot.Size = UDim2.fromOffset(0, 0)
    slot.AutomaticSize = Enum.AutomaticSize.XY
    slot.BackgroundTransparency = 1
    slot.Visible = false
    slot.Parent = parent
    return slot
end

-- Pixel height of the visible stack (0 when nothing is showing).
function Stack.GetHeight()
    if not container then return 0 end
    for _, child in ipairs(container:GetChildren()) do
        if child:IsA("GuiObject") and child.Visible then
            return container.AbsoluteSize.Y
        end
    end
    return 0
end

--[[
    Pill(parent, opts) -> { frame, icon, label, stroke }
    A dark rounded plate: [icon] text. opts: height, iconSize, textSize, font, textWidth
    (fixed text width, so a ticking number doesn't make the pill jitter), strokeColor.
]]
function Stack.Pill(parent, opts)
    opts = opts or {}
    local height = opts.height or 32

    local frame = Instance.new("Frame")
    frame.Name = "Pill"
    frame.Size = UDim2.fromOffset(0, height)
    frame.AutomaticSize = Enum.AutomaticSize.X
    frame.BackgroundColor3 = Color3.fromRGB(12, 10, 10)
    frame.BackgroundTransparency = .35
    frame.BorderSizePixel = 0
    frame.Parent = parent
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)
    local padding = Instance.new("UIPadding", frame)
    padding.PaddingLeft = UDim.new(0, 8)
    padding.PaddingRight = UDim.new(0, 12)
    local stroke = Instance.new("UIStroke", frame)
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Thickness = 1
    stroke.Color = opts.strokeColor or Color3.fromRGB(90, 70, 50)
    stroke.Transparency = .4
    local row = Instance.new("UIListLayout", frame)
    row.FillDirection = Enum.FillDirection.Horizontal
    row.VerticalAlignment = Enum.VerticalAlignment.Center
    row.SortOrder = Enum.SortOrder.LayoutOrder
    row.Padding = UDim.new(0, 6)

    local iconSize = opts.iconSize or (height - 8)
    local icon = Instance.new("ImageLabel")
    icon.Name = "Icon"
    icon.LayoutOrder = 1
    icon.BackgroundTransparency = 1
    icon.Size = UDim2.fromOffset(iconSize, iconSize)
    icon.ScaleType = Enum.ScaleType.Fit
    icon.Image = opts.image or ""
    icon.Visible = (opts.image or "") ~= ""
    icon.Parent = frame

    local label = Instance.new("TextLabel")
    label.Name = "Text"
    label.LayoutOrder = 2
    label.BackgroundTransparency = 1
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextSize = opts.textSize or 16
    label.TextColor3 = opts.textColor or Color3.fromRGB(230, 225, 215)
    label.TextStrokeTransparency = .6
    if opts.textWidth then
        label.Size = UDim2.fromOffset(opts.textWidth, height)
    else
        label.Size = UDim2.fromOffset(0, height)
        label.AutomaticSize = Enum.AutomaticSize.X
    end
    pcall(function() label.FontFace = opts.font end)
    label.Text = ""
    label.Parent = frame

    return { frame = frame, icon = icon, label = label, stroke = stroke }
end

return Stack
