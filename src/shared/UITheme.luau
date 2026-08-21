--[[
	UITheme
	Central place for shared UI colors, alongside UIFonts. Right now just the "gold" trim color
	used everywhere (PanelShell/QuickNav/SkillsPanel/HearthstonePanel/PlayerPreview/ContextMenu/
	Tooltip all had their own literal Color3.fromRGB(217, 184, 80)) -- one constant here means
	retuning the whole UI's gold in one place instead of hunting down every file.
]]

return {
	-- Muted/desaturated bronze-gold (was the brighter Color3.fromRGB(217, 184, 80)) -- less
	-- vibrant polished-gold, closer to an aged-brass trim, per reference.
	Gold = Color3.fromRGB(172, 150, 108),
}
