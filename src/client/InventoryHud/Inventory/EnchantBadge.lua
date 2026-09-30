--!strict
--  EnchantBadge -- the "+N" enchant chip in an item slot's top-left corner, shown whenever the
--  item is enchanted (not only inside the Enchanting Station). Sized as a FRACTION of the slot
--  (the station's 34x18 chip on a 92px slot), because the bag/equip slots are authored at
--  ~510px and scaled down by a UIScale -- a pixel size would be wrong at every scale.
--  Used by ItemSlot (bag), PlayerPreview's EquipmentSlot, and the Enchanting Station.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIFonts = require(ReplicatedStorage:WaitForChild("UIFonts"))
local React = require(ReplicatedStorage.Packages.React)
local e = React.createElement

local EnchantBadge = {}

EnchantBadge.BG = Color3.fromRGB(20, 15, 12)
EnchantBadge.TEXT = Color3.fromRGB(255, 220, 130)

-- The item's enchant level (0 when none).
function EnchantBadge.LevelOf(item: any): number
	if type(item) ~= "table" then return 0 end
	return math.max(0, math.floor(tonumber(item.enchantLevel) or 0))
end

-- props: text ("+3"), zIndex (optional, default 6 -- above icons/counts, below hit buttons
-- that need no text over them anyway: a TextLabel never blocks clicks).
function EnchantBadge.Component(props: { text: string, zIndex: number? })
	return e("TextLabel", {
		Name = "EnchantBadge",
		ZIndex = props.zIndex or 6,
		Position = UDim2.fromScale(0.045, 0.045),
		Size = UDim2.fromScale(0.37, 0.2),
		BackgroundColor3 = EnchantBadge.BG,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		FontFace = UIFonts.BodyBold,
		TextScaled = true,
		TextColor3 = EnchantBadge.TEXT,
		Text = props.text,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0.2, 0) }),
		Pad = e("UIPadding", {
			PaddingTop = UDim.new(0.12, 0), PaddingBottom = UDim.new(0.12, 0),
			PaddingLeft = UDim.new(0.08, 0), PaddingRight = UDim.new(0.08, 0),
		}),
	})
end

-- Convenience: the badge element for an item, or nil when it isn't enchanted.
function EnchantBadge.ForItem(item: any, zIndex: number?)
	local level = EnchantBadge.LevelOf(item)
	if level <= 0 then return nil end
	return EnchantBadge.Component({ text = "+" .. tostring(level), zIndex = zIndex })
end

return EnchantBadge
