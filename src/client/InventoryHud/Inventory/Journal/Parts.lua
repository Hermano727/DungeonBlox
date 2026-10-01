--!strict
--  Journal/Parts -- the small building blocks every Journal page is made of. Each one draws
--  its uploaded art (RS/Assets/Images/JournalUI via Style.Art) when it exists, else a flat
--  grey-box stand-in of the same size, so art lands piece by piece without layout changes.
--
--    ArtFrame     a plate: 9-slice / tiled / stretched art, or a flat rounded panel
--    ChromeButton a tab / chip / sidebar row / wide button (art key for normal + selected)
--    Heading      serif page heading
--    Divider      ink rule with a small diamond
--    HelpIcon     a circled "?" that shows a tooltip while hovered
--    Gem          rarity gem, bigger and brighter up the rarities; Epic/Legendary glow pulses
--    BarTrough    thin recessed track with a coloured fill (0..1)
--    SplitBar     one bar split between two shares (overworld moss / dungeon iron)
--    Text / List  plain page text, and a centred vertical stack
--    Medallion    a picture in the carved bronze ring (avatars, glyphs)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local React = require(ReplicatedStorage.Packages.React)
local Types = require(ReplicatedStorage:WaitForChild("ProfileTypes"))
local Style = require(script.Parent:WaitForChild("Style"))

local e = React.createElement
local Parts = {}

type FlatSpec = { color: Color3, edge: Color3?, edgeTransparency: number?, corner: number?, transparency: number? }

-- props: art (registry key), flat (FlatSpec), plus any GuiObject props (Size, Position, ...),
-- children.
function Parts.ArtFrame(props: any)
	local art = props.art and Style.Art(props.art) or nil
	local base = {
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		ZIndex = props.ZIndex,
		LayoutOrder = props.LayoutOrder,
		Visible = props.Visible,
		BorderSizePixel = 0,
	}
	local children = props.children or {}
	if art and art.Pad and art.SliceCenter then
		-- Glow around the plate: draw the art bigger than the box by the glow's size, so the
		-- plate itself fills the box exactly (lines up with the unselected state).
		local s = props.SliceScale or art.SliceScale or 1
		local l, t, r, b = art.Pad[1] * s, art.Pad[2] * s, art.Pad[3] * s, art.Pad[4] * s
		local inner = table.clone(children)
		inner.Art = e("ImageLabel", {
			Position = UDim2.fromOffset(-l, -t),
			Size = UDim2.new(1, l + r, 1, t + b),
			BackgroundTransparency = 1,
			Image = art.Image,
			ImageColor3 = props.ImageColor3,
			ImageTransparency = props.ImageTransparency or 0,
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = art.SliceCenter,
			SliceScale = s,
			ZIndex = props.ZIndex,
		})
		base.BackgroundTransparency = 1
		return e("Frame", base, inner)
	end
	if art then
		base.BackgroundTransparency = 1
		base.Image = art.Image
		base.ImageColor3 = props.ImageColor3
		base.ImageTransparency = props.ImageTransparency or 0
		if art.SliceCenter then
			base.ScaleType = Enum.ScaleType.Slice
			base.SliceCenter = art.SliceCenter
			base.SliceScale = props.SliceScale or art.SliceScale or 1
		elseif art.TileSize then
			base.ScaleType = Enum.ScaleType.Tile
			base.TileSize = UDim2.fromOffset(art.TileSize, art.TileSize)
		else
			base.ScaleType = Enum.ScaleType.Stretch
		end
		return e("ImageLabel", base, children)
	end
	local flat: FlatSpec = props.flat or { color = Style.Flat.Plate }
	base.BackgroundColor3 = flat.color
	base.BackgroundTransparency = flat.transparency or 0
	local merged = table.clone(children)
	merged.FlatCorner = e("UICorner", { CornerRadius = UDim.new(0, flat.corner or 6) })
	if flat.edge then
		merged.FlatEdge = e("UIStroke", {
			Color = flat.edge,
			Thickness = 1,
			Transparency = flat.edgeTransparency or 0.4,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		})
	end
	return e("Frame", base, merged)
end

