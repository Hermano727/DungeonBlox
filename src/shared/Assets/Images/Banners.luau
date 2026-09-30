--[[
	Banners -- ReplicatedStorage/Assets/Images

	Full-screen end-of-run banners (DungeonCompleteBanner, client), keyed by name. The server
	picks the key (DungeonRunService.EndRunFor: "DungeonComplete" on a clear, "DungeonFailed" on
	a death or wipe), so a dungeon that wants its own art just registers another key here.

		Image      the banner art: a transparent PNG
		Glow       optional soft white halo in the art's silhouette, drawn BEHIND it and tinted
		           GlowColor ("" = no glow). Generated from the source PNG (blurred outline).
		Aspect     the art's width / height
		GlowScale  the glow PNG's size relative to the art (it is padded so the halo isn't
		           clipped at the art's edges), as Vector2(x, y)
		GlowColor  tint of the halo
		Style      how it animates: "Complete" or "Failed" (STYLES in DungeonCompleteBanner)

	Sources: assets/ui/<name>.png and assets/ui/<name> glow.png.
]]

return {
	DungeonComplete = {
		Image = "rbxassetid://125485549872227",
		Glow = "", -- assets/ui/dungeon complete glow.png, once uploaded
		Aspect = 1688 / 932,
		GlowScale = Vector2.new(1868 / 1688, 1112 / 932),
		GlowColor = Color3.fromRGB(255, 212, 110),
		Style = "Complete",
	},
	DungeonFailed = {
		Image = "rbxassetid://115141121476987",
		Glow = "", -- assets/ui/dungeon failed glow.png, once uploaded
		Aspect = 624 / 345,
		GlowScale = Vector2.new(696 / 624, 417 / 345),
		GlowColor = Color3.fromRGB(150, 18, 18), -- dull blood red, not neon
		Style = "Failed",
	},
}
