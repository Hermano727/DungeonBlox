--!strict
--  StatsPage -- the Journal's "Stats" page: combat stats only (skill levels live on Skills,
--  coins in the inventory). Drawn in Journal/Book with category ribbons hanging off the
--  book's right edge; each ribbon is one spread:
--
--    Overview  left  Character: the rotatable 3D portrait (CharacterViewport, drag to turn)
--                    over the painted backdrop, and the STR / INT / DEX / VIT medallions (the
--                    one boosting your current weapon is lit)
--              right Summary: one clickable row per category (jumps to its ribbon), plus
--                    Coin Find
--    Defense   left  Health, HP Regen, Energy Regen, Armor (as % less damage), Block vs its cap
--              right what each armor slot adds (HP / Armor / Block) and the totals
--    Melee     left  the Weapon slot's weapon: card, damage per hit (hover: the breakdown), the
--                    attribute that boosts it and progress to its next step
--              right its effects, each with what it actually does
--    Ranged    the same for the Bow slot
--    Mount     left  your fastest saddle vs sprinting, or where to get one (Show on map ->
--                    the world map pinned on the Animal Trainer, RS/WorldMapRequest)
--              right every saddle tier, owned ones marked
--
--  Weapons are shown "currently equipped": as if wielded from their slot. DISPLAY ONLY; the
--  game applies a weapon's stats only while it is held (see RS/StatsSheet).
--  All numbers come from RS/StatsSheet.Compute(snapshot), which mirrors the combat maths.
--  Every number has a hover tip saying where it comes from.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Types = require(ReplicatedStorage:WaitForChild("ProfileTypes"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local ItemConfig = require(ReplicatedStorage:WaitForChild("ItemConfig"))
local EnergyConfig = require(ReplicatedStorage:WaitForChild("EnergyConfig"))
local StatsSheet = require(ReplicatedStorage:WaitForChild("StatsSheet"))
local WorldMapRequest = require(ReplicatedStorage:WaitForChild("WorldMapRequest"))
local InventoryData = require(script.Parent:WaitForChild("InventoryData"))
local CharacterViewport = require(script.Parent:WaitForChild("CharacterViewport"))
local Journal = script.Parent:WaitForChild("Journal")
local Style = require(Journal:WaitForChild("Style"))
local Parts = require(Journal:WaitForChild("Parts"))
local TipLayer = require(Journal:WaitForChild("TipLayer"))
local Book = require(Journal:WaitForChild("Book"))

local e = React.createElement

local CATEGORIES = {
	{ id = "overview", label = "Overview", icon = "icon_cat_overview" },
	{ id = "defense",  label = "Defense",  icon = "icon_cat_defense" },
	{ id = "melee",    label = "Melee",    icon = "icon_cat_melee" },
	{ id = "ranged",   label = "Ranged",   icon = "icon_cat_ranged" },
	{ id = "mount",    label = "Mount",    icon = "icon_cat_mount" },
}

local PER_200_PCT = ItemConfig.ARMOR_SUBSTAT_DMG_PER_200 * 100 -- damage % per 200 points of an attribute (smooth)
local SADDLE_TIERS = 5 -- T<n>MountSaddle ids looked up in ItemDefinitions; missing tiers are skipped

------------------------------------------------------------------------------------------
-- Formatting
------------------------------------------------------------------------------------------

local function num(n: number, dp: number?): string
	local s = string.format("%." .. tostring(dp or 1) .. "f", n)
	s = string.gsub(s, "%.?0+$", "")
	return s
end

local function pct(n: number): string
	return num(n, 1) .. "%"
end

local function range(lo: number, hi: number): string
	return tostring(lo) .. " - " .. tostring(hi)
end

local function sources(list: { any }, unit: string?): string
	if #list == 0 then return "None of your gear adds to it." end
	local parts = {}
	for _, src in ipairs(list) do
		table.insert(parts, src.slot .. " " .. num(src.value, 2) .. (unit or ""))
	end
	return "From gear: " .. table.concat(parts, ", ")
end

------------------------------------------------------------------------------------------
-- Small pieces
------------------------------------------------------------------------------------------

local function text(props: any)
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

local function list(padding: number, children: { [string]: any }, valign: Enum.VerticalAlignment?)
	children.Layout = e("UIListLayout", {
		Padding = UDim.new(0, padding),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = valign or Enum.VerticalAlignment.Center,
	})
	return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, children)
end

local function artImage(key: string): string?
	local art = Style.Art(key)
	return art and art.Image or nil
end

-- An art piece with a glow margin (Pad, in source px of a Width x Width/Aspect image), drawn so
-- the plate itself fills its box exactly: the position + size, as scales of that box.
local function padScale(art: any): (UDim2, UDim2)
	local w = art.Width
	local h = w / art.Aspect
	local l, t, r, b = art.Pad[1], art.Pad[2], art.Pad[3], art.Pad[4]
	local innerW, innerH = w - l - r, h - t - b
	return UDim2.fromScale(-l / innerW, -t / innerH), UDim2.fromScale(w / innerW, h / innerH)
end

-- Hover tips: a small card, { title, lines = { ... }?, foot = string? }. A title in the
-- book's serif, a rule, the plain-language lines, then where it comes from (muted).
-- Explicit heights (see Parts.HelpIcon: AutomaticSize under the page's UIScale measures one
-- line), estimated from the text length.
export type Tip = { title: string, lines: { string }?, foot: string? }

local TIP_W = 280
local TIP_PAD = 12
local TIP_CHARS = 36 -- per line at 14 px in TIP_W minus padding
local TIP_INK = {
	Bg = Color3.fromRGB(22, 16, 11),
	Edge = Color3.fromRGB(176, 136, 76),
	Title = Color3.fromRGB(240, 214, 160),
	Body = Color3.fromRGB(228, 218, 200),
	Foot = Color3.fromRGB(150, 136, 114),
}

local function wrapHeight(str: string, lineH: number): number
	return math.max(1, math.ceil(#str / TIP_CHARS)) * lineH
end

local function TipLabel(props: { tip: Tip, above: boolean?, anchor: GuiObject? })
	local tip = props.tip
	local rows: { [string]: any } = {
		Layout = e("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
		Title = e("TextLabel", {
			LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1,
			Text = tip.title, FontFace = Style.Font.Heading, TextSize = 16, TextColor3 = TIP_INK.Title,
			TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 51,
		}),
		Rule = e("Frame", {
			LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = TIP_INK.Edge,
			BackgroundTransparency = 0.55, BorderSizePixel = 0, ZIndex = 51,
		}),
	}
	local height = TIP_PAD * 2 + 20 + 4 + 1 + 4
	for i, line in ipairs(tip.lines or {}) do
		local h = wrapHeight(line, 18)
		height += h + 4
		rows["L" .. i] = e("TextLabel", {
			LayoutOrder = 2 + i, Size = UDim2.new(1, 0, 0, h), BackgroundTransparency = 1,
			Text = line, TextWrapped = true, FontFace = Style.Font.Body, TextSize = 14, TextColor3 = TIP_INK.Body,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 51,
		})
	end
	if tip.foot and tip.foot ~= "" then
		local h = wrapHeight(tip.foot, 17)
		height += h + 6
		rows.Foot = e("TextLabel", {
			LayoutOrder = 100, Size = UDim2.new(1, 0, 0, h + 2), BackgroundTransparency = 1,
			Text = tip.foot, TextWrapped = true, FontFace = Style.Font.Body, TextSize = 13, TextColor3 = TIP_INK.Foot,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Bottom, ZIndex = 51,
		})
	end
	-- Drawn in TipLayer (above the whole menu) at the hovered element, not inside the page.
	return e(TipLayer.Floating, { anchor = props.anchor, above = props.above, width = TIP_W, height = height }, { Card = e("Frame", {
		Size = UDim2.fromOffset(TIP_W, height),
		BackgroundColor3 = TIP_INK.Bg,
		BackgroundTransparency = 0.03,
		BorderSizePixel = 0,
		ZIndex = 50,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0, 4) }),
		Edge = e("UIStroke", { Color = TIP_INK.Edge, Thickness = 1.5, Transparency = 0.2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
		Pad = e("UIPadding", {
			PaddingLeft = UDim.new(0, TIP_PAD), PaddingRight = UDim.new(0, TIP_PAD),
			PaddingTop = UDim.new(0, TIP_PAD), PaddingBottom = UDim.new(0, TIP_PAD),
		}),
		Rows = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 51 }, rows),
	}) })
end

-- A box that shows `tip` while hovered. Raises itself above its siblings while the tip is up.
local function Hover(props: any)
	local hovered, setHovered = React.useState(false)
	local ref = React.useRef(nil)
	local children = table.clone(props.children or {})
	if hovered and type(props.tip) == "table" then
		children.Tip = e(TipLabel, { tip = props.tip, above = props.above, anchor = ref.current })
	end
	return e("Frame", {
		ref = ref,
		LayoutOrder = props.order,
		Size = props.Size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		BackgroundTransparency = 1,
		ZIndex = hovered and 20 or 1,
		[React.Event.MouseEnter] = function() setHovered(true) end,
		[React.Event.MouseLeave] = function() setHovered(false) end,
	}, children)
end

local function Icon(props: { art: string?, image: string?, size: number, Position: UDim2?, AnchorPoint: Vector2?, order: number? })
	local image = props.image or (props.art and artImage(props.art)) or nil
	if not image then
		return e("Frame", {
			LayoutOrder = props.order, Position = props.Position, AnchorPoint = props.AnchorPoint,
			Size = UDim2.fromOffset(props.size, props.size), BackgroundTransparency = 1,
		})
	end
	return e("ImageLabel", {
		LayoutOrder = props.order,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		Size = UDim2.fromOffset(props.size, props.size),
		BackgroundTransparency = 1,
		Image = image,
		ScaleType = Enum.ScaleType.Fit,
	})
end

-- An item's icon in a dark box edged in its rarity colour; `fallbackArt` (a JournalUI key) when
-- the item has no icon of its own (saddles).
local function ItemIcon(props: { item: any?, image: string?, rarity: string?, size: number, Position: UDim2?, AnchorPoint: Vector2?, dim: boolean?, fallbackArt: string? })
	local image = props.image or (props.item and ItemDefinitions.GetIconForItem(props.item)) or nil
	if (image == nil or image == "") and props.fallbackArt then image = artImage(props.fallbackArt) end
	if image == "" then image = nil end
	local rarity = props.rarity or (props.item and props.item.rarity) or nil
	return e("Frame", {
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		Size = UDim2.fromOffset(props.size, props.size),
		BackgroundColor3 = Style.Flat.Trough,
		BackgroundTransparency = props.dim and 0.4 or 0,
		BorderSizePixel = 0,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0, 5) }),
		Edge = e("UIStroke", {
			Color = rarity and Types.GetRarityColor(rarity) or Style.Flat.Edge,
			Thickness = 2,
			Transparency = props.dim and 0.6 or (rarity and 0 or 0.5),
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Image = image and e("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.82, 0.82),
			BackgroundTransparency = 1,
			Image = image,
			ImageTransparency = props.dim and 0.55 or 0,
			ScaleType = Enum.ScaleType.Fit,
		}) or nil,
	})
