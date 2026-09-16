--!strict
-- Tuneable settings for the tree-based dialog system.
-- Mirrors the shape of the old DialogModule's constants, but scoped to one
-- config module rather than magic numbers scattered through the code.

return {
	-- If true, freezes the player's WalkSpeed/JumpPower while dialog is open
	-- (same behavior the old DialogModule had via beginDialogLocomotionLock).
	FreezePlayer = true,

	-- Typewriter reveal speed, characters per second. Set high (e.g. 999) to
	-- effectively disable the effect.
	TextSpeed = 35,

	UI = {
		PanelSize = UDim2.fromOffset(860, 300),
		BackgroundColor = Color3.fromRGB(24, 20, 18),
		BackgroundTransparency = 0.08,
		AccentColor = Color3.fromRGB(200, 150, 90),
		TextColor = Color3.fromRGB(240, 235, 228),
		ButtonColor = Color3.fromRGB(45, 38, 32),
		ButtonHoverColor = Color3.fromRGB(65, 55, 45),
		CornerRadius = UDim.new(0, 12),
		TextSize = 22,
		ResponseTextSize = 18,

		-- Portrait box, ported from dialog system (3)'s DialogGui: pokes out
		-- past the panel's top-left edge rather than sitting inside it.
		-- Any tree node may set `image = "rbxassetid://..."` (see
		-- DialogTreeLoader's doc comment) -- the box only shows when the
		-- current node has one, same as dialog system (3)'s mood.image.
		ImageSize = UDim2.fromOffset(180, 180),
		ImageOverflowTop = 50,
		ImageOverflowLeft = 16,
	},
}
