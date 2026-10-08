--!strict
--  DurabilityBar -- the thin wear bar along the bottom of an item's slot (bag, equip sockets):
--  white for what's left over a grey track, like ----[][]. A broken item (0 durability, see
--  SSS/DurabilityService) shows an empty red track instead, and its icon is dimmed by the caller
--  (DurabilityBar.IsBroken). Only gear carries durability; everything else gets no bar.
--
--  Sized in scale of whatever it's dropped into, so it works at any slot size.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)
local e = React.createElement

local FILL = Color3.fromRGB(245, 242, 235)
local TRACK = Color3.fromRGB(70, 66, 60)
local BROKEN = Color3.fromRGB(170, 46, 36)
-- Broken icons are drawn greyed out and see-through.
local BROKEN_ICON_TINT = Color3.fromRGB(150, 150, 150)
local BROKEN_ICON_ALPHA = 0.45

local DurabilityBar = {}

DurabilityBar.BROKEN_ICON_TINT = BROKEN_ICON_TINT
DurabilityBar.BROKEN_ICON_ALPHA = BROKEN_ICON_ALPHA

function DurabilityBar.IsBroken(item: any): boolean
	return type(item) == "table" and item.broken == true
end

-- 0..1 left, or nil when the item doesn't wear.
function DurabilityBar.Fraction(item: any): number?
	if type(item) ~= "table" then return nil end
	local maxDur = tonumber(item.maxDurability)
	if not maxDur or maxDur <= 0 then return nil end
	if item.broken == true then return 0 end
	return math.clamp((tonumber(item.durability) or maxDur) / maxDur, 0, 1)
end

-- The bar element, or nil. `width` / `bottom` (scale of the parent) let a round socket tuck it
-- in further than a square slot.
function DurabilityBar.ForItem(item: any, opts: { width: number?, bottom: number?, zIndex: number? }?)
	local fraction = DurabilityBar.Fraction(item)
	if not fraction then return nil end
	local o = opts or {}
	local broken = DurabilityBar.IsBroken(item)
	local z = o.zIndex or 6
	return e("Frame", {
		Name = "Durability",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, o.bottom or 0.94),
		Size = UDim2.fromScale(o.width or 0.78, 0.06),
		BackgroundColor3 = broken and BROKEN or TRACK,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		ZIndex = z,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Edge = e("UIStroke", { Color = Color3.new(0, 0, 0), Transparency = 0.45, Thickness = 1 }),
		Fill = fraction > 0 and e("Frame", {
			Size = UDim2.fromScale(fraction, 1),
			BackgroundColor3 = FILL,
			BorderSizePixel = 0,
			ZIndex = z + 1,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
		}) or nil,
	})
end

return DurabilityBar
