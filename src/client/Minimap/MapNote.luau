--[[
	MapNote -- the world map's paper (2026-10-11): parchment slips pinned onto the map (the marker
	picker and card, the hover tooltip, the toast, a WorldMapRequest pin's label) and the legend's
	cartouche, written on in ink like a cartographer's notes. Art in RS/Assets/Images/MapUI; the
	ink colours and serif match the Journal's pages (Journal/Style).

		MapNote.Backing(frame, art, sliceScale, zIndex)  paints a 9-slice paper behind `frame`'s
		                                     content (a child "Paper", Size 1,1); without the art,
		                                     flat parchment with an ink edge
		MapNote.Label(props, parent)         a TextLabel in ink (props override the defaults)
		MapNote.MenuIcon(name, parent, z)    one ink icon off the MENU_ICONS sheet (Track,
		                                     StopTracking, ChangeType, Remove, Shown, Hidden, Centre);
		                                     nil without the art
		MapNote.INK / MapNote.FONT           the colours and fonts
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local MapUI = require(ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images"):WaitForChild("MapUI"))

local MapNote = {}

MapNote.INK = {
	Heading = Color3.fromRGB(38, 28, 18),
	Body = Color3.fromRGB(58, 44, 30),
	Muted = Color3.fromRGB(110, 92, 70),
	Danger = Color3.fromRGB(140, 52, 36),
	Wash = Color3.fromRGB(110, 92, 70), -- the hovered row's faint wash
}

MapNote.FONT = {
	Heading = UIFonts.SerifBold,
	Body = UIFonts.BodyMedium,
	Note = Font.new(UIFonts.Families.Body, Enum.FontWeight.Regular, Enum.FontStyle.Italic),
}

local PAPER = Color3.fromRGB(233, 221, 191) -- the fallback's flat parchment

local function hasArt(art)
	return art ~= nil and art.Image ~= ""
end
MapNote.HasArt = hasArt

function MapNote.Backing(frame, art, sliceScale, zIndex)
	local paper = Instance.new("ImageLabel")
	paper.Name = "Paper"
	paper.Size = UDim2.fromScale(1, 1)
	paper.BackgroundTransparency = 1
	paper.ZIndex = zIndex
	if hasArt(art) then
		paper.Image = art.Image
		paper.ScaleType = Enum.ScaleType.Slice
		paper.SliceCenter = art.SliceCenter
		paper.SliceScale = sliceScale
	else
		paper.BackgroundColor3 = PAPER
		paper.BackgroundTransparency = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 4)
		corner.Parent = paper
		local edge = Instance.new("UIStroke")
		edge.Color = MapNote.INK.Muted
		edge.Thickness = 1
		edge.Parent = paper
	end
	paper.Parent = frame
	return paper
end

function MapNote.Label(props, parent)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.FontFace = MapNote.FONT.Body
	label.TextSize = 15
	label.TextColor3 = MapNote.INK.Body
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = ""
	for k, v in pairs(props) do label[k] = v end
	label.Parent = parent
	return label
end

function MapNote.MenuIcon(name, parent, zIndex)
	local sheet = MapUI.MENU_ICONS
	local cell = hasArt(sheet) and sheet.Rects[name]
	if not cell then return nil end
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Image = sheet.Image
	icon.ImageRectOffset = cell.Offset
	icon.ImageRectSize = cell.Size
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = zIndex
	icon.Parent = parent
	return icon
end

-- Points a MenuIcon at another cell of the sheet (Track <-> StopTracking, Shown <-> Hidden).
function MapNote.SetMenuIcon(icon, name)
	local cell = icon and MapUI.MENU_ICONS.Rects[name]
	if not cell then return end
	icon.ImageRectOffset = cell.Offset
	icon.ImageRectSize = cell.Size
end

return MapNote
