--!strict
--  Tooltip -- the hover card for an owned item (rebuilt 2026-10-12; used by the inventory and the
--  Enchanting Station; the Auction House borrows BaseStatLines / SubstatLines for its text).
--
--    [icon]  Item Name                         <- nameplate band in the rarity colour (Grenze)
--    M Y T H I C            [chain] Soulbound  <- spaced rarity caps; tags: Soulbound,
--    ============----   1320 / 1500                 Untradeable, Protected, Broken
--    ---------------- <> ----------------
--    [icon]  +103   Health                      <- base stats: icon, value (serif), label
--    [icon]  +3.72  Energy / sec
--    ---------------- <> ----------------
--    [icon]  +276   DEX                         <- substats, values in the accent colour; the
--                                                  four attributes by short name, in blue
--
--  Stats read the way players read them: the value first, a "+", plain words in sentence case
--  (LABELS below; the attributes just "DEX", never ItemConfig's "DEX (Sword DMG)"). Binding is a one-word tag, not a
--  sentence (RS/ItemBinding). Art: RS/Assets/Images/InventoryUI TOOLTIP_* (card, nameplate,
--  tag glyphs), stat icons from the Journal's fx_* set, the divider from JournalUI.
--
--  Laid out at fixed widths and row heights computed once (layoutFor), shared by the render and
--  EstimateSize, so the caller can clamp the card on screen before it ever renders.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local Types = require(ReplicatedStorage:WaitForChild("ProfileTypes"))
local ItemConfig = require(ReplicatedStorage:WaitForChild("ItemConfig"))
local ItemDefinitions = require(ReplicatedStorage:WaitForChild("ItemDefinitions"))
local ItemBinding = require(ReplicatedStorage:WaitForChild("ItemBinding"))
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local SkillXPShared = require(ReplicatedStorage:WaitForChild("SkillXPShared"))
local Images = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Images")
local InventoryUI = require(Images:WaitForChild("InventoryUI"))
local JournalUI = require(Images:WaitForChild("JournalUI"))
local e = React.createElement

-------------------------------------------------------------------------------------------------
-- Words and icons

-- Substat id -> plain words. Anything missing falls back to its ItemConfig label, then to the
-- key split into words ("MiningLevel" -> "Mining level").
local LABELS: { [string]: string } = {
	-- The four attributes go by their short names (what they do is on the Journal's Stats page),
	-- in ATTRIBUTE_COLOR so they stand out from the other substats.
	vit = "VIT", str = "STR", int = "INT", dex = "DEX",
	block = "Block chance", reflect = "Reflect", dodge = "Dodge", coinFind = "Coin find",
	elemRes = "Elemental resistance",
	vsMon = "Damage vs monsters", vsPly = "Damage vs players", accuracy = "Accuracy",
	critical = "Critical hit chance", execute = "Execute", cleave = "Cleave", crushing = "Crushing",
	pierce = "Armor pierce", shatter = "Shatter", elemDmg = "Elemental damage", lifesteal = "Life steal",
	glowing = "Glowing", bleeding = "Bleed chance", blinding = "Blind chance", slowness = "Slow chance",
	MiningLevel = "Mining level", FishingLevel = "Fishing level",
}

-- Stat -> an icon (JournalUI key, or a raw image id). Missing = a blank slot, so values line up.
local ICONS: { [string]: string } = {
	damage = "icon_cat_melee", hp = "fx_health", hps = "fx_hpregen", armor = "fx_armor", dmgRed = "fx_block",
	energy = "fx_energy",
	vit = "icon_cat_melee", str = "icon_cat_melee", int = "icon_cat_melee", dex = "icon_cat_melee",
	block = "fx_block", coinFind = "fx_coinfind", vsMon = "fx_vsmon", vsPly = "fx_vsply",
	critical = "fx_critical", execute = "fx_execute", cleave = "fx_cleave", crushing = "fx_crushing",
	pierce = "fx_pierce", shatter = "fx_shatter", elemDmg = "fx_elemental", elemRes = "fx_elemental",
	lifesteal = "fx_lifesteal", bleeding = "fx_bleeding", blinding = "fx_blinding", slowness = "fx_slowness",
}
local function iconImage(key: string): string?
	if key == "MiningLevel" then return ItemConfig.TOOL_ICONS and ItemConfig.TOOL_ICONS.Pickaxe end
	if key == "FishingLevel" then return ItemConfig.TOOL_ICONS and ItemConfig.TOOL_ICONS.FishingRod end
	local art = ICONS[key] and (JournalUI :: any)[ICONS[key]]
	return (type(art) == "table" and art.Image ~= "") and art.Image or nil
end

local ATTRIBUTES: { [string]: boolean } = { vit = true, str = true, int = true, dex = true }
local ATTRIBUTE_COLOR = Color3.fromRGB(112, 172, 255)

-- Which substats are percentages (from ItemConfig, so it can't drift from what rolls).
local PCT: { [string]: boolean } = {}
local CONFIG_LABEL: { [string]: string } = {}
for _, list in ipairs({ ItemConfig.WEAPON_EFFECTS, ItemConfig.ARMOR_EFFECTS, ItemConfig.ARMOR_BONUS_EFFECTS }) do
	for _, effect in ipairs(list or {}) do
		PCT[effect.id] = effect.valueType == "pct"
		CONFIG_LABEL[effect.id] = effect.label
	end
end

local function wordsOf(key: string): string
	local spaced = key:gsub("(%l)(%u)", "%1 %2")
	return spaced:sub(1, 1):upper() .. spaced:sub(2):lower()
end
local function labelOf(key: string): string
	return LABELS[key] or CONFIG_LABEL[key] or wordsOf(key)
end

-- Base-stat keys (shown first, fixed order) and ItemClass's private "_raw*" bookkeeping.
local BASE_STAT_KEYS = { dmgMin = true, dmgMax = true, hp = true, hps = true, armor = true, energy = true, dmgRed = true }
local function isInternalKey(key: string): boolean
	return string.sub(key, 1, 1) == "_"
end

local function plus(n: number, decimals: boolean?): string
	local text = decimals and string.format("%.2f", n) or tostring(math.floor(n + 0.5))
	return (n >= 0 and "+" or "") .. text
end

-- { { icon key, value text, label } } for the base stats, in a fixed order.
local function baseStats(subStats: any): { { string } }
	local out = {}
	if type(subStats) ~= "table" then return out end
	if subStats.dmgMin and subStats.dmgMax then
		table.insert(out, { "damage", ("%d-%d"):format(subStats.dmgMin, subStats.dmgMax), "Damage" })
	end
	if subStats.hp then table.insert(out, { "hp", plus(subStats.hp), "Health" }) end
	if subStats.hps then table.insert(out, { "hps", plus(subStats.hps), "Health regen / sec" }) end
	if subStats.armor then table.insert(out, { "armor", plus(subStats.armor), "Armor" }) end
	if subStats.dmgRed then table.insert(out, { "dmgRed", plus(subStats.dmgRed) .. "%", "Damage reduction" }) end
	if subStats.energy then table.insert(out, { "energy", plus(subStats.energy, true), "Energy / sec" }) end
	return out
end

-- A profession tool (soulbound, so it is always yours) shows YOUR skill level, "Level 21 Mining".
-- Tools carry no level bonus (removed 2026-10-12: professions start at 1 and are earned); the
-- old MiningLevel / FishingLevel stat is skipped below in case a save still has it. The level is
-- the client's display cache (SkillXPShared).
local PROFESSION = {
	Pickaxe = { key = "MiningLevel", skill = "Mining" },
	FishingSpear = { key = "FishingLevel", skill = "Fishing" },
}
local TOOL_LEVEL_KEYS = { MiningLevel = true, FishingLevel = true }
local function professionRow(item: any): { string }?
	local tool = PROFESSION[Types.GetAllowedEquipSlot(item) or ""]
	if not tool then return nil end
	local level = (SkillXPShared :: any)[tool.skill] and (SkillXPShared :: any)[tool.skill].Level or 1
	return { tool.key, "Level " .. tostring(level), tool.skill }
end

-- A coin sack shows what it holds ("87 / 150"); a coin note shows its face value.
local function coinRow(item: any): { string }?
	local capacity = ItemDefinitions.GetCoinCapacity(item.itemId)
	local held = math.max(0, math.floor(tonumber(item.coins) or 0))
	if capacity then
		return { "coinFind", ("%d / %d"):format(held, capacity), "Coins held" }
	elseif ItemDefinitions.IsCoinNote(item.itemId) then
		return { "coinFind", tostring(held), "Coins, redeemable anywhere" }
	end
	return nil
end

-- The same for everything else the item rolled, sorted by label.
local function substats(subStats: any): { { string } }
	local out = {}
	if type(subStats) ~= "table" then return out end
	for key, value in pairs(subStats) do
		if type(key) == "string" and not BASE_STAT_KEYS[key] and not TOOL_LEVEL_KEYS[key] and not isInternalKey(key) then
			local n = tonumber(value)
			local text = n and (plus(n, n % 1 ~= 0) .. (PCT[key] and "%" or "")) or tostring(value)
			table.insert(out, { key, text, labelOf(key), ATTRIBUTES[key] and "attribute" or nil })
		end
	end
	table.sort(out, function(a, b) return a[3] < b[3] end)
	return out
end

-- The one-word tags: binding, then protection / broken.
local TAG_COLORS = {
	Soulbound = Color3.fromRGB(196, 198, 206),
	Untradeable = Color3.fromRGB(190, 160, 122),
	Protected = Color3.fromRGB(226, 186, 112),
	Broken = Color3.fromRGB(226, 110, 96),
}
local function tagsOf(item: any): { string }
	local out = {}
	local binding = ItemBinding.Level(item)
	if binding == ItemBinding.BOUND then
		table.insert(out, "Soulbound")
	elseif binding == ItemBinding.UNTRADEABLE then
		table.insert(out, "Untradeable")
	end
	if item.broken == true then
		table.insert(out, "Broken")
	elseif item.scrollProtected == true then
		table.insert(out, "Protected")
	end
	return out
end

-------------------------------------------------------------------------------------------------
-- Layout (shared by render and EstimateSize)

local CARD_W = 292
local PAD_X, PAD_TOP, PAD_BOTTOM = 15, 13, 13
local CONTENT_W = CARD_W - PAD_X * 2
local NAME_H, RARITY_H, DURABILITY_H, DIVIDER_H, ROW_H = 34, 20, 16, 14, 21
local GAP = 4

local INK = {
	Name = Color3.fromRGB(250, 242, 224),
	Value = Color3.fromRGB(240, 228, 204),
	Accent = Color3.fromRGB(150, 212, 194), -- substat values
	Label = Color3.fromRGB(178, 160, 128),
	Muted = Color3.fromRGB(140, 126, 104),
	Bad = Color3.fromRGB(226, 110, 96),
	Outline = Color3.fromRGB(16, 11, 7),
}

type Block = { kind: string, h: number, data: any? }

local function layoutFor(item: any): ({ Block }, number)
	local blocks: { Block } = {}
	local function add(kind: string, h: number, data: any?) table.insert(blocks, { kind = kind, h = h, data = data }) end
	add("name", NAME_H)
	add("rarity", RARITY_H)
	local maxDur = tonumber(item.maxDurability)
	if item.broken == true or (maxDur and maxDur > 0) then add("durability", DURABILITY_H) end
	local base = baseStats(item.subStats)
	local toolRow = professionRow(item)
	if toolRow then table.insert(base, 1, toolRow) end
	local coins = coinRow(item)
	if coins then table.insert(base, 1, coins) end
	local sub = substats(item.subStats)
	if #base > 0 then
		add("divider", DIVIDER_H)
		for _, row in ipairs(base) do add("stat", ROW_H, { row = row, accent = false }) end
	end
	if #sub > 0 then
		add("divider", DIVIDER_H)
		for _, row in ipairs(sub) do add("stat", ROW_H, { row = row, accent = true }) end
	end
	local h = PAD_TOP + PAD_BOTTOM
	for i, block in ipairs(blocks) do h += block.h + (i > 1 and GAP or 0) end
	return blocks, h
end

-------------------------------------------------------------------------------------------------
-- Pieces

local THIN = utf8.char(0x2009) -- a thin space: spaced capitals ("M Y T H I C") without real tracking
local function spaced(word: string): string
	local letters = {}
	for _, code in utf8.codes(string.upper(word)) do table.insert(letters, utf8.char(code)) end
	return table.concat(letters, THIN)
end

local function Nameplate(item: any, rarityColor: Color3, y: number)
	local art = InventoryUI.TOOLTIP_NAMEPLATE
	local icon = ItemDefinitions.GetIconForItem(item)
	local rarity = ItemDefinitions.GetRarityForItem(item)
	local shimmer = rarity == "Legendary" or rarity == "Mythic"
	-- The band in the rarity colour, deepened so the light name reads on it. Legendary / Mythic
	-- names catch the light: a soft gold-white gradient across the text.
	return e("Frame", {
		Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, NAME_H), BackgroundTransparency = 1, ZIndex = 61,
	}, {
		Band = art.Image ~= "" and e("ImageLabel", {
			Position = UDim2.fromOffset(18, 2), Size = UDim2.new(1, -18, 1, -4), BackgroundTransparency = 1,
			Image = art.Image, ScaleType = Enum.ScaleType.Slice, SliceCenter = art.SliceCenter,
			SliceScale = (NAME_H - 4) / art.Size.Y,
			ImageColor3 = rarityColor:Lerp(Color3.new(0, 0, 0), 0.45),
			ZIndex = 61,
		}) or nil,
		Icon = (type(icon) == "string" and icon ~= "") and e("ImageLabel", {
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(NAME_H, NAME_H),
			BackgroundTransparency = 1, Image = icon, ScaleType = Enum.ScaleType.Fit, ZIndex = 63,
		}) or nil,
		Name = e("TextLabel", {
			BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(NAME_H + 8, 0), Size = UDim2.new(1, -(NAME_H + 22), 1, 0),
			-- Long names shrink (down to 12 px, wrapping onto a second line) rather than being cut off.
			Text = ItemDefinitions.GetDisplayNameForItem(item), FontFace = UIFonts.Fantasy, TextScaled = true,
			TextWrapped = true, TextColor3 = INK.Name, TextStrokeColor3 = INK.Outline, TextStrokeTransparency = 0.35,
			ZIndex = 62,
		}, {
			Fit = e("UITextSizeConstraint", { MaxTextSize = 20, MinTextSize = 12 }),
			Shine = shimmer and e("UIGradient", {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 226, 150)),
					ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 226, 150)),
				}),
			}) or nil,
		}),
	})
