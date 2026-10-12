--[[
	DevMenu/Ui -- the F8 dev menu's look: colours, fonts, Journal art, and the small widget helpers
	every tab builds with.

	Widgets are plain pixel-positioned Instances (tabs are dev tooling, laid out quickly), styled
	from the Journal kit: dark leather plates with a thin bronze rim, Journal serif for headings,
	the body font for everything small, Journal art (book cover, chips) where a piece exists.

	lbl(parent, text, x, y, w, h, size?, color?, bold?, xAlign?) -> TextLabel
	mkB(parent, text, x, y, w, h, bg?)                          -> TextButton
	mkI(parent, placeholder, x, y, w, h, default?)               -> TextBox
	section(ctx, name, scrolling?)                               -> the tab's root Frame (hidden)
	applyArt(image, key)                                         -> puts Journal art on an Image*'s own image
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local JournalUI = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images"):WaitForChild("JournalUI"))

local Ui = {}

Ui.Color = {
	Window = Color3.fromRGB(28, 20, 14),   -- under the book-cover art
	Page = Color3.fromRGB(34, 26, 18),     -- content panels
	Plate = Color3.fromRGB(52, 39, 26),    -- buttons
	Field = Color3.fromRGB(20, 15, 10),    -- text boxes, wells
	Rim = Color3.fromRGB(172, 150, 108),   -- bronze (UITheme.Gold)
	Label = Color3.fromRGB(196, 170, 120), -- small caps labels (the old ACC)
	Text = Color3.fromRGB(240, 232, 212),
	Muted = Color3.fromRGB(158, 143, 122),
	Gold = Color3.fromRGB(255, 215, 100),
	Good = Color3.fromRGB(46, 86, 44),
	Bad = Color3.fromRGB(110, 36, 30),
	Status = Color3.fromRGB(255, 220, 120),
	Error = Color3.fromRGB(255, 120, 120),
}

Ui.Font = {
	Heading = UIFonts.SerifBold,
	Body = UIFonts.Body,
	BodyBold = UIFonts.BodyBold or UIFonts.SerifBold,
}

local function setFont(obj, font)
	pcall(function() obj.FontFace = font end)
end

function Ui.lbl(parent, text, x, y, w, h, size, color, bold, xAlign)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromOffset(x, y)
	l.Size = UDim2.fromOffset(w, h)
	setFont(l, bold and Ui.Font.BodyBold or Ui.Font.Body)
	l.TextSize = size or 14
	l.TextColor3 = color or Ui.Color.Text
	l.TextXAlignment = xAlign or Enum.TextXAlignment.Left
	l.Text = text
	l.ZIndex = 3
	l.Parent = parent
	return l
end

function Ui.mkB(parent, text, x, y, w, h, bg)
	local b = Instance.new("TextButton")
	b.Position = UDim2.fromOffset(x, y)
	b.Size = UDim2.fromOffset(w, h)
	b.BackgroundColor3 = bg or Ui.Color.Plate
	b.BorderSizePixel = 0
	setFont(b, Ui.Font.BodyBold)
	b.TextSize = 14
	b.TextColor3 = Ui.Color.Text
	b.Text = text
	b.ZIndex = 4
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
	local rim = Instance.new("UIStroke")
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Color = Ui.Color.Rim
	rim.Transparency = 0.55
	rim.Parent = b
	b.Parent = parent
	return b
end

function Ui.mkI(parent, placeholder, x, y, w, h, default)
	local b = Instance.new("TextBox")
	b.Position = UDim2.fromOffset(x, y)
	b.Size = UDim2.fromOffset(w, h)
	b.BackgroundColor3 = Ui.Color.Field
	b.BorderSizePixel = 0
	setFont(b, Ui.Font.Body)
	b.TextSize = 14
	b.TextColor3 = Ui.Color.Text
	b.PlaceholderText = placeholder
	b.PlaceholderColor3 = Color3.fromRGB(110, 95, 80)
	b.ClearTextOnFocus = false
	b.Text = default or ""
	b.ZIndex = 4
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
	local rim = Instance.new("UIStroke")
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Color = Ui.Color.Rim
	rim.Transparency = 0.6
	rim.Parent = b
	b.Parent = parent
	return b
end

-- A tab's root: positioned and sized by the host area the shell gives it (ctx.w x ctx.h),
-- hidden until the tab is selected. Scrolling roots grow with their content.
function Ui.section(ctx, name, scrolling)
	local sec = Instance.new(scrolling and "ScrollingFrame" or "Frame")
	sec.Name = name
	sec.Position = UDim2.fromOffset(0, ctx.y or 0)
	sec.Size = UDim2.fromOffset(ctx.w, ctx.h)
	sec.BackgroundTransparency = 1
	sec.BorderSizePixel = 0
	sec.Visible = false
	if scrolling then
		sec.CanvasSize = UDim2.new()
		sec.AutomaticCanvasSize = Enum.AutomaticSize.Y
		sec.ScrollingDirection = Enum.ScrollingDirection.Y
		sec.ScrollBarThickness = 6
		sec.ScrollBarImageColor3 = Ui.Color.Rim
		sec.TopImage = ""
		sec.BottomImage = ""
	end
	sec.Parent = ctx.parent
	return sec
end

-- Puts Journal art on an ImageLabel/ImageButton's OWN image (9-sliced when it has slice data).
-- On the object's own image, never as a child: in Sibling z-order a child always draws above its
-- parent, so art parented inside a button would cover the button's text. False = not uploaded.
function Ui.applyArt(image, key)
	local entry = JournalUI[key]
	if type(entry) ~= "table" or type(entry.Image) ~= "string" or entry.Image == "" then
		return false
	end
	image.Image = entry.Image
	if entry.SliceCenter then
		image.ScaleType = Enum.ScaleType.Slice
		image.SliceCenter = entry.SliceCenter
		image.SliceScale = entry.SliceScale or 1
	else
		image.ScaleType = Enum.ScaleType.Stretch
	end
	return true
end

return Ui
