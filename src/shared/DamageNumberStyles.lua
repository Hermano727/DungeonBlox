--[[
	DamageNumberStyles -- ReplicatedStorage

	Colour (and any future per-source styling) for floating damage numbers,
	keyed by a short source string the SERVER states explicitly on the
	DamageNumberEvent payload.

	Why the server has to say it rather than the client inferring it:
	`enchantFeedback.effects.Bleeding` is true on a bleed TICK *and* on the main
	weapon hit that applied the bleed (CombatEnchantStatus.Apply returns the proc
	in `extras`, which EnchantHitFeedback.Select merges into the main hit's
	effects). The two are indistinguishable client-side, so the source has to
	travel on the wire as its own field.

	Keys are constants in `Sources` rather than bare strings at the call sites so
	a typo on the server can't silently fall back to the default colour.

	This covers the NUMBER's own colour only. The world-space hit effect that
	plays alongside it is a separate system with its own palette --
	RS/EnchantHitEffectConfig, drawn by client/EnchantHitEffects. The two are
	deliberately tuned apart: an effect colour is a burst against the mob, a
	number colour has to stay legible as small text against any background, so
	the number reads brighter. Retune them together.
]]

local DamageNumberStyles = {}

-- Source keys. Server passes one of these; nil means "ordinary weapon damage".
DamageNumberStyles.Sources = {
	Bleed = "bleed",
}

-- Ordinary weapon damage, including cleave splash -- cleave is still a hit from
-- your weapon, so it stays the default rather than earning a colour of its own.
local DEFAULT = {
	Color = Color3.fromRGB(255, 255, 255),
}

DamageNumberStyles.Styles = {
	-- Brighter than EnchantHitEffectConfig.Bleeding.Accent (173, 35, 42), which
	-- is tuned as a burst colour against a mob rather than as readable text.
	[DamageNumberStyles.Sources.Bleed] = {
		Color = Color3.fromRGB(198, 42, 48),
	},
}

-- Always returns a table, so callers never branch on nil.
function DamageNumberStyles.Get(sourceKey)
	if type(sourceKey) ~= "string" then
		return DEFAULT
	end
	return DamageNumberStyles.Styles[sourceKey] or DEFAULT
end

return DamageNumberStyles