end

local function Empty(props: { title: string, body: string })
	return list(8, {
		Title = text({ text = props.title, font = Style.Font.Heading, size = 20, color = Style.Text.Heading, height = 28, order = 1 }),
		Body = text({ text = props.body, size = 15, color = Style.Text.Muted, wrap = true, height = 44, order = 2 }),
	})
end

------------------------------------------------------------------------------------------
-- Ribbons (the category bookmarks on the book's right edge)
------------------------------------------------------------------------------------------

local function Ribbon(props: { cat: any, selected: boolean, onClick: () -> (), order: number })
	local hovered, setHovered = React.useState(false)
	local art = Style.Art(props.selected and "ribbon_selected" or "ribbon")
	-- Slides further out from under the cover when hovered / selected.
	local out = props.selected and 0.16 or (hovered and 0.08 or 0)

	local plate
	if art and art.Pad then
		local pos, size = padScale(art)
		plate = e("ImageLabel", {
			Position = pos, Size = size, BackgroundTransparency = 1, Image = art.Image, ScaleType = Enum.ScaleType.Stretch,
		})
	elseif art then
		plate = e("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = art.Image, ScaleType = Enum.ScaleType.Stretch })
	else
		plate = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = props.selected and Style.Flat.PlateOn or Style.Flat.Cover,
			BorderSizePixel = 0,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 6) }),
			Edge = e("UIStroke", { Color = Style.Flat.Edge, Transparency = props.selected and 0.1 or 0.5 }),
		})
	end

	return e("TextButton", {
		LayoutOrder = props.order,
		Size = UDim2.fromScale(1, 0.2),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		[React.Event.Activated] = props.onClick,
		[React.Event.MouseEnter] = function() setHovered(true) end,
		[React.Event.MouseLeave] = function() setHovered(false) end,
	}, {
		Aspect = e("UIAspectRatioConstraint", { AspectRatio = 445 / 722, DominantAxis = Enum.DominantAxis.Width }),
		Body = e("Frame", {
			Position = UDim2.fromScale(out, 0),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		}, {
			Plate = plate,
			-- Centred on the part that shows past the cover (the left Style.RIBBON_TUCK is under it).
			Icon = e("ImageLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				-- Centred on what shows: from the cover's edge (RIBBON_TUCK) to where the notch begins.
				Position = UDim2.fromScale((Style.RIBBON_TUCK + 0.84) / 2, 0.5),
				Size = UDim2.fromScale(0.52, 0.52 * 445 / 722),
				BackgroundTransparency = 1,
				Image = artImage(props.cat.icon) or "",
				ImageTransparency = (props.selected or hovered) and 0 or 0.2,
				ScaleType = Enum.ScaleType.Fit,
				ZIndex = 2,
			}),
			Label = hovered and e("TextLabel", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(1, 8, 0.5, 0),
				Size = UDim2.fromOffset(0, 26),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundColor3 = Color3.fromRGB(16, 12, 9),
				BackgroundTransparency = 0.05,
				BorderSizePixel = 0,
				Text = props.cat.label,
				FontFace = Style.Font.Chrome,
				TextSize = 15,
				TextColor3 = Style.Chrome.Selected,
				ZIndex = 5,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(0, 4) }),
				Pad = e("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
				Edge = e("UIStroke", { Color = Style.Flat.Edge, Transparency = 0.35, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
			}) or nil,
		}),
	})
