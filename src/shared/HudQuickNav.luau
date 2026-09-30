--[[
	HudQuickNav (client-only; lives in RS so every client script shares one copy)

	The row of small quick-access buttons at the top right, hanging under the minimap's
	bottom-left corner. New buttons join on the RIGHT of the row, in ORDER.

		Slot(name, order) -> Frame     lower order = further left
			ORDER.Settings = 10        (the settings gear, SettingsClient)
			ORDER.Crosshair = 20       (crosshair on/off, client/Crosshair)
		FollowBelow(frame)             hang the row under `frame` (the minimap does this);
		                               while that frame is hidden (dungeons), the row moves up
		                               to the top of the screen instead of leaving a gap
		BUTTON_SIZE                    the square size every button here uses
		Tooltip(button, text)          a small label under the button while hovered
		                               ("Settings", "Toggle Crosshair")

	A slot sizes itself to its content (AutomaticSize), so owners just parent a button into it.
	DisplayOrder sits just above SettingsGui's click-away backdrop (250), so the gear stays
	clickable while its own panel is open.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuickNav = {}

QuickNav.ORDER = {
	Settings = 10,
	Crosshair = 20,
}

QuickNav.MARGIN = 8       -- from the screen's top/right edges when nothing to follow
QuickNav.GAP = 8          -- under the followed frame (clears its 2px border stroke too)
QuickNav.PADDING = 6      -- between buttons
QuickNav.BUTTON_SIZE = 30

local gui, container, followConns

local function ensure()
	if container and container.Parent then return container end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = Instance.new("ScreenGui")
	gui.Name = "HudQuickNav"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 251
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	container = Instance.new("Frame")
	container.Name = "Row"
	container.AnchorPoint = Vector2.new(1, 0)
	container.Position = UDim2.new(1, -QuickNav.MARGIN, 0, QuickNav.MARGIN)
	container.Size = UDim2.fromOffset(0, 0)
	container.AutomaticSize = Enum.AutomaticSize.XY
	container.BackgroundTransparency = 1
	container.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, QuickNav.PADDING)
	layout.Parent = container
	return container
end

function QuickNav.Slot(name, order)
	local parent = ensure()
	local slot = parent:FindFirstChild(name)
	if slot then return slot end
	slot = Instance.new("Frame")
	slot.Name = name
	slot.LayoutOrder = order or 0
	slot.Size = UDim2.fromOffset(0, 0)
	slot.AutomaticSize = Enum.AutomaticSize.XY
	slot.BackgroundTransparency = 1
	slot.Parent = parent
	return slot
end

-- Hangs the row under `frame`'s bottom-left corner. `frame` must sit directly in a full-screen
-- ScreenGui that ignores the inset (like this one), so its own Position/Size/AnchorPoint ARE
-- screen coordinates here too. Uses those layout values, not AbsolutePosition: the minimap starts
-- hidden, and reading absolute pixels at that moment (before layout) put the row inside the map.
function QuickNav.FollowBelow(frame)
	local row = ensure()
	if followConns then
		for _, c in ipairs(followConns) do c:Disconnect() end
	end
	local function place()
		local pos, size, anchor = frame.Position, frame.Size, frame.AnchorPoint
		local leftScale = pos.X.Scale - anchor.X * size.X.Scale
		local leftOffset = pos.X.Offset - anchor.X * size.X.Offset
		local bottomScale = pos.Y.Scale + (1 - anchor.Y) * size.Y.Scale
		local bottomOffset = pos.Y.Offset + (1 - anchor.Y) * size.Y.Offset
		row.AnchorPoint = Vector2.new(0, 0)
		if frame.Visible then
			row.Position = UDim2.new(leftScale, leftOffset, bottomScale, bottomOffset + QuickNav.GAP)
		else
			row.Position = UDim2.new(leftScale, leftOffset, 0, QuickNav.MARGIN)
		end
	end
	followConns = {}
	for _, prop in ipairs({ "Position", "Size", "AnchorPoint", "Visible" }) do
		table.insert(followConns, frame:GetPropertyChangedSignal(prop):Connect(place))
	end
	place()
end

-- One shared hover label for the whole row. It lives in this ScreenGui (not inside the button:
-- slots size themselves to their content, so a child hanging below would reflow the row) and is
-- placed from the hovered button's AbsolutePosition, which is screen space here (IgnoreGuiInset).
local tip
local hovered

local function ensureTip()
	if tip and tip.Parent then return tip end
	ensure()
	local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
	tip = Instance.new("TextLabel")
	tip.Name = "Tooltip"
	tip.AnchorPoint = Vector2.new(0.5, 0)
	tip.AutomaticSize = Enum.AutomaticSize.XY
	tip.Size = UDim2.fromOffset(0, 0)
	tip.BackgroundColor3 = Color3.fromRGB(14, 13, 16)
	tip.BackgroundTransparency = 0.1
	tip.BorderSizePixel = 0
	tip.FontFace = UIFonts.BodyBold
	tip.TextSize = 13
	tip.TextColor3 = Color3.fromRGB(236, 226, 208)
	tip.Visible = false
	tip.ZIndex = 20
	tip.Parent = gui
	Instance.new("UICorner", tip).CornerRadius = UDim.new(0, 4)
	local pad = Instance.new("UIPadding", tip)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 7), UDim.new(0, 7)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 3), UDim.new(0, 3)
	local edge = Instance.new("UIStroke", tip)
	edge.Color = Color3.fromRGB(70, 60, 50)
	edge.Transparency = 0.2
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	return tip
end

function QuickNav.Tooltip(button, text)
	button.MouseEnter:Connect(function()
		local label = ensureTip()
		hovered = button
		label.Text = text
		local pos, size = button.AbsolutePosition, button.AbsoluteSize
		local screenW = gui.AbsoluteSize.X
		-- Centred under the button, kept on screen at the right edge.
		local x = math.min(pos.X + size.X / 2, screenW - label.AbsoluteSize.X / 2 - QuickNav.MARGIN)
		label.Position = UDim2.fromOffset(x, pos.Y + size.Y + 6)
		label.Visible = true
	end)
	button.MouseLeave:Connect(function()
		if hovered == button and tip then
			hovered = nil
			tip.Visible = false
		end
	end)
end

return QuickNav
