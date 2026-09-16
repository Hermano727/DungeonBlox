--!strict
--  RarityBorder -- shared rarity-colored item border, used by both the bag slots (ItemSlot)
--  and the equipped-item slots (PlayerPreview) so both read the same rarity language. Renders
--  as a UIStroke with a UIGradient child (Roblox tints a stroke's color off a UIGradient placed
--  inside it), giving a brushed-metal gradient -- bright at the seam, dipping into two darker
--  "spot" dips symmetrically around the loop -- instead of one flat color. See
--  ProfileTypes.GetRarityGradient.
--
--  Legendary gets extra treatment on top of that static gradient: the UIGradient continuously
--  rotates (the bright seam and dark spots visibly travel/shimmer around the outline instead of
--  sitting still) and the stroke thickness gently pulses -- both plain TweenService loops, no external
--  assets, so every other rarity stays cheap/static per "ok UI styling, custom UI later."
--
--  Pass `color` instead of `rarity` for the couple of non-rarity border cases (the white
--  "currently held" outline in ItemSlot, the gold "empty slot" outline in PlayerPreview) --
--  those get a plain flat-color stroke, no gradient, no animation.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local React = require(ReplicatedStorage.Packages.React)
local Types = require(ReplicatedStorage:WaitForChild("ProfileTypes"))
local e = React.createElement

export type RarityBorderProps = {
	rarity: string?,
	color: Color3?,
	thickness: number?,
}

local function RarityBorder(props: RarityBorderProps)
	local thickness = props.thickness or 3
	local isAnimated = (props.rarity == "Legendary" or props.rarity == "Mythic") and props.color == nil
	local isMythic = props.rarity == "Mythic" and props.color == nil
	local isLegendary = isAnimated

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
			TweenInfo.new(isMythic and 2.2 or 3.2, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1, false),
			{ Rotation = 360 }
		)
		shimmer:Play()

		-- Breathe: the outline itself gently thickens/thins on a slower, separate cycle.
		local breathe = TweenService:Create(
			stroke,
			TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Thickness = thickness + (isMythic and 2.2 or 1.5) }
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

	-- Every non-Legendary rarity border was silently never rendering: Roblox doesn't composite
	-- a UIGradient's tint onto its parent UIStroke on the very first paint when both are created
	-- in the same instant (as React does here) -- nothing is wrong with the properties
	-- (Color/Thickness/Enabled/the Gradient's ColorSequence all verified correct live in Studio),
	-- the renderer just never draws it until something changes on the stroke *after* mount.
	-- Legendary items only ever worked by accident, because their shimmer/breathe tween above
	-- keeps nudging properties every frame. Give every other rarity the same one-time nudge (two
	-- real writes, not a no-op set-to-same-value) so the border actually paints once and then
	-- just sits there like the flat/empty/selected strokes already do.
	React.useEffect(function()
		if isLegendary or props.color then
			return
		end
		local stroke = strokeRef.current
		if not stroke then
			return
		end
		task.defer(function()
			if not stroke then
				return
			end
			stroke.Thickness = thickness + 0.01
			task.defer(function()
				if stroke then
					stroke.Thickness = thickness
				end
			end)
		end)
	end, { isLegendary :: any, props.color :: any })

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