end

local function Ribbons(props: { selected: string, onSelect: (string) -> () })
	local children: { [string]: any } = {
		Layout = e("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	}
	for i, cat in ipairs(CATEGORIES) do
		children[cat.id] = e(Ribbon, {
			cat = cat,
			selected = cat.id == props.selected,
			order = i,
			onClick = function() props.onSelect(cat.id) end,
		})
	end
	return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, children)
end

------------------------------------------------------------------------------------------
-- Overview
------------------------------------------------------------------------------------------


local function Medallion(props: { attr: string, value: number, lit: boolean, tip: Tip, order: number })
	local size = 58
	local art = Style.Art(props.lit and "nav_medallion_selected" or "nav_medallion")
	local ring
	if art and art.Pad then
		local pos, sz = padScale(art)
		ring = e("ImageLabel", { Position = pos, Size = sz, BackgroundTransparency = 1, Image = art.Image })
	elseif art then
		ring = e("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = art.Image })
	else
		ring = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = props.lit and Style.Flat.PlateOn or Style.Flat.Plate,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Edge = e("UIStroke", { Color = Style.Flat.Edge, Thickness = props.lit and 2 or 1, Transparency = props.lit and 0 or 0.5 }),
		})
	end
	local glyph = artImage("attr_" .. props.attr)
	return e(Hover, {
		order = props.order,
		Size = UDim2.fromOffset(96, size + 26),
		tip = props.tip,
		above = true,
		children = {
			Ring = e("Frame", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromScale(0.5, 0),
				Size = UDim2.fromOffset(size, size),
				BackgroundTransparency = 1,
			}, {
				Plate = ring,
				Glyph = glyph and e("ImageLabel", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromScale(0.5, 0.5),
					BackgroundTransparency = 1,
					Image = glyph,
					ScaleType = Enum.ScaleType.Fit,
					ZIndex = 2,
				}) or text({
					text = StatsSheet.ATTRIBUTE_LABEL[props.attr],
					font = Style.Font.Chrome,
					size = 15,
					color = props.lit and Style.Chrome.Selected or Style.Chrome.Label,
					Size = UDim2.fromScale(1, 1),
					ZIndex = 2,
				}),
			}),
			Value = text({
				text = tostring(math.floor(props.value)),
				font = Style.Font.Number,
				size = 18,
				color = props.lit and Style.Text.Heading or Style.Text.Body,
				Position = UDim2.fromOffset(0, size + 2),
				height = 22,
			}),
		},
	})
end

