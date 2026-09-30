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

local ROW_H = 50
local PAD = 18

local function Sidebar(props: { pages: { any }, selected: string, onSelect: (string) -> () })
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
			Size = UDim2.new(1, 0, 0, ROW_H),
			LayoutOrder = i,
			textSize = 18,
			onClick = function() props.onSelect(page.id) end,
		})
	end
	local vines = Style.Art("sidebar_vines")
	return e(Parts.ArtFrame, {
		art = "sidebar_panel",
		flat = { color = Style.Flat.Sidebar, edge = Style.Flat.Edge, edgeTransparency = 0.25, corner = 8 },
		Size = UDim2.fromScale(1, 1),
		children = {
			Vines = vines and e("ImageLabel", {
				Position = UDim2.fromOffset(0, 0),
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Image = vines.Image,
				ScaleType = Enum.ScaleType.Fit,
				ZIndex = 1,
			}) or nil,
			Rows = e("Frame", {
				Position = UDim2.fromOffset(PAD, PAD + 24),
				Size = UDim2.new(1, -PAD * 2, 1, -(PAD * 2 + 24)),
				BackgroundTransparency = 1,
				ZIndex = 2,
			}, rows),
		},
	})
end

return Sidebar
