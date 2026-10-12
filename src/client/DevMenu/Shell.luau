--[[
	DevMenu/Shell -- the F8 window: everything that isn't a tab.

	+--------------------------------------------------------------------------+
	| Dev tools   World / Mob                              [Hide tabs]  [X]   |  header
	| WORLD  [Mob][NPC][Elite][Zone][Time]                                     |  tab list: one row
	| ITEMS  [Gear][Items][Mythic]   (PLAYER, MEDIA rows below)               |  per group
	| +---------------------------------------------+ +----------------------+ |
	| |                 the active tab               | | Managed spawners     | |  body (list column
	| |                                              | | (tabs with listType) | |  only for tabs
	| +---------------------------------------------+ +----------------------+ |  that manage things)
	| status line ......................................... [ Action button ]  |  footer
	+--------------------------------------------------------------------------+

	Sized from the viewport once at build (about 90% of the screen). Tabs are grouped by their
	`group` field, one row per group (a long group wraps under itself), so adding tabs never needs
	layout edits; "Hide tabs" folds the whole list to free the body, and the header always names
	the active tab.

	Also owns the floating HUD strip (zone drawing / fly help) that stays up while the window is
	hidden: shell.hud:Set(visible, title, hint1, hint2, status, statusColor).
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Ui = require(script.Parent:WaitForChild("Ui"))

local player = Players.LocalPlayer
local C = Ui.Color

local PAD = 40 -- clear of the book cover's corner ornaments (~70 px at its slice scale)
local HEADER_H = 40
local CHIP_H = 40 -- chip_selected's 9-slice edges need ~40 px
local ROW_GAP = 6
local FOOTER_H = 48
local DISPLAY_ORDER = 300
local GROUP_ORDER = { "World", "Items", "Dungeon", "Player", "Media" }

local Shell = {}
Shell.__index = Shell

local function viewport()
	local camera = Workspace.CurrentCamera
	local size = camera and camera.ViewportSize or Vector2.new(0, 0)
	if size.X < 400 then
		-- Very early in the session the camera can still report a placeholder size.
		task.wait(1)
		camera = Workspace.CurrentCamera
		size = camera and camera.ViewportSize or Vector2.new(1600, 900)
	end
	return size
end

local function chipWidth(text)
	return math.max(84, #text * 9 + 34)
end

-- A tab chip: an ImageButton wearing the Journal chip art (chip_selected when active), with its
-- label as a child so it draws on top of the art.
local function makeChip(parent, text, x, y)
	local b = Instance.new("ImageButton")
	b.Name = "Chip_" .. text
	b.Position = UDim2.fromOffset(x, y)
	b.Size = UDim2.fromOffset(chipWidth(text), CHIP_H)
	b.BackgroundColor3 = C.Plate
	b.BorderSizePixel = 0
	b.ZIndex = 5
	b.Parent = parent
	if Ui.applyArt(b, "chip") then
		b.BackgroundTransparency = 1
	else
		Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
	end
	local label = Ui.lbl(b, text, 0, 0, 0, 0, 14, Color3.fromRGB(214, 200, 172), true, Enum.TextXAlignment.Center)
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 6
	pcall(function() label.FontFace = Ui.Font.Heading end)
	return b, label
end

function Shell.new(tabs)
	local self = setmetatable({}, Shell)
	local vp = viewport()
	local winW = math.clamp(math.floor(vp.X * 0.9), 980, 2400)
	local winH = math.clamp(math.floor(vp.Y * 0.88), 600, 1400)
	self.winW, self.winH = winW, winH

	local gui = Instance.new("ScreenGui")
	gui.Name = "DevPlacerUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- Above every HUD layer (quick-nav buttons 251, loot banners 260, zone banners 220): the
	-- window spans most of the screen, and any HUD button drawn over it would take its clicks
	-- (the right half of the tab list sat under the minimap's quick-nav row at 200).
	gui.DisplayOrder = DISPLAY_ORDER
	gui.Enabled = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	self.gui = gui

	-- The window wears the Journal book cover as its own image (children draw on top of it).
	local window = Instance.new("ImageLabel")
	window.Name = "Window"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromOffset(winW, winH)
	window.BackgroundColor3 = C.Window
	window.BorderSizePixel = 0
	window.Parent = gui
	if Ui.applyArt(window, "book_cover") then
		window.BackgroundTransparency = 1
	else
		Instance.new("UICorner", window).CornerRadius = UDim.new(0, 10)
	end
	self.window = window

	-- header
	local title = Ui.lbl(window, "Dev tools", PAD + 6, PAD, 160, HEADER_H, 22, C.Gold, true)
	pcall(function() title.FontFace = Ui.Font.Heading end)
	self.crumb = Ui.lbl(window, "", PAD + 170, PAD, winW - PAD * 2 - 420, HEADER_H, 15, C.Muted)
	self.closeButton = Ui.mkB(window, "X", winW - PAD - 40, PAD + 4, 36, 32, C.Bad)
	self.collapseButton = Ui.mkB(window, "Hide tabs", winW - PAD - 160, PAD + 4, 110, 32)

	-- tab list: groups in GROUP_ORDER, then any other group name in first-seen order. One row per
	-- group: its heading, then its chips (wrapping under themselves if a group outgrows the row).
	local groups, seen = {}, {}
	for _, name in ipairs(GROUP_ORDER) do
		groups[#groups + 1] = { name = name, tabs = {} }
		seen[name] = groups[#groups]
	end
	for _, tab in ipairs(tabs) do
		local name = tab.group or "Other"
		if not seen[name] then
			groups[#groups + 1] = { name = name, tabs = {} }
			seen[name] = groups[#groups]
		end
		table.insert(seen[name].tabs, tab)
	end

	local bar = Instance.new("Frame")
	bar.Name = "TabList"
	bar.BackgroundTransparency = 1
	bar.Position = UDim2.fromOffset(PAD + 6, PAD + HEADER_H + 6)
	bar.Parent = window
	self.bar = bar
	self.maxX = winW - PAD * 2 - 12
	self.chips = {}
	self.groups = {}
	for _, group in ipairs(groups) do
		if #group.tabs > 0 then
			group.header = Ui.lbl(bar, string.upper(group.name), 0, 0, 0, CHIP_H, 12, C.Label, true)
			for _, tab in ipairs(group.tabs) do
				local chip, label = makeChip(bar, tab.label, 0, 0)
				self.chips[tab.key] = { button = chip, label = label, group = group.name }
				chip.Activated:Connect(function()
					if self.onTabClicked then self.onTabClicked(tab.key) end
				end)
			end
			table.insert(self.groups, group)
		end
	end

	-- body
	self.bodyW = winW - PAD * 2 - 12
	self.listW = math.clamp(math.floor(self.bodyW * 0.32), 340, 620)
	local host = Instance.new("Frame")
	host.Name = "Host"
	host.BackgroundColor3 = C.Page
	host.BackgroundTransparency = 0.05
	host.BorderSizePixel = 0
	host.ClipsDescendants = true
	host.Parent = window
	Instance.new("UICorner", host).CornerRadius = UDim.new(0, 8)
	local hostPad = Instance.new("UIPadding")
	hostPad.PaddingTop = UDim.new(0, 10)
	hostPad.PaddingLeft = UDim.new(0, 10)
	hostPad.Parent = host
	self.host = host

	local listColumn = Instance.new("Frame")
	listColumn.Name = "ListColumn"
	listColumn.BackgroundColor3 = C.Field
	listColumn.BackgroundTransparency = 0.2
	listColumn.BorderSizePixel = 0
	listColumn.AnchorPoint = Vector2.new(1, 0)
	listColumn.Position = UDim2.new(1, -10, 0, 0)
	listColumn.Size = UDim2.new(0, self.listW, 1, -10)
	listColumn.Visible = false
	listColumn.ZIndex = 2
	listColumn.Parent = host
	Instance.new("UICorner", listColumn).CornerRadius = UDim.new(0, 6)
	self.listColumn = listColumn

	-- footer
	local footerY = winH - PAD - FOOTER_H
	self.status = Ui.lbl(window, "", PAD + 12, footerY, winW - PAD * 2 - 330, FOOTER_H, 15, C.Status)
	self.status.TextTruncate = Enum.TextTruncate.AtEnd
	self.actionButton = Ui.mkB(window, "", winW - PAD - 300, footerY + 4, 294, FOOTER_H - 8, C.Good)
	self.actionButton.TextSize = 16
	self.actionButton.Visible = false

	-- "Hide tabs" folds the whole list away to give the body the room.
	self.collapsed = false
	self.collapseButton.Activated:Connect(function()
		self.collapsed = not self.collapsed
		self.collapseButton.Text = self.collapsed and "Show tabs" or "Hide tabs"
		self:Layout()
	end)

	-- Tabs are built at the body height with the list shown (the smallest it gets).
	self:Layout()
	self.bodyH = host.Size.Y.Offset

	self.hud = Shell.newHud()
	return self
end

-- One row per group: headings in a column on the left, chips after them, a group too long for
-- one row wrapping under its own chips. Then the body is fitted under the list.
function Shell:Layout()
	local headingW = 0
	for _, group in ipairs(self.groups) do
		headingW = math.max(headingW, #group.name * 9 + 18)
	end
	local y = 0
	for i, group in ipairs(self.groups) do
		if i > 1 then y += CHIP_H + ROW_GAP end
		group.header.Position = UDim2.fromOffset(0, y)
		group.header.Size = UDim2.fromOffset(headingW, CHIP_H)
		local x = headingW + 6
		for _, tab in ipairs(group.tabs) do
			local w = chipWidth(tab.label)
			if x + w > self.maxX then
				x, y = headingW + 6, y + CHIP_H + ROW_GAP
			end
			self.chips[tab.key].button.Position = UDim2.fromOffset(x, y)
			x += w + 6
		end
	end
	self.barHeight = y + CHIP_H
	self.bar.Size = UDim2.fromOffset(self.maxX, self.barHeight)
	self.bar.Visible = not self.collapsed

	local top = PAD + HEADER_H + (self.collapsed and 6 or (self.barHeight + 14))
	self.host.Position = UDim2.fromOffset(PAD + 6, top)
	self.host.Size = UDim2.fromOffset(self.bodyW, self.winH - top - FOOTER_H - PAD - 8)
end

-- Width the active tab may use: the whole body, or what's left beside the list column.
function Shell:TabWidth(tab)
	local w = self.bodyW - 20
	if tab.listType then
		w -= self.listW + 12
	end
	return w
end

function Shell:SetActive(tab)
	for key, chip in pairs(self.chips) do
		local active = key == tab.key
		if not Ui.applyArt(chip.button, active and "chip_selected" or "chip") then
			chip.button.BackgroundColor3 = active and C.Good or C.Plate
		end
		chip.label.TextColor3 = active and Color3.fromRGB(246, 230, 190) or Color3.fromRGB(214, 200, 172)
	end
	local chip = self.chips[tab.key]
	self.crumb.Text = (chip and chip.group or "") .. "  /  " .. tab.label
	self.listColumn.Visible = tab.listType ~= nil
end

function Shell:SetStatus(text, isError)
	self.status.Text = tostring(text or "")
	self.status.TextColor3 = isError and C.Error or C.Status
end

function Shell:SetAction(text, color)
	self.actionButton.Visible = text ~= nil
	if text then
		self.actionButton.Text = text
		self.actionButton.BackgroundColor3 = color or C.Good
	end
end

function Shell:SetVisible(v)
	self.gui.Enabled = v
end

function Shell:Contains(point)
	if not self.gui.Enabled then return false end
	local p, s = self.window.AbsolutePosition, self.window.AbsoluteSize
	return point.X >= p.X and point.X <= p.X + s.X and point.Y >= p.Y and point.Y <= p.Y + s.Y
end

---------------------------------------------------------------- floating HUD

function Shell.newHud()
	local gui = Instance.new("ScreenGui")
	gui.Name = "DevPlacerDrawHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = DISPLAY_ORDER - 1
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 64)
	frame.Size = UDim2.fromOffset(720, 92)
	frame.BackgroundColor3 = C.Window
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Parent = gui
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
	local rim = Instance.new("UIStroke")
	rim.Color = C.Rim
	rim.Transparency = 0.5
	rim.Parent = frame
	local center = Enum.TextXAlignment.Center
	local title = Ui.lbl(frame, "", 10, 6, 700, 22, 16, C.Gold, true, center)
	local hint1 = Ui.lbl(frame, "", 10, 30, 700, 16, 13, C.Text, false, center)
	local hint2 = Ui.lbl(frame, "", 10, 48, 700, 16, 13, C.Muted, false, center)
	local status = Ui.lbl(frame, "", 10, 66, 700, 18, 13, C.Status, false, center)
	return {
		Set = function(_, visible, t, h1, h2, statusText, statusColor)
			gui.Enabled = visible
			if not visible then return end
			title.Text, hint1.Text, hint2.Text = t or "", h1 or "", h2 or ""
			status.Text = statusText or ""
			status.TextColor3 = statusColor or C.Status
		end,
	}
end

return Shell