local function Portrait(props: { equipped: any })
	local backdrop = artImage("stats_backdrop")
	return e("Frame", {
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 286),
		BackgroundTransparency = 1,
	}, {
		Backdrop = e("ImageLabel", {
			Position = UDim2.fromOffset(12, 12),
			Size = UDim2.new(1, -24, 1, -24),
			BackgroundColor3 = Style.Flat.Trough,
			BackgroundTransparency = backdrop and 1 or 0,
			Image = backdrop or "",
			ScaleType = Enum.ScaleType.Crop,
			ZIndex = 1,
		}),
		Viewport = e(CharacterViewport, {
			equipped = props.equipped,
			size = UDim2.new(1, -24, 1, -24),
			position = UDim2.fromOffset(12, 12),
			zIndex = 2,
			rotatable = true,
		}),
		Frame = e(Parts.ArtFrame, {
			art = "card_frame",
			flat = { color = Style.Flat.Trough, edge = Style.Flat.Edge, edgeTransparency = 0.2, corner = 6, transparency = 1 },
			ZIndex = 3,
		}),
		Hint = text({
			text = "Drag to turn",
			size = 13,
			color = Color3.fromRGB(236, 226, 208),
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -18),
			Size = UDim2.fromOffset(120, 18),
			ZIndex = 4,
		}),
	})
end

local function attributeTip(sheet: any, key: string): Tip
	local total = sheet.attributes[key]
	local label = StatsSheet.ATTRIBUTE_LABEL[key]
	local weapon = string.lower(sheet.attributeWeapon[key])
	return {
		title = ("%s %d"):format(label, total),
		lines = {
			("+%s %s damage"):format(pct(total / 200 * sheet.per200), weapon),
			("Every 200 %s adds %s, counted point by point."):format(label, pct(sheet.per200)),
		},
		foot = sources(sheet.attributeSources[key]),
	}
end

local function CharacterSpread(props: { sheet: any, equipped: any })
	local sheet = props.sheet
	local litKey = sheet.melee and sheet.melee.attrKey or nil
	local medallions: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 12),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for i, key in ipairs(StatsSheet.ATTRIBUTES) do
		medallions[key] = e(Medallion, {
			attr = key, -- not `key`: React keeps that prop for itself
			value = sheet.attributes[key],
			lit = key == litKey,
			tip = attributeTip(sheet, key),
			order = i,
		})
	end
	return list(8, {
		Heading = e(Parts.Heading, { text = "Character", size = 26, order = 1, height = 32 }),
		Portrait = e(Portrait, { equipped = props.equipped }),
		Attributes = e("Frame", { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 84), BackgroundTransparency = 1 }, medallions),
	})
end

local function SummaryRow(props: { icon: string, title: string, value: string, tip: Tip?, onClick: (() -> ())?, order: number })
	local hovered, setHovered = React.useState(false)
	local rowRef = React.useRef(nil)
	local clickable = props.onClick ~= nil
	local body = {
		Icon = e(Icon, { art = props.icon, size = 38, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 6, 0.5, 0) }),
		Title = text({
			text = props.title, font = Style.Font.Heading, size = 18, color = Style.Text.Heading,
			align = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(56, 8), Size = UDim2.new(1, -90, 0, 22),
		}),
		Value = text({
			text = props.value, size = 15, color = Style.Text.Body, truncate = true,
			align = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(56, 30), Size = UDim2.new(1, -90, 0, 20),
		}),
		Arrow = clickable and text({
			text = ">", font = Style.Font.Heading, size = 20,
			color = hovered and Style.Text.Heading or Style.Text.Muted,
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(20, 24),
		}) or nil,
		Rule = e("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Style.Text.Muted,
			BackgroundTransparency = 0.7,
			BorderSizePixel = 0,
		}),
		Tip = (hovered and props.tip) and e(TipLabel, { tip = props.tip, anchor = rowRef.current }) or nil,
	}
	local base: { [any]: any } = {
		LayoutOrder = props.order,
		Size = UDim2.new(1, 0, 0, 60),
		BackgroundColor3 = Style.Text.Heading,
		BackgroundTransparency = (clickable and hovered) and 0.92 or 1,
		BorderSizePixel = 0,
		ZIndex = hovered and 20 or 1,
		ref = rowRef,
		[React.Event.MouseEnter] = function() setHovered(true) end,
		[React.Event.MouseLeave] = function() setHovered(false) end,
	}
	if clickable then
		base.Text = ""
		base.AutoButtonColor = false
		base[React.Event.Activated] = props.onClick
		return e("TextButton", base, body)
	end
	return e("Frame", base, body)
end

local function weaponLine(w: any?): string
	if not w then return "Nothing equipped" end
	return range(w.lo, w.hi) .. " damage" .. (w.weaponType and (", " .. w.weaponType) or "")
end

local function SummarySpread(props: { sheet: any, go: (string) -> () })
	local sheet = props.sheet
	local mount = sheet.mount
	return list(4, {
		Heading = e(Parts.Heading, { text = "Summary", size = 26, order = 1, height = 40 }),
		Defense = e(SummaryRow, {
			order = 2, icon = "icon_cat_defense", title = "Defense",
			value = ("%d HP, %s less damage"):format(sheet.maxHp, pct(sheet.reduction * 100)),
			onClick = function() props.go("defense") end,
		}),
		Melee = e(SummaryRow, {
			order = 3, icon = "icon_cat_melee", title = "Melee",
			value = weaponLine(sheet.melee),
			onClick = function() props.go("melee") end,
		}),
		Ranged = e(SummaryRow, {
			order = 4, icon = "icon_cat_ranged", title = "Ranged",
			value = weaponLine(sheet.ranged),
			onClick = function() props.go("ranged") end,
		}),
		Mount = e(SummaryRow, {
			order = 5, icon = "icon_cat_mount", title = "Mount",
			value = mount and ("%s, %s speed"):format(mount.name, num(mount.speed)) or "No saddle yet",
			onClick = function() props.go("mount") end,
		}),
		CoinFind = e(SummaryRow, {
			order = 6, icon = "fx_coinfind", title = "Coin Find",
			value = "+" .. pct(sheet.coinFind) .. " coins",
			tip = {
				title = "Coin Find +" .. pct(sheet.coinFind),
				lines = { "Extra coins from every coin drop." },
				foot = sources(sheet.coinSources, "%"),
			},
		}),
	})