-- props: text, selected, onClick, art ("chip"), artSelected ("chip_selected"), Size,
-- LayoutOrder, textSize, icon (image id, optional), disabled, dim (e.g. locked tabs)
function Parts.ChromeButton(props: any)
	local hovered, setHovered = React.useState(false)
	local selected = props.selected == true
	local disabled = props.disabled == true
	local flatColor = selected and Style.Flat.PlateOn or Style.Flat.Plate
	local textColor = disabled and Style.Chrome.Dim
		or (selected and Style.Chrome.Selected or (hovered and Style.Chrome.Selected or Style.Chrome.Label))
	local iconSize = props.icon and (props.iconSize or 22) or 0
	local iconInset = props.iconInset or 14
	return e("TextButton", {
		Size = props.Size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Active = not disabled,
		[React.Event.Activated] = function()
			if not disabled and props.onClick then props.onClick() end
		end,
		[React.Event.MouseEnter] = function() setHovered(true) end,
		[React.Event.MouseLeave] = function() setHovered(false) end,
	}, {
		Plate = e(Parts.ArtFrame, {
			art = selected and (props.artSelected or props.art) or props.art,
			flat = {
				color = flatColor,
				edge = Style.Flat.Edge,
				edgeTransparency = selected and 0.05 or (hovered and 0.3 or 0.65),
				corner = 5,
				transparency = disabled and 0.35 or 0,
			},
			ImageTransparency = disabled and 0.4 or 0,
			ZIndex = 1,
		}),
		Icon = props.icon and e("ImageLabel", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, iconInset, 0.5, 0),
			Size = UDim2.fromOffset(iconSize, iconSize),
			BackgroundTransparency = 1,
			Image = props.icon,
			ImageTransparency = disabled and 0.5 or 0,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 2,
		}) or nil,
		Label = e("TextLabel", {
			Position = UDim2.fromOffset(props.icon and (iconInset + iconSize + 8) or 0, 0),
			Size = UDim2.new(1, props.icon and -(iconInset + iconSize + 8) or 0, 1, 0),
			BackgroundTransparency = 1,
			Text = props.text,
			FontFace = Style.Font.Chrome,
			TextSize = props.textSize or 16,
			TextColor3 = textColor,
			TextXAlignment = props.icon and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center,
			ZIndex = 3,
		}),
		-- Locked (dimmed) tabs get the small lock once its art exists; the dim label says it
		-- until then.
		Lock = (props.locked and Style.Art("lock_icon")) and e("ImageLabel", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(14, 14),
			BackgroundTransparency = 1,
			Image = (Style.Art("lock_icon") :: any).Image,
			ImageTransparency = 0.2,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 3,
		}) or nil,
	})
end

function Parts.Heading(props: { text: string, size: number?, order: number?, align: Enum.TextXAlignment?, height: number? })
	return e("TextLabel", {
		LayoutOrder = props.order,
		Size = UDim2.new(1, 0, 0, props.height or 40),
		BackgroundTransparency = 1,
		Text = props.text,
		FontFace = Style.Font.Heading,
		TextSize = props.size or 30,
		TextColor3 = Style.Text.Heading,
		TextXAlignment = props.align or Enum.TextXAlignment.Center,
	})
end

function Parts.Divider(props: { order: number?, width: number? })
	local art = Style.Art("divider")
	local width = props.width or 0.8
	if art then
		return e("ImageLabel", {
			LayoutOrder = props.order,
			Size = UDim2.new(width, 0, 0, 14),
			BackgroundTransparency = 1,
			Image = art.Image,
			ImageColor3 = Style.OnPaper and Color3.new(1, 1, 1) or Color3.fromRGB(200, 180, 140),
			ScaleType = Enum.ScaleType.Fit,
		})
	end
	return e("Frame", {
		LayoutOrder = props.order,
		Size = UDim2.new(width, 0, 0, 14),
		BackgroundTransparency = 1,
	}, {
		Line = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Style.Text.Muted,
			BackgroundTransparency = 0.4,
			BorderSizePixel = 0,
		}),
		Diamond = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(7, 7),
			Rotation = 45,
			BackgroundColor3 = Style.OnPaper and Color3.fromRGB(214, 196, 160) or Style.Flat.Page,
			BorderSizePixel = 0,
		}, {
			Stroke = e("UIStroke", { Color = Style.Text.Muted, Thickness = 1 }),
		}),
	})
end