end

local function Tag(word: string, order: number)
	local sheet = InventoryUI.TOOLTIP_TAGS
	local cell = sheet.Image ~= "" and sheet.Cells[word] or nil
	local color = TAG_COLORS[word] or INK.Label
	return e("Frame", {
		LayoutOrder = order, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, RARITY_H),
		BackgroundTransparency = 1, ZIndex = 61,
	}, {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Glyph = cell and e("ImageLabel", {
			LayoutOrder = 1, Size = UDim2.fromOffset(13, 13), BackgroundTransparency = 1, Image = sheet.Image,
			ImageRectOffset = cell.Offset, ImageRectSize = cell.Size, ScaleType = Enum.ScaleType.Fit,
			ImageColor3 = color, ZIndex = 62,
		}) or nil,
		Word = e("TextLabel", {
			LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, RARITY_H),
			BackgroundTransparency = 1, Text = word, FontFace = UIFonts.BodyBold, TextSize = 12,
			TextColor3 = color, TextTransparency = word == "Soulbound" and 0.15 or 0, ZIndex = 62,
		}),
	})
end

local function RarityRow(item: any, rarityColor: Color3, y: number)
	local rarity = ItemDefinitions.GetRarityForItem(item)
	local tags: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for i, word in ipairs(tagsOf(item)) do tags["T" .. i] = Tag(word, i) end
	return e("Frame", {
		Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, RARITY_H), BackgroundTransparency = 1, ZIndex = 61,
	}, {
		Rarity = type(rarity) == "string" and e("TextLabel", {
			BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(0.5, 0, 1, 0), Text = spaced(rarity), FontFace = UIFonts.BodyBold, TextSize = 11,
			TextColor3 = rarityColor, TextTransparency = 0.1, ZIndex = 62,
		}) or nil,
		Tags = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 61 }, tags),
	})