end

------------------------------------------------------------------------------------------
-- Defense
------------------------------------------------------------------------------------------

local function StatBlock(props: { icon: string, value: string, caption: string, tip: Tip, order: number })
	return e(Hover, {
		order = props.order,
		tip = props.tip,
		children = {
			Icon = e(Icon, { art = props.icon, size = 40, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 2) }),
			Value = text({ text = props.value, font = Style.Font.Number, size = 28, color = Style.Text.Value, Position = UDim2.fromOffset(0, 44), height = 32 }),
			Caption = text({ text = props.caption, size = 14, color = Style.Text.Muted, Position = UDim2.fromOffset(0, 76), height = 18 }),
		},
	})
end

local function DefenseLeft(props: { sheet: any })
	local s = props.sheet
	local gearHp = s.maxHp - s.base.maxHp
	local blocks = {
		Grid = e("UIGridLayout", {
			CellSize = UDim2.fromOffset(220, 100),
			CellPadding = UDim2.fromOffset(16, 10),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Health = e(StatBlock, {
			order = 1, icon = "fx_health", value = tostring(s.maxHp), caption = "Max Health",
			tip = {
				title = ("Max Health %d"):format(s.maxHp),
				lines = { ("Right now: %d."):format(s.hp) },
				foot = ("Base %d, gear +%d"):format(s.base.maxHp, gearHp),
			},
		}),
		Regen = e(StatBlock, {
			order = 2, icon = "fx_hpregen", value = num(s.hpRegen) .. " / s", caption = "Health Regen",
			tip = {
				title = ("Health Regen %s / s"):format(num(s.hpRegen)),
				lines = { "Health you recover every second." },
				foot = ("Base %s, gear +%s"):format(num(s.base.hpRegen), num(s.hpRegen - s.base.hpRegen)),
			},
		}),
		Energy = e(StatBlock, {
			-- Regen never stops, sprinting included; sprint drains SPRINT_COST on top of it
			-- (EnergyData). The armor share is what decides whether you can sprint forever.
			order = 3, icon = "fx_energy", value = num(s.energyRegen, 2) .. " / s",
			caption = ("%s base + %s from armor"):format(num(s.base.energyRegen, 2), num(s.energyRegen - s.base.energyRegen, 2)),
			tip = (function()
				local cost = EnergyConfig.SPRINT_COST
				local net = s.energyRegen - cost
				local sprint = net >= 0
					and ("Sprinting costs %s / s, so you can sprint forever (gaining %s / s)."):format(num(cost, 2), num(net, 2))
					or ("Sprinting costs %s / s: you lose %s / s. %s more from armor and you can sprint forever."):format(num(cost, 2), num(-net, 2), num(-net, 2))
				return {
					title = ("Energy Regen %s / s"):format(num(s.energyRegen, 2)),
					lines = { "Energy you recover every second, even while sprinting. Swings spend it per swing.", sprint },
					foot = ("Base %s + %s from armor (helm, chest, legs and boots)"):format(num(s.base.energyRegen, 2), num(s.energyRegen - s.base.energyRegen, 2)),
				}
			end)(),
		}),
		Armor = e(StatBlock, {
			order = 4, icon = "fx_armor", value = pct(s.reduction * 100), caption = ("Less damage (%d armor)"):format(s.armor),
			tip = {
				title = ("Armor %d"):format(s.armor),
				lines = {
					("You take %s less damage from every hit."):format(pct(s.reduction * 100)),
					"Damage is cut to 100 / (100 + armor). More always helps, a little less each time.",
				},
			},
		}),
	}
	local blockLines = {
		"A chance to stop a hit entirely, rolled on every hit you take.",
		("Caps at %d%%."):format(s.blockCap),
	}
	if s.blockRaw > s.blockCap then
		table.insert(blockLines, ("Your gear has %s; the extra does nothing."):format(pct(s.blockRaw)))
	end
	local blockTip: Tip = { title = "Block " .. pct(s.block), lines = blockLines, foot = sources(s.blockSources, "%") }
	return list(10, {
		Heading = e(Parts.Heading, { text = "Defense", size = 26, order = 1, height = 34 }),
		Blocks = e("Frame", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 212), BackgroundTransparency = 1 }, blocks),
		Divider = e(Parts.Divider, { order = 3 }),
		Block = e(Hover, {
			order = 4,
			Size = UDim2.new(1, -40, 0, 66),
			tip = blockTip,
			above = true,
			children = {
				Icon = e(Icon, { art = "fx_block", size = 30, Position = UDim2.fromOffset(0, 0) }),
				Label = text({ text = "Block", font = Style.Font.Heading, size = 18, color = Style.Text.Heading,
					align = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(40, 4), Size = UDim2.new(0.5, 0, 0, 24) }),
				Value = text({ text = pct(s.block) .. "  of " .. s.blockCap .. "%", font = Style.Font.Number, size = 18, color = Style.Text.Value,
					align = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 4), Size = UDim2.new(0.5, 0, 0, 24) }),
				Bar = e(Parts.BarTrough, {
					fill = s.blockCap > 0 and (s.block / s.blockCap) or 0,
					color = Style.Split.Dungeon,
					Position = UDim2.fromOffset(0, 40),
					Size = UDim2.new(1, 0, 0, 16),
				}),
			},
		}),
	})