-- A circled "?" beside a heading; hovering it shows `text`.
local TIP_W = 280
local TIP_CHARS_PER_LINE = 38 -- at 14 px in TIP_W minus padding (Work Sans averages ~6.5 px a glyph)
function Parts.HelpIcon(props: { text: string, Position: UDim2?, AnchorPoint: Vector2? })
	local hovered, setHovered = React.useState(false)
	-- Explicit height: AutomaticSize + TextWrapped under the page's UIScale measured one line
	-- and cut the rest off.
	local lines = math.max(1, math.ceil(#props.text / TIP_CHARS_PER_LINE))
	local tipH = lines * 18 + 16
	return e("TextButton", {
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		Size = UDim2.fromOffset(22, 22),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "?",
		FontFace = Style.Font.BodyBold,
		TextSize = 15,
		TextColor3 = Style.Text.Muted,
		ZIndex = 5,
		[React.Event.MouseEnter] = function() setHovered(true) end,
		[React.Event.MouseLeave] = function() setHovered(false) end,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Ring = e("UIStroke", {
			Color = Style.Text.Muted,
			Thickness = 1.5,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Tip = hovered and e("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 1, 8),
			Size = UDim2.fromOffset(TIP_W, tipH),
			BackgroundColor3 = Color3.fromRGB(16, 12, 9),
			BackgroundTransparency = 0.05,
			BorderSizePixel = 0,
			Text = props.text,
			TextWrapped = true,
			FontFace = Style.Font.Body,
			TextSize = 14,
			TextColor3 = Color3.fromRGB(236, 226, 208),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 50,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 5) }),
			Pad = e("UIPadding", {
				PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
				PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
			}),
			Edge = e("UIStroke", { Color = Style.Flat.Edge, Transparency = 0.3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
		}) or nil,
	})
end

-- Size and glow climb with rarity (the blueprint's "gems escalate" rule).
local GEM = {
	Common    = { size = 20, glow = false },
	Uncommon  = { size = 23, glow = false },
	Rare      = { size = 27, glow = false },
	Epic      = { size = 31, glow = true },
	Legendary = { size = 36, glow = true },
}

function Parts.Gem(props: { rarity: string, scale: number?, Position: UDim2?, AnchorPoint: Vector2? })
	local spec = GEM[props.rarity] or GEM.Common
	local size = math.floor(spec.size * (props.scale or 1))
	local color = Types.GetRarityColor(props.rarity)
	local glowRef = React.useRef(nil :: GuiObject?)
	local art = Style.Art("gem_" .. string.lower(props.rarity))
	local glowArt = Style.Art("gem_glow")

	-- Epic / Legendary: the glow breathes.
	React.useEffect(function()
		local glow = glowRef.current
		if not glow or not spec.glow then return end
		local prop = glow:IsA("ImageLabel") and "ImageTransparency" or "Transparency"
		local target = glow:IsA("ImageLabel") and glow or glow:FindFirstChildOfClass("UIStroke")
		if not target then return end
		local tween = TweenService:Create(target, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ [prop] = 0.75 })
		tween:Play()
		return function() tween:Cancel() end
	end, { props.rarity })

	local children: { [string]: any } = {}
	if spec.glow then
		if glowArt then
			children.Glow = e("ImageLabel", {
				ref = glowRef,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(2.2, 2.2),
				BackgroundTransparency = 1,
				Image = glowArt.Image,
				ImageColor3 = color,
				ImageTransparency = 0.35,
				ZIndex = 1,
			})
		else
			children.Glow = e("Frame", {
				ref = glowRef,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.72, 0.72),
				Rotation = 45,
				BackgroundTransparency = 1,
				ZIndex = 1,
			}, {
				Stroke = e("UIStroke", { Color = color, Thickness = 5, Transparency = 0.35 }),
			})
		end
	end
	if art then
		children.Stone = e("ImageLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = art.Image,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 2,
		})
	else
		children.Stone = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.68, 0.68),
			Rotation = 45,
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = 2,
		}, {
			Edge = e("UIStroke", { Color = Color3.fromRGB(12, 9, 6), Thickness = 1.5, Transparency = 0.2 }),
			Shine = e("UIGradient", {
				Rotation = 45,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(1, props.rarity == "Common" and 0.35 or 0.1),
				}),
				Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 150)),
			}),
		})
	end
	return e("Frame", {
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
	}, children)
end

function Parts.BarTrough(props: { fill: number, color: Color3, Size: UDim2?, Position: UDim2?, AnchorPoint: Vector2? })
	local inset = Style.Art("bar_trough") and 4 or 2 -- the art's bronze rim is ~3 px on screen
	local fill = math.clamp(props.fill, 0, 1)
	return e(Parts.ArtFrame, {
		art = "bar_trough",
		flat = { color = Style.Flat.Trough, edge = Style.Flat.Edge, edgeTransparency = 0.6, corner = 4 },
		Size = props.Size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		children = {
			Fill = e("Frame", {
				Position = UDim2.fromOffset(inset, inset),
				Size = UDim2.new(fill, -inset * 2 * fill, 1, -inset * 2),
				BackgroundColor3 = props.color,
				BorderSizePixel = 0,
				ZIndex = 2,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, 3) }),
				Sheen = e("UIGradient", {
					Rotation = 90,
					Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170)),
				}),
			}),
		},
	})
end

