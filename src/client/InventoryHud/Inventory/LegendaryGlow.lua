--!strict
--  LegendaryGlow -- soft pulsing glow rendered behind a Legendary item's icon, in both the bag
--  slots and the equipped-item slots. Built from plain circular frames (UICorner at 0.5 scale)
--  instead of an external blur/glow texture -- three stacked, increasingly larger and more
--  transparent circles behind the icon, each gently pulsing its own transparency via
--  TweenService so the glow "breathes" instead of sitting static. No new image assets needed.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local React = require(ReplicatedStorage.Packages.React)
local e = React.createElement

local GLOW_COLOR = Color3.fromRGB(255, 175, 85) -- same orange as the Legendary rarity color

local LAYERS = {
	{ scale = 1.55, transparency = 0.90 },
	{ scale = 1.30, transparency = 0.80 },
	{ scale = 1.10, transparency = 0.66 },
}

local function GlowLayer(props: { scale: number, transparency: number, zIndex: number })
	local ref = React.useRef(nil :: Frame?)

	React.useEffect(function()
		local frame = ref.current
		if not frame then
			return
		end
		local tween = TweenService:Create(
			frame,
			TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ BackgroundTransparency = math.min(1, props.transparency + 0.12) }
		)
		tween:Play()
		return function()
			tween:Cancel()
		end
	end, {})

	return e("Frame", {
		ref = ref,
		Size = UDim2.fromScale(props.scale, props.scale),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = GLOW_COLOR,
		BackgroundTransparency = props.transparency,
		BorderSizePixel = 0,
		ZIndex = props.zIndex,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
	})
end

-- zIndex: the lowest ZIndex the glow's 3 layers should use (they stack upward from there) --
-- pass something below the icon's own ZIndex so the glow always renders behind it.
local function LegendaryGlow(props: { zIndex: number })
	local baseZ = props.zIndex
	return e(React.Fragment, nil, {
		Layer1 = e(GlowLayer, { scale = LAYERS[1].scale, transparency = LAYERS[1].transparency, zIndex = baseZ }),
		Layer2 = e(GlowLayer, { scale = LAYERS[2].scale, transparency = LAYERS[2].transparency, zIndex = baseZ + 1 }),
		Layer3 = e(GlowLayer, { scale = LAYERS[3].scale, transparency = LAYERS[3].transparency, zIndex = baseZ + 2 }),
	})
end

return LegendaryGlow