end

local COLS = { name = 0.46, hp = 0.18, armor = 0.18, block = 0.18 }

local function GearCells(props: { hp: string, armor: string, block: string, color: Color3, font: any?, size: number? })
	local function cell(value: string, x: number, w: number)
		return text({
			text = value, font = props.font or Style.Font.Number, size = props.size or 16, color = props.color,
			Position = UDim2.fromScale(x, 0), Size = UDim2.fromScale(w, 1),
		})
	end
	return {
		Hp = cell(props.hp, COLS.name, COLS.hp),
		Armor = cell(props.armor, COLS.name + COLS.hp, COLS.armor),
		Block = cell(props.block, COLS.name + COLS.hp + COLS.armor, COLS.block),
	}
end

local function dash(n: number, suffix: string?): string
	return n > 0 and (num(n, 1) .. (suffix or "")) or "-"
end

local GEAR_ICON = 50
local GEAR_ROW_H = 60

local function GearRow(props: { slot: any, order: number })
	local slot = props.slot
	local children = GearCells({
		hp = dash(slot.hp), armor = dash(slot.armor), block = dash(slot.block, "%"),
		color = slot.item and Style.Text.Value or Style.Text.Muted,
	})
	children.Icon = e(ItemIcon, {
		item = slot.item, size = GEAR_ICON, dim = slot.item == nil,
		AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
	})
	children.Slot = text({
		text = slot.slot, font = Style.Font.Heading, size = 16, color = Style.Text.Heading,
		align = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(GEAR_ICON + 10, 9), Size = UDim2.new(COLS.name, -(GEAR_ICON + 14), 0, 22),
	})
	children.Name = text({
		text = slot.name or "Empty", size = 13, color = Style.Text.Muted, truncate = true,
		align = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(GEAR_ICON + 10, 31), Size = UDim2.new(COLS.name, -(GEAR_ICON + 14), 0, 18),
	})
	local tip: Tip? = nil
	if slot.item then
		local lines = { ("Health +%s, Armor +%s, Block %s"):format(dash(slot.hp), dash(slot.armor), dash(slot.block, "%")) }
		if slot.hps > 0 or slot.energy > 0 then
			table.insert(lines, ("Health Regen +%s / s, Energy Regen +%s / s"):format(num(slot.hps), num(slot.energy, 2)))
		end
		tip = { title = slot.name, lines = lines, foot = slot.slot .. " slot" }
	end
	return e(Hover, { order = props.order, Size = UDim2.new(1, 0, 0, GEAR_ROW_H), tip = tip, children = children })
end

local function DefenseRight(props: { sheet: any })
	local s = props.sheet
	local rows: { [string]: any } = {}
	local total = { hp = 0, armor = 0 }
	for i, slot in ipairs(s.slots) do
		rows["r" .. i] = e(GearRow, { slot = slot, order = 2 + i })
		total.hp += slot.hp
		total.armor += slot.armor
	end
	local header = GearCells({ hp = "HP", armor = "Armor", block = "Block", color = Style.Text.Muted, font = Style.Font.BodyBold, size = 14 })
	header.Label = text({
		text = "Slot", font = Style.Font.BodyBold, size = 14, color = Style.Text.Muted,
		align = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(GEAR_ICON + 10, 0), Size = UDim2.new(COLS.name, -(GEAR_ICON + 10), 1, 0),
	})
	local totals = GearCells({ hp = dash(total.hp), armor = dash(total.armor), block = dash(s.block, "%"), color = Style.Text.Heading })
	totals.Label = text({
		text = "Total", font = Style.Font.Heading, size = 16, color = Style.Text.Heading,
		align = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(GEAR_ICON + 10, 0), Size = UDim2.new(COLS.name, -(GEAR_ICON + 10), 1, 0),
	})
	rows.Heading = e(Parts.Heading, { text = "Gear", size = 26, order = 1, height = 34 })
	rows.Header = e("Frame", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1 }, header)
	rows.Divider = e(Parts.Divider, { order = 20, width = 1 })
	rows.Totals = e("Frame", { LayoutOrder = 21, Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1 }, totals)
	return list(3, rows)
end

------------------------------------------------------------------------------------------
-- Melee / Ranged
------------------------------------------------------------------------------------------

local function damageTip(w: any): Tip
	local lines = { ("Weapon roll %s (enchants included)"):format(range(w.baseLo, w.baseHi)) }
	if w.attrKey then
		table.insert(lines, ("%s %d: +%s"):format(StatsSheet.ATTRIBUTE_LABEL[w.attrKey], w.attrTotal, pct(w.attrBonusPct)))
	end
	if w.pierce > 0 then table.insert(lines, ("Piercing: +%d"):format(math.floor(w.pierce))) end
	if w.elem > 0 then table.insert(lines, ("Elemental: +%d"):format(math.floor(w.elem))) end
	return {
		title = "Damage " .. range(w.lo, w.hi),
		lines = lines,
		foot = "Per hit, before the target's armor. Critical, Execute and other procs come on top.",
	}
end