-- Plain text on a page (ink colours from Style). props: text, order, Position, AnchorPoint,
-- Size (or height), size, font, color, align, alignY, wrap, rich, truncate, ZIndex.
function Parts.Text(props: any)
	return e("TextLabel", {
		LayoutOrder = props.order,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		Size = props.Size or UDim2.new(1, 0, 0, props.height or 22),
		BackgroundTransparency = 1,
		Text = props.text,
		RichText = props.rich == true,
		TextWrapped = props.wrap == true,
		TextTruncate = props.truncate and Enum.TextTruncate.AtEnd or nil,
		FontFace = props.font or Style.Font.Body,
		TextSize = props.size or 16,
		TextColor3 = props.color or Style.Text.Body,
		TextXAlignment = props.align or Enum.TextXAlignment.Center,
		TextYAlignment = props.alignY or Enum.TextYAlignment.Center,
		ZIndex = props.ZIndex,
	})
end

-- A page-filling vertical stack, centred (short pages sit mid-page, not top-heavy).
function Parts.List(padding: number, children: { [string]: any }, valign: Enum.VerticalAlignment?)
	children.Layout = e("UIListLayout", {
		Padding = UDim.new(0, padding),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = valign or Enum.VerticalAlignment.Center,
	})
	return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, children)
end

-- A picture in a carved bronze ring (nav_medallion; nav_medallion_selected when lit): player
-- avatars (round = true crops the picture to a circle), the hearthstone / party glyphs.
function Parts.Medallion(props: { image: string?, size: number, lit: boolean?, round: boolean?, imageScale: number?,
	order: number?, Position: UDim2?, AnchorPoint: Vector2?, dim: boolean? })
	local art = Style.Art(props.lit and "nav_medallion_selected" or "nav_medallion")
	local ring
	if art and art.Pad and art.Width then
		local w, h = art.Width, art.Width / art.Aspect
		local l, t, r, b = art.Pad[1], art.Pad[2], art.Pad[3], art.Pad[4]
		local iw, ih = w - l - r, h - t - b
		ring = e("ImageLabel", {
			Position = UDim2.fromScale(-l / iw, -t / ih), Size = UDim2.fromScale(w / iw, h / ih),
			BackgroundTransparency = 1, Image = art.Image, ImageTransparency = props.dim and 0.35 or 0, ZIndex = 2,
		})
	elseif art then
		ring = e("ImageLabel", {
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = art.Image,
			ImageTransparency = props.dim and 0.35 or 0, ZIndex = 2,
		})
	else
		ring = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2 }, {
			Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Edge = e("UIStroke", { Color = Style.Flat.Edge, Thickness = 2 }),
		})
	end
	local inner = props.imageScale or (props.round and 0.7 or 0.52)
	return e("Frame", {
		LayoutOrder = props.order,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		Size = UDim2.fromOffset(props.size, props.size),
		BackgroundTransparency = 1,
	}, {
		Picture = (props.image and props.image ~= "") and e("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(inner, inner),
			BackgroundColor3 = Style.Flat.Trough,
			BackgroundTransparency = props.round and 0 or 1,
			Image = props.image,
			ImageTransparency = props.dim and 0.4 or 0,
			ScaleType = props.round and Enum.ScaleType.Crop or Enum.ScaleType.Fit,
			ZIndex = props.round and 1 or 3,
		}, {
			Corner = props.round and e("UICorner", { CornerRadius = UDim.new(1, 0) }) or nil,
		}) or nil,
		Ring = ring,
	})
end

function Parts.SplitBar(props: { a: number, b: number, height: number?, order: number? })
	local total = math.max(0, props.a) + math.max(0, props.b)
	local share = total > 0 and (math.max(0, props.a) / total) or 0.5
	local height = props.height or 20
	return e(Parts.ArtFrame, {
		-- its own ornate frame once one exists; the thin bar track until then
		art = Style.Art("split_bar_frame") and "split_bar_frame" or "bar_trough",
		flat = { color = Style.Flat.Trough, edge = Style.Flat.Edge, edgeTransparency = 0.3, corner = 5 },
		Size = UDim2.new(1, 0, 0, height),
		LayoutOrder = props.order,
		children = {
			Inner = e("Frame", {
				Position = UDim2.fromOffset(4, 4),
				Size = UDim2.new(1, -8, 1, -8),
				BackgroundTransparency = 1,
				ZIndex = 2,
			}, {
				Overworld = total > 0 and e("Frame", {
					Size = UDim2.fromScale(share, 1),
					BackgroundColor3 = Style.Split.Overworld,
					BorderSizePixel = 0,
				}) or nil,
				Dungeon = total > 0 and e("Frame", {
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.fromScale(1, 0),
					Size = UDim2.fromScale(1 - share, 1),
					BackgroundColor3 = Style.Split.Dungeon,
					BorderSizePixel = 0,
				}) or nil,
			}),
		},
	})
end

return Parts