end

local function Durability(item: any, y: number)
	local maxDur = math.max(1, math.floor(tonumber(item.maxDurability) or 1))
	local cur = item.broken == true and 0 or math.clamp(math.floor(tonumber(item.durability) or maxDur), 0, maxDur)
	local frac = cur / maxDur
	local fill = frac > 0.5 and Color3.fromRGB(222, 210, 186) or (frac > 0.2 and Color3.fromRGB(226, 172, 90) or INK.Bad)
	return e("Frame", {
		Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, DURABILITY_H), BackgroundTransparency = 1, ZIndex = 61,
	}, {
		Trough = e("Frame", {
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(1, -96, 0, 4),
			BackgroundColor3 = Color3.fromRGB(46, 36, 26), BorderSizePixel = 0, ZIndex = 61,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Fill = e("Frame", {
				Size = UDim2.fromScale(frac, 1), BackgroundColor3 = fill, BorderSizePixel = 0, ZIndex = 62,
			}, { Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }) }),
		}),
		Numbers = e("TextLabel", {
			BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0),
			Size = UDim2.new(0, 90, 1, 0), TextXAlignment = Enum.TextXAlignment.Right,
			Text = item.broken == true and "Repair at a smith" or ("%d / %d"):format(cur, maxDur),
			FontFace = UIFonts.BodyMedium, TextSize = 11, TextColor3 = item.broken == true and INK.Bad or INK.Muted, ZIndex = 62,
		}),
	})
