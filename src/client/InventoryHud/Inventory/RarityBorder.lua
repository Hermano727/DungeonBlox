--!strict
--  RarityBorder -- shared rarity-colored item border, used by both the bag slots (ItemSlot)
--  and the equipped-item slots (PlayerPreview) so both read the same rarity language. Renders
--  as a UIStroke with a UIGradient child (Roblox tints a stroke's color off a UIGradient placed
--  inside it), giving a gradient with two bright "shiny" highlight spots instead of one flat
--  color -- see DungeonProfileTypes.GetRarityGradient.
--
--  Legendary gets extra treatment on top of that static gradient: the UIGradient continuously
--  rotates (the two bright spots visibly travel/shimmer around the outline instead of sitting
--  still) and the stroke thickness gently pulses -- both plain TweenService loops, no external
--  assets, so every other rarity stays cheap/static per "ok UI styling, custom UI later."
--
--  Pass `color` instead of `rarity` for the couple of non-rarity border cases (the white
--  "currently held" outline in ItemSlot, the gold "empty slot" outline in PlayerPreview) --
--  those get a plain flat-color stroke, no gradient, no animation.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local React = require(ReplicatedStorage.Packages.React)
local Types = require(ReplicatedStorage:WaitForChild("DungeonProfileTypes"))
local e = React.createElement

export type RarityBorderProps = {
	rarity: string?,
	color: Color3?,
	thickness: number?,
}

local function RarityBorder(props: RarityBorderProps)
	local thickness = props.thickness or 3
	local isLegendary = props.rarity == "Legendary" and props.color == nil

	local strokeRef = React.useRef(nil :: UIStroke?)
	local gradientRef = React.useRef(nil :: UIGradient?)

	React.useEffect(function()
		if not isLegendary then
			return
		end
		local stroke = strokeRef.current
		local gradient = gradientRef.current
		if not stroke or not gradient then
			return
		end

		-- Shimmer: the gradient's bright spots slowly sweep around the whole outline.
		local shimmer = TweenService:Create(
			gradient,
			TweenInfo.new(3.2, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1, false),
			{ Rotation = 360 }
		)
		shimmer:Play()

		-- Breathe: the outline itself gently thickens/thins on a slower, separate cycle.
		local breathe = TweenService:Create(
			stroke,
			TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Thickness = thickness + 1.5 }
		)
		breathe:Play()

		return function()
			shimmer:Cancel()
			breathe:Cancel()
			if gradient then
				gradient.Rotation = 0
			end
			if stroke then
				stroke.Thickness = thickness
			end
		end
	end, { isLegendary :: any })

	if props.color then
		return e("UIStroke", {
			Color = props.color,
			Thickness = thickness,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		})
	end

	local flat = Types.GetRarityColor(props.rarity)
	local gradient = Types.GetRarityGradient(props.rarity)

	return e("UIStroke", {
		ref = strokeRef,
		Color = flat,
		Thickness = thickness,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, {
		Gradient = e("UIGradient", {
			ref = gradientRef,
			Color = gradient,
		}),
	})
end

return RarityBorder
