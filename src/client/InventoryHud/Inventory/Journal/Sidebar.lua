--!strict
--  Journal/Sidebar -- the tall leather/wood panel left of the book listing the Journal's
--  top-level pages (Loot Score, Records, ...). Deeper views (Loot Score -> Activity) are not
--  listed here; they're reached from inside their page and left with Back.
--
--    e(Sidebar, { pages = { { id, label, icon? } }, selected = id, onSelect = fn(id) })

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Style = require(script.Parent:WaitForChild("Style"))
local Parts = require(script.Parent:WaitForChild("Parts"))

local e = React.createElement

local ROW_H = 58
local PAD = 18
local TEXT_MAX, TEXT_MIN = 18, 12
local ICON_ROOM = 26 + 32 + 8 + 14 -- icon inset + icon + gap before the label + room at the end
local GLYPH_EM = 0.6 -- the serif's average glyph width, in text sizes

-- One label size for every row: as big as TEXT_MAX allows while the LONGEST label still fits
-- the row. The panel keeps its painted shape, so it narrows when the book is short.
local function useLabelSize(pages: { any })
	local ref = React.useRef(nil :: Frame?)
	local size, setSize = React.useState(TEXT_MAX)
	local longest = 1
	for _, page in ipairs(pages) do longest = math.max(longest, #page.label) end
	React.useEffect(function()
		local frame = ref.current
		if not frame then return end
		local function fit()
			local room = frame.AbsoluteSize.X - ICON_ROOM
			if room <= 0 then return end
			setSize(math.clamp(math.floor(room / (longest * GLYPH_EM)), TEXT_MIN, TEXT_MAX))
		end
		fit()
		local conn = frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		return function() conn:Disconnect() end
	end, { longest })
	return ref, size
end

local function Sidebar(props: { pages: { any }, selected: string, onSelect: (string) -> () })
	local rowsRef, labelSize = useLabelSize(props.pages)
	local panelArt = Style.Art("sidebar_panel")
	local rows: { [string]: any } = {
		Layout = e("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }),
	}
	for i, page in ipairs(props.pages) do
		local iconArt = page.iconArt and Style.Art(page.iconArt) or nil
		rows[page.id] = e(Parts.ChromeButton, {
			text = page.label,
			selected = page.id == props.selected,
			art = "sidebar_row",
			artSelected = "sidebar_row_selected",
			icon = iconArt and iconArt.Image or nil,
			iconSize = 32,
			iconInset = 26, -- clear of the plaque's bronze end cap
			Size = UDim2.new(1, 0, 0, ROW_H),
			LayoutOrder = i,
			textSize = labelSize,
			onClick = function() props.onSelect(page.id) end,
		})
	end
	local vines = Style.Art("sidebar_vines")
	return e(Parts.ArtFrame, {
		art = "sidebar_panel",
		flat = { color = Style.Flat.Sidebar, edge = Style.Flat.Edge, edgeTransparency = 0.25, corner = 8 },
		Size = UDim2.fromScale(1, 1),
		children = {
			-- The panel art keeps its painted shape (top-aligned beside the book) rather than
			-- stretching to the book's height: no seams through the vine, no squashed caps.
			Aspect = panelArt and e("UIAspectRatioConstraint", {
				AspectRatio = panelArt.Aspect,
				DominantAxis = Enum.DominantAxis.Width,
			}) or nil,
			Vines = vines and e("ImageLabel", {
				Position = UDim2.fromOffset(0, 0),
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Image = vines.Image,
				ScaleType = Enum.ScaleType.Fit,
				ZIndex = 1,
			}) or nil,
			Rows = e("Frame", {
				ref = rowsRef,
				Position = UDim2.fromOffset(PAD, PAD + 24),
				Size = UDim2.new(1, -PAD * 2, 1, -(PAD * 2 + 24)),
				BackgroundTransparency = 1,
				ZIndex = 2,
			}, rows),
		},
	})
end

return Sidebar