local function WeaponLeft(props: { title: string, w: any?, slotName: string })
	local w = props.w
	if not w then
		return list(10, {
			Heading = e(Parts.Heading, { text = props.title, size = 26, order = 1, height = 34 }),
			Empty = e("Frame", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 90), BackgroundTransparency = 1 }, {
				Body = e(Empty, {
					title = "Nothing in your " .. props.slotName .. " slot",
					body = "Equip one from your Inventory to see it here.",
				}),
			}),
		})
	end
	local name = w.enchant > 0 and (w.name .. "  +" .. w.enchant) or w.name
	local children: { [string]: any } = {
		Heading = e(Parts.Heading, { text = props.title, size = 26, order = 1, height = 34 }),
		Card = e("Frame", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 104), BackgroundTransparency = 1 }, {
			Icon = e(ItemIcon, { item = w.item, size = 96, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0) }),
			Name = text({
				text = name, font = Style.Font.Heading, size = 21, color = Style.Text.Heading, truncate = true,
				align = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(122, 12), Size = UDim2.new(1, -130, 0, 28),
			}),
			Gem = w.rarity and e(Parts.Gem, { rarity = w.rarity, scale = 0.7, Position = UDim2.fromOffset(122, 46) }) or nil,
			Type = text({
				text = (w.rarity and (w.rarity .. " ") or "") .. (w.weaponType or "Weapon"), size = 16, color = Style.Text.Body,
				align = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(w.rarity and 148 or 122, 44), Size = UDim2.new(1, -160, 0, 22),
			}),
		}),
		Divider = e(Parts.Divider, { order = 3 }),
		Damage = e(Hover, {
			order = 4,
			Size = UDim2.fromOffset(260, 78),
			tip = damageTip(w),
			children = {
				Value = text({ text = range(w.lo, w.hi), font = Style.Font.Number, size = 44, color = Style.Text.Value, height = 52 }),
				Caption = text({ text = "Damage", size = 15, color = Style.Text.Muted, Position = UDim2.fromOffset(0, 54), height = 20 }),
			},
		}),
	}
	if w.attrKey then
		local label = StatsSheet.ATTRIBUTE_LABEL[w.attrKey]
		local weapon = string.lower(w.weaponType or "weapon")
		children.Attr = e("Frame", { LayoutOrder = 5, Size = UDim2.new(1, -40, 0, 44), BackgroundTransparency = 1 }, {
			Line = text({
				text = ("%s %d: +%s %s damage"):format(label, w.attrTotal, pct(w.attrBonusPct), weapon),
				font = Style.Font.BodyBold, size = 16, color = Style.Text.Heading, height = 22,
			}),
			Rate = text({
				text = ("Every 200 %s on your armor adds %s"):format(label, pct(PER_200_PCT)),
				size = 13, color = Style.Text.Muted, Position = UDim2.fromOffset(0, 24), height = 18,
			}),
		})
	end
	return list(8, children)
end

local function EffectRow(props: { fx: any, order: number })
	local fx = props.fx
	return e("Frame", { LayoutOrder = props.order, Size = UDim2.new(1, 0, 0, 62), BackgroundTransparency = 1 }, {
		Icon = e(Icon, { art = fx.icon, size = 38, Position = UDim2.fromOffset(4, 6) }),
		Name = text({
			text = fx.label, font = Style.Font.Heading, size = 17, color = Style.Text.Heading,
			align = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(54, 4), Size = UDim2.new(1, -130, 0, 22),
		}),
		Value = text({
			text = fx.valueText, font = Style.Font.Number, size = 17, color = Style.Text.Value,
			align = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 4), Size = UDim2.fromOffset(70, 22),
		}),
		Explain = text({
			text = fx.explain, size = 14, color = Style.Text.Body, wrap = true,
			align = Enum.TextXAlignment.Left, alignY = Enum.TextYAlignment.Top,
			Position = UDim2.fromOffset(54, 28), Size = UDim2.new(1, -58, 0, 34),
		}),
	})
end

local function WeaponRight(props: { w: any? })
	local w = props.w
	local children: { [string]: any } = {
		Heading = e(Parts.Heading, { text = "Effects", size = 26, order = 1, height = 34 }),
	}
	if not w or #w.effects == 0 then
		children.None = text({
			order = 2, height = 40, size = 15, color = Style.Text.Muted,
			text = w and "This weapon has no special effects." or "No weapon, no effects.",
		})
	else
		for i, fx in ipairs(w.effects) do
			children["fx" .. i] = e(EffectRow, { fx = fx, order = 1 + i })
		end
	end
	return list(6, children)
end

------------------------------------------------------------------------------------------
-- Mount
------------------------------------------------------------------------------------------

local function ShowOnMap(props: { order: number })
	local position = WorldMapRequest.NpcPosition("AnimalTrainer")
	return e(Parts.ChromeButton, {
		text = position and "Show on map" or "Location unknown",
		art = "chip",
		artSelected = "chip_selected",
		disabled = position == nil,
		Size = UDim2.fromOffset(200, 40),
		LayoutOrder = props.order,
		textSize = 16,
		onClick = function()
			if position then WorldMapRequest.ShowAt(position, "Animal Trainer") end
		end,
	})
end

local function SpeedBar(props: { label: string, speed: number, max: number, color: Color3, order: number })
	return e("Frame", { LayoutOrder = props.order, Size = UDim2.new(1, -40, 0, 44), BackgroundTransparency = 1 }, {
		Label = text({ text = props.label, size = 15, color = Style.Text.Body, align = Enum.TextXAlignment.Left, Size = UDim2.new(0.6, 0, 0, 20) }),
		Value = text({ text = num(props.speed), font = Style.Font.Number, size = 16, color = Style.Text.Value,
			align = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.4, 0, 0, 20) }),
		Bar = e(Parts.BarTrough, {
			fill = props.max > 0 and props.speed / props.max or 0, color = props.color,
			Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 14),
		}),
	})
end

