--!strict
--  Journal/Book -- the open book every Journal page is drawn in: a leather cover, two paper
--  pages with the spine between them, and an optional row of bookmark tabs standing on the
--  cover's top edge (the tier tabs: they filter BOTH pages, so they belong to the book, not
--  to one page).
--
--    e(Book, { tabs = element?, left = element, right = element, side = element?, ribbons = element? })
--
--  `side` (the Journal sidebar) hangs off the spread's LEFT edge, outside it, so the book
--  itself stays centred under the Tab menu's top row. `ribbons` (the Stats page's category
--  bookmarks) hang off the RIGHT edge, tucked under the cover: give it a vertical stack, it
--  gets a column Style.RIBBON_W wide (a share of the book's width, so it scales with it).
--
--  The spread keeps Style.BOOK_ASPECT (about 2:1) at any screen size, capped at
--  Style.BOOK_MAX, centred in whatever space it's given. Each page's content is laid out on
--  a fixed Style.PAGE_DESIGN canvas and scaled (UIScale) to fit the page: design pages in
--  those pixels and they fit every window size.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Style = require(script.Parent:WaitForChild("Style"))
local Parts = require(script.Parent:WaitForChild("Parts"))

local e = React.createElement

local COVER_INSET = 18 -- leather visible around the pages
local SPINE_W = 8 -- the gap between the pages (the blueprint's thin crease, shaded below)
local TAB_OVERLAP = 6  -- tabs sink this far into the cover's top edge

-- Fits a Style.PAGE_DESIGN-sized canvas into whatever space the page has, keeping its shape.
local function ScaledCanvas(props: { content: any })
	local outerRef = React.useRef(nil :: Frame?)
	local scale, setScale = React.useState(1)
	React.useEffect(function()
		local outer = outerRef.current
		if not outer then return end
		local function fit()
			local size = outer.AbsoluteSize
			if size.X <= 0 or size.Y <= 0 then return end
			setScale(math.min(size.X / Style.PAGE_DESIGN.X, size.Y / Style.PAGE_DESIGN.Y))
		end
		fit()
		local conn = outer:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		return function() conn:Disconnect() end
	end, {})
	return e("Frame", {
		ref = outerRef,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		Canvas = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(Style.PAGE_DESIGN.X, Style.PAGE_DESIGN.Y),
			BackgroundTransparency = 1,
		}, {
			Scale = e("UIScale", { Scale = scale }),
			Body = props.content,
		}),
	})
end

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
			}, { Body = e(ScaledCanvas, { content = props.content }) }),
		},
	})
end

local SIDE_GAP = 22 -- between `side` and the book's cover

local function Book(props: { tabs: any?, left: any, right: any, side: any?, ribbons: any? })
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

			Side = props.side and e("Frame", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(0, -SIDE_GAP, 0, tabH),
				Size = UDim2.new(0, Style.SIDEBAR_W, 1, -tabH),
				BackgroundTransparency = 1,
			}, { Body = props.side }) or nil,

			-- ZIndex 0: behind the cover, so the tucked-in end of each ribbon disappears under it.
			Ribbons = props.ribbons and e("Frame", {
				Position = UDim2.new(1 - Style.RIBBON_W * Style.RIBBON_TUCK, 0, 0, tabH + 46),
				Size = UDim2.new(Style.RIBBON_W, 0, 1, -(tabH + 92)),
				BackgroundTransparency = 1,
				ZIndex = 0,
			}, { Stack = props.ribbons }) or nil,

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
					-- On parchment (and with no spine art) the fold is a soft shadow across both
					-- page edges; on the grey-box pages, a flat dark strip.
					Spine = (Style.OnPaper and not Style.Art("book_spine")) and e("Frame", {
						AnchorPoint = Vector2.new(0.5, 0),
						Position = UDim2.new(0.5, 0, 0, COVER_INSET),
						Size = UDim2.new(0, SPINE_W + 70, 1, -COVER_INSET * 2),
						BackgroundColor3 = Color3.fromRGB(28, 18, 10),
						BorderSizePixel = 0,
						ZIndex = 4,
					}, {
						Shade = e("UIGradient", {
							Transparency = NumberSequence.new({
								NumberSequenceKeypoint.new(0, 1),
								NumberSequenceKeypoint.new(0.4, 0.55),
								NumberSequenceKeypoint.new(0.5, 0.05),
								NumberSequenceKeypoint.new(0.6, 0.55),
								NumberSequenceKeypoint.new(1, 1),
							}),
						}),
					}) or e(Parts.ArtFrame, {
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
