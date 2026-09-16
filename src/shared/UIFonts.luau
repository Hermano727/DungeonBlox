--[[
	UIFonts
	Central place to pick "the" RPG UI font(s) so every panel/label references the same
	constants instead of scattering Enum.Font / Font.new calls everywhere -- swap the family
	here and it rolls out everywhere that requires this module.

	Display -- Builder Extended (rbxassetid://16658237174), a bold geometric Roblox-uploaded
	font (confirmed via MarketplaceService:GetProductInfo -- AssetTypeId 73 = Font, Creator =
	Roblox, IsPublicDomain = true; native styles Light/Regular/SemiBold/Bold/ExtraBold, all
	verified rendering live in Play mode) for panel titles, headers, and callouts. Swapped from
	Garamond -- team wanted a stronger/more modern look for headers.

	Prior history for context: an earlier attempt at "Cinzel" failed silently because Cinzel
	isn't one of Roblox's bundled font families -- Enum.Font has no Cinzel entry, so
	rbxasset://fonts/families/Cinzel.json never resolved to a real file, and Font.new() doesn't
	validate the path at construction time. It just fell back to Roblox's default font, with
	only a console warning ("Font family ... failed to load"). The SAME trap bit "Quicksand"
	(used directly in AuctionHouseClient / DungeonMenuUI / DialogModule before this pass) and
	almost bit "Work Sans" and "Bungee" too -- none of those are in Roblox's bundled family list
	either. The fix every time: use the actual rbxassetid:// of the specific Font asset Roblox
	uploaded for that Google Fonts family (found via Studio's font picker / Toolbox, confirmed
	via MarketplaceService:GetProductInfo), never a guessed rbxasset://fonts/families/*.json path.

	Body -- Work Sans (rbxassetid://12187373327), a Roblox-uploaded Google Fonts family (same
	verification as above; native styles Thin through Black plus italics) for anything dense or
	small (stat numbers, descriptions, tooltip/body text, dialogue, HUD readouts, NPC nameplates).
	Swapped from Gotham.

	Damage -- floating combat damage numbers use Bungee Inline (rbxassetid://12187370000),
	verified the same way. It ships with a single native "Regular" style; requesting Bold still
	renders fine (Roblox just uses the one available face regardless of requested weight).

	IMPORTANT: every value below except `Families` (which holds raw asset-id strings) is a Font
	datatype (Font.new(...)), not Enum.Font -- it can ONLY be assigned via the `FontFace`
	property/prop, never the legacy `Font` property. Assigning a Font datatype to `.Font`
	hard-errors ("EnumItem, number, or string expected, got Font"). Every consumer in this
	codebase has been switched to FontFace as part of this pass.

	---------------------------------------------------------------------------------------
	Scalability: this module is the ONLY place a font family/asset-id should ever be typed.
	Every call site should read a constant from here (or, for a one-off weight this module
	doesn't pre-bake, build one from `Families` -- e.g. Font.new(UIFonts.Families.Body,
	Enum.FontWeight.SemiBold)) rather than hardcoding rbxasset://, an asset id, or Enum.Font.*
	directly. That's what makes a global font swap possible by editing this one file.

	NPCDefault / NPCOverrides / GetNPCFont -- every NPC type (Merchant, Blacksmith, Innkeeper,
	AnimalTrainer, Dungeoneer, Cuso, Miner, Fisherman) gets its nameplate/dialog-bubble font from
	NPCBootstrapKit.EnsureHeadGui, which calls GetNPCFont(npcType, slot). With NPCOverrides empty,
	every NPC type resolves to the same NPCDefault. To give one archetype a distinct look later
	(e.g. the Blacksmith get a heavier nameplate font), add an entry to NPCOverrides keyed by the
	same npcType string NPCBootstrapKit is called with -- no call site needs to change.

	MobName -- floating "Level N <MobName>" nameplate above monsters (MobHPBarUI.lua).

	HUDLabel -- always-visible main-screen HUD readouts: health/hunger/energy bar text and icons
	(HealthClient.client.lua, EnergyClient.client.lua). NOTE: the energy bar's GUI
	(StarterGui.EnergyBarGui) is a hand-built static Instance, not a Rojo-synced script file (it's
	under syncbackRules.ignoreTrees in default.project.json) -- EnergyClient.client.lua applies
	HUDLabel to it at runtime instead of it being a permanent baked-in property, so it still
	follows this registry.
]]

local Families = {
	Display = "rbxassetid://16658237174", -- Builder Extended
	Body = "rbxassetid://12187373327", -- Work Sans
	Damage = "rbxassetid://12187370000", -- Bungee Inline
}

local NPCDefault = {
	Name = Font.new(Families.Body, Enum.FontWeight.Bold),
	Dialog = Font.new(Families.Body, Enum.FontWeight.Medium),
}

-- Per-NPC-type overrides, keyed by the same npcType string bootstrap scripts identify
-- themselves with (e.g. "Merchant", "Blacksmith"). Empty for now -- every NPC type falls back
-- to NPCDefault via GetNPCFont. Example for later:
--   NPCOverrides.Blacksmith = { Name = Font.new(Families.Display, Enum.FontWeight.Bold) }
local NPCOverrides = {}

--- Returns the font for `slot` ("Name" or "Dialog") for the given NPC type, falling back to
--- NPCDefault when there's no override (or no npcType at all). Called from
--- NPCBootstrapKit.EnsureHeadGui.
local function GetNPCFont(npcType, slot)
	local override = npcType and NPCOverrides[npcType]
	if override and override[slot] then
		return override[slot]
	end
	return NPCDefault[slot]
end

return {
	Families = Families,

	DisplayBold = Font.new(Families.Display, Enum.FontWeight.Bold),
	DisplayRegular = Font.new(Families.Display, Enum.FontWeight.Regular),
	DisplaySemibold = Font.new(Families.Display, Enum.FontWeight.SemiBold),

	Body = Font.new(Families.Body, Enum.FontWeight.Regular),
	BodyMedium = Font.new(Families.Body, Enum.FontWeight.Medium),
	BodyBold = Font.new(Families.Body, Enum.FontWeight.Bold),

	Damage = Font.new(Families.Damage, Enum.FontWeight.Bold),

	NPCDefault = NPCDefault,
	NPCOverrides = NPCOverrides,
	GetNPCFont = GetNPCFont,

	MobName = Font.new(Families.Body, Enum.FontWeight.Bold),
	HUDLabel = Font.new(Families.Body, Enum.FontWeight.Bold),
}
