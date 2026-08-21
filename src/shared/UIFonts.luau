--[[
	UIFonts
	Central place to pick "the" RPG UI font(s) so every panel/label references the same
	constants instead of scattering Enum.Font / Font.new calls everywhere -- swap the family
	here and it rolls out everywhere that requires this module.

	Display -- Garamond, an elegant classical serif for panel titles, headers, and callouts.
	Distinguished without tipping into the "over the top" medieval-cliche look (MedievalSharp,
	Uncial Antiqua, etc.) -- reads as refined RPG chrome, not a joke font.

	Swapped from Cinzel: "Cinzel" is NOT one of Roblox's actual bundled font families --
	Enum.Font has no Cinzel entry, so rbxasset://fonts/families/Cinzel.json never resolved to a
	real file. Font.new()/Font.fromName() don't validate the path at construction time, so this
	failed silently at render time every single time (not intermittently, as first assumed) --
	it just fell back to Roblox's default font, with only a console warning
	("Font family ... failed to load"). Garamond IS a real bundled family (confirmed via
	Enum.Font:GetEnumItems()), so this is an actual fix, not another guess.

	Body -- kept as the existing clean sans (Gotham) for anything dense or small (stat numbers,
	descriptions, tooltip/body text) -- serif display fonts hurt legibility at small sizes.
]]

return {
	DisplayBold = Font.new("rbxasset://fonts/families/Garamond.json", Enum.FontWeight.Bold),
	DisplayRegular = Font.new("rbxasset://fonts/families/Garamond.json", Enum.FontWeight.Regular),
	DisplaySemibold = Font.new("rbxasset://fonts/families/Garamond.json", Enum.FontWeight.SemiBold),

	Body = Enum.Font.Gotham,
	BodyMedium = Enum.Font.GothamMedium,
	BodyBold = Enum.Font.GothamBold,
}