end

local function Divider(y: number)
	local art = (JournalUI :: any).divider
	if type(art) == "table" and art.Image ~= "" then
		return e("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, y + DIVIDER_H / 2),
			Size = UDim2.fromOffset(CONTENT_W - 10, math.max(6, math.floor((CONTENT_W - 10) / art.Aspect + 0.5))),
			BackgroundTransparency = 1, Image = art.Image, ImageColor3 = Color3.fromRGB(172, 150, 108),
			ImageTransparency = 0.15, ZIndex = 61,
		})
	end
	return e("Frame", {
		Position = UDim2.fromOffset(5, y + DIVIDER_H / 2), Size = UDim2.fromOffset(CONTENT_W - 10, 1),
		BackgroundColor3 = Color3.fromRGB(107, 85, 54), BorderSizePixel = 0, ZIndex = 61,
	})
end

local VALUE_W = 72 -- fits "Level 100" as well as "+1,250"
local function StatRow(row: { string }, accent: boolean, y: number)
	local image = iconImage(row[1])
	return e("Frame", {
		Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, ROW_H), BackgroundTransparency = 1, ZIndex = 61,
	}, {
		Icon = image and e("ImageLabel", {
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(17, 17),
			BackgroundTransparency = 1, Image = image, ScaleType = Enum.ScaleType.Fit, ZIndex = 62,
		}) or nil,
		Value = e("TextLabel", {
			BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Right,
			Position = UDim2.fromOffset(22, 0), Size = UDim2.new(0, VALUE_W, 1, 0),
			Text = row[2], FontFace = UIFonts.SerifBold, TextSize = 14,
			TextColor3 = accent and INK.Accent or INK.Value, ZIndex = 62,
		}),
		Label = e("TextLabel", {
			BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(22 + VALUE_W + 10, 0), Size = UDim2.new(1, -(22 + VALUE_W + 10), 1, 0),
			Text = row[3], FontFace = row[4] == "attribute" and UIFonts.BodyBold or UIFonts.BodyMedium, TextSize = 13,
			TextColor3 = row[4] == "attribute" and ATTRIBUTE_COLOR or INK.Label,
			TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 62,
		}),
	})
