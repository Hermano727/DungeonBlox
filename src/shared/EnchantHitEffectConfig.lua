-- First-pass geometry effects. No uploaded textures or mesh assets required.
return {
	MaxDistance = 120,
	MaxActiveEffects = 12,
	SameEffectInterval = 0.10,
	Order = { "Elemental", "Glowing", "Bleeding", "Slowness", "Blinding", "Cleave", "Piercing", "Crushing", "Shatter", "Execute" },
	Execute = { Duration = 0.52, Color = Color3.fromRGB(125, 22, 32), Accent = Color3.fromRGB(238, 71, 54) },
	Shatter = { Duration = 0.55, Color = Color3.fromRGB(107, 137, 153), Accent = Color3.fromRGB(213, 239, 245) },
	Crushing = { Duration = 0.44, Color = Color3.fromRGB(124, 103, 74), Accent = Color3.fromRGB(216, 185, 132) },
	Piercing = { Duration = 0.25, Color = Color3.fromRGB(190, 185, 163), Accent = Color3.fromRGB(255, 245, 206) },
	Cleave = { Duration = 0.38, Color = Color3.fromRGB(151, 105, 47), Accent = Color3.fromRGB(241, 190, 107) },
	Bleeding = { Duration = 0.60, Color = Color3.fromRGB(102, 15, 28), Accent = Color3.fromRGB(173, 35, 42) },
	Blinding = { Duration = 0.48, Color = Color3.fromRGB(199, 178, 113), Accent = Color3.fromRGB(255, 242, 197) },
	Slowness = { Duration = 0.70, Color = Color3.fromRGB(76, 100, 116), Accent = Color3.fromRGB(157, 186, 195) },
	Elemental = { Duration = 0.50, Color = Color3.fromRGB(174, 70, 26), Accent = Color3.fromRGB(255, 181, 73) },
	Glowing = { Duration = 0.85, Color = Color3.fromRGB(153, 144, 96), Accent = Color3.fromRGB(243, 233, 164) },
}
