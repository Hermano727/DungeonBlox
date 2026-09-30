--!strict
--  Journal/Book -- the open book every Journal page is drawn in: a leather cover, two paper
--  pages with the spine between them, and an optional row of bookmark tabs standing on the
--  cover's top edge (the tier tabs: they filter BOTH pages, so they belong to the book, not
--  to one page).
--
--    e(Book, { tabs = element?, left = element, right = element })
--
--  The spread keeps Style.BOOK_ASPECT (about 2:1) at any screen size, capped at
--  Style.BOOK_MAX, centred in whatever space it's given. Each page's content gets a padded
--  frame; lay it out with a UIListLayout or explicit positions.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Style = require(script.Parent:WaitForChild("Style"))
local Parts = require(script.Parent:WaitForChild("Parts"))

local e = React.createElement

local COVER_INSET = 18 -- leather visible around the pages
local SPINE_W = 26
local TAB_OVERLAP = 6  -- tabs sink this far into the cover's top edge

local function Page(props: { side: string, content: any })
	local isLeft = props.side == "left"
	return e(Parts.ArtFrame, {
		art = "page_paper",
		flat = { color = Style.Flat.Page, corner = 4 },
		Position = isLeft and UDim2.fromOffset(COVER_INSET, COVER_INSET)
			or UDim2.new(0.5, SPINE_W / 2, 0, COVER_INSET),
		Size = UDim2.new(0.5, -(COVER_INSET + SPINE_W / 2), 1, -COVER_INSET * 2),
		ZIndex = 2,
		children = {
			Content = e("Frame", {
				Position = UDim2.fromOffset(Style.PAGE_PAD, Style.PAGE_PAD - 8),
				Size = UDim2.new(1, -Style.PAGE_PAD * 2, 1, -(Style.PAGE_PAD * 2 - 8)),
				BackgroundTransparency = 1,
				ZIndex = 3,
			}, { Body = props.content }),
		},
	})
end

local function Book(props: { tabs: any?, left: any, right: any })
	local tabH = props.tabs and Style.TAB_H or 0
	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		Spread = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		}, {
			Aspect = e("UIAspectRatioConstraint", { AspectRatio = Style.BOOK_ASPECT }),
			Max = e("UISizeConstraint", { MaxSize = Style.BOOK_MAX }),

			Tabs = props.tabs and e("Frame", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0),
				Size = UDim2.new(1, -120, 0, Style.TAB_H),
				BackgroundTransparency = 1,
				ZIndex = 6,
			}, { Row = props.tabs }) or nil,

			Cover = e(Parts.ArtFrame, {
				art = "book_cover",
				flat = { color = Style.Flat.Cover, edge = Style.Flat.CoverEdge, edgeTransparency = 0.2, corner = 10 },
				Position = UDim2.fromOffset(0, math.max(0, tabH - TAB_OVERLAP)),
				Size = UDim2.new(1, 0, 1, -math.max(0, tabH - TAB_OVERLAP)),
				ZIndex = 1,
				children = {
					Left = e(Page, { side = "left", content = props.left }),
					Right = e(Page, { side = "right", content = props.right }),
					Spine = e(Parts.ArtFrame, {
						art = "book_spine",
						flat = { color = Style.Flat.Spine, corner = 2 },
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.new(0.5, 0, 0, COVER_INSET - 6),
						Size = UDim2.new(0, SPINE_W, 1, -(COVER_INSET - 6) * 2),
						ZIndex = 4,
					}),
				},
			}),
		}),
	})
end

return Book