end

-------------------------------------------------------------------------------------------------
-- The card

local function renderTooltip(props: { item: any, position: Vector2 })
	local item = props.item
	if type(item) ~= "table" then
		return nil :: any
	end
	local rarity = ItemDefinitions.GetRarityForItem(item)
	local rarityColor = Types.GetRarityColor(rarity)
	local blocks, height = layoutFor(item)

	local children: { [string]: any } = {}
	local y = 0
	for i, block in ipairs(blocks) do
		if i > 1 then y += GAP end
		local key = block.kind .. i
		if block.kind == "name" then
			children[key] = Nameplate(item, rarityColor, y)
		elseif block.kind == "rarity" then
			children[key] = RarityRow(item, rarityColor, y)
		elseif block.kind == "durability" then
			children[key] = Durability(item, y)
		elseif block.kind == "divider" then
			children[key] = Divider(y)
		elseif block.kind == "stat" then
			children[key] = StatRow(block.data.row, block.data.accent, y)
		end
		y += block.h
	end

	local card = InventoryUI.TOOLTIP_CARD
	-- Position is the final, already-clamped top-left corner: the caller decides where, using
	-- EstimateSize to know how big this will be.
	return e("Frame", {
		Position = UDim2.fromOffset(props.position.X, props.position.Y),
		Size = UDim2.fromOffset(CARD_W, height),
		BackgroundColor3 = Color3.fromRGB(20, 14, 9),
		BackgroundTransparency = card.Image ~= "" and 1 or 0,
		BorderSizePixel = 0,
		ZIndex = 60,
	}, {
		Card = card.Image ~= "" and e("ImageLabel", {
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = card.Image,
			ScaleType = Enum.ScaleType.Slice, SliceCenter = card.SliceCenter, SliceScale = 0.36, ZIndex = 60,
		}) or e("UIStroke", { Color = Color3.fromRGB(172, 150, 108), Thickness = 1 }),
		Content = e("Frame", {
			Position = UDim2.fromOffset(PAD_X, PAD_TOP), Size = UDim2.new(1, -PAD_X * 2, 1, -(PAD_TOP + PAD_BOTTOM)),
			BackgroundTransparency = 1, ZIndex = 61,
		}, children),
	})
end

-- The card's real size for `item`, without rendering it (the same layout the render uses).
local function estimateSize(item: any): Vector2
	if type(item) ~= "table" then
		return Vector2.new(0, 0)
	end
	local _, height = layoutFor(item)
	return Vector2.new(CARD_W, height)
end

-- Plain-text stat lines for other screens (the Auction House): "+103 Health".
local function asLines(rows: { { string } }): { string }
	local out = {}
	for _, row in ipairs(rows) do table.insert(out, row[2] .. " " .. row[3]) end
	return out
end

return {
	Component = renderTooltip,
	EstimateSize = estimateSize,
	BaseStatLines = function(subStats) return asLines(baseStats(subStats)) end,
	SubstatLines = function(subStats) return asLines(substats(subStats)) end,
}