local function MountLeft(props: { sheet: any })
	local s = props.sheet
	local m = s.mount
	if not m then
		return list(12, {
			Heading = e(Parts.Heading, { text = "Mount", size = 26, order = 1, height = 34 }),
			Icon = e(Icon, { art = "icon_cat_mount", size = 72, order = 2 }),
			Title = text({ text = "No saddle yet", font = Style.Font.Heading, size = 20, color = Style.Text.Heading, height = 28, order = 3 }),
			Body = text({
				text = "Saddles are sold by the Animal Trainer. Even the first one outruns your sprint.",
				size = 15, color = Style.Text.Muted, wrap = true, height = 44, order = 4,
			}),
			Map = e(ShowOnMap, { order = 5 }),
		})
	end
	local faster = (m.speed / s.sprintSpeed - 1) * 100
	local max = math.max(m.speed, s.sprintSpeed)
	return list(10, {
		Heading = e(Parts.Heading, { text = "Mount", size = 26, order = 1, height = 34 }),
		Card = e("Frame", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 96), BackgroundTransparency = 1 }, {
			Icon = e(ItemIcon, { item = m.item, size = 88, fallbackArt = "icon_cat_mount", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 20, 0.5, 0) }),
			Name = text({ text = m.name, font = Style.Font.Heading, size = 21, color = Style.Text.Heading,
				align = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(124, 18), Size = UDim2.new(1, -130, 0, 28) }),
			Sub = text({ text = "Your fastest saddle", size = 14, color = Style.Text.Muted,
				align = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(124, 50), Size = UDim2.new(1, -130, 0, 20) }),
		}),
		Divider = e(Parts.Divider, { order = 3 }),
		Speed = e(Hover, {
			order = 4,
			Size = UDim2.fromOffset(260, 74),
			tip = {
				title = "Riding speed " .. num(m.speed),
				lines = { ("On foot you walk at %s and sprint at %s."):format(num(s.walkSpeed), num(s.sprintSpeed)) },
				foot = "From " .. m.name,
			},
			children = {
				Value = text({ text = num(m.speed), font = Style.Font.Number, size = 44, color = Style.Text.Value, height = 52 }),
				Caption = text({ text = ("Riding speed, +%s vs sprinting"):format(pct(faster)), size = 15, color = Style.Text.Muted,
					Position = UDim2.fromOffset(0, 52), height = 20 }),
			},
		}),
		Sprint = e(SpeedBar, { label = "Sprinting", speed = s.sprintSpeed, max = max, color = Style.Split.Dungeon, order = 5 }),
		Mounted = e(SpeedBar, { label = "Mounted", speed = m.speed, max = max, color = Style.Split.Overworld, order = 6 }),
	})
end

local function MountRight(props: { sheet: any, profile: any })
	local owned: { [string]: boolean } = {}
	for _, item in pairs(props.profile.inventory or {}) do
		if type(item) == "table" and type(item.itemId) == "string" then owned[item.itemId] = true end
	end
	local children: { [string]: any } = {
		Heading = e(Parts.Heading, { text = "Saddles", size = 26, order = 1, height = 34 }),
	}
	for tier = 1, SADDLE_TIERS do
		local id = ("T%dMountSaddle"):format(tier)
		local def = ItemDefinitions.Get(id)
		if def and def.MountSpeed then
			local have = owned[id] == true
			children[id] = e("Frame", { LayoutOrder = 1 + tier, Size = UDim2.new(1, -20, 0, 52), BackgroundTransparency = 1 }, {
				Icon = e(ItemIcon, {
					image = ItemDefinitions.GetIconForItem({ itemId = id }), fallbackArt = "icon_cat_mount",
					rarity = def.Rarity, size = 42, dim = not have,
					AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
				}),
				Name = text({ text = def.DisplayName or id, font = Style.Font.Heading, size = 16,
					color = have and Style.Text.Heading or Style.Text.Muted,
					align = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(54, 6), Size = UDim2.new(1, -150, 0, 22) }),
				State = text({ text = have and "Owned" or "Not owned", size = 13,
					color = have and Style.Text.Good or Style.Text.Muted,
					align = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(54, 28), Size = UDim2.new(1, -150, 0, 18) }),
				Speed = text({ text = num(def.MountSpeed) .. " speed", font = Style.Font.Number, size = 16,
					color = have and Style.Text.Value or Style.Text.Muted,
					align = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(100, 22) }),
			})
		end
	end
	children.Divider = e(Parts.Divider, { order = 20 })
	children.Where = text({ order = 21, text = "Sold by the Animal Trainer", size = 15, color = Style.Text.Muted, height = 22 })
	children.Map = props.sheet.mount and e(ShowOnMap, { order = 22 }) or nil
	return list(6, children)
end

------------------------------------------------------------------------------------------
-- Page
------------------------------------------------------------------------------------------

local function StatsPage(props: { side: any? })
	local snapshot = InventoryData.useSnapshot()
	local category, setCategory = React.useState("overview")
	local sheet = StatsSheet.Compute(snapshot)
	local ribbons = e(Ribbons, { selected = category, onSelect = setCategory })

	local left, right
	if not sheet then
		left = e(Empty, { title = "Reading your character", body = "One moment." })
		right = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	elseif category == "defense" then
		left, right = e(DefenseLeft, { sheet = sheet }), e(DefenseRight, { sheet = sheet })
	elseif category == "melee" then
		left = e(WeaponLeft, { title = "Melee", w = sheet.melee, slotName = "Weapon" })
		right = e(WeaponRight, { w = sheet.melee })
	elseif category == "ranged" then
		left = e(WeaponLeft, { title = "Ranged", w = sheet.ranged, slotName = "Bow" })
		right = e(WeaponRight, { w = sheet.ranged })
	elseif category == "mount" then
		left, right = e(MountLeft, { sheet = sheet }), e(MountRight, { sheet = sheet, profile = snapshot.profile })
	else
		left = e(CharacterSpread, { sheet = sheet, equipped = snapshot.profile.equipped })
		right = e(SummarySpread, { sheet = sheet, go = setCategory })
	end

	return e(Book, { side = props.side, ribbons = ribbons, left = left, right = right })
end

return StatsPage
